import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'post_marker.dart';

/// Renders a temporary [DuplicateGroup] (see LayoutEditorProvider) while
/// the farmer is positioning it — one ghost tree per member, plus a
/// dashed bounding outline so the group reads as one coherent unit.
///
/// Deliberately visually distinct from permanent trees per spec §8: every
/// marker is drawn at reduced opacity with a dashed selection-style
/// outline, so there's no ambiguity that "these trees are being
/// positioned and have not been placed yet." Any member that would fall
/// outside the field boundary is tinted red instead, matching the
/// existing invalid-preview convention used by RowPlacementLayer.
///
/// Purely visual, like RowPlacementLayer/FieldBoundaryLayer — FarmCanvas's
/// single top-level GestureDetector does all hit-testing and dragging
/// centrally (see FarmCanvas._resolveDragTarget), so nothing here carries
/// its own GestureDetector.
class DuplicateGroupLayer extends StatelessWidget {
  final List<Offset> positions;
  final List<PostColor> colors;
  final List<bool> validity;

  const DuplicateGroupLayer({
    super.key,
    required this.positions,
    required this.colors,
    required this.validity,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (positions.length > 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GroupOutlinePainter(positions: positions),
              ),
            ),
          ),
        for (var i = 0; i < positions.length; i++) _buildGhost(i),
      ],
    );
  }

  Widget _buildGhost(int i) {
    final pos = positions[i];
    final valid = i < validity.length ? validity[i] : true;
    final color = i < colors.length ? colors[i] : PostColor.yellow;

    final marker = Opacity(
      opacity: 0.55,
      child: PostMarker(postCode: '+', color: color, treeState: TreeState.empty),
    );

    return Positioned(
      left: pos.dx - AppConstants.postIconSize / 2,
      top: pos.dy - AppConstants.postIconSize / 2,
      child: IgnorePointer(
        child: valid
            ? marker
            : Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  marker,
                  Positioned(
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      child: const Icon(Icons.priority_high, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A loose dashed bounding box around every member's position, purely to
/// visually tie the group together — has no effect on hit-testing.
class _GroupOutlinePainter extends CustomPainter {
  final List<Offset> positions;
  _GroupOutlinePainter({required this.positions});

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;
    const pad = AppConstants.postIconSize;
    double minX = positions.first.dx, maxX = positions.first.dx;
    double minY = positions.first.dy, maxY = positions.first.dy;
    for (final p in positions) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final rect = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    final paint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _drawDashedRect(canvas, rect, paint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft, rect.topLeft];
    for (var i = 0; i < corners.length - 1; i++) {
      _drawDashedLine(canvas, corners[i], corners[i + 1], paint);
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
  bool shouldRepaint(covariant _GroupOutlinePainter oldDelegate) {
    return oldDelegate.positions != positions;
  }
}
