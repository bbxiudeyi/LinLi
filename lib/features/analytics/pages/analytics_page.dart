import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Period selector
            SegmentedButton(
              segments: const [
                ButtonSegment(value: 'week', label: Text('本周')),
                ButtonSegment(value: 'month', label: Text('本月')),
                ButtonSegment(value: 'year', label: Text('今年')),
              ],
              selected: const {'month'},
              onSelectionChanged: (_) {},
            ),
            const SizedBox(height: 24),

            // Summary cards
            Row(
              children: [
                _SummaryCard(title: '距离', value: '0', unit: 'km'),
                const SizedBox(width: 8),
                _SummaryCard(title: '时间', value: '0', unit: 'h'),
                const SizedBox(width: 8),
                _SummaryCard(title: '次数', value: '0', unit: '次'),
                const SizedBox(width: 8),
                _SummaryCard(title: '爬升', value: '0', unit: 'm'),
              ],
            ),
            const SizedBox(height: 24),

            // Placeholder charts
            const Text('运动趋势',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('趋势图表 (fl_chart)')),
            ),
            const SizedBox(height: 24),

            // Personal records
            const Text('个人记录',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _RecordItem(title: '最快 1km', value: '--:--'),
            _RecordItem(title: '最快 5km', value: '--:--'),
            _RecordItem(title: '最快 10km', value: '--:--'),
            _RecordItem(title: '最快半马', value: '--:--'),
            _RecordItem(title: '最快全马', value: '--:--'),
            _RecordItem(title: '最远距离', value: '-- km'),
          ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(title,
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
                  Text(unit,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final String title;
  final String value;

  const _RecordItem({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
