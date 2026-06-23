import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/feed_provider.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);

    return Scaffold(
      body: SafeArea(
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
    // 点赞数：后端返回 kudo_count，本地根据已赞状态即时增减
    final baseKudos = (activity['kudo_count'] as num?)?.toInt() ?? 0;
    final kudoCount = baseKudos + (hasKudo ? 1 : 0);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User row（扁平 nickname / avatar_url）
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: (activity['avatar_url'] as String?) != null
                        ? NetworkImage(activity['avatar_url'] as String)
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
                      color: hasKudo ? const Color(0xFFFF6B35) : null,
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
        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFFFF6B35),
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
