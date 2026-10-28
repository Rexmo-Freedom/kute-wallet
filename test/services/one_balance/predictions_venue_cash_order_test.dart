// A bet funded from Dollars and the Investing cash, no Bitcoin: the bet
// slip's Predictions path on the same runner as the Investing order slip
// (venue_cash_funded_order.dart), through the bet's own request
// (predictions_venue_cash_order.dart). The step graph is recorded at the
// approval, every source starts at once, the Investing cash goes straight
// into Predictions by CCTP where the approval binds it (Flashnet offers no
// HyperCore-source route), a leg home to Dollars lands by its order's
// status while the Dollars reading still says nothing, the bet is placed
// after Predictions' readiness, every wait is bounded, and a fallback says
// its real reason.

import 'dart:async';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/slip_shortfall.dart' show fundedStopLine;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_venue_cash_order.dart';
import 'package:kute/services/one_balance/venue_cash_funded_order.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

final _now = DateTime.utc(2026, 10, 15, 18);

/// The Investing cash as the real rail treats it: straight into
/// Predictions by CCTP only within the approval's leg caps, else refused
/// before anything moved with [refuseWith]; home to Dollars otherwise.
class _Investing implements VenueCashSource, DirectVenueCashSource {
  _Investing(this.cash, {this.refuseWith});
  double cash;
  final String? refuseWith;
  final direct = <double>[];
  final home = <double>[];
  final startedAt = <String, DateTime>{};

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => const Duration(minutes: 5);

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    startedAt['home'] = DateTime.now();
    home.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_home',
        orderId: 'ord_home',
        sentUsd: usd,
        arrivingUsdEstimate: usd - 0.12);
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.predictions;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    startedAt['direct'] = DateTime.now();
    final refusal = refuseWith;
    if (refusal != null) throw DirectRouteRefused(refusal);
    final grant = (auth as ApprovedLegAuthorization).grant;
    if (!DirectLegGrants.take(grant,
        venue: venue.name,
        destination: destination.code,
        amount: IntentUnits.usd(usd))) {
      throw const DirectRouteRefused('settlement_declined');
    }
    direct.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_direct',
        orderId: 'ord_direct',
        sentUsd: usd,
        arrivingUsdEstimate: usd - 0.12);
  }
}

/// Dollars → Predictions: what left, and when.
class _Predictions implements VenueFunder {
  _Predictions(this.run);
  final _Run run;
  final sent = <double>[];

  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    sent.add(usd);
    run.dollars -= usd;
    final first = sent.length == 1;
    if (first) run.dollarsStartedAt = DateTime.now();
    return VenueMoveResult(
        quoteId: first ? 'q_dollars' : 'q_onward',
        orderId: first ? 'ord_dollars' : 'ord_onward',
        sentUsd: usd,
        arrivingUsdEstimate: usd - 0.05,
        operationId: first ? 'op_dollars' : 'op_onward');
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd - 0.05,
      feeUsd: 0.05,
      fixedCostUsd: 0,
      minUsd: 1,
      maxUsd: 1000);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// The founder's bet: $10 on Yes, $0 in Predictions, $5 in Dollars, $6 in
/// Investing.
class _Run {
  _Run({
    this.refuseDirect,
    this.statuses = const {},
  });

  final String? refuseDirect;

  /// What Dollars read once asked to catch up (null: unchanged).
  double? dollarsAfterCheck;

  /// What Dollars read when the leg home was found delivered.
  double? dollarsAtCheck;

  /// Orchestra statuses by order id (default: completed).
  final Map<String, String> statuses;

  late final _Investing investing = _Investing(6, refuseWith: refuseDirect);
  double dollars = 5;
  DateTime? dollarsStartedAt;
  var checks = 0;
  late final _Predictions funder = _Predictions(this);
  late ProviderContainer c;
  late VenueCashPuller puller;
  late VenueCashPlan plan;
  late String runId;
  late AuthGrant grant;
  final delivered = <String>{};
  final phases = StreamController<String>.broadcast();
  final phasesSeen = <String>[];

  /// The current phase first, then every new one, as the app's own
  /// readiness stream does (venueReadinessPhases): a step that starts
  /// late (the conversion after the wait for every leg) still sees it.
  Stream<String> readiness() {
    final current = phasesSeen.isEmpty ? null : phasesSeen.last;
    final c = StreamController<String>();
    if (current != null) c.add(current);
    final sub = phases.stream.listen(c.add);
    c.onCancel = sub.cancel;
    return c.stream;
  }

  FundedOrderRecord get record =>
      c.read(fundedOrdersProvider).firstWhere((r) => r.id == runId);

  PendingBetIntent? get bet => c.read(pendingPolymarketBetProvider);

  Future<void> until(bool Function() ok, {int tries = 2000}) async {
    for (var i = 0; i < tries && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(ok(), isTrue);
  }

  Future<String?> _status(String id) async {
    final s = statuses[id] ?? 'completed';
    if (s == 'completed') delivered.add(id);
    return s;
  }

  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => 'spark1own',
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) =>
            throw StateError('no bitcoin in this bet'),
        watcher: ({required DateTime since}) =>
            throw StateError('the balance is never the landing signal'),
        dollarsNow: () => dollars,
        freshDollars: () async => null,
        legStatus: _status,
        legPollEvery: const Duration(milliseconds: 1),
        readiness: (_) => readiness(),
        checkDollars: () {
          checks++;
          dollarsAtCheck = dollars;
          final after = dollarsAfterCheck;
          if (after != null) dollars = after;
        },
      );

  /// The venue's autofire: once the bet is queued and Predictions hold
  /// what every move brings, it walks the readiness (convert to pUSD,
  /// approve spend, confirm the balance), then places the bet.
  Future<void> autofire(Set<String> needed) async {
    for (var i = 0; i < 3000; i++) {
      final PendingBetIntent? b;
      try {
        b = bet;
      } catch (_) {
        return; // The container went with the test.
      }
      if (b == null || grant.revoked) return;
      if (b.status == PendingBetStatus.awaitingBalance &&
          delivered.containsAll(needed)) {
        for (final p in const ['converting', 'approving', 'confirming']) {
          phasesSeen.add(p);
          phases.add(p);
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        phasesSeen.add('ready');
        phases.add('ready');
        final n = c.read(pendingPolymarketBetProvider.notifier);
        n.updateStatus(PendingBetStatus.placing);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        OrderFundingJourney.instance
            .completed(OneBalanceVenue.predictions, resized: false);
        n.updateStatus(PendingBetStatus.done);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<BitcoinFundedRun> start() async {
    puller = VenueCashPuller(
      sources: [investing],
      readDollars: () => dollars,
      minimumUsd: (_) async => 1,
      sleep: (_) async {},
    );
    c = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(env),
      venueCashPullerProvider.overrideWithValue(puller),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => funder, dollarsUsd: () => dollars)),
    ]);
    addTearDown(c.dispose);
    addTearDown(phases.close);
    // The slip's plan before the approval: $10 into Predictions, $5 of it
    // from Dollars, the rest from Investing.
    plan = await puller.plan(
      neededUsd: 10,
      exclude: OneBalanceVenue.predictions,
      destination: VenueCashDestination.predictions,
    );
    expect(plan.dollarsUsd, 5);
    expect(plan.covers, isTrue);
    grant = AuthGrants.issue(
      SensitiveIntent(
        action: SensitiveAction.pmBet,
        walletId: 'w',
        venue: IntentVenue.polymarket,
        destination: 'yes-token',
        asset: 'USDC',
        amountMax: IntentUnits.usd(10),
        limits: {
          VenueLimit.directLegs:
              puller.directLegLimit(plan, VenueCashDestination.predictions),
        },
        ttl: AuthGrants.autofireTtl,
      ),
      method: AuthGrantMethod.biometric,
      now: _now,
    );
    // The slip's prepared bet, held with its funding cap.
    const pending = PendingBetIntent(
      tokenId: 'yes-token',
      amount: 10,
      slippagePct: 2,
      marketQuestion: 'Will it rain?',
      outcomeName: 'Yes',
      expectedPrice: 0.5,
      fundUsd: 10,
    );
    c.read(pendingPolymarketBetProvider.notifier).setIntent(pending);
    final run = c.read(venueCashFundedOrderRunnerProvider).start(
          predictionsVenueCashRequest(
            c,
            grant: grant,
            pending: pending,
            label: const FundedOrderLabel(
              venue: OneBalanceVenue.predictions,
              orderUsd: 10,
              side: 'Yes',
              market: 'Will it rain?',
              marketKey: 'yes-token',
            ),
            legPlan: plan,
            fundUsd: 10,
            requiredUsd: 10,
            readyUsd: 0,
            balanceUsd: 0,
            moveId: MultiSourceMoveStore.newId(),
            entrySource: 'market',
          ),
        );
    runId = run.id;
    return run;
  }
}

List<String> _lines(AppLocalizations l10n, MoneyStepGraph g) => [
      for (final l in moneyStepLines(
          l10n, g, (usd) => '\$${usd.toStringAsFixed(2)}',
          readyLabel: l10n.slipStepPreparingPrediction,
          placeLine: l10n.slipStepPlacingBet('\$10.00', 'Yes')))
        l.text,
    ];

void main() {
  late List<(String, Map<String, Object?>?)> events;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    AuthGrants.clock = () => _now;
    FundedOrdersNotifier.persist = false;
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
    OrderFundingJourney.reset();
    VenueCashFundedOrderRunner.dollarsCatchUp = const Duration(seconds: 2);
    VenueCashFundedOrderRunner.dollarsPollEvery =
        const Duration(milliseconds: 2);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    AuthGrants.clock = DateTime.now;
    FundedOrdersNotifier.persist = true;
    TrackingService.debugTrackObserver = null;
    VenueCashFundedOrderRunner.dollarsCatchUp = const Duration(seconds: 30);
    VenueCashFundedOrderRunner.dollarsPollEvery =
        const Duration(milliseconds: 500);
    VenueCashFundedOrderRunner.legMaxWait = const Duration(minutes: 12);
  });

  test(
      'a \$10 bet, \$0 in Predictions, \$5 in Dollars, \$6 in Investing: '
      'both sources start together, the steps show from the approval, the '
      'Investing cash goes straight in, the bet is placed after readiness',
      () async {
    final h = _Run();
    final run = await h.start();
    final investingUsd = h.plan.pullFrom(OneBalanceVenue.investing)!.usd;
    // At the approval, before anything landed: one line per source, the
    // readiness and the bet.
    final g0 = h.record.steps;
    expect([for (final l in g0.legs) l.id], ['leg:investing', 'leg:dollars']);
    expect(g0.byId('leg:investing')!.route, MoneyRoute.direct);
    expect(_lines(l10n, g0).first,
        'Moving \$${investingUsd.toStringAsFixed(2)} from Investing');
    expect(_lines(l10n, g0)[1], 'Moving \$5.00 from Dollars');
    expect(_lines(l10n, g0).last, 'Placing \$10.00 on Yes');
    expect(_lines(l10n, g0), contains('Getting your prediction ready'));
    expect(_lines(l10n, g0), contains('Confirming balance'));
    // Every source at once: the Dollars share and the Investing leg left
    // together, neither waiting on the other.
    await h
        .until(() => h.funder.sent.isNotEmpty && h.investing.direct.isNotEmpty);
    expect(
        h.dollarsStartedAt!
            .difference(h.investing.startedAt['direct']!)
            .inMilliseconds
            .abs(),
        lessThan(100));
    expect(h.funder.sent.first, 5.0);
    // The approved plan, exactly.
    expect(h.investing.direct, [investingUsd]);
    // Queued behind both moves: it fires once Predictions hold what they
    // bring.
    await h.until(() => h.bet?.status == PendingBetStatus.awaitingBalance);
    final investingArriving =
        h.plan.pullFrom(OneBalanceVenue.investing)!.arrivingUsd;
    expect(h.bet!.fundArrivingUsd, closeTo(4.95 + investingArriving, 1e-9));

    unawaited(h.autofire({'ord_dollars', 'ord_direct'}));
    expect(await run.ended.timeout(const Duration(seconds: 10)),
        BitcoinFundedEnd.placed);
    final g = h.record.steps;
    expect(g.byId('leg:investing')!.status, MoneyStepStatus.done);
    expect(g.byId('leg:investing')!.ref, 'ord_direct');
    expect(g.byId('leg:dollars')!.status, MoneyStepStatus.done);
    for (final id in [
      'ready:gather',
      'ready:convert',
      'ready:approve',
      'ready:confirm'
    ]) {
      expect(g.byId(id)!.status, MoneyStepStatus.done, reason: id);
      // Placed only after readiness.
      expect(g.byId(id)!.endedAt!.isAfter(g.byId('place')!.endedAt!), isFalse,
          reason: id);
    }
    // Nothing at Predictions before both legs' money was there: the
    // conversion and the allowance start only once the wait for both
    // ended, which ends only after both legs landed.
    final gathered = g.byId('ready:gather')!.endedAt!;
    for (final id in ['leg:investing', 'leg:dollars']) {
      expect(g.byId(id)!.endedAt!.isAfter(gathered), isFalse, reason: id);
    }
    for (final id in ['ready:convert', 'ready:approve']) {
      expect(g.byId(id)!.startedAt!.isBefore(gathered), isFalse, reason: id);
    }
    expect(g.byId('place')!.status, MoneyStepStatus.done);
    expect(_lines(l10n, g), [
      'Moved \$${investingUsd.toStringAsFixed(2)} from Investing',
      'Moved \$5.00 from Dollars',
      'Getting your prediction ready',
      'Both arrived',
      'Converted to pUSD',
      'Spend approved',
      'Balance confirmed',
      'Placing \$10.00 on Yes',
    ]);
    expect(h.record.stage, FundedOrderStage.done);
    // One Activity row: the Dollars move is the move's own step.
    final move = MultiSourceMoveStore.all().single;
    expect(move.finalOperationId, 'op_dollars');
    expect(move.legs.single.direct, isTrue);
    final started =
        events.where((e) => e.$1 == 'order_funding_started').first.$2!;
    expect(started['venue'], isNotNull);
    expect(started['funding_source'], 'venue_cash');
    expect(started['other_venue_used'], isTrue);
    final completed =
        events.where((e) => e.$1 == 'order_funding_completed').single.$2!;
    expect(completed['route'], 'direct');
    expect(completed['other_venue_used'], isTrue);
    expect(completed['ms_leg_investing'], isA<int>());
    expect(completed['ms_leg_dollars'], isA<int>());
  });

  test(
      'the via-Dollars fallback with its real reason: the Investing leg '
      'lands by its order status while Dollars still read \$0, goes on '
      'into Predictions, and the bet is placed after readiness', () async {
    final h = _Run(refuseDirect: 'cctp_paused');
    final run = await h.start();
    final investingUsd = h.plan.pullFrom(OneBalanceVenue.investing)!.usd;
    // Once asked, Dollars catch up with what the leg brought home.
    h.dollarsAfterCheck = investingUsd - 0.12;
    // The Dollars share leaves at once; Dollars then read nothing (the
    // SDK's token row is behind) while the leg home lands.
    await h.until(() => h.funder.sent.isNotEmpty);
    h.dollars = 0;
    unawaited(h.autofire({'ord_dollars', 'ord_onward'}));
    expect(await run.ended.timeout(const Duration(seconds: 10)),
        BitcoinFundedEnd.placed);
    expect(h.investing.home, [investingUsd]);
    expect(h.investing.direct, isEmpty);
    // Landed by its order status (Dollars still read $0): Dollars were
    // asked to catch up, and the move on sent what landed, within what
    // the approval has left ($10 in all, $5 already sent).
    expect(h.checks, 1);
    expect(h.dollarsAtCheck, 0);
    expect(h.funder.sent, [5.0, 5.0]);
    final g = h.record.steps;
    expect(g.byId('leg:investing')!.status, MoneyStepStatus.fellBack);
    expect(g.byId('leg:investing')!.reason, 'cctp_paused');
    expect(g.byId('leg:investing:via_dollars')!.status, MoneyStepStatus.done);
    expect(g.byId('leg:investing:via_dollars')!.ref, 'ord_home');
    expect(
        g.byId('leg:dollars:onward:investing')!.status, MoneyStepStatus.done);
    expect(g.byId('ready:confirm')!.status, MoneyStepStatus.done);
    expect(g.byId('place')!.status, MoneyStepStatus.done);
    // Never "busy": the route is paused.
    expect(_lines(l10n, g).first,
        'Investing route unavailable, going via Dollars');
    // The queued bet waited for the move on too.
    expect(h.bet, isNotNull);
    final completed =
        events.where((e) => e.$1 == 'order_funding_completed').single.$2!;
    expect(completed['route'], 'via_dollars');
    expect(completed['route_reason'], 'cctp_paused');
  });

  test(
      'a leg that never lands stops within its bound: the bet goes, its '
      'approval is cancelled, the steps say where the money is', () async {
    VenueCashFundedOrderRunner.legMaxWait = const Duration(milliseconds: 80);
    final h = _Run(
        refuseDirect: 'cctp_in_flight',
        statuses: const {'ord_home': 'processing'});
    final run = await h.start();
    expect(await run.ended.timeout(const Duration(seconds: 10)),
        BitcoinFundedEnd.ready);
    expect(h.grant.revoked, isTrue);
    // The queued bet is dropped: it never fires on a later balance.
    expect(h.bet, isNull);
    final r = h.record;
    expect(r.reason, 'timeout');
    // It lands in Dollars whenever it does: the money is in Investments.
    expect(r.moneyAt, FundedMoneyAt.investments);
    expect(r.steps.byId('leg:investing:via_dollars')!.status,
        MoneyStepStatus.failed);
    expect(fundedStopLine(l10n, r, (usd) => '\$${usd.toStringAsFixed(2)}'),
        contains('Investments'));
    // A transient refusal, said as one.
    expect(
        _lines(l10n, r.steps).first, 'Investing route busy, going via Dollars');
  });

  test('the fallback line gives the real reason, never "busy" by default', () {
    String line(String reason) => moneyStepLine(
        l10n,
        MoneyStep(
            id: 'leg:investing',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.investing,
            usd: 6,
            status: MoneyStepStatus.fellBack,
            reason: reason),
        (usd) => '\$$usd');
    // Investing's direct refusals (HyperCoreMoveRail.withdrawDirect).
    expect(
        line('cctp_paused'), 'Investing route unavailable, going via Dollars');
    expect(line('cctp_capability'),
        'Investing route unavailable, going via Dollars');
    expect(line('cctp_below_minimum'),
        'Too small to go straight from Investing, going via Dollars');
    expect(line('cctp_in_flight'), 'Investing route busy, going via Dollars');
    expect(line('cctp_fee_terms_unavailable'), 'Investing going via Dollars');
    expect(line('account_unavailable'), 'Investing going via Dollars');
    expect(
        line('wallet_guard_recipient_not_own'), 'Investing going via Dollars');
  });
}
