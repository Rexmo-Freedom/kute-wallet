// Money home to Bitcoin from both venues at once is ONE Activity row on the
// Bitcoin tab, never a "Withdraw · from Investments" row per venue.
//
// The founder's report this pins (build 85/86, Bitcoin tab): two rows at
// 13:35, "Withdraw · Pending · from Investments · ₿0 · from $16.53" and
// "Withdraw · Pending · from Investments · ₿10,539 · from $8.49". One Buy
// bitcoin from Investments: both legs already share one move record (the
// fan-out records every source under one move id); the Bitcoin tab and its
// "See all" list the spending wallet through `walletIdOverride`, and a list
// with an override carried no moves, so each leg stood as its own row. The
// CCTP leg, written with a bitcoin figure of 0, read "₿0".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/buy_bitcoin_fanout.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart'
    show kDollarsToBtcRoute;
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/theme/app_theme.dart';

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 10, 27, 13, 35);

/// A venue whose direct leg to Bitcoin goes at once and records the
/// operation its rows carry.
class _Venue implements VenueCashSource, DirectVenueCashSource {
  _Venue(this.venue);
  @override
  final OneBalanceVenue venue;
  @override
  Duration get estimatedArrival => Duration.zero;
  @override
  Future<double> availableUsd() async => 100;
  @override
  bool canPullTo(VenueCashDestination destination) => true;
  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) =>
      throw StateError('a direct leg never comes home first here');
  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
          {required String purpose, required MoveAuthorization auth}) async =>
      VenueMoveResult(
          quoteId: 'q_${venue.name}',
          operationId: 'op-${venue.name}',
          sentUsd: usd,
          arrivingUsdEstimate: usd * 0.99);
}

SwapOrderTransaction _leg(
  String id, {
  required String from,
  required String fromNet,
  required String usd,
  required String btc,
  required String op,
  String status = 'exchanging',
  String? routeVersion,
}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: _t0,
      isConfirmed: false,
      details: SwapOrder(
        id: id,
        coinFrom: from,
        networkFrom: fromNet,
        coinTo: 'BTC',
        networkTo: 'SPARK',
        depositAddress: 'deposit-$id',
        depositAmount: usd,
        withdrawalAmount: btc,
        status: status,
        timestamp: _t0.millisecondsSinceEpoch,
        withdrawalAddress: _self,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
        operationId: op,
        routeVersion: routeVersion,
      ),
    );

// The two rows of the screenshot: the CCTP leg out of Investing (no
// bitcoin figure yet) and the Predictions leg (its quote's estimate).
SwapOrderTransaction _investing(
        {String btc = '0', String status = 'exchanging'}) =>
    _leg('ord_hl',
        from: 'USDC',
        fromNet: 'HYPERCORE',
        usd: '16.53',
        btc: btc,
        op: 'op-investing',
        status: status,
        routeVersion: 'hypercore_cctp_to_spark_btc_v1');
SwapOrderTransaction _predictions({String status = 'exchanging'}) =>
    _leg('ord_pm',
        from: 'USDC',
        fromNet: 'POLYGON',
        usd: '8.49',
        btc: '0.00010539',
        op: 'op-predictions',
        status: status);

const _kinds = {
  'ord_hl': SwapActivityKind.investingWithdrawal,
  'ord_pm': SwapActivityKind.predictionsWithdrawal,
};

/// What Buy bitcoin from Investments records for $16.53 from Investing and
/// $8.49 from Predictions, both straight to Bitcoin, no Dollars: the real
/// fan-out and puller.
Future<MultiSourceMove> _buyFromBothVenues() async {
  MultiSourceMoveStore.reset();
  final puller = VenueCashPuller(
      sources: [for (final v in OneBalanceVenue.values) _Venue(v)],
      readDollars: () => 0,
      minimumUsd: (_) async => 1,
      walletId: () => 'spending');
  final plan = VenueCashPlan(
      neededUsd: 25.02,
      dollarsUsd: 0,
      pulls: [
        VenueCashPull(
            venue: OneBalanceVenue.investing,
            usd: 16.53,
            arrivingUsd: 16.36,
            eta: Duration.zero),
        VenueCashPull(
            venue: OneBalanceVenue.predictions,
            usd: 8.49,
            arrivingUsd: 8.40,
            eta: Duration.zero),
      ],
      covers: true,
      eta: Duration.zero,
      uncoveredUsd: 0);
  final approval = AuthGrants.issue(
      DirectLegGrants.buyBitcoin(
          walletId: 'spending',
          ownSpark: _self,
          route: kDollarsToBtcRoute.label,
          asset: 'USDB',
          totalUsd: plan.neededUsd,
          directLegs: puller.directLegLimit(plan, VenueCashDestination.bitcoin),
          ttl: AuthGrants.autofireTtl),
      method: AuthGrantMethod.pin);
  await BitcoinPurchaseFanout(
      buy: (usd, grant, id, onFunding) async =>
          throw StateError('no Dollars part')).start(
      puller: puller,
      plan: plan,
      approval: approval,
      walletId: 'spending',
      ownSpark: _self);
  return MultiSourceMoveStore.all().single;
}

List<BaseTransaction> _bitcoinTab(List<BaseTransaction> rows,
        {required List<MultiSourceMove> moves}) =>
    assembleActivityRows(
      rows,
      ownAddresses: const {_self},
      isHardwareOrWatchOnly: false,
      onlyUsdb: false,
      classify: (o) => _kinds[o.id] ?? classifySwapActivity(o),
      moves: moves,
      walletId: 'spending',
      deliveryLinks: const {},
    );

void main() {
  setUp(OwnSparkArrivals.reset);

  group('which lists fold the moves', () {
    test('Home, and the Bitcoin tab and its "See all" (the spending wallet)',
        () {
      expect(activityCarriesMoves(null, spendingId: 'spending'), isTrue);
      expect(activityCarriesMoves('spending', spendingId: 'spending'), isTrue);
    });

    test('never another wallet\'s list', () {
      expect(activityCarriesMoves('ledger', spendingId: 'spending'), isFalse);
      expect(activityCarriesMoves('spending', spendingId: null), isFalse);
    });
  });

  group('Buy bitcoin from Investments, both venues at once', () {
    test('records one move for both legs', () async {
      final move = await _buyFromBothVenues();
      expect(move.destination, VenueCashDestination.bitcoin);
      expect(move.okLegs.map((l) => l.operationId),
          unorderedEquals(['op-investing', 'op-predictions']));
    });

    test('is one row on the Bitcoin tab, both legs inside it', () async {
      final move = await _buyFromBothVenues();
      final rows = _bitcoinTab([_investing(), _predictions()], moves: [move]);
      expect(rows, hasLength(1));
      final parent = rows.single as MultiSourceMoveTransaction;
      expect(parent.legRows.map((r) => r.id),
          unorderedEquals(['ord_hl', 'ord_pm']));
      expect(parent.isConfirmed, isFalse, reason: 'Pending until every leg');
    });

    test('a list without the moves showed one row per leg (the report)',
        () async {
      final rows = _bitcoinTab([_investing(), _predictions()], moves: const []);
      expect(rows.map((r) => r.id), unorderedEquals(['ord_hl', 'ord_pm']));
    });

    test('settles only once both legs have', () async {
      final move = await _buyFromBothVenues();
      final half = _bitcoinTab([_investing(), _predictions(status: 'success')],
          moves: [move]).single as MultiSourceMoveTransaction;
      expect(half.isConfirmed, isFalse);
      final both = _bitcoinTab([
        _investing(btc: '0.00020500', status: 'success'),
        _predictions(status: 'success'),
      ], moves: [
        move
      ]).single as MultiSourceMoveTransaction;
      expect(both.isConfirmed, isTrue);
    });
  });

  group('on screen', () {
    setUp(() => Intl.defaultLocale = 'en_US');
    tearDown(() => Intl.defaultLocale = null);

    Future<void> pumpRow(WidgetTester tester, BaseTransaction tx) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                balancePrivacy: 0,
                biometricsEnabled: false,
                bitcoinElectrumNode: 'localhost',
                nodeType: 'Blockstream',
                reviewDone: false,
                wallets: [WalletConfig(id: 'spending', name: 'Spending')],
                activeWalletId: 'spending',
              ))),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                  builder: (context, ref, _) =>
                      buildUnifiedTransactionItem(tx, context, ref)),
            ),
          ),
        ),
      ));
    }

    testWidgets(
        'the one row reads the dollars of both legs while a leg\'s bitcoin '
        'is unknown, never ₿0 nor one leg\'s bitcoin', (tester) async {
      final move = await _buyFromBothVenues();
      final row =
          _bitcoinTab([_investing(), _predictions()], moves: [move]).single;
      await pumpRow(tester, row);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.textContaining('from Investments'), findsOneWidget);
      expect(find.textContaining('25.02'), findsOneWidget);
      expect(find.textContaining('10,539'), findsNothing);
      expect(find.textContaining('₿0'), findsNothing);
      expect(find.textContaining('Pending', findRichText: true), findsWidgets);
    });

    testWidgets('once every leg\'s bitcoin is known: the bitcoin of both',
        (tester) async {
      final move = await _buyFromBothVenues();
      final row = _bitcoinTab([
        _investing(btc: '0.00020500'),
        _predictions(),
      ], moves: [
        move
      ]).single;
      await pumpRow(tester, row);
      expect(find.textContaining('31,039'), findsOneWidget);
      expect(find.text('from \$25.02'), findsOneWidget);
    });

    testWidgets('a lone withdrawal with no bitcoin figure reads its dollars',
        (tester) async {
      await pumpRow(tester, _investing());
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.textContaining('16.53'), findsOneWidget);
      expect(find.textContaining('from \$16.53'), findsNothing);
      expect(find.textContaining(RegExp(r'(^|\D)0 sats|₿0')), findsNothing);
    });

    testWidgets('and its bitcoin once known', (tester) async {
      await pumpRow(tester, _investing(btc: '0.00020500'));
      expect(find.textContaining('20,500'), findsOneWidget);
      expect(find.text('from \$16.53'), findsOneWidget);
    });
  });
}
