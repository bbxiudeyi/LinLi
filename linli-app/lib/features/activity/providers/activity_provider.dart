import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/network/api_client.dart';
import '../models/activity_models.dart';

class ActivityListState {
  final List<Map<String, dynamic>> activities;
  final bool loading;

  const ActivityListState({
    this.activities = const [],
    this.loading = false,
  });

  ActivityListState copyWith({
    List<Map<String, dynamic>>? activities,
    bool? loading,
  }) {
    return ActivityListState(
      activities: activities ?? this.activities,
      loading: loading ?? this.loading,
    );
  }
}

/// 详情页数据：活动行 + 轨迹点（已转 GpsPoint）。
class ActivityDetailState {
  final Map<String, dynamic>? activity;
  final List<GpsPoint> points;
  final bool loading;

  const ActivityDetailState({
    this.activity,
    this.points = const [],
    this.loading = false,
  });
}

class ActivityListNotifier extends StateNotifier<ActivityListState> {
  ActivityListNotifier() : super(const ActivityListState());

  /// 从云端加载我的活动列表（按开始时间降序）。
  Future<void> loadMyActivities() async {
    state = state.copyWith(loading: true);
    try {
      final res = await ApiClient.instance.dio.get('/activities');
      final list = (res.data as List).cast<Map<String, dynamic>>();
      state = ActivityListState(activities: list, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  /// 上传运动活动到云端。
  /// 把 GpsPoint[] 转成后端要求的 [[lng, lat], ...] GeoJSON 坐标格式。
  Future<String?> saveActivity(ActivitySummary summary) async {
    try {
      // 轨迹点转 [[lng, lat], ...]（GeoJSON LineString 坐标格式）
      final track = summary.gpsPoints
          .map((p) => [p.latLng.longitude, p.latLng.latitude])
          .toList();

      final res = await ApiClient.instance.dio.post('/activities', data: {
        'type': summary.type.name,
        'distance_m': summary.distanceMeters,
        'duration_s': summary.durationSeconds,
        'moving_time_s': summary.movingTimeSeconds,
        'avg_pace_s_per_km': summary.avgPaceSecondsPerKm,
        'avg_speed_kmh': summary.avgSpeedKmh,
        'max_speed_kmh': summary.maxSpeedKmh,
        'elevation_gain_m': summary.elevationGain,
        'elevation_loss_m': summary.elevationLoss,
        'calories': summary.calories,
        'start_time': summary.startTime.toUtc().toIso8601String(),
        'end_time': summary.endTime.toUtc().toIso8601String(),
        'track': track,
      });
      return res.data['id'] as String?;
    } on DioException catch (e) {
      // 上传失败：打印错误便于排查（生产可改为本地缓存重试）
      debugPrint('上传活动失败: ${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('上传活动异常: $e');
      return null;
    }
  }
}

final activityListProvider =
    StateNotifierProvider<ActivityListNotifier, ActivityListState>(
  (ref) => ActivityListNotifier(),
);

/// 按活动 ID 从云端拉取详情（活动行 + 轨迹点）。
class ActivityDetailNotifier
    extends FamilyNotifier<ActivityDetailState, String> {
  @override
  ActivityDetailState build(String activityId) {
    _load(activityId);
    return const ActivityDetailState(loading: true);
  }

  Future<void> _load(String activityId) async {
    try {
      final res = await ApiClient.instance.dio.get('/activities/$activityId');
      final data = res.data as Map<String, dynamic>;
      // 后端返回 track: [[lng, lat], ...]，转回 GpsPoint 列表
      final trackCoords = (data['track'] as List?) ?? [];
      final points = trackCoords.map((coord) {
        final c = coord as List;
        return GpsPoint(
          latLng: LatLng(c[1] as double, c[0] as double), // [lng, lat] → LatLng(lat, lng)
          altitude: 0,
          speed: 0,
          accuracy: 0,
          timestamp: DateTime.parse(data['start_time'] as String),
        );
      }).toList();

      // 移除 track 字段（避免 activity map 太大）
      final activityMap = Map<String, dynamic>.from(data);
      activityMap.remove('track');

      state = ActivityDetailState(
          activity: activityMap, points: points, loading: false);
    } catch (_) {
      state = const ActivityDetailState(loading: false);
    }
  }
}

final activityDetailProvider = NotifierProviderFamily<
    ActivityDetailNotifier, ActivityDetailState, String>(
  ActivityDetailNotifier.new,
);
