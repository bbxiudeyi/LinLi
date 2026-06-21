import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/map/mapbox_config.dart';
import '../../features/activity/models/activity_models.dart';

/// 可复用的运动轨迹地图组件，基于 Mapbox 官方 SDK（mapbox_maps_flutter）。
///
/// 用法：
/// ```dart
/// ActivityMap(points: gpsPoints, interactive: true)
/// ```
///
/// - [points]：轨迹点序列（[GpsPoint]），自动连成线。
/// - [interactive]：false 时禁用手势（用于 Feed 卡片等纯预览场景）。
/// - [fitBounds]：true 时自动把视野缩放到整条轨迹（详情页/Feed 预览用）。
///
/// 实现说明：使用官方 [PolylineAnnotationManager] 画线（比手写
/// GeoJsonSource + LineLayer 稳定），用 [OverviewViewportState] 适配视野。
class ActivityMap extends StatefulWidget {
  final List<GpsPoint> points;
  final bool interactive;
  final bool fitBounds;
  final double height;
  /// 录制场景：即使没有轨迹点也显示地图底图（用于实时录制页）。
  /// 详情/Feed 场景为 false（没点时显示占位）。
  final bool alwaysShowMap;

  const ActivityMap({
    super.key,
    required this.points,
    this.interactive = true,
    this.fitBounds = true,
    this.height = 200,
    this.alwaysShowMap = false,
  });

  @override
  State<ActivityMap> createState() => _ActivityMapState();
}

class _ActivityMapState extends State<ActivityMap> {
  MapboxMap? _map;
  PolylineAnnotationManager? _lineManager;
  bool _trackRendered = false;
  /// 当前 viewport 状态；null = 用地图默认（跟随手势/初始位置）
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
    await _ensureLineManager();
    await _renderTrack();
    if (widget.fitBounds) {
      _applyOverviewViewport();
    } else if (widget.points.isNotEmpty) {
      // 录制场景：已有 GPS 点，直接定位到最新点（避免先跳默认视野）
      _followLatestPoint();
    } else {
      // 录制场景：还没点，先用合理默认（北京），等点来了会自动跟随
      _applyInitialViewport();
    }
  }

  @override
  void didUpdateWidget(covariant ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 录制中轨迹点持续追加 → 重画线 + 重新适配视野
    if (oldWidget.points.length != widget.points.length) {
      _trackRendered = false;
      _renderTrack();
      if (widget.fitBounds) {
        _applyOverviewViewport();
      } else if (widget.points.isNotEmpty) {
        // 录制场景：有 GPS 点了，移动相机到最新位置（跟随）
        _followLatestPoint();
      }
    }
  }

  /// 创建注解管理器（需等地图就绪，整个生命周期复用同一个）。
  Future<void> _ensureLineManager() async {
    if (_lineManager != null || _map == null) return;
    _lineManager = await _map!.annotations.createPolylineAnnotationManager();
    await _lineManager!.setLineColor(0xFFFF6B35); // 主题橙
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

  /// 用 OverviewViewportState 自动把整条轨迹放进视野。
  /// 通过 setState 更新 MapWidget 的 viewport 参数触发动画。
  void _applyOverviewViewport() {
    final pts = widget.points;
    if (pts.length < 2) return;
    if (!mounted) return;

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

  /// 录制场景初始视野：中国北京（合理默认，避免一打开是美国）。
  void _applyInitialViewport() {
    if (!mounted) return;
    setState(() {
      _viewport = CameraViewportState(
        center: Point(coordinates: Position(116.4074, 39.9042)), // 北京
        zoom: 11.0,
      );
    });
  }

  /// 录制场景：跟随最新 GPS 点，移动相机到当前位置。
  void _followLatestPoint() {
    if (!mounted) return;
    final last = widget.points.last;
    setState(() {
      _viewport = CameraViewportState(
        center: Point(
          coordinates: Position(last.latLng.longitude, last.latLng.latitude),
        ),
        zoom: 16.0, // 放大到街道级，适合录制跟随
      );
    });
  }
}

/// 占位 UI（未配置 Token 或无点时）。
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
