import 'dart:ui';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/database_helper.dart';
import '../models/farm_drawing.dart';

/// All persistence for FarmDrawing (Farm Layout Painter annotations).
/// Screens/providers never touch SQLite directly — everything funnels
/// through this repository, same as every other model in the app.
class FarmDrawingRepository {
  final _uuid = const Uuid();

  /// Oldest first, so undo/redo and rendering order stay predictable.
  Future<List<FarmDrawing>> getForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'farm_drawings',
      where: 'farm_id = ?',
      whereArgs: [farmId],
      orderBy: 'created_at ASC',
    );
    return rows.map(FarmDrawing.fromMap).toList();
  }

  Future<FarmDrawing> create({
    required String farmId,
    required DrawingType type,
    required Offset start,
    required Offset end,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final drawing = FarmDrawing(
      id: _uuid.v4(),
      farmId: farmId,
      type: type,
      startX: start.dx,
      startY: start.dy,
      endX: end.dx,
      endY: end.dy,
      createdAt: DateTime.now(),
    );
    await db.insert('farm_drawings', drawing.toMap());
    return drawing;
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('farm_drawings', where: 'id = ?', whereArgs: [id]);
  }

  /// Not called during normal "Delete Farm" — the `farm_drawings.farm_id`
  /// foreign key has `ON DELETE CASCADE` (see DatabaseHelper), so every
  /// drawing is already removed automatically the moment its farm row is
  /// deleted. Kept for symmetry with FieldBoundaryRepository.deleteForFarm
  /// and any future explicit use.
  Future<void> deleteForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('farm_drawings', where: 'farm_id = ?', whereArgs: [farmId]);
  }

  /// Bulk-inserts already fully-formed [drawings] — used by
  /// FarmImportService, which always builds brand-new FarmDrawing records
  /// (fresh ids, freshly remapped farmId) against a farm it just created.
  ///
  /// [executor] lets this run as part of a caller-managed transaction (see
  /// FarmImportService.saveFarm and PostRepository.insertPostsBatch for
  /// why the executor-provided path inserts sequentially rather than via
  /// `batch()` — sqflite doesn't support a nested transaction/batch inside
  /// an already-open one). Left unset, it runs as its own batched
  /// transaction.
  Future<void> insertBatch(List<FarmDrawing> drawings, {DatabaseExecutor? executor}) async {
    if (drawings.isEmpty) return;
    if (executor != null) {
      for (final d in drawings) {
        await executor.insert('farm_drawings', d.toMap());
      }
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final d in drawings) {
        batch.insert('farm_drawings', d.toMap());
      }
      await batch.commit(noResult: true);
    });
  }
}
