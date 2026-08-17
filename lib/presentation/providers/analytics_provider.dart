import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/fruit_calculation_service.dart';
import '../../data/models/post.dart';
import '../../data/repositories/flower_count_repository.dart';
import '../../data/repositories/post_repository.dart';

/// State for the Analytics Map. Owns the current filter, re-queries the
/// (already-efficient, single-round-trip) repository methods whenever a
/// filter changes, and hands the raw data to AnalyticsService for
/// aggregation. The UI only ever reads the computed [treeAnalytics] /
/// [farmAnalytics] — it never aggregates anything itself.
class AnalyticsProvider extends ChangeNotifier {
  final String farmId;
  AnalyticsProvider(this.farmId);

  final _postRepo = PostRepository();
  final _countRepo = FlowerCountRepository();
  static const _service = AnalyticsService();
  static const _fruitCalc = FruitCalculationService();

  bool loading = true;
  List<Post> posts = [];
  List<TreeAnalytics> treeAnalytics = [];
  FarmAnalytics farmAnalytics = const FarmAnalytics(
    totalFlowers: 0,
    averagePerTree: 0,
    treesWithFlowers: 0,
    treesWithoutFlowers: 0,
    highestProducing: null,
    lowestProducing: null,
    totalsByColor: {},
    estimatedFruits: 0,
  );

  // --- Filter state -------------------------------------------------
  DateFilterMode dateMode = DateFilterMode.single;
  DateTime singleDate = DateTime.now();
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  QuickFilter? activeQuickFilter = QuickFilter.today;
  SeasonView seasonView = SeasonView.flower;
  double fruitSetPercentage = FruitCalculationService.defaultFruitSetPercentage;

  bool get fruitViewAvailableForFilter {
    final (_, to) = _service.resolveRange(
      mode: dateMode,
      singleDate: singleDate,
      startDate: startDate,
      endDate: endDate,
    );
    return _fruitCalc.isFruitViewUnlocked(to);
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    posts = await _postRepo.getPostsForFarm(farmId);
    await _recalculate();
    loading = false;
    notifyListeners();
  }

  Future<void> _recalculate() async {
    final (from, to) = _service.resolveRange(
      mode: dateMode,
      singleDate: singleDate,
      startDate: startDate,
      endDate: endDate,
    );
    final filteredCounts = await _countRepo.getAggregatedCountsForFarm(farmId, from: from, to: to);
    final fullHistory = await _countRepo.getFullHistoryForFarm(farmId);

    treeAnalytics = _service.buildTreeAnalytics(
      posts: posts.map((p) => (id: p.id, postCode: p.postCode, color: p.color)).toList(),
      filteredCountsByPost: filteredCounts,
      fullHistoryByPost: fullHistory,
    );
    farmAnalytics = _service.buildFarmAnalytics(
      treeAnalytics,
      fruitViewEnabled: seasonView == SeasonView.fruit,
      fruitSetPercentage: fruitSetPercentage,
    );
  }

  Future<void> _applyAndReload() async {
    notifyListeners(); // instant UI feedback (loading chips, etc.)
    await _recalculate();
    notifyListeners();
  }

  Future<void> setSingleDate(DateTime date) async {
    dateMode = DateFilterMode.single;
    singleDate = date;
    activeQuickFilter = null;
    await _applyAndReload();
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    dateMode = DateFilterMode.range;
    startDate = start;
    endDate = end;
    activeQuickFilter = QuickFilter.customRange;
    await _applyAndReload();
  }

  Future<void> setUntilToday(DateTime start) async {
    dateMode = DateFilterMode.untilToday;
    startDate = start;
    endDate = DateTime.now();
    activeQuickFilter = QuickFilter.untilToday;
    await _applyAndReload();
  }

  Future<void> applyQuickFilter(QuickFilter filter) async {
    final now = DateTime.now();
    activeQuickFilter = filter;
    switch (filter) {
      case QuickFilter.today:
        dateMode = DateFilterMode.single;
        singleDate = now;
        break;
      case QuickFilter.yesterday:
        dateMode = DateFilterMode.single;
        singleDate = now.subtract(const Duration(days: 1));
        break;
      case QuickFilter.last7Days:
        dateMode = DateFilterMode.range;
        startDate = now.subtract(const Duration(days: 6));
        endDate = now;
        break;
      case QuickFilter.last30Days:
        dateMode = DateFilterMode.range;
        startDate = now.subtract(const Duration(days: 29));
        endDate = now;
        break;
      case QuickFilter.thisMonth:
        dateMode = DateFilterMode.range;
        startDate = DateTime(now.year, now.month, 1);
        endDate = now;
        break;
      case QuickFilter.thisSeason:
        dateMode = DateFilterMode.range;
        startDate = now.subtract(const Duration(days: 120));
        endDate = now;
        break;
      case QuickFilter.untilToday:
        dateMode = DateFilterMode.untilToday;
        // startDate left as whatever the user last picked via the date
        // field; if never set, default to the start of this season.
        endDate = now;
        break;
      case QuickFilter.customRange:
        dateMode = DateFilterMode.range;
        break;
    }
    await _applyAndReload();
  }

  Future<void> setSeasonView(SeasonView view) async {
    seasonView = view;
    await _applyAndReload();
  }

  Future<void> setFruitSetPercentage(double value) async {
    fruitSetPercentage = value.clamp(
      FruitCalculationService.minFruitSetPercentage,
      FruitCalculationService.maxFruitSetPercentage,
    );
    await _applyAndReload();
  }

  TreeAnalytics? analyticsForPost(String postId) {
    for (final t in treeAnalytics) {
      if (t.postId == postId) return t;
    }
    return null;
  }
}
