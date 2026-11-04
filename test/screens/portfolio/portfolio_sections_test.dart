// The Portfolio screen after its overhaul (founder, 4 November 2026: "the
// top chart means nothing, it's super confusing … much, much, much better
// fintech design comparable to the rest of the app";
// investments_portfolio.dart, components/portfolio_hero.dart):
//
//   * the hero: "Invested" over the Dollars header's figure, the P&L over
//     the range in its colour, ONE P&L chart with the app's range row,
//     "N positions · Available $X"; no ring anywhere, the same hero on
//     every section;
//   * Activity | Positions | P&L, Activity first: the home's squares and
//     rows for the investments' actions, the biggest positions as squares
//     and the rest as the Investing list's rows, each venue's P&L and the
//     all-time stats (the chart is the hero's);
//   * one empty state at one place for all three, one scroll with the
//     strip pinning, every last row clear of the bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
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
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show HlListRow;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioCardList, PortfolioPositionRow;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/activity/activity_history_screen.dart'
    show ActivityHistoryScreen;
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, ActivitySquareGrid;
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalIdleDirector, SalSprite;
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityRowLayout, ActivityRowShape;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
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

PortfolioPerformance _perf(List<(int, double)> points, String source) {
  final now = DateTime.now().toUtc();
  return PortfolioPerformance(
      points: [
        for (final (days, pnl) in points)
          PortfolioPnlPoint(
              timestamp: now.subtract(Duration(days: days)), pnlUsd: pnl)
      ],
      totalPnlUsd: points.last.$2,
      asOf: now.subtract(Duration(days: points.last.$1)),
      sourceLabel: source,
      basisLabel: 'P&L',
      coverageLabel: 'All time');
}

/// A month of Investing P&L that dips under zero and ends above it.
List<Override> _history() => [
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.trading))
          .overrideWith((_) async => _perf(
              [(30, 0.0), (22, -4.0), (15, -9.5), (8, 3.2), (1, 12.4)],
              'Hyperliquid')),
    ];

/// Predictions' P&L: nothing a month and a half ago, $7.61 now.
List<Override> _predictionsHistory() => [
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.predictions))
          .overrideWith((_) async =>
              _perf([(45, 0.0), (20, 2.5), (2, 7.61)], 'Polymarket')),
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

/// Lots to scroll: open predictions, one per token.
List<Override> _manyRows(
        [List<String> tokens = const ['a', 'b', 'c', 'd', 'e', 'f']]) =>
    [
      polymarketActivePositionsProvider.overrideWith((_) => [
            for (final t in tokens)
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

final _t0 = DateTime.now().toUtc().subtract(const Duration(hours: 1));

PolymarketTransaction _bet(String id, Duration ago, {String side = 'BUY'}) =>
    PolymarketTransaction(
      id: id,
      timestamp: _t0.subtract(ago),
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: _t0.subtract(ago).millisecondsSinceEpoch ~/ 1000,
        conditionId: '0x$id',
        type: 'TRADE',
        size: 10,
        usdcSize: 5,
        transactionHash: '0x$id',
        side: side,
        asset: 'asset-$id',
        outcomeIndex: 0,
        title: 'Will $id happen?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

HlFill _fill(String coin, Duration ago, String dir) => HlFill(
      coin: coin,
      px: 60000,
      sz: 0.01,
      side: dir == 'Open Long' ? 'B' : 'A',
      time: _t0.subtract(ago).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0.1,
      feeToken: 'USDC',
      oid: ago.inMinutes,
      hash: '0xfill-$coin-${ago.inMinutes}',
      dir: dir,
      cloid: null,
    );

Transaction _bets(int count) => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: const [],
      sparkUnclaimedDeposits: const [],
      polymarketTransactions: [
        for (var i = 0; i < count; i++)
          _bet('bet$i', Duration(hours: i * 2), side: i == 1 ? 'SELL' : 'BUY'),
      ],
    );

Future<void> _mount(WidgetTester tester,
    {List<Override> extra = const [],
    OneBalanceState state = _nothingOpen,
    HyperliquidTradingState trading = const HyperliquidTradingState(),
    Transaction? history,
    List<HlFill> fills = const [],
    PortfolioSection section = PortfolioSection.balances,
    Size size = const Size(390, 844),
    double textScale = 1}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(trading: trading, history: history),
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
          reviewDone: true,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
      oneBalanceProvider.overrideWith((ref) => state),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      hyperliquidActivityFillsProvider.overrideWithValue(fills),
      portfolioSectionProvider.overrideWith((_) => section),
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: Material(
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

/// The Portfolio screen's one scroll (the hero, the strip, the section).
final _pageScroll = find
    .descendant(
        of: find.byKey(const ValueKey('portfolio-page-scroll')),
        matching: find.byType(Scrollable))
    .first;

/// The hero's P&L line as written.
String _change(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
    .textSpan!
    .toPlainText();

/// A live figure's text (it rolls glyph by glyph).
String _figure(WidgetTester tester, String key) =>
    tester.widget<BalancesLiveFigure>(find.byKey(ValueKey(key))).figure.text;

/// Opens the Predictions card past its first rows ("See all"), when the
/// squares leave it more than it shows folded.
Future<void> _seeAll(WidgetTester tester) async {
  final fold =
      find.byKey(const ValueKey('portfolio-balance-predictions-see-all'));
  if (fold.evaluate().isEmpty) return;
  await tester.ensureVisible(fold);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(fold);
  await _settle(tester);
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  scroll.jumpTo(0);
  await _settle(tester);
}

/// The keys of the rows drawn as squares ("hl-BTC", "poly-a"), in order:
/// each row's own widget carries its key, the square is drawn under it.
List<String> _squareKeys(WidgetTester tester) => [
      for (final e in find
          .descendant(
              of: find.byKey(const ValueKey('portfolio-balance-squares')),
              matching: find.byType(PortfolioPositionRow))
          .evaluate())
        () {
          String? key;
          e.visitAncestorElements((a) {
            final k = a.widget.key;
            if (k is ValueKey<String> &&
                (k.value.startsWith('hl-') || k.value.startsWith('poly-'))) {
              key = k.value;
              return false;
            }
            return true;
          });
          return key ?? '';
        }(),
    ];

void main() {
  testWidgets(
      'all three sections empty: one empty state, Sal and the title at the '
      'same place, only the copy changes; the hero says nothing twice',
      (tester) async {
    await _mount(tester, section: PortfolioSection.activity);
    final titles = {
      PortfolioSection.activity: 'No activity yet',
      PortfolioSection.balances: 'No open positions',
      PortfolioSection.charts: 'No P&L yet',
    };
    final sal = <PortfolioSection, Rect>{};
    final title = <PortfolioSection, Rect>{};
    for (final section in [
      PortfolioSection.activity,
      PortfolioSection.balances,
      PortfolioSection.charts,
      PortfolioSection.activity,
    ]) {
      if (sal.isNotEmpty) {
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
      if (sal[section] case final before?) {
        _expectSameRect(s, before, 'Sal back on $section');
        _expectSameRect(t, title[section]!, 'title back on $section');
      }
      sal[section] = s;
      title[section] = t;
      expect(
          tester.widget<Text>(find.text(titles[section]!)).style?.fontWeight,
          FontWeight.w600);
    }
    final base = sal[PortfolioSection.activity]!;
    for (final section in PortfolioSection.values) {
      _expectSameRect(sal[section]!, base, 'Sal on $section');
      expect(title[section]!.top,
          moreOrLessEquals(title[PortfolioSection.activity]!.top, epsilon: 0.01),
          reason: 'title top on $section');
    }
    expect(base.width, moreOrLessEquals(160.sp));
    // Never traded: the hero is the figure and its line; no P&L line, no
    // chart, no caption repeating the sections' empty state.
    expect(find.byKey(const ValueKey('portfolio-hero-no-history')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-hero-change')), findsNothing);
    expect(find.text('Your P&L shows up after your first position.'),
        findsNothing);
    // Nothing open: Available alone.
    expect(find.byKey(const ValueKey('portfolio-hero-positions')),
        findsNothing);
    expect(_figure(tester, 'portfolio-hero-available'), r'$17.64');
    await _unmount(tester);
  });

  testWidgets(
      'the strip is Activity | Positions | P&L in equal thirds, Activity '
      'first and the screen\'s default', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(portfolioSectionProvider), PortfolioSection.activity);
    expect(PortfolioSection.values.map((s) => s.key),
        ['activity', 'balances', 'charts']);

    await _mount(tester);
    final pills = [
      for (final s in PortfolioSection.values)
        find.byKey(ValueKey('portfolio-section-pill-${s.key}'))
    ];
    for (final (pill, label) in [
      (pills[0], 'Activity'),
      (pills[1], 'Positions'),
      (pills[2], 'P&L'),
    ]) {
      expect(pill, findsOneWidget);
      expect(
          find.descendant(of: pill, matching: find.text(label)), findsOneWidget);
    }
    expect(
        tester.getRect(pills[0]).left, lessThan(tester.getRect(pills[1]).left));
    expect(
        tester.getRect(pills[1]).left, lessThan(tester.getRect(pills[2]).left));
    for (final p in pills.skip(1)) {
      expect(tester.getSize(p).width,
          moreOrLessEquals(tester.getSize(pills[0]).width, epsilon: 0.01));
    }
    expect(find.text('P&L Charts'), findsNothing);
    // Links: Positions is still `balances`, P&L `charts`; an old
    // `?tab=activity` is the Bitcoin home's (app_router.dart).
    expect(PortfolioSection.forLink('positions'), PortfolioSection.balances);
    expect(PortfolioSection.forLink('orders'), PortfolioSection.charts);
    expect(PortfolioSection.forLink('activity'), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'the hero: "Invested" over the Dollars header\'s figure, the P&L over '
      'the range in its colour, ONE chart with the app\'s range row, the '
      'positions and Available under it; no ring anywhere', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        trading: _btcHeld,
        extra: [..._history(), ..._predictionsHistory()]);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('portfolio-hero-caption')))
            .data,
        'Invested');
    expect(_figure(tester, 'portfolio-hero-value'), r'$14.24');
    final change = _change(tester);
    expect(change, startsWith('▲ \$'));
    expect(change, endsWith(' · Past month'));
    expect(change, isNot(contains('%')), reason: 'no base, no percent');
    final line = tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan! as TextSpan;
    expect((line.children!.first as TextSpan).style!.color, AppColors.marketUp);
    // The one chart, the split fill, the range row 1W to ALL with 1M on.
    final chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('portfolio-hero-chart')));
    expect(chart.zeroSplit, isTrue);
    expect(chart.rangeLabels, ['1W', '1M', '3M', '1Y', 'ALL']);
    expect(chart.selectedRange, 1);
    expect(find.byType(KuteTrendChart), findsOneWidget);
    // "1 position · Available $42.64": the BTC perp; Dollars and the
    // venues' spare cash.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('portfolio-hero-line')),
            matching: find.text('1 position')),
        findsOneWidget);
    expect(_figure(tester, 'portfolio-hero-available'), r'$42.64');
    // The ring and its remnants are gone.
    expect(find.byType(KuteDonutChart), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-shares-hero')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-all-time')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-row-dot')), findsNothing);
    // Top down: caption, figure, P&L line, chart, the line, the strip.
    double top(String key) => tester.getRect(find.byKey(ValueKey(key))).top;
    final tops = [
      top('portfolio-hero-caption'),
      top('portfolio-hero-value'),
      top('portfolio-hero-change'),
      top('portfolio-hero-chart'),
      top('portfolio-hero-line'),
      top('portfolio-strip'),
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: 'hero order $i');
    }
    await _unmount(tester);
  });

  testWidgets(
      'one hero for every section: never rebuilt by a switch, at the same '
      'place; a range picked moves the P&L line and the P&L section\'s '
      'venue rows together', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.activity,
        size: const Size(390, 1400),
        // Investing traded: its venue row has figures.
        fills: [
          _fill('BTC', const Duration(days: 10), 'Open Long'),
          _fill('BTC', const Duration(days: 3), 'Close Long'),
        ],
        extra: [..._history(), ..._predictionsHistory()]);
    final chart = find.byType(PortfolioHeroChart);
    final state = tester.state(chart);
    final rect = tester.getRect(find.byKey(const ValueKey('portfolio-hero')));
    for (final s in [PortfolioSection.balances, PortfolioSection.charts]) {
      await _pick(tester, s);
      await _settle(tester);
      expect(tester.state(chart), same(state), reason: '$s');
      _expectSameRect(
          tester.getRect(find.byKey(const ValueKey('portfolio-hero'))),
          rect,
          '$s');
    }
    final venueChange = find.descendant(
        of: find.byKey(const ValueKey('pnl-venue-investing')),
        matching: find.byKey(const ValueKey('pnl-venue-change')));
    final month = tester.widget<Text>(venueChange).data;
    await tester.tap(find.text('1W'));
    await _settle(tester);
    expect(_change(tester), endsWith(' · Past week'));
    expect(tester.widget<Text>(venueChange).data, isNot(month));
    await tester.tap(find.text('ALL'));
    await _settle(tester);
    // ALL: the P&L since the account began, both venues added.
    expect(_change(tester), '▲ \$20.01 · All time');
    await _unmount(tester);
  });

  testWidgets(
      'scrubbed: the P&L line follows the finger (its P&L since the range\'s '
      'start and its moment), the figure stays; released, the range again; '
      'one scrub event', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await _mount(tester,
        state: _bothAtWork, extra: [..._history(), ..._predictionsHistory()]);
    final rest = _change(tester);
    final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
    final touch = await tester.startGesture(plot.center);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 150));
    final scrubbed = _change(tester);
    expect(scrubbed, isNot(rest));
    expect(scrubbed, isNot(endsWith('Past month')));
    expect(_figure(tester, 'portfolio-hero-value'), r'$14.24');
    await touch.up();
    await _settle(tester);
    expect(_change(tester), rest);
    expect(
        events
            .where((e) => e.$1 == 'portfolio_performance_chart_scrubbed')
            .map((e) => e.$2),
        [
          {'venue': 'all'}
        ]);
    await _unmount(tester);
  });

  testWidgets(
      'Activity: the four newest actions as the home\'s squares, the next '
      'two as its Earlier rows, then "See all" to the Activity screen on the '
      'Investments activity',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await _mount(tester,
        section: PortfolioSection.activity,
        size: const Size(390, 1600),
        history: _bets(5),
        fills: [
          _fill('BTC', const Duration(hours: 1), 'Open Long'),
          _fill('ETH', const Duration(hours: 30), 'Close Short'),
        ]);
    final squares = find.byKey(const ValueKey('portfolio-activity-squares'));
    expect(squares, findsOneWidget);
    expect(tester.widget<ActivitySquareGrid>(squares).children, hasLength(4));
    expect(
        tester
            .widget<ActivityRowLayout>(find
                .ancestor(of: squares, matching: find.byType(ActivityRowLayout))
                .first)
            .shape,
        ActivityRowShape.square);
    final earlier = find.byKey(const ValueKey('portfolio-activity-earlier'));
    expect(earlier, findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(
        tester
            .widget<ActivityRowLayout>(find
                .ancestor(of: earlier, matching: find.byType(ActivityRowLayout))
                .first)
            .shape,
        ActivityRowShape.plain);
    // The Investing open is among the newest.
    expect(find.descendant(of: squares, matching: find.text('Long BTC')),
        findsOneWidget);
    // The section starts where every section does.
    final strip = tester.getRect(find.byKey(const ValueKey('portfolio-strip')));
    expect(tester.getRect(squares).top - strip.bottom,
        moreOrLessEquals(kPortfolioSectionEmptyTop.h, epsilon: 0.5));
    // "See all": the home's pill, opening the whole list.
    final seeAll = find.byKey(const ValueKey('portfolio-activity-see-all'));
    final pill = tester.widget<KutePill>(seeAll);
    expect(pill.label, 'See all');
    expect(pill.icon, Icons.arrow_forward_rounded);
    expect(pill.selected, isTrue);
    await tester.tap(seeAll);
    await _settle(tester);
    final screen = tester
        .widget<ActivityHistoryScreen>(find.byType(ActivityHistoryScreen));
    expect(screen.listedScope, ActivityScope.investments);
    expect(
        events.where((e) => e.$1 == 'activity_history_opened').single.$2,
        {'entry_source': 'portfolio', 'scope': 'investments'});
    await _unmount(tester);
  });

  testWidgets(
      'P&L: each venue\'s P&L and the all-time stats, no chart of its own '
      '(the hero\'s is the one), its first title where every section starts',
      (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.charts,
        extra: [..._history(), ..._predictionsHistory()]);
    expect(find.byKey(const ValueKey('statistics-pnl-chart')), findsNothing);
    expect(
        find.byKey(const ValueKey('statistics-pnl-headline')), findsNothing);
    expect(find.byType(KuteTrendChart), findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-figures')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pnl-venue-predictions')), findsOneWidget);
    expect(find.byKey(const ValueKey('pnl-venue-investing')), findsOneWidget);
    // The rows chart nothing: no pick.
    expect(find.byKey(const ValueKey('pnl-venue-investing-pick')),
        findsNothing);
    final byVenue = find.byKey(const ValueKey('statistics-pnl-by-venue'));
    expect(tester.widget<Text>(byVenue).data, 'By venue');
    final strip = tester.getRect(find.byKey(const ValueKey('portfolio-strip')));
    expect(tester.getRect(byVenue).top - strip.bottom,
        moreOrLessEquals(kPortfolioSectionEmptyTop.h, epsilon: 0.5));
    await _unmount(tester);
  });

  testWidgets('P&L, never traded: the first frame is the empty state',
      (tester) async {
    await _mount(tester);
    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-performance-loading')),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets('P&L with history: the first frame is the venue rows',
      (tester) async {
    await _mount(tester, extra: _history());
    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    expect(find.byKey(const ValueKey('statistics-figures')), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-performance-loading')),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'Positions: the four biggest are squares, biggest first, the rest the '
      'Investing list\'s rows under their venue; no dot, no long press',
      (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1400),
        trading: _btcHeld,
        extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
    await _seeAll(tester);
    expect(find.byType(PortfolioPositionRow), findsNWidgets(7));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('portfolio-balance-squares')),
            matching: find.byType(PortfolioPositionRow)),
        findsNWidgets(4));
    // BTC ($10,812) leads.
    expect(_squareKeys(tester).first, 'hl-BTC');
    expect(find.byKey(const ValueKey('portfolio-row-dot')), findsNothing);
    final rest = find.descendant(
        of: find.byKey(
            const ValueKey('portfolio-balance-predictions-positions')),
        matching: find.byType(HlListRow));
    expect(rest, findsNWidgets(3));
    expect(tester.widget<HlListRow>(rest.first).onLongPress, isNull);
    // The hero counts what is open.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('portfolio-hero-line')),
            matching: find.text('7 positions')),
        findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'Positions with three: the two biggest are squares side by side, the '
      'third the Investing list\'s row under its venue, counted as what it '
      'lists', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1400),
        trading: _btcHeld,
        extra: [
          polymarketActivePositionsProvider.overrideWith((_) => [
                for (final (t, size) in [('a', 4.0), ('b', 2.0)])
                  PolymarketPosition(
                      marketId: 'm-$t',
                      marketQuestion: 'Will $t happen this year?',
                      outcome: 'Yes',
                      size: size,
                      avgPrice: 0.5,
                      currentPrice: 0.6,
                      pnl: 0,
                      pnlPercent: 0,
                      isResolved: false,
                      tokenId: t),
              ]),
        ]);
    final block = find.byKey(const ValueKey('portfolio-balance-squares'));
    final squares = find.descendant(
        of: block, matching: find.byKey(const ValueKey('portfolio-square')));
    expect(squares, findsNWidgets(2));
    final left = tester.getRect(squares.at(0));
    final right = tester.getRect(squares.at(1));
    expect(left.top, right.top);
    expect(left.width, moreOrLessEquals(right.width));
    expect(_squareKeys(tester), ['hl-BTC', 'poly-a']);
    expect(find.text('Predictions · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-balance-investing-positions')),
        findsNothing);
    final rest = find.descendant(
        of: find.byKey(
            const ValueKey('portfolio-balance-predictions-positions')),
        matching: find.byType(HlListRow));
    expect(rest, findsOneWidget);
    expect(tester.getRect(rest).top, greaterThan(left.bottom));
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
          section: section,
          trading: _btcHeld,
          history: _bets(8),
          extra: [
            ..._history(),
            ..._predictionsHistory(),
            ..._manyRows(const ['a', 'b', 'c', 'd', 'e']),
          ]);
      expect(tester.takeException(), isNull);
      await tester.drag(_pageScroll, const Offset(0, -4000));
      await _settle(tester);
      final last = switch (section) {
        PortfolioSection.activity =>
          find.byKey(const ValueKey('portfolio-activity-see-all')),
        PortfolioSection.balances => find.byType(PortfolioPositionRow).last,
        PortfolioSection.charts =>
          find.byKey(const ValueKey('statistics-pnl-stats-card')),
      };
      expect(last, findsOneWidget);
      final bar = size.height - kuteBarScrollClearance * size.height / 932;
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(bar + 0.5),
          reason: 'the last row under the bar');
      final inset = 16 * size.width / 430;
      final card = switch (section) {
        PortfolioSection.activity =>
          find.byKey(const ValueKey('portfolio-activity-earlier')),
        PortfolioSection.balances => find
            .byKey(const ValueKey('portfolio-balance-predictions-positions')),
        PortfolioSection.charts =>
          find.byKey(const ValueKey('statistics-figures')),
      };
      final right = tester.getRect(card).right - inset + 0.5;
      final texts = find.descendant(of: card, matching: find.byType(Text));
      expect(texts, findsWidgets);
      for (final e in texts.evaluate()) {
        expect(tester.getRect(find.byWidget(e.widget)).right,
            lessThanOrEqualTo(right),
            reason: (e.widget as Text).data);
      }
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  for (final width in [402.0, 375.0]) {
    testWidgets(
        'at ${width.round()} pt and 130 % text: the hero and every card '
        'inside the 16 gutters, every figure inside its padding',
        (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: Size(width, 1400),
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      expect(tester.takeException(), isNull);
      final gutter = 16 * width / 430;
      for (final key in [
        'portfolio-hero-value',
        'portfolio-hero-change',
        'portfolio-hero-line',
        'portfolio-hero-chart',
      ]) {
        final r = tester.getRect(find.byKey(ValueKey(key)));
        expect(r.left, greaterThanOrEqualTo(gutter - 0.5), reason: key);
        expect(r.right, lessThanOrEqualTo(width - gutter + 0.5), reason: key);
      }
      for (final (name, block, pad) in [
        (
          'squares',
          find.byKey(const ValueKey('portfolio-balance-squares')),
          14 * width / 430
        ),
        (
          'predictions',
          find.descendant(
              of: find.byKey(
                  const ValueKey('portfolio-balance-predictions-positions')),
              matching: find.byType(PortfolioCardList)),
          gutter
        ),
      ]) {
        final r = tester.getRect(block);
        expect(r.left, moreOrLessEquals(gutter, epsilon: 0.5), reason: name);
        expect(r.right, moreOrLessEquals(width - gutter, epsilon: 0.5),
            reason: name);
        for (final key in ['portfolio-row-value', 'portfolio-row-pnl']) {
          for (final e in find
              .descendant(of: block, matching: find.byKey(ValueKey(key)))
              .evaluate()) {
            expect(tester.getRect(find.byWidget(e.widget)).right,
                lessThanOrEqualTo(r.right - pad + 0.5),
                reason: '$name $key');
          }
        }
      }
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      for (final key in ['statistics-figures', 'statistics-pnl-stats-card']) {
        final card = find.byKey(ValueKey(key));
        final r = tester.getRect(card);
        expect(r.left, moreOrLessEquals(gutter, epsilon: 0.5), reason: key);
        expect(r.right, moreOrLessEquals(width - gutter, epsilon: 0.5),
            reason: key);
        for (final e
            in find.descendant(of: card, matching: find.byType(Text)).evaluate()) {
          expect(tester.getRect(find.byWidget(e.widget)).right,
              lessThanOrEqualTo(r.right - gutter + 0.5),
              reason: key);
        }
      }
      await _unmount(tester);
    });
  }

  group('the whole page scrolls', () {
    // Short and at 130 % text, so the Positions section scrolls well past
    // the pin.
    const size = Size(375, 420);
    final hero = find.byKey(const ValueKey('portfolio-hero'));
    final strip = find.byKey(const ValueKey('portfolio-strip'));
    double stripTop(WidgetTester tester) => tester.getRect(strip).top;
    // Off screen above the strip (a finder skips what is off stage).
    void heroAway(WidgetTester tester) {
      final h =
          find.byKey(const ValueKey('portfolio-hero'), skipOffstage: false);
      if (h.evaluate().isEmpty) return;
      expect(tester.getRect(h).bottom, lessThanOrEqualTo(0.5));
    }

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(_pageScroll).position;

    testWidgets(
        'one scroll: the hero scrolls away with the section, the strip '
        'pins at the top once it gets there', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      await _seeAll(tester);
      final top0 = stripTop(tester);
      // The hero, the strip and the section in one scroll.
      expect(find.byType(Scrollable), findsOneWidget);
      position(tester).jumpTo(60);
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(top0 - 60, epsilon: 0.5));
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      expect(position(tester).pixels, greaterThan(top0));
      await _unmount(tester);
    });

    testWidgets(
        'a switch keeps the hero\'s offset: half scrolled stays half '
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

      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      expect(position(tester).pixels, greaterThan(pin));
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      expect(position(tester).pixels, moreOrLessEquals(pin, epsilon: 0.5));
      await _unmount(tester);
    });

    testWidgets(
        'a short section never drops the strip: it is at least the '
        'viewport under the strip tall', (tester) async {
      // Long Positions, P&L empty (nothing ever charted).
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
      expect(
          find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      await _unmount(tester);
    });
  });
}
