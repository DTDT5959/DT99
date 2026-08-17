import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Replaces TransformationController/InteractiveViewer for the farm canvas.
///
/// InteractiveViewer transforms a *bounded* child, which always has an edge
/// somewhere no matter how large that child is made — that's exactly the
/// bug the infinite-plane requirement calls out. CameraController instead
/// tracks a world-space center point + zoom level with no size at all;
/// FarmCanvas paints an infinite green background independent of this
/// state, and positions world content (posts, boundary) using this
/// controller's coordinate math. There is no "edge" to hit because nothing
/// here has a size — panning is just moving where [center] points.
class CameraController extends ChangeNotifier {
  Offset center = Offset.zero;
  double zoom = 1.0;

  static const double minZoom = AppConstants.minCanvasScale;
  static const double maxZoom = AppConstants.maxCanvasScale;

  void setCamera(Offset newCenter, double newZoom) {
    center = newCenter;
    zoom = newZoom.clamp(minZoom, maxZoom);
    notifyListeners();
  }

  /// "Reset View" — per spec, resets ONLY camera position/zoom. Never
  /// touches world data (trees, boundary, coordinates).
  void reset() => setCamera(Offset.zero, 1.0);

  void centerOn(Offset worldPos, {double? zoomLevel}) {
    setCamera(worldPos, zoomLevel ?? zoom);
  }

  /// "Fit Field": centers and zooms so [bounds] (a world-space rect, e.g.
  /// the boundary's bounding box) is fully visible with a comfortable
  /// margin inside [viewportSize]. Works for any polygon shape since it
  /// only depends on the bounding box.
  void fitBounds(Rect bounds, Size viewportSize, {double margin = 60}) {
    final availableW = (viewportSize.width - margin * 2).clamp(50.0, double.infinity);
    final availableH = (viewportSize.height - margin * 2).clamp(50.0, double.infinity);
    final scaleX = availableW / bounds.width;
    final scaleY = availableH / bounds.height;
    final rawScale = scaleX < scaleY ? scaleX : scaleY;
    setCamera(bounds.center, rawScale.isFinite ? rawScale : zoom);
  }

  /// World -> screen. Screen origin (0,0) is the viewport's top-left;
  /// [viewportSize] is that viewport's current size.
  Offset worldToScreen(Offset worldPos, Size viewportSize) {
    final viewportCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
    return viewportCenter + (worldPos - center) * zoom;
  }

  /// Screen -> world, the inverse of [worldToScreen].
  Offset screenToWorld(Offset screenPos, Size viewportSize) {
    final viewportCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
    return center + (screenPos - viewportCenter) / zoom;
  }

  /// The Matrix4 used to paint/hit-test world content — equivalent to
  /// applying [worldToScreen] to every point, expressed as a transform so
  /// it can drive a single `Transform` widget instead of per-widget math.
  Matrix4 matrixFor(Size viewportSize) {
    return Matrix4.identity()
      ..translate(viewportSize.width / 2, viewportSize.height / 2)
      ..scale(zoom)
      ..translate(-center.dx, -center.dy);
  }
}
