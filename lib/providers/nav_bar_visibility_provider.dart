import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the persistent top nav bar should be HIDDEN (slid up off the top
/// edge). Memory-only, shared across the four tab screens that live inside
/// the persistent nav shell.
///
/// Each tab screen's scroll listener writes to this from its own
/// `_scrollController` (reverse scroll = hide, forward / near-top = show),
/// and the single [KuteTopNavBar] mounted in the shell WATCHES it to drive
/// its slide animation. With one persistent bar (no per-screen remount) the
/// bar can't own four different scroll controllers, so the hide state is
/// routed through here instead.
final navBarHiddenProvider = StateProvider<bool>((ref) => false);

/// How long the top nav bar takes to slide away or back; a screen that
/// gives the bar's room back while it is away (Investments) eases that
/// room over the same time so the two move together.
const Duration kNavBarSlideDuration = Duration(milliseconds: 220);
