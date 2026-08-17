import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class PostEditResult {
  final String postCode;
  final PostColor color;
  final String? notes;
  PostEditResult({required this.postCode, required this.color, this.notes});
}

/// Bottom sheet shown right after a post is placed on the canvas (and when
/// editing an existing post's identity). Kept separate from the flower-count
/// popup because they serve very different moments in the workflow.
Future<PostEditResult?> showPostEditSheet(
  BuildContext context, {
  required String initialCode,
  required PostColor initialColor,
  String? initialNotes,
}) {
  final codeController = TextEditingController(text: initialCode);
  final notesController = TextEditingController(text: initialNotes ?? '');
  PostColor selected = initialColor;

  return showModalBottomSheet<PostEditResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text('Post Details', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Post ID'),
                ),
                const SizedBox(height: 16),
                Text('Color', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: PostColor.values.map((c) {
                    final isSelected = c == selected;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selected = c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? c.swatch.withValues(alpha: 0.2) : null,
                            border: Border.all(
                              color: isSelected ? c.swatch : Colors.grey.shade300,
                              width: isSelected ? 2.5 : 1.5,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.circle, color: c.swatch, size: 22),
                              const SizedBox(height: 6),
                              Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'e.g. Needs fertilizer, weak growth...',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (codeController.text.trim().isEmpty) return;
                          Navigator.pop(
                            ctx,
                            PostEditResult(
                              postCode: codeController.text.trim(),
                              color: selected,
                              notes: notesController.text.trim().isEmpty
                                  ? null
                                  : notesController.text.trim(),
                            ),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
