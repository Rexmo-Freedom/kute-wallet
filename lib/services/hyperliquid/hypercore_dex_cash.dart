import 'dart:math' as math;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

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
