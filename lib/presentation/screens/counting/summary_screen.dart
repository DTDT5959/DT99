import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/flower_count_repository.dart';
import '../../screens/farms/farm_detail_screen.dart';
import '../statistics/statistics_screen.dart';

class SummaryScreen extends StatefulWidget {
  final String farmId;
  final String farmName;
  final DateTime date;
  const SummaryScreen({super.key, required this.farmId, required this.farmName, required this.date});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _repo = FlowerCountRepository();
  Map<String, int>? _totals;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final totals = await _repo.totalsByColor(widget.farmId, from: widget.date, to: widget.date);
    if (mounted) setState(() => _totals = totals);
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    final grand = totals == null ? 0 : totals.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Session Complete')),
      body: totals == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const Icon(Icons.celebration, size: 64, color: Colors.amber),
                  const SizedBox(height: 16),
                  Text('Congratulations!', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Flower counting complete for ${DateFormat.yMMMMd().format(widget.date)}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _SummaryRow(label: 'Yellow', value: totals['yellow'] ?? 0, color: PostColor.yellow.swatch),
                          const Divider(),
                          _SummaryRow(label: 'Red', value: totals['red'] ?? 0, color: PostColor.red.swatch),
                          const Divider(),
                          _SummaryRow(label: 'White', value: totals['white'] ?? 0, color: Colors.grey),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                              Text('$grand Flowers',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: widget.farmId)),
                      (route) => route.isFirst,
                    ),
                    child: const Text('Return to Farm'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StatisticsScreen(farmId: widget.farmId, farmName: widget.farmName),
                      ),
                    ),
                    child: const Text('View Statistics'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SummaryRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 16)),
            ],
          ),
          Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
