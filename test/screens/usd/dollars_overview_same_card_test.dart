// THE OVERVIEW'S CARD IS THE PORTFOLIO'S, AND SO IS ITS P&L (founder, 11
// November 2026, on 2.2.0 (106), two screenshots of one open prediction
// worth $14.85 taken the same minute):
//
//   * the Portfolio's card read the side first ("Yes · Fed Decision in
//     December"), its chance bar under the line, and "▼ $0.14 · 1.0%";
//   * the Overview's read the event first, had no bar, and wrote "$14.85 ·
//     0.0%" in grey over "Open profits +$14.85".
//
// "here on the predictions remember we should have this little bar on the
// bottom on the overview." So:
//
//   1. the Overview draws the Portfolio's own cards
//      (PortfolioPositionSquares.holdings): the same line, the chance bar,
//      the same figures, in both themes;
//   2. a position the venue lists before it prices its entry (`avg_price`
//      0) has no known cost: no P&L on its card on either screen, nothing
//      of it in Open profits or on its line, never its whole value as a
//      profit (PolymarketPosition.costKnown);
//   3. where its own fill says what it cost (the trading state's pending
//      fill, the standing order's filledUsd over filledSize), that is its
//      entry at once, and both screens read the same P&L
//      (polyPositionEntryPrice).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlFill, HlPerpPosition;
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/open_pnl_history_provider.dart'
    show OpenPnlSources, openPnlBookProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioChanceBar;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsBody;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/pending_fills.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

const _token = 'tok-hegseth';
const _question =
    'Will Pete Hegseth leave the Trump Administration before 2027?';

/// What the Portfolio's card writes under the name: the side first.
const _line = 'Yes · Leave Trump Administration before 2027';

/// The founder's figures: 30 shares bought at 50¢ ($15.00), now 49.5¢:
/// worth $14.85, down $0.15 (1.0%).
const _size = 30.0;
const _entry = 0.5;
const _now = 0.495;

PolymarketPosition _held({double avg = _entry}) => PolymarketPosition(
    marketId: 'c-hegseth',
    marketQuestion: _question,
    outcome: 'Yes',
    size: _size,
    avgPrice: avg,
    currentPrice: _now,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: _token);

/// The position as the Data API lists it; [avg] 0: before it prices the
/// entry.
Position _listed({double avg = 0, double entryCost = 0}) => Position(
      proxyWallet: '0xproxy',
      asset: _token,
      conditionId: 'c-hegseth',
      size: _size,
      avgPrice: avg,
      initialValue: entryCost,
      currentValue: _size * _now,
      cashPnl: 0,
      percentPnl: 0,
      totalBought: _size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: _now,
      title: _question,
      slug: 'hegseth',
      eventSlug: '',
      outcome: 'Yes',
      outcomeIndex: 0,
      oppositeOutcome: 'No',
      oppositeAsset: 'tok-hegseth-no',
    );

PolymarketTradingState _account(List<Position> positions,
        {List<PolymarketPendingFill> fills = const []}) =>
    PolymarketTradingState(
        isAuthenticated: true,
        proxyWalletAddress: '0xproxy',
        openPositions: positions,
        pendingFills: fills);

/// The Predictions account, changed by the test (the entry arriving).
class _Poly extends PolymarketTradingNotifier {
  _Poly(this.initial);
  final PolymarketTradingState initial;

  @override
  Future<PolymarketTradingState> build() async => initial;

  void land(PolymarketTradingState next) => state = AsyncData(next);
}

PolymarketPendingFill _fill({double shares = _size, double cost = 15}) =>
    PolymarketPendingFill(
        key: 'order-1',
        tokenId: _token,
        shares: shares,
        price: cost / shares,
        costUsd: cost,
        expectedShares: shares,
        cashBeforeUsd: 20,
        at: DateTime.now(),
        indexed: true);

StandingOrder _order(
        {String id = 'so_1',
        StandingOrderState state = StandingOrderState.filled,
        double? filledSize = _size,
        double? filledUsd = 15,
        bool isBuy = true,
        String token = _token}) =>
    StandingOrder(
      id: id,
      walletId: 'spending',
      venue: StandingOrderVenue.predictions,
      marketKey: token,
      marketTitle: _question,
      sideLabel: 'Yes',
      isBuy: isBuy,
      size: _size,
      approvedPrice: 0.52,
      amountUsd: 15,
      orderKind: 'market',
      state: state,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      filledSize: filledSize,
      filledUsd: filledUsd,
    );

class _NoLive extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: false, prices: {});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
}

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// What a card writes, to compare the two screens'.
typedef _Card = ({
  String title,
  String line,
  String value,
  String? pnlUsd,
  String? pnl,
  Color? pnlColor,
  double? chance,
  double? entry,
});

_Card _read(WidgetTester tester, Finder card) {
  Finder inCard(String key) =>
      find.descendant(of: card, matching: find.byKey(ValueKey(key)));
  String? figure(String key) => inCard(key).evaluate().isEmpty
      ? null
      : tester.widget<RollingFigure>(inCard(key)).text;
  final bar = find.descendant(of: card, matching: find.byType(PortfolioChanceBar));
  final chance = bar.evaluate().isEmpty
      ? null
      : tester.widget<PortfolioChanceBar>(bar);
  return (
    title: tester.widget<Text>(inCard('portfolio-row-title')).data!,
    line: tester.widget<Text>(inCard('portfolio-row-subtitle')).data!,
    value: figure('portfolio-row-value')!,
    pnlUsd: figure('portfolio-row-pnl-usd'),
    pnl: figure('portfolio-row-pnl'),
    pnlColor: inCard('portfolio-row-pnl').evaluate().isEmpty
        ? null
        : tester
            .widget<RollingFigure>(inCard('portfolio-row-pnl'))
            .style
            .color,
    chance: chance?.chance,
    entry: chance?.entry,
  );
}

final _squares = find.byKey(const ValueKey('dollars-activity-squares'));
final _wide = find.byKey(const ValueKey('portfolio-wide'));
final _strip = find.byKey(const ValueKey('dollars-pnl-strip'));

Finder _overviewCard() => find.descendant(of: _squares, matching: _wide);

Future<void> _pumpOverview(WidgetTester tester,
    {List<Override> overrides = const [],
    bool dark = false,
    Size size = const Size(390, 1400),
    double textScale = 1,
    OpenPnlSources? openPnlSources}) async {
  await pumpInvestments(tester,
      size: size,
      dark: dark,
      textScale: textScale,
      openPnlSources: openPnlSources,
      overrides: [
        livePriceProvider.overrideWith(_NoLive.new),
        ...overrides,
      ]);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The Portfolio screen on Positions, over the same providers.
Future<void> _pumpPortfolio(WidgetTester tester,
    {List<Override> overrides = const [], bool dark = false}) async {
  await pumpInvestments(tester,
      size: const Size(390, 1400),
      dark: dark,
      overrides: [
        livePriceProvider.overrideWith(_NoLive.new),
        usdBalanceUnknownProvider.overrideWithValue(false),
        venueSweeperProvider.overrideWith(_Sweeper.new),
        hyperliquidActivityFillsProvider.overrideWithValue(const <HlFill>[]),
        portfolioSectionProvider
            .overrideWith((_) => PortfolioSection.balances),
        ...overrides,
      ],
      child: Scaffold(
        body: SafeArea(
          child: Material(
            child: InvestmentsPortfolio(onSection: (_) {}),
          ),
        ),
      ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ProviderContainer _overviewContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
        tester.element(find.byType(InvestmentsBody, skipOffstage: false)));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  group('the fill\'s own cost (pure)', () {
    test('the venue\'s average where it has one; else its own entry cost '
        'over the shares; else unknown (0)', () {
      expect(
          polyPositionEntryPrice(tokenId: _token, size: 30, avgPrice: 0.42),
          0.42);
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 30, avgPrice: 0, initialValue: 15),
          0.5);
      expect(polyPositionEntryPrice(tokenId: _token, size: 30, avgPrice: 0), 0);
      // A cost above $1 a share is no entry.
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 30, avgPrice: 0, initialValue: 45),
          0);
      expect(_held(avg: 0).costKnown, isFalse);
      expect(_held().costKnown, isTrue);
    });

    test('the session\'s fills: their cost over their shares, only where '
        'they account for the shares held', () {
      const fills = [
        (shares: 20.0, costUsd: 10.0),
        (shares: 10.0, costUsd: 5.6),
      ];
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 30, avgPrice: 0, fills: fills),
          closeTo(0.52, 1e-9));
      // Part of it sold since: the average stays.
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 12, avgPrice: 0, fills: fills),
          closeTo(0.52, 1e-9));
      // More held than the fills bought: shares whose cost nobody said.
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 45, avgPrice: 0, fills: fills),
          0);
    });

    test('the fills are noted while the trading state carries them and '
        'kept while the token is held; a token sold and no longer pending '
        'starts afresh', () {
      final memo = <String, Map<String, PolyFillCost>>{};
      notePolyFillCosts(memo, [_fill()], {});
      expect(memo[_token]!['order-1'], (shares: 30.0, costUsd: 15.0));
      // The reads caught up: the pending fill is gone, the token listed.
      notePolyFillCosts(memo, const [], {_token});
      expect(memo[_token]!['order-1'], (shares: 30.0, costUsd: 15.0));
      // A fill the positions read shows part of keeps its own shares.
      notePolyFillCosts(
          memo, [_fill().copyWith(shares: 4, indexed: false)], {_token});
      expect(memo[_token]!['order-1']!.shares, closeTo(30, 1e-9));
      // Sold: neither held nor pending.
      notePolyFillCosts(memo, const [], {'another'});
      expect(memo, isEmpty);
    });

    test('the standing orders: filled buys of the token with their fill\'s '
        'own figures, newest first, until they account for the shares', () {
      expect(standingFillEntryPrice([_order()], _token, 30), 0.5);
      expect(
          standingFillEntryPrice([
            _order(id: 'a', filledSize: 20, filledUsd: 10),
            _order(id: 'b', filledSize: 10, filledUsd: 5.6),
          ], _token, 30),
          closeTo(0.52, 1e-9));
      // The newest alone accounts for what is held: the older is another
      // holding's.
      expect(
          standingFillEntryPrice([
            _order(id: 'old', filledSize: 30, filledUsd: 27),
            _order(id: 'new', filledSize: 30, filledUsd: 15),
          ], _token, 30),
          0.5);
      // Not filled, a fill with no figures, another token, a sale, or
      // fewer shares than held: nothing known.
      expect(
          standingFillEntryPrice(
              [_order(state: StandingOrderState.posting)], _token, 30),
          isNull);
      expect(
          standingFillEntryPrice(
              [_order(filledSize: null, filledUsd: null)], _token, 30),
          isNull);
      expect(standingFillEntryPrice([_order(token: 'other')], _token, 30),
          isNull);
      expect(standingFillEntryPrice([_order(isBuy: false)], _token, 30),
          isNull);
      expect(standingFillEntryPrice([_order()], _token, 60), isNull);
      expect(
          polyPositionEntryPrice(
              tokenId: _token, size: 30, avgPrice: 0, orders: [_order()]),
          0.5);
    });
  });

  for (final dark in [false, true]) {
    testWidgets(
        'one open prediction${dark ? ', dark' : ''}: the Overview\'s '
        'full-width card is the Portfolio\'s: the side first on the line, '
        'the chance bar under it with its entry tick, the same value and '
        'P&L', (tester) async {
      final overrides = [
        polymarketActivePositionsProvider.overrideWith((_) => [_held()]),
      ];
      await _pumpOverview(tester, overrides: overrides, dark: dark);
      expect(tester.takeException(), isNull);
      expect(_overviewCard(), findsOneWidget);
      final overview = _read(tester, _overviewCard());
      expect(overview.title, 'Pete Hegseth');
      expect(overview.line, _line);
      expect(overview.value, r'$14.85');
      expect(overview.pnlUsd, r'▼ $0.15');
      expect(overview.pnl, '1.0%');
      expect(overview.pnlColor, AppColors.marketDown);
      expect(overview.chance, _now);
      expect(overview.entry, _entry);

      // The bar: under the line, inside the card, its tick drawn.
      final card = tester.getRect(_overviewCard());
      final bar = tester.getRect(find.descendant(
          of: _overviewCard(), matching: find.byType(PortfolioChanceBar)));
      final line = tester.getRect(find.descendant(
          of: _overviewCard(),
          matching: find.byKey(const ValueKey('portfolio-row-subtitle'))));
      expect(bar.top, greaterThanOrEqualTo(line.bottom));
      expect(bar.bottom, lessThanOrEqualTo(card.bottom));
      expect(bar.left, moreOrLessEquals(line.left, epsilon: 0.5));
      expect(bar.right, lessThanOrEqualTo(card.right));
      expect(bar.width, greaterThan(40));
      expect(
          find.descendant(
              of: _overviewCard(),
              matching: find.byKey(const ValueKey('portfolio-row-entry-tick'))),
          findsOneWidget);
      // Open profits: the card's own P&L.
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('dollars-pnl-figure')))
              .text,
          r'−$0.15');
      await unmountInvestments(tester);

      await _pumpPortfolio(tester, overrides: overrides, dark: dark);
      expect(tester.takeException(), isNull);
      expect(_wide, findsOneWidget);
      expect(_read(tester, _wide), overview);
      await unmountInvestments(tester);
    });
  }

  testWidgets(
      'two open predictions: the Overview\'s squares carry the chance bar '
      'as the Portfolio\'s do, between the line and the value',
      (tester) async {
    await _pumpOverview(tester, overrides: [
      polymarketActivePositionsProvider.overrideWith((_) => [
            _held(),
            PolymarketPosition(
                marketId: 'c-rain',
                marketQuestion: 'Will it rain tomorrow?',
                outcome: 'No',
                size: 10,
                avgPrice: 0.3,
                currentPrice: 0.4,
                pnl: 0,
                pnlPercent: 0,
                isResolved: false,
                tokenId: 'tok-rain'),
          ]),
    ]);
    expect(tester.takeException(), isNull);
    final cards = find.descendant(
        of: _squares, matching: find.byKey(const ValueKey('portfolio-square')));
    expect(cards, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      Rect inside(Finder f) => tester
          .getRect(find.descendant(of: cards.at(i), matching: f).first);
      final bar = inside(find.byType(PortfolioChanceBar));
      final card = tester.getRect(cards.at(i));
      expect(
          bar.top,
          greaterThanOrEqualTo(
              inside(find.byKey(const ValueKey('portfolio-row-subtitle')))
                  .bottom));
      expect(
          bar.bottom,
          lessThanOrEqualTo(
              inside(find.byKey(const ValueKey('portfolio-row-value'))).top));
      expect(bar.left, greaterThan(card.left));
      expect(bar.right, lessThan(card.right));
    }
    expect(_read(tester, cards.at(0)).line, _line);
    await unmountInvestments(tester);
  });

  testWidgets(
      'just filled, its cost not known (listed with no entry price, no '
      'fill of its own to say): no P&L on its card on either screen, no '
      'Open profits card, nothing of it in the open P&L\'s book; the entry '
      'arrives and both read the same P&L', (tester) async {
    final poly = _Poly(_account([_listed()]));
    final overrides = [polymarketTradingProvider.overrideWith(() => poly)];
    await _pumpOverview(tester, overrides: overrides);
    expect(tester.takeException(), isNull);
    var card = _read(tester, _overviewCard());
    expect(card.line, _line);
    expect(card.value, r'$14.85');
    expect(card.pnlUsd, isNull);
    expect(card.pnl, isNull);
    // Never the whole value as a profit, anywhere on the tab.
    expect(_strip, findsNothing);
    expect(find.textContaining(r'+$14.85'), findsNothing);
    expect(find.text('0.0%'), findsNothing);
    final container = _overviewContainer(tester);
    expect(container.read(polymarketActivePositionsProvider).single.costKnown,
        isFalse);
    expect(container.read(openPnlBookProvider).isEmpty, isTrue);

    // The venue prices the entry: the card and Open profits say it.
    poly.land(_account([_listed(avg: _entry, entryCost: 15)]));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    card = _read(tester, _overviewCard());
    expect(card.pnlUsd, r'▼ $0.15');
    expect(card.pnl, '1.0%');
    expect(card.entry, _entry);
    expect(_strip, findsOneWidget);
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('dollars-pnl-figure')))
            .text,
        r'−$0.15');
    await unmountInvestments(tester);

    // The Portfolio, the cost not known: the same card, no P&L either.
    await _pumpPortfolio(tester, overrides: [
      polymarketTradingProvider
          .overrideWith(() => _Poly(_account([_listed()]))),
    ]);
    expect(tester.takeException(), isNull);
    final portfolio = _read(tester, _wide);
    expect(portfolio.value, r'$14.85');
    expect(portfolio.pnlUsd, isNull);
    expect(portfolio.pnl, isNull);
    expect(find.textContaining(r'+$14.85'), findsNothing);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Open profits and its line never count a position whose cost is not '
      'known: beside a charted Investing position (+\$2.00) the figure and '
      'the last point stay +\$2.00, not +\$16.85', (tester) async {
    final now = DateTime.now();
    await _pumpOverview(tester,
        openPnlSources: OpenPnlSources(
          activity: (_) async => const [],
          candles: (_, wire, interval, window) async => [
            for (var t = now.subtract(window);
                t.isBefore(now);
                t = t.add(const Duration(hours: 1)))
              HyperliquidCandle(
                  openTime: t,
                  closeTime: t.add(const Duration(hours: 1)),
                  open: 102,
                  high: 102,
                  low: 102,
                  close: 102,
                  volume: 1),
          ],
          polyHistory: (_, __, ___) async => null,
        ),
        overrides: [
          polymarketTradingProvider
              .overrideWith(() => _Poly(_account([_listed()]))),
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
                  HyperliquidTradingState(isInitialized: true, positions: [
                const HlPerpPosition(
                    coin: 'BTC',
                    szi: 1,
                    entryPx: 100,
                    positionValue: 102,
                    unrealizedPnl: 2,
                    returnOnEquity: 0,
                    liquidationPx: null,
                    marginUsed: 50,
                    leverageType: 'cross',
                    leverageValue: 2,
                    maxLeverage: 40),
              ], recentFills: [
                HlFill(
                  coin: 'BTC',
                  px: 100,
                  sz: 1,
                  side: 'B',
                  time: now
                      .subtract(const Duration(days: 10))
                      .millisecondsSinceEpoch,
                  closedPnl: 0,
                  fee: 0,
                  feeToken: 'USDC',
                  oid: 1,
                  hash: '0xopen-BTC',
                  dir: 'Open Long',
                  cloid: null,
                  startPosition: 0,
                ),
              ]))),
        ]);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('dollars-pnl-figure')))
            .text,
        r'+$2.00');
    final chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('dollars-pnl-chart')));
    expect(chart.values.last, closeTo(2, 1e-9));
    expect(chart.values.every((v) => v <= 2 + 1e-9), isTrue);
    // The book the line is laid from: the perp alone.
    expect(
        [
          for (final e
              in _overviewContainer(tester).read(openPnlBookProvider).entries)
            e.id
        ],
        ['BTC']);
    await unmountInvestments(tester);
  });

  for (final (name, account, orders) in [
    (
      'the standing order\'s fill (filledUsd over filledSize)',
      _account([_listed()]),
      [_order()],
    ),
    (
      'the bet\'s own pending fill',
      _account([_listed()], fills: [_fill()]),
      const <StandingOrder>[],
    ),
    (
      'the read\'s own entry cost',
      _account([_listed(entryCost: 15)]),
      const <StandingOrder>[],
    ),
  ]) {
    testWidgets(
        'listed with no entry price, its cost known from $name: the '
        'Overview and the Portfolio read the same P&L at once, the bar '
        'with its entry tick', (tester) async {
      await _pumpOverview(tester, overrides: [
        polymarketTradingProvider.overrideWith(() => _Poly(account)),
      ]);
      _overviewContainer(tester)
          .read(standingOrdersProvider.notifier)
          .debugReplace(orders);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final overview = _read(tester, _overviewCard());
      expect(overview.line, _line);
      expect(overview.value, r'$14.85');
      expect(overview.pnlUsd, r'▼ $0.15');
      expect(overview.pnl, '1.0%');
      expect(overview.pnlColor, AppColors.marketDown);
      expect(overview.chance, _now);
      expect(overview.entry, closeTo(_entry, 1e-9));
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('dollars-pnl-figure')))
              .text,
          r'−$0.15');
      await unmountInvestments(tester);

      await _pumpPortfolio(tester, overrides: [
        polymarketTradingProvider.overrideWith(() => _Poly(account)),
      ]);
      ProviderScope.containerOf(tester.element(_wide))
          .read(standingOrdersProvider.notifier)
          .debugReplace(orders);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final portfolio = _read(tester, _wide);
      expect(portfolio.line, overview.line);
      expect(portfolio.value, overview.value);
      expect(portfolio.pnlUsd, overview.pnlUsd);
      expect(portfolio.pnl, overview.pnl);
      expect(portfolio.pnlColor, overview.pnlColor);
      expect(portfolio.chance, overview.chance);
      expect(portfolio.entry, closeTo(_entry, 1e-9));
      await unmountInvestments(tester);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'at 320 pt and text ×1.5${dark ? ', dark' : ''}: the lone card '
        'with its bar, nothing cut or overflowing', (tester) async {
      await _pumpOverview(tester,
          dark: dark,
          size: const Size(320, 1400),
          textScale: 1.5,
          overrides: [
            polymarketActivePositionsProvider.overrideWith((_) => [_held()]),
          ]);
      expect(tester.takeException(), isNull);
      final card = tester.getRect(_overviewCard());
      for (final key in const [
        'portfolio-row-title',
        'portfolio-row-subtitle',
      ]) {
        final words = tester.widget<Text>(find.descendant(
            of: _overviewCard(), matching: find.byKey(ValueKey(key))));
        expect(words.maxLines, isNull, reason: key);
        expect(words.overflow, isNull, reason: key);
      }
      for (final f in [
        find.byType(PortfolioChanceBar),
        find.byKey(const ValueKey('portfolio-row-value')),
        find.byKey(const ValueKey('portfolio-row-pnl-usd')),
        find.byKey(const ValueKey('portfolio-row-pnl')),
      ]) {
        final r =
            tester.getRect(find.descendant(of: _overviewCard(), matching: f));
        expect(r.left, greaterThanOrEqualTo(card.left));
        expect(r.right, lessThanOrEqualTo(card.right + 0.5));
        expect(r.top, greaterThanOrEqualTo(card.top));
        expect(r.bottom, lessThanOrEqualTo(card.bottom + 0.5));
      }
      expect(_read(tester, _overviewCard()).line, _line);
      await unmountInvestments(tester);
    });
  }
}
