import 'package:flutter/widgets.dart';

/// Returns true when the user has enabled the OS-level "Reduce Motion"
/// (iOS) / "Remove animations" (Android) accessibility setting.
///
/// Every new animation in the Kute app MUST route through this helper.
/// When true:
///   * Mascot renders the static SVG fallback (no Rive / no custom
///     animation).
///   * Balance roll-ups become instant text swaps.
///   * Slide-in transitions snap into place.
///   * Confetti is suppressed entirely.
///   * Pull-to-refresh falls back to the stock indicator.
///
/// Read at build-time via `MediaQuery.disableAnimationsOf(context)` —
/// this also subscribes the widget to changes so toggling the OS
/// setting reflows the UI without a restart.
bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
