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
  /// 成功后同步更新 kudoMap 和 activities 里的 kudo_count，
  /// 保证 UI 即时反映正确数字（后端 kudo_count 已含当前用户的赞）。
  Future<void> toggleKudo(String activityId) async {
    final has = state.kudoMap[activityId] ?? false;
    try {
      if (has) {
        await ApiClient.instance.dio.delete('/activities/$activityId/kudos');
      } else {
        await ApiClient.instance.dio.post('/activities/$activityId/kudos');
      }
      // 更新 kudoMap
      final newMap = Map<String, bool>.from(state.kudoMap);
      newMap[activityId] = !has;
      // 同步更新 activities 里对应项的 kudo_count（点赞 +1，取消 -1）
      final newActivities = state.activities.map((a) {
        if (a['id'] == activityId) {
          final cur = (a['kudo_count'] as num?)?.toInt() ?? 0;
          return {...a, 'kudo_count': cur + (!has ? 1 : -1)};
        }
        return a;
      }).toList();
      state = FeedState(
        activities: newActivities,
        kudoMap: newMap,
        loading: state.loading,
      );
    } catch (e) {
      debugPrint('切换点赞失败: $e');
      // 网络失败，状态不变
    }
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) => FeedNotifier(),
);
