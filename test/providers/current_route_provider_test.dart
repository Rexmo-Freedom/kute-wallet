// Regression coverage for the route plumbing that gates background
// sync. The historical bug: closing a named sheet ('polymarket-bet-slip',
// 'settings', ...) revealed the nav shell's UNNAMED page, the observer
// published nothing, and currentRouteProvider stayed frozen on the
// closed route's name — so every route-gated poller (home 2 s sync
// loop, Polymarket poll pipeline) believed the user never returned and
// Predictions/Investing balances + pending rows only refreshed on a
// manual pull-to-refresh.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/current_route_provider.dart';

Route<void> _route(String? name) => PageRouteBuilder<void>(
      settings: RouteSettings(name: name),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

void main() {
  group('shellTabRouteName', () {
    test('maps every shell tab to its GoRoute name', () {
      expect(shellTabRouteName(ActiveNavTab.home), 'home');
      expect(shellTabRouteName(ActiveNavTab.bank), 'bank');
      expect(shellTabRouteName(ActiveNavTab.trading), 'hyperliquid');
      expect(shellTabRouteName(ActiveNavTab.predictions), 'polymarket');
    });
  });

  group('SyncRouteObserver', () {
    test('publishes named pushes and resets on pop to an unnamed route',
        () async {
      String? current;
      var resets = 0;
      final observer = SyncRouteObserver(
        onRouteChanged: (name) => current = name,
        onReturnedToUnnamed: () => resets++,
      );

      final shell = _route(null);
      final sheet = _route('polymarket-bet-slip');

      observer.didPush(sheet, shell);
      await Future<void>.delayed(Duration.zero);
      expect(current, 'polymarket-bet-slip');
      expect(resets, 0);

      // Closing the sheet reveals the unnamed shell page: the observer
      // must fire the reset hook instead of silently leaving the stale
      // sheet name in place.
      observer.didPop(sheet, shell);
      await Future<void>.delayed(Duration.zero);
      expect(resets, 1);
    });

    test('pop back to a NAMED route publishes that name, no reset',
        () async {
      String? current;
      var resets = 0;
      final observer = SyncRouteObserver(
        onRouteChanged: (name) => current = name,
        onReturnedToUnnamed: () => resets++,
      );

      final settings = _route('settings');
      final camera = _route('camera');

      observer.didPop(camera, settings);
      await Future<void>.delayed(Duration.zero);
      expect(current, 'settings');
      expect(resets, 0);
    });

    test('unnamed pushes leave the current value untouched', () async {
      String? current = 'home';
      var resets = 0;
      final observer = SyncRouteObserver(
        onRouteChanged: (name) => current = name,
        onReturnedToUnnamed: () => resets++,
      );

      observer.didPush(_route(null), _route(null));
      await Future<void>.delayed(Duration.zero);
      expect(current, 'home');
      expect(resets, 0);
    });
  });
}
