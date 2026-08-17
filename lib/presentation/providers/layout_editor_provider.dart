import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/geometry_service.dart';
import '../../data/models/field_boundary.dart';
import '../../data/models/post.dart';
import '../../data/repositories/field_boundary_repository.dart';
import '../../data/repositories/post_repository.dart';

/// Snapshot of layout state used for undo/redo. Storing full post lists is
/// simple and fast enough at the target scale (≤3,000 posts).
class _LayoutSnapshot {
  final List<Post> posts;
  _LayoutSnapshot(List<Post> source) : posts = List.unmodifiable(source.map((p) => p));
}

/// In-memory draft for "Add Tree Row": just a count/color/line — nothing
/// here is ever persisted. Only the individual Post rows created on
/// confirmation are saved (see LayoutEditorProvider.confirmRowPlacement).
class RowPlacementDraft {
  final int count;
  final PostColor color;
  final Offset start;
  final Offset end;

  const RowPlacementDraft({
    required this.count,
    required this.color,
    required this.start,
    required this.end,
  });

  RowPlacementDraft copyWith({Offset? start, Offset? end}) => RowPlacementDraft(
        count: count,
        color: color,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

/// One tree within a temporary [DuplicateGroup]. [offset] is fixed, in
/// WORLD units, relative to the group's anchor for the group's entire
/// lifetime — dragging the group only ever moves the anchor, so relative
/// spacing between members can never drift or get rearranged (spec §2-3,
/// §6). [color] is copied from the source tree at duplicate-time and is
/// the only thing about that tree this member remembers — no flower/fruit
/// history, no id, nothing else (spec §12-13).
class DuplicateGroupMember {
  final PostColor color;
  final Offset offset;
  const DuplicateGroupMember({required this.color, required this.offset});
}

/// A temporary, purely in-memory group of duplicated trees, created by
/// "Duplicate" on a selection and never written to the database until
/// [LayoutEditorProvider.placeDuplicateGroup] runs (spec §1, §20). A group
/// containing exactly one member is still a valid DuplicateGroup — that's
/// how the single-tree "Duplicate" tool is implemented (spec §17).
class DuplicateGroup {
  final Offset anchor;
  final List<DuplicateGroupMember> members;
  const DuplicateGroup({required this.anchor, required this.members});

  /// Each member's actual world position right now: anchor + its fixed
  /// offset (spec §3).
  List<Offset> get worldPositions => [for (final m in members) anchor + m.offset];
}

class LayoutEditorProvider extends ChangeNotifier {
  final PostRepository _postRepo = PostRepository();
  final FieldBoundaryRepository _boundaryRepo = FieldBoundaryRepository();
  static const _geometry = GeometryService();

  final String farmId;
  LayoutEditorProvider(this.farmId);

  List<Post> _posts = [];
  EditorTool tool = EditorTool.addPost;
  PostColor selectedColor = PostColor.yellow;
  String? selectedPostId;
  bool gridSnap = false;
  bool _loading = false;

  // --- Field Boundary state ------------------------------------------
  FieldBoundary? boundary;
  BoundaryMode boundaryMode = BoundaryMode.none;
  BoundaryEditTool boundaryEditTool = BoundaryEditTool.move;
  List<Offset> draftVertices = [];
  Set<String> outOfBoundsPostIds = {};

  // --- Tree Row placement state ---------------------------------------
  RowPlacementDraft? rowDraft;
  bool get isPlacingRow => rowDraft != null;

  // --- Multi-select state ----------------------------------------------
  // The set of individually-selected tree ids the farmer is currently
  // working with via EditorTool.select (tap-to-toggle or drag-a-rectangle).
  // Every group action (Move/Color/Duplicate/Delete) reads this set — never
  // "the last tree", "the newest tree", or a list index (spec §33).
  Set<String> selectedPostIds = {};
  bool get hasSelection => selectedPostIds.isNotEmpty;

  // In-memory snapshot of where each selected post was standing when the
  // current group-move drag began; see beginGroupMove/updateGroupMove.
  Map<String, Offset>? _groupMoveOriginals;
  bool get isGroupMoving => _groupMoveOriginals != null;

  // --- Duplicate Group placement state ----------------------------------
  DuplicateGroup? duplicateGroup;
  bool get isDuplicatePlacementMode => duplicateGroup != null;

  // Snapshot of the group's anchor when the current group-drag gesture
  // began — see beginDuplicateGroupDrag/updateDuplicateGroupDrag, which
  // mirror _groupMoveOriginals's "always apply the delta to the original
  // snapshot" approach so repeated per-frame deltas can't compound.
  Offset? _duplicateGroupDragStartAnchor;

  final List<_LayoutSnapshot> _undoStack = [];
  final List<_LayoutSnapshot> _redoStack = [];

  List<Post> get posts => _posts;
  bool get loading => _loading;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasBoundary => boundary != null && boundary!.vertices.length >= 3;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _posts = await _postRepo.getPostsForFarm(farmId);
    boundary = await _boundaryRepo.getForFarm(farmId);
    _recomputeOutOfBounds();
    _loading = false;
    notifyListeners();
  }

  void setTool(EditorTool t) {
    tool = t;
    notifyListeners();
  }

  void setSelectedColor(PostColor c) {
    selectedColor = c;
    notifyListeners();
  }

  void toggleGridSnap() {
    gridSnap = !gridSnap;
    notifyListeners();
  }

  double _snap(double v) {
    if (!gridSnap) return v;
    return (v / AppConstants.gridSize).round() * AppConstants.gridSize;
  }

  void _pushUndo() {
    _undoStack.add(_LayoutSnapshot(_posts));
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  Future<void> addPostAt(double x, double y, {String? code, required PostColor color}) async {
    _pushUndo();
    final postCode = code ?? await _postRepo.nextPostCode(farmId);
    final placedAt = _constrainToBoundary(Offset(_snap(x), _snap(y)));
    final post = await _postRepo.createPost(
      farmId: farmId,
      postCode: postCode,
      color: color,
      x: placedAt.dx,
      y: placedAt.dy,
    );
    _posts = [..._posts, post];
    _recomputeOutOfBounds();
    notifyListeners();
  }

  /// Tree Constraint algorithm: if a boundary exists and the desired
  /// footprint isn't fully inside it, find the nearest grid position that
  /// is. With no boundary set, placement is unconstrained (unchanged
  /// pre-boundary-feature behavior).
  Offset _constrainToBoundary(Offset desired) {
    if (!hasBoundary) return desired;
    return _geometry.nearestValidGridPosition(
      desired,
      boundary!.vertices,
      gridSize: AppConstants.gridSize,
      footprintHalfSize: AppConstants.postIconSize / 2,
    );
  }

  Future<void> movePost(String postId, double x, double y) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final updated = _posts[idx].copyWith(positionX: _snap(x), positionY: _snap(y));
    _posts = List.of(_posts)..[idx] = updated;
    notifyListeners();
    await _postRepo.updatePosition(postId, updated.positionX, updated.positionY);
  }

  /// Called once a drag gesture ends: if a boundary exists and the tree's
  /// final footprint isn't fully inside it, snap to the nearest valid grid
  /// position. Deliberately not applied on every drag-update frame (that
  /// would feel jerky) — only once, when the farmer lets go.
  Future<void> finalizePostDrag(String postId) async {
    if (!hasBoundary) return;
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final post = _posts[idx];
    final current = Offset(post.positionX, post.positionY);
    if (_geometry.isFootprintInPolygon(current, AppConstants.postIconSize / 2, boundary!.vertices)) {
      _recomputeOutOfBounds();
      notifyListeners();
      return;
    }
    final safe = _constrainToBoundary(current);
    await movePost(postId, safe.dx, safe.dy);
    _recomputeOutOfBounds();
    notifyListeners();
  }

  /// Called once when a drag gesture starts, so a whole drag is one undo step.
  void beginMove() => _pushUndo();

  Future<void> deletePost(String postId) async {
    _pushUndo();
    _posts = _posts.where((p) => p.id != postId).toList();
    notifyListeners();
    await _postRepo.deletePost(postId);
  }

  Future<void> updatePostDetails(Post post) async {
    _pushUndo();
    await _postRepo.updatePost(post);
    final idx = _posts.indexWhere((p) => p.id == post.id);
    if (idx != -1) {
      _posts = List.of(_posts)..[idx] = post;
      notifyListeners();
    }
  }

  // =====================================================================
  // MULTI-SELECT — tap-to-toggle / drag-a-rectangle, plus the group
  // actions (Move, Color, Duplicate, Delete) that operate on whatever is
  // currently in [selectedPostIds]. See spec §26-37.
  // =====================================================================

  void toggleSelectPost(String postId) {
    final next = Set<String>.of(selectedPostIds);
    if (!next.remove(postId)) next.add(postId);
    selectedPostIds = next;
    notifyListeners();
  }

  void clearSelection() {
    if (selectedPostIds.isEmpty) return;
    selectedPostIds = {};
    notifyListeners();
  }

  /// Marquee selection: every post whose center falls inside [worldRect].
  /// Replaces whatever was selected before — a touch UI has no modifier
  /// key to express "add to selection", so a fresh rectangle drag always
  /// starts a fresh group.
  void selectPostsInRect(Rect worldRect) {
    selectedPostIds = _posts
        .where((p) => worldRect.contains(Offset(p.positionX, p.positionY)))
        .map((p) => p.id)
        .toSet();
    notifyListeners();
  }

  /// Called once when a group-move drag starts, so the whole drag is one
  /// undo step — mirrors [beginMove] for a single tree. Snapshots every
  /// selected post's starting position; [updateGroupMove] always applies
  /// its delta to THIS snapshot, never to the already-moved position, so
  /// repeated frames can't compound drift.
  void beginGroupMove() {
    if (selectedPostIds.isEmpty) return;
    _pushUndo();
    _groupMoveOriginals = {
      for (final p in _posts)
        if (selectedPostIds.contains(p.id)) p.id: Offset(p.positionX, p.positionY),
    };
  }

  /// Applies the SAME [delta] to every selected post (spec §6, adapted for
  /// an already-existing group rather than a fresh duplicate) — relative
  /// spacing between them is therefore preserved automatically.
  void updateGroupMove(Offset delta) {
    final originals = _groupMoveOriginals;
    if (originals == null) return;
    _posts = _posts.map((p) {
      final orig = originals[p.id];
      if (orig == null) return p;
      return p.copyWith(positionX: _snap(orig.dx + delta.dx), positionY: _snap(orig.dy + delta.dy));
    }).toList();
    notifyListeners();
  }

  /// Ends a group-move drag: snaps any post left outside the boundary back
  /// to the nearest valid position (same per-post rule [finalizePostDrag]
  /// already uses for a single tree), then persists every moved position
  /// in one batch write — nothing is written to the database on every
  /// drag frame (spec §35).
  Future<void> finalizeGroupMove() async {
    final originals = _groupMoveOriginals;
    if (originals == null) return;
    _groupMoveOriginals = null;

    if (hasBoundary) {
      for (final id in originals.keys) {
        final idx = _posts.indexWhere((p) => p.id == id);
        if (idx == -1) continue;
        final post = _posts[idx];
        final current = Offset(post.positionX, post.positionY);
        if (!_geometry.isFootprintInPolygon(current, AppConstants.postIconSize / 2, boundary!.vertices)) {
          final safe = _constrainToBoundary(current);
          _posts = List.of(_posts)..[idx] = post.copyWith(positionX: safe.dx, positionY: safe.dy);
        }
      }
    }

    final updates = [
      for (final p in _posts)
        if (originals.containsKey(p.id)) (id: p.id, x: p.positionX, y: p.positionY),
    ];
    await _postRepo.updatePositionsBatch(updates);
    _recomputeOutOfBounds();
    notifyListeners();
  }

  /// "Change Color" group action: updates every selected tree's variety in
  /// one operation, through the existing Post records (never creates new
  /// ones), so id/position/flower history/creation date are all untouched
  /// (spec §27-29, §34). Selection is left unchanged afterward (spec §32).
  Future<void> changeSelectedColor(PostColor color) async {
    if (selectedPostIds.isEmpty) return;
    _pushUndo();
    final updated = <Post>[];
    _posts = _posts.map((p) {
      if (!selectedPostIds.contains(p.id)) return p;
      final np = p.copyWith(color: color);
      updated.add(np);
      return np;
    }).toList();
    notifyListeners();
    await _postRepo.updatePostsBatch(updated);
  }

  /// "Delete" group action: removes every selected tree (and, via the
  /// existing per-post delete path, its history) and clears the selection
  /// since those trees no longer exist (spec §31-32).
  Future<void> deleteSelected() async {
    if (selectedPostIds.isEmpty) return;
    _pushUndo();
    final ids = selectedPostIds.toList();
    _posts = _posts.where((p) => !selectedPostIds.contains(p.id)).toList();
    selectedPostIds = {};
    _recomputeOutOfBounds();
    notifyListeners();
    for (final id in ids) {
      await _postRepo.deletePost(id);
    }
  }

  // =====================================================================
  // DUPLICATE GROUP PLACEMENT
  //
  // "Duplicate" (whether from a multi-select group or the single-tree
  // Duplicate tool — spec §17) never commits anything immediately. It
  // creates a temporary DuplicateGroup, which the farmer drags into place
  // and then explicitly Places or Cancels. See spec §1-25.
  // =====================================================================

  /// Starts Duplicate Placement Mode for the current multi-select.
  void startGroupDuplicate() {
    if (selectedPostIds.isEmpty) return;
    final selected = _posts.where((p) => selectedPostIds.contains(p.id)).toList();
    if (selected.isEmpty) return;
    _beginDuplicateGroupFrom(selected);
  }

  /// Starts Duplicate Placement Mode for a single tapped tree (the
  /// existing "Duplicate" tool) — reuses the exact same group-placement
  /// system with a one-member group (spec §17).
  void startGroupDuplicateForPost(String postId) {
    final source = _posts.where((p) => p.id == postId).toList();
    if (source.isEmpty) return;
    _beginDuplicateGroupFrom(source);
  }

  void _beginDuplicateGroupFrom(List<Post> selected) {
    final cx = selected.map((p) => p.positionX).reduce((a, b) => a + b) / selected.length;
    final cy = selected.map((p) => p.positionY).reduce((a, b) => a + b) / selected.length;
    // Nudge the group off of the originals so it's immediately visible as
    // its own, separately-movable group rather than sitting exactly on
    // top of the source trees (spec §16: originals must never move).
    final anchor = Offset(cx + AppConstants.rowTreeSpacing, cy + AppConstants.rowTreeSpacing);
    final members = [
      for (final p in selected)
        DuplicateGroupMember(color: p.color, offset: Offset(p.positionX - cx, p.positionY - cy)),
    ];
    duplicateGroup = DuplicateGroup(anchor: anchor, members: members);
    notifyListeners();
  }

  /// Called once when a duplicate-group drag starts, snapshotting the
  /// anchor so every subsequent update can apply its delta to a fixed
  /// starting point rather than to an already-moved anchor.
  void beginDuplicateGroupDrag() {
    _duplicateGroupDragStartAnchor = duplicateGroup?.anchor;
  }

  /// Moves the whole temporary group by re-anchoring it to
  /// (drag-start anchor + [totalDeltaFromDragStart]) — every member's
  /// fixed offset is untouched, so relative spacing can never drift
  /// (spec §5-7). In-memory only; nothing is written to the database
  /// while dragging (spec §20).
  void updateDuplicateGroupDrag(Offset totalDeltaFromDragStart) {
    final g = duplicateGroup;
    final startAnchor = _duplicateGroupDragStartAnchor;
    if (g == null || startAnchor == null) return;
    duplicateGroup = DuplicateGroup(anchor: startAnchor + totalDeltaFromDragStart, members: g.members);
    notifyListeners();
  }

  void endDuplicateGroupDrag() {
    _duplicateGroupDragStartAnchor = null;
  }

  List<Offset> get duplicateGroupPositions => duplicateGroup?.worldPositions ?? const [];
  List<PostColor> get duplicateGroupColors =>
      duplicateGroup?.members.map((m) => m.color).toList() ?? const [];

  /// Validates the ENTIRE group against the boundary, per member — never
  /// just the anchor, so a group can't end up half in/half out undetected
  /// (spec §9). No boundary set => everything is valid, matching every
  /// other unconstrained-placement path in this file.
  List<bool> get duplicateGroupValidity {
    final g = duplicateGroup;
    if (g == null) return const [];
    final positions = g.worldPositions;
    if (!hasBoundary) return List.filled(positions.length, true);
    return positions
        .map((p) => _geometry.isFootprintInPolygon(p, AppConstants.postIconSize / 2, boundary!.vertices))
        .toList();
  }

  /// Option B from spec §9: Place stays disabled while any member would
  /// land outside the field, rather than silently dropping members.
  bool get duplicateGroupCanPlace {
    if (duplicateGroup == null) return false;
    return duplicateGroupValidity.every((v) => v);
  }

  /// Discards the temporary group entirely — no database writes, original
  /// trees untouched (spec §14).
  void cancelDuplicateGroup() {
    duplicateGroup = null;
    notifyListeners();
  }

  /// Commits the temporary group: every member becomes a brand-new,
  /// independent Post — new id (never reused/copied), variety preserved,
  /// zero flower/fruit history (a new id simply has none recorded against
  /// it yet — spec §11-13). Originals are never touched. The newly created
  /// trees become the new selection afterward (spec §15, §32).
  Future<int> placeDuplicateGroup() async {
    final g = duplicateGroup;
    if (g == null || !duplicateGroupCanPlace) return 0;
    _pushUndo();
    final positions = g.worldPositions;
    final colors = [for (final m in g.members) m.color];
    final created = await _postRepo.createPostsBatchVaried(farmId: farmId, colors: colors, positions: positions);
    _posts = [..._posts, ...created];
    duplicateGroup = null;
    selectedPostIds = created.map((p) => p.id).toSet();
    _recomputeOutOfBounds();
    notifyListeners();
    return created.length;
  }

  // =====================================================================
  // TREE ROW — "Add Tree Row"
  //
  // Trees are only ever previewed here; nothing touches the database until
  // confirmRowPlacement() runs. The row itself is never a stored entity —
  // it exists only as this in-memory draft, and once confirmed each tree
  // becomes an ordinary, independent Post created via the same
  // repository/undo path as every other post.
  // =====================================================================

  /// Enters Tree Row Placement Mode with a starting horizontal preview line
  /// centered on [viewportCenterWorld], using the farm's existing tree
  /// spacing (AppConstants.gridSize) — never a new hard-coded value.
  void startRowPlacement({
    required int count,
    required PostColor color,
    required Offset viewportCenterWorld,
  }) {
    if (count <= 0) return;
    final halfLength = (count - 1) * AppConstants.rowTreeSpacing / 2;
    rowDraft = RowPlacementDraft(
      count: count,
      color: color,
      start: Offset(viewportCenterWorld.dx - halfLength, viewportCenterWorld.dy),
      end: Offset(viewportCenterWorld.dx + halfLength, viewportCenterWorld.dy),
    );
    notifyListeners();
  }

  void updateRowStart(Offset worldPos) {
    final d = rowDraft;
    if (d == null) return;
    rowDraft = d.copyWith(start: worldPos);
    notifyListeners();
  }

  void updateRowEnd(Offset worldPos) {
    final d = rowDraft;
    if (d == null) return;
    rowDraft = d.copyWith(end: worldPos);
    notifyListeners();
  }

  /// Leaves the farm exactly as it was before row placement began — no DB
  /// writes ever happened, so there's nothing to undo.
  void cancelRowPlacement() {
    rowDraft = null;
    notifyListeners();
  }

  /// The preview tree positions for the current draft, spaced along the
  /// start->end direction using the same grid spacing as every other tree,
  /// and grid-snapped exactly like manually-placed trees when Grid Snap is
  /// on. Purely derived/in-memory — safe to recompute on every drag frame
  /// with no database cost (see spec §16 performance).
  List<Offset> get rowPreviewPositions {
    final d = rowDraft;
    if (d == null) return const [];
    if (d.count == 1) return [Offset(_snap(d.start.dx), _snap(d.start.dy))];

    final delta = d.end - d.start;
    final rawDistance = delta.distance;
    // Degenerate case (start == end, e.g. right after opening the dialog
    // before the user has dragged anything): default to a horizontal row
    // rather than dividing by zero.
    final direction = rawDistance < 1e-6 ? const Offset(1, 0) : delta / rawDistance;
    const spacing = AppConstants.rowTreeSpacing;

    return List.generate(d.count, (i) {
      final raw = d.start + direction * spacing * i.toDouble();
      return Offset(_snap(raw.dx), _snap(raw.dy));
    });
  }

  /// Per-position validity against the existing field boundary — true
  /// (valid) everywhere when there's no boundary set, exactly mirroring
  /// how unconstrained single-tree placement already behaves.
  List<bool> get rowPreviewValidity {
    final positions = rowPreviewPositions;
    if (!hasBoundary) return List.filled(positions.length, true);
    return positions
        .map((p) => _geometry.isFootprintInPolygon(p, AppConstants.postIconSize / 2, boundary!.vertices))
        .toList();
  }

  int get rowValidCount => rowPreviewValidity.where((v) => v).length;

  /// Commits the row: creates one independent Post per in-boundary preview
  /// position (out-of-boundary ones are simply skipped, never silently
  /// placed — see spec §8), as a single undo step. Returns how many trees
  /// were actually created.
  Future<int> confirmRowPlacement() async {
    final d = rowDraft;
    if (d == null) return 0;

    final positions = rowPreviewPositions;
    final validity = rowPreviewValidity;
    final validPositions = [
      for (var i = 0; i < positions.length; i++)
        if (validity[i]) positions[i],
    ];

    if (validPositions.isEmpty) {
      rowDraft = null;
      notifyListeners();
      return 0;
    }

    _pushUndo(); // whole row = one undo step, per spec §11
    final created = await _postRepo.createPostsBatch(
      farmId: farmId,
      color: d.color,
      positions: validPositions,
    );
    _posts = [..._posts, ...created];
    rowDraft = null;
    _recomputeOutOfBounds();
    notifyListeners();
    return created.length;
  }

  /// Undo/redo operate on in-memory state instantly; DB is reconciled after
  /// so the canvas never feels laggy under rapid taps.
  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_LayoutSnapshot(_posts));
    final snap = _undoStack.removeLast();
    _posts = snap.posts;
    notifyListeners();
    await _reconcile();
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_LayoutSnapshot(_posts));
    final snap = _redoStack.removeLast();
    _posts = snap.posts;
    notifyListeners();
    await _reconcile();
  }

  /// Rewrites the posts table to match in-memory state after an undo/redo.
  Future<void> _reconcile() async {
    final current = await _postRepo.getPostsForFarm(farmId);
    final currentIds = current.map((p) => p.id).toSet();
    final targetIds = _posts.map((p) => p.id).toSet();

    for (final id in currentIds.difference(targetIds)) {
      await _postRepo.deletePost(id);
    }
    for (final post in _posts) {
      if (currentIds.contains(post.id)) {
        await _postRepo.updatePost(post);
      }
      // Re-adding a deleted-then-undone post would need INSERT OR REPLACE;
      // out of scope for this snapshot-based undo model at MVP stage.
    }
  }

  Future<void> saveLayout() async {
    // Autosave already persists every change; this exists to give the user
    // an explicit, reassuring "Save Layout" action per the spec.
    notifyListeners();
  }

  // =====================================================================
  // FIELD BOUNDARY — creation
  // =====================================================================

  void startBoundaryCreation() {
    boundaryMode = BoundaryMode.creating;
    draftVertices = [];
    notifyListeners();
  }

  /// Every tap in Boundary Creation Mode adds one vertex, connected to the
  /// previous one. No maximum vertex count.
  void addDraftVertex(Offset worldPos) {
    if (boundaryMode != BoundaryMode.creating) return;
    draftVertices = [...draftVertices, worldPos];
    notifyListeners();
  }

  void cancelBoundaryCreation() {
    boundaryMode = BoundaryMode.none;
    draftVertices = [];
    notifyListeners();
  }

  /// Connects the final point back to the first, closes the polygon, and
  /// saves it. Returns false (without saving) if fewer than 3 points exist
  /// — the caller is expected to surface that as a validation message.
  Future<bool> finishBoundaryCreation() async {
    if (draftVertices.length < 3) return false;
    boundary = await _boundaryRepo.save(farmId, draftVertices);
    draftVertices = [];
    boundaryMode = BoundaryMode.none;
    _recomputeOutOfBounds();
    notifyListeners();
    return true;
  }

  // =====================================================================
  // FIELD BOUNDARY — editing
  // =====================================================================

  void startBoundaryEditing() {
    if (boundary == null) return;
    boundaryMode = BoundaryMode.editing;
    boundaryEditTool = BoundaryEditTool.move;
    notifyListeners();
  }

  void setBoundaryEditTool(BoundaryEditTool t) {
    boundaryEditTool = t;
    notifyListeners();
  }

  void doneEditingBoundary() {
    boundaryMode = BoundaryMode.none;
    notifyListeners();
  }

  /// Live-updates a vertex position while dragging (in-memory only, for
  /// smooth real-time line redraw) — call [commitBoundaryVertexMove] once
  /// the drag ends to persist and re-check affected trees.
  void moveBoundaryVertexLive(int index, Offset newPos) {
    final b = boundary;
    if (b == null || index < 0 || index >= b.vertices.length) return;
    final updated = List<Offset>.of(b.vertices)..[index] = newPos;
    boundary = b.copyWith(vertices: updated);
    notifyListeners();
  }

  Future<void> commitBoundaryVertexMove() async {
    final b = boundary;
    if (b == null) return;
    boundary = await _boundaryRepo.save(farmId, b.vertices);
    _recomputeOutOfBounds();
    notifyListeners();
  }

  /// Inserts a new vertex into the segment at [segmentIndex] (between
  /// vertices[segmentIndex] and vertices[segmentIndex + 1]).
  Future<void> insertBoundaryPoint(int segmentIndex, Offset newPoint) async {
    final b = boundary;
    if (b == null) return;
    final vertices = List<Offset>.of(b.vertices);
    vertices.insert(segmentIndex + 1, newPoint);
    boundary = await _boundaryRepo.save(farmId, vertices);
    notifyListeners();
  }

  /// Deletes a vertex. Refuses if fewer than 3 would remain (a polygon
  /// needs at least 3 points) — returns false in that case.
  Future<bool> deleteBoundaryPoint(int index) async {
    final b = boundary;
    if (b == null) return false;
    if (b.vertices.length <= 3) return false;
    final vertices = List<Offset>.of(b.vertices)..removeAt(index);
    boundary = await _boundaryRepo.save(farmId, vertices);
    _recomputeOutOfBounds();
    notifyListeners();
    return true;
  }

  /// Recomputes which posts now fall outside the current boundary. Never
  /// deletes anything — this only tracks IDs so the UI can warn about them.
  void _recomputeOutOfBounds() {
    final b = boundary;
    if (b == null || b.vertices.length < 3) {
      outOfBoundsPostIds = {};
      return;
    }
    outOfBoundsPostIds = _geometry
        .postsOutsideBoundary(
          _posts.map((p) => (id: p.id, x: p.positionX, y: p.positionY)).toList(),
          b.vertices,
          footprintHalfSize: AppConstants.postIconSize / 2,
        )
        .toSet();
  }

  /// "Move Trees Inside": relocates every currently out-of-bounds post to
  /// its nearest valid grid position. Never deletes tree data.
  Future<void> moveAffectedTreesInside() async {
    final b = boundary;
    if (b == null) return;
    for (final id in outOfBoundsPostIds.toList()) {
      final idx = _posts.indexWhere((p) => p.id == id);
      if (idx == -1) continue;
      final post = _posts[idx];
      final safePos = _geometry.nearestValidGridPosition(
        Offset(post.positionX, post.positionY),
        b.vertices,
        gridSize: AppConstants.gridSize,
        footprintHalfSize: AppConstants.postIconSize / 2,
      );
      await movePost(id, safePos.dx, safePos.dy);
    }
    _recomputeOutOfBounds();
    notifyListeners();
  }

  /// Bounding box of the current boundary, for "Fit Field" — null if no
  /// boundary exists yet.
  Rect? get boundaryBoundingBox {
    final b = boundary;
    if (b == null || b.vertices.length < 3) return null;
    return _geometry.boundingBox(b.vertices);
  }
}
