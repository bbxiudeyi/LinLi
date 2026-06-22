import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/map/mapbox_config.dart';
import '../../features/activity/models/activity_models.dart';

/// 可复用的运动轨迹地图组件，基于 Mapbox 官方 SDK（mapbox_maps_flutter）。
///
/// - [showLocationPuck]：录制场景，显示位置圆点 + 朝向箭头 + **渐隐尾巴**（影子轨迹）。
///   走过的路径画成线，停下来后尾部逐渐渐隐消失（彗星尾巴效果）。
///   实现用 GeoJsonSource + LineLayer（lineTrimOffset/lineTrimColor/FadeRange）+ 定时器。
/// - 否则：用 PolylineAnnotationManager 画静态轨迹线（详情页/Feed）。
class ActivityMap extends StatefulWidget {
  final List<GpsPoint> points;
  final bool interactive;
  final bool fitBounds;
  final double height;
  final bool alwaysShowMap;
  final bool showLocationPuck;

  const ActivityMap({
    super.key,
    required this.points,
    this.interactive = true,
    this.fitBounds = true,
    this.height = 200,
    this.alwaysShowMap = false,
    this.showLocationPuck = false,
  });

  @override
  State<ActivityMap> createState() => _ActivityMapState();
}

class _ActivityMapState extends State<ActivityMap> {
  MapboxMap? _map;

  // 详情/Feed 模式：静态轨迹线
  PolylineAnnotationManager? _lineManager;
  bool _trackRendered = false;

  // 录制模式：渐隐尾巴
  static const _ghostSourceId = 'ghost-source';
  LineLayer? _ghostLayer;
  Timer? _ghostTimer;
  /// 尾部修剪进度：[0,1]，0=不修剪（整条线可见），1=全修剪（全消失）
  double _trimStart = 0.0;
  /// 最近一次收到 GPS 点的时间，用于判断是否停下
  DateTime? _lastPointTime;

  ViewportState? _viewport;

  @override
  Widget build(BuildContext context) {
    if (!MapboxConfig.isConfigured) {
      return _Placeholder(text: '未配置 Mapbox Token', height: widget.height);
    }
    if (widget.points.isEmpty && !widget.alwaysShowMap) {
      return _Placeholder(text: '暂无轨迹数据', height: widget.height);
    }

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MapWidget(
          key: const ValueKey('activity_map'),
          styleUri: MapboxConfig.defaultStyleUri,
          viewport: _viewport,
          onMapCreated: _onMapCreated,
        ),
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;

    if (widget.showLocationPuck) {
      await _enableLocationPuck();
      await _setupGhostTrack();
      _startGhostTimer();
    } else {
      await _ensureLineManager();
      await _renderTrack();
    }

    if (widget.fitBounds) {
      _applyOverviewViewport();
    } else if (widget.points.isNotEmpty) {
      _followLatestPoint();
    } else {
      _applyInitialViewport();
    }
  }

  @override
  void didUpdateWidget(covariant ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length) {
      if (widget.showLocationPuck) {
        _onPointsChanged();
      } else {
        _trackRendered = false;
        _renderTrack();
        if (widget.fitBounds) _applyOverviewViewport();
      }
    }
  }

  // ==================== Location Puck（位置指示器）====================

  Future<void> _enableLocationPuck() async {
    final map = _map;
    if (map == null) return;
    try {
      await map.location.updateSettings(LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
        pulsingEnabled: true,
        pulsingColor: 0xFFFF6B35,
        pulsingMaxRadius: 30,
        showAccuracyRing: true,
      ));
    } catch (_) {}
  }

  // ==================== 渐隐尾巴（Ghost Track）====================

  /// 建一个 GeoJsonSource + LineLayer，lineMetrics 必须开（否则 trim 不生效）。
  Future<void> _setupGhostTrack() async {
    final map = _map;
    if (map == null) return;
    try {
      await map.style.addSource(GeoJsonSource(
        id: _ghostSourceId,
        data: _emptyFeatureCollection(),
        lineMetrics: true, // ★ 必须，否则 lineTrimOffset 无效
      ));
      _ghostLayer = LineLayer(
        id: 'ghost-layer',
        sourceId: _ghostSourceId,
        lineColor: 0xFFFF6B35,
        lineWidth: 6.0,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineTrimColor: 0x00000000, // 被修剪部分：透明
        lineTrimFadeRange: [0.0, 0.15], // 渐变过渡占 15%
        lineTrimOffset: [_trimStart, 1.0],
      );
      await map.style.addLayer(_ghostLayer!);
    } catch (_) {}
  }

  String _emptyFeatureCollection() => json.encode({
        'type': 'FeatureCollection',
        'features': [],
      });

  String _pointsToGeoJson(List<GpsPoint> pts) {
    return json.encode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': pts
                .map((p) => [p.latLng.longitude, p.latLng.latitude])
                .toList(),
          },
        }
      ],
    });
  }

  /// 新点到了：更新 source 数据，重置 trim（让尾巴重新出现）。
  void _onPointsChanged() {
    final map = _map;
    if (map == null) return;
    final pts = widget.points;
    if (pts.isEmpty) return;
    _lastPointTime = DateTime.now();

    // 更新 source 数据
    map.style.setStyleSourceProperty(
        _ghostSourceId, 'data', _pointsToGeoJson(pts));

    // 收到新点 → 尾巴完整可见（trim 归零）
    if (_trimStart > 0) {
      _trimStart = 0.0;
      _applyTrim();
    }
  }

  /// 定时器：如果一段时间没新点（用户停下），逐步推进 trim 让尾巴渐隐。
  void _startGhostTimer() {
    _ghostTimer?.cancel();
    _ghostTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_lastPointTime == null) return;
      final idle = DateTime.now().difference(_lastPointTime!);
      // 停下超过 1 秒才开始让尾巴消失
      if (idle.inMilliseconds > 1000 && _trimStart < 1.0) {
        // 大约 5 秒从 0 消失到 1（0.02 / 100ms = 0.2/s → 5s 走完 1.0）
        _trimStart = (_trimStart + 0.02).clamp(0.0, 1.0);
        _applyTrim();
      }
    });
  }

  Future<void> _applyTrim() async {
    final map = _map;
    final layer = _ghostLayer;
    if (map == null || layer == null) return;
    try {
      // 更新 layer 对象的 trim 值，再用 updateLayer 整体提交
      layer.lineTrimOffset = [_trimStart, 1.0];
      await map.style.updateLayer(layer);
    } catch (_) {}
  }

  // ==================== 静态轨迹（详情/Feed）====================

  Future<void> _ensureLineManager() async {
    if (_lineManager != null || _map == null) return;
    _lineManager = await _map!.annotations.createPolylineAnnotationManager();
    await _lineManager!.setLineColor(0xFFFF6B35);
    await _lineManager!.setLineWidth(4.0);
    await _lineManager!.setLineJoin(LineJoin.ROUND);
    await _lineManager!.setLineCap(LineCap.ROUND);
  }

  Future<void> _renderTrack() async {
    final manager = _lineManager;
    final pts = widget.points;
    if (manager == null || pts.isEmpty || _trackRendered) return;
    await manager.deleteAll();
    await manager.create(PolylineAnnotationOptions(
      geometry: LineString(
        coordinates: pts
            .map((p) => Position(p.latLng.longitude, p.latLng.latitude))
            .toList(),
      ),
    ));
    _trackRendered = true;
  }

  // ==================== 相机视野 ====================

  void _applyOverviewViewport() {
    final pts = widget.points;
    if (pts.length < 2 || !mounted) return;
    final geometry = LineString(
      coordinates: pts
          .map((p) => Position(p.latLng.longitude, p.latLng.latitude))
          .toList(),
    );
    setState(() {
      _viewport = OverviewViewportState(
        geometry: geometry,
        geometryPadding: const EdgeInsets.all(40),
        animationDuration: const Duration(milliseconds: 600),
      );
    });
  }

  void _applyInitialViewport() {
    if (!mounted) return;
    setState(() {
      _viewport = CameraViewportState(
        center: Point(coordinates: Position(116.4074, 39.9042)),
        zoom: 11.0,
      );
    });
  }

  void _followLatestPoint() {
    if (!mounted) return;
    final last = widget.points.last;
    setState(() {
      _viewport = CameraViewportState(
        center: Point(
          coordinates: Position(last.latLng.longitude, last.latLng.latitude),
        ),
        zoom: 16.0,
      );
    });
  }

  @override
  void dispose() {
    _ghostTimer?.cancel();
    super.dispose();
  }
}

class _Placeholder extends StatelessWidget {
  final String text;
  final double height;
  const _Placeholder({required this.text, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.grey[600])),
      ),
    );
  }
}
