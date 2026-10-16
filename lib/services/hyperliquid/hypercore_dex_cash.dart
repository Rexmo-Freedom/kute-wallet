import 'dart:math' as math;
import 'dart:async';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

/// Report same-account collateral readiness to a queued order without coupling
/// the trading service to the pending-order provider. Direct orders need no
/// listener; the callback lives only for this placement attempt.
abstract final class OwnDexReadiness {
  static final Object _key = Object();
  static final Object _waitingKey = Object();
  static Future<T> follow<T>(Future<T> Function() action, void Function() ready,
          {void Function()? waiting}) =>
      runZoned(action, zoneValues: {_key: ready, _waitingKey: waiting});
  static void ready() => (Zone.current[_key] as void Function()?)?.call();
  static void waiting() =>
      (Zone.current[_waitingKey] as void Function()?)?.call();
}

/// A transfer was acknowledged but its target cash is not yet readable.
/// This is deliberately distinct from a margin rejection: retrying the whole
/// placement could submit another transfer against stale source balances.
class OwnDexCreditPending implements Exception {
  const OwnDexCreditPending();
}

/// A transfer acknowledgement precedes its clearinghouse read becoming usable.
/// Never submit the order against stale collateral, or resend a transfer while
/// waiting. Every read and the whole wait are bounded.
Future<void> waitForOwnDexCash({
  required Future<double> Function() availableUsd,
  required double requiredUsd,
  Duration maxWait = const Duration(seconds: 8),
  Duration pollEvery = const Duration(milliseconds: 300),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < maxWait) {
    final left = maxWait - clock.elapsed;
    try {
      final available = await availableUsd().timeout(left);
      if (available.isFinite && available + 1e-6 >= requiredUsd) return;
    } catch (_) {
      // Reads alone are retried. No money-moving action runs in this wait.
    }
    if (clock.elapsed >= maxWait) break;
    await Future<void>.delayed(pollEvery < maxWait - clock.elapsed
        ? pollEvery
        : maxWait - clock.elapsed);
  }
  throw const OwnDexCreditPending();
}

/// Collect only withdrawable collateral for a reviewed action. Exchange
/// withdrawal caps preserve margin; the destination is always the same owner.
/// A failed or ambiguous transfer aborts, without trying another route.
Future<void> collectOwnDexCash({
  required HyperliquidModel model,
  required HyperliquidExchangeService exchange,
  required double requiredDefaultUsd,
  String excludeDex = '',
  void Function()? beforeSend,
}) async {
  if (!requiredDefaultUsd.isFinite || requiredDefaultUsd < 0) {
    throw ArgumentError('Invalid collateral requirement');
  }
  if (requiredDefaultUsd == 0) return;
  final base = await model.getAccountSnapshot(exchange.walletAddress);
  if (!base.withdrawable.isFinite || base.withdrawable < 0) {
    throw const FormatException('Collateral unavailable');
  }
  var shortfall = requiredDefaultUsd - base.withdrawable;
  if (shortfall <= 0) return;
  final dexes = await model.getUsdcDexAccounts(exchange.walletAddress);
  // Validate the complete reserve before moving any collateral. Holdings
  // reserved for positions or open orders are never included.
  final available = dexes.entries
      .where((e) => e.key != excludeDex)
      .fold<double>(0, (total, e) => total + math.max(0, e.value.withdrawable));
  if (!available.isFinite || available + 1e-6 < shortfall) {
    throw const HyperliquidInsufficientMarginException(
        'Insufficient withdrawable USDC');
  }
  for (final entry in dexes.entries) {
    if (entry.key == excludeDex) continue;
    final amount =
        (math.min(shortfall, entry.value.withdrawable) * 1e6).floorToDouble() /
            1e6;
    if (amount <= 0) continue;
    await exchange.moveOwnUsdc(
        sourceDex: entry.key,
        destinationDex: '',
        amount: amount,
        beforeSend: beforeSend);
    shortfall -= amount;
    if (shortfall <= 1e-6) return;
  }
  if (shortfall > 1e-6) {
    throw const HyperliquidInsufficientMarginException(
        'Insufficient withdrawable USDC');
  }
}
