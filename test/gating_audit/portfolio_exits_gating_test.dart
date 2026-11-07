// Gating audit, v2.2: the Portfolio keeps every position on show and every
// exit open whatever the backend withholds from new business. Close,
// Sell and Clear answer to the exits (`hyperliquid.close`,
// `polymarket.close`), which no cascade ever reaches; a region block on
// swaps (the founder's cascade to the venues' trading and deposits) or
// trading denied by platform, switch or coming soon leaves them as they
// are. Only an exit switched off for everyone stops one.
//
//   * The Portfolio shows both venues of the spending account under
//     every denial (portfolioVenuesProvider).
//   * The Investing close ticket closes end to end (PIN, the exchange
//     call) under each denial of trading.
//   * The Predictions position: Sell is the bar's enabled primary and
//     opens the sell slip; a lost side's Clear redeems.
//   * Add margin from the cash already in Investing stays open (it is
//     `hyperliquid.close`); only the part that would move money in
//     (`hyperliquid.deposit`, in the cascade) says why, the named
//     regions over the one VPN sentence.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart'
    show PolySlipCta;
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show venueCashReachExcludingProvider;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../helpers/shell_bar_harness.dart';
import '../services/support/fake_secret_store.dart';
import 'investing_gating_policies.dart';

/// Every way the backend can withhold new business from the venues:
/// the swap cascade, and trading denied each of the four ways.
final _withheld = <String, RuntimeCapabilitiesService Function()>{
  'swap country block (cascade)': auditSwapCountryBlock,
  for (final denial in AuditDenial.values)
    'trading and deposits ${denial.name}': () => auditDenying(const [
          'hyperliquid.trade',
          'hyperliquid.deposit',
          'hyperliquid.stocks',
          'polymarket.trade',
          'polymarket.deposit',
          'polymarket.sports',
          'polymarket.politics',
        ], denial),
};

// ── The Investing close ticket, end to end ─────────────────────────────

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

/// The exchange call, answered at once.
class _Exchange {
  int closes = 0;
}

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.exchange);
  final _Exchange exchange;

  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, withdrawable: 100);

  @override
  Future<HlOrderResult> closePosition({
    required String coin,
    double fraction = 1.0,
    double slippagePct = 1.0,
    required AuthGrant grant,
  }) async {
    exchange.closes++;
    return Completer<HlOrderResult>().future;
  }
}

class _HlPrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

const _hlPosition = HlPerpPosition(
  coin: 'BTC',
  szi: 0.5,
  entryPx: 64000,
  positionValue: 32000,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: 58000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
);

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The close ticket under [policy], Max picked; returns the exchange.
Future<_Exchange> _pumpClose(WidgetTester tester, FakeKeychain keychain,
    RuntimeCapabilitiesService policy) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  ContinuousHaptics.debugReset();
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  installShellBar();
  final exchange = _Exchange();
  final container = ProviderContainer(overrides: [
    authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
    settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
    hyperliquidTradingProvider.overrideWith(() => _Trading(exchange)),
    hyperliquidLivePricesProvider.overrideWith(_HlPrices.new),
    hyperliquidPerpPositionsProvider.overrideWith((_) => const [_hlPosition]),
    hyperliquidAddressProvider.overrideWith((_) async => null),
    currencyProvider.overrideWith((_) => _Currency()),
    runtimeCapabilitiesProvider.overrideWithValue(policy),
    aiEnabledProvider.overrideWith((_) async => false),
  ]);
  addTearDown(container.dispose);
  container.read(sessionAuthProvider.notifier).state =
      SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: shellBarBuilder,
        navigatorObservers: shellBarObservers(),
        home: const Scaffold(
          body: HlClosePositionSheet(position: _hlPosition, market: _btc),
        ),
      ),
    ),
  ));
  await _frames(tester, 6);
  await tester.tap(find.bySemanticsLabel('Use maximum'));
  await _frames(tester, 6);
  return exchange;
}

/// Taps Close and approves it with the PIN, then waits for the exchange.
Future<void> _closeAndApprove(WidgetTester tester, _Exchange exchange) async {
  expect(barPrimaryEnabled(tester), isTrue);
  expect(barPrimaryLabel(tester), 'Close 100% now');
  await tapBarPrimary(tester, settle: false);
  for (var i = 0; i < 40 && find.byType(PinGateSheet).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (find.byType(PinGateSheet).evaluate().isEmpty) return;
  await _frames(tester, 16);
  for (final d in '111111'.split('')) {
    await tester.tap(
        find.descendant(of: find.byType(PinGateSheet), matching: find.text(d)));
    await tester.pump();
  }
  for (var i = 0; i < 40 && exchange.closes == 0; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── The Predictions position page ──────────────────────────────────────

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

class _PolyTrading extends PolymarketTradingNotifier {
  final redeemed = <String>[];

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();

  @override
  Future<void> refresh() async {}

  @override
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    redeemed.add(conditionId);
    return 0;
  }
}

class _PolyPrices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void removeTokens(List<String> tokenIds) {}
}

/// A held election position (politics: the category gate is denied in
/// the trading denials too).
const _open = PolymarketPosition(
  marketId: 'c-sen',
  marketQuestion: 'Will Republicans win the Senate?',
  outcome: 'Yes',
  size: 20,
  avgPrice: 0.40,
  currentPrice: 0.55,
  pnl: 3,
  pnlPercent: 37,
  isResolved: false,
  tokenId: 'sen-yes',
  eventSlug: 'senate-2026',
);

const _lost = PolymarketPosition(
  marketId: 'c-sen',
  marketQuestion: 'Will Republicans win the Senate?',
  outcome: 'Yes',
  size: 20,
  avgPrice: 0.40,
  currentPrice: 0,
  pnl: -8,
  pnlPercent: -100,
  isResolved: true,
  won: false,
  tokenId: 'sen-yes',
  eventSlug: 'senate-2026',
);

Future<_PolyTrading> _pumpPosition(WidgetTester tester,
    PolymarketPosition position, RuntimeCapabilitiesService policy) async {
  installShellBar();
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final trading = _PolyTrading();
  final router = GoRouter(observers: shellBarObservers(), routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PositionDetailSheet(position: position))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_PolyPrices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(() => trading),
      polymarketEventDetailsProvider('senate-2026')
          .overrideWith((ref) async => null),
      polyPositionJourneyProvider.overrideWith((ref, key) async => null),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: shellBarBuilder,
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await pumpBar(tester);
  await tester.pump(const Duration(milliseconds: 600));
  return trading;
}

// ── Add margin ─────────────────────────────────────────────────────────

class _NoFunded extends FundedOrdersNotifier {
  @override
  List<FundedOrderRecord> build() => const [];
}

class _NoEstimate implements VenueFunder {
  @override
  Future<VenueMoveQuote> estimate(double usd) => Future.error('offline');
  @override
  Future<VenueMoveResult> fund(
          {required double usd,
          required MoveAuthorization auth,
          String purpose = 'order_funding'}) =>
      throw UnimplementedError();
  @override
  Future<double> idleUsd() async => 0;
  @override
  Future<double> minimumUsd() async => 1;
}

/// The Add margin sheet on the isolated BTC position, $100 of Investing
/// cash and $49 more in Dollars and Predictions, under [policy].
Future<void> _pumpMargin(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_HlPrices.new),
      hyperliquidTradingProvider.overrideWith(() => _Trading(_Exchange())),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_hlPosition]),
      usdBalanceProvider.overrideWith((_) => 20),
      investmentsSpendableExcludingProvider.overrideWith((_, __) =>
          const InvestmentsSpendable(
              dollarsUsd: 20, venueCashUsd: 29, maxUsd: 49)),
      venueCashRefreshProvider.overrideWith((_) async {}),
      venueCashReachExcludingProvider.overrideWith((_, __) async => 49),
      hyperliquidVenueFunderProvider.overrideWithValue(_NoEstimate()),
      fundedOrdersProvider.overrideWith(_NoFunded.new),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      currencyProvider.overrideWith((_) => _Currency()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: shellBarBuilder,
        navigatorObservers: shellBarObservers(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HlAdjustMarginSheet(
                position: _hlPosition,
                market: _btc,
                add: true,
                source: HlMarginSource.liquidationRow),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _typeAmount(WidgetTester tester, String amount) async {
  final pad = find.byType(AmountKeypad);
  for (final key in amount.split('')) {
    await tester.tap(find.descendant(of: pad, matching: find.text(key)));
    await tester.pump();
  }
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'audit-session';
    keychain = FakeKeychain();
    keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    KuteConfirmation.debugFeedbackOverride = () async {};
  });
  tearDown(() {
    SecretStores.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    KuteConfirmation.debugFeedbackOverride = null;
  });

  group('the Portfolio shows both venues of the spending account', () {
    for (final MapEntry(key: name, value: make) in {
      ..._withheld,
      'browsing withheld (both venues off)': () => auditDenying(
          const ['hyperliquid.browse', 'polymarket.browse'],
          AuditDenial.masterOff),
    }.entries) {
      test(name, () async {
        final policy = make();
        addTearDown(policy.dispose);
        expect(await policy.refresh(), isTrue);
        final container = ProviderContainer(overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
          runtimeCapabilitiesProvider.overrideWithValue(policy),
        ]);
        addTearDown(container.dispose);
        expect(container.read(portfolioVenuesProvider),
            const PortfolioVenues(trading: true, predictions: true));
        for (final exit in kAuditExits) {
          expect(policy.allows(exit), isTrue, reason: exit);
        }
      });
    }
  });

  group('the Investing close ticket closes', () {
    for (final MapEntry(key: name, value: make) in _withheld.entries) {
      testWidgets(name, (tester) async {
        final policy = make();
        expect(await policy.refresh(), isTrue);
        RuntimeCapabilitiesService.debugInstance = policy;
        expect(policy.allows('hyperliquid.trade'), isFalse);
        final exchange = await _pumpClose(tester, keychain, policy);
        await _closeAndApprove(tester, exchange);
        expect(exchange.closes, 1, reason: 'the close reached the exchange');
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        policy.dispose();
      });
    }

    testWidgets(
        'only the exit switched off for everyone stops it, before the PIN',
        (tester) async {
      final policy =
          auditDenying(const ['hyperliquid.close'], AuditDenial.masterOff);
      expect(await policy.refresh(), isTrue);
      RuntimeCapabilitiesService.debugInstance = policy;
      final exchange = await _pumpClose(tester, keychain, policy);
      await _closeAndApprove(tester, exchange);
      expect(exchange.closes, 0);
      expect(find.byType(PinGateSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      policy.dispose();
    });
  });

  group('the Predictions position: Sell and Clear stay open', () {
    for (final MapEntry(key: name, value: make) in _withheld.entries) {
      testWidgets('$name: Sell is the enabled bar and opens the sell slip',
          (tester) async {
        final policy = make();
        expect(await policy.refresh(), isTrue);
        RuntimeCapabilitiesService.debugInstance = policy;
        expect(policy.allows('polymarket.trade'), isFalse);
        await _pumpPosition(tester, _open, policy);
        final ctx = barPrimaryContext(tester);
        expect(ctx.label, 'Sell');
        expect(ctx.enabled, isTrue);
        expect(find.byType(CapabilityBlockNote), findsNothing);
        await tapBarPrimary(tester, settle: false);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(SellSheet), findsOneWidget);
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);
        expect(find.byType(CapabilityBlockNote), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        policy.dispose();
      });

      testWidgets('$name: a lost side\'s Clear redeems', (tester) async {
        final policy = make();
        expect(await policy.refresh(), isTrue);
        RuntimeCapabilitiesService.debugInstance = policy;
        final trading = await _pumpPosition(tester, _lost, policy);
        expect(barPrimaryContext(tester).label, 'Clear position');
        expect(barPrimaryEnabled(tester), isTrue);
        await tapBarPrimary(tester, settle: false);
        for (var i = 0; i < 20 && trading.redeemed.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(trading.redeemed, ['c-sen']);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        policy.dispose();
      });
    }
  });

  group('Add margin from the Investing cash', () {
    testWidgets(
        'swap country block: the cash in Investing can be added, nothing '
        'is reached beyond it, and a larger amount says why with the '
        'named regions', (tester) async {
      final policy = auditSwapCountryBlock();
      expect(await policy.refresh(), isTrue);
      RuntimeCapabilitiesService.debugInstance = policy;
      await _pumpMargin(tester, policy);
      // Only the Investing cash: the move in is withheld.
      expect(find.text(r'Available: $100.00'), findsOneWidget);
      await _typeAmount(tester, '50');
      final cta = tester.widget<PolySlipCta>(find.byType(PolySlipCta));
      expect(cta.label, 'Add margin');
      expect(cta.enabled, isTrue);
      expect(barPrimaryEnabled(tester), isTrue);
      expect(find.byType(CapabilityBlockNote), findsNothing);

      await _typeAmount(tester, '0');
      final note = find.byType(CapabilityBlockNote);
      expect(note, findsOneWidget);
      expect(tester.widget<CapabilityBlockNote>(note).message,
          '$kAuditRegionTitle\n$kAuditVpnLine');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      policy.dispose();
    });

    for (final denial in AuditDenial.values) {
      testWidgets(
          'hyperliquid.trade ${denial.name}: Add margin from the cash stays '
          'enabled', (tester) async {
        final policy = auditDenying(const ['hyperliquid.trade'], denial);
        expect(await policy.refresh(), isTrue);
        RuntimeCapabilitiesService.debugInstance = policy;
        await _pumpMargin(tester, policy);
        await _typeAmount(tester, '50');
        final cta = tester.widget<PolySlipCta>(find.byType(PolySlipCta));
        expect(cta.label, 'Add margin');
        expect(cta.enabled, isTrue);
        expect(find.byType(CapabilityBlockNote), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        policy.dispose();
      });
    }
  });
}
