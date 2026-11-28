// The detail pages across the window (round three; founder, 25 November
// 2026: "it must be all occupying full screen when we can"): a position
// (Predictions and Investing) and a combo as two panes on EXPANDED, the
// dial / chart / summary on the left, the tiles, cards and rows on the
// right at a readable width. Checked for stretch at every EXPANDED size;
// shot when asked: DESK_FULL_RENDER=<dir>.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlCandleChart;
import 'package:kute/screens/polymarket/components/combo_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/balance_privacy.dart';
import 'desk_full_support.dart';

/// How the routes frame these pages on EXPANDED (position_detail_sheet,
/// hl_position_detail_sheet, combo_detail_sheet: `wide:` on their
/// KuteSheetPageRoute).
const KuteWideMode _mode = KuteWideMode.full;

// ── Predictions ───────────────────────────────────────────────────────

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

/// 50 Lula Yes shares bought at 34¢, now 41%.
const _lula = PolymarketPosition(
  marketId: 'm-lula',
  marketQuestion: 'Will Lula win the 2026 Brazilian presidential election?',
  outcome: 'Yes',
  size: 50,
  avgPrice: 0.34,
  currentPrice: 0.41,
  pnl: 3.5,
  pnlPercent: 20.6,
  isResolved: false,
  tokenId: 'lula-yes',
  eventSlug: 'brazil-election-2026',
);

final _election = PolymarketEvent(
  id: 'e-br',
  slug: 'brazil-election-2026',
  title: 'Brazil Presidential Election',
  volume: 1000,
  liquidity: 1000,
  category: 'politics',
  conditionId: 'c-br',
  description: 'This market resolves to the candidate who wins the 2026 '
      'Brazilian presidential election, as called by the TSE.',
  outcomes: const [
    PolymarketOutcome(
        gammaMarketId: 'm-lula',
        name: 'Lula',
        price: 0.41,
        tokenId: 'lula-yes'),
    PolymarketOutcome(
        gammaMarketId: 'm-tar',
        name: 'Tarcísio',
        price: 0.31,
        tokenId: 'tar-yes'),
    PolymarketOutcome(
        gammaMarketId: 'm-fla',
        name: 'Flávio',
        price: 0.19,
        tokenId: 'fla-yes'),
  ],
);

List<Override> _polyOverrides() => [
      balancePrivacyOverride(0),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(_NoTrading.new),
      polymarketEventDetailsProvider('brazil-election-2026')
          .overrideWith((ref) async => _election),
      polyPositionJourneyProvider.overrideWith((ref, key) async => null),
    ];

// ── Investing ─────────────────────────────────────────────────────────

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}

const _btcPosition = HlPerpPosition(
  coin: 'BTC',
  szi: 0.5,
  entryPx: 64000,
  positionValue: 33000,
  unrealizedPnl: 1000,
  returnOnEquity: 0.156,
  liquidationPx: 58000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
  fundingSinceOpen: 1.25,
);

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

final _candles = [
  for (var i = 0; i < 120; i++)
    HyperliquidCandle(
      openTime: DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
      closeTime: DateTime.utc(2026, 10, 1).add(Duration(hours: i + 1)),
      open: 64000.0 + i * 15 + (i % 7) * 40,
      high: 64150.0 + i * 15 + (i % 7) * 40,
      low: 63900.0 + i * 15 + (i % 5) * 30,
      close: 64050.0 + i * 15 + (i % 6) * 35,
      volume: 10,
    ),
];

List<Override> _hlOverrides() => [
      balancePrivacyOverride(0),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => _btc),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => _btc),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidOrderbookProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidPerpPositionsProvider.overrideWith((ref) => [_btcPosition]),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidLiveCandlesProvider.overrideWith(
          (ref, key) => Stream.value(HlLiveCandlesState(candles: _candles))),
      hyperliquidTradeFlowProvider
          .overrideWith((ref, coin) => Stream.value(const HlTradeFlowState())),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

// ── Combo ─────────────────────────────────────────────────────────────

ComboLeg _leg(int i, String title, String status, double price) => ComboLeg(
    index: i,
    positionId: '$i',
    outcomeIndex: 0,
    outcomeLabel: 'Yes',
    status: status,
    currentPrice: price,
    title: title,
    question: '$title?');

final _combo = ComboPosition(
    conditionId: 'combo-1',
    positionId: 'combo-1',
    outcomeIndex: 0,
    shares: 40,
    entryAvgPrice: 0.25,
    stakeUsd: 10,
    entryFeesUsd: 0,
    realizedPayoutUsd: 0,
    status: 'OPEN',
    redeemable: false,
    legsTotal: 4,
    legsResolved: 1,
    legsPending: 3,
    legs: [
      _leg(0, 'Lakers beat the Celtics', 'RESOLVED_WIN', 1),
      _leg(1, 'Bitcoin above \$100k on December 31', 'OPEN', 0.62),
      _leg(2, 'Fed cuts rates in December', 'OPEN', 0.71),
      _leg(3, 'Arsenal win the Premier League', 'OPEN', 0.48),
    ]);

class _Combos extends PolymarketCombosNotifier {
  @override
  Future<PolymarketCombosState> build() async =>
      PolymarketCombosState(positions: [_combo], loaded: true);

  /// The close sheet's quote, never answered here (it shows its wait).
  @override
  Future<ComboQuote> quoteClose(ComboPosition position) =>
      Completer<ComboQuote>().future;
}

List<Override> _comboOverrides() => [
      balancePrivacyOverride(0),
      polymarketCombosProvider.overrideWith(_Combos.new),
      comboEstimateSeriesProvider('combo-1').overrideWith((ref) async => [
            for (var i = 0; i < 60; i++)
              PolymarketPricePoint(
                  timestamp:
                      DateTime.utc(2026, 11, 17).add(Duration(hours: i * 3)),
                  price: 8 + i * 0.12 + (i % 5) * 0.4),
          ]),
    ];

// ── Pages ─────────────────────────────────────────────────────────────

typedef _Page = (String, Widget Function(), List<Override> Function());

final List<_Page> _pages = [
  (
    'poly_position',
    () => const PositionDetailSheet(position: _lula),
    _polyOverrides
  ),
  (
    'hl_position',
    () => const HlPositionDetailSheet(position: _btcPosition, market: _btc),
    _hlOverrides
  ),
  (
    'combo',
    () => const ComboDetailSheet(conditionId: 'combo-1'),
    _comboOverrides
  ),
];

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    PolyDialDragMemory.debugReset();
    OpenOnce.reset();
    KuteSideFlow.reset();
  });

  for (final (name, page, overrides) in _pages) {
    for (final (label, size) in deskFullExpanded) {
      testWidgets('$name at $label: two panes, nothing stretched',
          (tester) async {
        await pumpDeskPage(tester,
            size: size,
            dark: false,
            page: page(),
            mode: _mode,
            overrides: overrides());
        expect(tester.takeException(), isNull);
        expectDeskNothingStretched(tester,
            maxCard: kuteWideColumnMax,
            // The chart is meant to span its pane.
            allow: [find.byType(HlCandleChart)]);
        await deskFullEnd(tester);
      });
    }
  }

  for (final (name, page, overrides) in _pages) {
    for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: $name $label $mode', skip: deskFullDir == null,
            (tester) async {
          await deskFullAssets(tester);
          await pumpDeskPage(tester,
              size: size,
              dark: dark,
              page: page(),
              mode: _mode,
              overrides: overrides());
          await deskFullShoot(tester, '${name}_${label}_$mode');
          await deskFullEnd(tester);
        });
      }
    }
  }

  // ON A LAPTOP EVERY ACTION OF A PREDICTIONS POSITION OR COMBO PAGE IS A
  // SIDE PANEL (founder, 25 November 2026: "these ones also be side
  // bars"): Sell, Details, Close combo open at the window's right edge,
  // full height, over the page's right pane; the page stays under them.
  final actions = <(String, int, Finder Function())>[
    ('poly_position_sell', 0, () => find.byType(KuteBarPrimaryButton)),
    ('poly_position_details', 0,
        () => find.byKey(PositionDetailSheet.detailsRowKey)),
    ('combo_close', 2, () => find.byType(KuteBarPrimaryButton)),
  ];
  for (final (name, index, target) in actions) {
    final (_, page, overrides) = _pages[index];
    for (final (label, size) in const [
      ('1440x900', Size(1440, 900)),
      ('1000x700', Size(1000, 700)),
    ]) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('$name $label $mode: a side panel over the page',
            (tester) async {
          await deskFullAssets(tester);
          await pumpDeskPage(tester,
              size: size,
              dark: dark,
              page: page(),
              mode: _mode,
              overrides: overrides());
          await tester.tap(target().first, warnIfMissed: false);
          await deskFullFrames(tester, 8);
          expect(tester.takeException(), isNull);
          final panel =
              tester.getRect(find.byKey(const ValueKey('kute-dialog-card')));
          expect(panel.right, size.width);
          expect(panel.top, 0);
          expect(panel.bottom, size.height);
          expect(panel.width, kuteSidePanelWidth);
          // The page is still there, under the panel.
          expect(find.byType(page().runtimeType), findsOneWidget);
          await deskFullShoot(tester, '${name}_${label}_$mode');
          KuteSideFlow.reset();
          await deskFullEnd(tester);
        });
      }
    }
  }
}
