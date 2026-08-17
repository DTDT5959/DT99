import 'dart:ui';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/database_helper.dart';
import '../models/post.dart';

class PostRepository {
  final _uuid = const Uuid();

  Future<List<Post>> getPostsForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('posts', where: 'farm_id = ?', whereArgs: [farmId]);
    return rows.map(Post.fromMap).toList();
  }

  Future<Post?> getPost(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('posts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Post.fromMap(rows.first);
  }

  /// Generates the next [count] sequential post codes for a farm in one
  /// shot, e.g. A-01, A-02... Rolls to B-01 after Z-99 so codes stay short
  /// even on very large farms. Single source of truth for code generation —
  /// [nextPostCode] and the tree-row batch creator both go through this, so
  /// a row of trees gets a contiguous, gap-free run of codes exactly like
  /// adding that many trees one at a time would.
  Future<List<String>> nextPostCodes(String farmId, int count) async {
    if (count <= 0) return const [];
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM posts WHERE farm_id = ?',
      [farmId],
    );
    final startCount = (rows.first['c'] as int?) ?? 0;
    return List.generate(count, (i) {
      final n = startCount + i;
      final letterIndex = n ~/ 99;
      final number = (n % 99) + 1;
      final letter = String.fromCharCode('A'.codeUnitAt(0) + letterIndex);
      return '$letter-${number.toString().padLeft(2, '0')}';
    });
  }

  /// Generates the next sequential post code for a farm, e.g. A-01, A-02...
  Future<String> nextPostCode(String farmId) async => (await nextPostCodes(farmId, 1)).first;

  Future<Post> createPost({
    required String farmId,
    required String postCode,
    required PostColor color,
    required double x,
    required double y,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final post = Post(
      id: _uuid.v4(),
      farmId: farmId,
      postCode: postCode,
      color: color,
      positionX: x,
      positionY: y,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('posts', post.toMap());
    return post;
  }

  Future<void> updatePost(Post post) async {
    final db = await DatabaseHelper.instance.database;
    final updated = post.copyWith(updatedAt: DateTime.now());
    await db.update('posts', updated.toMap(), where: 'id = ?', whereArgs: [post.id]);
  }

  Future<void> updatePosition(String postId, double x, double y) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'posts',
      {'position_x': x, 'position_y': y, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [postId],
    );
  }

  Future<void> deletePost(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('posts', where: 'id = ?', whereArgs: [id]);
  }

  /// Creates many independent posts in one go — used by "Add Tree Row".
  /// Each entry in [positions] becomes exactly one full, ordinary Post row
  /// (own UUID, own sequential post code, own timestamps), inserted inside
  /// a single DB transaction so a row of 50-100 trees is one fast write
  /// instead of 50-100 separate ones. There is no "row" record anywhere —
  /// only these individual posts persist, and they are indistinguishable
  /// from manually-added ones afterward.
  Future<List<Post>> createPostsBatch({
    required String farmId,
    required PostColor color,
    required List<Offset> positions,
  }) async {
    if (positions.isEmpty) return const [];
    final db = await DatabaseHelper.instance.database;
    final codes = await nextPostCodes(farmId, positions.length);
    final now = DateTime.now();
    final posts = [
      for (var i = 0; i < positions.length; i++)
        Post(
          id: _uuid.v4(),
          farmId: farmId,
          postCode: codes[i],
          color: color,
          positionX: positions[i].dx,
          positionY: positions[i].dy,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final post in posts) {
        batch.insert('posts', post.toMap());
      }
      await batch.commit(noResult: true);
    });
    return posts;
  }

  Future<Post> duplicatePost(Post source, {double offsetX = 30, double offsetY = 30}) async {
    final code = await nextPostCode(source.farmId);
    return createPost(
      farmId: source.farmId,
      postCode: code,
      color: source.color,
      x: source.positionX + offsetX,
      y: source.positionY + offsetY,
    );
  }

  /// Like [createPostsBatch], but each position gets its own color instead
  /// of one uniform color for the whole batch. Used by Duplicate Group
  /// Placement, where a selected group may contain mixed varieties that
  /// must each be preserved (spec §13). Every created post is a full,
  /// ordinary, independent Post row with its own new UUID and its own
  /// sequential post code — nothing here marks them as a "group" in any
  /// persisted way (spec §11, §15).
  Future<List<Post>> createPostsBatchVaried({
    required String farmId,
    required List<PostColor> colors,
    required List<Offset> positions,
  }) async {
    assert(colors.length == positions.length);
    if (positions.isEmpty) return const [];
    final db = await DatabaseHelper.instance.database;
    final codes = await nextPostCodes(farmId, positions.length);
    final now = DateTime.now();
    final posts = [
      for (var i = 0; i < positions.length; i++)
        Post(
          id: _uuid.v4(),
          farmId: farmId,
          postCode: codes[i],
          color: colors[i],
          positionX: positions[i].dx,
          positionY: positions[i].dy,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final post in posts) {
        batch.insert('posts', post.toMap());
      }
      await batch.commit(noResult: true);
    });
    return posts;
  }

  /// Persists a batch of already-updated Post records in one transaction —
  /// used by group Change Color so recoloring 100 trees is one fast write
  /// instead of 100 separate ones. Updates the existing row for each post
  /// (matched by id); never inserts a new one.
  Future<void> updatePostsBatch(List<Post> posts) async {
    if (posts.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final post in posts) {
        final updated = post.copyWith(updatedAt: now);
        batch.update('posts', updated.toMap(), where: 'id = ?', whereArgs: [post.id]);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Persists a batch of position updates in one transaction — used at the
  /// end of a group-move drag so moving 100 selected trees together is one
  /// fast write instead of one per tree, and never a write per drag frame.
  Future<void> updatePositionsBatch(List<({String id, double x, double y})> updates) async {
    if (updates.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final u in updates) {
        batch.update(
          'posts',
          {'position_x': u.x, 'position_y': u.y, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [u.id],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Inserts fully-formed Post records exactly as given — own id, own
  /// post code, own timestamps, all already set by the caller. Never
  /// generates codes or ids itself, unlike every other creation method
  /// here. Used by FarmImportService, which must preserve each tree's
  /// original farmer-facing post code while giving it a brand-new
  /// internal id (spec §11).
  ///
  /// [executor] lets this run as part of a caller-managed transaction
  /// (see FarmImportService.saveFarm) for atomic multi-table imports. When
  /// provided, inserts run sequentially on that same executor rather than
  /// opening a nested transaction/batch, which sqflite doesn't support —
  /// still fully atomic, just without the batch-commit speedup used when
  /// this repository manages its own transaction.
  Future<void> insertPostsBatch(List<Post> posts, {DatabaseExecutor? executor}) async {
    if (posts.isEmpty) return;
    if (executor != null) {
      for (final post in posts) {
        await executor.insert('posts', post.toMap());
      }
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final post in posts) {
        batch.insert('posts', post.toMap());
      }
      await batch.commit(noResult: true);
    });
  }
}
