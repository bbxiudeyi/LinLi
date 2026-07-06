import 'package:badges/badges.dart' as badges;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../providers/feed_provider.dart';

class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(feedProvider.notifier).loadFeed();
      _loadUnread();
    });
  }

  /// 拉取未读通知数（用于 AppBar 角标）。
  Future<void> _loadUnread() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications/unread_count');
      final count = (res.data['count'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('动态'),
        actions: [
          // 好友搜索（左）
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索好友',
            onPressed: () => context.push('/search'),
          ),
          // 消息通知（右）+ 未读角标
          IconButton(
            tooltip: '消息通知',
            onPressed: () async {
              await context.push('/notifications');
              // 从通知页返回后刷新角标（已读后数量应减少）
              _loadUnread();
            },
            icon: badges.Badge(
              showBadge: _unreadCount > 0,
              badgeContent: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              badgeStyle: const badges.BadgeStyle(
                badgeColor: Colors.black,
                padding: EdgeInsets.all(4),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar 已处理顶部安全区
        child: _buildBody(context, ref, feed),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, FeedState feed) {
    if (feed.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (feed.activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('还没有动态',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            Text('关注其他运动爱好者来查看他们的活动',
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider.notifier).loadFeed(),
      child: ListView.builder(
        itemCount: feed.activities.length,
        itemBuilder: (context, index) {
          final activity = feed.activities[index];
          final id = activity['id'] as String?;
          final hasKudo = feed.kudoMap[id] ?? false;
          return _ActivityCard(
            activity: activity,
            hasKudo: hasKudo,
            onKudo: id == null ? null : () => ref.read(feedProvider.notifier).toggleKudo(id),
            onTap: id == null ? null : () => context.push('/activity/$id'),
          );
        },
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  final bool hasKudo;
  final VoidCallback? onKudo;
  final VoidCallback? onTap;

  const _ActivityCard({
    required this.activity,
    required this.hasKudo,
    required this.onKudo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String? ?? 'run';
    final distance = activity['distance_m'] as int? ?? 0;
    final duration = activity['duration_s'] as int? ?? 0;

    final sportLabel = {
      'run': '跑步',
      'ride': '骑行',
      'hike': '徒步',
      'walk': '走路',
    }[type] ?? type;

    final sportIcon = {
      'run': '🏃',
      'ride': '🚴',
      'hike': '🥾',
      'walk': '🚶',
    }[type] ?? '🏃';

    final distanceStr =
        distance >= 1000 ? '${(distance / 1000).toStringAsFixed(2)} km' : '$distance m';
    final durationStr = _formatDuration(duration);

    // 后端返回扁平的 nickname / avatar_url（无嵌套 users 对象）
    final nickname = (activity['nickname'] as String?) ?? '未知用户';
    // 点赞数：直接用后端的 kudo_count（已含当前用户的赞）。
    // toggleKudo 成功后 provider 会同步更新这个字段，UI 即时正确。
    final kudoCount = (activity['kudo_count'] as num?)?.toInt() ?? 0;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User row（扁平 nickname / avatar_url）—— 点击跳该用户资料页
              GestureDetector(
                onTap: () {
                  final userId = activity['user_id'] as String?;
                  if (userId != null) context.push('/user/$userId');
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: (activity['avatar_url'] as String?) != null
                          ? CachedNetworkImageProvider(activity['avatar_url'] as String)
                          : null,
                      child: (activity['avatar_url'] as String?) == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$sportIcon $sportLabel · ${_formatTime(activity['start_time'])}',
                            style: TextStyle(
                              color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
              const SizedBox(height: 12),

              // Description
              if (activity['description'] != null) ...[
                Text(activity['description'],
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
              ],

              // Stats
              Row(
                children: [
                  _statBadge(distanceStr),
                  const SizedBox(width: 12),
                  _statBadge(durationStr),
                  if (activity['avg_pace_s_per_km'] != null) ...[
                    const SizedBox(width: 12),
                    _statBadge(_formatPace(activity['avg_pace_s_per_km'] as int)),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Actions：仅点赞（评论功能未实现，暂不展示）
              Row(
                children: [
                  IconButton(
                    onPressed: onKudo,
                    icon: Icon(
                      hasKudo ? Icons.thumb_up : Icons.thumb_up_outlined,
                      size: 20,
                      color: hasKudo ? const Color(0xFF000000) : null,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Text('$kudoCount',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(int secondsPerKm) {
    final m = secondsPerKm ~/ 60;
    final s = secondsPerKm % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"/km";
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '';
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}月${dt.day}日';
  }
}
