// The card's buttons roll to the next window partway through this one
// (founder, 8 November 2026), with a fake clock and fake books: before and
// after the moment, the next window without prices (to the very end), a tap
// at the moment, a slip open across it, the rollover, someone holding this
// window, the name on the slip, the gate. The chart, target and countdown
// stay on this window throughout, and the card never changes height.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/round_heartbeat.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show polyPositionRowTitle;
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/current_round.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';

final roundStart = DateTime.utc(2026, 11, 8, 12, 0);
final nextStart = roundStart.add(const Duration(minutes: 5));
int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
String slugAt(DateTime t) => 'btc-updown-5m-${_epoch(t)}';

Btc5MinEvent windowEvent(DateTime start, String tokens, {double up = 0.905}) =>
    Btc5MinEvent(
      slug: slugAt(start),
      title: 'Bitcoin Up or Down - November 8, 7:00AM-7:05AM ET',
      windowStartTime: start,
      endDate: start.add(const Duration(minutes: 5)),
      upPrice: up,
      downPrice: 1 - up,
      upTokenId: '$tokens-up',
      downTokenId: '$tokens-down',
      conditionId: '$tokens-cond',
    );

/// The card's window, on a clock the test moves ([bump] repaints as the
/// provider's one-second countdown does).
class RoundState extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async => CryptoPredictState(
        asset: arg,
        currentPrice: 75965,
        priceToBeat: 75987,
        secondsRemaining: 179,
        priceHistory: [
          for (var i = 0; i < 30; i++)
            BtcPriceSnapshot(
                timestamp: roundStart.add(Duration(seconds: i * 4)),
                price: 75987 + (i % 7) * 6.0 - 12 - i),
        ],
        event: windowEvent(roundStart, 'cur'),
      );

  void bump() {
    final prev = state.requireValue;
    state = AsyncData(prev.copyWith(secondsRemaining: prev.secondsRemaining));
  }

  void rollTo(Btc5MinEvent event) {
    final prev = state.requireValue;
    state = AsyncData(prev.copyWith(event: event, secondsRemaining: 299));
  }
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(usdcBalance: 100);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

/// The test's world: what time it is, whether Gamma lists the next window,
/// and the live feed's books.
class CardWorld {
  DateTime now = roundStart.add(const Duration(minutes: 1));
  bool listed = true;
  int reads = 0;
  double currentUp = 0.905;

  void seedBook(String token, double bid, double ask) =>
      PolymarketLiveBooks.instance.debugSeed(PolymarketBookMessage(
        assetId: token,
        market: 'm',
        timestamp: 0,
        hash: '',
        bids: [PolymarketOrderSummary(price: bid, size: 500)],
        asks: [PolymarketOrderSummary(price: ask, size: 500)],
      ));

  /// The next window quoted 50/51, the founder's 50.5% / 49.5%.
  void quoteNext() {
    seedBook('next-up', 0.50, 0.51);
    seedBook('next-down', 0.49, 0.50);
  }

  void quoteCurrent() {
    seedBook('cur-up', currentUp - 0.005, currentUp + 0.005);
    seedBook('cur-down', 1 - currentUp - 0.005, 1 - currentUp + 0.005);
  }

  List<Override> overrides({List<PolymarketPosition> positions = const []}) => [
        cryptoPredictProvider.overrideWith(RoundState.new),
        cryptoRecentResultsProvider.overrideWith((ref, key) async => const [
              CryptoWindowResult(1, true),
              CryptoWindowResult(2, false),
              CryptoWindowResult(3, true),
              CryptoWindowResult(4, false),
            ]),
        cryptoOddsClockProvider.overrideWithValue(() => now),
        cryptoOddsForegroundProvider.overrideWithValue(() => true),
        cryptoOddsMidpointsProvider.overrideWithValue((_) async => const {}),
        polyRoundWindowReaderProvider
            .overrideWithValue((asset, start, minutes) async {
          reads++;
          expect(asset, 'btc');
          expect(minutes, 5);
          return listed && start == _epoch(nextStart)
              ? windowEvent(nextStart, 'next', up: 0.5)
              : null;
        }),
        polymarketActivePositionsProvider.overrideWithValue(positions),
        settingsProvider.overrideWith((ref) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true,
            ))),
        polymarketTradingProvider.overrideWith(_Trading.new),
        swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
        livePriceProvider.overrideWith(_Prices.new),
        polymarketOpenOrdersProvider
            .overrideWith((ref) => Stream.value(const [])),
        aiEnabledProvider.overrideWith((ref) async => false),
        usdBalanceProvider.overrideWithValue(0),
        currencyProvider.overrideWith((ref) => _Currency()),
      ];

  void install() {
    PolymarketLiveBooks.instance
      ..reset()
      ..clock = () => now;
  }
}

Widget cardApp(CardWorld world,
        {bool compact = true,
        bool dark = false,
        Locale? locale,
        List<PolymarketPosition> positions = const []}) =>
    ProviderScope(
      overrides: world.overrides(positions: positions),
      child: shellBarApp(
        dark: dark,
        locale: locale,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: CryptoPredictBanner(
                  key: const ValueKey('card'),
                  config: kCryptoPredictAssets.first,
                  compact: compact,
                ),
              ),
            ),
          ),
        ),
      ),
    );

const _next = ValueKey('crypto-round-next');
const _upPill = ValueKey('crypto-round-up');
const _downPill = ValueKey('crypto-round-down');
const _compact = ValueKey('crypto-round-compact');

/// The clock labels the test runner's zone gives this window.
String nextClock() => polyRoundClock(nextStart, locale: 'en');
String windowName(DateTime start) =>
    'BTC up or down · ${polyRoundClock(start, locale: 'en')}'
    '$kPolyRoundRangeJoin–$kPolyRoundRangeJoin'
    '${polyRoundClock(start.add(const Duration(minutes: 5)), locale: 'en')}';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The clock moves to [at] and the card repaints on its one-second tick.
Future<void> moveTo(WidgetTester tester, CardWorld world, DateTime at) async {
  world.now = at;
  final container = ProviderScope.containerOf(tester
      .element(find.byKey(const ValueKey('card'), skipOffstage: false)));
  (container.read(cryptoPredictProvider('BTC').notifier) as RoundState).bump();
  await settle(tester);
}

/// What the pill says to a screen reader, its side, chance and window: the
/// digits on screen roll, this is the figure they roll to.
bool pillSays(WidgetTester tester, Key key, String label) => tester
    .widgetList<Semantics>(find.descendant(
        of: find.byKey(key, skipOffstage: false),
        matching: find.byType(Semantics, skipOffstage: false)))
    .followedBy(tester.widgetList<Semantics>(find.ancestor(
        of: find.byKey(key, skipOffstage: false),
        matching: find.byType(Semantics, skipOffstage: false))))
    .any((w) => w.properties.label == label);

void _expectThisWindowOnShow() {
  expect(find.text(r'Target $75,987'), findsOneWidget);
  expect(find.text('02:59'), findsOneWidget);
  expect(find.textContaining(r'$75,965'), findsNothing,
      reason: 'the price rolls digit by digit');
}

void main() {
  late CardWorld world;
  late List<(String, Map<String, Object>?)> events;
  final moment = roundStart.add(kCryptoRoundButtonsStayFor);

  setUpAll(() async {
    // The real face: the test font's square glyphs overflow the full
    // card's buttons with or without this feature.
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    world = CardWorld()..install();
    BetSlipSheet.debugClock = () => world.now;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    installShellBar();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    BetSlipSheet.debugClock = DateTime.now;
    PolymarketLiveBooks.instance.reset();
  });

  Future<void> pumpCard(WidgetTester tester,
      {bool compact = true,
      List<PolymarketPosition> positions = const []}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        cardApp(world, compact: compact, positions: positions));
    await settle(tester);
  }

  Future<void> tearCardDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  }

  Map<String, Object> slipOpened() =>
      events.lastWhere((e) => e.$1 == 'polymarket_bet_slip_opened').$2!;

  group('before the moment', () {
    testWidgets('the buttons bet on this window, as today', (tester) async {
      world.now = moment.subtract(const Duration(seconds: 1));
      world.quoteNext();
      world.quoteCurrent();
      await pumpCard(tester);
      expect(find.byKey(_next), findsNothing);
      await tester.tap(find.byKey(_upPill));
      await tester.pump();
      await settle(tester);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.marketSlug, slugAt(roundStart));
      expect(slip.outcomes.map((o) => o.tokenId), ['cur-up', 'cur-down']);
      expect(slipOpened()['window'], 'current');
      expect(slipOpened()['seconds_to_window_end'], isA<int>());
      await tearCardDown(tester);
    });
  });

  group('after the moment', () {
    testWidgets(
        'the buttons read as the next window, this window stays on show, '
        'the card keeps its height', (tester) async {
      world.quoteNext();
      await pumpCard(tester);
      final before = tester.getSize(find.byKey(_compact)).height;
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      expect(find.text('Next · ${nextClock()}'), findsOneWidget);
      expect(find.text('Up'), findsOneWidget);
      final next = 'Next · ${nextClock()}';
      expect(pillSays(tester, _upPill, '$next, Up 50.5%'), isTrue);
      expect(pillSays(tester, _downPill, '$next, Down 49.5%'), isTrue);
      _expectThisWindowOnShow();
      expect(tester.getSize(find.byKey(_compact)).height, before,
          reason: 'the list under the card never jumps');
      expect(tester.takeException(), isNull);
      await tearCardDown(tester);
    });

    testWidgets('a tap bets the next window, named on the slip, on its live '
        'odds and answering to the same gate', (tester) async {
      world.quoteNext();
      await pumpCard(tester);
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      await tester.tap(find.byKey(_downPill));
      await tester.pump();
      await settle(tester);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.marketSlug, slugAt(nextStart));
      expect(slip.outcomes.map((o) => o.tokenId), ['next-up', 'next-down']);
      expect(slip.outcomes.map((o) => o.conditionId),
          ['next-cond', 'next-cond']);
      expect(slip.outcomes[0].price, closeTo(0.505, 1e-9));
      expect(slip.outcomes[1].price, closeTo(0.495, 1e-9));
      expect(slip.initialOutcomeIndex, 1);
      expect(slip.marketEndAt, nextStart.add(const Duration(minutes: 5)));
      expect(slip.marketCategory, 'crypto');
      expect(slip.source, 'crypto_banner');
      expect(find.text(windowName(nextStart)), findsOneWidget);
      final opened = slipOpened();
      expect(opened['window'], 'next');
      expect(opened['entry_source'], 'crypto_banner');
      await tearCardDown(tester);
    });

    testWidgets('the full card rolls the same, its split bar with it',
        (tester) async {
      world.quoteNext();
      await pumpCard(tester, compact: false);
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      expect(find.text('Next · ${nextClock()}'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.505, 1e-9));
      expect(find.text(r'Target $75,987'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tearCardDown(tester);
    });
  });

  group('no real prices for the next window', () {
    final veryEnd = roundStart.add(const Duration(minutes: 4, seconds: 58));

    testWidgets('not listed: stays on this window to the very end, and '
        'asks again', (tester) async {
      world.listed = false;
      world.now = moment;
      await pumpCard(tester);
      expect(world.reads, 1);
      await moveTo(tester, world, veryEnd);
      expect(find.byKey(_next), findsNothing);
      await tester.tap(find.byKey(_upPill));
      await tester.pump();
      await settle(tester);
      expect(tester.widget<BetSlipSheet>(find.byType(BetSlipSheet)).marketSlug,
          slugAt(roundStart));
      await tearCardDown(tester);
    });

    testWidgets('listed with no book: stays; the book arrives: rolls',
        (tester) async {
      world.now = moment;
      await pumpCard(tester);
      expect(find.byKey(_next), findsNothing);
      expect(find.textContaining('50.5%'), findsNothing,
          reason: 'never Gamma\'s price standing in');
      world.quoteNext();
      await moveTo(tester, world, moment.add(const Duration(seconds: 1)));
      expect(find.byKey(_next), findsOneWidget);
      await tearCardDown(tester);
    });

    testWidgets('a wide book is no price', (tester) async {
      world.now = moment;
      world.seedBook('next-up', 0.01, 0.99);
      world.seedBook('next-down', 0.01, 0.99);
      await pumpCard(tester);
      await moveTo(tester, world, veryEnd);
      world.seedBook('next-up', 0.01, 0.99);
      world.seedBook('next-down', 0.01, 0.99);
      await moveTo(tester, world, veryEnd);
      expect(find.byKey(_next), findsNothing);
      await tearCardDown(tester);
    });

    testWidgets('a feed gone quiet is no price: back on this window, and '
        'rolled again once it answers', (tester) async {
      world.now = moment;
      world.quoteNext();
      await pumpCard(tester);
      expect(find.byKey(_next), findsOneWidget);
      await moveTo(tester, world, moment.add(const Duration(seconds: 6)));
      expect(find.byKey(_next), findsNothing,
          reason: 'a book older than the feed\'s own limit is stale');
      world.quoteNext();
      await moveTo(tester, world, moment.add(const Duration(seconds: 7)));
      expect(find.byKey(_next), findsOneWidget);
      await tearCardDown(tester);
    });
  });

  testWidgets('a tap at the moment bets what the buttons showed',
      (tester) async {
    world.now = moment.subtract(const Duration(milliseconds: 100));
    await pumpCard(tester);
    // The next window read and quoted, the moment passed, no repaint yet:
    // the finger lands on what is on screen.
    await moveTo(tester, world, moment.subtract(const Duration(milliseconds: 50)));
    world.quoteNext();
    world.now = moment.add(const Duration(milliseconds: 1));
    expect(find.byKey(_next), findsNothing);
    await tester.tap(find.byKey(_upPill));
    await tester.pump();
    await settle(tester);
    expect(tester.widget<BetSlipSheet>(find.byType(BetSlipSheet)).marketSlug,
        slugAt(roundStart));
    await tearCardDown(tester);
  });

  testWidgets('a slip open across the moment and the rollover stays on the '
      'window it opened for', (tester) async {
    world.quoteNext();
    await pumpCard(tester);
    await tester.tap(find.byKey(_upPill));
    await tester.pump();
    await settle(tester);
    final opened = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
    expect(opened.marketSlug, slugAt(roundStart));
    final shownName = windowName(roundStart);
    expect(find.text(shownName), findsOneWidget);

    await moveTo(tester, world, moment);
    world.quoteNext();
    await moveTo(tester, world, moment);
    // The card behind has rolled; the slip has not.
    expect(find.text('Next · ${nextClock()}', skipOffstage: false),
        findsOneWidget);
    final still = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
    expect(still.marketSlug, slugAt(roundStart));
    expect(still.outcomes.map((o) => o.tokenId), ['cur-up', 'cur-down']);
    expect(find.text(shownName), findsOneWidget);
    expect(find.text(windowName(nextStart)), findsNothing);

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('card'), skipOffstage: false)));
    (container.read(cryptoPredictProvider('BTC').notifier) as RoundState)
        .rollTo(windowEvent(nextStart, 'next', up: 0.5));
    world.now = nextStart.add(const Duration(seconds: 1));
    await settle(tester);
    expect(tester.widget<BetSlipSheet>(find.byType(BetSlipSheet)).marketSlug,
        slugAt(roundStart));
    expect(find.text(shownName), findsOneWidget);
    await tearCardDown(tester);
  });

  group('the rollover', () {
    testWidgets('past the end the buttons hold the next window, then the '
        'card rolls forward onto it as today', (tester) async {
      world.quoteNext();
      await pumpCard(tester);
      await moveTo(tester, world, moment);
      world.quoteNext();
      // The window's end: the card has not read the new one yet.
      await moveTo(tester, world, nextStart);
      world.quoteNext();
      await moveTo(tester, world, nextStart);
      expect(find.byKey(_next), findsOneWidget);
      expect(pillSays(tester, _upPill, 'Next · ${nextClock()}, Up 50.5%'),
          isTrue);

      final container = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('card'))));
      (container.read(cryptoPredictProvider('BTC').notifier) as RoundState)
          .rollTo(windowEvent(nextStart, 'next', up: 0.5));
      world.now = nextStart.add(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byKey(_next), findsNothing,
          reason: 'it is this window now');
      await tester.tap(find.byKey(_upPill));
      await tester.pump();
      await settle(tester);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.marketSlug, slugAt(nextStart));
      expect(slipOpened()['window'], 'current');
      await tearCardDown(tester);
    });

    testWidgets('the next window\'s own first minutes do not roll on to the '
        'one after', (tester) async {
      world.quoteNext();
      await pumpCard(tester);
      final container = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('card'))));
      (container.read(cryptoPredictProvider('BTC').notifier) as RoundState)
          .rollTo(windowEvent(nextStart, 'next', up: 0.5));
      world.now = nextStart.add(const Duration(minutes: 1));
      await settle(tester);
      expect(find.byKey(_next), findsNothing);
      await tearCardDown(tester);
    });
  });

  group('holding this window', () {
    PolymarketPosition held() => PolymarketPosition(
          marketId: 'cur-cond',
          marketQuestion: 'Bitcoin Up or Down - November 8, 7:00AM-7:05AM ET',
          outcome: 'Up',
          size: 20,
          avgPrice: 0.5,
          currentPrice: 0.905,
          pnl: 8.1,
          pnlPercent: 81,
          isResolved: false,
          tokenId: 'cur-up',
          eventSlug: slugAt(roundStart),
        );

    testWidgets('the position names its own window, the card\'s buttons the '
        'next', (tester) async {
      world.quoteNext();
      await pumpCard(tester);
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      final context = tester.element(find.byKey(const ValueKey('card')));
      expect(polyPositionRowTitle(context, held(), null),
          windowName(roundStart));
      expect(find.text('Next · ${nextClock()}'), findsOneWidget);
      await tearCardDown(tester);
    });

    testWidgets('the heartbeat still reads this window; its chart and target '
        'stay, whichever window the buttons offer', (tester) async {
      world.quoteNext();
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: world.overrides(positions: [held()]),
        child: shellBarApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoundHeartbeat(
                asset: 'BTC',
                child: CryptoPredictBanner(
                  key: const ValueKey('card'),
                  config: kCryptoPredictAssets.first,
                ),
              ),
            ),
          ),
        ),
      ));
      await settle(tester);
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      expect(find.byKey(_next), findsOneWidget);
      expect(find.text(r'Target $75,987'), findsOneWidget);
      final container = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('card'))));
      final shownEvent =
          container.read(cryptoPredictProvider('BTC')).requireValue.event!;
      expect(shownEvent.upTokenId, 'cur-up',
          reason: 'the card\'s own window is the held one');
      expect(tester.takeException(), isNull);
      await tearCardDown(tester);
    });
  });

  group('the gate', () {
    testWidgets('the next window answers to the same capabilities',
        (tester) async {
      AffiliateService.debugSessionToken = 'test-session';
      final policy = runtimePolicyFixture(blocked: const {'polymarket.trade'});
      RuntimeCapabilitiesService.debugInstance = policy;
      addTearDown(() {
        RuntimeCapabilitiesService.debugInstance = null;
        AffiliateService.debugSessionToken = null;
      });
      await tester.runAsync(() async {
        expect(await policy.refresh(), isTrue);
      });
      world.quoteNext();
      await pumpCard(tester);
      await moveTo(tester, world, moment);
      world.quoteNext();
      await moveTo(tester, world, moment);
      await tester.tap(find.byKey(_upPill));
      await tester.pump();
      await settle(tester);
      expect(tester.widget<BetSlipSheet>(find.byType(BetSlipSheet)).marketSlug,
          slugAt(nextStart));
      expect(find.text('This feature is currently unavailable in Kute.'),
          findsOneWidget,
          reason: 'blocked on the next window exactly as on this one');
      await tearCardDown(tester);
      policy.dispose();
    });
  });
}
