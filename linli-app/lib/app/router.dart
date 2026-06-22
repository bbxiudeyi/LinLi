import 'package:go_router/go_router.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/pages/register_page.dart';
import '../features/feed/pages/feed_page.dart';
import '../features/activity/pages/activity_record_page.dart';
import '../features/profile/pages/profile_page.dart';
import '../features/profile/pages/edit_profile_page.dart';
import '../features/activity/pages/activity_detail_page.dart';
import 'main_shell.dart';

final router = GoRouter(
  initialLocation: '/feed',
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
      path: '/profile/edit',
      builder: (context, state) => const EditProfilePage(),
    ),
  ],
);
