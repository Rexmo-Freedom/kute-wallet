// The Portfolio screen's P&L, measured (founder, 2 November 2026:
// "Portfolio P&L chart is super slow. Make it decent."; since the
// overhaul of 4 November 2026 the one chart is the hero's and the P&L
// section lists the venues). Six months of history at both venues
// (Investing every six hours, Predictions daily with a 200-position
// book): the screen's first frames on Positions (whose hero draws the
// open positions' P&L since each was opened: ten predictions and a perp
// held for up to six months, their prices hourly and daily; one grid,
// laid once), a scrub and live ticks on that chart, the P&L section's
// first frame (its hero and venue squares drawn from the whole P&L
// engine, openPnlGrid, laid once per venue and range), a range switch, a
// scrub frame, a venue square picked and a scrub on it, and a live price
// tick (the engine's pinned last point alone: no grid), and how many P&L
// grids ([pnlSeries], [openPnlGrid], up to 20,000 points each) each of
// them lays. The numbers are printed (`PNL_PERF …`) and held to
// budgets well above what the screen needs now, so a regression to
// per-frame recomputation fails.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/models/polymarket_model.dart' show PolymarketPricePoint;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show HyperliquidTradingState;
import 'package:kute/providers/open_pnl_history_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart'
    show KuteTrendChart;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// The Predictions feed, ticked by hand.
class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(prices: {'open-0': 0.5});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}

  void tick(String token, double price) => state = LivePriceState(
      prices: {...state.prices, token: price}, live: state.live);

  /// The stream flowing, with [token] at [price].
  void tickLive(String token, double price) => state =
      LivePriceState(prices: {...state.prices, token: price}, live: true);
}

const _days = 180;

/// The venues' P&L now in [_sixMonths]: each series' last observation.
double get _hlNow => _lastOf(const Duration(hours: 6));
double get _pmNow {
  // Predictions: rebuilt from the book at the live prices (open-0 at the
  // feed's 0.80 by then, the others at their 0.45), as the hero draws it.
  var realised = 0.0;
  for (var i = 10; i < 200; i++) {
    realised += i % 3 == 0 ? -2 : 3;
  }
  var open = 0.0;
  for (var i = 0; i < 10; i++) {
    open += (i == 0 ? 0.8 : 0.45) * 20 - 8;
  }
  return realised + open;
}

double _lastOf(Duration every) {
  final n = (const Duration(days: _days).inMinutes / every.inMinutes).ceil();
  final i = n - 1;
  return ((i * 7) % 41) - 15.0 + i * 0.02;
}

/// [days] of P&L observations every [every], wandering above and below
/// zero.
List<PortfolioPnlPoint> _points(DateTime now, Duration every) {
  final out = <PortfolioPnlPoint>[];
  var t = now.subtract(const Duration(days: _days));
  var i = 0;
  while (t.isBefore(now)) {
    out.add(PortfolioPnlPoint(
        timestamp: t, pnlUsd: ((i * 7) % 41) - 15.0 + i * 0.02));
    t = t.add(every);
    i++;
  }
  return out;
}

List<Override> _sixMonths() {
  final now = DateTime.now().toUtc();
  final hl = _points(now, const Duration(hours: 6));
  final pm = _points(now, const Duration(days: 1));
  final book = PredictionsBook(records: [
    for (var i = 0; i < 200; i++)
      PredictionRecord(
        tokenId: i < 10 ? 'open-$i' : 'closed-$i',
        open: i < 10,
        redeemable: false,
        size: i < 10 ? 20 : 0,
        totalSize: 20,
        avgPrice: 0.4,
        entryCostUsd: i < 10 ? 8 : 0,
        currentPrice: 0.45,
        realizedPnlUsd: i < 10 ? 0 : (i % 3 == 0 ? -2 : 3),
        unrealizedPnlUsd: i < 10 ? 1 : 0,
        firstEntryAt: now.subtract(Duration(days: i % _days)),
        lastEventAt: now.subtract(Duration(days: i % 90)),
      ),
  ]);
  PortfolioPerformance perf(List<PortfolioPnlPoint> p, String source) =>
      PortfolioPerformance(
          points: p,
          totalPnlUsd: p.last.pnlUsd,
          realizedPnlUsd: p.last.pnlUsd,
          openPnlUsd: 0,
          asOf: p.last.timestamp,
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  final trading = perf(hl, 'Hyperliquid');
  final predictions = perf(pm, 'Polymarket').withPredictions(book);
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => trading),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => predictions),
  ];
}

/// The feed's notifier now (an auto-dispose provider: the latest one made).
_Prices? _feed;

/// What is open now: ten predictions bought up to six months back (their
/// first entries, today's shares) and a BTC long opened four months back
/// by one fill.
List<PolymarketPosition> _openPredictions(DateTime now) => [
      for (var i = 0; i < 10; i++)
        PolymarketPosition(
            marketId: 'm-$i',
            marketQuestion: 'Will $i happen this year?',
            outcome: 'Yes',
            size: 20,
            avgPrice: 0.4,
            currentPrice: 0.45,
            pnl: 0,
            pnlPercent: 0,
            isResolved: false,
            createdAt: now.subtract(Duration(days: 5 + i * 17)),
            tokenId: 'open-$i'),
    ];

const _btcLong = HlPerpPosition(
    coin: 'BTC',
    szi: 0.1,
    entryPx: 60000,
    positionValue: 6100,
    unrealizedPnl: 100,
    returnOnEquity: 0.016,
    liquidationPx: null,
    marginUsed: 6000,
    leverageType: 'cross',
    leverageValue: 1,
    maxLeverage: 40);

List<HlFill> _btcFills(DateTime now) => [
      HlFill(
        coin: 'BTC',
        px: 60000,
        sz: 0.1,
        side: 'B',
        time: now.subtract(const Duration(days: 120)).millisecondsSinceEpoch,
        closedPnl: 0,
        fee: 0,
        feeToken: 'USDC',
        oid: 1,
        hash: '0xopen',
        dir: 'Open Long',
        cloid: null,
        startPosition: 0,
      ),
    ];

/// Every price the chart asks for, at the grain asked: BTC candles and
/// each prediction's history, wandering.
OpenPnlSources _sources(DateTime now) => OpenPnlSources(
      activity: (_) async => const [],
      candles: (_, wire, interval, window) async {
        final step = switch (interval) {
          '15m' => const Duration(minutes: 15),
          '1h' => const Duration(hours: 1),
          _ => const Duration(days: 1),
        };
        final out = <HyperliquidCandle>[];
        var i = 0;
        for (var t = now.subtract(window); t.isBefore(now); t = t.add(step)) {
          final px = 60000 + ((i * 37) % 900) - 300.0;
          out.add(HyperliquidCandle(
              openTime: t,
              closeTime: t.add(step),
              open: px,
              high: px,
              low: px,
              close: px,
              volume: 1));
          i++;
        }
        return out;
      },
      polyHistory: (_, token, interval) async {
        final (back, step) = switch (interval) {
          '1h' => (const Duration(hours: 1), const Duration(minutes: 1)),
          '6h' => (const Duration(hours: 6), const Duration(minutes: 5)),
          '1d' => (const Duration(days: 1), const Duration(minutes: 5)),
          '1w' => (const Duration(days: 7), const Duration(hours: 1)),
          '1m' => (const Duration(days: 30), const Duration(hours: 3)),
          _ => (const Duration(days: 200), const Duration(hours: 12)),
        };
        final out = <PolymarketPricePoint>[];
        var i = 0;
        for (var t = now.subtract(back); t.isBefore(now); t = t.add(step)) {
          out.add(PolymarketPricePoint(
              timestamp: t, price: 0.3 + ((i * 7) % 30) / 100));
          i++;
        }
        return out;
      },
    );

/// Mounts the page on Positions; returns the grids the first frames laid
/// (the hero's chart once its reads land).
Future<int> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1500) * 3;
  addTearDown(tester.view.reset);
  final before = debugPnlSeriesGrids;
  final now = DateTime.now();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(
          trading: const HyperliquidTradingState(
              isInitialized: true, positions: [_btcLong]),
          openPnlSources: _sources(now)),
      polymarketActivePositionsProvider
          .overrideWith((_) => _openPredictions(now)),
      // The Investments activity reads the price (no rates box here).
      currentBtcUsdProvider.overrideWithValue(100000),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
            investingKnown: true,
            predictionsKnown: true,
          )),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      hyperliquidActivityFillsProvider.overrideWithValue(_btcFills(now)),
      portfolioSectionProvider.overrideWith((_) => PortfolioSection.balances),
      livePriceProvider.overrideWith(() => _feed = _Prices()),
      ..._sixMonths(),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Material(
            child: Consumer(
              builder: (context, ref, _) => InvestmentsPortfolio(
                onSection: (s) =>
                    ref.read(portfolioSectionProvider.notifier).state = s,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return debugPnlSeriesGrids - before;
}

/// One frame's wall time, the grids it laid and the widgets it rebuilt
/// (by type name).
Future<({double ms, int grids, Map<String, int> built})> _frame(
    WidgetTester tester, Future<void> Function() action) async {
  final before = debugPnlSeriesGrids;
  final built = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final k = e.widget.runtimeType.toString();
    built[k] = (built[k] ?? 0) + 1;
  };
  final sw = Stopwatch()..start();
  try {
    await action();
  } finally {
    sw.stop();
    debugOnRebuildDirtyWidget = null;
  }
  return (
    ms: sw.elapsedMicroseconds / 1000,
    grids: debugPnlSeriesGrids - before,
    built: built,
  );
}

/// The heavy parts of the page: none of them may rebuild on a scrub
/// frame or on another market's tick (a scrub frame rebuilds the hero's
/// P&L line and the plot alone; a tick of a position held, the open line
/// and the Positions chart alone).
const _heavy = [
  'PortfolioHero',
  'PortfolioHeroChart',
  '_HeroFigure',
  '_HeroLine',
  'PortfolioStatisticsOverview',
  'PnlBreakdown',
  'PnlVenueRow',
  'PnlVenueSquare',
  'PnlStatsStrip',
  'PnlStatTiles',
  'PortfolioBalanceBreakdown',
  'PortfolioActivitySection',
];

int _heavyBuilt(Map<String, int> built) =>
    _heavy.fold(0, (t, k) => t + (built[k] ?? 0));

void main() {
  testWidgets('P&L: first chart, the section, range switch, scrub, live tick',
      (tester) async {
    final firstGrids = await _mount(tester);
    // Positions: the hero draws the open positions' P&L since each was
    // opened: its line laid ONCE (the P&L chart's series none).
    expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsNothing);
    final openChart = find.byKey(const ValueKey('portfolio-hero-open-chart'));
    expect(openChart, findsOneWidget);
    // Its line once: a range reaching back past it is ALL's window of the
    // same line, nothing laid again.
    expect(firstGrids, 1);

    // A scrub on it: no grid, nothing heavy, not even the chart's own
    // widget (the plot and the line's text alone).
    final openPlot = find.descendant(
        of: openChart, matching: find.byKey(const ValueKey('trend-chart-plot')));
    final openBox = tester.getRect(openPlot);
    final openGesture = await tester
        .startGesture(Offset(openBox.left + 10, openBox.center.dy));
    await tester.pump(const Duration(milliseconds: 16));
    await openGesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    var openScrubMs = 0.0;
    var openScrubGrids = 0;
    var openScrubHeavy = 0;
    const openMoves = 40;
    final openStep = (openBox.width - 60) / openMoves;
    for (var i = 0; i < openMoves; i++) {
      await openGesture.moveBy(Offset(openStep, 0));
      final f = await _frame(
          tester, () => tester.pump(const Duration(milliseconds: 16)));
      openScrubMs += f.ms;
      openScrubGrids += f.grids;
      openScrubHeavy += _heavyBuilt(f.built) + (f.built['_OpenPnlChart'] ?? 0);
    }
    expect(find.textContaining(' · Open P&L · '), findsOneWidget);
    await openGesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(openScrubGrids, 0, reason: 'grids laid scrubbing Positions');
    expect(openScrubHeavy, 0,
        reason: 'hero, section or chart widget rebuilt scrubbing Positions');

    // A live tick on a prediction held: the last point moves, no grid,
    // the open line and the chart alone rebuild.
    // The stream starts flowing (every live reader follows it once).
    _feed!.tickLive('open-0', 0.45);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final valuesBefore =
        tester.widget<KuteTrendChart>(openChart).values;
    final openTick = await _frame(tester, () async {
      _feed!.tick('open-0', 0.8);
      await tester.pump();
    });
    final valuesAfter = tester.widget<KuteTrendChart>(openChart).values;
    expect(openTick.grids, 0, reason: 'grids laid on a tick on Positions');
    // The hero stays put (the Positions rows below follow their prices,
    // as they always did).
    for (final heavy in const [
      'PortfolioHero',
      'PortfolioHeroChart',
      '_HeroFigure',
      '_HeroLine',
    ]) {
      expect(openTick.built[heavy], isNull,
          reason: '$heavy rebuilt on a tick on Positions');
    }
    expect(openTick.built['_OpenPnlChart'] ?? 0, lessThanOrEqualTo(1));
    expect(valuesAfter.length, valuesBefore.length);
    // 20 shares of open-0 from 0.45 to 0.80: +$7.00 on the last point.
    expect(valuesAfter.last - valuesBefore.last, closeTo(7, 1e-9));
    expect(openTick.built['_OpenPnlChart'], 1);
    expect(openTick.built['_HeroOpenLine'], 1);
    expect(valuesAfter.sublist(0, valuesAfter.length - 1),
        valuesBefore.sublist(0, valuesBefore.length - 1));
    // Another market's tick: nothing.
    final openOther = await _frame(tester, () async {
      _feed!.tick('someone-else', 0.2);
      await tester.pump();
    });
    expect(openOther.grids, 0);
    expect(_heavyBuilt(openOther.built) + (openOther.built['_OpenPnlChart'] ?? 0),
        0,
        reason: 'another market\'s tick rebuilt the Positions chart');
    // A Positions range: the window, no grid.
    await tester.tap(find.descendant(of: openChart, matching: find.text('1W')));
    final openRange = await _frame(tester, () => tester.pump());
    expect(openRange.grids, 0, reason: 'grids laid on a Positions range');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The P&L section: the pill tapped, one frame (its venue squares, the
    // hero's series); the hero's chart unfolds over the next frames.
    final sectionBefore = debugPnlSeriesGrids;
    await tester
        .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
    final first = await _frame(tester, () => tester.pump());
    expect(find.byKey(const ValueKey('statistics-figures')), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The whole P&L engine (the hero's and the venue squares'): each
    // venue's line and both venues' once (and the venues' own published
    // lines the squares draw while it is read).
    final sectionGrids = debugPnlSeriesGrids - sectionBefore;
    expect(sectionGrids, lessThanOrEqualTo(6),
        reason: 'grids laid opening the P&L section');
    final heroChart = find.byKey(const ValueKey('portfolio-hero-chart'));
    expect(heroChart, findsOneWidget);
    // Its last point is the P&L now: the venues' own figures added.
    expect(tester.widget<KuteTrendChart>(heroChart).values.last,
        closeTo(_hlNow + _pmNow, 1e-6));

    // A range switch: 3M tapped (half a year of history: 1Y would be ALL's
    // window, so it is not offered), one frame.
    expect(find.text('1Y'), findsNothing);
    await tester.tap(find.text('3M'));
    final range = await _frame(tester, () => tester.pump());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // An idle frame: what a frame costs the test harness alone.
    var idleMs = 0.0;
    for (var i = 0; i < 10; i++) {
      idleMs += (await _frame(
              tester, () => tester.pump(const Duration(milliseconds: 16))))
          .ms;
    }
    idleMs /= 10;

    // One paint of the plot (the line, its fill and the crosshair).
    final plot = find.byKey(const ValueKey('trend-chart-plot'));
    final painter = tester
        .widget<CustomPaint>(
            find.descendant(of: plot, matching: find.byType(CustomPaint)))
        .painter!;
    final plotSize = tester.getSize(plot);
    final paintSw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), plotSize);
      recorder.endRecording().dispose();
    }
    final paintMs = paintSw.elapsedMicroseconds / 1000 / 50;

    // A scrub: 40 moves across the plot, a frame each.
    final box = tester.getRect(plot);
    final gesture =
        await tester.startGesture(Offset(box.left + 10, box.center.dy));
    await tester.pump(const Duration(milliseconds: 16));
    // The drag recogniser claims the pointer past the slop.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    var scrubMs = 0.0;
    var scrubGrids = 0;
    var scrubHeavy = 0;
    const moves = 40;
    final step = (box.width - 60) / moves;
    for (var i = 0; i < moves; i++) {
      await gesture.moveBy(Offset(step, 0));
      final f = await _frame(
          tester, () => tester.pump(const Duration(milliseconds: 16)));
      scrubMs += f.ms;
      scrubGrids += f.grids;
      scrubHeavy += _heavyBuilt(f.built);
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    // A venue square picked: one frame lays its series once; a scrub on it
    // is as light as on both.
    final pick = await _frame(tester, () async {
      await tester.tap(find.byKey(const ValueKey('pnl-venue-predictions')));
      await tester.pump();
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final venueGesture =
        await tester.startGesture(Offset(box.left + 10, box.center.dy));
    await tester.pump(const Duration(milliseconds: 16));
    await venueGesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    var venueScrubGrids = 0;
    var venueScrubHeavy = 0;
    for (var i = 0; i < 20; i++) {
      await venueGesture.moveBy(Offset(step, 0));
      final f = await _frame(
          tester, () => tester.pump(const Duration(milliseconds: 16)));
      venueScrubGrids += f.grids;
      venueScrubHeavy += _heavyBuilt(f.built);
    }
    await venueGesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    // The venue's window is its square's already: nothing laid.
    expect(pick.grids, 0, reason: 'grids on a pick');
    expect(venueScrubGrids, 0, reason: 'grids laid scrubbing a venue');
    expect(venueScrubHeavy, 0,
        reason: 'hero or section rebuilt scrubbing a venue');

    // A live price tick on an open prediction.
    final tick = await _frame(tester, () async {
      _feed!.tick('open-0', 0.61);
      await tester.pump();
    });
    // A tick on a token the account does not hold.
    final other = await _frame(tester, () async {
      _feed!.tick('someone-else', 0.3);
      await tester.pump();
    });

    // ignore: avoid_print
    print('PNL_PERF mount=$firstGrids grids sectionSettle=$sectionGrids grids '
        'openScrub=${(openScrubMs / openMoves).toStringAsFixed(2)}ms/frame '
        'openTick=${openTick.ms.toStringAsFixed(1)}ms '
        'openRange=${openRange.ms.toStringAsFixed(1)}ms pick=${pick.ms.toStringAsFixed(1)}ms/${pick.grids} grids '
        'section=${first.ms.toStringAsFixed(1)}ms/${first.grids} grids '
        'range=${range.ms.toStringAsFixed(1)}ms/${range.grids} grids '
        'idle=${idleMs.toStringAsFixed(2)}ms paint=${paintMs.toStringAsFixed(2)}ms '
        'scrub=${(scrubMs / moves).toStringAsFixed(2)}ms/frame '
        '${(scrubGrids / moves).toStringAsFixed(2)} grids/frame '
        'tick=${tick.ms.toStringAsFixed(1)}ms/${tick.grids} grids '
        'otherTick=${other.ms.toStringAsFixed(1)}ms/${other.grids} grids');

    // The work, held: a scrub frame lays no grid and rebuilds only the
    // hero's P&L line and the plot; another market's tick rebuilds
    // nothing; the first chart, the section and a range switch lay each
    // series a bounded number of times (the venues, their sum).
    expect(scrubGrids, 0, reason: 'grids laid while scrubbing');
    expect(scrubHeavy, 0, reason: 'hero or section rebuilt while scrubbing');
    expect(other.grids, 0);
    expect(_heavyBuilt(other.built), 0,
        reason: 'another market\'s tick rebuilt the section');
    expect(first.grids, lessThanOrEqualTo(6));
    expect(range.grids, lessThanOrEqualTo(6));
    // A tick moves the line's pinned last point alone: no grid.
    expect(tick.grids, 0);
    // The hero's P&L line is there to follow the finger.
    expect(find.byKey(const ValueKey('portfolio-hero-change')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
