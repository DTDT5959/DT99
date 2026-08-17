import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Renders a single post/tree on the farm canvas using the 3D tree icon
/// assets (Empty / Flowering / Fruiting), surrounded by a colored ring
/// that always identifies the post's variety (yellow / red / white) —
/// independent of tree state, so the variety stays legible whether the
/// tree is Empty, Flowering, or Fruiting.
///
/// Two contexts:
///  - Layout editor: tree stays Empty, ring still shows the chosen variety.
///  - Counting / Season View: [treeState] and [displayCount] are driven by
///    FruitCalculationService, so this widget never computes anything
///    itself — it only draws whatever it's told.
///
/// Switching TreeState (e.g. Flower View <-> Fruit View, or Empty ->
/// Flowering right after a count is saved) animates with a combined
/// fade+scale over 250ms, and the overlaid number cross-fades with it.
///
/// The outer footprint is kept identical to the pre-ring version
/// (postIconSize + 12) so FarmCanvas's tap/position math — which centers
/// this widget on postIconSize/2 — doesn't drift.
class PostMarker extends StatelessWidget {
  final String postCode;
  final PostColor color;
  final TreeState treeState;
  final int? displayCount; // null = no number shown (Empty state)
  final bool selected;

  const PostMarker({
    super.key,
    required this.postCode,
    required this.color,
    this.treeState = TreeState.empty,
    this.displayCount,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    // White variety gets an extra subtle gray outline so its ring stays
    // visible against light backgrounds — yellow and red already contrast
    // fine using their own swatch color as the ring.
    final bool needsGrayOutline = color == PostColor.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppConstants.postIconSize + 12,
          height: AppConstants.postIconSize + 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            // Selection takes visual precedence (a blue ring) while active;
            // otherwise the ring always shows the post's variety color.
            border: Border.all(
              color: selected
                  ? Colors.blueAccent
                  : (needsGrayOutline ? Colors.grey.shade400 : color.swatch),
              width: selected ? 3 : (needsGrayOutline ? 1.2 : 3),
            ),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
          ),
          alignment: Alignment.center,
          // White variety nests a second, thicker white ring just inside
          // the gray outline, so it still reads as "white ring" rather
          // than a plain gray circle — without growing the marker's size.
          child: (needsGrayOutline && !selected)
              ? Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.swatch, width: 3),
                  ),
                  child: _TreeStack(treeState: treeState, displayCount: displayCount),
                )
              : _TreeStack(treeState: treeState, displayCount: displayCount),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            postCode,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The tree image + flower/fruit count badge, factored out so PostMarker
/// can nest it inside either a single ring (yellow/red) or a double ring
/// (white, for visibility) without duplicating this markup.
class _TreeStack extends StatelessWidget {
  final TreeState treeState;
  final int? displayCount;
  const _TreeStack({required this.treeState, required this.displayCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: Image.asset(
            treeState.assetPath,
            key: ValueKey(treeState),
            width: AppConstants.postIconSize,
            height: AppConstants.postIconSize,
            fit: BoxFit.contain,
          ),
        ),
        if (displayCount != null)
          Positioned(
            top: -6,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: Container(
                key: ValueKey('$treeState-$displayCount'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$displayCount',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
