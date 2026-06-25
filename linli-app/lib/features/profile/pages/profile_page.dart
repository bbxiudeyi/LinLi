import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme_provider.dart';
import '../../../core/db/local_db.dart';
import '../../../shared/widgets/activity_heatmap.dart';
import '../../activity/services/activity_stats.dart';
import '../providers/profile_provider.dart';
import '../../auth/providers/auth_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allActivities = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadProfile();
      ref.read(activityStatsProvider.notifier).load();
      _loadAllActivities();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllActivities() async {
    final activities = await LocalDb.instance.listActivities();
    if (mounted) setState(() => _allActivities = activities);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 头部：头像 + 昵称 + 设置
            _ProfileHeader(
              profile: profile.profile,
              onSettings: () => _showSettings(context, ref),
            ),
            // 面板 / 活动 Tab
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFFF6B35),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFFF6B35),
              tabs: const [
                Tab(text: '面板'),
                Tab(text: '活动'),
              ],
            ),
            const Divider(height: 1),
            // Tab 内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 面板：活跃日历
                    RefreshIndicator(
                      onRefresh: () async {
                        await ref
                            .read(profileProvider.notifier)
                            .loadProfile();
                        await ref
                            .read(activityStatsProvider.notifier)
                            .load();
                      },
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        children: [
                          _HeatmapCard(
                              stats:
                                  ref.watch(activityStatsProvider).stats),
                        ],
                      ),
                    ),
                  // 活动：全部活动 + 搜索
                  _ActivitiesTab(
                    activities: _allActivities,
                    onChanged: _loadAllActivities,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
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
  final VoidCallback? onSettings;

  const _ProfileHeader({this.profile, this.onSettings});

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
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

/// 活跃日历卡片。
class _HeatmapCard extends StatelessWidget {
  final List<DailyStat> stats;
  const _HeatmapCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('活动活跃度',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('最近一年的运动记录',
              style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 12),
          ActivityHeatmap(stats: stats),
        ],
      ),
    );
  }
}

/// 活动 tab：全部活动列表 + 搜索。
class _ActivitiesTab extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final Future<void> Function() onChanged;
  const _ActivitiesTab({required this.activities, required this.onChanged});

  @override
  State<_ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends State<_ActivitiesTab> {
  String _query = '';

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.activities;
    final q = _query.toLowerCase();
    return widget.activities.where((a) {
      final type = (a['type'] as String?)?.toLowerCase() ?? '';
      final title = (a['title'] as String?)?.toLowerCase() ?? '';
      return type.contains(q) || title.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索活动（类型或标题）',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // 列表
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? '还没有活动记录' : '没有匹配的活动',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final activity = list[index];
                    final type = activity['type'] as String? ?? 'run';
                    final distance = (activity['distance_m'] as num?)?.toInt() ?? 0;
                    final distanceStr = distance >= 1000
                        ? '${(distance / 1000).toStringAsFixed(2)} km'
                        : '$distance m';
                    final sportIcon = {
                      'run': '🏃',
                      'ride': '🚴',
                      'hike': '🥾',
                      'walk': '🚶',
                    }[type] ?? '🏃';
                    final synced = (activity['sync_status'] as num?)?.toInt() == 1;

                    return ListTile(
                      leading: Text(sportIcon,
                          style: const TextStyle(fontSize: 24)),
                      title: Row(
                        children: [
                          Flexible(
                              child: Text(
                                  activity['title'] ?? distanceStr)),
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
                      onTap: () async {
                        await context
                            .push('/activity/${activity['id']}');
                        // 返回后刷新（可能上传状态变化）
                        widget.onChanged();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
