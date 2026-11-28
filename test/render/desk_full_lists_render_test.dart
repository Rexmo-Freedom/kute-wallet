// The list pages across the window (round three; founder, 25 November
// 2026: "lots of screens are vertical only. It must be all occupying full
// screen when we can"): Activity, the prediction history, a market
// category, a match's markets (group landing), the Portfolio and a
// Ledger's portfolio, their rows and cards in columns on EXPANDED, never
// one row stretched across the window. Checked for stretch at every
// EXPANDED size; shot when asked: DESK_FULL_RENDER=<dir> (DESK_FULL_SUFFIX
// names a run, e.g. `_before`).

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/group_landing_screen.dart';
import 'package:kute/screens/polymarket/prediction_history_screen.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/investment_market_browser.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/offline_venue_overrides.dart';
import '../helpers/portfolio_overrides.dart';
import 'desk_full_support.dart';

final String _suffix = Platform.environment['DESK_FULL_SUFFIX'] ?? '';

// ── fixtures ──

final DateTime _now = DateTime.now();
DateTime _ago(int days, int minutes) =>
    DateTime(_now.year, _now.month, _now.day, 12)
        .subtract(Duration(days: days, minutes: minutes));

SparkTransaction _spark(String id, int sats, DateTime at,
        {TransactionType direction = TransactionType.received}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: direction,
      pending: false,
    );

UsdbTokenTransaction _dollars(String id,
        {required double usd,
        required breez.PaymentType type,
        required DateTime at}) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: type,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

const _titles = [
  'Will it rain in London tomorrow?',
  'Fed cuts rates in December?',
  'Bitcoin above \$120k on Friday?',
  'Lakers win the NBA title?',
  'Will Taylor Swift tour Asia in 2027?',
  'Apple releases a foldable iPhone?',
];

PolymarketTransaction _bet(String id, DateTime at,
        {int title = 0,
        String type = 'TRADE',
        String side = 'BUY',
        double usd = 5}) =>
    PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0x$title',
        type: type,
        size: usd * 2,
        usdcSize: usd,
        transactionHash: '0x$id',
        side: side,
        asset: 'yes$title',
        outcomeIndex: 0,
        title: _titles[title % _titles.length],
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

/// Nine days of a spending account: bitcoin in and out, dollars and
/// predictions, from one to six rows a day.
Transaction _history() {
  const perDay = [3, 6, 2, 4, 1, 5, 2, 3, 4];
  final spark = <SparkTransaction>[];
  final dollars = <UsdbTokenTransaction>[];
  final bets = <PolymarketTransaction>[];
  var n = 0;
  for (var d = 0; d < perDay.length; d++) {
    for (var i = 0; i < perDay[d]; i++) {
      final at = _ago(d, 37 * i + 5);
      switch (n++ % 4) {
        case 0:
          spark.add(_spark('rx$n', 12000 + 913 * n, at));
        case 1:
          spark.add(_spark('tx$n', 5400 + 321 * n, at,
              direction: TransactionType.sent));
        case 2:
          dollars.add(_dollars('usd$n',
              usd: 20.0 + n,
              type:
                  n.isEven ? breez.PaymentType.receive : breez.PaymentType.send,
              at: at));
        default:
          bets.add(_bet('bet$n', at, title: n, usd: 3.0 + n));
      }
    }
  }
  return Transaction(
    bitcoinTransactions: const [],
    sparkTransactions: spark,
    sparkUnclaimedDeposits: const [],
    usdbTokenTransactions: dollars,
    swapOrderTransactions: const [],
    polymarketTransactions: bets,
  );
}

/// A prediction history: two dozen bets placed and sold over two weeks.
Transaction _bets() => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: const [],
      sparkUnclaimedDeposits: const [],
      usdbTokenTransactions: const [],
      swapOrderTransactions: const [],
      polymarketTransactions: [
        for (var i = 0; i < 24; i++)
          _bet('h$i', _ago(i ~/ 3 + (i % 5 == 0 ? 1 : 0), 41 * i),
              title: i, side: i % 4 == 3 ? 'SELL' : 'BUY', usd: 2.5 + i),
      ],
    );

Settings _settings() => Settings(
    currency: 'USD',
    language: 'en',
    btcFormat: 'sats',
    backup: false,
    biometricsEnabled: false,
    bitcoinElectrumNode: '',
    nodeType: '',
    reviewDone: true,
    activeWalletId: 'spending',
    wallets: [WalletConfig(id: 'spending', name: 'Spending')]);

List<Override> _spending({Transaction? history, HyperliquidTradingState? hl}) =>
    [
      ...portfolioOverrides(
          history: history, trading: hl ?? const HyperliquidTradingState()),
      ...offlineVenueOverrides,
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      currentBtcUsdProvider.overrideWithValue(100000),
      polymarketOpenOrdersProvider.overrideWith((_) => Stream.value(const [])),
      polymarketOrderMetadataProvider.overrideWith((_) async => const {}),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
    ];

PolymarketEvent _event(int i) {
  final yesNo = i % 3 != 1;
  final names = ['Arsenal', 'Chelsea', 'Draw'];
  return PolymarketEvent(
    id: 'ev$i',
    slug: 'ev-$i',
    title: [
      'Arsenal vs Chelsea: both teams to score?',
      'Arsenal vs Chelsea',
      'Over 2.5 goals?',
      'Arsenal win by 2+?',
      'Corners over 9.5?',
      'First half winner',
      'Saka to score?',
      'Red card in the match?',
      'Over 3.5 goals?',
      'Chelsea clean sheet?',
      'Penalty awarded?',
      'Halftime: Arsenal lead?',
    ][i % 12],
    volume: 120000.0 + 9000 * i,
    liquidity: 50000,
    category: 'sports',
    tags: const [],
    endDate: _now.add(Duration(days: 3 + i)),
    conditionId: 'c$i',
    outcomes: yesNo
        ? [
            PolymarketOutcome(
                name: 'Yes',
                price: 0.2 + 0.05 * (i % 10),
                tokenId: 'y$i',
                conditionId: 'c$i'),
            PolymarketOutcome(
                name: 'No',
                price: 0.8 - 0.05 * (i % 10),
                tokenId: 'n$i',
                conditionId: 'c$i'),
          ]
        : [
            for (var k = 0; k < 3; k++)
              PolymarketOutcome(
                name: names[k],
                question: 'Will ${names[k]} win?',
                price: [0.46, 0.31, 0.23][k],
                tokenId: 'o$i$k',
                noTokenId: 'o$i${k}n',
                conditionId: 'c$i$k',
              ),
          ],
  );
}

final _events = [for (var i = 0; i < 12; i++) _event(i)];

HlPerpPosition _perp(String coin, double size, double px, double pnl) =>
    HlPerpPosition(
        coin: coin,
        szi: size,
        entryPx: px,
        positionValue: (size * px).abs(),
        unrealizedPnl: pnl,
        returnOnEquity: pnl / (size * px).abs(),
        liquidationPx: null,
        marginUsed: (size * px).abs(),
        leverageType: 'cross',
        leverageValue: 1,
        maxLeverage: 40);

final _perps = [
  _perp('BTC', 0.05, 96000, 120.5),
  _perp('ETH', 1.2, 3400, -42.1),
  _perp('SOL', 20, 180, 18.3),
  _perp('HYPE', 40, 28, 61.0),
  _perp('DOGE', 9000, 0.38, -7.4),
  _perp('AVAX', 30, 36, 4.2),
  _perp('LINK', 60, 18.5, -11.0),
  _perp('SUI', 400, 3.6, 22.9),
];

List<Override> _ledger() => [
      ...offlineVenueOverrides,
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      ledgerIdentityProvider('ledger-a').overrideWith((_) =>
          const LedgerIdentity(
              walletId: 'ledger-a',
              evmAddress: 'ledger-address',
              evmVerifiedAtMs: 1)),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      ledgerHlAccountProvider('ledger-a').overrideWith((_) async =>
          LedgerHlAccount(
              walletId: 'ledger-a',
              address: 'ledger-address',
              account: HlAccountSnapshot(
                  accountValue: 8000,
                  withdrawable: 1200,
                  totalMarginUsed: 6800,
                  positions: _perps,
                  spotBalances: const []),
              openOrders: const [],
              fills: const [])),
      ledgerPmAccountProvider('ledger-a').overrideWith((_) async =>
          const LedgerPmAccount(
              walletId: 'ledger-a', eoa: 'ledger-address', positions: [])),
      ledgerPmActivityProvider('ledger-a').overrideWith((_) async => [
            for (final tx in _bets().polymarketTransactions) tx.activity,
          ]),
      ledgerAccountActionsProvider
          .overrideWithValue(const LedgerAccountActions()),
      for (final venue in PortfolioPerformanceVenue.values)
        portfolioPerformanceProvider(
                PortfolioPerformanceRequest(venue: venue, walletId: 'ledger-a'))
            .overrideWith((_) async => kPortfolioNoPerformance),
    ];

/// The venues' P&L series, for the Portfolio's chart.
List<Override> _performance() {
  final now = DateTime.now().toUtc();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  PortfolioPerformance series(List<(int, double)> points) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(timestamp: ago(days), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          sourceLabel: '',
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async =>
            series([(40, -5), (30, 12), (20, 4), (10, 29), (2, 35)])),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => series([(20, 0), (8, 6), (1, 4)])),
  ];
}

// ── the pages ──

typedef _Page = ({
  String name,
  Widget Function() page,
  KuteWideMode mode,
  List<Override> Function() overrides,
  // A tap from the root page that pushes the page (it frames itself).
  String? tap,
});

/// The category page is pushed from a venue browser's pill (the browser
/// at a phone's width: the page under the pushed one is not checked).
Widget _browser() => Scaffold(
      body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 430,
              child: ListView(children: [
                InvestmentMarketBrowser<PolymarketEvent>(
                  product: 'predictions',
                  sections: [
                    InvestmentBrowseSection(
                        label: 'Premier League', markets: _events),
                    InvestmentBrowseSection(
                        label: 'Politics', markets: _events.take(3).toList()),
                  ],
                  cardBuilder: (event, onTap, inGroup) => PredictionBrowseCard(
                      event: event, onTap: onTap, inGroup: inGroup),
                  groups: (e) => polyCardGroups(e.title, e.outcomes),
                  groupRowIndent: polyGroupRowIndent,
                  groupDivider: polyGroupRowDivider,
                  onOpenMarket: (_) {},
                ),
              ]))),
    );

final List<_Page> _pages = [
  (
    name: 'activity',
    page: () => const ActivityHistoryScreen(),
    mode: KuteWideMode.full,
    overrides: () => _spending(history: _history()),
    tap: null,
  ),
  (
    name: 'activity_empty',
    page: () => const ActivityHistoryScreen(),
    mode: KuteWideMode.full,
    overrides: () => _spending(),
    tap: null,
  ),
  (
    name: 'prediction_history',
    page: () => const PredictionHistoryScreen(),
    mode: KuteWideMode.full,
    overrides: () => [
          ..._spending(),
          scopedTransactionsProvider.overrideWithValue(_bets()),
        ],
    tap: null,
  ),
  (
    name: 'category',
    page: _browser,
    mode: KuteWideMode.own,
    overrides: () => _spending(),
    tap: 'Premier League',
  ),
  (
    name: 'group_landing',
    page: () =>
        GroupLandingScreen.events(title: 'Arsenal vs Chelsea', events: _events),
    mode: KuteWideMode.full,
    overrides: () => _spending(),
    tap: null,
  ),
  (
    name: 'portfolio',
    page: () => const OpenInvestmentsScreen(source: 'home'),
    mode: KuteWideMode.full,
    overrides: () => [
          ..._spending(
              history: _history(),
              hl: HyperliquidTradingState(
                  isInitialized: true, positions: _perps)),
          ..._performance(),
          for (final p in _perps) ...[
            hyperliquidLiveMidProvider(p.coin).overrideWith((_) => null),
            hyperliquidAccountMarketProvider(p.coin).overrideWith((_) => null),
          ],
        ],
    tap: null,
  ),
  (
    name: 'ledger_activity',
    page: () => const LedgerPortfolioScreen(
        walletId: 'ledger-a',
        product: InvestmentsProduct.predictions,
        initialTab: 2),
    mode: KuteWideMode.full,
    overrides: _ledger,
    tap: null,
  ),
  (
    name: 'ledger_portfolio',
    page: () => const LedgerPortfolioScreen(
        walletId: 'ledger-a', product: InvestmentsProduct.trading),
    mode: KuteWideMode.full,
    overrides: _ledger,
    tap: null,
  ),
];

Future<void> _pumpPage(WidgetTester tester, _Page p,
    {required Size size, required bool dark}) async {
  await pumpDeskPage(tester,
      size: size,
      dark: dark,
      page: p.page(),
      mode: p.mode,
      overrides: p.overrides());
  if (p.tap != null) {
    await tester.tap(find.text(p.tap!).first);
    await deskFullFrames(tester, 12);
  }
}

void main() {
  late Directory hiveDir;
  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('desk_full_lists');
    Hive.init(hiveDir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  for (final p in _pages) {
    for (final (label, size) in deskFullExpanded) {
      testWidgets('${p.name} at $label: columns, nothing stretched',
          (tester) async {
        await _pumpPage(tester, p, size: size, dark: false);
        expect(tester.takeException(), isNull);
        expectDeskNothingStretched(tester, maxCard: kuteWideColumnMax);
        await deskFullEnd(tester);
      });
    }
  }

  for (final p in _pages) {
    for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: ${p.name} $label $mode', skip: deskFullDir == null,
            (tester) async {
          await deskFullAssets(tester);
          await _pumpPage(tester, p, size: size, dark: dark);
          await deskFullShoot(tester, '${p.name}_${label}_$mode$_suffix');
          await deskFullEnd(tester);
        });
      }
    }
  }
}
