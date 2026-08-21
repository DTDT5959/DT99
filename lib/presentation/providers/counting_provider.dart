import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/flower_count.dart';
import '../../data/models/post.dart';
import '../../data/repositories/flower_count_repository.dart';
import '../../data/repositories/post_repository.dart';

class CountingProvider extends ChangeNotifier {
  final PostRepository _postRepo = PostRepository();
  final FlowerCountRepository _countRepo = FlowerCountRepository();

  final String farmId;
  final DateTime date;
  CountingProvider({required this.farmId, required this.date});

  List<Post> _posts = [];
  Map<String, FlowerCount> _counts = {}; // postId -> count for `date`
  bool _loading = false;

  List<Post> get posts => _posts;
  Map<String, FlowerCount> get counts => _counts;
  bool get loading => _loading;

  int get totalPosts => _posts.length;
  int get countedPosts => _counts.length;
  bool get isComplete => totalPosts > 0 && countedPosts >= totalPosts;

  int totalFor(PostColor color) {
    int sum = 0;
    for (final post in _posts) {
      if (post.color != color) continue;
      final c = _counts[post.id];
      if (c != null) sum += c.flowerCount;
    }
    return sum;
  }

  int get grandTotal => _counts.values.fold(0, (a, c) => a + c.flowerCount);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _posts = await _postRepo.getPostsForFarm(farmId);
    _counts = await _countRepo.getCountsForFarmDate(farmId, date);
    _loading = false;
    notifyListeners();
  }

  bool isCounted(String postId) => _counts.containsKey(postId);

  /// Saves a count for one post and closes the popup automatically — this
  /// is the single most important interaction in the whole app, so it's
  /// kept to one repository call and one notifyListeners().
  Future<void> saveCount(String postId, int count) async {
    final saved = await _countRepo.saveCount(postId: postId, date: date, count: count);
    _counts = {..._counts, postId: saved};
    notifyListeners();
  }

  /// How many posts still have no record for [date] — shown in the
  /// "Finish Counting" confirmation dialog.
  int get remainingUncounted => totalPosts - countedPosts;

  /// "Finish Counting": records every currently-uncounted post as 0
  /// flowers for this date, leaving every existing record (including any
  /// legitimate zero already saved) untouched. Delegates the actual write
  /// to FlowerCountRepository so this stays a thin orchestration layer —
  /// safe to call more than once, since the repository ignores posts that
  /// already have a record.
  Future<void> finishCounting() async {
    final allPostIds = _posts.map((p) => p.id).toList();
    await _countRepo.markRemainingAsZero(farmId: farmId, date: date, allPostIds: allPostIds);
    _counts = await _countRepo.getCountsForFarmDate(farmId, date);
    notifyListeners();
  }
}
