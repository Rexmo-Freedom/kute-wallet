// The Portfolio screen's bar shares what the section shows (founder, 2
// November 2026: "On share and brag portfolio we should say share
// portfolio on the bottom. PnL should say [something else]"): "Share
// portfolio" on Activity and Positions, "Share P&L" on P&L, the label
// morphing on a switch like every bar label; "Share P&L" opens the P&L
// card for the range picked on the hero's chart, and `brag_shared` says
// which card and which range. "Share portfolio" opens the portfolio card
// with its holdings (founder, 7 November 2026: "how much i made on
// each?"): the three open positions with the largest P&L either way,
// each figure the Portfolio's own row's, "+N more" for the rest, the real
// amounts whatever the hide-balances setting (as the card's hero).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show HyperliquidTradingState;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioPnlTone, PortfolioPositionRow;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart'
    show BragPortfolio, bragTopHoldings;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/pnl_share_card.dart';
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/portfolio_overrides.dart';

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// Both venues' P&L: Investing a year and a half of it, Predictions a
/// month and a half.
List<Override> _history() {
  final now = DateTime.now().toUtc();
  PortfolioPerformance perf(List<(int, double)> points, String source) =>
      PortfolioPerformance(
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
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf([
              (540, 0),
              (300, 40),
              (200, -12),
              (60, 22),
              (22, -4),
              (8, 3.2),
              (1, 12.4)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith(
            (_) async => perf([(45, 0), (20, 2.5), (2, 7.61)], 'Polymarket')),
  ];
}

/// [_history] with Predictions' book (one prediction closed for +$7.61),
/// so its venue square has figures and can be picked.
List<Override> _historyBooked() {
  final now = DateTime.now().toUtc();
  return [
    _history().first,
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
                    coverageLabel: 'All time')
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

/// Nothing ever traded at either venue.
List<Override> _none() => [
      for (final v in PortfolioPerformanceVenue.values)
        portfolioPerformanceProvider(PortfolioPerformanceRequest(venue: v))
            .overrideWith((_) async => kPortfolioNoPerformance),
    ];

/// The live prices, quiet: no socket, the prices given.
class _Prices extends LivePriceNotifier {
  _Prices(this.prices);
  final Map<String, double> prices;
  @override
  LivePriceState build() => LivePriceState(live: true, prices: prices);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

/// Five open positions: Anthropic short +$2.61 and Ethereum long +$0.84
/// (on $40 of margin each); Fed No −$1.12, Lakers Yes +$0.20 and
/// Verstappen +$0.10 at the live prices (each list price stale, so a card
/// on the list price would differ from the Portfolio's rows).
const _perpCoins = ['ANTH', 'ETH'];
const _fivePredictions = [
  // (token, question, outcome, size, avg, list price, live price)
  ('fed-no', 'Fed cuts rates in December?', 'No', 10.0, 0.5, 0.45, 0.388),
  (
    'lakers-yes',
    'Will the Lakers win the 2026 NBA Finals?',
    'Yes',
    4.0,
    0.25,
    0.2,
    0.3
  ),
  ('f1-ver', 'F1 Drivers Champion 2026', 'Verstappen', 2.0, 0.3, 0.4, 0.35),
];

List<Override> _holdings() => [
      polymarketActivePositionsProvider.overrideWith((_) => [
            for (final (token, q, outcome, size, avg, list, _)
                in _fivePredictions)
              PolymarketPosition(
                  marketId: token,
                  marketQuestion: q,
                  outcome: outcome,
                  size: size,
                  avgPrice: avg,
                  currentPrice: list,
                  pnl: 0,
                  pnlPercent: 0,
                  isResolved: false,
                  tokenId: token),
          ]),
      livePriceProvider.overrideWith(() => _Prices({
            for (final (token, _, _, _, _, _, live) in _fivePredictions)
              token: live
          })),
      for (final coin in _perpCoins) ...[
        hyperliquidLiveMidProvider(coin).overrideWith((_) => null),
        hyperliquidAccountMarketProvider(coin).overrideWith((_) => null),
      ],
    ];

/// The two perps, isolated, $40 of margin each.
const _fiveTrading = HyperliquidTradingState(isInitialized: true, positions: [
  HlPerpPosition(
      coin: 'ANTH',
      szi: -0.5,
      entryPx: 240,
      positionValue: 122.61,
      unrealizedPnl: 2.61,
      returnOnEquity: 0.06525,
      liquidationPx: null,
      marginUsed: 42.61,
      leverageType: 'isolated',
      leverageValue: 3,
      maxLeverage: 10),
  HlPerpPosition(
      coin: 'ETH',
      szi: 0.01,
      entryPx: 3000,
      positionValue: 30.84,
      unrealizedPnl: 0.84,
      returnOnEquity: 0.021,
      liquidationPx: null,
      marginUsed: 40.84,
      leverageType: 'isolated',
      leverageValue: 3,
      maxLeverage: 10),
]);

Future<void> _mount(WidgetTester tester,
    {required List<Override> extra,
    HyperliquidTradingState trading = const HyperliquidTradingState(),
    int balancePrivacy = 0}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1400) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(trading: trading),
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
          balancePrivacy: balancePrivacy,
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
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        builder: withKuteShellBar,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PortfolioScreen(),
      ),
    ),
  ));
  await _settle(tester);
}

/// Sal loops: a fixed run of frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pick(WidgetTester tester, PortfolioSection section) async {
  await tester
      .tap(find.byKey(ValueKey('portfolio-section-pill-${section.key}')));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late List<(String, Map<String, Object>?)> events;
  setUp(() {
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    BragPreviewSheet.debugSharer = null;
    BragPreviewSheet.debugLineSeed = null;
  });

  testWidgets(
      'the bar says "Share portfolio" on Positions and Activity and "Share '
      'P&L" on P&L, the words morphing on the switch, the same button',
      (tester) async {
    await _mount(tester, extra: _history());
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(find.text('Share and brag'), findsNothing);
    final button = tester.state(find.byType(KuteBarPrimaryButton));

    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-morph: the old words on their way out, the new ones rising, in
    // the bar's one morph (KuteMorphLabel), on the same button.
    expect(find.byType(KuteMorphLabel), findsWidgets);
    expect(kuteBarPrimaryWithText('Share P&L'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(tester.state(find.byType(KuteBarPrimaryButton)), same(button));
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share P&L'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsNothing);

    await _pick(tester, PortfolioSection.balances);
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    await _pick(tester, PortfolioSection.activity);
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share P&L'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('nothing ever traded: the default bar on every section',
      (tester) async {
    await _mount(tester, extra: _none());
    expect(kuteBarPrimary, findsNothing);
    for (final s in [PortfolioSection.charts, PortfolioSection.activity]) {
      await _pick(tester, s);
      await _settle(tester);
      expect(kuteBarPrimary, findsNothing, reason: '$s');
    }
    expect(find.text('Share P&L'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      '"Share P&L" opens the P&L card for the range picked on the hero '
      '(3M): the hero\'s P&L, the range, its line; Share sends card pnl and '
      'the range', (tester) async {
    BragPreviewSheet.debugLineSeed = 0;
    final sent = <String>[];
    BragPreviewSheet.debugSharer = (_, text) async => sent.add(text);
    await _mount(tester, extra: _history());
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    // Ten months of history (Investing's first P&L 300 days back): 1Y
    // would draw all of it, ALL's window, so the row does not offer it.
    expect(find.text('1Y'), findsNothing);
    await tester.tap(find.text('3M'));
    await _settle(tester);
    // The hero's P&L over three months ("▲ $X · Past 3 months").
    final headline = tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan!
        .toPlainText()
        .split(' · ')
        .first;

    await tester.tap(kuteBarPrimary);
    await _settle(tester);
    final card = tester.widget<PnlShareCard>(find.byType(PnlShareCard));
    expect(card.data.range, BalanceRange.threeMonths);
    expect(card.data.venue, isNull);
    // The card's figure is the hero's, the range its pill's.
    expect(card.data.result!.text.replaceAll(RegExp(r'[^\d.,]'), ''),
        headline.replaceAll(RegExp(r'[^\d.,]'), ''));
    Finder onCard(Finder f) =>
        find.descendant(of: find.byType(PnlShareCard), matching: f);
    expect(onCard(find.text('MY P&L · 3M')), findsOneWidget);
    expect(onCard(find.text('Past 3 months')), findsOneWidget);
    expect(find.byKey(const ValueKey('pnl-card-chart')), findsOneWidget);
    expect(card.data.series, isNotNull);
    // The sheet's title and its own Share.
    expect(find.text('Share P&L'), findsWidgets);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(kuteBarPrimary);
      for (var i = 0; i < 100 && sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await _settle(tester);
    expect(sent.single, startsWith('My P&L on Kute '));
    expect(events.where((e) => e.$1 == 'brag_shared').map((e) => e.$2), [
      {'kind': 'portfolio', 'card': 'pnl', 'range': '3M'}
    ]);
    await _unmount(tester);
  });

  testWidgets(
      'a venue square picked: "Share P&L" opens that venue\'s card, its P&L '
      'the hero\'s; P&L left and opened again, both venues\' card',
      (tester) async {
    await _mount(tester, extra: _historyBooked());
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('pnl-venue-predictions')));
    await _settle(tester);
    // "Predictions · ▲ $X · All time": the month (the start) reaches past
    // the venue's three weeks of P&L, so the hero draws all of it, ALL lit.
    final parts = tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan!
        .toPlainText()
        .split(' · ');
    expect(parts.first, 'Predictions');
    final headline = parts[1];

    await tester.tap(kuteBarPrimary);
    await _settle(tester);
    var card = tester.widget<PnlShareCard>(find.byType(PnlShareCard));
    expect(parts.last, 'All time');
    expect(card.data.venue, PortfolioPerformanceVenue.predictions);
    // The card's range is the one the hero draws, its pill lit.
    expect(card.data.range, BalanceRange.all);
    expect(card.data.result!.text.replaceAll(RegExp(r'[^\d.,]'), ''),
        headline.replaceAll(RegExp(r'[^\d.,]'), ''));
    Navigator.of(tester.element(find.byType(PnlShareCard))).pop();
    await _settle(tester);

    // Away from P&L and back: the pick is gone, the card is both venues'.
    await _pick(tester, PortfolioSection.activity);
    await _settle(tester);
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    await tester.tap(kuteBarPrimary);
    await _settle(tester);
    card = tester.widget<PnlShareCard>(find.byType(PnlShareCard));
    expect(card.data.venue, isNull);
    await _unmount(tester);
  });

  /// Opens "Share portfolio" and returns the card's data.
  Future<BragPortfolio> openPortfolioCard(WidgetTester tester) async {
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    await tester.tap(kuteBarPrimary);
    await _settle(tester);
    return tester.widget<BragCard>(find.byType(BragCard)).data as BragPortfolio;
  }

  String? cardRow(WidgetTester tester, int i, String part) {
    final f = find.byKey(ValueKey('brag-card-top-$i-$part'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  testWidgets(
      '"Share portfolio": the three open positions with the largest P&L '
      'either way, each the figure its Portfolio row shows at the live '
      'price, "+2 more", and holdings_count 5 when shared', (tester) async {
    BragPreviewSheet.debugLineSeed = 0;
    BragPreviewSheet.debugSharer = (_, __) async {};
    await _mount(tester,
        trading: _fiveTrading, extra: [..._history(), ..._holdings()]);
    // What each of the Portfolio's own rows shows: its name and its P&L
    // in money (at the live price, not the stale list price).
    final rows = {
      for (final r in tester
          .widgetList<PortfolioPositionRow>(find.byType(PortfolioPositionRow)))
        r.title: (r.pnlAmount, r.pnl?.tone)
    };
    expect(rows, hasLength(5));
    // The Positions hero adds them up: the five at the live prices.
    expect(find.textContaining(r'$2.63', findRichText: true), findsWidgets);
    final data = await openPortfolioCard(tester);
    expect(data.openCount, 5);
    expect(data.top.map((p) => p.title),
        ['Anthropic', 'Fed cuts rates in December', 'Ethereum']);
    for (final (p, usd) in [
      for (final (i, usd) in const [2.61, -1.12, 0.84].indexed)
        (data.top[i], usd)
    ]) {
      expect(p.result.usd, closeTo(usd, 1e-9), reason: p.title);
    }
    // Each card row is its Portfolio row's own figure, with the sign.
    for (var i = 0; i < 3; i++) {
      final name = cardRow(tester, i, 'name')!;
      final (amount, tone) = rows[name]!;
      final sign = tone == PortfolioPnlTone.down ? '−' : '+';
      expect(cardRow(tester, i, 'pnl'), '$sign$amount', reason: name);
    }
    expect([
      for (var i = 0; i < 3; i++)
        (
          cardRow(tester, i, 'name'),
          cardRow(tester, i, 'side'),
          cardRow(tester, i, 'pnl')
        )
    ], [
      ('Anthropic', ' · Short', r'+$2.61'),
      ('Fed cuts rates in December', ' · No', '−\$1.12'),
      ('Ethereum', ' · Long', r'+$0.84'),
    ]);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('brag-card-more'))).data,
        '+2 more');
    // The ranking is the pure one.
    expect(bragTopHoldings(data.top).map((p) => p.title),
        data.top.map((p) => p.title));
    // Perps and predictions, never "stocks" or "shares".
    expect(
        find.descendant(
            of: find.byType(BragCard),
            matching: find.textContaining(
                RegExp(r'\bstocks?\b|\bshares\b', caseSensitive: false))),
        findsNothing);

    await tester.runAsync(() async {
      await tester.tap(kuteBarPrimary);
      for (var i = 0;
          i < 100 && !events.any((e) => e.$1 == 'brag_shared');
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await _settle(tester);
    expect(events.where((e) => e.$1 == 'brag_shared').map((e) => e.$2), [
      {'kind': 'portfolio', 'card': 'portfolio', 'holdings_count': 5}
    ]);
    await _unmount(tester);
  });

  testWidgets(
      'balances hidden: the card still shows the real amounts, the rows as '
      'the all-time figure (the share card never hides them)', (tester) async {
    await _mount(tester,
        trading: _fiveTrading,
        balancePrivacy: 2,
        extra: [..._history(), ..._holdings()]);
    final data = await openPortfolioCard(tester);
    final hero = tester
        .widget<Text>(find.byKey(const ValueKey('brag-card-number')))
        .data!;
    expect(hero, data.allTime!.text);
    expect(hero, contains(r'$'));
    expect(hero, isNot(contains('•')));
    expect(cardRow(tester, 0, 'pnl'), r'+$2.61');
    expect(cardRow(tester, 1, 'pnl'), '−\$1.12');
    expect(
        find.descendant(
            of: find.byType(BragCard), matching: find.textContaining('•')),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets('nothing open: the portfolio card lists no row, its line alone',
      (tester) async {
    await _mount(tester, extra: _history());
    final data = await openPortfolioCard(tester);
    expect(data.top, isEmpty);
    expect(data.openCount, 0);
    expect(find.byKey(const ValueKey('brag-card-rows')), findsNothing);
    expect(find.byKey(const ValueKey('brag-card-more')), findsNothing);
    expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
    await _unmount(tester);
  });
}
