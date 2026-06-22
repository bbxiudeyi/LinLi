import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_db.dart';
import '../../../core/database/local_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final LocalUser? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
  });

  AuthState copyWith({AuthStatus? status, LocalUser? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// 本地认证：手机号 + 假验证码（任意 6 位数字都通过）。
///
/// 替代 Supabase Auth 的 OTP 登录。单用户本地模式，无需云服务。
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  void _init() {
    // 本地模式：默认未登录（登录状态不持久化，每次启动需重新登录）
    state = state.copyWith(status: AuthStatus.unauthenticated);
  }

  /// 发送验证码（本地模式：假装发送成功）。
  Future<void> signInWithPhone(String phone) async {
    state = state.copyWith(error: null);
    // 本地模式不做任何实际请求，直接成功（UI 会进入验证码输入步骤）
  }

  /// 验证验证码：任意 6 位数字都通过。
  /// 查本地 users 表：有该 phone → 登录；无 → 报错让 UI 跳注册。
  Future<void> verifyOtp(String phone, String code) async {
    if (code.length != 6) {
      state = state.copyWith(error: '请输入 6 位验证码');
      return;
    }
    try {
      final user = await LocalDb.findUserByPhone(phone);
      if (user != null) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
      } else {
        // 新用户：登录流程仍标记成功，由 UI 判断是否跳注册页
        // 这里给一个临时未注册标记，供 login_page 决定跳转
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: '__new_user__',
        );
      }
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
    }
  }

  /// 注册新用户（本地创建）。
  Future<void> register(String phone, String nickname) async {
    try {
      final user = await LocalDb.createUser(phone: phone, nickname: nickname);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (e) {
      state = state.copyWith(error: '注册失败：$e');
    }
  }

  /// 退出登录（清内存状态，不删数据）。
  Future<void> signOut() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
