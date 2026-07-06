import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';

/// 用户搜索页：按昵称搜索，结果带"关注/已关注"按钮。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false; // 是否已发起过搜索（区分初始空态）

  Future<void> _doSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final res = await ApiClient.instance.dio
          .get('/users/search', queryParameters: {'q': query, 'limit': 20});
      final data = (res.data as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _results = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    final isFollowing = (user['is_following'] as bool?) ?? false;
    try {
      if (isFollowing) {
        await ApiClient.instance.dio.delete('/users/$id/follow');
      } else {
        await ApiClient.instance.dio.post('/users/$id/follow');
      }
      setState(() {
        user['is_following'] = !isFollowing;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索好友')),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              decoration: InputDecoration(
                hintText: '输入昵称搜索',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          // 结果列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searched ? '没有找到匹配的用户' : '输入昵称开始搜索',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          return _UserRow(
                            user: user,
                            onTap: () => context.push('/user/${user['id']}'),
                            onFollow: () => _toggleFollow(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onTap;
  final VoidCallback onFollow;

  const _UserRow({required this.user, required this.onTap, required this.onFollow});

  @override
  Widget build(BuildContext context) {
    final nickname = (user['nickname'] as String?) ?? '未知';
    final avatar = user['avatar_url'] as String?;
    final bio = user['bio'] as String?;
    final isFollowing = (user['is_following'] as bool?) ?? false;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
        child: avatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(nickname),
      subtitle: bio != null && bio.isNotEmpty ? Text(bio, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: TextButton(
        onPressed: onFollow,
        child: Text(isFollowing ? '已关注' : '关注'),
      ),
    );
  }
}
