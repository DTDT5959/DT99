import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Renders the live "Add Tree Row" preview: the direction line, one ghost
/// marker per tree that will be created, and two draggable handles (start
/// and end) that define the row's direction.
///
/// Sits inside FarmCanvas's world-space Stack exactly like
/// [FieldBoundaryLayer] — vertex/handle dragging here uses the same
/// Positioned + GestureDetector pattern FieldBoundaryLayer already uses for
/// its boundary vertex handles, so this introduces no new gesture pattern
/// to the app, just reuses the one already proven to work alongside
/// FarmCanvas's single top-level pan/zoom GestureDetector.
///
/// Nothing drawn here is persisted — nothing here talks to the database at
/// all. It's pure preview until LayoutEditorProvider.confirmRowPlacement()
/// runs.
class RowPlacementLayer extends StatelessWidget {
  final Offset start;
  final Offset end;
  final List<Offset> previewPositions;
  final List<bool> previewValidity;
  final PostColor color;

  /// Needed for painting only now (handle sizing stays constant on screen
  /// regardless of zoom). Dragging itself is centralized in FarmCanvas's
  /// top-level GestureDetector — see its _resolveDragTarget — so these
  /// handles are purely visual and no longer carry their own Pan
  /// recognizer (that used to compete with FarmCanvas's own Scale
  /// recognizer for the same touch and made dragging unreliable).
  final double zoom;

  const RowPlacementLayer({
    super.key,
    required this.start,
    required this.end,
    required this.previewPositions,
    required this.previewValidity,
    required this.color,
    this.zoom = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RowPreviewPainter(
                start: start,
                end: end,
                previewPositions: previewPositions,
                previewValidity: previewValidity,
                color: color.swatch,
              ),
            ),
          ),
        ),
        _handle(isStart: true, position: start),
        _handle(isStart: false, position: end),
      ],
    );
  }

  Widget _handle({required bool isStart, required Offset position}) {
    return Positioned(
      left: position.dx - 16,
      top: position.dy - 16,
      child: IgnorePointer(
        // Purely visual — FarmCanvas's centralized hit-test compares raw
        // touch position against rowHandleStart/End directly, so this
        // widget doesn't need (and shouldn't have) its own GestureDetector.
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.blueAccent, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          alignment: Alignment.center,
          child: Icon(isStart ? Icons.trip_origin : Icons.flag, size: 14, color: Colors.blueAccent),
        ),
      ),
    );
  }
}

class _RowPreviewPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final List<Offset> previewPositions;
  final List<bool> previewValidity;
  final Color color;

  _RowPreviewPainter({
    required this.start,
    required this.end,
    required this.previewPositions,
    required this.previewValidity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Direction line, dashed so it clearly reads as "not yet placed".
    final linePaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    _drawDashedLine(canvas, start, end, linePaint);

    // One ghost marker per tree that will actually be created — plain
    // circles (not full PostMarker/tree art) so they read unmistakably as
    // "preview, not yet real" and stay cheap to draw even for a 100-tree row.
    for (var i = 0; i < previewPositions.length; i++) {
      final pos = previewPositions[i];
      final valid = i < previewValidity.length ? previewValidity[i] : true;
      final fill = Paint()..color = (valid ? color : Colors.redAccent).withValues(alpha: 0.35);
      final ring = Paint()
        ..color = valid ? color : Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final radius = AppConstants.postIconSize / 2.4;
      canvas.drawCircle(pos, radius, fill);
      canvas.drawCircle(pos, radius, ring);
      if (!valid) {
        final tp = TextPainter(
          text: const TextSpan(text: '!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 6.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final direction = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segStart = a + direction * covered;
      final segEnd = a + direction * (covered + dashLength).clamp(0.0, total);
      canvas.drawLine(segStart, segEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _RowPreviewPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.previewPositions != previewPositions ||
        oldDelegate.previewValidity != previewValidity ||
        oldDelegate.color != color;
  }
}
