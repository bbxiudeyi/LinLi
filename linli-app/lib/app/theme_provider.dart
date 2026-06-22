import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式状态管理（亮色/暗色/跟随系统），持久化到 SharedPreferences。
///
/// 用法：在根 Widget 用 ref.watch(themeModeProvider) 取 ThemeMode，
/// 设置时调 ref.read(themeModeProvider.notifier).setThemeMode(...)。
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      state = _parse(saved) ?? ThemeMode.system;
    } catch (_) {
      // 读取失败保持默认
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {}
  }

  ThemeMode? _parse(String? s) {
    switch (s) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
