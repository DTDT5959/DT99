import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database_helper.dart';
import '../models/farm.dart';

/// All persistence for Farms. Screens/providers never touch `sqflite`
/// directly — everything funnels through repositories like this one so the
/// storage engine (SQLite today, a cloud API tomorrow) can be swapped.
class FarmRepository {
  final _uuid = const Uuid();
  Future<DatabaseHelper> get _helper async => DatabaseHelper.instance;

  Future<List<Farm>> getAllFarms() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT f.*, (SELECT COUNT(*) FROM posts p WHERE p.farm_id = f.id) AS total_posts
      FROM farms f
      ORDER BY f.updated_at DESC
    ''');
    return rows.map(Farm.fromMap).toList();
  }

  Future<Farm?> getFarm(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT f.*, (SELECT COUNT(*) FROM posts p WHERE p.farm_id = f.id) AS total_posts
      FROM farms f WHERE f.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Farm.fromMap(rows.first);
  }

  /// [executor] lets FarmImportService run this insert as part of its own
  /// outer `db.transaction(...)` (see FarmImportService.saveFarm) so a
  /// whole farm import is one atomic write — every other call site leaves
  /// it unset and gets a normal, immediately-committed insert exactly as
  /// before. [importedAt] is only ever passed by FarmImportService; every
  /// farm created through the normal "New Farm" flow leaves it null.
  Future<Farm> createFarm({
    required String name,
    String? description,
    DateTime? importedAt,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final farm = Farm(
      id: _uuid.v4(),
      name: name.trim(),
      description: description?.trim(),
      createdAt: now,
      updatedAt: now,
      importedAt: importedAt,
    );
    await db.insert('farms', farm.toMap());
    return farm;
  }

  Future<void> updateFarm(Farm farm) async {
    final db = await DatabaseHelper.instance.database;
    final updated = farm.copyWith(updatedAt: DateTime.now());
    await db.update('farms', updated.toMap(), where: 'id = ?', whereArgs: [farm.id]);
  }

  Future<void> deleteFarm(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('farms', where: 'id = ?', whereArgs: [id]);
  }
}
