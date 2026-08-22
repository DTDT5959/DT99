import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/fruit_calculation_service.dart';
import '../../../data/models/post.dart';
import '../../providers/counting_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/camera_controller.dart';
import '../../widgets/farm_canvas.dart';
import '../../widgets/flower_count_sheet.dart';
import '../history/post_history_screen.dart';
import 'summary_screen.dart';

/// "Fast Count Mode": tap a post → popup → enter number → save → popup
/// closes automatically → ready for the next post. No extra confirmations.
///
/// Also doubles as the Season View screen when reopened from History for a
/// past date: once a session is 40+ days old, a Flower/Fruit segmented
/// toggle appears and switching it redraws the map using
/// FruitCalculationService — counting itself (tapping a post to enter a
/// number) is only meaningful in Flower View, since Fruit View is a
/// read-only live estimate that's never stored.
class CountingScreen extends StatelessWidget {
  final String farmId;
  final String farmName;
  final DateTime date;
  const CountingScreen({super.key, required this.farmId, required this.farmName, required this.date});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CountingProvider(farmId: farmId, date: date)..load(),
      child: _CountingBody(farmName: farmName, date: date),
    );
  }
}

class _CountingBody extends StatefulWidget {
  final String farmName;
  final DateTime date;
  const _CountingBody({required this.farmName, required this.date});

  @override
  State<_CountingBody> createState() => _CountingBodyState();
}

class _CountingBodyState extends State<_CountingBody> {
  static const _calculator = FruitCalculationService();

  final _camera = CameraController();
  bool _navigatedToSummary = false;
  String? _highlightedPostId;
  PostColor? _colorFilter;
  bool? _countedFilter; // null = all, true = counted only, false = not counted only
  SeasonView _seasonView = SeasonView.flower;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  bool get _fruitViewUnlocked => _calculator.isFruitViewUnlocked(widget.date);

  Future<void> _searchPostId(BuildContext context) async {
    final provider = context.read<CountingProvider>();
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search Post ID'),
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
    final match = provider.posts.where(
      (p) => p.postCode.toLowerCase() == result.trim().toLowerCase(),
    );
    if (match.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No post "$result" found')));
      }
      return;
    }
    final post = match.first;
    setState(() => _highlightedPostId = post.id);
    _camera.centerOn(Offset(post.positionX, post.positionY));
  }

  Future<void> _finishCounting(BuildContext context) async {
    final provider = context.read<CountingProvider>();
    final remaining = provider.remainingUncounted;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every post is already counted for this date')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish Counting?'),
        content: Text(
          'You have $remaining ${remaining == 1 ? 'tree' : 'trees'} remaining.\n\n'
          'All uncounted trees will be recorded as 0 flowers for '
          '${DateFormat.yMMMMd().format(widget.date)}.\n\n'
          'This action will mark those trees as counted with 0 flowers.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finish Counting')),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.finishCounting();
    if (!context.mounted) return;

    if (provider.isComplete && !_navigatedToSummary) {
      _navigatedToSummary = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryScreen(
            farmId: provider.farmId,
            farmName: widget.farmName,
            date: widget.date,
          ),
        ),
      );
    }
  }

  Future<void> _showFilters(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter by Color', style: Theme.of(ctx).textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _colorFilter == null,
                      onSelected: (_) => setState(() => _colorFilter = null),
                    ),
                    for (final c in PostColor.values)
                      ChoiceChip(
                        label: Text(c.label),
                        selected: _colorFilter == c,
                        onSelected: (_) => setState(() => _colorFilter = c),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Filter by Status', style: Theme.of(ctx).textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _countedFilter == null,
                      onSelected: (_) => setState(() => _countedFilter = null),
                    ),
                    ChoiceChip(
                      label: const Text('Counted'),
                      selected: _countedFilter == true,
                      onSelected: (_) => setState(() => _countedFilter = true),
                    ),
                    ChoiceChip(
                      label: const Text('Not Counted'),
                      selected: _countedFilter == false,
                      onSelected: (_) => setState(() => _countedFilter = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    setState(() {});
  }

  Future<void> _handlePostTap(BuildContext context, Post post) async {
    // Fruit View is a read-only live estimate — counting only happens in
    // Flower View, where the underlying stored data actually lives.
    if (_seasonView == SeasonView.fruit) return;

    final provider = context.read<CountingProvider>();
    final existing = provider.counts[post.id];
    final value = await showFlowerCountSheet(
      context,
      postCode: post.postCode,
      color: post.color,
      initialValue: existing?.flowerCount,
    );
    if (value == null) return;
    await provider.saveCount(post.id, value);

    if (!context.mounted) return;
    if (provider.isComplete && !_navigatedToSummary) {
      _navigatedToSummary = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryScreen(
            farmId: provider.farmId,
            farmName: widget.farmName,
            date: widget.date,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fruitSetPercentage = context.watch<SettingsProvider>().fruitSetPercentage;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.farmName} · ${DateFormat.MMMd().format(widget.date)}'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _searchPostId(context)),
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () => _showFilters(context)),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Finish Counting',
            // Same rule as tapping a post: counting is only meaningful in
            // Flower View, where the underlying stored data lives.
            onPressed: _seasonView == SeasonView.fruit ? null : () => _finishCounting(context),
          ),
        ],
      ),
      body: Consumer<CountingProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.posts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This farm has no posts yet. Add posts in the layout editor first.'),
              ),
            );
          }
          final visiblePosts = provider.posts.where((p) {
            if (_colorFilter != null && p.color != _colorFilter) return false;
            if (_countedFilter != null && provider.isCounted(p.id) != _countedFilter) return false;
            return true;
          }).toList();
          final flowerCounts = {
            for (final e in provider.counts.entries) e.key: e.value.flowerCount,
          };
          return Column(
            children: [
              if (_fruitViewUnlocked) _SeasonViewToggle(
                view: _seasonView,
                onChanged: (v) => setState(() => _seasonView = v),
              ),
              _ProgressAndTotals(
                provider: provider,
                seasonView: _seasonView,
                fruitSetPercentage: fruitSetPercentage,
              ),
              Expanded(
                child: FarmCanvas(
                  camera: _camera,
                  posts: visiblePosts,
                  selectedPostId: _highlightedPostId,
                  flowerCounts: flowerCounts,
                  distinguishNotCounted: true,
                  drawings: provider.drawings,
                  seasonView: _seasonView,
                  fruitSetPercentage: fruitSetPercentage,
                  onPostTap: (post) => _handlePostTap(context, post),
                  onPostLongPress: (post) => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PostHistoryScreen(postId: post.id)),
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

class _SeasonViewToggle extends StatelessWidget {
  final SeasonView view;
  final ValueChanged<SeasonView> onChanged;
  const _SeasonViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Center(
        child: SegmentedButton<SeasonView>(
          segments: const [
            ButtonSegment(value: SeasonView.flower, label: Text('🌸 Flower View')),
            ButtonSegment(value: SeasonView.fruit, label: Text('🍎 Fruit View')),
          ],
          selected: {view},
          onSelectionChanged: (set) => onChanged(set.first),
        ),
      ),
    );
  }
}

class _ProgressAndTotals extends StatelessWidget {
  final CountingProvider provider;
  final SeasonView seasonView;
  final double fruitSetPercentage;
  const _ProgressAndTotals({
    required this.provider,
    required this.seasonView,
    required this.fruitSetPercentage,
  });

  static const _calculator = FruitCalculationService();

  int _totalFor(PostColor color) {
    final flowerTotal = provider.totalFor(color);
    if (seasonView == SeasonView.flower) return flowerTotal;
    return _calculator.estimateFruits(flowerTotal, fruitSetPercentage);
  }

  @override
  Widget build(BuildContext context) {
    final progress = provider.totalPosts == 0 ? 0.0 : provider.countedPosts / provider.totalPosts;
    final grand = seasonView == SeasonView.flower
        ? provider.grandTotal
        : _calculator.estimateFruits(provider.grandTotal, fruitSetPercentage);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Progress', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${provider.countedPosts} / ${provider.totalPosts}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TotalChip(label: 'Yellow', value: _totalFor(PostColor.yellow), color: PostColor.yellow.swatch),
              const SizedBox(width: 8),
              _TotalChip(label: 'Red', value: _totalFor(PostColor.red), color: PostColor.red.swatch),
              const SizedBox(width: 8),
              _TotalChip(label: 'White', value: _totalFor(PostColor.white), color: Colors.grey),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                    child: Text(
                      '$grand',
                      key: ValueKey('$seasonView-$grand'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                    ),
                  ),
                  Text(seasonView == SeasonView.flower ? 'Total Flowers' : 'Est. Fruits', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _TotalChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
