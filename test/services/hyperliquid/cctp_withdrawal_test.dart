// Investing → Dollars, Bitcoin or Predictions by Circle CCTP onto a
// ONE-TIME Orchestra quote: the fallback while Orchestra refuses
// HyperCore-source routes. Fakes stand in for HyperEVM, Arbitrum, the
// HyperCore ledger, the exchange and Orchestra (quote, submit, status);
// the settlement store is the real one on a temporary Hive box, so every
// resume rule runs against the record as it is persisted. No standing
// address is registered or paid by any move.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show SweepAuthorization;
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
    show
        DirectHypercoreResult,
        SparkFundingAsset,
        SparkHypercoreFundingService,
        kHypercoreToSparkUsdRoute,
        sparkHypercoreFundingServiceProvider;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart'
    show HypercoreBalanceShortfall;
import 'package:kute/services/one_balance/money_movement_route.dart'
    show moneyMovementFailureReason, moneyMovementProvesNothingSent;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure;
import 'package:kute/services/security/wallet_guard_exception.dart';
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
// The one-time quotes' deposit addresses, one per quote asked for.
const _deposits = [
  '0x17c01c4dc5fe4b698978e302b3480efc9e3a19b6',
  '0x2222222222222222222222222222222222222222',
  '0x3333333333333333333333333333333333333333',
];
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
  final mintReads = <({String to, int fromBlock, int toBlock})>[];

  /// The Arbitrum head, and how many reads of it fail first.
  int block = 514276600;
  int blockErrors = 0;
  int blockReads = 0;

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
  Future<int> arbitrumBlock() async {
    blockReads++;
    if (blockErrors > 0) {
      blockErrors--;
      throw const ArbitrumReadException('no RPC');
    }
    return block;
  }

  /// Answers the mints inside the window, as `eth_getLogs` does, and
  /// refuses a window wider than a public endpoint caps.
  @override
  Future<List<ArbitrumTokenMint>> arbitrumUsdcMints(String to,
      {required int fromBlock, required int toBlock}) async {
    mintReads.add((to: to, fromBlock: fromBlock, toBlock: toBlock));
    expect(toBlock, greaterThanOrEqualTo(fromBlock));
    expect(toBlock - fromBlock + 1, lessThanOrEqualTo(kCctpMintScanChunkBlocks),
        reason: 'one eth_getLogs window');
    if (mintError != null) throw mintError!;
    return [
      for (final m in mints)
        if (m.block >= fromBlock && m.block <= toBlock) m
    ];
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

  /// What stopped a refused send before anything was posted.
  Object refusal = StateError('locked');
  final sends = <({String destination, BigInt amount8, String token})>[];
  int nonce = 1791851727813;
  int signed = 0;

  /// Runs after signing, before the POST hook (the cash collection's time).
  void Function()? afterSigning;

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
      throw SettlementFundingRefused(refusal);
    }
    signed++;
    afterSigning?.call();
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

typedef _QuoteAsk = ({
  InvestingWithdrawalDestination destination,
  BigInt amountIn6,
  String recipient,
  String refundAddress,
  String idempotencyKey,
});

class _Orchestra implements CctpOrchestraPort {
  _Orchestra(this.clock);

  final DateTime Function() clock;

  /// A record an older build paid (a standing instruction): read only.
  StandingDepositRecord? held;
  int recordReads = 0;
  List<Map<String, dynamic>> depositList = [];
  Object? depositsError;
  final orders = <String, OrchestraOrder>{};
  double? minimum = 0.8;
  final logged = <String>[];

  final quotes = <_QuoteAsk>[];

  /// The validity each quote comes back with, by attempt.
  Duration Function(int attempt) quoteLife = (_) => const Duration(minutes: 2);
  Object? quoteError;
  int? appFeeBps;
  String Function(int attempt)? depositAddressOf;

  final submits = <({String quoteId, String txHash, String key})>[];
  CctpSubmitResult Function() submitAnswer =
      () => (outcome: CctpSubmitOutcome.accepted, orderId: 'ord_1');

  @override
  Future<CctpQuote> quote({
    required InvestingWithdrawalDestination destination,
    required BigInt amountIn6,
    required String recipient,
    required String refundAddress,
    required String idempotencyKey,
  }) async {
    final attempt = quotes.length;
    quotes.add((
      destination: destination,
      amountIn6: amountIn6,
      recipient: recipient,
      refundAddress: refundAddress,
      idempotencyKey: idempotencyKey,
    ));
    if (quoteError != null) throw quoteError!;
    return CctpQuote(
      quoteId: 'q_${attempt + 1}',
      depositAddress: depositAddressOf?.call(attempt) ?? _deposits[attempt],
      expiresAt: clock().add(quoteLife(attempt)),
      amountIn6: amountIn6,
      appFeeBps: appFeeBps,
    );
  }

  @override
  Future<CctpSubmitResult> submit({
    required String quoteId,
    required String txHash,
    required String idempotencyKey,
  }) async {
    submits.add((quoteId: quoteId, txHash: txHash, key: idempotencyKey));
    return submitAnswer();
  }

  @override
  Future<StandingDepositRecord?> record(String walletId, String label) async {
    recordReads++;
    return held?.label == label ? held : null;
  }

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

OrchestraOrder _order(String id, String status,
        {String recipient = _spark, String? quoteId = 'q_1'}) =>
    OrchestraOrder(
        id: id,
        status: status,
        quoteId: quoteId,
        amountIn: '5050000',
        amountOut: '5040000',
        recipientAddress: recipient,
        createdAt: DateTime.utc(2026, 10, 19).toIso8601String());

ArbitrumTokenMint _mint(
        [int units = 5050000, String tx = _mintTx, int block = 514276600]) =>
    ArbitrumTokenMint(amount: BigInt.from(units), txHash: tx, block: block);

/// The native HyperCore route as Flashnet answers it today: refused for the
/// route itself, before anything is signed.
class _RefusingNative extends SparkHypercoreFundingService {
  _RefusingNative(super.read);

  int calls = 0;

  @override
  Future<void> ensureAvailable({required bool deposit}) async {}

  @override
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    calls++;
    throw OrchestraQuoteFailure(
      'HyperCore source routes require independent deposit verification '
      'and are unavailable',
      routeError:
          RouteQuoteError(RouteQuoteErrorCode.fromCode('unsupported_route')!),
    );
  }
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
        blockReadBackoff: Duration.zero,
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
      (await store.all()).singleWhere((op) => op.flow.isInvestingCctp);

  Map<String, dynamic> cctpOf(SettlementOperation op) =>
      Map<String, dynamic>.from(op.raw['cctp'] as Map);

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
    orchestra = _Orchestra(() => now);
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
          matchCctpMint(mints: [mint(5050000)], amount6: amount6, maxFee6: fee6)
              ?.txHash,
          _mintTx);
      expect(
          matchCctpMint(
              mints: [mint(5049999)], amount6: amount6, maxFee6: fee6),
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
    RuntimeCapabilitiesService serving(Future<http.Response> Function() answer,
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
            'expiresAt':
                evaluated.add(const Duration(minutes: 2)).toIso8601String(),
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

    test('withheld hyperliquid.withdraw: nothing quoted, approved or signed',
        () async {
      policy.dispose();
      policy = runtimePolicyFixture(blocked: {'hyperliquid.withdraw'});
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>()
              .having(
                  (e) => e.reason, 'reason', CctpUnavailableReason.capability)
              .having((e) => e.decision?.allowed, 'decision.allowed', false)
              .having(
                  (e) => e.decision?.reason, 'decision.reason', 'disabled')));
      expect(await normalRoute(), isA<CapabilityUnavailableException>(),
          reason: 'the normal route refuses too');
      expect(orchestra.quotes, isEmpty);
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

    test(
        'a policy that cannot be read: the normal route\'s rule (an exit, '
        'allowed)', () async {
      policy.dispose();
      policy = serving(() async => http.Response('unavailable', 503));
      expect(await normalRoute(), isNull,
          reason: 'hyperliquid.withdraw is in the offline table');
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      expect(sender.sends, hasLength(1));
      expect(named('hyperliquid_cctp_unavailable'), isEmpty);
    });

    test(
        'a policy that cannot be read after a denial: still refused, as '
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

  test('Dollars: one-time quote, sign to its address, mint found, submitted',
      () async {
    reads.ledger = (nonce) => nonce == sender.nonce ? _ledgerHash : null;
    orchestra.appFeeBps = null; // inside Investments: no app fee
    final result = await service()
        .withdrawToDollars(usd: 5.25, stepUp: approve(), purpose: 'sweep');
    expect(result.sentUsd, 5.25);
    expect(result.arrivingUsdEstimate, closeTo(5.05, 1e-9));
    expect(result.kuteFeeBps, 0);

    // The quote: exact in for what Circle mints, to the own Spark address,
    // refunds to the own EVM address (the Investing account).
    final ask = orchestra.quotes.single;
    expect(ask.destination, InvestingWithdrawalDestination.dollars);
    expect(ask.amountIn6, BigInt.from(5050000));
    expect(ask.recipient, _spark);
    expect(ask.refundAddress, _account);
    // Signed to the quote's deposit address, never a standing address.
    expect(sender.sends.single.destination, _deposits[0]);
    expect(sender.sends.single.amount8, BigInt.from(525000000));
    expect(sender.sends.single.token, 'USDC');
    expect(orchestra.recordReads, 0, reason: 'no standing instruction');

    // The approval names the own Spark address and the dollar route home.
    final intent = intents.single;
    expect(intent.destination, '$_spark|$kHypercoreCctpRouteVersion');
    expect(intent.routeLabel, kHypercoreToSparkUsdRoute.label);
    expect(intent.amountIn, BigInt.from(525000000));

    var op = await only();
    expect(op.stage, SettlementStage.funded);
    expect(op.funding?.hlNonce, sender.nonce);
    expect(op.funding?.evmTxHash, _ledgerHash);
    final cctp = cctpOf(op);
    expect(cctp['quoteId'], 'q_1');
    expect(cctp['depositAddress'], _deposits[0]);
    expect(cctp['target'], 'onetime');
    expect(cctp.containsKey('label'), isFalse);
    final pendingId = '$kCctpRowPrefix${op.operationId}';
    final row = rows.byId[pendingId]!;
    expect(row.networkFrom, 'HYPERCORE');
    expect(row.coinTo, 'USDB');
    expect(row.depositAddress, _deposits[0],
        reason: 'Track this exchange opens the quote address on Arbiscan');
    expect(row.shouldPollOrchestra, isFalse);

    // Circle mints on Arbitrum; the mint is submitted; the order exists.
    now = now.add(const Duration(seconds: 15));
    reads.mints = [_mint()];
    orchestra.orders['ord_1'] = _order('ord_1', 'processing');
    await service().reconcile(op, force: true);
    expect(reads.mintReads.last.to, _deposits[0]);
    expect(reads.mintReads.last.fromBlock, 514276600);
    expect(reads.mintReads.last.toBlock, 514276600, reason: 'the head');
    final submit = orchestra.submits.single;
    expect(submit.quoteId, 'q_1');
    expect(submit.txHash, _mintTx);
    expect(submit.key, cctp['submitKey']);
    op = await only();
    expect(op.stage, SettlementStage.processing);
    expect(op.orderId, 'ord_1');
    expect(rows.byId.containsKey(pendingId), isFalse);
    final orderRow = rows.byId['ord_1']!;
    expect(orderRow.networkFrom, 'HYPERCORE');
    expect(orderRow.coinTo, 'USDB');
    expect(orderRow.depositAddress, _deposits[0]);
    expect(orderRow.operationId, op.operationId);
    expect(orderRow.routeVersion, kHypercoreCctpRouteVersion);
    expect(orderRow.shouldPollOrchestra, isTrue);
    expect(orchestra.logged, ['ord_1']);

    orchestra.orders['ord_1'] = _order('ord_1', 'completed');
    now = now.add(const Duration(minutes: 1));
    await service().reconcile(op, force: true);
    op = await only();
    expect(op.stage, SettlementStage.settled);
    expect(orchestra.submits, hasLength(1), reason: 'never submitted again');
    expect(named('hyperliquid_withdraw_step'), [
      'cctp_sent',
      'core_confirmed',
      'arbitrum_minted',
      'orchestra_submitted',
    ]);
    final completed =
        events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_completed');
    expect(completed.$2?['route'], 'cctp');
    expect(completed.$2?['cctp_target'], 'onetime');
    expect(completed.$2?['submit_result'], 'submitted');
    expect(completed.$2?['destination'], 'usd');
    expect(completed.$2?.values.contains('ord_1'), isFalse);
    expect(completed.$2?.values.contains(_deposits[0]), isFalse);
    for (final step
        in events.where((e) => e.$1 == 'hyperliquid_withdraw_step')) {
      expect(step.$2?['cctp_target'], 'onetime');
    }

    // A later pass never reports the outcome twice.
    await service().reconcile(op, force: true);
    expect(named('hyperliquid_withdraw_completed').length, 1);

    // The legs as the Activity detail shows them.
    final legs = cctpLegProgressOf(op)!;
    expect([legs.burned, legs.minted, legs.ordered], [true, true, true]);
    expect(legs.sentUsd, 5.25);
    expect(legs.mintUsd, closeTo(5.05, 1e-9));
  });

  test(
      'Investing → Dollars on the rail: HyperCore refused, then CCTP onto a '
      'one-time quote, signed to its address, the mint submitted', () async {
    final container = ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((_) async => _account),
      sparkSelfAddressProvider.overrideWith((_) async => _spark),
    ]);
    addTearDown(container.dispose);
    final native = _RefusingNative(container.read);
    final read = ProviderContainer(
      parent: container,
      overrides: [
        sparkHypercoreFundingServiceProvider.overrideWithValue(native)
      ],
    ).read;
    reads.ledger = (_) => _ledgerHash;
    final result = await HyperCoreMoveRail(read, cctp: service)
        .withdrawToDollars(usd: 5.25, auth: SweepAuthorization.automatic);
    expect(native.calls, 1, reason: 'the native route first');
    expect(result.sentUsd, 5.25);
    expect(orchestra.quotes.single.recipient, _spark);
    expect(sender.sends.single.destination, _deposits[0]);
    expect(orchestra.recordReads, 0, reason: 'no standing registration');
    final submitted =
        events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted');
    expect(submitted.$2?['route'], 'cctp');
    expect(submitted.$2?['cctp_target'], 'onetime');

    reads.mints = [_mint()];
    orchestra.orders['ord_1'] = _order('ord_1', 'processing');
    now = now.add(const Duration(seconds: 20));
    await service().reconcile(await only(), force: true);
    expect(orchestra.submits.single.txHash, _mintTx);
    expect((await only()).orderId, 'ord_1');
  });

  test('Predictions: one-time quote to the own Predictions wallet, submitted',
      () async {
    reads.ledger = (_) => _ledgerHash;
    await service().withdrawTo(
        destination: InvestingWithdrawalDestination.predictions,
        usd: 5.25,
        stepUp: approve(),
        purpose: 'manual_move');
    final ask = orchestra.quotes.single;
    expect(ask.destination, InvestingWithdrawalDestination.predictions);
    expect(ask.recipient, _pmWallet);
    expect(ask.refundAddress, _account);
    expect(ask.amountIn6, BigInt.from(5050000));
    expect(sender.sends.single.destination, _deposits[0]);
    expect(orchestra.recordReads, 0);
    var op = await only();
    expect(op.flow, SettlementFlow.investingToPredictionsCctp);
    expect(op.recipient?.kind, OwnedAddressKind.polymarketDepositWallet);
    expect(intents.single.destination,
        '$_pmWallet|$kHypercoreCctpPredictionsRouteVersion');
    final row = rows.byId['$kCctpRowPrefix${op.operationId}']!;
    expect(row.coinTo, 'USDC.e');
    expect(row.networkTo, 'POLYGON');

    reads.mints = [_mint()];
    orchestra.orders['ord_1'] =
        _order('ord_1', 'processing', recipient: _pmWallet);
    now = now.add(const Duration(seconds: 20));
    await service().reconcile(op, force: true);
    expect(orchestra.submits.single.txHash, _mintTx);
    op = await only();
    expect(op.orderId, 'ord_1');
    expect(rows.byId['ord_1']!.networkTo, 'POLYGON');
  });

  test('Bitcoin: one-time quote into spark:BTC to the own Spark address',
      () async {
    reads.ledger = (_) => _ledgerHash;
    orchestra.appFeeBps = 50;
    final result = await service().withdrawTo(
        destination: InvestingWithdrawalDestination.bitcoin,
        usd: 5.25,
        stepUp: approve(),
        purpose: 'cash_pull');
    expect(result.kuteFeeBps, 50);
    expect(feeRateText(result.kuteFeeBps!), '0.50%');
    expect(orchestra.quotes.single.destination,
        InvestingWithdrawalDestination.bitcoin);
    expect(orchestra.quotes.single.recipient, _spark);
    final intent = intents.single;
    expect(intent.flow, SettlementFlow.investingToBtcCctp);
    expect(intent.routeLabel,
        cctpRouteFor(InvestingWithdrawalDestination.bitcoin).label);
    final op = await only();
    expect(op.flow, SettlementFlow.investingToBtcCctp);
    expect(rows.byId['$kCctpRowPrefix${op.operationId}']!.coinTo, 'BTC');
  });

  test('Predictions needs polymarket.deposit too', () {
    expect(cctpCapabilitiesFor(InvestingWithdrawalDestination.predictions),
        containsAll(['hyperliquid.withdraw', 'polymarket.deposit']));
    expect(cctpCapabilitiesFor(InvestingWithdrawalDestination.bitcoin),
        ['hyperliquid.withdraw']);
    expect(cctpQuoteTag(InvestingWithdrawalDestination.predictions),
        'kute:investing_to_predictions_cctp');
    expect(cctpQuoteTag(InvestingWithdrawalDestination.dollars),
        'kute:investing_withdrawal_cctp');
  });

  group('quote validity', () {
    test('too close to expiry: asks again, never signs to the short one',
        () async {
      orchestra.quoteLife = (attempt) => attempt == 0
          ? kCctpQuoteMinRemaining - const Duration(seconds: 1)
          : const Duration(minutes: 2);
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      expect(orchestra.quotes, hasLength(2));
      expect(orchestra.quotes[0].idempotencyKey,
          isNot(orchestra.quotes[1].idempotencyKey));
      expect(sender.sends.single.destination, _deposits[1]);
      expect(cctpOf(await only())['quoteId'], 'q_2');
    });

    test('no quote with enough validity: stops before signing', () async {
      orchestra.quoteLife = (_) => const Duration(seconds: 40);
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>().having(
              (e) => e.reason, 'reason', CctpUnavailableReason.quoteExpired)));
      expect(orchestra.quotes, hasLength(kCctpQuoteAttempts));
      expect(sender.signed, 0);
      expect(await store.all(), isEmpty);
      expect(rows.byId, isEmpty);
      expect(named('hyperliquid_cctp_unavailable'), ['quote_expired']);
    });

    test('ran short between signing and the POST: never posted', () async {
      sender.afterSigning = () => now = now.add(const Duration(seconds: 100));
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>().having(
              (e) => e.reason, 'reason', CctpUnavailableReason.quoteExpired)));
      expect(sender.sends, isEmpty, reason: 'nothing posted');
      final op = await only();
      expect(op.stage, SettlementStage.abandoned);
      expect(op.funding?.hlNonce, isNull);
      expect(rows.byId, isEmpty);
    });

    test('a refused or unreachable quote stops before signing', () async {
      orchestra.quoteError = const OrchestraQuoteFailure('unsupported_route');
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>().having((e) => e.reason, 'reason',
              CctpUnavailableReason.quoteUnavailable)));
      orchestra.quoteError =
          const WalletGuardException(WalletGuardReason.recipientNotOwn);
      await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>()));
      expect(sender.signed, 0);
      expect(await store.all(), isEmpty);
    });

    test('the backend withholding the route is shown as the restriction',
        () async {
      final decision = CapabilityDecision(allowed: false, reason: 'disabled');
      orchestra.quoteError = OrchestraQuoteFailure('feature_unavailable',
          denial:
              CapabilityUnavailableException('hyperliquid.withdraw', decision));
      await expectLater(
          service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>()
              .having(
                  (e) => e.reason, 'reason', CctpUnavailableReason.capability)
              .having((e) => e.decision?.reason, 'decision', 'disabled')));
      expect(sender.signed, 0);
    });

    test('a quote whose deposit address is the Investing account is refused',
        () async {
      orchestra.depositAddressOf = (_) => _account;
      await expectLater(service().withdrawToDollars(usd: 5, stepUp: approve()),
          throwsA(isA<CctpUnavailable>()));
      expect(sender.signed, 0);
    });
  });

  group('after the burn', () {
    test('restart after signing: never signs again, the submit resumes',
        () async {
      sender.mode = _SendMode.lostAfterPost;
      reads.ledger = (_) => null;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      var op = await only();
      expect(op.stage, SettlementStage.broadcasting);
      expect(cctpOf(op)['quoteId'], 'q_1');
      expect(cctpOf(op)['depositAddress'], _deposits[0]);

      // A fresh process: the ledger shows the burn, Circle minted.
      reads.ledger = (_) => _ledgerHash;
      reads.mints = [_mint(4800000)];
      orchestra.orders['ord_1'] = _order('ord_1', 'processing');
      now = now.add(const Duration(seconds: 30));
      await service().reconcile(op);
      op = await only();
      expect(op.funding?.evmTxHash, _ledgerHash);
      expect(orchestra.submits.single.quoteId, 'q_1');
      expect(op.orderId, 'ord_1');
      expect(sender.signed, 1, reason: 'never signs again');
      expect(orchestra.quotes, hasLength(1), reason: 'never quotes again');
    });

    test('the mint not found quickly: keeps watching, never signs twice',
        () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(minutes: 5));
        await service().reconcile(await only(), force: true);
      }
      var op = await only();
      expect(op.stage, SettlementStage.funded);
      expect(orchestra.submits, isEmpty, reason: 'nothing to submit yet');
      expect(rows.byId.values.single.status, 'exchanging');

      // Past the attention window: still watched on the slow pace.
      now = now.add(kCctpAttentionAfter);
      await service().reconcile(op, force: true);
      op = await only();
      expect(op.stage, SettlementStage.needsAttention);

      // The mint turns up late: submitted, the order adopted.
      reads.mints = [_mint(4800000)];
      orchestra.orders['ord_1'] = _order('ord_1', 'processing');
      now = now.add(const Duration(minutes: 11));
      await service().reconcile(op);
      op = await only();
      expect(orchestra.submits, hasLength(1));
      expect(op.orderId, 'ord_1');
      expect(op.stage, SettlementStage.processing);
      expect(sender.signed, 1);
      expect(orchestra.quotes, hasLength(1));
    });

    test('minted but no order for long: needs attention, still submitted',
        () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.mints = [_mint(4800000)];
      orchestra.submitAnswer =
          () => (outcome: CctpSubmitOutcome.transient, orderId: null);
      now = now.add(const Duration(seconds: 20));
      await service().reconcile(await only(), force: true);
      expect((await only()).stage, SettlementStage.processing);
      now = now.add(kCctpAttentionAfter);
      await service().reconcile(await only(), force: true);
      expect((await only()).stage, SettlementStage.needsAttention);
      now = now.add(const Duration(minutes: 11));
      await service().reconcile(await only());
      expect(orchestra.submits, hasLength(3));
      expect(orchestra.submits.map((s) => s.key).toSet(), hasLength(1));
      expect(sender.signed, 1);
    });

    test('Orchestra finds it first: the order is adopted as detected',
        () async {
      reads.ledger = (_) => _ledgerHash;
      reads.mintError = const ArbitrumReadException('no RPC');
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      orchestra.orders['q_1'] = _order('ord_7', 'processing');
      orchestra.orders['ord_7'] = _order('ord_7', 'completed');
      now = now.add(const Duration(seconds: 30));
      await service().reconcile(await only(), force: true);
      var op = await only();
      expect(op.orderId, 'ord_7');
      expect(orchestra.submits, isEmpty);
      expect(cctpOf(op)['submitResult'], 'detected');
      now = now.add(const Duration(seconds: 30));
      await service().reconcile(op, force: true);
      op = await only();
      expect(op.stage, SettlementStage.settled);
      final completed =
          events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_completed');
      expect(completed.$2?['submit_result'], 'detected');
    });

    test(
        'a refused submit tries again later with a new key; an unknown '
        'answer keeps it', () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.mints = [_mint(4800000)];
      orchestra.submitAnswer =
          () => (outcome: CctpSubmitOutcome.transient, orderId: null);
      now = now.add(const Duration(seconds: 20));
      await service().reconcile(await only(), force: true);
      now = now.add(kCctpSubmitRetryAfter);
      await service().reconcile(await only(), force: true);
      expect(orchestra.submits, hasLength(2));
      expect(orchestra.submits[0].key, orchestra.submits[1].key);

      orchestra.submitAnswer =
          () => (outcome: CctpSubmitOutcome.rejected, orderId: null);
      now = now.add(kCctpSubmitRetryAfter);
      await service().reconcile(await only(), force: true);
      orchestra.submitAnswer =
          () => (outcome: CctpSubmitOutcome.accepted, orderId: 'ord_1');
      orchestra.orders['ord_1'] = _order('ord_1', 'processing');
      now = now.add(kCctpSubmitRetryAfter);
      await service().reconcile(await only(), force: true);
      expect(orchestra.submits, hasLength(4));
      expect(orchestra.submits[3].key, isNot(orchestra.submits[2].key));
      expect((await only()).orderId, 'ord_1');
      expect(sender.signed, 1);
    });

    test('an order for someone else is never adopted', () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.mints = [_mint()];
      orchestra.orders['ord_1'] =
          _order('ord_1', 'processing', recipient: _otherSpark);
      now = now.add(const Duration(seconds: 20));
      await service().reconcile(await only(), force: true);
      expect((await only()).orderId, isNull);
      expect(rows.byId.containsKey('ord_1'), isFalse);
    });

    test(
        'an order for someone else found under the quote leaves no trace of '
        'an order on the record', () async {
      reads.ledger = (_) => _ledgerHash;
      reads.mintError = const ArbitrumReadException('no RPC');
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      orchestra.orders['q_1'] =
          _order('ord_9', 'processing', recipient: _otherSpark);
      now = now.add(const Duration(seconds: 30));
      await service().reconcile(await only(), force: true);
      final op = await only();
      expect(op.orderId, isNull);
      expect(cctpOf(op).containsKey('submitResult'), isFalse);
      expect(cctpOf(op)['steps'], ['cctp_sent', 'core_confirmed']);
      expect(cctpLegProgressOf(op)!.ordered, isFalse);
      expect(rows.byId.containsKey('ord_9'), isFalse);
      expect(rows.byId.values.single.id, '$kCctpRowPrefix${op.operationId}');
      expect(orchestra.submits, isEmpty);
    });

    test(
        'a submit that never answered but went through counts as submitted '
        'once the order appears; one Orchestra made after a refusal is '
        'detected', () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.mints = [_mint(4800000)];
      orchestra.submitAnswer = () => throw TimeoutException('no answer');
      now = now.add(const Duration(seconds: 20));
      await service().reconcile(await only(), force: true);
      var op = await only();
      expect(orchestra.submits, hasLength(1));
      expect(op.orderId, isNull);
      expect(cctpOf(op)['submitSent'], isTrue);

      // The server took it: the order shows under the quote.
      orchestra.orders['q_1'] = _order('ord_1', 'processing');
      orchestra.orders['ord_1'] = _order('ord_1', 'completed');
      now = now.add(const Duration(seconds: 5));
      await service().reconcile(op, force: true);
      op = await only();
      expect(op.orderId, 'ord_1');
      expect(cctpOf(op)['submitResult'], 'submitted');
      expect(cctpOf(op)['steps'], contains('orchestra_submitted'));
      expect(cctpOf(op)['steps'], isNot(contains('orchestra_detected')));
      expect(orchestra.submits, hasLength(1), reason: 'inside the retry wait');
      now = now.add(const Duration(seconds: 30));
      await service().reconcile(op, force: true);
      final completed =
          events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_completed');
      expect(completed.$2?['submit_result'], 'submitted');
      expect(sender.signed, 1);

      // A second move: the submit refused outright, then Orchestra finds
      // the mint on its own. That order is detected, not submitted.
      await Hive.deleteFromDisk();
      store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
        clock: () => now,
      );
      rows = _Rows();
      orchestra = _Orchestra(() => now);
      sender = _Sender();
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      orchestra.submitAnswer =
          () => (outcome: CctpSubmitOutcome.rejected, orderId: null);
      now = now.add(const Duration(seconds: 20));
      await service().reconcile(await only(), force: true);
      op = await only();
      expect(cctpOf(op)['submitSent'], isFalse);
      orchestra.orders['q_1'] = _order('ord_2', 'processing');
      orchestra.orders['ord_2'] = _order('ord_2', 'processing');
      now = now.add(const Duration(seconds: 5));
      await service().reconcile(op, force: true);
      op = await only();
      expect(op.orderId, 'ord_2');
      expect(cctpOf(op)['submitResult'], 'detected');
      expect(cctpOf(op)['steps'], contains('orchestra_detected'));
    });

    test(
        'the mint search pages in windows, the first window first, and '
        'resumes from the position the record keeps', () async {
      const from = 514276600;
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      var op = await only();
      expect(cctpOf(op)['fromBlock'], from);

      // Hours later: the head is 35,000 blocks on, the mint sits 32,000
      // blocks after the burn. One pass reads three windows and keeps
      // where it got to.
      reads.block = from + 35000;
      reads.mints = [_mint(4800000, _mintTx, from + 32000)];
      now = now.add(const Duration(hours: 3));
      await service().reconcile(op, force: true);
      expect(
          reads.mintReads.map((r) => (r.fromBlock, r.toBlock)).toList(),
          [
            (from, from + 9999),
            (from + 10000, from + 19999),
            (from + 20000, from + 29999),
          ]);
      op = await only();
      expect(cctpOf(op)['mintScannedTo'], from + 29999);
      expect(cctpOf(op).containsKey('mintTx'), isFalse);
      expect(orchestra.submits, isEmpty);

      // A fresh process: the first window again, then on from the kept
      // position (re-reading a little behind it), bounded by the head.
      reads.mintReads.clear();
      orchestra.orders['ord_1'] = _order('ord_1', 'processing');
      now = now.add(const Duration(minutes: 1));
      await service().reconcile(op, force: true);
      expect(
          reads.mintReads.map((r) => (r.fromBlock, r.toBlock)).toList(),
          [(from, from + 9999), (from + 29500, from + 35000)]);
      op = await only();
      expect(cctpOf(op)['mintTx'], _mintTx);
      expect(orchestra.submits.single.txHash, _mintTx);
      expect(op.orderId, 'ord_1');
      expect(named('hyperliquid_withdraw_step'), [
        'cctp_sent',
        'core_confirmed',
        'arbitrum_minted',
        'orchestra_submitted',
      ]);
      expect(sender.signed, 1);
    });

    test(
        'a failed window keeps the position before it; the next pass reads '
        'it again', () async {
      const from = 514276600;
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.block = from + 25000;
      now = now.add(const Duration(hours: 2));
      await service().reconcile(await only(), force: true);
      expect(cctpOf(await only())['mintScannedTo'], from + 25000);
      reads.mintError = const ArbitrumReadException('no RPC');
      reads.block = from + 60000;
      now = now.add(const Duration(hours: 2));
      await service().reconcile(await only(), force: true);
      expect(cctpOf(await only())['mintScannedTo'], from + 25000,
          reason: 'a failed read moves nothing');
      expect((await only()).stage, SettlementStage.needsAttention,
          reason: 'no order this long after the burn: still watched');
    });

    test(
        'the head is read again before the quote; a start the burn never '
        'got is estimated from the time signed when the search runs',
        () async {
      reads.ledger = (_) => _ledgerHash;
      reads.blockErrors = 2;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      expect(reads.blockReads, 3, reason: 'two failures, then the head');
      expect(cctpOf(await only())['fromBlock'], 514276600);
      expect(orchestra.quotes, hasLength(1));

      // A head that never answered before the burn: the record has no
      // start, and the search still runs from where the chain stood when
      // the burn was signed (ten minutes at five blocks a second, with a
      // margin), kept on the record as an estimate.
      await Hive.deleteFromDisk();
      store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
        clock: () => now,
      );
      rows = _Rows();
      reads.blockErrors = 1 << 20;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      var op = await only();
      expect(cctpOf(op).containsKey('fromBlock'), isFalse);
      expect(op.stage, SettlementStage.funded);

      reads.blockErrors = 0;
      reads.block = 514276600 + 3000;
      reads.mints = [_mint(4800000, _mintTx, 514276600 + 2900)];
      orchestra.orders['ord_1'] = _order('ord_1', 'processing');
      now = now.add(const Duration(minutes: 10));
      await service().reconcile(op, force: true);
      const estimated = 514276600 + 3000 - 600 * 5 - 2000;
      expect(reads.mintReads.single.fromBlock, estimated);
      expect(reads.mintReads.single.toBlock, 514276600 + 3000);
      op = await only();
      expect(cctpOf(op)['fromBlock'], estimated);
      expect(cctpOf(op)['fromBlockEstimated'], isTrue);
      expect(cctpOf(op)['mintTx'], _mintTx);
      expect(op.orderId, 'ord_1');
      expect(sender.signed, 2, reason: 'one per move, never twice');
    });

    test('an RPC failure never reads as arrived', () async {
      reads.ledger = (_) => _ledgerHash;
      await service().withdrawToDollars(usd: 5, stepUp: approve());
      reads.mintError = const ArbitrumReadException('no RPC');
      now = now.add(const Duration(minutes: 10));
      await service().reconcile(await only(), force: true);
      final op = await only();
      expect(op.stage, SettlementStage.funded);
      expect(rows.byId.values.single.status, 'exchanging');
      expect(
          named('hyperliquid_withdraw_step'), ['cctp_sent', 'core_confirmed']);
    });
  });

  test(
      'a record an older build paid onto the standing address still '
      'resolves (and shows held money)', () async {
    // The stuck kind: an Investing-withdrawal standing instruction's label,
    // no quote. Nothing new is registered; its deposit listing is read.
    orchestra.held = _record(purpose: 'investments_internal', appFeeBps: 0);
    final created = now;
    final op = await store.create(SettlementOperation(
      operationId: 'legacy-op',
      walletId: 'w',
      accountKind: SettlementAccountKind.hlHot,
      flow: SettlementFlow.investingToDollarsCctp,
      routeVersion: kHypercoreCctpRouteVersion,
      route: kHypercoreToSparkUsdRoute,
      amountInBaseUnits: '200000000',
      recipient: const SettlementAddressRef(
          address: _spark, kind: OwnedAddressKind.sparkSelf),
      refund: const SettlementAddressRef(
          address: _account, kind: OwnedAddressKind.hyperliquidEoa),
      stage: SettlementStage.created,
      createdAt: created,
      updatedAt: created,
      raw: {
        'cctp': {
          'label': orchestra.held!.label,
          'depositAddress': _standing,
          'destination': 'dollars',
          'forwardFee6': '200000',
          'amount6': '2000000',
          'fromBlock': 1,
          'steps': <String>[],
        },
      },
    ));
    await store.transition(op.operationId, SettlementStage.broadcasting,
        from: SettlementStage.created,
        patch: (c) => c.copyWith(
            funding: const SettlementFunding(
                kind: SettlementFundingKind.hyperliquid,
                hlNonce: 1791851727000)));
    reads.ledger = (_) => _ledgerHash;
    orchestra.depositList = [
      {
        'id': 'dep_h',
        'chain': 'arbitrum',
        'asset': 'USDC',
        'amount': '1800000',
        'sourceTxId': '0x${'3' * 64}',
        'observedAt': now.toIso8601String(),
        'status': 'held',
        'code': 'below_minimum',
        'orderId': null,
      }
    ];
    now = now.add(const Duration(seconds: 30));
    await service().reconcile((await store.get('legacy-op'))!, force: true);
    var after = (await store.get('legacy-op'))!;
    expect(after.funding?.evmTxHash, _ledgerHash);
    expect(after.stage, SettlementStage.needsAttention);
    expect(rows.byId['${kStuckStandingDepositRowPrefix}dep_h']!.status, 'held');
    expect(orchestra.quotes, isEmpty);
    expect(orchestra.submits, isEmpty);

    // Flashnet processes it after all: the order shows and settles.
    orchestra.depositList = [
      {
        ...orchestra.depositList.single,
        'status': 'completed',
        'orderId': 'ord_s'
      }
    ];
    orchestra.orders['ord_s'] = _order('ord_s', 'completed', quoteId: null);
    now = now.add(const Duration(minutes: 11));
    await service().reconcile(after, force: true);
    after = (await store.get('legacy-op'))!;
    expect(after.orderId, 'ord_s');
    expect(after.stage, SettlementStage.settled);
    final completed =
        events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_completed');
    expect(completed.$2?['cctp_target'], 'standing');
    expect(completed.$2?.containsKey('submit_result'), isFalse);
  });

  test('a paused CoreDepositWallet stops before anything is quoted or signed',
      () async {
    reads.paused = true;
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<CctpUnavailable>()
            .having((e) => e.reason, 'reason', CctpUnavailableReason.paused)));
    expect(sender.sends, isEmpty);
    expect(orchestra.quotes, isEmpty);
    expect(intents, isEmpty);
    expect(await store.all(), isEmpty);
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

  test('a declined approval stops before quoting or signing', () async {
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve(answer: false)),
        throwsA(isA<SettlementStopped>()));
    expect(orchestra.quotes, isEmpty);
    expect(sender.sends, isEmpty);
    expect(await store.all(), isEmpty);
  });

  test('a refusal before the POST ends the record and its row', () async {
    sender.mode = _SendMode.refused;
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<SettlementFundingRefused>()
            .having((e) => e.cause, 'cause', isA<StateError>())));
    expect((await only()).stage, SettlementStage.abandoned);
    expect(rows.byId, isEmpty);
  });

  test(
      'a cash shortfall found after the approval keeps its proof: not sent, '
      'never an unknown outcome', () async {
    // Perpetuals came up short between the read and the burn: refused
    // before the POST, after the approval already fired.
    sender.mode = _SendMode.refused;
    sender.refusal = HypercoreBalanceShortfall();
    Object? thrown;
    try {
      await service().withdrawToDollars(usd: 5, stepUp: approve());
    } catch (e) {
      thrown = e;
    }
    expect(intents, hasLength(1), reason: 'approved before the stop');
    expect(thrown, isA<SettlementFundingRefused>());
    final refused = thrown! as SettlementFundingRefused;
    expect(refused.cause, isA<HypercoreBalanceShortfall>());
    // What the Move sheet and the rails read from it, once funding
    // started: proof that nothing left, the shortfall as its category.
    expect(moneyMovementProvesNothingSent(refused, fundingStarted: true),
        isTrue);
    expect(
        moneyMovementFailureReason(refused, fundingStarted: true), 'not_sent');
    expect(TrackingService.errorCategory(refused.cause), 'insufficient_funds');
    expect((await only()).stage, SettlementStage.abandoned);
    expect(rows.byId, isEmpty);
    expect(sender.signed, 0);
  });

  test('a stop between the nonce write and the POST is not funded', () async {
    sender.mode = _SendMode.refusedAfterNonce;
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve()),
        throwsA(isA<SettlementFundingRefused>()
            .having((e) => e.cause, 'cause', isA<StateError>())));
    final op = await only();
    expect(op.stage, SettlementStage.notFunded);
    expect(rows.byId.values.single.status, 'expired');
  });

  test('restart after the nonce was recorded: no ledger row means not funded',
      () async {
    sender.mode = _SendMode.lostAfterPost;
    reads.ledger = (_) => null;
    final result = await service().withdrawToDollars(usd: 5, stepUp: approve());
    expect(result.operationId, isNotEmpty);
    var op = await only();
    expect(op.stage, SettlementStage.broadcasting);
    expect(op.funding?.hlNonce, sender.nonce);

    await service().reconcile(op, force: true);
    expect((await only()).stage, SettlementStage.broadcasting);

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

  test('one CCTP move at a time until the earlier one is at Orchestra',
      () async {
    reads.ledger = (_) => _ledgerHash;
    await service().withdrawToDollars(usd: 5, stepUp: approve());
    await expectLater(
        service().withdrawToDollars(usd: 5, stepUp: approve()),
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
    expect(
        sender.sends.single.token, 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054');
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
