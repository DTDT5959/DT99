class Farm {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set once, at creation, when this farm was created by importing a
  /// .salsfarm package (see FarmImportService) — null for every farm
  /// created locally via "New Farm". Purely a UI indicator (spec §27):
  /// nothing in the app reads this to restrict functionality — an
  /// imported farm is a completely normal, fully-editable farm.
  final DateTime? importedAt;

  /// Not stored directly on the table — populated by the repository via a
  /// COUNT(*) join so list screens don't need a second query per farm.
  final int totalPosts;

  const Farm({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.importedAt,
    this.totalPosts = 0,
  });

  bool get isImported => importedAt != null;

  Farm copyWith({
    String? name,
    String? description,
    DateTime? updatedAt,
    int? totalPosts,
  }) {
    return Farm(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      importedAt: importedAt, // never changes after creation
      totalPosts: totalPosts ?? this.totalPosts,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'imported_at': importedAt?.toIso8601String(),
      };

  factory Farm.fromMap(Map<String, dynamic> map) => Farm(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        importedAt: map['imported_at'] != null ? DateTime.parse(map['imported_at'] as String) : null,
        totalPosts: (map['total_posts'] as int?) ?? 0,
      );
}
