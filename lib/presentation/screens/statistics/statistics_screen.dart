import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


import 'analytics_map_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farm.dart';
import '../../../data/repositories/farm_repository.dart';
import '../../../data/repositories/flower_count_repository.dart';
import '../../../data/repositories/post_repository.dart';

/// If [farmId] is null, this shows a farm picker (reached from the Home
/// screen's "Statistics" button); otherwise it shows the dashboard directly
/// for that farm (reached from a farm's own detail screen).
class StatisticsScreen extends StatefulWidget {
  final String? farmId;
  final String? farmName;
  const StatisticsScreen({super.key, this.farmId, this.farmName});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final _farmRepo = FarmRepository();
  final _countRepo = FlowerCountRepository();
  final _postRepo = PostRepository();

  List<Farm> _farms = [];
  String? _selectedFarmId;
  bool _loadingFarms = true;

  Map<String, int> _weekTotals = {};
  Map<String, int> _monthTotals = {};
  Map<String, int> _seasonTotals = {};
  Map<String, dynamic>? _highest;
  Map<String, dynamic>? _lowest;
  List<Map<String, dynamic>> _daily = [];
  int _postCount = 0;
  bool _loadingStats = false;

  @override
  void initState() {
    super.initState();
    _selectedFarmId = widget.farmId;
    _init();
  }

  Future<void> _init() async {
    final farms = await _farmRepo.getAllFarms();
    setState(() {
      _farms = farms;
      _loadingFarms = false;
      _selectedFarmId ??= farms.isNotEmpty ? farms.first.id : null;
    });
    if (_selectedFarmId != null) await _loadStats(_selectedFarmId!);
  }

  Future<void> _loadStats(String farmId) async {
    setState(() => _loadingStats = true);
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));
    final seasonAgo = now.subtract(const Duration(days: 120));

    final week = await _countRepo.totalsByColor(farmId, from: weekAgo, to: now);
    final month = await _countRepo.totalsByColor(farmId, from: monthAgo, to: now);
    final season = await _countRepo.totalsByColor(farmId, from: seasonAgo, to: now);
    final highest = await _countRepo.highestProducingPost(farmId);
    final lowest = await _countRepo.lowestProducingPost(farmId);
    final daily = await _countRepo.dailyTotals(farmId, days: 30);
    final posts = await _postRepo.getPostsForFarm(farmId);

    if (!mounted) return;
    setState(() {
      _weekTotals = week;
      _monthTotals = month;
      _seasonTotals = season;
      _highest = highest;
      _lowest = lowest;
      _daily = daily;
      _postCount = posts.length;
      _loadingStats = false;
    });
  }

  int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.farmName ?? 'Statistics')),
      body: _loadingFarms
          ? const Center(child: CircularProgressIndicator())
          : _farms.isEmpty
              ? Center(child: Text('Create a farm to see statistics', style: TextStyle(color: Colors.grey.shade600)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (widget.farmId == null) ...[
                      DropdownButtonFormField<String>(
                        value: _selectedFarmId,
                        decoration: const InputDecoration(labelText: 'Farm'),
                        items: _farms
                            .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          setState(() => _selectedFarmId = id);
                          _loadStats(id);
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

if (_selectedFarmId != null) ...[
  Card(
    child: ListTile(
      leading: const Icon(Icons.map),
      title: const Text('Analytics Map'),
      subtitle: const Text('See flower production on the farm layout'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnalyticsMapScreen(
            farmId: _selectedFarmId!,
            farmName: _farms.firstWhere((f) => f.id == _selectedFarmId).name,
          ),
        ),
      ),
    ),
  ),
  const SizedBox(height: 20),
],



                    if (_loadingStats)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(child: _StatCard(label: 'This Week', value: _sum(_weekTotals))),
                          const SizedBox(width: 12),
                          Expanded(child: _StatCard(label: 'This Month', value: _sum(_monthTotals))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _StatCard(label: 'This Season', value: _sum(_seasonTotals))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'Avg / Post',
                              value: _postCount == 0 ? 0 : (_sum(_seasonTotals) / _postCount).round(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoCard(
                              icon: Icons.trending_up,
                              title: 'Highest Producing',
                              value: _highest == null
                                  ? '—'
                                  : '${_highest!['post_code']} (${_highest!['total']})',
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoCard(
                              icon: Icons.trending_down,
                              title: 'Lowest Producing',
                              value: _lowest == null
                                  ? '—'
                                  : '${_lowest!['post_code']} (${_lowest!['total']})',
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Average By Color (Season)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _ColorAverageRow(color: PostColor.yellow, total: _seasonTotals['yellow'] ?? 0),
                              _ColorAverageRow(color: PostColor.red, total: _seasonTotals['red'] ?? 0),
                              _ColorAverageRow(color: PostColor.white, total: _seasonTotals['white'] ?? 0),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Daily Flowering (Last 30 Days)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
                          child: SizedBox(
                            height: 200,
                            child: _daily.isEmpty
                                ? Center(
                                    child: Text('No data yet', style: TextStyle(color: Colors.grey.shade600)))
                                : LineChart(_buildLineChartData()),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  LineChartData _buildLineChartData() {
    final spots = <FlSpot>[];
    for (var i = 0; i < _daily.length; i++) {
      spots.add(FlSpot(i.toDouble(), ((_daily[i]['total'] as int?) ?? 0).toDouble()));
    }
    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: const Color(0xFF2E7D32),
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: const Color(0x332E7D32)),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            //edited 
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  const _InfoCard({required this.icon, required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ColorAverageRow extends StatelessWidget {
  final PostColor color;
  final int total;
  const _ColorAverageRow({required this.color, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color.swatch),
          const SizedBox(width: 10),
          Text(color.label),
          const Spacer(),
          Text('$total', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
