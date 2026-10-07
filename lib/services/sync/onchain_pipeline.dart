// Native BDK owns on-chain wallet I/O on a serial platform executor.
// External-address wallets continue to use the HTTP address service.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/sync/sync_status.dart';

class OnchainPipeline {
  OnchainPipeline();

  /// Stable name for `SyncPipelineStatus` indexing.
  static const String debugName = 'OnchainPipeline';

  ProviderContainer? _container;
  int _generation = 0;
  bool _refreshingNonActive = false;

  /// Bind to a [container] for subsequent calls. Stop tears down
  /// state but doesn't dispose the cached BDK sessions until
  /// [stop] is called explicitly — they're cheap to hold and the
  /// Wallet handles can't safely cross a container rebuild
  /// boundary, so we keep them alive for the whole service lifetime.
  void start(ProviderContainer container) {
    _generation++;
    _container = container;
  }

  void stop() {
    _generation++;
    _container = null;
  }

  /// Active-wallet sync — delegates to the [BackgroundSyncNotifier]
  /// `performFullUpdate` chain (BDK + Spark + Polymarket activity +
  /// USDC receives + swap orders + outlogic + currency + polymarket
  /// trading state). When [fanOut] is true, also kicks the cross-
  /// wallet refresh + BDK warming for the user's other wallets;
  /// callers gate this on the All-Accounts scope so we don't pay
  /// for picker-card freshness when nothing on screen reads it.
  ///
  /// Status (`running` → `idle`/`failing`) is reported through
  /// [syncPipelineStatusProvider] under the [debugName] key.
  ///
  /// Generation handling: the pipeline captures ITS OWN `_generation`
  /// at entry and uses it for mid-flight staleness checks. Callers
  /// used to pass the *service's* generation counter here, but the two
  /// counters advance independently (the pipeline's on every
  /// start()/stop(), the service's only on restart()), so after the
  /// first app background/resume cycle they permanently diverged and
  /// every background sync tick returned before doing any work — the
  /// bug that froze Predictions/Investing deposit + withdrawal rows on
  /// "pending" until a manual pull-to-refresh.
  Future<void> runActiveWalletSync({bool fanOut = false}) async {
    final container = _container;
    if (container == null) return;
    final gen = _generation;
    final status = container.read(syncPipelineStatusProvider.notifier);
    status.markRunning(debugName);
    try {
      // Keep the existing refresh cadence. Native BDK performs its work on
      // the platform executor while the Flutter UI remains responsive.
      await container
          .read(backgroundSyncNotifierProvider.notifier)
          .performFullUpdate(force: false);
      if (_generation != gen) return;
      if (fanOut) {
        unawaited(refreshExternalAddressWallets());
        unawaited(warmHardwareAndWatchOnly());
      }
      status.markSuccess(debugName);
    } catch (e) {
      status.markFailure(debugName, e.toString());
    }
  }

  // Keep the existing on-demand refresh policy. Native ownership is shared
  // across active and scoped wallets; there is no separate Dart FFI worker.
  Future<void> prewarmAllWallets() async {}

  /// Refresh on-chain balances for non-active EXTERNAL-ADDRESS
  /// wallets via mempool.space. Best-effort per-wallet — a single
  /// API failure doesn't abort the loop.
  ///
  /// We deliberately skip Spark hot wallets (refreshing requires
  /// a Breez SDK session, which only the active wallet has) and
  /// hardware/watch-only (those go through [warmHardwareAndWatchOnly]
  /// which uses BDK + Electrum). External-address wallets are the
  /// easy case — a single concrete address with no SDK dependency.
  Future<void> refreshExternalAddressWallets() async {
    if (_refreshingNonActive) return;
    final container = _container;
    if (container == null) return;
    final gen = _generation;
    _refreshingNonActive = true;
    try {
      final settings = container.read(settingsProvider);
      final activeId = settings.activeWalletId;
      final cacheNotifier =
          container.read(walletBalanceCacheProvider.notifier);
      // The wallet the shell's first tab is showing goes to the FRONT of
      // the round. This loop is sequential and every entry costs a
      // mempool.space round trip, so a tracked wallet sitting late in
      // `settings.wallets` used to be the last balance to land right after
      // the person switched to it. Order only — nothing is scanned twice
      // and nothing else is skipped.
      final scopedId = container.read(bdkScopeWalletIdProvider);
      final ordered = [...settings.wallets];
      if (scopedId != null) {
        final at = ordered.indexWhere((w) => w.id == scopedId);
        if (at > 0) ordered.insert(0, ordered.removeAt(at));
      }
      for (final wallet in ordered) {
        if (_container == null || _generation != gen) break;
        if (wallet.id == activeId) continue;
        if (!wallet.isExternalAddress) continue;
        try {
          final address = await AuthModel().getExternalAddress(wallet.id);
          if (address == null || address.isEmpty) continue;
          final stats =
              await MempoolAddressService.fetchAddressData(address);
          if (_container == null || _generation != gen) break;
          // walletId-keyed write — survives mid-sync active wallet
          // swaps because the cache notifier indexes by id.
          cacheNotifier.updateOnChainBtcBalance(wallet.id, stats.balanceSats);
        } catch (_) {
          // Per-wallet failure stays per-wallet; loop continues.
        }
      }
    } finally {
      _refreshingNonActive = false;
    }
  }

  Future<void> warmHardwareAndWatchOnly({bool force = false}) async {}

  // Existing activation callers may await this compatibility hook. Native
  // sessions have one owner, so changing the visible wallet needs no eviction.
  Future<void> evictFromWorker(String walletId) async {}
}
