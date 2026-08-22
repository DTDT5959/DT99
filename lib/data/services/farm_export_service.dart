import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/farm_package.dart';
import '../repositories/farm_drawing_repository.dart';
import '../repositories/farm_repository.dart';
import '../repositories/field_boundary_repository.dart';
import '../repositories/flower_count_repository.dart';
import '../repositories/photo_repository.dart';
import '../repositories/post_repository.dart';

/// Builds a complete, portable .salsfarm package for one farm — every
/// tree, boundary point, flower-count record, Farm Layout Painter drawing,
/// and post photo that logically belongs to it (see FarmPackage) — and
/// writes it to a share-ready temp file. Never touches the UI; ShareFarmSheet
/// calls this and hands the resulting file to share_plus.
///
/// Deliberately reuses the SAME repositories and models the rest of the
/// app already uses for this farm: export is just "read everything
/// through the normal repository layer and serialize it," never a second
/// parallel data-access path (spec §5, §30).
class FarmExportService {
  final FarmRepository _farmRepo;
  final PostRepository _postRepo;
  final FlowerCountRepository _flowerRepo;
  final FieldBoundaryRepository _boundaryRepo;
  final FarmDrawingRepository _drawingRepo;
  final PhotoRepository _photoRepo;

  FarmExportService({
    FarmRepository? farmRepo,
    PostRepository? postRepo,
    FlowerCountRepository? flowerRepo,
    FieldBoundaryRepository? boundaryRepo,
    FarmDrawingRepository? drawingRepo,
    PhotoRepository? photoRepo,
  })  : _farmRepo = farmRepo ?? FarmRepository(),
        _postRepo = postRepo ?? PostRepository(),
        _flowerRepo = flowerRepo ?? FlowerCountRepository(),
        _boundaryRepo = boundaryRepo ?? FieldBoundaryRepository(),
        _drawingRepo = drawingRepo ?? FarmDrawingRepository(),
        _photoRepo = photoRepo ?? PhotoRepository();

  /// Loads every record that belongs to [farmId], builds the package, and
  /// writes it to the OS temp directory as a `.salsfarm` zip, ready to
  /// hand to share_plus. Everything is gathered through a single pass
  /// over each post (posts, then that post's flower history and photos)
  /// so a 1,000-tree farm with years of history is still just one
  /// sequential sweep, not a query-per-field explosion (spec §25).
  ///
  /// Throws [StateError] if [farmId] doesn't exist.
  Future<FarmExportResult> exportFarm(String farmId) async {
    final farm = await _farmRepo.getFarm(farmId);
    if (farm == null) {
      throw StateError('Farm not found');
    }

    final posts = await _postRepo.getPostsForFarm(farmId);
    final boundary = await _boundaryRepo.getForFarm(farmId);
    final drawings = await _drawingRepo.getForFarm(farmId);

    final flowerCountMaps = <Map<String, dynamic>>[];
    final countingDates = <String>{};
    final packagePhotos = <FarmPackagePhoto>[];
    final photoSourceFiles = <String, File>{}; // archivePath -> file on this device

    for (final post in posts) {
      final history = await _flowerRepo.getHistoryForPost(post.id);
      for (final fc in history) {
        flowerCountMaps.add(fc.toMap());
        countingDates.add(fc.toMap()['date'] as String);
      }

      final postPhotos = await _photoRepo.getPhotosForPost(post.id);
      for (final photo in postPhotos) {
        final source = File(photo.imagePath);
        if (!await source.exists()) continue; // skip a missing file rather than failing the whole export
        final archivePath = 'photos/${photo.id}${p.extension(photo.imagePath)}';
        packagePhotos.add(
          FarmPackagePhoto(postId: post.id, archivePath: archivePath, createdAt: photo.createdAt),
        );
        photoSourceFiles[archivePath] = source;
      }
    }

    final package = FarmPackage(
      version: FarmPackage.currentVersion,
      exportedAt: DateTime.now(),
      farmMap: farm.toMap(),
      boundaryMap: boundary?.toMap(),
      postMaps: posts.map((post) => post.toMap()).toList(),
      flowerCountMaps: flowerCountMaps,
      photos: packagePhotos,
      drawingMaps: drawings.map((d) => d.toMap()).toList(),
    );

    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(package.toManifestJson()));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    for (final entry in photoSourceFiles.entries) {
      final bytes = await entry.value.readAsBytes();
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }

    // Zip gives us both the "compress if useful" ask (spec §25) and a
    // single-file container for the manifest + every photo, for free.
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Could not build the farm package');
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, _sanitizedFileName(farm.name)));
    await file.writeAsBytes(zipBytes, flush: true);

    return FarmExportResult(
      file: file,
      summary: FarmExportSummary(
        farmName: farm.name,
        treeCount: posts.length,
        countingDateCount: countingDates.length,
        flowerRecordCount: flowerCountMaps.length,
      ),
    );
  }

  /// "Dragon Farm" -> "Dragon_Farm.salsfarm"; strips characters that
  /// aren't safe across Android/iOS/Windows/macOS filesystems (spec §7).
  static String _sanitizedFileName(String farmName) {
    final sanitized = farmName.trim().replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    final base = sanitized.isEmpty ? 'Farm' : sanitized;
    return '$base.salsfarm';
  }
}

class FarmExportResult {
  final File file;
  final FarmExportSummary summary;
  const FarmExportResult({required this.file, required this.summary});
}

/// Real, calculated numbers for the Share Farm confirmation (spec §28) —
/// never hard-coded.
class FarmExportSummary {
  final String farmName;
  final int treeCount;
  final int countingDateCount;
  final int flowerRecordCount;
  const FarmExportSummary({
    required this.farmName,
    required this.treeCount,
    required this.countingDateCount,
    required this.flowerRecordCount,
  });
}
