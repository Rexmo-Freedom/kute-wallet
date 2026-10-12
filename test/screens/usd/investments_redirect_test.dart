// `/hyperliquid` and `/polymarket` for the spending account land on the
// Investments tab with that venue's pill picked (one balance); a Ledger
// owner keeps its own venue branch. The redirect reads the strip's owner
// the way the strip does.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';

final _ledger = WalletConfig(
  id: 'ledger-1',
  name: 'Ledger',
  sparkEnabled: false,
  isHardware: true,
  isWatchOnly: true,
  walletType: 'ledger',
);
final _spending = WalletConfig(id: 'spending', name: 'Spending');

Future<GoRouter> _pump(WidgetTester tester, {String? shellWalletId}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const Text('home')),
      // The real /usd route reads the pill the same way.
      GoRoute(
          path: '/usd',
          builder: (_, state) => Text(
              'usd:${InvestmentsTab.fromKey(state.uri.queryParameters['tab'])?.key}')),
      GoRoute(
          path: '/hyperliquid',
          redirect: (context, _) =>
              spendingVenueRedirect(context, InvestmentsTab.investing),
          builder: (_, __) => const Text('hyperliquid')),
      GoRoute(
          path: '/polymarket',
          redirect: (context, _) =>
              spendingVenueRedirect(context, InvestmentsTab.predictions),
          builder: (_, __) => const Text('polymarket')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [_spending, _ledger],
          ))),
      shellWalletIdProvider.overrideWith((_) => shellWalletId),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('the spending account: the venue links open Investments '
      'on that pill', (tester) async {
    final router = await _pump(tester);
    router.go('/polymarket');
    await tester.pumpAndSettle();
    expect(find.text('usd:predictions'), findsOneWidget);
    expect(router.state.uri.toString(), '/usd?tab=predictions');

    router.go('/hyperliquid');
    await tester.pumpAndSettle();
    expect(find.text('usd:investing'), findsOneWidget);
    expect(router.state.uri.toString(), '/usd?tab=investing');
  });

  testWidgets('a Ledger owner keeps its own venue branches', (tester) async {
    final router = await _pump(tester, shellWalletId: 'ledger-1');
    router.go('/polymarket');
    await tester.pumpAndSettle();
    expect(find.text('polymarket'), findsOneWidget);
    router.go('/hyperliquid');
    await tester.pumpAndSettle();
    expect(find.text('hyperliquid'), findsOneWidget);
  });
}
