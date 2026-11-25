import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart' show Settings;
// lib/providers/hyperliquid_account_provider.dart
//
// The user's Hyperliquid account state: address derivation (READ-ONLY —
// the private key is derived and immediately discarded; signing lives in
// the trading notifier), the polled clearinghouse snapshot, cheap derived
// views for the UI, and the non-autoDispose badge count for the home
// pill.
//
// Polling cadence (mirrors PolymarketTradingNotifier._adjustRefreshRate):
//   - 4 s while a HyperCore deposit is in flight (an Orchestra row still
//     pending into HYPERCORE for this wallet), so the credit shows within
//     one short poll of landing; back to the cadence below once the row
//     settles;
//   - 5 s while positions are open OR an order placement is in flight —
//     the position cards animate PnL each tick via RollingNumberText;
//   - 15 s idle — a flat account only needs a heartbeat.
// Snapshots are value-compared before writing state so an idle tick that
// produced identical data doesn't rebuild every consumer.
//
// Lifecycle: everything here except the badge count is autoDispose — the
// account stack only runs while a Hyperliquid surface (or the trading
// notifier) is alive. The badge count is deliberately NOT autoDispose
// (the home pill watches it permanently) and is gated by the
// 'hl_enabled_<walletId>' secure-storage flag written at provisioning:
// users who never traded Hyperliquid get a constant 0 and NEVER hit the
// network — each 60 s tick for them is a local flag read only.

import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hyperliquid_account_cache.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/one_balance/move_settled_refresh.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart';
import 'package:kute/services/passkey_service.dart'
    show resolveBip39MnemonicFor;
import 'package:kute/services/polymarket/order_poll_gate.dart';

// ────────────────────── model value-equality helpers ──────────────────────
// The hyperliquid_market.dart structs deliberately don't override == (they
// are wire DTOs); the providers compare them field-wise so an unchanged
// poll tick can short-circuit notifications (same GC rationale as
// PolymarketTradingState's operator==).

bool hlPerpPositionEquals(HlPerpPosition a, HlPerpPosition b) =>
    a.coin == b.coin &&
    a.szi == b.szi &&
    a.entryPx == b.entryPx &&
    a.positionValue == b.positionValue &&
    a.unrealizedPnl == b.unrealizedPnl &&
    a.returnOnEquity == b.returnOnEquity &&
    a.liquidationPx == b.liquidationPx &&
    a.marginUsed == b.marginUsed &&
    a.leverageType == b.leverageType &&
    a.leverageValue == b.leverageValue;

bool hlPerpPositionListEquals(List<HlPerpPosition> a, List<HlPerpPosition> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!hlPerpPositionEquals(a[i], b[i])) return false;
  }
  return true;
}

bool hlSpotBalanceListEquals(List<HlSpotBalance> a, List<HlSpotBalance> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].coin != b[i].coin ||
        a[i].total != b[i].total ||
        a[i].hold != b[i].hold ||
        a[i].entryNtl != b[i].entryNtl) {
      return false;
    }
  }
  return true;
}

bool hlOpenOrderListEquals(List<HlOpenOrder> a, List<HlOpenOrder> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].oid != b[i].oid ||
        a[i].coin != b[i].coin ||
        a[i].sz != b[i].sz ||
        a[i].limitPx != b[i].limitPx ||
        a[i].isBuy != b[i].isBuy ||
        // A WS-only row carries placeholder metadata until REST fills it
        // in; the refresh must not be swallowed as "unchanged".
        a[i].orderType != b[i].orderType ||
        a[i].isTrigger != b[i].isTrigger ||
        a[i].triggerPx != b[i].triggerPx ||
        a[i].reduceOnly != b[i].reduceOnly ||
        a[i].tif != b[i].tif ||
        a[i].isPositionTpsl != b[i].isPositionTpsl) {
      return false;
    }
  }
  return true;
}

bool hlFillListEquals(List<HlFill> a, List<HlFill> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].oid != b[i].oid ||
        a[i].time != b[i].time ||
        a[i].coin != b[i].coin ||
        a[i].sz != b[i].sz ||
        a[i].px != b[i].px) {
      return false;
    }
  }
  return true;
}

bool hlAccountSnapshotEquals(HlAccountSnapshot a, HlAccountSnapshot b) =>
    a.accountValue == b.accountValue &&
    a.withdrawable == b.withdrawable &&
    a.totalMarginUsed == b.totalMarginUsed &&
    a.crossMaintenanceMarginUsed == b.crossMaintenanceMarginUsed &&
    hlPerpPositionListEquals(a.positions, b.positions) &&
    hlSpotBalanceListEquals(a.spotBalances, b.spotBalances) &&
    setEquals(a.activeDexes, b.activeDexes);

// ───────────────────────────── address ─────────────────────────────

/// The user's Hyperliquid account address — the SPENDING wallet's EOA at
/// m/44'/60'/0'/0/0, the exact same derivation Polymarket uses (see
/// polymarket_trading_provider.build). Derivation is READ-ONLY: the
/// private key is dropped on the floor here; anything that needs to sign
/// re-derives on demand inside the trading notifier.
///
/// Null when there's no hot wallet, the session isn't unlocked (passkey
/// wallets included), or the mnemonic can't be resolved. Recomputes on
/// wallet switch, on a new unlock, and once the lock overlay lifts after
/// a build behind it.
/// The spending wallet and its EVM format: what selects its EVM account.
(String?, EvmDerivationVersion?) _spendingEvmIdentity(Settings s) {
  final wallet = pickSpendingWallet(s);
  return (wallet?.id, wallet?.evmDerivationVersion);
}

final hyperliquidAddressProvider = FutureProvider<String?>((ref) async {
  // Scope rebuilds to the spending wallet identity + session, not
  // every settings write. The EVM format is part of that identity: a
  // recovered wallet's unlock-time format check can settle it.
  ref.watch(settingsProvider.select(_spendingEvmIdentity));
  ref.watch(sessionAuthProvider);

  final settings = ref.read(settingsProvider);
  final spending = pickSpendingWallet(settings);
  if (spending == null) return null;
  if (!watchSessionUnlock(ref)) return null;

  try {
    final mnemonic = await resolveBip39MnemonicFor(spending,
        access: SeedAccess.automatic, session: ref.read(seedSessionProvider));
    if (mnemonic == null) return null;
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);
    return wallet.address;
  } catch (_) {
    return null;
  }
});

// ───────────────────────── account snapshot ─────────────────────────

/// Poll interval while a HyperCore deposit is pending (spec: 3–5 s).
const int kHlDepositPendingIntervalSecs = 4;

/// Poll interval with open positions or a placement in flight.
const int kHlActiveIntervalSecs = 5;

/// Poll interval with spot tokens held (their value moves) or before the
/// first snapshot has loaded (a failed first read retries on it).
const int kHlIdleIntervalSecs = 15;

/// The cadence an account holding nothing gets: no periodic read at all
/// (founder, 2026-10-13: "no open positions on a venue → no polling for
/// it"). Its cash changes only through events that read it themselves: a
/// fill (userFills invalidates this provider), a deposit (the pending
/// cadence above), a funding move or sweep landing and a close (the
/// one-balance live refresh). The sweeper's free-USDC badge poll is
/// separate and stays.
const int kHlNoPollIntervalSecs = 0;

/// One Investing account read at a time per account, shared by every
/// reader of [hyperliquidAccountProvider] (one per notifier, which
/// Riverpod keeps across the provider's rebuilds): the account's own build (a
/// websocket ledger push, a fill or a credit invalidates it), its 4 s /
/// 5 s / 15 s poll and the queued order's fresh credit read
/// ([HlAccountNotifier.freshRead]). A read asked while one is in flight
/// joins it, unless the asker knows the account changed just now (a
/// build after an invalidation, [HlAccountNotifier.refresh], a credit
/// signal): that one waits for a single read sent behind the one in
/// flight. The poll and the fresh read also take a read sent less than
/// [reuseWithin] (950 ms) ago instead of sending another, so these never
/// read the account twice within the same second. The fresh read backs off
/// after a failure (a 429 included): 1, 2, 4, 8, then 15 s at most,
/// answering the last snapshot meanwhile without a request.
///
/// Hyperliquid info API weight (1200 per minute per IP): a fresh read is
/// `clearinghouseState` + `spotClearinghouseState` (2 + 2 = 4; the
/// builder DEXs' part is reused from the last full read,
/// [HyperliquidModel.getCreditSnapshot]); a full read adds 2 per USDC
/// builder DEX. At one fresh read a second for the first 30 s after a
/// funding: 4 weight/s, ≤ 240 per minute (20% of the budget), ≤ 120 over
/// the 30 s, and the 4 s poll's reads in that window are absorbed by it.
class HlAccountReads {
  final Map<String, Future<HlAccountSnapshot>> _inFlight = {};
  final Map<String, HlAccountSnapshot> _last = {};

  /// Accounts read within the last [reuseWithin] (a timer clears each).
  final Map<String, Timer> _recent = {};

  /// The fresh read's backoff per account, and the timer ending it.
  final Map<String, Duration> _backoff = {};
  final Map<String, Timer> _backingOff = {};

  /// A read SENT less than this ago answers the poll and the fresh read
  /// without a request (just under a second, so the 1 s tick still
  /// reads every second while nothing reads twice within it).
  static const Duration reuseWithin = Duration(milliseconds: 950);
  static const Duration backoffStart = Duration(seconds: 1);
  static const Duration backoffCap = Duration(seconds: 15);

  /// Requests sent and failed (diagnostics, tests).
  int sent = 0;
  int failed = 0;

  /// The read queued behind the one in flight ([read]'s `after`), per
  /// account: what it will fetch, whether that is the full account, and
  /// everyone waiting on it.
  final Map<String, Completer<HlAccountSnapshot>> _queued = {};
  final Map<String, Future<HlAccountSnapshot> Function()> _queuedFetch = {};
  final Map<String, bool> _queuedLight = {};

  /// [fetch] for [address], joined with one in flight; with [reuse], a
  /// read completed within [reuseWithin] answers instead.
  ///
  /// [after]: the asker knows the account changed just now (an exchange
  /// action answered, a fill or a ledger push on the socket, an explicit
  /// refresh before an order is sized): only a request SENT from now on
  /// answers it. A read in flight was sent before and may not show the
  /// change, so it is not joined; ONE more read is sent when it ends,
  /// shared by everyone who asked meanwhile (still one request in flight
  /// at a time). [light]: [fetch] is the credit watch's light read; the
  /// queued read is the full one as soon as any asker needs the whole
  /// account.
  Future<HlAccountSnapshot> read(
      String address, Future<HlAccountSnapshot> Function() fetch,
      {bool reuse = false, bool after = false, bool light = false}) {
    final key = address.toLowerCase();
    final running = _inFlight[key];
    if (running != null) {
      if (!after) return running;
      final queued = _queued[key];
      if (queued != null) {
        if (!light && (_queuedLight[key] ?? false)) {
          _queuedFetch[key] = fetch;
          _queuedLight[key] = false;
        }
        return queued.future;
      }
      final next = Completer<HlAccountSnapshot>();
      _queued[key] = next;
      _queuedFetch[key] = fetch;
      _queuedLight[key] = light;
      void send() {
        _queued.remove(key);
        _queuedLight.remove(key);
        final queuedFetch = _queuedFetch.remove(key) ?? fetch;
        read(address, queuedFetch)
            .then(next.complete, onError: next.completeError);
      }

      running.then((_) => send(), onError: (Object _) => send());
      return next.future;
    }
    final last = _last[key];
    if (reuse && !after && last != null && _recent.containsKey(key)) {
      return Future.value(last);
    }
    sent++;
    final future = fetch();
    _inFlight[key] = future;
    _recent.remove(key)?.cancel();
    _recent[key] = Timer(reuseWithin, () => _recent.remove(key));
    // No longer in flight from the first listener on, so a read queued
    // behind this one (registered after it) is sent, not joined to it.
    void ended() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }

    future.then((snap) {
      ended();
      _last[key] = snap;
      _backoff.remove(key);
      _backingOff.remove(key)?.cancel();
    }, onError: (Object _) {
      ended();
      failed++;
      final before = _backoff[key] ?? Duration.zero;
      final next = before == Duration.zero
          ? backoffStart
          : (before * 2 > backoffCap ? backoffCap : before * 2);
      _backoff[key] = next;
      _backingOff.remove(key)?.cancel();
      _backingOff[key] = Timer(next, () => _backingOff.remove(key));
    });
    return future;
  }

  /// Whether the fresh read for [address] is backing off now.
  bool backingOff(String address) =>
      _backingOff.containsKey(address.toLowerCase());

  /// The backoff the next failure of [address] would extend (tests).
  @visibleForTesting
  Duration backoffOf(String address) =>
      _backoff[address.toLowerCase()] ?? Duration.zero;

  /// The last completed read of [address], if any.
  HlAccountSnapshot? lastOf(String address) =>
      _last[address.toLowerCase()];
}

class HlAccountNotifier extends AutoDisposeAsyncNotifier<HlAccountSnapshot> {
  Timer? _timer;

  /// This account's shared reads ([HlAccountReads]).
  @visibleForTesting
  final HlAccountReads reads = HlAccountReads();
  int _currentIntervalSecs = kHlIdleIntervalSecs;

  /// Test-only: the cadence currently in force, seconds.
  @visibleForTesting
  int get debugIntervalSecs => _currentIntervalSecs;
  bool _disposed = false;
  String? _address;

  @override
  Future<HlAccountSnapshot> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });

    // Placement activity drives the adaptive cadence: a new in-flight
    // order drops the poll to 5 s and forces an immediate tick so the
    // fresh position lands (and the placing tile reconciles) fast.
    // Registered before any await — ref.listen must run synchronously
    // within build.
    ref.listen(placingHyperliquidOrderProvider, (prev, next) {
      _applyCadence();
      if ((prev == null || prev.isEmpty) && next.isNotEmpty) {
        unawaited(_silentRefresh());
      }
    });
    // A deposit on its way into HyperCore drops the poll to 4 s until the
    // Orchestra row settles (the background sync flips it), so the credit
    // lands on screen within one short poll. A new pending deposit also
    // forces a tick straight away.
    ref.listen(pendingTradingDepositUsdProvider, (prev, next) {
      _applyCadence();
      if ((prev ?? 0) <= 0 && next > 0) {
        unawaited(_silentRefresh());
      }
    });

    final address = await ref.watch(hyperliquidAddressProvider.future);
    _address = address;
    if (address == null) return HlAccountSnapshot.empty;

    // Timer starts before the first fetch so a failed initial load
    // (error state) still self-heals on the next tick instead of
    // sticking until something re-watches the provider.
    _startTimer();
    final model = ref.read(hyperliquidTradingModelProvider);
    // A build is the first read or follows an invalidation (a fill, a
    // ledger push, an action answered): never answered by a read sent
    // before it, never by the credit watch's light one.
    final snap = await reads.read(
        address, () => model.getPortfolioSnapshot(address),
        after: true);
    _reconcilePlacements(snap);
    _publishPositions(snap);
    _noteCredit(address, snap);
    // The first snapshot is in: an account holding nothing stops polling.
    _applyCadence(snap);
    return snap;
  }

  int _targetIntervalSecs(HlAccountSnapshot? snap) {
    final depositPending = _depositPending();
    if (depositPending) return kHlDepositPendingIntervalSecs;
    final placing = ref.read(placingHyperliquidOrderProvider).isNotEmpty;
    final hasPositions = (snap?.positions.isNotEmpty ?? false);
    if (placing || hasPositions) return kHlActiveIntervalSecs;
    // Not loaded yet: keep the retry tick. Spot tokens held: their value
    // moves, keep the idle read. Nothing held: no poll.
    if (snap == null) return kHlIdleIntervalSecs;
    final holdsSpot =
        snap.spotBalances.any((b) => b.coin != 'USDC' && b.total > 0);
    return holdsSpot ? kHlIdleIntervalSecs : kHlNoPollIntervalSecs;
  }

  bool _depositPending() {
    try {
      return ref.read(pendingTradingDepositUsdProvider) > 0;
    } catch (_) {
      return false;
    }
  }

  void _applyCadence([HlAccountSnapshot? snap]) {
    if (_disposed) return;
    final target = _targetIntervalSecs(snap ?? state.valueOrNull);
    if (target == _currentIntervalSecs && (_timer != null) == (target > 0)) {
      return;
    }
    _currentIntervalSecs = target;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = _currentIntervalSecs <= 0
        ? null
        : Timer.periodic(
            Duration(seconds: _currentIntervalSecs),
            (_) {
              if (!OrderPollGate.paused) _silentRefresh();
            },
          );
  }

  /// [now]: the caller needs the account as it is from this moment
  /// ([refresh]); the poll and the cadence listeners take a read sent
  /// within the last second, or the one in flight.
  Future<void> _silentRefresh({bool now = false}) async {
    if (_disposed) return;
    final address = _address;
    if (address == null) return;
    try {
      final model = ref.read(hyperliquidTradingModelProvider);
      final snap = await reads.read(
          address, () => model.getPortfolioSnapshot(address),
          reuse: !now, after: now);
      if (_disposed) return;
      _take(address, snap);
      _applyCadence();
    } catch (_) {
      // Silent — keep the last snapshot on a background refresh failure.
    }
  }

  void _take(String address, HlAccountSnapshot snap) {
    _reconcilePlacements(snap);
    _publishPositions(snap);
    _noteCredit(address, snap);
    final current = state.valueOrNull;
    // Value-equality short-circuit: identical snapshots don't notify.
    if (current == null || !hlAccountSnapshotEquals(current, snap)) {
      state = AsyncData(snap);
    }
  }

  /// A FRESH read of the account for a queued order waiting on its credit
  /// (the autofire's 1 s tick for the first 30 s after funding), not the
  /// cached snapshot: shared through [HlAccountReads] (joins a read in
  /// flight, takes one completed within the last second, never two in the
  /// same second with the ledger push or the poll), the builder DEXs'
  /// part reused ([HyperliquidModel.getCreditSnapshot], weight 4). While
  /// it backs off after a failure (a 429 included) no request goes: the
  /// last snapshot answers and `sent` is false. Throws only when nothing
  /// was ever read.
  ///
  /// [reuse] false (a ledger push or a credit just said the money moved):
  /// neither a read completed before it nor the one in flight answers;
  /// one read is sent behind the one in flight ([HlAccountReads.read]).
  Future<({HlAccountSnapshot snap, bool sent, bool failed})> freshRead(
      {bool reuse = true}) async {
    final address = _address;
    final current = state.valueOrNull;
    if (address == null) {
      // Not built yet (or rebuilding): its own build is the read.
      return (snap: await future, sent: false, failed: false);
    }
    if (reads.backingOff(address)) {
      final last = current ?? reads.lastOf(address);
      if (last != null) return (snap: last, sent: false, failed: false);
    }
    final model = ref.read(hyperliquidTradingModelProvider);
    try {
      final snap = await reads.read(
          address, () => model.getCreditSnapshot(address),
          reuse: reuse, after: !reuse, light: true);
      if (!_disposed) _take(address, snap);
      return (snap: snap, sent: true, failed: false);
    } catch (_) {
      final last = current ?? reads.lastOf(address);
      if (last == null) rethrow;
      return (snap: last, sent: true, failed: true);
    }
  }

  /// The last account read and whose it was, for [_noteCredit].
  HlAccountSnapshot? _lastRead;
  String? _lastReadAddress;

  /// The account's cash read higher than the read before it while a move
  /// into Investing is on its way, with nothing held that moves that cash
  /// on its own ([VenueArrivals.investingCreditBetween]): the move it
  /// stands for is marked arrived, as the venue's ledger socket does
  /// (the same credit seen by both is taken once). Covers an account
  /// whose socket is not open (one that never traded).
  void _noteCredit(String address, HlAccountSnapshot snap) {
    final before = _lastRead;
    final sameAccount =
        _lastReadAddress?.toLowerCase() == address.toLowerCase();
    _lastRead = snap;
    _lastReadAddress = address;
    if (before == null || !sameAccount) return;
    try {
      final usd = VenueArrivals.investingCreditBetween(before, snap);
      if (usd == null) return;
      final rows = ref.read(swapOrdersProvider);
      if (!VenueArrivals.investingOnTheWay(rows, account: address)) return;
      final row =
          VenueArrivals.investingArrived(rows, account: address, usd: usd);
      // The move landed: its source reads again, with Investing.
      if (row != null) {
        MoveSettledRefresh.settledRow(row, source: 'hypercore_credit');
      }
    } catch (_) {}
  }

  /// Hands the fresh positions to the trade alerts (liquidation risk,
  /// funding), which run app-wide on the slower badge poll otherwise.
  void _publishPositions(HlAccountSnapshot snap) {
    try {
      final held = ref.read(hyperliquidHeldPositionsProvider.notifier);
      if (!hlPerpPositionListEquals(held.state, snap.positions)) {
        held.state = snap.positions;
      }
    } catch (_) {}
  }

  void _reconcilePlacements(HlAccountSnapshot snap) {
    try {
      ref
          .read(placingHyperliquidOrderProvider.notifier)
          .reconcileWithPositions(snap.positions);
    } catch (_) {
      // Reconcile is a UX nicety — never let it break the fetch path.
    }
  }

  /// One immediate refetch — called by the trading notifier after every
  /// exchange action and by the user-events provider on WS fills (which
  /// also `ref.invalidate`s; this method exists for callers that want to
  /// keep the notifier's timers intact). The order slip calls it at
  /// Confirm to size the order on the cash that is there NOW, and a
  /// settled move to show where its money went: the venue is read from
  /// this call on, never answered by a read sent before it.
  Future<void> refresh() => _silentRefresh(now: true);
}

/// Perp clearinghouse summary + open positions + spot balances, polled
/// adaptively (5 s active / 15 s idle — see file header).
final hyperliquidAccountProvider =
    AsyncNotifierProvider.autoDispose<HlAccountNotifier, HlAccountSnapshot>(
  HlAccountNotifier.new,
);

/// Separate from execution: cached account figures may only feed display.
final hyperliquidDisplayCacheKeyProvider = Provider<String?>((ref) {
  final identity = ref.watch(settingsProvider.select(_spendingEvmIdentity));
  if (identity.$1 == null) return null;
  return '${identity.$1}:${identity.$2?.storageValue}';
});

/// Retains known balances and positions across refreshes and app runs.
/// A failed read never replaces the cache; a successful empty response does.
final hyperliquidDisplayAccountProvider =
    Provider.autoDispose<AsyncValue<HlAccountSnapshot>>((ref) {
  final key = ref.watch(hyperliquidDisplayCacheKeyProvider);
  if (key == null) return const AsyncLoading();
  return ref.watch(hyperliquidDisplayAccountSnapshotProvider(key));
});

/// A family keeps Riverpod's previous-data retention inside this wallet's
/// identity; switching wallets must never expose the previous wallet's rows.
final hyperliquidDisplayAccountSnapshotProvider = FutureProvider.autoDispose
    .family<HlAccountSnapshot, String>((ref, key) async {
  final fresh = ref.watch(hyperliquidAccountProvider);
  final resolved = ref.watch(hyperliquidAddressProvider);
  final address = resolved.valueOrNull;
  if (!fresh.isLoading &&
      !fresh.hasError &&
      !resolved.isLoading &&
      address != null &&
      fresh.hasValue) {
    final snapshot = fresh.requireValue;
    unawaited(HyperliquidAccountCache.write(
        key, HlCachedAccount(address: address, snapshot: snapshot)));
    return snapshot;
  }
  final cached = await HyperliquidAccountCache.open(key);
  if (cached != null &&
      (address == null ||
          cached.address.toLowerCase() == address.toLowerCase())) {
    return cached.snapshot;
  }
  return ref.watch(hyperliquidAccountProvider.future);
});

// ───────────────────────── derived views ─────────────────────────

/// Open perp positions (empty while loading / on error / flat account).
final hyperliquidPerpPositionsProvider =
    Provider.autoDispose<List<HlPerpPosition>>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.positions ??
      const [];
});

/// Perp USDC available for withdrawal / new margin, USD.
final hyperliquidWithdrawableProvider = Provider.autoDispose<double>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.withdrawable ?? 0;
});

/// Spot token balances (includes the USDC row).
final hyperliquidSpotBalancesProvider =
    Provider.autoDispose<List<HlSpotBalance>>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.spotBalances ??
      const [];
});

// ───────────────────────── badge count ─────────────────────────

class HlOpenPositionsCountNotifier extends Notifier<int> {
  Timer? _timer;
  bool _fetching = false;
  String? _cachedAddress;

  @override
  int build() {
    // Rebuild (and reset the cached address) on wallet switch.
    ref.watch(settingsProvider.select(_spendingEvmIdentity));
    _cachedAddress = null;

    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!OrderPollGate.paused) unawaited(_tick());
    });
    unawaited(_tick());
    return 0;
  }

  /// One tick now, for a pull-to-refresh (`refresh_everything_provider`):
  /// the once-flag, the free USDC and the held positions read again
  /// without waiting for the 60 s poll.
  Future<void> refreshNow() => _tick();

  Future<void> _tick() async {
    if (_fetching) return;
    _fetching = true;
    try {
      // Yield one microtask first: build() kicks the initial _tick
      // synchronously, and writing `state` before build returns throws.
      await Future<void>.value();
      final settings = ref.read(settingsProvider);
      final spending = pickSpendingWallet(settings);
      if (spending == null) {
        state = 0;
        ref.read(hyperliquidFreeUsdcProvider.notifier).state = 0;
        ref.read(hyperliquidProvisionedProvider.notifier).state = false;
        ref.read(hyperliquidHeldPositionsProvider.notifier).state = const [];
        return;
      }

      // Once-flag gate: 'hl_enabled_<walletId>' is written by
      // provisionHyperliquidAccount the first time this wallet trades.
      // Until then every tick is this LOCAL read and nothing else — no
      // address derivation, no network. Re-checked each tick so a user
      // who enables trading mid-session starts counting within 60 s.
      final enabled = await HyperliquidOnboardingService.isEnabled(spending.id);
      if (!enabled) {
        state = 0;
        ref.read(hyperliquidFreeUsdcProvider.notifier).state = 0;
        ref.read(hyperliquidProvisionedProvider.notifier).state = false;
        ref.read(hyperliquidHeldPositionsProvider.notifier).state = const [];
        return;
      }
      ref.read(hyperliquidProvisionedProvider.notifier).state = true;

      final address =
          _cachedAddress ??= await ref.read(hyperliquidAddressProvider.future);
      if (address == null) return;

      final model = ref.read(hyperliquidTradingModelProvider);
      final snap = await model.getPortfolioSnapshot(address);
      unawaited(HyperliquidAccountCache.write(
        '${spending.id}:${spending.evmDerivationVersion.storageValue}',
        HlCachedAccount(address: address, snapshot: snap),
      ));
      final spotHoldings = snap.spotBalances
          .where((b) => b.coin != 'USDC' && b.total > 0)
          .length;
      final count = snap.positions.length + spotHoldings;
      if (count != state) state = count;
      final held = ref.read(hyperliquidHeldPositionsProvider.notifier);
      if (!hlPerpPositionListEquals(held.state, snap.positions)) {
        held.state = snap.positions;
      }

      // Piggyback the unified-USDC number on this same poll so the home
      // balance never spins up the full trading stack. Free cash only
      // (perp withdrawable + unheld spot USDC) — margin locked in open
      // positions is portfolio value, not spendable balance, matching
      // polymarketBalanceProvider's semantics.
      final spotUsdc = snap.spotBalances
          .where((b) => b.coin == 'USDC')
          .fold<double>(0, (sum, b) => sum + b.available);
      ref.read(hyperliquidFreeUsdcProvider.notifier).state =
          snap.withdrawable + spotUsdc;
    } catch (_) {
      // Keep the last-known count on transient failures.
    } finally {
      _fetching = false;
    }
  }
}

/// Open perp positions + non-USDC spot holdings. NOT autoDispose — the
/// venue sweeper listens to it for the whole session (it is what fills
/// [hyperliquidProvisionedProvider] and [hyperliquidFreeUsdcProvider],
/// whatever browse/trade/deposit the policy allows) — and deliberately
/// independent of [hyperliquidAccountProvider] so keeping it alive
/// never spins up the full trading stack: its own
/// 60 s poll only touches the network for wallets that have actually
/// provisioned Hyperliquid (see the once-flag gate in [_tick]).
final hyperliquidOpenPositionsCountProvider =
    NotifierProvider<HlOpenPositionsCountNotifier, int>(
  HlOpenPositionsCountNotifier.new,
);

/// Hyperliquid free USDC (perp withdrawable + unheld spot USDC) for the
/// unified `usdcBalanceProvider`. Written by [HlOpenPositionsCountNotifier]'s
/// 60 s tick — same once-flag gating, zero extra network. NOT autoDispose
/// for the same reason as the badge count: the home balance watches it
/// permanently. While a Hyperliquid surface is open the trading provider's
/// 5–15 s snapshot is fresher; this one is the always-on coarse number.
final hyperliquidFreeUsdcProvider = StateProvider<double>((_) => 0);

/// The spending wallet's open perp positions, from whichever poll ran
/// last: the 5 s account poll while an Investing surface is open, else the
/// 60 s badge poll. Read by the app-wide trade alerts (liquidation risk,
/// funding); NOT autoDispose, and empty for wallets that never traded.
final hyperliquidHeldPositionsProvider =
    StateProvider<List<HlPerpPosition>>((_) => const []);

/// The spending wallet has provisioned Hyperliquid (the badge poll's
/// once-flag gate). The trade alerts keep the user-events socket open
/// only while this is true.
final hyperliquidProvisionedProvider = StateProvider<bool>((_) => false);
