import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// 查看其他用户的公开资料页。
///
/// 通过路由 /user/:id 进入。从 Feed / 活动详情点别人头像跳转来。
/// 数据来源：后端 GET /users/:id（返回 PublicUserProfile，不含 email/体重）。
class UserProfilePage extends ConsumerStatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final res =
          await ApiClient.instance.dio.get('/users/${widget.userId}');
      if (mounted) {
        setState(() {
          _user = res.data as Map<String, dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final u = _user!;
    final nickname = u['nickname'] as String? ?? '未知用户';
    final bio = u['bio'] as String?;
    final avatarUrl = u['avatar_url'] as String?;
    final createdAt = u['created_at'] as String?;

    return SafeArea(
      child: Column(
        children: [
          // 头部：头像 + 昵称 + 简介
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage:
                      avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 56)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(nickname,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(bio,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600])),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '加入于 ${_formatDate(createdAt)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          // 关注按钮（后端 follow 接口已有）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: _follow,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('关注'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const Spacer(),
          // 提示：该用户的活动（后端暂无"按用户查活动"接口，占位）
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '该用户的活动动态即将上线',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _follow() async {
    try {
      await ApiClient.instance.dio.post('/users/${widget.userId}/follow');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已关注')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关注失败')),
        );
      }
    }
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.year}年${dt.month}月';
  }
}
