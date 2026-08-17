import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class AddTreeRowResult {
  final int count;
  final PostColor color;
  AddTreeRowResult({required this.count, required this.color});
}

/// Bottom sheet shown when the farmer taps "Add Tree Row": asks for how
/// many trees and which variety, then hands off to Tree Row Placement Mode
/// on the canvas (see LayoutEditorProvider.startRowPlacement). Deliberately
/// mirrors showPostEditSheet's look so it reads as the same family of
/// action as "Add Tree", not a separate feature bolted on.
Future<AddTreeRowResult?> showAddTreeRowSheet(
  BuildContext context, {
  PostColor initialColor = PostColor.yellow,
}) {
  final countController = TextEditingController(text: '10');
  PostColor selected = initialColor;

  return showModalBottomSheet<AddTreeRowResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          String? error;

          void submit() {
            final n = int.tryParse(countController.text.trim());
            if (n == null || n <= 0) {
              setState(() => error = 'Enter a number of trees greater than 0');
              return;
            }
            if (n > AppConstants.maxSupportedPosts) {
              setState(() => error = 'That\'s more than one row should hold — try a smaller number');
              return;
            }
            Navigator.pop(ctx, AddTreeRowResult(count: n, color: selected));
          }

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
                Text('Add Tree Row', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Next you\'ll drag a line on the map to position the row.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: countController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Number of trees',
                    hintText: 'e.g. 20',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Variety', style: Theme.of(ctx).textTheme.titleMedium),
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
                        onPressed: submit,
                        child: const Text('Next: Position Row'),
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
