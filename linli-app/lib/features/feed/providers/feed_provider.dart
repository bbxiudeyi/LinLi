import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_db.dart';

class FeedState {
  final List<Map<String, dynamic>> activities;
  final bool loading;
  // 点赞状态：activityId -> 是否已赞
  final Map<String, bool> kudoMap;

  const FeedState({
    this.activities = const [],
    this.loading = false,
    this.kudoMap = const {},
  });

  FeedState copyWith({
    List<Map<String, dynamic>>? activities,
    bool? loading,
    Map<String, bool>? kudoMap,
  }) {
    return FeedState(
      activities: activities ?? this.activities,
      loading: loading ?? this.loading,
      kudoMap: kudoMap ?? this.kudoMap,
    );
  }
}

/// 本地 Feed：单用户模式，只显示自己的活动（无关注/他人）。
/// 点赞/取消点赞针对自己的活动。
class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier() : super(const FeedState());

  Future<void> loadFeed() async {
    state = state.copyWith(loading: true);
    try {
      final data = await LocalDb.queryActivities(limit: 30);

      // 查每个活动的点赞状态（单用户：给自己点赞）
      final kudoMap = <String, bool>{};
      for (final a in data) {
        final id = a['id'] as String;
        kudoMap[id] = await LocalDb.hasKudo(id);
      }

      state = FeedState(activities: data, kudoMap: kudoMap, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  /// 切换某活动的点赞状态。
  Future<void> toggleKudo(String activityId) async {
    final has = await LocalDb.hasKudo(activityId);
    if (has) {
      await LocalDb.removeKudo(activityId);
    } else {
      await LocalDb.addKudo(activityId);
    }
    final newMap = Map<String, bool>.from(state.kudoMap);
    newMap[activityId] = !has;
    state = state.copyWith(kudoMap: newMap);
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) => FeedNotifier(),
);
