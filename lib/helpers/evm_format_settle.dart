import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/recovery_evm_format.dart';
import 'package:kute/services/venue_total_cache_service.dart';

/// Settles a recovered wallet's pending EVM format check in the session it
/// was recovered in.
///
/// A phrase recovery whose venue check could not finish keeps the standard
/// format with [WalletConfig.evmFormatCheckPending]. The check used to be
/// retried only on the next cold-start PIN unlock, so a restore ran its
/// whole first session on an unsettled format. This runs the retry on a
/// short bounded schedule ([RecoveryEvmFormat.settleBackoff]) while the app
/// is unlocked and online; Predictions waits (sets nothing up) until it
/// settles. One schedule at a time; callers just ask for it.
abstract final class EvmFormatSettle {
  static Future<void>? _running;

  /// Replaces the schedule in tests (provider tests build the trading
  /// notifier with a pending wallet and must not start real timers).
  @visibleForTesting
  static void Function(ProviderContainer container)? debugScheduleOverride;

  /// Starts the schedule unless one is running or nothing is pending.
  /// Never throws.
  static void schedule(ProviderContainer container) {
    final override = debugScheduleOverride;
    if (override != null) {
      override(container);
      return;
    }
    if (_running != null) return;
    try {
      final pending = container.read(settingsProvider).wallets.any(
          (w) => w.evmFormatCheckPending && RecoveryCheck.holdsStoredSeed(w));
      if (!pending) return;
    } catch (_) {
      return;
    }
    _running = run(container).whenComplete(() => _running = null);
  }

  /// The schedule itself, awaited by the cold-start unlock path.
  static Future<void> run(ProviderContainer container) {
    bool canRun() {
      try {
        return container.read(sessionUnlockedProvider) &&
            container.read(onlineProvider);
      } catch (_) {
        return false;
      }
    }

    return RecoveryEvmFormat.settlePending(
      settings: container.read(settingsProvider.notifier),
      wallets: () => container.read(settingsProvider).wallets,
      canRun: canRun,
      readMnemonic: (walletId) => AuthModel().getMnemonic(walletId,
          access: SeedAccess.automatic,
          session: container.read(seedSessionProvider)),
      onAdopted: (walletId, mnemonic, {required hyperliquidActive}) =>
          afterAdopted(container, walletId, mnemonic,
              hyperliquidActive: hyperliquidActive),
    );
  }

  /// A recovered wallet just moved to its legacy EVM account: drop the
  /// venue caches built for the old account, rebuild what derived it, and
  /// set Predictions up for the new one.
  static Future<void> afterAdopted(
    ProviderContainer container,
    String walletId,
    String mnemonic, {
    required bool hyperliquidActive,
  }) async {
    await forgetPolymarketAccountCache(walletId);
    await VenueTotalCacheService.deleteWallet(walletId);
    if (hyperliquidActive) {
      await HyperliquidOnboardingService.markEnabled(walletId);
    }
    container
      ..invalidate(polymarketTradingProvider)
      ..invalidate(polymarketBalanceProvider)
      ..invalidate(hyperliquidTradingProvider)
      ..invalidate(hyperliquidAddressProvider);
    unawaited(provisionPolymarketAccount(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: EvmDerivationVersion.legacySha256));
  }
}
