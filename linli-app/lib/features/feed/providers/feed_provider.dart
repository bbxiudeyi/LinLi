import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

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

/// 云端 Feed：关注流（自己 + 关注的人的活动）。
class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier() : super(const FeedState());

  Future<void> loadFeed() async {
    state = state.copyWith(loading: true);
    try {
      final res = await ApiClient.instance.dio.get('/feed');
      final data = (res.data as List).cast<Map<String, dynamic>>();

      // 后端返回了 has_kudo 字段，直接用它构建 kudoMap
      final kudoMap = <String, bool>{};
      for (final a in data) {
        final id = a['id'] as String?;
        if (id != null) {
          kudoMap[id] = a['has_kudo'] as bool? ?? false;
        }
      }

      state = FeedState(activities: data, kudoMap: kudoMap, loading: false);
    } catch (e) {
      debugPrint('加载 Feed 失败: $e');
      state = state.copyWith(loading: false);
    }
  }

  /// 切换某活动的点赞状态（调云端 API）。
  Future<void> toggleKudo(String activityId) async {
    final has = state.kudoMap[activityId] ?? false;
    try {
      if (has) {
        await ApiClient.instance.dio.delete('/activities/$activityId/kudos');
      } else {
        await ApiClient.instance.dio.post('/activities/$activityId/kudos');
      }
      final newMap = Map<String, bool>.from(state.kudoMap);
      newMap[activityId] = !has;
      state = state.copyWith(kudoMap: newMap);
    } catch (e) {
      debugPrint('切换点赞失败: $e');
      // 网络失败，状态不变
    }
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) => FeedNotifier(),
);
