import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/local_db.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileState {
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> recentActivities;
  final int activityCount; // 本地活动总数（用于统计展示）
  final bool loading;

  const ProfileState({
    this.profile,
    this.recentActivities = const [],
    this.activityCount = 0,
    this.loading = false,
  });

  ProfileState copyWith({
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>>? recentActivities,
    int? activityCount,
    bool? loading,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      recentActivities: recentActivities ?? this.recentActivities,
      activityCount: activityCount ?? this.activityCount,
      loading: loading ?? this.loading,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final Ref _ref;
  ProfileNotifier(this._ref) : super(const ProfileState());

  /// 加载当前用户资料 + 最近活动（本地优先，后台云端刷新）。
  /// 本地优先：秒开 + 离线可用；活动列表读本地（含未同步的）。
  Future<void> loadProfile() async {
    final user = _ref.read(authProvider).user;
    if (user == null) {
      state = state.copyWith(loading: false);
      return;
    }

    // ① 本地优先：先读本地缓存，立即展示
    try {
      final cachedProfile = await LocalDb.instance.getMyProfile();
      final localActivities = await LocalDb.instance.listActivities(limit: 10);
      final total = await LocalDb.instance.countActivities();
      if (!mounted) return;
      if (cachedProfile != null || localActivities.isNotEmpty) {
        state = ProfileState(
          profile: cachedProfile,
          recentActivities: localActivities,
          activityCount: total,
          loading: false,
        );
      } else {
        // 本地无数据，显示 loading 等云端
        state = state.copyWith(loading: true);
      }
    } catch (e) {
      debugPrint('读取本地资料失败: $e');
      state = state.copyWith(loading: true);
    }

    // ② 后台拉云端刷新（失败用本地兜底，不报错）
    try {
      final profileRes = await ApiClient.instance.dio.get('/auth/me');
      final profile = profileRes.data as Map<String, dynamic>;
      // 写入本地缓存
      await LocalDb.instance.saveMyProfile(profile);

      // 重新读本地活动（合并云端后），保证未同步的也显示
      final activities = await LocalDb.instance.listActivities(limit: 10);
      final total = await LocalDb.instance.countActivities();

      if (!mounted) return;
      state = ProfileState(
        profile: profile,
        recentActivities: activities,
        activityCount: total,
        loading: false,
      );
    } catch (e) {
      debugPrint('云端资料刷新失败（用本地缓存）: $e');
      // 网络失败，保持本地数据
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  /// 更新资料到云端，成功后刷新本地 state + 本地缓存。
  /// 若服务端返回新 token（改密码时会重签），同步更新本地 token。
  Future<bool> updateProfile(Map<String, dynamic> fields) async {
    try {
      final res = await ApiClient.instance.dio.patch('/users/me', data: fields);
      final data = res.data as Map<String, dynamic>;
      // 改密码时后端会返回重签的 token，替换本地旧 token
      final newToken = data['token'] as String?;
      if (newToken != null && newToken.isNotEmpty) {
        await ApiClient.instance.saveToken(newToken);
      }
      // 用服务器返回的完整 profile 覆盖本地（token 字段已剥离）
      final profile = Map<String, dynamic>.from(data)..remove('token');
      // 写入本地缓存
      await LocalDb.instance.saveMyProfile(profile);
      state = state.copyWith(profile: profile);
      return true;
    } on DioException catch (e) {
      debugPrint('更新资料失败: ${e.response?.data}');
      return false;
    } catch (e) {
      debugPrint('更新资料异常: $e');
      return false;
    }
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(ref),
);
