import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/activity_map.dart';
import '../models/activity_models.dart';
import '../services/gps_tracker.dart';
import '../providers/activity_provider.dart';

class ActivityRecordPage extends ConsumerWidget {
  const ActivityRecordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(gpsTrackerProvider);

    return switch (tracking.state) {
      // 选运动类型
      RecordingState.idle => _SportSelection(ref: ref),
      // 选完运动，待开始
      RecordingState.ready => _ReadyView(tracking: tracking, ref: ref),
      // 录制中 和 暂停 共用同一视图（地图不消失，只换底部按钮）
      RecordingState.recording ||
      RecordingState.paused =>
        _ActiveView(tracking: tracking, ref: ref),
      // 停止后：保存页
      RecordingState.stopped => _SaveView(tracking: tracking, ref: ref),
    };
  }
}

/// 运动类型选择页（idle 态）。
class _SportSelection extends ConsumerWidget {
  const _SportSelection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = SportType.values;

    return Scaffold(
      body: SafeArea(
        child: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(24),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: sports.map((sport) {
            return Card(
              child: InkWell(
                onTap: () =>
                    ref.read(gpsTrackerProvider.notifier).selectSport(sport),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(sport.icon, style: const TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text(
                      sport.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 准备页（ready 态）：选完运动类型、未开始录制，显示"开始"按钮。
class _ReadyView extends StatefulWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _ReadyView({required this.tracking, required this.ref});

  @override
  State<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends State<_ReadyView> {
  bool _starting = false;

  Future<void> _begin() async {
    if (_starting) return;
    setState(() => _starting = true);
    await widget.ref.read(gpsTrackerProvider.notifier).beginRecording();
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final sport = widget.tracking.sportType;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(sport.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(sport.label,
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _starting
                        ? null
                        : () => widget.ref
                            .read(gpsTrackerProvider.notifier)
                            .reset(),
                    child: const Text('换一个'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(sport.icon, style: const TextStyle(fontSize: 96)),
            const SizedBox(height: 16),
            Text('准备好了吗？',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('点击开始后开始记录你的${sport.label}',
                style: TextStyle(color: Colors.grey[600])),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: FloatingActionButton.large(
                backgroundColor: const Color(0xFFFF6B35),
                onPressed: _starting ? null : _begin,
                child: _starting
                    ? const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3),
                      )
                    : const Icon(Icons.play_arrow,
                        color: Colors.white, size: 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 录制中 + 暂停 共用视图（地图始终显示，只切底部按钮）。
/// paused 态时不隐藏地图，只把"暂停"按钮换成"继续"按钮。
class _ActiveView extends StatelessWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _ActiveView({required this.tracking, required this.ref});

  bool get _isPaused => tracking.state == RecordingState.paused;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(tracking.sportType.icon,
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(tracking.sportType.label,
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (_isPaused)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('已暂停',
                          style: TextStyle(
                              color: Colors.blueGrey.shade700,
                              fontSize: 12)),
                    ),
                ],
              ),
            ),
            // 地图（录制中和暂停都显示，不隐藏）
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ActivityMap(
                  points: tracking.gpsPoints,
                  interactive: false,
                  fitBounds: false,
                  alwaysShowMap: true,
                  showLocationPuck: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _DataBlock(
                    label: '距离',
                    value: tracking.distanceDisplay,
                    unit: tracking.distanceMeters >= 1000 ? 'km' : 'm',
                  ),
                  _DataBlock(
                    label: '用时',
                    value: tracking.durationDisplay,
                    unit: '',
                  ),
                  _DataBlock(
                    label: '配速',
                    value: tracking.avgPaceDisplay,
                    unit: '/km',
                  ),
                  _DataBlock(
                    label: '爬升',
                    value: tracking.elevationGain.toStringAsFixed(0),
                    unit: 'm',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 底部按钮：暂停↔继续 切换，结束按钮常驻
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton.large(
                    heroTag: 'toggle',
                    backgroundColor:
                        _isPaused ? const Color(0xFFFF6B35) : Colors.blueGrey,
                    onPressed: () {
                      final n = ref.read(gpsTrackerProvider.notifier);
                      if (_isPaused) {
                        n.resume();
                      } else {
                        n.pause();
                      }
                    },
                    tooltip: _isPaused ? '继续' : '暂停',
                    child: Icon(
                      _isPaused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  FloatingActionButton.large(
                    heroTag: 'stop',
                    backgroundColor: Colors.red,
                    onPressed: () =>
                        ref.read(gpsTrackerProvider.notifier).stop(),
                    tooltip: '结束',
                    child:
                        const Icon(Icons.stop, color: Colors.white, size: 40),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 保存页（stopped 态）：显示统计 + 轨迹概览 + 保存/放弃。
class _SaveView extends StatefulWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _SaveView({required this.tracking, required this.ref});

  @override
  State<_SaveView> createState() => _SaveViewState();
}

class _SaveViewState extends State<_SaveView> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final summary =
        await widget.ref.read(gpsTrackerProvider.notifier).buildSummary();
    if (summary == null) {
      widget.ref.read(gpsTrackerProvider.notifier).reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有录制到有效轨迹')),
        );
        context.go('/feed');
      }
      return;
    }

    final id = await widget.ref
        .read(activityListProvider.notifier)
        .saveActivity(summary);

    widget.ref.read(gpsTrackerProvider.notifier).reset();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(id != null ? '活动已保存' : '活动已保存，待网络恢复后同步'),
      ),
    );
    context.go('/profile');
  }

  void _discard() {
    widget.ref.read(gpsTrackerProvider.notifier).discard();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracking;
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存活动'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(t.sportType.icon, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 8),
                Text(t.sportType.label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ActivityMap(
                points: t.gpsPoints,
                height: 200,
                interactive: false,
                fitBounds: true,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _DataBlock(
                  label: '距离',
                  value: t.distanceDisplay,
                  unit: t.distanceMeters >= 1000 ? 'km' : 'm',
                ),
                _DataBlock(
                  label: '用时',
                  value: t.durationDisplay,
                  unit: '',
                ),
                _DataBlock(
                  label: '配速',
                  value: t.avgPaceDisplay,
                  unit: '/km',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _DataBlock(
                  label: '移动时间',
                  value: _fmtDuration(t.movingTimeSeconds),
                  unit: '',
                ),
                _DataBlock(
                  label: '爬升',
                  value: t.elevationGain.toStringAsFixed(0),
                  unit: 'm',
                ),
                _DataBlock(
                  label: '最高速度',
                  value: t.maxSpeedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? '保存中...' : '保存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _saving ? null : _discard,
              child: const Text('放弃本次活动',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
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
}

class _DataBlock extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _DataBlock({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ],
      ),
    );
  }
}
