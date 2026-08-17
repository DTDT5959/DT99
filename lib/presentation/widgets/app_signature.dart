import 'package:flutter/material.dart';

import '../../core/constants/app_branding.dart';

/// Subtle "Ibrahim • SALS CO" signature shown on every main screen.
///
/// Meant to be the LAST child of a `Stack` wrapping a screen's body, e.g.:
///
/// ```dart
/// body: Stack(
///   children: [
///     yourExistingBodyContent,
///     const AppSignature(),
///   ],
/// ),
/// ```
///
/// Non-interactive (wrapped in IgnorePointer) so it never intercepts taps
/// meant for content underneath, and respects SafeArea so it never sits
/// under a system inset. [alignment] defaults to bottom-center but should
/// be overridden per screen when that would collide with a FAB, bottom
/// toolbar, or a button pinned to the bottom of the layout — e.g. use
/// `Alignment.topRight` on screens with a bottom-pinned primary action, or
/// `Alignment.bottomLeft` on screens with a bottom-right FAB.
class AppSignature extends StatelessWidget {
  final Alignment alignment;

  const AppSignature({super.key, this.alignment = Alignment.bottomCenter});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: alignment,
              child: Opacity(
                opacity: 0.65,
                child: Text(
                  AppBranding.signature,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
