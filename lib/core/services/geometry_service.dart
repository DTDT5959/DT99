import 'dart:math' as math;
import 'dart:ui';

/// Pure polygon/geometry math for the free-form Field Boundary system.
/// Stateless and dependency-free beyond `Offset`/`Rect`, so it's reusable
/// between the boundary editor UI and the tree-placement constraint logic,
/// and trivially testable in isolation.
class GeometryService {
  const GeometryService();

  /// Ray-casting point-in-polygon test. [vertices] should NOT repeat the
  /// first point at the end — the polygon is treated as implicitly closed
  /// (last vertex connects back to the first).
  bool isPointInPolygon(Offset point, List<Offset> vertices) {
    if (vertices.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      final intersects = ((vi.dy > point.dy) != (vj.dy > point.dy)) &&
          (point.dx < (vj.dx - vi.dx) * (point.dy - vi.dy) / (vj.dy - vi.dy) + vi.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Whether a square tree footprint centered at [center] with half-width
  /// [halfSize] sits FULLY inside the polygon — checked via all 4 corners
  /// plus the center, not just the center point, per the "complete tree
  /// footprint must be inside" requirement.
  bool isFootprintInPolygon(Offset center, double halfSize, List<Offset> vertices) {
    if (vertices.length < 3) return true; // no boundary set => unconstrained
    final corners = <Offset>[
      center,
      Offset(center.dx - halfSize, center.dy - halfSize),
      Offset(center.dx + halfSize, center.dy - halfSize),
      Offset(center.dx - halfSize, center.dy + halfSize),
      Offset(center.dx + halfSize, center.dy + halfSize),
    ];
    return corners.every((c) => isPointInPolygon(c, vertices));
  }

  Rect boundingBox(List<Offset> vertices) {
    final xs = vertices.map((v) => v.dx);
    final ys = vertices.map((v) => v.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  Offset centroid(List<Offset> vertices) {
    double cx = 0, cy = 0;
    for (final v in vertices) {
      cx += v.dx;
      cy += v.dy;
    }
    return Offset(cx / vertices.length, cy / vertices.length);
  }

  /// Grid-aligned spiral search outward from [desired] for the nearest
  /// position whose full tree footprint fits inside the polygon. Falls
  /// back to the polygon centroid (snapped) if nothing is found within
  /// [maxRings] steps — this always terminates.
  Offset nearestValidGridPosition(
    Offset desired,
    List<Offset> vertices, {
    required double gridSize,
    required double footprintHalfSize,
    int maxRings = 80,
  }) {
    if (vertices.length < 3) return desired;

    Offset snap(Offset o) => Offset(
          (o.dx / gridSize).round() * gridSize,
          (o.dy / gridSize).round() * gridSize,
        );

    final start = snap(desired);
    if (isFootprintInPolygon(start, footprintHalfSize, vertices)) return start;

    for (int ring = 1; ring <= maxRings; ring++) {
      for (int dx = -ring; dx <= ring; dx++) {
        for (int dy = -ring; dy <= ring; dy++) {
          if (dx.abs() != ring && dy.abs() != ring) continue; // perimeter of this ring only
          final candidate = Offset(start.dx + dx * gridSize, start.dy + dy * gridSize);
          if (isFootprintInPolygon(candidate, footprintHalfSize, vertices)) {
            return candidate;
          }
        }
      }
    }
    return snap(centroid(vertices));
  }

  /// Index of the polygon edge nearest to [point] — edge i connects
  /// vertices[i] -> vertices[(i+1) % length]. Used by "Add Point" to know
  /// which segment to split; the new vertex is inserted at index i+1.
  int nearestSegmentIndex(Offset point, List<Offset> vertices) {
    double bestDist = double.infinity;
    int bestIndex = 0;
    for (int i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final dist = _distanceToSegment(point, a, b);
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Index of the vertex nearest to [point], for "Delete Point" hit
  /// testing. Returns null if nothing is within [maxDistance].
  int? nearestVertexIndex(Offset point, List<Offset> vertices, {double maxDistance = 32}) {
    double bestDist = double.infinity;
    int? bestIndex;
    for (int i = 0; i < vertices.length; i++) {
      final dist = (vertices[i] - point).distance;
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    if (bestIndex != null && bestDist <= maxDistance) return bestIndex;
    return null;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLenSq == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx) + ((p - a).dy * ab.dy)) / abLenSq;
    final tClamped = t.clamp(0.0, 1.0);
    final projection = Offset(a.dx + ab.dx * tClamped, a.dy + ab.dy * tClamped);
    return (p - projection).distance;
  }

  /// Which posts (by id) fall outside the polygon (footprint not fully
  /// contained) — used after a boundary edit to warn about affected trees.
  /// Returns an empty list when there's no boundary (unconstrained).
  List<String> postsOutsideBoundary(
    List<({String id, double x, double y})> posts,
    List<Offset> vertices, {
    required double footprintHalfSize,
  }) {
    if (vertices.length < 3) return const [];
    return posts
        .where((p) => !isFootprintInPolygon(Offset(p.x, p.y), footprintHalfSize, vertices))
        .map((p) => p.id)
        .toList();
  }
}
