import '../constants/app_constants.dart';

/// Single source of truth for turning a stored flower count into an
/// estimated fruit count, and for deciding when Fruit View unlocks for a
/// given counting session.
///
/// Deliberately stateless and side-effect free: it never reads or writes
/// the database. Screens/providers call it with data they already have,
/// which keeps this logic reusable and trivially testable.
class FruitCalculationService {
  const FruitCalculationService();

  static const int fruitViewUnlockDays = 40;
  static const double defaultFruitSetPercentage = 95.0;
  static const double minFruitSetPercentage = 50.0;
  static const double maxFruitSetPercentage = 100.0;

  /// Estimated Fruits = round(Flower Count × percentage / 100).
  /// A flower count of 0 always yields 0 (tree stays Empty either way).
  int estimateFruits(int flowerCount, double fruitSetPercentage) {
    if (flowerCount <= 0) return 0;
    final clamped = fruitSetPercentage.clamp(minFruitSetPercentage, maxFruitSetPercentage);
    return (flowerCount * clamped / 100).round();
  }

  /// A session unlocks Fruit View once it is [fruitViewUnlockDays] or more
  /// days old. `now` is injectable for testability; defaults to the real
  /// current time.
  bool isFruitViewUnlocked(DateTime sessionDate, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final sessionDay = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return todayDay.difference(sessionDay).inDays >= fruitViewUnlockDays;
  }

  /// Maps a flower count + active season view into the tree icon state
  /// that should be drawn. This is the *only* place that decision is made,
  /// so the UI layer never has to re-derive it.
  TreeState treeStateFor({required int flowerCount, required SeasonView view}) {
    if (flowerCount <= 0) return TreeState.empty;
    return view == SeasonView.fruit ? TreeState.fruiting : TreeState.flowering;
  }

  /// The number to display on top of the tree icon for the given view.
  ///
  /// [counted] must reflect whether an actual counting record exists for
  /// this post/date — NOT whether flowerCount > 0. A tree that was
  /// genuinely counted as 0 flowers still shows "0"; a tree with no record
  /// at all shows nothing. Counted-zero and not-counted must never be
  /// conflated (spec: "counted zero" vs "not counted").
  int? displayCountFor({
    required int flowerCount,
    required bool counted,
    required SeasonView view,
    required double fruitSetPercentage,
  }) {
    if (!counted) return null;
    if (flowerCount <= 0) return 0;
    return view == SeasonView.fruit ? estimateFruits(flowerCount, fruitSetPercentage) : flowerCount;
  }
}
