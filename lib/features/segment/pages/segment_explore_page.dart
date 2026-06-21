import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/segment_provider.dart';

class SegmentExplorePage extends ConsumerWidget {
  const SegmentExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(segmentExploreProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Toggle map/list
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<SegmentViewMode>(
                segments: const [
                  ButtonSegment(value: SegmentViewMode.list, label: Text('列表'), icon: Icon(Icons.list)),
                  ButtonSegment(value: SegmentViewMode.map, label: Text('地图'), icon: Icon(Icons.map)),
                ],
                selected: {state.viewMode},
                onSelectionChanged: (mode) =>
                    ref.read(segmentExploreProvider.notifier).setViewMode(mode.first),
              ),
            ),

          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.segments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.route_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('附近暂无路段',
                                style: TextStyle(color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Text('创建你的第一个路段吧！',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.segments.length,
                        itemBuilder: (context, index) {
                          final segment = state.segments[index];
                          return _SegmentCard(segment: segment);
                        },
                      ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final Map<String, dynamic> segment;

  const _SegmentCard({required this.segment});

  @override
  Widget build(BuildContext context) {
    final distance = segment['distance_m'] as int? ?? 0;
    final distanceStr =
        distance >= 1000 ? '${(distance / 1000).toStringAsFixed(1)} km' : '$distance m';
    final grade = segment['avg_grade'] as num?;
    final climbCat = segment['climb_category'] as int? ?? 0;
    final sportType = segment['sport_type'] as String? ?? 'run';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sportType == 'ride' ? Icons.pedal_bike : Icons.directions_run,
                  size: 20,
                  color: const Color(0xFFFF6B35),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    segment['name'] ?? '未命名路段',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                if (grade != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _gradeColor(grade.toDouble()),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${grade.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _badge(distanceStr),
                const SizedBox(width: 8),
                _badge('爬坡等级 ${climbCat > 0 ? climbCat : "HC"}'),
                const SizedBox(width: 8),
                _badge('${segment['effort_count'] ?? 0} 次挑战'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  Color _gradeColor(double grade) {
    if (grade > 8) return Colors.purple;
    if (grade > 5) return Colors.red;
    if (grade > 3) return Colors.orange;
    return Colors.green;
  }
}
