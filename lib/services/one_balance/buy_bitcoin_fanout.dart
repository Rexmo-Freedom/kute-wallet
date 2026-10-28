// A multi-source Buy Bitcoin starts each approved source independently.
// Ordinary order-funding priorities and single-source purchases are unchanged.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/tracking_service.dart';

enum ParallelDollarsEnd { submitted, notSent, unknown, skipped, none }

typedef ParallelDollarsBuy = Future<DollarsToBitcoinSent> Function(
    double usd, AuthGrant grant, String moveId, void Function() onFunding);

class BitcoinPurchaseFanoutResult {
  const BitcoinPurchaseFanoutResult(
      {required this.pull, required this.grant, required this.dollarsEnd});
  final VenueCashPullOutcome pull;

  /// Only the unsent venue/fallback part; initial Dollars have a separate cap.
  final AuthGrant grant;
  final ParallelDollarsEnd dollarsEnd;
}

class BitcoinPurchaseFanout {
  BitcoinPurchaseFanout({required ParallelDollarsBuy buy}) : _buy = buy;
  final ParallelDollarsBuy _buy;
  final Map<String, Future<BitcoinPurchaseFanoutResult>> _running = {};

  Future<BitcoinPurchaseFanoutResult> start({
    required VenueCashPuller puller,
    required VenueCashPlan plan,
    required AuthGrant approval,
    required String walletId,
    required String ownSpark,
    String? moveId,
    void Function(VenueCashPlan)? onPlanned,
    void Function(VenueCashLegOutcome)? onLeg,
    void Function(String)? onStarted,
  }) {
    final id = moveId ?? MultiSourceMoveStore.newId();
    final existing = _running[id];
    if (existing != null) {
      approval.revoke();
      return existing;
    }
    final work = _start(id, puller, plan, approval, walletId, ownSpark,
        onPlanned, onLeg, onStarted);
    _running[id] = work;
    return work.whenComplete(() => _running.remove(id));
  }

  Future<BitcoinPurchaseFanoutResult> _start(
      String id,
      VenueCashPuller puller,
      VenueCashPlan plan,
      AuthGrant approval,
      String walletId,
      String ownSpark,
      void Function(VenueCashPlan)? onPlanned,
      void Function(VenueCashLegOutcome)? onLeg,
      void Function(String)? onStarted) async {
    // Re-derive the exact immutable source plan that was reviewed, before
    // issuing child scopes. A changed recipient/source mix requires approval.
    final reviewed = DirectLegGrants.buyBitcoin(
      walletId: walletId,
      ownSpark: ownSpark,
      route: kDollarsToBtcRoute.label,
      asset: 'USDB',
      totalUsd: plan.neededUsd,
      directLegs: puller.directLegLimit(plan, VenueCashDestination.bitcoin),
      ttl: AuthGrants.autofireTtl,
    );
    GrantGuard.consume(approval, reviewed,
        allowed: const {SensitiveAction.moveTransfer});
    final initial = math.min(plan.dollarsUsd, plan.neededUsd);
    AuthGrant child(double usd, {required bool venues}) {
      final now = AuthGrants.clock();
      final remaining = approval.expiresAt.difference(now);
      if (remaining <= Duration.zero || approval.revoked) {
        throw const GrantExpired();
      }
      final intent = reviewed.copyWith(
          amountMax: IntentUnits.usd(usd),
          limits: {
            for (final entry in reviewed.limits.entries)
              if (venues || entry.key != VenueLimit.directLegs)
                entry.key: entry.value
          },
          ttl: remaining);
      // The reviewed parent was consumed above. Both children are strictly
      // disjoint dollar budgets and neither can outlive that approval.
      return AuthGrants.issue(intent, method: approval.method, now: now);
    }

    final venueGrant =
        child(math.max(0.0, plan.neededUsd - initial), venues: true);
    final initialGrant = initial > 0 ? child(initial, venues: false) : null;
    Future<ParallelDollarsEnd>? initialWork;
    try {
      final pull = await puller.pullShortfall(
        neededUsd: plan.neededUsd,
        forAction: VenueCashFor.buyBitcoin,
        destination: VenueCashDestination.bitcoin,
        moveId: id,
        approval: venueGrant,
        plan: plan,
        waitFor: Duration.zero,
        deferFinishEvent: true,
        onPlanned: onPlanned,
        onLeg: onLeg,
        onStarted: (move) {
          MultiSourceMoveStore.markParallelPurchase(move);
          if (initialGrant != null) {
            MultiSourceMoveStore.updateSteps(
                move,
                (record) =>
                    MoveSteps.withInitialDollars(record.steps, initial));
            initialWork = _initial(move, initial, initialGrant);
          }
          onStarted?.call(move);
        },
      );
      final initialEnd =
          await (initialWork ?? Future.value(ParallelDollarsEnd.none));
      final onward = math.max(0.0, pull.dollarsNeededUsd - initial);
      // All original venue calls have finished submission. Retire their
      // direct rights and expose only this exact onward cash budget.
      venueGrant.revoke();
      final canContinue =
          !approval.revoked && !approval.isExpiredAt(AuthGrants.clock());
      final onwardGrant = onward > 0 && canContinue
          ? child(onward, venues: false)
          : venueGrant; // inert; no onward transfer is authorized
      final recorded = MultiSourceMoveStore.get(id);
      TrackingService.track('multi_source_move_finished', params: {
        'delivered_usd': recorded?.deliveredUsd ?? 0,
        'failed_legs': pull.failedLegs.length +
            (initialEnd == ParallelDollarsEnd.notSent ? 1 : 0),
        'destination': VenueCashFor.buyBitcoin,
        'landed': false,
        'dollars_usd': recorded?.initialDollarsSentUsd ?? 0,
        'dollars_outcome': initialEnd.name,
      });
      approval.revoke();
      return BitcoinPurchaseFanoutResult(
        pull: VenueCashPullOutcome(
            plan: pull.plan,
            legs: pull.legs,
            dollarsCover: onward < .01,
            eta: pull.eta,
            destination: pull.destination,
            moveId: pull.moveId,
            onwardUsd: onward,
            alreadyDeliveredUsd: pull.alreadyDeliveredUsd),
        grant: onwardGrant,
        dollarsEnd: initialEnd,
      );
    } catch (_) {
      approval.revoke();
      venueGrant.revoke();
      if (initialWork == null) initialGrant?.revoke();
      rethrow;
    }
  }

  Future<ParallelDollarsEnd> _initial(
      String id, double usd, AuthGrant grant) async {
    var funding = false;
    try {
      final result = await _buy(usd, grant, id, () => funding = true);
      MultiSourceMoveStore.attachInitialDollars(
          id, result.operationId, result.sentUsd);
      _initialState(id, MoneyStepStatus.running,
          operationId: result.operationId);
      return ParallelDollarsEnd.submitted;
    } on DollarsToBitcoinBelowMinimum {
      _initialState(id, MoneyStepStatus.skipped, reason: 'below_minimum');
      return ParallelDollarsEnd.skipped;
    } catch (_) {
      _initialState(
          id, funding ? MoneyStepStatus.running : MoneyStepStatus.failed,
          reason: funding ? 'outcome_unknown' : 'not_sent');
      return funding ? ParallelDollarsEnd.unknown : ParallelDollarsEnd.notSent;
    } finally {
      grant.revoke();
    }
  }
}

void _initialState(String id, MoneyStepStatus status,
    {String? reason, String? operationId}) {
  MultiSourceMoveStore.updateSteps(
      id,
      (move) => MoveSteps.initialDollarsState(move.steps, status,
          reason: reason, operationId: operationId));
}

/// Only a failure proven before the native funding callback is retryable.
/// An accepted result or an ambiguous native send is never submitted again.
bool initialDollarsRetryable(MultiSourceMove move) {
  final step = move.steps.byId(MoveSteps.initialDollarsId);
  return move.initialDollarsOperationId == null &&
      step?.ref == null &&
      step?.status == MoneyStepStatus.failed &&
      step?.reason == 'not_sent';
}

final _initialRetries = <String>{};
Future<void> retryInitialDollarsPurchase(ProviderReader read,
    {required String moveId, required AuthGrant grant}) async {
  final move = MultiSourceMoveStore.get(moveId);
  if (move == null ||
      !initialDollarsRetryable(move) ||
      move.walletId != grant.walletId ||
      !_initialRetries.add(moveId)) {
    grant.revoke();
    return;
  }
  final usd = move.steps.byId(MoveSteps.initialDollarsId)!.usd;
  var funding = false;
  _initialState(moveId, MoneyStepStatus.running);
  try {
    await buyBitcoinFromDollars(read,
        amountBaseUnits: IntentUnits.usd(usd),
        usd: usd,
        stepUp: approvedPurchaseStepUp(grant),
        moveId: moveId,
        initialDollars: true,
        onFunding: () => funding = true);
  } catch (error) {
    _initialState(
        moveId,
        error is DollarsToBitcoinBelowMinimum
            ? MoneyStepStatus.skipped
            : funding
                ? MoneyStepStatus.running
                : MoneyStepStatus.failed,
        reason: error is DollarsToBitcoinBelowMinimum
            ? 'below_minimum'
            : funding
                ? 'outcome_unknown'
                : 'not_sent');
    rethrow;
  } finally {
    _initialRetries.remove(moveId);
    grant.revoke();
  }
}

final bitcoinPurchaseFanoutProvider = Provider<BitcoinPurchaseFanout>((ref) =>
    BitcoinPurchaseFanout(
        buy: (usd, grant, id, onFunding) => buyBitcoinFromDollars(ref.read,
            amountBaseUnits: IntentUnits.usd(usd),
            usd: usd,
            stepUp: approvedPurchaseStepUp(grant),
            moveId: id,
            initialDollars: true,
            onFunding: onFunding)));
