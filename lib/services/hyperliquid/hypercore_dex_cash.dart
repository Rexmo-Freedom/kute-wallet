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

/// How long an order waits for the builder dex to show the collateral it
/// was just sent ([waitForOwnDexCash]'s [maxWait] on the order path).
/// Nothing moves during the wait: it is long enough for a slow dex read,
/// so the first order on a builder market does not give up while its cash
/// is on the way, only to work the second time.
const Duration kOwnDexCreditWait = Duration(seconds: 30);

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
/// Returns what it moved into the main perpetuals account (0: nothing).
///
/// Each leg is the shortfall rounded UP to the transfer's micro-dollar (never
/// more than that dex's whole micro-dollars): flooring it left the main
/// account a fraction of a micro-dollar short of an exact eight-decimal
/// requirement, and the send that followed then asked spot for the rest.
Future<double> collectOwnDexCash({
  required HyperliquidModel model,
  required HyperliquidExchangeService exchange,
  required double requiredDefaultUsd,
  String excludeDex = '',
  void Function()? beforeSend,
}) async {
  if (!requiredDefaultUsd.isFinite || requiredDefaultUsd < 0) {
    throw ArgumentError('Invalid collateral requirement');
  }
  if (requiredDefaultUsd == 0) return 0;
  final base = await model.getAccountSnapshot(exchange.walletAddress);
  if (!base.withdrawable.isFinite || base.withdrawable < 0) {
    throw const FormatException('Collateral unavailable');
  }
  var shortfall = requiredDefaultUsd - base.withdrawable;
  if (shortfall <= 0) return 0;
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
  var moved = 0.0;
  for (final entry in dexes.entries) {
    if (entry.key == excludeDex) continue;
    final whole = (entry.value.withdrawable * 1e6 + 1e-3).floorToDouble();
    final wanted = (shortfall * 1e6 - 1e-3).ceilToDouble();
    final amount = math.min(wanted, whole) / 1e6;
    if (amount <= 0) continue;
    await exchange.moveOwnUsdc(
        sourceDex: entry.key,
        destinationDex: '',
        amount: amount,
        beforeSend: beforeSend);
    moved += amount;
    shortfall -= amount;
    if (shortfall <= 1e-6) return moved;
  }
  if (shortfall > 1e-6) {
    throw const HyperliquidInsufficientMarginException(
        'Insufficient withdrawable USDC');
  }
  return moved;
}

/// How long a send out of the main perpetuals account waits for the main
/// account's read to show cash just moved into it from the person's own
/// builder dex or spot balance ([gatherOwnPerpCash]). Reads only. Shorter
/// than an order's [kOwnDexCreditWait]: the one-time CCTP quote in hand has
/// at least 75 s left when the send starts and must keep 30 s at the POST.
const Duration kOwnPerpCreditWait = Duration(seconds: 20);

/// Gathers the person's own Investing cash into the main perpetuals account
/// before a send out of it (a CCTP burn, a native `usdSend`): first
/// [requiredDefaultBaseUnits] (eight-decimal USDC) from the builder dexes
/// ([collectOwnDexCash]), then whatever [spotMove] still asks of unheld
/// spot USDC, and after each internal move it WAITS (reads only, bounded by
/// [maxWait]) until the main account's own read shows [requiredBaseUnits]
/// there. Never touches a position's margin; every move stays in the same
/// account.
///
/// Why the wait: an acknowledged same-account transfer is not yet in the
/// clearinghouse read. Without it, a Swap right after a stock round-trip
/// (its cash back on the builder dex) moved the cash home, read the main
/// account at once, found it short and stopped the leg as "not sent"; the
/// Retry, finding the cash already home, went through (founder, 12
/// November 2026). The order path learnt the same lesson
/// ([waitForOwnDexCash]).
///
/// [beforeSend] runs right before each internal POST, [afterSend] right
/// after each one is acknowledged. Throws (nothing external sent) when the
/// cash is not there: [HyperliquidInsufficientMarginException],
/// [OwnDexCreditPending], or what [spotMove] throws.
Future<void> gatherOwnPerpCash({
  required HyperliquidModel model,
  required HyperliquidExchangeService exchange,
  required BigInt requiredBaseUnits,
  required BigInt requiredDefaultBaseUnits,
  required Future<BigInt> Function() spotMove,
  void Function()? beforeSend,
  void Function()? afterSend,
  Duration maxWait = kOwnPerpCreditWait,
  Duration pollEvery = const Duration(milliseconds: 300),
}) async {
  final clock = Stopwatch()..start();
  Duration left() {
    final rest = maxWait - clock.elapsed;
    return rest > Duration.zero ? rest : Duration.zero;
  }

  Future<void> settled(BigInt required) => waitForOwnDexCash(
        requiredUsd: required.toDouble() / 1e8,
        maxWait: left(),
        pollEvery: pollEvery,
        availableUsd: () async =>
            (await model.getAccountSnapshot(exchange.walletAddress))
                .withdrawable,
      );

  final fromDexes = await collectOwnDexCash(
      model: model,
      exchange: exchange,
      requiredDefaultUsd: requiredDefaultBaseUnits.toDouble() / 1e8,
      beforeSend: beforeSend);
  afterSend?.call();
  if (fromDexes > 0) await settled(requiredDefaultBaseUnits);
  final fromSpot = await spotMove();
  if (fromSpot > BigInt.zero) {
    await exchange.usdClassTransfer(
      amount: fromSpot.toDouble() / 1e8,
      toPerp: true,
      beforeSend: beforeSend,
    );
    afterSend?.call();
    await settled(requiredBaseUnits);
  }
}
