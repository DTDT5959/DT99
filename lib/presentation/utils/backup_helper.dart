import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

/// Simplest possible offline backup strategy for an MVP: copy the raw
/// SQLite file out to a shareable location. This is intentionally decoupled
/// from any future cloud-sync layer — sync will use per-row timestamps
/// instead, this stays as a manual "just in case" export.
class BackupHelper {
  static Future<void> backup(BuildContext context) async {
    try {
      final dbPath = await getDatabasesPath();
      final source = File(p.join(dbPath, 'dragon_fruit_flower_counter.db'));
      if (!await source.exists()) {
        _snack(context, 'No data to back up yet');
        return;
      }
      final dir = await getTemporaryDirectory();
      final dest = File(p.join(dir.path,
          'dragon_fruit_backup_${DateTime.now().millisecondsSinceEpoch}.db'));
      await source.copy(dest.path);
      await SharePlus.instance.share(ShareParams(files: [XFile(dest.path)], text: 'DragonTrack backup'));
    } catch (e) {
      _snack(context, 'Backup failed: $e');
    }
  }

  static Future<void> restore(BuildContext context) async {
    // A full implementation would use file_picker to select a .db file and
    // then close/replace the live database before reopening it. Left as a
    // clearly-marked extension point for the next iteration.
    _snack(context, 'Restore from file: connect a file picker to enable this.');
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
