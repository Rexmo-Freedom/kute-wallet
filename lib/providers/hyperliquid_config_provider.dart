import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

final hyperliquidTradingEnabledProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.trade'));
final hyperliquidDepositsEnabledProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.deposit'));
final hyperliquidWithdrawalsEnabledProvider = Provider.autoDispose<bool>(
    (ref) =>
        ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.withdraw'));
final hyperliquidGeoAllowedProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.browse'));
