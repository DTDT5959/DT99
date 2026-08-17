import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/fruit_calculation_service.dart';
import '../../data/models/post.dart';
import 'camera_controller.dart';
import 'duplicate_group_layer.dart';
import 'field_boundary_layer.dart';
import 'post_marker.dart';
import 'row_placement_layer.dart';

/// The farm layout workspace: an infinite green plane with world-space
/// content (posts, field boundary) drawn on top, panned/zoomed via a
/// manual camera transform.
///
/// CRITICAL ARCHITECTURE NOTE: this widget has no fixed-size Container and
/// no InteractiveViewer. Both of those approaches ultimately transform a
/// *bounded* child, which always has an edge no matter how large. Instead:
///   1. The green background is a plain full-viewport ColoredBox, painted
///      completely independently of [camera] — it can never show an edge
///      because it isn't tied to world coordinates at all.
///   2. The grid is painted in screen space using modulo arithmetic on the
///      camera's position/zoom, so it also has no edge.
///   3. World content (boundary, posts) is positioned using raw world
///      coordinates inside a Stack with `clipBehavior: Clip.none`, wrapped
///      in a `Transform` driven by [camera] — Positioned children can sit
///      at literally any coordinate, arbitrarily far from origin, and
///      still render correctly once panned into view.
/// Reused by the layout editor and the counting/season-view screens so
/// post placement always looks identical.
class FarmCanvas extends StatefulWidget {
  final CameraController camera;
  final List<Post> posts;
  final void Function(Offset worldPosition)? onCanvasTap;
  final void Function(Post post)? onPostTap;
  final void Function(Post post)? onPostLongPress;
  final void Function(Post post)? onDragStart;
  final void Function(Post post, Offset newWorldPosition)? onDragUpdate;
  final void Function(Post post)? onDragEnd;
  final bool postsDraggable;
  final String? selectedPostId;

  // --- Multi-select passthrough (all optional; canvas works exactly as
  // before if none of these are supplied) -------------------------------
  /// Ids currently in the multi-select working group — drawn with the
  /// same selection ring as [selectedPostId].
  final Set<String> selectedPostIds;

  /// True when a tap-drag starting on an already-selected tree should drag
  /// the whole selected group together (EditorTool.select with a non-empty
  /// selection). Mutually exclusive in practice with [postsDraggable].
  final bool groupDragEnabled;
  final VoidCallback? onGroupDragStart;
  final void Function(Offset totalDeltaFromDragStart)? onGroupDragUpdate;
  final VoidCallback? onGroupDragEnd;

  /// True when a drag starting on empty canvas should draw a selection
  /// rectangle instead of panning the camera (EditorTool.select).
  final bool selectionRectEnabled;
  final void Function(Rect worldRect)? onSelectionRectComplete;

  // --- Duplicate Group placement passthrough (all optional) -------------
  /// World positions of every temporary duplicate, recomputed live from
  /// the group's anchor + each member's fixed offset. Non-empty exactly
  /// when Duplicate Placement Mode is active.
  final List<Offset> duplicateGroupPositions;
  final List<PostColor> duplicateGroupColors;
  final List<bool> duplicateGroupValidity;
  final VoidCallback? onDuplicateGroupDragStart;
  final void Function(Offset totalDeltaFromDragStart)? onDuplicateGroupDragUpdate;
  final VoidCallback? onDuplicateGroupDragEnd;

  /// Raw flower counts for the active session, postId -> count. Absent
  /// entries (not yet counted) render identically to a recorded 0 — both
  /// are the Empty tree state, per spec.
  final Map<String, int> flowerCounts;

  /// Which season view to render trees in. Flower View shows the raw
  /// count; Fruit View shows a live-estimated fruit count via
  /// FruitCalculationService — never persisted, recalculated every build.
  final SeasonView seasonView;
  final double fruitSetPercentage;

  // --- Field Boundary passthrough (all optional; canvas works exactly
  // as before if none of these are supplied) ---------------------------
  final List<Offset>? boundaryVertices;
  final List<Offset> draftBoundaryVertices;
  final bool boundaryEditable;
  final void Function(int index)? onBoundaryVertexDragStart;
  final void Function(int index, Offset newWorldPos)? onBoundaryVertexDragUpdate;
  final void Function(int index)? onBoundaryVertexDragEnd;
  final Set<String> outOfBoundsPostIds;

  // --- Tree Row placement passthrough (all optional; canvas works exactly
  // as before if none of these are supplied) ----------------------------
  final Offset? rowHandleStart;
  final Offset? rowHandleEnd;
  final List<Offset> rowPreviewPositions;
  final List<bool> rowPreviewValidity;
  final PostColor rowPreviewColor;
  final void Function(Offset newWorldPos)? onRowStartDragUpdate;
  final void Function(Offset newWorldPos)? onRowEndDragUpdate;

  const FarmCanvas({
    super.key,
    required this.camera,
    required this.posts,
    this.onCanvasTap,
    this.onPostTap,
    this.onPostLongPress,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.postsDraggable = false,
    this.selectedPostId,
    this.selectedPostIds = const {},
    this.groupDragEnabled = false,
    this.onGroupDragStart,
    this.onGroupDragUpdate,
    this.onGroupDragEnd,
    this.selectionRectEnabled = false,
    this.onSelectionRectComplete,
    this.duplicateGroupPositions = const [],
    this.duplicateGroupColors = const [],
    this.duplicateGroupValidity = const [],
    this.onDuplicateGroupDragStart,
    this.onDuplicateGroupDragUpdate,
    this.onDuplicateGroupDragEnd,
    this.flowerCounts = const {},
    this.seasonView = SeasonView.flower,
    this.fruitSetPercentage = FruitCalculationService.defaultFruitSetPercentage,
    this.boundaryVertices,
    this.draftBoundaryVertices = const [],
    this.boundaryEditable = false,
    this.onBoundaryVertexDragStart,
    this.onBoundaryVertexDragUpdate,
    this.onBoundaryVertexDragEnd,
    this.outOfBoundsPostIds = const {},
    this.rowHandleStart,
    this.rowHandleEnd,
    this.rowPreviewPositions = const [],
    this.rowPreviewValidity = const [],
    this.rowPreviewColor = PostColor.yellow,
    this.onRowStartDragUpdate,
    this.onRowEndDragUpdate,
  });

  @override
  State<FarmCanvas> createState() => _FarmCanvasState();
}

/// What the currently-active single-finger drag is acting on, decided once
/// at gesture start by centralized hit-testing (see [_FarmCanvasState._handleScaleStart]).
/// Everything (posts, boundary vertices, row handles, camera pan) is driven
/// through this ONE top-level GestureDetector — no nested per-element
/// GestureDetectors compete with it for the same touch, which is what made
/// dragging unreliable before (a nested Pan recognizer fighting this
/// widget's own Scale recognizer for the same pointer is a losing,
/// unpredictable race in Flutter's gesture arena).
/// What the currently-active single-finger drag is acting on, decided once
/// at gesture start by centralized hit-testing (see [_FarmCanvasState._resolveDragTarget]).
/// Everything (posts, boundary vertices, row handles, camera pan, taps,
/// long-presses) is driven through this ONE top-level GestureDetector — no
/// nested per-element GestureDetectors compete with it for the same touch.
/// That was the root cause of two separate bugs: dragging trees/vertices
/// felt unreliable (nested Pan vs outer Scale), and tapping an existing
/// tree did nothing (the outer detector's own Tap recognizer — wired to
/// onTapUp for "tap empty canvas to add a tree" — was unconditionally
/// firing onCanvasTap for every tap with no hit-test of its own, regardless
/// of what a nested widget's onTap might also have fired for).
enum _DragTarget { none, camera, post, boundaryVertex, rowStart, rowEnd, group, duplicateGroup, selectionRect }

class _FarmCanvasState extends State<FarmCanvas> {
  static const _calculator = FruitCalculationService();

  Offset? _gestureStartFocalWorld;
  double _gestureStartZoom = 1.0;
  Size _lastViewportSize = Size.zero;

  _DragTarget _dragTarget = _DragTarget.none;
  Post? _draggedPost;
  int? _draggedVertexIndex;

  // Group drag (multi-select Move, and Duplicate Group placement) both
  // work the same way: remember the world position under the finger at
  // gesture start, then on every update report the TOTAL delta since then
  // — the provider applies that delta to its own snapshot (selected
  // posts' original positions, or the duplicate group's anchor) rather
  // than us trying to track per-frame deltas here.
  Offset? _groupDragStartWorld;

  // Selection rectangle, tracked in screen space (not world space) since
  // it's a transient UI overlay independent of world content.
  Offset? _selectionRectStartScreen;
  Offset? _selectionRectCurrentScreen;

  /// Screen-space touch tolerance for "did the finger land on this
  /// element", converted to world units so it stays a consistent finger-
  /// width regardless of zoom level. Shared by every hit-test below so tap,
  /// long-press, and drag-start all agree on what counts as "on the tree".
  double _hitRadiusWorld() => 26 / widget.camera.zoom;

  /// Screen -> world conversion, single source of truth used by every
  /// gesture callback (tap, long-press, drag). Verified against the
  /// camera's actual current transform every call — never assumes a
  /// pointer position and a stored world position are directly comparable
  /// without going through this.
  Offset _toWorld(Offset screenPos) => widget.camera.screenToWorld(screenPos, _lastViewportSize);

  /// Finds the post whose world position is under [worldPos], if any.
  /// Iterates every post — never assumes "the last one" or "the newest
  /// one" is the answer.
  Post? _hitTestPost(Offset worldPos) {
    final hitRadius = _hitRadiusWorld();
    for (final post in widget.posts) {
      final dx = worldPos.dx - post.positionX;
      final dy = worldPos.dy - post.positionY;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) return post;
    }
    return null;
  }

  /// Whether [worldPos] lands on any member of the temporary duplicate
  /// group — used to start a group drag from "any part of the group",
  /// per spec §5.
  bool _hitTestDuplicateGroup(Offset worldPos) {
    final hitRadius = _hitRadiusWorld();
    for (final pos in widget.duplicateGroupPositions) {
      final dx = worldPos.dx - pos.dx;
      final dy = worldPos.dy - pos.dy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) return true;
    }
    return false;
  }

  /// Finds the boundary vertex index under [worldPos], if any. Iterates
  /// every vertex — never assumes "the last one" is the answer.
  int? _hitTestBoundaryVertex(Offset worldPos) {
    final vertices = widget.boundaryVertices;
    if (vertices == null) return null;
    final hitRadius = _hitRadiusWorld();
    for (var i = 0; i < vertices.length; i++) {
      if ((worldPos - vertices[i]).distance <= hitRadius) return i;
    }
    return null;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = widget.camera.zoom;
    final worldPos = _toWorld(details.localFocalPoint);
    _gestureStartFocalWorld = worldPos;
    _dragTarget = _resolveDragTarget(worldPos);
    if (_dragTarget == _DragTarget.selectionRect) {
      setState(() {
        _selectionRectStartScreen = details.localFocalPoint;
        _selectionRectCurrentScreen = details.localFocalPoint;
      });
    }
  }

  /// Centralized hit-test for the start of a drag: whatever is literally
  /// closest under the finger wins, in the priority a farmer would expect —
  /// row handles (only relevant during row placement) > boundary vertices
  /// (only when editable) > posts (only when draggable) > falling through
  /// to camera pan/zoom. Each check is skipped entirely when not
  /// applicable, so this costs nothing extra outside those modes.
  _DragTarget _resolveDragTarget(Offset worldPos) {
    final hitRadius = _hitRadiusWorld();

    // Duplicate Group placement takes priority over everything else while
    // active (spec §21) — any touch on any member starts the group drag.
    // Touches elsewhere still fall through to camera pan/zoom below, so
    // the farmer can still navigate to find a placement spot.
    if (widget.duplicateGroupPositions.isNotEmpty && _hitTestDuplicateGroup(worldPos)) {
      _groupDragStartWorld = worldPos;
      widget.onDuplicateGroupDragStart?.call();
      return _DragTarget.duplicateGroup;
    }

    if (widget.rowHandleStart != null && (worldPos - widget.rowHandleStart!).distance <= hitRadius) {
      return _DragTarget.rowStart;
    }
    if (widget.rowHandleEnd != null && (worldPos - widget.rowHandleEnd!).distance <= hitRadius) {
      return _DragTarget.rowEnd;
    }

    if (widget.boundaryEditable) {
      final vertexIndex = _hitTestBoundaryVertex(worldPos);
      if (vertexIndex != null) {
        _draggedVertexIndex = vertexIndex;
        widget.onBoundaryVertexDragStart?.call(vertexIndex);
        return _DragTarget.boundaryVertex;
      }
    }

    // Multi-select group drag: only engages when the drag STARTS on a
    // tree that's actually in the current selection (spec §33) — starting
    // on an unselected tree or empty space falls through to selection-
    // rectangle / camera below instead.
    if (widget.groupDragEnabled) {
      final post = _hitTestPost(worldPos);
      if (post != null && widget.selectedPostIds.contains(post.id)) {
        _groupDragStartWorld = worldPos;
        widget.onGroupDragStart?.call();
        return _DragTarget.group;
      }
    }

    if (widget.postsDraggable) {
      final post = _hitTestPost(worldPos);
      if (post != null) {
        _draggedPost = post;
        widget.onDragStart?.call(post);
        return _DragTarget.post;
      }
    }

    if (widget.selectionRectEnabled) {
      return _DragTarget.selectionRect;
    }

    return _DragTarget.camera;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final worldPos = _toWorld(details.localFocalPoint);
    switch (_dragTarget) {
      case _DragTarget.rowStart:
        widget.onRowStartDragUpdate?.call(worldPos);
        return;
      case _DragTarget.rowEnd:
        widget.onRowEndDragUpdate?.call(worldPos);
        return;
      case _DragTarget.boundaryVertex:
        final idx = _draggedVertexIndex;
        if (idx != null) widget.onBoundaryVertexDragUpdate?.call(idx, worldPos);
        return;
      case _DragTarget.post:
        final post = _draggedPost;
        if (post != null) widget.onDragUpdate?.call(post, worldPos);
        return;
      case _DragTarget.group:
        final start = _groupDragStartWorld;
        if (start != null) widget.onGroupDragUpdate?.call(worldPos - start);
        return;
      case _DragTarget.duplicateGroup:
        final start = _groupDragStartWorld;
        if (start != null) widget.onDuplicateGroupDragUpdate?.call(worldPos - start);
        return;
      case _DragTarget.selectionRect:
        setState(() => _selectionRectCurrentScreen = details.localFocalPoint);
        return;
      case _DragTarget.camera:
      case _DragTarget.none:
        final startWorld = _gestureStartFocalWorld;
        if (startWorld == null) return;
        final newZoom =
            (_gestureStartZoom * details.scale).clamp(CameraController.minZoom, CameraController.maxZoom);
        final viewportCenter = Offset(_lastViewportSize.width / 2, _lastViewportSize.height / 2);
        // Solve for the camera center that keeps `startWorld` under the
        // current focal point at the new zoom — this makes a single-finger
        // drag pan naturally and a pinch zoom stay anchored under your
        // fingers, with the same formula for both.
        final newCenter = startWorld - (details.localFocalPoint - viewportCenter) / newZoom;
        widget.camera.setCamera(newCenter, newZoom);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    switch (_dragTarget) {
      case _DragTarget.boundaryVertex:
        final idx = _draggedVertexIndex;
        if (idx != null) widget.onBoundaryVertexDragEnd?.call(idx);
        break;
      case _DragTarget.post:
        final post = _draggedPost;
        if (post != null) widget.onDragEnd?.call(post);
        break;
      case _DragTarget.group:
        widget.onGroupDragEnd?.call();
        break;
      case _DragTarget.duplicateGroup:
        widget.onDuplicateGroupDragEnd?.call();
        break;
      case _DragTarget.selectionRect:
        final startScreen = _selectionRectStartScreen;
        final endScreen = _selectionRectCurrentScreen;
        if (startScreen != null && endScreen != null) {
          final a = _toWorld(startScreen);
          final b = _toWorld(endScreen);
          widget.onSelectionRectComplete?.call(Rect.fromPoints(a, b));
        }
        setState(() {
          _selectionRectStartScreen = null;
          _selectionRectCurrentScreen = null;
        });
        break;
      case _DragTarget.rowStart:
      case _DragTarget.rowEnd:
      case _DragTarget.camera:
      case _DragTarget.none:
        break;
    }
    _dragTarget = _DragTarget.none;
    _draggedPost = null;
    _draggedVertexIndex = null;
    _groupDragStartWorld = null;
  }

  /// Centralized tap hit-test — this is the fix for "tapping a tree does
  /// nothing". Priority order matches _resolveDragTarget: boundary vertex
  /// (only when editable — reuses the same onBoundaryVertexDragEnd signal
  /// the Add/Delete Point sub-tools already key off of) > post (opens the
  /// existing detail/statistics sheet via the existing onPostTap callback,
  /// with the post's *actual* id — never "posts.last") > empty canvas
  /// (existing add-post-on-tap behavior). Every tree and every vertex goes
  /// through the exact same check, not just the newest one.
  void _handleTapUp(TapUpDetails details) {
    final worldPos = _toWorld(details.localPosition);

    if (widget.boundaryEditable) {
      final vertexIndex = _hitTestBoundaryVertex(worldPos);
      if (vertexIndex != null) {
        widget.onBoundaryVertexDragEnd?.call(vertexIndex);
        return;
      }
    }

    final post = _hitTestPost(worldPos);
    if (post != null) {
      widget.onPostTap?.call(post);
      return;
    }

    widget.onCanvasTap?.call(worldPos);
  }

  /// Centralized long-press hit-test (post history). Only posts respond to
  /// long-press, so this is a single, simple lookup.
  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.onPostLongPress == null) return;
    final post = _hitTestPost(_toWorld(details.localPosition));
    if (post != null) widget.onPostLongPress!(post);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastViewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return AnimatedBuilder(
          animation: widget.camera,
          builder: (context, _) {
            final viewportSize = _lastViewportSize;
            return ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapUp,
                onLongPressStart: _handleLongPressStart,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Layer 1: infinite green plane. Fills the viewport
                    // unconditionally — completely independent of camera
                    // position/zoom, so it can never show an edge.
                    const Positioned.fill(child: ColoredBox(color: Color(0xFFDCEDC8))),
                    // Layer 2: subtle grid, computed in screen space from
                    // camera state so it scrolls seamlessly with no edge.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _InfiniteGridPainter(cameraCenter: widget.camera.center, zoom: widget.camera.zoom),
                      ),
                    ),
                    // Layers 3-4: boundary + trees, in world space via the
                    // camera transform. Positioned children can sit at any
                    // world coordinate, arbitrarily far from origin.
                    Transform(
                      transform: widget.camera.matrixFor(viewportSize),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (widget.boundaryVertices != null || widget.draftBoundaryVertices.isNotEmpty)
                            FieldBoundaryLayer(
                              savedVertices: widget.boundaryVertices,
                              draftVertices: widget.draftBoundaryVertices,
                              editable: widget.boundaryEditable,
                            ),
                          ...widget.posts.map((post) => _buildPost(post)),
                          if (widget.rowHandleStart != null && widget.rowHandleEnd != null)
                            RowPlacementLayer(
                              start: widget.rowHandleStart!,
                              end: widget.rowHandleEnd!,
                              previewPositions: widget.rowPreviewPositions,
                              previewValidity: widget.rowPreviewValidity,
                              color: widget.rowPreviewColor,
                              zoom: widget.camera.zoom,
                            ),
                          if (widget.duplicateGroupPositions.isNotEmpty)
                            DuplicateGroupLayer(
                              positions: widget.duplicateGroupPositions,
                              colors: widget.duplicateGroupColors,
                              validity: widget.duplicateGroupValidity,
                            ),
                        ],
                      ),
                    ),
                    // Layer 5: multi-select marquee, in screen space (not
                    // subject to the world Transform) since it's a
                    // transient UI overlay, not world content.
                    if (_selectionRectStartScreen != null && _selectionRectCurrentScreen != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _SelectionRectPainter(
                              start: _selectionRectStartScreen!,
                              end: _selectionRectCurrentScreen!,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPost(Post post) {
    final flowerCount = widget.flowerCounts[post.id] ?? 0;
    final treeState = _calculator.treeStateFor(flowerCount: flowerCount, view: widget.seasonView);
    final displayCount = _calculator.displayCountFor(
      flowerCount: flowerCount,
      view: widget.seasonView,
      fruitSetPercentage: widget.fruitSetPercentage,
    );

    final marker = PostMarker(
      postCode: post.postCode,
      color: post.color,
      selected: post.id == widget.selectedPostId || widget.selectedPostIds.contains(post.id),
      treeState: treeState,
      displayCount: displayCount,
    );

    final isOutOfBounds = widget.outOfBoundsPostIds.contains(post.id);

    // Purely visual now — no GestureDetector here at all. FarmCanvas's
    // single top-level GestureDetector does all hit-testing centrally
    // (see _hitTestPost / _handleTapUp / _handleLongPressStart /
    // _resolveDragTarget). A nested Tap/Pan recognizer here used to
    // compete with the canvas's own recognizers for the same touch, which
    // is exactly why taps on existing trees were being swallowed and drags
    // felt unreliable — removing it removes the ambiguity entirely.
    return Positioned(
      left: post.positionX - AppConstants.postIconSize / 2,
      top: post.positionY - AppConstants.postIconSize / 2,
      child: isOutOfBounds ? _OutOfBoundsBadge(child: marker) : marker,
    );
  }
}

/// Wraps a post marker with a small warning badge when a boundary edit has
/// left it outside the field — never hides the tree or its data, just
/// flags it so the farmer notices (see "Move Trees Inside" / "Keep
/// Editing" in the layout editor).
class _OutOfBoundsBadge extends StatelessWidget {
  final Widget child;
  const _OutOfBoundsBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          left: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Screen-space marquee rectangle for Multi-Select drag-to-select. Purely
/// visual — FarmCanvas resolves which posts fall inside the equivalent
/// WORLD rect once the drag ends (see _handleScaleEnd / onSelectionRectComplete).
class _SelectionRectPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  _SelectionRectPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()..color = Colors.blueAccent.withValues(alpha: 0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionRectPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

/// Screen-space grid painter — deliberately NOT part of the transformed
/// world Stack. Line positions are computed each frame from the camera's
/// current center/zoom using modulo arithmetic, so the grid scrolls
/// seamlessly with no maximum coordinate and no visible edge, satisfying
/// the same infinite-plane requirement as the green background.
class _InfiniteGridPainter extends CustomPainter {
  final Offset cameraCenter;
  final double zoom;

  _InfiniteGridPainter({required this.cameraCenter, required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    final period = AppConstants.gridSize * zoom;
    if (period < 4) return; // too dense to render meaningfully when zoomed far out

    final paint = Paint()
      ..color = const Color(0xFFAED581).withValues(alpha: 0.35)
      ..strokeWidth = 1;

    final viewportCenter = Offset(size.width / 2, size.height / 2);

    final originScreenX = viewportCenter.dx - cameraCenter.dx * zoom;
    final startX = originScreenX - (originScreenX / period).floorToDouble() * period - period;
    for (double x = startX; x < size.width + period; x += period) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final originScreenY = viewportCenter.dy - cameraCenter.dy * zoom;
    final startY = originScreenY - (originScreenY / period).floorToDouble() * period - period;
    for (double y = startY; y < size.height + period; y += period) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InfiniteGridPainter oldDelegate) {
    return oldDelegate.cameraCenter != cameraCenter || oldDelegate.zoom != zoom;
  }
}
