import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// 路段功能规划中，暂未接入后端 API。
  /// 等 segments 端点上线后实现。
  Future<void> loadNearbySegments({
    double? lat,
    double? lng,
    double radiusKm = 50,
  }) async {
    state = state.copyWith(loading: false);
  }

  Future<List<Map<String, dynamic>>> loadLeaderboard(String segmentId) async {
    return const [];
  }
}

final segmentExploreProvider =
    StateNotifierProvider<SegmentExploreNotifier, SegmentExploreState>(
  (ref) => SegmentExploreNotifier(),
);
