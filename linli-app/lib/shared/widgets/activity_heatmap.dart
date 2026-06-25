import 'package:flutter/material.dart';
import '../../features/activity/services/activity_stats.dart';

/// GitHub 风格的活跃日历热力图（最近一年），带坐标轴。
///
/// 布局：
///   左侧纵轴（Mon/Wed/Fri） | 网格 7行×N周
///                           | 底部横轴（月份 Jan/Feb...）
class ActivityHeatmap extends StatefulWidget {
  final List<DailyStat> stats;
  const ActivityHeatmap({super.key, required this.stats});

  static const cellSize = 12.0;
  static const cellGap = 3.0;
  static const axisWidth = 28.0; // 左侧纵轴宽度
  static const axisHeight = 16.0; // 底部横轴高度

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 首帧渲染后滚动到最右（最近的活动在右端，打开即可见，无需手动滑）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  static const _cellSize = ActivityHeatmap.cellSize;
  static const _cellGap = ActivityHeatmap.cellGap;
  static const _axisWidth = ActivityHeatmap.axisWidth;
  static const _axisHeight = ActivityHeatmap.axisHeight;

  @override
  Widget build(BuildContext context) {
    final map = <String, int>{};
    for (final s in widget.stats) {
      final key = _dateKey(s.date);
      map[key] = (map[key] ?? 0) + s.count;
    }

    // GitHub 标准：固定 53 列（周）× 7 行（天）。
    // 最右一列是本周，往前推 52 周，覆盖完整一年。
    const weekCount = 53;
    final today = DateTime.now();
    // 本周的周一（最右列起点）
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    // 第一列的周一 = 往前推 52 周
    final startMonday = thisMonday.subtract(const Duration(days: 52 * 7));
    final maxCount = map.values.fold(0, (a, b) => a > b ? a : b);

    final gridWidth = weekCount * (_cellSize + _cellGap);
    final gridHeight = 7 * (_cellSize + _cellGap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: gridHeight + _axisHeight,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _axisWidth + gridWidth,
              child: Column(
                children: [
                  // 网格行：纵轴 + 网格
                  SizedBox(
                    height: gridHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 纵轴：Mon(1) Wed(3) Fri(5)
                        SizedBox(
                          width: _axisWidth,
                          height: gridHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _axisLabel('Mon'), // weekday 1
                              const SizedBox(),
                              _axisLabel('Wed'), // weekday 3
                              const SizedBox(),
                              _axisLabel('Fri'), // weekday 5
                              const SizedBox(),
                              const SizedBox(),
                            ],
                          ),
                        ),
                        // 网格
                        SizedBox(
                          width: gridWidth,
                          height: gridHeight,
                          child: GridView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: _cellGap,
                              crossAxisSpacing: _cellGap,
                              mainAxisExtent: _cellSize,
                              childAspectRatio: 1,
                            ),
                            itemCount: weekCount * 7,
                            itemBuilder: (context, index) {
                              final week = index ~/ 7;
                              final day = index % 7;
                              final date = startMonday
                                  .add(Duration(days: week * 7 + day));
                              if (date.isAfter(today)) {
                                return const SizedBox.shrink();
                              }
                              final count = map[_dateKey(date)] ?? 0;
                              return Tooltip(
                                message:
                                    '${_dateKey(date)}: $count 个活动',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _colorForCount(count, maxCount),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 横轴：月份
                  SizedBox(
                    height: _axisHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: _axisWidth),
                        Expanded(
                          child: _MonthAxis(
                            startMonday: startMonday,
                            weekCount: weekCount,
                            cellSize: _cellSize,
                            cellGap: _cellGap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 图例
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('少',
                style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            const SizedBox(width: 4),
            ...List.generate(
              5,
              (i) => Container(
                width: _cellSize,
                height: _cellSize,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: _colorForLevel(i),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('多',
                style: TextStyle(color: Colors.grey[500], fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _axisLabel(String text) {
    return Text(text,
        style: TextStyle(color: Colors.grey[500], fontSize: 9));
  }

  Color _colorForCount(int count, int maxCount) {
    if (count == 0) return const Color(0xFFEBEDF0);
    final ratio = maxCount > 0 ? count / maxCount : 0.0;
    int level;
    if (ratio <= 0.25) {
      level = 1;
    } else if (ratio <= 0.5) {
      level = 2;
    } else if (ratio <= 0.75) {
      level = 3;
    } else {
      level = 4;
    }
    return _colorForLevel(level);
  }

  Color _colorForLevel(int level) {
    switch (level) {
      case 0:
        return const Color(0xFFEBEDF0); // 无活动：灰
      case 1:
        return const Color(0xFFFFC4A3); // ≥1个：明显浅橙（保证有活动就看得到）
      case 2:
        return const Color(0xFFFF9D63); // 中橙
      case 3:
        return Color.fromARGB(255, 255, 130, 50); // 深橙
      case 4:
        return const Color(0xFFFF6B35); // 最深橙（活动密集）
      default:
        return const Color(0xFFEBEDF0);
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 横轴月份标签（Jan/Feb...）。
class _MonthAxis extends StatelessWidget {
  final DateTime startMonday;
  final int weekCount;
  final double cellSize;
  final double cellGap;

  const _MonthAxis({
    required this.startMonday,
    required this.weekCount,
    required this.cellSize,
    required this.cellGap,
  });

  @override
  Widget build(BuildContext context) {
    // 在每个月第一周的位置放一个月标签
    final monthPositions = <int, String>{};
    var lastMonth = -1;
    for (var w = 0; w < weekCount; w++) {
      final date = startMonday.add(Duration(days: w * 7));
      if (date.month != lastMonth && date.day <= 7) {
        monthPositions[w] = _monthShort(date.month);
        lastMonth = date.month;
      }
    }

    return SizedBox(
      height: 16,
      child: Stack(
        children: monthPositions.entries.map((e) {
          final x = e.key * (cellSize + cellGap);
          return Positioned(
            left: x,
            top: 0,
            child: Text(e.value,
                style: TextStyle(color: Colors.grey[500], fontSize: 9)),
          );
        }).toList(),
      ),
    );
  }

  String _monthShort(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[m - 1];
  }
}
