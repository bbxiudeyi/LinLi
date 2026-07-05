import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  static const _tabs = [
    _TabConfig('/feed', Icons.home_outlined, Icons.home, '动态'),
    _TabConfig('/record', Icons.play_circle_outline, Icons.play_circle, '记录'),
    _TabConfig('/clubs', Icons.groups_2_outlined, Icons.groups_2, '俱乐部'),
    _TabConfig('/profile', Icons.person_outline, Icons.person, '我的'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) {
          // 切换 tab 前，关闭任何已打开的模态弹窗（底部 sheet / dialog），
          // 避免切走后残留白色蒙罩。
          // settings sheet 用 useRootNavigator: true 挂在根 navigator，
          // 这里也用 rootNavigator: true 才能关掉它。
          Navigator.of(context, rootNavigator: true).popUntil(
              (route) => route is! PopupRoute && route is! RawDialogRoute);
          context.go(_tabs[i].path);
        },
        items: _tabs
            .map((tab) => BottomNavigationBarItem(
                  icon: Icon(tab.icon),
                  activeIcon: Icon(tab.activeIcon),
                  label: tab.label,
                ))
            .toList(),
      ),
    );
  }
}

class _TabConfig {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _TabConfig(this.path, this.icon, this.activeIcon, this.label);
}
