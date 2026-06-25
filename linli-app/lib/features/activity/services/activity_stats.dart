import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/local_db.dart';
import '../../../core/network/api_client.dart';

/// 每日活动统计（用于活跃日历）。
class DailyStat {
  final DateTime date;
  final int count;
  const DailyStat(this.date, this.count);
}

/// 活跃日历状态。
class ActivityStatsState {
  final List<DailyStat> stats;
  final bool loading;
  const ActivityStatsState({this.stats = const [], this.loading = false});
}

/// 加载最近一年的每日活动数（本地优先 + 云端刷新）。
class ActivityStatsNotifier extends StateNotifier<ActivityStatsState> {
  ActivityStatsNotifier() : super(const ActivityStatsState());

  Future<void> load() async {
    // ① 本地优先：从本地 activities 表按日聚合
    try {
      final rows = await LocalDb.instance.rawQuery(
        'SELECT date(start_time) AS d, COUNT(*) AS c FROM activities GROUP BY d ORDER BY d',
      );
      final local = rows
          .map((r) => DailyStat(
                DateTime.parse(r['d'] as String),
                (r['c'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      if (!mounted) return;
      state = ActivityStatsState(stats: local, loading: false);
    } catch (e) {
      debugPrint('读取本地活动统计失败: $e');
    }

    // ② 云端刷新（失败用本地）
    try {
      final res = await ApiClient.instance.dio
          .get('/activities/stats/daily');
      final list = (res.data as List).cast<Map<String, dynamic>>();
      final remote = list
          .map((d) => DailyStat(
                DateTime.parse(d['date'] as String),
                (d['count'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      if (!mounted) return;
      state = ActivityStatsState(stats: remote, loading: false);
    } catch (e) {
      debugPrint('云端活动统计刷新失败: $e');
    }
  }
}

final activityStatsProvider =
    StateNotifierProvider<ActivityStatsNotifier, ActivityStatsState>(
  (ref) => ActivityStatsNotifier(),
);
