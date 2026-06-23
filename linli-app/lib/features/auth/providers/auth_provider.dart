import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';
import '../../activity/providers/activity_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// 用户信息（来自后端 /auth/me 或 register/login 的返回）。
class RemoteUser {
  final String id;
  final String email;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? birthday;
  final double? weightKg;
  final String createdAt;

  const RemoteUser({
    required this.id,
    required this.email,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.birthday,
    this.weightKg,
    required this.createdAt,
  });

  factory RemoteUser.fromJson(Map<String, dynamic> j) => RemoteUser(
        id: j['id'] as String,
        email: j['email'] as String,
        nickname: j['nickname'] as String,
        avatarUrl: j['avatar_url'] as String?,
        bio: j['bio'] as String?,
        gender: j['gender'] as String?,
        birthday: j['birthday'] as String?,
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        createdAt: j['created_at'] as String,
      );
}

class AuthState {
  final AuthStatus status;
  final RemoteUser? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
  });

  AuthState copyWith({AuthStatus? status, RemoteUser? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// 云端认证：邮箱 + 密码。
/// 调用 Rust 后端 /api/v1/auth/* 接口。
class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  AuthNotifier(this._ref) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    // 启动时检查是否有持久化 token，有的话调 /auth/me 恢复登录态
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('linli_jwt_token');
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final res = await ApiClient.instance.dio.get('/auth/me');
      final user = RemoteUser.fromJson(res.data as Map<String, dynamic>);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      // 登录态恢复成功，触发待同步活动的重试（fire-and-forget）
      _triggerSync();
    } catch (_) {
      // token 失效，清除
      await ApiClient.instance.clearToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// fire-and-forget 触发待同步活动重试。
  void _triggerSync() {
    Future(() async {
      try {
        await _ref.read(activityListProvider.notifier).retryUnsynced();
      } catch (_) {}
    });
  }

  /// 登录（邮箱 + 密码）。
  Future<void> login(String email, String password) async {
    state = state.copyWith(error: null);
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = res.data['token'] as String;
      final user = RemoteUser.fromJson(res.data['user'] as Map<String, dynamic>);
      await ApiClient.instance.saveToken(token);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      _triggerSync();
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '登录失败';
      state = state.copyWith(error: msg);
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
    }
  }

  /// 注册（邮箱 + 密码 + 昵称）。
  Future<void> register(String email, String password, String nickname) async {
    state = state.copyWith(error: null);
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/register',
        data: {'email': email, 'password': password, 'nickname': nickname},
      );
      final token = res.data['token'] as String;
      final user = RemoteUser.fromJson(res.data['user'] as Map<String, dynamic>);
      await ApiClient.instance.saveToken(token);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      _triggerSync();
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '注册失败';
      state = state.copyWith(error: msg);
    } catch (e) {
      state = state.copyWith(error: '注册失败：$e');
    }
  }

  /// 退出登录：通知后端撤销 token + 清本地状态。
  Future<void> signOut() async {
    try {
      // 通知后端撤销 token（token_version + 1）
      await ApiClient.instance.dio.post('/auth/logout');
    } catch (_) {
      // 网络失败不影响登出
    }
    await ApiClient.instance.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
