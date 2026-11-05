// The Portfolio screen's P&L, measured (founder, 2 November 2026:
// "Portfolio P&L chart is super slow. Make it decent."; since the
// overhaul of 4 November 2026 the one chart is the hero's and the P&L
// section lists the venues). Six months of history at both venues
// (Investing every six hours, Predictions daily with a 200-position
// book): the screen's first frames on Positions (whose hero draws no
// chart: no grid), the P&L section's first frame, a range switch, a scrub
// frame, a venue square picked and a scrub on it, and a live price tick,
// and how many P&L grids ([pnlSeries], up to 20,000 points each) each of
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

  void tick(String token, double price) =>
      state = LivePriceState(prices: {...state.prices, token: price});
}

const _days = 180;

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

/// Mounts the page on Positions; returns the grids the first frames laid
/// (the hero's chart once its reads land).
Future<int> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1500) * 3;
  addTearDown(tester.view.reset);
  final before = debugPnlSeriesGrids;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
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
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
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
/// P&L line and the plot alone).
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
    // Positions: the hero reads the positions open now, no chart, so no
    // P&L grid is laid for it.
    expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsNothing);
    expect(firstGrids, 0);

    // The P&L section: the pill tapped, one frame (its venue squares, the
    // hero's series); the hero's chart unfolds over the next frames.
    await tester
        .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
    final first = await _frame(tester, () => tester.pump());
    expect(find.byKey(const ValueKey('statistics-figures')), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsOneWidget);

    // A range switch: 1Y tapped, one frame.
    await tester.tap(find.text('1Y'));
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
    expect(pick.grids, lessThanOrEqualTo(6), reason: 'grids on a pick');
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
    print('PNL_PERF mount=$firstGrids grids pick=${pick.ms.toStringAsFixed(1)}ms/${pick.grids} grids '
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
    expect(tick.grids, lessThanOrEqualTo(6));
    // The hero's P&L line is there to follow the finger.
    expect(find.byKey(const ValueKey('portfolio-hero-change')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
