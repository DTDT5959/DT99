import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/farm_drawing.dart';

/// Renders every saved [FarmDrawing] for the current farm — plain, subtle
/// visual markings only, never confused with the Field Boundary (which
/// has its own distinct brown glow, see FieldBoundaryLayer).
///
/// Sits inside FarmCanvas's world-space Stack (positioned via raw world
/// coordinates, mapped to screen space by FarmCanvas's camera Transform),
/// so a drawing at world position (x, y) lines up exactly with a post at
/// that position with no extra transform math of its own — and stays
/// attached to the same spot on the farm through any zoom/pan.
///
/// Purely visual — no GestureDetector here. FarmCanvas's single top-level
/// GestureDetector does all drawing hit-testing centrally (see
/// _FarmCanvasState._hitTestDrawing), the same centralized architecture
/// used for posts and boundary vertices, so this layer never competes
/// with tree taps/drags for the same touch.
class FarmDrawingLayer extends StatelessWidget {
  final List<FarmDrawing> drawings;

  /// While the Eraser tool is active, the drawing currently under the
  /// farmer's last tap (if any) — drawn with a highlight so it's clear
  /// what's about to be deleted.
  final String? highlightedDrawingId;

  const FarmDrawingLayer({super.key, required this.drawings, this.highlightedDrawingId});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DrawingsPainter(drawings: drawings, highlightedDrawingId: highlightedDrawingId),
        ),
      ),
    );
  }
}

class _DrawingsPainter extends CustomPainter {
  final List<FarmDrawing> drawings;
  final String? highlightedDrawingId;
  _DrawingsPainter({required this.drawings, this.highlightedDrawingId});

  // Subtle blue-grey, clearly visible over the green background but never
  // competing with the tree icons or the boundary's brown — deliberately
  // a different color from FieldBoundaryLayer's boundaryColor so the two
  // are never visually confused (spec: "Painter line/rectangle = visual
  // annotation only").
  static const _color = Color(0xFF37474F);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drawings) {
      final isHighlighted = d.id == highlightedDrawingId;
      final paint = Paint()
        ..color = (isHighlighted ? Colors.redAccent : _color).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 4 : 2.5
        ..strokeCap = StrokeCap.round;

      if (d.type == DrawingType.line) {
        canvas.drawLine(d.start, d.end, paint);
      } else {
        canvas.drawRect(Rect.fromPoints(d.start, d.end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingsPainter oldDelegate) {
    return oldDelegate.drawings != drawings || oldDelegate.highlightedDrawingId != highlightedDrawingId;
  }
}
