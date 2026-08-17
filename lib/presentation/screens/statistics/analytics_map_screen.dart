import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/fruit_calculation_service.dart';
import '../../../data/repositories/post_repository.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/analytics_tree_detail_sheet.dart';
import '../../widgets/farm_canvas.dart';
import '../../widgets/camera_controller.dart';

/// Statistics → Select Farm → Analytics Map.
///
/// Reuses the existing FarmCanvas (same positions, same rendering) in a
/// fully read-only mode: no add/move/delete/drag, tapping a tree opens the
/// detail sheet instead of the count entry sheet. Every number on screen —
/// tree labels, farm summary, tree states — comes from AnalyticsProvider,
/// which recalculates via AnalyticsService whenever a filter changes.
/// Nothing here aggregates data itself.
class AnalyticsMapScreen extends StatelessWidget {
  final String farmId;
  final String farmName;
  const AnalyticsMapScreen({super.key, required this.farmId, required this.farmName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AnalyticsProvider(farmId)..load(),
      child: _AnalyticsMapBody(farmName: farmName),
    );
  }
}

class _AnalyticsMapBody extends StatefulWidget {
  final String farmName;
  const _AnalyticsMapBody({required this.farmName});

  @override
  State<_AnalyticsMapBody> createState() => _AnalyticsMapBodyState();
}

class _AnalyticsMapBodyState extends State<_AnalyticsMapBody> {
  final _cameraController = CameraController();
  bool _filterBarExpanded = true;
  bool _fullScreen = false;
  String? _highlightedPostId;

  @override
  void dispose() {
   _cameraController.dispose();
    super.dispose();
  }

  Future<void> _searchPostId(BuildContext context, AnalyticsProvider provider) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search Tree ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. A-14'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Find')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    final match = provider.posts.where((p) => p.postCode.toLowerCase() == result.trim().toLowerCase());
    if (match.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No tree "$result" found')));
      }
      return;
    }
    final post = match.first;
    setState(() => _highlightedPostId = post.id);
    // Center the transform roughly on the found post so "zoom to" reads as
    // intentional rather than just an outline flash.
    _cameraController.centerOn(
  Offset(post.positionX, post.positionY),
  zoomLevel: 1.2,
);
  }

  Future<void> _openTreeDetail(BuildContext context, AnalyticsProvider provider, String postId) async {
    final analytics = provider.analyticsForPost(postId);
    if (analytics == null) return;
    final post = await PostRepository().getPost(postId);
    const fruitCalc = FruitCalculationService();
    final estimatedFruits = provider.seasonView == SeasonView.fruit
        ? fruitCalc.estimateFruits(analytics.filteredTotal, provider.fruitSetPercentage)
        : null;
    if (!context.mounted) return;
    await AnalyticsTreeDetailSheet.show(
      context,
      analytics: analytics,
      seasonView: provider.seasonView,
      notes: post?.notes,
      estimatedFruits: estimatedFruits,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fruitSetPercentage = context.watch<SettingsProvider>().fruitSetPercentage;

    return Scaffold(
      appBar: _fullScreen
          ? null
          : AppBar(
              title: Text('Analytics Map · ${widget.farmName}'),
              actions: [
                Consumer<AnalyticsProvider>(
                  builder: (context, provider, _) => IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _searchPostId(context, provider),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Full Screen Mode',
                  onPressed: () => setState(() => _fullScreen = true),
                ),
              ],
            ),
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, _) {
          if (provider.loading && provider.posts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          // Keep the provider's fruit% in sync with the global setting so
          // Fruit View estimates match Settings without a second control.
          if (provider.fruitSetPercentage != fruitSetPercentage) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.setFruitSetPercentage(fruitSetPercentage);
            });
          }

          return Stack(
            children: [
              Column(
                children: [
                  if (!_fullScreen) _FilterBar(expanded: _filterBarExpanded, onToggle: () {
                    setState(() => _filterBarExpanded = !_filterBarExpanded);
                  }),
                  if (!_fullScreen) _StatsHeader(analytics: provider.farmAnalytics, seasonView: provider.seasonView),
                  if (!_fullScreen) _LegendBar(),
                  Expanded(
                    child: FarmCanvas(
                      camera: _cameraController,
                      posts: provider.posts,
                      selectedPostId: _highlightedPostId,
                      seasonView: provider.seasonView,
                      fruitSetPercentage: provider.fruitSetPercentage,
                      flowerCounts: {for (final t in provider.treeAnalytics) t.postId: t.filteredTotal},
                      onPostTap: (post) => _openTreeDetail(context, provider, post.id),
                    ),
                  ),
                ],
              ),
              if (_fullScreen)
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: FloatingActionButton.small(
                      onPressed: () => setState(() => _fullScreen = false),
                      child: const Icon(Icons.fullscreen_exit),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}


class _FilterBar extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _FilterBar({required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnalyticsProvider>();
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Text('Filters', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  const Spacer(),
                  Text(_summaryFor(provider), style: TextStyle(fontSize: 12, color: Colors.white)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: QuickFilter.values.map((f) {
                      return ChoiceChip(
                        label: Text(f.label),
                        selected: provider.activeQuickFilter == f,
                        onSelected: (_) async {
                          if (f == QuickFilter.customRange) {
                            await _pickRange(context, provider);
                          } else if (f == QuickFilter.untilToday) {
                            await _pickUntilTodayStart(context, provider);
                          } else {
                            provider.applyQuickFilter(f);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  _DateModeRow(provider: provider),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('View:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      SegmentedButton<SeasonView>(
                        segments: [
                          const ButtonSegment(value: SeasonView.flower, label: Text('🌸 Flower')),
                          ButtonSegment(
                            value: SeasonView.fruit,
                            label: const Text('🍎 Fruit'),
                            enabled: provider.fruitViewAvailableForFilter,
                          ),
                        ],
                        selected: {provider.seasonView},
                        onSelectionChanged: (set) => provider.setSeasonView(set.first),
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _summaryFor(AnalyticsProvider p) {
    switch (p.dateMode) {
      case DateFilterMode.single:
        return DateFormat.yMMMd().format(p.singleDate);
      case DateFilterMode.range:
        return '${DateFormat.MMMd().format(p.startDate)} – ${DateFormat.MMMd().format(p.endDate)}';
      case DateFilterMode.untilToday:
        return '${DateFormat.MMMd().format(p.startDate)} – Today';
    }
  }

  Future<void> _pickRange(BuildContext context, AnalyticsProvider provider) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: provider.startDate, end: provider.endDate),
    );
    if (range == null) return;
    provider.setRange(range.start, range.end);
  }

  Future<void> _pickUntilTodayStart(BuildContext context, AnalyticsProvider provider) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    provider.setUntilToday(picked);
  }
}

class _DateModeRow extends StatelessWidget {
  final AnalyticsProvider provider;
  const _DateModeRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Date:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_label(), overflow: TextOverflow.ellipsis),
            onPressed: () => _openPicker(context),
          ),
        ),
      ],
    );
  }

  String _label() {
    switch (provider.dateMode) {
      case DateFilterMode.single:
        return DateFormat.yMMMMd().format(provider.singleDate);
      case DateFilterMode.range:
        return '${DateFormat.yMMMd().format(provider.startDate)} → ${DateFormat.yMMMd().format(provider.endDate)}';
      case DateFilterMode.untilToday:
        return '${DateFormat.yMMMd().format(provider.startDate)} → Today';
    }
  }

  Future<void> _openPicker(BuildContext context) async {
    if (provider.dateMode == DateFilterMode.single) {
      final picked = await showDatePicker(
        context: context,
        initialDate: provider.singleDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked != null) provider.setSingleDate(picked);
    } else {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: provider.startDate, end: provider.endDate),
      );
      if (range != null) provider.setRange(range.start, range.end);
    }
  }
}

class _StatsHeader extends StatelessWidget {
  final FarmAnalytics analytics;
  final SeasonView seasonView;
  const _StatsHeader({required this.analytics, required this.seasonView});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Farm Summary', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Builder(builder: (context) {
              final highest = analytics.highestProducing;
              final lowest = analytics.lowestProducing;
              return Row(
                children: [
                  _StatCard(label: 'Total Flowers', value: '${analytics.totalFlowers}'),
                  _StatCard(label: 'Avg / Tree', value: analytics.averagePerTree.toStringAsFixed(1)),
                  _StatCard(label: 'Flowering Trees', value: '${analytics.treesWithFlowers}'),
                  _StatCard(label: 'Empty Trees', value: '${analytics.treesWithoutFlowers}'),
                  _StatCard(label: '% With Flowers', value: '${analytics.percentTreesWithFlowers.toStringAsFixed(0)}%'),
                  _StatCard(
                    label: 'Highest',
                    value: highest == null ? '—' : '${highest.postCode} (${highest.filteredTotal})',
                  ),
                  _StatCard(
                    label: 'Lowest',
                    value: lowest == null ? '—' : '${lowest.postCode} (${lowest.filteredTotal})',
                  ),
                  _StatCard(label: 'Yellow', value: '${analytics.totalsByColor[PostColor.yellow] ?? 0}', color: PostColor.yellow.swatch),
                  _StatCard(label: 'White', value: '${analytics.totalsByColor[PostColor.white] ?? 0}', color: Colors.grey),
                  _StatCard(label: 'Red', value: '${analytics.totalsByColor[PostColor.red] ?? 0}', color: PostColor.red.swatch),
                  if (seasonView == SeasonView.fruit)
                    _StatCard(label: 'Est. Fruits', value: '${analytics.estimatedFruits}', highlight: true),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool highlight;
  const _StatCard({required this.label, required this.value, this.color, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(12),
        //here 
        border: Border.all(color: Colors.black),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: Row(
              key: ValueKey(value),
              children: [
                if (color != null) ...[
                  Icon(Icons.circle, size: 8, color: color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15,color: Colors.black),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.black)),
        ],
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _LegendDot(color: PostColor.yellow.swatch, label: 'Yellow'),
          const SizedBox(width: 12),
          _LegendDot(color: PostColor.red.swatch, label: 'Red'),
          const SizedBox(width: 12),
          _LegendDot(color: Colors.grey, label: 'White'),
          const Spacer(),
          // edited
          Text('Tap a tree for details', style: TextStyle(fontSize: 11, color: Colors.black)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11,color: Colors.black)),
      ],
    );
  }
}
