// lib/providers/active_shell_tab_provider.dart
//
// The shell-tab identity shared between the navigation UI and the
// live-price notifiers. Lives under providers/ (not screens/) because
// app_shell.dart imports both live-price providers — the notifiers
// reading the active tab at creation time from a screens/ file would be
// an import cycle.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which destination tab should render as active. Home is the default
/// (the pill is painted on the home scaffold). Destination screens pass
/// their own key (e.g. [ActiveNavTab.predictions] on PolymarketScreen)
/// so the nav reads "you are here" consistently across the app.
// `earn` was removed from the enum when the Flashnet USDB Earn product
// was removed from the app entirely.
// `usd` is the spending account's dollar tab, in the strip slot the
// hidden Bank tab used to occupy.
enum ActiveNavTab { home, bank, usd, predictions, trading }

/// The shell tab currently on screen. Written by the app-shell state
/// (initial mount + every branch change) and read by:
///   * the app-level lifecycle handler in app_widget.dart, so a
///     foreground resume revives only the live sockets the visible tab
///     actually needs;
///   * the live-price notifiers at CREATION, so a notifier born on a
///     non-owning tab (e.g. a bet slip reached from the Home feed)
///     starts pause-requested instead of streaming for a tab that never
///     resumed it — see the `build()` notes in each notifier.
final activeShellTabProvider =
    StateProvider<ActiveNavTab>((_) => ActiveNavTab.home);
