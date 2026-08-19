import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/local_db.dart';
import '../../../core/network/api_client.dart';

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
  ProfileNotifier() : super(const ProfileState());

  /// 加载当前用户资料 + 最近活动（本地优先，后台云端刷新）。
  /// 本地优先：秒开 + 离线可用；活动列表读本地（含未同步的）。
  ///
  /// 注意：不依赖 authProvider.user——因为 App 启动时 authProvider 异步
  /// 恢复登录态（要等 /auth/me 网络请求），此时 user 可能还是 null。
  /// 但本地缓存的 profile 里就有 avatar_url，应立即展示，不等网络。
  Future<void> loadProfile() async {
    // ① 本地优先：先读本地缓存，立即展示（即使 authProvider 还没恢复）
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
    //    即使 authProvider 还没恢复，ApiClient 的 token 拦截器会从磁盘读 token，
    //    所以这里直接请求即可；token 无效时 catch 走本地兜底。
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

  /// 上传头像：选好的图片文件 → 上传到后端 → PATCH /users/me 写入 avatar_url。
  /// 成功返回 true（本地 state + 缓存已刷新），失败返回 false。
  /// 图片压缩由调用方（image_picker 的 maxWidth/imageQuality）完成。
  Future<bool> uploadAvatar(File image) async {
    // ① 上传文件拿 URL
    final url = await ApiClient.instance.uploadAvatar(image);
    if (url == null) {
      debugPrint('头像上传失败');
      return false;
    }
    // ② PATCH /users/me 写入 avatar_url（复用 updateProfile 的刷新逻辑）
    return updateProfile({'avatar_url': url});
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(),
);
