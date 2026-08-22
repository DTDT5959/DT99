import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/geometry_service.dart';
import '../../../data/models/farm_drawing.dart';
import '../../../data/models/post.dart';
import '../../providers/layout_editor_provider.dart';
import '../../widgets/add_tree_row_sheet.dart';
import '../../widgets/camera_controller.dart';
import '../../widgets/farm_canvas.dart';
import '../../widgets/farm_scene_3d.dart';
import '../../widgets/post_edit_sheet.dart';
import '../history/post_history_screen.dart';

/// The most important screen in the app per the product spec: an infinite
/// green farm workspace where the farmer taps to drop a post icon for
/// every real dragon-fruit post in the field, then can move, duplicate,
/// or delete them — plus the free-form Field Boundary system: a
/// farmer-drawn polygon overlay that constrains where trees can be placed.
///
/// The workspace itself has no edge in any direction (see FarmCanvas /
/// CameraController) — the Field Boundary is just a shape drawn on top of
/// it, never the extent of the canvas itself.
class LayoutEditorScreen extends StatelessWidget {
  final String farmId;
  final String farmName;
  const LayoutEditorScreen({super.key, required this.farmId, required this.farmName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LayoutEditorProvider(farmId)..load(),
      child: _LayoutEditorBody(farmName: farmName),
    );
  }
}

class _LayoutEditorBody extends StatefulWidget {
  final String farmName;
  const _LayoutEditorBody({required this.farmName});

  @override
  State<_LayoutEditorBody> createState() => _LayoutEditorBodyState();
}

class _LayoutEditorBodyState extends State<_LayoutEditorBody> {
  static const _geometry = GeometryService();

  final _camera = CameraController();
  final _transformController3D = TransformationController(); // 3D view is a separate, bounded presentation scene
  ViewMode _viewMode = ViewMode.twoD;

  @override
  void dispose() {
    _camera.dispose();
    _transformController3D.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Canvas tap routing: exactly one of these is active at a time, mirroring
  // the single-active-tool pattern already used for EditorTool. [worldPos]
  // arrives already converted from screen to world coordinates by
  // FarmCanvas — the editor never deals in screen pixels.
  // -------------------------------------------------------------------
  Future<void> _handleCanvasTap(BuildContext context, Offset worldPos) async {
    final provider = context.read<LayoutEditorProvider>();

    // Duplicate Placement Mode owns all interaction while active — the
    // temporary group can only be exited via Place/Cancel (spec §22), so a
    // stray tap elsewhere on the canvas must do nothing.
    if (provider.isDuplicatePlacementMode) return;

    if (provider.tool == EditorTool.select) {
      // Tapping empty canvas while selecting clears the current group,
      // matching the "None of these" convention elsewhere in the app.
      provider.clearSelection();
      return;
    }

    if (provider.boundaryMode == BoundaryMode.creating) {
      provider.addDraftVertex(worldPos);
      return;
    }

    if (provider.boundaryMode == BoundaryMode.editing &&
        provider.boundaryEditTool == BoundaryEditTool.addPoint &&
        provider.hasBoundary) {
      final segmentIndex = _geometry.nearestSegmentIndex(worldPos, provider.boundary!.vertices);
      await provider.insertBoundaryPoint(segmentIndex, worldPos);
      return;
    }

    if (provider.boundaryMode != BoundaryMode.none) return; // editing/creating: no post placement

    if (provider.isPlacingRow) return; // row placement is driven by the row handles, not canvas taps

    if (provider.tool != EditorTool.addPost) return;

    final code = await _peekNextCode(context);
    final result = await showPostEditSheet(
      context,
      initialCode: code,
      initialColor: provider.selectedColor,
    );
    if (result == null) return;
    await provider.addPostAt(worldPos.dx, worldPos.dy, code: result.postCode, color: result.color);
  }

  Future<String> _peekNextCode(BuildContext context) async {
    final n = context.read<LayoutEditorProvider>().posts.length + 1;
    final letterIndex = (n - 1) ~/ 99;
    final number = ((n - 1) % 99) + 1;
    final letter = String.fromCharCode('A'.codeUnitAt(0) + letterIndex);
    return '$letter-${number.toString().padLeft(2, '0')}';
  }

  Future<void> _handlePostTap(BuildContext context, Post post) async {
    final provider = context.read<LayoutEditorProvider>();
    if (provider.isDuplicatePlacementMode) return; // temporary group owns interaction (spec §22)
    if (provider.boundaryMode != BoundaryMode.none) return;
    if (provider.isPlacingRow) return;
    switch (provider.tool) {
      case EditorTool.select:
        provider.toggleSelectPost(post.id);
        break;
      case EditorTool.delete:
        _confirmDeletePost(context, post);
        break;
      case EditorTool.duplicate:
        // Single-tree duplicate now goes through Duplicate Group Placement
        // too — a group of one is still a valid DuplicateGroup (spec §17).
        provider.startGroupDuplicateForPost(post.id);
        break;
      case EditorTool.move:
      case EditorTool.addPost:
        final result = await showPostEditSheet(
          context,
          initialCode: post.postCode,
          initialColor: post.color,
          initialNotes: post.notes,
        );
        if (result == null) return;
        await provider.updatePostDetails(
          post.copyWith(postCode: result.postCode, color: result.color, notes: result.notes),
        );
        break;
      case EditorTool.addRow:
        // Row placement is driven entirely by isPlacingRow/rowDraft, not by
        // `tool` — this case can't actually be reached (see guard above),
        // but is required for an exhaustive switch now that the enum has
        // this value.
        break;
    }
  }

  // -------------------------------------------------------------------
  // Multi-select group actions (spec §26-37)
  // -------------------------------------------------------------------
  Future<void> _changeSelectedColor(BuildContext context, LayoutEditorProvider provider) async {
    final color = await showModalBottomSheet<PostColor>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Change Color', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${provider.selectedPostIds.length} tree${provider.selectedPostIds.length == 1 ? '' : 's'} selected',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...PostColor.values.map(
                (c) => ListTile(
                  leading: Icon(Icons.circle, color: c.swatch, size: 22),
                  title: Text(c.label),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (color == null) return;
    await provider.changeSelectedColor(color);
  }

  Future<void> _deleteSelected(BuildContext context, LayoutEditorProvider provider) async {
    final count = provider.selectedPostIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected trees?'),
        content: Text('Remove $count tree${count == 1 ? '' : 's'} and all of their history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.deleteSelected();
  }

  void _confirmDeletePost(BuildContext context, Post post) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text('Remove post ${post.postCode} and all of its history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<LayoutEditorProvider>().deletePost(post.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Boundary vertex interaction (move / delete sub-tools)
  // -------------------------------------------------------------------
  void _onVertexDragStart(BuildContext context, int index) {
    // No dedicated undo step for boundary edits (undo/redo tracks tree
    // layout only) — dragging is safe to do freely since it can always be
    // dragged back, and every drop is validated against affected trees.
  }

  void _onVertexDragUpdate(BuildContext context, int index, Offset newPos) {
    final provider = context.read<LayoutEditorProvider>();
    if (provider.boundaryEditTool != BoundaryEditTool.move) return;
    provider.moveBoundaryVertexLive(index, newPos);
  }

  Future<void> _onVertexDragEnd(BuildContext context, int index) async {
    final provider = context.read<LayoutEditorProvider>();
    if (provider.boundaryEditTool == BoundaryEditTool.move) {
      await provider.commitBoundaryVertexMove();
      if (provider.outOfBoundsPostIds.isNotEmpty && context.mounted) {
        _showOutOfBoundsDialog(context, provider);
      }
    } else if (provider.boundaryEditTool == BoundaryEditTool.deletePoint) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete boundary point?'),
          content: const Text('This removes this vertex from the field boundary.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final ok = await provider.deleteBoundaryPoint(index);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A field boundary needs at least 3 points')),
        );
      } else if (context.mounted && provider.outOfBoundsPostIds.isNotEmpty) {
        _showOutOfBoundsDialog(context, provider);
      }
    }
  }

  void _showOutOfBoundsDialog(BuildContext context, LayoutEditorProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Some trees are now outside the field'),
        content: Text(
          '${provider.outOfBoundsPostIds.length} tree(s) fall outside the updated boundary. '
          "They haven't been deleted — choose how to resolve this.",
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () async {
              await provider.moveAffectedTreesInside();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Move Trees Inside'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Boundary creation flow
  // -------------------------------------------------------------------
  Future<void> _finishBoundary(BuildContext context, LayoutEditorProvider provider) async {
    if (provider.draftVertices.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 3 points to finish the boundary')),
      );
      return;
    }
    await provider.finishBoundaryCreation();
    if (context.mounted && provider.outOfBoundsPostIds.isNotEmpty) {
      _showOutOfBoundsDialog(context, provider);
    }
  }

  // -------------------------------------------------------------------
  // Tree Row flow: dialog for count/variety, then drag-to-position on the
  // canvas, then confirm/cancel. Mirrors the shape of the boundary-creation
  // flow above (dialog/snackbar -> provider mutation -> optional follow-up
  // dialog), just for a different existing subsystem (posts, not boundary).
  // -------------------------------------------------------------------
  Future<void> _startAddTreeRow(BuildContext context, LayoutEditorProvider provider) async {
    final result = await showAddTreeRowSheet(context, initialColor: provider.selectedColor);
    if (result == null || !context.mounted) return;
    provider.startRowPlacement(
      count: result.count,
      color: result.color,
      viewportCenterWorld: _camera.center,
    );
  }

  Future<void> _confirmTreeRow(BuildContext context, LayoutEditorProvider provider) async {
    final draft = provider.rowDraft;
    if (draft == null) return;
    final total = draft.count;
    final valid = provider.rowValidCount;

    if (valid < total) {
      if (valid == 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Some trees are outside the field boundary'),
            content: const Text(
              'None of the trees in this position are inside the field. Drag the row to reposition it, or cancel.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Positioning')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  provider.cancelRowPlacement();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel Row'),
              ),
            ],
          ),
        );
        return;
      }

      final placeValid = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some trees are outside the field boundary'),
          content: Text('$valid of $total trees are inside the field. The other ${total - valid} would fall outside it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Reposition')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Place $valid Valid Trees'),
            ),
          ],
        ),
      );
      if (placeValid != true) return; // user chose to keep repositioning
    }

    final created = await provider.confirmRowPlacement();
    if (context.mounted && created > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $created tree${created == 1 ? '' : 's'}')),
      );
    }
  }

  // -------------------------------------------------------------------
  // Duplicate Group placement flow (spec §1-25): Place commits every
  // temporary member as a brand-new, independent Post; Cancel discards the
  // group entirely with no database writes either way.
  // -------------------------------------------------------------------
  Future<void> _placeDuplicateGroup(BuildContext context, LayoutEditorProvider provider) async {
    final created = await provider.placeDuplicateGroup();
    if (context.mounted && created > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Placed $created tree${created == 1 ? '' : 's'}')),
      );
    }
  }

  /// Guards leaving the screen (or otherwise navigating away) while a
  /// temporary duplicate group is still unplaced (spec §22).
  Future<bool> _confirmDiscardDuplicateGroup(BuildContext context, LayoutEditorProvider provider) async {
    if (!provider.isDuplicatePlacementMode) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Place duplicated trees before leaving?'),
        content: const Text('The duplicated trees haven\'t been placed yet and will be discarded.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continue Editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) {
      provider.cancelDuplicateGroup();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Farm Layout Painter (spec: Line, Rectangle, Eraser, Undo, Done).
  // -------------------------------------------------------------------
  Future<void> _handleDrawComplete(
    BuildContext context,
    LayoutEditorProvider provider,
    DrawingType type,
    Offset worldStart,
    Offset worldEnd,
  ) async {
    await provider.addDrawing(type, worldStart, worldEnd);
  }

  /// Eraser tool: highlight first, then confirm before deleting — mirrors
  /// the tap-to-confirm-delete pattern already used for trees
  /// (_confirmDeletePost) rather than inventing a new interaction.
  Future<void> _handleDrawingTap(
    BuildContext context,
    LayoutEditorProvider provider,
    FarmDrawing drawing,
  ) async {
    provider.highlightDrawing(drawing.id);
    final label = drawing.type == DrawingType.line ? 'line' : 'rectangle';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete this $label?'),
        content: const Text('This removes only this drawing — trees, boundary, and counting data are unaffected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteDrawing(drawing.id);
    } else {
      provider.highlightDrawing(null);
    }
  }

  // -------------------------------------------------------------------
  // Fit Field: moves/zooms the CAMERA ONLY so the whole boundary is
  // visible — never resizes or affects the underlying infinite workspace.
  // Works for any polygon shape since it only uses the bounding box.
  // -------------------------------------------------------------------
  void _fitField(BuildContext context, LayoutEditorProvider provider) {
    final bbox = provider.boundaryBoundingBox;
    if (bbox == null) return;
    // Approximate viewport size (screen minus known chrome); FarmCanvas
    // measures its exact size internally for rendering, but this estimate
    // is comfortably within the margin fitBounds already applies.
    final size = MediaQuery.of(context).size;
    const chromeHeight = 260.0;
    _camera.fitBounds(bbox, Size(size.width, size.height - chromeHeight));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LayoutEditorProvider>();
    return PopScope(
      canPop: !provider.isDuplicatePlacementMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscardDuplicateGroup(context, context.read<LayoutEditorProvider>());
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.farmName),
        actions: [
          
            //removed 3d and 2d 
          if (_viewMode == ViewMode.twoD) ...[
            Consumer<LayoutEditorProvider>(
              builder: (context, p, __) => IconButton(
                tooltip: p.gridSnap ? 'Grid snap: on' : 'Grid snap: off',
                icon: Icon(p.gridSnap ? Icons.grid_on : Icons.grid_off),
                onPressed: p.toggleGridSnap,
              ),
            ),
            IconButton(
              tooltip: 'Reset View',
              icon: const Icon(Icons.my_location),
              onPressed: _camera.reset,
            ),
          ],
        ],
      ),
      body: Consumer<LayoutEditorProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewMode == ViewMode.threeD) {
            return Column(
              children: [
                _ThreeDBanner(count: provider.posts.length),
                Expanded(
                  child: FarmScene3D(
                    posts: provider.posts,
                    transformController: _transformController3D,
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              _StatusBar(
                count: provider.posts.length,
                boundaryMode: provider.boundaryMode,
                rowDraft: provider.rowDraft,
                rowValidCount: provider.rowValidCount,
                isDuplicatePlacementMode: provider.isDuplicatePlacementMode,
                duplicateGroupTotal: provider.duplicateGroupPositions.length,
                duplicateGroupValidCount: provider.duplicateGroupValidity.where((v) => v).length,
                isSelecting: provider.tool == EditorTool.select,
                selectedCount: provider.selectedPostIds.length,
              ),
              Expanded(
                child: FarmCanvas(
                  camera: _camera,
                  posts: provider.posts,
                  postsDraggable: provider.tool == EditorTool.move &&
                      provider.boundaryMode == BoundaryMode.none &&
                      !provider.isPlacingRow &&
                      !provider.isDuplicatePlacementMode &&
                      provider.painterMode == PainterMode.off,
                  onCanvasTap: (worldPos) => _handleCanvasTap(context, worldPos),
                  onPostTap: (post) => _handlePostTap(context, post),
                  onPostLongPress: provider.boundaryMode == BoundaryMode.none &&
                          !provider.isDuplicatePlacementMode &&
                          provider.painterMode == PainterMode.off
                      ? (post) => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PostHistoryScreen(postId: post.id)),
                          )
                      : null,
                  onDragStart: (post) => provider.beginMove(),
                  onDragUpdate: (post, newPos) => provider.movePost(post.id, newPos.dx, newPos.dy),
                  onDragEnd: (post) => provider.finalizePostDrag(post.id),
                  boundaryVertices: provider.boundary?.vertices,
                  draftBoundaryVertices: provider.draftVertices,
                  boundaryEditable: provider.painterMode == PainterMode.off && provider.boundaryMode == BoundaryMode.editing,
                  onBoundaryVertexDragStart: (i) => _onVertexDragStart(context, i),
                  onBoundaryVertexDragUpdate: (i, pos) => _onVertexDragUpdate(context, i, pos),
                  onBoundaryVertexDragEnd: (i) => _onVertexDragEnd(context, i),
                  outOfBoundsPostIds: provider.outOfBoundsPostIds,
                  rowHandleStart: provider.rowDraft?.start,
                  rowHandleEnd: provider.rowDraft?.end,
                  rowPreviewPositions: provider.rowPreviewPositions,
                  rowPreviewValidity: provider.rowPreviewValidity,
                  rowPreviewColor: provider.rowDraft?.color ?? provider.selectedColor,
                  onRowStartDragUpdate: provider.updateRowStart,
                  onRowEndDragUpdate: provider.updateRowEnd,
                  // --- Multi-select ---
                  selectedPostIds: provider.selectedPostIds,
                  groupDragEnabled: provider.tool == EditorTool.select &&
                      provider.hasSelection &&
                      provider.boundaryMode == BoundaryMode.none &&
                      !provider.isPlacingRow &&
                      !provider.isDuplicatePlacementMode &&
                      provider.painterMode == PainterMode.off,
                  onGroupDragStart: provider.beginGroupMove,
                  onGroupDragUpdate: provider.updateGroupMove,
                  onGroupDragEnd: provider.finalizeGroupMove,
                  selectionRectEnabled: provider.tool == EditorTool.select &&
                      provider.boundaryMode == BoundaryMode.none &&
                      !provider.isPlacingRow &&
                      !provider.isDuplicatePlacementMode &&
                      provider.painterMode == PainterMode.off,
                  onSelectionRectComplete: provider.selectPostsInRect,
                  // --- Duplicate Group placement ---
                  duplicateGroupPositions: provider.duplicateGroupPositions,
                  duplicateGroupColors: provider.duplicateGroupColors,
                  duplicateGroupValidity: provider.duplicateGroupValidity,
                  onDuplicateGroupDragStart: provider.beginDuplicateGroupDrag,
                  onDuplicateGroupDragUpdate: provider.updateDuplicateGroupDrag,
                  onDuplicateGroupDragEnd: provider.endDuplicateGroupDrag,
                  // --- Farm Layout Painter ---
                  drawings: provider.drawings,
                  activeDrawingTool: provider.painterMode == PainterMode.line
                      ? DrawingType.line
                      : provider.painterMode == PainterMode.rectangle
                          ? DrawingType.rectangle
                          : null,
                  onDrawComplete: (type, start, end) => _handleDrawComplete(context, provider, type, start, end),
                  eraseDrawingMode: provider.painterMode == PainterMode.erase,
                  onDrawingTap: (drawing) => _handleDrawingTap(context, provider, drawing),
                  highlightedDrawingId: provider.highlightedDrawingId,
                ),
              ),
              _EditorToolbar(
                onFinishBoundary: () => _finishBoundary(context, provider),
                onFitField: () => _fitField(context, provider),
                onAddTreeRow: () => _startAddTreeRow(context, provider),
                onConfirmTreeRow: () => _confirmTreeRow(context, provider),
                onPlaceDuplicateGroup: () => _placeDuplicateGroup(context, provider),
                onChangeSelectedColor: () => _changeSelectedColor(context, provider),
                onDeleteSelected: () => _deleteSelected(context, provider),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThreeDBanner extends StatelessWidget {
  final int count;
  const _ThreeDBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.park, size: 18),
          const SizedBox(width: 8),
          Text('$count posts · 3D view (read-only)', style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            'For layout & counting, switch back to 2D',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final int count;
  final BoundaryMode boundaryMode;
  final RowPlacementDraft? rowDraft;
  final int rowValidCount;
  final bool isDuplicatePlacementMode;
  final int duplicateGroupTotal;
  final int duplicateGroupValidCount;
  final bool isSelecting;
  final int selectedCount;
  const _StatusBar({
    required this.count,
    required this.boundaryMode,
    this.rowDraft,
    this.rowValidCount = 0,
    this.isDuplicatePlacementMode = false,
    this.duplicateGroupTotal = 0,
    this.duplicateGroupValidCount = 0,
    this.isSelecting = false,
    this.selectedCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon = Icons.local_florist;
    final draft = rowDraft;
    if (isDuplicatePlacementMode) {
      icon = Icons.copy_all;
      message = 'Place duplicated trees · $duplicateGroupTotal tree${duplicateGroupTotal == 1 ? '' : 's'}'
          '${duplicateGroupValidCount < duplicateGroupTotal ? ' · some outside the field' : ''}';
    } else if (draft != null) {
      message = 'Place Tree Row · ${draft.count} trees · ${draft.color.label}'
          '${rowValidCount < draft.count ? ' · $rowValidCount inside field' : ''}';
    } else if (isSelecting) {
      icon = Icons.check_box_outlined;
      message = selectedCount == 0
          ? 'Tap trees or drag to select'
          : '$selectedCount tree${selectedCount == 1 ? '' : 's'} selected';
    } else {
      switch (boundaryMode) {
        case BoundaryMode.creating:
          icon = Icons.hexagon_outlined;
          message = 'Tap to place boundary points · at least 3 needed';
          break;
        case BoundaryMode.editing:
          icon = Icons.hexagon_outlined;
          message = 'Editing field boundary';
          break;
        case BoundaryMode.none:
          message = '$count posts placed';
          break;
      }
    }
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            'Pinch to zoom · Drag to pan · Infinite workspace',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  final VoidCallback onFinishBoundary;
  final VoidCallback onFitField;
  final VoidCallback onAddTreeRow;
  final VoidCallback onConfirmTreeRow;
  final VoidCallback onPlaceDuplicateGroup;
  final VoidCallback onChangeSelectedColor;
  final VoidCallback onDeleteSelected;
  const _EditorToolbar({
    required this.onFinishBoundary,
    required this.onFitField,
    required this.onAddTreeRow,
    required this.onConfirmTreeRow,
    required this.onPlaceDuplicateGroup,
    required this.onChangeSelectedColor,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LayoutEditorProvider>(
      builder: (context, provider, _) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2)),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buttonsFor(context, provider)),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buttonsFor(BuildContext context, LayoutEditorProvider provider) {
    // Only show controls relevant to the current mode, per spec, so the
    // toolbar doesn't get overcrowded.

    // Duplicate Placement Mode is the most exclusive mode in the editor —
    // it can only be exited via Place or Cancel (spec §22) — so it takes
    // priority over everything else, including a lingering multi-select.
    if (provider.isDuplicatePlacementMode) {
      final total = provider.duplicateGroupPositions.length;
      final valid = provider.duplicateGroupValidity.where((v) => v).length;
      return [
        _ToolButton(
          icon: Icons.check_circle,
          label: valid == total ? 'Place' : 'Place ($valid/$total)',
          enabled: provider.duplicateGroupCanPlace,
          onTap: onPlaceDuplicateGroup,
        ),
        _ToolButton(icon: Icons.close, label: 'Cancel', onTap: provider.cancelDuplicateGroup),
      ];
    }

    // Farm Layout Painter owns the toolbar exclusively while active — same
    // priority tier as Duplicate Group placement above, and checked before
    // multi-select/row/boundary so none of those can be entered mid-draw.
    if (provider.painterMode != PainterMode.off) {
      return [
        _ToolButton(
          icon: Icons.show_chart,
          label: 'Line',
          active: provider.painterMode == PainterMode.line,
          onTap: () => provider.setPainterMode(PainterMode.line),
        ),
        _ToolButton(
          icon: Icons.crop_square,
          label: 'Rectangle',
          active: provider.painterMode == PainterMode.rectangle,
          onTap: () => provider.setPainterMode(PainterMode.rectangle),
        ),
        _ToolButton(
          icon: Icons.auto_fix_normal_outlined,
          label: 'Eraser',
          active: provider.painterMode == PainterMode.erase,
          onTap: () => provider.setPainterMode(PainterMode.erase),
        ),
        _ToolButton(
          icon: Icons.undo,
          label: 'Undo',
          enabled: provider.canUndoDrawing,
          onTap: provider.undoLastDrawing,
        ),
        _ToolButton(icon: Icons.check, label: 'Done', onTap: () => provider.setPainterMode(PainterMode.off)),
      ];
    }

    // A non-empty multi-select group gets its own action bar — Color,
    // Duplicate, and Delete all act on selectedPostIds as a whole (spec
    // §26-37) no matter which tool is active. Move happens by dragging a
    // selected tree while the Select tool is active (see FarmCanvas
    // groupDragEnabled) — the Move button here is just a hint for that.
    if (provider.hasSelection) {
      final count = provider.selectedPostIds.length;
      return [
        _ToolButton(
          icon: Icons.open_with,
          label: 'Move',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drag any selected tree to move the whole group')),
          ),
        ),
        _ToolButton(icon: Icons.palette_outlined, label: 'Color', onTap: onChangeSelectedColor),
        _ToolButton(icon: Icons.copy_all, label: 'Duplicate', onTap: provider.startGroupDuplicate),
        _ToolButton(icon: Icons.delete_outline, label: 'Delete', onTap: onDeleteSelected),
        _ToolButton(icon: Icons.close, label: '$count Selected', onTap: provider.clearSelection),
      ];
    }

    if (provider.isPlacingRow) {
      final total = provider.rowDraft!.count;
      final valid = provider.rowValidCount;
      return [
        _ToolButton(
          icon: Icons.check_circle,
          label: valid == total ? 'Confirm' : 'Confirm ($valid/$total)',
          onTap: onConfirmTreeRow,
        ),
        _ToolButton(icon: Icons.close, label: 'Cancel', onTap: provider.cancelRowPlacement),
      ];
    }

    if (provider.boundaryMode == BoundaryMode.creating) {
      return [
        _ToolButton(icon: Icons.check_circle, label: 'Finish Boundary', onTap: onFinishBoundary),
        _ToolButton(icon: Icons.close, label: 'Cancel', onTap: provider.cancelBoundaryCreation),
      ];
    }

    if (provider.boundaryMode == BoundaryMode.editing) {
      return [
        _ToolButton(
          icon: Icons.open_with,
          label: 'Move',
          active: provider.boundaryEditTool == BoundaryEditTool.move,
          onTap: () => provider.setBoundaryEditTool(BoundaryEditTool.move),
        ),
        _ToolButton(
          icon: Icons.add_circle_outline,
          label: 'Add Point',
          active: provider.boundaryEditTool == BoundaryEditTool.addPoint,
          onTap: () => provider.setBoundaryEditTool(BoundaryEditTool.addPoint),
        ),
        _ToolButton(
          icon: Icons.remove_circle_outline,
          label: 'Delete Point',
          active: provider.boundaryEditTool == BoundaryEditTool.deletePoint,
          onTap: () => provider.setBoundaryEditTool(BoundaryEditTool.deletePoint),
        ),
        _ToolButton(icon: Icons.center_focus_strong, label: 'Fit Field', onTap: onFitField),
        _ToolButton(icon: Icons.check, label: 'Done', onTap: provider.doneEditingBoundary),
      ];
    }

    // BoundaryMode.none — normal layout editing, plus entry points into
    // the boundary system.
    return [
      _ToolButton(
        icon: Icons.add_location_alt,
        label: 'Add Tree',
        active: provider.tool == EditorTool.addPost,
        onTap: () => provider.setTool(EditorTool.addPost),
      ),
      _ToolButton(
        icon: Icons.view_week,
        label: 'Add Tree Row',
        onTap: onAddTreeRow,
      ),
      _ToolButton(
        icon: Icons.open_with,
        label: 'Move',
        active: provider.tool == EditorTool.move,
        onTap: () => provider.setTool(EditorTool.move),
      ),
      _ToolButton(
        icon: Icons.delete_outline,
        label: 'Delete',
        active: provider.tool == EditorTool.delete,
        onTap: () => provider.setTool(EditorTool.delete),
      ),
      _ToolButton(
        icon: Icons.copy_all,
        label: 'Duplicate',
        active: provider.tool == EditorTool.duplicate,
        onTap: () => provider.setTool(EditorTool.duplicate),
      ),
      _ToolButton(
        icon: Icons.check_box_outlined,
        label: 'Select',
        active: provider.tool == EditorTool.select,
        onTap: () => provider.setTool(EditorTool.select),
      ),
      _ToolButton(
        icon: Icons.brush_outlined,
        label: 'Draw',
        onTap: () => provider.setPainterMode(PainterMode.line),
      ),
      _ToolButton(
        icon: Icons.hexagon_outlined,
        label: provider.hasBoundary ? 'Redraw Boundary' : 'Add Boundary',
        onTap: provider.startBoundaryCreation,
      ),
      if (provider.hasBoundary) ...[
        _ToolButton(icon: Icons.edit_outlined, label: 'Edit Boundary', onTap: provider.startBoundaryEditing),
        _ToolButton(icon: Icons.center_focus_strong, label: 'Fit Field', onTap: onFitField),
      ],
      _ToolButton(icon: Icons.undo, label: 'Undo', enabled: provider.canUndo, onTap: provider.undo),
      _ToolButton(icon: Icons.redo, label: 'Redo', enabled: provider.canRedo, onTap: provider.redo),
      _ToolButton(
        icon: Icons.save,
        label: 'Save Layout',
        onTap: () async {
          await provider.saveLayout();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layout saved')));
          }
        },
      ),
    ];
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: active ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
