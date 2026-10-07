import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/ledger/ledger_account_action_bar.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show LedgerAccountTab;
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/ledger/ledger_tab_states.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';

import '../../helpers/offline_venue_overrides.dart';

/// pumpAndSettle that lets a skeleton shimmer on: a Ledger venue header
/// with no total known (cash unknown, an uncertain account) shows the
/// figure's skeleton, which never stops animating.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final product in InvestmentsProduct.values) {
    for (final matching in [true, false]) {
      testWidgets(
          matching
              ? '${product.name} Ledger portfolio keeps supported chip tabs and wallet scope'
              : '${product.name} mismatched Ledger snapshot cannot display data or actions',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? cancelledWallet;
        const order = HlOpenOrder(
            coin: 'LEDGER_ONLY',
            oid: 9,
            isBuy: true,
            limitPx: 100,
            sz: 1,
            origSz: 1,
            timestamp: 0,
            cloid: null,
            reduceOnly: false,
            orderType: 'Limit',
            isTrigger: false,
            triggerPx: null);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              ...offlineVenueOverrides,
              ledgerIdentityProvider('ledger-a').overrideWith((_) =>
                  const LedgerIdentity(
                      walletId: 'ledger-a',
                      evmAddress: 'ledger-address',
                      evmVerifiedAtMs: 1)),
              settingsProvider.overrideWith((_) => SettingsModel(Settings(
                  currency: 'USD',
                  language: 'en',
                  btcFormat: 'sats',
                  backup: false,
                  biometricsEnabled: false,
                  bitcoinElectrumNode: '',
                  nodeType: '',
                  reviewDone: true))),
              ledgerHlAccountProvider('ledger-a').overrideWith((_) async =>
                  LedgerHlAccount(
                      walletId: 'ledger-a',
                      address:
                          matching ? 'ledger-address' : 'other-ledger-address',
                      account: HlAccountSnapshot.empty,
                      openOrders: [order],
                      fills: [])),
              ledgerPmAccountProvider('ledger-a')
                  .overrideWith((_) async => LedgerPmAccount(
                        walletId: 'ledger-a',
                        eoa: matching
                            ? 'ledger-address'
                            : 'other-ledger-address',
                        positions: const [],
                      )),
              ledgerPmActivityProvider('ledger-a')
                  .overrideWith((_) async => []),
              ledgerAccountActionsProvider.overrideWithValue(
                  LedgerAccountActions(
                      onCancelOrder: (context, walletId, order) =>
                          cancelledWallet = walletId)),
            ],
            child: ScreenUtilInit(
                designSize: const Size(430, 932),
                builder: (_, __) => MaterialApp(
                      theme: ThemeData(
                          splashFactory: NoSplash.splashFactory,
                          fontFamily: 'Inter',
                          extensions: [AppColorsExtension.light()]),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      home: Scaffold(
                          body: Builder(
                              builder: (context) => TextButton(
                                    onPressed: () => LedgerPortfolioScreen.show(
                                        context,
                                        walletId: 'ledger-a',
                                        product: product),
                                    child: const Text('Open Ledger portfolio'),
                                  ))),
                    ))));
        await tester.tap(find.text('Open Ledger portfolio'));
        await _settle(tester);
        expect(find.text('Portfolio'), findsOneWidget);
        expect(find.text('Markets'), findsNothing);
        expect(find.byType(PortfolioTabs), findsOneWidget);
        expect(find.text('Yield'), findsNothing);
        expect(find.text('Build portfolio'), findsNothing);
        expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
        // Pill tabs, not a TabBar; both venues show Open, Orders, Activity
        // and Statistics since Ledger prediction orders were exposed
        // (89f4f7ad).
        final tabs =
            DefaultTabController.of(tester.element(find.byType(PortfolioTabs)));
        expect(tabs.length, 4);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.text('Orders'), findsOneWidget);
        await tester.tap(find.text(
            product == InvestmentsProduct.trading ? 'Orders' : 'Activity'));
        await _settle(tester);
        if (!matching) {
          expect(find.text('LEDGER_ONLY'), findsNothing);
          expect(find.byType(LedgerTabLoadFailed), findsWidgets);
          expect(cancelledWallet, isNull);
          expect(tester.takeException(), isNull);
          return;
        }
        expect(
            find.text('LEDGER_ONLY'),
            product == InvestmentsProduct.trading
                ? findsOneWidget
                : findsNothing);
        if (product == InvestmentsProduct.predictions) {
          expect(find.text('No activity yet'), findsOneWidget);
        }
        expect(find.byType(TextField), findsNothing);
        // The dock stays bound to this Ledger wallet and venue. Its money
        // verbs are its own buttons and its square button is search.
        final dock = tester.widget<LedgerAccountActionBar>(
            find.byType(LedgerAccountActionBar));
        expect(dock.walletId, 'ledger-a');
        expect(
            dock.tab,
            product == InvestmentsProduct.trading
                ? LedgerAccountTab.investing
                : LedgerAccountTab.predictions);
        final bar = tester
            .widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
        expect(bar.actions.map((a) => a.label), ['Deposit', 'Withdraw']);
        expect(bar.onSearch, isNotNull);
        expect(find.text('Ask Sal anything'), findsNothing);
        final context = tester.element(find.byType(PortfolioTabs));
        expect(DefaultTabController.of(context).index,
            product == InvestmentsProduct.trading ? 1 : 2);
        if (product == InvestmentsProduct.trading) {
          await tester.tap(
              find.text(AppLocalizations.of(context).ledgerCancelOrderSummary));
          await _settle(tester);
          expect(cancelledWallet, 'ledger-a');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
