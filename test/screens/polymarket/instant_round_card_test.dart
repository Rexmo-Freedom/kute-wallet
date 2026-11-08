// The Instant screen's one card (instant_round_card.dart) on a fake clock,
// fake Gamma reads and fake books: the strip of rounds, which round the one
// pair of buttons bets on (the roll by default, a tap until the round
// starts or ends), a round without prices, the slip on the picked round,
// the held marker, and the longer lengths' chart window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:kute/screens/home/components/btc_predict_chart.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/instant_round_card.dart';
import 'package:kute/screens/polymarket/components/instant_round_strip.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/current_round.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

final roundStart = DateTime.utc(2026, 11, 8, 12, 0);
int epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Gamma's event of the [minutes] round starting at [start].
Btc5MinEvent roundEvent(DateTime start, String tokens,
        {int minutes = 5, double up = 0.6}) =>
    Btc5MinEvent(
      slug: polyCryptoRoundSlug('btc', minutes, epoch(start)),
      title: 'Bitcoin Up or Down - November 8',
      windowStartTime: start,
      endDate: start.add(Duration(minutes: minutes)),
      upPrice: up,
      downPrice: 1 - up,
      upTokenId: '$tokens-up',
      downTokenId: '$tokens-down',
      conditionId: '$tokens-cond',
    );

/// The round in play, on the test's clock; [bump] repaints as the
/// notifier's one-second countdown does, [rollTo] moves to a new window.
class InstantRoundState extends CryptoRoundNotifier {
  InstantRoundState(this.world);
  final CardWorld world;

  @override
  Future<CryptoPredictState> build(CryptoRoundKey arg) async {
    world.built.add(arg);
    ref.onDispose(() => world.alive.remove(arg));
    world.alive.add(arg);
    final minutes = arg.minutes;
    final start = DateTime.fromMillisecondsSinceEpoch(
        polyRoundStartAt(world.now, minutes) * 1000,
        isUtc: true);
    final span = minutes * 60;
    return CryptoPredictState(
      asset: arg.asset,
      currentPrice: 75965,
      priceToBeat: 75987,
      secondsRemaining: span - world.now.difference(start).inSeconds,
      priceHistory: [
        // From a minute before the round opened (the backfill) to now.
        for (var t = -60; t <= world.now.difference(start).inSeconds; t += 4)
          BtcPriceSnapshot(
              timestamp: start.add(Duration(seconds: t)),
              price: 75987 + (t % 7) * 6.0 - 12 - t / 20),
      ],
      event: roundEvent(start, 'cur', minutes: minutes),
    );
  }

  /// The one-second tick: the time left follows the clock.
  void bump() {
    final prev = state.requireValue;
    final end = prev.event?.endDate;
    final left = end == null ? prev.secondsRemaining : end.difference(world.now).inSeconds;
    state = AsyncData(prev.copyWith(secondsRemaining: left < 0 ? 0 : left));
  }

  void rollTo(Btc5MinEvent event) {
    final prev = state.requireValue;
    state = AsyncData(prev.copyWith(event: event, secondsRemaining: 299));
  }
}

class _Prices extends LivePriceNotifier {
  _Prices(this.world);
  final CardWorld world;
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokens) {
    for (final t in tokens) {
      world.socketTokens[t] = (world.socketTokens[t] ?? 0) + 1;
    }
  }

  @override
  void unregisterCardTokens(List<String> tokens) {
    for (final t in tokens) {
      final n = (world.socketTokens[t] ?? 0) - 1;
      if (n <= 0) {
        world.socketTokens.remove(t);
      } else {
        world.socketTokens[t] = n;
      }
    }
  }

  @override
  void unsubscribeAll() {}
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

/// The test's world: the clock, what Gamma lists ahead, the books, and
/// what the card has asked for.
class CardWorld {
  DateTime now = roundStart.add(const Duration(minutes: 1));

  /// Gamma's rounds ahead by start (UTC seconds).
  final Map<int, Btc5MinEvent> listed = {};
  final Set<CryptoRoundKey> built = {};
  final Set<CryptoRoundKey> alive = {};
  final Map<String, int> socketTokens = {};
  List<PolymarketPosition> positions = const [];

  /// The feed's quotes; a real feed streams them, so every move of the
  /// clock seeds them again ([requote]), as the roll's own test does.
  final Map<String, (double, double)> quotes = {};

  void seedBook(String token, double bid, double ask) {
    quotes[token] = (bid, ask);
    PolymarketLiveBooks.instance.debugSeed(PolymarketBookMessage(
      assetId: token,
      market: 'm',
      timestamp: 0,
      hash: '',
      bids: [PolymarketOrderSummary(price: bid, size: 500)],
      asks: [PolymarketOrderSummary(price: ask, size: 500)],
    ));
  }

  void requote() {
    for (final e in quotes.entries) {
      seedBook(e.key, e.value.$1, e.value.$2);
    }
  }

  /// The books go silent: nothing is quoted any more.
  void silence() {
    quotes.clear();
    PolymarketLiveBooks.instance.reset();
    install();
  }

  /// The next round listed and quoted 50/51.
  void listNext({int minutes = 5}) {
    final start = roundStart.add(Duration(minutes: minutes));
    listed[epoch(start)] = roundEvent(start, 'next', minutes: minutes, up: 0.5);
    seedBook('next-up', 0.50, 0.51);
    seedBook('next-down', 0.49, 0.50);
  }

  /// The one after listed and quoted too.
  void listLater({int minutes = 5}) {
    final start = roundStart.add(Duration(minutes: 2 * minutes));
    listed[epoch(start)] =
        roundEvent(start, 'later', minutes: minutes, up: 0.5);
    seedBook('later-up', 0.50, 0.51);
    seedBook('later-down', 0.49, 0.50);
  }

  void quoteCurrent() {
    seedBook('cur-up', 0.595, 0.605);
    seedBook('cur-down', 0.395, 0.405);
  }

  List<Override> overrides() => [
        cryptoRoundProvider.overrideWith(() => InstantRoundState(this)),
        cryptoRecentResultsProvider.overrideWith((ref, key) async => [
              CryptoWindowResult(key.currentStart - 4 * key.minutes * 60, true),
              CryptoWindowResult(key.currentStart - 3 * key.minutes * 60, false),
              CryptoWindowResult(key.currentStart - 2 * key.minutes * 60, true),
              CryptoWindowResult(key.currentStart - key.minutes * 60, null),
            ]),
        cryptoOddsClockProvider.overrideWithValue(() => now),
        cryptoOddsForegroundProvider.overrideWithValue(() => true),
        cryptoOddsMidpointsProvider.overrideWithValue((_) async => const {}),
        polyRoundWindowReaderProvider
            .overrideWithValue((asset, start, minutes) async {
          expect(asset, 'BTC');
          return listed[start];
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
        livePriceProvider.overrideWith(() => _Prices(this)),
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

const cardKey = ValueKey('card');

Widget cardApp(CardWorld world, {String length = '5m'}) => ProviderScope(
      overrides: world.overrides(),
      child: shellBarApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: InstantRoundCard(
                  key: cardKey,
                  config: kCryptoPredictAssets.first,
                  length: length,
                ),
              ),
            ),
          ),
        ),
      ),
    );

const _upPill = ValueKey('crypto-round-up');
const _downPill = ValueKey('crypto-round-down');
const _next = ValueKey('crypto-round-next');

String clockOf(DateTime t) => polyRoundClock(t, locale: 'en');
String windowName(DateTime start, {int minutes = 5}) =>
    'BTC up or down · ${clockOf(start)}–'
    '${clockOf(start.add(Duration(minutes: minutes)))}';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The clock moves to [at] and the card repaints on its one-second tick.
Future<void> moveTo(WidgetTester tester, CardWorld world, DateTime at,
    {int minutes = 5}) async {
  world.now = at;
  world.requote();
  final container = ProviderScope.containerOf(
      tester.element(find.byKey(cardKey, skipOffstage: false)));
  (container.read(cryptoRoundProvider((asset: 'BTC', minutes: minutes)).notifier)
          as InstantRoundState)
      .bump();
  await settle(tester);
}

bool pillSelected(WidgetTester tester, int start) => tester
    .widget<KutePill>(find.byKey(InstantRoundStrip.pillKey(start)))
    .selected;

void main() {
  late CardWorld world;
  late List<(String, Map<String, Object>?)> events;
  final nextStart = roundStart.add(const Duration(minutes: 5));
  final laterStart = roundStart.add(const Duration(minutes: 10));
  final moment = roundStart.add(kCryptoRoundButtonsStayFor);

  setUpAll(() async {
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

  Future<void> pumpCard(WidgetTester tester, {String length = '5m'}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(cardApp(world, length: length));
    await settle(tester);
  }

  Future<void> tearCardDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  }

  Future<BetSlipSheet> openUp(WidgetTester tester) async {
    await tester.tap(find.byKey(_upPill));
    await tester.pump();
    await settle(tester);
    return tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
  }

  Iterable<(String, Map<String, Object>?)> picks() =>
      events.where((e) => e.$1 == 'predictions_instant_round_picked');

  testWidgets('one pair of buttons, the strip, the round in play by default',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    expect(find.byKey(_upPill), findsOneWidget);
    expect(find.byKey(_downPill), findsOneWidget);
    expect(find.byKey(const ValueKey('instant-round-strip')), findsOneWidget);
    // Four results as dots, then Now, Next and the one after.
    expect(find.byKey(const ValueKey('crypto-round-past-dots')), findsOneWidget);
    expect(find.text('Now · 04:00', findRichText: true), findsOneWidget);
    expect(find.text('Next · ${clockOf(nextStart)}', findRichText: true),
        findsOneWidget);
    expect(find.textContaining(clockOf(laterStart), findRichText: true),
        findsOneWidget);
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    expect(pillSelected(tester, epoch(nextStart)), isFalse);
    expect(find.byKey(_next), findsNothing, reason: 'the round on show');
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    // The one after is listed by nobody: no prices, dimmed, no tap.
    final later = find.byKey(InstantRoundStrip.pillKey(epoch(laterStart)));
    expect(tester.widget<KutePill>(later).detail, 'No prices yet');
    await tester.tap(later);
    await settle(tester);
    expect(pillSelected(tester, epoch(laterStart)), isFalse);
    expect(picks(), isEmpty);
    final slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(roundStart)));
    expect(slip.outcomes.map((o) => o.tokenId), ['cur-up', 'cur-down']);
    await tearCardDown(tester);
  });

  testWidgets('a tap on Next: the buttons and the slip bet on it, the chart stays',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await tester.tap(find.byKey(InstantRoundStrip.pillKey(epoch(nextStart))));
    await settle(tester);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    expect(pillSelected(tester, epoch(roundStart)), isFalse);
    expect(find.text(windowName(nextStart)), findsOneWidget,
        reason: 'the card says which round the buttons are for');
    expect(find.text(r'Target $75,987'), findsOneWidget,
        reason: 'the target and the chart stay the live round');
    final pick = picks().single.$2!;
    expect(pick['which'], 'next');
    expect(pick['length'], '5m');
    expect(pick['seconds_to_start'], 240);
    final slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    expect(slip.outcomes.map((o) => o.tokenId), ['next-up', 'next-down']);
    expect(slip.outcomes.first.price, closeTo(0.505, 0.001),
        reason: 'the live odds on the button, never Gamma\'s');
    await tearCardDown(tester);
  });

  testWidgets('the default follows the roll: Next once this round is two minutes old',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    expect(find.text(windowName(nextStart)), findsOneWidget);
    expect(picks(), isEmpty, reason: 'nobody tapped');
    expect(find.text('Now · 03:00', findRichText: true), findsOneWidget,
        reason: 'the round on show stays on show');
    // Without prices on the next round the buttons stay here.
    world.silence();
    await moveTo(tester, world, moment.add(const Duration(seconds: 1)));
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    expect(tester
        .widget<KutePill>(find.byKey(InstantRoundStrip.pillKey(epoch(nextStart))))
        .detail, 'No prices yet');
    await tearCardDown(tester);
  });

  testWidgets('a tap on Now overrides the roll until this round ends',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    await tester.tap(find.byKey(InstantRoundStrip.pillKey(epoch(roundStart))));
    await settle(tester);
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    expect(find.byKey(_next), findsNothing);
    final pick = picks().single.$2!;
    expect(pick['which'], 'current');
    expect(pick['seconds_to_start'], -120);
    var slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(roundStart)));
    Navigator.of(tester.element(find.byType(BetSlipSheet))).pop();
    await settle(tester);
    // Later still, the pick stands.
    await moveTo(tester, world, roundStart.add(const Duration(minutes: 4)));
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    // The round ends and the card rolls on: the next round is now the one
    // on show, early, and the buttons are on it by the roll's own rule.
    world.listed.clear();
    world.silence();
    final after = roundStart.add(const Duration(minutes: 5, seconds: 2));
    world.now = after;
    final container =
        ProviderScope.containerOf(tester.element(find.byKey(cardKey)));
    (container.read(cryptoRoundProvider((asset: 'BTC', minutes: 5)).notifier)
            as InstantRoundState)
        .rollTo(roundEvent(nextStart, 'next'));
    await settle(tester);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    expect(find.byKey(_next), findsNothing);
    slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    await tearCardDown(tester);
  });

  testWidgets('a pick of Next stands until it starts', (tester) async {
    world.listNext();
    world.listLater();
    world.quoteCurrent();
    await pumpCard(tester);
    await tester.tap(find.byKey(InstantRoundStrip.pillKey(epoch(nextStart))));
    await settle(tester);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    // The one after has prices too: it can be picked, and is "later".
    await tester.tap(find.byKey(InstantRoundStrip.pillKey(epoch(laterStart))));
    await settle(tester);
    expect(pillSelected(tester, epoch(laterStart)), isTrue);
    expect(find.text(windowName(laterStart)), findsOneWidget);
    expect(picks().last.$2!['which'], 'later');
    final slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(laterStart)));
    expect(slip.outcomes.map((o) => o.tokenId), ['later-up', 'later-down']);
    await tearCardDown(tester);
  });

  testWidgets('a held round carries its marker on the strip', (tester) async {
    world.listNext();
    world.positions = [
      PolymarketPosition(
        marketId: 'held',
        marketQuestion: 'Bitcoin Up or Down',
        outcome: 'Up',
        size: 12,
        avgPrice: 0.5,
        currentPrice: 0.62,
        pnl: 1.44,
        pnlPercent: 24,
        isResolved: false,
        tokenId: 'cur-up',
        eventSlug: polyCryptoRoundSlug('btc', 5, epoch(roundStart)),
      ),
    ];
    await pumpCard(tester);
    expect(find.byKey(ValueKey('instant-round-held-${epoch(roundStart)}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('instant-round-held-${epoch(nextStart)}')),
        findsNothing);
    await tearCardDown(tester);
  });

  testWidgets('the sockets: this round\'s and the listed rounds\' tokens, gone with the card',
      (tester) async {
    world.listNext();
    await pumpCard(tester);
    expect(world.socketTokens.keys.toSet(),
        {'cur-up', 'cur-down', 'next-up', 'next-down'});
    expect(world.alive, {(asset: 'BTC', minutes: 5)});
    await tearCardDown(tester);
    expect(world.socketTokens, isEmpty);
    expect(world.alive, isEmpty);
  });

  for (final (length, minutes) in [('15m', 15), ('1h', 60), ('4h', 240)]) {
    testWidgets('$length: the whole round on the chart, the strip in its own steps',
        (tester) async {
      world.now = roundStart.add(const Duration(minutes: 7));
      world.install();
      world.listNext(minutes: minutes);
      await pumpCard(tester, length: length);
      expect(find.text('BTC up or down · $length'), findsOneWidget);
      final chart = tester.widget<BtcPredictChart>(find.byType(BtcPredictChart));
      expect(chart.maxWindow, Duration(minutes: minutes + 1),
          reason: 'the round from its start, not a sliding minute');
      expect(chart.roundStart, roundStart);
      expect(chart.externalHistory!.first.timestamp,
          roundStart.subtract(const Duration(minutes: 1)),
          reason: 'the backfill reaches before the open');
      final next = roundStart.add(Duration(minutes: minutes));
      expect(find.text('Next · ${clockOf(next)}', findRichText: true),
          findsOneWidget);
      expect(pillSelected(tester, epoch(roundStart)), isTrue,
          reason: 'no roll at this length');
      await tester.tap(find.byKey(InstantRoundStrip.pillKey(epoch(next))));
      await settle(tester);
      expect(find.text(windowName(next, minutes: minutes)), findsOneWidget);
      final slip = await openUp(tester);
      expect(slip.marketSlug, polyCryptoRoundSlug('btc', minutes, epoch(next)));
      await tearCardDown(tester);
    });
  }

  testWidgets('5m keeps the sliding minute', (tester) async {
    await pumpCard(tester);
    final chart = tester.widget<BtcPredictChart>(find.byType(BtcPredictChart));
    expect(chart.maxWindow, kBtcPredictChartWindow);
    await tearCardDown(tester);
  });
}
