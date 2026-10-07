import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
// Recent confirmed fills for activity and Bitcoin comparisons.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';

/// The user's recent fills (newest-first from the exchange, capped at
/// 2000 there). 60 s refresh — cost basis only shifts when the user
/// trades, and position cards re-read on account changes anyway.
final hyperliquidUserFillsProvider =
    FutureProvider.autoDispose<List<HlFill>>((ref) async {
  final address = await ref.watch(hyperliquidAddressProvider.future);
  if (address == null) return const [];

  final timer = Timer.periodic(const Duration(seconds: 60), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return ref.read(hyperliquidTradingModelProvider).getUserFills(address);
});

/// History and live executions together: a new close must not hide its entry.
final hyperliquidActivityFillsProvider =
    Provider.autoDispose<List<HlFill>>((ref) {
  final history =
      ref.watch(hyperliquidUserFillsProvider).valueOrNull ?? const <HlFill>[];
  final live = ref.watch(hyperliquidTradingProvider).valueOrNull?.recentFills ??
      const <HlFill>[];
  return mergeHlFills(history, live);
});
