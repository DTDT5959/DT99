import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';

/// The single most-used screen element in the app: tap a post, punch in a
/// number, save, and it auto-closes so the farmer can move to the next post
/// with the fewest possible taps. No confirmation dialogs on top of this.
Future<int?> showFlowerCountSheet(
  BuildContext context, {
  required String postCode,
  required PostColor color,
  int? initialValue,
}) {
  int value = initialValue ?? 0;
  final textController = TextEditingController(text: value == 0 ? '' : value.toString());

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          void updateFromText(String text) {
            final parsed = int.tryParse(text);
            if (parsed != null && parsed >= 0) {
              value = parsed;
            }
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
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, color: color.swatch, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'Post $postCode',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ],
                ),
                Text(color.label, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 24),
                Text('Flower Count', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StepperButton(
                      icon: Icons.remove,
                      onTap: () => setState(() {
                        if (value > 0) value--;
                        textController.text = value.toString();
                      }),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: textController,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (text) => setState(() => updateFromText(text)),
                      ),
                    ),
                    const SizedBox(width: 20),
                    _StepperButton(
                      icon: Icons.add,
                      onTap: () => setState(() {
                        value++;
                        textController.text = value.toString();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
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
                          updateFromText(textController.text);
                          Navigator.pop(ctx, value);
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

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, size: 26),
        ),
      ),
    );
  }
}
