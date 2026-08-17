import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/post.dart';
import '../../data/repositories/flower_count_repository.dart';

/// Builds farm counting data into CSV / Excel / PDF and hands it to the OS
/// share sheet. Kept as a standalone utility (not a repository) since it
/// only reads already-loaded data and never touches SQLite directly.
class ExportHelper {
  static Future<List<Map<String, dynamic>>> _rowsForFarm(
    String farmId,
    List<Post> posts,
    DateTime date,
  ) async {
    final countRepo = FlowerCountRepository();
    final counts = await countRepo.getCountsForFarmDate(farmId, date);

    return posts
        .map((p) => {
              'Post ID': p.postCode,
              'Color': p.color.label,
              'Flower Count': counts[p.id]?.flowerCount ?? 0,
            })
        .toList();
  }

  static Future<void> exportCsv(
    BuildContext context,
    String farmId,
    List<Post> posts,
    DateTime date,
) async {
  final rows = await _rowsForFarm(farmId, posts, date);

  final csvData = csv.encode([
    ['Post ID', 'Color', 'Flower Count'],
    ...rows.map((r) => [
          r['Post ID'],
          r['Color'],
          r['Flower Count'],
        ]),
  ]);

  final file = await _writeTemp('flower_count.csv', csvData);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
    ),
  );
}

  static Future<void> exportExcel(
    BuildContext context,
    String farmId,
    List<Post> posts,
    DateTime date,
  ) async {
    final rows = await _rowsForFarm(farmId, posts, date);

    final workbook = xl.Excel.createExcel();
    final sheet = workbook['Flower Count'];

    sheet.appendRow(
      ['Post ID', 'Color', 'Flower Count']
          .map((e) => xl.TextCellValue(e))
          .toList(),
    );

    for (final row in rows) {
      sheet.appendRow([
        xl.TextCellValue('${row['Post ID']}'),
        xl.TextCellValue('${row['Color']}'),
        xl.IntCellValue(row['Flower Count'] as int),
      ]);
    }

    final bytes = workbook.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/flower_count.xlsx');

    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)]),
    );
  }

  static Future<void> exportPdf(
    BuildContext context,
    String farmName,
    String farmId,
    List<Post> posts,
    DateTime date,
  ) async {
    final rows = await _rowsForFarm(farmId, posts, date);

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              farmName,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: const [
                'Post ID',
                'Color',
                'Flower Count',
              ],
              data: rows
                  .map((r) => [
                        r['Post ID'],
                        r['Color'],
                        '${r['Flower Count']}',
                      ])
                  .toList(),
            ),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/flower_count_report.pdf');

    await file.writeAsBytes(await doc.save());

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)]),
    );
  }

  static Future<File> _writeTemp(
    String name,
    String contents,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');

    return file.writeAsString(contents);
  }
}