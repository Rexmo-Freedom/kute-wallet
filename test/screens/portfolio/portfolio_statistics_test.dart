import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart'
    show hyperliquidLiveMidProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show
        BalancesCategory,
        BalancesEndFigure,
        BalancesLiveFigure,
        balancesCategoryColor,
        kBalancesRingDiameter;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyEventsBatchFetchProvider, polyFeedCacheLookupProvider;
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

PortfolioPerformance _history() => PortfolioPerformance(
        points: [
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 8, 1, 23), pnlUsd: 10),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 9, 9, 23), pnlUsd: 30),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 9, 15, 23), pnlUsd: 70),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 9, 16, 23), pnlUsd: 20),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 9, 17, 23), pnlUsd: 40),
        ],
        totalPnlUsd: 40,
        realizedPnlUsd: 30,
        openPnlUsd: 10,
        sourceLabel: 'Polymarket',
        basisLabel: 'Economic P&L',
        coverageLabel: 'All time');

/// A Predictions account dated from now: its positions rebuild the
/// current figures (6 realised, 10 open) on top of a series that ends two
/// days ago.
PortfolioPerformance _predictions(
    {bool noOpen = false, bool none = false, bool drill = false}) {
  final now = DateTime.now().toUtc();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  PredictionRecord record(String token,
          {required bool open,
          required double totalSize,
          required double avgPrice,
          double size = 0,
          double price = 0,
          double realized = 0,
          required DateTime entered,
          required DateTime last,
          String market = '',
          String title = '',
          String event = '',
          String outcome = ''}) =>
      PredictionRecord(
          tokenId: token,
          open: open,
          redeemable: false,
          size: size,
          totalSize: totalSize,
          avgPrice: avgPrice,
          entryCostUsd: size * avgPrice,
          currentPrice: price,
          realizedPnlUsd: realized,
          unrealizedPnlUsd: size * (price - avgPrice),
          firstEntryAt: entered,
          lastEventAt: last,
          conditionId: market,
          title: title,
          eventSlug: event,
          outcome: outcome);
  return PortfolioPerformance(
          points: [
        PortfolioPnlPoint(timestamp: ago(40), pnlUsd: -5, realizedPnlUsd: -5),
        PortfolioPnlPoint(timestamp: ago(10), pnlUsd: 9, realizedPnlUsd: 7),
        PortfolioPnlPoint(timestamp: ago(2), pnlUsd: 15, realizedPnlUsd: 6),
      ],
          totalPnlUsd: 15,
          realizedPnlUsd: 6,
          asOf: ago(2),
          sourceLabel: 'Polymarket',
          basisLabel: 'Economic P&L',
          coverageLabel: 'All time')
      .withPredictions(PredictionsBook(records: [
    if (!none) ...[
      // Won 12 on 8 put in, decided twelve days ago.
      record('won',
          market: '0xsports',
          title: 'Lakers win the title?',
          event: 'nba-champion',
          outcome: 'Yes',
          open: false,
          totalSize: 20,
          avgPrice: .4,
          price: 1,
          realized: 12,
          entered: ago(15),
          last: ago(12)),
      // Lost 5, decided before the month.
      record('lost',
          market: '0xpolitics',
          open: false,
          totalSize: 10,
          avgPrice: .5,
          realized: -5,
          entered: ago(50),
          last: ago(45)),
    ],
    // Live: 40 shares at 0.50 now at 0.75, 1 of fees realised.
    if (!noOpen && !none)
      record('live',
          market: '0xcrypto',
          title: 'Bitcoin above 100k?',
          event: 'btc-100k',
          outcome: 'Yes',
          open: true,
          totalSize: 40,
          avgPrice: .5,
          size: 40,
          price: .75,
          realized: -1,
          entered: ago(3),
          last: ago(3)),
    // The drill-down's: a second market in the live one's event (10 No
    // shares at 0.50 now at 0.40: worth 4, −1), and another crypto event
    // with a live position (10 at 0.20 now at 0.10: worth 1, −1) and a
    // lost one (3 put in, all lost).
    if (drill) ...[
      record('live-c',
          market: '0xcrypto3',
          title: 'Bitcoin above 120k?',
          event: 'btc-100k',
          outcome: 'No',
          open: true,
          totalSize: 10,
          avgPrice: .5,
          size: 10,
          price: .4,
          entered: ago(3),
          last: ago(3)),
      record('live-b',
          market: '0xcrypto2',
          title: 'Bitcoin 150k this year?',
          event: 'btc-150k',
          outcome: 'Yes',
          open: true,
          totalSize: 10,
          avgPrice: .2,
          size: 10,
          price: .1,
          entered: ago(4),
          last: ago(4)),
      record('lost-b',
          market: '0xcrypto2',
          title: 'Bitcoin 150k this year?',
          event: 'btc-150k',
          outcome: 'No',
          open: false,
          totalSize: 10,
          avgPrice: .3,
          realized: -3,
          entered: ago(30),
          last: ago(25)),
    ],
  ]));
}

/// An Investing account: the venue's P&L series (no realised / open split)
/// ending two days ago, and on the device its fills and open positions.
/// The ETH trade was closed twenty days ago for +10 gross on 1 of fees;
/// BTC opened five days ago and is still open.
PortfolioPerformance _tradingHistory() {
  final now = DateTime.now().toUtc();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  return PortfolioPerformance(
      points: [
        PortfolioPnlPoint(timestamp: ago(40), pnlUsd: -5),
        PortfolioPnlPoint(timestamp: ago(10), pnlUsd: 9),
        PortfolioPnlPoint(timestamp: ago(2), pnlUsd: 15),
      ],
      totalPnlUsd: 15,
      asOf: ago(2),
      sourceLabel: 'Hyperliquid',
      basisLabel: 'Reported account P&L',
      coverageLabel: 'All time');
}

List<HlFill> _tradingFills() {
  final now = DateTime.now().toUtc();
  int ago(int days) =>
      now.subtract(Duration(days: days)).millisecondsSinceEpoch;
  HlFill fill(String id, String coin, double before, double size, String side,
          int time,
          {required double px, double pnl = 0, required double fee}) =>
      HlFill.fromJson({
        'coin': coin,
        'tid': id,
        'oid': int.parse(id),
        'hash': 'h$id',
        'time': time,
        'startPosition': '$before',
        'sz': '$size',
        'px': '$px',
        'side': side,
        'closedPnl': '$pnl',
        'fee': '$fee',
        'feeToken': 'USDC',
        'dir': before == 0 ? 'Open Long' : 'Close Long',
      });
  return [
    fill('3', 'BTC', 0, 0.1, 'B', ago(5), px: 60000, fee: 1),
    fill('2', 'ETH', 1, 1, 'A', ago(20), px: 110, pnl: 10, fee: 0.5),
    fill('1', 'ETH', 0, 1, 'B', ago(50), px: 100, fee: 0.5),
  ];
}

/// The Investing account as the venue reports it, every read.
class _Account extends HlAccountNotifier {
  _Account(this.snapshot);
  final HlAccountSnapshot snapshot;

  @override
  Future<HlAccountSnapshot> build() async => snapshot;
}

HlAccountSnapshot _flat() => const HlAccountSnapshot(
    accountValue: 100,
    withdrawable: 100,
    totalMarginUsed: 0,
    positions: [],
    spotBalances: [HlSpotBalance(coin: 'USDC', total: 100, hold: 0)]);

HlAccountSnapshot _positions() => const HlAccountSnapshot(
      accountValue: 100,
      withdrawable: 50,
      totalMarginUsed: 50,
      positions: [
        HlPerpPosition(
            coin: 'BTC',
            szi: 0.1,
            entryPx: 60000,
            positionValue: 6007.5,
            unrealizedPnl: 7.5,
            returnOnEquity: 0,
            liquidationPx: null,
            marginUsed: 50,
            leverageType: 'cross',
            leverageValue: 1,
            maxLeverage: 40),
        HlPerpPosition(
            coin: 'SOL',
            szi: -2,
            entryPx: 20,
            positionValue: 42.5,
            unrealizedPnl: -2.5,
            returnOnEquity: 0,
            liquidationPx: null,
            marginUsed: 10,
            leverageType: 'cross',
            leverageValue: 1,
            maxLeverage: 20),
      ],
      spotBalances: [],
    );

Future<void> _pump(WidgetTester tester,
    {bool hidden = false,
    bool empty = false,
    bool fail = false,
    PortfolioPerformance? series,
    bool predictions = false,
    bool trading = false,
    bool noOpen = false,
    bool noPredictions = false,
    bool flat = false,
    bool drill = false,
    List<NavigatorObserver> observers = const [],
    List<Override> overrides = const [],
    StatisticsScope scope = StatisticsScope.historic,
    bool reduceMotion = false,
    bool settle = true,
    bool tagsPending = false,
    bool tagsFail = false,
    Map<String, Set<String>>? tags,
    double textScale = 1,
    Size size = const Size(390, 844),
    Override? displayAccount,
    Widget? home}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            balancePrivacy: hidden ? 1 : 0))),
        portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                venue: PortfolioPerformanceVenue.predictions))
            .overrideWith((_) async {
          if (fail) throw Exception('offline');
          if (series != null) return series;
          return empty
              ? const PortfolioPerformance(
                  points: [],
                  sourceLabel: 'Polymarket',
                  basisLabel: 'P&L',
                  coverageLabel: 'No observations')
              : predictions
                  ? _predictions(
                      noOpen: noOpen, none: noPredictions, drill: drill)
                  : _history();
        }),
        portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                venue: PortfolioPerformanceVenue.trading))
            .overrideWith((_) async => _tradingHistory()),
        hyperliquidUserFillsProvider.overrideWith((_) async => _tradingFills()),
        hyperliquidActivityFillsProvider.overrideWithValue(_tradingFills()),
        hyperliquidAccountProvider
            .overrideWith(() => _Account(flat ? _flat() : _positions())),
        displayAccount ??
            hyperliquidDisplayAccountProvider
                .overrideWith((ref) => ref.watch(hyperliquidAccountProvider)),
        hyperliquidPerpMarketsProvider.overrideWith((_) async => const []),
        hyperliquidSpotMarketsProvider.overrideWith((_) async => const []),
        // Gamma's tags for the three markets the predictions were on.
        polyMarketTagsFetchProvider.overrideWithValue(tagsPending
            ? (ids) => Completer<Map<String, Set<String>>>().future
            : tagsFail
                ? (ids) async => throw Exception('offline')
                : (ids) async =>
                    tags ??
                    {
                      '0xsports': {'sports', 'nba'},
                      '0xpolitics': {'politics', 'us-politics'},
                      '0xcrypto': {'crypto', 'bitcoin'},
                      '0xcrypto2': {'crypto'},
                      '0xcrypto3': {'crypto'},
                    }),
        // The drill-down's event titles and images: nothing to read.
        polyEventsBatchFetchProvider.overrideWithValue((slugs) async => []),
        polyFeedCacheLookupProvider.overrideWithValue((slug) => null),
        ...overrides,
      ],
      child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                navigatorObservers: observers,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                        disableAnimations: reduceMotion),
                    child: child!),
                home: Scaffold(
                    body: home ??
                        PortfolioStatistics(
                            venue: trading
                                ? PortfolioPerformanceVenue.trading
                                : PortfolioPerformanceVenue.predictions)),
              ))));
  // The tab opens on Active; the all-time figures are a tap away.
  if (scope == StatisticsScope.historic) {
    final pill = find.byKey(const ValueKey('statistics-historic'));
    for (var i = 0; i < 5 && pill.evaluate().isEmpty; i++) {
      await tester.pump();
    }
    if (pill.evaluate().isNotEmpty) {
      await tester.tap(pill);
      await tester.pump();
    }
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // The providers' futures, then the first frames of the entrance.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }
}

/// The Statistics card: the app's card surface the sub-tab's donut and
/// figures sit on (the P&L chart's card above it aside).
final _card = find.byWidgetPredicate((w) =>
    w is Container &&
    w.clipBehavior == Clip.antiAlias &&
    w.decoration != null &&
    w.key != const ValueKey('statistics-pnl-card'));

/// The P&L chart's card.
final _chartCard = find.byKey(const ValueKey('statistics-pnl-card'));

/// The figure in the donut's hole.
String _hole(WidgetTester tester) => tester
    .widget<RollingNumberText>(find.descendant(
        of: find.byType(PortfolioCategoryCard),
        matching: find.byType(RollingNumberText)))
    .text;

/// A stat tile's figure, read under its [label].
String _tile(WidgetTester tester, String label) {
  final column =
      find.ancestor(of: find.text(label), matching: find.byType(Column));
  final texts = tester
      .widgetList<Text>(
          find.descendant(of: column.first, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts[texts.indexOf(label) + 1]!;
}

/// The donut's data painter as last drawn.
KuteDonutPainter _ring(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
        of: find.byType(KuteDonutChart), matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<KuteDonutPainter>()
    .single;

/// Taps the ring [fraction] of the way round from twelve o'clock.
Future<void> _tapRing(WidgetTester tester, double fraction) async {
  final rect = tester.getRect(find.byType(KuteDonutChart));
  final g = KuteDonutGeometry.of(rect.size, thickness: _ring(tester).thickness);
  final a = fraction * 2 * math.pi;
  await tester.tapAt(
      rect.topLeft + g.center + Offset(math.sin(a), -math.cos(a)) * g.radius);
  await tester.pumpAndSettle();
}

/// The texts in the donut's hole and legend.
List<String> _donutTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(PortfolioCategoryCard), matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  setUp(debugClearPolyCategoryCache);

  testWidgets(
      'the P&L chart leads, the sub-tab pills under it, then the card with '
      'the category donut and the tiles', (tester) async {
    await _pump(tester, predictions: true);
    // The chart card: caption, the account's P&L (6 realised + 10 open)
    // and the line over the range picked under it.
    expect(_chartCard, findsOneWidget);
    expect(find.byType(PortfolioPnlChart), findsOneWidget);
    expect(find.text('Profit and loss'), findsOneWidget);
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('statistics-pnl-headline')))
            .text,
        r'+$16.00');
    final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
    // The result colour (up over the month), straight segments.
    expect(chart.lineColor, AppColors.marketUp);
    expect(chart.straight, isTrue);
    expect(chart.zoomable, isTrue);
    // From zero before the first trade to the P&L now.
    expect(chart.values.first, 0);
    expect(chart.values.last, 16);
    expect(chart.values.toSet(), containsAll(<double>[0, -5, 9, 15, 16]));
    // The range row under the plot, 1M to start.
    expect(find.byType(KuteRangePills), findsOneWidget);
    for (final pill in ['1W', '1M', '3M', '1Y', 'ALL']) {
      expect(find.text(pill), findsOneWidget);
    }
    // One soft fade under the line, a solid hairline at zero.
    expect(chart.showFill, isTrue);
    expect(chart.baselineAt, 0);
    expect(chart.solidBaseline, isTrue);
    expect(chart.fillAboveColor, isNull);
    expect(chart.fillBelowColor, isNull);
    // The figure leads: the balance type, over the 20sp tile figures.
    final hero = tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .style;
    final balance =
        AppTextStyles.balance(tester.element(find.byType(PortfolioPnlChart)));
    expect(hero.fontSize, balance.fontSize);
    expect(hero.fontWeight, FontWeight.w700);
    expect(hero.color, AppColors.marketUp);
    expect(find.text('Total gains and losses'), findsNothing);
    // Chart, then the sub-tab pills, then the donut card.
    expect(
        tester.getBottomLeft(_chartCard).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('statistics-active')))
            .dy));
    expect(
        tester
            .getBottomLeft(find.byKey(const ValueKey('statistics-active')))
            .dy,
        lessThan(tester.getTopLeft(_card).dy));
    // Two rolling figures: the chart's headline and the donut's hole.
    expect(find.byType(RollingNumberText), findsNWidgets(2));
    expect(_hole(tester), r'$33.00');
    // One card under the pills: the donut flush at its top, on the card's
    // own surface (no card of its own), the tiles under it.
    expect(_card, findsOneWidget);
    expect(find.descendant(of: _card, matching: find.byType(KuteDonutChart)),
        findsOneWidget);
    expect(tester.getTopLeft(find.byType(PortfolioCategoryCard)).dy,
        tester.getTopLeft(_card).dy);
    final donutBox = tester.widget<Container>(find
        .descendant(
            of: find.byType(PortfolioCategoryCard),
            matching: find.byType(Container))
        .first);
    expect(donutBox.decoration, isNull);
    expect(donutBox.margin, isNull);
    expect(tester.getBottomLeft(find.byType(KuteDonutChart)).dy,
        lessThan(tester.getTopLeft(find.text('Amount predicted')).dy));
    // What is settled, signed and coloured as the headline, leads the
    // tiles.
    expect(_tile(tester, 'Realized P&L'), r'+$6.00');
    expect(tester.widget<Text>(find.text(r'+$6.00')).style?.color,
        AppColors.marketUp);
    expect(tester.takeException(), isNull);
  });
  testWidgets('without categories the card starts with the tiles',
      (tester) async {
    // The markets' categories could not be read: no donut, no gap.
    await _pump(tester, predictions: true, tagsFail: true);
    expect(find.byType(KuteDonutChart), findsNothing);
    expect(find.byType(PortfolioCategorySkeleton), findsNothing);
    // The chart stays: it is the series', not the categories'.
    expect(find.byType(KuteLineChart), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Amount predicted')).dy -
            tester.getTopLeft(_card).dy,
        closeTo(16 * 390 / 430, 1));
    expect(_tile(tester, 'Amount predicted'), r'$33.00');
    expect(_tile(tester, 'Realized P&L'), r'+$6.00');
    expect(tester.takeException(), isNull);
  });
  testWidgets('while the categories load, the skeleton sits in the card',
      (tester) async {
    await _pump(tester, predictions: true, tagsPending: true, settle: false);
    final skeleton = find.byType(PortfolioCategorySkeleton);
    expect(skeleton, findsOneWidget);
    expect(find.descendant(of: _card, matching: skeleton), findsOneWidget);
    expect(find.descendant(of: skeleton, matching: find.byType(SkeletonCard)),
        findsNothing);
    expect(tester.getTopLeft(skeleton).dy, tester.getTopLeft(_card).dy);
    expect(find.text('Amount predicted'), findsOneWidget);
    expect(find.text('Realized P&L'), findsOneWidget);
  });
  testWidgets(
      'empty history does not fabricate a zero result: the quiet line in '
      'the chart\'s place', (tester) async {
    await _pump(tester, empty: true);
    expect(find.byType(KuteLineChart), findsNothing);
    expect(_chartCard, findsNothing);
    expect(
        find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
    expect(find.text('No predictions yet'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.byIcon(Icons.insights_outlined), findsNothing);
  });
  testWidgets('nothing published and nothing done: one quiet line, not two',
      (tester) async {
    await _pump(tester, empty: true, scope: StatisticsScope.active);
    expect(
        find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-empty')), findsNothing);
    expect(find.text('No predictions yet'), findsOneWidget);
  });
  testWidgets('failure remains retryable instead of empty', (tester) async {
    await _pump(tester, fail: true);
    expect(find.text('Performance unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('statistics fits accessibility text', (tester) async {
    await _pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await _pump(tester, textScale: 2, predictions: true);
    expect(tester.takeException(), isNull);
  });

  group('Empty and flat lines', () {
    PortfolioPerformance series(List<(int, double)> points) {
      final now = DateTime.now().toUtc();
      return PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: now.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          sourceLabel: 'Polymarket',
          basisLabel: 'Economic P&L',
          coverageLabel: 'All time');
    }

    testWidgets(
        'a P&L at zero all the way draws no line: the quiet line in its '
        'place', (tester) async {
      await _pump(tester, series: series([(40, 0), (10, 0), (1, 0)]));
      expect(find.byType(KuteLineChart), findsNothing);
      expect(_chartCard, findsNothing);
      expect(
          find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
      expect(find.text('No predictions yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a line flat for its last months still moved from zero: no change '
        'in the month, over the baseline at zero', (tester) async {
      // Five dollars made two months ago, nothing since.
      await _pump(tester, series: series([(60, 5), (40, 5), (1, 5)]));
      expect(find.byType(KuteLineChart), findsOneWidget);
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      expect(chart.values.first, 0);
      expect(chart.values.last, 5);
      expect(chart.baselineAt, 0);
      expect(find.text('No change in the past month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a young account: the month opens on its whole history, from the '
        'first trade', (tester) async {
      await _pump(tester, series: series([(10, 2), (1, 5)]));
      expect(
          find.byKey(const ValueKey('statistics-pnl-chart')), findsOneWidget);
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      expect(chart.values.first, 0);
      expect(chart.values.last, 5);
      expect(chart.defaultSpan, chart.values.length - 1);
      expect(find.byType(KuteRangePills), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PortfolioPerformance.combine', () {
    final t0 = DateTime.utc(2026, 9, 1);
    DateTime day(int n) => t0.add(Duration(days: n));
    PortfolioPerformance series(List<(int, double)> points,
            {double? realized, double? open}) =>
        PortfolioPerformance(
            points: [
              for (final (n, pnl) in points)
                PortfolioPnlPoint(timestamp: day(n), pnlUsd: pnl)
            ],
            totalPnlUsd: points.isEmpty ? null : points.last.$2,
            realizedPnlUsd: realized,
            openPnlUsd: open,
            sourceLabel: 'v',
            basisLabel: 'P&L',
            coverageLabel: 'All time');

    test(
        'adds the venues on every moment either published, carrying each '
        'at its last point (zero before its first)', () {
      final sum = PortfolioPerformance.combine([
        series([(0, -5), (3, 9), (5, 15)]),
        series([(2, 1), (3, 2), (6, 4)]),
      ]);
      expect([for (final p in sum.points) p.timestamp],
          [day(0), day(2), day(3), day(5), day(6)]);
      expect([for (final p in sum.points) p.pnlUsd], [-5, -4, 11, 17, 19]);
      expect(sum.totalPnlUsd, 19);
      expect(sum.hasMovement, isTrue);
    });

    test('a venue with no series is the other venue', () {
      final sum = PortfolioPerformance.combine([
        series([]),
        series([(1, 3), (2, 7)], realized: 2, open: 5),
      ]);
      expect([for (final p in sum.points) p.pnlUsd], [3, 7]);
      expect(sum.totalPnlUsd, 7);
      expect(sum.realizedPnlUsd, 2);
      expect(sum.openPnlUsd, 5);
    });

    test('a split one venue does not publish leaves the sum\'s unknown', () {
      final sum = PortfolioPerformance.combine([
        series([(1, 3)], realized: 2, open: 1),
        series([(1, 4)]),
      ]);
      expect(sum.realizedPnlUsd, isNull);
      expect(sum.openPnlUsd, isNull);
      expect(sum.totalPnlUsd, 7);
    });

    test('nothing at all, or zero all the way, has no movement', () {
      expect(PortfolioPerformance.combine([]).hasMovement, isFalse);
      expect(
          PortfolioPerformance.combine([
            series([(0, 0), (2, 0)]),
            series([(1, 0)]),
          ]).hasMovement,
          isFalse);
    });
  });

  group('Predictions figures', () {
    testWidgets('the tiles are all time, today\'s positions included',
        (tester) async {
      await _pump(tester, predictions: true);
      await tester.scrollUntilVisible(find.text('Predictions'), 100);
      // What is settled, every stake and every prediction; the open P&L
      // is Active's.
      expect(_tile(tester, 'Realized P&L'), r'+$6.00');
      expect(find.text('Open P&L'), findsNothing);
      expect(_tile(tester, 'Amount predicted'), r'$33.00');
      expect(_tile(tester, 'Predictions'), '3');
      // No score of any kind.
      expect(find.text('Biggest win'), findsNothing);
      expect(find.textContaining('ccuracy'), findsNothing);
      expect(find.textContaining('rate'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden balances hide the tiles\' amounts, not the count',
        (tester) async {
      await _pump(tester, predictions: true, hidden: true);
      expect(find.textContaining(r'$'), findsNothing);
      expect(_tile(tester, 'Predictions'), '3');
      expect(_tile(tester, 'Amount predicted'), '••••••');
      expect(_tile(tester, 'Realized P&L'), '••••••');
    });

    testWidgets('without positions there are no prediction tiles',
        (tester) async {
      await _pump(tester);
      expect(find.text('Amount predicted'), findsNothing);
    });
  });

  group('Investing figures', () {
    testWidgets(
        'the same tiles as Predictions, all time, from the fills and the '
        'open positions', (tester) async {
      await _pump(tester, trading: true);
      await tester.scrollUntilVisible(find.text('Trades'), 100);
      // Every fill: the ETH round trip (+10 on 1 of fees) and the BTC
      // open (1 of fees); what closing realised leads.
      expect(_tile(tester, 'Realized P&L'), r'+$8.00');
      expect(find.text('Open P&L'), findsNothing);
      expect(_tile(tester, 'Volume traded'), r'$6,210.00');
      expect(_tile(tester, 'Trades'), '3');
      expect(find.text('Biggest win'), findsNothing);
      // No Predictions tile, and no funding tile: the venue gives funding
      // per trade.
      expect(find.text('Amount predicted'), findsNothing);
      expect(find.text('Predictions'), findsNothing);
      expect(find.textContaining('unding'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden balances hide the amounts, not the count',
        (tester) async {
      await _pump(tester, trading: true, hidden: true);
      expect(find.textContaining(r'$'), findsNothing);
      expect(_tile(tester, 'Trades'), '3');
      expect(_tile(tester, 'Volume traded'), '••••••');
      expect(_tile(tester, 'Realized P&L'), '••••••');
    });

    testWidgets('fits accessibility text', (tester) async {
      await _pump(tester, trading: true, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Category donut', () {
    testWidgets(
        'Predictions: the amount predicted per category, all time, at the '
        'top of the card', (tester) async {
      await _pump(tester, predictions: true);
      await tester.scrollUntilVisible(find.byType(KuteDonutChart), 200);
      await tester.pumpAndSettle();
      // Above the figures, never under them.
      expect(tester.getBottomLeft(find.byType(PortfolioCategoryCard)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text('Predictions')).dy));
      // 20 on crypto, 8 on sports, 5 on politics: the Predictions pills'
      // names, largest first; the percents add up to 100.
      final texts = _donutTexts(tester);
      expect(
          texts,
          containsAllInOrder([
            'All time',
            'Crypto',
            '61%',
            r'$20.00',
            'Sports',
            '24%',
            r'$8.00',
            'Politics',
            '15%',
            r'$5.00',
          ]));
      expect(_hole(tester), r'$33.00');
      // The slices wear the theme's categorical palette in slice order.
      final donut = tester.widget<KuteDonutChart>(find.byType(KuteDonutChart));
      expect([for (final s in donut.segments) s.color],
          AppColorsExtension.light().chartCategorical.take(3).toList());
      // Each slice reads out on its own.
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final labels = <String>[];
      bool collect(SemanticsNode node) {
        labels.add(node.label);
        node.visitChildren(collect);
        return true;
      }

      tester.getSemantics(find.byType(KuteDonutChart)).visitChildren(collect);
      expect(
          labels,
          containsAll([
            r'Crypto, 61%, $20.00',
            r'Sports, 24%, $8.00',
            r'Politics, 15%, $5.00'
          ]));
      semantics.dispose();
      expect(find.text('Biggest win'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a tap on a slice picks it: the hole names it, a selection click, '
        'one event once it settles; the centre clears', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, predictions: true);
      await tester.scrollUntilVisible(find.byType(KuteDonutChart), 200);
      await tester.pumpAndSettle();
      // The Historic pill's own click aside.
      haptics.clear();
      events.clear();
      // Sports runs from 61% to 85% of the way round.
      await _tapRing(tester, 0.72);
      expect(_ring(tester).selectedId, 'sports');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      final texts = _donutTexts(tester);
      expect(texts.first, 'Sports');
      expect(texts, contains('24% of total'));
      expect(_hole(tester), r'$8.00');
      // Reported once the pick has held.
      expect(events.where((e) => e.$1 == 'portfolio_category_slice_selected'),
          isEmpty);
      await tester.pump(const Duration(milliseconds: 700));
      final picked = events
          .where((e) => e.$1 == 'portfolio_category_slice_selected')
          .toList();
      expect(picked.length, 1);
      expect(picked.single.$2, {
        'venue': 'predictions',
        'slice_rank': 2,
        'category_kind': 'category',
        'category': 'sports',
        'wallet_kind': 'hot',
        'scope': 'historic',
        'drill_level': 1,
      });
      // The centre clears.
      await tester.tap(find.byType(KuteDonutChart));
      await tester.pumpAndSettle();
      expect(_ring(tester).selectedId, isNull);
      expect(_donutTexts(tester).first, 'All time');
    });

    testWidgets(
        'a legend row picks the same slice and opens it; the All pill '
        'brings the legend back', (tester) async {
      await _pump(tester, predictions: true);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('category-legend-politics')), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-legend-politics')));
      await tester.pumpAndSettle();
      expect(_ring(tester).selectedId, 'politics');
      expect(_donutTexts(tester), contains('15% of total'));
      expect(
          find.byKey(const ValueKey('category-legend-politics')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('category-drill-back')));
      await tester.pumpAndSettle();
      expect(_ring(tester).selectedId, isNull);
      expect(find.byKey(const ValueKey('category-legend-politics')),
          findsOneWidget);
    });

    testWidgets('hidden balances mask the amounts and the shares',
        (tester) async {
      await _pump(tester, predictions: true, hidden: true);
      await tester.scrollUntilVisible(find.byType(KuteDonutChart), 200);
      await tester.pumpAndSettle();
      final texts = _donutTexts(tester);
      expect(texts, containsAllInOrder(['Crypto', '••%', '••••••']));
      expect(texts.any((t) => t.contains(r'$') || t.contains('61')), isFalse);
      await tester.tap(find.byKey(const ValueKey('category-legend-crypto')));
      await tester.pumpAndSettle();
      expect(_donutTexts(tester), contains('••% of total'));
    });

    testWidgets('the slices sweep in, drawn at once under Reduce Motion',
        (tester) async {
      await _pump(tester, predictions: true, settle: false);
      expect(_ring(tester).sweep, lessThan(1));
      await tester.pumpAndSettle();
      expect(_ring(tester).sweep, 1);
      await _pump(tester, predictions: true, reduceMotion: true, settle: false);
      expect(_ring(tester).sweep, 1);
    });

    testWidgets('Investing: the volume traded per category', (tester) async {
      await _pump(tester, trading: true);
      await tester.scrollUntilVisible(find.byType(KuteDonutChart), 200);
      await tester.pumpAndSettle();
      // Every fill is on a main-dex perp: all crypto, all time.
      expect(_donutTexts(tester),
          containsAllInOrder(['All time', 'Crypto', '100%', r'$6,210.00']));
      expect(find.text('Biggest win'), findsNothing);
    });

    testWidgets('the card fits accessibility text', (tester) async {
      await _pump(tester, predictions: true, textScale: 2);
      await tester.scrollUntilVisible(find.byType(KuteDonutChart), 200);
      await tester.tap(find.byKey(const ValueKey('category-legend-sports')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no donut without predictions to split', (tester) async {
      await _pump(tester);
      expect(find.byType(KuteDonutChart), findsNothing);
    });
  });

  group('Active | Historic', () {
    bool selected(WidgetTester tester, String key) => tester
        .widget<KutePill>(find.byKey(ValueKey('statistics-$key')))
        .selected;

    testWidgets('the tab opens on Active; the pills switch the content',
        (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pump(tester, predictions: true, scope: StatisticsScope.active);
      expect(selected(tester, 'active'), isTrue);
      expect(selected(tester, 'historic'), isFalse);
      // The pills sit above the card.
      expect(
          tester
              .getBottomLeft(find.byKey(const ValueKey('statistics-active')))
              .dy,
          lessThan(tester.getTopLeft(_card).dy));
      expect(find.text('Amount at stake'), findsOneWidget);
      expect(find.text('Amount predicted'), findsNothing);
      expect(find.text('Open P&L'), findsOneWidget);
      expect(find.text('Realized P&L'), findsNothing);
      expect(events.where((e) => e.$1 == 'portfolio_tab_changed'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      expect(selected(tester, 'historic'), isTrue);
      expect(find.text('Amount at stake'), findsNothing);
      expect(find.text('Amount predicted'), findsOneWidget);
      expect(find.text('Realized P&L'), findsOneWidget);
      expect(find.text('Open P&L'), findsNothing);
      expect(_donutTexts(tester).first, 'All time');
      expect(events.where((e) => e.$1 == 'portfolio_tab_changed').single.$2,
          {'tab': 'statistics', 'subtab': 'historic'});

      // The picked pill again sends nothing.
      await tester.tap(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      expect(events.where((e) => e.$1 == 'portfolio_tab_changed').length, 1);
      await tester.tap(find.byKey(const ValueKey('statistics-active')));
      await tester.pumpAndSettle();
      expect(events.where((e) => e.$1 == 'portfolio_tab_changed').last.$2,
          {'tab': 'statistics', 'subtab': 'active'});
      expect(find.text('Amount at stake'), findsOneWidget);
    });

    testWidgets(
        'Predictions Active: the live positions\' value by category, what '
        'they cost and how many', (tester) async {
      await _pump(tester, predictions: true, scope: StatisticsScope.active);
      // Only the live prediction is open: 40 shares now at 0.75, on crypto.
      expect(_donutTexts(tester),
          containsAllInOrder(['Active', 'Crypto', '100%', r'$30.00']));
      expect(_hole(tester), r'$30.00');
      expect(find.text('Sports'), findsNothing);
      await tester.scrollUntilVisible(find.text('Open positions'), 100);
      // 40 shares bought at 0.50 now at 0.75.
      expect(_tile(tester, 'Open P&L'), r'+$10.00');
      expect(_tile(tester, 'Amount at stake'), r'$20.00');
      expect(_tile(tester, 'Open positions'), '1');
      expect(find.text('Amount predicted'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Investing Active: open positions at their close value',
        (tester) async {
      await _pump(tester, trading: true, scope: StatisticsScope.active);
      // BTC: 50 of margin +7.5; SOL: 10 of margin −2.5. Both crypto.
      expect(_donutTexts(tester),
          containsAllInOrder(['Active', 'Crypto', '100%', r'$65.00']));
      await tester.scrollUntilVisible(find.text('Open positions'), 100);
      // BTC +7.5, SOL −2.5.
      expect(_tile(tester, 'Open P&L'), r'+$5.00');
      expect(_tile(tester, 'Amount at stake'), r'$60.00');
      expect(_tile(tester, 'Open positions'), '2');
      expect(find.text('Volume traded'), findsNothing);
    });

    testWidgets('an Active pick carries scope active', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pump(tester, predictions: true, scope: StatisticsScope.active);
      await tester.tap(find.byKey(const ValueKey('category-legend-crypto')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(
          events
              .where((e) => e.$1 == 'portfolio_category_slice_selected')
              .single
              .$2,
          {
            'venue': 'predictions',
            'slice_rank': 1,
            'category_kind': 'category',
            'category': 'crypto',
            'wallet_kind': 'hot',
            'scope': 'active',
            'drill_level': 1,
          });
    });

    testWidgets('nothing open: one quiet line on Active, Historic unchanged',
        (tester) async {
      await _pump(tester,
          predictions: true, noOpen: true, scope: StatisticsScope.active);
      expect(find.text('No open predictions'), findsOneWidget);
      expect(find.byType(KuteDonutChart), findsNothing);
      expect(find.text('Open P&L'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      expect(find.text('No open predictions'), findsNothing);
      expect(_tile(tester, 'Predictions'), '2');
    });

    testWidgets('Investing with nothing open says so', (tester) async {
      await _pump(tester,
          trading: true, flat: true, scope: StatisticsScope.active);
      expect(find.text('No open investments'), findsOneWidget);
      expect(find.text('Open P&L'), findsNothing);
    });

    testWidgets('nothing ever predicted: one quiet line on Historic',
        (tester) async {
      await _pump(tester, predictions: true, noPredictions: true);
      expect(find.text('No predictions yet'), findsOneWidget);
      expect(find.text('Realized P&L'), findsNothing);
    });

    testWidgets('Active fits accessibility text', (tester) async {
      await _pump(tester,
          predictions: true, textScale: 2, scope: StatisticsScope.active);
      expect(tester.takeException(), isNull);
      await _pump(tester,
          trading: true, textScale: 2, scope: StatisticsScope.active);
      expect(tester.takeException(), isNull);
    });
  });

  group('Empty states', () {
    final sal = find.byType(NoActivityState);

    /// The app's empty state (Sal, the headline, a tagline) saying
    /// [title], [compact] or not, with no card around it and no figures.
    /// [inBlock]: in the venue rows' place inside the spending account's
    /// one card, under its lead row.
    void expectEmptyState(WidgetTester tester, String title,
        {required bool compact, bool inBlock = false}) {
      expect(sal, findsOneWidget);
      expect(tester.widget<NoActivityState>(sal).compact, compact);
      expect(
          find.descendant(of: sal, matching: find.text(title)), findsOneWidget);
      expect(
          find.ancestor(
              of: sal,
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration != null)),
          inBlock ? findsOneWidget : findsNothing);
      if (inBlock) {
        expect(find.descendant(of: _chartCard, matching: sal), findsOneWidget);
      }
      expect(_card, findsNothing);
      expect(find.byKey(const ValueKey('statistics-figures')), findsNothing);
      expect(find.text(r'$0.00'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    testWidgets(
        'Active with nothing open: the compact empty state under the pills, '
        'no card, no figures of zeros', (tester) async {
      await _pump(tester,
          predictions: true, noOpen: true, scope: StatisticsScope.active);
      expect(find.byKey(const ValueKey('statistics-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-active')), findsOneWidget);
      expect(find.text('Open P&L'), findsNothing);
      expect(find.text('At stake'), findsNothing);
      expectEmptyState(tester, 'No open predictions', compact: true);
    });

    testWidgets(
        'the spending account\'s Active with nothing open: no chart, only '
        'the lead row and the compact empty state', (tester) async {
      await _pump(tester,
          flat: true,
          scope: StatisticsScope.active,
          home: const PortfolioStatisticsOverview(
              trading: true, predictions: false));
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      // Nothing open to chart (founder, 28 October 2026): no plot, no
      // axis, no range pills.
      expect(find.byType(KuteLineChart), findsNothing);
      expect(find.byType(KuteRangePills), findsNothing);
      expect(
          find.byKey(const ValueKey('statistics-chart-empty')), findsNothing);
      // The lead row stays (the ring, the chart's figure, the pair); no
      // second total, no venue rows under it.
      expect(find.byKey(const ValueKey('statistics-pnl-lead')), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-active')), findsOneWidget);
      expect(find.text('Open P&L'), findsNothing);
      expect(find.byKey(const ValueKey('pnl-venue-investing')), findsNothing);
      expectEmptyState(tester, 'No open investments',
          compact: true, inBlock: true);
    });

    testWidgets('Historic with nothing ever closed: the same compact state',
        (tester) async {
      await _pump(tester, predictions: true, noPredictions: true);
      expect(find.byKey(const ValueKey('statistics-empty')), findsOneWidget);
      expect(find.text('Realized P&L'), findsNothing);
      expect(find.text('Amount predicted'), findsNothing);
      expectEmptyState(tester, 'No predictions yet', compact: true);
    });

    for (final scope in StatisticsScope.values) {
      testWidgets(
          'never traded (${scope.name}): one empty state for the page, no '
          'pills, nothing stacked', (tester) async {
        await _pump(tester, empty: true, scope: scope);
        expect(find.byKey(const ValueKey('statistics-chart-empty')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('statistics-empty')), findsNothing);
        expect(find.byType(KutePill), findsNothing);
        expectEmptyState(tester, 'No predictions yet', compact: false);
      });
    }

    testWidgets(
        'the spending account never traded: one empty state for the page',
        (tester) async {
      await _pump(tester,
          empty: true,
          scope: StatisticsScope.active,
          home: const PortfolioStatisticsOverview(
              trading: false, predictions: true));
      expect(
          find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-empty')), findsNothing);
      expect(find.byType(KutePill), findsNothing);
      expect(find.byType(PortfolioCategoryCard), findsNothing);
      expectEmptyState(tester, 'No predictions yet', compact: false);
    });
  });

  group('Drill-down', () {
    /// The opened slice's items, top to bottom.
    List<String> items(WidgetTester tester) {
      final found = find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>)
                  .value
                  .startsWith('category-drill-item-'))
          .evaluate()
          .toList()
        ..sort((a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
      return [
        for (final e in found)
          (e.widget.key as ValueKey<String>)
              .value
              .substring('category-drill-item-'.length)
      ];
    }

    List<String> texts(WidgetTester tester, String key) => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();

    Color? colorOf(WidgetTester tester, String key, String text) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.text(text)))
        .style
        ?.color;

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Predictions Active: a slice opens to its events, largest first; '
        'an event to its positions with their open P&L', (tester) async {
      await _pump(tester,
          predictions: true, drill: true, scope: StatisticsScope.active);
      await tapKey(tester, 'category-legend-crypto');
      expect(_ring(tester).selectedId, 'crypto');
      // The legend gives way to the category and the All pill.
      expect(
          find.byKey(const ValueKey('category-legend-crypto')), findsNothing);
      expect(find.byKey(const ValueKey('category-drill-back')), findsOneWidget);
      expect(items(tester), ['btc-100k', 'btc-150k']);
      expect(texts(tester, 'category-drill-item-btc-100k'),
          containsAllInOrder(['Bitcoin above 100k?', '97%', r'$34.00']));
      expect(texts(tester, 'category-drill-item-btc-150k'),
          containsAllInOrder(['Bitcoin 150k this year?', '3%', r'$1.00']));
      expect(
          find.byKey(const ValueKey('category-drill-line-live')), findsNothing);

      await tapKey(tester, 'category-drill-item-btc-100k');
      expect(texts(tester, 'category-drill-line-live'), [
        'Bitcoin above 100k?',
        'Yes · 40 shares at 50¢',
        r'$30.00',
        r'+$10.00 (+50.0%)',
      ]);
      expect(colorOf(tester, 'category-drill-line-live', r'+$10.00 (+50.0%)'),
          AppColors.marketUp);
      expect(texts(tester, 'category-drill-line-live-c'),
          containsAllInOrder([r'$4.00', r'−$1.00 (−20.0%)']));
      expect(colorOf(tester, 'category-drill-line-live-c', r'−$1.00 (−20.0%)'),
          AppColors.marketDown);
      // One item open at a time.
      await tapKey(tester, 'category-drill-item-btc-150k');
      expect(
          find.byKey(const ValueKey('category-drill-line-live')), findsNothing);
      expect(find.byKey(const ValueKey('category-drill-line-live-b')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Predictions Historic: events by amount predicted; positions with '
        'what they realised, won, lost or open', (tester) async {
      await _pump(tester, predictions: true, drill: true);
      await tapKey(tester, 'category-legend-crypto');
      expect(items(tester), ['btc-100k', 'btc-150k']);
      expect(texts(tester, 'category-drill-item-btc-100k'),
          containsAllInOrder(['83%', r'$25.00']));
      expect(texts(tester, 'category-drill-item-btc-150k'),
          containsAllInOrder(['17%', r'$5.00']));
      await tapKey(tester, 'category-drill-item-btc-150k');
      expect(texts(tester, 'category-drill-line-lost-b'), [
        'Bitcoin 150k this year?',
        'Lost · No · 10 shares at 30¢',
        r'−$3.00',
        r'$3.00',
      ]);
      expect(colorOf(tester, 'category-drill-line-lost-b', r'−$3.00'),
          AppColors.marketDown);
      expect(texts(tester, 'category-drill-line-live-b').first,
          'Bitcoin 150k this year?');
      expect(
          texts(tester, 'category-drill-line-live-b')[1], startsWith('Open'));

      // Another slice: the won prediction.
      await tapKey(tester, 'category-drill-back');
      await tapKey(tester, 'category-legend-sports');
      expect(items(tester), ['nba-champion']);
      await tapKey(tester, 'category-drill-item-nba-champion');
      expect(texts(tester, 'category-drill-line-won'),
          containsAllInOrder(['Won · Yes · 20 shares at 40¢', r'+$12.00']));
      expect(colorOf(tester, 'category-drill-line-won', r'+$12.00'),
          AppColors.marketUp);
    });

    testWidgets(
        'Investing Active: coins by what closing gives back; a coin opens '
        'to its position with side, size, entry and open P&L', (tester) async {
      await _pump(tester, trading: true, scope: StatisticsScope.active);
      await tapKey(tester, 'category-legend-crypto');
      expect(items(tester), ['BTC', 'SOL']);
      expect(texts(tester, 'category-drill-item-BTC'),
          containsAllInOrder(['BTC', '88%', r'$57.50']));
      await tapKey(tester, 'category-drill-item-BTC');
      expect(texts(tester, 'category-drill-line-perp-BTC'), [
        'Long 1x',
        r'Size 0.1 · Entry $60,000',
        r'$57.50',
        r'+$7.50 (+15.0%)',
      ]);
      expect(
          colorOf(tester, 'category-drill-line-perp-BTC', r'+$7.50 (+15.0%)'),
          AppColors.marketUp);
      await tapKey(tester, 'category-drill-item-SOL');
      expect(texts(tester, 'category-drill-line-perp-SOL'),
          containsAllInOrder(['Short 1x', r'$7.50', r'−$2.50 (−25.0%)']));
      expect(
          colorOf(tester, 'category-drill-line-perp-SOL', r'−$2.50 (−25.0%)'),
          AppColors.marketDown);
    });

    testWidgets(
        'Investing Historic: coins by volume traded; a coin opens to its '
        'round trips net of fees', (tester) async {
      await _pump(tester, trading: true);
      await tapKey(tester, 'category-legend-crypto');
      expect(items(tester), ['BTC', 'ETH']);
      expect(texts(tester, 'category-drill-item-ETH'),
          containsAllInOrder(['ETH', '3%', r'$210.00']));
      await tapKey(tester, 'category-drill-item-ETH');
      final eth = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>)
              .value
              .startsWith('category-drill-line-ETH'));
      expect(eth, findsOneWidget);
      final ethTexts = tester
          .widgetList<Text>(
              find.descendant(of: eth, matching: find.byType(Text)))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .toList();
      // Bought 1 at 100, sold at 110: +10 on 1 of fees.
      expect(ethTexts.first, 'Long');
      expect(ethTexts, containsAllInOrder([r'+$9.00', r'$210.00']));
      await tapKey(tester, 'category-drill-item-BTC');
      final btc = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>)
              .value
              .startsWith('category-drill-line-BTC'));
      final btcTexts = tester
          .widgetList<Text>(
              find.descendant(of: btc, matching: find.byType(Text)))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .toList();
      // Still open: only its opening fee so far.
      expect(btcTexts[1], startsWith('Open · '));
      expect(btcTexts, contains(r'−$1.00'));
    });

    testWidgets('hidden balances mask the items and the lines', (tester) async {
      await _pump(tester,
          predictions: true,
          drill: true,
          hidden: true,
          scope: StatisticsScope.active);
      await tapKey(tester, 'category-legend-crypto');
      await tapKey(tester, 'category-drill-item-btc-100k');
      final shown = [
        ...texts(tester, 'category-drill-item-btc-100k'),
        ...texts(tester, 'category-drill-line-live'),
      ];
      expect(shown, containsAll(['••%', '••••••']));
      expect(
          shown.any((t) => t.contains(r'$') || t.contains('shares')), isFalse);
      // The P&L is masked and takes no up / down colour.
      final masked = tester.widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('category-drill-line-live')),
          matching: find.text('••••••')));
      expect(masked.length, 2);
      expect(masked.map((t) => t.style?.color),
          everyElement(isNot(AppColors.marketUp)));
    });

    testWidgets('an item and a line opened report their level', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pump(tester, trading: true, scope: StatisticsScope.active);
      await tapKey(tester, 'category-legend-crypto');
      await tester.pump(const Duration(milliseconds: 700));
      await tapKey(tester, 'category-drill-item-SOL');
      final picked = events
          .where((e) => e.$1 == 'portfolio_category_slice_selected')
          .map((e) => e.$2)
          .toList();
      expect(picked.length, 2);
      expect(picked.first!['drill_level'], 1);
      expect(picked.last, {
        'venue': 'trading',
        'slice_rank': 1,
        'category_kind': 'category',
        'category': 'crypto',
        'wallet_kind': 'hot',
        'scope': 'active',
        'drill_level': 2,
        'item_rank': 2,
      });
    });

    testWidgets('a line opens the position screen', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final pushed = <String?>[];
      await _pump(tester,
          trading: true,
          scope: StatisticsScope.active,
          observers: [
            _RouteNames(pushed)
          ],
          // The position screen's live feeds stay closed.
          overrides: [
            hyperliquidTradingProvider.overrideWith(_Trading.new),
            hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
            hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
          ]);
      await tapKey(tester, 'category-legend-crypto');
      await tapKey(tester, 'category-drill-item-BTC');
      pushed.clear();
      await tester
          .tap(find.byKey(const ValueKey('category-drill-line-perp-BTC')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pushed, ['hyperliquid-position-detail-sheet']);
      expect(find.byType(HlPositionDetailSheet), findsOneWidget);
      expect(
          events
              .where((e) => e.$1 == 'portfolio_category_slice_selected')
              .last
              .$2,
          containsPair('drill_level', 3));
      expect(
          events
              .where((e) => e.$1 == 'portfolio_category_slice_selected')
              .last
              .$2,
          containsPair('line_kind', 'perp'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the opened slice fits accessibility text', (tester) async {
      await _pump(tester,
          predictions: true,
          drill: true,
          textScale: 2,
          scope: StatisticsScope.active);
      await tapKey(tester, 'category-legend-crypto');
      await tapKey(tester, 'category-drill-item-btc-100k');
      expect(tester.takeException(), isNull);
    });
  });

  group('Overview (P&L charts, the Portfolio screen)', () {
    late List<(String, Map<String, Object>?)> events;
    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    Future<void> pumpOverview(WidgetTester tester,
            {bool trading = true,
            bool predictions = true,
            bool reduceMotion = false,
            bool flat = false,
            bool noOpen = false,
            bool hidden = false,
            bool settle = true,
            Override? displayAccount,
            double textScale = 1,
            Size size = const Size(390, 844)}) =>
        _pump(tester,
            predictions: true,
            flat: flat,
            noOpen: noOpen,
            settle: settle,
            displayAccount: displayAccount,
            hidden: hidden,
            scope: StatisticsScope.active,
            reduceMotion: reduceMotion,
            textScale: textScale,
            size: size,
            home: PortfolioStatisticsOverview(
                trading: trading, predictions: predictions));

    final figures = find.byKey(const ValueKey('statistics-figures'));
    final lead = find.byKey(const ValueKey('statistics-pnl-lead'));
    final ring = find.byKey(const ValueKey('statistics-allocation-ring'));
    Finder venueRow(String venue) => find.byKey(ValueKey('pnl-venue-$venue'));

    BalancesLiveFigure live(WidgetTester tester, String key) =>
        tester.widget<BalancesLiveFigure>(find.byKey(ValueKey(key)));
    String rolling(WidgetTester tester, String key) =>
        live(tester, key).figure.text;
    String venueAmount(WidgetTester tester, String venue) =>
        rolling(tester, 'pnl-venue-$venue-amount');
    String venuePnl(WidgetTester tester, String venue) => tester
        .widget<RollingFigure>(find.byKey(ValueKey('pnl-venue-$venue-pnl')))
        .text;
    String venueCount(WidgetTester tester, String venue) => tester
        .widget<Text>(find.byKey(ValueKey('pnl-venue-$venue-count')))
        .data!;
    String stat(WidgetTester tester, String venue) => tester
        .widget<BalancesEndFigure>(
            find.byKey(ValueKey('pnl-venue-$venue-stat-amount')))
        .figure
        .text;

    String headline(WidgetTester tester) => tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .text;

    Future<void> open(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    void expectOneOfEach(WidgetTester tester) {
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      expect(find.byType(KuteLineChart), findsOneWidget);
      // The range row under the plot (1W to ALL).
      expect(find.byType(KuteRangePills), findsOneWidget);
      expect(find.text('Profit and loss'), findsOneWidget);
      // The bare ring, the lead row, the pair, the venue rows: all in the
      // one card.
      for (final f in [
        ring,
        lead,
        find.byKey(const ValueKey('statistics-active')),
        figures,
      ]) {
        expect(find.descendant(of: _chartCard, matching: f), findsOneWidget);
      }
      // One total (the chart's figure): no All · Investing · Predictions
      // control, no Open P&L or Realized P&L lead.
      expect(find.byKey(const ValueKey('statistics-venue-all')), findsNothing);
      expect(find.text('All'), findsNothing);
      expect(find.text('Open P&L'), findsNothing);
      expect(find.text('Realized P&L'), findsNothing);
      expect(find.byKey(const ValueKey('statistics-pnl-lead-amount')),
          findsNothing);
      // The old donut card, its legend and the stat tiles are gone.
      expect(find.byType(PortfolioCategoryCard, skipOffstage: false),
          findsNothing);
      expect(find.byType(PortfolioTile, skipOffstage: false), findsNothing);
      expect(find.byType(PortfolioTileRow, skipOffstage: false), findsNothing);
      expect(find.textContaining('%', skipOffstage: false),
          findsNWidgets(2)); // the venue headers' P&L only
      expect(find.text('Orders', skipOffstage: false), findsNothing);
      expect(find.text('Total', skipOffstage: false), findsNothing);
    }

    testWidgets(
        'the venue rows are the chart\'s filter: a row tapped draws that '
        'venue alone (figure, change line, chart), the row selected and the '
        'other dimmed; tapped again All; the same event', (tester) async {
      await pumpOverview(tester);
      expectOneOfEach(tester);
      final all = headline(tester);
      Finder pick(String venue) =>
          find.byKey(ValueKey('pnl-venue-$venue-pick'));
      double opacity(String venue) => tester
          .widget<AnimatedOpacity>(find
              .descendant(
                  of: pick(venue), matching: find.byType(AnimatedOpacity))
              .first)
          .opacity;
      Finder selected(String venue, bool on) =>
          find.byKey(ValueKey('pnl-venue-$venue-selected-$on'));
      // All to start: neither row picked, neither dimmed.
      expect(selected('investing', false), findsOneWidget);
      expect(selected('predictions', false), findsOneWidget);
      expect(opacity('investing'), 1);
      expect(opacity('predictions'), 1);

      await tester.tap(pick('investing'));
      await tester.pumpAndSettle();
      expect(headline(tester), r'+$15.00');
      expect(find.byType(KuteLineChart), findsOneWidget);
      // The line is Investing's alone, ending on its P&L now.
      expect(
          tester.widget<KuteLineChart>(find.byType(KuteLineChart)).values.last,
          15);
      expect(selected('investing', true), findsOneWidget);
      expect(
          tester
              .widget<AnimatedContainer>(selected('investing', true))
              .decoration,
          BoxDecoration(
              color: AppColorsExtension.light().surfaceElevated,
              borderRadius: BorderRadius.circular(8.r)));
      expect(opacity('investing'), 1);
      expect(opacity('predictions'), lessThan(1));
      expect(opacity('predictions'), greaterThan(0.4));
      expect(events.where((e) => e.$1 == 'portfolio_performance_range_changed'),
          isEmpty);

      // The other row: straight to Predictions.
      await tester.tap(pick('predictions'));
      await tester.pumpAndSettle();
      expect(selected('predictions', true), findsOneWidget);
      expect(selected('investing', false), findsOneWidget);
      expect(opacity('investing'), lessThan(1));

      // The picked row again: All.
      await tester.tap(pick('predictions'));
      await tester.pumpAndSettle();
      expect(headline(tester), all);
      expect(selected('predictions', false), findsOneWidget);
      expect(opacity('investing'), 1);
      expect(
          events
              .where((e) => e.$1 == 'portfolio_statistics_venue_toggled')
              .map((e) => e.$2),
          [
            {'venue': 'hyperliquid'},
            {'venue': 'polymarket'},
            {'venue': 'all'}
          ]);
      expectOneOfEach(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'top down, one card: the ring, the figure and the pair on one row, '
        'a hairline, Predictions then Investing, a hairline, the chart, the '
        'ranges', (tester) async {
      await pumpOverview(tester);
      double top(Finder f) => tester.getTopLeft(f).dy;
      final pair = find.byKey(const ValueKey('statistics-active'));
      // One row: the ring on the left, the caption, figure and change line
      // beside it, the pair at the row's end, all overlapping in height.
      final ringRect = tester.getRect(ring);
      final leadRect = tester.getRect(lead);
      final pairRect = tester.getRect(pair);
      expect(ringRect.right, lessThan(leadRect.left));
      expect(leadRect.right, lessThanOrEqualTo(pairRect.left));
      expect(pairRect.right, lessThanOrEqualTo(390));
      expect(ringRect.top, lessThan(leadRect.bottom));
      expect(leadRect.top, lessThan(ringRect.bottom));
      expect(pairRect.top, lessThan(ringRect.bottom));
      expect(pairRect.bottom, greaterThan(ringRect.top));
      expect(
          find.descendant(
              of: lead,
              matching: find.byKey(const ValueKey('statistics-pnl-headline'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: lead,
              matching: find.byKey(const ValueKey('statistics-pnl-header'))),
          findsOneWidget);
      // A hairline under the row, the venue rows, a hairline, the plot.
      final hairlines = find.descendant(
          of: find.byType(KuteLineChart), matching: find.byType(Divider));
      expect(hairlines, findsNWidgets(2));
      expect(top(hairlines.first), greaterThan(ringRect.bottom));
      expect(top(venueRow('predictions')), greaterThan(top(hairlines.first)));
      expect(top(venueRow('investing')),
          greaterThan(top(venueRow('predictions'))));
      expect(top(hairlines.last),
          greaterThan(tester.getBottomLeft(venueRow('investing')).dy));
      final plot = find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_KuteLinePainter');
      expect(top(plot), greaterThan(top(hairlines.last)));
      expect(top(find.byType(KuteRangePills)),
          greaterThan(tester.getBottomLeft(plot).dy));
      // Under each venue its one quiet sub-row, indented past the dot.
      final stat = find.byKey(const ValueKey('pnl-venue-predictions-stat'));
      expect(top(stat), greaterThan(top(venueRow('predictions'))));
      expect(top(stat), lessThan(top(venueRow('investing'))));
      expect(
          tester
              .getTopLeft(find.descendant(
                  of: stat, matching: find.text('Amount at stake')))
              .dx,
          greaterThan(tester
                  .getTopLeft(find.descendant(
                      of: venueRow('predictions'),
                      matching: find.text('Predictions')))
                  .dx -
              0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the ring is bare: each venue\'s share of what is at stake in its '
        'colour, nothing written in it, not a control', (tester) async {
      await pumpOverview(tester);
      // Predictions 20 of 80 at stake, Investing 60.
      final painter = _ring(tester);
      final arcs = {for (final a in painter.arcs) a.id: a};
      expect(arcs.keys,
          {BalancesCategory.predictions, BalancesCategory.investing});
      expect(arcs[BalancesCategory.predictions]!.fraction, closeTo(0.25, 1e-9));
      expect(arcs[BalancesCategory.investing]!.fraction, closeTo(0.75, 1e-9));
      final c = AppColorsExtension.light();
      expect(arcs[BalancesCategory.predictions]!.color,
          balancesCategoryColor(c, BalancesCategory.predictions));
      expect(arcs[BalancesCategory.investing]!.color,
          balancesCategoryColor(c, BalancesCategory.investing));
      expect(
          find.descendant(of: ring, matching: find.byType(Text)), findsNothing);
      expect(
          find.descendant(of: ring, matching: find.byType(RollingNumberText)),
          findsNothing);
      expect(tester.widget<KuteDonutChart>(ring).diameter,
          closeTo(kBalancesRingDiameter * 390 / 430, 0.01));
      expect(find.ancestor(of: ring, matching: find.byType(IgnorePointer)),
          findsWidgets);
      // The venues' dots wear the same colours.
      expect(
          tester
              .widget<Container>(find
                  .descendant(
                      of: venueRow('predictions'),
                      matching: find.byType(Container))
                  .first)
              .decoration,
          BoxDecoration(
              color: balancesCategoryColor(c, BalancesCategory.predictions),
              shape: BoxShape.circle));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Active: the chart\'s figure is the one total; each venue row with '
        'its count, value and P&L; Amount at stake under it', (tester) async {
      await pumpOverview(tester);
      expect(find.text('Open P&L'), findsNothing);
      expect(find.byKey(const ValueKey('statistics-pnl-lead-amount')),
          findsNothing);
      // Predictions: one live position worth 30 (20 put in, +10).
      expect(venueCount(tester, 'predictions'), '1');
      expect(venueAmount(tester, 'predictions'), r'$30.00');
      expect(venuePnl(tester, 'predictions'), r'+$10.00 (50.0%)');
      expect(stat(tester, 'predictions'), r'$20.00');
      // Investing: BTC and SOL, 60 of margin, +5.
      expect(venueCount(tester, 'investing'), '2');
      expect(venueAmount(tester, 'investing'), r'$65.00');
      expect(venuePnl(tester, 'investing'), r'+$5.00 (8.3%)');
      expect(stat(tester, 'investing'), r'$60.00');
      expect(find.text('Amount at stake'), findsNWidgets(2));
      // Nothing said twice: no "Open positions" line, no tiles, no legend
      // percentages, no second Open P&L.
      expect(find.text('Open positions'), findsNothing);
      expect(find.text('Open P&L'), findsNothing);
      expect(find.byType(PortfolioTile), findsNothing);
      expect(
          find.byKey(const ValueKey('category-legend-crypto')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Historic: the pair switches the figures; each venue\'s realised P&L '
        'at its row\'s end, the amount predicted or volume traded under it, '
        'no second total; the same ring morphs; the event is sent',
        (tester) async {
      await pumpOverview(tester);
      final ringState = tester.state(find.byType(KuteDonutChart));
      await open(tester, find.byKey(const ValueKey('statistics-historic')));
      expect(
          events
              .where((e) => e.$1 == 'portfolio_allocation_view_changed')
              .map((e) => e.$2),
          [
            {'view': 'historic'}
          ]);
      // The old sub-tab event is the Ledger's alone now.
      expect(events.where((e) => e.$1 == 'portfolio_tab_changed'), isEmpty);
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      expect(tester.state(find.byType(KuteDonutChart)), same(ringState));
      expect(find.text('Realized P&L'), findsNothing);
      expect(find.text('Open P&L'), findsNothing);
      // 6 realised at Predictions, 8 at Investing (10 gross on 2 of fees).
      expect(venueCount(tester, 'predictions'), '3');
      expect(venueAmount(tester, 'predictions'), r'+$6.00');
      expect(live(tester, 'pnl-venue-predictions-amount').style.color,
          AppColors.marketUp);
      expect(find.byKey(const ValueKey('pnl-venue-predictions-pnl')),
          findsNothing);
      expect(stat(tester, 'predictions'), r'$33.00');
      expect(find.text('Amount predicted'), findsOneWidget);
      expect(venueCount(tester, 'investing'), '3');
      expect(venueAmount(tester, 'investing'), r'+$8.00');
      expect(stat(tester, 'investing'), r'$6,210.00');
      expect(find.text('Volume traded'), findsOneWidget);
      expect(find.text('Amount at stake'), findsNothing);
      expect(find.text('Trades'), findsNothing);
      // The ring: 33 of 6,243 predicted, the rest traded.
      final arcs = {for (final a in _ring(tester).arcs) a.id: a};
      expect(arcs[BalancesCategory.predictions]!.fraction,
          closeTo(33 / 6243, 1e-6));
      expect(arcs[BalancesCategory.investing]!.fraction,
          closeTo(6210 / 6243, 1e-6));

      // Back to Active: the figures and the ring come back.
      await open(tester, find.byKey(const ValueKey('statistics-active')));
      expect(venueAmount(tester, 'predictions'), r'$30.00');
      expect(_ring(tester).arcs.map((a) => a.fraction), [0.25, 0.75]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'nothing held now and nothing resting: the lead row, then the '
        'compact empty state, no venue rows; Historic still draws',
        (tester) async {
      await pumpOverview(tester, flat: true, predictions: false);
      expect(find.byKey(const ValueKey('statistics-empty')), findsOneWidget);
      expect(figures, findsNothing);
      expect(venueRow('investing'), findsNothing);
      expect(lead, findsOneWidget);
      expect(find.text('No open investments'), findsOneWidget);
      // Nothing open: no chart on Active.
      expect(find.byType(KuteLineChart), findsNothing);
      // Only the track: no slice while nothing is at stake.
      expect(_ring(tester).arcs, isEmpty);
      await open(tester, find.byKey(const ValueKey('statistics-historic')));
      expect(find.byKey(const ValueKey('statistics-empty')), findsNothing);
      expect(find.byType(KuteLineChart), findsOneWidget);
      expect(venueCount(tester, 'investing'), '3');
      expect(stat(tester, 'investing'), r'$6,210.00');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'one venue with nothing on the sub-tab: its row reads "No open '
        'positions" at the end and lists nothing', (tester) async {
      await pumpOverview(tester, flat: true);
      // Predictions has a live position; Investing holds nothing.
      expect(figures, findsOneWidget);
      expect(venueAmount(tester, 'predictions'), r'$30.00');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('pnl-venue-investing-line')))
              .data,
          'No open positions');
      expect(find.byKey(const ValueKey('pnl-venue-investing-amount')),
          findsNothing);
      expect(find.byKey(const ValueKey('pnl-venue-investing-count')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('pnl-venue-investing-stat')), findsNothing);
      expect(find.byKey(const ValueKey('statistics-empty')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Founder, 28 October 2026: "if on P&L no active predictions maybe
    // don't show the graph".
    group('Active with nothing open: no chart', () {
      final chart = find.byType(KuteLineChart);
      final ranges = find.byKey(const ValueKey('statistics-pnl-ranges'));
      final skeleton =
          find.byKey(const ValueKey('portfolio-performance-loading'));

      testWidgets(
          'nothing open at either venue: no plot, axis or range pills; the '
          'lead row and both venue rows stay; Historic charts', (tester) async {
        await pumpOverview(tester, flat: true, noOpen: true);
        expect(_chartCard, findsOneWidget);
        expect(chart, findsNothing);
        expect(ranges, findsNothing);
        expect(find.byType(KuteRangePills), findsNothing);
        expect(find.descendant(of: _chartCard, matching: lead), findsOneWidget);
        expect(headline(tester), isNotEmpty);
        // Both rows, each with its quiet line, still pick the series.
        for (final venue in ['predictions', 'investing']) {
          expect(
              tester
                  .widget<Text>(find.byKey(ValueKey('pnl-venue-$venue-line')))
                  .data,
              'No open positions');
          expect(find.byKey(ValueKey('pnl-venue-$venue-pick')), findsOneWidget);
        }
        await open(tester, find.byKey(const ValueKey('statistics-historic')));
        expect(chart, findsOneWidget);
        expect(ranges, findsOneWidget);
        // Back to Active: hidden again.
        await open(tester, find.byKey(const ValueKey('statistics-active')));
        expect(chart, findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'All with one venue open charts All; the venue picked with '
          'nothing open hides it, picked again (All) it is back',
          (tester) async {
        await pumpOverview(tester, flat: true);
        // Predictions open, Investing not: All is charted.
        expect(chart, findsOneWidget);
        expect(ranges, findsOneWidget);
        await open(
            tester, find.byKey(const ValueKey('pnl-venue-investing-pick')));
        expect(chart, findsNothing);
        expect(ranges, findsNothing);
        // The rows stay: the other venue is a tap away.
        expect(find.byKey(const ValueKey('pnl-venue-predictions-pick')),
            findsOneWidget);
        await open(
            tester, find.byKey(const ValueKey('pnl-venue-predictions-pick')));
        expect(chart, findsOneWidget);
        await open(
            tester, find.byKey(const ValueKey('pnl-venue-predictions-pick')));
        expect(chart, findsOneWidget); // All again
        // Investing picked on Historic: charted (Historic always is).
        await open(
            tester, find.byKey(const ValueKey('pnl-venue-investing-pick')));
        expect(chart, findsNothing);
        await open(tester, find.byKey(const ValueKey('statistics-historic')));
        expect(chart, findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'the first load: the card\'s skeleton until Investing\'s positions '
          'answer, never the chart then nothing; a reload keeps the card',
          (tester) async {
        final account = StateProvider<AsyncValue<HlAccountSnapshot>>(
            (_) => const AsyncLoading());
        await pumpOverview(tester,
            flat: true,
            noOpen: true,
            settle: false,
            displayAccount: hyperliquidDisplayAccountProvider
                .overrideWith((ref) => ref.watch(account)));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(skeleton, findsOneWidget);
          expect(_chartCard, findsNothing);
          expect(chart, findsNothing);
        }
        final c = ProviderScope.containerOf(
            tester.element(find.byType(PortfolioStatisticsOverview)));
        c.read(account.notifier).state = AsyncData(_flat());
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(skeleton, findsNothing);
          expect(_chartCard, findsOneWidget);
          expect(chart, findsNothing);
        }
        // A reload (the last snapshot kept): no skeleton, nothing moves.
        c.read(account.notifier).state = const AsyncLoading<HlAccountSnapshot>()
            .copyWithPrevious(AsyncData(_flat()));
        await tester.pump();
        expect(skeleton, findsNothing);
        expect(_chartCard, findsOneWidget);
        expect(chart, findsNothing);
        // A read that failed with nothing before it: decided, not loading
        // for good.
        c.read(account.notifier).state = AsyncError<HlAccountSnapshot>(
            Exception('offline'), StackTrace.empty);
        await tester.pump();
        expect(skeleton, findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('one venue: its row alone, picking nothing', (tester) async {
      await pumpOverview(tester, trading: false);
      expect(find.byKey(const ValueKey('statistics-venue-all')), findsNothing);
      expect(venueRow('predictions'), findsOneWidget);
      expect(venueRow('investing'), findsNothing);
      expect(find.byKey(const ValueKey('pnl-venue-predictions-pick')),
          findsNothing);
      expect(venueCount(tester, 'predictions'), '1');
      expect(_ring(tester).arcs.map((a) => a.fraction), [1.0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden balances mask the amounts, not the counts',
        (tester) async {
      await pumpOverview(tester, hidden: true);
      expect(headline(tester), '••••••');
      expect(venueAmount(tester, 'predictions'), '••••••');
      expect(stat(tester, 'investing'), '••••••');
      expect(find.byKey(const ValueKey('pnl-venue-predictions-pnl')),
          findsNothing);
      expect(venueCount(tester, 'investing'), '2');
      expect(find.textContaining(r'$'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the ring morphs between Active and Historic; at once under Reduce '
        'Motion', (tester) async {
      final pill = find.byKey(const ValueKey('statistics-historic'));
      await pumpOverview(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(_ring(tester).arcs.map((a) => a.id),
          [BalancesCategory.predictions, BalancesCategory.investing]);
      expect(_ring(tester).arcs.first.fraction, closeTo(33 / 6243, 1e-6));

      await tester.pumpWidget(const SizedBox());
      await pumpOverview(tester, reduceMotion: true);
      await tester.tap(pill);
      await tester.pump();
      await tester.pump();
      expect(_ring(tester).arcs.first.fraction, closeTo(33 / 6243, 1e-6));
    });

    testWidgets('a footer runs under the figures', (tester) async {
      await _pump(tester,
          predictions: true,
          scope: StatisticsScope.active,
          home: const PortfolioStatisticsOverview(
              trading: true,
              predictions: true,
              footerEmpty: false,
              footer: [
                SliverToBoxAdapter(
                    child: SizedBox(
                        key: ValueKey('footer'), height: 40, width: 10)),
              ]));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('footer')), 200,
          scrollable: find
              .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('footer'))).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(figures).dy - 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits accessibility text', (tester) async {
      await pumpOverview(tester, textScale: 2);
      await open(tester, find.byKey(const ValueKey('statistics-historic')));
      expect(venueCount(tester, 'investing'), '3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('375 pt at 130 % text: the lead row fits, nothing cut',
        (tester) async {
      await pumpOverview(tester, size: const Size(375, 812), textScale: 1.3);
      final pair = find.byKey(const ValueKey('statistics-historic'));
      expect(tester.getRect(pair).right, lessThanOrEqualTo(375));
      expect(tester.getRect(ring).left, greaterThanOrEqualTo(0));
      expect(
          tester.getRect(lead).right,
          lessThanOrEqualTo(tester
              .getRect(find.byKey(const ValueKey('statistics-active')))
              .left));
      for (final label in ['Profit and loss', 'Amount at stake']) {
        for (final r in find
            .text(label)
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(375));
        }
      }
      expect(tester.takeException(), isNull);
    });
  });
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState();
}

/// Records the name of every route pushed.
class _RouteNames extends NavigatorObserver {
  _RouteNames(this.names);
  final List<String?> names;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);
}
