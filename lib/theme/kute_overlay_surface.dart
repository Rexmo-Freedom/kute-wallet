// lib/theme/kute_overlay_surface.dart
//
// TEXT DRAWN ABOVE THE NAVIGATOR NEVER WEARS FLUTTER'S ERROR STYLE
// (founder report, 1 November 2026: "Search or ask Sal" showed a yellow
// double underline for a moment as the Sal sheet opened; "Continue" on the
// bar did the same earlier). Anything painted outside every page's
// Material (an OverlayEntry on the root overlay, the MaterialApp
// builder's Stack: the shell bar, the pill's travel to the composer, a
// toast) has no DefaultTextStyle but WidgetsApp's fallback, the monospace
// red text with the yellow double underline. [KuteOverlaySurface] gives
// such a subtree a transparent Material (ink, the theme's text) and the
// theme's body style explicitly, with no decoration.

import 'package:flutter/material.dart';

class KuteOverlaySurface extends StatelessWidget {
  const KuteOverlaySurface({super.key, required this.child});

  final Widget child;

  /// The style text above the navigator inherits: the theme's body, never
  /// decorated.
  static TextStyle textStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(decoration: TextDecoration.none);

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(style: textStyle(context), child: child),
      );
}
