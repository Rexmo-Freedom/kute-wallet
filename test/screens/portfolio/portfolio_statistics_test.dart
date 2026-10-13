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
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyEventsBatchFetchProvider, polyFeedCacheLookupProvider;
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
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
    double textScale = 1,
    Widget? home}) async {
  tester.view.physicalSize = const Size(390, 844);
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
        hyperliquidPerpMarketsProvider.overrideWith((_) async => const []),
        hyperliquidSpotMarketsProvider.overrideWith((_) async => const []),
        // Gamma's tags for the three markets the predictions were on.
        polyMarketTagsFetchProvider.overrideWithValue(tagsPending
            ? (ids) => Completer<Map<String, Set<String>>>().future
            : tagsFail
                ? (ids) async => throw Exception('offline')
                : (ids) async => {
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
    // The chart card: caption, the account's P&L (6 realised + 10 open),
    // the change over the month drawn, the line, the range pills.
    expect(_chartCard, findsOneWidget);
    expect(find.byType(PortfolioPnlChart), findsOneWidget);
    expect(find.text('Profit and loss'), findsOneWidget);
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('statistics-pnl-headline')))
            .text,
        r'+$16.00');
    expect(find.text(r'+$21.00 past 1m'), findsOneWidget);
    final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
    expect(chart.lineColor, AppColors.marketUp);
    // From the P&L the account had a month ago (−5, forty days in) through
    // the venue's points to now.
    expect(chart.values, [-5, 9, 15, 16]);
    // The account is forty days old: the ranges reaching back past its
    // first point would draw ALL again, so they are not offered.
    for (final pill in ['1D', '1W', '1M', 'ALL']) {
      expect(find.text(pill), findsOneWidget);
    }
    for (final pill in ['3M', 'YTD', '1Y']) {
      expect(find.text(pill), findsNothing);
    }
    // No fill under the line; it moves, so the dashed baseline is drawn.
    expect(chart.showFill, isFalse);
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is PnlBaselinePainter),
        findsOneWidget);
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

    bool baselineDrawn() => find
        .byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is PnlBaselinePainter)
        .evaluate()
        .isNotEmpty;

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
        'a range the line does not move over: the line, no dashed '
        'baseline', (tester) async {
      // Five dollars made two months ago, nothing since: the month drawn
      // is flat.
      await _pump(tester, series: series([(60, 5), (40, 5), (1, 5)]));
      expect(find.byType(KuteLineChart), findsOneWidget);
      expect(tester.widget<KuteLineChart>(find.byType(KuteLineChart)).values,
          [5, 5]);
      expect(baselineDrawn(), isFalse);
      // All time it moved (from zero): the baseline is back.
      await tester.tap(find.text('ALL'));
      await tester.pumpAndSettle();
      expect(baselineDrawn(), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a young account opens on ALL; the ranges that would draw it again '
        'are not offered', (tester) async {
      await _pump(tester, series: series([(10, 2), (1, 5)]));
      final chart = find.byType(KuteLineChart);
      expect(chart, findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-pnl-chart-all')),
          findsOneWidget);
      for (final pill in ['1D', '1W', 'ALL']) {
        expect(find.text(pill), findsOneWidget);
      }
      for (final pill in ['1M', '3M', 'YTD', '1Y']) {
        expect(find.text(pill), findsNothing);
      }
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

  group('Overview (the spending account)', () {
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
            double textScale = 1}) =>
        _pump(tester,
            predictions: true,
            flat: flat,
            scope: StatisticsScope.active,
            reduceMotion: reduceMotion,
            textScale: textScale,
            home: PortfolioStatisticsOverview(
                trading: trading, predictions: predictions));

    final figures = find.byKey(const ValueKey('statistics-figures'));
    String figure(WidgetTester tester, String label) {
      final column = find.ancestor(
          of: find.descendant(of: figures, matching: find.text(label)),
          matching: find.byType(Column));
      final texts = tester
          .widgetList<Text>(
              find.descendant(of: column.first, matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      return texts[texts.indexOf(label) + 1]!;
    }

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
      expect(find.byType(KuteRangePills), findsOneWidget);
      expect(find.text('Profit and loss'), findsOneWidget);
      expect(find.byType(KuteDonutChart, skipOffstage: false), findsOneWidget);
      expect(find.byType(PortfolioCategoryCard, skipOffstage: false),
          findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-active')), findsOneWidget);
      expect(figures, findsOneWidget);
    }

    testWidgets(
        'one chart: the toggle draws each venue in it, the headline and '
        'events follow', (tester) async {
      await pumpOverview(tester);
      expectOneOfEach(tester);
      final all = headline(tester);
      await tester
          .tap(find.byKey(const ValueKey('statistics-venue-hyperliquid')));
      await tester.pumpAndSettle();
      expect(headline(tester), r'+$15.00');
      expect(find.byType(KuteLineChart), findsOneWidget);
      await tester.tap(find.text('ALL'));
      await tester.pumpAndSettle();
      expect(
          events
              .where((e) => e.$1 == 'portfolio_performance_range_changed')
              .single
              .$2?['venue'],
          'hyperliquid');
      await tester.tap(find.byKey(const ValueKey('statistics-venue-all')));
      await tester.pumpAndSettle();
      expect(headline(tester), all);
      expect(
          events
              .where((e) => e.$1 == 'portfolio_statistics_venue_toggled')
              .map((e) => e.$2),
          [
            {'venue': 'hyperliquid'},
            {'venue': 'all'}
          ]);
      expectOneOfEach(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'one donut: the venues at the top, a row opens one in the same '
        'ring and the figures follow; back returns', (tester) async {
      await pumpOverview(tester);
      final ring = tester.state(find.byType(KuteDonutChart));
      // The top level: the venues by what they hold now, the total.
      expect(_donutTexts(tester), contains('Total'));
      expect(_hole(tester), r'$95.00');
      expect(find.byKey(const ValueKey('category-legend-trading')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('category-legend-predictions')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('category-level-back')), findsNothing);
      // The account's figures: both venues added.
      expect(figure(tester, 'Open P&L'), r'+$15.00');
      expect(figure(tester, 'Amount at stake'), r'$80.00');
      expect(figure(tester, 'Open positions'), '3');

      await open(
          tester, find.byKey(const ValueKey('category-legend-predictions')));
      expect(
          events.where((e) => e.$1 == 'portfolio_allocation_drilled').last.$2,
          {'venue': 'polymarket', 'level': 'venue'});
      // The same ring, now the venue's categories.
      expect(tester.state(find.byType(KuteDonutChart)), same(ring));
      expect(_ring(tester).arcs.map((a) => a.id), ['crypto']);
      expect(
          _donutTexts(tester), containsAllInOrder(['Predictions', 'Crypto']));
      expect(_hole(tester), r'$30.00');
      expect(
          find.byKey(const ValueKey('category-legend-trading')), findsNothing);
      expect(find.byKey(const ValueKey('category-level-back')), findsOneWidget);
      // The figures are the venue's now, shown once.
      expect(figure(tester, 'Open P&L'), r'+$10.00');
      expect(figure(tester, 'Amount at stake'), r'$20.00');
      expect(figure(tester, 'Open positions'), '1');
      expectOneOfEach(tester);
      // A category opens up as on the venue's own tab, one way back at a
      // time.
      await open(tester, find.byKey(const ValueKey('category-legend-crypto')));
      expect(find.byKey(const ValueKey('category-drill-back')), findsOneWidget);
      expect(
          tester
              .widget<Visibility>(find.ancestor(
                  of: find.byKey(const ValueKey('category-level-back')),
                  matching: find.byType(Visibility)))
              .visible,
          isFalse);
      await open(tester, find.byKey(const ValueKey('category-drill-back')));

      await open(tester, find.byKey(const ValueKey('category-level-back')));
      expect(
          events.where((e) => e.$1 == 'portfolio_allocation_drilled').last.$2,
          {'venue': 'polymarket', 'level': 'top'});
      expect(tester.state(find.byType(KuteDonutChart)), same(ring));
      expect(find.byKey(const ValueKey('category-legend-trading')),
          findsOneWidget);
      expect(figure(tester, 'Open positions'), '3');

      // Investing opened from the ring itself.
      await open(tester, find.byKey(const ValueKey('category-legend-trading')));
      expect(
          events.where((e) => e.$1 == 'portfolio_allocation_drilled').last.$2,
          {'venue': 'hyperliquid', 'level': 'venue'});
      expect(_donutTexts(tester), contains('Investing'));
      expect(_hole(tester), r'$65.00');
      expect(figure(tester, 'Open positions'), '2');
      // A venue pick sends no slice event of its own; the category opened
      // inside Predictions did.
      expect(
          events
              .where((e) => e.$1 == 'portfolio_category_slice_selected')
              .map((e) => e.$2?['category']),
          ['crypto']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Historic: the figures follow the level, said once',
        (tester) async {
      await pumpOverview(tester);
      await open(tester, find.byKey(const ValueKey('statistics-historic')));
      expectOneOfEach(tester);
      expect(find.text('Realized P&L'), findsOneWidget);
      expect(find.descendant(of: figures, matching: find.text('Volume traded')),
          findsOneWidget);
      expect(find.descendant(of: figures, matching: find.text('Trades')),
          findsOneWidget);
      await open(
          tester, find.byKey(const ValueKey('category-legend-predictions')));
      expect(figure(tester, 'Realized P&L'), r'+$6.00');
      expect(
          find.descendant(of: figures, matching: find.text('Amount predicted')),
          findsOneWidget);
      expect(find.text('Realized P&L'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a venue holding nothing is listed at 0%; opened, its ring is empty '
        'and its sub-tab says so once', (tester) async {
      await pumpOverview(tester, flat: true);
      expect(_hole(tester), r'$30.00');
      expect(_donutTexts(tester), containsAllInOrder(['Investing', '0%']));
      await open(tester, find.byKey(const ValueKey('category-legend-trading')));
      expect(find.byKey(const ValueKey('category-level-back')), findsOneWidget);
      expect(_ring(tester).arcs, isEmpty);
      expect(_hole(tester), r'$0.00');
      expect(figures, findsNothing);
      expect(find.text('No open investments'), findsOneWidget);
      await open(tester, find.byKey(const ValueKey('statistics-historic')));
      expect(figure(tester, 'Trades'), '3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('one venue: the ring opens on it, no way up, no toggle',
        (tester) async {
      await pumpOverview(tester, trading: false);
      expect(find.byKey(const ValueKey('statistics-venue-all')), findsNothing);
      expect(find.byKey(const ValueKey('category-level-back')), findsNothing);
      expect(find.byKey(const ValueKey('category-legend-predictions')),
          findsNothing);
      expect(
          _donutTexts(tester), containsAllInOrder(['Predictions', 'Crypto']));
      expect(_hole(tester), r'$30.00');
      expect(figure(tester, 'Open positions'), '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ring morphs between levels; at once under Reduce Motion',
        (tester) async {
      final row = find.byKey(const ValueKey('category-legend-predictions'));
      await pumpOverview(tester);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-morph: the venues' slices on their way out.
      expect(_ring(tester).arcs.map((a) => a.id), contains('trading'));
      await tester.pumpAndSettle();
      expect(_ring(tester).arcs.map((a) => a.id), ['crypto']);

      await tester.pumpWidget(const SizedBox());
      await pumpOverview(tester, reduceMotion: true);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      expect(_ring(tester).arcs.map((a) => a.id), ['crypto']);
      expect(_ring(tester).arcs.single.fraction, 1);
    });

    testWidgets('fits accessibility text', (tester) async {
      await pumpOverview(tester, textScale: 2);
      await open(
          tester, find.byKey(const ValueKey('category-legend-predictions')));
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
