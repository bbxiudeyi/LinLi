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
  final double? height;
  final bool alwaysShowMap;
  final bool showLocationPuck;
  /// points 为空时显示的提示文字（如"轨迹加载中..."）。
  /// 设置后 points 空时仍渲染地图（带居中提示），避免布局跳动。
  final String? loadingHint;

  const ActivityMap({
    super.key,
    required this.points,
    this.interactive = true,
    this.fitBounds = true,
    this.height,
    this.alwaysShowMap = false,
    this.showLocationPuck = false,
    this.loadingHint,
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
    // points 为空：若无 loadingHint 则显示占位；有 loadingHint 则继续渲染地图（叠加提示）
    if (widget.points.isEmpty &&
        !widget.alwaysShowMap &&
        widget.loadingHint == null) {
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

    // height 为 null/double.infinity 时不约束高度（让父级 Positioned.fill 决定）
    final constrainHeight =
        widget.height != null && widget.height != double.infinity;
    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          map,
          // points 空时居中显示加载提示（地图照常显示，不跳布局）
          if (widget.points.isEmpty && widget.loadingHint != null)
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(widget.loadingHint!,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return constrainHeight ? SizedBox(height: widget.height, child: inner) : inner;
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
    // 录制模式持续跟随最新点；详情/准备页只 apply 一次
    if (widget.showLocationPuck && widget.points.isNotEmpty) {
      _followLatest(widget.points.last);
    } else {
      _applyCamera();
    }
  }

  @override
  void didUpdateWidget(covariant ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length) {
      _renderTrack();
      final pts = widget.points;
      if (widget.showLocationPuck && pts.isNotEmpty) {
        // 录制模式：持续跟随最新点（用户移动时地图平滑跟随，不跳变）
        _followLatest(pts.last);
      } else if (!_cameraApplied && pts.isNotEmpty) {
        // 详情/准备页：只 apply 一次相机（适配轨迹或跟随首点）
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

  /// 录制模式：把相机移到最新点（持续跟随，每次来新点都调用）。
  /// 不设 _cameraApplied，让录制中持续跟随。
  void _followLatest(GpsPoint p) {
    final controller = _controller;
    if (controller == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(p.latLng.latitude, p.latLng.longitude),
      ),
    );
  }

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
  final double? height;
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
