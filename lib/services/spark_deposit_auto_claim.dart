import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/claim_policy.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/services/tracking_service.dart';

/// Automatic claims the SDK does not make itself, after every deposit
/// snapshot (connect, each sync and SDK deposit event, pull to refresh):
///
/// - Fee above the floor, within the share: a mature deposit whose claim the
///   SDK refused with MaxDepositClaimFeeExceeded is claimed when the
///   provider's required fee is within [sparkAutoClaimCeilingSats], under
///   the required fee plus the usual headroom, never above that ceiling.
///   Above it the deposit stays "Waiting for a lower fee".
/// - A stale early claim: a mature deposit whose early claim the provider
///   accepted but never settled. The SDK skips such a deposit on every later
///   pass (an early claim cannot be made twice), so nobody would claim it.
///
/// Everything else the SDK already retries on each 60 s sync under its own
/// cap; claiming those from here too would only race its claim guard.
///
/// At most one attempt per outpoint per snapshot, never two at once for the
/// same outpoint, with a growing wait between attempts. Holds only outpoint
/// keys in memory.
class SparkDepositAutoClaimer {
  SparkDepositAutoClaimer({
    required this.actions,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SparkDepositActions actions;
  final DateTime Function() _now;

  /// Waits between attempts on one outpoint: the first runs at once.
  static const backoff = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  final Map<String, ({int attempts, DateTime last})> _history = {};
  final Set<String> _inFlight = {};

  /// Outpoints this session already claimed (or found claimed): never
  /// claimed again, even if a stale snapshot still lists them.
  final Set<String> _claimed = {};

  /// Outpoints with an attempt running now.
  @visibleForTesting
  Set<String> get inFlight => Set.unmodifiable(_inFlight);

  /// The fee ceiling to claim [deposit] under automatically, with the path
  /// that allows it; null when the app leaves it to the SDK or the person.
  static ({int maxFeeSats, String path, String reasonPrefix})? plan(
      SparkUnclaimedDeposit deposit) {
    if (!deposit.isMature) return null;
    if (deposit.stage == SparkDepositStage.refunding) return null;
    final amount = deposit.amount.toInt();
    if (amount < 2) return null;
    // Never a ceiling at or above the deposit itself.
    final ceiling = min(sparkAutoClaimCeilingSats(amount), amount - 1);
    final required = deposit.requiredFeeSats;
    if (required != null) {
      if (!sparkAutoClaimCovers(
          requiredFeeSats: required, depositSats: amount)) {
        return null;
      }
      final suggested = suggestedClaimFeeSats(
              lastQuoteSats: required, depositAmountSats: amount) ??
          required;
      return (
        maxFeeSats: min(suggested, ceiling),
        path: 'auto_percent',
        reasonPrefix: 'pct'
      );
    }
    if (deposit.hasStaleEarlyClaim) {
      return (
        maxFeeSats: ceiling,
        path: 'auto_stale_early_claim',
        reasonPrefix: 'stale'
      );
    }
    return null;
  }

  /// Reviews one snapshot of [walletId]'s pending deposits. Returns once
  /// every attempt it started has finished.
  Future<void> review(
      String walletId, List<SparkUnclaimedDeposit> deposits) async {
    final listed = <String>{};
    final attempts = <Future<void>>[];
    for (final deposit in deposits) {
      final key = sparkOutpointKey(deposit.txid, deposit.vout);
      listed.add(key);
      final planned = plan(deposit);
      if (planned == null) continue;
      // One guard with every other claim: a claim running from the sheet
      // (or the SDK's refund) holds the outpoint, and this one skips.
      if (_inFlight.contains(key) || _claimed.contains(key)) continue;
      if (actions.isBusy(deposit.txid, deposit.vout)) continue;
      final past = _history[key];
      if (past != null) {
        final wait = backoff[past.attempts.clamp(0, backoff.length - 1)];
        if (_now().difference(past.last) < wait) continue;
      }
      attempts.add(_attempt(walletId, deposit, key, planned));
    }
    // A deposit the SDK no longer lists starts over if it ever returns.
    _history.removeWhere((key, _) => !listed.contains(key));
    await Future.wait(attempts);
  }

  Future<void> _attempt(
      String walletId,
      SparkUnclaimedDeposit deposit,
      String key,
      ({int maxFeeSats, String path, String reasonPrefix}) planned) async {
    _inFlight.add(key);
    final attempts = (_history[key]?.attempts ?? 0) + 1;
    _history[key] = (attempts: attempts, last: _now());
    final amount = deposit.amount.toInt();
    final feeSats = deposit.requiredFeeSats;
    try {
      final result = await actions.claim(
        walletId: walletId,
        txid: deposit.txid,
        vout: deposit.vout,
        maxFeeSats: BigInt.from(planned.maxFeeSats),
        depositAmountSats: BigInt.from(amount),
      );
      if (result.outcome != SparkDepositClaimOutcome.statusUnknown) {
        _claimed.add(key);
      }
      TrackingService.sparkDepositClaimed(
        outcome: switch (result.outcome) {
          SparkDepositClaimOutcome.submitted => 'submitted',
          SparkDepositClaimOutcome.alreadyReceived => 'already_received',
          SparkDepositClaimOutcome.noLongerPending => 'no_longer_pending',
          SparkDepositClaimOutcome.statusUnknown => 'status_unknown',
        },
        status: result.paymentStatus?.name,
        amountSats: amount > 0 ? amount : null,
        feeSats: feeSats,
        trigger: 'auto',
        path: planned.path,
      );
    } on SparkDepositActionException catch (e) {
      // Busy means the SDK or the sheet holds the outpoint right now: not
      // an attempt, so it does not grow the wait.
      if (e.reason == SparkDepositActionReason.busy) {
        _history[key] = (attempts: attempts - 1, last: _now());
      } else {
        TrackingService.autoClaimFailed(
            amountSats: amount,
            reason: '${planned.reasonPrefix}_${e.reason.name}');
      }
    } catch (_) {
      TrackingService.autoClaimFailed(
          amountSats: amount, reason: '${planned.reasonPrefix}_sdk_error');
    } finally {
      _inFlight.remove(key);
    }
  }
}
