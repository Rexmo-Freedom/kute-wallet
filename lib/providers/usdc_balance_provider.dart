import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';

/// Unified USDC balance across all platforms:
/// Polymarket USDC.e on Polygon + Hyperliquid free USDC (perp
/// withdrawable + unheld spot USDC — margin locked in open positions is
/// portfolio value, not cash, so it's excluded on purpose).
/// Keeps alive so the balance doesn't flicker when widgets rebuild.
final usdcBalanceProvider = Provider<double>((ref) {
  final polymarketUsdc = ref.watch(polymarketBalanceProvider);
  final hyperliquidUsdc = ref.watch(hyperliquidFreeUsdcProvider);
  return polymarketUsdc + hyperliquidUsdc;
});
