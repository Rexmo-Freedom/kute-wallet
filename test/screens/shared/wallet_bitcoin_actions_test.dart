import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/shared/wallet_bitcoin_body.dart';
import 'package:kute/theme/app_theme.dart';

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, WalletConfig wallet,
    {bool cached = true, VoidCallback? onSearch}) async {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: false,
          activeWalletId: 'spending',
          wallets: [wallet],
        ))),
    walletBalanceCacheProvider.overrideWith((_) => _Balances({
          'spending':
              WalletBalance(onChainBtcBalance: 999, sparkBitcoinbalance: 999),
          if (cached)
            wallet.id:
                WalletBalance(onChainBtcBalance: 200, sparkBitcoinbalance: 800),
        })),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
              body: const SizedBox.shrink(),
              bottomNavigationBar:
                  WalletBitcoinActionBar(
                      wallet: wallet, onSearch: onSearch ?? () {}),
            )),
    GoRoute(
        path: '/receive',
        name: 'receive',
        builder: (_, __) => const Text('Receive route')),
    GoRoute(
        path: '/send',
        name: 'pay_send',
        builder: (_, __) => const Text('Send route')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            fontFamily: 'Inter',
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('hardware receive pins exact wallet and Bitcoin network',
      (tester) async {
    final wallet = WalletConfig(
        id: 'ledger', name: 'Ledger', isHardware: true, isWatchOnly: true);
    final scope = await _pump(tester, wallet);
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    // Send and Receive are the dock's own buttons now, not sheet tiles:
    // Receive on the left, Send on the right.
    expect(bar.actions.map((a) => a.label), ['Receive', 'Send']);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.text('Receive route'), findsOneWidget);
    expect(scope.read(bdkScopeWalletIdProvider), wallet.id);
    expect(scope.read(viewedWalletIdProvider), wallet.id);
    expect(scope.read(selectedNetworkTypeProvider), 'Bitcoin Network');
    expect(scope.read(settingsProvider).activeWalletId, 'spending');
  });

  for (final wallet in [
    WalletConfig(
        id: 'ledger', name: 'Ledger', isHardware: true, isWatchOnly: true),
    WalletConfig(id: 'watch', name: 'Watch', isWatchOnly: true),
  ]) {
    testWidgets('${wallet.id} send remains available with exact wallet scope',
        (tester) async {
      final scope = await _pump(tester, wallet);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Send route'), findsOneWidget);
      expect(scope.read(bdkScopeWalletIdProvider), wallet.id);
      expect(scope.read(viewedWalletIdProvider), wallet.id);
    });
  }

  for (final wallet in [
    WalletConfig(id: 'external', name: 'Address', isExternalAddress: true),
    WalletConfig(id: 'signer', name: 'Signer', isSigner: true),
  ]) {
    testWidgets('${wallet.id} cannot enter send or mutate wallet scope',
        (tester) async {
      final scope = await _pump(tester, wallet);
      final before = scope.read(bdkScopeWalletIdProvider);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Send route'), findsNothing);
      expect(scope.read(bdkScopeWalletIdProvider), before);
    });
  }

  testWidgets('the square is the wallet\'s own search door', (tester) async {
    var searches = 0;
    await _pump(
        tester, WalletConfig(id: 'cold', name: 'Cold', isHardware: true),
        onSearch: () => searches++);
    // A magnifier, never a plus: accounts open from the header now.
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.search_rounded));
    expect(searches, 1);
  });

  testWidgets('the dock never reads a balance', (tester) async {
    await _pump(
        tester, WalletConfig(id: 'cold', name: 'Cold', isHardware: true),
        cached: false);
    expect(find.textContaining('available'), findsNothing);
  });
}
