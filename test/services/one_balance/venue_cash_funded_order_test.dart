// An Investing order funded from Dollars and the Predictions cash, no
// Bitcoin (founder report 15 October 2026: "i have 5 dollars in
// polymarket, 5 in usdb, and it still does not show all the steps we have
// to do, besides it is stuck at preparing order"): every source starts at
// once on the order's step graph, straight in where the approval binds
// it, its landing read from the Orchestra order (not the Dollars balance
// alone), every wait bounded, and the via-Dollars fallback with its real
// reason on the same lines.

import 'dart:async';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_funded_order.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

final _now = DateTime.utc(2026, 10, 15, 15);

/// Predictions cash as the real rail treats it: straight into Investing
/// only within the approval's leg caps ([DirectLegGrants.take]), else
/// refused before anything moved with [refuseWith].
class _Predictions implements VenueCashSource, DirectVenueCashSource {
  _Predictions(this.cash, {this.refuseWith});
  double cash;
  final String? refuseWith;
  final direct = <double>[];
  final home = <double>[];
  var cashReads = 0;
  final hold = Completer<void>();
  bool holding = false;

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;

  @override
  Duration get estimatedArrival => const Duration(minutes: 1);

  @override
  Future<double> availableUsd() async {
    cashReads++;
    return cash;
  }

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    home.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_home',
        orderId: 'ord_home',
        sentUsd: usd,
        arrivingUsdEstimate: 4.15);
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.investing;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    final refusal = refuseWith;
    if (refusal != null) throw DirectRouteRefused(refusal);
    final grant = (auth as ApprovedLegAuthorization).grant;
    if (!DirectLegGrants.take(grant,
        venue: venue.name,
        destination: destination.code,
        amount: IntentUnits.usd(usd))) {
      throw const DirectRouteRefused('settlement_declined');
    }
    if (holding) await hold.future;
    direct.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_direct',
        orderId: 'ord_direct',
        sentUsd: usd,
        arrivingUsdEstimate: 3.91);
  }
}

/// One run against stand-ins for the wallet, Orchestra and the venue.
class _Run {
  _Run({
    this.refuseDirect,
    this.dollarsAfterCheck,
    this.holdDirect = false,
    this.statuses = const {},
  });

  final String? refuseDirect;

  /// What Dollars read once the reading was asked to catch up (null: the
  /// founder's Dollars, $5 then what landed).
  final double? dollarsAfterCheck;
  final bool holdDirect;

  /// Orchestra statuses by order id (default: completed).
  final Map<String, String> statuses;

  late final _Predictions predictions =
      _Predictions(5, refuseWith: refuseDirect)..holding = holdDirect;
  double dollars = 5;
  var checks = 0;
  final queued = <({double fundUsd, double readyUsd, DateTime at})>[];
  final more = <double>[];
  var dropped = 0;
  late ProviderContainer c;
  late VenueCashPuller puller;
  late String runId;
  late AuthGrant grant;
  final _delivered = <String>{};
  void Function()? onSourceStatus;

  FundedOrderRecord get record =>
      c.read(fundedOrdersProvider).firstWhere((r) => r.id == runId);

  Future<void> until(bool Function() ok, {int tries = 1000}) async {
    for (var i = 0; i < tries && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(ok(), isTrue);
  }

  Future<String?> _status(String id) async {
    final s = statuses[id] ?? 'completed';
    if (id == 'ord_direct' || id == 'ord_home') onSourceStatus?.call();
    if (s == 'completed') _delivered.add(id);
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
            throw StateError('no bitcoin in this order'),
        watcher: ({required DateTime since}) =>
            throw StateError('the balance is never the landing signal'),
        dollarsNow: () => dollars,
        freshDollars: () async => null,
        legStatus: _status,
        legPollEvery: const Duration(milliseconds: 1),
        checkDollars: () {
          checks++;
          final after = dollarsAfterCheck;
          if (after != null) dollars = after;
        },
      );

  Future<BitcoinFundedRun> start({bool trackCash = false}) async {
    puller = VenueCashPuller(
      sources: [predictions],
      readDollars: () => dollars,
      minimumUsd: (_) async => 1,
      sleep: (_) async {},
      onCashMoved: trackCash
          ? (leg, before) =>
              c.read(venueCashSnapshotProvider).cashMoved(leg, before)
          : null,
    );
    c = ProviderContainer(overrides: [
      bitcoinLegEnvProvider.overrideWithValue(env),
      venueCashPullerProvider.overrideWithValue(puller),
    ]);
    addTearDown(c.dispose);
    if (trackCash) {
      final snapshot = c.read(venueCashSnapshotProvider);
      c.read(venueCashLastReadProvider.notifier).state = (
        walletId: snapshot.walletId,
        candidates: [
          (
            venue: OneBalanceVenue.predictions,
            availableUsd: 5,
            eta: const Duration(minutes: 1),
            minimumUsd: 1
          )
        ],
      );
    }
    // The slip's plan before the approval: $9.11 into Investing, $5.00
    // of it from Dollars, the rest from Predictions ($4.20 leaves).
    final plan = await puller.plan(
      neededUsd: 9.11,
      exclude: OneBalanceVenue.investing,
      destination: VenueCashDestination.investing,
    );
    expect(plan.pullFrom(OneBalanceVenue.predictions)!.usd, 4.20);
    expect(plan.dollarsUsd, 5);
    grant = AuthGrants.issue(
      SensitiveIntent(
        action: SensitiveAction.hlOrder,
        walletId: 'w',
        venue: IntentVenue.hyperliquid,
        destination: 'BTC',
        asset: 'BTC',
        amountMax: IntentUnits.usd(10.76),
        limits: {
          VenueLimit.directLegs:
              puller.directLegLimit(plan, VenueCashDestination.investing),
        },
        ttl: AuthGrants.autofireTtl,
      ),
      method: AuthGrantMethod.biometric,
      now: _now,
    );
    final run = c.read(venueCashFundedOrderRunnerProvider).start(
          VenueCashFundedRequest(
            venue: OneBalanceVenue.investing,
            grant: grant,
            label: const FundedOrderLabel(
              venue: OneBalanceVenue.investing,
              orderUsd: 10.76,
              side: 'Long',
              market: 'BTC',
              marketKey: 'BTC',
            ),
            fundUsd: 9.11,
            readyUsd: 2.37,
            plan: plan,
            entrySource: 'market',
            queue: ({required double fundUsd, required double readyUsd}) async {
              queued.add(
                  (fundUsd: fundUsd, readyUsd: readyUsd, at: DateTime.now()));
              if (fundUsd <= 0) return const OrderFundingNotNeeded();
              dollars -= fundUsd;
              return OrderFundingFunded(VenueMoveResult(
                  quoteId: 'q_dollars',
                  orderId: 'ord_dollars',
                  sentUsd: fundUsd,
                  arrivingUsdEstimate: fundUsd - 1.24,
                  operationId: 'op_dollars'));
            },
            fundMore: (controller, usd) async {
              more.add(usd);
              dollars -= usd;
              return OrderFundingFunded(VenueMoveResult(
                  quoteId: 'q_onward',
                  orderId: 'ord_onward',
                  sentUsd: usd,
                  arrivingUsdEstimate: usd - 1.24));
            },
            dropOrder: () {
              dropped++;
              grant.revoke();
            },
            // The venue's autofire: it places the order once the account
            // holds enough, i.e. once every move into it was delivered.
            awaitPlacement: ({required onCredited}) async {
              for (var i = 0; i < 3000; i++) {
                final needed = refuseDirect == null
                    ? {'ord_dollars', 'ord_direct'}
                    : {'ord_dollars', 'ord_onward'};
                if (_delivered.containsAll(needed)) {
                  onCredited();
                  OrderFundingJourney.instance
                      .completed(OneBalanceVenue.investing, resized: false);
                  return true;
                }
                if (grant.revoked) return false;
                await Future<void>.delayed(const Duration(milliseconds: 2));
              }
              return false;
            },
          ),
        );
    runId = run.id;
    return run;
  }
}

List<String> _lines(AppLocalizations l10n, MoneyStepGraph g) => [
      for (final l in moneyStepLines(
          l10n, g, (usd) => '\$${usd.toStringAsFixed(2)}',
          readyLabel: 'Preparing your order',
          placeLine: 'Opening \$10.76 Long BTC'))
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

  for (final home in [false, true]) {
    for (final status in ['refunded', 'failed', 'processing']) {
      test(
          '${home ? 'home' : 'direct'} accepted source $status reconciles '
          'cash only on explicit refund proof', () async {
        VenueCashFundedOrderRunner.legMaxWait =
            const Duration(milliseconds: 15);
        final h = _Run(
            refuseDirect: home ? 'no_route' : null,
            statuses: {home ? 'ord_home' : 'ord_direct': status});
        // The source endpoint may still show its old figure; only explicit
        // refund proof can release the accepted send's reservation.
        h.onSourceStatus = () => h.predictions.cash = 5;
        final run = await h.start(trackCash: true);
        await run.ended;
        double available() => h.c
            .read(venueCashLastReadProvider)!
            .candidates
            .singleWhere((s) => s.venue == OneBalanceVenue.predictions)
            .availableUsd;
        await h.until(() =>
            (available() - (status == 'refunded' ? 5 : 0.8)).abs() < 1e-6);
        expect(available(), closeTo(status == 'refunded' ? 5 : 0.8, 1e-6));
        expect(h.predictions.cashReads, status == 'refunded' ? 2 : 1,
            reason: 'only the explicit refund requests one reconciliation');
      });
    }
  }

  test('a refund from a retired snapshot cannot refresh a new generation',
      () async {
    final h = _Run(statuses: const {'ord_direct': 'refunded'});
    var replaced = false;
    h.onSourceStatus = () {
      if (replaced) return;
      replaced = true;
      h.c.invalidate(venueCashSnapshotProvider);
      final next = h.c.read(venueCashSnapshotProvider);
      h.c.read(venueCashLastReadProvider.notifier).state = (
        walletId: next.walletId,
        candidates: [
          (
            venue: OneBalanceVenue.predictions,
            availableUsd: 7,
            eta: const Duration(minutes: 1),
            minimumUsd: 1
          )
        ],
      );
    };
    final run = await h.start(trackCash: true);
    await run.ended;
    expect(replaced, isTrue);
    expect(
        h.c.read(venueCashLastReadProvider)!.candidates.single.availableUsd, 7);
  });

  test(
      'the founder\'s order: Predictions \$5 + Dollars \$5 + Investing '
      '\$2.37 for \$10.76: both sources start together, Predictions goes '
      'straight in, one line per source, the order fires on the credit',
      () async {
    final h = _Run(holdDirect: true);
    final run = await h.start();
    // Before the Predictions leg has even gone, the Dollars already held
    // are on their way (the order queued with them).
    await h.until(() => h.queued.isNotEmpty);
    expect(h.predictions.direct, isEmpty);
    expect(h.queued.single.fundUsd, 5.0);
    // The venue counts what the direct leg brings: Dollars send only
    // their share.
    expect(h.queued.single.readyUsd, greaterThan(2.37));
    final g0 = h.record.steps;
    expect([for (final l in g0.legs) l.id], ['leg:predictions', 'leg:dollars']);
    expect(g0.byId('leg:predictions')!.route, MoneyRoute.direct);
    expect(
        g0
            .byId('leg:dollars')!
            .startedAt!
            .difference(g0.byId('leg:predictions')!.startedAt!)
            .inMilliseconds
            .abs(),
        lessThan(50));
    expect(_lines(l10n, g0), [
      'Moving \$4.20 from Predictions',
      'Moving \$5.00 from Dollars',
      'Preparing your order',
      // Nothing at Investing before both legs' money is there.
      'Waiting for both to arrive',
      'Crediting to trading balance',
      'Opening \$10.76 Long BTC',
    ]);
    h.predictions.hold.complete();
    expect(await run.ended, BitcoinFundedEnd.placed);
    expect(h.predictions.direct, [4.20]);
    expect(h.predictions.home, isEmpty);
    expect(h.more, isEmpty);
    final g = h.record.steps;
    expect(g.byId('leg:predictions')!.status, MoneyStepStatus.done);
    expect(g.byId('leg:predictions')!.ref, 'ord_direct');
    expect(g.byId('leg:dollars')!.status, MoneyStepStatus.done);
    expect(g.byId('ready:credit')!.status, MoneyStepStatus.done);
    expect(g.byId('place')!.status, MoneyStepStatus.done);
    expect(h.record.stage, FundedOrderStage.done);
    expect(h.record.route, MoneyRoute.direct);
    // One Activity row: the Dollars move is the move's own step.
    final move = MultiSourceMoveStore.all().single;
    expect(move.finalOperationId, 'op_dollars');
    expect(move.legs.single.direct, isTrue);
    // The funnel's end carries the route and each leg's time.
    final completed =
        events.where((e) => e.$1 == 'order_funding_completed').single.$2!;
    expect(completed['route'], 'direct');
    expect(completed['ms_leg_predictions'], isA<int>());
    expect(completed['ms_leg_dollars'], isA<int>());
    for (final e in events) {
      for (final v in (e.$2 ?? const {}).values.whereType<String>()) {
        expect(v.contains('ord_') || v.contains('0x') || v.contains('spark1'),
            isFalse,
            reason: '${e.$1} carries an id or an address');
      }
    }
  });

  test(
      'the via-Dollars fallback keeps the lines, with the real reason: the '
      'Predictions leg lands by its order status while the Dollars balance '
      'still reads nothing, then goes on into Investing', () async {
    final h = _Run(
      refuseDirect: 'wallet_guard_recipient_not_own',
      dollarsAfterCheck: 4.15,
    );
    final run = await h.start();
    // The Dollars share leaves at once; then Dollars read nothing (the
    // SDK's token row is behind) while the leg home lands.
    await h.until(() => h.queued.isNotEmpty);
    h.dollars = 0;
    expect(await run.ended, BitcoinFundedEnd.placed);
    expect(h.predictions.home, [4.20]);
    expect(h.predictions.direct, isEmpty);
    // Landed by its order status: Dollars were then asked to catch up,
    // and the move on sent what landed, within what the approval has
    // left ($9.11 in all, $5.00 of it already sent).
    expect(h.checks, 1);
    expect(h.more, [4.11]);
    final g = h.record.steps;
    expect(g.byId('leg:predictions')!.status, MoneyStepStatus.fellBack);
    expect(g.byId('leg:predictions')!.reason, 'wallet_guard_recipient_not_own');
    expect(g.byId('leg:predictions:via_dollars')!.status, MoneyStepStatus.done);
    expect(g.byId('leg:predictions:via_dollars')!.ref, 'ord_home');
    expect(
        g.byId('leg:dollars:onward:predictions')!.status, MoneyStepStatus.done);
    expect(g.byId('place')!.status, MoneyStepStatus.done);
    expect(_lines(l10n, g).take(4).toList(), [
      // Never "route busy": the wallet's own guard said no.
      'Predictions going via Dollars',
      'Moved \$4.20 from Predictions → Dollars',
      'Moved \$4.11 from Dollars',
      'Moved \$5.00 from Dollars',
    ]);
    // What came home and went on is no longer counted as on its way.
    expect(h.puller.pendingUsd, 0);
    // The move's record keeps the reason for its Activity detail.
    final move = MultiSourceMoveStore.all().single;
    expect(move.legs.single.fellBack, 'wallet_guard_recipient_not_own');
    expect(MoveSteps.of(move).byId('leg:predictions')!.reason,
        'wallet_guard_recipient_not_own');
    final completed =
        events.where((e) => e.$1 == 'order_funding_completed').single.$2!;
    expect(completed['route'], 'via_dollars');
    expect(completed['route_reason'], 'wallet_guard_recipient_not_own');
    final refused =
        events.where((e) => e.$1 == 'venue_cash_direct_refused').toList();
    // A guard refusal is not asked twice.
    expect(refused, hasLength(1));
    expect(refused.single.$2!['reason'], 'wallet_guard_recipient_not_own');
  });

  test(
      'a leg that never lands stops clearly within its bound: the order '
      'goes, the steps say where the money is', () async {
    VenueCashFundedOrderRunner.legMaxWait = const Duration(milliseconds: 60);
    final h = _Run(statuses: const {'ord_direct': 'processing'});
    final run = await h.start();
    expect(await run.ended.timeout(const Duration(seconds: 5)),
        BitcoinFundedEnd.ready);
    expect(h.dropped, 1);
    expect(h.grant.revoked, isTrue);
    final r = h.record;
    expect(r.stage, FundedOrderStage.ready);
    expect(r.reason, 'timeout');
    // It lands in Investing whenever it does.
    expect(r.moneyAt, FundedMoneyAt.venue);
    expect(r.steps.byId('leg:predictions')!.status, MoneyStepStatus.failed);
    expect(r.steps.byId('leg:predictions')!.reason, 'timeout');
    // The wait for both legs stops with the run; nothing at Investing
    // (the credit, the order) ever started.
    await h.until(() => h.record.steps.byId('ready:gather')!.status.ended);
    expect(h.record.steps.byId('ready:gather')!.status, MoneyStepStatus.failed);
    expect(
        h.record.steps.byId('ready:credit')!.status, MoneyStepStatus.waiting);
    expect(h.record.steps.byId('place')!.status, MoneyStepStatus.waiting);
    expect(
        events
            .where((e) => e.$1 == 'order_funding_failed')
            .single
            .$2!['error_category'],
        'timeout');
  });
}
