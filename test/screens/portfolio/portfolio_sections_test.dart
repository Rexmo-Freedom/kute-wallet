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
    show PortfolioCardList, PortfolioPositionRow;
import 'package:kute/screens/shared/rolling_number_text.dart';
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

/// Both venues at work: Investing $10.00, Predictions $4.24; $25.00 in
/// Dollars.
const _bothAtWork = OneBalanceState(
  dollarsUsd: 25,
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
        of: find.byKey(const ValueKey('portfolio-balance-ring'),
            skipOffstage: false),
        matching: find.byType(CustomPaint),
        skipOffstage: false))
    .map((p) => p.painter)
    .whereType<KuteDonutPainter>()
    .first
    .arcs;

double _alphaOf(WidgetTester tester, Object id) =>
    _arcs(tester).firstWhere((a) => a.id == id).color.a;

String _centreCaption(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('portfolio-all-time-caption'),
        skipOffstage: false))
    .data!;

String _centreAmount(WidgetTester tester) {
  final w = tester.widget(find.byKey(const ValueKey('portfolio-all-time-amount'),
      skipOffstage: false));
  return w is Text ? w.data! : (w as dynamic).text as String;
}

/// The Portfolio screen's one scroll (the ring, the strip, the section).
final _pageScroll = find
    .descendant(
        of: find.byKey(const ValueKey('portfolio-page-scroll')),
        matching: find.byType(Scrollable))
    .first;

/// The dot before a legend figure.
Color _legendDot(WidgetTester tester, Finder figure) {
  final dot = tester.widget<Container>(find
      .descendant(
          of: figure,
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle))
      .first);
  return (dot.decoration! as BoxDecoration).color!;
}

/// Lots to scroll: an Investing position and six predictions (open them
/// all with [_seeAll]).
List<Override> _manyRows() => [
      polymarketActivePositionsProvider.overrideWith((_) => [
            for (final t in ['a', 'b', 'c', 'd', 'e', 'f'])
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
    ];

const _btcHeld = HyperliquidTradingState(isInitialized: true, positions: [
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
]);

/// Opens the Predictions card past its first rows ("See all").
Future<void> _seeAll(WidgetTester tester) async {
  final fold =
      find.byKey(const ValueKey('portfolio-balance-predictions-see-all'));
  await tester.ensureVisible(fold);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(fold);
  await _settle(tester);
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  scroll.jumpTo(0);
  await _settle(tester);
}

Future<void> _tapVenue(WidgetTester tester, String venue) async {
  final pick = find.byKey(ValueKey('pnl-venue-$venue-pick'));
  await tester.ensureVisible(pick);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(pick);
}

void _ringAndCardsMain() {
  testWidgets(
      'P&L Charts: the ring is each venue\'s P&L over the range in its '
      'result colour, the hole the range over its P&L; a venue picked in '
      '"By venue" keeps its slice and dims the other to 30% on the settle '
      'curve, the hole reads the venue, the line what it has at work; '
      'picked again, the range again', (tester) async {
    // Tall enough that the ring and the venue rows are both on screen.
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1600),
        extra: [..._history(), ..._predictionsHistory()]);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    final donut = tester.widget<KuteDonutChart>(
        find.byKey(const ValueKey('portfolio-balance-ring')));
    expect(donut.morphCurve, KuteMotion.settle);
    // Nothing picked: both venues up over the month, green, full colour;
    // the hole the month over the account's P&L for it.
    expect(_arcs(tester).map((a) => a.id).toSet(),
        {BalancesCategory.investing, BalancesCategory.predictions});
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
      expect(a.color.withValues(alpha: 1), AppColors.marketUp,
          reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'Past month');
    expect(_centreAmount(tester), startsWith('▲ \$'));
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
    // Its dot is the venue's slice colour.
    final slice = _arcs(tester)
        .firstWhere((a) => a.id == BalancesCategory.predictions)
        .color;
    expect(_legendDot(tester, focus), slice);

    // Picked again: All, the range again.
    await _tapVenue(tester, 'predictions');
    await _settle(tester);
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'Past month');
    expect(find.byKey(const ValueKey('portfolio-legend-focus')), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'Reduce Motion: the slices dim at once; leaving P&L Charts shows the '
      'positions and clears the pick', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1600),
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
    expect(_centreCaption(tester), 'Invested');
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    expect(_centreCaption(tester), 'Past month');
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
      final list = _pageScroll;
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

  testWidgets(
      'a venue picked with no P&L over the range: no slice of its own, the '
      'other dimmed, and the dot the quiet tertiary, never a colour no '
      'slice has', (tester) async {
    final now = DateTime.now().toUtc();
    await _mount(tester, state: _bothAtWork, size: const Size(390, 1600), extra: [
      ..._history(),
      // Five dollars made two months ago, nothing since: it moved, but
      // not this month.
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.predictions))
          .overrideWith((_) async => PortfolioPerformance(
              points: [
                for (final (days, pnl) in [(60, 0.0), (45, 5.0), (1, 5.0)])
                  PortfolioPnlPoint(
                      timestamp: now.subtract(Duration(days: days)),
                      pnlUsd: pnl)
              ],
              totalPnlUsd: 5,
              sourceLabel: 'Polymarket',
              basisLabel: 'P&L',
              coverageLabel: 'All time')),
    ]);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    await _tapVenue(tester, 'predictions');
    await _settle(tester);
    expect(_arcs(tester).any((a) => a.id == BalancesCategory.predictions),
        isFalse);
    for (final a in _arcs(tester)) {
      expect(a.color.a, moreOrLessEquals(kBalancesRingDimmed, epsilon: 0.01),
          reason: '${a.id}');
    }
    final focus = find.byKey(const ValueKey('portfolio-legend-focus'));
    expect(find.descendant(of: focus, matching: find.text('Invested in Predictions')),
        findsOneWidget);
    expect(_legendDot(tester, focus), AppColorsExtension.light().textTertiary);
    await _unmount(tester);
  });

  testWidgets(
      'Portfolio: one slice per open position by its value in its palette '
      'colour (the dot on its row the same), a grey slice for Available; '
      'the hole "Invested" over what they are worth with the open P&L, the '
      'line "7 positions · Available"; a long press shows one position '
      '(its name, value and %), the others at 30%; again: cleared',
      (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1400),
        trading: _btcHeld,
        extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
    await _seeAll(tester);
    final arcs = _arcs(tester);
    final ids = arcs.map((a) => a.id).toList();
    expect(ids, contains('hl-BTC'));
    for (final t in ['a', 'b', 'c', 'd', 'e', 'f']) {
      expect(ids, contains('poly-$t'));
    }
    // Available last, in the palette's grey.
    final palette = AppColorsExtension.light().chartCategorical;
    expect(ids.last, 'available');
    expect(arcs.last.color, palette.last);
    // The largest first (BTC, $10,811.97 + 0.4), the palette in order.
    expect(ids.first, 'hl-BTC');
    expect(arcs.first.color, palette.first);
    // Each row's dot is its slice's colour.
    final rows = find.byType(PortfolioPositionRow);
    expect(rows, findsNWidgets(7));
    for (final e in rows.evaluate()) {
      final row = e.widget as PortfolioPositionRow;
      final dot = tester.widget<Container>(find.descendant(
          of: find.byWidget(row),
          matching: find.byKey(const ValueKey('portfolio-row-dot'))));
      expect((dot.decoration! as BoxDecoration).color,
          arcs.firstWhere((a) => a.id == row.sliceId).color,
          reason: row.sliceId);
    }
    expect(_centreCaption(tester), 'Invested');
    expect(_centreAmount(tester), r'$10,819.17');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('portfolio-hero-sub'))).data,
        startsWith('▲ \$'));
    final legend = find.byKey(const ValueKey('portfolio-shares-legend'));
    expect(find.descendant(of: legend, matching: find.text('7 positions')),
        findsOneWidget);
    expect(
        find.descendant(
            of: legend,
            matching: find.byKey(const ValueKey('portfolio-legend-available'))),
        findsOneWidget);

    // A long press on BTC's row: its slice, its name, value and %.
    final btc = find.byWidgetPredicate(
        (w) => w is PortfolioPositionRow && w.sliceId == 'hl-BTC');
    await tester.longPress(btc);
    await _settle(tester);
    expect(_alphaOf(tester, 'hl-BTC'), 1);
    for (final a in _arcs(tester).where((a) => a.id != 'hl-BTC')) {
      expect(a.color.a, moreOrLessEquals(kBalancesRingDimmed, epsilon: 0.01),
          reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'Bitcoin');
    expect(_centreAmount(tester), r'$10,811.97');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('portfolio-hero-sub'))).data,
        endsWith('%'));
    // The tap still opens the position: the long press only shows it.
    await tester.longPress(btc);
    await _settle(tester);
    for (final a in _arcs(tester)) {
      expect(a.color.a, 1, reason: '${a.id}');
    }
    expect(_centreCaption(tester), 'Invested');
    await _unmount(tester);
  });

  testWidgets(
      'P&L Charts scrubbed: the hole follows the finger, the chart\'s '
      'figure and its moment; released, the range again', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1400),
        extra: [..._history(), ..._predictionsHistory()]);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    expect(_centreCaption(tester), 'Past month');
    final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
    final touch = await tester.startGesture(plot.center);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 150));
    final headline = tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .text;
    final moment = tester
        .widget<Text>(find.byKey(const ValueKey('statistics-pnl-header')))
        .textSpan!
        .toPlainText();
    expect(_centreCaption(tester), moment);
    expect(_centreCaption(tester), isNot('Past month'));
    // The same figure, written with the ring's arrow in place of a sign.
    final digits = RegExp(r'[\d.,]+');
    expect(digits.stringMatch(_centreAmount(tester)),
        digits.stringMatch(headline));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    expect(_centreCaption(tester), 'Past month');
    await _unmount(tester);
  });

  testWidgets(
      'a switch morphs the same ring (one chart, never rebuilt) on the '
      'settle curve', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        trading: _btcHeld,
        extra: [..._history(), ..._predictionsHistory()]);
    final ring = find.byKey(const ValueKey('portfolio-balance-ring'));
    final before = tester.state(ring);
    expect(_arcs(tester).map((a) => a.id), contains('hl-BTC'));
    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.state(ring), same(before));
    // Mid-morph: the positions on their way out, the venues on their way
    // in.
    final mid = _arcs(tester).map((a) => a.id).toSet();
    expect(mid, contains('hl-BTC'));
    expect(mid, contains(BalancesCategory.investing));
    await _settle(tester);
    expect(_arcs(tester).map((a) => a.id),
        isNot(contains('hl-BTC')));
    await _unmount(tester);
  });

  for (final width in [402.0, 375.0]) {
    testWidgets(
        'at ${width.round()} pt and 130 % text in the one scroll: each '
        'card inside the 16 gutters, every figure inside its padding',
        (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: Size(width, 1400),
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      expect(tester.takeException(), isNull);
      final gutter = 16 * width / 430;
      for (final venue in ['investing', 'predictions']) {
        final card = find.descendant(
            of: find.byKey(ValueKey('portfolio-balance-$venue-positions')),
            matching: find.byType(PortfolioCardList));
        final r = tester.getRect(card);
        expect(r.left, moreOrLessEquals(gutter, epsilon: 0.5), reason: venue);
        expect(r.right, moreOrLessEquals(width - gutter, epsilon: 0.5),
            reason: venue);
        for (final key in ['portfolio-row-value', 'portfolio-row-pnl-pill']) {
          for (final e in find
              .descendant(of: card, matching: find.byKey(ValueKey(key)))
              .evaluate()) {
            expect(tester.getRect(find.byWidget(e.widget)).right,
                lessThanOrEqualTo(r.right - gutter + 0.5),
                reason: '$venue $key');
          }
        }
      }
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final card = find.byKey(const ValueKey('statistics-figures'));
      final r = tester.getRect(card);
      expect(r.left, moreOrLessEquals(gutter, epsilon: 0.5));
      expect(r.right, moreOrLessEquals(width - gutter, epsilon: 0.5));
      for (final e in find
          .descendant(of: card, matching: find.byType(Text))
          .evaluate()) {
        expect(tester.getRect(find.byWidget(e.widget)).right,
            lessThanOrEqualTo(r.right - gutter + 0.5));
      }
      await _unmount(tester);
    });
  }

  group('the whole page scrolls', () {
    // Short and at 130 % text, so the Portfolio section scrolls well past
    // the pin.
    const size = Size(375, 420);
    final hero = find.byKey(const ValueKey('portfolio-shares-hero'));
    final strip = find.byKey(const ValueKey('portfolio-strip'));
    double stripTop(WidgetTester tester) => tester.getRect(strip).top;
    // Off screen above the strip (a finder skips what is off stage).
    void heroAway(WidgetTester tester) {
      final h = find.byKey(const ValueKey('portfolio-shares-hero'),
          skipOffstage: false);
      if (h.evaluate().isEmpty) return;
      expect(tester.getRect(h).bottom, lessThanOrEqualTo(0.5));
    }
    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(_pageScroll).position;

    testWidgets(
        'one scroll: the ring scrolls away with the section, the strip '
        'pins at the top once it gets there', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      await _seeAll(tester);
      final top0 = stripTop(tester);
      expect(top0, greaterThan(tester.getRect(hero).bottom - 0.5));
      // The ring, the line and the strip are in the same scroll as the
      // section: no other scroll view.
      expect(find.byType(Scrollable), findsOneWidget);
      position(tester).jumpTo(60);
      await _settle(tester);
      // Moved up with the content, not yet pinned.
      expect(stripTop(tester), moreOrLessEquals(top0 - 60, epsilon: 0.5));
      await tester.drag(_pageScroll, const Offset(0, -2000));
      await _settle(tester);
      // Pinned at the top, the ring off screen above it.
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      expect(position(tester).pixels, greaterThan(top0));
      await _unmount(tester);
    });

    testWidgets(
        'a switch keeps the top block\'s offset: half scrolled stays half '
        'scrolled; scrolled past the pin, the strip stays pinned and the '
        'next section opens at its top', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      await _seeAll(tester);
      final pin = stripTop(tester);
      position(tester).jumpTo(40);
      await _settle(tester);
      final heroAt = tester.getRect(hero);
      final stripAt = stripTop(tester);
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(tester.getRect(hero), heroAt);
      expect(stripTop(tester), stripAt);
      await _pick(tester, PortfolioSection.balances);
      await _settle(tester);
      expect(tester.getRect(hero), heroAt);

      // Past the pin, deep into the section.
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      expect(position(tester).pixels, greaterThan(pin));
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      // At the pin exactly: the new section from its top.
      expect(position(tester).pixels, moreOrLessEquals(pin, epsilon: 0.5));
      await _unmount(tester);
    });

    testWidgets(
        'a short section never drops the strip: it is at least the '
        'viewport under the strip tall', (tester) async {
      // Long Portfolio, P&L Charts empty (nothing ever charted).
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: _btcHeld,
          extra: _manyRows());
      await _seeAll(tester);
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(find.byKey(const ValueKey('statistics-chart-empty')),
          findsOneWidget);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      // And it stays there when dragged further.
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      await _unmount(tester);
    });
  });
}
