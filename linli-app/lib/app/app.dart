import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/providers/auth_provider.dart';
import 'theme.dart';
import 'theme_provider.dart';
import 'router.dart';

class TujiApp extends ConsumerWidget {
  const TujiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 在根部监听认证状态（P1-1）：保证 App 一启动就实例化 AuthNotifier，
    // 冷启动时恢复登录态 + 切换本地数据归属 + 触发待同步重试，
    // 而不是等到某个页面恰好用到 authProvider 才发生。
    ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: '林立',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
