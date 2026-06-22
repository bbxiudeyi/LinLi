import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_db.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileState {
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> recentActivities;
  final bool loading;

  const ProfileState({
    this.profile,
    this.recentActivities = const [],
    this.loading = false,
  });

  ProfileState copyWith({
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>>? recentActivities,
    bool? loading,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      recentActivities: recentActivities ?? this.recentActivities,
      loading: loading ?? this.loading,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final Ref _ref;
  ProfileNotifier(this._ref) : super(const ProfileState());

  /// 加载当前登录用户的资料 + 最近活动（本地数据库）。
  Future<void> loadProfile() async {
    final user = _ref.read(authProvider).user;
    if (user == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true);
    try {
      final profile = await LocalDb.getUser(user.id);
      final activities = await LocalDb.queryActivities(limit: 10);
      state = ProfileState(
        profile: profile,
        recentActivities: activities,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  /// 更新当前用户资料，成功后刷新本地 state。
  Future<bool> updateProfile(Map<String, dynamic> fields) async {
    final user = _ref.read(authProvider).user;
    if (user == null) return false;

    try {
      await LocalDb.updateUser(user.id, fields);
      // 合并到现有 profile，避免整页重新加载
      final merged = <String, dynamic>{
        ...?state.profile,
        ...fields,
      };
      state = state.copyWith(profile: merged);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(ref),
);
