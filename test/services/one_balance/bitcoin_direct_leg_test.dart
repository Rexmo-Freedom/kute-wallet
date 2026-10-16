// Bitcoin straight into the venue (founder decision 15 October 2026: "it
// should go directly into polymarket or hyperliquid if i am there already
// and i have no usdb balance ... we must parallelize these things
// decently"): the planner's rules, the grant pinning the own deposit, the
// delivered-wrap the Predictions row triggers, and the funded-order chain
// running every leg at once with its fallback to the via-Dollars chain.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/predictions_deposit_wrap.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/margin_funding.dart'
    show MarginFundingPlan;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        DirectRouteRefusals,
        venueCashPullerProvider,
        planDollarsShortfall,
        VenueCashSource,
        VenueCashPuller,
        VenueCashPull,
        VenueCashLegOutcome,
        VenueCashPullOutcome,
        VenueCashPlan;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_funded_order.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/tracking_service.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherEvm = '0x0000000000000000000000000000000000000001';
final _now = DateTime.utc(2026, 9, 15, 12);

OrchestraQuote _fixture() => OrchestraQuote.fromJson(jsonDecode(
    File('test/services/fixtures/orchestra_quote_spark_to_polygon.json')
        .readAsStringSync()) as Map<String, dynamic>);

/// spark:BTC → polygon:USDC.e to [recipient], verified by the quote gate.
VerifiedOrchestraQuote _directQuote({String recipient = _pmWallet}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amountBaseUnits: BigInt.from(100000),
        recipientAddress: recipient,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownPmWallet,
        ownAddress: recipient,
      ),
      _fixture(),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: 60000000),
      mainnet: true,
    );

SettlementAuthorizationIntent _directIntent(VerifiedOrchestraQuote q,
        {String? recipient,
        String route = BitcoinLegGrants.directPredictionsRoute}) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.moveBtcToPredictions,
      walletId: 'w',
      destination: '${recipient ?? q.request.recipientAddress}|v1',
      routeLabel: route,
      amountIn: q.amountIn,
      minReceive: BigInt.zero,
      maxFeeBps: 200,
      reviewedQuote: q,
    );

AuthGrant _grant({String? ownVenue = _pmWallet, int directMaxSats = 120000}) =>
    AuthGrants.issue(
      PmGrants.fundedBetReview(
        PmGrants.betReview(
            walletId: 'w',
            tokenId: 'tok',
            maxCostUsd: 15.5,
            worstPrice: 0.6,
            orderType: 'fak'),
        fundUsd: 15.1,
        venue: 'polymarket',
        btcLeg: BitcoinLegGrants.limitWithDirect(
            maxSats: 120000,
            ownSpark: _ownSpark,
            venue: 'predictions',
            ownVenue: ownVenue,
            directMaxSats: directMaxSats),
      ).copyWith(ttl: AuthGrants.autofireTtl),
      method: AuthGrantMethod.biometric,
      now: _now,
    );

/// The founder's case: $15 on Polymarket, no Dollars, from Bitcoin at
/// $15,000 a bitcoin (so 100,000 sats are $15).
const _via = BitcoinLegPlan(
  dollarsShortUsd: 15.1,
  targetUsd: 15.1,
  sats: 102000,
  maxSats: 107100,
  usdPerBtc: 15000,
);

const _label = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 15,
  side: 'Yes',
  market: 'Lakers vs Celtics',
  marketKey: 'tok',
);

void main() {
  setUp(() {
    AuthGrants.clock = () => _now;
    DirectRouteRefusals.reset();
  });
  tearDown(() => AuthGrants.clock = DateTime.now);

  for (final home in [false, true]) {
    for (final status in ['refunded', 'failed', 'completed']) {
      test(
          'Bitcoin mixed source ${home ? 'via Dollars' : 'direct'} $status '
          'reconciles only its proved outcome', () async {
        final h = _Harness(
            sourceStatus: status,
            sourceHome: home,
            plan: const DirectBitcoinPlan.direct(
                targetUsd: 15.01,
                sats: 100000,
                dollarsUsd: 0,
                bitcoinShareUsd: 12.1,
                otherUsd: 3,
                directCostUsd: 15,
                viaCostUsd: 15.3));
        final run = h.start();
        await run.ended;
        double available() => h.c
            .read(venueCashLastReadProvider)!
            .candidates
            .singleWhere((s) => s.venue == OneBalanceVenue.investing)
            .availableUsd;
        await h.until(
            () => (available() - (status == 'refunded' ? 5 : 2)).abs() < 1e-6);
        expect(available(), closeTo(status == 'refunded' ? 5 : 2, 1e-6));
        if (status == 'completed') {
          expect(h.record.steps.byId('leg:investing')!.status,
              MoneyStepStatus.done);
        }
      });
    }
  }

  test('stale requests never replace a newer live graph before binding',
      () async {
    FundedOrdersNotifier.persist = false;
    addTearDown(() => FundedOrdersNotifier.persist = true);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final orders = c.read(fundedOrdersProvider.notifier);
    final active = orders.start(_label, stage: FundedOrderStage.preparing);
    final before = orders.byId(active);
    var binds = 0;
    final bitcoin = c
        .read(bitcoinFundedOrderRunnerProvider)
        .start(BitcoinFundedOrderRequest(
          venue: OneBalanceVenue.predictions,
          grant: _grant(),
          plan: _via,
          label: _label,
          fundUsd: 15.1,
          readyUsd: 0,
          isCurrentAttempt: () => false,
          bindAttempt: (_) {
            binds++;
            return false;
          },
          fundVenue: (_, __) async => throw StateError('must never fund'),
          dropOrder: () => throw StateError('must not clear new attempt'),
        ));
    expect(await bitcoin.ended, BitcoinFundedEnd.notSent);
    expect(identical(orders.byId(active), before), isTrue);
    final venue =
        c.read(venueCashFundedOrderRunnerProvider).start(VenueCashFundedRequest(
              venue: OneBalanceVenue.predictions,
              grant: _grant(),
              label: _label,
              fundUsd: 15.1,
              readyUsd: 0,
              plan: planDollarsShortfall(
                  neededUsd: 15.1, dollarsUsd: 15.1, sources: []),
              isCurrentAttempt: () => false,
              bindAttempt: (_) {
                binds++;
                return false;
              },
              queue: ({required fundUsd, required readyUsd}) async =>
                  throw StateError('must never queue'),
              fundMore: (_, __) async => throw StateError('must never fund'),
              dropOrder: () => throw StateError('must not clear new attempt'),
            ));
    expect(await venue.ended, BitcoinFundedEnd.notSent);
    expect(identical(orders.byId(active), before), isTrue);
    expect(c.read(fundedOrdersProvider), hasLength(1));
    expect(binds, 0);
  });

  // ── The planner ─────────────────────────────────────────────────────
  group('planDirectBitcoinLeg', () {
    test(
        'a cold Dollars limit read starts alongside the direct route estimates',
        () async {
      final limit = Completer<double>();
      final reads = <String>[];
      final pending = planDirectBitcoinLeg(
        fundUsd: 15.1,
        addUsd: 14.1,
        dollarsUsd: 1,
        via: _via,
        availableSats: 1000000,
        directMaxSats: 200000,
        venueArriving: (usd) async {
          reads.add('dollars_estimate');
          return usd * 0.994;
        },
        directOutUsd: (sats) async {
          reads.add('direct_estimate');
          return sats / 1e8 * 15000 * 0.99;
        },
        directMinimumUsd: () async => 1,
        dollarsMinimumUsd: 1,
        readDollarsMinimumUsd: () => limit.future,
      );
      expect(
          reads, ['dollars_estimate', 'dollars_estimate', 'direct_estimate']);
      limit.complete(1);
      expect((await pending).direct, isTrue);
    });
    test(
        'Bitcoin-only Investing uses the reviewed arrival without a Dollars route read',
        () async {
      final p = await planDirectBitcoinLeg(
        fundUsd: 10.93,
        addUsd: 10.93,
        dollarsUsd: 0,
        via: _via,
        availableSats: 1000000,
        directMaxSats: 200000,
        venueTargetUsd: 10.71,
        venueArriving: (_) => throw StateError('Dollars endpoint unavailable'),
        directOutUsd: (sats) async => sats / 1e8 * 15000 * 0.99,
        directMinimumUsd: () async => 1,
        dollarsMinimumUsd: 1,
        readDollarsMinimumUsd: () =>
            throw StateError('Dollars limit unavailable'),
      );
      expect(p.direct, isTrue);
      expect(p.targetUsd, 10.71);
      expect(p.dollarsUsd, 0);
      expect(p.directCostUsd! <= p.viaCostUsd!, isTrue);
    });
    // Dollars → Predictions keeps 0.6%; Bitcoin → Predictions straight
    // keeps [directSpread] (its spread with Kute's fee).
    Future<DirectBitcoinPlan> plan({
      required double fundUsd,
      required double addUsd,
      required double dollars,
      double directSpread = 0.01,
      double minimum = 1,
      int maxSats = 200000,
      bool estimate = true,
      BitcoinLegPlan via = _via,
    }) =>
        planDirectBitcoinLeg(
          fundUsd: fundUsd,
          addUsd: addUsd,
          dollarsUsd: dollars,
          via: via,
          availableSats: 1000000,
          directMaxSats: maxSats,
          venueArriving: (usd) async => usd * 0.994,
          directOutUsd: (sats) async =>
              estimate ? sats / 1e8 * 15000 * (1 - directSpread) : null,
          directMinimumUsd: () async => minimum,
          dollarsMinimumUsd: 1,
        );

    test(
        'Bitcoin only, venue empty, no Dollars: one direct leg for what '
        'must land, no Dollars leg', () async {
      final p = await plan(fundUsd: 15.1, addUsd: 15.1, dollars: 0);
      expect(p.direct, isTrue);
      expect(p.dollarsUsd, 0);
      expect(p.otherUsd, 0);
      // What the full move would land (15.1 less 0.6%), to the cent.
      expect(p.targetUsd, 15.01);
      // Dollars carry none of the move.
      expect(p.bitcoinShareUsd, 15.1);
      // Sized on the route's own price with the arrival buffer.
      expect(p.sats, (15.01 / (15000 * 0.99 / 1e8) * 1.003).ceil());
      expect(p.directCostUsd! <= p.viaCostUsd!, isTrue);
    });

    test(
        'Dollars + Bitcoin: Dollars give what they hold, Bitcoin lands the '
        'rest straight in', () async {
      final via = const BitcoinLegPlan(
          dollarsShortUsd: 10.1,
          targetUsd: 10.1,
          sats: 68000,
          maxSats: 71400,
          usdPerBtc: 15000);
      final p = await plan(fundUsd: 15.1, addUsd: 10.1, dollars: 5, via: via);
      expect(p.direct, isTrue);
      expect(p.dollarsUsd, 5);
      // 15.0094 must land; Dollars' 5 land 4.97.
      expect(p.targetUsd, 10.04);
      expect(p.bitcoinShareUsd, 10.1);
    });

    test(
        'never costs more than the chain: a pricier direct route goes via '
        'Dollars', () async {
      final p = await plan(
          fundUsd: 15.1, addUsd: 15.1, dollars: 0, directSpread: 0.05);
      expect(p.direct, isFalse);
      expect(p.reason, DirectBitcoinReason.costlier);
      expect(p.directCostUsd! > p.viaCostUsd!, isTrue);
    });

    test('no estimate, or over the approval cap: via Dollars', () async {
      expect(
          (await plan(fundUsd: 15.1, addUsd: 15.1, dollars: 0, estimate: false))
              .reason,
          DirectBitcoinReason.noEstimate);
      expect(
          (await plan(fundUsd: 15.1, addUsd: 15.1, dollars: 0, maxSats: 1000))
              .reason,
          DirectBitcoinReason.overCap);
    });

    group('a Bitcoin share under the direct route minimum', () {
      const smallVia = BitcoinLegPlan(
          dollarsShortUsd: 1.1,
          targetUsd: 1.1,
          sats: 7500,
          maxSats: 7900,
          usdPerBtc: 15000);
      test('folds: Bitcoin takes the minimum, Dollars send that much less',
          () async {
        final p = await plan(
            fundUsd: 15.1,
            addUsd: 1.1,
            dollars: 14,
            minimum: 5,
            directSpread: 0.001,
            via: smallVia);
        expect(p.direct, isTrue);
        expect(p.folded, isTrue);
        expect(p.targetUsd, 5);
        expect(p.dollarsUsd, closeTo(10.1, 0.011));
      });

      test(
          'a Dollars share left under its own minimum goes too: Bitcoin '
          'covers it all, no Dollars needed', () async {
        const via = BitcoinLegPlan(
            dollarsShortUsd: 4.6,
            targetUsd: 4.6,
            sats: 31000,
            maxSats: 32600,
            usdPerBtc: 15000);
        final p = await plan(
            fundUsd: 5.1,
            addUsd: 4.6,
            dollars: 0.5,
            minimum: 4.9,
            directSpread: 0.002,
            via: via);
        expect(p.direct, isTrue);
        expect(p.folded, isTrue);
        expect(p.dollarsUsd, 0);
        expect(p.targetUsd, closeTo(5.1 * 0.994, 0.011));
      });

      test('folding that costs more than the chain: via Dollars', () async {
        final p = await plan(
            fundUsd: 15.1,
            addUsd: 1.1,
            dollars: 14,
            minimum: 5,
            directSpread: 0.02,
            via: smallVia);
        expect(p.direct, isFalse);
      });
    });
  });

  // ── The grant ───────────────────────────────────────────────────────
  group('the one approval pins the own venue deposit', () {
    test(
        'a direct leg to the own deposit is covered once; the via leg can '
        'no longer run under the same grant', () {
      final grant = _grant();
      expect(BitcoinLegGrants.directTo(grant)?.toLowerCase(),
          _pmWallet.toLowerCase());
      final intent = _directIntent(_directQuote());
      expect(
          BitcoinLegGrants.coversDirect(grant, intent,
              ownVenue: _pmWallet, ownSpark: _ownSpark),
          isTrue);
      expect(
          BitcoinLegGrants.takeDirect(grant, intent,
              ownVenue: _pmWallet, ownSpark: _ownSpark),
          isTrue);
      // Single use, shared with the via leg.
      expect(
          BitcoinLegGrants.takeDirect(grant, intent,
              ownVenue: _pmWallet, ownSpark: _ownSpark),
          isFalse);
      expect(BitcoinLegGrants.takenBy(grant), isTrue);
    });

    test(
        'anyone else\'s address, another route, more sats, or a grant '
        'without the direct leg: refused', () {
      // A quote paying another account than the one bound.
      final foreign = _directIntent(_directQuote(recipient: _otherEvm));
      expect(
          BitcoinLegGrants.coversDirect(_grant(), foreign,
              ownVenue: _otherEvm, ownSpark: _ownSpark),
          isFalse);
      // The bound deposit, but the wallet now reads another one.
      expect(
          BitcoinLegGrants.coversDirect(_grant(), _directIntent(_directQuote()),
              ownVenue: _otherEvm, ownSpark: _ownSpark),
          isFalse);
      // The Investing route under a Predictions binding.
      expect(
          BitcoinLegGrants.coversDirect(
              _grant(),
              _directIntent(_directQuote(),
                  route: BitcoinLegGrants.directInvestingRoute),
              ownVenue: _pmWallet,
              ownSpark: _ownSpark),
          isFalse);
      // More sats than the direct cap.
      expect(
          BitcoinLegGrants.coversDirect(
              _grant(directMaxSats: 99999), _directIntent(_directQuote()),
              ownVenue: _pmWallet, ownSpark: _ownSpark),
          isFalse);
      // No own deposit could be read when it was approved: no direct leg.
      final viaOnly = _grant(ownVenue: null);
      expect(BitcoinLegGrants.directTo(viaOnly), isNull);
      expect(
          BitcoinLegGrants.coversDirect(viaOnly, _directIntent(_directQuote()),
              ownVenue: _pmWallet, ownSpark: _ownSpark),
          isFalse);
      // The refund must be the own Spark address.
      expect(
          BitcoinLegGrants.coversDirect(_grant(), _directIntent(_directQuote()),
              ownVenue: _pmWallet,
              ownSpark:
                  'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2'),
          isFalse);
    });

    test('margin binds the direct leg to the own Investing account', () {
      const plan = MarginFundingPlan(
        amountUsd: 20,
        readyUsd: 2,
        fundUsd: 19.5,
        dollarsUsd: 0,
        bitcoin: _via,
        ownSpark: _ownSpark,
        ownInvesting: _otherEvm,
      );
      final limits = plan.grantLimits()[VenueLimit.fundBtc] as Map;
      final direct = limits['direct'] as Map;
      expect(direct['to'], _otherEvm);
      expect(direct['route'], BitcoinLegGrants.directInvestingRoute);
      expect(limits['to'], _ownSpark);
    });
  });

  test(
      'the direct Predictions row is a deposit the background sync wraps to '
      'pUSD once delivered', () {
    final row = BitcoinToVenueLeg.predictionsRow(
      id: 'ord_1',
      depositAddress: 'spark1deposit',
      sats: 100000,
      estimatedOut: '15000000',
      evm: _pmWallet,
      ownSpark: _ownSpark,
      walletId: 'w',
      operationId: 'op',
    );
    expect(isPredictionsDepositOrder(row), isTrue);
    expect(
        predictionsDepositNeedsWrap(row.copyWith(status: 'success'),
            activeWalletId: 'w',
            predictionsAddress: _pmWallet.toLowerCase(),
            orders: const []),
        isTrue);
    // Never another account's.
    expect(
        predictionsDepositNeedsWrap(row.copyWith(status: 'success'),
            activeWalletId: 'w',
            predictionsAddress: _otherEvm,
            orders: const []),
        isFalse);
  });

  test(
      'after a restart: legs on their way are followed to their end, the '
      'steps that needed the approval stop where they were', () async {
    FundedOrdersNotifier.persist = false;
    addTearDown(() => FundedOrdersNotifier.persist = true);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final orders = c.read(fundedOrdersProvider.notifier);
    final id = orders.start(_label, stage: FundedOrderStage.preparing);
    final graph = MoneyStepGraph([
      const MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 15,
          status: MoneyStepStatus.running,
          ref: 'ord_a'),
      const MoneyStep(
          id: 'ready:confirm',
          kind: MoneyStepKind.confirm,
          status: MoneyStepStatus.running),
      const MoneyStep(id: 'place', kind: MoneyStepKind.place),
    ]);
    // What the next process reads back.
    final mapped = FundedOrdersNotifier.interruptedSteps(graph);
    expect(mapped.byId('leg:bitcoin')!.status, MoneyStepStatus.running);
    expect(mapped.byId('ready:confirm')!.status, MoneyStepStatus.failed);
    expect(mapped.byId('ready:confirm')!.reason, 'interrupted');
    expect(mapped.byId('place')!.status, MoneyStepStatus.waiting);
    orders.setSteps(id, mapped, route: 'direct');
    await orders.resumeLegs(
        statusOf: (id) async => id == 'ord_a' ? 'completed' : null,
        pollEvery: const Duration(milliseconds: 1));
    final leg = c.read(fundedOrdersProvider).single.steps.byId('leg:bitcoin')!;
    expect(leg.status, MoneyStepStatus.done);
  });

  test('a fresh approved try starts its own receipt without old completed legs',
      () async {
    FundedOrdersNotifier.persist = false;
    addTearDown(() => FundedOrdersNotifier.persist = true);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final orders = c.read(fundedOrdersProvider.notifier);
    final first = orders.start(_label, stage: FundedOrderStage.preparing);
    orders.setSteps(
        first,
        const MoneyStepGraph([
          MoneyStep(
              id: 'leg:dollars',
              kind: MoneyStepKind.leg,
              from: MoneyPlace.dollars,
              usd: 5,
              status: MoneyStepStatus.done),
          MoneyStep(
              id: 'leg:investing',
              kind: MoneyStepKind.leg,
              from: MoneyPlace.investing,
              usd: 2,
              status: MoneyStepStatus.failed),
          MoneyStep(id: 'place', kind: MoneyStepKind.place),
        ]));
    orders.stop(first,
        stage: FundedOrderStage.failed,
        reason: 'venue_cash_pending',
        moneyAt: FundedMoneyAt.investments);
    final retry = orders.start(_label, stage: FundedOrderStage.preparing);
    final carried = orders.byId(retry)!.steps;
    expect(carried.steps, isEmpty);
    expect(orders.byId(first)!.steps.byId('leg:dollars')!.status,
        MoneyStepStatus.done,
        reason: 'the prior receipt retains its history');
    // The runner over the new graph runs the new branch only.
    final ran = <String>[];
    final graph = MoneyStepGraph([
      ...carried.steps,
      const MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          usd: 2),
      const MoneyStep(
          id: 'place', kind: MoneyStepKind.place, after: ['leg:investing']),
    ]);
    final end = await MoneyStepRunner(
      graph: graph,
      actionFor: (s) => (step, _) async {
        ran.add(step.id);
        return const MoneyStepDone();
      },
    ).run();
    expect(ran, ['leg:investing', 'place']);
    expect(end.allDone, isTrue);
  });

  test('an order funded from Dollars alone shows the same graph: its Dollars '
      'leg lands on its own, then the order', () async {
    FundedOrdersNotifier.persist = false;
    addTearDown(() => FundedOrdersNotifier.persist = true);
    final statuses = <String>['processing', 'completed'];
    final c = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) =>
            throw StateError('no bitcoin here'),
        watcher: ({required DateTime since}) => _Landed(),
        dollarsNow: () => 20,
        freshDollars: () async => 20,
        legStatus: (id) async =>
            statuses.length > 1 ? statuses.removeAt(0) : statuses.first,
        legPollEvery: const Duration(milliseconds: 1),
      )),
    ]);
    addTearDown(c.dispose);
    final pending = c.read(pendingPolymarketBetProvider.notifier);
    pending.setIntent(const PendingBetIntent(
      tokenId: 'tok',
      amount: 15,
      slippagePct: 2,
      marketQuestion: 'Lakers vs Celtics',
      outcomeName: 'Yes',
      expectedPrice: 0.5,
      fundUsd: 15.1,
      status: PendingBetStatus.awaitingBalance,
    ));
    final runner = c.read(bitcoinFundedOrderRunnerProvider);
    final id = runner.beginFunded(_label);
    runner.followFunded(id,
        move: const VenueMoveResult(
            quoteId: 'q_d', orderId: 'ord_d', sentUsd: 15.1, arrivingUsdEstimate: 15));
    FundedOrderRecord rec() => c.read(fundedOrdersProvider.notifier).byId(id)!;
    expect([for (final l in rec().steps.legs) l.id], ['leg:dollars']);
    expect(rec().steps.byId('leg:dollars')!.usd, 15.1);
    for (var i = 0; i < 100 &&
            rec().steps.byId('leg:dollars')!.status != MoneyStepStatus.done;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(rec().steps.byId('leg:dollars')!.status, MoneyStepStatus.done);
    pending.updateStatus(PendingBetStatus.placing);
    pending.updateStatus(PendingBetStatus.done);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rec().stage, FundedOrderStage.done);
    expect(rec().steps.byId('place')!.status, MoneyStepStatus.done);
  });

  // ── The chain ───────────────────────────────────────────────────────
  group('the funded order, every leg at once', () {
    late List<(String, Map<String, Object>?)> events;
    setUp(() {
      FundedOrdersNotifier.persist = false;
      OrderFundingJourney.reset();
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() {
      FundedOrdersNotifier.persist = true;
      TrackingService.debugTrackObserver = null;
    });

    test(
        'fundRestThenMove: Dollars send only their share, the order waits '
        'for the Bitcoin landing straight in', () async {
      final queued = <(double, double, double)>[];
      Future<OrderFundingOutcome> queue({
        required double fundUsd,
        required double readyUsd,
        required double directArrivingUsd,
        String? moveId,
      }) async {
        queued.add((fundUsd, readyUsd, directArrivingUsd));
        return const OrderFundingNotNeeded();
      }

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final puller = c.read(venueCashPullerProvider);
      // Venue cash 3 + Bitcoin covering the whole move: Dollars send none.
      await fundRestThenMove(
        puller: puller,
        venue: OneBalanceVenue.predictions,
        fundUsd: 15.1,
        readyUsd: 3,
        needsOtherVenue: false,
        grant: _grant(),
        queue: queue,
        legs: const FundingLegContext(
            bitcoinShareUsd: 15.1, bitcoinArrivingUsd: 15.01),
      );
      // Dollars + Bitcoin: Dollars send 5.
      await fundRestThenMove(
        puller: puller,
        venue: OneBalanceVenue.predictions,
        fundUsd: 15.1,
        readyUsd: 0,
        needsOtherVenue: false,
        grant: _grant(),
        queue: queue,
        legs: const FundingLegContext(
            bitcoinShareUsd: 10.1, bitcoinArrivingUsd: 10.04),
      );
      expect(queued[0].$1, 0);
      expect(queued[0].$2, closeTo(18.01, 1e-9));
      expect(queued[0].$3, closeTo(15.01, 1e-9));
      expect(queued[1].$1, closeTo(5, 1e-9));
      expect(queued[1].$2, closeTo(10.04, 1e-9));
      expect(queued[1].$3, closeTo(10.04, 1e-9));
    });

    late _Harness h;

    test(
        'the founder\'s case: no Dollars, \$15 on Polymarket from Bitcoin: ONE '
        'direct order into the own deposit, no Dollars leg', () async {
      h = _Harness(
          plan: const DirectBitcoinPlan.direct(
        targetUsd: 15.01,
        sats: 100000,
        dollarsUsd: 0,
        bitcoinShareUsd: 15.1,
        otherUsd: 0,
        directCostUsd: 15.0,
        viaCostUsd: 15.3,
      ));
      final run = h.start();
      expect(await run.ended, BitcoinFundedEnd.placed);
      expect(h.viaSends, 0);
      expect(h.directSends, 1);
      expect(h.fundCalls, hasLength(1));
      expect(h.fundCalls.single.bitcoinShareUsd, 15.1);
      expect(h.fundCalls.single.bitcoinArrivingUsd, 15.01);
      final record = h.record;
      expect(record.route, 'direct');
      expect([for (final l in record.steps.legs) l.id], ['leg:bitcoin']);
      expect(record.steps.byId('leg:bitcoin')!.status, MoneyStepStatus.done);
      expect(record.steps.byId('leg:bitcoin')!.ref, 'ord_direct');
      expect(record.steps.byId('place')!.status, MoneyStepStatus.done);
      expect(record.stage, FundedOrderStage.done);
      final completed =
          events.where((e) => e.$1 == 'order_funding_completed').single.$2!;
      expect(completed['route'], 'direct');
      expect(completed['ms_leg_bitcoin'], isA<int>());
      for (final e in events) {
        for (final v in (e.$2 ?? const {}).values.whereType<String>()) {
          expect(v.contains('spark1') || v.contains('0x'), isFalse,
              reason: '${e.$1} carries an address');
        }
      }
    });

    test(
        'Dollars + Bitcoin: both legs start together and complete on their '
        'own', () async {
      h = _Harness(
        plan: const DirectBitcoinPlan.direct(
          targetUsd: 10.04,
          sats: 100000,
          dollarsUsd: 5,
          bitcoinShareUsd: 10.1,
          otherUsd: 0,
          directCostUsd: 15.0,
          viaCostUsd: 15.3,
        ),
        dollars: 5,
        holdBitcoin: true,
      );
      final run = h.start();
      // The Dollars move went out as soon as the Bitcoin quote was
      // accepted, while the bitcoin is still on its way.
      await h.until(() => h.fundCalls.isNotEmpty);
      await h.until(() =>
          h.record.steps.byId('leg:dollars')?.status == MoneyStepStatus.done);
      expect(
          h.record.steps.byId('leg:bitcoin')!.status, MoneyStepStatus.running);
      final bitcoinStarted = h.record.steps.byId('leg:bitcoin')!.startedAt!;
      final dollarsStarted = h.record.steps.byId('leg:dollars')!.startedAt!;
      expect(dollarsStarted.difference(bitcoinStarted).inSeconds, 0);
      h.releaseBitcoin();
      expect(await run.ended, BitcoinFundedEnd.placed);
      expect(h.record.steps.byId('leg:bitcoin')!.status, MoneyStepStatus.done);
    });

    test(
        'the direct route refused before any sats leave: the chain via '
        'Dollars, remembered, under the same approval', () async {
      h = _Harness(
        plan: const DirectBitcoinPlan.direct(
          targetUsd: 15.01,
          sats: 100000,
          dollarsUsd: 0,
          bitcoinShareUsd: 15.1,
          otherUsd: 0,
          directCostUsd: 15.0,
          viaCostUsd: 15.3,
        ),
        refuseDirect: true,
      );
      final run = h.start();
      expect(await run.ended, BitcoinFundedEnd.placed);
      expect(h.directPaid, 0);
      expect(h.viaSends, 1);
      expect(DirectRouteRefusals.isBitcoinRefused(OneBalanceVenue.predictions),
          isTrue);
      final steps = h.record.steps;
      expect(steps.byId('leg:bitcoin')!.status, MoneyStepStatus.fellBack);
      expect(steps.byId('leg:bitcoin>dollars')!.status, MoneyStepStatus.done);
      expect(steps.byId('leg:dollars:onward')!.status, MoneyStepStatus.done);
      // The whole move from Dollars once the bitcoin's dollars landed.
      expect(h.fundCalls.single.bitcoinShareUsd, 0);
      expect(h.record.route, 'via_dollars');
      expect(
          events.any((e) =>
              e.$1 == 'venue_cash_direct_refused' &&
              e.$2!['venue'] == 'bitcoin'),
          isTrue);
      expect(
          events
              .where((e) => e.$1 == 'order_funding_completed')
              .single
              .$2!['route'],
          'via_dollars');
    });

    test(
        'an own deposit that no longer matches the approval: never paid, '
        'the chain instead', () async {
      h = _Harness(
        plan: const DirectBitcoinPlan.direct(
          targetUsd: 15.01,
          sats: 100000,
          dollarsUsd: 0,
          bitcoinShareUsd: 15.1,
          otherUsd: 0,
          directCostUsd: 15.0,
          viaCostUsd: 15.3,
        ),
        ownVenue: _otherEvm,
      );
      final run = h.start();
      expect(await run.ended, BitcoinFundedEnd.placed);
      expect(h.directSends, 0);
      expect(h.viaSends, 1);
    });

    test(
        'Orchestra refunds the direct leg after the sats left: the bitcoin '
        'comes back, the order is dropped, the approval cancelled', () async {
      h = _Harness(
        plan: const DirectBitcoinPlan.direct(
          targetUsd: 15.01,
          sats: 100000,
          dollarsUsd: 0,
          bitcoinShareUsd: 15.1,
          otherUsd: 0,
          directCostUsd: 15.0,
          viaCostUsd: 15.3,
        ),
        bitcoinStatus: 'refunded',
      );
      final run = h.start();
      expect(await run.ended, BitcoinFundedEnd.refunded);
      expect(h.dropped, 1);
      expect(h.record.moneyAt, FundedMoneyAt.bitcoin);
      expect(
          h.record.steps.byId('leg:bitcoin')!.status, MoneyStepStatus.failed);
      expect(
          events
              .where((e) => e.$1 == 'order_funding_failed')
              .single
              .$2!['route'],
          'direct');
    });

    test(
        'the Dollars move refused after the bitcoin left: the money is in '
        'the venue, the order dropped', () async {
      h = _Harness(
        plan: const DirectBitcoinPlan.direct(
          targetUsd: 10.04,
          sats: 100000,
          dollarsUsd: 5,
          bitcoinShareUsd: 10.1,
          otherUsd: 0,
          directCostUsd: 15.0,
          viaCostUsd: 15.3,
        ),
        dollars: 5,
        refuseVenueMove: true,
      );
      final run = h.start();
      expect(await run.ended, BitcoinFundedEnd.ready);
      expect(h.dropped, 1);
      expect(h.record.moneyAt, FundedMoneyAt.venue);
      expect(h.record.reason, 'venue_refused');
    });
  });
}

/// One funded-order run against stand-ins for the wallet, Orchestra and
/// the venue.
class _Harness {
  _Harness({
    required this.plan,
    this.dollars = 0,
    this.holdBitcoin = false,
    this.refuseDirect = false,
    this.refuseVenueMove = false,
    this.bitcoinStatus = 'completed',
    this.ownVenue = _pmWallet,
    this.sourceStatus,
    this.sourceHome = false,
  });

  final DirectBitcoinPlan plan;
  final double dollars;
  final bool holdBitcoin;
  final bool refuseDirect;
  final bool refuseVenueMove;
  final String bitcoinStatus;
  final String ownVenue;
  final String? sourceStatus;
  final bool sourceHome;
  double sourceCash = 5;

  var directSends = 0;
  var directPaid = 0;
  var viaSends = 0;
  var dropped = 0;
  final fundCalls = <FundingLegContext>[];
  final _bitcoinHeld = Completer<void>();
  final _bitcoinIn = Completer<void>();
  final _funded = Completer<void>();
  late ProviderContainer c;
  String? _runId;

  void releaseBitcoin() {
    if (!_bitcoinHeld.isCompleted) _bitcoinHeld.complete();
  }

  FundedOrderRecord get record =>
      c.read(fundedOrdersProvider).firstWhere((r) => r.id == _runId);

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 500 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(ok(), isTrue);
  }

  Future<String?> _status(String id) async {
    if (id == 'ord_other') return sourceStatus;
    if (id == 'ord_direct') {
      if (holdBitcoin && !_bitcoinHeld.isCompleted) return 'processing';
      if (bitcoinStatus == 'completed' && !_bitcoinIn.isCompleted) {
        _bitcoinIn.complete();
      }
      return bitcoinStatus;
    }
    return 'completed';
  }

  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          viaSends++;
          onSending();
          return const BitcoinLegTicket(
              quoteId: 'q_btc',
              sats: 102000,
              estimatedOutUsd: 15.1,
              minOutUsd: 15.1);
        },
        watcher: ({required DateTime since}) => _Landed(),
        dollarsNow: () => dollars,
        freshDollars: () async => dollars,
        ownVenue: (_) async => ownVenue,
        planDirect: ({
          required OneBalanceVenue venue,
          required double fundUsd,
          required double addUsd,
          required double dollarsUsd,
          required BitcoinLegPlan via,
          required String ownVenue,
          required int directMaxSats,
        }) async =>
            plan,
        sendDirect: ({
          required OneBalanceVenue venue,
          required String ownVenue,
          required String ownSpark,
          required int sats,
          required double targetUsd,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          directSends++;
          if (refuseDirect) {
            // Orchestra has no route: refused at the quote, nothing moved.
            throw const RouteUnavailable('route_unavailable');
          }
          final ok = await stepUp(_directIntent(_directQuote()));
          if (!ok) throw const SettlementStopped(SettlementStopReason.declined);
          onSending();
          directPaid++;
          return const DirectLegSent(
              quoteId: 'q_direct',
              orderId: 'ord_direct',
              sats: 100000,
              estimatedOutUsd: 15.01);
        },
        legStatus: _status,
        legPollEvery: const Duration(milliseconds: 1),
      );

  BitcoinFundedRun start() {
    c = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(env),
      if (sourceStatus != null)
        venueCashPullerProvider.overrideWithValue(VenueCashPuller(
            sources: [_OtherCash(() => sourceCash)],
            readDollars: () => dollars,
            minimumUsd: (_) async => 1)),
    ]);
    addTearDown(c.dispose);
    if (sourceStatus != null) {
      final snapshot = c.read(venueCashSnapshotProvider);
      c.read(venueCashLastReadProvider.notifier).state = (
        walletId: snapshot.walletId,
        candidates: [
          (
            venue: OneBalanceVenue.investing,
            availableUsd: 5,
            eta: const Duration(minutes: 1),
            minimumUsd: 1
          )
        ],
      );
    }
    final grant = _grant();
    final run = c.read(bitcoinFundedOrderRunnerProvider).start(
          BitcoinFundedOrderRequest(
            venue: OneBalanceVenue.predictions,
            grant: grant,
            plan: _via,
            label: _label,
            fundUsd: 15.1,
            readyUsd: 0,
            entrySource: 'market',
            fundVenue: (controller, legs) async {
              fundCalls.add(legs);
              if (sourceStatus != null) {
                const pull = VenueCashPull(
                    venue: OneBalanceVenue.investing,
                    usd: 3,
                    arrivingUsd: 3,
                    eta: Duration(minutes: 1));
                final leg = VenueCashLegOutcome(
                    pull: pull,
                    route: sourceHome
                        ? MoneyRoute.viaDollars
                        : MoneyRoute.direct,
                    landsIn: sourceHome
                        ? VenueCashDestination.dollars
                        : VenueCashDestination.predictions,
                    result: const VenueMoveResult(
                        quoteId: 'q_other',
                        orderId: 'ord_other',
                        operationId: 'op_other',
                        sentUsd: 3,
                        arrivingUsdEstimate: 3));
                c.read(venueCashSnapshotProvider).cashMoved(leg, 5);
                sourceCash = sourceStatus == 'completed' ? 2 : 5;
                legs.onPulled?.call(VenueCashPullOutcome(
                    plan: const VenueCashPlan(
                        neededUsd: 3,
                        dollarsUsd: 0,
                        pulls: [pull],
                        covers: true,
                        eta: Duration(minutes: 1),
                        uncoveredUsd: 0),
                    legs: [leg],
                    dollarsCover: true,
                    eta: const Duration(minutes: 1)));
              }
              if (refuseVenueMove) {
                return const OrderFundingRefused('no_route');
              }
              if (!_funded.isCompleted) _funded.complete();
              if (legs.bitcoinShareUsd > 0 && plan.dollarsUsd <= 0) {
                return const OrderFundingNotNeeded();
              }
              return OrderFundingFunded(VenueMoveResult(
                  quoteId: 'q_venue',
                  orderId: 'o_venue',
                  sentUsd: legs.bitcoinShareUsd > 0 ? plan.dollarsUsd : 15.1,
                  arrivingUsdEstimate: 5));
            },
            dropOrder: () {
              dropped++;
              grant.revoke();
            },
            // The venue credits the order once its money landed.
            // The venue credits the order once its money landed, and the
            // autofire reports the funnel's end.
            awaitPlacement: ({required onCredited}) async {
              await _funded.future;
              if (directSends > 0 && !refuseDirect && ownVenue == _pmWallet) {
                await _bitcoinIn.future;
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
              onCredited();
              OrderFundingJourney.instance
                  .completed(OneBalanceVenue.predictions, resized: false);
              return true;
            },
          ),
        );
    _runId = run.id;
    return run;
  }
}

class _OtherCash implements VenueCashSource {
  _OtherCash(this.cash);
  final double Function() cash;
  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;
  @override
  Duration get estimatedArrival => const Duration(minutes: 1);
  @override
  Future<double> availableUsd() async => cash();
  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) =>
      throw StateError('the accepted source result is injected by the harness');
}

class _Landed extends DollarsLandingWatcher {
  _Landed()
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async =>
      const DollarsLanded(byStatus: true, freshDollarsUsd: 15.1);
}
