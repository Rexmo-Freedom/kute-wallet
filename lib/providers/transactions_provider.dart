// lib/providers/transactions_provider.dart
//
// Per-wallet transaction state. Mirrors the balance pipeline: the
// `walletTransactionCacheProvider` is the source of truth, keyed by
// walletId. The active-wallet `transactionNotifierProvider` is a
// read-side facade that mirrors the active wallet's slot — it stays
// for backwards compatibility with the many UI callsites that
// `ref.watch(transactionNotifierProvider)`.
//
// Why this shape: previously the notifier was rebuilt every time
// `activeWalletId` changed, and sync writes targeted "the current
// notifier". A mid-sync wallet swap would write wallet A's tx list
// into wallet B's notifier — same race we already fixed for the
// balance side. With cache-as-truth + walletId-keyed writes, the
// race is structurally impossible.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/outlogic_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/polymarket_model.dart' show Activity, ActivityType;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/milestone_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/settings_model.dart' show Settings;
import 'package:kute/services/milestone_service.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:kute/services/polymarket/combos/combo_feed.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/haptic_gates.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/tx_fiat_snapshot_service.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:money2/money2.dart';
import 'package:kute/services/transaction_cache_codec.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/onchain_types.dart' as bdk;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RawTransactionData {
  final List<bdk.TxDetails> bitcoinTxs; // From BDK (Standard On-Chain)

  // Categorized according to SparkTransactionType enum
  final List<breez.Payment> lightningPayments; // SparkTransactionType.lightning
  final List<breez.Payment> sparkOnChainPayments; // SparkTransactionType.bitcoin (Deposit/Withdraw)
  final List<breez.Payment> sparkInternalPayments; // SparkTransactionType.spark (Internal)

  // Dedicated list for raw Unclaimed Deposits
  final List<breez.DepositInfo> unclaimedDeposits;

  // Pending on-chain deposits tracked via Mempool API (< 3 confirmations)
  final List<SparkPendingDeposit> sparkPendingDeposits;

  // Mempool API transactions for tracked external addresses
  final List<MempoolAddressTransaction> mempoolTxs;

  // USDB token payments from Breez SDK (Spark token transfers)
  final List<breez.Payment> usdbTokenPayments;

  // Swap orders: Orchestra swaps, Cash App purchases, retired-provider history
  final List<SwapOrder> swapOrders;

  // Polymarket on-chain activity (deposits, withdrawals, trades)
  final List<Activity> polymarketActivity;

  // External USDC + USDC.e inflows to the Polymarket Safe, indexed
  // via Polygonscan's tokentx endpoint. Polymarket's Data API only
  // returns bet-related activity, so plain inbound transfers from
  // other wallets aren't surfaced anywhere else.
  final List<PolymarketUsdcReceive> polymarketUsdcReceives;

  // Outlogic buy/sell orders
  final List<OutlogicOrder> outlogicOrders;

  // True when `listPayments` failed/timed out for this build, so the
  // three `*Payments` lists above are zero by default — NOT by
  // observation. Consumers must preserve the cached Spark rows instead
  // of treating the empty lists as authoritative.
  final bool sparkPaymentsFetchFailed;

  // True when `listUnclaimedDeposits` failed/timed out for this build.
  // Same load-bearing distinction as `sparkPaymentsFetchFailed`: an
  // empty `unclaimedDeposits` from a 15s timeout is NOT "no deposits",
  // and writing it as authoritative erases the user's claim row —
  // on slow devices the timeout fires chronically, so the deposit
  // becomes permanently invisible and unclaimable.
  final bool unclaimedDepositsFetchFailed;

  RawTransactionData({
    required this.bitcoinTxs,
    required this.lightningPayments,
    required this.sparkOnChainPayments,
    required this.sparkInternalPayments,
    required this.unclaimedDeposits,
    this.sparkPendingDeposits = const [],
    this.mempoolTxs = const [],
    this.usdbTokenPayments = const [],
    this.swapOrders = const [],
    this.polymarketActivity = const [],
    this.polymarketUsdcReceives = const [],
    this.outlogicOrders = const [],
    this.sparkPaymentsFetchFailed = false,
    this.unclaimedDepositsFetchFailed = false,
  });
}

final rawTransactionDataProvider = StateProvider<RawTransactionData?>((ref) => null);

/// Per-wallet transaction cache — source of truth. Background sync
/// writes its result here, keyed by walletId at sync start, so a
/// mid-sync wallet swap can't redirect tx history to the wrong
/// wallet's slot.
final walletTransactionCacheProvider =
    StateNotifierProvider<WalletTransactionCacheNotifier, Map<String, Transaction>>(
        (ref) => WalletTransactionCacheNotifier());


class WalletTransactionCacheNotifier
    extends StateNotifier<Map<String, Transaction>> {
  /// Hive box name for the per-wallet `Transaction` cache. The box
  /// stores JSON-encoded snapshots produced by
  /// [TransactionCacheCodec]; on cold start the constructor hydrates
  /// from disk so the home Activity feed paints immediately, before
  /// the first sync writes fresh data.
  static const String _kBoxName = 'wallet_transaction_cache';

  /// Per-wallet write debounce. Sync writes can land in rapid bursts
  /// (Spark stream events especially); we don't need every
  /// intermediate snapshot on disk, just the latest one. 150 ms is
  /// short enough that a user backgrounding the app right after a
  /// new deposit / payment lands still gets the row persisted —
  /// 800 ms was eating writes when the user closed the app
  /// quickly, which is exactly when persistence matters most.
  final Map<String, Timer> _writeDebounce = {};
  static const Duration _writeDelay = Duration(milliseconds: 150);

  WalletTransactionCacheNotifier() : super(const {}) {
    _hydrateFromHive();
  }

  /// Pulls every cached entry into [state] synchronously. Bad / old
  /// entries are returned as `null` by the codec and skipped without
  /// crashing.
  void _hydrateFromHive() {
    try {
      if (!Hive.isBoxOpen(_kBoxName)) {
        return;
      }
      final box = Hive.box<String>(_kBoxName);
      if (box.isEmpty) {
        return;
      }
      final next = <String, Transaction>{};
      for (final key in box.keys) {
        if (key is! String) continue;
        final raw = box.get(key);
        final decoded = TransactionCacheCodec.decode(raw);
        if (decoded != null) next[key] = decoded;
      }
      if (next.isNotEmpty) state = next;
    } catch (_) {
      // Hive read failure is non-fatal — the in-memory cache stays
      // empty and the first sync repopulates it.
    }
  }

  /// Replace [walletId]'s transaction list. Used by background sync
  /// to deposit a wallet's freshly-built `Transaction` snapshot.
  /// Schedules a debounced write to the on-disk Hive cache so the
  /// next cold start hydrates from the freshest known snapshot.
  void setForWallet(String walletId, Transaction tx) {
    state = {...state, walletId: tx};
    _scheduleWriteThrough(walletId, tx);
  }

  /// Drop a wallet's cached transactions when the user removes the
  /// wallet so a recycled id can't inherit stale data.
  void deleteWallet(String walletId) {
    _writeDebounce.remove(walletId)?.cancel();
    if (state.containsKey(walletId)) {
      final next = {...state}..remove(walletId);
      state = next;
    }
    try {
      if (Hive.isBoxOpen(_kBoxName)) {
        Hive.box<String>(_kBoxName).delete(walletId);
      }
    } catch (_) {}
  }

  /// Surgical mutator for the optimistic-Polymarket-activity flow:
  /// merge [tx] into the wallet's existing transaction record without
  /// going through the full sync. Idempotent — keeps the prior list
  /// when [walletId] has no entry.
  void mergeForWallet(
      String walletId, Transaction Function(Transaction current) merge) {
    final current = state[walletId];
    if (current == null) return;
    final merged = merge(current);
    state = {...state, walletId: merged};
    _scheduleWriteThrough(walletId, merged);
  }

  /// Insert/replace a swap order row (Orchestra, Cash App purchase,
  /// retired-provider history)
  /// in the per-wallet transaction cache. Use this immediately after
  /// `swapOrdersProvider.notifier.addExchange(...)` so the
  /// new swap appears on the home Activity feed without waiting for
  /// the next periodic sync. Provide [counterpartWalletId] when both
  /// sides of the swap touch user-owned wallets (e.g. Move spending
  /// → savings) so the row shows on both feeds.
  void mergeSwapOrder(
    SwapOrder exchange, {
    String? ownerWalletId,
    String? counterpartWalletId,
  }) {
    final ownerId = exchange.walletId ?? ownerWalletId;
    final tx = SwapOrderTransaction(
      id: exchange.id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(exchange.timestamp),
      details: exchange,
      isConfirmed: exchange.isComplete,
    );
    void writeInto(String walletId) {
      // mergeForWallet returns early when there's no existing entry
      // for the wallet. A swap order can be the FIRST entry for
      // a savings wallet, so seed with empty if missing then merge.
      final current = state[walletId] ?? Transaction.empty();
      final existing =
          current.swapOrderTransactions.where((t) => t.id != tx.id).toList();
      final next = current.copyWith(
        swapOrderTransactions: <SwapOrderTransaction>[tx, ...existing],
      );
      state = {...state, walletId: next};
      _scheduleWriteThrough(walletId, next);
    }
    if (ownerId != null) writeInto(ownerId);
    if (counterpartWalletId != null && counterpartWalletId != ownerId) {
      writeInto(counterpartWalletId);
    }
  }

  /// Remove a swap order transaction from every wallet's cache by id.
  /// Used when an Orchestra quote (q_…) is replaced by its real order (ord_…)
  /// so the stale quote row doesn't linger in the Activity feed alongside the
  /// real one.
  void removeSwapOrder(String id) {
    var changed = false;
    final next = <String, Transaction>{};
    state.forEach((walletId, tx) {
      final filtered =
          tx.swapOrderTransactions.where((t) => t.id != id).toList();
      if (filtered.length != tx.swapOrderTransactions.length) {
        changed = true;
        final updated = tx.copyWith(swapOrderTransactions: filtered);
        next[walletId] = updated;
        _scheduleWriteThrough(walletId, updated);
      } else {
        next[walletId] = tx;
      }
    });
    if (changed) state = next;
  }

  void _scheduleWriteThrough(String walletId, Transaction tx) {
    _writeDebounce[walletId]?.cancel();
    _writeDebounce[walletId] = Timer(_writeDelay, () {
      _writeDebounce.remove(walletId);
      // ignore: unawaited_futures
      _writeNowOffThread(walletId, tx);
    });
  }

  /// Monotonic per-wallet write stamp. The off-thread write awaits a
  /// `compute`, so unlike the old synchronous encode two writes for
  /// the same wallet CAN now interleave — a slow encode of older data
  /// finishing after a newer write would persist stale rows over
  /// fresh ones. Every write (async or sync) bumps the stamp; an
  /// async write only puts if its stamp is still the latest.
  final Map<String, int> _writeGeneration = {};

  /// Debounced-path write. `jsonEncode` of a big history is a pure
  /// main-thread stall — on low-end devices it lands right after a
  /// sync tick already flooded the heap and costs dropped frames /
  /// GC churn — so only the string encode runs in a background
  /// isolate via `compute`. The json-safe map is still built on the
  /// main isolate (it touches SDK-backed model objects, which must
  /// not cross the isolate boundary). The sudden-app-close path
  /// (`persistNowForWallet`) keeps the fully synchronous `_writeNow`
  /// so a teardown can't lose the row waiting on an isolate spawn.
  Future<void> _writeNowOffThread(String walletId, Transaction tx) async {
    final gen = (_writeGeneration[walletId] ?? 0) + 1;
    _writeGeneration[walletId] = gen;
    try {
      if (!Hive.isBoxOpen(_kBoxName)) return;
      final map = TransactionCacheCodec.toCacheMap(tx);
      final encoded = await compute(jsonEncode, map);
      // A newer write (async or the sync persist-now path) landed
      // while we were encoding — drop this stale payload.
      if (_writeGeneration[walletId] != gen) return;
      if (!Hive.isBoxOpen(_kBoxName)) return;
      final box = Hive.box<String>(_kBoxName);
      // ignore: unawaited_futures
      box.put(walletId, encoded);
    } catch (_) {}
  }

  /// Flush a wallet's tx state to Hive synchronously, bypassing the
  /// debounce. Use after writes that MUST survive a sudden app close
  /// — e.g., a `newDeposits` SDK event landing on the stream — where
  /// waiting 150 ms for the debounce to fire risks losing the row.
  void persistNowForWallet(String walletId) {
    final tx = state[walletId];
    if (tx == null) return;
    _writeDebounce.remove(walletId)?.cancel();
    _writeNow(walletId, tx);
  }

  /// Drops an outpoint whose manual claim just returned, so its row does not
  /// wait for the next full sync. A later deposit snapshot stays authoritative.
  void removeSparkUnclaimedDeposit(String walletId,
      {required String txid, required int vout}) {
    mergeForWallet(
      walletId,
      (current) => current.copyWith(
        sparkUnclaimedDeposits: applySparkDepositUpdate(
          current.sparkUnclaimedDeposits,
          SparkDepositUpdate(SparkDepositUpdateKind.claimed, [
            breez.DepositInfo(
                txid: txid, vout: vout, amountSats: BigInt.zero, isMature: true),
          ]),
          now: DateTime.now(),
        ),
      ),
    );
    persistNowForWallet(walletId);
  }

  void _writeNow(String walletId, Transaction tx) {
    // Invalidate any in-flight off-thread encode for this wallet —
    // this synchronous write is newer, and the async put must not
    // land stale data over it.
    _writeGeneration[walletId] = (_writeGeneration[walletId] ?? 0) + 1;
    try {
      if (!Hive.isBoxOpen(_kBoxName)) return;
      final box = Hive.box<String>(_kBoxName);
      // ignore: unawaited_futures
      box.put(walletId, TransactionCacheCodec.encode(tx));
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final t in _writeDebounce.values) {
      t.cancel();
    }
    _writeDebounce.clear();
    super.dispose();
  }
}

/// Phase 17 — Union of every wallet's tx history. Active wallet's
/// txs come from the live `transactionNotifierProvider` (always
/// freshest); all other wallets pull from the per-wallet cache,
/// which is hydrated by `BackgroundSyncService` whenever a wallet
/// finishes syncing.
///
/// Each sub-list is a flat concat — duplicates can theoretically
/// occur if a Spark transfer goes between two of the user's own
/// wallets (the same payment shows up on both sides), but that's a
/// rare edge worth accepting versus the cost of correlating tx IDs
/// across heterogeneous types here.
/// Cross-wallet aggregate. Previously this watched the active-wallet
/// notifier *and* `settings.activeWalletId` to deduplicate the
/// active wallet's slot — which meant every carousel swipe (which
/// commits a new active id 250 ms later) re-ran the merge,
/// allocating ~MBs of fresh lists for nothing because the cache
/// contents themselves hadn't changed.
///
/// `walletTransactionCacheProvider` is the single source of truth:
/// the active-wallet `transactionNotifierProvider` mirrors a slot of
/// it. Reading directly from the cache means the merge only re-runs
/// when an actual write lands — sync ticks, optimistic updates,
/// wallet add/remove — not when the carousel flips identity. The
/// `Transaction.==` value-equality check on the StateNotifier also
/// means even when the merge does run, an identical-content output
/// won't notify downstream consumers.
final mergedTransactionsProvider = Provider<Transaction>((ref) {
  final cache = ref.watch(walletTransactionCacheProvider);

  final btc = <BitcoinTransaction>[];
  final spark = <SparkTransaction>[];
  final unclaimed = <SparkUnclaimedDeposit>[];
  final pending = <SparkPendingDeposit>[];
  final mempool = <MempoolAddressTransaction>[];
  final usdb = <UsdbTokenTransaction>[];
  final swapOrders = <SwapOrderTransaction>[];
  final polymarket = <PolymarketTransaction>[];
  final usdcReceives = <PolymarketUsdcReceive>[];
  final outlogic = <OutlogicTransaction>[];

  for (final t in cache.values) {
    btc.addAll(t.bitcoinTransactions);
    spark.addAll(t.sparkTransactions);
    unclaimed.addAll(t.sparkUnclaimedDeposits);
    pending.addAll(t.sparkPendingDeposits);
    mempool.addAll(t.mempoolTransactions);
    usdb.addAll(t.usdbTokenTransactions);
    swapOrders.addAll(t.swapOrderTransactions);
    polymarket.addAll(t.polymarketTransactions);
    usdcReceives.addAll(t.polymarketUsdcReceives);
    outlogic.addAll(t.outlogicTransactions);
  }

  return Transaction(
    bitcoinTransactions: btc,
    sparkTransactions: spark,
    sparkUnclaimedDeposits: unclaimed,
    sparkPendingDeposits: pending,
    mempoolTransactions: mempool,
    usdbTokenTransactions: usdb,
    swapOrderTransactions: swapOrders,
    polymarketTransactions: polymarket,
    polymarketUsdcReceives: usdcReceives,
    outlogicTransactions: outlogic,
  );
});

/// Read-side projection for the wallet the user is currently looking
/// at on the carousel. Decoupled from `activeWalletId` so swiping
/// between wallets repaints the tx list immediately, without waiting
/// for the 250 ms `activeWalletId` debounce that gates operational
/// state.
///
/// Resolution rule (subtle — read carefully before changing):
///
///   1. `viewedId == null` (cold start before any carousel page
///      change) → mirror the active-wallet notifier.
///   2. `viewedId == activeWalletId` (user is on the spending
///      sub-pages, or the active wallet IS the savings page they
///      swiped to) → mirror the active-wallet notifier. Reading
///      `cache[activeId]` directly works *most* of the time but
///      a fresh just-imported active wallet whose first sync is
///      mid-flight can briefly have its slot empty in the cache
///      while `transactionNotifierProvider.state` already holds
///      the latest snapshot from the in-flight write — the
///      notifier is the safer source.
///   3. `viewedId != activeWalletId` (parked on a non-active
///      savings card) → read `cache[viewedId]`, falling back to
///      `Transaction.empty()` if its slot is empty. Falling back
///      to the active notifier here would paint the *spending*
///      wallet's tx list onto a *savings* card during the 250 ms
///      swipe-debounce window — reads as a flicker.
final viewedWalletTransactionsProvider = Provider<Transaction>((ref) {
  final viewedId = ref.watch(viewedWalletIdProvider);
  final activeId = ref.watch(settingsProvider.select((s) => s.activeWalletId));
  if (viewedId == null || viewedId == activeId) {
    return ref.watch(transactionNotifierProvider);
  }
  final cache = ref.watch(walletTransactionCacheProvider);
  return cache[viewedId] ?? Transaction.empty();
});

/// Scope-aware tx feed for home / activity surfaces. When the home
/// carousel is on the All page, returns the merged feed; otherwise
/// the *viewed* wallet's feed (instant on swipe via
/// `viewedWalletIdProvider`). Widgets can swap their existing
/// `ref.watch(transactionNotifierProvider)` to this provider to
/// participate in the all-accounts view without further changes.
final scopedTransactionsProvider = Provider<Transaction>((ref) {
  final isAll = ref.watch(isAllAccountsScopeProvider);
  if (isAll) return ref.watch(mergedTransactionsProvider);
  return ref.watch(viewedWalletTransactionsProvider);
});

final getFiatPurchasesProvider = FutureProvider.autoDispose<void>((ref) async {
});

/// Active-wallet transaction view. Reads from the per-wallet cache;
/// writes go through the cache via the explicit `setForWallet` API,
/// which is also exposed via `.notifier.updateTransactions` here for
/// backwards compatibility with sync callers that target "the
/// current notifier" by reflex.
///
/// New code should prefer
/// `walletTransactionCacheProvider.notifier.setForWallet(walletId, …)`
/// directly so the wallet id is captured at sync start and never
/// inherits the active-wallet swap mid-flight.
final transactionNotifierProvider =
    StateNotifierProvider<TransactionNotifier, Transaction>((ref) {
  return TransactionNotifier(ref);
});

class TransactionNotifier extends StateNotifier<Transaction> {
  final Ref ref;
  ProviderSubscription<Map<String, Transaction>>? _cacheSub;
  ProviderSubscription<String?>? _activeIdSub;
  ProviderSubscription<AsyncValue<Settings>>? _initialSettingsSub;

  /// In-memory set of tx ids we've already reported as received.
  /// Reset on app launch (we don't persist this — every cold start
  /// rebuilds the set from the first cache snapshot, then only NEW
  /// receives from that point fire `transaction_received`). This
  /// avoids duplicate analytics events when the cache refreshes for
  /// reasons unrelated to a new tx (sync ticks, wallet swaps).
  final Set<String> _reportedReceiveIds = <String>{};

  /// Money arriving buzzes only for a payment stamped in this session:
  /// the history a first sync or a restore streams in is older and quiet.
  final IncomingPaymentGate _arrivals =
      IncomingPaymentGate(startedAt: DateTime.now());
  /// Mirror of [_reportedReceiveIds] for outgoing txs — the dedup set
  /// behind the centralized `transaction_sent` emission. Sends are
  /// emitted from here (the canonical snapshot) rather than the UI
  /// success handlers so every completed send is counted exactly once,
  /// regardless of which path (Spark hot wallet, hardware PSBT) finished
  /// it, and a cache refresh never re-fires an already-reported send.
  final Set<String> _reportedSentIds = <String>{};
  /// Per-wallet "have we seeded the historical set yet" flag. Was
  /// previously a single bool, which caused a recovery bug: the very
  /// first `_refresh` ran on the empty bootstrap snapshot, flipped
  /// `_seeded = true`, and then the genuinely-first non-empty
  /// snapshot (the sync filling in 169 historical receives for a
  /// freshly-restored wallet) flowed straight into
  /// `_reportNewReceives`, firing a `transaction_received` for every
  /// single one. Per-wallet tracking lets each wallet seed
  /// independently on its first real snapshot.
  final Set<String> _seededWalletIds = <String>{};

  TransactionNotifier(this.ref) : super(Transaction.empty()) {
    // Attach the cache listener FIRST and fire it immediately. The per-wallet
    // cache hydrates from Hive synchronously the very first time it's read —
    // which is this `ref.listen` call. Without `fireImmediately` that
    // already-completed hydration is never delivered (ref.listen only relays
    // *future* changes), so the cold-start Activity feed sat empty even though
    // the prior session's snapshot was on disk, until the next sync wrote the
    // cache (or the user pulled to refresh).
    _cacheSub = ref.listen<Map<String, Transaction>>(
      walletTransactionCacheProvider,
      (_, __) => _refresh(),
      fireImmediately: true,
    );
    _activeIdSub = ref.listen<String?>(
      settingsProvider.select((s) => s.activeWalletId),
      (_, __) => _refresh(),
      fireImmediately: true,
    );
    // `activeWalletId` is null on the first frame — settings load async via
    // the `initialSettingsProvider` FutureProvider — so both listeners above
    // resolve to an empty snapshot at construction time. Re-run `_refresh` the
    // moment settings finish loading and the real wallet id is known, so the
    // hydrated cache paints immediately instead of waiting for a background
    // sync. The `next == state` guard in `_refresh` makes this a no-op when
    // the id was already known.
    _initialSettingsSub = ref.listen<AsyncValue<Settings>>(
      initialSettingsProvider,
      (_, next) {
        if (next.hasValue) _refresh();
      },
    );
  }

  void _refresh() {
    final id = ref.read(settingsProvider).activeWalletId;
    final cache = ref.read(walletTransactionCacheProvider);
    final next = id == null
        ? Transaction.empty()
        : (cache[id] ?? Transaction.empty());
    if (next == state) return;

    if (id != null && !_seededWalletIds.contains(id)) {
      // First non-empty snapshot for this wallet — seed every
      // existing receive id and silence the events. Catches both
      // cold-start hydration of a long-held wallet AND the initial
      // sync burst on a freshly-restored wallet (where the SDK
      // walks chronologically and writes the cache 169 times).
      // Empty snapshots don't count — we wait until real data
      // arrives before flipping the seed.
      if (_hasAnyTx(next)) {
        _seedReceivedIds(next);
        _seededWalletIds.add(id);
      }
    } else if (id != null) {
      _reportNewReceives(next, id);
      _reportNewSends(next, id);
    }
    state = next;
  }

  bool _hasAnyTx(Transaction t) =>
      t.sparkTransactions.isNotEmpty ||
      t.bitcoinTransactions.isNotEmpty ||
      t.polymarketUsdcReceives.isNotEmpty;

  /// Returns the wallet-creation timestamp embedded in the wallet
  /// id (format `<unix-ms>-<rand>`), or null when the id doesn't
  /// parse. Used as a cutoff in `_reportNewReceives` so a tx whose
  /// timestamp predates the wallet's local creation can never fire
  /// a fresh-receive event — defends against late sync writes after
  /// a wallet swap.
  DateTime? _walletCreatedAt(String walletId) {
    final dash = walletId.indexOf('-');
    if (dash <= 0) return null;
    final ms = int.tryParse(walletId.substring(0, dash));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// First snapshot after launch — index every existing receive id so
  /// we don't fire `transaction_received` for txs that were already on
  /// disk. Future receives that aren't in this set will fire.
  void _seedReceivedIds(Transaction snapshot) {
    for (final tx in snapshot.sparkTransactions) {
      if (tx.type == TransactionType.received) {
        _reportedReceiveIds.add('spark:${tx.id}');
      } else {
        // Seed historical sends too — otherwise the first non-empty
        // snapshot (cold-start hydration / restore sync burst) would
        // fire a `transaction_sent` for every past outgoing tx.
        _reportedSentIds.add('spark:${tx.id}');
      }
    }
    for (final tx in snapshot.bitcoinTransactions) {
      if (_isBitcoinReceive(tx)) {
        _reportedReceiveIds.add('bitcoin:${tx.id}');
      } else {
        _reportedSentIds.add('bitcoin:${tx.id}');
      }
    }
    for (final tx in snapshot.polymarketUsdcReceives) {
      _reportedReceiveIds.add('usdc:${tx.id}');
    }
  }

  /// Walk the snapshot, fire `transaction_received` once for any
  /// incoming entry not in the reported set, then add it.
  /// Current BTC price in USD (value of 1 BTC), used to snapshot the
  /// at-the-time fiat value of a new transaction. Returns 0 if unavailable
  /// (e.g. rates not loaded yet) — `recordFromBtcPrice` no-ops on 0.
  double _currentBtcUsd() {
    try {
      final cs = ref.read(currencyProvider);
      final btc = Money.fromIntWithCurrency(100000000, AppCurrencies.btc);
      final usd = cs.convert(btc, AppCurrencies.usd);
      return double.tryParse(usd.amount.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _reportNewReceives(Transaction snapshot, String walletId) {
    final activeWallet = ref.read(settingsProvider).activeWallet;
    final walletCategory = activeWallet != null
        ? TrackingService.walletCategory(
            isHardware: activeWallet.isHardware,
            isWatchOnly: activeWallet.isWatchOnly,
            isSigner: activeWallet.isSigner,
            isExternalAddress: activeWallet.isExternalAddress,
          )
        : null;
    final walletKind = activeWallet != null
        ? TrackingService.walletKind(
            isLedger: activeWallet.isLedger,
            isHardware: activeWallet.isHardware,
            isWatchOnly: activeWallet.isWatchOnly,
            isSigner: activeWallet.isSigner,
            isExternalAddress: activeWallet.isExternalAddress,
          )
        : null;
    // Bucketed only (usdBucket); never the sats amount itself.
    final btcUsd = _currentBtcUsd();
    double? usdOf(int sats) => btcUsd > 0 ? sats * btcUsd / 100000000 : null;
    // Any tx older than the wallet's local-creation moment is
    // historical and shouldn't fire a fresh-receive event — even if
    // it wasn't covered by the per-wallet seed (e.g. tx arrives via
    // a late sync write minutes after seeding).
    final cutoff = _walletCreatedAt(walletId);
    // Track whether ANY receive lands this snapshot. If yes, fire the
    // mascot's `incoming` choreography exactly once at the end — even
    // if multiple receives arrived together (e.g. cold-start
    // hydration with a few cached deposits), we want a single wag,
    // not three stacking on top of each other.
    bool anyReceiveFired = false;
    // A bitcoin receive stamped in this session: one haptic at the end.
    bool arrivedNow = false;
    // Orchestra delivery legs (a conversion's inbound side, already
    // counted by swap_completed): reported as purpose 'conversion_leg' so
    // they do not bump affiliate activity or first-receive milestones.
    final deliveryLegs = PolymarketSparkTxsService.orchestraDeliverySnapshot();
    for (final tx in snapshot.sparkTransactions) {
      // Cached shells (no live `details`) are skipped here — we
      // only fire `transaction_received` for events surfaced by the
      // live SDK so we don't double-fire on cold-start hydration.
      // The next sync replaces shells with live entries which are
      // ALSO seeded into `_reportedReceiveIds` (via
      // `_seedReceivedIds`), so genuine new receives still fire.
      if (tx.type != TransactionType.received) continue;
      final key = 'spark:${tx.id}';
      if (_reportedReceiveIds.contains(key)) continue;
      _reportedReceiveIds.add(key);
      if (cutoff != null && tx.timestamp.isBefore(cutoff)) continue;
      final network = tx.sparkType == SparkTransactionType.lightning
          ? 'lightning'
          : tx.sparkType == SparkTransactionType.spark
              ? 'spark'
              : 'bitcoin';
      final amountSats = tx.amountSats.abs();
      // Snapshot the at-the-time USD value (write-once). Only genuinely NEW
      // receives reach here (history is seeded into `_reportedReceiveIds`),
      // so we never backfill old txs at today's price.
      TxFiatSnapshotService.recordFromBtcPrice(
          tx.id, amountSats, _currentBtcUsd());
      TrackingService.transactionReceived(
        network: network,
        amountSats: amountSats,
        walletCategory: walletCategory,
        amountUsd: usdOf(amountSats),
        walletKind: walletKind,
        purpose: deliveryLegs.contains(tx.id) ||
                PolymarketSparkTxsService.isTagged(tx.id)
            ? 'conversion_leg'
            : 'transfer',
      );
      anyReceiveFired = true;
      if (_arrivals.arrivedThisSession(tx.timestamp)) arrivedNow = true;
      _maybeUnlockMilestone(MilestoneKeys.firstSatReceived);
      if (network == 'lightning') {
        _maybeUnlockMilestone(MilestoneKeys.firstLightning);
      }
    }
    for (final tx in snapshot.bitcoinTransactions) {
      if (!_isBitcoinReceive(tx)) continue;
      final key = 'bitcoin:${tx.id}';
      if (_reportedReceiveIds.contains(key)) continue;
      _reportedReceiveIds.add(key);
      if (cutoff != null && tx.timestamp.isBefore(cutoff)) continue;
      final amountSats = _bitcoinReceiveAmount(tx);
      TxFiatSnapshotService.recordFromBtcPrice(
          tx.id, amountSats, _currentBtcUsd());
      TrackingService.transactionReceived(
        network: 'bitcoin',
        amountSats: amountSats,
        walletCategory: walletCategory,
        amountUsd: usdOf(amountSats),
        walletKind: walletKind,
      );
      anyReceiveFired = true;
      if (_arrivals.arrivedThisSession(tx.timestamp)) arrivedNow = true;
      _maybeUnlockMilestone(MilestoneKeys.firstSatReceived);
    }
    for (final tx in snapshot.polymarketUsdcReceives) {
      final key = 'usdc:${tx.id}';
      if (_reportedReceiveIds.contains(key)) continue;
      _reportedReceiveIds.add(key);
      if (cutoff != null && tx.timestamp.isBefore(cutoff)) continue;
      // Same policy as the BTC-rail receives above: coarse network +
      // wallet_category, no amount. Labelling the USDC (Polymarket)
      // receive keeps it out of the unlabelled `transaction_received`
      // bucket so it's filterable by network in PostHog like the rest.
      TrackingService.track('transaction_received', params: {
        'network': 'usdc',
        'asset': 'usdc',
        if (walletCategory != null) 'wallet_category': walletCategory,
        if (walletKind != null) 'wallet_kind': walletKind,
      });
      anyReceiveFired = true;
    }
    // Money landed in Bitcoin: one pattern however many receives this
    // snapshot holds. The helper keeps it quiet in the background and
    // right after a success overlay already marked the moment.
    if (arrivedNow) KuteHaptics.play(KuteHaptic.moneyIn);
    if (anyReceiveFired) {
      // Drive the mascot into `incoming` for ~1.6s. Single wag
      // regardless of how many receives landed in this snapshot.
      try {
        ref.read(kuteStateProvider.notifier).onReceive();
      } catch (_) {
        // Best-effort — never let mascot wiring break tx processing.
      }
      // Balance-threshold milestones — check on every receive so we
      // catch the upward crossings of 100k / 1M sats. Reads the
      // notifier's live balance value, NOT individual tx amounts,
      // because the user may receive several small amounts that
      // collectively cross a threshold.
      _checkBalanceMilestones();
    }

    // Backfill: snapshot the USD value of EVERY on-chain / Spark tx that
    // doesn't have one yet (write-once). Pre-feature txs pick up today's
    // price — they read 0% now and track gain/loss from here forward;
    // genuinely-new txs were already snapshotted above at their real
    // first-seen price, so this never overwrites them.
    final backfillBtcUsd = _currentBtcUsd();
    if (backfillBtcUsd > 0) {
      for (final tx in snapshot.sparkTransactions) {
        TxFiatSnapshotService.recordFromBtcPrice(
            tx.id, tx.amountSats.abs(), backfillBtcUsd);
      }
      for (final tx in snapshot.bitcoinTransactions) {
        final sats = (tx.receivedSats - tx.sentSats).abs();
        TxFiatSnapshotService.recordFromBtcPrice(tx.id, sats, backfillBtcUsd);
      }
      // Outlogic BTC purchases: snapshot the BTC received at the current
      // price (keyed by order id). The order also stores the exact fiat
      // paid — we keep today's price here for consistency with the rest of
      // the backfill; an exact-fiat refinement can use `order.fromAmount`.
      for (final tx in snapshot.outlogicTransactions) {
        final o = tx.details;
        final trade = o.trade;
        if (trade != null &&
            trade.toAsset.toUpperCase() == 'BTC' &&
            trade.toAmount > 0) {
          final sats = (trade.toAmount * 100000000).round();
          TxFiatSnapshotService.recordFromBtcPrice(o.id, sats, backfillBtcUsd);
        }
      }
    }
  }

  /// Mirror of [_reportNewReceives] for outgoing txs. Fires
  /// `transaction_sent` once per new sent entry (keyed in
  /// [_reportedSentIds]), tagged with the rail (lightning/spark/
  /// bitcoin). Emitting from the canonical snapshot — not the
  /// send-success UI handlers — means every completed send is counted
  /// regardless of which flow finished it, with no double-fire.
  void _reportNewSends(Transaction snapshot, String walletId) {
    final activeWallet = ref.read(settingsProvider).activeWallet;
    final walletCategory = activeWallet != null
        ? TrackingService.walletCategory(
            isHardware: activeWallet.isHardware,
            isWatchOnly: activeWallet.isWatchOnly,
            isSigner: activeWallet.isSigner,
            isExternalAddress: activeWallet.isExternalAddress,
          )
        : null;
    final walletKind = activeWallet != null
        ? TrackingService.walletKind(
            isLedger: activeWallet.isLedger,
            isHardware: activeWallet.isHardware,
            isWatchOnly: activeWallet.isWatchOnly,
            isSigner: activeWallet.isSigner,
            isExternalAddress: activeWallet.isExternalAddress,
          )
        : null;
    // Bucketed only (usdBucket); never the sats amount itself.
    final btcUsd = _currentBtcUsd();
    double? usdOf(int sats) => btcUsd > 0 ? sats * btcUsd / 100000000 : null;
    final cutoff = _walletCreatedAt(walletId);
    for (final tx in snapshot.sparkTransactions) {
      if (tx.type != TransactionType.sent) continue;
      final key = 'spark:${tx.id}';
      if (_reportedSentIds.contains(key)) continue;
      _reportedSentIds.add(key);
      if (cutoff != null && tx.timestamp.isBefore(cutoff)) continue;
      final network = tx.sparkType == SparkTransactionType.lightning
          ? 'lightning'
          : tx.sparkType == SparkTransactionType.spark
              ? 'spark'
              : 'bitcoin';
      TrackingService.transactionSent(
        network: network,
        amountSats: tx.amountSats.abs(),
        walletCategory: walletCategory,
        amountUsd: usdOf(tx.amountSats.abs()),
        walletKind: walletKind,
        // Orchestra funding sends (swap/venue deposit legs) are tagged at
        // send time; their flow's own events already count them.
        purpose: PolymarketSparkTxsService.isTagged(tx.id)
            ? 'conversion_leg'
            : 'transfer',
      );
    }
    for (final tx in snapshot.bitcoinTransactions) {
      if (tx.type != TransactionType.sent) continue;
      final key = 'bitcoin:${tx.id}';
      if (_reportedSentIds.contains(key)) continue;
      _reportedSentIds.add(key);
      if (cutoff != null && tx.timestamp.isBefore(cutoff)) continue;
      TrackingService.transactionSent(
        network: 'bitcoin',
        amountSats: (tx.sentSats - tx.receivedSats).abs(),
        walletCategory: walletCategory,
        amountUsd: usdOf((tx.sentSats - tx.receivedSats).abs()),
        walletKind: walletKind,
      );
    }
  }

  /// Forwards a milestone key into the pending-milestone provider so
  /// the home overlay can render the unlock card. Best-effort —
  /// failure to claim never breaks tx processing.
  void _maybeUnlockMilestone(String key) {
    try {
      ref.read(pendingMilestoneProvider.notifier).unlock(key);
    } catch (_) {}
  }

  /// Checks balance-threshold milestones against the latest balance
  /// snapshot. Each milestone uses `OnceFlagsService` internally so a
  /// repeated call is a cheap no-op once the threshold has been
  /// claimed.
  void _checkBalanceMilestones() {
    try {
      final balance = ref.read(balanceNotifierProvider);
      final totalSats =
          balance.sparkBitcoinbalance + balance.onChainBtcBalance;
      if (totalSats >= 100000) {
        _maybeUnlockMilestone(MilestoneKeys.hundredKSats);
      }
      if (totalSats >= 1000000) {
        _maybeUnlockMilestone(MilestoneKeys.oneMSats);
      }
    } catch (_) {}
  }

  bool _isBitcoinReceive(BitcoinTransaction tx) {
    return tx.receivedSats > tx.sentSats;
  }

  int _bitcoinReceiveAmount(BitcoinTransaction tx) {
    return (tx.receivedSats - tx.sentSats).abs();
  }

  String? get _activeId => ref.read(settingsProvider).activeWalletId;

  /// Re-pull optimistic Polymarket activities from disk and merge them into
  /// the current state. Called after a successful sell/redeem so the home
  /// Activity feed reflects the new entry immediately, instead of waiting
  /// for the next background sync (~10-30s).
  void refreshOptimisticPolymarketActivity() {
    final id = _activeId;
    if (id == null) return;
    ref.read(walletTransactionCacheProvider.notifier).mergeForWallet(
      id,
      (current) {
        final apiHashes = current.polymarketTransactions
            .map((t) => t.activity.transactionHash.toLowerCase())
            .toSet();
        final optimistic = PolymarketOptimisticActivityService.snapshot(
          confirmedHashes: apiHashes,
          confirmed: [for (final t in current.polymarketTransactions) t.activity],
        );
        if (optimistic.isEmpty) return current;
        final existingIds =
            current.polymarketTransactions.map((t) => t.id).toSet();
        final newTxs = optimistic
            .where((a) =>
                !(a.activityType == ActivityType.redeem && a.usdcSize <= 0))
            .map((a) => PolymarketTransaction(
                  id: '${a.transactionHash}_${a.timestamp}',
                  timestamp: a.timestampDate,
                  activity: a,
                ))
            .where((t) => !existingIds.contains(t.id))
            .toList();
        if (newTxs.isEmpty) return current;
        return current.copyWith(
          polymarketTransactions: [
            ...newTxs,
            ...current.polymarketTransactions,
          ],
        );
      },
    );
  }

  /// Replaces the combo (parlay) rows of the active wallet's Polymarket
  /// activity with [rows] (`ComboActivityFeed.rowsFor`), so a placed,
  /// closed or claimed combo shows without waiting for the next sync.
  /// Only for the hot spending wallet, whose deposit wallet holds them.
  void refreshComboActivity(List<Activity> rows) {
    final id = _activeId;
    if (id == null ||
        id != pickSpendingWallet(ref.read(settingsProvider))?.id) {
      return;
    }
    ref.read(walletTransactionCacheProvider.notifier).mergeForWallet(
      id,
      (current) {
        final kept = current.polymarketTransactions
            .where((t) =>
                !ComboActivityFeed.isComboCondition(t.activity.conditionId))
            .toList();
        final combos = rows
            .where((a) =>
                !(a.activityType == ActivityType.redeem && a.usdcSize <= 0))
            .map((a) => PolymarketTransaction(
                  id: '${a.transactionHash}_${a.timestamp}',
                  timestamp: a.timestampDate,
                  activity: a,
                ))
            .toList();
        if (combos.isEmpty &&
            kept.length == current.polymarketTransactions.length) {
          return current;
        }
        return current.copyWith(
          polymarketTransactions: [...combos, ...kept]
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
      },
    );
  }

  /// Backwards-compatible facade over the cache write. Captures the
  /// CURRENT active wallet id and routes the build into that slot.
  /// New sync code should prefer
  /// `updateTransactionsFor(walletId, raw)` so the id is captured at
  /// sync start, not at write time.
  Future<void> updateTransactions(RawTransactionData? rawData) async {
    final id = _activeId;
    if (id == null) {
      if (rawData == null) {
        if (state != Transaction.empty()) state = Transaction.empty();
      }
      return;
    }
    await updateTransactionsFor(id, rawData);
  }

  /// Build the per-wallet `Transaction` snapshot from [rawData] and
  /// drop it into the cache slot for [walletId]. Single source of
  /// truth — the active-wallet notifier mirrors the cache, so
  /// downstream UI sees the update through its existing
  /// `ref.watch(transactionNotifierProvider)` automatically.
  Future<void> updateTransactionsFor(
      String walletId, RawTransactionData? rawData) async {
    if (rawData == null) {
      if (walletId == _activeId && state != Transaction.empty()) {
        state = Transaction.empty();
      }
      return;
    }

    // 1. Bitcoin Transactions (BDK)
    final bitcoinTransactions = rawData.bitcoinTxs.map((btcTx) {
      final cp = btcTx.chainPosition;
      final isConfirmed = cp is bdk.ConfirmedChainPosition;
      DateTime timestamp;
      if (isConfirmed) {
        final confirmTime = (cp).confirmationBlockTime.confirmationTime;
        timestamp = confirmTime != 0
            ? DateTime.fromMillisecondsSinceEpoch(confirmTime * 1000)
            : DateTime.now();
      } else {
        timestamp = DateTime.now();
      }
      return BitcoinTransaction(
        id: btcTx.txid.toString(),
        timestamp: timestamp,
        btcDetails: btcTx,
        isConfirmed: isConfirmed,
      );
    }).toList();

    // On-chain Bitcoin txs are append-only — a scan that comes back empty
    // (e.g. an Electrum hiccup on a hardware wallet) must NOT wipe the
    // rows the cache already holds. Same protection as the
    // Spark guard below: keep the cached list whenever the fresh scan is
    // empty but we already had rows.
    final cachedBitcoin = ref
            .read(walletTransactionCacheProvider)[walletId]
            ?.bitcoinTransactions ??
        const <BitcoinTransaction>[];
    final effectiveBitcoinTransactions =
        bitcoinTransactions.isEmpty && cachedBitcoin.isNotEmpty
            ? cachedBitcoin
            : bitcoinTransactions;

    // 2. Consolidated Spark Transactions (History)
    // If listPayments failed for this run, keep whatever rows the
    // cache already has for this wallet — overwriting with the empty
    // build payload would clear the user's Activity feed even though
    // the SDK still has the history (manifests as "balance OK, but no
    // transactions" until the next payment event lands).
    final cachedSpark = ref
            .read(walletTransactionCacheProvider)[walletId]
            ?.sparkTransactions ??
        const <SparkTransaction>[];
    final List<SparkTransaction> sparkTransactions;
    if (rawData.sparkPaymentsFetchFailed) {
      sparkTransactions = cachedSpark;
    } else {
      final Map<String, breez.Payment> uniqueSparkPayments = {};
      for (var p in rawData.lightningPayments) {
        uniqueSparkPayments[p.id] = p;
      }
      for (var p in rawData.sparkOnChainPayments) {
        uniqueSparkPayments[p.id] = p;
      }
      for (var p in rawData.sparkInternalPayments) {
        uniqueSparkPayments[p.id] = p;
      }
      final built = uniqueSparkPayments.values.map((payment) {
        return SparkTransaction(
          id: payment.id,
          timestamp: DateTime.fromMillisecondsSinceEpoch(payment.timestamp.toInt() * 1000),
          details: payment,
          isConfirmed: payment.status == breez.PaymentStatus.completed,
        );
      }).toList();
      // `sparkPaymentsFetchFailed` only covers a null / thrown fetch. An EMPTY
      // SUCCESS ([]) — e.g. `listPayments` returning nothing while the Spark
      // SDK is still warming up on a cold start — must ALSO not wipe a
      // non-empty cache: spark history is append-only, so an empty result for
      // a wallet we already have rows for is transient, never authoritative.
      // This is the "balance OK, but no transactions" bug on the spending
      // wallet.
      sparkTransactions =
          built.isEmpty && cachedSpark.isNotEmpty ? cachedSpark : built;
    }

    // Txids currently tracked by a mempool `n/3` row (0–2 confs). Breez flags
    // an on-chain deposit as "unclaimed" after the first confirmation, so the
    // mempool row and the unclaimed row overlap during the 1–2 conf window.
    // We want the `n/3` row to be the SINGLE representation through that whole
    // window — so the unclaimed twin is hidden below, not the mempool row.
    final pendingMempoolTxids = rawData.sparkPendingDeposits
        .map((pd) => pd.mempoolTx.txid.toLowerCase())
        .toSet();

    // 4. Spark Unclaimed Deposits — hide any that still have a live mempool
    // `n/3` twin (the progress row covers them until 3 confs); the unclaimed
    // "claim" row reappears only once the mempool row drops at 3 confs.
    //
    // If `listUnclaimedDeposits` failed/timed out for this run, keep the
    // cached rows — same shield as the Spark history guard above. On
    // low-end phones the 15s timeout fires routinely, and rebuilding
    // from the (defaulted-empty) raw list erased the claim row on
    // every failing tick, leaving the deposit invisible and the user
    // unable to claim. The row clears through a SUCCESSFUL fetch or
    // the `claimedDeposits` push event, never through a timeout.
    final List<SparkUnclaimedDeposit> sparkUnclaimedDeposits;
    if (rawData.unclaimedDepositsFetchFailed) {
      sparkUnclaimedDeposits = ref
              .read(walletTransactionCacheProvider)[walletId]
              ?.sparkUnclaimedDeposits ??
          const <SparkUnclaimedDeposit>[];
    } else {
      final cached = ref.read(walletTransactionCacheProvider)[walletId];
      // Same rules as the push pipeline. Deposit payments already in the
      // cache stop a list read taken before a claim from restoring its row.
      sparkUnclaimedDeposits = applySparkDepositUpdate(
        cached?.sparkUnclaimedDeposits ?? const <SparkUnclaimedDeposit>[],
        SparkDepositUpdate(
            SparkDepositUpdateKind.snapshot, rawData.unclaimedDeposits),
        now: DateTime.now(),
        settledOutpoints: sparkDepositPaymentOutpoints([
          ...sparkTransactions,
          ...?cached?.sparkTransactions,
        ]),
        mempoolTxids: pendingMempoolTxids,
      );
    }

    // 4b. Spark Pending Deposits (websocket/mempool-tracked, 0–2 confs).
    // Show the `n/3` row for the WHOLE pending window. We deliberately do NOT
    // drop it when the deposit becomes "unclaimed" (Breez flips that at ~1
    // conf) — doing so made the progress row vanish after one confirmation.
    // The mempool row is the single source of truth for 0–2 confs; its
    // unclaimed twin is hidden above, the raw Breez/BDK rows are hidden at
    // display time (`Transaction._pendingDepositTxids`), and it drops out
    // automatically at 3 confs (the source filters `>= 3`), at which point
    // the unclaimed/confirmed row takes over.
    final sparkPendingDeposits = rawData.sparkPendingDeposits.toList();

    // 5. Mempool Transactions (External Address)
    final mempoolTransactions = rawData.mempoolTxs;

    // 6. USDB Token Transactions (Breez SDK)
    final usdbTokenTransactions = rawData.usdbTokenPayments.map((payment) {
      return UsdbTokenTransaction(
        id: payment.id,
        timestamp: DateTime.fromMillisecondsSinceEpoch(payment.timestamp.toInt() * 1000),
        details: payment,
        isConfirmed: payment.status == breez.PaymentStatus.completed,
      );
    }).toList();

    // 8. Swap order transactions (Orchestra, Cash App, retired-provider history)
    // Filter out 0-value exchanges and exchanges belonging to other wallets
    final swapOrderTransactions = rawData.swapOrders
        .where((e) {
          final dep = double.tryParse(e.depositAmount) ?? 0;
          final wth = double.tryParse(e.withdrawalAmount) ?? 0;
          if (dep <= 0 && wth <= 0) return false;
          // Hide BitcoinVN orders still awaiting deposit
          if (e.providerName == 'BitcoinVN' && e.status == 'wait') return false;
          return true;
        })
        .map((e) {
          return SwapOrderTransaction(
            id: e.id,
            timestamp: DateTime.fromMillisecondsSinceEpoch(e.timestamp),
            details: e,
            isConfirmed: e.isComplete,
          );
        }).toList();

    // 9. Polymarket Activity (deposits, withdrawals, trades)
    // Filter out $0 redeems — they carry no value and clutter the list.
    // Merge in optimistic local activities (just-sold/redeemed entries the
    // user wrote before the Data API caught up). Dedupe by transactionHash:
    // if the API now reports the same hash, we drop our optimistic copy.
    final apiHashes = rawData.polymarketActivity
        .map((a) => a.transactionHash.toLowerCase())
        .toSet();
    final optimisticActivity =
        PolymarketOptimisticActivityService.snapshot(
      confirmedHashes: apiHashes,
      // Fuzzy eviction: BUY rows are keyed by orderID, which never
      // matches the API's chain hash — shape-match instead.
      confirmed: rawData.polymarketActivity,
    );
    final mergedActivity = [...optimisticActivity, ...rawData.polymarketActivity];
    final polymarketTransactions = mergedActivity
        .where((a) {
          // `a.activityType` parses a string into the bundled SDK enum and
          // THROWS on values it doesn't know (e.g. Polymarket's newer
          // "YIELD"). That throw used to escape this `.where`/`.map` and nuke
          // the ENTIRE `updateTransactionsFor` build — so a single
          // unrecognised activity blanked the whole Activity feed ("balance
          // OK, no transactions") even though every other tx was fine. Treat
          // an unparseable activity as "drop this one row" instead of fatal.
          try {
            return !(a.activityType == ActivityType.redeem && a.usdcSize <= 0);
          } catch (_) {
            return false;
          }
        })
        .map((a) {
      return PolymarketTransaction(
        id: '${a.transactionHash}_${a.timestamp}',
        timestamp: a.timestampDate,
        activity: a,
      );
    }).toList();

    // 10. Outlogic Orders
    final outlogicTransactions = rawData.outlogicOrders.map((order) {
      DateTime ts = DateTime.now();
      if (order.createdAt.isNotEmpty) {
        ts = DateTime.tryParse(order.createdAt) ?? DateTime.now();
      }
      return OutlogicTransaction(
        id: 'outlogic_${order.id}',
        timestamp: ts,
        details: order,
        isConfirmed: order.status == 'COMPLETED',
      );
    }).toList();

    final next = Transaction(
      bitcoinTransactions: effectiveBitcoinTransactions,
      sparkTransactions: sparkTransactions,
      sparkUnclaimedDeposits: sparkUnclaimedDeposits,
      sparkPendingDeposits: sparkPendingDeposits,
      mempoolTransactions: mempoolTransactions,
      usdbTokenTransactions: usdbTokenTransactions,
      swapOrderTransactions: swapOrderTransactions,
      polymarketTransactions: polymarketTransactions,
      polymarketUsdcReceives: rawData.polymarketUsdcReceives,
      outlogicTransactions: outlogicTransactions,
    );

    ref
        .read(walletTransactionCacheProvider.notifier)
        .setForWallet(walletId, next);
  }

  @override
  void dispose() {
    _cacheSub?.close();
    _activeIdSub?.close();
    _initialSettingsSub?.close();
    super.dispose();
  }
}

