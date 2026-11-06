// The real path the founder took on device (6 November 2026: "Predictions
// on search have no buy button on the bet slip, and Hyperliquid the
// same"): the Sal bar's pill opens the search sheet (the pill travels to
// its composer), a typed query lists an Investing market, its row opens
// the market page OVER the sheet, Invest opens the order slip over that,
// and the slip's one action is the bar: visible, enabled once an amount
// is typed, taking the tap, with the round share button beside it. The
// sheet stays under all of it and gets its pill back when they close
// (kute_bar_context.dart, THE SEARCH SHEET ONLY HOLDS THE BAR WHILE IT IS
// ON TOP). The same slips opened straight from a market page, and from
// the Dollars Send's "Send an investment or prediction" pick sheet, keep
// their button too.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/hl_chart_edit_harness.dart' show hlEditBtc, hlEditCandles;
import '../../helpers/runtime_policy_fixture.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _LivePrices extends HlLivePricesNotifier {
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

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => true;
  @override
  String? blockReason(String id) => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

class _Funded extends FundedOrdersNotifier {
  @override
  List<FundedOrderRecord> build() => const [];
}

class _PolyPrices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: true);
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _PolyTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

/// One Yes / No prediction, open well past today.
final PolymarketEvent _fed = PolymarketModel().parseEventsRaw([
  {
    'id': '7',
    'slug': 'fed-cut-december',
    'title': 'Will the Fed cut rates in December?',
    'endDate': '2099-12-31T00:00:00Z',
    'markets': [
      {
        'id': 'm1',
        'question': 'Will the Fed cut rates in December?',
        'outcomes': '["Yes", "No"]',
        'outcomePrices': '["0.62", "0.38"]',
        'clobTokenIds': '["yes-token", "no-token"]',
        'conditionId': '0xfed',
      }
    ],
  }
]).single;

final _btcRow = HlMarketSearchResult(
  coin: 'BTC',
  wireCoin: 'BTC',
  kind: HlMarketKind.perp,
  isStock: false,
  name: null,
  category: 'crypto',
  iconUrl: null,
  markPx: 66000,
  dayChangePct: 0.015,
  maxLeverage: 40,
  market: hlEditBtc,
);

NavigatorState _nav() => AppRouter.rootNavigatorKey.currentState!;

final _primary = find.byKey(const ValueKey('kute-bar-primary-button'));
final _share = find.byKey(const ValueKey('kute-bar-share'));
final _morphed = find.byKey(const ValueKey('kute-bar-morphed'));

bool _barUp(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('kute-shell-bar-slide')));
  return slide.offset == Offset.zero;
}

/// Whether a tap at [finder]'s centre reaches its render box.
bool _tapLands(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == box);
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

late FakeHyperliquidMoveRail _rail;

/// The app's layering (the bar over the root navigator, the route
/// observer, the scroll listener), the tab shell mounted, every read the
/// search sheet, the Investing page and its slip make overridden.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  kuteShellMounted.value = true;
  addTearDown(() => kuteShellMounted.value = false);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      // The search sheet.
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data([GlobalMarketSearchResult(_fed)])),
      globalHyperliquidResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data([_btcRow])),
      hyperliquidAllMarketsProvider.overrideWith((_) => [hlEditBtc]),
      // The Investing page.
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => hlEditBtc),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => hlEditBtc),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const []),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidLiveCandlesProvider.overrideWith((ref, key) =>
          Stream.value(HlLiveCandlesState(candles: hlEditCandles()))),
      hyperliquidTradeFlowProvider.overrideWith(
          (ref, coin) => Stream.value(const HlTradeFlowState())),
      // The order slip.
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: false,
          ))),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidMoveRailProvider.overrideWithValue(_rail),
      fundedOrdersProvider.overrideWith(_Funded.new),
      // The prediction's page and its bet slip.
      livePriceProvider.overrideWith(_PolyPrices.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polyGameLinesProvider
          .overrideWith((ref, slug) => Completer<PolyGameLines>().future),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polyWatchlistProvider.overrideWith(_NoStars.new),
      polymarketTradingProvider.overrideWith(_PolyTrading.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
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
        navigatorKey: AppRouter.rootNavigatorKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) => Stack(children: [
          NotificationListener<ScrollNotification>(
            onNotification: kuteBarScroll.report,
            child: child!,
          ),
          const KuteShellBar(),
        ]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await _frames(tester, 5);
}

/// The pill opens the search sheet, the query lists [row].
Future<void> _search(WidgetTester tester, String query, Finder row) async {
  await tester.tap(find.byType(KuteSalPill));
  await _frames(tester, 8);
  expect(find.byType(UnifiedSearchSurface), findsOneWidget);
  expect(_morphed, findsOneWidget);
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _frames(tester, 6);
  // The keyboard is not up in a test; the row is on screen.
  expect(row, findsOneWidget);
}

/// The Investing market page is up (from wherever): its trade row, then
/// Invest's order slip, whose primary takes an amount and the tap,
/// beside the round share button; back down to the page.
Future<void> _investingSlip(WidgetTester tester) async {
  expect(find.byType(HlMarketDetailSheet), findsOneWidget);
  // The page has its own bar: Invest | Short and Sal.
  expect(_morphed, findsNothing);
  expect(_barUp(tester), isTrue);
  final invest = find.byKey(const ValueKey('kute-bar-trade-invest'));
  expect(invest, findsOneWidget);
  expect(_tapLands(tester, invest), isTrue);

  await tester.tap(invest);
  await _frames(tester, 15);
  expect(find.byType(HlOrderSlipSheet), findsOneWidget);
  await _expectSlipPrimary(tester, ['1', '2'], '12');

  _nav().pop();
  await _frames(tester);
  expect(invest, findsOneWidget);
}

/// The prediction's page is up: Yes | No, then Yes's bet slip, whose
/// primary takes an amount and the tap, beside the round share button;
/// back down to the page.
Future<void> _predictionSlip(WidgetTester tester) async {
  expect(find.byType(MarketDetailSheet), findsOneWidget);
  expect(_morphed, findsNothing);
  expect(_barUp(tester), isTrue);
  final yes = find.byKey(const ValueKey('kute-bar-trade-yes'));
  expect(yes, findsOneWidget);
  expect(_tapLands(tester, yes), isTrue);

  await tester.tap(yes);
  await _frames(tester, 15);
  expect(find.byType(BetSlipSheet), findsOneWidget);
  await _expectSlipPrimary(tester, ['1', '0'], '10');

  _nav().pop();
  await _frames(tester);
  expect(yes, findsOneWidget);
}

/// The slip's one action is the bar: up, the round share button beside
/// it, and once [keys] are typed on the slip's keypad, enabled with the
/// amount and taking the tap.
Future<void> _expectSlipPrimary(
    WidgetTester tester, List<String> keys, String amount) async {
  expect(_barUp(tester), isTrue);
  expect(_primary, findsOneWidget);
  expect(_share, findsOneWidget);
  expect(_tapLands(tester, _share), isTrue);
  final pad = find.byType(AmountKeypad);
  for (final k in keys) {
    await tester.tap(find.descendant(of: pad, matching: find.text(k)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _frames(tester, 5);
  final ctx = tester
      .widget<KuteBarPrimaryButton>(find.byType(KuteBarPrimaryButton))
      .barContext;
  expect(ctx.actionable, isTrue, reason: ctx.primaryLabel);
  expect(ctx.primaryLabel, contains(amount));
  expect(_tapLands(tester, _primary), isTrue);
}

/// [body] with the slips' own gate reading a policy that allows
/// everything, and no network.
Future<void> _withPolicy(Future<void> Function() body) async {
  AffiliateService.debugSessionToken = 'test-session';
  final policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
  try {
    await http.runWithClient(
        body, () => MockClient((_) async => http.Response('[]', 200)));
  } finally {
    policy.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  }
}

/// Closes the sheet the pill became: it holds the pill again while on
/// top, and lands back on it.
Future<void> _closeSearch(WidgetTester tester) async {
  expect(find.byType(UnifiedSearchSurface), findsOneWidget);
  expect(_morphed, findsOneWidget);
  _nav().pop();
  await _frames(tester, 10);
  expect(_morphed, findsNothing);
  expect(find.byType(KuteSalPill), findsOneWidget);
  expect(_barUp(tester), isTrue);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The recents store and the order slip's boxes.
    Hive.init(Directory.systemTemp.createTempSync('search-slip').path);
    expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue);
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
    _rail = FakeHyperliquidMoveRail();
  });

  testWidgets(
      'Investing from search: the market page has its trade row, Invest '
      'opens the order slip and its primary is there, enabled with an '
      'amount and taking the tap, beside the round share button',
      (tester) async {
    await _withPolicy(() async {
      await _pump(tester);
      await _search(tester, 'btc', find.byType(SearchInvestingRow));
      await tester.tap(find.byType(SearchInvestingRow));
      await _frames(tester);
      await _investingSlip(tester);
      _nav().pop();
      await _frames(tester);
      await _closeSearch(tester);
      await _end(tester);
    });
  });

  testWidgets(
      'a prediction from search: the market page has Yes | No, Yes opens '
      'the bet slip and its primary is there, enabled with an amount and '
      'taking the tap, beside the round share button', (tester) async {
    await _withPolicy(() async {
      await _pump(tester);
      await _search(tester, 'fed', find.byType(SearchPredictionRow));
      await tester.tap(find.byType(SearchPredictionRow));
      await _frames(tester);
      await _predictionSlip(tester);
      _nav().pop();
      await _frames(tester);
      await _closeSearch(tester);
      await _end(tester);
    });
  });

  testWidgets(
      'straight from the market page (no search): both slips keep their '
      'primary', (tester) async {
    await _withPolicy(() async {
      await _pump(tester);
      final home = _nav().context;
      HlMarketDetailSheet.show(home, market: hlEditBtc, source: 'test');
      await _frames(tester);
      await _investingSlip(tester);
      _nav().pop();
      await _frames(tester);
      MarketDetailSheet.show(home, event: _fed, source: 'test');
      await _frames(tester);
      await _predictionSlip(tester);
      _nav().pop();
      await _frames(tester);
      await _end(tester);
    });
  });

  testWidgets(
      'the Dollars Send\'s "Send an investment or prediction": a market '
      'picked opens its page over the pick sheet, and its slip keeps its '
      'primary and the round share button', (tester) async {
    SendPickMarketSheet.debugFeeds =
        (predictions: [_fed], investing: [hlEditBtc]);
    addTearDown(() => SendPickMarketSheet.debugFeeds = null);
    await _withPolicy(() async {
      await _pump(tester);
      unawaited(showSendPickMarketSheet(_nav().context, entrySource: 'test'));
      await _frames(tester, 8);
      expect(find.byType(SendPickMarketSheet), findsOneWidget);

      await tester.tap(find.byType(SearchPredictionRow).first);
      await _frames(tester);
      await _predictionSlip(tester);
      _nav().pop();
      await _frames(tester);

      await tester.tap(find.byType(SearchInvestingRow).first);
      await _frames(tester);
      await _investingSlip(tester);
      _nav().pop();
      await _frames(tester);
      expect(find.byType(SendPickMarketSheet), findsOneWidget);
      await _end(tester);
    });
  });
}
