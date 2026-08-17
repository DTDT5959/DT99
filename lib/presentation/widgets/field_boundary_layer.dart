import 'package:flutter/material.dart';

/// Renders the Field Boundary — both the completed polygon (closed, glowing
/// white outline) and, during creation, the in-progress open polyline of
/// tapped points — plus draggable vertex handles while editing.
///
/// Sits inside FarmCanvas's world-space Stack (positioned via raw world
/// coordinates, then mapped to screen space by FarmCanvas's camera
/// Transform), so a vertex at world position (x, y) lines up exactly with
/// a post at that position with no extra transform math of its own.
///
/// Note on the spec's "live preview line to cursor/finger": that's a
/// mouse-hover concept. On a touchscreen there's no continuous pointer
/// position before a tap lands, so this implementation shows the preview
/// line only while the user is actively panning with a finger down (via
/// FarmCanvas's centralized drag handling in creation mode) — on a plain
/// tap-tap-tap flow (the normal mobile case) each point simply appears
/// connected to the last one immediately, which still makes the growing
/// shape fully clear.
class FieldBoundaryLayer extends StatelessWidget {
  final List<Offset>? savedVertices;
  final List<Offset> draftVertices;
  final Offset? livePreviewPoint;
  final bool editable;

  const FieldBoundaryLayer({
    super.key,
    this.savedVertices,
    this.draftVertices = const [],
    this.livePreviewPoint,
    this.editable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BoundaryPainter(
                savedVertices: savedVertices,
                draftVertices: draftVertices,
                livePreviewPoint: livePreviewPoint,
              ),
            ),
          ),
        ),
        // Purely visual handles — no GestureDetector of their own.
        // FarmCanvas's single top-level GestureDetector does all
        // hit-testing (tap AND drag) centrally now (see its
        // _hitTestBoundaryVertex / _handleTapUp / _resolveDragTarget). A
        // nested recognizer here used to compete with the canvas's own
        // recognizers for the same touch — that's what made both dragging
        // feel unreliable and tapping a vertex to select/delete it not
        // register at all.
        if (editable && savedVertices != null)
          for (int i = 0; i < savedVertices!.length; i++)
            Positioned(
              left: savedVertices![i].dx - 14,
              top: savedVertices![i].dy - 14,
              child: IgnorePointer(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF2E7D32), width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _BoundaryPainter extends CustomPainter {
  final List<Offset>? savedVertices;
  final List<Offset> draftVertices;
  final Offset? livePreviewPoint;

  _BoundaryPainter({this.savedVertices, required this.draftVertices, this.livePreviewPoint});

  @override
  void paint(Canvas canvas, Size size) {
    // Completed boundary: closed polygon, white/off-white glow, per spec's
    // "professional agricultural map overlay" look — not a thick wall.
    final saved = savedVertices;
    if (saved != null && saved.length >= 3) {
      final path = Path()..moveTo(saved.first.dx, saved.first.dy);
      for (final v in saved.skip(1)) {
        path.lineTo(v.dx, v.dy);
      }
      path.close();

      // Completed boundary color: natural brown (#795548), clearly visible
      // against the green background without reading as a thick wall.
      const boundaryColor = Color(0xFF795548);

      final glowPaint = Paint()
        ..color = boundaryColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path, glowPaint);

      final linePaint = Paint()
        ..color = boundaryColor.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);
    }

    // In-progress creation: open polyline + point markers, newest point
    // visually distinct so it's obvious where the next tap will connect.
    if (draftVertices.isNotEmpty) {
      final draftPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (int i = 0; i < draftVertices.length - 1; i++) {
        canvas.drawLine(draftVertices[i], draftVertices[i + 1], draftPaint);
      }

      if (livePreviewPoint != null) {
        final previewPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(draftVertices.last, livePreviewPoint!, previewPaint);
      }

      for (int i = 0; i < draftVertices.length; i++) {
        final isNewest = i == draftVertices.length - 1;
        final dotPaint = Paint()..color = isNewest ? const Color(0xFF2E7D32) : Colors.white;
        final ringPaint = Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        final radius = isNewest ? 8.0 : 6.0;
        canvas.drawCircle(draftVertices[i], radius, dotPaint);
        canvas.drawCircle(draftVertices[i], radius, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoundaryPainter oldDelegate) {
    return oldDelegate.savedVertices != savedVertices ||
        oldDelegate.draftVertices != draftVertices ||
        oldDelegate.livePreviewPoint != livePreviewPoint;
  }
}
