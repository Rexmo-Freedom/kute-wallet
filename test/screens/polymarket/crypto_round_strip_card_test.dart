// The live round card's strip of rounds (CryptoPredictBanner,
// polymarket_screen.dart, under Crypto › 5 Min and on the round's own
// sheet; crypto_round_strip.dart) on a fake clock, fake Gamma reads and
// fake books: the past rounds, Now, Next and the one after under the
// chart, which round the one pair of buttons bets on (the roll by default,
// a tap until the round starts or ends), a round without prices, the slip
// on the picked round, the held marker, the sockets, the longer lengths
// and the full card. The Instant card's strip of 8 November 2026
// (b180992d), back after build 2.2.0 (101) (founder: "we also don't have
// the 'next' tab we can choose on the bottom").

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
import 'package:kute/providers/crypto_next_round_provider.dart'
    show kCryptoRoundNoteFor;
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
import 'package:kute/screens/polymarket/components/crypto_round_strip.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
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
        {int minutes = 5, double up = 0.6, String asset = 'btc'}) =>
    Btc5MinEvent(
      slug: polyCryptoRoundSlug(asset, minutes, epoch(start)),
      title: 'Bitcoin Up or Down - November 8',
      windowStartTime: start,
      endDate: start.add(Duration(minutes: minutes)),
      upPrice: up,
      downPrice: 1 - up,
      upTokenId: '$tokens-up',
      downTokenId: '$tokens-down',
      conditionId: '$tokens-cond',
    );

/// Each coin's live price and target on the test's clock.
const Map<String, (double, double)> kSpot = {
  'BTC': (75965, 75987),
  'ETH': (3471.12, 3470.02),
  'SOL': (182.44, 182.31),
  'XRP': (2.4312, 2.4305),
};

/// The card's round, at the chips' length, on the test's clock; [bump]
/// repaints as the notifier's one-second countdown does, [rollTo] moves to
/// a new window.
class StripRoundState extends CryptoPredictNotifier {
  StripRoundState(this.world);
  final CardWorld world;

  @override
  Future<CryptoPredictState> build(String arg) async {
    final minutes = ref.watch(cryptoPredictWindowProvider);
    final start = DateTime.fromMillisecondsSinceEpoch(
        polyRoundStartAt(world.now, minutes) * 1000,
        isUtc: true);
    final span = minutes * 60;
    // Bitcoin's figures as they always were; another coin (the rows under
    // the card on the 5 Min page) its own price, tokens and round.
    final (price, target) = kSpot[arg] ?? kSpot['BTC']!;
    final scale = target / 75987;
    final history = [
      for (var t = -60; t <= world.now.difference(start).inSeconds; t += 4)
        BtcPriceSnapshot(
            timestamp: start.add(Duration(seconds: t)),
            price: (75987 + (t % 7) * 6.0 - 12 - t / 20) * scale),
    ];
    if (world.eventless) {
      return CryptoPredictState(
          asset: arg, secondsRemaining: span, priceHistory: history);
    }
    return CryptoPredictState(
      asset: arg,
      currentPrice: price,
      priceToBeat: target,
      secondsRemaining: span - world.now.difference(start).inSeconds,
      priceHistory: history,
      event: arg == 'BTC'
          ? roundEvent(start, 'cur', minutes: minutes)
          : roundEvent(start, 'cur-${arg.toLowerCase()}',
              minutes: minutes, asset: arg.toLowerCase()),
    );
  }

  void bump() {
    final prev = state.requireValue;
    final end = prev.event?.endDate;
    final left = end == null
        ? prev.secondsRemaining
        : end.difference(world.now).inSeconds;
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

/// The test's world: the clock, the chips' length, what Gamma lists ahead,
/// the books, and what the card has asked for.
class CardWorld {
  DateTime now = roundStart.add(const Duration(minutes: 1));
  int minutes = 5;

  /// Gamma has no event for the round in play.
  bool eventless = false;

  /// Gamma's rounds ahead by start (UTC seconds).
  final Map<int, Btc5MinEvent> listed = {};
  final Map<String, int> socketTokens = {};
  List<PolymarketPosition> positions = const [];

  /// The feed's quotes; a real feed streams them, so every move of the
  /// clock seeds them again ([requote]).
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

  /// The next round listed and quoted 50/51, after [live] (the round in
  /// play's start, [roundStart] by default).
  void listNext({DateTime? live}) {
    final start = (live ?? roundStart).add(Duration(minutes: minutes));
    listed[epoch(start)] = roundEvent(start, 'next', minutes: minutes, up: 0.5);
    seedBook('next-up', 0.50, 0.51);
    seedBook('next-down', 0.49, 0.50);
  }

  /// The one after listed and quoted too.
  void listLater() {
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
        cryptoPredictWindowProvider.overrideWith((ref) => minutes),
        cryptoPredictProvider.overrideWith(() => StripRoundState(this)),
        cryptoRecentResultsProvider.overrideWith((ref, key) async => [
              CryptoWindowResult(key.currentStart - 4 * key.minutes * 60, true),
              CryptoWindowResult(
                  key.currentStart - 3 * key.minutes * 60, false),
              CryptoWindowResult(key.currentStart - 2 * key.minutes * 60, true),
              CryptoWindowResult(key.currentStart - key.minutes * 60, null),
            ]),
        cryptoOddsClockProvider.overrideWithValue(() => now),
        cryptoOddsForegroundProvider.overrideWithValue(() => true),
        cryptoOddsMidpointsProvider.overrideWithValue((_) async => const {}),
        polyRoundWindowReaderProvider
            .overrideWithValue((asset, start, minutes) async {
          expect(asset, 'btc');
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

Widget cardApp(CardWorld world, {bool compact = true}) => ProviderScope(
      overrides: world.overrides(),
      child: shellBarApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: CryptoPredictBanner(
                  key: cardKey,
                  config: kCryptoPredictAssets.first,
                  compact: compact,
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

StripRoundState roundOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
      tester.element(find.byKey(cardKey, skipOffstage: false)));
  return container.read(cryptoPredictProvider('BTC').notifier)
      as StripRoundState;
}

/// The clock moves to [at] and the card repaints on its one-second tick.
Future<void> moveTo(WidgetTester tester, CardWorld world, DateTime at) async {
  world.now = at;
  world.requote();
  roundOf(tester).bump();
  await settle(tester);
}

KutePill pillOf(WidgetTester tester, int start) =>
    tester.widget<KutePill>(find.byKey(CryptoRoundStrip.pillKey(start)));

bool pillSelected(WidgetTester tester, int start) =>
    pillOf(tester, start).selected;

/// A round without prices: the same pill, dimmed, with no words added to
/// it (a screen reader still hears why), and no tap.
void expectUnpriced(WidgetTester tester, int start) {
  final pill = pillOf(tester, start);
  expect(pill.detail, isNull, reason: 'no "No prices yet" on the pill');
  expect(pill.semanticLabel, '${pill.label}, No prices yet');
  final dim = tester.widget<Opacity>(find
      .ancestor(
          of: find.byKey(CryptoRoundStrip.pillKey(start)),
          matching: find.byType(Opacity))
      .first);
  expect(dim.opacity, lessThan(1));
  expect(
      find.descendant(
          of: find.byKey(const ValueKey('crypto-round-strip')),
          matching: find.textContaining('No prices yet', findRichText: true)),
      findsNothing);
}

/// The line over the buttons.
String? lineOverButtons(WidgetTester tester) {
  final line = find.descendant(
      of: find.byKey(const ValueKey('crypto-round-next')),
      matching: find.byType(Text));
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

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

  Future<void> pumpCard(WidgetTester tester, {bool compact = true}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(cardApp(world, compact: compact));
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
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsOneWidget);
    // Four results as dots (in the strip, not twice in the header), then
    // Now, Next and the one after.
    expect(
        find.byKey(const ValueKey('crypto-round-past-dots')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('crypto-round-strip')),
            matching: find.byKey(const ValueKey('crypto-round-past-dots'))),
        findsOneWidget);
    expect(pillOf(tester, epoch(roundStart)).label, 'Now · 04:00');
    expect(
        pillOf(tester, epoch(nextStart)).label, 'Next · ${clockOf(nextStart)}');
    expect(pillOf(tester, epoch(laterStart)).label, clockOf(laterStart));
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    expect(pillSelected(tester, epoch(nextStart)), isFalse);
    expect(find.byKey(_next), findsNothing, reason: 'the round on show');
    // The one after is listed by nobody: no prices, dimmed, no tap.
    final later = find.byKey(CryptoRoundStrip.pillKey(epoch(laterStart)));
    expectUnpriced(tester, epoch(laterStart));
    expect(lineOverButtons(tester), isNull);
    await tester.tap(later);
    await settle(tester);
    expect(pillSelected(tester, epoch(laterStart)), isFalse);
    expect(picks(), isEmpty);
    // The tap is answered on the line over the buttons, for a moment; the
    // buttons stay on the round in play.
    expect(lineOverButtons(tester), '${clockOf(laterStart)} · No prices yet');
    await tester.pump(kCryptoRoundNoteFor);
    await settle(tester);
    expect(lineOverButtons(tester), isNull);
    final slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(roundStart)));
    expect(slip.outcomes.map((o) => o.tokenId), ['cur-up', 'cur-down']);
    expect(tester.takeException(), isNull);
    await tearCardDown(tester);
  });

  testWidgets(
      'a tap on Next: the buttons and the slip bet on it, the chart stays',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(nextStart))));
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
    expect(slip.marketEndAt, nextStart.add(const Duration(minutes: 5)));
    await tearCardDown(tester);
  });

  testWidgets(
      'the default follows the roll: Next once this round is two minutes old',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    expect(find.text(windowName(nextStart)), findsOneWidget);
    expect(picks(), isEmpty, reason: 'nobody tapped');
    expect(pillOf(tester, epoch(roundStart)).label, 'Now · 03:00',
        reason: 'the round on show stays on show');
    // Without prices on the next round the buttons stay here.
    world.silence();
    await moveTo(tester, world, moment.add(const Duration(seconds: 1)));
    expect(pillSelected(tester, epoch(roundStart)), isTrue);
    expectUnpriced(tester, epoch(nextStart));
    await tearCardDown(tester);
  });

  testWidgets('a tap on Now overrides the roll until this round ends',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(roundStart))));
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
    world.now = roundStart.add(const Duration(minutes: 5, seconds: 2));
    roundOf(tester).rollTo(roundEvent(nextStart, 'next'));
    await settle(tester);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    expect(pillOf(tester, epoch(nextStart)).label, startsWith('Now · '));
    expect(find.byKey(_next), findsNothing);
    slip = await openUp(tester);
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    await tearCardDown(tester);
  });

  testWidgets(
      'a pick of Next stands until it starts; the one after can be '
      'picked too', (tester) async {
    world.listNext();
    world.listLater();
    world.quoteCurrent();
    await pumpCard(tester);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(nextStart))));
    await settle(tester);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    await moveTo(tester, world, moment);
    expect(pillSelected(tester, epoch(nextStart)), isTrue);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(laterStart))));
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
    expect(find.byKey(ValueKey('crypto-round-held-${epoch(roundStart)}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('crypto-round-held-${epoch(nextStart)}')),
        findsNothing);
    await tearCardDown(tester);
  });

  testWidgets(
      'the sockets: this round\'s and the listed rounds\' tokens, gone with '
      'the card', (tester) async {
    world.listNext();
    await pumpCard(tester);
    expect(world.socketTokens.keys.toSet(),
        {'cur-up', 'cur-down', 'next-up', 'next-down'});
    await tearCardDown(tester);
    expect(world.socketTokens, isEmpty);
  });

  testWidgets('the full card (the round\'s own sheet) carries the same strip',
      (tester) async {
    world.listNext();
    world.quoteCurrent();
    await pumpCard(tester, compact: false);
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('crypto-round-past-dots')), findsOneWidget);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(nextStart))));
    await settle(tester);
    expect(find.text(windowName(nextStart)), findsOneWidget);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.505, 1e-9));
    await tester.tap(find.text('Up'));
    await tester.pump();
    await settle(tester);
    final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    expect(tester.takeException(), isNull);
    await tearCardDown(tester);
  });

  for (final (length, minutes) in [('15m', 15), ('1h', 60), ('4h', 240)]) {
    testWidgets('$length: the strip in its own steps, the slip on the pick',
        (tester) async {
      // The four-hour rounds run on the New York clock (crypto_round.dart):
      // on 8 November (EST) the one before noon UTC is 4 AM–8 AM ET,
      // 09:00Z–13:00Z, never 12:00Z–16:00Z.
      final start = minutes == 240 ? DateTime.utc(2026, 11, 8, 9) : roundStart;
      world.minutes = minutes;
      world.now = start.add(const Duration(minutes: 7));
      world.install();
      world.listNext(live: start);
      await pumpCard(tester);
      final next = start.add(Duration(minutes: minutes));
      expect(pillOf(tester, epoch(next)).label, 'Next · ${clockOf(next)}');
      expect(pillSelected(tester, epoch(start)), isTrue,
          reason: 'no roll at this length');
      if (minutes >= 60) {
        expect(pillOf(tester, epoch(start)).label,
            'Now · ${minutes ~/ 60 - 1}:53:00',
            reason: 'hours, never minutes past 59');
      }
      await tester.tap(find.byKey(CryptoRoundStrip.pillKey(epoch(next))));
      await settle(tester);
      expect(find.text(windowName(next, minutes: minutes)), findsOneWidget);
      expect(picks().single.$2!['length'], length);
      final slip = await openUp(tester);
      expect(slip.marketSlug, polyCryptoRoundSlug('btc', minutes, epoch(next)));
      await tearCardDown(tester);
    });
  }

  testWidgets(
      'without Gamma\'s event the round in play reads its start and no '
      'prices, and takes no tap', (tester) async {
    world.eventless = true;
    await pumpCard(tester);
    final live = find.byKey(CryptoRoundStrip.pillKey(epoch(roundStart)));
    expectUnpriced(tester, epoch(roundStart));
    expect(tester.widget<KutePill>(live).label, clockOf(roundStart));
    expect(find.textContaining('Now ·', findRichText: true), findsNothing);
    // The buttons stand on it: the line over them says so while they do.
    expect(lineOverButtons(tester), '${clockOf(roundStart)} · No prices yet');
    await tearCardDown(tester);
  });
}
