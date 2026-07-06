import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';

/// 消息通知页：列出关注通知等。进入页面后自动标记为已读。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.dio.get('/notifications');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _items = data);

      // 进入页面后，把所有未读标记为已读
      final unread = data.where((n) => n['read'] != true).toList();
      for (final n in unread) {
        final id = n['id'] as String?;
        if (id != null) {
          try {
            await ApiClient.instance.dio.post('/notifications/$id/read');
          } catch (_) {}
        }
      }
      // 本地刷新状态（不重新请求，避免闪烁）
      if (mounted && unread.isNotEmpty) {
        setState(() {
          for (final n in _items) {
            n['read'] = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载通知失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtTime(String? isoTime) {
    if (isoTime == null) return '';
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    final local = dt.toLocal();
    return '${local.month}-${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('消息通知')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 200),
                      Center(
                        child: Text('暂无通知',
                            style: TextStyle(color: Colors.grey[500])),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final n = _items[index];
                      final type = n['type'] as String? ?? 'follow';
                      final actorNickname =
                          n['actor_nickname'] as String? ?? '未知用户';
                      final actorAvatar = n['actor_avatar_url'] as String?;
                      final actorId = n['actor_id'] as String?;
                      final read = n['read'] as bool? ?? true;
                      final time = _fmtTime(n['created_at'] as String?);

                      String text;
                      switch (type) {
                        case 'follow':
                          text = '$actorNickname 关注了你';
                          break;
                        default:
                          text = '$actorNickname $type';
                      }

                      return ListTile(
                        onTap: actorId != null
                            ? () => context.push('/user/$actorId')
                            : null,
                        leading: CircleAvatar(
                          backgroundImage: actorAvatar != null
                              ? CachedNetworkImageProvider(actorAvatar)
                              : null,
                          child: actorAvatar == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(text),
                        subtitle: Text(time,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12)),
                        trailing: read
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      );
                    },
                  ),
      ),
    );
  }
}
