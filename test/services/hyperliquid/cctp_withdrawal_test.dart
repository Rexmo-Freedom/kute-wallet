// Investing → Dollars by Circle CCTP: the fallback while Orchestra refuses
// HyperCore-source routes. Fakes stand in for HyperEVM, Arbitrum, the
// HyperCore ledger, the exchange and Orchestra; the settlement store is
// the real one on a temporary Hive box, so every resume rule runs against
// the record as it is persisted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settlement_reconciler_provider.dart'
    show SettlementReconcilerDriver;
import 'package:kute/screens/shared/fee_copy.dart' show feeRateText;
import 'package:kute/services/arbitrum_read_rpc.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show kHypercoreToSparkUsdRoute;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _otherSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _account = '0x7578d21940ee6ac4f882b6d5173d26bce62f5136';
const _standing = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';
const _pmWallet = '0x9999999999999999999999999999999999999999';
const _ledgerHash =
    '0x3e1e694226c985983f9804466f30530208450027c1cca46ae1e71494e5cd5f82';
const _mintTx =
    '0x7eeaa949877f4565c47d50fdb740b8800ae72e22532e2e6b9029cd6b7d21316c';

StandingDepositRecord _record({
  String recipient = _spark,
  String purpose = 'venue_withdrawal',
  bool enabled = true,
  int appFeeBps = 50,
  bool legacy = false,
  InvestingWithdrawalDestination destination =
      InvestingWithdrawalDestination.dollars,
}) =>
    StandingDepositRecord(
      walletId: 'w',
      label: StandingDepositStore.investingWithdrawalLabelFor(recipient, 7,
          destination: destination, legacy: legacy),
      recipient: recipient,
      asset: destination.asset,
      chain: destination.chain,
      revision: 7,
      response: {
        'standingAddressId': 'sda_1',
        'enabled': enabled,
        'addresses': {'arbitrum': _standing},
        'kuteFeePolicy': {
          'revision': 7,
          'purpose': purpose,
          'appFeeBps': appFeeBps,
        },
      },
    );

class _Reads implements CctpChainReads {
  bool paused = false;
  BigInt fee = BigInt.from(200000); // 0.20 USDC
  Object? feeError;
  Object? pausedError;
  List<ArbitrumTokenMint> mints = [];
  Object? mintError;
  String? Function(int nonce)? ledger;
  Object? ledgerError;
  int pausedReads = 0;

  @override
  Future<bool> coreDepositWalletPaused() async {
    pausedReads++;
    if (pausedError != null) throw pausedError!;
    return paused;
  }

  @override
  Future<BigInt> forwardingFee(int domain) async {
    expect(domain, kCctpArbitrumDomain);
    if (feeError != null) throw feeError!;
    return fee;
  }

  @override
  Future<int> arbitrumBlock() async => 514276600;

  @override
  Future<List<ArbitrumTokenMint>> arbitrumUsdcMints(
      String to, int fromBlock) async {
    expect(to, _standing);
    if (mintError != null) throw mintError!;
    return mints;
  }

  @override
  Future<String?> ledgerSendHash(
      {required String source,
      required BigInt amount8,
      required int nonce}) async {
    expect(source, _account);
    if (ledgerError != null) throw ledgerError!;
    return ledger?.call(nonce);
  }
}

enum _SendMode { ok, refused, rejected, lostAfterPost, refusedAfterNonce }

class _Sender implements CctpSender {
  BigInt sendable = BigInt.from(2500000000); // $25
  _SendMode mode = _SendMode.ok;
  final sends = <({String destination, BigInt amount8, String token})>[];
  int nonce = 1791851727813;

  @override
  Future<BigInt> sendableBaseUnits(String account) async => sendable;

  @override
  Future<int> send({
    required String walletId,
    required String account,
    required String destination,
    required BigInt amount8,
    required int domain,
    required String token,
    required Future<void> Function(int nonce) onBeforePost,
  }) async {
    if (mode == _SendMode.refused) {
      throw SettlementFundingRefused(StateError('locked'));
    }
    await onBeforePost(nonce);
    if (mode == _SendMode.refusedAfterNonce) {
      throw SettlementFundingRefused(StateError('wallet changed'));
    }
    sends.add((destination: destination, amount8: amount8, token: token));
    switch (mode) {
      case _SendMode.rejected:
        throw CctpSendRejected(StateError('Insufficient balance'));
      case _SendMode.lostAfterPost:
        throw TimeoutException('no answer');
      default:
        return nonce;
    }
  }
}

class _Orchestra implements CctpOrchestraPort {
  StandingDepositRecord? held = _record();
  Object? instructionError;
  List<Map<String, dynamic>> depositList = [];
  Object? depositsError;
  final orders = <String, OrchestraOrder>{};
  double? minimum = 0.8;
  final logged = <String>[];
  int instructions = 0;
  final destinations = <InvestingWithdrawalDestination>[];

  @override
  Future<StandingDepositRecord> instruction({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required bool Function() wanted,
    InvestingWithdrawalDestination destination =
        InvestingWithdrawalDestination.dollars,
  }) async {
    instructions++;
    destinations.add(destination);
    expect(refundAddress, _account);
    if (instructionError != null) throw instructionError!;
    return held!;
  }

  @override
  Future<StandingDepositRecord?> record(String walletId, String label) async =>
      held?.label == label ? held : null;

  @override
  Future<List<Map<String, dynamic>>> deposits(
      StandingDepositRecord record, bool Function() current) async {
    if (depositsError != null) throw depositsError!;
    return depositList;
  }

  @override
  Future<OrchestraOrder?> order(String orderId) async => orders[orderId];

  @override
  Future<double?> minimumUsd(
          {InvestingWithdrawalDestination destination =
              InvestingWithdrawalDestination.dollars}) async =>
      minimum;

  @override
  void logPending(SwapOrder row) => logged.add(row.id);
}

class _Rows implements CctpActivityRows {
  final byId = <String, SwapOrder>{};

  @override
  SwapOrder? find(String id) => byId[id];

  @override
  Future<void> put(SwapOrder row) async => byId[row.id] = row;

  @override
  Future<void> remove(String id) async => byId.remove(id);
}

class _Wallet implements CctpWalletContext {
  String spark = _spark;

  @override
  String spendingWalletId() => 'w';

  @override
  void ensureSpending(String walletId) => expect(walletId, 'w');

  @override
  Future<String> investingAddress() async => _account;

  @override
  Future<String> sparkAddress() async => spark;

  String predictions = _pmWallet;

  @override
  Future<String> predictionsAddress() async => predictions;
}

void main() {
  late Directory temporary;
  late SettlementStore store;
  late _Reads reads;
  late _Sender sender;
  late _Orchestra orchestra;
  late _Rows rows;
  late _Wallet wallet;
  late DateTime now;
  late List<(String, Map<String, Object>?)> events;
  late List<SettlementAuthorizationIntent> intents;
  late RuntimeCapabilitiesService policy;

  HypercoreCctpWithdrawal service() => HypercoreCctpWithdrawal(
        reads: reads,
        sender: sender,
        orchestra: orchestra,
        rows: rows,
        wallet: wallet,
        store: () async => store,
        clock: () => now,
        policy: () => policy,
        confirmAttempts: 2,
        confirmInterval: Duration.zero,
        watchFor: Duration.zero,
      );

  SettlementStepUpHook approve({bool answer = true}) => (intent) async {
        intents.add(intent);
        return answer;
      };

  List<String> named(String event) => [
        for (final e in events)
          if (e.$1 == event) '${e.$2?['step'] ?? e.$2?['reason'] ?? ''}',
      ];

  Future<SettlementOperation> only() async =>
      (await store.all()).singleWhere(
          (op) => op.flow == SettlementFlow.investingToDollarsCctp);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cctp-withdrawal');
    Hive.init(temporary.path);
    now = DateTime.fromMillisecondsSinceEpoch(1791851727813 + 500);
    store = SettlementStore(
      box: await Hive.openBox<String>('operations'),
      quarantine: await Hive.openBox<String>('quarantine'),
      clock: () => now,
    );
    reads = _Reads();
    sender = _Sender();
    orchestra = _Orchestra();
    rows = _Rows();
    wallet = _Wallet();
    events = [];
    intents = [];
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    policy.dispose();
    AffiliateService.debugSessionToken = null;
    await Hive.deleteFromDisk();
    await temporary.delete(recursive: true);
  });

  group('pure rules', () {
    test('pre-flight: paused, the fee and the route minimum', () {
      final fee = BigInt.from(200000);
      expect(
          cctpPreflightBlocker(
              paused: true,
              forwardFee6: fee,
              amount6: BigInt.from(5000000),
              minimumUsd: 0.8),
          CctpUnavailableReason.paused);
      expect(
          cctpPreflightBlocker(
              paused: false,
              forwardFee6: fee,
              amount6: BigInt.from(200000),
              minimumUsd: 0.8),
          CctpUnavailableReason.belowMinimum,
          reason: 'not above the forwarding fee');
      // 1.04 − 0.20 = 0.84 < 0.80 + 0.05.
      expect(
          cctpPreflightBlocker(
              paused: false,
              forwardFee6: fee,
              amount6: BigInt.from(1040000),
              minimumUsd: 0.8),
          CctpUnavailableReason.belowMinimum);
      expect(
          cctpPreflightBlocker(
              paused: false,
              forwardFee6: fee,
              amount6: BigInt.from(1050000),
              minimumUsd: 0.8),
          isNull);
    });

    test('send amount keeps the HyperCore gas reserve back', () {
      expect(
          cctpSendAmount(
              requested8: BigInt.from(500000000),
              sendable8: BigInt.from(2500000000)),
          BigInt.from(500000000));
      // 100%: everything minus $0.06, whole micro-dollars.
      expect(
          cctpSendAmount(
              requested8: BigInt.from(2500000000),
              sendable8: BigInt.from(2500000099)),
          BigInt.from(2494000000));
      expect(
          cctpSendAmount(
              requested8: BigInt.from(100), sendable8: BigInt.from(5000000)),
          BigInt.zero);
    });

    test('the ledger match needs this nonce, amount, sender and system send',
        () {
      Map<String, dynamic> row({
        String type = 'send',
        int nonce = 42,
        String amount = '5.25',
        String user = _account,
        String destination = '0x2000000000000000000000000000000000000000',
      }) =>
          {
            'time': 43,
            'hash': _ledgerHash,
            'delta': {
              'type': type,
              'user': user,
              'destination': destination,
              'sourceDex': '',
              'destinationDex': 'spot',
              'token': 'USDC',
              'amount': amount,
              'fee': '0.015284',
              'nonce': nonce,
              'feeToken': 'USDC',
            },
          };
      final amount = BigInt.from(525000000);
      String? match(List<dynamic> updates) => matchHypercoreCctpSend(
          updates: updates, source: _account, amount8: amount, nonce: 42);
      expect(match([row()]), _ledgerHash);
      expect(match([row(nonce: 43)]), isNull);
      expect(match([row(amount: '5.24')]), isNull);
      expect(match([row(user: _standing)]), isNull);
      expect(match([row(destination: _standing)]), isNull);
      expect(match([row(type: 'spotTransfer')]), isNull);
    });

    test('mint and deposit matches stay inside the fee window', () {
      final amount6 = BigInt.from(5250000);
      final fee6 = BigInt.from(200000);
      ArbitrumTokenMint mint(int units, [String tx = _mintTx]) =>
          ArbitrumTokenMint(amount: BigInt.from(units), txHash: tx, block: 1);
      expect(
          matchCctpMint(
                  mints: [mint(5050000)], amount6: amount6, maxFee6: fee6)
              ?.txHash,
          _mintTx);
      expect(
          matchCctpMint(mints: [mint(5049999)], amount6: amount6, maxFee6: fee6),
          isNull);
      expect(
          matchCctpMint(
              mints: [mint(5050000)],
              amount6: amount6,
              maxFee6: fee6,
              claimed: {_mintTx}),
          isNull);
      final sentAt = DateTime.utc(2026, 10, 13, 1);
      Map<String, dynamic> deposit(String id, int units, DateTime at) => {
            'id': id,
            'chain': 'arbitrum',
            'asset': 'USDC',
            'amount': '$units',
            'sourceTxId': '0x${'1' * 64}',
            'observedAt': at.toIso8601String(),
          };
      expect(
          matchCctpDeposit(deposits: [
            deposit('a', 5050000, sentAt.add(const Duration(seconds: 20))),
          ], amount6: amount6, maxFee6: fee6, sentAt: sentAt)?['id'],
          'a');
      expect(
          matchCctpDeposit(deposits: [
            deposit('old', 5050000, sentAt.subtract(const Duration(hours: 1))),
          ], amount6: amount6, maxFee6: fee6, sentAt: sentAt),
          isNull,
          reason: 'an older deposit of the same size is not this move');
      expect(
          matchCctpDeposit(deposits: [
            deposit('a', 5050000, sentAt),
            deposit('b', 5050000, sentAt),
          ], amount6: amount6, maxFee6: fee6, sentAt: sentAt),
          isNull,
          reason: 'ambiguous: wait');
    });
  });

  test('happy path: burn, ledger, mint, order, completed', () async {
    reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
    final result = await service().withdrawToDollars(
        usd: 5.25, stepUp: approve(), purpose: 'sweep');
    expect(result.sentUsd, 5.25);
    expect(result.arrivingUsdEstimate, closeTo(5.05, 1e-9));
    expect(sender.sends.single.destination, _standing);
    expect(sender.sends.single.amount8, BigInt.from(525000000));
    expect(sender.sends.single.token, 'USDC');

    // The approval names the own Spark address and the dollar route home.
    final intent = intents.single;
    expect(intent.destination, '$_spark|$kHypercoreCctpRouteVersion');
    expect(intent.routeLabel, kHypercoreToSparkUsdRoute.label);
    expect(intent.amountIn, BigInt.from(525000000));

    var op = await only();
    expect(op.stage, SettlementStage.funded);
    expect(op.funding?.hlNonce, sender.nonce);
    expect(op.funding?.evmTxHash, _ledgerHash);
    final row = rows.byId['$kCctpRowPrefix${op.operationId}']!;
    expect(row.networkFrom, 'HYPERCORE');
    expect(row.coinFrom, 'USDC');
    expect(row.networkTo, 'SPARK');
    expect(row.coinTo, 'USDB');
    expect(row.isPending, isTrue);
    expect(row.shouldPollOrchestra, isFalse);

    // Circle mints on Arbitrum, Orchestra sees it and makes the order.
    now = now.add(const Duration(seconds: 15));
    reads.mints = [
      ArbitrumTokenMint(amount: BigInt.from(5050000), txHash: _mintTx, block: 9)
    ];
    orchestra.depositList = [
      {
        'id': 'dep_1',
        'chain': 'arbitrum',
        'asset': 'USDC',
        'amount': '5050000',
        'sourceTxId': _mintTx,
        'observedAt': now.toIso8601String(),
        'status': 'processing',
        'orderId': 'ord_1',
      }
    ];
    orchestra.orders['ord_1'] = OrchestraOrder(
        id: 'ord_1',
        status: 'processing',
        amountIn: '5050000',
        amountOut: '5040000',
        recipientAddress: _spark,
        createdAt: now.toIso8601String());
    await service().reconcile(op, force: true);
    op = await only();
    expect(op.stage, SettlementStage.processing);
    expect(op.orderId, 'ord_1');
    expect(rows.byId.containsKey('$kCctpRowPrefix${op.operationId}'), isFalse);
    final orderRow = rows.byId['ord_1']!;
    expect(orderRow.networkFrom, 'HYPERCORE');
    expect(orderRow.coinTo, 'USDB');
    expect(orderRow.operationId, op.operationId);
    expect(orderRow.routeVersion, kHypercoreCctpRouteVersion);
    expect(orchestra.logged, ['ord_1'], reason: 'provider event: pending');

    orchestra.orders['ord_1'] = OrchestraOrder(
        id: 'ord_1',
        status: 'completed',
        amountIn: '5050000',
        amountOut: '5040000',
        recipientAddress: _spark,
        createdAt: now.toIso8601String());
    now = now.add(const Duration(minutes: 1));
    await service().reconcile(op, force: true);
    op = await only();
    expect(op.stage, SettlementStage.settled);
    expect(named('hyperliquid_withdraw_step'),
        ['cctp_sent', 'core_confirmed', 'arbitrum_minted', 'orchestra_detected']);
    final completed =
        events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_completed');
    expect(completed.$2?['route'], 'cctp');
    expect(completed.$2?['destination'], 'usd');
    expect(completed.$2?.containsKey('order_ref'), isTrue);
    expect(completed.$2?.values.contains('ord_1'), isFalse,
        reason: 'ids only as a one-way ref');

    // A later pass never reports the outcome twice.
    await service().reconcile(op, force: true);
    expect(named('hyperliquid_withdraw_completed').length, 1);
  });

  group('the Kute fee of the instruction paid', () {
    test('investments_internal on the new Dollars label: the fee line is 0%',
        () async {
      orchestra.held = _record(purpose: 'investments_internal', appFeeBps: 0);
      reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
      final result = await service().withdrawToDollars(
          usd: 5.25, stepUp: approve(), purpose: 'manual_move');
      expect(result.kuteFeeBps, 0);
      expect(feeRateText(result.kuteFeeBps!), '0.00%');
      final op = await only();
      final cctp = op.raw['cctp'] as Map;
      expect(cctp['kuteFeeBps'], 0);
      // One withdrawal, one instruction, one address.
      expect(orchestra.instructions, 1);
      expect(cctp['label'], orchestra.held!.label);
      expect(sender.sends.single.destination, _standing);
    });

    test('venue_withdrawal (an old backend, or the legacy label): its rate',
        () async {
      orchestra.held = _record(legacy: true);
      reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
      final result = await service().withdrawToDollars(
          usd: 5.25, stepUp: approve(), purpose: 'manual_move');
      expect(result.kuteFeeBps, 50);
      expect(feeRateText(result.kuteFeeBps!), '0.50%');
      final op = await only();
      expect((op.raw['cctp'] as Map)['kuteFeeBps'], 50);
      expect((op.raw['cctp'] as Map)['label'],
          StandingDepositStore.investingWithdrawalLabelFor(_spark, 7,
              legacy: true));
      expect(sender.sends, hasLength(1));
    });
  });

  group('straight to the final destination', () {
    test('Bitcoin: its own instruction, the BTC route, own Spark', () async {
      orchestra.held = _record(destination: InvestingWithdrawalDestination.bitcoin);
      reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
      final result = await service().withdrawTo(
          destination: InvestingWithdrawalDestination.bitcoin,
          usd: 5.25,
          stepUp: approve(),
          purpose: 'cash_pull');
      expect(result.sentUsd, 5.25);
      expect(orchestra.destinations, [InvestingWithdrawalDestination.bitcoin]);
      expect(sender.sends.single.destination, _standing);
      final intent = intents.single;
      expect(intent.flow, SettlementFlow.investingToBtcCctp);
      expect(intent.destination, '$_spark|$kHypercoreCctpBtcRouteVersion');
      expect(intent.routeLabel,
          cctpRouteFor(InvestingWithdrawalDestination.bitcoin).label);
      final op = (await store.all()).single;
      expect(op.flow, SettlementFlow.investingToBtcCctp);
      expect(op.recipient?.address, _spark);
      final row = rows.byId['$kCctpRowPrefix${op.operationId}']!;
      expect(row.coinTo, 'BTC');
      expect(row.networkTo, 'SPARK');
    });

    test('Predictions: the own deposit wallet on Polygon USDC.e', () async {
      orchestra.held = _record(
          recipient: _pmWallet,
          purpose: 'investments_internal',
          destination: InvestingWithdrawalDestination.predictions);
      reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
      await service().withdrawTo(
          destination: InvestingWithdrawalDestination.predictions,
          usd: 5.25,
          stepUp: approve(),
          purpose: 'cash_pull');
      final op = (await store.all()).single;
      expect(op.flow, SettlementFlow.investingToPredictionsCctp);
      expect(op.recipient?.kind, OwnedAddressKind.polymarketDepositWallet);
      expect(intents.single.destination,
          '$_pmWallet|$kHypercoreCctpPredictionsRouteVersion');
      final row = rows.byId['$kCctpRowPrefix${op.operationId}']!;
      expect(row.coinTo, 'USDC.e');
      expect(row.networkTo, 'POLYGON');
    });

    test('an instruction pinned to another rule is never paid', () async {
      // A Bitcoin instruction that came back with the deposit rule.
      orchestra.held = _record(
          purpose: 'cross_chain_deposit',
          destination: InvestingWithdrawalDestination.bitcoin);
      await expectLater(
          service().withdrawTo(
              destination: InvestingWithdrawalDestination.bitcoin,
              usd: 5,
              stepUp: approve()),
          throwsA(isA<CctpUnavailable>().having((e) => e.reason, 'reason',
              CctpUnavailableReason.feeTermsUnavailable)));
      // The Dollars instruction never stands in for Bitcoin.
      orchestra.held = _record();
      await expectLater(
          service().withdrawTo(
              destination: InvestingWithdrawalDestination.bitcoin,
              usd: 5,
              stepUp: approve()),
          throwsA(isA<CctpUnavailable>()));
      expect(sender.sends, isEmpty);
      expect(intents, isEmpty);
    });

    test('Predictions needs polymarket.deposit too', () {
      expect(cctpCapabilitiesFor(InvestingWithdrawalDestination.predictions),
          containsAll(['hyperliquid.withdraw', 'polymarket.deposit']));
      expect(cctpCapabilitiesFor(InvestingWithdrawalDestination.bitcoin),
          ['hyperliquid.withdraw']);
    });
  });

  group('runtime policy', () {
    // The normal route's quote answers to these for
    // `hypercore:USDC → spark:USDB`; the fallback must answer to the same.
    Future<Object?> normalRoute() async {
      try {
        await policy.ensureAllAllowed(orchestraCapabilityRequirements(
            sourceChain: 'hypercore',
            sourceAsset: 'USDC',
            destinationChain: 'spark',
            destinationAsset: 'USDB'));
        return null;
      } catch (e) {
        return e;
      }
    }

    /// A policy whose backend answers [answer]; its own clock.
    RuntimeCapabilitiesService serving(
            Future<http.Response> Function() answer,
            {DateTime Function()? clock}) =>
        RuntimeCapabilitiesService.forTesting(
          client: MockClient((_) => answer()),
          baseUrl: () => 'https://policy.test',
          sessionToken: () => AffiliateService.sessionToken,
          clock: clock,
        );

    http.Response policyBody({required bool withdraw}) {
      final evaluated = DateTime.now().toUtc();
      return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'revision': 1,
            'evaluatedAt': evaluated.toIso8601String(),
            'expiresAt': evaluated
                .add(const Duration(minutes: 2))
                .toIso8601String(),
            'capabilities': {
              'hyperliquid.withdraw': {
                'allowed': withdraw,
                'reason': withdraw ? '' : 'disabled',
                'comingSoon': false,
              },
            },
          }),
          200);
    }

    test('the fallback needs what the normal route needs', () {
      expect(kCctpCapabilities, ['hyperliquid.withdraw']);
    });

    test('withheld hyperliquid.withdraw: nothing registered, approved or '
        'signed', () async {
      policy.dispose();
      policy = runtimePolicyFixture(blocked: {'hyperliquid.withdraw'});
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>()
              .having((e) => e.reason, 'reason',
                  CctpUnavailableReason.capability)
              .having((e) => e.decision?.allowed, 'decision.allowed', false)
              .having((e) => e.decision?.reason, 'decision.reason',
                  'disabled')));
      expect(await normalRoute(), isA<CapabilityUnavailableException>(),
          reason: 'the normal route refuses too');
      expect(orchestra.instructions, 0);
      expect(reads.pausedReads, 0);
      expect(intents, isEmpty, reason: 'no approval asked');
      expect(sender.sends, isEmpty);
      expect(await store.all(), isEmpty);
      expect(rows.byId, isEmpty);
      expect(named('hyperliquid_cctp_unavailable'), ['capability']);
    });

    test('allowed: the move goes out as before', () async {
      expect(await normalRoute(), isNull);
      final result =
          await service().withdrawToDollars(usd: 5, stepUp: approve());
      expect(result.sentUsd, 5);
      expect(sender.sends, hasLength(1));
      expect(named('hyperliquid_cctp_unavailable'), isEmpty);
    });

    test('a policy that cannot be read: the normal route\'s rule (an exit, '
        'allowed)', () async {
      policy.dispose();
      policy = serving(() async => http.Response('unavailable', 503));
      expect(await normalRoute(), isNull,
          reason: 'hyperliquid.withdraw is in the offline table');
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      expect(sender.sends, hasLength(1));
      expect(named('hyperliquid_cctp_unavailable'), isEmpty);
    });

    test('a policy that cannot be read after a denial: still refused, as '
        'the normal route', () async {
      var policyNow = DateTime.now();
      var reachable = true;
      policy.dispose();
      policy = serving(
          () async => reachable
              ? policyBody(withdraw: false)
              : http.Response('unavailable', 503),
          clock: () => policyNow);
      expect(await policy.refresh(), isTrue);
      // The denial expires and the backend goes away.
      reachable = false;
      policyNow = policyNow.add(const Duration(minutes: 5));
      expect(await normalRoute(), isA<CapabilityUnavailableException>());
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>().having(
              (e) => e.reason, 'reason', CctpUnavailableReason.capability)));
      expect(sender.sends, isEmpty);
      expect(named('hyperliquid_cctp_unavailable'), ['capability']);
    });
  });

  test('a paused CoreDepositWallet stops before anything is signed', () async {
    reads.paused = true;
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()
            .having((e) => e.reason, 'reason', CctpUnavailableReason.paused)));
    expect(sender.sends, isEmpty);
    expect(intents, isEmpty);
    expect(await store.all(), isEmpty);
    expect(rows.byId, isEmpty);
    expect(named('hyperliquid_cctp_unavailable'), ['paused']);
  });

  test('below the minimum waits, nothing signed', () async {
    // $1.00 − $0.20 forwarding = $0.80 < $0.80 + margin.
    await expectLater(
        service().withdrawToDollars(usd: 1, stepUp: approve()),
        throwsA(isA<CctpUnavailable>().having(
            (e) => e.reason, 'reason', CctpUnavailableReason.belowMinimum)));
    expect(sender.sends, isEmpty);
    expect(named('hyperliquid_cctp_unavailable'), ['below_minimum']);
  });

  test('fee and RPC reads that fail stop before signing', () async {
    reads.feeError = StateError('rpc down');
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()));
    reads
      ..feeError = null
      ..pausedError = StateError('rpc down');
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()));
    expect(named('hyperliquid_cctp_unavailable'),
        ['fee_read_failed', 'rpc_failed']);
    expect(sender.sends, isEmpty);
  });

  test('without Kute\'s venue-withdrawal fee pinned nothing is sent', () async {
    orchestra.instructionError = const InvestingWithdrawalTermsUnavailable();
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>().having((e) => e.reason, 'reason',
            CctpUnavailableReason.feeTermsUnavailable)));
    // An instruction whose stored terms are the dollar-deposit rule.
    orchestra
      ..instructionError = null
      ..held = _record(purpose: 'usdb_swap_deposit');
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()));
    expect(sender.sends, isEmpty);
    expect(reads.pausedReads, 0, reason: 'terms first, before any read');
  });

  test('the automatic sweep only ever pays the own standing address',
      () async {
    // An instruction for someone else's Spark address is never used.
    orchestra.held = _record(recipient: _otherSpark);
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()));
    expect(sender.sends, isEmpty);
    expect(intents, isEmpty, reason: 'no approval asked for a stranger');
    // A paused instruction neither.
    orchestra.held = _record(enabled: false);
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()));
    expect(sender.sends, isEmpty);
  });

  test('a declined approval stops before signing', () async {
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve(answer: false)),
        throwsA(isA<SettlementStopped>()));
    expect(sender.sends, isEmpty);
    expect(await store.all(), isEmpty);
  });

  test('a refusal before the POST ends the record and its row', () async {
    sender.mode = _SendMode.refused;
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<StateError>()));
    expect((await only()).stage, SettlementStage.abandoned);
    expect(rows.byId, isEmpty);
  });

  test('a stop between the nonce write and the POST is not funded', () async {
    sender.mode = _SendMode.refusedAfterNonce;
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<StateError>()));
    final op = await only();
    expect(op.stage, SettlementStage.notFunded);
    expect(rows.byId.values.single.status, 'expired');
  });

  test('restart after the nonce was recorded: no ledger row means not funded',
      () async {
    sender.mode = _SendMode.lostAfterPost;
    reads.ledger = (_) => null;
    final result =
        await service().withdrawToDollars(usd: 5, stepUp: approve());
    expect(result.operationId, isNotEmpty);
    var op = await only();
    expect(op.stage, SettlementStage.broadcasting);
    expect(op.funding?.hlNonce, sender.nonce);

    // A fresh process within the window: still unknown, still pending.
    await service().reconcile(op, force: true);
    expect((await only()).stage, SettlementStage.broadcasting);

    // Past the window with a successful empty ledger read: never sent.
    now = now.add(kCctpNotSentAfter + const Duration(seconds: 1));
    await service().reconcile(op, force: true);
    op = await only();
    expect(op.stage, SettlementStage.notFunded);
    expect(rows.byId.values.single.status, 'expired');
    expect(sender.sends.length, 1, reason: 'never signs again');

    // A late ledger row still wins.
    reads.ledger = (_) => _ledgerHash;
    now = now.add(const Duration(minutes: 11));
    await service().reconcile(op);
    expect((await only()).stage, SettlementStage.funded);
    expect(rows.byId.values.single.status, 'exchanging');
  });

  test('restart after the ledger shows the send resumes watching', () async {
    sender.mode = _SendMode.lostAfterPost;
    reads.ledger = (_) => null;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    reads.ledger = (_) => _ledgerHash;
    orchestra.depositList = [
      {
        'id': 'dep_9',
        'chain': 'arbitrum',
        'asset': 'USDC',
        'amount': '4800000',
        'sourceTxId': '0x${'2' * 64}',
        'observedAt': now.toIso8601String(),
        'status': 'confirming',
        'orderId': null,
      }
    ];
    now = now.add(const Duration(seconds: 30));
    await service().reconcile(await only());
    final op = await only();
    expect(op.stage, SettlementStage.processing);
    expect(op.funding?.evmTxHash, _ledgerHash);
    expect(sender.sends.length, 1);
  });

  test('an RPC failure never reads as arrived', () async {
    reads.ledger = (_) => _ledgerHash;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    reads.mintError = const ArbitrumReadException('no RPC');
    orchestra.depositsError = StateError('backend down');
    now = now.add(const Duration(hours: 2));
    await service().reconcile(await only(), force: true);
    final op = await only();
    expect(op.stage, SettlementStage.funded,
        reason: 'neither arrived nor needs attention on failed reads');
    expect(rows.byId.values.single.status, 'exchanging');
    expect(named('hyperliquid_withdraw_step'), ['cctp_sent', 'core_confirmed']);

    // A ledger read failure on a broadcast proves nothing either.
    sender
      ..mode = _SendMode.lostAfterPost
      ..nonce += 1;
    final other = HypercoreCctpWithdrawal(
      reads: reads..ledgerError = StateError('ledger down'),
      sender: sender,
      orchestra: orchestra,
      rows: rows,
      wallet: wallet,
      store: () async => store,
      clock: () => now,
      confirmAttempts: 1,
      confirmInterval: Duration.zero,
      watchFor: Duration.zero,
    );
    // The first move is past `funded`, so a second may start.
    await store.transition(op.operationId, SettlementStage.processing,
        from: SettlementStage.funded);
    await other.withdrawToDollars(usd: 5, stepUp: approve());
    now = now.add(const Duration(hours: 1));
    final second = (await store.all()).firstWhere(
        (o) => o.operationId != op.operationId);
    await other.reconcile(second, force: true);
    expect((await store.get(second.operationId))!.stage,
        SettlementStage.broadcasting);
  });

  test('Orchestra holding the deposit shows it held, money not lost',
      () async {
    reads.ledger = (_) => _ledgerHash;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    orchestra.depositList = [
      {
        'id': 'dep_h',
        'chain': 'arbitrum',
        'asset': 'USDC',
        'amount': '4800000',
        'sourceTxId': '0x${'3' * 64}',
        'observedAt': now.toIso8601String(),
        'status': 'held',
        'code': 'below_minimum',
        'orderId': null,
      }
    ];
    now = now.add(const Duration(seconds: 30));
    var op = await only();
    await service().reconcile(op, force: true);
    op = await only();
    expect(op.stage, SettlementStage.needsAttention);
    final held = rows.byId['${kStuckStandingDepositRowPrefix}dep_h']!;
    expect(held.status, 'held');
    expect(held.networkFrom, 'HYPERCORE', reason: 'reads as Investing');
    expect(held.coinTo, 'USDB');
    expect(held.operationId, op.operationId);
    expect(rows.byId.containsKey('$kCctpRowPrefix${op.operationId}'), isFalse);
    expect(events.any((e) => e.$1 == 'settlement_needs_attention'), isTrue);
  });

  test('one CCTP move at a time until the earlier one is at Orchestra',
      () async {
    reads.ledger = (_) => _ledgerHash;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>().having(
            (e) => e.reason, 'reason', CctpUnavailableReason.inFlight)));
    expect(sender.sends.length, 1);
  });

  test('a rejected action is not funded and keeps its row as expired',
      () async {
    sender.mode = _SendMode.rejected;
    await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<StateError>()));
    expect((await only()).stage, SettlementStage.notFunded);
    expect(rows.byId.values.single.status, 'expired');
  });

  test('the token switch only changes the wire token', () async {
    reads.ledger = (_) => _ledgerHash;
    await HypercoreCctpWithdrawal(
      reads: reads,
      sender: sender,
      orchestra: orchestra,
      rows: rows,
      wallet: wallet,
      store: () async => store,
      clock: () => now,
      tokenForm: CctpTokenForm.tokenId,
      confirmAttempts: 1,
      confirmInterval: Duration.zero,
      watchFor: Duration.zero,
    ).withdrawToDollars(usd: 5, stepUp: approve());
    expect(sender.sends.single.token,
        'USDC:0x6d1e7cde53ba9467b783cb7c530ce054');
    expect(cctpTokenWire(kHypercoreCctpTokenForm), 'USDC',
        reason: 'Circle\'s form by default');
  });

  test('the reconciler driver hands CCTP records to the watcher only',
      () async {
    sender.mode = _SendMode.lostAfterPost;
    reads.ledger = (_) => null;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    final before = await only();
    final handed = <String>[];
    final driver = SettlementReconcilerDriver(
      sessionUnlocked: () => false,
      store: () async => store,
      clock: () => now,
      cctp: (op) async => handed.add(op.operationId),
    );
    await driver.runOnce();
    expect(handed, [before.operationId]);
    final after = await only();
    expect(after.version, before.version,
        reason: 'the Orchestra ladder never touched it');
  });
}
