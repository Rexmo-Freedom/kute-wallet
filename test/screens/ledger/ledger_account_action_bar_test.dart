import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Position;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/ledger_account_action_bar.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/ledger/ledger_investment_balance_header.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';

const _id = 'ledger-1';
const _address = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _depositWallet = '0x1111111111111111111111111111111111111111';
const _position = Position(
  proxyWallet: _depositWallet,
  asset: '1',
  conditionId: '0xc0',
  size: 5,
  avgPrice: 0.5,
  initialValue: 2.5,
  currentValue: 5,
  cashPnl: 2.5,
  percentPnl: 100,
  totalBought: 5,
  realizedPnl: 0,
  percentRealizedPnl: 0,
  curPrice: 1,
  redeemable: true,
  title: 'Ledger position',
  slug: 'resolved',
  eventSlug: 'resolved',
  outcome: 'Yes',
  outcomeIndex: 0,
  oppositeOutcome: 'No',
  oppositeAsset: '2',
);

WalletConfig _ledger({bool verified = true}) => WalletConfig(
      id: _id,
      name: 'Ledger',
      sparkEnabled: false,
      isHardware: true,
      isWatchOnly: true,
      walletType: 'ledger',
      evmAddress: verified ? _address : null,
      evmVerifiedAtMs: verified ? 1 : null,
    );

LedgerPmAccount _predictions({
  PolymarketLedgerAccount account = const PolymarketLedgerAccount.depositWallet(
      _depositWallet, DepositWalletVariant.uups),
  int? cash = 1000000,
  String walletId = _id,
  List<Position> positions = const [],
}) =>
    LedgerPmAccount(
      walletId: walletId,
      eoa: _address,
      account: account,
      positions: positions,
      pusdBalance: cash == null ? null : BigInt.from(cash),
      usdceBalance: cash == null ? null : BigInt.from(cash),
    );

/// Allows everything except Ledger Investing.
class _NoLedgerInvesting extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      CapabilityDecision(allowed: id != 'ledger.hyperliquid');
  @override
  bool allows(String id) => id != 'ledger.hyperliquid';
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

class _AllowedCapabilities extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => true;
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// Deposit is the venue's top button and Withdraw is the dock's own, so
/// there is nothing to open before asserting on them. This just settles
/// pending frames.
Future<void> _openActions(WidgetTester tester) async {
  await _settle(tester);
}

Future<void> _chooseAction(WidgetTester tester, String label) async {
  await _openActions(tester);
  // 'Deposit' is the venue's top button, named for the venue ("Investing
  // deposit" / "Predictions deposit"); the portfolio screen's dock keeps
  // the plain "Deposit".
  final venueDeposit = find.byType(VenueDepositButton);
  await tester.tap(label == 'Deposit' && venueDeposit.evaluate().isNotEmpty
      ? venueDeposit
      : find.text(label));
  await _settle(tester);
}

void _expectDisabled(WidgetTester tester, String label) {
  if (label == 'Deposit') {
    // The top button renders disabled when the venue cannot take a
    // deposit; a header with no verified balance shows no button at all.
    final buttons = find.byType(VenueDepositButton);
    if (buttons.evaluate().isEmpty) {
      expect(find.textContaining('deposit'), findsNothing);
      return;
    }
    expect(tester.widget<VenueDepositButton>(buttons).onTap, isNull);
    return;
  }
  final action =
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  expect(action.evaluate().single.widget,
      isA<InkWell>().having((w) => w.onTap, 'onTap', isNull));
}

Future<void> _pump(
  WidgetTester tester, {
  required LedgerAccountTab tab,
  required LedgerAccountActions actions,
  bool verified = true,
  String walletId = _id,
  LedgerPmAccount? predictions,
  LedgerHlAccount? investing,
  Widget? body,
  RuntimeCapabilitiesService? policy,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = Settings(
    currency: 'USD',
    language: 'en',
    btcFormat: 'sats',
    backup: false,
    biometricsEnabled: false,
    bitcoinElectrumNode: '',
    nodeType: 'Blockstream',
    reviewDone: false,
    activeWalletId: 'spending',
    wallets: [
      WalletConfig(id: 'spending', name: 'Spending'),
      _ledger(verified: verified),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...offlineVenueOverrides,
      settingsProvider.overrideWith((_) => SettingsModel(settings)),
      ledgerAccountActionsProvider.overrideWithValue(actions),
      runtimeCapabilitiesProvider
          .overrideWithValue(policy ?? _AllowedCapabilities()),
      ledgerPmBuyingPowerProvider(_id).overrideWith((_) async => null),
      ledgerPmActivityProvider(_id).overrideWith((_) async => []),
      ledgerPmAccountProvider(_id)
          .overrideWith((_) async => predictions ?? _predictions()),
      ledgerHlAccountProvider(_id).overrideWith((_) async =>
          investing ??
          const LedgerHlAccount(
            walletId: _id,
            address: _address,
            account: HlAccountSnapshot.empty,
            openOrders: [],
          )),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: body ??
              (tab == LedgerAccountTab.predictions
                  ? LedgerPolymarketTab(walletId: walletId)
                  : LedgerHyperliquidTab(walletId: walletId)),
          bottomNavigationBar: body == null
              ? LedgerAccountActionBar(
                  walletId: walletId,
                  tab: tab,
                )
              : null,
        ),
      ),
    ),
  ));
  await _settle(tester);
}

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
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The Ledger venue tabs read the backend's ledger.* gates from the
    // service singleton (d2dc3b10) and fail closed without a policy; this
    // policy allows them, so the Ledger venue code itself is on.
    RuntimeCapabilitiesService.debugInstance = _AllowedCapabilities();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
  });

  for (final predictions in [false, true]) {
    testWidgets(
        'Portfolio door opens full screen and keeps funding scope ($predictions)',
        (tester) async {
      final calls = <String>[];
      await _pump(tester,
          tab: predictions
              ? LedgerAccountTab.predictions
              : LedgerAccountTab.investing,
          predictions: _predictions(positions: [_position]),
          // $5 of committed perp equity gives Investing a portfolio to open.
          investing: const LedgerHlAccount(
            walletId: _id,
            address: _address,
            account: HlAccountSnapshot(
              accountValue: 5,
              withdrawable: 0,
              totalMarginUsed: 5,
              positions: [],
              spotBalances: [],
            ),
            openOrders: [],
          ),
          actions: LedgerAccountActions(
            onFundInvesting: (_, id) => calls.add('deposit:$id'),
            onWithdrawInvesting: (_, id) => calls.add('withdraw:$id'),
            onPredictionsFund: (_, id, {required requiresDeploy}) {
              expect(requiresDeploy, isFalse);
              calls.add('deposit:$id');
            },
            onPredictionsWithdraw: (_, id) => calls.add('withdraw:$id'),
          ));
      final before =
          tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
      // Deposit at the top, Portfolio and Withdraw in the dock.
      expect(find.byType(VenueDepositButton), findsOneWidget);
      final bar =
          tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
      expect(bar.actions.map((a) => a.label), ['Portfolio', 'Withdraw']);
      expect(bar.actions.map((a) => a.trackingId), ['portfolio', 'withdraw']);
      // Portfolio wears the solid CTA fill, as on the spending wallet's dock.
      expect(bar.actions.map((a) => a.solid), [true, false]);
      await tester.tap(find.text('Portfolio'));
      await _settle(tester);
      final screen = tester
          .widget<LedgerPortfolioScreen>(find.byType(LedgerPortfolioScreen));
      expect(screen.walletId, _id);
      expect(
          screen.product,
          predictions
              ? InvestmentsProduct.predictions
              : InvestmentsProduct.trading);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // The portfolio screen has no top button; its dock is Deposit and
      // Withdraw.
      expect(find.byType(VenueDepositButton), findsNothing);
      final after =
          tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
      expect(after.amountText, before.amountText);
      expect(after.totalLabel, before.totalLabel);
      await _chooseAction(tester, 'Deposit');
      await _chooseAction(tester, 'Withdraw');
      expect(calls, ['deposit:$_id', 'withdraw:$_id']);
      expect(tester.takeException(), isNull);
    });
  }

  test(
      'Ledger portfolio values committed equity rather than leveraged notional',
      () {
    final data = LedgerHlAccount(
      walletId: _id,
      account: HlAccountSnapshot(
        accountValue: 50,
        withdrawable: 20,
        totalMarginUsed: 30,
        positions: [
          HlPerpPosition.fromJson({
            'position': {'coin': 'BTC', 'szi': '1', 'positionValue': '10000'}
          })
        ],
        spotBalances: const [
          HlSpotBalance(coin: 'USDC', total: 100, hold: 75),
          HlSpotBalance(coin: 'TOKEN', total: 2, hold: 0),
        ],
      ),
    );
    expect(ledgerHlPortfolioValue(data, spotPrices: {'TOKEN': 3}), 111);
    expect(ledgerHlPortfolioValue(data), isNull);
  });

  testWidgets('investing uses the Ledger id while spending remains active',
      (tester) async {
    final calls = <String>[];
    await _pump(tester,
        tab: LedgerAccountTab.investing,
        actions: LedgerAccountActions(
          onFundInvesting: (_, id) => calls.add('deposit:$id'),
          onWithdrawInvesting: (_, id) => calls.add('withdraw:$id'),
        ));
    // Deposit is the top button; Withdraw is the dock's own.
    expect(
        find.descendant(
            of: find.byType(KuteBottomActionBar),
            matching: find.text('Withdraw')),
        findsOneWidget);
    expect(find.byType(VenueDepositButton), findsOneWidget);
    await _chooseAction(tester, 'Deposit');
    await _chooseAction(tester, 'Withdraw');
    expect(calls, ['deposit:$_id', 'withdraw:$_id']);
    expect(tester.takeException(), isNull);
  });

  for (final deployed in [false, true]) {
    testWidgets('predictions funding preserves deploy=$deployed requirement',
        (tester) async {
      final calls = <String>[];
      await _pump(tester,
          tab: LedgerAccountTab.predictions,
          predictions: _predictions(
              account: deployed
                  ? const PolymarketLedgerAccount.depositWallet(
                      _depositWallet, DepositWalletVariant.uups)
                  : const PolymarketLedgerAccount.none()),
          actions: LedgerAccountActions(
            onPredictionsFund: (_, id, {required requiresDeploy}) =>
                calls.add('deposit:$id:$requiresDeploy'),
            onPredictionsWithdraw: (_, id) => calls.add('withdraw:$id'),
          ));
      await _chooseAction(tester, 'Deposit');
      await _chooseAction(tester, 'Withdraw');
      expect(calls, ['deposit:$_id:${!deployed}', 'withdraw:$_id']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final account in [
    const PolymarketLedgerAccount.legacySafe(_depositWallet),
    const PolymarketLedgerAccount.uncertain(),
  ]) {
    testWidgets(
        '${account.kind.name} account can open withdrawal but not deposit',
        (tester) async {
      await _pump(tester,
          tab: LedgerAccountTab.predictions,
          predictions: _predictions(account: account),
          actions: LedgerAccountActions(
            onPredictionsFund: (_, __, {required requiresDeploy}) =>
                fail('Read-only account must not fund'),
            onPredictionsWithdraw: (_, id) => expect(id, _id),
          ));
      await _openActions(tester);
      _expectDisabled(tester, 'Deposit');
      await _chooseAction(tester, 'Withdraw');
      expect(find.byType(KuteBottomActionBar), findsOneWidget);
    });
  }

  for (final walletId in [_id, 'missing', 'spending']) {
    testWidgets(
        '$walletId without verified identity can open wallet-bound withdrawal',
        (tester) async {
      await _pump(tester,
          tab: LedgerAccountTab.investing,
          walletId: walletId,
          verified: false,
          actions: LedgerAccountActions(
            onFundInvesting: (_, __) => fail('Unverified identity'),
            onWithdrawInvesting: (_, id) => expect(id, walletId),
          ));
      await _openActions(tester);
      _expectDisabled(tester, 'Deposit');
      await _chooseAction(tester, 'Withdraw');
      expect(find.byType(KuteBottomActionBar), findsOneWidget);
    });
  }

  testWidgets(
      'mismatched reads keep withdrawal navigation bound to selected wallet',
      (tester) async {
    await _pump(tester,
        tab: LedgerAccountTab.predictions,
        predictions: _predictions(walletId: 'other-ledger'),
        actions: LedgerAccountActions(
          onPredictionsFund: (_, __, {required requiresDeploy}) =>
              fail('Mismatched wallet'),
          onPredictionsWithdraw: (_, id) => expect(id, _id),
        ));
    await _openActions(tester);
    _expectDisabled(tester, 'Deposit');
    await _chooseAction(tester, 'Withdraw');
  });

  for (final cash in [null, 0]) {
    testWidgets('predictions opens withdrawal with unknown/zero cash ($cash)',
        (tester) async {
      await _pump(tester,
          tab: LedgerAccountTab.predictions,
          predictions: _predictions(cash: cash),
          actions: LedgerAccountActions(
            onPredictionsFund: (_, __, {required requiresDeploy}) {},
            onPredictionsWithdraw: (_, id) => expect(id, _id),
          ));
      // No total known and none cached: the figure's skeleton, never a
      // dash or "Balance unavailable" in the headline.
      expect(find.text('Balance unavailable'), findsNothing);
      expect(find.text('—'), findsNothing);
      if (cash == null) {
        expect(
            tester
                .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
                .loading,
            isTrue);
      }
      await _openActions(tester);
      expect(find.text('Predictions deposit'), findsOneWidget);
      await _chooseAction(tester, 'Withdraw');
    });
  }

  testWidgets('predictions cash stays in header beside portfolio and actions',
      (tester) async {
    await _pump(tester,
        tab: LedgerAccountTab.predictions,
        actions: const LedgerAccountActions());
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions.map((a) => a.label), ['Portfolio', 'Withdraw']);
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.amountText, r'$2.00');
    expect(header.totalLabel, 'Predictions total');
    expect(header.showActionRow, isFalse);
    // The square button is the search door.
    expect(bar.onSearch, isNotNull);
    expect(find.byType(VenueDepositButton), findsOneWidget);
    expect(find.text('Ask Sal anything'), findsNothing);
  });

  testWidgets('wrong EVM read hides funding and balance', (tester) async {
    await _pump(tester,
        tab: LedgerAccountTab.investing,
        investing: const LedgerHlAccount(
            walletId: _id,
            address: _depositWallet,
            account: HlAccountSnapshot.empty),
        actions: LedgerAccountActions(
            onFundInvesting: (_, __) => fail('Wrong address')));
    _expectDisabled(tester, 'Deposit');
    expect(find.textContaining('available'), findsNothing);
    expect(find.byType(PoolBalanceHeader), findsNothing);
  });

  testWidgets('investing available excludes spot cash held in orders',
      (tester) async {
    await _pump(tester,
        tab: LedgerAccountTab.investing,
        actions: const LedgerAccountActions(),
        investing: const LedgerHlAccount(
            walletId: _id,
            address: _address,
            account: HlAccountSnapshot(
                accountValue: 50,
                withdrawable: 20,
                totalMarginUsed: 30,
                positions: [],
                spotBalances: [
                  HlSpotBalance(coin: 'USDC', total: 100, hold: 75)
                ]),
            openOrders: []));
    // The header leads with the total (63c59f51); available cash, which
    // excludes the USDC held in orders, sits under it.
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.availableText, r'$45.00');
    expect(header.amountText, r'$150.00');
    expect(header.investedText, r'$105.00');
  });

  testWidgets('single wired investing funding hook remains available',
      (tester) async {
    var deposits = 0;
    await _pump(tester, tab: LedgerAccountTab.investing,
        actions: LedgerAccountActions(onFundInvesting: (_, id) {
      expect(id, _id);
      deposits++;
    }));
    await _chooseAction(tester, 'Deposit');
    expect(deposits, 1);
    await _openActions(tester);
    _expectDisabled(tester, 'Withdraw');
  });

  testWidgets('unwired Ledger funding hooks remain disabled', (tester) async {
    await _pump(tester,
        tab: LedgerAccountTab.investing, actions: const LedgerAccountActions());
    await _openActions(tester);
    _expectDisabled(tester, 'Deposit');
    _expectDisabled(tester, 'Withdraw');
  });

  testWidgets('moving funding keeps Make funds available in predictions',
      (tester) async {
    final calls = <String>[];
    await _pump(tester,
        tab: LedgerAccountTab.predictions,
        body: const LedgerPolymarketTab(walletId: _id),
        actions: LedgerAccountActions(
          onPredictionsFund: (_, __, {required requiresDeploy}) {},
          onPredictionsWithdraw: (_, __) {},
          onPredictionsMakeFundsAvailable: (_, id) => calls.add(id),
        ));
    // No dock here: Deposit is the header's own button, Withdraw and
    // Portfolio are the dock's.
    expect(find.text('Portfolio'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    await tester.tap(find.text('Make funds available'));
    expect(calls, [_id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account tab changes notify the host dock', (tester) async {
    final semantics = tester.ensureSemantics();
    final tabs = <LedgerAccountTab>[];
    await _pump(tester,
        tab: LedgerAccountTab.investing,
        verified: false,
        body: LedgerAccountBody(
          wallet: _ledger(verified: false),
          initialTab: LedgerAccountTab.investing,
          onTabChanged: tabs.add,
        ),
        actions: const LedgerAccountActions());
    await tester.tap(find.bySemanticsLabel('Predictions, Polymarket'));
    await _settle(tester);
    expect(tabs, [LedgerAccountTab.predictions]);
    await tester.tap(find.bySemanticsLabel('Predictions, Polymarket'));
    expect(tabs, [LedgerAccountTab.predictions]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a Ledger venue that is off has no tab at all', (tester) async {
    final semantics = tester.ensureSemantics();
    RuntimeCapabilitiesService.debugInstance = _NoLedgerInvesting();
    final tabs = <LedgerAccountTab>[];
    await _pump(tester,
        tab: LedgerAccountTab.predictions,
        policy: _NoLedgerInvesting(),
        body: LedgerAccountBody(
          wallet: _ledger(),
          initialTab: LedgerAccountTab.predictions,
          onTabChanged: tabs.add,
        ),
        actions: const LedgerAccountActions());
    expect(find.bySemanticsLabel('Predictions, Polymarket'), findsOneWidget);
    // Not a disabled chip, and no unavailable sheet: absent.
    expect(find.bySemanticsLabel(RegExp('Hyperliquid')), findsNothing);
    expect(find.text('Investing'), findsNothing);
    expect(tabs, isEmpty);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
