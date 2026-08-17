import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/post.dart';

/// Read-only, presentation-only visualization of the farm layout using an
/// isometric projection of each post's real (x, y) position — the same
/// positions FarmCanvas uses, just re-projected so the farm reads as a
/// three-dimensional scene instead of a flat map.
///
/// This is deliberately NOT a real 3D engine (no camera, no lighting, no
/// rotation) — that would need a heavy dependency this offline farm app
/// doesn't need. Isometric projection + painter's-algorithm depth sorting
/// gives a convincing "3D farm" feel at negligible cost, so it stays smooth
/// even with thousands of posts. Never used for counting or editing.
class FarmScene3D extends StatelessWidget {
  final List<Post> posts;
  final TransformationController transformController;

  const FarmScene3D({super.key, required this.posts, required this.transformController});

  // Isometric projection: rotate the 2D ground plane ~30° and compress
  // vertically so it reads as a receding floor rather than a flat map.
  static Offset _project(double x, double y) {
    final isoX = (x - y) * 0.86;
    final isoY = (x + y) * 0.5;
    return Offset(isoX, isoY);
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text('No posts to visualize yet', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    // Project every post, then normalize so the whole scene is positioned
    // within a comfortable, centered canvas regardless of farm size/shape.
    final projected = <Post, Offset>{for (final p in posts) p: _project(p.positionX, p.positionY)};
    final xs = projected.values.map((o) => o.dx);
    final ys = projected.values.map((o) => o.dy);
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    const padding = 220.0;
    final sceneWidth = (maxX - minX) + padding * 2;
    final sceneHeight = (maxY - minY) + padding * 2;

    // Painter's algorithm: draw far posts (smaller iso Y) first so nearer
    // posts (larger iso Y) correctly layer on top, matching depth.
    final ordered = posts.toList()
      ..sort((a, b) => projected[a]!.dy.compareTo(projected[b]!.dy));

    return InteractiveViewer(
      transformationController: transformController,
      minScale: 0.3,
      maxScale: 3.0,
      boundaryMargin: const EdgeInsets.all(300),
      child: Container(
        width: sceneWidth,
        height: sceneHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFBFE3C8), Color(0xFF8FBF9A)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: ordered.map((post) {
            final iso = projected[post]!;
            final left = iso.dx - minX + padding;
            final top = iso.dy - minY + padding;
            // Depth-based scale: posts nearer the "camera" (larger iso Y)
            // render slightly bigger, reinforcing the sense of depth.
            final depthT = maxY == minY ? 0.5 : (iso.dy - minY) / (maxY - minY);
            final scale = 0.75 + depthT * 0.55;

            return Positioned(
              left: left,
              top: top,
              child: Transform.translate(
                offset: const Offset(-40, -70),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: _Tree3D(post: post),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Tree3D extends StatelessWidget {
  final Post post;
  const _Tree3D({required this.post});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Soft ground shadow gives each tree visual weight against the
        // isometric ground plane.
        SizedBox(
          width: 80,
          height: 90,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 2,
                child: Container(
                  width: 44,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                child: Image.asset(TreeState.empty.assetPath, width: 80, height: 90, fit: BoxFit.contain),
              ),
              Positioned(
                top: -6,
                right: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: post.color.swatch,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(5)),
          child: Text(
            post.postCode,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
