import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/map/map_config.dart';
import '../../features/activity/models/activity_models.dart';

/// 可复用的运动轨迹地图组件，基于 MapLibre（maplibre_gl）+ 自建瓦片服务。
///
/// - [showLocationPuck]：录制场景，显示用户位置圆点 + 走过的整条路径。
///   （原 Mapbox 版有「渐隐尾巴」特效，依赖 lineTrimOffset，MapLibre 不支持，
///    已降级为整条路径常显。）
/// - 否则：用线图层画静态轨迹（详情页/Feed）。
///
/// 对外 API 与旧版保持一致（构造参数不变），避免调用方改动。
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
  MapLibreMapController? _controller;

  // 轨迹线 source id（在 onStyleLoaded 里一次性建好，后续只更新数据）
  static const _trackSourceId = 'track-source';
  static const _trackLayerId = 'track-layer';
  bool _trackLayerAdded = false;
  bool _cameraApplied = false; // 防止重复移动相机

  @override
  Widget build(BuildContext context) {
    if (!MapConfig.isConfigured) {
      return _Placeholder(text: '地图服务未配置', height: widget.height);
    }
    if (widget.points.isEmpty && !widget.alwaysShowMap) {
      return _Placeholder(text: '暂无轨迹数据', height: widget.height);
    }

    final map = MapLibreMap(
      styleString: MapConfig.styleUri,
      // 录制模式开启定位跟随
      myLocationEnabled: widget.showLocationPuck,
      myLocationTrackingMode: widget.showLocationPuck
          ? MyLocationTrackingMode.tracking
          : MyLocationTrackingMode.none,
      // 录制模式下用 compass 模式：puck 显示指南针方向箭头（iOS 上也更稳定）
      myLocationRenderMode: widget.showLocationPuck
          ? MyLocationRenderMode.compass
          : MyLocationRenderMode.normal,
      // 交互开关
      rotateGesturesEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
      doubleClickZoomEnabled: widget.interactive,
      dragEnabled: widget.interactive,
      // 初始视野（北京）
      initialCameraPosition: const CameraPosition(
        target: LatLng(39.9042, 116.4074),
        zoom: 11.0,
      ),
      // OSM 署名按钮（ODbL 协议要求）：MapLibre 自带 attribution 控件，默认右下角
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
    );

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: map,
      ),
    );
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
  }

  /// 样式加载完成后：建 source + line layer，再画线 + 移动相机。
  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    // 一次性建好轨迹 source + line layer
    if (!_trackLayerAdded) {
      try {
        await controller.addGeoJsonSource(
          _trackSourceId,
          _pointsToGeoJson(widget.points),
        );
        await controller.addLineLayer(
          _trackLayerId,
          _trackSourceId,
          const LineLayerProperties(
            lineColor: '#FF6B35', // 与旧版一致的橙色
            lineWidth: 5.0,
            lineCap: 'round',
            lineJoin: 'round',
          ),
        );
        _trackLayerAdded = true;
      } catch (e) {
        // source/layer 可能已存在，忽略重复添加错误
        debugPrint('addGeoJsonSource/addLineLayer 失败: $e');
      }
    }

    await _renderTrack();
    _applyCamera();
  }

  @override
  void didUpdateWidget(covariant ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length) {
      _renderTrack();
      // 准备页场景：style 先加载（当时 points 空，相机没 apply），
      // selectSport 拿到首位置后 points 更新，这里补一次相机跟随。
      if (!_cameraApplied && widget.points.isNotEmpty) {
        _applyCamera();
      }
    }
  }

  // ==================== 画线 ====================

  Future<void> _renderTrack() async {
    final controller = _controller;
    if (controller == null || !_trackLayerAdded) return;
    final pts = widget.points;
    if (pts.isEmpty) return;
    try {
      await controller.setGeoJsonSource(
        _trackSourceId,
        _pointsToGeoJson(pts),
      );
    } catch (e) {
      debugPrint('setGeoJsonSource 失败: $e');
    }
  }

  Map<String, dynamic> _pointsToGeoJson(List<GpsPoint> pts) {
    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            // GeoJSON 坐标顺序是 [经度, 纬度]
            'coordinates': pts
                .map((p) => [p.latLng.longitude, p.latLng.latitude])
                .toList(),
          },
        }
      ],
    };
  }

  // ==================== 相机视野 ====================

  void _applyCamera() {
    if (_cameraApplied) return;
    final controller = _controller;
    if (controller == null) return;
    final pts = widget.points;

    if (widget.fitBounds && pts.length >= 2) {
      // 适配整条轨迹
      _fitBounds(pts);
    } else if (pts.isNotEmpty) {
      // 跟随最新点（录制场景）
      final last = pts.last;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(last.latLng.latitude, last.latLng.longitude),
          16.0,
        ),
      );
    }
    _cameraApplied = true;
  }

  Future<void> _fitBounds(List<GpsPoint> pts) async {
    final controller = _controller;
    if (controller == null) return;

    double? minLat, minLng, maxLat, maxLng;
    for (final p in pts) {
      final lat = p.latLng.latitude;
      final lng = p.latLng.longitude;
      minLat = (minLat == null || lat < minLat) ? lat : minLat;
      maxLat = (maxLat == null || lat > maxLat) ? lat : maxLat;
      minLng = (minLng == null || lng < minLng) ? lng : minLng;
      maxLng = (maxLng == null || lng > maxLng) ? lng : maxLng;
    }
    if (minLat == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, left: 40, top: 40, right: 40, bottom: 40),
    );
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
