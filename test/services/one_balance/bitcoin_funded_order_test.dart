// An order funded from bitcoin (founder decision 14 October 2026): after
// the one approval the chain runs headless — Bitcoin → Dollars under the
// order's grant, the landing, Dollars → the venue under the SAME grant,
// the venue's autofire. Every stop leaves the money where the person can
// see it, never on a rail without a line, and never places anything the
// chain did not reach.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementFundingUnknown,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/tracking_service.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _foreignSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
final _now = DateTime.utc(2026, 9, 15, 12);

VerifiedOrchestraQuote _quote({String recipient = _ownSpark, int sats = 100000}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'spark',
        destinationAsset: 'USDB',
        amountBaseUnits: BigInt.from(sats),
        recipientAddress: recipient,
        refundAddress: recipient,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: recipient,
      ),
      OrchestraQuote.fromJson({
        'quoteId': 'q_btc',
        'depositAddress': _foreignSpark,
        'amountIn': '$sats',
        'estimatedOut': '${sats * 600}',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': 'USDB',
        'route': ['spark:BTC', 'spark:USDB'],
        'expiresAt': '2026-09-15T12:02:00Z',
        'priceLockMode': 'floating',
      }),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: sats * 600.0),
      mainnet: true,
    );

AuthGrant _grant({int maxSats = 120000}) => AuthGrants.issue(
      PmGrants.fundedBetReview(
        PmGrants.betReview(
            walletId: 'w',
            tokenId: 'tok',
            maxCostUsd: 5.2,
            worstPrice: 0.6,
            orderType: 'fak'),
        fundUsd: 5.3,
        venue: 'polymarket',
        btcLeg: BitcoinLegGrants.limit(maxSats: maxSats, ownSpark: _ownSpark),
      ).copyWith(ttl: AuthGrants.autofireTtl),
      method: AuthGrantMethod.biometric,
      now: _now,
    );

const _plan = BitcoinLegPlan(
  dollarsShortUsd: 5,
  targetUsd: 5.1,
  sats: 100000,
  maxSats: 105000,
  usdPerBtc: 60000,
);

const _label = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 5,
  side: 'Yes',
  market: 'Lakers vs Celtics',
  marketKey: 'tok',
);

/// A watcher that answers [outcome] when asked.
class _Watcher extends DollarsLandingWatcher {
  _Watcher(this.outcome, {this.slow = false})
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );
  final DollarsLandingOutcome outcome;
  final bool slow;
  int watched = 0;
  double? baseline;

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async {
    watched++;
    baseline = baselineUsd;
    if (slow) onSlow?.call();
    return outcome;
  }
}

class _Env {
  _Env({
    this.landing = const DollarsLanded(byStatus: true, freshDollarsUsd: 6),
    this.quote,
    this.sendError,
    this.slow = false,
  });
  final DollarsLandingOutcome landing;
  final VerifiedOrchestraQuote? quote;
  final Object? sendError;
  final bool slow;
  var sends = 0;
  var paid = 0;
  late final _Watcher watcher = _Watcher(landing, slow: slow);
  double dollars = 1;

  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          sends++;
          final q = quote ?? _quote();
          // The runner's own hook, against the verified quote, exactly as
          // the settlement runner calls it before any payment.
          final ok = await stepUp(SettlementAuthorizationIntent(
            flow: SettlementFlow.moveBtcToUsdc,
            walletId: 'w',
            destination: '${q.request.recipientAddress}|',
            routeLabel: BitcoinLegGrants.route,
            amountIn: q.amountIn,
            minReceive: BigInt.zero,
            maxFeeBps: 0,
            reviewedQuote: q,
          ));
          if (!ok) throw const SettlementStopped(SettlementStopReason.declined);
          if (sendError != null) throw sendError!;
          onSending();
          paid++;
          return const BitcoinLegTicket(
              quoteId: 'q_btc', sats: 100000, estimatedOutUsd: 6, minOutUsd: 6);
        },
        watcher: ({required DateTime since}) => watcher,
        dollarsNow: () => dollars,
        freshDollars: () async => dollars,
      );
}

class _Funder implements VenueFunder {
  final sent = <double>[];
  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    sent.add(usd);
    return VenueMoveResult(
        quoteId: 'q_venue', orderId: 'o_venue', sentUsd: usd, arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

void main() {
  late List<(String, Map<String, Object>?)> events;
  late _Funder funder;

  setUp(() {
    AuthGrants.clock = () => _now;
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    funder = _Funder();
  });
  tearDown(() {
    AuthGrants.clock = DateTime.now;
    FundedOrdersNotifier.persist = true;
    TrackingService.debugTrackObserver = null;
  });

  ProviderContainer containerFor(_Env env, {double dollars = 0}) {
    final c = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(env.env),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => funder, dollarsUsd: () => dollars)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ({BitcoinFundedOrderRequest request, List<String> calls}) request(
    AuthGrant grant, {
    Future<OrderFundingOutcome> Function(OrderFundingController c)? fundVenue,
    bool placed = true,
    void Function()? onCredit,
  }) {
    final calls = <String>[];
    return (
      calls: calls,
      request: BitcoinFundedOrderRequest(
        venue: OneBalanceVenue.predictions,
        grant: grant,
        plan: _plan,
        label: _label,
        fundUsd: 5.3,
        readyUsd: 0,
        entrySource: 'market',
        fundVenue: (controller,
            {required bitcoinSentAt, required bitcoinLandedAt}) async {
          calls.add('fund');
          if (fundVenue != null) return fundVenue(controller);
          return controller.fundAndQueue(
            venue: OneBalanceVenue.predictions,
            orderUsd: 5,
            requiredUsd: 5.3,
            readyUsd: 0,
            auth: UserGrantAuthorization(grant),
            fundUsd: 5.3,
            continueJourney: true,
          );
        },
        dropOrder: () => calls.add('drop'),
        awaitPlacement: ({required onCredited}) async {
          calls.add('await');
          onCredited();
          onCredit?.call();
          return placed;
        },
      ),
    );
  }

  test(
      'the whole chain under one grant: bitcoin, then the venue move with '
      'the fresh balance, then the venue places it', () async {
    final env = _Env();
    final c = containerFor(env);
    final grant = _grant();
    final r = request(grant);
    final run = c.read(bitcoinFundedOrderRunnerProvider).start(r.request);
    // The record is written at once, at the first step.
    expect(c.read(fundedOrdersProvider).single.stage, FundedOrderStage.adding);
    expect(await run.ended, BitcoinFundedEnd.placed);
    expect(env.paid, 1);
    // The controller read the fresh balance the dollars landed in (6),
    // not the shown one (0): the venue move went out under the same grant.
    expect(funder.sent, [5.3]);
    expect(r.calls, ['fund', 'await']);
    expect(BitcoinLegGrants.takenBy(grant), isTrue);
    final record = c.read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(record.btcRowIds, contains('q_btc'));
    expect(record.venueRowIds, containsAll(['q_venue', 'o_venue']));
    // One journey, tagged bitcoin, exact amounts, no ids.
    final started =
        events.where((e) => e.$1 == 'order_funding_started').toList();
    expect(started, hasLength(1));
    expect(started.single.$2!['funding_source'], 'bitcoin');
    expect(started.single.$2!['add_usd'], 5.1);
    expect(started.single.$2!['add_sats'], 100000);
    expect(
        events.any((e) =>
            e.$1 == 'order_funding_step' &&
            e.$2!['step'] == 'bitcoin' &&
            e.$2!['funding_source'] == 'bitcoin'),
        isTrue);
    for (final e in events) {
      final params = e.$2 ?? const {};
      expect(params.values.whereType<String>().where((v) => v.contains('spark1')),
          isEmpty);
    }
  });

  test('a quote paying someone else is refused: nothing moves, no order',
      () async {
    final env = _Env(quote: _quote(recipient: _foreignSpark));
    final c = containerFor(env);
    final r = request(_grant());
    final run = c.read(bitcoinFundedOrderRunnerProvider).start(r.request);
    expect(await run.ended, BitcoinFundedEnd.notSent);
    expect(env.paid, 0);
    expect(funder.sent, isEmpty);
    expect(r.calls, ['drop']);
    expect(c.read(fundedOrdersProvider).single.stage, FundedOrderStage.failed);
    expect(
        events.any((e) =>
            e.$1 == 'order_funding_failed' && e.$2!['stage'] == 'bitcoin'),
        isTrue);
  });

  test('more sats than approved are refused before anything moves',
      () async {
    final env = _Env();
    final c = containerFor(env);
    final r = request(_grant(maxSats: 50000));
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.notSent);
    expect(env.paid, 0);
    expect(funder.sent, isEmpty);
  });

  test('an expired grant moves nothing', () async {
    final env = _Env();
    final c = containerFor(env);
    final grant = _grant();
    AuthGrants.clock = () => _now.add(const Duration(hours: 1));
    final r = request(grant);
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.notSent);
    expect(env.paid, 0);
  });

  test('an unknown payment outcome is never resent nor placed', () async {
    final env = _Env(sendError: const SettlementFundingUnknown('op', 'x'));
    final c = containerFor(env);
    final r = request(_grant());
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.maybeSent);
    expect(env.sends, 1);
    expect(r.calls, ['drop']);
    expect(c.read(fundedOrdersProvider).single.stage, FundedOrderStage.ready);
  });

  test('a refunded leg: the bitcoin comes back, no venue move, no order',
      () async {
    final env = _Env(landing: const DollarsLegFailed('refunded'));
    final c = containerFor(env);
    final r = request(_grant());
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.refunded);
    expect(funder.sent, isEmpty);
    expect(r.calls, ['drop']);
    expect(c.read(fundedOrdersProvider).single.reason, 'refunded');
  });

  test(
      'dollars too slow: the order goes, the money lands in Dollars, '
      'the slip says tap to place', () async {
    final env = _Env(landing: const DollarsLandingTimedOut(), slow: true);
    final c = containerFor(env);
    final r = request(_grant());
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.ready);
    expect(funder.sent, isEmpty);
    expect(r.calls, ['drop']);
    final record = c.read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.ready);
    expect(record.reason, 'timeout');
    expect(
        FundedOrdersNotifier.readyOn(c.read(fundedOrdersProvider),
            OneBalanceVenue.predictions, 'tok', DateTime.now()),
        isNotNull);
  });

  test(
      'the venue move refused: the money stays in Dollars, no order, a '
      'clear ready state', () async {
    final env = _Env();
    final c = containerFor(env);
    final r = request(_grant(),
        fundVenue: (_) async => const OrderFundingRefused('no_route'));
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.ready);
    expect(r.calls, ['fund', 'drop']);
    final record = c.read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.ready);
    expect(record.reason, 'venue_refused');
  });

  test(
      'the venue does not place it (the price moved past what was '
      'approved): the run stops, the money stays at the venue', () async {
    final env = _Env();
    final c = containerFor(env);
    final r = request(_grant(), placed: false);
    expect(await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended,
        BitcoinFundedEnd.placementFailed);
    // The order's own retry (at the new price) is the venue's: nothing is
    // dropped and no money comes back by itself.
    expect(r.calls, ['fund', 'await']);
    expect(c.read(fundedOrdersProvider).single.reason, 'placement');
  });

  test('the stages advance: adding, preparing, placing, done', () async {
    final env = _Env();
    final c = containerFor(env);
    final stages = <FundedOrderStage>[];
    c.listen<List<FundedOrderRecord>>(fundedOrdersProvider, (_, next) {
      if (next.isEmpty) return;
      final s = next.first.stage;
      if (stages.isEmpty || stages.last != s) stages.add(s);
    }, fireImmediately: true);
    final r = request(_grant());
    await c.read(bitcoinFundedOrderRunnerProvider).start(r.request).ended;
    expect(stages, [
      FundedOrderStage.adding,
      FundedOrderStage.preparing,
      FundedOrderStage.placing,
      FundedOrderStage.done,
    ]);
  });

  test('a second funded order on the venue is seen while one runs', () async {
    final gate = Completer<DollarsLandingOutcome>();
    final env = _Env();
    final r = request(_grant());
    // Hold the landing open.
    final hold = BitcoinLegEnv(
      ownSpark: env.env.ownSpark,
      send: env.env.send,
      watcher: ({required DateTime since}) => _GateWatcher(gate.future),
      dollarsNow: () => 0,
      freshDollars: () async => 0,
    );
    final c2 = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(hold),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => funder, dollarsUsd: () => 0)),
    ]);
    addTearDown(c2.dispose);
    final run = c2.read(bitcoinFundedOrderRunnerProvider).start(r.request);
    await Future<void>.delayed(Duration.zero);
    expect(
        FundedOrdersNotifier.activeOf(
            c2.read(fundedOrdersProvider), OneBalanceVenue.predictions),
        isNotNull);
    gate.complete(const DollarsLandingTimedOut());
    await run.ended;
    expect(
        FundedOrdersNotifier.activeOf(
            c2.read(fundedOrdersProvider), OneBalanceVenue.predictions),
        isNull);
  });

  group('DollarsLandingWatcher', () {
    test('the status says delivered first: landed once the fresh balance '
        'shows it, the sync kicked and never awaited', () {
      fakeAsync((async) {
        var fresh = 1.0;
        var kicks = 0;
        String? polled;
        final w = DollarsLandingWatcher(
          statusOf: (id) async {
            polled = id;
            return 'completed';
          },
          dollarsNow: () => 1,
          freshDollars: () async => fresh,
          kickSync: () => kicks++,
        );
        DollarsLandingOutcome? out;
        w
            .watch(
                id: () => 'ord_1',
                baselineUsd: 1,
                minRiseUsd: 5,
                enoughUsd: 6.3)
            .then((o) => out = o);
        async.elapse(const Duration(seconds: 1));
        expect(polled, 'ord_1');
        expect(kicks, 1);
        expect(out, isNull); // the cache has not caught up yet
        fresh = 6.5;
        async.elapse(const Duration(milliseconds: 300));
        expect(out, isA<DollarsLanded>());
        expect((out! as DollarsLanded).byStatus, isTrue);
        expect((out! as DollarsLanded).freshDollarsUsd, 6.5);
      });
    });

    test('the balance rises past the quoted amount first: landed', () {
      fakeAsync((async) {
        final changes = StreamController<double>();
        final w = DollarsLandingWatcher(
          statusOf: (_) async => 'processing',
          dollarsNow: () => 1,
          freshDollars: () async => 7,
          kickSync: () {},
          dollarsChanges: changes.stream,
        );
        DollarsLandingOutcome? out;
        w
            .watch(
                id: () => 'q',
                baselineUsd: 1,
                minRiseUsd: 5.99,
                enoughUsd: 6.3)
            .then((o) => out = o);
        changes.add(7);
        async.flushMicrotasks();
        expect(out, isA<DollarsLanded>());
        expect((out! as DollarsLanded).byStatus, isFalse);
        changes.close();
      });
    });

    test('a refunded order ends the wait at once', () {
      fakeAsync((async) {
        final w = DollarsLandingWatcher(
          statusOf: (_) async => 'refunded',
          dollarsNow: () => 1,
          freshDollars: () async => 1,
          kickSync: () {},
        );
        DollarsLandingOutcome? out;
        w
            .watch(id: () => 'q', baselineUsd: 1, minRiseUsd: 5, enoughUsd: 6)
            .then((o) => out = o);
        async.elapse(const Duration(seconds: 1));
        expect(out, isA<DollarsLegFailed>());
      });
    });

    test('slow after two minutes, gives up after twelve', () {
      fakeAsync((async) {
        var slow = 0;
        final w = DollarsLandingWatcher(
          statusOf: (_) async => null,
          dollarsNow: () => 1,
          freshDollars: () async => 1,
          kickSync: () {},
        );
        DollarsLandingOutcome? out;
        w
            .watch(
                id: () => 'q',
                baselineUsd: 1,
                minRiseUsd: 5,
                enoughUsd: 6,
                onSlow: () => slow++)
            .then((o) => out = o);
        async.elapse(const Duration(seconds: 119));
        expect(slow, 0);
        async.elapse(const Duration(seconds: 1));
        expect(slow, 1);
        expect(out, isNull);
        async.elapse(const Duration(minutes: 10));
        expect(out, isA<DollarsLandingTimedOut>());
        expect(slow, 1);
      });
    });
  });

  group('sizing', () {
    test('covers the shortfall plus a buffer, rounded up, within the bitcoin',
        () {
      final s = BitcoinLegRules.size(
          dollarsShortUsd: 4.2, usdPerBtc: 60000, availableSats: 1000000);
      final plan = s.plan!;
      expect(plan.targetUsd, 4.3); // 4.2 + max(1%, $0.10)
      expect(plan.sats * 60000 / 1e8, greaterThan(plan.targetUsd));
      expect(plan.maxSats, greaterThan(plan.sats));
    });

    test('never under the route minimum', () {
      final plan = BitcoinLegRules.size(
              dollarsShortUsd: 0.2, usdPerBtc: 60000, availableSats: 1000000)
          .plan!;
      expect(plan.targetUsd, 1.0);
    });

    test('refused when the bitcoin does not cover it, or without a price', () {
      expect(
          BitcoinLegRules.size(
                  dollarsShortUsd: 50, usdPerBtc: 60000, availableSats: 10000)
              .refusal,
          BitcoinLegRefusal.insufficientBitcoin);
      expect(
          BitcoinLegRules.size(
                  dollarsShortUsd: 5, usdPerBtc: 0, availableSats: 1000000)
              .refusal,
          BitcoinLegRefusal.noPrice);
    });

    test('the approval cap never exceeds the wallet', () {
      final plan = BitcoinLegRules.size(
              dollarsShortUsd: 5, usdPerBtc: 60000, availableSats: 8800)
          .plan!;
      expect(plan.maxSats, lessThanOrEqualTo(8800));
    });
  });
}

class _GateWatcher extends DollarsLandingWatcher {
  _GateWatcher(this.gate)
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );
  final Future<DollarsLandingOutcome> gate;

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) =>
      gate;
}
