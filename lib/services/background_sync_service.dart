import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/cash_app_payment_window_provider.dart'
    show cashAppClosedWindowScheduleProvider;
import 'package:kute/providers/current_route_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/models/onchain_types.dart' as bdk;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/sync/onchain_pipeline.dart';
import 'package:kute/services/sync/polymarket_poll_pipeline.dart';
import 'package:kute/services/sync/push_pipeline.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackgroundSyncService {
  static final BackgroundSyncService _instance = BackgroundSyncService._internal();
  factory BackgroundSyncService() {
    return _instance;
  }
  BackgroundSyncService._internal();

  Timer? _timer;
  bool _isSyncing = false;
  ProviderContainer? _container;

  int _generation = 0;
  MempoolWebSocketService? _mempoolWs;
  StreamSubscription? _wsSubscription;
  Timer? _fallbackPollTimer;
  DateTime? _lastRestSync;

  /// Counter for the periodic "refresh every other wallet's balance"
  /// trigger. Every Nth completed active-wallet sync we also poke the
  /// cache for non-active on-chain wallets so the wallet picker
  /// shows reasonably fresh numbers without the user having to
  /// manually switch into each one.
  int _syncTickCount = 0;
  static const int _allWalletsRefreshEvery = 10;

  /// On-chain pipeline — owns the BDK warm cache + non-active wallet
  /// fan-out (mempool.space for external addresses, Electrum for
  /// hardware/watch-only). Service still drives the cadence (when
  /// to refresh, when to warm) but no longer owns the FFI handles
  /// or the per-wallet bookkeeping.
  final OnchainPipeline _onchainPipeline = OnchainPipeline();

  /// Polymarket / USDC refresh — extracted into a route-aware
  /// pipeline so it can self-throttle when the user isn't on a
  /// surface that consumes Polymarket state. See
  /// [PolymarketPollPipeline] for the timer + cadence logic. The
  /// service still owns the lifecycle (start on `_startForCurrentWallet`,
  /// stop on `_stopAll`) so existing app-lifecycle hooks keep
  /// working unchanged.
  final PolymarketPollPipeline _polymarketPipeline = PolymarketPollPipeline();

  /// Push-based Spark `walletInfoStream` listener — extracted into a
  /// dedicated pipeline that owns the subscription, retry/backoff,
  /// cache writes, and debounced sync trigger. Calls back into
  /// `_runSyncIfOnHome` to delegate the route-gating decision (so
  /// the policy lives in one place — here — rather than duplicated
  /// inside the pipeline).
  late final PushPipeline _pushPipeline = PushPipeline(
    onSyncRequested: _runSyncIfOnHome,
  );

  void start(BuildContext context) {
    // Invalidate any continuous-sync loop left over from a previous
    // start. Without this, a loop parked in its 2 s sleep across a
    // background/resume cycle wakes to find a live container again and
    // keeps running alongside the freshly-spawned loop — one extra
    // loop per resume, each burning a full sync fan-out.
    _generation++;
    _container = ProviderScope.containerOf(context);
    _container!.read(backgroundSyncInProgressProvider.notifier).state = false;
    _onchainPipeline.start(_container!);

    _runStaleSparkOnchainCleanup();
    // Re-run the cleanup whenever the wallet list changes — covers
    // adds/removes/imports + role changes (e.g. a wallet that used
    // to track on-chain stops doing so) without waiting for app
    // restart.
    _walletsListSub?.close();
    _walletsListSub = _container!.listen<List<settings_model.WalletConfig>>(
      settingsProvider.select((s) => s.wallets),
      (_, __) => _runStaleSparkOnchainCleanup(),
    );

    // The "All accounts" portfolio card sums every wallet's balance
    // and surfaces a unified activity feed. We only want to do the
    // expensive cross-wallet refresh while the user is actually
    // looking at that surface (gated in `_runSync`), but the user
    // expects the numbers to be fresh the moment they swipe to it,
    // not on the next 50-second bucket. Watch the scope provider and
    // kick a one-shot refresh on the rising edge of `'all'`.
    _scopeSub?.close();
    _scopeSub = _container!.listen<bool>(
      isAllAccountsScopeProvider,
      (prev, next) {
        if (prev != true && next == true) {
          // Warm sync runs entirely inside [BdkWarmWorker] now —
          // synchronous BDK FFI no longer touches the main isolate,
          // so we don't need the 1.5 s defer or the cooldown that
          // older revisions used. Fire immediately on All-scope
          // entry; the worker handles its own queueing.
          unawaited(_refreshNonActiveWalletBalances());
          unawaited(_warmHardwareAndWatchOnlyBalances());
        }
      },
      fireImmediately: true,
    );

    _startForCurrentWallet();

    // Mint the affiliate row in the background once the SDK + paykute
    // address are ready. Idempotent — if the user already registered
    // (cached session token in secure storage) this is a no-op. On
    // wallet recovery the backend keys by Breez identity pubkey, so
    // the user gets their original affiliate code back.
    AffiliateService.startBackgroundRegistration(_container!);

    // Eagerly load every non-active hardware / watch-only wallet's
    // BDK session in the background. Each `wallet.transactions()` /
    // `wallet.balance()` we'd later need is gated by the
    // `Wallet.load` cost (SQLite open + descriptor build, ~50–
    // 200 ms per wallet). Doing them sequentially in the
    // background here means the first carousel swipe to any
    // savings page lands on an already-warm BDK session and
    // renders instantly.
    //
    // Fire-and-forget: failures of any single warm-load don't
    // block the others, and the live activation path retries the
    // load on its own if it ever needs to.
    unawaited(_onchainPipeline.prewarmAllWallets());
  }

  ProviderSubscription<List<settings_model.WalletConfig>>? _walletsListSub;
  ProviderSubscription<bool>? _scopeSub;

  void _runStaleSparkOnchainCleanup() {
    final container = _container;
    if (container == null) return;
    try {
      final settings = container.read(settingsProvider);
      final nonOnchainIds = settings.wallets
          .where((w) =>
              w.isSparkWallet)
          .map((w) => w.id);
      container
          .read(walletBalanceCacheProvider.notifier)
          .clearStaleSparkOnchain(nonOnchainIds);
    } catch (_) {}
  }

  /// Per-wallet timestamp of the last successful `_runSync` completion.
  /// Used by [restart] to skip the post-wallet-swap sync when this wallet
  /// was just synced — the carousel back-and-forth pattern (savings →
  /// spending → savings) was triggering a full 8-fetch sync on every
  /// swap, with a ~15 MB heap churn per cycle. Within the freshness
  /// window the cache is good; we keep the Spark stream subscription
  /// reattached but skip the heavy sync.
  final Map<String, DateTime> _lastSyncedAt = {};
  static const _walletSwapSyncFreshness = Duration(seconds: 10);

  void restart() {
    if (_container == null) return;
    _generation++;
    _stopAll();
    _container!.read(backgroundSyncInProgressProvider.notifier).state = false;
    _startForCurrentWallet();
  }

  /// Force an immediate sync (e.g. after a payment succeeds).
  /// Skips if a sync is already running.
  void syncNow() {
    _runSync();
  }

  /// Per-wallet scan for the wallet currently registered in
  /// `bdkScopeWalletIdProvider`. Runs a single BDK Electrum sync
  /// against that wallet, then writes balance + bitcoin txs into the
  /// wallet-keyed caches so the detail screen (and any Send / Move
  /// flow pushed from it) renders the freshest state.
  ///
  /// Single-shot by design — BDK Electrum scans on the main isolate
  /// have a known crash mode under continuous polling (the "wallet
  /// crash on scan" pattern). Callers fire this at key moments only:
  ///   * WalletDetailScreen.initState (on entry)
  ///   * Pull-to-refresh on the detail screen
  ///   * Just before Send / Move from the detail screen so the user
  ///     sees a fresh on-chain balance before drafting.
  ///
  /// Concurrent calls are coalesced via `_bdkScopeScanInFlight` — a
  /// second tap while the first scan is mid-flight returns the
  /// same future instead of spawning a parallel BDK session.
  ///
  /// [fullScan] forces a stop-gap full scan instead of the revealed-
  /// address sync. Pull-to-refresh uses it: a deposit to an address the
  /// app never revealed (taken from the hardware device or another
  /// wallet app at a higher index) is invisible to the revealed sync,
  /// and the one-time first scan may have run before that address was
  /// used.
  ///
  /// [walletId] scans that wallet instead of the scoped one: after a
  /// broadcast from a hardware / watch-only wallet, so its balance drops
  /// by the unconfirmed send (BDK only counts it once a sync sees the
  /// transaction in the mempool) whichever wallet the screen is on.
  Future<void> scanBdkScope(
      {String source = 'unknown', bool fullScan = false, String? walletId}) {
    final container = _container;
    final scopeId = container?.read(bdkScopeWalletIdProvider);
    return _scanBdkWallet(container, walletId ?? scopeId,
        source: source, fullScan: fullScan);
  }

  Future<void> _scanBdkWallet(ProviderContainer? container, String? walletId,
      {required String source, required bool fullScan}) {
    if (container == null || walletId == null) return Future.value();
    final existing = _bdkScopeScanInFlight[walletId];
    if (existing != null) return existing;
    // A send build holds this wallet's native slot while it waits for a
    // fee-rate quote. Starting a scan on top of it is exactly the overlap
    // native rejects with 'busy', and the build would then wait out the
    // whole scan. Let the build own the slot; the caller keeps whatever
    // the cache already had.
    if (NativeOnchainService.instance.isSlotReserved(walletId)) {
      return Future.value();
    }
    // Native runs ONE thread for every wallet (see OnchainPlugin's
    // single-thread executor), so a scan for another wallet is not
    // parallel work, it is work queued in front of everything else. A
    // slow wallet, a hardware one mid full scan, would otherwise hold up
    // the spending wallet's own sync and its pending receives.
    //
    // So a switch-scan stands down while another wallet is already
    // scanning rather than joining the queue. The caller keeps the cache
    // it had, and the next tick picks this wallet up.
    final busyElsewhere = _bdkScopeScanInFlight.keys
        .any((scanning) => scanning != walletId);
    if (busyElsewhere) return Future.value();
    _markScanning(container, walletId, true);
    final future = _doScanBdkScope(container, walletId,
        source: source, fullScan: fullScan);
    _bdkScopeScanInFlight[walletId] = future;
    return future.whenComplete(() {
      _bdkScopeScanInFlight.remove(walletId);
      // Cleared through the SAME container it was set with. Reading the
      // field again could find it null, or swapped, and the flag would
      // never come off: the wallet would be marked as scanning for the
      // rest of the session and its surfaces would hold a loading state
      // over a balance that had already arrived.
      _markScanning(container, walletId, false);
    });
  }

  /// Publishes / clears [walletId] in [bdkScanningWalletsProvider] so the
  /// wallet's own surfaces can render a loading state instead of a
  /// confident zero while its first scan after a tab switch runs.
  void _markScanning(ProviderContainer? container, String walletId, bool on) {
    if (container == null) return;
    try {
      final notifier = container.read(bdkScanningWalletsProvider.notifier);
      final current = notifier.state;
      if (on) {
        if (current.contains(walletId)) return;
        notifier.state = {...current, walletId};
      } else {
        if (!current.contains(walletId)) return;
        notifier.state = {...current}..remove(walletId);
      }
    } catch (_) {
      // Container torn down mid-scan; nothing is left to render.
    }
  }

  final _bdkScopeScanInFlight = <String, Future<void>>{};

  Future<void> _doScanBdkScope(ProviderContainer container, String walletId,
      {String source = 'unknown', bool fullScan = false}) async {
    final settings = container.read(settingsProvider);
    final wallet = settings.wallets.cast<settings_model.WalletConfig?>().firstWhere(
          (w) => w?.id == walletId,
          orElse: () => null,
        );
    if (wallet == null) return;

    // External-address wallets don't have a BDK descriptor — they
    // use the mempool.space path. Route through the existing
    // non-active refresher (single-wallet variant).
    if (wallet.isExternalAddress) {
      await _scanExternalAddressFor(container, wallet);
      return;
    }

    // Signer wallets never scan — they're air-gapped and only sign
    // PSBTs that arrive from the active spending wallet.
    if (wallet.isSigner) return;

    // Telemetry-only: time the scan + record ok/error. Wraps the
    // existing scan path without altering any scan logic.
    final scanSw = Stopwatch()..start();
    try {
      final bitcoinModel = await container
          .read(bitcoinModelForWalletProvider(walletId).future);
      // First sync per wallet = full Electrum scan (discovers all
      // history regardless of birth height); every sync after =
      // incremental (which sees the mempool, so 0-conf shows). Persist
      // `firstScanDone` the instant the one-time full scan succeeds so a
      // later launch goes straight to incremental instead of re-scanning
      // (or, worse, scanning incrementally against an empty DB).
      final scanAll = bitcoinModel.config.needsFullScan || fullScan;
      if (scanAll) {
        await bitcoinModel.fullScan();
        bitcoinModel.config.needsFullScan = false;
        await container
            .read(settingsProvider.notifier)
            .setFirstScanDone(walletId);
      } else {
        await bitcoinModel.sync();
      }
      if (_container == null) return;
      if (kDebugMode) {
        final b = bitcoinModel.getBalance();
        debugPrint('[onchain-sync] ok source=$source '
            'wallet=${_shortId(walletId)} full=$scanAll '
            'host=${bitcoinModel.config.electrumUrl} '
            'txs=${bitcoinModel.getTransactions().length} '
            'confirmed=${b.confirmed.toSat()} '
            'pending=${b.trustedPending.toSat() + b.untrustedPending.toSat()}');
      }

      // 1. Balance into the per-wallet balance cache. The notifier
      //    keys by walletId so this lands cleanly even though the
      //    wallet is NOT the active wallet — no cross-pollution
      //    risk because we never call setActiveWallet here.
      final balance = bitcoinModel.getBalance();
      container
          .read(walletBalanceCacheProvider.notifier)
          .updateOnChainBtcBalance(walletId, balance.total.toSat());

      // 2. Transactions: convert BDK TxDetails → BitcoinTransaction
      //    and merge into the wallet's existing transaction cache,
      //    preserving any other tx types (swap orders the
      //    user pushed into this wallet's history live alongside).
      final txDetails = bitcoinModel.getTransactions();
      final bitcoinTxs = txDetails.map((btcTx) {
        final cp = btcTx.chainPosition;
        final isConfirmed = cp is bdk.ConfirmedChainPosition;
        DateTime ts;
        if (isConfirmed) {
          final confirmTime = cp.confirmationBlockTime.confirmationTime;
          ts = confirmTime != 0
              ? DateTime.fromMillisecondsSinceEpoch(confirmTime * 1000)
              : DateTime.now();
        } else {
          ts = DateTime.now();
        }
        return BitcoinTransaction(
          id: btcTx.txid.toString(),
          timestamp: ts,
          btcDetails: btcTx,
          isConfirmed: isConfirmed,
        );
      }).toList();

      final cache = container.read(walletTransactionCacheProvider);
      final existing = cache[walletId] ?? Transaction.empty();
      final next = existing.copyWith(bitcoinTransactions: bitcoinTxs);
      container
          .read(walletTransactionCacheProvider.notifier)
          .setForWallet(walletId, next);
      scanSw.stop();
      TrackingService.bdkScan(
          result: 'ok', latencyMs: scanSw.elapsedMilliseconds, source: source);
    } catch (e) {
      scanSw.stop();
      TrackingService.bdkScan(
          result: 'error',
          latencyMs: scanSw.elapsedMilliseconds,
          source: source);
      // BDK / Electrum failures stay quiet in the UI — the detail screen
      // keeps showing whatever the cache had on entry, and the user can
      // re-trigger via pull-to-refresh. The log line is the only trace.
      debugPrint('[onchain-sync] failed source=$source '
          'wallet=${_shortId(walletId)} after ${scanSw.elapsedMilliseconds}ms: $e');
    }
  }

  static String _shortId(String id) => id.length > 6 ? id.substring(0, 6) : id;

  Future<void> _scanExternalAddressFor(
    ProviderContainer container,
    settings_model.WalletConfig wallet,
  ) async {
    try {
      final address = await container
          .read(walletAddressProvider(wallet.id).future);
      if (address.isEmpty) return;

      // Fetch balance + tx list in parallel — same pair the active
      // wallet's mempool path runs (background_sync_provider.dart
      // around line 519), so tracked-address detail screens render
      // the same Activity feed and balance the spending-wallet flow
      // would have produced if this wallet were currently active.
      final results = await Future.wait([
        MempoolAddressService.fetchAddressData(address),
        MempoolAddressService.fetchAddressTransactions(address),
      ]);
      final stats = results[0] as MempoolAddressData;
      final txList = results[1] as List<MempoolTransaction>;

      container
          .read(walletBalanceCacheProvider.notifier)
          .updateOnChainBtcBalance(wallet.id, stats.balanceSats);

      final mempoolTxModels = txList.map((tx) {
        final timestamp = tx.blockTime != null
            ? DateTime.fromMillisecondsSinceEpoch(tx.blockTime! * 1000)
            : DateTime.now();
        return MempoolAddressTransaction(
          id: tx.txid,
          timestamp: timestamp,
          isConfirmed: tx.confirmed,
          details: tx,
        );
      }).toList();

      final cache = container.read(walletTransactionCacheProvider);
      final existing = cache[wallet.id] ?? Transaction.empty();
      final next = existing.copyWith(mempoolTransactions: mempoolTxModels);
      container
          .read(walletTransactionCacheProvider.notifier)
          .setForWallet(wallet.id, next);
    } catch (_) {
      // best-effort — detail screen falls back to whatever was in
      // cache, user can pull-to-refresh to retry.
    }
  }

  /// Force a full refresh: invalidates any stream-fresh guard so the
  /// next poll value sticks regardless of value direction, fans out
  /// to non-active wallets too, and reconnects the Spark stream if
  /// it had silently dropped. Called on `AppLifecycleState.resumed`
  /// and after explicit user-initiated payments so cached values
  /// don't shadow what just landed.
  Future<void> forceRefreshAll() async {
    final container = _container;
    if (container == null) return;
    try {
      // Bypass stream-fresh guards on every wallet so the next poll
      // sticks. Cheap — just clears in-memory bookkeeping.
      final cacheNotifier =
          container.read(walletBalanceCacheProvider.notifier);
      for (final w in container.read(settingsProvider).wallets) {
        cacheNotifier.invalidateStreamFreshness(w.id);
      }
    } catch (_) {}
    // Investing/Predictions pool state on resume: kick the Polymarket
    // pipeline's 30 s refresh immediately, and re-run the Hyperliquid
    // 60 s badge tick (which also refreshes hyperliquidFreeUsdcProvider
    // for the home strip — the once-flag inside keeps it a local no-op
    // for wallets that never traded). The full account snapshot is
    // only invalidated when something is actually watching it, so a
    // resume never spins up the trading stack by itself.
    unawaited(_polymarketPipeline.kickNow());
    try {
      container.invalidate(hyperliquidOpenPositionsCountProvider);
      if (container.exists(hyperliquidAccountProvider)) {
        container.invalidate(hyperliquidAccountProvider);
      }
    } catch (_) {}
    // Re-attach the Spark stream in case it dropped during background.
    _listenToWalletInfoStream();
    // Kick the active-wallet sync — but respect the per-wallet
    // freshness window. forceRefreshAll fires from biometric resume;
    // a brief biometric prompt (< 30s) on top of a wallet that was
    // just synced doesn't need another full 8-fetch performFullUpdate
    // (the 15-16 MB allocation we observed). The 5 s continuous loop
    // will catch up the moment the gate opens. Cross-wallet fan-out
    // is also skipped off the All-Accounts page — same logic as the
    // regular tick.
    await _runSync(respectFreshness: true);
    if (_isAllAccountsScope()) {
      unawaited(_refreshNonActiveWalletBalances());
      unawaited(_warmHardwareAndWatchOnlyBalances());
    }
  }

  void _startForCurrentWallet() {
    if (_container == null) return;

    final settings = _container!.read(settingsProvider);
    final activeWallet = settings.activeWallet;
    if (activeWallet?.isSigner ?? false) return;

    // The newly-active wallet is going to open its SQLite on the
    // main isolate (regular sync path). Evict it from the warm
    // worker so we don't have two isolates writing to the same DB
    // file. We wait for the worker's ack before kicking the main-
    // isolate sync — without the wait, force-refresh on a
    // hardware/watch-only wallet that the worker is mid-warming
    // would race two SQLite handles on the same DB and bring the
    // process down with a native crash.
    if (activeWallet != null) {
      // ignore: discarded_futures
      _onchainPipeline.evictFromWorker(activeWallet.id).then((_) {
        if (_container == null) return;
        _runSync(respectFreshness: true);
      });
    } else {
      _runSync(respectFreshness: true);
    }

    final isExternal = activeWallet?.isExternalAddress ?? false;
    final isSpark = activeWallet?.sparkEnabled ?? false;

    if (isSpark) {
      _listenToWalletInfoStream();
    }

    if (isExternal) {
      _startExternalAddressSync();
    } else {
      _startContinuousSync();
    }
    final container = _container;
    if (container != null) {
      _polymarketPipeline.start(container);
    }
  }

  /// Continuously syncs: run sync → wait 2 s → repeat.
  ///
  /// Normally we skip the tick when the user is not on `/home` — no
  /// portfolio surface to update off-home, so the constant rebuild
  /// cascade is wasted work. EXCEPT when the active wallet has
  /// pending status-bearing rows (an Orchestra
  /// exchange mid-flight, an
  /// unconfirmed Bitcoin tx still in the mempool, a pending Spark
  /// payment, an unclaimed deposit). Those rows surface their status
  /// on every screen that renders the activity feed (Move detail,
  /// Transactions, exchange-detail sheets); blocking the sync off
  /// `/home` left them stuck at the last-seen status until the user
  /// pulled to refresh. Status polling is comparatively cheap — the
  /// underlying call is just a status GET per pending row plus the
  /// per-tick `_gatherAndUpdateTransactions` rebuild — so we lift the
  /// gate while there's something pending and fall back to it once
  /// everything has settled.
  ///
  /// Spark `walletInfoStream` and `paymentsStream` stay subscribed
  /// regardless (push-based, debounced) so an incoming Lightning
  /// payment still updates the cache immediately. Send/Receive/etc.
  /// pull a one-shot fresh balance on screen entry where they need
  /// to.
  void _startContinuousSync() {
    final gen = _generation;
    Future<void> loop() async {
      while (_container != null && _generation == gen) {
        if (_isOnActiveSyncRoute() || _hasPendingActivity()) {
          await _runSync();
        }
        if (_container == null || _generation != gen) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    loop();
  }

  /// True when the active wallet has at least one row whose status
  /// the user is waiting on. Drives the off-home sync override so
  /// Orchestra / mempool / Spark
  /// pending rows refresh while the user sits on a non-home screen.
  bool _hasPendingActivity() {
    final container = _container;
    if (container == null) return false;
    try {
      // Every swap order lives in the swap orders store —
      // `isPending` covers the user-perceptible pending states for
      // each provider and is never true for a retired provider.
      final exchanges = container.read(swapOrdersProvider);
      if (exchanges.any(
          (e) => e.isPending || (e.isOrchestra && e.shouldPollOrchestra))) {
        return true;
      }
      // Unpaid Cash App orders whose payment window closed in the last day
      // keep reconciling off the sync routes, but only when their slower
      // status check is actually due.
      if (container
          .read(cashAppClosedWindowScheduleProvider)
          .anyRecentlyClosedDue(exchanges)) {
        return true;
      }

      final settings = container.read(settingsProvider);
      final activeId = settings.activeWalletId;
      if (activeId == null) return false;
      final cache = container.read(walletTransactionCacheProvider);
      final tx = cache[activeId];
      if (tx == null) return false;

      // Mempool-tracked Bitcoin tx (BDK + external-address wallets)
      // and unclaimed Spark deposits both flip status without user
      // input and want the activity feed to repaint when they do.
      if (tx.bitcoinTransactions.any((t) => !t.isConfirmed)) return true;
      if (tx.mempoolTransactions.any((t) => !t.isConfirmed)) return true;
      if (tx.sparkUnclaimedDeposits.isNotEmpty) return true;
      if (tx.sparkTransactions.any((t) => t.isPending)) return true;
      return false;
    } catch (_) {
      // Provider not yet initialised (very early boot, container
      // teardown). Don't synthesise an off-home tick from a missing
      // signal.
      return false;
    }
  }

  /// True when the user is currently on `/home`. Reading the route
  /// from Riverpod avoids a brittle string-match against GoRouter's
  /// internal location and keeps the check trivially cheap.
  bool _isOnHome() {
    final container = _container;
    if (container == null) return false;
    try {
      return container.read(isOnHomeRouteProvider);
    } catch (_) {
      // Provider not initialized yet (very early boot) — fall back to
      // running the sync rather than freezing the wallet on first
      // launch.
      return true;
    }
  }

  /// True when the user is on a surface that wants the active-wallet
  /// continuous sync to keep ticking. Home or the dedicated wallet
  /// detail screen — both need fresh BDK / balance data on screen.
  bool _isOnActiveSyncRoute() {
    final container = _container;
    if (container == null) return false;
    try {
      return container.read(isOnActiveSyncRouteProvider);
    } catch (_) {
      return true;
    }
  }

  /// True when the home carousel is on the all-accounts portfolio
  /// page (the aggregated total tile, [homeViewScopeProvider] == 'all').
  /// Used to gate cross-wallet balance refresh: when the user is
  /// looking at a single wallet, we only sync that one — refreshing
  /// every wallet to keep the picker numbers warm is wasted work
  /// when nothing on screen reads them.
  bool _isAllAccountsScope() {
    final container = _container;
    if (container == null) return false;
    try {
      return container.read(isAllAccountsScopeProvider);
    } catch (_) {
      return false;
    }
  }

  /// Spark `walletInfoStream` plumbing — owned by [PushPipeline].
  /// Kept as a thin shim for callers that still expect "start
  /// listening" semantics; the orchestrator state lives inside the
  /// pipeline now.
  void _listenToWalletInfoStream() {
    final container = _container;
    if (container == null) return;
    _pushPipeline.start(container);
  }

  void _stopAll() {
    _timer?.cancel();
    _timer = null;
    _pushPipeline.stop();
    _polymarketPipeline.stop();
    _stopExternalAddressSync();
    _isSyncing = false;
    _lastRestSync = null;
  }

  /// Callback the [PushPipeline] uses to ask for a transaction-list
  /// refresh after a debounced burst of Spark stream events. Decision
  /// to actually run the sync lives here so the route-gate policy
  /// stays in one place — the pipeline doesn't duplicate the home-
  /// check logic.
  void _runSyncIfOnHome() {
    if (!_isOnHome()) return;
    _runSync();
  }

  void _startExternalAddressSync() {
    _stopExternalAddressSync();

    _fallbackPollTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _runSync();
    });

    _connectWebSocket();
  }

  void _stopExternalAddressSync() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _mempoolWs?.disconnect();
    _mempoolWs = null;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
  }

  Future<void> _connectWebSocket() async {
    if (_container == null) return;

    final settings = _container!.read(settingsProvider);
    final activeWallet = settings.activeWallet;
    if (activeWallet == null || !activeWallet.isExternalAddress) return;

    final address = await _container!.read(backgroundSyncNotifierProvider.notifier)
        .getExternalAddressString();
    if (address == null || address.isEmpty) return;

    _mempoolWs = MempoolWebSocketService();

    _wsSubscription = _mempoolWs!.updates.listen((update) {
      final now = DateTime.now();
      if (_lastRestSync != null && now.difference(_lastRestSync!).inSeconds < 30) {
        return;
      }
      _runSync();
    });

    await _mempoolWs!.connect(address);
  }

  Future<void> _runSync({bool respectFreshness = false}) async {
    if (_isSyncing || _container == null) return;

    // Wallet-swap freshness gate. When the carousel triggers a
    // restart() right after a recent sync of THIS wallet (the
    // savings → spending → savings churn pattern), running a full
    // performFullUpdate again allocates ~15 MB of JSON-decoded API
    // responses + a Riverpod cascade. The cache that was just
    // written is good enough — skip and let the regular 5 s loop
    // (or the next user action) refresh when staleness matters.
    final activeWalletId =
        _container!.read(settingsProvider).activeWalletId;
    if (respectFreshness && activeWalletId != null) {
      final last = _lastSyncedAt[activeWalletId];
      if (last != null &&
          DateTime.now().difference(last) < _walletSwapSyncFreshness) {
        return;
      }
    }

    final gen = _generation;
    try {
      _isSyncing = true;
      // Heavy work (8-fetch performFullUpdate + cross-wallet fan-out)
      // owned by OnchainPipeline. Service still owns:
      //   - the `_isSyncing` mutex (one in-flight sync at a time)
      //   - the per-wallet freshness gate (`_lastSyncedAt`)
      //   - the every-Nth-tick scope decision (fan out only when on
      //     the All-Accounts page)
      //   - the generation guard against mid-sync wallet swaps.
      _syncTickCount++;
      final fanOut = _syncTickCount % _allWalletsRefreshEvery == 0 &&
          _isAllAccountsScope();
      await _onchainPipeline.runActiveWalletSync(fanOut: fanOut);
      _lastRestSync = DateTime.now();
      if (activeWalletId != null) {
        _lastSyncedAt[activeWalletId] = DateTime.now();
      }
    } catch (_) {
      // intentionally empty
    } finally {
      if (_generation == gen) {
        _isSyncing = false;
      }
    }
  }

  /// Refresh on-chain balances for non-active EXTERNAL-ADDRESS
  /// wallets. We deliberately skip Spark hot wallets (refreshing
  /// requires a Breez SDK session, only available for the active
  /// wallet) and watch-only / hardware wallets (their balance comes
  /// from BDK over an Electrum session, also active-only). The
  /// persisted balance cache from the last time they were active is
  /// good enough to keep the picker showing real numbers.
  ///
  /// External-address wallets are the easy case: a single concrete
  /// Bitcoin address with no SDK dependency, so we can hit
  /// mempool.space directly and write through the cache. Delegated
  /// to [OnchainPipeline.refreshExternalAddressWallets].
  Future<void> _refreshNonActiveWalletBalances() async {
    await _onchainPipeline.refreshExternalAddressWallets();
  }

  void stop() {
    // Same loop-invalidation as [start] — the container nulls out
    // below, but bumping the generation makes the teardown airtight
    // even if a later start() re-populates it before a sleeping loop
    // re-checks.
    _generation++;
    _stopAll();
    _walletsListSub?.close();
    _walletsListSub = null;
    _scopeSub?.close();
    _scopeSub = null;
    _onchainPipeline.stop();
    _container = null;
  }

  /// Keep every non-active hardware / watch-only wallet warm: BDK
  /// session per walletId, reused across ticks so SQLite isn't
  /// reopened. Delegated to [OnchainPipeline.warmHardwareAndWatchOnly].
  Future<void> _warmHardwareAndWatchOnlyBalances() async {
    await _onchainPipeline.warmHardwareAndWatchOnly();
  }
}
