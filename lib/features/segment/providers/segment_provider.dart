import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/supabase_client.dart';

/// 发现页视图模式：列表 / 地图
enum SegmentViewMode { list, map }

class SegmentExploreState {
  final List<Map<String, dynamic>> segments;
  final bool loading;
  final SegmentViewMode viewMode;

  const SegmentExploreState({
    this.segments = const [],
    this.loading = false,
    this.viewMode = SegmentViewMode.list,
  });

  SegmentExploreState copyWith({
    List<Map<String, dynamic>>? segments,
    bool? loading,
    SegmentViewMode? viewMode,
  }) {
    return SegmentExploreState(
      segments: segments ?? this.segments,
      loading: loading ?? this.loading,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

class SegmentExploreNotifier extends StateNotifier<SegmentExploreState> {
  SegmentExploreNotifier() : super(const SegmentExploreState());

  /// 切换列表/地图视图
  void setViewMode(SegmentViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  Future<void> loadNearbySegments({
    double? lat,
    double? lng,
    double radiusKm = 50,
  }) async {
    state = state.copyWith(loading: true);
    try {
      var query = supabase.from('segments')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      final data = await query;
      state =
          state.copyWith(segments: List.from(data), loading: false);
    } catch (e) {
      state = state.copyWith(loading: false);
    }
  }

  Future<List<Map<String, dynamic>>> loadLeaderboard(
      String segmentId) async {
    final data = await supabase.from('segment_efforts')
        .select(''', users:nickname, users:avatar_url''')
        .eq('segment_id', segmentId)
        .order('duration_s', ascending: true)
        .limit(50);
    return List.from(data);
  }
}

final segmentExploreProvider =
    StateNotifierProvider<SegmentExploreNotifier, SegmentExploreState>(
  (ref) => SegmentExploreNotifier(),
);
