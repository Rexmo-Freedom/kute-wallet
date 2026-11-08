// A row of the P&L tab's "Closed positions" opens the receipt of that closed
// position (founder, 8 November 2026): a prediction won, lost or sold, an
// Investing close, in the first five and with the list unfolded ("See all"),
// and the receipt's result is the row's figure to the cent. A row with no
// receipt opens the market's page; one with neither does not press. See
// lib/screens/portfolio/portfolio_closed_receipt.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, ClosedPosition, PolymarketEvent;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/portfolio/portfolio_closed_receipt.dart';
import 'package:kute/screens/portfolio/portfolio_pnl_section.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart' show portfolioOverrides;

final _now = DateTime.now().toUtc();
DateTime _ago(int hours) => _now.subtract(Duration(hours: hours));
int _secs(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

PredictionRecord _record(
  String token, {
  required double realized,
  required DateTime at,
  double total = 10,
  double avg = 0.5,
  double price = 0,
  double unrealized = 0,
  double size = 0,
  double entry = 0,
  bool open = false,
  bool redeemable = false,
  String outcome = 'Down',
  String eventSlug = '',
}) =>
    PredictionRecord(
      tokenId: token,
      conditionId: '0x$token',
      open: open,
      redeemable: redeemable,
      size: size,
      totalSize: total,
      avgPrice: avg,
      entryCostUsd: entry,
      currentPrice: price,
      realizedPnlUsd: realized,
      unrealizedPnlUsd: unrealized,
      lastEventAt: at,
      title: 'Market $token',
      eventSlug: eventSlug,
      outcome: outcome,
    );

PolymarketTransaction _venue(
  String token, {
  required String type,
  required double usdc,
  required double size,
  required DateTime at,
  String? side,
  double? price,
  String? asset,
  String hash = '0xabc',
  String outcome = 'Down',
}) {
  final a = Activity(
    proxyWallet: '0xme',
    timestamp: _secs(at),
    conditionId: '0x$token',
    type: type,
    size: size,
    usdcSize: usdc,
    transactionHash: hash,
    side: side,
    price: price,
    asset: asset ?? token,
    title: 'Market $token',
    outcome: outcome,
  );
  return PolymarketTransaction(
      id: '$token-$type-${side ?? ''}-$hash', timestamp: at, activity: a);
}

ClosedPosition _closedLost(String token, {required double size, required double avg}) =>
    ClosedPosition(
      proxyWallet: '0xme',
      asset: token,
      conditionId: '0x$token',
      size: size,
      avgPrice: avg,
      initialValue: size * avg,
      payout: 0,
      cashPnl: -size * avg,
      percentPnl: -100,
      title: 'Market $token',
      slug: token,
      eventSlug: '',
      outcome: 'Down',
      outcomeIndex: 0,
      resolutionDate: _ago(4),
    );

HlFill _fill(int oid,
        {required double px,
        required double sz,
        required double pnl,
        required double fee,
        required DateTime at,
        String coin = 'xyz:ANTHROPIC',
        String dir = 'Close Short',
        String id = 't'}) =>
    HlFill(
      coin: coin,
      px: px,
      sz: sz,
      side: 'B',
      time: at.millisecondsSinceEpoch,
      closedPnl: pnl,
      fee: fee,
      feeToken: 'USDC',
      oid: oid,
      hash: '0xhash',
      dir: dir,
      cloid: null,
      tradeId: id,
    );

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.initial);
  final PolymarketTradingState initial;
  @override
  Future<PolymarketTradingState> build() async => initial;
}

const _perf = PortfolioPerformance(
    points: [], sourceLabel: '', basisLabel: 'P&L', coverageLabel: 'All time');

/// A won prediction, claimed: +$1.10 on a $10.00 payout.
final _won = _record('won', realized: 1.10, at: _ago(1), avg: 0.89, price: 1);
final _wonClaim = _venue('won',
    type: 'REDEEM', usdc: 10, size: 10, at: _ago(1), asset: '', hash: '0xw');

/// A prediction lost: −$4.00, read from the market.
final _lost = _record('lost', realized: -4, at: _ago(2), total: 8, price: 0);

/// A prediction sold in one sale: +$1.31.
final _sold = _record('sold', realized: 1.31, at: _ago(3), avg: 0.306, price: .5);
final _soldSale = _venue('sold',
    type: 'TRADE',
    side: 'SELL',
    usdc: 4.37,
    size: 10,
    price: 0.437,
    at: _ago(3),
    hash: '0xs');

/// An Investing close of two fills: +$1.31 after $0.09 of fees.
final _closeFills = [
  _fill(77, px: 100, sz: 1, pnl: 0.8, fee: 0.05, at: _ago(5), id: 'a'),
  _fill(77, px: 110, sz: 1, pnl: 0.6, fee: 0.04, at: _ago(4), id: 'b'),
];

/// Nothing to open: a sale older than the history, no event.
final _nowhere =
    _record('gone', realized: 0.42, at: _ago(6), avg: 0.3, price: 0.5);

/// Older rows, so the list folds.
List<PredictionRecord> _older() => [
      for (var i = 0; i < 3; i++)
        _record('old$i', realized: 1, at: _ago(20 + i), avg: .3, price: .5),
    ];

Future<void> _mount(
  WidgetTester tester, {
  required List<PredictionRecord> records,
  List<PolymarketTransaction> history = const [],
  List<ClosedPosition> closed = const [],
  List<HlFill> fills = const [],
  List<Override> extra = const [],
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(
          history: Transaction.empty()
              .copyWith(polymarketTransactions: history)),
      ...offlineVenueOverrides,
      currentBtcUsdProvider.overrideWithValue(100000),
      oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
          investingKnown: true, predictionsKnown: true)),
      usdBalanceUnknownProvider.overrideWithValue(false),
      hyperliquidActivityFillsProvider.overrideWithValue(fills),
      hyperliquidAccountMarketProvider('xyz:ANTHROPIC').overrideWith((_) => null),
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.predictions))
          .overrideWith(
              (_) async => _perf.withPredictions(PredictionsBook(records: records))),
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.trading))
          .overrideWith((_) async => _perf),
      polymarketTradingProvider.overrideWith(() => _Trading(
          PolymarketTradingState(
              isAuthenticated: true,
              proxyWalletAddress: '0xme',
              closedPositions: closed))),
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
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PortfolioPnlBreakdown(
              listed: const [
                PortfolioPerformanceVenue.predictions,
                PortfolioPerformanceVenue.trading
              ],
              quiet: const {},
              quietText: (_) => '',
              selected: null,
              onPick: null,
            ),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _row(String id) => find.byKey(ValueKey('portfolio-closed-$id'));

Finder _sheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

/// The figure the closed row writes.
String _rowFigure(WidgetTester tester, String id) => tester
    .widget<PortfolioClosedRow>(find.descendant(
        of: _row(id), matching: find.byType(PortfolioClosedRow)))
    .resultUsd
    .toStringAsFixed(2);

String _tile(WidgetTester tester, String label) => tester
    .widgetList<Text>(find.descendant(
        of: _sheet(find.byKey(ValueKey('receipt-tile-$label'))),
        matching: find.byType(Text)))
    .map((t) => t.data)
    .toList()[1]!;

Future<void> _open(WidgetTester tester, String id) async {
  await tester.ensureVisible(_row(id));
  await tester.pump();
  await tester.tap(_row(id));
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(BottomSheet))).pop();
  await _settle(tester);
}

/// Every kind's receipt, with the row's figure, opened from where the list
/// stands now.
Future<void> _expectEveryReceipt(WidgetTester tester) async {
  // Won and claimed: the claim's receipt, the row's figure its result.
  await _open(tester, 'pm:won');
  expect(_rowFigure(tester, 'pm:won'), '1.10');
  expect(_sheet(find.text('Won · Down')), findsOneWidget);
  expect(_sheet(find.text(r'+$10.00')), findsWidgets);
  expect(_sheet(find.text(r'$1.10 profit')), findsOneWidget);
  expect(_tile(tester, 'Result'), r'+$1.10');
  await _close(tester);

  // Lost: the result read from the market.
  await _open(tester, 'pm:lost');
  expect(_rowFigure(tester, 'pm:lost'), '-4.00');
  expect(_sheet(find.text('Lost · Down')), findsOneWidget);
  expect(_sheet(find.text(r'−$4.00')), findsWidgets);
  expect(_tile(tester, 'Cost'), r'$4.00');
  expect(_tile(tester, 'Payout'), r'$0.00');
  expect(_tile(tester, 'Realized profits'), r'−$4.00');
  await _close(tester);

  // Sold: the sale's receipt.
  await _open(tester, 'pm:sold');
  expect(_rowFigure(tester, 'pm:sold'), '1.31');
  expect(_sheet(find.text('Sold · Down')), findsOneWidget);
  expect(_sheet(find.text(r'+$4.37')), findsWidgets);
  expect(_sheet(find.text(r'$1.31 profit')), findsOneWidget);
  expect(_tile(tester, 'Result'), r'+$1.31');
  await _close(tester);

  // An Investing close of two fills: the order, added, net of its fees.
  await _open(tester, 'hl:xyz:ANTHROPIC:77');
  expect(_rowFigure(tester, 'hl:xyz:ANTHROPIC:77'), '1.31');
  expect(_sheet(find.text(r'+$1.31')), findsOneWidget);
  expect(_sheet(find.text(r'$210.00')), findsWidgets, reason: 'both fills');
  expect(_tile(tester, 'Execution price'), r'$105.00');
  expect(_tile(tester, 'Paid fee'), r'$0.09');
  await _close(tester);
}

Future<void> _mountEveryKind(WidgetTester tester) => _mount(
      tester,
      records: [_won, _lost, _sold, ..._older()],
      history: [_wonClaim, _soldSale],
      closed: [_closedLost('lost', size: 8, avg: 0.5)],
      fills: _closeFills,
    );

void main() {
  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  List<Map<String, Object>?> tapped() => [
        for (final e in events)
          if (e.$1 == 'portfolio_closed_position_tapped') e.$2
      ];

  testWidgets(
      'in the section: won, lost, sold and an Investing close each open their '
      'receipt, its result the row\'s figure, and the tap is counted',
      (tester) async {
    await _mountEveryKind(tester);
    await _expectEveryReceipt(tester);
    expect(tapped(), [
      {'venue': 'polymarket', 'source': 'section'},
      {'venue': 'polymarket', 'source': 'section'},
      {'venue': 'polymarket', 'source': 'section'},
      {'venue': 'hyperliquid', 'source': 'section'},
    ]);
  });

  testWidgets('with "See all" unfolded: the same receipts, source see_all',
      (tester) async {
    await _mountEveryKind(tester);
    await tester.ensureVisible(
        find.byKey(const ValueKey('portfolio-closed-see-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('portfolio-closed-see-all')));
    await _settle(tester);
    expect(_row('pm:old2'), findsOneWidget, reason: 'the rest of the list');
    await _expectEveryReceipt(tester);
    expect(tapped(), [
      {'venue': 'polymarket', 'source': 'see_all'},
      {'venue': 'polymarket', 'source': 'see_all'},
      {'venue': 'polymarket', 'source': 'see_all'},
      {'venue': 'hyperliquid', 'source': 'see_all'},
    ]);
  });

  testWidgets('a row with nowhere to go has no press state and sends nothing',
      (tester) async {
    await _mount(tester, records: [_nowhere]);
    final row = find.descendant(
        of: _row('pm:gone'), matching: find.byType(PortfolioClosedRow));
    expect(tester.widget<PortfolioClosedRow>(row).onTap, isNull);
    expect(
        tester
            .widget<KutePressable>(
                find.descendant(of: row, matching: find.byType(KutePressable)))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<InkWell>(
                find.descendant(of: row, matching: find.byType(InkWell)))
            .onTap,
        isNull);
    await tester.tap(_row('pm:gone'));
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tapped(), isEmpty);
  });

  testWidgets(
      'a row with only a market page presses once its event is known, not '
      'before', (tester) async {
    final old = _record('far',
        realized: 0.42, at: _ago(6), avg: 0.3, price: 0.5, eventSlug: 'far-ev');
    PortfolioClosedRow row() => tester.widget<PortfolioClosedRow>(find.descendant(
        of: _row('pm:far'), matching: find.byType(PortfolioClosedRow)));

    await _mount(tester, records: [old], extra: [
      polyPositionEventProvider('far-ev').overrideWith((_) => null),
    ]);
    expect(row().onTap, isNull);

    await tester.pumpWidget(const SizedBox());
    await _mount(tester, records: [old], extra: [
      polyPositionEventProvider('far-ev').overrideWith((_) =>
          const PolymarketEvent(
              id: '1',
              slug: 'far-ev',
              title: 'Far',
              volume: 0,
              liquidity: 0,
              category: 'crypto',
              conditionId: '0xfar',
              outcomes: [])),
    ]);
    expect(row().onTap, isNotNull);
  });

  group('resolveClosedPrediction', () {
    test('a sale and then a claim: the claim, the last thing that happened', () {
      final r = _record('mix', realized: 3.1, at: _ago(1), price: 1);
      final claim = _venue('mix',
          type: 'REDEEM', usdc: 5, size: 5, at: _ago(1), asset: '', hash: '0x1');
      final sale = _venue('mix',
          type: 'TRADE', side: 'SELL', usdc: 3, size: 5, at: _ago(3), hash: '0x2');
      final to = resolveClosedPrediction(r,
          resultUsd: 3.1, history: [sale, claim], results: const []);
      expect((to as PortfolioClosedVenueReceipt).tx, same(claim));
    });

    test('a hedge: the side that lost never opens the other side\'s claim', () {
      final lost = _record('hedge', realized: -2, at: _ago(1), total: 4);
      final claim = _venue('hedge',
          type: 'REDEEM', usdc: 5, size: 5, at: _ago(1), asset: '');
      final to = resolveClosedPrediction(lost,
          resultUsd: -2, history: [claim], results: const []);
      final result = (to as PortfolioClosedResultReceipt).result;
      expect(result.won, isFalse);
      expect(result.pnlUsd, closeTo(-2, 1e-9));
    });

    test('several sales: one Sold receipt, everything added, no one hash', () {
      final r = _record('two', realized: 0.5, at: _ago(1), price: 0.5);
      final a = _venue('two',
          type: 'TRADE',
          side: 'SELL',
          usdc: 3,
          size: 5,
          price: 0.6,
          at: _ago(3),
          hash: '0xa');
      final b = _venue('two',
          type: 'TRADE',
          side: 'SELL',
          usdc: 2.5,
          size: 5,
          price: 0.5,
          at: _ago(1),
          hash: '0xb');
      final to = resolveClosedPrediction(r,
          resultUsd: 0.5, history: [a, b], results: const []);
      final tx = (to as PortfolioClosedVenueReceipt).tx;
      expect(tx.activity.usdcSize, 5.5);
      expect(tx.activity.size, 10);
      expect(tx.activity.price, closeTo(0.55, 1e-9));
      expect(tx.activity.transactionHash, '');
      expect(tx.timestamp, b.timestamp);
    });

    test('another token\'s sale is not this one\'s', () {
      final r = _record('mine', realized: 0.5, at: _ago(1), price: 0.5);
      final other = PolymarketTransaction(
          id: 'x',
          timestamp: _ago(1),
          activity: Activity(
              proxyWallet: '0xme',
              timestamp: _secs(_ago(1)),
              conditionId: '0xmine',
              type: 'TRADE',
              side: 'SELL',
              size: 1,
              usdcSize: 1,
              transactionHash: '0x',
              asset: 'theirs'));
      expect(
          resolveClosedPrediction(r,
              resultUsd: 0.5, history: [other], results: const []),
          isNull);
    });

    test('a win older than the history: its record, when it says the same', () {
      final r = _record('oldwin', realized: 5, at: _ago(900), price: 1);
      final to = resolveClosedPrediction(r,
          resultUsd: 5, history: const [], results: const []);
      final result = (to as PortfolioClosedResultReceipt).result;
      expect(result.won, isTrue);
      expect(result.payoutUsd, 10);
      expect(result.stakeUsd, 5);
      expect(result.pnlUsd, 5);
    });

    test(
        'a win partly sold and older than the history: no sheet that would '
        'not add up, the market', () {
      final r = _record('oldmix',
          realized: 3.1, at: _ago(900), price: 1, eventSlug: 'ev');
      final to = resolveClosedPrediction(r,
          resultUsd: 3.1, history: const [], results: const []);
      expect((to as PortfolioClosedMarketPage).eventSlug, 'ev');
    });

    test('the market\'s result comes first when the market has one', () {
      final r = _record('res', realized: -4, at: _ago(1), total: 8);
      final result = PredictionResult(
          activity: Activity(
              proxyWallet: '0xme',
              timestamp: _secs(_ago(1)),
              conditionId: '0xres',
              type: 'REDEEM',
              size: 8,
              usdcSize: 0,
              transactionHash: '',
              asset: 'res'),
          won: false,
          stakeUsd: 4,
          payoutUsd: 0);
      final to = resolveClosedPrediction(r,
          resultUsd: -4, history: const [], results: [result]);
      expect((to as PortfolioClosedResultReceipt).result, same(result));
    });
  });

  group('foldClosedFills', () {
    test('one fill stands as it is', () {
      final f = _closeFills.first;
      expect(foldClosedFills([f]), same(f));
    });

    test('several: added, the average price, no fill id', () {
      final f = foldClosedFills(_closeFills);
      expect(f.sz, 2);
      expect(f.px, closeTo(105, 1e-9));
      expect(f.closedPnl, closeTo(1.4, 1e-9));
      expect(f.fee, 0.09);
      expect(f.tradeId, isNull);
      expect(f.time, _closeFills.last.time);
    });
  });

  testWidgets(
      'partly sold, then lost: the sheet writes the row\'s figure and drops the '
      'cost that no longer adds up to it', (tester) async {
    final r = _record('part', realized: -1.5, at: _ago(1), total: 8, price: 0);
    await _mount(tester, records: [
      r
    ], history: [
      _venue('part',
          type: 'TRADE',
          side: 'SELL',
          usdc: 2,
          size: 4,
          price: 0.5,
          at: _ago(3),
          outcome: 'Down'),
    ], closed: [
      _closedLost('part', size: 8, avg: 0.5),
    ]);
    await _open(tester, 'pm:part');
    expect(_sheet(find.text('Lost · Down')), findsOneWidget);
    expect(_sheet(find.text(r'−$2.00')), findsWidgets, reason: 'the stake lost');
    expect(_sheet(find.text(r'$1.50 loss')), findsOneWidget);
    expect(_tile(tester, 'Realized profits'), r'−$1.50');
    expect(_sheet(find.byKey(const ValueKey('receipt-tile-Cost'))), findsNothing);
  });
}
