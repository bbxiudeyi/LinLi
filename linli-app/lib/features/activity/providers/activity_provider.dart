import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/db/local_db.dart';
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

/// 活动列表 + 上传同步控制器。
///
/// 离线策略：本地 DB 是"我的活动"的权威源。
/// - loadMyActivities：本地优先（秒开），后台拉云端合并。
/// - saveActivity：带客户端 id 上传，成功 markSynced，失败保留 sync_status=0。
/// - retryUnsynced：扫描所有待同步活动逐个上传（App 启动/登录后触发）。
class ActivityListNotifier extends StateNotifier<ActivityListState> {
  ActivityListNotifier() : super(const ActivityListState());

  /// 加载我的活动列表（本地优先：先读本地秒开，后台拉云端更新）。
  Future<void> loadMyActivities() async {
    // ① 本地优先：先读本地 DB，立即展示
    try {
      final local = await LocalDb.instance.listActivities();
      if (!mounted) return;
      state = ActivityListState(activities: local, loading: false);
    } catch (e) {
      debugPrint('读取本地活动列表失败: $e');
    }

    // ② 后台拉云端，合并更新（失败不影响本地展示）
    try {
      final res = await ApiClient.instance.dio.get('/activities');
      final remote = (res.data as List).cast<Map<String, dynamic>>();
      // 云端拉到的都是已同步的，写回本地（去重）
      for (final a in remote) {
        final id = a['id'] as String?;
        if (id == null) continue;
        await LocalDb.instance.insertActivity({
          ...a,
          'created_at': a['start_time'], // 本地表需要 created_at
        });
        await LocalDb.instance.markSynced(id);
      }
      // 重新读本地（合并云端 + 本地未同步的）
      if (!mounted) return;
      final merged = await LocalDb.instance.listActivities();
      state = ActivityListState(activities: merged, loading: false);
    } catch (e) {
      debugPrint('云端活动列表刷新失败（用本地缓存）: $e');
      // 网络失败，保持本地数据，不动 state
    }
  }

  /// 清空内存列表（登出时调用；本地数据保留，按账号隔离）。
  void clear() {
    state = const ActivityListState();
  }

  /// 上传运动活动到云端（带客户端生成的 id，幂等）。
  /// 数据已在录制时写入本地 DB，这里只负责上传 + 更新同步状态。
  ///
  /// [isPrivate] 是用户在保存页选择的可见范围（P0-3：默认私密）。
  /// 上传前先把活动标记为 saved：只有用户明确保存过的活动才会上传，
  /// 与"放弃"互斥（P0-2）；上传中途崩溃也会走重试而不是被当僵尸清理。
  /// 返回活动 id（成功）；失败返回 null 但**数据不丢**（本地保留 sync_status=0）。
  Future<String?> saveActivity(ActivitySummary summary,
      {bool isPrivate = true}) async {
    final activityId = summary.localActivityId;
    if (activityId == null) {
      debugPrint('saveActivity: 缺少 localActivityId');
      return null;
    }
    try {
      // 先落"已保存"状态 + 可见范围，再上传（P0-2/P0-3）
      await LocalDb.instance
          .markSaved(activityId, isPrivate: isPrivate);
      // 多维轨迹点：{lat, lng, ele, speed, time}（与后端 TrackPointInput 对齐）
      final track = summary.gpsPoints.asMap().entries.map((e) {
        final p = e.value;
        return {
          'lat': p.latLng.latitude,
          'lng': p.latLng.longitude,
          'ele': p.altitude,
          'speed': p.speed,
          'time': p.timestamp.toIso8601String(),
        };
      }).toList();

      final res = await ApiClient.instance.dio.post('/activities', data: {
        'id': activityId, // ★ 客户端生成，本地 ID = 云端 ID
        'type': summary.type.name,
        'title': summary.title,
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
        'is_private': isPrivate,
        'track': track,
      });
      // 写本地活动行的 title（录制时本地行无 title，这里补上）
      if (summary.title != null && summary.title!.isNotEmpty) {
        await LocalDb.instance.updateActivityStats(
            activityId, {'title': summary.title});
      }
      final returnedId = res.data['id'] as String?;
      // 上传成功，标记已同步
      await LocalDb.instance.markSynced(activityId);
      return returnedId ?? activityId;
    } on DioException catch (e) {
      // 上传失败：数据已在本地（sync_status=0），不丢，等重试
      debugPrint('上传活动失败（已存本地待重试）: ${e.response?.statusCode} ${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('上传活动异常（已存本地待重试）: $e');
      return null;
    }
  }

  /// 删除活动（P1-2：云端删除失败时不再物理删本地，防"删除复活"）。
  /// - 已同步过的活动：必须先删掉云端，成功才删本地；失败返回 false，
  ///   由 UI 提示重试（tombstone/自动重试留待后续 outbox 改造）。
  /// - 从未同步过的活动：直接删本地即可（云端本来就没有）。
  Future<bool> deleteActivity(String id) async {
    final local = await LocalDb.instance.getActivity(id);
    final wasSynced = (local?['sync_status'] as int? ?? 0) == 1;
    if (wasSynced) {
      try {
        await ApiClient.instance.dio.delete('/activities/$id');
      } catch (e) {
        debugPrint('云端删除活动失败（保留本地，稍后重试）: $e');
        return false;
      }
    }
    await LocalDb.instance.deleteActivity(id);
    await loadMyActivities();
    return true;
  }

  /// 扫描所有未同步的活动，逐个上传重试。
  /// App 启动 / 登录成功后调用。幂等：后端 ON CONFLICT DO NOTHING 保证重传安全。
  Future<void> retryUnsynced() async {
    final unsynced = await LocalDb.instance.getUnsyncedActivities();
    if (unsynced.isEmpty) return;
    debugPrint('发现 ${unsynced.length} 条待同步活动，开始重试');

    for (final row in unsynced) {
      final activityId = row['id'] as String?;
      if (activityId == null) continue;

      // 从本地读轨迹点
      final pointRows = await LocalDb.instance.getPoints(activityId);
      if (pointRows.length < 2) {
        debugPrint('活动 $activityId 点数不足，跳过');
        continue;
      }

      final track = pointRows.map((p) => {
        'lat': (p['lat'] as num).toDouble(),
        'lng': (p['lng'] as num).toDouble(),
        'ele': (p['ele'] as num?)?.toDouble(),
        'speed': (p['speed'] as num?)?.toDouble(),
        'time': p['recorded_at'] as String?,
      }).toList();

      try {
        await ApiClient.instance.dio.post('/activities', data: {
          'id': activityId,
          'type': row['type'],
          'title': row['title'],
          'distance_m': row['distance_m'],
          'duration_s': row['duration_s'],
          'moving_time_s': row['moving_time_s'],
          'avg_pace_s_per_km': row['avg_pace_s_per_km'],
          'avg_speed_kmh': row['avg_speed_kmh'],
          'max_speed_kmh': row['max_speed_kmh'],
          'elevation_gain_m': row['elevation_gain_m'],
          'elevation_loss_m': row['elevation_loss_m'],
          'calories': row['calories'],
          'start_time': row['start_time'],
          'end_time': row['end_time'],
          // SQLite 存的是 INTEGER 0/1，后端要 bool——必须转换，
          // 之前直接传 int 会被 serde 拒绝导致补传永远失败
          'is_private': (row['is_private'] as int? ?? 1) == 1,
          'track': track,
        });
        await LocalDb.instance.markSynced(activityId);
        debugPrint('活动 $activityId 同步成功');
      } catch (e) {
        debugPrint('活动 $activityId 重试失败: $e');
        // 继续下一条，下次启动再试
      }
    }
  }
}

final activityListProvider =
    StateNotifierProvider<ActivityListNotifier, ActivityListState>(
  (ref) => ActivityListNotifier(),
);

/// 按活动 ID 加载详情（本地优先 + 云端刷新）。
class ActivityDetailNotifier
    extends FamilyNotifier<ActivityDetailState, String> {
  bool _disposed = false;

  ActivityDetailNotifier() {
    // FamilyNotifier 无 mounted 属性，用 onDispose 标志位防止销毁后写 state
    // （build 执行时 ref 才可用，故在构造里注册）
  }

  @override
  ActivityDetailState build(String activityId) {
    ref.onDispose(() => _disposed = true);
    _load(activityId);
    return const ActivityDetailState(loading: true);
  }

  Future<void> _load(String activityId) async {
    // ① 本地优先：先读本地，秒开（含离线/未同步的活动）
    try {
      final local = await LocalDb.instance.getActivity(activityId);
      final pointRows = await LocalDb.instance.getPoints(activityId);
      if (local != null) {
        final points = _rowsToPoints(pointRows, local['start_time'] as String?);
        if (_disposed) return;
        state = ActivityDetailState(
          activity: local,
          points: points,
          loading: false,
        );
      }
    } catch (e) {
      debugPrint('读取本地活动详情失败: $e');
    }

    // ② 后台拉云端刷新（失败不影响本地展示）
    try {
      final res = await ApiClient.instance.dio.get('/activities/$activityId');
      final data = res.data as Map<String, dynamic>;
      final trackPoints = (data['track'] as List?) ?? [];
      final points = trackPoints.map((raw) {
        final p = raw as Map<String, dynamic>;
        final startTime = data['start_time'] as String? ?? '';
        return GpsPoint(
          latLng: LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
          altitude: (p['ele'] as num?)?.toDouble() ?? 0,
          speed: (p['speed'] as num?)?.toDouble() ?? 0,
          accuracy: 0,
          timestamp: p['recorded_at'] != null
              ? DateTime.parse(p['recorded_at'] as String)
              : (startTime.isNotEmpty ? DateTime.parse(startTime) : DateTime.now()),
        );
      }).toList();

      final activityMap = Map<String, dynamic>.from(data);
      activityMap.remove('track');

      if (_disposed) return;
      state = ActivityDetailState(
          activity: activityMap, points: points, loading: false);
    } catch (e) {
      debugPrint('云端活动详情刷新失败（用本地）: $e');
      // 网络失败保持本地数据；本地也没有则停止 loading
      if (state.activity == null && !_disposed) {
        state = const ActivityDetailState(loading: false);
      }
    }
  }

  /// 本地点表行 → GpsPoint 列表。
  List<GpsPoint> _rowsToPoints(
      List<Map<String, dynamic>> rows, String? fallbackTime) {
    return rows.map((p) {
      final recorded = p['recorded_at'] as String?;
      return GpsPoint(
        latLng: LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        ),
        altitude: (p['ele'] as num?)?.toDouble() ?? 0,
        speed: (p['speed'] as num?)?.toDouble() ?? 0,
        accuracy: 0,
        timestamp: recorded != null
            ? DateTime.parse(recorded)
            : (fallbackTime != null && fallbackTime.isNotEmpty
                ? DateTime.parse(fallbackTime)
                : DateTime.now()),
      );
    }).toList();
  }

  /// 下载活动的 GPX 文件（返回 XML 字符串，由调用方决定分享/保存）。
  Future<String?> downloadGpx(String activityId) async {
    try {
      final res = await ApiClient.instance.dio.get(
        '/activities/$activityId/export.gpx',
        options: Options(responseType: ResponseType.plain),
      );
      return res.data as String;
    } catch (e) {
      debugPrint('下载 GPX 失败: $e');
      return null;
    }
  }
}

final activityDetailProvider = NotifierProviderFamily<
    ActivityDetailNotifier, ActivityDetailState, String>(
  ActivityDetailNotifier.new,
);
