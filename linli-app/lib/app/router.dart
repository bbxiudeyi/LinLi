import 'package:go_router/go_router.dart';
import '../core/network/api_client.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/pages/register_page.dart';
import '../features/club/pages/club_list_page.dart';
import '../features/feed/pages/feed_page.dart';
import '../features/activity/pages/activity_record_page.dart';
import '../features/profile/pages/profile_page.dart';
import '../features/profile/pages/edit_profile_page.dart';
import '../features/profile/pages/user_profile_page.dart';
import '../features/activity/pages/activity_detail_page.dart';
import 'main_shell.dart';

/// 需要登录才能访问的路径前缀。
const _protectedPrefixes = ['/feed', '/record', '/clubs', '/profile', '/activity', '/user'];

final router = GoRouter(
  initialLocation: '/feed',
  redirect: (context, state) {
    final isLoggedIn = ApiClient.instance.hasToken;
    final location = state.matchedLocation;
    final goingAuth = location == '/login' || location == '/register';
    final goingProtected =
        _protectedPrefixes.any((p) => location == p || location.startsWith('$p/'));

    // 1) 没登录却想去受保护页 → 踢去登录，记住原本想去的地方
    if (!isLoggedIn && goingProtected) {
      return '/login?redirect=${Uri.encodeComponent(location)}';
    }
    // 2) 已登录还停在登录/注册页 → 直接进首页，别再登一次
    if (isLoggedIn && goingAuth) {
      final redirect = state.uri.queryParameters['redirect'];
      return (redirect != null && redirect.isNotEmpty) ? redirect : '/feed';
    }
    // 3) 其他情况正常放行
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    ShellRoute(
      builder: (context, state, child) {
        return MainShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/feed',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FeedPage(),
          ),
        ),
        GoRoute(
          path: '/record',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ActivityRecordPage(),
          ),
        ),
        GoRoute(
          path: '/clubs',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ClubListPage(),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProfilePage(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/activity/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ActivityDetailPage(activityId: id);
      },
    ),
    GoRoute(
      path: '/user/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return UserProfilePage(userId: id);
      },
    ),
    GoRoute(
      path: '/profile/edit',
      builder: (context, state) => const EditProfilePage(),
    ),
  ],
);
