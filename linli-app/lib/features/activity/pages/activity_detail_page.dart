import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/widgets/activity_map.dart';
import '../providers/activity_provider.dart';
import '../services/activity_stats.dart';

class ActivityDetailPage extends ConsumerWidget {
  final String activityId;

  const ActivityDetailPage({super.key, required this.activityId});

  /// 导出 GPX：下载 XML → 写临时文件 → 调系统分享。
  Future<void> _exportGpx(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在生成 GPX...')),
    );
    final xml = await ref
        .read(activityDetailProvider(activityId).notifier)
        .downloadGpx(activityId);
    if (xml == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('导出失败，请重试')),
      );
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/linli-$activityId.gpx');
      await file.writeAsString(xml);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '林立运动轨迹 $activityId',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('分享失败: $e')),
      );
    }
  }

  /// 删除活动：二次确认 → 云端+本地删除 → 刷新活跃日历 → 返回上一页。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除活动'),
        content: const Text('确定删除此活动？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(activityListProvider.notifier).deleteActivity(activityId);
    // 删除后刷新活跃日历（Profile 页的活动列表靠 onChanged 回调自动刷新）
    ref.read(activityStatsProvider.notifier).load();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('活动已删除')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(activityDetailProvider(activityId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '导出 GPX',
            // 详情加载完才允许导出
            onPressed: detail.activity == null
                ? null
                : () => _exportGpx(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除活动',
            // 详情加载完才允许删除
            onPressed: detail.activity == null
                ? null
                : () => _confirmDelete(context, ref),
          ),
        ],
      ),
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
    final movingTime = (a['moving_time_s'] as num?)?.toInt() ?? 0;
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

          // 轨迹地图（MapLibre + 自托管 pixelmap 底图）
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
          _DetailRow(label: '移动时间', value: _fmtDuration(movingTime)),
          _DetailRow(label: '累计下降', value: '${elevLoss.toStringAsFixed(0)} m'),
          _DetailRow(label: '消耗热量', value: '$calories kcal'),
          _DetailRow(
              label: '轨迹点数', value: '${detail.points.length}个'),
          const SizedBox(height: 16),
          // 导出提示（实际按钮在 AppBar）
          Center(
            child: Text(
              '点击右上角图标可导出 GPX 文件',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
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
