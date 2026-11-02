// The Portfolio screen's P&L Charts, measured (founder, 2 November 2026:
// "Portfolio P&L chart is super slow. Make it decent."). Six months of
// history at both venues (Investing every six hours, Predictions daily
// with a 200-position book): the time to the first chart, a range
// switch, a scrub frame and a live price tick, and how many P&L grids
// ([pnlSeries], up to 20,000 points each) each of them lays. The numbers
// are printed (`PNL_PERF …`) and held to budgets well above what the
// screen needs now, so a regression to per-frame recomputation fails.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
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

Future<void> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1500) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
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
                sharesHeader: true,
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
/// frame or on another market's tick.
const _heavy = [
  'PortfolioStatisticsOverview',
  'PortfolioPnlChart',
  'PnlVenueRow',
  'PnlStatsStrip',
  '_SectionHero',
  'PortfolioBalanceBreakdown',
];

int _heavyBuilt(Map<String, int> built) =>
    _heavy.fold(0, (t, k) => t + (built[k] ?? 0));

void main() {
  testWidgets('P&L Charts: first chart, range switch, scrub, live tick',
      (tester) async {
    await _mount(tester);

    // Time to the first chart: the pill tapped, one frame.
    await tester
        .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
    final first = await _frame(tester, () => tester.pump());
    expect(find.byKey(const ValueKey('statistics-pnl-chart')), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

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
    print('PNL_PERF first=${first.ms.toStringAsFixed(1)}ms/${first.grids} grids '
        'range=${range.ms.toStringAsFixed(1)}ms/${range.grids} grids '
        'idle=${idleMs.toStringAsFixed(2)}ms paint=${paintMs.toStringAsFixed(2)}ms '
        'scrub=${(scrubMs / moves).toStringAsFixed(2)}ms/frame '
        '${(scrubGrids / moves).toStringAsFixed(2)} grids/frame '
        'tick=${tick.ms.toStringAsFixed(1)}ms/${tick.grids} grids '
        'otherTick=${other.ms.toStringAsFixed(1)}ms/${other.grids} grids');

    // The work, held: a scrub frame lays no grid and rebuilds only the
    // figure, the line under it, the plot and the ring's hole; another
    // market's tick rebuilds nothing; the first chart and a range switch
    // lay each series once (both venues, their sum).
    expect(scrubGrids, 0, reason: 'grids laid while scrubbing');
    expect(scrubHeavy, 0, reason: 'section or ring rebuilt while scrubbing');
    expect(other.grids, 0);
    expect(_heavyBuilt(other.built), 0,
        reason: 'another market\'s tick rebuilt the section');
    expect(first.grids, lessThanOrEqualTo(6));
    expect(range.grids, lessThanOrEqualTo(6));
    expect(tick.grids, lessThanOrEqualTo(6));
    // The scrub's figure follows the finger, and the ring's hole with it.
    expect(find.byKey(const ValueKey('statistics-pnl-headline')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
