// The Portfolio screen's two sections under the pinned strip
// (investments_portfolio.dart, sharesHeader; Activity moved to the
// Bitcoin home): their empty states are ONE treatment at one place
// (portfolio_empty_state.dart), both speak one language (titles in 13 sp
// textSecondary, lists in soft cards), and P&L Charts never opens on a
// blank frame.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesCategory, kBalancesRingDimmed;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlVenueRangeChange;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioPositionRow;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalIdleDirector, SalSprite;
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

/// Nothing open anywhere, the cash read.
const _nothingOpen = OneBalanceState(
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// Predictions' P&L: nothing a month and a half ago, $7.61 now.
List<Override> _predictionsHistory() {
  final now = DateTime.now().toUtc();
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => PortfolioPerformance(
            points: [
              for (final (days, pnl) in [(45, 0.0), (20, 2.5), (2, 7.61)])
                PortfolioPnlPoint(
                    timestamp: now.subtract(Duration(days: days)),
                    pnlUsd: pnl)
            ],
            totalPnlUsd: 7.61,
            asOf: now.subtract(const Duration(days: 2)),
            sourceLabel: 'Polymarket',
            basisLabel: 'P&L',
            coverageLabel: 'All time')),
  ];
}

/// Both venues at work: Investing $10.00, Predictions $4.24.
const _bothAtWork = OneBalanceState(
  investedUsd: 14.24,
  investedByVenue: {
    OneBalanceVenue.investing: 10,
    OneBalanceVenue.predictions: 4.24,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// A month of Investing P&L that dips under zero and ends above it.
List<Override> _history() {
  final now = DateTime.now().toUtc();
  final points = [(30, 0.0), (22, -4.0), (15, -9.5), (8, 3.2), (1, 12.4)];
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => PortfolioPerformance(
            points: [
              for (final (days, pnl) in points)
                PortfolioPnlPoint(
                    timestamp: now.subtract(Duration(days: days)),
                    pnlUsd: pnl)
            ],
            totalPnlUsd: 12.4,
            asOf: now.subtract(const Duration(days: 1)),
            sourceLabel: 'Hyperliquid',
            basisLabel: 'P&L',
            coverageLabel: 'All time')),
  ];
}

Future<void> _mount(WidgetTester tester,
    {List<Override> extra = const [],
    OneBalanceState state = _nothingOpen,
    HyperliquidTradingState trading = const HyperliquidTradingState(),
    Size size = const Size(390, 844),
    bool reduceMotion = false,
    double textScale = 1}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(trading: trading),
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
      oneBalanceProvider.overrideWith((ref) => state),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
      portfolioSectionProvider.overrideWith((_) => PortfolioSection.balances),
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!),
        home: Scaffold(
          body: SafeArea(
            child: Material(
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
    ),
  ));
  await _settle(tester);
}

/// Sal never settles (he loops), so a fixed run of frames, not
/// pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pick(WidgetTester tester, PortfolioSection section) async {
  await tester
      .tap(find.byKey(ValueKey('portfolio-section-pill-${section.key}')));
}

/// Equal up to float rounding.
void _expectSameRect(Rect actual, Rect expected, String reason) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, moreOrLessEquals(e, epsilon: 0.01), reason: reason);
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'both sections empty: one empty state, Sal and the title at the '
      'same place, only the copy changes', (tester) async {
    await _mount(tester);
    final titles = {
      PortfolioSection.balances: 'No open positions',
      PortfolioSection.charts: 'No P&L yet',
    };
    final sal = <PortfolioSection, Rect>{};
    final title = <PortfolioSection, Rect>{};
    for (final section in [
      PortfolioSection.balances,
      PortfolioSection.charts,
      PortfolioSection.balances,
    ]) {
      if (section != PortfolioSection.balances || sal.isNotEmpty) {
        await _pick(tester, section);
        await _settle(tester);
      }
      expect(find.byType(PortfolioSectionEmpty), findsOneWidget,
          reason: '$section draws the sections\' one empty state');
      expect(find.byType(SalIdleDirector), findsOneWidget);
      // The hero Sal alone: no pixel Sal anywhere.
      expect(find.byType(SalSprite), findsOneWidget);
      final s = tester.getRect(find.byType(SalIdleDirector));
      final t = tester.getRect(find.text(titles[section]!));
      // Back on the first section: exactly where it was.
      if (sal[section] case final before?) {
        _expectSameRect(s, before, 'Sal back on $section');
        _expectSameRect(t, title[section]!, 'title back on $section');
      }
      sal[section] = s;
      title[section] = t;
      // The title: 22 w600.
      final text = tester.widget<Text>(find.text(titles[section]!));
      expect(text.style?.fontWeight, FontWeight.w600);
    }
    final base = sal[PortfolioSection.balances]!;
    for (final section in PortfolioSection.values) {
      _expectSameRect(sal[section]!, base, 'Sal on $section');
      final t0 = title[PortfolioSection.balances]!;
      expect(title[section]!.top, moreOrLessEquals(t0.top, epsilon: 0.01),
          reason: 'title top on $section');
      expect(
          title[section]!.height, moreOrLessEquals(t0.height, epsilon: 0.01),
          reason: 'title height on $section');
      expect(title[section]!.center.dx,
          moreOrLessEquals(title[PortfolioSection.balances]!.center.dx),
          reason: 'title centred on $section');
    }
    // The same size the P&L one had: the hero 160.
    expect(base.width, moreOrLessEquals(160.sp));
    await _unmount(tester);
  });

  testWidgets('P&L Charts, never traded: the first frame is the empty state',
      (tester) async {
    await _mount(tester);
    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    expect(find.byKey(const ValueKey('statistics-chart-empty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-performance-loading')),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets('P&L Charts with history: the first frame is the chart',
      (tester) async {
    await _mount(tester, extra: _history());
    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    expect(find.byKey(const ValueKey('statistics-pnl-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-pnl-headline')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-performance-loading')),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'the strip is Portfolio | P&L Charts in two halves; no Activity',
      (tester) async {
    await _mount(tester);
    final portfolio = find.byKey(const ValueKey('portfolio-section-pill-balances'));
    final charts = find.byKey(const ValueKey('portfolio-section-pill-charts'));
    expect(portfolio, findsOneWidget);
    expect(charts, findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-section-pill-activity')),
        findsNothing);
    expect(find.text('Activity'), findsNothing);
    expect(tester.getSize(portfolio).width,
        moreOrLessEquals(tester.getSize(charts).width, epsilon: 0.01));
    expect(PortfolioSection.forLink('activity'), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'one language: "Profit and loss" in the 13 sp textSecondary title '
      'style, no card, its top where the empty state\'s Sal starts',
      (tester) async {
    await _mount(tester);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    final salTop = tester.getTopLeft(find.byType(SalIdleDirector)).dy;
    await _unmount(tester);

    await _mount(tester, extra: _history());
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    final caption = find.byKey(const ValueKey('statistics-pnl-caption'));
    final style = tester.widget<Text>(caption).style!;
    expect(style.fontSize, moreOrLessEquals(13 * 390 / 430, epsilon: 0.01));
    expect(style.color, AppColorsExtension.light().textSecondary);
    expect(find.byKey(const ValueKey('statistics-pnl-card')), findsNothing);
    // kPortfolioSectionEmptyTop under the section's top, as the Portfolio
    // section's first title and the empty state's Sal.
    expect(tester.getTopLeft(caption).dy, moreOrLessEquals(salTop, epsilon: 1));
    await _unmount(tester);
  });

  _ringAndCardsMain();
}

/// The hero ring's slices as painted now (mid-morph included).
List<KuteDonutArc> _arcs(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('portfolio-balance-ring')),
        matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<KuteDonutPainter>()
    .first
    .arcs;

double _alphaOf(WidgetTester tester, Object id) =>
    _arcs(tester).firstWhere((a) => a.id == id).color.a;

String _centreCaption(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('portfolio-all-time-caption')))
    .data!;

String _centreAmount(WidgetTester tester) {
  final w = tester.widget(find.byKey(const ValueKey('portfolio-all-time-amount')));
  return w is Text ? w.data! : (w as dynamic).text as String;
}

Future<void> _tapVenue(WidgetTester tester, String venue) async {
  final pick = find.byKey(ValueKey('pnl-venue-$venue-pick'));
  await tester.ensureVisible(pick);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(pick);
}

void _ringAndCardsMain() {
  testWidgets(
      'the top ring adapts: a venue picked in "By venue" keeps its slice and '
      'dims the others to 30% on the settle curve, the hole reads the '
      'venue over its P&L for the range, the line under the ring what it '
      'has at work; picked again, the allocation again', (tester) async {
    await _mount(tester,
        state: _bothAtWork, extra: [..._history(), ..._predictionsHistory()]);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    final donut = tester.widget<KuteDonutChart>(
        find.byKey(const ValueKey('portfolio-balance-ring')));
    expect(donut.morphCurve, KuteMotion.settle);
    // Nothing picked: the allocation, as on Portfolio.
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'All time');
    expect(find.byKey(const ValueKey('portfolio-legend-invested')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-legend-focus')), findsNothing);

    await _tapVenue(tester, 'predictions');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-morph: on its way down, not there yet.
    final mid = _alphaOf(tester, BalancesCategory.investing);
    expect(mid, lessThan(1));
    expect(mid, greaterThan(kBalancesRingDimmed));
    await _settle(tester);
    expect(_alphaOf(tester, BalancesCategory.predictions), 1);
    expect(_alphaOf(tester, BalancesCategory.investing),
        moreOrLessEquals(kBalancesRingDimmed, epsilon: 0.01));
    expect(_alphaOf(tester, BalancesCategory.buyingPower),
        moreOrLessEquals(kBalancesRingDimmed, epsilon: 0.01));
    // The hole: the venue over its P&L for the range picked (1M).
    final data = PortfolioPerformance(
        points: [
          for (final (days, pnl) in [(45, 0.0), (20, 2.5), (2, 7.61)])
            PortfolioPnlPoint(
                timestamp:
                    DateTime.now().toUtc().subtract(Duration(days: days)),
                pnlUsd: pnl)
        ],
        totalPnlUsd: 7.61,
        sourceLabel: 'Polymarket',
        basisLabel: 'P&L',
        coverageLabel: 'All time');
    final month =
        pnlVenueRangeChange(data, BalanceRange.month, DateTime.now())!;
    expect(month, greaterThan(0));
    expect(_centreCaption(tester), 'Predictions');
    expect(_centreAmount(tester), '▲ \$${month.toStringAsFixed(2)}');
    // The line under the ring: what Predictions has at work.
    final focus = find.byKey(const ValueKey('portfolio-legend-focus'));
    expect(focus, findsOneWidget);
    expect(find.descendant(of: focus, matching: find.text('Invested in Predictions')),
        findsOneWidget);
    expect(
        find.descendant(
            of: focus,
            matching: find.byWidgetPredicate(
                (w) => w is RollingFigure && w.text == r'$4.24')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-legend-available')),
        findsNothing);

    // Picked again: All, the allocation and the all-time P&L again.
    await _tapVenue(tester, 'predictions');
    await _settle(tester);
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'All time');
    expect(find.byKey(const ValueKey('portfolio-legend-focus')), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'Reduce Motion: the slices dim at once; leaving P&L Charts shows the '
      'allocation and clears the pick', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        reduceMotion: true,
        extra: [..._history(), ..._predictionsHistory()]);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    await _tapVenue(tester, 'investing');
    await tester.pump();
    expect(_alphaOf(tester, BalancesCategory.investing), 1);
    expect(_alphaOf(tester, BalancesCategory.predictions),
        moreOrLessEquals(kBalancesRingDimmed, epsilon: 0.01));
    expect(_centreCaption(tester), 'Investing');

    await _pick(tester, PortfolioSection.balances);
    await _settle(tester);
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'All time');
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    expect(_centreCaption(tester), 'All time');
    expect(find.byKey(const ValueKey('portfolio-legend-focus')), findsNothing);
    await _unmount(tester);
  });

  for (final section in PortfolioSection.values) {
    testWidgets(
        '${section.key}: the last row scrolls clear of the bar '
        '(kuteBarScrollClearance inside the scroll), at 375 pt and 130 % '
        'text, its figures whole inside the card', (tester) async {
      const size = Size(375, 560);
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: const HyperliquidTradingState(
              isInitialized: true,
              positions: [
                HlPerpPosition(
                    coin: 'BTC',
                    szi: 0.1,
                    entryPx: 60000,
                    positionValue: 10812.37,
                    unrealizedPnl: 0.4,
                    returnOnEquity: 0.004,
                    liquidationPx: null,
                    marginUsed: 10811.97,
                    leverageType: 'isolated',
                    leverageValue: 1,
                    maxLeverage: 40),
              ]),
          extra: [
            ..._history(),
            ..._predictionsHistory(),
            // Enough rows that the Portfolio section scrolls.
            polymarketActivePositionsProvider.overrideWith((_) => [
                  for (final t in ['a', 'b', 'c'])
                    PolymarketPosition(
                        marketId: 'm-$t',
                        marketQuestion: 'Will $t happen this year?',
                        outcome: 'Yes',
                        size: 2,
                        avgPrice: 0.5,
                        currentPrice: 0.6,
                        pnl: 0,
                        pnlPercent: 0,
                        isResolved: false,
                        tokenId: t),
                ]),
          ]);
      if (section == PortfolioSection.charts) {
        await _pick(tester, section);
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
      final list = find
          .descendant(
              of: find.byKey(ValueKey('portfolio-section-${section.key}')),
              matching: find.byType(Scrollable))
          .first;
      await tester.drag(list, const Offset(0, -4000));
      await _settle(tester);
      final last = section == PortfolioSection.charts
          ? find.byKey(const ValueKey('pnl-venue-investing'))
          : find.byType(PortfolioPositionRow).last;
      expect(last, findsOneWidget);
      final bar = size.height - kuteBarScrollClearance * size.height / 932;
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(bar + 0.5),
          reason: 'the last row under the bar');
      // Everything in its card whole inside the card's 16 inset (the P&L
      // venue rows' figures at 375 pt / 130 % are checked with real
      // figures in portfolio_statistics_test.dart).
      final inset = 16 * size.width / 430;
      final card = section == PortfolioSection.charts
          ? find.byKey(const ValueKey('statistics-figures'))
          : find.byKey(const ValueKey('portfolio-balance-investing-positions'));
      final right = tester.getRect(card).right - inset + 0.5;
      final texts = find.descendant(of: card, matching: find.byType(Text));
      expect(texts, findsWidgets);
      for (final e in texts.evaluate()) {
        expect(tester.getRect(find.byWidget(e.widget)).right,
            lessThanOrEqualTo(right),
            reason: (e.widget as Text).data);
      }
      for (final key in ['portfolio-row-value', 'portfolio-row-pnl-pill']) {
        for (final e in find
            .descendant(of: card, matching: find.byKey(ValueKey(key)))
            .evaluate()) {
          expect(tester.getRect(find.byWidget(e.widget)).right,
              lessThanOrEqualTo(right),
              reason: key);
        }
      }
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }
}
