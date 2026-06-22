import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/activity_map.dart';
import '../providers/activity_provider.dart';

class ActivityDetailPage extends ConsumerWidget {
  final String activityId;

  const ActivityDetailPage({super.key, required this.activityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(activityDetailProvider(activityId));

    return Scaffold(
      appBar: AppBar(),
      body: detail.loading
          ? const Center(child: CircularProgressIndicator())
          : detail.activity == null
              ? const Center(child: Text('活动不存在'))
              : _buildContent(context, detail),
    );
  }

  Widget _buildContent(BuildContext context, ActivityDetailState detail) {
    final a = detail.activity!;
    final distance = (a['distance_m'] as num?)?.toInt() ?? 0;
    final duration = (a['duration_s'] as num?)?.toInt() ?? 0;
    final avgPace = (a['avg_pace_s_per_km'] as num?)?.toInt() ?? 0;
    final elevGain = (a['elevation_gain_m'] as num?)?.toDouble() ?? 0;
    final elevLoss = (a['elevation_loss_m'] as num?)?.toDouble() ?? 0;
    final avgSpeed = (a['avg_speed_kmh'] as num?)?.toDouble() ?? 0;
    final maxSpeed = (a['max_speed_kmh'] as num?)?.toDouble() ?? 0;
    final calories = (a['calories'] as num?)?.toInt() ?? 0;
    final type = a['type'] as String? ?? 'run';

    final sportLabel = const {
      'run': '跑步',
      'ride': '骑行',
      'hike': '徒步',
      'walk': '走路',
    }[type] ?? type;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 运动类型标题
          Text(sportLabel,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // 轨迹地图（真实 Mapbox 地图）
          ActivityMap(
            points: detail.points,
            height: 220,
            interactive: true,
            fitBounds: true,
          ),
          const SizedBox(height: 16),

          // 核心统计
          Row(
            children: [
              _StatItem(
                label: '距离',
                value: distance >= 1000
                    ? (distance / 1000).toStringAsFixed(2)
                    : '$distance',
                unit: distance >= 1000 ? 'km' : 'm',
              ),
              _StatItem(label: '用时', value: _fmtDuration(duration), unit: ''),
              _StatItem(label: '配速', value: _fmtPace(avgPace), unit: '/km'),
              _StatItem(
                  label: '爬升',
                  value: elevGain.toStringAsFixed(0),
                  unit: 'm'),
            ],
          ),
          const Divider(height: 32),

          // 详细数据
          const Text('详细数据',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _DetailRow(label: '平均速度', value: '${avgSpeed.toStringAsFixed(1)} km/h'),
          _DetailRow(label: '最高速度', value: '${maxSpeed.toStringAsFixed(1)} km/h'),
          _DetailRow(label: '累计下降', value: '${elevLoss.toStringAsFixed(0)} m'),
          _DetailRow(label: '消耗热量', value: '$calories kcal'),
          _DetailRow(
              label: '轨迹点数', value: '${detail.points.length}个'),
        ],
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtPace(int secondsPerKm) {
    if (secondsPerKm == 0) return '--:--';
    final m = secondsPerKm ~/ 60;
    final s = secondsPerKm % 60;
    return "$m'${s.toString().padLeft(2, '0')}";
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatItem(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              if (unit.isNotEmpty)
                Text(unit,
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
