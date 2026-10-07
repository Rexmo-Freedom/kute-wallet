import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';

/// Tracks the route the user is currently looking at, so background
/// services (notably [BackgroundSyncService]) can pause work that the
/// current screen doesn't need. Updated by [SyncRouteObserver] which
/// lives in the GoRouter `observers` list.
///
/// Value is the `GoRoute` name (e.g. `'home'`, `'camera'`, `'settings'`)
/// or `null` before the first navigation. The name comes from
/// `state.name` on `GoRoute`s; routes pushed without a name (system
/// dialogs, MaterialPageRoutes inside a screen) leave the value
/// unchanged so we don't false-positive "left home" when the user
/// opens an in-screen modal.
final currentRouteProvider = StateProvider<String?>((ref) => null);

/// GoRoute name for a shell tab. The nav shell's branch navigators
/// don't fire the root [SyncRouteObserver] (tab switches are
/// `goBranch` calls, not root pushes), so tab identity reaches
/// [currentRouteProvider] through [activeShellTabProvider] instead —
/// wired in app_widget.dart. This mapping keeps the two vocabularies
/// (ActiveNavTab enum vs GoRoute name) in one place.
String shellTabRouteName(ActiveNavTab tab) {
  switch (tab) {
    case ActiveNavTab.home:
      return 'home';
    case ActiveNavTab.bank:
      return 'bank';
    case ActiveNavTab.usd:
      return 'usd';
    case ActiveNavTab.trading:
      return 'hyperliquid';
    case ActiveNavTab.predictions:
      return 'polymarket';
  }
}

/// True while the top route is the home tab. The 5s wallet-sync loop
/// gates on this so off-home screens (Send, Receive, Settings, etc.)
/// don't pay the constant-rebuild tax. Spark stream events still fire
/// regardless because they're push-based.
final isOnHomeRouteProvider = Provider<bool>(
    (ref) => ref.watch(currentRouteProvider) == 'home');

/// True when the user is on a surface that needs the active-wallet
/// continuous sync to keep ticking — Home (spending wallet) or the
/// dedicated wallet detail screen (a cold wallet the user just
/// drilled into). Used by the sync loop's gate so hardware wallet
/// transaction history populates while the user is staring at the
/// detail screen, not just when they swap back to Home.
final isOnActiveSyncRouteProvider = Provider<bool>(
  (ref) {
    final route = ref.watch(currentRouteProvider);
    return route == 'home' || route == 'walletDetail';
  },
);

/// Pushes the current route name into [currentRouteProvider]. Plug
/// into GoRouter via `observers: [SyncRouteObserver(onRouteChanged: ...)]`.
/// The callback runs on every push/pop/replace; pass it a closure that
/// writes the name into the Riverpod store (see `app_widget.dart`).
class SyncRouteObserver extends NavigatorObserver {
  SyncRouteObserver({required this.onRouteChanged, this.onReturnedToUnnamed});

  final void Function(String name) onRouteChanged;

  /// Fired when a pop/remove reveals a route with NO name — in this app
  /// that's the nav shell's page (its StatefulShellRoute page carries no
  /// settings.name). Without this hook, closing a named sheet/screen
  /// (e.g. 'polymarket-bet-slip', 'settings') left [currentRouteProvider]
  /// frozen on the closed route's name forever, so every route-gated
  /// background sync (the 2 s home loop, the Polymarket poll pipeline,
  /// the Spark push→sync trigger) believed the user never came back —
  /// balances and pending deposit/withdraw rows then only refreshed on a
  /// manual pull. The app_widget wiring resets the provider to the
  /// active shell tab's route name.
  final void Function()? onReturnedToUnnamed;

  void _publish(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) {
      final reset = onReturnedToUnnamed;
      if (route != null && reset != null) {
        scheduleMicrotask(reset);
      }
      return;
    }
    // `didPush` fires from inside Navigator's frame work — sometimes
    // mid-build of the route widget being pushed. Calling
    // `onRouteChanged` synchronously here can trip Riverpod's
    // "Tried to modify a provider while the widget tree was building"
    // assertion. Defer to the next microtask so the provider write
    // happens after the build completes.
    scheduleMicrotask(() => onRouteChanged(name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Pushes of unnamed routes (in-screen dialogs, MaterialPageRoutes
    // without settings) leave the value unchanged — same contract as
    // before. Only the *reveal* direction (pop/remove/replace) resets.
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    scheduleMicrotask(() => onRouteChanged(name));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publish(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _publish(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publish(previousRoute);
  }
}
