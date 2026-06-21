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
      RecordingState.idle => _SportSelection(ref: ref),
      RecordingState.recording =>
        _RecordingView(tracking: tracking, ref: ref),
      RecordingState.paused => _PausedView(tracking: tracking, ref: ref),
    };
  }
}

class _SportSelection extends StatefulWidget {
  final WidgetRef ref;

  const _SportSelection({required this.ref});

  @override
  State<_SportSelection> createState() => _SportSelectionState();
}

class _SportSelectionState extends State<_SportSelection> {
  bool _locating = false;

  Future<void> _start(SportType sport) async {
    if (_locating) return;
    setState(() => _locating = true);
    widget.ref.read(gpsTrackerProvider.notifier).selectSport(sport);
    await widget.ref.read(gpsTrackerProvider.notifier).start();
    // start() 完成后 state 已切到 recording，页面会自动 rebuild 到录制视图
    if (mounted) setState(() => _locating = false);
  }

  @override
  Widget build(BuildContext context) {
    final sports = SportType.values;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(24),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: sports.map((sport) {
                return Card(
                  child: InkWell(
                    onTap: _locating ? null : () => _start(sport),
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
          // 定位中遮罩：点击后等待期间显示 loading，避免误操作
          if (_locating)
            Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _RecordingView extends StatelessWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _RecordingView({required this.tracking, required this.ref});

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
                  IconButton(
                    onPressed: () =>
                        ref.read(gpsTrackerProvider.notifier).pause(),
                    icon: const Icon(Icons.pause_circle, size: 36),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // 录制中：地图始终显示（哪怕还没轨迹点），跟随真实 GPS 画轨迹
                child: ActivityMap(
                  points: tracking.gpsPoints,
                  interactive: false, // 录制中禁用拖拽，避免误操作
                  fitBounds: false,   // 跟随当前点，不全览
                  alwaysShowMap: true, // 关键：录制页强制显示地图底图
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
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: FloatingActionButton.large(
                backgroundColor: Colors.red,
                onPressed: () => _finish(context),
                child:
                    const Icon(Icons.stop, color: Colors.white, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _finish(BuildContext context) async {
    ref.read(gpsTrackerProvider.notifier).stop();
    final summary =
        ref.read(gpsTrackerProvider.notifier).buildSummary();
    if (summary != null) {
      final id = await ref
          .read(activityListProvider.notifier)
          .saveActivity(summary);
      ref.read(gpsTrackerProvider.notifier).reset();
      if (id != null && context.mounted) {
        context.go('/activity/$id');
      }
    }
  }
}

class _PausedView extends StatelessWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _PausedView({required this.tracking, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('已暂停',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 32),
            Row(
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
              ],
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.large(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    ref.read(gpsTrackerProvider.notifier).stop();
                    ref.read(gpsTrackerProvider.notifier).reset();
                  },
                  child: const Icon(Icons.stop, color: Colors.white),
                ),
                const SizedBox(width: 32),
                FloatingActionButton.large(
                  backgroundColor: const Color(0xFFFF6B35),
                  onPressed: () =>
                      ref.read(gpsTrackerProvider.notifier).resume(),
                  child:
                      const Icon(Icons.play_arrow, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
                      fontSize: 24, fontWeight: FontWeight.bold)),
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
