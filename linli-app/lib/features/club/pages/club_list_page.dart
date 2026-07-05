import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 俱乐部列表页（找向导）。
///
/// 当前为前端 UI 框架，使用占位数据。
/// 后端 clubs / guides 接口上线后，替换为真实数据加载。
class ClubListPage extends ConsumerWidget {
  const ClubListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('俱乐部')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 顶部说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF000000).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.explore, color: Color(0xFF000000)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '发现附近的运动俱乐部，寻找专业向导一起探索',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 占位俱乐部列表
            ..._placeholderClubs.map((c) => _ClubCard(club: c)),
          ],
        ),
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  final Map<String, dynamic> club;
  const _ClubCard({required this.club});

  @override
  Widget build(BuildContext context) {
    final guides = club['guides'] as int? ?? 0;
    final members = club['members'] as int? ?? 0;
    final sports = (club['sports'] as List?)?.cast<String>() ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('俱乐部详情即将上线')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF000000).withValues(alpha: 0.15),
                    child: Text(
                      (club['name'] as String?)?.substring(0, 1) ?? '?',
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          club['name'] as String? ?? '未命名俱乐部',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          club['location'] as String? ?? '',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // 向导数徽章
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$guides 位向导',
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 运动类型标签
              Wrap(
                spacing: 6,
                children: sports
                    .map((s) => Chip(
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.people_outline,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('$members 成员',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 占位俱乐部数据（后端接口上线后替换）。
const _placeholderClubs = [
  {
    'name': '山野徒步联盟',
    'location': '北京 · 海淀',
    'guides': 8,
    'members': 1240,
    'sports': ['徒步', '登山'],
  },
  {
    'name': '城市骑行团',
    'location': '上海 · 浦东',
    'guides': 5,
    'members': 860,
    'sports': ['骑行'],
  },
  {
    'name': '晨跑俱乐部',
    'location': '深圳 · 南山',
    'guides': 3,
    'members': 532,
    'sports': ['跑步'],
  },
  {
    'name': '户外探索者',
    'location': '成都 · 武侯',
    'guides': 12,
    'members': 2100,
    'sports': ['徒步', '登山', '骑行'],
  },
];
