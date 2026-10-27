// A Buy bitcoin from Investments that took $8.49 from Predictions and
// $16.53 from Investing at once, where the Predictions leg landed and the
// Investing leg's Circle CCTP send stopped before it was posted (the native
// HyperCore route refused first, CCTP was the fallback). Founder report:
// "Withdraw · Needs attention · ₿10,537 · from $8.49", Bitcoin up exactly
// 10,537 sats, nothing saying where the $16.53 was or what to do.
//
// The $16.53 never left Investing. The row says so ("Partly done", "$16.53
// is still in Investing"), its detail offers Retry, Retry asks the same
// Investing door again (native first, CCTP when refused), and the stopped
// attempt's row folds into the move instead of standing beside it.

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
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/theme/app_theme.dart';

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 10, 27, 13, 35);

/// A venue whose direct leg to Bitcoin goes, or stops before anything was
/// sent (the CCTP send refused before its POST, naming its record).
class _Venue implements VenueCashSource, DirectVenueCashSource {
  _Venue(this.venue, {this.stopsFirst = 0});
  @override
  final OneBalanceVenue venue;
  int stopsFirst;
  int directCalls = 0;
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
      {required String purpose, required MoveAuthorization auth}) async {
    directCalls++;
    if (stopsFirst > 0) {
      stopsFirst--;
      throw SettlementFundingRefused(StateError('perpetuals came up short'),
          operationId: 'op-cctp-stopped');
    }
    return VenueMoveResult(
        quoteId: 'q_${venue.name}_$directCalls',
        operationId: 'op-${venue.name}-$directCalls',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

AuthGrant _grant(VenueCashPuller puller, VenueCashPlan plan) =>
    AuthGrants.issue(
        DirectLegGrants.buyBitcoin(
            walletId: 'spending',
            ownSpark: _self,
            route: kDollarsToBtcRoute.label,
            asset: 'USDB',
            totalUsd: plan.neededUsd,
            directLegs:
                puller.directLegLimit(plan, VenueCashDestination.bitcoin),
            ttl: AuthGrants.autofireTtl),
        method: AuthGrantMethod.pin);

late _Venue _investing;
late VenueCashPuller _puller;

Future<MultiSourceMove> _buy() async {
  MultiSourceMoveStore.reset();
  DirectRouteRefusals.reset();
  _investing = _Venue(OneBalanceVenue.investing, stopsFirst: 1);
  _puller = VenueCashPuller(
      sources: [_Venue(OneBalanceVenue.predictions), _investing],
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
  await BitcoinPurchaseFanout(
      buy: (usd, grant, id, onFunding) async =>
          throw StateError('no Dollars part')).start(
      puller: _puller,
      plan: plan,
      approval: _grant(_puller, plan),
      walletId: 'spending',
      ownSpark: _self);
  return MultiSourceMoveStore.all().single;
}

SwapOrderTransaction _row(String id,
        {required String from,
        required String fromNet,
        required String usd,
        required String btc,
        required String op,
        required String status}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: _t0,
      isConfirmed: status == 'success',
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
        routeVersion: from == 'USDC' && fromNet == 'HYPERCORE'
            ? 'hypercore_cctp_to_spark_btc_v1'
            : null,
      ),
    );

// The Predictions leg, landed; the stopped CCTP attempt's row (a stop
// after its nonce was written leaves it Expired).
final _landed = _row('ord_pm',
    from: 'USDC',
    fromNet: 'POLYGON',
    usd: '8.49',
    btc: '0.00010537',
    op: 'op-predictions-1',
    status: 'success');
final _stopped = _row('cctp-op-cctp-stopped',
    from: 'USDC',
    fromNet: 'HYPERCORE',
    usd: '16.53',
    btc: '0',
    op: 'op-cctp-stopped',
    status: 'expired');

List<BaseTransaction> _surface(List<BaseTransaction> rows, MultiSourceMove move,
        {bool onlyUsdb = false}) =>
    assembleActivityRows(
      rows,
      ownAddresses: const {_self},
      isHardwareOrWatchOnly: false,
      onlyUsdb: onlyUsdb,
      classify: (o) => o.id == 'ord_pm'
          ? SwapActivityKind.predictionsWithdrawal
          : classifySwapActivity(o),
      moves: [move],
      walletId: 'spending',
      deliveryLinks: const {},
    );

void main() {
  setUp(OwnSparkArrivals.reset);

  group('the stopped Investing leg', () {
    test('is recorded as not sent, with the record it ended', () async {
      final move = await _buy();
      final investing =
          move.legs.singleWhere((l) => l.venue == OneBalanceVenue.investing);
      expect(investing.ok, isFalse);
      expect(investing.uncertain, isFalse);
      expect(investing.error, 'not_sent');
      expect(investing.stoppedOperationId, 'op-cctp-stopped');
      expect(move.partial, isTrue);
      expect(multiSourceMoveStillAtVenue(move),
          {OneBalanceVenue.investing: 16.53});
    });

    test('its row folds into the move: one row, Partly done', () async {
      final move = await _buy();
      for (final onlyUsdb in [false, true]) {
        final rows = _surface([_stopped, _landed], move, onlyUsdb: onlyUsdb);
        expect(rows.map((r) => r.id), [move.id],
            reason: 'no second attention row (onlyUsdb: $onlyUsdb)');
        final tx = rows.single as MultiSourceMoveTransaction;
        expect(tx.partlyDone, isTrue);
        expect(tx.stepFailed, isTrue, reason: 'its step did stop');
      }
      expect(multiSourceMoveLegIds([_stopped, _landed], [move]),
          containsAll(['cctp-op-cctp-stopped', 'ord_pm']),
          reason: 'the Investments activity never lists it beside the move');
    });

    test('a leg whose outcome is unknown is never "Partly done"', () async {
      final move = await _buy();
      final unknown = move.copyWith(legs: [
        for (final l in move.legs)
          l.ok
              ? l
              : MultiSourceMoveLeg(
                  venue: l.venue,
                  usd: l.usd,
                  arrivingUsd: l.arrivingUsd,
                  route: l.route,
                  ok: false,
                  at: l.at,
                  error: 'unknown',
                  uncertain: true),
      ]);
      final tx = MultiSourceMoveTransaction(move: unknown, legRows: [_landed]);
      expect(tx.partlyDone, isFalse);
    });

    test('Retry asks the same Investing door again, for that leg alone',
        () async {
      final move = await _buy();
      expect(_investing.directCalls, 1);
      final plan = (await _puller.planRetry(move.id))!;
      expect(plan.pulls.map((p) => (p.venue, p.usd)),
          [(OneBalanceVenue.investing, 16.53)]);
      await _puller.retryMove(move.id,
          approval: _grant(_puller, plan), plan: plan);
      expect(_investing.directCalls, 2,
          reason: 'straight to Bitcoin again: native first, CCTP if refused');
      final after = MultiSourceMoveStore.get(move.id)!;
      expect(after.partial, isFalse);
      expect(after.okLegs.map((l) => l.operationId),
          containsAll(['op-predictions-1', 'op-investing-2']));
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
        'the row: Partly done, where the rest is, the bitcoin that landed',
        (tester) async {
      final move = await _buy();
      await pumpRow(tester, _surface([_stopped, _landed], move).single);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.textContaining('Partly done', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('\$16.53 is still in Investing',
              findRichText: true),
          findsOneWidget);
      expect(find.textContaining('10,537'), findsOneWidget);
      expect(find.text('from \$8.49'), findsOneWidget);
      expect(find.textContaining('Needs attention', findRichText: true),
          findsNothing);
    });
  });
}
