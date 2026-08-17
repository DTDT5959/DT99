/// The portable "farm package" format used by Farm Sharing — see
/// FarmExportService (builds one) and FarmImportService (reads one). A
/// .salsfarm file is a zip archive containing `manifest.json` (this
/// model, serialized) plus one file per bundled post photo under
/// `photos/`.
///
/// Deliberately just a thin wrapper around plain Maps built from the
/// SAME `toMap()`/`fromMap()` every other model already uses for SQLite —
/// export/import reuses that serialization rather than inventing a
/// second one, and it's already JSON-safe (strings, nums, nulls only).
library;

/// Format/version identifiers stamped into every package. Bump
/// [FarmPackage.currentVersion] whenever the manifest shape changes in a
/// way an older app version couldn't tolerate; [FarmImportService]
/// rejects anything newer than it understands rather than guessing at
/// unfamiliar fields (spec §15-16).
class FarmPackage {
  static const String format = 'SALS_FARM';
  static const int currentVersion = 1;

  final int version;
  final DateTime exportedAt;

  /// Farm.toMap() output — deliberately just the farm's own fields (name,
  /// description, timestamps). No original owner id is ever included;
  /// there isn't one to begin with (spec §2, §24).
  final Map<String, dynamic> farmMap;

  /// FieldBoundary.toMap() output, or null if the farm has no boundary.
  final Map<String, dynamic>? boundaryMap;

  /// One Post.toMap() per tree.
  final List<Map<String, dynamic>> postMaps;

  /// One FlowerCount.toMap() per historical counting record, across every
  /// tree and every date — the full history, never flattened to only the
  /// latest count (spec §18).
  final List<FarmPackagePhoto> photos;
  final List<Map<String, dynamic>> flowerCountMaps;

  const FarmPackage({
    required this.version,
    required this.exportedAt,
    required this.farmMap,
    this.boundaryMap,
    required this.postMaps,
    required this.flowerCountMaps,
    required this.photos,
  });

  Map<String, dynamic> toManifestJson() => {
        'format': format,
        'version': version,
        'exported_at': exportedAt.toIso8601String(),
        'farm': farmMap,
        'boundary': boundaryMap,
        'posts': postMaps,
        'flower_counts': flowerCountMaps,
        'photos': photos.map((p) => p.toMap()).toList(),
      };

  /// Parses a decoded manifest.json. Throws [FarmPackageFormatException]
  /// if [json] isn't a recognizable SALS_FARM manifest (wrong format tag,
  /// missing required fields, wrong types), or
  /// [FarmPackageVersionException] if it's a version newer than this app
  /// understands (spec §14-15). Never throws for a merely-old version or
  /// for missing OPTIONAL fields — see the field-by-field null handling
  /// below (spec §16).
  factory FarmPackage.fromManifestJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const FarmPackageFormatException();
    }
    final versionValue = json['version'];
    if (versionValue is! int) {
      throw const FarmPackageFormatException();
    }
    if (versionValue > currentVersion) {
      throw FarmPackageVersionException(versionValue);
    }

    final farmMap = json['farm'];
    final postsRaw = json['posts'];
    if (farmMap is! Map<String, dynamic> || postsRaw is! List) {
      throw const FarmPackageFormatException();
    }

    final boundaryRaw = json['boundary'];
    final flowerCountsRaw = json['flower_counts'];
    final photosRaw = json['photos'];

    return FarmPackage(
      version: versionValue,
      exportedAt: DateTime.tryParse(json['exported_at'] as String? ?? '') ?? DateTime.now(),
      farmMap: farmMap,
      boundaryMap: boundaryRaw is Map<String, dynamic> ? boundaryRaw : null,
      postMaps: postsRaw.whereType<Map<String, dynamic>>().toList(),
      flowerCountMaps:
          (flowerCountsRaw is List ? flowerCountsRaw : const []).whereType<Map<String, dynamic>>().toList(),
      photos: (photosRaw is List ? photosRaw : const [])
          .whereType<Map<String, dynamic>>()
          .map(FarmPackagePhoto.fromMap)
          .whereType<FarmPackagePhoto>()
          .toList(),
    );
  }
}

/// One bundled photo's metadata inside the package. [postId] is the
/// ORIGINAL (sender-side) post id at export time — FarmImportService
/// remaps it to the newly-created local post id during [saveFarm].
/// [archivePath] is where the actual image bytes live inside the zip
/// (e.g. `photos/<id>.jpg`) — never embedded as base64 in the JSON, so a
/// farm with many photos doesn't inflate the manifest itself.
class FarmPackagePhoto {
  final String postId;
  final String archivePath;
  final DateTime createdAt;

  const FarmPackagePhoto({required this.postId, required this.archivePath, required this.createdAt});

  Map<String, dynamic> toMap() => {
        'post_id': postId,
        'archive_path': archivePath,
        'created_at': createdAt.toIso8601String(),
      };

  /// Returns null (rather than throwing) for a malformed photo entry —
  /// one bad photo record shouldn't sink an otherwise-valid import; the
  /// caller filters nulls out.
  static FarmPackagePhoto? fromMap(Map<String, dynamic> map) {
    final postId = map['post_id'];
    final archivePath = map['archive_path'];
    if (postId is! String || archivePath is! String) return null;
    return FarmPackagePhoto(
      postId: postId,
      archivePath: archivePath,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Calculated, read-only summary of a parsed [FarmPackage] — backs the
/// Import Farm preview screen (spec §9) and the Share Farm confirmation
/// (spec §28). Every number here is derived directly from the package
/// contents, never hard-coded.
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

/// Thrown for any package that isn't a valid, recognizable SALS_FARM
/// manifest — corrupted file, wrong format tag, missing required fields,
/// dangling references, duplicate ids inside the package, and so on (spec
/// §14). Deliberately one generic exception type for all of these: the UI
/// shows the same friendly message either way rather than a stack trace.
class FarmPackageFormatException implements Exception {
  const FarmPackageFormatException();
  @override
  String toString() => 'Unable to import this farm. The file may be damaged or created by an incompatible '
      'version of the app.';
}

/// Thrown specifically when the package's version is newer than this app
/// build understands (spec §15).
class FarmPackageVersionException implements Exception {
  final int foundVersion;
  const FarmPackageVersionException(this.foundVersion);
  @override
  String toString() => 'This farm was shared from a newer version of the app. Update the app to import it.';
}
