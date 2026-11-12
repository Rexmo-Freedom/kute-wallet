// THE LIVE CRYPTO ROUND CARD BETS ONLY ON THE NEXT ROUND (founder, 12
// November 2026: late in a round one side is ~98%, and funding takes 20 to
// 60 s, so a bet on the round in play is unfair or lands too late).
// CryptoPredictBanner (polymarket_screen.dart: Predictions › Crypto › 5 Min
// and pinned under Crypto › All, the compact card; the round's own sheet
// FiveMinMarketDetailSheet and Ledger Predictions, the full card) on a fake
// clock, fake Gamma reads and fake books: the round in play stays on show
// (chart, price, target, countdown) and the line over the buttons says the
// bet is on the next round, counting down to its start ("Next · Starts in
// 02:16"); the buttons, the slip, the receipt and the position are the next
// round's (tokens, slug, end, live book odds). No real prices yet: the
// buttons disabled, "No prices yet" on the line, never the round in play;
// enabled as soon as prices come. No strip of rounds: nothing to pick. The
// longer lengths, the rollover, the sockets, holding the round in play, the
// gate, and a round in play opened from another door (a list's pill).
//
// The world (CardWorld) is shared with the 5 Min page's test
// (test/screens/usd/five_min_page_test.dart).

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
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/crypto_round_card.dart'
    show CompactSidePill;
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardOpenSlip;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/current_round.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:money2/money2.dart';

import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/polymarket/components/round_heartbeat.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show polyPositionRowTitle;
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
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

  /// Gamma's rounds ahead by slug.
  final Map<String, Btc5MinEvent> listed = {};

  /// How many times Gamma was asked for a round.
  int reads = 0;
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

  /// The next round listed and, unless [quoted] is false, quoted 50/51,
  /// after [live] (the round in play's start, [roundStart] by default):
  /// Bitcoin's, or [coin]'s ('eth') for the rows.
  void listNext({DateTime? live, String coin = 'btc', bool quoted = true}) {
    final start = (live ?? roundStart).add(Duration(minutes: minutes));
    final tokens = coin == 'btc' ? 'next' : 'next-$coin';
    final event =
        roundEvent(start, tokens, minutes: minutes, up: 0.5, asset: coin);
    listed[event.slug] = event;
    if (!quoted) return;
    seedBook('$tokens-up', 0.50, 0.51);
    seedBook('$tokens-down', 0.49, 0.50);
  }

  /// The one after listed and quoted too.
  void listLater() {
    final start = roundStart.add(Duration(minutes: 2 * minutes));
    final event = roundEvent(start, 'later', minutes: minutes, up: 0.5);
    listed[event.slug] = event;
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
          reads++;
          return listed[polyCryptoRoundSlug(asset, minutes, start)];
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

Widget cardApp(CardWorld world,
        {bool compact = true, bool dark = false, Locale? locale}) =>
    ProviderScope(
      overrides: world.overrides(),
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

const upPill = ValueKey('crypto-round-up');
const downPill = ValueKey('crypto-round-down');

String clockOf(DateTime t) => polyRoundClock(t, locale: 'en');
String windowName(DateTime start, {int minutes = 5}) =>
    'BTC up or down · ${clockOf(start)}–'
    '${clockOf(start.add(Duration(minutes: minutes)))}';

/// The window's name on the slip, the receipt and the position: the range
/// held whole by its joiners.
String slipWindowName(DateTime start, {int minutes = 5}) =>
    'BTC up or down · ${clockOf(start)}'
    '$kPolyRoundRangeJoin–$kPolyRoundRangeJoin'
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

/// Whether the card's [key] button bets: enabled and inert alike read off
/// the pill (compact) or the pair button (full card).
bool buttonEnabled(WidgetTester tester, Key key) {
  final w = tester.widget(find.byKey(key));
  if (w is MarketPairButton) return w.enabled;
  return (w as CompactSidePill).enabled;
}

/// What the button says to a screen reader: the round it bets on, its
/// side and chance (the digits on screen roll; this is the figure they
/// roll to).
bool buttonSays(WidgetTester tester, Key key, String label) => tester
    .widgetList<Semantics>(find.descendant(
        of: find.byKey(key), matching: find.byType(Semantics)))
    .followedBy(tester.widgetList<Semantics>(
        find.ancestor(of: find.byKey(key), matching: find.byType(Semantics))))
    .any((w) => w.properties.label == label);

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

  /// A tap on [key]: the slip it opened, or null when nothing opened.
  Future<BetSlipSheet?> tapSide(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key), warnIfMissed: false);
    await tester.pump();
    await settle(tester);
    final slips = find.byType(BetSlipSheet);
    return slips.evaluate().isEmpty
        ? null
        : tester.widget<BetSlipSheet>(slips.last);
  }

  Map<String, Object> slipOpened() =>
      events.lastWhere((e) => e.$1 == 'polymarket_bet_slip_opened').$2!;

  for (final compact in [true, false]) {
    final shape = compact ? 'compact card' : 'full card (the round sheet)';
    testWidgets(
        '$shape: the bet is on the next round, "Next · Starts in" over the '
        'buttons, its tokens, end and live odds; the round in play stays '
        'on show; no strip', (tester) async {
      world.listNext();
      world.quoteCurrent();
      await pumpCard(tester, compact: compact);
      expect(lineOverButtons(tester), 'Next · Starts in 04:00');
      expect(find.byKey(const ValueKey('crypto-round-strip')), findsNothing,
          reason: 'nothing to pick');
      expect(find.textContaining('Now · '), findsNothing);
      // The round in play is the context: its target and its clock.
      expect(find.text(r'Target $75,987'), findsOneWidget);
      expect(find.text('04:00'), findsOneWidget);
      expect(buttonEnabled(tester, upPill), isTrue);
      expect(buttonEnabled(tester, downPill), isTrue);
      final name = windowName(nextStart);
      expect(buttonSays(tester, upPill, compact ? '$name, Up 50.5%' : name),
          isTrue);
      if (!compact) {
        final bar = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator));
        expect(bar.value, closeTo(0.505, 1e-9));
      }
      final slip = (await tapSide(tester, downPill))!;
      expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
      expect(slip.outcomes.map((o) => o.tokenId), ['next-up', 'next-down']);
      expect(slip.outcomes.map((o) => o.conditionId),
          ['next-cond', 'next-cond']);
      expect(slip.outcomes[0].price, closeTo(0.505, 1e-9),
          reason: 'the live odds on the button, never Gamma\'s');
      expect(slip.outcomes[1].price, closeTo(0.495, 1e-9));
      expect(slip.initialOutcomeIndex, 1);
      expect(slip.marketEndAt, nextStart.add(const Duration(minutes: 5)));
      expect(slip.marketCategory, 'crypto');
      expect(slip.source, 'crypto_banner');
      // The slip names the window, as the receipt and the position will.
      expect(find.text(slipWindowName(nextStart)), findsOneWidget);
      expect(slipOpened()['window'], 'next');
      expect(events.where((e) => e.$1 == 'predictions_instant_round_picked'),
          isEmpty);
      expect(tester.takeException(), isNull);
      await tearCardDown(tester);
    });
  }

  testWidgets('the line counts down to the next round\'s start',
      (tester) async {
    world.listNext();
    await pumpCard(tester);
    await moveTo(tester, world,
        roundStart.add(const Duration(minutes: 2, seconds: 44)));
    expect(lineOverButtons(tester), 'Next · Starts in 02:16');
    await moveTo(tester, world,
        roundStart.add(const Duration(minutes: 4, seconds: 59)));
    expect(lineOverButtons(tester), 'Next · Starts in 00:01');
    // To the last second, still the next round: never the one in play.
    final slip = (await tapSide(tester, upPill))!;
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    await tearCardDown(tester);
  });

  group('no prices for the next round yet', () {
    for (final compact in [true, false]) {
      final shape = compact ? 'compact' : 'full';
      testWidgets(
          '$shape: listed without a book: disabled, "No prices yet" on the '
          'line, no odds, no slip and never the round in play; the book '
          'arrives: enabled', (tester) async {
        world.listNext(quoted: false);
        world.quoteCurrent();
        await pumpCard(tester, compact: compact);
        expect(lineOverButtons(tester),
            'Next · Starts in 04:00 · No prices yet');
        expect(buttonEnabled(tester, upPill), isFalse);
        expect(buttonEnabled(tester, downPill), isFalse);
        expect(find.textContaining('%'), findsNothing,
            reason: 'no odds, never Gamma\'s 50% standing in');
        expect(await tapSide(tester, upPill), isNull);
        expect(await tapSide(tester, downPill), isNull);
        // The book arrives: the buttons bet the next round at once.
        world.seedBook('next-up', 0.50, 0.51);
        world.seedBook('next-down', 0.49, 0.50);
        await moveTo(tester, world, world.now.add(const Duration(seconds: 1)));
        expect(lineOverButtons(tester), 'Next · Starts in 03:59');
        expect(buttonEnabled(tester, upPill), isTrue);
        final slip = (await tapSide(tester, upPill))!;
        expect(slip.outcomes.map((o) => o.tokenId), ['next-up', 'next-down']);
        expect(tester.takeException(), isNull);
        await tearCardDown(tester);
      });
    }

    testWidgets('not listed: disabled, and Gamma is asked again',
        (tester) async {
      world.quoteCurrent();
      await pumpCard(tester);
      expect(buttonEnabled(tester, upPill), isFalse);
      final asked = world.reads;
      expect(asked, greaterThan(0));
      world.listNext();
      await tester.pump(const Duration(seconds: 11));
      await moveTo(tester, world, world.now.add(const Duration(seconds: 11)));
      expect(world.reads, greaterThan(asked));
      expect(buttonEnabled(tester, upPill), isTrue);
      await tearCardDown(tester);
    });

    testWidgets('a book wider than 10¢ is no price', (tester) async {
      world.listNext(quoted: false);
      world.seedBook('next-up', 0.01, 0.99);
      world.seedBook('next-down', 0.01, 0.99);
      await pumpCard(tester);
      expect(buttonEnabled(tester, upPill), isFalse);
      await tearCardDown(tester);
    });

    testWidgets('a feed gone quiet is no price; it answers: enabled again',
        (tester) async {
      world.listNext();
      await pumpCard(tester);
      expect(buttonEnabled(tester, upPill), isTrue);
      world.quotes.clear();
      world.now = world.now.add(const Duration(seconds: 6));
      roundOf(tester).bump();
      await settle(tester);
      expect(buttonEnabled(tester, upPill), isFalse,
          reason: 'a book older than the feed\'s own limit is stale');
      world.listNext();
      await moveTo(tester, world, world.now.add(const Duration(seconds: 1)));
      expect(buttonEnabled(tester, upPill), isTrue);
      await tearCardDown(tester);
    });
  });

  testWidgets(
      'the round in play is never bettable: at its end, before the card '
      'rolls, the buttons are disabled; rolled, they bet the round after',
      (tester) async {
    world.listNext();
    world.listLater();
    world.quoteCurrent();
    await pumpCard(tester);
    // The next round has started; the card still shows the old one.
    await moveTo(tester, world, nextStart);
    expect(buttonEnabled(tester, upPill), isFalse);
    expect(lineOverButtons(tester), 'Next · Starts in 00:00 · No prices yet');
    expect(await tapSide(tester, upPill), isNull);
    // The card rolls on: the next round is the one in play, the buttons
    // bet the one after.
    world.now = nextStart.add(const Duration(seconds: 2));
    world.requote();
    roundOf(tester).rollTo(roundEvent(nextStart, 'next'));
    await settle(tester);
    expect(lineOverButtons(tester), startsWith('Next · Starts in 04:5'));
    final slip = (await tapSide(tester, upPill))!;
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(laterStart)));
    expect(slip.outcomes.map((o) => o.tokenId), ['later-up', 'later-down']);
    await tearCardDown(tester);
  });

  testWidgets('a slip open across the start stays on the round it opened for',
      (tester) async {
    world.listNext();
    world.listLater();
    await pumpCard(tester);
    final opened = (await tapSide(tester, upPill))!;
    expect(opened.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    world.now = nextStart.add(const Duration(seconds: 2));
    roundOf(tester).rollTo(roundEvent(nextStart, 'next'));
    await settle(tester);
    final still = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
    expect(still.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    await tearCardDown(tester);
  });

  for (final minutes in [15, 60]) {
    testWidgets('$minutes-minute rounds: the same, the next round of that '
        'length', (tester) async {
      world.minutes = minutes;
      world.listNext();
      await pumpCard(tester);
      expect(
          lineOverButtons(tester),
          minutes == 60
              ? 'Next · Starts in 0:59:00'
              : 'Next · Starts in 14:00');
      final slip = (await tapSide(tester, upPill))!;
      final next = roundStart.add(Duration(minutes: minutes));
      expect(slip.marketSlug, polyCryptoRoundSlug('btc', minutes, epoch(next)));
      expect(slip.marketEndAt, next.add(Duration(minutes: minutes)));
      await tearCardDown(tester);
    });
  }

  testWidgets(
      'the sockets: the round in play\'s and the next round\'s tokens, gone '
      'with the card', (tester) async {
    world.listNext();
    await pumpCard(tester);
    expect(world.socketTokens.keys.toSet(),
        {'cur-up', 'cur-down', 'next-up', 'next-down'});
    await tearCardDown(tester);
    expect(world.socketTokens, isEmpty);
  });

  testWidgets(
      'holding the round in play: the position names its own window, the '
      'heartbeat reads it, the buttons bet the next', (tester) async {
    final held = PolymarketPosition(
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
      eventSlug: polyCryptoRoundSlug('btc', 5, epoch(roundStart)),
    );
    world.positions = [held];
    world.listNext();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: world.overrides(),
      child: shellBarApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoundHeartbeat(
              asset: 'BTC',
              child: CryptoPredictBanner(
                key: cardKey,
                config: kCryptoPredictAssets.first,
              ),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
    final context = tester.element(find.byKey(cardKey));
    expect(polyPositionRowTitle(context, held, null),
        slipWindowName(roundStart));
    expect(lineOverButtons(tester), 'Next · Starts in 04:00');
    final container = ProviderScope.containerOf(context);
    expect(
        container
            .read(cryptoPredictProvider('BTC'))
            .requireValue
            .event!
            .upTokenId,
        'cur-up',
        reason: 'the card\'s own round is the held one');
    final slip = (await tapSide(tester, upPill))!;
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    expect(tester.takeException(), isNull);
    await tearCardDown(tester);
  });

  testWidgets('the next round answers to the same capabilities',
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
    world.listNext();
    await pumpCard(tester);
    final slip = (await tapSide(tester, upPill))!;
    expect(slip.marketSlug, polyCryptoRoundSlug('btc', 5, epoch(nextStart)));
    expect(find.text('This feature is currently unavailable in Kute.'),
        findsOneWidget);
    await tearCardDown(tester);
    policy.dispose();
  });

  group('the round in play from any other door', () {
    PolymarketEvent inPlay(DateTime now, {int minutes = 15}) {
      final start = DateTime.fromMillisecondsSinceEpoch(
          polyRoundStartAt(now, minutes) * 1000,
          isUtc: true);
      final ev = roundEvent(start, 'cur15', minutes: minutes);
      return PolymarketEvent(
        id: ev.slug,
        slug: ev.slug,
        title: ev.title,
        volume: 0,
        volume24hr: 0,
        liquidity: 1000,
        category: 'crypto',
        endDate: ev.endDate,
        conditionId: 'cur15-cond',
        outcomes: const [
          PolymarketOutcome(name: 'Up', price: 0.97, tokenId: 'cur15-up'),
          PolymarketOutcome(name: 'Down', price: 0.03, tokenId: 'cur15-down'),
        ],
      );
    }

    test('a buy on a round in play is closed, of any length; a round ahead '
        'and any other market are not', () {
      final now = DateTime.now();
      for (final minutes in [5, 15, 240]) {
        final start = polyRoundStartAt(now, minutes);
        expect(
            polyRoundBuyClosed(polyCryptoRoundSlug('btc', minutes, start),
                now: now),
            isTrue,
            reason: '$minutes');
        expect(
            polyRoundBuyClosed(
                polyCryptoRoundSlug('btc', minutes, start + minutes * 60),
                now: now),
            isFalse,
            reason: '$minutes ahead');
      }
      final hour = polyRoundStartAt(now, 60);
      expect(
          polyRoundBuyClosed(polyCryptoRoundSlug('btc', 60, hour),
              endDate: DateTime.fromMillisecondsSinceEpoch(
                  (hour + 3600) * 1000,
                  isUtc: true),
              now: now),
          isTrue);
      expect(polyRoundBuyClosed('will-it-rain', now: now), isFalse);
      expect(polyRoundBuyClosed(null, now: now), isFalse);
    });

    testWidgets(
        'a list\'s pill on a 15-minute round in play opens no slip: its page '
        'opens read-only, its one pill the next round', (tester) async {
      final now = DateTime.now();
      world.now = now;
      BetSlipSheet.debugClock = () => now;
      final event = inPlay(now);
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: world.overrides(),
        child: shellBarApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => polyCardOpenSlip(context,
                      event: event, side: 'up', source: 'feed_card'),
                  child: const Text('pill'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('pill'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(find.byType(MarketDetailSheet), findsOneWidget);
      // Read-only: the bar's trade row is the one pill to the next round,
      // no Up or Down on the round in play.
      final round = polyCryptoRoundOf(event.slug)!;
      expect(find.byKey(const ValueKey('kute-bar-trade-next-round')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('kute-bar-trade-next-round')),
              matching: find.text('Next · ${clockOf(round.end)}')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('kute-bar-trade-yes')), findsNothing);
      expect(find.byKey(const ValueKey('kute-bar-trade-no')), findsNothing);
      // The pill opens the next round as its own market, where it is bet.
      final next = roundEvent(round.end, 'next15', minutes: 15);
      world.listed[next.slug] = next;
      await tester.tap(find.byKey(const ValueKey('kute-bar-trade-next-round')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final sheets =
          tester.widgetList<MarketDetailSheet>(find.byType(MarketDetailSheet));
      expect(sheets.last.event.slug, next.slug);
      expect(sheets.last.event.outcomes.map((o) => o.tokenId),
          ['next15-up', 'next15-down']);
      expect(
          events.where((e) => e.$1 == 'polymarket_bet_slip_opened'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    });
  });
}
