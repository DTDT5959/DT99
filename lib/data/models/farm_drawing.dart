import 'dart:ui';

import '../../core/constants/app_constants.dart';

/// A purely visual annotation the farmer draws on top of the farm layout
/// to divide/mark sections — a straight line or a rectangle. This is NOT
/// a tree, NOT the field boundary, NOT a counting area, and has NO
/// database relationship to posts or flower counts: a FarmDrawing exists
/// only to be rendered.
///
/// [startX]/[startY]/[endX]/[endY] are always WORLD coordinates — the
/// same coordinate space Post and FieldBoundary already use — never
/// screen coordinates, so a drawing stays attached to the same spot on
/// the farm regardless of zoom, pan, device, or screen size. For a
/// rectangle, start/end are two opposite corners (order doesn't matter).
class FarmDrawing {
  final String id;
  final String farmId;
  final DrawingType type;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final DateTime createdAt;

  const FarmDrawing({
    required this.id,
    required this.farmId,
    required this.type,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.createdAt,
  });

  Offset get start => Offset(startX, startY);
  Offset get end => Offset(endX, endY);

  Map<String, dynamic> toMap() => {
        'id': id,
        'farm_id': farmId,
        'type': type.dbValue,
        'start_x': startX,
        'start_y': startY,
        'end_x': endX,
        'end_y': endY,
        'created_at': createdAt.toIso8601String(),
      };

  factory FarmDrawing.fromMap(Map<String, dynamic> map) {
    return FarmDrawing(
      id: map['id'] as String,
      farmId: map['farm_id'] as String,
      type: DrawingTypeX.fromDb(map['type'] as String),
      startX: (map['start_x'] as num).toDouble(),
      startY: (map['start_y'] as num).toDouble(),
      endX: (map['end_x'] as num).toDouble(),
      endY: (map['end_y'] as num).toDouble(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
