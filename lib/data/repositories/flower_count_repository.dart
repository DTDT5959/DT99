import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database_helper.dart';
import '../models/flower_count.dart';

class FlowerCountRepository {
  final _uuid = const Uuid();

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Returns a map of postId -> FlowerCount for a given farm and date, i.e.
  /// everything already counted in a session (used to pre-fill the canvas).
  Future<Map<String, FlowerCount>> getCountsForFarmDate(String farmId, DateTime date) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT fc.* FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ? AND fc.date = ?
    ''', [farmId, _dateKey(date)]);
    final result = <String, FlowerCount>{};
    for (final row in rows) {
      final fc = FlowerCount.fromMap(row);
      result[fc.postId] = fc;
    }
    return result;
  }

  /// Upsert: one flower count per (post, date). Editing a counted post
  /// during the same session overwrites its earlier value.
  Future<FlowerCount> saveCount({
    required String postId,
    required DateTime date,
    required int count,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final key = _dateKey(date);
    final existing = await db.query(
      'flower_counts',
      where: 'post_id = ? AND date = ?',
      whereArgs: [postId, key],
    );
    final now = DateTime.now();
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String;
      final updated = FlowerCount(
        id: id,
        postId: postId,
        date: date,
        flowerCount: count,
        createdAt: DateTime.parse(existing.first['created_at'] as String),
        updatedAt: now,
      );
      await db.update('flower_counts', updated.toMap(), where: 'id = ?', whereArgs: [id]);
      return updated;
    } else {
      final created = FlowerCount(
        id: _uuid.v4(),
        postId: postId,
        date: date,
        flowerCount: count,
        createdAt: now,
        updatedAt: now,
      );
      await db.insert('flower_counts', created.toMap());
      return created;
    }
  }

  /// All distinct counting sessions for a farm (used by the History screen),
  /// newest first, with the grand total flowers for that date.
  Future<List<Map<String, dynamic>>> getSessionsForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT fc.date as date, SUM(fc.flower_count) as total
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ?
      GROUP BY fc.date
      ORDER BY fc.date DESC
    ''', [farmId]);
  }


// Sum of flower_count per post within [from, to] inclusive — the core
// query behind the Analytics Map. A single grouped SQL query rather
// than one lookup per post is what keeps this fast at 3,000+ trees;
// panning/zooming the map never re-queries, it only re-renders.
Future<Map<String, int>> getAggregatedCountsForFarm(
  String farmId, {
  required DateTime from,
  required DateTime to,
}) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery('''
    SELECT fc.post_id as post_id, SUM(fc.flower_count) as total
    FROM flower_counts fc
    INNER JOIN posts p ON p.id = fc.post_id
    WHERE p.farm_id = ? AND fc.date >= ? AND fc.date <= ?
    GROUP BY fc.post_id
  ''', [farmId, _dateKey(from), _dateKey(to)]);
  return {for (final row in rows) row['post_id'] as String: (row['total'] as int?) ?? 0};
}

// Every individual session's flower_count for every post in a farm, as
// a single query — backs the average/max/min shown in the Analytics Map
// tree-detail sheet without a per-post round trip.
Future<Map<String, List<int>>> getFullHistoryForFarm(String farmId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery('''
    SELECT fc.post_id as post_id, fc.flower_count as flower_count
    FROM flower_counts fc
    INNER JOIN posts p ON p.id = fc.post_id
    WHERE p.farm_id = ?
  ''', [farmId]);
  final result = <String, List<int>>{};
  for (final row in rows) {
    final postId = row['post_id'] as String;
    result.putIfAbsent(postId, () => []).add(row['flower_count'] as int);
  }
  return result;
}



  Future<List<FlowerCount>> getHistoryForPost(String postId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'flower_counts',
      where: 'post_id = ?',
      whereArgs: [postId],
      orderBy: 'date DESC',
    );
    return rows.map(FlowerCount.fromMap).toList();
  }

  /// Aggregate totals by color for a farm within an optional date range —
  /// backs the Statistics dashboard (week / month / season summaries).
  Future<Map<String, int>> totalsByColor(String farmId, {DateTime? from, DateTime? to}) async {
    final db = await DatabaseHelper.instance.database;
    final where = StringBuffer('p.farm_id = ?');
    final args = <Object?>[farmId];
    if (from != null) {
      where.write(' AND fc.date >= ?');
      args.add(_dateKey(from));
    }
    if (to != null) {
      where.write(' AND fc.date <= ?');
      args.add(_dateKey(to));
    }
    final rows = await db.rawQuery('''
      SELECT p.color as color, SUM(fc.flower_count) as total
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE $where
      GROUP BY p.color
    ''', args);
    final result = {'yellow': 0, 'red': 0, 'white': 0};
    for (final row in rows) {
      result[row['color'] as String] = (row['total'] as int?) ?? 0;
    }
    return result;
  }

  Future<int> grandTotal(String farmId, {DateTime? from, DateTime? to}) async {
    final totals = await totalsByColor(farmId, from: from, to: to);
    return totals.values.fold<int>(0, (int a, int b) => a + b);
  }

  /// Daily flowering totals for the last N days — feeds the line chart.
  Future<List<Map<String, dynamic>>> dailyTotals(String farmId, {int days = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final since = DateTime.now().subtract(Duration(days: days));
    return db.rawQuery('''
      SELECT fc.date as date, SUM(fc.flower_count) as total
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ? AND fc.date >= ?
      GROUP BY fc.date
      ORDER BY fc.date ASC
    ''', [farmId, _dateKey(since)]);
  }

  Future<Map<String, dynamic>?> highestProducingPost(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.post_code as post_code, SUM(fc.flower_count) as total
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ?
      GROUP BY p.id
      ORDER BY total DESC
      LIMIT 1
    ''', [farmId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> lowestProducingPost(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.post_code as post_code, SUM(fc.flower_count) as total
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ?
      GROUP BY p.id
      ORDER BY total ASC
      LIMIT 1
    ''', [farmId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// "Finish Counting": for every post id in [allPostIds] that does not
  /// already have a record for [date], inserts one with flowerCount = 0.
  /// Posts that already have a record (any value, including a genuine 0)
  /// are left completely untouched — existing rows are never overwritten
  /// here.
  ///
  /// Safe to call repeatedly / concurrently: each insert uses
  /// [ConflictAlgorithm.ignore] against the existing unique (post_id, date)
  /// index, so a record created by a race (or a second tap of "Finish
  /// Counting") is silently skipped rather than duplicated or overwritten.
  Future<void> markRemainingAsZero({
    required String farmId,
    required DateTime date,
    required List<String> allPostIds,
  }) async {
    if (allPostIds.isEmpty) return;
    final existing = await getCountsForFarmDate(farmId, date);
    final missing = allPostIds.where((id) => !existing.containsKey(id)).toList();
    if (missing.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final postId in missing) {
        final zero = FlowerCount(
          id: _uuid.v4(),
          postId: postId,
          date: date,
          flowerCount: 0,
          createdAt: now,
          updatedAt: now,
        );
        batch.insert('flower_counts', zero.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Counts, for the confirmation dialog, how many distinct counting dates
  /// and how many individual flower records fall within [from, to]
  /// (inclusive) for this farm — used by Reset Counting before it deletes
  /// anything.
  Future<({int dateCount, int recordCount})> getResetPreview(
    String farmId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT fc.date) as date_count, COUNT(*) as record_count
      FROM flower_counts fc
      INNER JOIN posts p ON p.id = fc.post_id
      WHERE p.farm_id = ? AND fc.date >= ? AND fc.date <= ?
    ''', [farmId, _dateKey(from), _dateKey(to)]);
    final row = rows.first;
    return (
      dateCount: (row['date_count'] as int?) ?? 0,
      recordCount: (row['record_count'] as int?) ?? 0,
    );
  }

  /// "Reset Counting": permanently removes (not zeroes out) every flower
  /// count record for this farm whose date falls within [from, to]
  /// inclusive. Trees, layout, boundary, photos, and records outside the
  /// range are never touched. A tree that had a record inside the range —
  /// including a genuine 0 — goes back to "not counted" for that date,
  /// because the row itself is deleted rather than its value changed.
  ///
  /// Runs as a single transaction: either the whole range is removed or
  /// (on error) nothing is, so the database is never left half-reset.
  Future<void> resetRange({
    required String farmId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.rawDelete('''
        DELETE FROM flower_counts
        WHERE post_id IN (SELECT id FROM posts WHERE farm_id = ?)
          AND date >= ? AND date <= ?
      ''', [farmId, _dateKey(from), _dateKey(to)]);
    });
  }

  /// Inserts fully-formed FlowerCount records exactly as given — own id,
  /// own timestamps, all already set by the caller. Unlike [saveCount],
  /// never checks for an existing (post, date) row first, since these are
  /// always brand-new rows against a brand-new set of imported post ids.
  /// Used by FarmImportService to bulk-load a farm's entire flower
  /// history in one go (spec §18).
  ///
  /// [executor] lets this run as part of a caller-managed transaction
  /// (see FarmImportService.saveFarm) for atomic multi-table imports —
  /// see [PostRepository.insertPostsBatch] for why the executor-provided
  /// path inserts sequentially rather than via a nested batch/transaction.
  Future<void> insertBatch(List<FlowerCount> counts, {DatabaseExecutor? executor}) async {
    if (counts.isEmpty) return;
    if (executor != null) {
      for (final c in counts) {
        await executor.insert('flower_counts', c.toMap());
      }
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final c in counts) {
        batch.insert('flower_counts', c.toMap());
      }
      await batch.commit(noResult: true);
    });
  }
}
