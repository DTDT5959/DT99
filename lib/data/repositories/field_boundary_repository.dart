import 'dart:ui';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database_helper.dart';
import '../models/field_boundary.dart';

/// One boundary per farm. All persistence for FieldBoundary lives here —
/// screens/providers never touch SQLite directly.
class FieldBoundaryRepository {
  final _uuid = const Uuid();

  Future<FieldBoundary?> getForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('field_boundaries', where: 'farm_id = ?', whereArgs: [farmId]);
    if (rows.isEmpty) return null;
    return FieldBoundary.fromMap(rows.first);
  }

  /// Upsert: a farm has at most one boundary, so saving always overwrites
  /// whatever vertex list existed before.
  Future<FieldBoundary> save(String farmId, List<Offset> vertices) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await getForFarm(farmId);
    final now = DateTime.now();
    if (existing != null) {
      final updated = existing.copyWith(vertices: vertices, updatedAt: now);
      await db.update('field_boundaries', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      return updated;
    }
    final created = FieldBoundary(
      id: _uuid.v4(),
      farmId: farmId,
      vertices: vertices,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('field_boundaries', created.toMap());
    return created;
  }

  Future<void> deleteForFarm(String farmId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('field_boundaries', where: 'farm_id = ?', whereArgs: [farmId]);
  }

  /// Plain insert of an already fully-formed [boundary] — no
  /// existing-boundary check, unlike [save]. Used by FarmImportService,
  /// which always builds a brand-new FieldBoundary (fresh id, freshly
  /// remapped farmId) against a farm it just created, so there is never
  /// an existing row to upsert over.
  ///
  /// [executor] lets this run as part of a caller-managed transaction
  /// (see FarmImportService.saveFarm) for atomic multi-table imports.
  Future<void> insertBoundary(FieldBoundary boundary, {DatabaseExecutor? executor}) async {
    final db = executor ?? await DatabaseHelper.instance.database;
    await db.insert('field_boundaries', boundary.toMap());
  }
}
