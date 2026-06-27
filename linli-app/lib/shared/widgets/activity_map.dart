import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/map/map_config.dart';
import '../../features/activity/models/activity_models.dart';

/// 可复用的运动轨迹地图组件，基于 MapLibre 开源 SDK（maplibre_gl）。
///
/// 底图来自自托管的 pixelmap 地图服务，不依赖 Mapbox 云。
///
/// - [showLocationPuck]：录制场景，显示用户位置圆点 + 渐隐尾巴。
///   （阶段 A 最简版：暂只显示地图 + 静态轨迹，puck 和渐隐尾巴后续阶段实现）
/// - 否则：用 GeoJSON line layer 画静态轨迹线（详情页/保存确认）。
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
  bool _trackRendered = false;
  bool _styleLoaded = false;

  // 轨迹图层/source 的 ID（静态轨迹用）
  static const _trackSourceId = 'track-source';
  static const _trackLayerId = 'track-layer';

  // 轨迹颜色（橙色，保持和原 Mapbox 版一致）
  static const _trackColor = '#FF6B35';

  // source 是否已添加到 style（避免重复添加）
  bool _trackSourceAdded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty && !widget.alwaysShowMap) {
      return _Placeholder(text: '暂无轨迹数据', height: widget.height);
    }

    final initialTarget = widget.points.isNotEmpty
        ? LatLng(widget.points.last.latLng.latitude,
            widget.points.last.latLng.longitude)
        : LatLng(MapConfig.defaultCenterLat, MapConfig.defaultCenterLng);
    final initialZoom =
        widget.fitBounds ? MapConfig.defaultZoom : 16.0;

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MapLibreMap(
          styleString: MapConfig.styleUrl,
          initialCameraPosition: CameraPosition(target: initialTarget, zoom: initialZoom),
          // 阶段 B 会用 myLocationEnabled 控制 puck；阶段 A 暂统一关闭
          myLocationEnabled: false,
          // 录制场景关闭手势交互（跟随最新点）
          rotateGesturesEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: widget.interactive,
          doubleClickZoomEnabled: widget.interactive,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
        ),
      ),
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    // 样式加载完后，渲染轨迹 + 调整相机
    _renderTrack();
    _applyCamera();
  }

  @override
  void didUpdateWidget(covariant ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length) {
      _trackRendered = false;
      if (_styleLoaded) {
        _renderTrack();
        _applyCamera();
      }
    }
  }

  // ==================== 静态轨迹 ====================

  Future<void> _renderTrack() async {
    final controller = _controller;
    final pts = widget.points;
    if (controller == null || pts.length < 2 || _trackRendered) return;

    final geoJson = _pointsToGeoJson(pts);

    try {
      if (_trackSourceAdded) {
        // source 已存在，更新数据
        await controller.setGeoJsonSource(_trackSourceId, geoJson);
      } else {
        // 首次：新建 source + layer
        await controller.addGeoJsonSource(_trackSourceId, geoJson);
        await controller.addLineLayer(
          _trackLayerId,
          _trackSourceId,
          LineLayerProperties(
            lineColor: _trackColor,
            lineWidth: 4.0,
            lineOpacity: 1.0,
            lineCap: 'round',
            lineJoin: 'round',
          ),
        );
        _trackSourceAdded = true;
      }
      _trackRendered = true;
    } catch (e) {
      debugPrint('渲染轨迹失败: $e');
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
            'coordinates': pts
                .map((p) => [p.latLng.longitude, p.latLng.latitude])
                .toList(),
          },
        }
      ],
    };
  }

  // ==================== 相机 ====================

  Future<void> _applyCamera() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final pts = widget.points;

    if (widget.fitBounds && pts.length >= 2) {
      // 俯瞰整条轨迹：算 bounds
      final bounds = _calcBounds(pts);
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, left: 40, top: 40, right: 40, bottom: 40),
        duration: const Duration(milliseconds: 600),
      );
    } else if (pts.isNotEmpty) {
      // 跟随最后一个点（录制场景）
      final last = pts.last;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(last.latLng.latitude, last.latLng.longitude),
          16.0,
        ),
        duration: const Duration(milliseconds: 400),
      );
    }
  }

  LatLngBounds _calcBounds(List<GpsPoint> pts) {
    double minLat = 90, minLng = 180, maxLat = -90, maxLng = -180;
    for (final p in pts) {
      final lat = p.latLng.latitude;
      final lng = p.latLng.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
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
