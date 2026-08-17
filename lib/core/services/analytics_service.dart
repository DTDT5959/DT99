import '../constants/app_constants.dart';
import 'fruit_calculation_service.dart';

/// How the Analytics Map's date filter is currently configured.
enum DateFilterMode { single, range, untilToday }

/// Immutable snapshot of one tree's aggregated numbers for the current
/// filter, used both by the map (label + tree state) and the tree-detail
/// bottom sheet.
class TreeAnalytics {
  final String postId;
  final String postCode;
  final PostColor color;
  final int filteredTotal; // sum of flower counts within the active filter
  final int sessionCount; // how many counting sessions fall in the filter
  final double averageFlowers; // across ALL recorded sessions (full history)
  final int maxFlowers;
  final int minFlowers;

  const TreeAnalytics({
    required this.postId,
    required this.postCode,
    required this.color,
    required this.filteredTotal,
    required this.sessionCount,
    required this.averageFlowers,
    required this.maxFlowers,
    required this.minFlowers,
  });

  TreeState treeStateFor(SeasonView view) =>
      const FruitCalculationService().treeStateFor(flowerCount: filteredTotal, view: view);
}

/// Farm-wide rollup for the statistics header. Every field here is derived
/// — nothing here is ever written back to storage.
class FarmAnalytics {
  final int totalFlowers;
  final double averagePerTree;
  final int treesWithFlowers;
  final int treesWithoutFlowers;
  final TreeAnalytics? highestProducing;
  final TreeAnalytics? lowestProducing;
  final Map<PostColor, int> totalsByColor;
  final int estimatedFruits;

  const FarmAnalytics({
    required this.totalFlowers,
    required this.averagePerTree,
    required this.treesWithFlowers,
    required this.treesWithoutFlowers,
    required this.highestProducing,
    required this.lowestProducing,
    required this.totalsByColor,
    required this.estimatedFruits,
  });

  int get totalTrees => treesWithFlowers + treesWithoutFlowers;

  double get percentTreesWithFlowers => totalTrees == 0 ? 0 : (treesWithFlowers / totalTrees) * 100;
}

/// Turns raw (post, flowerCounts-by-date) data into everything the
/// Analytics Map needs: per-tree totals for the active filter, and the
/// farm-wide statistics header. Pure and stateless — it never touches the
/// database itself; callers pass in whatever rows the repository already
/// fetched, which keeps this trivially testable and keeps the "which SQL
/// query to run" concern separate from "how to aggregate the results".
class AnalyticsService {
  const AnalyticsService();

  static const _fruitCalc = FruitCalculationService();

  /// Resolves a [DateFilterMode] + user-picked date(s) into a concrete
  /// (from, to) range to query. `single` collapses from == to.
  (DateTime from, DateTime to) resolveRange({
    required DateFilterMode mode,
    required DateTime singleDate,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    switch (mode) {
      case DateFilterMode.single:
        return (singleDate, singleDate);
      case DateFilterMode.range:
        return (startDate, endDate ?? DateTime.now());
      case DateFilterMode.untilToday:
        return (startDate, DateTime.now());
    }
  }

  /// Builds per-tree analytics for every post in [posts].
  ///
  /// [filteredCountsByPost] = sum of flower_count for each post within the
  /// active date filter (from the repository's ranged aggregation query).
  /// [fullHistoryByPost] = every session ever recorded for each post
  /// (used only for the average/max/min shown in the tree-detail sheet,
  /// which stay meaningful regardless of the active map filter).
  List<TreeAnalytics> buildTreeAnalytics({
    required List<({String id, String postCode, PostColor color})> posts,
    required Map<String, int> filteredCountsByPost,
    required Map<String, List<int>> fullHistoryByPost,
  }) {
    return posts.map((p) {
      final history = fullHistoryByPost[p.id] ?? const <int>[];
      final avg = history.isEmpty ? 0.0 : history.reduce((a, b) => a + b) / history.length;
      final maxV = history.isEmpty ? 0 : history.reduce((a, b) => a > b ? a : b);
      final minV = history.isEmpty ? 0 : history.reduce((a, b) => a < b ? a : b);
      return TreeAnalytics(
        postId: p.id,
        postCode: p.postCode,
        color: p.color,
        filteredTotal: filteredCountsByPost[p.id] ?? 0,
        sessionCount: history.length,
        averageFlowers: avg,
        maxFlowers: maxV,
        minFlowers: minV,
      );
    }).toList();
  }

  /// Rolls a list of already-computed [TreeAnalytics] up into the farm-wide
  /// statistics header, including a fruit estimate when Fruit View is on.
  FarmAnalytics buildFarmAnalytics(
    List<TreeAnalytics> trees, {
    required bool fruitViewEnabled,
    required double fruitSetPercentage,
  }) {
    if (trees.isEmpty) {
      return const FarmAnalytics(
        totalFlowers: 0,
        averagePerTree: 0,
        treesWithFlowers: 0,
        treesWithoutFlowers: 0,
        highestProducing: null,
        lowestProducing: null,
        totalsByColor: {},
        estimatedFruits: 0,
      );
    }

    final totalFlowers = trees.fold<int>(0, (a, t) => a + t.filteredTotal);
    final withFlowers = trees.where((t) => t.filteredTotal > 0).toList();
    final withoutFlowers = trees.length - withFlowers.length;

    TreeAnalytics? highest;
    TreeAnalytics? lowest;
    for (final t in trees) {
      if (highest == null || t.filteredTotal > highest.filteredTotal) highest = t;
      if (lowest == null || t.filteredTotal < lowest.filteredTotal) lowest = t;
    }

    final byColor = <PostColor, int>{for (final c in PostColor.values) c: 0};
    for (final t in trees) {
      byColor[t.color] = (byColor[t.color] ?? 0) + t.filteredTotal;
    }

    return FarmAnalytics(
      totalFlowers: totalFlowers,
      averagePerTree: trees.isEmpty ? 0 : totalFlowers / trees.length,
      treesWithFlowers: withFlowers.length,
      treesWithoutFlowers: withoutFlowers,
      highestProducing: highest,
      lowestProducing: lowest,
      totalsByColor: byColor,
      estimatedFruits: fruitViewEnabled
          ? _fruitCalc.estimateFruits(totalFlowers, fruitSetPercentage)
          : 0,
    );
  }
}
