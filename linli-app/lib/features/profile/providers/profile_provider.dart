import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
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

  /// 从云端加载当前用户资料 + 最近活动。
  Future<void> loadProfile() async {
    final user = _ref.read(authProvider).user;
    if (user == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true);
    try {
      // 并行请求：用户资料 + 活动列表
      final profileRes = await ApiClient.instance.dio.get('/auth/me');
      final activitiesRes = await ApiClient.instance.dio.get(
        '/activities',
        queryParameters: {'limit': 10},
      );

      state = ProfileState(
        profile: profileRes.data as Map<String, dynamic>,
        recentActivities:
            (activitiesRes.data as List).cast<Map<String, dynamic>>(),
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  /// 更新资料到云端，成功后刷新本地 state。
  Future<bool> updateProfile(Map<String, dynamic> fields) async {
    try {
      final res = await ApiClient.instance.dio.patch('/users/me', data: fields);
      // 用服务器返回的完整 profile 覆盖本地
      state = state.copyWith(profile: res.data as Map<String, dynamic>);
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
