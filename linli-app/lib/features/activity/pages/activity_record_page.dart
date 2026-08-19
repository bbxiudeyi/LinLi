import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/db/local_db.dart';
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
      // 准备页 + 录制中 + 暂停 合并成一个连续视图（地图不销毁，无缝切换）
      RecordingState.ready ||
      RecordingState.recording ||
      RecordingState.paused =>
        _RecordSessionView(tracking: tracking, ref: ref),
      // 停止后：保存页
      RecordingState.stopped => _SaveView(tracking: tracking, ref: ref),
    };
  }
}

/// 运动类型选择页（idle 态）。选完运动后会请求权限+定位，期间显示加载遮罩。
class _SportSelection extends ConsumerStatefulWidget {
  const _SportSelection({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_SportSelection> createState() => _SportSelectionState();
}

class _SportSelectionState extends ConsumerState<_SportSelection> {
  bool _starting = false;

  Future<void> _onSelect(SportType sport) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await widget.ref.read(gpsTrackerProvider.notifier).selectSport(sport);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
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
                    onTap: _starting ? null : () => _onSelect(sport),
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
            // 加载遮罩：请求权限 / 拿首个定位期间显示
            if (_starting)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在定位...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 录制会话视图（ready / recording / paused 三态共用）。
///
/// 关键设计：地图 ActivityMap 用固定的 ValueKey，三态切换时
/// Widget 树保持同一个实例，地图不被销毁重建，实现"无缝衔接"。
/// 状态变化只影响底部按钮区（开始 ↔ 暂停/结束）和数据块是否显示。
class _RecordSessionView extends StatefulWidget {
  final TrackingState tracking;
  final WidgetRef ref;

  const _RecordSessionView({required this.tracking, required this.ref});

  @override
  State<_RecordSessionView> createState() => _RecordSessionViewState();
}

class _RecordSessionViewState extends State<_RecordSessionView> {
  bool _starting = false;

  bool get _isReady =>
      widget.tracking.state == RecordingState.ready;
  bool get _isPaused =>
      widget.tracking.state == RecordingState.paused;
  bool get _isActive =>
      widget.tracking.state == RecordingState.recording ||
      widget.tracking.state == RecordingState.paused;

  Future<void> _begin() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await widget.ref.read(gpsTrackerProvider.notifier).beginRecording();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stack 布局：地图占据整个 body（绝对固定，不受底部内容影响），
    // 顶部栏 + 数据块 + 按钮浮在地图上方。
    // 这是运动 App 的标准做法，地图区域在三态切换时绝不会变化。
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // ===== 地图：铺满整个 body，固定 key 三态共用同一实例 =====
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ActivityMap(
                  key: const ValueKey('session_map'),
                  points: widget.tracking.gpsPoints,
                  height: double.infinity, // 铺满 Stack
                  interactive: true,
                  fitBounds: false,
                  alwaysShowMap: true,
                  showLocationPuck: true,
                ),
              ),
            ),
            // ===== 顶部栏（浮在地图上）=====
            // 左上角：返回重选（仅准备态显示）；右上角：暂停标记
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_isReady)
                      IconButton(
                        onPressed: _starting
                            ? null
                            : () => widget.ref
                                .read(gpsTrackerProvider.notifier)
                                .reset(),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: '返回重选运动',
                      ),
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
            ),
            // ===== 底部区（浮在地图上）：数据块 + 按钮 =====
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 录制中/暂停：显示数据块（半透明背景，浮在地图上）
                  if (_isActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _DataBlock(
                            label: '距离',
                            value: widget.tracking.distanceDisplay,
                            unit: widget.tracking.distanceMeters >= 1000
                                ? 'km'
                                : 'm',
                          ),
                          _DataBlock(
                            label: '用时',
                            value: widget.tracking.durationDisplay,
                            unit: '',
                          ),
                          _DataBlock(
                            label: '配速',
                            value: widget.tracking.avgPaceDisplay,
                            unit: '/km',
                          ),
                          _DataBlock(
                            label: '爬升',
                            value:
                                widget.tracking.elevationGain.toStringAsFixed(0),
                            unit: 'm',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  // 按钮行：开始/暂停/继续 始终居中，录制态右侧加停止
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.large(
                          heroTag: 'toggle',
                          backgroundColor: const Color(0xFF000000),
                          onPressed: _isActive
                              ? () {
                                  final n = widget.ref
                                      .read(gpsTrackerProvider.notifier);
                                  if (_isPaused) {
                                    n.resume();
                                  } else {
                                    n.pause();
                                  }
                                }
                              : (_starting ? null : _begin),
                          tooltip: _isReady
                              ? '开始'
                              : (_isPaused ? '继续' : '暂停'),
                          child: _starting
                              ? const SizedBox(
                                  height: 28,
                                  width: 28,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 3),
                                )
                              : Icon(
                                  _isReady
                                      ? Icons.play_arrow
                                      : (_isPaused
                                          ? Icons.play_arrow
                                          : Icons.pause),
                                  color: Colors.white,
                                  size: 48,
                                ),
                        ),
                        if (_isActive) ...[
                          const SizedBox(width: 48),
                          FloatingActionButton.large(
                            heroTag: 'stop',
                            backgroundColor: Colors.red,
                            onPressed: () => widget.ref
                                .read(gpsTrackerProvider.notifier)
                                .stop(),
                            tooltip: '结束',
                            child: const Icon(Icons.stop,
                                color: Colors.white, size: 40),
                          ),
                        ],
                      ],
                    ),
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
  bool _isPrivate = true; // P0-3：默认私密，用户显式选择才公开
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(); // 不预填，用户自己输入
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final summary =
        await widget.ref.read(gpsTrackerProvider.notifier).buildSummary();
    if (summary == null) {
      // 点数不足（< 2）或无开始时间：删除录制时建的空壳活动行 + 点，
      // 避免它作为"未同步"僵尸活动留在列表里。
      final localId = widget.tracking.localActivityId;
      if (localId != null) {
        await LocalDb.instance.deleteActivity(localId);
      }
      widget.ref.read(gpsTrackerProvider.notifier).reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('轨迹太短，无法保存有效活动')),
        );
        context.go('/feed');
      }
      return;
    }

    // 把用户输入的活动名称填进 summary
    final title = _titleController.text.trim();
    final named = title.isEmpty ? summary : summary.copyWith(title: title);

    final id = await widget.ref
        .read(activityListProvider.notifier)
        .saveActivity(named, isPrivate: _isPrivate);

    widget.ref.read(gpsTrackerProvider.notifier).reset();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(id != null ? '活动已保存' : '活动已保存，待网络恢复后同步'),
      ),
    );
    context.go('/profile');
  }

  /// 放弃本次录制（P0-2）：只有本地数据真正删掉才算成功。
  /// 删除失败时不清内存、不离开保存页，明确提示稍后重试。
  Future<void> _discard() async {
    final ok =
        await widget.ref.read(gpsTrackerProvider.notifier).discard();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已放弃本次录制')),
      );
      // tracker 已 reset 回 idle，录制页自动回到运动选择视图（安全页）
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能丢弃，请稍后重试')),
      );
    }
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
            // 活动名称输入框（地图上方，不预填，可空）
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '活动名称',
                hintText: '给这次活动起个名字（可选）',
                prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
            const SizedBox(height: 24),
            // 可见范围（P0-3）：默认私密；公开会向已登录用户暴露完整精确轨迹
            SwitchListTile(
              value: !_isPrivate,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _isPrivate = !v),
              title: const Text('公开本次活动'),
              subtitle: Text(
                _isPrivate ? '仅自己可见（推荐）' : '关注你的人可在动态流看到轨迹',
              ),
              contentPadding: EdgeInsets.zero,
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
    // 白色阴影：数据直接显示在地图上时保证可读性
    const shadow = Shadow(
      color: Colors.white70,
      blurRadius: 4,
      offset: Offset(1, 1),
    );
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  shadows: [shadow])),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      shadows: [shadow])),
              if (unit.isNotEmpty)
                Text(unit,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        shadows: [shadow])),
            ],
          ),
        ],
      ),
    );
  }
}
