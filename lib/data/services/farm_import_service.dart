import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/database_helper.dart';
import '../models/farm_package.dart';
import '../models/field_boundary.dart';
import '../models/flower_count.dart';
import '../models/photo.dart';
import '../models/post.dart';
import '../repositories/farm_repository.dart';
import '../repositories/field_boundary_repository.dart';
import '../repositories/flower_count_repository.dart';
import '../repositories/photo_repository.dart';
import '../repositories/post_repository.dart';

/// Reads, validates, and (on confirmation) imports a .salsfarm package
/// built by FarmExportService.
///
/// [readPackage] only parses the file into an in-memory [ParsedFarmImport]
/// — nothing is written to the database until [saveFarm] is explicitly
/// called, so the UI can show the farmer an Import Preview first and let
/// them back out (spec §9-10).
class FarmImportService {
  final _uuid = const Uuid();
  final FarmRepository _farmRepo;
  final PostRepository _postRepo;
  final FlowerCountRepository _flowerRepo;
  final FieldBoundaryRepository _boundaryRepo;
  final PhotoRepository _photoRepo;

  FarmImportService({
    FarmRepository? farmRepo,
    PostRepository? postRepo,
    FlowerCountRepository? flowerRepo,
    FieldBoundaryRepository? boundaryRepo,
    PhotoRepository? photoRepo,
  })  : _farmRepo = farmRepo ?? FarmRepository(),
        _postRepo = postRepo ?? PostRepository(),
        _flowerRepo = flowerRepo ?? FlowerCountRepository(),
        _boundaryRepo = boundaryRepo ?? FieldBoundaryRepository(),
        _photoRepo = photoRepo ?? PhotoRepository();

  /// Reads and validates [file] without touching the database. Throws
  /// [FarmPackageFormatException] / [FarmPackageVersionException] on
  /// anything malformed or unsupported — callers should catch these and
  /// show the friendly message each carries (spec §14) rather than a
  /// stack trace.
  Future<ParsedFarmImport> readPackage(File file) async {
    final Uint8ListLike bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw const FarmPackageFormatException();
    }
    if (bytes.isEmpty) throw const FarmPackageFormatException();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FarmPackageFormatException();
    }

    ArchiveFile? manifestFile;
    for (final f in archive.files) {
      if (f.name == 'manifest.json') {
        manifestFile = f;
        break;
      }
    }
    if (manifestFile == null) throw const FarmPackageFormatException();

    final Map<String, dynamic> manifestJson;
    try {
      final decoded = jsonDecode(utf8.decode(manifestFile.content as List<int>));
      if (decoded is! Map<String, dynamic>) throw const FarmPackageFormatException();
      manifestJson = decoded;
    } on FarmPackageFormatException {
      rethrow;
    } catch (_) {
      throw const FarmPackageFormatException();
    }

    final package = FarmPackage.fromManifestJson(manifestJson);
    _validate(package);

    final dateKeys = package.flowerCountMaps.map((m) => m['date'] as String? ?? '').toSet()..remove('');
    final rawName = package.farmMap['name'] as String?;
    final preview = FarmImportPreview(
      farmName: (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : 'Imported Farm',
      treeCount: package.postMaps.length,
      countingDateCount: dateKeys.length,
      flowerRecordCount: package.flowerCountMaps.length,
      hasBoundary: package.boundaryMap != null,
      photoCount: package.photos.length,
    );

    return ParsedFarmImport(package: package, preview: preview, archive: archive);
  }

  /// Structural/reference validation beyond what
  /// [FarmPackage.fromManifestJson] already checks: required fields on
  /// every post and flower-count record, duplicate ids inside the
  /// package, and flower-count records that don't point at any post in
  /// the same package (spec §14).
  void _validate(FarmPackage package) {
    final farmName = package.farmMap['name'];
    if (farmName is! String || farmName.trim().isEmpty) {
      throw const FarmPackageFormatException();
    }

    final postIds = <String>{};
    for (final map in package.postMaps) {
      final id = map['id'];
      final code = map['post_code'];
      final x = map['position_x'];
      final y = map['position_y'];
      final color = map['color'];
      if (id is! String || code is! String || x is! num || y is! num || color is! String) {
        throw const FarmPackageFormatException();
      }
      if (!postIds.add(id)) {
        throw const FarmPackageFormatException(); // duplicate id inside the package
      }
    }

    for (final map in package.flowerCountMaps) {
      final postId = map['post_id'];
      final date = map['date'];
      final count = map['flower_count'];
      if (postId is! String || date is! String || count is! int) {
        throw const FarmPackageFormatException();
      }
      if (!postIds.contains(postId)) {
        throw const FarmPackageFormatException(); // dangling reference
      }
    }

    final boundaryMap = package.boundaryMap;
    if (boundaryMap != null && boundaryMap['vertices'] is! String) {
      throw const FarmPackageFormatException();
    }
  }

  /// Commits [parsed] as a brand-new, fully independent farm. Every id
  /// (farm, posts, flower counts, boundary, photos) is regenerated
  /// locally — nothing from the sender's device is reused as-is except
  /// the farmer-facing post code (spec §11). The whole write happens
  /// inside one database transaction, so a failure partway through
  /// leaves nothing behind (spec §12). Returns the new farm's id.
  Future<String> saveFarm(ParsedFarmImport parsed) async {
    final package = parsed.package;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();

    final rawName = package.farmMap['name'] as String?;
    final resolvedName =
        await _resolveUniqueName((rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : 'Imported Farm');

    // Original (in-package) post id -> brand-new local post id. Every
    // downstream reference (flower counts, photos) is rewritten through
    // this map rather than ever reusing a sender-side id (spec §11).
    final postIdMap = <String, String>{};
    late final String newFarmId;

    await db.transaction((txn) async {
      final farm = await _farmRepo.createFarm(
        name: resolvedName,
        description: package.farmMap['description'] as String?,
        importedAt: now,
        executor: txn,
      );
      newFarmId = farm.id;

      final newPosts = <Post>[];
      for (final map in package.postMaps) {
        final newId = _uuid.v4();
        postIdMap[map['id'] as String] = newId;
        newPosts.add(Post(
          id: newId,
          farmId: newFarmId,
          postCode: map['post_code'] as String,
          color: PostColorX.fromDb(map['color'] as String),
          positionX: (map['position_x'] as num).toDouble(),
          positionY: (map['position_y'] as num).toDouble(),
          notes: map['notes'] as String?,
          latitude: (map['latitude'] as num?)?.toDouble(),
          longitude: (map['longitude'] as num?)?.toDouble(),
          qrCode: map['qr_code'] as String?,
          createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? now,
          updatedAt: now,
        ));
      }
      await _postRepo.insertPostsBatch(newPosts, executor: txn);

      final boundaryMap = package.boundaryMap;
      if (boundaryMap != null) {
        final boundary = FieldBoundary.fromMap({
          ...boundaryMap,
          'id': _uuid.v4(),
          'farm_id': newFarmId,
        });
        await _boundaryRepo.insertBoundary(boundary, executor: txn);
      }

      final newCounts = <FlowerCount>[];
      for (final map in package.flowerCountMaps) {
        final newPostId = postIdMap[map['post_id'] as String];
        if (newPostId == null) continue; // already rejected by _validate; stay defensive
        newCounts.add(FlowerCount(
          id: _uuid.v4(),
          postId: newPostId,
          date: DateTime.parse(map['date'] as String),
          flowerCount: map['flower_count'] as int,
          countedBy: map['counted_by'] as String?,
          createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? now,
          updatedAt: now,
        ));
      }
      await _flowerRepo.insertBatch(newCounts, executor: txn);

      final newPhotos = <Photo>[];
      for (final photoEntry in package.photos) {
        final newPostId = postIdMap[photoEntry.postId];
        if (newPostId == null) continue;
        final localPath = await _extractPhoto(parsed.archive, photoEntry.archivePath);
        if (localPath == null) continue; // missing/corrupt entry — skip, don't fail the whole import
        newPhotos.add(Photo(
          id: _uuid.v4(),
          postId: newPostId,
          imagePath: localPath,
          createdAt: photoEntry.createdAt,
        ));
      }
      await _photoRepo.insertBatch(newPhotos, executor: txn);
    });

    return newFarmId;
  }

  /// Writes one photo's bytes out of the package archive into this app's
  /// own documents directory under a fresh filename, and returns that new
  /// local path. Never reuses the sender's original imagePath — that path
  /// only ever existed on the sender's device and would point nowhere
  /// (or worse, somewhere wrong) locally.
  Future<String?> _extractPhoto(Archive archive, String archivePath) async {
    ArchiveFile? entry;
    for (final f in archive.files) {
      if (f.name == archivePath) {
        entry = f;
        break;
      }
    }
    if (entry == null || !entry.isFile) return null;

    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'imported_photos'));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final fileName = '${_uuid.v4()}${p.extension(archivePath)}';
    final file = File(p.join(photosDir.path, fileName));
    try {
      await file.writeAsBytes(entry.content as List<int>, flush: true);
    } catch (_) {
      return null;
    }
    return file.path;
  }

  /// "Dragon Farm" -> "Dragon Farm (2)" -> "Dragon Farm (3)"... — never
  /// overwrites or merges with an existing farm of the same name (spec
  /// §13).
  Future<String> _resolveUniqueName(String desired) async {
    final existingNames = (await _farmRepo.getAllFarms()).map((f) => f.name).toSet();
    if (!existingNames.contains(desired)) return desired;
    var n = 2;
    while (existingNames.contains('$desired ($n)')) {
      n++;
    }
    return '$desired ($n)';
  }
}

class ParsedFarmImport {
  final FarmPackage package;
  final FarmImportPreview preview;
  final Archive archive; // kept only to extract photo bytes during saveFarm
  const ParsedFarmImport({required this.package, required this.preview, required this.archive});
}
class FarmImportPreview {
  final String farmName;
  final int treeCount;
  final int countingDateCount;
  final int flowerRecordCount;
  final bool hasBoundary;
  final int photoCount;

  const FarmImportPreview({
    required this.farmName,
    required this.treeCount,
    required this.countingDateCount,
    required this.flowerRecordCount,
    required this.hasBoundary,
    required this.photoCount,
  });
}

/// [File.readAsBytes] actually returns `Uint8List`, but this service only
/// needs list-like access (`.isEmpty`) — this typedef just documents that
/// without pulling in a `dart:typed_data` import purely for an annotation.
typedef Uint8ListLike = List<int>;
