import 'package:kute/services/polymarket/combos/combo_feed.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'dart:async';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/helpers/orchestra_chain_for_network.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/helpers/predictions_deposit_wrap.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraOrder;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/api_response_cache_service.dart';
import 'package:kute/providers/usdb_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart'
    show Activity, PolymarketModel;
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:kute/providers/orchestra_provider.dart';
import 'package:kute/providers/settlement_reconciler_provider.dart'
    show settlementReconcilerProvider;
import 'package:kute/providers/outlogic_provider.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/orchestra/orchestra_history.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/providers/cash_app_payment_window_provider.dart'
    show cashAppClosedWindowScheduleProvider;

/// The Spark spending wallet: the first wallet that is not hardware,
/// watch-only, tracked or signer. Same predicate confirm_receive uses
/// when it creates accumulation rows, shared here so the sweep and the
/// purchase re-attribution agree on where Spark deliveries belong.
String? _spendingWalletId(List<WalletConfig> wallets) {
  for (final w in wallets) {
    if (w.isSparkWallet) {
      return w.id;
    }
  }
  return null;
}

abstract class SyncNotifier<T> extends AsyncNotifier<T> {
  Future<T> performSync();

  @protected
  Future<T> handleSync({
    required Future<T> Function() syncOperation,
    required void Function() onSuccess,
    required void Function() onFailure,
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        final result = await syncOperation();
        onSuccess();
        return result;
      } catch (e, stackTrace) {
        attempt++;
        if (attempt >= maxAttempts) {
          onFailure();
          state = AsyncError(e, stackTrace);
          rethrow;
        }
        await Future.delayed(Duration(seconds: 3 * (1 << (attempt - 1))));
      }
    }
    throw Exception('handleSync failed after $maxAttempts attempts');
  }
}

/// Resolve the wallet that the Spark SDK is bound to. Spark is a
/// per-spending-wallet session, so balance updates from
/// `sparkBitcoinBalanceProvider` always belong on that wallet's cache
/// slot regardless of which wallet the carousel is parked on. Returns
/// null if no spending-style wallet exists; sync writes guard on that
/// and skip.
String? _resolveSparkWalletId(Ref ref) {
  final settings = ref.read(settingsProvider);
  for (final w in settings.wallets) {
    if (w.isSparkWallet) {
      return w.id;
    }
  }
  // Track the rare case so we'd notice in telemetry. Previously this
  // path threw a string and was silently caught — invisible to ops.
  // Drop the active_id — sending the active wallet id as an event
  // param made every BigQuery row clusterable by wallet. The count
  // alone is what tells us whether this firing is "no wallets at
  // all" vs "wallets present but no spending pick", which is the
  // actionable signal.
  TrackingService.track('spark_wallet_id_unresolved', params: {
    'wallets': settings.wallets.length.toString(),
  });
  return null;
}

/// Pick the USD-equivalent leg of an Orchestra exchange so we can emit
/// it as the GA4 `purchase` event's `value`. Orchestra trades cross
/// asset+chain combos (BTC↔USDC/USDB variants). We treat the dollar
/// stablecoin leg as the USD value; for BTC↔BTC-rail moves (and
/// non-dollar fiat legs) we return 0 so the event is skipped.
/// The backend's provider_events row carries the same number on its
/// destination_amount field, so BigQuery joins are deterministic.
double _resolveUsdLegForOrchestra({
  required String coinFrom,
  required String coinTo,
  required String depositAmount,
  required String withdrawalAmount,
}) {
  // Dollar stablecoins including USDB (the Spark dollar balance). EUR,
  // GBP and CHF are not dollars and must not be summed as USD.
  if (isOrchestraUsdLikeCoin(coinFrom)) {
    return double.tryParse(depositAmount) ?? 0;
  }
  if (isOrchestraUsdLikeCoin(coinTo)) {
    return double.tryParse(withdrawalAmount) ?? 0;
  }
  return 0;
}

/// Real settlement of an Orchestra order into or out of Polygon USDC:
/// polymarket_deposit_completed / polymarket_withdraw_completed. Callers
/// have already claimed the order's terminal-success flag, so each order
/// reports once however many syncs overlap.
void _reportPolymarketOrderCompleted(
    SwapOrder exchange, String orderId, double usdLeg) {
  final amountUsd = usdLeg > 0 ? usdLeg : null;
  if (isPolymarketDepositOrder(exchange)) {
    final from = exchange.coinFrom.toUpperCase();
    TrackingService.polymarketDepositCompleted(
      orderId: orderId,
      amountUsd: amountUsd,
      route: from == 'BTC'
          ? 'btc_spending'
          : isOrchestraUsdLikeCoin(from)
              ? 'usd'
              : null,
    );
  } else if (isPolymarketWithdrawOrder(exchange)) {
    TrackingService.polymarketWithdrawCompleted(
      orderId: orderId,
      amountUsd: amountUsd,
    );
  }
}

class BackgroundSyncNotifier extends SyncNotifier<WalletBalance> {
  final _legacyExpiredQuoteChecks = LegacyExpiredQuoteSchedule();

  DateTime? _lastOrchestraPoll;
  static const _orchestraPollInterval = Duration(seconds: 5);

  DateTime? _lastAccumulationSweep;

  /// Slower than [_orchestraPollInterval] on purpose: accumulation
  /// addresses live FOREVER once cached, so this sweep never stops
  /// paying rent — one getHistory round-trip per cached address per
  /// interval. Discovery isn't latency-critical either: the receive
  /// screen's own 10 s poller covers the watching-the-screen case, and
  /// once a row is recorded the regular getStatus poller above takes
  /// over at full cadence.
  static const _accumulationSweepInterval = Duration(seconds: 30);

  bool _receiveQuoteSweepRunning = false;
  final Map<String, DateTime> _receiveQuoteChecks = {};

  /// Recent Spark BTC deposit addresses (latest first). `getSparkBitcoinAddressProvider`
  /// is invalidated on every `claimedDeposits` event, so each
  /// rotation appends a new address. Mempool-pending polling needs
  /// to query ALL addresses the user has actually shared — querying
  /// only the current one means a payer who used a previously-shared
  /// invoice after rotation is invisible to the pending poller.
  /// Capped at 5 to keep the per-tick mempool round-trip count bounded.
  /// Hive-backed: opened in `main.dart` under `spark_address_ring`.
  /// Entries keyed `pos_0` (latest) through `pos_4`. The in-memory
  /// list is the source of truth at runtime; Hive is the durable
  /// mirror so a cold start can rehydrate the ring before the first
  /// sync tick runs. Without persistence, an app restart between
  /// "user shared address A" and "A's tx hits 3 confs" loses A,
  /// and the pending poller silently stops watching it.
  static const String _sparkAddressRingBox = 'spark_address_ring';
  final List<String> _sparkAddressRing = <String>[];
  static const int _sparkAddressRingMax = 5;
  bool _sparkAddressRingHydrated = false;

  void _hydrateSparkAddressRingIfNeeded() {
    if (_sparkAddressRingHydrated) return;
    _sparkAddressRingHydrated = true;
    try {
      final box = Hive.box<String>(_sparkAddressRingBox);
      for (int i = 0; i < _sparkAddressRingMax; i++) {
        final v = box.get('pos_$i');
        if (v != null && v.isNotEmpty) {
          _sparkAddressRing.add(v);
        }
      }
    } catch (_) {}
  }

  void _persistSparkAddressRing() {
    try {
      final box = Hive.box<String>(_sparkAddressRingBox);
      for (int i = 0; i < _sparkAddressRingMax; i++) {
        if (i < _sparkAddressRing.length) {
          box.put('pos_$i', _sparkAddressRing[i]);
        } else {
          box.delete('pos_$i');
        }
      }
    } catch (_) {}
  }

  void _recordSparkAddress(String addr) {
    if (addr.isEmpty) return;
    _hydrateSparkAddressRingIfNeeded();
    if (_sparkAddressRing.isNotEmpty && _sparkAddressRing.first == addr) return;
    _sparkAddressRing.remove(addr);
    _sparkAddressRing.insert(0, addr);
    if (_sparkAddressRing.length > _sparkAddressRingMax) {
      _sparkAddressRing.removeRange(
          _sparkAddressRingMax, _sparkAddressRing.length);
    }
    _persistSparkAddressRing();
  }

  @override
  Future<WalletBalance> build() async => WalletBalance.empty();

  /// Run [tasks] with at most [concurrency] in flight, preserving
  /// result order (results[i] always belongs to tasks[i], exactly like
  /// Future.wait). Used to stagger the sync fetch fan-out: on 4GB
  /// devices, running every fetch simultaneously spikes main-isolate
  /// allocation (concurrent JSON decodes) high enough that the OS
  /// kills the app mid-refresh. Each task is expected to handle its
  /// own errors (all sync fetches return fallback values); a throw
  /// propagates just as it would from Future.wait.
  Future<List<dynamic>> _runStaggered(
    List<Future<dynamic> Function()> tasks, {
    int concurrency = 4,
  }) async {
    final results = List<dynamic>.filled(tasks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tasks.length) break;
        results[i] = await tasks[i]();
      }
    }

    final workerCount = concurrency < tasks.length ? concurrency : tasks.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }

  Future<void> _gatherAndUpdateTransactions({bool forceRefresh = false}) async {
    final settings = ref.read(settingsProvider);
    final walletIdAtStart = settings.activeWalletId;
    final activeWallet = settings.activeWallet;
    final isSpark = activeWallet?.sparkEnabled ?? false;
    final isExternalAddress = activeWallet?.isExternalAddress ?? false;

    // Every periodic tick refreshes the underlying tx-list providers
    // — `ref.read(provider.future)` would return the *cached* first
    // result forever, which is why incoming transactions only
    // appeared after a manual pull-to-refresh. `ref.refresh(...)`
    // re-runs the fetcher so we actually see new payments / deposits
    // / usdb activity on each sync tick. The `forceRefresh` arg used
    // to mean "run live" but at this point every caller wants live.
    Future<List<TxDetails>> getBitcoinTxs() async {
      if (isSpark || isExternalAddress) return <TxDetails>[];
      try {
        return await ref
            .refresh(getBitcoinTransactionsProvider.future)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        return <TxDetails>[];
      }
    }

    // Returns null on error/timeout so the caller can distinguish a
    // genuine empty wallet from a transient SDK-not-ready failure. The
    // distinction is load-bearing: writing an empty list as if it
    // were authoritative wipes every cached Spark row, and the user
    // sees balance with no transactions until the next stream event.
    Future<List<breez.Payment>?> getSparkHistoryPayments() async {
      if (!isSpark) return <breez.Payment>[];
      try {
        return await ref
            .refresh(listSparkBitcoinPaymentsProvider(
                    const breez.ListPaymentsRequest())
                .future)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        return null;
      }
    }

    // Returns null on error/timeout — mirrors `getSparkHistoryPayments`
    // above and for the same reason: an empty list from a timeout is
    // not "no unclaimed deposits", and treating it as authoritative
    // wiped the claim row on every slow tick (chronic on low-end
    // phones), leaving a confirmed deposit invisible and unclaimable.
    Future<List<breez.DepositInfo>?> getSparkUnclaimedDeposits() async {
      if (!isSpark) return <breez.DepositInfo>[];
      try {
        return await ref
            .refresh(listSparkUnclaimedDepositsProvider.future)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        return null;
      }
    }

    Future<List<breez.Payment>> getUsdbTokenPayments() async {
      if (!isSpark) return <breez.Payment>[];
      try {
        return await ref
            .refresh(listSparkBitcoinPaymentsProvider(
              breez.ListPaymentsRequest(
                assetFilter: breez.AssetFilter.token(
                    tokenIdentifier: usdbTokenIdentifier),
              ),
            ).future)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        return <breez.Payment>[];
      }
    }

    // Polymarket Data API indexes by proxy wallet address, not EOA.
    Future<String?> resolveProxyAddress() async {
      String? addr;
      if (walletIdAtStart != null) {
        addr =
            await secureStorage.read(key: 'pm_proxy_wallet_$walletIdAtStart');
      }
      if (addr == null || addr.isEmpty) {
        final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
        addr = tradingState?.proxyWalletAddress;
      }
      if (addr == null || addr.isEmpty) return null;
      return addr;
    }

    Future<List<PolymarketUsdcReceive>> getPolymarketUsdcReceives() async {
      // Inbound USDC.e/USDC-via-Polygonscan rows are disabled — that
      // path scrapes Polygonscan/Etherscan with an API key for every
      // sync tick (~10 s on the polling cadence), which is expensive,
      // rate-limited, and surfaces transfers the user can already see
      // via Spark deposit / on-chain BTC paths. Returning empty means
      // these rows simply don't render in the Activity feed.
      //
      // Re-enable by uncommenting the body below; the persistent
      // on-disk cache via `ApiResponseCacheService` is preserved.
      return <PolymarketUsdcReceive>[];
      // ignore: dead_code
      // final addr = await resolveProxyAddress();
      // if (addr == null) return <PolymarketUsdcReceive>[];
      // final cached = ApiResponseCacheService.readPolymarketUsdcReceives(addr);
      // try {
      //   final fresh = await PolygonscanSafeService.fetchInboundUsdc(addr)
      //       .timeout(const Duration(seconds: 12));
      //   if (fresh.isEmpty && cached.isNotEmpty) return cached;
      //   unawaited(
      //       ApiResponseCacheService.writePolymarketUsdcReceives(addr, fresh));
      //   return fresh;
      // } catch (_) {
      //   return cached;
      // }
    }

    Future<List<Activity>> getPolymarketVenueActivity(String addr) async {
      try {
        final model = PolymarketModel();
        final activity = await model
            .getUserActivity(addr)
            .timeout(const Duration(seconds: 10));
        model.dispose();
        // Persist the live API result before any optimistic-merge
        // step so the cache reflects what's confirmed on chain. The
        // optimistic entries are added on top at read time.
        unawaited(
            ApiResponseCacheService.writePolymarketActivity(addr, activity));
        // Merge optimistic local activities (just-sold/redeemed entries
        // the user wrote before the Data API caught up) so the home feed
        // reflects their latest action immediately. Auto-cleans on dedup
        // once the API confirms the same transactionHash.
        final apiHashes =
            activity.map((a) => a.transactionHash.toLowerCase()).toSet();
        final optimistic = PolymarketOptimisticActivityService.snapshot(
          confirmedHashes: apiHashes,
          confirmed: activity,
        );
        if (optimistic.isEmpty) return activity;
        final merged = [...optimistic, ...activity]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return merged;
      } catch (e) {
        // API failure — return the cached snapshot, optimistic-merged.
        final cached = ApiResponseCacheService.readPolymarketActivity(addr);
        if (cached.isEmpty) return cached;
        final cachedHashes =
            cached.map((a) => a.transactionHash.toLowerCase()).toSet();
        final optimistic = PolymarketOptimisticActivityService.snapshot(
          confirmedHashes: cachedHashes,
          confirmed: cached,
        );
        if (optimistic.isEmpty) return cached;
        return [...optimistic, ...cached]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    }

    Future<List<Activity>> getPolymarketActivity() async {
      final addr = await resolveProxyAddress();
      if (addr == null) return <Activity>[];
      final venue = await getPolymarketVenueActivity(addr);
      // Combos (parlays) have their own Data API feed; their exact rows
      // are kept locally per deposit wallet (combo_feed.dart).
      final combos = await ComboActivityFeed.rowsFor(addr);
      if (combos.isEmpty) return venue;
      return [...combos, ...venue]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    // In-mempool watcher for the Spark BTC receive address. The SDK's
    // `depositsStream` only emits once a deposit needs user action
    // (`unclaimedDeposits` / `claimError`), so an inbound tx with
    // 0/1/2 confirmations is invisible to the SDK push pipeline.
    // To surface "Receiving..." rows in the activity feed before
    // the deposit matures (3 confs), poll mempool.space for recent
    // txs landing on the Spark deposit address and materialise
    // `SparkPendingDeposit` rows for incoming, sub-3-conf txs.
    //
    // Dedup against the SDK-driven paths (unclaimed + spark mixed
    // payments) is handled downstream in `transactions_provider.dart`
    // where all sources are collated.
    Future<List<SparkPendingDeposit>> getSparkPendingDeposits() async {
      if (!isSpark) return <SparkPendingDeposit>[];
      try {
        // Hydrate from Hive once per process — covers the case
        // where the user shared addresses in a prior session,
        // killed the app, and reopened. Without this, the ring
        // starts empty and only the current address gets polled.
        _hydrateSparkAddressRingIfNeeded();
        // Record the current deposit address into the ring before
        // polling. Idempotent — if the address hasn't rotated since
        // last tick, the ring is unchanged.
        try {
          final currentAddr = await ref
              .read(getSparkBitcoinAddressProvider.future)
              .timeout(const Duration(seconds: 8));
          _recordSparkAddress(currentAddr);
        } catch (_) {}
        if (_sparkAddressRing.isEmpty) return <SparkPendingDeposit>[];

        // Poll mempool for every address the wallet has used recently.
        // A payer who saved a previously-shared address can broadcast
        // after the SDK has rotated, and the new address is meaningless
        // for finding their tx. Tip height fetched once and reused.
        final tipFuture = MempoolAddressService.fetchBlockTipHeight()
            .timeout(const Duration(seconds: 8));
        final addrFutures = _sparkAddressRing
            .map((a) => MempoolAddressService.fetchAddressTransactions(a)
                .timeout(const Duration(seconds: 10))
                .catchError((_) => <MempoolTransaction>[]))
            .toList();
        final tipHeight = await tipFuture;
        final perAddrTxs = await Future.wait(addrFutures);

        final seenTxids = <String>{};
        final pending = <SparkPendingDeposit>[];
        for (final txs in perAddrTxs) {
          for (final tx in txs) {
            // Only incoming credits to the deposit address. Outbound
            // (balanceChange <= 0) belongs to the withdraw path which
            // the SDK already covers via `sparkOnChainPayments`.
            if (tx.balanceChange <= 0) continue;
            // Dedup across addresses — a tx fetched twice (very rare
            // but possible if the same tx credited two addresses we
            // track) collapses to one pending row.
            if (!seenTxids.add(tx.txid)) continue;

            // Compute confirmation count. mempool.space marks
            // `confirmed == false` while in mempool; once mined,
            // `blockHeight` is set. Anything at 3+ confs is owned
            // by the SDK history list — drop it here to avoid
            // double-counting.
            final int confirmations;
            if (!tx.confirmed || tx.blockHeight == null) {
              confirmations = 0;
            } else {
              final c = tipHeight - tx.blockHeight! + 1;
              confirmations = c < 0 ? 0 : c;
            }
            if (confirmations >= 3) continue;

            final timestamp = tx.blockTime != null
                ? DateTime.fromMillisecondsSinceEpoch(tx.blockTime! * 1000)
                : DateTime.now();

            pending.add(SparkPendingDeposit(
              id: 'spark_pending_${tx.txid}',
              timestamp: timestamp,
              mempoolTx: tx,
              confirmations: confirmations,
            ));
          }
        }
        return pending;
      } catch (_) {
        // Network failure / SDK not ready — empty list keeps the
        // activity feed stable instead of flashing an error row.
        return <SparkPendingDeposit>[];
      }
    }

    // Staggered fan-out (was a plain N-way Future.wait). On 4GB
    // devices the simultaneous fetches — two full listPayments, the
    // mempool poll, Polymarket activity — all decode JSON on the main
    // isolate at once, spiking allocation right when the UI is also
    // repainting, and the OS kills the app mid-refresh. Capping the
    // in-flight count trades a little wall-clock for a bounded peak.
    // Results stay positional and each fetch keeps its own internal
    // error handling, so downstream unpacking is unchanged.
    final transactionFutures = await _runStaggered([
      getBitcoinTxs,
      getSparkHistoryPayments,
      getSparkUnclaimedDeposits,
      getUsdbTokenPayments,
      getPolymarketActivity,
      getSparkPendingDeposits,
      getPolymarketUsdcReceives,
    ]);

    // Yield to the scheduler before the post-fetch synchronous list
    // partitioning. The fetches above land on the same microtask
    // queue as the UI; without this break, the JSON-decoded payloads
    // and the subsequent .where().toList() partitions all run on the
    // next microtask in series, blocking frame rendering for the
    // duration. A zero-delay Future hands one frame back to the
    // scheduler so the UI thread can paint between the fetch wave
    // and the partition wave.
    await Future<void>.delayed(Duration.zero);

    // Scope Outlogic orders (persisted fiat-purchase history — the
    // ramp itself is gone) to the wallet captured at sync start.
    // Orders were tagged with `walletId` at create time — without this
    // filter every wallet's activity feed would surface every fiat
    // purchase the user ever made on the device. Legacy orders
    // persisted before the tag existed have `walletId == null` and
    // fall through to the active wallet so they don't disappear from
    // history.
    final allOutlogicOrders = ref.read(outlogicOrdersProvider);
    final outlogicOrders = walletIdAtStart == null
        ? allOutlogicOrders
        : allOutlogicOrders
            .where((o) => o.walletId == null || o.walletId == walletIdAtStart)
            .toList();

    // The unpack below is POSITIONAL against the _runStaggered list
    // above — the two must always change together, entry for entry.
    final bitcoinTx = transactionFutures[0] as List<TxDetails>;
    final sparkMixedPayments = transactionFutures[1] as List<breez.Payment>?;
    final unclaimedDepositsRaw =
        transactionFutures[2] as List<breez.DepositInfo>?;
    final usdbTokenPayments = transactionFutures[3] as List<breez.Payment>;
    final polymarketActivity = transactionFutures[4] as List<Activity>;
    final sparkPendingDeposits =
        transactionFutures[5] as List<SparkPendingDeposit>;
    final polymarketUsdcReceives =
        transactionFutures[6] as List<PolymarketUsdcReceive>;

    // Null payload === listPayments timed out or threw. Flag the
    // build so `updateTransactionsFor` preserves the existing cached
    // Spark rows instead of overwriting them with empty lists.
    final sparkPaymentsFetchFailed = sparkMixedPayments == null;
    final sparkPaymentsSafe = sparkMixedPayments ?? const <breez.Payment>[];

    // Same null-signal contract for unclaimed deposits — a timed-out
    // fetch must not masquerade as "no deposits" or the claim row
    // vanishes (see getSparkUnclaimedDeposits).
    final unclaimedDepositsFetchFailed = unclaimedDepositsRaw == null;
    final unclaimedDeposits =
        unclaimedDepositsRaw ?? const <breez.DepositInfo>[];

    final lightningPayments = sparkPaymentsSafe
        .where((p) => p.method == breez.PaymentMethod.lightning)
        .toList();

    final sparkOnChainPayments = sparkPaymentsSafe
        .where((p) =>
            p.method == breez.PaymentMethod.deposit ||
            p.method == breez.PaymentMethod.withdraw)
        .toList();

    final sparkInternalPayments = sparkPaymentsSafe
        .where((p) => p.method == breez.PaymentMethod.spark)
        .toList();

    // Yield again before the swap-order filter pass + cache write.
    // Without this the partition wave above runs back-to-back with
    // the cache write which itself triggers provider notifications,
    // and the UI gets no frame in between.
    await Future<void>.delayed(Duration.zero);

    final allSwapOrders = ref.read(swapOrdersProvider);
    final activeWalletId = settings.activeWalletId;
    final swapOrders = activeWalletId != null
        ? allSwapOrders.where((e) => e.walletId == activeWalletId).toList()
        : allSwapOrders;

    if (ref.read(settingsProvider).activeWalletId != walletIdAtStart) return;

    final rawData = RawTransactionData(
      bitcoinTxs: bitcoinTx,
      lightningPayments: lightningPayments,
      sparkOnChainPayments: sparkOnChainPayments,
      sparkInternalPayments: sparkInternalPayments,
      unclaimedDeposits: unclaimedDeposits,
      sparkPendingDeposits: sparkPendingDeposits,
      usdbTokenPayments: usdbTokenPayments,
      swapOrders: swapOrders,
      polymarketActivity: polymarketActivity,
      polymarketUsdcReceives: polymarketUsdcReceives,
      outlogicOrders: outlogicOrders,
      sparkPaymentsFetchFailed: sparkPaymentsFetchFailed,
      unclaimedDepositsFetchFailed: unclaimedDepositsFetchFailed,
    );

    ref.read(rawTransactionDataProvider.notifier).state = rawData;
    // Write the freshly-built tx snapshot directly into the cache
    // slot for the wallet captured at sync start. The active-wallet
    // notifier mirrors the cache automatically, so UI subscribers
    // pick the new value up via their existing watch.
    if (walletIdAtStart != null) {
      await ref
          .read(transactionNotifierProvider.notifier)
          .updateTransactionsFor(walletIdAtStart, rawData);
    }
    // Status-update fan-out for swap orders that belong to
    // OTHER wallets (savings / hardware). The per-wallet cache slot
    // for those wallets only gets a one-shot optimistic write at
    // create time — the subsequent status polls (wait → success)
    // update the global Hive store but never reach the per-wallet
    // cache, so the wallet detail screen shows the row frozen at
    // "Pending" forever. Re-merge every exchange not owned by the
    // active wallet into its owning wallet's cache so wallet-detail
    // activity feeds reflect the latest status. Idempotent: the
    // merge dedupes by exchange id.
    for (final ex in allSwapOrders) {
      final wid = ex.walletId;
      if (wid == null) continue;
      if (wid == activeWalletId) continue;
      ref.read(walletTransactionCacheProvider.notifier).mergeSwapOrder(ex);
    }

    // After every sync pass the Orchestra status pollers
    // (lines ~810 + ~827) may have flipped some exchanges to terminal
    // status. Mirror those terminal transitions to the backend's
    // provider_events table by calling logProviderEvent({status:
    // 'completed' | 'failed', ...}) — that's what triggers
    // provider_log.go's earnings calc and PostHog's revenue_recorded
    // event. The order-create sites in confirm_send/receive/move_sheet
    // already wrote pending rows; this is the missing settlement
    // mirror.
    _reportTerminalExchangesToBackend(allSwapOrders);
  }

  /// Process-lifetime cache of (provider, providerOrderId) keys already
  /// reported to the backend with terminal status. Backend UPSERT +
  /// PostHog `$insert_id` dedup make re-reports safe, but the cache
  /// avoids needless network chatter on every sync. Cleared on app
  /// restart (safe — first sync re-reports + dedup catches it).
  final Set<String> _terminalsReported = {};

  void _reportTerminalExchangesToBackend(List<SwapOrder> exchanges) {
    for (final ex in exchanges) {
      // Synthetic accumulation placeholders never exist backend-side —
      // the sweep-discovered real order carries the attribution.
      if (ex.id.startsWith('acu-')) continue;
      final providerKey = _exchangeProviderKey(ex.providerName);
      if (providerKey == null) continue;
      final statusKey = _exchangeStatusKey(ex.status);
      if (statusKey == null) continue; // not terminal yet
      final key = '$providerKey:${ex.id}';
      if (!_terminalsReported.add(key)) {
        continue; // already reported this session
      }
      // ignore: unawaited_futures
      AffiliateService.logProviderEvent(
        provider: providerKey,
        providerOrderId: ex.id,
        status: statusKey,
        sourceAsset: ex.coinFrom,
        sourceAmount: double.tryParse(ex.depositAmount) ?? 0,
        destinationAsset: ex.coinTo,
        destinationAmount: double.tryParse(ex.withdrawalAmount) ?? 0,
      );
    }
  }

  String? _exchangeProviderKey(String? providerName) {
    switch (providerName) {
      case 'Orchestra':
        return 'orchestra';
      default:
        return null;
    }
  }

  /// Maps the local exchange status to the provider_events status
  /// vocabulary that `provider_log.go::isCompletedStatus` understands.
  /// Returns null for non-terminal statuses (pending / exchanging /
  /// confirmation / sending) — those don't need a server upsert beyond
  /// the initial 'pending' row written at order create.
  String? _exchangeStatusKey(String status) {
    switch (status) {
      case 'settled':
      case 'success':
      case 'completed':
        return 'completed';
      case 'refund':
      case 'refunded':
      case 'expired':
      case 'failed':
      case 'overdue':
        return 'failed';
      default:
        return null;
    }
  }

  /// Lightweight transaction load (DB-only, no network sync).
  /// Used by PDF export to collect transactions for non-active wallets.
  Future<void> gatherTransactionsOnly() async {
    await _gatherAndUpdateTransactions(forceRefresh: false);
  }

  /// Writes, updates or retires the Activity row of one standing deposit
  /// that never became an order (see standing_deposit_activity.dart).
  /// Once the deposit has an order and that order's row exists, the
  /// stuck row goes: the order row and its refund take over.
  Future<void> _syncStuckStandingDeposit({
    required Map<String, dynamic> deposit,
    required StandingDepositRecord record,
    required String walletId,
    required String recipient,
  }) async {
    final rowId = stuckStandingDepositRowId(deposit);
    if (rowId == null) return;
    final rows = ref.read(swapOrdersProvider);
    final existing = rows.where((r) => r.id == rowId).firstOrNull;
    final row = stuckStandingDepositRow(
        deposit: deposit,
        record: record,
        walletId: walletId,
        recipient: recipient,
        existing: existing);
    if (row == null) {
      final orderId = deposit['orderId'];
      if (existing != null &&
          standingDepositHasOrder(deposit) &&
          rows.any((r) => r.id == orderId)) {
        await ref.read(swapOrdersProvider.notifier).deleteExchange(rowId);
        ref.read(walletTransactionCacheProvider.notifier).removeSwapOrder(rowId);
      }
      return;
    }
    if (existing != null &&
        existing.status == row.status &&
        existing.depositAmount == row.depositAmount) {
      return;
    }
    await ref.read(swapOrdersProvider.notifier).updateExchange(row);
    ref.read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row);
  }

  DateTime? _lastStandingSweep;
  DateTime? _lastStandingRestore;
  static const _standingRestoreInterval = Duration(minutes: 30);
  bool _standingSweepRunning = false;
  Future<void> _sweepStandingDeposits() async {
    if (_standingSweepRunning ||
        (_lastStandingSweep != null &&
            DateTime.now().difference(_lastStandingSweep!) <
                const Duration(minutes: 1))) {
      return;
    }
    _standingSweepRunning = true;
    _lastStandingSweep = DateTime.now();
    try {
      final walletId = _spendingWalletId(ref.read(settingsProvider).wallets);
      if (walletId == null) return;
      final scope = StandingDepositStore.capture(walletId);
      bool current() =>
          StandingDepositStore.current(scope) &&
          _spendingWalletId(ref.read(settingsProvider).wallets) == walletId;
      final recipient = await ref.read(sparkSelfAddressProvider.future);
      if (!current()) return;
      // Addresses another install of this wallet registered come back
      // from the backend's recovery list, so money sent to them stays
      // visible (and returnable) here. A failed read keeps the local
      // records as they are.
      final lastRestore = _lastStandingRestore;
      if (lastRestore == null ||
          DateTime.now().difference(lastRestore) >= _standingRestoreInterval) {
        _lastStandingRestore = DateTime.now();
        try {
          await StandingDepositStore.restore(
              walletId: walletId, recipient: recipient, wanted: current);
        } catch (_) {}
      }
      final records = await StandingDepositStore.records(walletId);
      if (records.isEmpty || !current()) return;
      for (final saved in records) {
        if (!current()) return;
        // Order discovery matches today's recipient. A stuck deposit is
        // returned to its payer, so every reference this wallet holds is
        // swept for those, whichever recipient it names.
        final ownRecipient = sameSparkAddress(recipient, saved.recipient);
        try {
          var record = saved;
          if (record.response['addresses'] is! Map) {
            final state = await OrchestraService.standingRequest(
                operation: 'read', label: record.label, current: current);
            if (state['standingAddressId'] == null || state['enabled'] is! bool) {
              continue;
            }
            record = record.copy(response: {...record.response, ...state});
            await StandingDepositStore.saveResponse(
                record, record.response, scope);
          }
          final deposits = await StandingDepositStore.deposits(record, current);
          for (final deposit in deposits) {
            // A deposit that never became an order gets its own row in
            // that asset's Activity, with the refund in its details.
            await _syncStuckStandingDeposit(
                deposit: deposit,
                record: record,
                walletId: walletId,
                recipient: record.recipient);
            if (!current()) return;
            if (!ownRecipient) continue;
            final id = deposit['orderId'];
            if (id is! String ||
                !id.startsWith('ord_') ||
                ref.read(swapOrdersProvider).any((r) => r.id == id)) {
              continue;
            }
            final chain = deposit['chain'] as String?;
            final asset = deposit['asset'] as String?;
            if (chain == null || asset == null) continue;
            final address = record.addressFor(chain);
            if (address == null) continue;
            final order = (await OrchestraService.getStatus(id)).data;
            if (!current()) return;
            if (order == null ||
                order.id != id ||
                !orchestraHistoryMatchesDeposit(order,
                    sourceChain: chain,
                    sourceAsset: asset,
                    destinationAsset: record.asset,
                    depositAddress: address,
                    recipientSparkAddress: recipient)) {
              continue;
            }
            final row = SwapOrder(
                id: id,
                activityDirection: 'receive',
                coinFrom: asset,
                networkFrom: chain,
                coinTo: record.asset,
                networkTo: 'SPARK',
                depositAddress: address,
                depositAmount: orchestraAmountToDecimalString(
                    order.amountIn ?? '0', asset, chain: chain),
                withdrawalAmount: orchestraAmountToDecimalString(
                    order.amountOut ?? '0', record.asset, chain: 'spark'),
                status: orchestraExchangeStatus(order.status),
                timestamp: DateTime.tryParse(order.createdAt)
                        ?.millisecondsSinceEpoch ??
                    DateTime.now().millisecondsSinceEpoch,
                withdrawalAddress: recipient,
                depositMin: '0',
                depositMax: '0',
                rate: '0',
                refundAddress: '',
                provider: 'Orchestra',
                walletId: walletId,
                purchaseSource: 'crypto_receive');
            if (!current()) return;
            await ref.read(swapOrdersProvider.notifier).addExchange(row);
            if (!current()) return;
            ref
                .read(walletTransactionCacheProvider.notifier)
                .mergeSwapOrder(row);
            reportDiscoveredOrchestraOrder(row);
          }
        } catch (_) {
          /* Every reference remains available for the next sweep. */
        }
      }
    } catch (_) {
      /* Locked/offline wallets retain their deposit references. */
    } finally {
      _standingSweepRunning = false;
    }
  }

  /// A quote is watched until its real order takes over, even after expiry.
  Future<void> _sweepOrchestraReceiveQuotes() async {
    if (_receiveQuoteSweepRunning) return;
    _receiveQuoteSweepRunning = true;
    try {
      final walletId = _spendingWalletId(ref.read(settingsProvider).wallets);
      if (walletId == null) return;
      final scope = PendingReceiveQuoteCache.capture(walletId);
      final pending = (await PendingReceiveQuoteCache.pending())
          .where((quote) => quote.walletId == walletId)
          .toList();
      if (pending.isEmpty) return;
      final recipient = await ref.read(sparkSelfAddressProvider.future);
      bool current() =>
          PendingReceiveQuoteCache.isCurrent(scope) &&
          _spendingWalletId(ref.read(settingsProvider).wallets) == walletId;
      if (!current()) return;
      final now = DateTime.now();
      pending.sort((a, b) =>
          (_receiveQuoteChecks[a.id]?.millisecondsSinceEpoch ?? 0).compareTo(
              _receiveQuoteChecks[b.id]?.millisecondsSinceEpoch ?? 0));
      List<OrchestraOrder>? history;
      var historyRead = false;
      var reads = 0;
      for (final quote in pending) {
        if (!current()) return;
        if (!sameSparkAddress(recipient, quote.withdrawalAddress)) continue;
        final age = now
            .difference(DateTime.fromMillisecondsSinceEpoch(quote.expiresAt!));
        final interval = age > const Duration(days: 7)
            ? const Duration(hours: 6)
            : age > const Duration(days: 1)
                ? const Duration(hours: 1)
                : age > const Duration(hours: 1)
                    ? const Duration(minutes: 5)
                    : const Duration(seconds: 30);
        final checked = _receiveQuoteChecks[quote.id];
        if (checked != null && now.difference(checked) < interval) continue;
        if (reads++ >= 4) break;
        _receiveQuoteChecks[quote.id] = now;
        try {
          final result = await OrchestraService.getStatus(quote.id);
          if (!current()) return;
          var order = result.data;
          if (order == null ||
              !_receiveQuoteMatchesOrder(quote, order, fromQuoteStatus: true)) {
            if (!historyRead) {
              historyRead = true;
              history = (await OrchestraService.getHistory(recipient)).data;
              if (!current()) return;
            }
            order = null;
            for (final candidate in history ?? <OrchestraOrder>[]) {
              if (_receiveQuoteMatchesOrder(quote, candidate)) {
                order = candidate;
                break;
              }
            }
          }
          if (order == null) continue;
          final exchangeBox =
              await Hive.openBox<SwapOrder>(kSwapOrdersBoxName);
          if (!current()) return;
          final existing = exchangeBox.get(order.id);
          if (existing != null && existing.walletId != walletId) continue;
          if (existing == null) {
            final exchange = quote.copyWith(
              id: order.id,
              status: orchestraExchangeStatus(order.status),
              depositAmount: order.amountIn == null
                  ? quote.depositAmount
                  : orchestraAmountToDecimalString(
                      order.amountIn!, quote.coinFrom,
                      chain: quote.networkFrom),
              withdrawalAmount: order.amountOut == null
                  ? '0'
                  : orchestraAmountToDecimalString(
                      order.amountOut!, quote.coinTo,
                      chain: 'spark'),
              timestamp:
                  DateTime.tryParse(order.createdAt)?.millisecondsSinceEpoch ??
                      quote.timestamp,
              purchaseSource: 'crypto_receive',
            );
            await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
            await exchangeBox.flush();
            if (!current()) return;
            ref
                .read(walletTransactionCacheProvider.notifier)
                .mergeSwapOrder(exchange);
            reportDiscoveredOrchestraOrder(exchange);
          } else {
            await exchangeBox.flush();
          }
          await PendingReceiveQuoteCache.complete(quote.id);
          _receiveQuoteChecks.remove(quote.id);
        } catch (_) {
          // Keep the instructions on disk for the next reconciliation pass.
        }
      }
    } catch (_) {
      // A locked wallet, failed lookup or storage error cannot retire a quote.
    } finally {
      _receiveQuoteSweepRunning = false;
    }
  }

  bool _receiveQuoteMatchesOrder(SwapOrder quote, OrchestraOrder order,
      {bool fromQuoteStatus = false}) {
    if (order.orderMissing ||
        !order.id.startsWith('ord_') ||
        order.status.trim().isEmpty ||
        (order.quoteId != null && order.quoteId != quote.id)) {
      return false;
    }
    if (!fromQuoteStatus) {
      // A shared source address can serve several quotes. History must name
      // this quote as well as match its full route and recipient.
      return order.quoteId == quote.id &&
          orchestraHistoryMatchesDeposit(order,
              sourceChain: quote.networkFrom,
              sourceAsset: quote.coinFrom,
              destinationAsset: quote.coinTo,
              depositAddress: quote.depositAddress,
              recipientSparkAddress: quote.withdrawalAddress);
    }
    // /status?quoteId=... is the authoritative link even when it omits
    // addresses. Every echoed instruction must still match the saved quote.
    bool label(String? actual, String expected) =>
        actual == null || actual.toLowerCase() == expected.toLowerCase();
    final deposit = order.depositAddress;
    return label(order.sourceChain, quote.networkFrom) &&
        label(order.sourceAsset, quote.coinFrom) &&
        label(order.destinationChain, quote.networkTo) &&
        label(order.destinationAsset, quote.coinTo) &&
        (order.recipientAddress == null ||
            sameSparkAddress(
                order.recipientAddress!, quote.withdrawalAddress)) &&
        (deposit == null ||
            (kEvmAddressChains.contains(quote.networkFrom.toLowerCase())
                ? sameEvmAddress(deposit, quote.depositAddress)
                : deposit == quote.depositAddress));
  }

  /// Off-screen deposit discovery for Orchestra accumulation addresses.
  /// The receive screen's history poller (confirm_receive.dart) only
  /// lives while that screen is open, but the addresses it hands out
  /// are REUSABLE — the UI explicitly says "send any amount" — so
  /// deposits routinely land after the screen closes. Flashnet still
  /// delivers the BTC to Spark either way, but without this sweep no
  /// exchange row is ever recorded and the order's affiliate/revenue
  /// attribution is permanently lost. Sweeps every cached address via
  /// getHistory on the sync tick (same stamp+interval backoff shape as
  /// the other pollers here — no extra timer) and records any order id
  /// the exchange store doesn't know yet. First-insert attribution
  /// lives in [reportDiscoveredOrchestraOrder], shared with the screen
  /// poller so whichever path discovers an order first reports exactly
  /// once. Never throws — both performSync branches call it bare.
  Future<void> _sweepOrchestraAccumulationAddresses() async {
    try {
      final now = DateTime.now();
      if (_lastAccumulationSweep != null &&
          now.difference(_lastAccumulationSweep!) <
              _accumulationSweepInterval) {
        return;
      }
      // No cached addresses → no requests. This is the common case for
      // most users, so the sweep stays free until the first Orchestra
      // receive address is ever created on this device.
      final addresses = AccumulationAddressCache.getAll();
      if (addresses.isEmpty) return;
      _lastAccumulationSweep = now;
      // Accumulation deliveries always land on the Spark spending
      // wallet — confirm_receive only creates them for it (see
      // `_isPickedWalletSparkSpending`) — so tag discovered rows with
      // that wallet id, not whatever wallet happens to be active when
      // the sweep runs. Same spending-wallet predicate as the creator.
      final spendingWalletId =
          _spendingWalletId(ref.read(settingsProvider).wallets);
      final historyByRecipient = <String, List<OrchestraOrder>?>{};
      for (final addr in addresses) {
        final depositAddress = addr.depositAddress;
        if (depositAddress == null || depositAddress.isEmpty) continue;
        try {
          final recipient = addr.recipientSparkAddress;
          if (!historyByRecipient.containsKey(recipient)) {
            historyByRecipient[recipient] =
                (await OrchestraService.getHistory(recipient)).data;
          }
          if (_spendingWalletId(ref.read(settingsProvider).wallets) !=
              spendingWalletId) {
            return;
          }
          final orders = historyByRecipient[recipient];
          if (orders == null) continue;
          // Re-read per address: earlier iterations of this loop (or
          // the receive screen's poller, if it's open right now) may
          // have just inserted rows for this sweep's ids.
          final known = ref.read(swapOrdersProvider).map((e) => e.id).toSet();
          for (final order in orders) {
            if (order.id.isEmpty || known.contains(order.id)) continue;
            if (!orchestraHistoryMatchesDeposit(order,
                sourceChain: addr.sourceChain,
                sourceAsset: addr.sourceAsset,
                destinationAsset: addr.destinationAsset,
                depositAddress: depositAddress,
                recipientSparkAddress: recipient)) {
              continue;
            }
            // Shared vocabulary with confirm_receive's discovery loop
            // (orchestra_routes.dart) so rows read identically no
            // matter which path recorded them. Terminal-at-discovery
            // orders are recorded WITH their terminal status so the
            // getStatus pollers above never treat them as pending.
            final mappedStatus = orchestraExchangeStatus(order.status);
            // Flashnet amounts are smallest-unit (micro-stable in,
            // sats out) — same conversion the getStatus pollers use.
            // The cache's sourceAsset is Flashnet's code ('USDC.e'),
            // which the exact formatter resolves case-insensitively.
            final depAmt = order.amountIn != null
                ? orchestraAmountToDecimalString(
                    order.amountIn!, addr.sourceAsset,
                    chain: addr.sourceChain)
                : '0';
            final wdAmt = order.amountOut != null
                ? orchestraAmountToDecimalString(
                    order.amountOut!, addr.destinationAsset,
                    chain: 'spark')
                : '0';
            final createdMs =
                DateTime.tryParse(order.createdAt)?.millisecondsSinceEpoch ??
                    now.millisecondsSinceEpoch;
            final exchange = SwapOrder(
              id: order.id,
              activityDirection: 'receive',
              coinFrom: addr.sourceAsset.toUpperCase(),
              // Orchestra chain slug, uppercased into the display form
              // the rest of the exchange rows use ('TRON', 'BASE', …).
              networkFrom: addr.sourceChain.toUpperCase(),
              coinTo: addr.destinationAsset.toUpperCase(),
              networkTo: 'SPARK',
              depositAddress: depositAddress,
              depositAmount: depAmt,
              withdrawalAmount: wdAmt,
              status: mappedStatus,
              timestamp: createdMs,
              withdrawalAddress: addr.recipientSparkAddress,
              depositMin: '0',
              depositMax: '0',
              rate: '0',
              refundAddress: '',
              provider: 'Orchestra',
              walletId: spendingWalletId,
            );
            await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
            // Surface in the Activity feed without waiting for the
            // next full gather pass — same propagation the q_→ord_
            // swap above does.
            ref
                .read(walletTransactionCacheProvider.notifier)
                .mergeSwapOrder(exchange);
            // First-insert attribution (pending row, or the completed/
            // failed fan-out for terminal-at-discovery orders). Runs
            // exactly once per order: subsequent sweeps skip the id
            // via the `known` guard above.
            reportDiscoveredOrchestraOrder(exchange);
            // Retire the synthetic acu- placeholder this order fulfils
            // (the HL withdraw writes one per withdrawal for instant
            // feedback — no real id exists until the USDC lands). At
            // most one per discovered order, closest timestamp first,
            // regardless of whether the reconciler already settled it:
            // the real row above tells the same story with real data.
            SwapOrder? placeholder;
            int? bestGapMs;
            for (final e in ref.read(swapOrdersProvider)) {
              if (!e.id.startsWith('acu-')) continue;
              if (e.depositAddress != depositAddress) continue;
              final gap = (createdMs - e.timestamp).abs();
              if (gap > 6 * 60 * 60 * 1000) continue;
              if (bestGapMs == null || gap < bestGapMs) {
                bestGapMs = gap;
                placeholder = e;
              }
            }
            if (placeholder != null) {
              await ref
                  .read(swapOrdersProvider.notifier)
                  .deleteExchange(placeholder.id);
              // Purge the Activity cache too — same propagation the
              // q_→ord_ swap does; without it the stale pending row
              // survives on screen until the next full gather.
              ref
                  .read(walletTransactionCacheProvider.notifier)
                  .removeSwapOrder(placeholder.id);
            }
          }
        } catch (_) {
          // One address failing (network blip, 5xx) shouldn't starve
          // the rest — and the next sweep retries everything anyway.
        }
      }
    } catch (_) {}
  }

  /// Fund-attribution safety net for Cash App purchase rows.
  ///
  /// Builds before 483e986a delivered every purchase to the Spark
  /// spending address while the pending row could be attributed to a
  /// cold wallet (walletId = hardware / watch-only / tracked wallet,
  /// withdrawalAddress = that wallet's on-chain address). The status
  /// payload carries the order's real recipient, so once it arrives:
  ///   * recipient is a Spark address (sp1… / spark1…) or the
  ///     destination chain is spark, and the row sits on a cold wallet
  ///     → move the row to the spending wallet (networkTo SPARK,
  ///     withdrawalAddress = real recipient), keeping the purchase
  ///     marker, and track the correction categorically;
  ///   * recipient is an on-chain bitcoin address → the cold wallet
  ///     attribution is right, leave it;
  ///   * payload exposes no recipient at all → nothing to correct on.
  /// Returns [row] unchanged whenever no correction applies.
  SwapOrder _reattributePurchaseRow(SwapOrder row, OrchestraOrder order) {
    if (!row.isCashAppPurchase) return row;
    final recipient = (order.recipientAddress ?? '').trim();
    final destChain = (order.destinationChain ?? '').trim().toLowerCase();
    if (recipient.isEmpty && destChain.isEmpty) return row;
    final lower = recipient.toLowerCase();
    final landsOnSpark = destChain == 'spark' ||
        lower.startsWith('sp1') ||
        lower.startsWith('spark1');
    if (!landsOnSpark) return row;
    final wallets = ref.read(settingsProvider).wallets;
    WalletConfig? rowWallet;
    for (final w in wallets) {
      if (w.id == row.walletId) {
        rowWallet = w;
        break;
      }
    }
    if (rowWallet == null) return row;
    final isCold = rowWallet.isHardware ||
        rowWallet.isWatchOnly ||
        rowWallet.isExternalAddress;
    if (!isCold) return row;
    final spendingId = _spendingWalletId(wallets);
    if (spendingId == null || spendingId == row.walletId) return row;
    TrackingService.track('purchase_row_reattributed', params: {
      'from': 'cold',
      'to': 'spending',
    });
    return row.copyWith(
      walletId: spendingId,
      networkTo: 'SPARK',
      withdrawalAddress: recipient.isNotEmpty ? recipient : null,
      // The marker was implicit (shape fallback) on old rows; pin it
      // so the moved row stays a purchase on every surface.
      purchaseSource: 'cashapp',
    );
  }

  /// Status polling survives closing the Cash App payment screen. Once the
  /// provider delivers USDC.e, finish the same deposit wrap used by the
  /// foreground flow. A different active account is never touched.
  Future<void> _finishCashAppVenueDeposit(SwapOrder row) async {
    if (!row.isComplete ||
        cashAppDestination(row) != CashAppDestination.predictions ||
        row.walletId != ref.read(settingsProvider).activeWalletId) {
      return;
    }
    try {
      final predictions = await ref.read(polymarketTradingProvider.future);
      if (!cashAppNeedsPredictionsWrap(
        row,
        activeWalletId: ref.read(settingsProvider).activeWalletId,
        predictionsAddress: predictions.proxyWalletAddress,
        orders: ref.read(swapOrdersProvider),
      )) {
        return;
      }
      final notifier = ref.read(polymarketTradingProvider.notifier);
      notifier.invalidateBalanceCache();
      notifier.wrapIncomingUsdcEToPusd();
    } catch (_) {
      // Delivery remains recorded. The trading flow can wrap USDC.e on
      // demand if this best-effort refresh cannot initialize the account.
    }
  }

  /// Every other source's deposit into Predictions (Bitcoin, Dollars) the
  /// same way: once Orchestra reports the order complete, the USDC.e it
  /// delivered is converted to pUSD from here, so it happens even when the
  /// Move sheet was closed long before. Same account and withdrawal guards
  /// as the Cash App path.
  Future<void> _finishPredictionsDeposit(SwapOrder row) async {
    final activeWalletId = ref.read(settingsProvider).activeWalletId;
    if (!row.isComplete ||
        !isPredictionsDepositOrder(row) ||
        row.walletId != activeWalletId) {
      return;
    }
    try {
      final predictions = await ref.read(polymarketTradingProvider.future);
      if (!predictionsDepositNeedsWrap(
        row,
        activeWalletId: ref.read(settingsProvider).activeWalletId,
        predictionsAddress: predictions.proxyWalletAddress,
        orders: ref.read(swapOrdersProvider),
      )) {
        return;
      }
      final notifier = ref.read(polymarketTradingProvider.notifier);
      notifier.invalidateBalanceCache();
      notifier.wrapIncomingUsdcEToPusd();
    } catch (_) {
      // Delivery remains recorded. The order path converts USDC.e itself
      // when pUSD alone is short.
    }
  }

  /// Settle synthetic acu- placeholder rows (written by the HL
  /// withdraw) against the Spark receives that fulfil them, and hide
  /// the raw receive from the home feed. The placeholder has no
  /// queryable order id, so status polling can never finish it — the
  /// delivery itself is the completion signal. Match is deliberately
  /// STRONG (both conditions, unlike the retired time-only claim
  /// heuristic): the receive landed between 2 min before and 90 min
  /// after the exchange was created, AND its sats are within
  /// [0.5×, 1.25×] of the exchange's estimated out (rate drift plus
  /// Orchestra fees stay well inside that band). Never throws — both
  /// performSync branches call it bare.
  /// Settlement operations (Phase 5 plan B8): one reconcile pass per sync
  /// tick. Never throws; nothing in it moves funds.
  Future<void> _reconcileSettlementOperations() async {
    try {
      await ref.read(settlementReconcilerProvider).runOnce();
    } catch (_) {}
  }

  Future<void> _reconcileSyntheticOrchestraRows() async {
    try {
      // Not just acu- placeholders: real ord_/q_ Orchestra rows bound
      // for Spark (Predictions withdraw, claim deliveries) also sit
      // pending for minutes after the BTC has visibly landed, because
      // getStatus lags actual delivery. The receive itself is the
      // authoritative completion signal for all of them; the status
      // poller still reconciles amounts later if it disagrees.
      final synthetic = ref
          .read(swapOrdersProvider)
          .where((e) =>
              (e.id.startsWith('acu-') ||
                  e.id.startsWith('ord_') ||
                  e.id.startsWith('q_')) &&
              e.providerName == 'Orchestra' &&
              !e.isCashAppPurchase &&
              e.networkTo == 'SPARK' &&
              e.isPending)
          .toList();
      final alreadyHidden =
          PolymarketSparkTxsService.orchestraDeliverySnapshot();
      final cacheSnapshots =
          ref.read(walletTransactionCacheProvider).values.toList();
      // Candidate receives across every cached wallet snapshot —
      // deliveries land on the Spark spending wallet, but reading all
      // slots keeps this correct if that mapping ever widens.
      final receives = <SparkTransaction>[];
      final seenRxIds = <String>{};
      for (final snapshot in cacheSnapshots) {
        for (final tx
            in snapshot.allTransactionsSorted.whereType<SparkTransaction>()) {
          if (tx.type != TransactionType.received) continue;
          if (tx.isPending) continue;
          if (alreadyHidden.contains(tx.id)) continue;
          if (!seenRxIds.add(tx.id)) continue;
          receives.add(tx);
        }
      }
      for (final ex in synthetic) {
        if (receives.isEmpty) break;
        final estSats =
            ((double.tryParse(ex.withdrawalAmount) ?? 0) * 1e8).round();
        SparkTransaction? best;
        int? bestDeltaMs;
        for (final rx in receives) {
          final delta = rx.timestamp.millisecondsSinceEpoch - ex.timestamp;
          if (delta < -2 * 60 * 1000 || delta > 90 * 60 * 1000) continue;
          if (estSats > 0) {
            final sats = rx.amountSats;
            if (sats <= 0) continue;
            final ratio = sats / estSats;
            if (ratio < 0.5 || ratio > 1.25) continue;
          }
          if (bestDeltaMs == null || delta.abs() < bestDeltaMs) {
            bestDeltaMs = delta.abs();
            best = rx;
          }
        }
        if (best == null) continue;
        // One receive settles one exchange.
        receives.remove(best);
        final actualBtc = (best.amountSats / 1e8).toStringAsFixed(8);
        final settled = ex.copyWith(
          status: 'settled',
          withdrawalAmount: actualBtc,
        );
        await ref.read(swapOrdersProvider.notifier).updateExchange(settled);
        PolymarketSparkTxsService.tagOrchestraDelivery(best.id);
        // Surface the settled row without waiting for the next full
        // gather pass — same propagation the sweep's inserts use.
        ref
            .read(walletTransactionCacheProvider.notifier)
            .mergeSwapOrder(settled);
      }

      // Deposit twin: Orchestra rows settling USDC on POLYGON (the
      // Predictions deposit) match against the Safe's confirmed USDC
      // receive events the same way — getStatus lags actual delivery
      // there too (user report: rows sat PENDING until a manual
      // refresh). Consumed receive ids share the delivery tag box for
      // persistence; the home feed's hide only applies to
      // SparkTransaction ids, so tagging these is inert on-screen.
      final polygonPending = ref
          .read(swapOrdersProvider)
          .where((e) =>
              e.providerName == 'Orchestra' &&
              e.networkTo == 'POLYGON' &&
              e.coinTo == 'USDC' &&
              e.isPending)
          .toList();
      if (polygonPending.isEmpty) return;
      final usdcRx = <PolymarketUsdcReceive>[];
      final seenUsdcIds = <String>{};
      for (final snapshot in cacheSnapshots) {
        for (final rx in snapshot.polymarketUsdcReceives) {
          if (!rx.isConfirmed) continue;
          if (alreadyHidden.contains(rx.id)) continue;
          if (!seenUsdcIds.add(rx.id)) continue;
          usdcRx.add(rx);
        }
      }
      for (final ex in polygonPending) {
        if (usdcRx.isEmpty) break;
        final estUsd = double.tryParse(ex.withdrawalAmount) ?? 0;
        PolymarketUsdcReceive? best;
        int? bestDeltaMs;
        for (final rx in usdcRx) {
          final delta = rx.timestamp.millisecondsSinceEpoch - ex.timestamp;
          if (delta < -2 * 60 * 1000 || delta > 90 * 60 * 1000) continue;
          if (estUsd > 0) {
            final usd = rx.amount.toDouble();
            if (usd <= 0) continue;
            final ratio = usd / estUsd;
            if (ratio < 0.5 || ratio > 1.25) continue;
          }
          if (bestDeltaMs == null || delta.abs() < bestDeltaMs) {
            bestDeltaMs = delta.abs();
            best = rx;
          }
        }
        if (best == null) continue;
        usdcRx.remove(best);
        final settled = ex.copyWith(
          status: 'settled',
          withdrawalAmount: best.amount.toStringAsFixed(2),
        );
        await ref.read(swapOrdersProvider.notifier).updateExchange(settled);
        PolymarketSparkTxsService.tagOrchestraDelivery(best.id);
        ref
            .read(walletTransactionCacheProvider.notifier)
            .mergeSwapOrder(settled);
      }
    } catch (_) {}
  }

  @override
  Future<WalletBalance> performSync() async {
    bool anySyncFailed = false;

    return await handleSync(
      syncOperation: () async {
        // Use current in-memory balance (not stale Hive cache) to avoid flash of old values
        final previousBalance = ref.read(balanceNotifierProvider);
        final settings = ref.read(settingsProvider);
        final walletIdAtSyncStart = settings.activeWalletId;
        final activeWallet = settings.activeWallet;
        final isSpark = activeWallet?.sparkEnabled ?? false;
        final isExternalAddress = activeWallet?.isExternalAddress ?? false;

        if (isExternalAddress) {
          final address =
              await AuthModel().getExternalAddress(activeWallet!.id);
          if (address != null && address.isNotEmpty) {
            final results = await Future.wait([
              MempoolAddressService.fetchAddressData(address),
              MempoolAddressService.fetchAddressTransactions(address),
            ]);

            final addressData = results[0] as MempoolAddressData;
            final txList = results[1] as List<MempoolTransaction>;

            // Persist the tx list keyed by walletId — so on cold start
            // the external-address wallet can render its tx list from
            // disk before the live mempool.space round-trip completes.
            if (walletIdAtSyncStart != null) {
              unawaited(ApiResponseCacheService.writeMempoolTransactions(
                  walletIdAtSyncStart, txList));
            }

            // No early-return on active-wallet swap — the cache write
            // is keyed by walletIdAtSyncStart so it lands in the right
            // slot even if the user already moved on.
            if (walletIdAtSyncStart != null) {
              ref
                  .read(walletBalanceCacheProvider.notifier)
                  .updateOnChainBtcBalance(
                      walletIdAtSyncStart, addressData.balanceSats);
            }

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

            final allSwapOrders = ref.read(swapOrdersProvider);
            final swapOrders = walletIdAtSyncStart != null
                ? allSwapOrders
                    .where((e) => e.walletId == walletIdAtSyncStart)
                    .toList()
                : allSwapOrders;

            // Give the delivery reconciler first shot at synthetic
            // acu- rows so a placeholder that already has its Spark
            // receive settles instead of hitting the 24h expiry below
            // (matters for rows created before an app update lands).
            await _reconcileSyntheticOrchestraRows();
            await _reconcileSettlementOperations();

            // Orchestra polling for pending orders
            final orchestraCheckedAt = DateTime.now();
            final orchestraPending = swapOrders
                .where((e) =>
                    legacyOrchestraRowNeedsStatusCheck(e, orchestraCheckedAt))
                .toList();

            for (final exchange in orchestraPending) {
              final eid = exchange.id;
              // Old liq_/acu_ composite IDs can't be queried — expire them
              if (eid.startsWith('liq_') || eid.startsWith('acu_')) {
                // Old liquidation/accumulation IDs can never be queried — expire them
                await ref
                    .read(swapOrdersProvider.notifier)
                    .updateExchange(exchange.copyWith(status: 'expired'));
                continue;
              }
              // Synthetic accumulation placeholders (acu-…, written by
              // the HL withdraw for instant feedback) have no queryable
              // order id. The delivery reconciler settles them when the
              // matching Spark receive lands, and the accumulation
              // sweep retires them once the real order shows up — only
              // age them out after a day so a missed match can't pin a
              // pending row forever.
              if (eid.startsWith('acu-')) {
                final age =
                    DateTime.now().millisecondsSinceEpoch - exchange.timestamp;
                if (age > 24 * 60 * 60 * 1000) {
                  await ref
                      .read(swapOrdersProvider.notifier)
                      .updateExchange(exchange.copyWith(status: 'expired'));
                }
                continue;
              }
              // Unpaid Cash App orders whose payment window closed reconcile
              // on a slower schedule; every other order is always due.
              final cashAppChecks =
                  ref.read(cashAppClosedWindowScheduleProvider);
              if (!cashAppChecks.begin(exchange)) continue;
              if (!_legacyExpiredQuoteChecks.begin(exchange)) continue;
              try {
                final result = await OrchestraService.getStatus(eid);
                if (result.isSuccess && result.data != null) {
                  cashAppChecks.recordSuccess(eid);
                }
                final read = classifyOrchestraStatusRead(result);
                _legacyExpiredQuoteChecks.recordRead(eid, read);
                // A failed read never expires a quote row. Only a successful
                // not-found read past the quote's grace does, and the row
                // keeps a daily check for a late detected deposit.
                final readAction = legacyStatusReadAction(
                  row: exchange,
                  read: read,
                  now: DateTime.now(),
                );
                if (readAction == LegacyStatusReadAction.markExpired) {
                  await ref
                      .read(swapOrdersProvider.notifier)
                      .updateExchange(exchange.copyWith(status: 'expired'));
                  continue;
                }
                if (readAction != LegacyStatusReadAction.apply &&
                    eid.startsWith('q_') &&
                    !exchange.isCashAppPurchase) {
                  continue;
                }
                if (result.isSuccess && result.data != null) {
                  final order = result.data!;
                  final mappedStatus = exchange.isCashAppPurchase
                      ? cashAppExchangeStatus(order.status,
                          paymentReceived: order.paymentReceived == true)
                      : orchestraExchangeStatus(order.status);
                  // Convert Flashnet smallest-unit amounts to human-readable decimals
                  final depAmt = order.amountIn != null
                      ? orchestraRowAmountToDecimalString(
                          order.amountIn!, exchange.coinFrom,
                          network: exchange.networkFrom,
                          orderChain: order.sourceChain)
                      : exchange.depositAmount;
                  final wdAmt = order.amountOut != null
                      ? orchestraRowAmountToDecimalString(
                          order.amountOut!, exchange.coinTo,
                          network: exchange.networkTo,
                          orderChain: order.destinationChain)
                      : exchange.withdrawalAmount;
                  var updated = exchange.copyWith(
                    status: mappedStatus,
                    expiresAt: DateTime.tryParse(order.expiresAt ?? '')
                        ?.millisecondsSinceEpoch,
                    depositAmount: depAmt,
                    withdrawalAmount: wdAmt,
                  );
                  // Fund-attribution safety net: a purchase row pinned
                  // to a cold wallet whose order actually delivers to
                  // Spark moves to the spending wallet (see helper).
                  final reattributed = _reattributePurchaseRow(updated, order);
                  final movedWallet = reattributed.walletId != updated.walletId;
                  updated = reattributed;
                  // Swap the local q_ placeholder for Orchestra's real order
                  // id once it returns one. Don't require an `ord_` prefix:
                  // Flashnet's id format/field isn't guaranteed, and a change
                  // there is exactly what strands rows on the quote id. Any
                  // non-empty id that isn't the quote itself is the real one.
                  final replacementId = legacyReplacementOrderId(eid, order);
                  if (replacementId != null) {
                    // The new row keeps every field the quote row carried
                    // (purchase marker, fiat paid, provider token,
                    // expiry) so a Cash App purchase does not degrade
                    // to a plain swap once it gets its real order id.
                    // It is written before the quote row is deleted, so a
                    // kill between the two writes leaves a polled row.
                    updated = legacyRowWithOrderId(updated, replacementId);
                    await replaceOrchestraRowId(
                      oldId: eid,
                      replacement: updated,
                      add: ref.read(swapOrdersProvider.notifier).addExchange,
                      delete:
                          ref.read(swapOrdersProvider.notifier).deleteExchange,
                    );
                    // Register the REAL order (ord_) as pending now that we know
                    // its id — the creation site couldn't (submitDeposit hadn't
                    // returned ord_ yet, so it skipped to avoid logging q_). Skip
                    // when already terminal; the completion handler below records
                    // those. Idempotent upsert on (provider, provider_order_id).
                    if (!exchange.isCashAppPurchase &&
                        mappedStatus != 'success' &&
                        mappedStatus != 'refunded' &&
                        mappedStatus != 'expired' &&
                        mappedStatus != 'overdue') {
                      // ignore: unawaited_futures
                      AffiliateService.logProviderEvent(
                        provider: 'orchestra',
                        providerOrderId: order.id,
                        status: 'pending',
                        sourceAsset: exchange.coinFrom,
                        sourceAmount: double.tryParse(depAmt),
                        destinationAsset: exchange.coinTo,
                        destinationAmount: double.tryParse(wdAmt),
                      );
                    }
                    // Propagate to the Activity cache (what the UI renders):
                    // drop the stale q_ row and surface the real ord_ one, so
                    // the active wallet's feed doesn't stay frozen on the quote.
                    ref
                        .read(walletTransactionCacheProvider.notifier)
                        .removeSwapOrder(eid);
                    ref
                        .read(walletTransactionCacheProvider.notifier)
                        .mergeSwapOrder(updated);
                  } else {
                    await ref
                        .read(swapOrdersProvider.notifier)
                        .updateExchange(updated);
                    // A re-attributed row must leave the cold wallet's
                    // cache slot, not just appear on the spending one.
                    if (movedWallet) {
                      ref
                          .read(walletTransactionCacheProvider.notifier)
                          .removeSwapOrder(updated.id);
                    }
                    // Keep the Activity cache in sync with the new status.
                    ref
                        .read(walletTransactionCacheProvider.notifier)
                        .mergeSwapOrder(updated);
                  }
                  // Fire analytics on terminal-status transitions —
                  // creation-site fired the wrong amounts because the
                  // exchange was still pending at that point. The
                  // sentinel-only fan-out below guards against double-
                  // counting: we look at the prior status on the
                  // in-memory `exchange` snapshot vs the new mappedStatus.
                  final wasTerminal = !legacyExpiredQuoteNewOutcome(
                          exchange, mappedStatus, orchestraCheckedAt) &&
                      (exchange.status == 'success' ||
                          exchange.status == 'refunded' ||
                          exchange.status == 'expired');
                  if (updated.isCashAppPurchase) {
                    if (!wasTerminal &&
                        orchestraExchangeStatusIsTerminal(mappedStatus)) {
                      reportDiscoveredOrchestraOrder(updated);
                      unawaited(_finishCashAppVenueDeposit(updated));
                    }
                    // Unpaid order whose window closed: once per order.
                    reportCashAppPaymentWindowEnded(updated);
                    continue;
                  }
                  if (!wasTerminal && mappedStatus == 'success') {
                    unawaited(_finishPredictionsDeposit(updated));
                  }
                  if (!wasTerminal &&
                      mappedStatus == 'success' &&
                      claimOrderTerminalAnalytics(order.id, success: true)) {
                    // GA4 revenue — value is the USD-equivalent of
                    // whichever leg is fiat. For BTC↔USDC swaps the
                    // USDC leg is already USD-equivalent; for BTC sells
                    // we use the USD-leg directly.
                    final usdLeg = _resolveUsdLegForOrchestra(
                      coinFrom: exchange.coinFrom,
                      coinTo: exchange.coinTo,
                      depositAmount: depAmt,
                      withdrawalAmount: wdAmt,
                    );
                    TrackingService.swapCompleted(
                      fromCoin: exchange.coinFrom,
                      toCoin: exchange.coinTo,
                      provider: 'orchestra',
                      fromAmount: double.tryParse(depAmt),
                      toAmount: double.tryParse(wdAmt),
                      amountUsd: usdLeg > 0 ? usdLeg : null,
                      amountOutUsd: isOrchestraUsdLikeCoin(exchange.coinTo)
                          ? double.tryParse(wdAmt)
                          : null,
                      fromNetwork: exchange.networkFrom,
                      toNetwork: exchange.networkTo,
                      venue: orchestraOrderVenue(exchange),
                      providerOrderId: order.id,
                    );
                    if (usdLeg > 0) {
                      TrackingService.revenueEventCompleted(
                        transactionId: order.id,
                        provider: 'orchestra',
                        valueUsd: usdLeg,
                        sourceAsset: exchange.coinFrom,
                        destinationAsset: exchange.coinTo,
                      );
                    }
                    // The real Predictions funding outcome. The Move sheet
                    // only reports *_submitted at hand-off, so this is the
                    // single completion for every Orchestra order into or
                    // out of Polygon USDC (route-detected; guarded by the
                    // terminal claim above).
                    _reportPolymarketOrderCompleted(
                        exchange, order.id, usdLeg);
                  } else if (!wasTerminal &&
                      (mappedStatus == 'expired' ||
                          mappedStatus == 'refunded') &&
                      claimOrderTerminalAnalytics(order.id, success: false)) {
                    final usdLegFail = _resolveUsdLegForOrchestra(
                      coinFrom: exchange.coinFrom,
                      coinTo: exchange.coinTo,
                      depositAmount: depAmt,
                      withdrawalAmount: wdAmt,
                    );
                    TrackingService.swapFailed(
                      fromCoin: exchange.coinFrom,
                      toCoin: exchange.coinTo,
                      provider: 'orchestra',
                      reason: mappedStatus,
                      fromAmount: double.tryParse(depAmt),
                      amountUsd: usdLegFail > 0 ? usdLegFail : null,
                      fromNetwork: exchange.networkFrom,
                      toNetwork: exchange.networkTo,
                      venue: orchestraOrderVenue(exchange),
                      providerOrderId: order.id,
                    );
                    final isPmDeposit = isPolymarketDepositOrder(exchange);
                    final isPmWithdraw = isPolymarketWithdrawOrder(exchange);
                    if (isPmDeposit || isPmWithdraw) {
                      if (isPmDeposit) {
                        TrackingService.polymarketDepositFailed(
                          amountUsd: usdLegFail,
                          provider: 'orchestra',
                          reason: mappedStatus,
                        );
                      } else {
                        TrackingService.polymarketWithdrawFailed(
                          amountUsd: usdLegFail,
                          provider: 'orchestra',
                          reason: mappedStatus,
                        );
                      }
                    }
                  }
                }
              } catch (_) {}
            }

            // Same accumulation-address discovery sweep the main
            // (non-external-address) path runs — deliveries land on
            // the Spark spending wallet regardless of which wallet is
            // active, so an external-address session must keep
            // watching too. Self-throttled; no-op when nothing is
            // cached.
            await _sweepOrchestraAccumulationAddresses();
            await _sweepOrchestraReceiveQuotes();
            await _sweepStandingDeposits();
            await _reconcileSyntheticOrchestraRows();

            final rawData = RawTransactionData(
              bitcoinTxs: <TxDetails>[],
              lightningPayments: <breez.Payment>[],
              sparkOnChainPayments: <breez.Payment>[],
              sparkInternalPayments: <breez.Payment>[],
              unclaimedDeposits: <breez.DepositInfo>[],
              mempoolTxs: mempoolTxModels,
              swapOrders: swapOrders,
              // Same per-wallet scoping the main sync path uses —
              // orders tagged with another wallet's id stay hidden.
              outlogicOrders: walletIdAtSyncStart == null
                  ? ref.read(outlogicOrdersProvider)
                  : ref
                      .read(outlogicOrdersProvider)
                      .where((o) =>
                          o.walletId == null ||
                          o.walletId == walletIdAtSyncStart)
                      .toList(),
            );
            ref.read(rawTransactionDataProvider.notifier).state = rawData;
            // walletId-keyed write — see _gatherAndUpdateTransactions
            // for the same pattern. The active notifier mirrors.
            if (walletIdAtSyncStart != null) {
              await ref
                  .read(transactionNotifierProvider.notifier)
                  .updateTransactionsFor(walletIdAtSyncStart, rawData);
            }
          }
          ref.read(onlineProvider.notifier).state = true;

          final latestBalance = ref.read(balanceNotifierProvider);
          return latestBalance;
        }

        final syncResults = await Future.wait([
          Future(() async {
            try {
              await _gatherAndUpdateTransactions(forceRefresh: false);
            } catch (_) {}
            return true;
          }),
          Future(() async {
            // BDK Electrum sync is intentionally NOT run on the home /
            // app-foreground / background-loop full update. The
            // synchronous Electrum FFI — the eager `ElectrumClient(...)`
            // built when `bitcoinProvider` resolves PLUS `sync_` /
            // `fullScan` — blocks the main isolate on DNS/TCP connect,
            // which was the top production ANR
            // (`uniffi_bdkffi_fn_constructor_electrumclient_new`, "slow
            // operations in main thread", concentrated on the few users
            // parked on a non-Spark wallet). On-chain / savings /
            // hardware wallets now sync ONLY from the wallet-detail
            // screen via `BackgroundSyncService.scanBdkScope()` (screen
            // entry, pull-to-refresh, and just before Send/Move). Home
            // shows the balance the last detail-screen scan cached;
            // nothing on this path touches Electrum. (`isSpark` wallets
            // never synced BDK here anyway.)
            return true;
          }),
          Future(() async {
            try {
              await ref.read(getFiatPurchasesProvider.future);
              return true;
            } catch (e) {
              return true;
            }
          }),
          Future(() async {
            if (!isSpark) return true;
            try {
              final balance =
                  await ref.refresh(sparkBitcoinBalanceProvider.future);
              final sNotifier = ref.read(walletBalanceCacheProvider.notifier);
              // Resolve the spending wallet now (Spark SDK is bound
              // to that wallet regardless of which wallet the
              // carousel is parked on).
              final sparkWalletId = _resolveSparkWalletId(ref);
              if (sparkWalletId != null) {
                try {
                  sNotifier.updateSparkBitcoinbalance(
                      sparkWalletId, balance.toInt());
                } catch (_) {}
              }
              return true;
            } catch (e) {
              return false;
            }
          }),
          Future(() async {
            try {
              final allExchanges = ref.read(swapOrdersProvider);

              // Orchestra polling — for quote-based orders + Polymarket
              // orders. Reads ALL exchanges, not the wallet-filtered
              // list: status polling is wallet-agnostic, and filtering
              // permanently skipped rows with a null/other walletId
              // while they still rendered pending on wallet feeds.
              final orchestraCheckedAt2 = DateTime.now();
              final orchestraPending2 = allExchanges
                  .where((e) => legacyOrchestraRowNeedsStatusCheck(
                      e, orchestraCheckedAt2))
                  .toList();
              for (final ex in orchestraPending2) {
                final eid = ex.id;
                if (eid.startsWith('liq_') || eid.startsWith('acu_')) {
                  final age =
                      DateTime.now().millisecondsSinceEpoch - ex.timestamp;
                  if (age > 30 * 60 * 1000) {
                    await ref
                        .read(swapOrdersProvider.notifier)
                        .updateExchange(ex.copyWith(status: 'expired'));
                  }
                  continue;
                }
                // Same slower schedule for closed unpaid Cash App orders.
                final cashAppChecks =
                    ref.read(cashAppClosedWindowScheduleProvider);
                if (!cashAppChecks.begin(ex)) continue;
                if (!_legacyExpiredQuoteChecks.begin(ex)) continue;
                try {
                  final result = await OrchestraService.getStatus(eid);
                  if (result.isSuccess && result.data != null) {
                    cashAppChecks.recordSuccess(eid);
                  }
                  final read2 = classifyOrchestraStatusRead(result);
                  _legacyExpiredQuoteChecks.recordRead(eid, read2);
                  final readAction2 = legacyStatusReadAction(
                    row: ex,
                    read: read2,
                    now: DateTime.now(),
                  );
                  if (readAction2 == LegacyStatusReadAction.markExpired) {
                    await ref
                        .read(swapOrdersProvider.notifier)
                        .updateExchange(ex.copyWith(status: 'expired'));
                    continue;
                  }
                  if (readAction2 != LegacyStatusReadAction.apply &&
                      eid.startsWith('q_') &&
                      !ex.isCashAppPurchase) {
                    continue;
                  }
                  if (result.isSuccess && result.data != null) {
                    final order = result.data!;
                    final mappedStatus = ex.isCashAppPurchase
                        ? cashAppExchangeStatus(order.status,
                            paymentReceived: order.paymentReceived == true)
                        : orchestraExchangeStatus(order.status);
                    final depAmt = order.amountIn != null
                        ? orchestraRowAmountToDecimalString(
                            order.amountIn!, ex.coinFrom,
                            network: ex.networkFrom,
                            orderChain: order.sourceChain)
                        : ex.depositAmount;
                    final wdAmt = order.amountOut != null
                        ? orchestraRowAmountToDecimalString(
                            order.amountOut!, ex.coinTo,
                            network: ex.networkTo,
                            orderChain: order.destinationChain)
                        : ex.withdrawalAmount;
                    var updated = ex.copyWith(
                      status: mappedStatus,
                      expiresAt: DateTime.tryParse(order.expiresAt ?? '')
                          ?.millisecondsSinceEpoch,
                      depositAmount: depAmt,
                      withdrawalAmount: wdAmt,
                    );
                    // Same fund-attribution safety net as the primary
                    // block.
                    final reattributed2 =
                        _reattributePurchaseRow(updated, order);
                    final movedWallet2 =
                        reattributed2.walletId != updated.walletId;
                    updated = reattributed2;
                    // See the matching block above: swap on any real, non-quote
                    // order id, not just an `ord_`-prefixed one.
                    final replacementId = legacyReplacementOrderId(eid, order);
                    if (replacementId != null) {
                      // Same as the primary block: the purchase marker and
                      // fiat paid survive the id swap, and the new row is
                      // written before the quote row is deleted.
                      updated = legacyRowWithOrderId(updated, replacementId);
                      await replaceOrchestraRowId(
                        oldId: eid,
                        replacement: updated,
                        add: ref.read(swapOrdersProvider.notifier).addExchange,
                        delete: ref
                            .read(swapOrdersProvider.notifier)
                            .deleteExchange,
                      );
                      // Propagate to the Activity cache (what the UI renders):
                      // drop the stale q_ row and surface the real ord_ one, so
                      // the active wallet's feed doesn't stay frozen on the quote.
                      ref
                          .read(walletTransactionCacheProvider.notifier)
                          .removeSwapOrder(eid);
                      ref
                          .read(walletTransactionCacheProvider.notifier)
                          .mergeSwapOrder(updated);
                    } else {
                      await ref
                          .read(swapOrdersProvider.notifier)
                          .updateExchange(updated);
                      if (movedWallet2) {
                        ref
                            .read(walletTransactionCacheProvider.notifier)
                            .removeSwapOrder(updated.id);
                      }
                      // Keep the Activity cache in sync with the new status.
                      ref
                          .read(walletTransactionCacheProvider.notifier)
                          .mergeSwapOrder(updated);
                    }
                    // Terminal-status analytics — same fan-out as the
                    // primary Orchestra polling block above.
                    final wasTerminal2 = !legacyExpiredQuoteNewOutcome(
                            ex, mappedStatus, orchestraCheckedAt2) &&
                        (ex.status == 'success' ||
                            ex.status == 'refunded' ||
                            ex.status == 'expired');
                    if (updated.isCashAppPurchase) {
                      if (!wasTerminal2 &&
                          orchestraExchangeStatusIsTerminal(mappedStatus)) {
                        reportDiscoveredOrchestraOrder(updated);
                        unawaited(_finishCashAppVenueDeposit(updated));
                      }
                      // Unpaid order whose window closed: once per order.
                      reportCashAppPaymentWindowEnded(updated);
                      continue;
                    }
                    if (!wasTerminal2 && mappedStatus == 'success') {
                      unawaited(_finishPredictionsDeposit(updated));
                    }
                    if (!wasTerminal2 &&
                        mappedStatus == 'success' &&
                        claimOrderTerminalAnalytics(order.id, success: true)) {
                      final usdLeg2 = _resolveUsdLegForOrchestra(
                        coinFrom: ex.coinFrom,
                        coinTo: ex.coinTo,
                        depositAmount: depAmt,
                        withdrawalAmount: wdAmt,
                      );
                      TrackingService.swapCompleted(
                        fromCoin: ex.coinFrom,
                        toCoin: ex.coinTo,
                        provider: 'orchestra',
                        fromAmount: double.tryParse(depAmt),
                        toAmount: double.tryParse(wdAmt),
                        amountUsd: usdLeg2 > 0 ? usdLeg2 : null,
                        amountOutUsd: isOrchestraUsdLikeCoin(ex.coinTo)
                            ? double.tryParse(wdAmt)
                            : null,
                        fromNetwork: ex.networkFrom,
                        toNetwork: ex.networkTo,
                        venue: orchestraOrderVenue(ex),
                        providerOrderId: order.id,
                      );
                      if (usdLeg2 > 0) {
                        TrackingService.revenueEventCompleted(
                          transactionId: order.id,
                          provider: 'orchestra',
                          valueUsd: usdLeg2,
                          sourceAsset: ex.coinFrom,
                          destinationAsset: ex.coinTo,
                        );
                      }
                      // Same real Predictions completion as the primary
                      // block.
                      _reportPolymarketOrderCompleted(ex, order.id, usdLeg2);
                    } else if (!wasTerminal2 &&
                        (mappedStatus == 'expired' ||
                            mappedStatus == 'refunded') &&
                        claimOrderTerminalAnalytics(order.id,
                            success: false)) {
                      final usdLegFail2 = _resolveUsdLegForOrchestra(
                        coinFrom: ex.coinFrom,
                        coinTo: ex.coinTo,
                        depositAmount: depAmt,
                        withdrawalAmount: wdAmt,
                      );
                      TrackingService.swapFailed(
                        fromCoin: ex.coinFrom,
                        toCoin: ex.coinTo,
                        provider: 'orchestra',
                        reason: mappedStatus,
                        fromAmount: double.tryParse(depAmt),
                        amountUsd: usdLegFail2 > 0 ? usdLegFail2 : null,
                        fromNetwork: ex.networkFrom,
                        toNetwork: ex.networkTo,
                        venue: orchestraOrderVenue(ex),
                        providerOrderId: order.id,
                      );
                      // Polymarket-specific funnel break-out. The
                      // Orchestra exchange is shape-keyed: USDC ↔
                      // POLYGON on one leg signals it's a Polymarket
                      // deposit (BTC → USDC) or withdrawal (USDC →
                      // BTC). Generic swap_failed already fired
                      // above; this row gives the Polymarket revenue
                      // dashboard a top-of-funnel drop-off signal it
                      // can join against `polymarket_deposit_completed`
                      // for true conversion rate.
                      final isPmDeposit =
                          ex.networkTo.toUpperCase() == 'POLYGON' &&
                              ex.coinTo.toUpperCase().startsWith('USDC');
                      final isPmWithdraw =
                          ex.networkFrom.toUpperCase() == 'POLYGON' &&
                              ex.coinFrom.toUpperCase().startsWith('USDC');
                      if (isPmDeposit || isPmWithdraw) {
                        final usdLegFail = _resolveUsdLegForOrchestra(
                          coinFrom: ex.coinFrom,
                          coinTo: ex.coinTo,
                          depositAmount: depAmt,
                          withdrawalAmount: wdAmt,
                        );
                        if (isPmDeposit) {
                          TrackingService.polymarketDepositFailed(
                            amountUsd: usdLegFail,
                            provider: 'orchestra',
                            reason: mappedStatus,
                          );
                        } else {
                          TrackingService.polymarketWithdrawFailed(
                            amountUsd: usdLegFail,
                            provider: 'orchestra',
                            reason: mappedStatus,
                          );
                        }
                      }
                    }
                  }
                } catch (_) {}
              }

              // Discovery sweep for reusable accumulation addresses —
              // deposits that arrived while the receive screen was
              // closed have no exchange row yet, so the id-based
              // poller above can't see them. Self-throttled; no-op
              // when nothing is cached.
              await _sweepOrchestraAccumulationAddresses();
              await _sweepOrchestraReceiveQuotes();
              await _sweepStandingDeposits();
              await _reconcileSyntheticOrchestraRows();
              await _reconcileSettlementOperations();

              return true;
            } catch (e) {
              return true;
            }
          }),
          Future(() async {
            final now = DateTime.now();
            if (_lastOrchestraPoll != null &&
                now.difference(_lastOrchestraPoll!) < _orchestraPollInterval) {
              return true;
            }
            try {
              final notifier = ref.read(orchestraOrdersProvider.notifier);
              final pending = notifier.pendingOrders;
              if (pending.isEmpty) return true;
              _lastOrchestraPoll = now;
              for (final order in pending) {
                final result = await OrchestraService.getStatus(order.id);
                if (result.isSuccess && result.data != null) {
                  notifier.updateOrder(result.data!);
                }
              }
              return true;
            } catch (e) {
              return true;
            }
          }),
        ]);

        final btcSuccess = syncResults[1];
        final sparkSuccess = syncResults[3];
        anySyncFailed = isSpark ? !sparkSuccess : !btcSuccess;

        if (ref.read(settingsProvider).activeWalletId != walletIdAtSyncStart) {
          return ref.read(balanceNotifierProvider);
        }

        await _gatherAndUpdateTransactions(forceRefresh: true);

        final latestBalance = ref.read(balanceNotifierProvider);
        _compareBalances(previousBalance, latestBalance);

        if (isSpark) await ref.read(setupLnAddressProvider.future);

        return latestBalance;
      },
      onSuccess: () {
        if (anySyncFailed) {
          ref.read(onlineProvider.notifier).state = false;
        } else {
          ref.read(onlineProvider.notifier).state = true;
        }
      },
      onFailure: () {
        ref.read(onlineProvider.notifier).state = false;
        setBackgroundSyncInProgress(false);
      },
    );
  }

  Future<String?> getExternalAddressString() async {
    final settings = ref.read(settingsProvider);
    final activeWallet = settings.activeWallet;
    if (activeWallet == null || !activeWallet.isExternalAddress) return null;
    return await AuthModel().getExternalAddress(activeWallet.id);
  }

  /// Whether the current `performSync` run was kicked off by the
  /// user (pull-to-refresh, post-payment refresh, settings retry,
  /// [force] is retained for caller compatibility (settings, post-
  /// payment refreshes, the 2 s background loop's `force: false`), but
  /// no longer gates a BDK Electrum sync here — on-chain wallets sync
  /// only from the wallet-detail screen now (see `scanBdkScope`).
  Future<void> performFullUpdate({bool force = true}) async {
    if (ref.read(backgroundSyncInProgressProvider)) return;
    try {
      setBackgroundSyncInProgress(true);
      await performSync();
    } catch (e) {
      // ignore
    } finally {
      setBackgroundSyncInProgress(false);
    }
    try {
      await ref.read(updateCurrencyProvider.future);
    } catch (e) {
      // ignore
    }
    try {
      final pmNotifier = ref.read(polymarketTradingProvider.notifier);
      await pmNotifier.refresh();
    } catch (_) {}
  }

  void setBackgroundSyncInProgress(bool inProgress) {
    ref.read(backgroundSyncInProgressProvider.notifier).state = inProgress;
  }

  void _compareBalances(WalletBalance previous, WalletBalance current) {
    final assets = [
      {
        'name': 'Bitcoin',
        'previous': previous.onChainBtcBalance,
        'current': current.onChainBtcBalance
      },
      {
        'name': 'Lightning',
        'previous': previous.sparkBitcoinbalance,
        'current': current.sparkBitcoinbalance
      },
    ];
    for (var asset in assets) {
      _checkAndNotify(
        assetName: asset['name'] as String,
        previousAmount: asset['previous'] as int,
        currentAmount: asset['current'] as int,
      );
    }
  }

  void _checkAndNotify(
      {required String assetName,
      required int previousAmount,
      required int currentAmount}) {
    if (previousAmount < currentAmount) {
      final Map<String, String> assetTickerMap = {
        'Spark': 'Lightning',
        'Bitcoin': 'Bitcoin',
        'Lightning': 'Lightning'
      };
      final balanceChange = BalanceChange(
          asset: assetTickerMap[assetName] ?? assetName,
          amount: currentAmount - previousAmount);
      ref.read(balanceChangeProvider.notifier).state = balanceChange;
    }
  }
}

final backgroundSyncNotifierProvider =
    AsyncNotifierProvider<BackgroundSyncNotifier, WalletBalance>(
        BackgroundSyncNotifier.new);
final backgroundSyncInProgressProvider = StateProvider<bool>((ref) => false);

/// Wallet ids whose scoped BDK scan is currently in flight, written by
/// `BackgroundSyncService.scanBdkScope`.
///
/// Switching the shell's first tab to a wallet kicks that wallet's scan
/// immediately, so a cold wallet can sit for a few seconds with nothing in
/// its balance cache. Surfaces read this to say "loading" instead of
/// rendering a confident zero, and nothing else may start a second scan
/// while an id is in here — native BDK holds one slot per wallet.
final bdkScanningWalletsProvider =
    StateProvider<Set<String>>((ref) => const <String>{});
