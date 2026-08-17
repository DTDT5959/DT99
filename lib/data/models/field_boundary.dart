import 'dart:convert';
import 'dart:ui';

/// A farm's field boundary: an ordered, open polygon (the last vertex is
/// implicitly connected back to the first when rendering/validating — the
/// first point is never duplicated in storage). Vertices are always world
/// coordinates, the same coordinate space posts use, so boundary and posts
/// never drift relative to each other regardless of zoom/pan/screen size.
class FieldBoundary {
  final String id;
  final String farmId;
  final List<Offset> vertices;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FieldBoundary({
    required this.id,
    required this.farmId,
    required this.vertices,
    required this.createdAt,
    required this.updatedAt,
  });

  FieldBoundary copyWith({List<Offset>? vertices, DateTime? updatedAt}) {
    return FieldBoundary(
      id: id,
      farmId: farmId,
      vertices: vertices ?? this.vertices,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farm_id': farmId,
        'vertices': jsonEncode(vertices.map((v) => {'x': v.dx, 'y': v.dy}).toList()),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory FieldBoundary.fromMap(Map<String, dynamic> map) {
    final raw = jsonDecode(map['vertices'] as String) as List<dynamic>;
    return FieldBoundary(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      vertices: raw
          .map((v) => Offset((v['x'] as num).toDouble(), (v['y'] as num).toDouble()))
          .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
