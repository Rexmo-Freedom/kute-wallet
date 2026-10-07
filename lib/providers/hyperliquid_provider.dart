// lib/providers/hyperliquid_provider.dart
//
// Riverpod providers fronting `HyperliquidModel`. Spot tickers refresh
// every 30 s and auto-dispose when no widget is watching. The browse cards'
// sparkline candles live in hyperliquid_sparkline_provider.dart (a
// device cache, one request per coin per UTC day).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_model.dart';

final _hyperliquidModelProvider = Provider<HyperliquidModel>((ref) {
  return HyperliquidModel();
});

/// Spot tickers keyed by token name (e.g. 'AAPL', 'NVDA'). Used for the
/// Stocks rail since equity/commodity tokens only live on HL spot.
final hyperliquidSpotTickersProvider = FutureProvider.autoDispose<({
  Map<String, HyperliquidTicker> tickers,
  Map<String, String> pairNameByToken,
})>((ref) async {
  final model = ref.watch(_hyperliquidModelProvider);

  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return model.getSpotTickers();
});
