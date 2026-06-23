import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme_provider.dart';
import '../providers/profile_provider.dart';
import '../../auth/providers/auth_provider.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      // 用透明背景的 AppBar 承载设置按钮，保证可点击（无标题、无阴影）
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () => _showSettings(context, ref),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(profileProvider.notifier).loadProfile(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _ProfileHeader(profile: profile.profile),
                const SizedBox(height: 16),
                _StatsRow(),
                const Divider(height: 32),
                _RecentActivities(activities: profile.recentActivities),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          // 放在 builder 内部：每次 setLocalState 都重新读最新值
          final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑资料'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile/edit');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('深色模式'),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (val) {
                      ref.read(themeModeProvider.notifier).setThemeMode(
                            val ? ThemeMode.dark : ThemeMode.light,
                          );
                      // 触发本 builder 重建 → isDark 重新读取 → Switch 滑块动
                      setLocalState(() {});
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('退出登录',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(authProvider.notifier).signOut();
                    context.go('/login');
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic>? profile;

  const _ProfileHeader({this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundImage: profile?['avatar_url'] != null
                ? NetworkImage(profile!['avatar_url'])
                : null,
            child: profile?['avatar_url'] == null
                ? const Icon(Icons.person, size: 36)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?['nickname'] ?? '未设置昵称',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (profile?['bio'] != null)
                  Text(profile!['bio'],
                      style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: '活动', value: '0'),
          _StatItem(label: '关注', value: '0'),
          _StatItem(label: '粉丝', value: '0'),
          _StatItem(label: '路段', value: '0'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }
}

class _RecentActivities extends StatelessWidget {
  final List<Map<String, dynamic>> activities;

  const _RecentActivities({required this.activities});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('最近活动',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        if (activities.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text('还没有活动记录',
                  style: TextStyle(color: Colors.grey[500])),
            ),
          )
        else
          ...activities.map((activity) {
            final type = activity['type'] as String? ?? 'run';
            final distance = activity['distance_m'] as int? ?? 0;
            final distanceStr = distance >= 1000
                ? '${(distance / 1000).toStringAsFixed(2)} km'
                : '$distance m';
            final sportIcon = {
              'run': '🏃',
              'ride': '🚴',
              'hike': '🥾',
              'walk': '🚶',
            }[type] ?? '🏃';
            // 本地活动行带 sync_status：0=待同步, 1=已同步
            final synced = (activity['sync_status'] as int?) == 1;

            return ListTile(
              leading: Text(sportIcon, style: const TextStyle(fontSize: 24)),
              title: Row(
                children: [
                  Flexible(
                      child: Text(activity['title'] ?? distanceStr)),
                  if (!synced) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('未同步',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade800)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(distanceStr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push('/activity/${activity['id']}'),
            );
          }),
      ],
    );
  }
}
