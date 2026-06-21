import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/database/local_db.dart';
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

  /// 加载本地所有活动（按开始时间降序）。
  Future<void> loadMyActivities() async {
    state = state.copyWith(loading: true);
    try {
      final data = await LocalDb.queryActivities(limit: 50);
      state = state.copyWith(activities: data, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  /// 保存运动活动：写 activities 行 + 批量写轨迹点。
  /// **修复原 Supabase 版轨迹点丢失的问题**。
  Future<String?> saveActivity(ActivitySummary summary) async {
    try {
      final id = await LocalDb.insertActivity({
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
        'start_time': summary.startTime.toIso8601String(),
        'end_time': summary.endTime.toIso8601String(),
      });

      // 轨迹点入库（核心修复：原版直接丢弃了 summary.gpsPoints）
      final points = <Map<String, dynamic>>[];
      for (var i = 0; i < summary.gpsPoints.length; i++) {
        final p = summary.gpsPoints[i];
        points.add({
          'lat': p.latLng.latitude,
          'lng': p.latLng.longitude,
          'altitude': p.altitude,
          'speed': p.speed,
          'accuracy': p.accuracy,
          'timestamp': p.timestamp.toIso8601String(),
          'seq': i,
        });
      }
      await LocalDb.insertPoints(id, points);

      return id;
    } catch (_) {
      return null;
    }
  }
}

final activityListProvider =
    StateNotifierProvider<ActivityListNotifier, ActivityListState>(
  (ref) => ActivityListNotifier(),
);

/// 按活动 ID 拉取详情（活动行 + 轨迹点）。
/// 用 StateNotifierProvider.family 兼容 riverpod 2.6。
class ActivityDetailNotifier
    extends FamilyNotifier<ActivityDetailState, String> {
  @override
  ActivityDetailState build(String activityId) {
    _load(activityId);
    return const ActivityDetailState(loading: true);
  }

  Future<void> _load(String activityId) async {
    try {
      final activity = await LocalDb.getActivity(activityId);
      final pointRows = await LocalDb.getPoints(activityId);
      final points = pointRows.map((row) {
        return GpsPoint(
          latLng: LatLng(row['lat'] as double, row['lng'] as double),
          altitude: (row['altitude'] as num?)?.toDouble() ?? 0,
          speed: (row['speed'] as num?)?.toDouble() ?? 0,
          accuracy: (row['accuracy'] as num?)?.toDouble() ?? 0,
          timestamp: DateTime.parse(row['timestamp'] as String),
        );
      }).toList();
      state = ActivityDetailState(
          activity: activity, points: points, loading: false);
    } catch (_) {
      state = const ActivityDetailState(loading: false);
    }
  }
}

final activityDetailProvider = NotifierProviderFamily<
    ActivityDetailNotifier, ActivityDetailState, String>(
  ActivityDetailNotifier.new,
);
