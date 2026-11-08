// The Portfolio screen after its redesign (7 November 2026, after the
// Robinhood / Public / Webull / Polymarket / Kalshi review; founder: "yes
// build this"; investments_portfolio.dart, components/portfolio_hero.dart,
// portfolio_pnl_section.dart, portfolio_activity.dart):
//
//   * the hero: the TOTAL (the open positions' worth plus Available), the
//     P&L over the range in its colour with its percent on a real base,
//     ONE P&L chart (1W 1M 3M ALL, 1M to start, ALL when 1M is not
//     offered), "Invested $X · Available $Y"; the same hero on every
//     section; on P&L the "By product" row picked alone;
//   * Positions | P&L | Activity, Positions first: the open positions by
//     value under plain "Investing" / "Predictions" headings, each row its
//     value over the P&L since it was opened; "You're up $X" with the two
//     rows that add up to it, "By product", the closed positions; the
//     investments' feed by day with its filter chips;
//   * one empty state at one place for all three, one scroll with the
//     strip pinning, every last row clear of the bar.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
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
import 'package:kute/providers/open_pnl_history_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show HlMetaChip;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show PnlVenueRow, pnlChartRangeProvider, portfolioPnlVenueProvider;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow, PortfolioCardList, PortfolioPositionRow;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/activity/activity_history_screen.dart'
    show ActivityHistoryScreen;
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/shared/all_activity.dart' show ActivityScope;
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalIdleDirector, SalSprite;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityDaySection;
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

/// Predictions' P&L with its book: one prediction closed for +$7.61, so
/// its square has figures (and so can be picked).
List<Override> _predictionsBooked() {
  final now = DateTime.now().toUtc();
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async =>
            _perf([(45, 0.0), (20, 2.5), (2, 7.61)], 'Polymarket')
                .withPredictions(PredictionsBook(records: [
              PredictionRecord(
                tokenId: 'won',
                open: false,
                redeemable: false,
                size: 0,
                totalSize: 20,
                avgPrice: 0.4,
                entryCostUsd: 0,
                currentPrice: 1,
                realizedPnlUsd: 7.61,
                unrealizedPnlUsd: 0,
                firstEntryAt: now.subtract(const Duration(days: 40)),
                lastEventAt: now.subtract(const Duration(days: 2)),
              ),
            ]))),
  ];
}

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
    double textScale = 1,
    bool hidden = false,
    OpenPnlSources? sources}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(
          trading: trading, history: history, openPnlSources: sources),
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
          balancePrivacy: hidden ? 1 : 0,
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

/// A Polymarket transaction of [type] ('TRADE', 'REDEEM', 'DEPOSIT').
PolymarketTransaction _poly(String id, Duration ago,
        {required String type, String side = '', double usdc = 5}) =>
    PolymarketTransaction(
      id: id,
      timestamp: _t0.subtract(ago),
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: _t0.subtract(ago).millisecondsSinceEpoch ~/ 1000,
        conditionId: '0x$id',
        type: type,
        size: 10,
        usdcSize: usdc,
        transactionHash: '0x$id',
        side: side,
        asset: 'asset-$id',
        outcomeIndex: 0,
        title: 'Will $id happen?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

/// Open predictions of [sizes] shares each, bought at 50¢, now at 60¢.
List<Override> _sized(Map<String, double> sizes) => [
      polymarketActivePositionsProvider.overrideWith((_) => [
            for (final MapEntry(key: t, value: size) in sizes.entries)
              PolymarketPosition(
                  marketId: 'm-$t',
                  marketQuestion: 'Will $t happen this year?',
                  outcome: t == 'b' ? 'No' : 'Yes',
                  size: size,
                  avgPrice: 0.5,
                  currentPrice: 0.6,
                  pnl: 0,
                  pnlPercent: 0,
                  isResolved: false,
                  tokenId: t),
          ]),
    ];

/// The written P&L figure of a row's [key] (rolling glyph by glyph).
String _rolling(WidgetTester tester, Finder row, String key) => tester
    .widget<RollingFigure>(
        find.descendant(of: row, matching: find.byKey(ValueKey(key))))
    .text;

void main() {
  testWidgets(
      'all three sections empty: one empty state, Sal and the title at the '
      'same place, only the copy changes; the hero is the total and its '
      'line, nothing said twice; Positions offers Browse Investing',
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
      expect(find.byType(SalSprite), findsOneWidget);
      final s = tester.getRect(find.byType(SalIdleDirector));
      final t = tester.getRect(find.text(titles[section]!));
      if (sal[section] case final before?) {
        _expectSameRect(s, before, 'Sal back on $section');
        _expectSameRect(t, title[section]!, 'title back on $section');
      }
      sal[section] = s;
      title[section] = t;
      // Browse Investing under Positions' empty state alone.
      expect(find.byKey(const ValueKey('portfolio-browse-investing')),
          section == PortfolioSection.balances ? findsOneWidget : findsNothing,
          reason: '$section');
    }
    final base = sal[PortfolioSection.activity]!;
    for (final section in PortfolioSection.values) {
      _expectSameRect(sal[section]!, base, 'Sal on $section');
    }
    expect(base.width, moreOrLessEquals(160.sp));
    // Never traded: the total and its line; no P&L line, no chart.
    expect(find.byKey(const ValueKey('portfolio-hero-no-history')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-hero-change')), findsNothing);
    expect(_figure(tester, 'portfolio-hero-value'), r'$17.64');
    expect(_figure(tester, 'portfolio-hero-invested'), r'$0.00');
    expect(_figure(tester, 'portfolio-hero-available'), r'$17.64');

    // Browse Investing: the app's link pill; a tap sends its event.
    await _pick(tester, PortfolioSection.balances);
    await _settle(tester);
    final browse = find.byKey(const ValueKey('portfolio-browse-investing'));
    final pill = tester.widget<KutePill>(browse);
    expect(pill.label, 'Browse Investing');
    expect(pill.link, isTrue);
    expect(pill.icon, Icons.arrow_forward_rounded);
    await _unmount(tester);
  });

  testWidgets(
      'the strip is Positions | P&L | Activity in equal thirds, Positions '
      'first and the screen\'s default, Activity last; analytics names '
      'them positions, pnl, activity', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    // The keys (links, widget keys) are unchanged; analytics' names are
    // the pills' own.
    expect(PortfolioSection.values.map((s) => s.key),
        ['balances', 'charts', 'activity']);
    expect(PortfolioSection.values.map((s) => s.eventName),
        ['positions', 'pnl', 'activity']);

    await _mount(tester);
    final pills = [
      for (final s in PortfolioSection.values)
        find.byKey(ValueKey('portfolio-section-pill-${s.key}'))
    ];
    for (final (pill, label) in [
      (pills[0], 'Positions'),
      (pills[1], 'P&L'),
      (pills[2], 'Activity'),
    ]) {
      expect(find.descendant(of: pill, matching: find.text(label)),
          findsOneWidget);
    }
    for (final p in pills.skip(1)) {
      expect(tester.getSize(p).width,
          moreOrLessEquals(tester.getSize(pills[0]).width, epsilon: 0.01));
    }
    expect(PortfolioSection.forLink('positions'), PortfolioSection.balances);
    expect(PortfolioSection.forLink('orders'), PortfolioSection.charts);
    expect(PortfolioSection.forLink('activity'), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'the hero: the TOTAL (the open positions\' worth plus Available), the '
      'P&L over the range with its percent in its colour, ONE chart with '
      'its range row, "Invested \$X · Available \$Y" under it; no '
      '"Invested" hero, no caption, no ring', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.activity,
        trading: _btcHeld,
        extra: [..._history(), ..._predictionsHistory()]);
    // $14.24 invested and $42.64 available: $56.88.
    expect(_figure(tester, 'portfolio-hero-value'), r'$56.88');
    expect(_figure(tester, 'portfolio-hero-invested'), r'$14.24');
    expect(_figure(tester, 'portfolio-hero-available'), r'$42.64');
    expect(find.byKey(const ValueKey('portfolio-hero-caption')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('portfolio-hero')),
            matching: find.text('Invested')),
        findsNothing,
        reason: '"Invested" is the line under the chart, never the hero');
    // Three weeks of P&L: the month (the start) is not offered, so ALL;
    // +$20.01 over a base of $36.87 (what is held less the change).
    expect(_change(tester), r'▲ $20.01 (+54.3%) · All time');
    final line = tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan! as TextSpan;
    expect((line.children!.first as TextSpan).style!.color, AppColors.marketUp);
    final chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('portfolio-hero-chart')));
    expect(chart.zeroSplit, isTrue);
    expect(chart.baseline, 0);
    expect(chart.lineColor, AppColors.marketUp);
    expect(chart.rangeLabels, ['1W', 'ALL']);
    expect(chart.selectedRange, 1);
    expect(find.byType(KuteTrendChart), findsOneWidget);
    expect(find.byType(KuteDonutChart), findsNothing);
    // Top down: the total, the P&L line, the chart, the line, the strip.
    double top(String key) => tester.getRect(find.byKey(ValueKey(key))).top;
    final tops = [
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
      'the percent only on a real base: a base under a dollar (or a change '
      'of 1000 % or more) writes the amount alone', (tester) async {
    // $0.50 held now, +$20.01 over the range: the base is negative.
    await _mount(tester,
        state: const OneBalanceState(
          dollarsUsd: 0.5,
          investingKnown: true,
          predictionsKnown: true,
        ),
        section: PortfolioSection.activity,
        extra: [..._history(), ..._predictionsHistory()]);
    expect(_change(tester), r'▲ $20.01 · All time');
    expect(_change(tester), isNot(contains('%')));
    await _unmount(tester);
  });

  testWidgets(
      'the 1M default: 1M when the history offers it, ALL when it does not '
      '(the line never draws a flat stretch before it)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pnlChartRangeProvider), BalanceRange.month);
    // Three weeks: ALL lit.
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.charts,
        extra: [..._history(), ..._predictionsHistory()]);
    var chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('portfolio-hero-chart')));
    expect(chart.rangeLabels![chart.selectedRange], 'ALL');
    expect(_change(tester), endsWith(' · All time'));
    await _unmount(tester);
    // Four months: 1M lit, and 1Y never offered.
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.charts,
        extra: [
          portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                  venue: PortfolioPerformanceVenue.trading))
              .overrideWith((_) async => _perf(
                  [(120, 0.0), (100, 1.0), (40, 6.0), (2, 12.4)],
                  'Hyperliquid')),
        ]);
    chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('portfolio-hero-chart')));
    expect(chart.rangeLabels, ['1W', '1M', '3M', 'ALL']);
    expect(chart.rangeLabels![chart.selectedRange], '1M');
    expect(_change(tester), endsWith(' · Past month'));
    await _unmount(tester);
  });

  testWidgets(
      'one hero for every section: never rebuilt by a switch, at the same '
      'place and the same size; a range picked moves the hero\'s line, the '
      'P&L headline and the "By product" rows together', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.activity,
        size: const Size(390, 1600),
        fills: [
          _fill('BTC', const Duration(days: 10), 'Open Long'),
          _fill('BTC', const Duration(days: 3), 'Close Long'),
        ],
        extra: [
          ..._history(),
          ..._predictionsBooked()
        ]);
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
      expect(find.byKey(const ValueKey('portfolio-hero-chart')), findsOneWidget,
          reason: '$s: the chart on every section');
    }
    String headline() => tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-pnl-headline')))
        .data!;
    String product(String v) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey('pnl-venue-$v')),
            matching: find.byKey(const ValueKey('pnl-venue-figure'))))
        .data!;
    expect(_change(tester), startsWith(r'▲ $20.01'));
    expect(headline(), r"You're up $20.01");
    final whole = product('investing');
    await tester.tap(find.text('1W'));
    await _settle(tester);
    expect(_change(tester), endsWith(' · Past week'));
    expect(headline(), isNot(r"You're up $20.01"));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('portfolio-pnl-period')))
            .data,
        'Past week');
    expect(product('investing'), isNot(whole));
    await tester.tap(find.text('ALL'));
    await _settle(tester);
    expect(headline(), r"You're up $20.01");
    expect(product('investing'), whole);
    await _unmount(tester);
  });

  testWidgets(
      'scrubbed: the line reads "Up \$X · <day>" or "Down \$X · <day>" (the '
      'P&L since the range\'s start to the point under the finger), the '
      'total stays; released, the range again; one scrub event',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.activity,
        extra: [..._history(), ..._predictionsHistory()]);
    final rest = _change(tester);
    final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
    final touch = await tester.startGesture(plot.center);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 150));
    final scrubbed = _change(tester);
    expect(scrubbed, isNot(rest));
    expect(scrubbed,
        matches(RegExp(r'^(Up \$[\d,.]+|Down \$[\d,.]+|No change) · .+$')));
    expect(scrubbed, isNot(contains('▲')));
    expect(scrubbed, isNot(contains('%')));
    expect(_figure(tester, 'portfolio-hero-value'), r'$56.88');
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
      'hidden balances: the total, the line and the P&L are dots, nothing '
      'says which way it went', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        hidden: true,
        section: PortfolioSection.charts,
        extra: [..._history(), ..._predictionsHistory()]);
    expect(_figure(tester, 'portfolio-hero-value'), '••••••');
    expect(_figure(tester, 'portfolio-hero-invested'), '••••••');
    expect(_change(tester), '•••••• · All time');
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('portfolio-pnl-headline')))
            .data,
        '••••••');
    expect(find.textContaining(r'$'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'Activity: one feed by day on the app\'s day cards, each row its own '
      'surface\'s widget ("Closed ETH short" with its result), the filter '
      'chips All / Trades / Payouts / Transfers; the pill\'s second tap '
      'opens the whole Investments activity', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await _mount(tester,
        section: PortfolioSection.activity,
        size: const Size(390, 2400),
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [
            _poly('buy', const Duration(hours: 2), type: 'TRADE', side: 'BUY'),
            _poly('won', const Duration(hours: 26), type: 'REDEEM', usdc: 10),
            _poly('in', const Duration(hours: 50), type: 'DEPOSIT', usdc: 20),
          ],
        ),
        fills: [
          _fill('BTC', const Duration(hours: 1), 'Open Long'),
          _fill('ETH', const Duration(hours: 30), 'Close Short'),
        ]);
    final section = find.byKey(const ValueKey('portfolio-activity'));
    expect(section, findsOneWidget);
    // By day: today, yesterday, two days back.
    expect(
        find.descendant(of: section, matching: find.byType(ActivityDaySection)),
        findsNWidgets(3));
    // The squares and the Earlier card are gone.
    expect(
        find.byKey(const ValueKey('portfolio-activity-squares')), findsNothing);
    expect(find.text('Earlier'), findsNothing);
    Iterable<String> titles() => [
          for (final t in [
            'Long BTC',
            'Prediction · Yes',
            'Won · Yes',
            'Closed ETH short',
            'Deposit',
          ])
            if (find
                .descendant(of: section, matching: find.text(t))
                .evaluate()
                .isNotEmpty)
              t,
        ];
    expect(titles(), [
      'Long BTC',
      'Prediction · Yes',
      'Won · Yes',
      'Closed ETH short',
      'Deposit',
    ]);
    // The chips, the app's pills, All on.
    final chips = {
      for (final f in ['all', 'trades', 'payouts', 'transfers'])
        f: find.byKey(ValueKey('portfolio-activity-filter-$f')),
    };
    expect([for (final c in chips.values) tester.widget<KutePill>(c).label],
        ['All', 'Trades', 'Payouts', 'Transfers']);
    expect(tester.widget<KutePill>(chips['all']!).selected, isTrue);
    for (final (f, shown) in [
      ('trades', ['Long BTC', 'Prediction · Yes', 'Closed ETH short']),
      ('payouts', ['Won · Yes']),
      ('transfers', ['Deposit']),
      (
        'all',
        [
          'Long BTC',
          'Prediction · Yes',
          'Won · Yes',
          'Closed ETH short',
          'Deposit',
        ]
      ),
    ]) {
      await tester.tap(chips[f]!);
      await _settle(tester);
      expect(tester.widget<KutePill>(chips[f]!).selected, isTrue);
      expect(titles(), shown, reason: f);
    }
    // The section starts where every section does.
    final strip = tester.getRect(find.byKey(const ValueKey('portfolio-strip')));
    expect(
        tester
                .getRect(
                    find.byKey(const ValueKey('portfolio-activity-filters')))
                .top -
            strip.bottom,
        moreOrLessEquals(kPortfolioSectionEmptyTop.h, epsilon: 0.5));
    // The Bitcoin home's mechanism: Activity on screen, its pill reads
    // "→ See all" and opens the whole Investments activity.
    final pill = find.byKey(const ValueKey('portfolio-section-pill-activity'));
    expect(find.descendant(of: pill, matching: find.text('See all')),
        findsOneWidget);
    await tester.tap(pill);
    await _settle(tester);
    final screen = tester
        .widget<ActivityHistoryScreen>(find.byType(ActivityHistoryScreen));
    expect(screen.listedScope, ActivityScope.investments);
    expect(events.where((e) => e.$1 == 'activity_history_opened').single.$2,
        {'entry_source': 'portfolio', 'scope': 'investments'});
    await _unmount(tester);
  });

  testWidgets(
      'P&L: "You\'re up \$X" over the hero\'s range with the two rows that '
      'add up to it, "By product" as plain rows (no venue squares, no '
      'sparklines, no "All time" cards), no chart of its own; its headline '
      'where every section starts', (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        section: PortfolioSection.charts,
        size: const Size(390, 1400),
        extra: [..._history(), ..._predictionsBooked()]);
    expect(find.byType(KuteTrendChart), findsOneWidget, reason: 'the hero\'s');
    final head = find.byKey(const ValueKey('portfolio-pnl-headline'));
    expect(tester.widget<Text>(head).data, r"You're up $20.01");
    expect(_change(tester), startsWith(r'▲ $20.01'));
    double money(String key) {
      final t = tester
          .widget<Text>(find.descendant(
              of: find.byKey(ValueKey(key)),
              matching:
                  find.byKey(const ValueKey('portfolio-pnl-split-figure'))))
          .data!;
      final v = double.parse(t.replaceAll(RegExp(r'[^\d.]'), ''));
      return t.startsWith('−') ? -v : v;
    }

    expect(
        ((money('portfolio-pnl-closed') + money('portfolio-pnl-open')) * 100)
            .round(),
        2001);
    expect(find.byType(PnlVenueRow), findsNWidgets(2));
    expect(find.byKey(const ValueKey('pnl-venue-square')), findsNothing);
    expect(find.byKey(const ValueKey('pnl-sparkline')), findsNothing);
    expect(find.byKey(const ValueKey('pnl-venue-change')), findsNothing);
    expect(find.byKey(const ValueKey('statistics-pnl-all-time')), findsNothing);
    expect(find.text('All time'), findsNWidgets(1), reason: 'the period line');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('statistics-figures')),
            matching: find.byType(PortfolioCardList)),
        findsNothing,
        reason: 'the rows ARE the card');
    // The closed prediction (+$7.61, two days back) under "Closed
    // positions".
    final closed = find.byKey(const ValueKey('portfolio-closed'));
    expect(closed, findsOneWidget);
    expect(
        _rolling(
            tester,
            find.descendant(
                of: closed, matching: find.byType(PortfolioPositionRow)),
            'portfolio-row-value'),
        r'+$7.61');
    final strip = tester.getRect(find.byKey(const ValueKey('portfolio-strip')));
    expect(tester.getRect(head).top - strip.bottom,
        moreOrLessEquals(kPortfolioSectionEmptyTop.h, epsilon: 1));
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

  testWidgets('P&L with history: the first frame is the section',
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
      'Positions: the open positions under plain "Investing" and '
      '"Predictions" headings, biggest first, as the Activity tab\'s squares '
      '(an odd last one the wide card): the P&L in money over its %, the '
      'side first on the line under the name',
      (tester) async {
    await _mount(tester,
        state: _bothAtWork,
        size: const Size(390, 1400),
        trading: _btcHeld,
        extra: [
          ..._history(),
          ..._predictionsHistory(),
          ..._sized({'a': 2, 'b': 8, 'c': 4}),
        ]);
    expect(find.text('Investing'), findsOneWidget);
    expect(find.text('Predictions'), findsOneWidget);
    expect(find.textContaining('Investing ·'), findsNothing);
    expect(tester.getRect(find.text('Investing')).top,
        lessThan(tester.getRect(find.text('Predictions')).top));
    final investing =
        find.byKey(const ValueKey('portfolio-balance-investing-positions'));
    final predictions =
        find.byKey(const ValueKey('portfolio-balance-predictions-positions'));
    expect(find.descendant(of: investing, matching: find.byType(HlPositionRow)),
        findsOneWidget);
    final rows = find.descendant(
        of: predictions, matching: find.byType(PortfolioPositionRow));
    expect(rows, findsNWidgets(3));
    // Biggest first: b ($4.80), c ($2.40), a ($1.20).
    expect([
      for (var i = 0; i < 3; i++)
        _rolling(tester, rows.at(i), 'portfolio-row-value')
    ], [
      r'$4.80',
      r'$2.40',
      r'$1.20'
    ]);
    // The squares two by two, the odd third the wide card; one lone
    // Investing position the wide card too. Never a lone half square.
    expect(
        find.descendant(
            of: predictions,
            matching: find.byKey(const ValueKey('portfolio-square'))),
        findsNWidgets(2));
    expect(
        find.descendant(
            of: predictions,
            matching: find.byKey(const ValueKey('portfolio-wide'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: investing,
            matching: find.byKey(const ValueKey('portfolio-wide'))),
        findsOneWidget);
    // The P&L since each was opened: the money over its percent.
    expect(_rolling(tester, rows.at(0), 'portfolio-row-pnl-usd'), r'▲ $0.80');
    expect(_rolling(tester, rows.at(0), 'portfolio-row-pnl'), '20.0%');
    expect(
        tester
            .widget<RollingFigure>(find.descendant(
                of: rows.at(0),
                matching: find.byKey(const ValueKey('portfolio-row-pnl'))))
            .style
            .color,
        AppColors.marketUp);
    // The side first on the line under the name: No on b, Long on BTC
    // (with its size, as on the Activity tab's squares).
    String line(Finder of) => tester
        .widget<Text>(find.descendant(
            of: of,
            matching: find.byKey(const ValueKey('portfolio-row-subtitle'))))
        .data!;
    expect(line(rows.at(0)), startsWith('No'));
    expect(line(investing), 'Long · 0.1 BTC');
    expect(find.byType(HlMetaChip), findsNothing);
    // No leverage, no mark price, no chance bar on a square.
    expect(find.byKey(const ValueKey('portfolio-row-chance')), findsNothing);
    expect(find.textContaining('ROE'), findsNothing);
    await _unmount(tester);
  });

  group('P&L: a "By product" row picks what the hero shows', () {
    Finder row(String v) => find.byKey(ValueKey('pnl-venue-$v'));

    testWidgets(
        'a row tapped: the hero\'s line names that venue after its logo, its '
        'chart is that venue\'s, the total stays and "All" puts both back; '
        'the headline follows; one event each way', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _mount(tester,
          state: _bothAtWork,
          section: PortfolioSection.charts,
          size: const Size(390, 1400),
          fills: [
            _fill('BTC', const Duration(days: 10), 'Open Long'),
            _fill('BTC', const Duration(days: 3), 'Close Long'),
          ],
          extra: [
            ..._history(),
            ..._predictionsBooked()
          ]);
      final total = _figure(tester, 'portfolio-hero-value');
      await tester.tap(row('predictions'));
      await _settle(tester);
      expect(_change(tester), startsWith(r'Predictions · ▲ $7.61 · '));
      expect(find.byKey(const ValueKey('portfolio-hero-venue-logo')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('portfolio-hero-all')), findsOneWidget);
      expect(_figure(tester, 'portfolio-hero-value'), total);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('portfolio-pnl-headline')))
              .data,
          r"You're up $7.61");
      expect(tester.widget<PnlVenueRow>(row('investing')).dimmed, isTrue);
      await tester.tap(find.byKey(const ValueKey('portfolio-hero-all')));
      await _settle(tester);
      expect(_change(tester), startsWith(r'▲ $20.01'));
      expect(find.byKey(const ValueKey('portfolio-hero-all')), findsNothing);
      expect(
          events
              .where((e) => e.$1 == 'portfolio_statistics_venue_toggled')
              .map((e) => e.$2),
          [
            {'venue': 'polymarket'},
            {'venue': 'all'}
          ]);
      await _unmount(tester);
    });

    testWidgets('leaving P&L drops the pick: the hero is both venues again',
        (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          section: PortfolioSection.charts,
          size: const Size(390, 1400),
          fills: [
            _fill('BTC', const Duration(days: 10), 'Open Long'),
            _fill('BTC', const Duration(days: 3), 'Close Long'),
          ],
          extra: [
            ..._history(),
            ..._predictionsBooked()
          ]);
      await tester.tap(row('investing'));
      await _settle(tester);
      expect(_change(tester), startsWith('Investing · '));
      await _pick(tester, PortfolioSection.activity);
      await _settle(tester);
      expect(_change(tester), startsWith(r'▲ $20.01'));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(PortfolioHeroChart)));
      expect(container.read(portfolioPnlVenueProvider), isNull);
      await _unmount(tester);
    });
  });

  test('the pick goes with the screen: with nothing watching it, both again',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(portfolioPnlVenueProvider, (_, __) {});
    container.read(portfolioPnlVenueProvider.notifier).state =
        PortfolioPerformanceVenue.trading;
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(portfolioPnlVenueProvider), isNull);
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
      final card = switch (section) {
        PortfolioSection.activity => find.byType(ActivityDaySection).last,
        PortfolioSection.balances =>
          find.byKey(const ValueKey('portfolio-balance-predictions-positions')),
        PortfolioSection.charts =>
          find.byKey(const ValueKey('statistics-figures')),
      };
      final last = switch (section) {
        PortfolioSection.balances => find.byType(PortfolioPositionRow).last,
        _ => card,
      };
      expect(last, findsOneWidget);
      final bar = size.height - kuteBarScrollClearance * size.height / 932;
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(bar + 0.5),
          reason: 'the last row under the bar');
      // The cards' 16 inset; the squares' own 14.
      final inset = (section == PortfolioSection.balances ? 14 : 16) *
          size.width /
          430;
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
          extra: [..._history(), ..._predictionsBooked(), ..._manyRows()]);
      expect(tester.takeException(), isNull);
      final gutter = 16 * width / 430;
      void inGutters(List<String> keys) {
        for (final key in keys) {
          final r = tester.getRect(find.byKey(ValueKey(key)));
          expect(r.left, greaterThanOrEqualTo(gutter - 0.5), reason: key);
          expect(r.right, lessThanOrEqualTo(width - gutter + 0.5), reason: key);
        }
      }

      void cardsInGutters(List<Finder> cards, {double? pad}) {
        for (final card in cards) {
          final r = tester.getRect(card);
          expect(r.left, moreOrLessEquals(gutter, epsilon: 0.5));
          expect(r.right, moreOrLessEquals(width - gutter, epsilon: 0.5));
          for (final e in find
              .descendant(of: card, matching: find.byType(Text))
              .evaluate()) {
            expect(tester.getRect(find.byWidget(e.widget)).right,
                lessThanOrEqualTo(r.right - (pad ?? gutter) + 0.5),
                reason: (e.widget as Text).data);
          }
        }
      }

      inGutters(const [
        'portfolio-hero-value',
        'portfolio-hero-change',
        'portfolio-hero-line',
        'portfolio-hero-chart',
      ]);
      // The squares stand on the gutters, their text inside their own 14.
      cardsInGutters([
        find.byKey(const ValueKey('portfolio-balance-predictions-positions')),
      ], pad: 14 * width / 430);
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      cardsInGutters([
        find.byKey(const ValueKey('portfolio-pnl-split')),
        find.byKey(const ValueKey('statistics-figures')),
      ]);
      // A venue picked: its logo and name in the line, "All" beside the
      // total, all of it inside the gutters.
      await tester.tap(find.byKey(const ValueKey('pnl-venue-predictions')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      inGutters(const [
        'portfolio-hero-value',
        'portfolio-hero-change',
        'portfolio-hero-venue-logo',
        'portfolio-hero-all',
        'portfolio-hero-chart',
      ]);
      await _unmount(tester);
    });
  }

  group(
      'the hero on P&L and Activity: the account\'s P&L from the whole P&L '
      'engine, realised steps and each position from its own entry, under '
      'the venue\'s own figures', () {
    final now = DateTime.now();
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    HlFill fill(String coin, double px, double sz, String side, Duration at,
            double start, String dir) =>
        HlFill(
          coin: coin,
          px: px,
          sz: sz,
          side: side,
          time: ago(at),
          closedPnl: 0,
          fee: coin == 'ETH' ? 0.5 : 0,
          feeToken: 'USDC',
          oid: at.inMinutes,
          hash: '0x$coin-${at.inMinutes}',
          dir: dir,
          cloid: null,
          startPosition: start,
        );

    /// BTC long 0.1 at 60,000 six days back, held; ETH 1 bought at 2,000
    /// five days back and sold at 2,100 four days back ($0.50 fee each:
    /// +$99 realised).
    final fills = [
      fill('BTC', 60000, 0.1, 'B', const Duration(days: 6), 0, 'Open Long'),
      fill('ETH', 2000, 1, 'B', const Duration(days: 5), 0, 'Open Long'),
      fill('ETH', 2100, 1, 'A', const Duration(days: 4), 1, 'Close Long'),
    ];

    /// BTC's candles at 60,004 (+$0.40 on 0.1), ETH's at 2,050 (+$50 on
    /// 1 while held); [btc] false: BTC's cannot be read.
    OpenPnlSources sources({bool btc = true}) => OpenPnlSources(
          activity: (_) async => const [],
          candles: (_, wire, interval, window) async {
            if (wire == 'BTC' && !btc) return null;
            final px = wire == 'BTC' ? 60004.0 : 2050.0;
            return [
              for (var t = now.subtract(window);
                  t.isBefore(now);
                  t = t.add(const Duration(hours: 1)))
                HyperliquidCandle(
                    openTime: t,
                    closeTime: t.add(const Duration(hours: 1)),
                    open: px,
                    high: px,
                    low: px,
                    close: px,
                    volume: 1),
            ];
          },
          polyHistory: (_, __, ___) async => null,
        );

    /// The venue's own P&L: $1.00 twenty days back that no fill carries
    /// (funding, say), then everything: $100.40 two days back and now.
    List<Override> venue() => [
          portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                  venue: PortfolioPerformanceVenue.trading))
              .overrideWith((_) async =>
                  _perf([(30, 0.0), (20, 1.0), (2, 100.4)], 'Hyperliquid')),
        ];

    KuteTrendChart chart(WidgetTester tester) => tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('portfolio-hero-chart')));

    String line(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan!
        .toPlainText();

    for (final section in const [
      PortfolioSection.activity,
      PortfolioSection.charts,
    ]) {
      testWidgets(
          '${section.key}: the venue\'s figure before the fills, then BTC '
          'from its entry, ETH marked while held and its +\$99 realised at '
          'its sale, the last point the P&L now; the dashed line at zero',
          (tester) async {
        await _mount(tester,
            state: _bothAtWork,
            section: section,
            trading: _btcHeld,
            fills: fills,
            size: const Size(390, 1600),
            sources: sources(),
            extra: venue());
        final c = chart(tester);
        // The past month (the start) reaches past the history (the venue's
        // first P&L twenty days back): ALL, the whole line from its short
        // lead-in, zero then; the row offers 1W and ALL.
        expect(c.rangeLabels, ['1W', 'ALL']);
        expect(c.selectedRange, 1);
        expect(c.times!.first.isBefore(now.subtract(const Duration(days: 20))),
            isTrue);
        expect(c.times!.first.isAfter(now.subtract(const Duration(days: 23))),
            isTrue);
        expect(c.values.first, 0);
        expect(c.values.last, closeTo(100.4, 1e-9));
        for (var i = 0; i < c.values.length - 1; i++) {
          final t = c.times![i];
          final expected = t.isBefore(now.subtract(const Duration(days: 20)))
              ? 0.0
              : t.isBefore(now.subtract(const Duration(days: 6)))
                  ? 1.0
                  : t.isBefore(now.subtract(const Duration(days: 5)))
                      ? 1.4
                      : t.isBefore(now.subtract(const Duration(days: 4)))
                          // ETH held: +$50 at 2,050, its $0.50 fee paid.
                          ? 1.4 + 49.5
                          : 1.4 + 99;
          expect(c.values[i], closeTo(expected, 1e-9), reason: '$t');
        }
        expect(c.baseline, 0);
        expect(c.zeroSplit, isTrue);
        expect(c.lineColor, AppColors.marketUp);
        // ALL's P&L: all of it, live less the window's start (zero).
        expect(line(tester), startsWith(r'▲ $100.40 · All time'));
        expect(find.byKey(const ValueKey('portfolio-hero-left-out')),
            findsNothing);

        // The past week: from its start (the $1.00 then) to now.
        await tester.tap(find.descendant(
            of: find.byKey(const ValueKey('portfolio-hero-chart')),
            matching: find.text('1W')));
        await _settle(tester);
        expect(chart(tester).selectedRange, 0);
        expect(line(tester), startsWith(r'▲ $99.40 · Past week'));
        expect(chart(tester).values.last, closeTo(100.4, 1e-9));
        await _unmount(tester);
      });
    }

    testWidgets(
        'the row offers what the history has (a hundred days: 1W 1M 3M '
        'ALL, 1Y not); every pill a window of its own, its P&L the P&L now '
        'less the window\'s start, ALL all of it', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          section: PortfolioSection.charts,
          trading: _btcHeld,
          fills: fills,
          size: const Size(390, 1600),
          sources: sources(),
          extra: [
            portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                    venue: PortfolioPerformanceVenue.trading))
                .overrideWith((_) async =>
                    _perf([(120, 0.0), (100, 1.0), (2, 100.4)], 'Hyperliquid')),
          ]);
      var c = chart(tester);
      expect(c.rangeLabels, ['1W', '1M', '3M', 'ALL']);
      // The month to start: offered here.
      expect(c.selectedRange, 1);
      expect(line(tester), startsWith(r'▲ $99.40 · Past month'));
      final firsts = <String, DateTime>{};
      for (final (label, period) in const [
        ('3M', 'Past 3 months'),
        ('1W', 'Past week'),
        ('ALL', 'All time'),
        ('1M', 'Past month'),
      ]) {
        await tester.tap(find.descendant(
            of: find.byKey(const ValueKey('portfolio-hero-chart')),
            matching: find.text(label)));
        await _settle(tester);
        c = chart(tester);
        expect(c.rangeLabels![c.selectedRange], label);
        expect(c.values.last, closeTo(100.4, 1e-9), reason: label);
        firsts[label] = c.times!.first;
        // The P&L over the window: the figure now less its first point
        // (ALL's is the lead-in at zero: all of it).
        final pnl = (100.4 - c.values.first).toStringAsFixed(2);
        expect(line(tester), startsWith('▲ \$$pnl · $period'), reason: label);
        if (label == 'ALL') {
          expect(c.values.first, 0);
          expect(
              c.times!.first.isBefore(now.subtract(const Duration(days: 100))),
              isTrue);
        } else {
          expect(c.values.first, closeTo(1, 1e-9), reason: label);
        }
      }
      expect(firsts.values.toSet(), hasLength(4),
          reason: 'every pill a window of its own');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('portfolio-hero-chart')),
              matching: find.text('1Y')),
          findsNothing);
      await _unmount(tester);
    });

    testWidgets(
        'a position held whose prices cannot be read: its realised steps '
        'stay, its swings are left out and said so; the last point is still '
        'the P&L now', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          section: PortfolioSection.activity,
          trading: _btcHeld,
          fills: fills,
          size: const Size(390, 1600),
          sources: sources(btc: false),
          extra: venue());
      expect(chart(tester).values.last, closeTo(100.4, 1e-9));
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('portfolio-hero-left-out')))
              .data,
          '1 position not charted (history unavailable)');
      await _unmount(tester);
    });

    testWidgets(
        'a "By product" row picked: the hero draws that venue\'s engine '
        'line, and the row says the hero\'s own range P&L', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          section: PortfolioSection.charts,
          trading: _btcHeld,
          fills: fills,
          size: const Size(390, 1600),
          sources: sources(),
          extra: [...venue(), ..._predictionsBooked()]);
      await tester.tap(find.byKey(const ValueKey('pnl-venue-investing')));
      await _settle(tester);
      expect(chart(tester).values.last, closeTo(100.4, 1e-9));
      // The month (the start) reaches past its twenty days: ALL.
      expect(line(tester), contains(r'▲ $100.40 · All time'));
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('pnl-venue-investing')),
                  matching: find.byKey(const ValueKey('pnl-venue-figure'))))
              .data,
          r'+$100.40');
      await _unmount(tester);
    });
  });

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
        'a switch keeps the hero where it is (one hero, the same height on '
        'every section): half scrolled stays half scrolled; scrolled past '
        'the pin, the strip stays pinned and the next section opens at its '
        'top', (tester) async {
      await _mount(tester,
          state: _bothAtWork,
          size: size,
          textScale: 1.3,
          trading: _btcHeld,
          extra: [..._history(), ..._predictionsHistory(), ..._manyRows()]);
      final pin = stripTop(tester);
      position(tester).jumpTo(40);
      await _settle(tester);
      final heroAt = tester.getRect(hero);
      final stripAt = stripTop(tester);
      for (final s in [PortfolioSection.charts, PortfolioSection.balances]) {
        await _pick(tester, s);
        await _settle(tester);
        expect(tester.getRect(hero), heroAt, reason: '$s');
        expect(stripTop(tester), moreOrLessEquals(stripAt, epsilon: 0.01));
      }

      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      expect(position(tester).pixels, greaterThan(pin));
      await _pick(tester, PortfolioSection.charts);
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      heroAway(tester);
      // The next section at its top: the pin.
      expect(position(tester).pixels, moreOrLessEquals(pin, epsilon: 0.5));

      // Scrolled down P&L, back to Positions: the strip stays pinned and
      // Positions opens at its top.
      await tester.drag(_pageScroll, const Offset(0, -3000));
      await _settle(tester);
      await _pick(tester, PortfolioSection.balances);
      await _settle(tester);
      expect(stripTop(tester), moreOrLessEquals(0, epsilon: 0.5));
      expect(position(tester).pixels, moreOrLessEquals(pin, epsilon: 0.5));
      expect(find.byKey(const ValueKey('portfolio-balance-venue-investing')),
          findsOneWidget);
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
