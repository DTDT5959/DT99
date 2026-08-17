import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database_helper.dart';
import '../models/photo.dart';

class PhotoRepository {
  final _uuid = const Uuid();

  Future<List<Photo>> getPhotosForPost(String postId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'photos',
      where: 'post_id = ?',
      whereArgs: [postId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Photo.fromMap).toList();
  }

  Future<Photo> addPhoto({required String postId, required String imagePath}) async {
    final db = await DatabaseHelper.instance.database;
    final photo = Photo(
      id: _uuid.v4(),
      postId: postId,
      imagePath: imagePath,
      createdAt: DateTime.now(),
    );
    await db.insert('photos', photo.toMap());
    return photo;
  }

  Future<void> deletePhoto(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  /// Inserts fully-formed Photo records exactly as given — used by
  /// FarmImportService once each photo's bytes have been extracted from
  /// the .salsfarm package and written to a fresh local file (see
  /// FarmImportService._extractPhoto); [imagePath] is always already a
  /// new local path by the time it reaches here, never the sender's
  /// original one.
  ///
  /// [executor] lets this run as part of a caller-managed transaction
  /// (see FarmImportService.saveFarm) for atomic multi-table imports —
  /// see [PostRepository.insertPostsBatch] for why the executor-provided
  /// path inserts sequentially rather than via a nested batch/transaction.
  Future<void> insertBatch(List<Photo> photos, {DatabaseExecutor? executor}) async {
    if (photos.isEmpty) return;
    if (executor != null) {
      for (final photo in photos) {
        await executor.insert('photos', photo.toMap());
      }
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final photo in photos) {
        batch.insert('photos', photo.toMap());
      }
      await batch.commit(noResult: true);
    });
  }
}
