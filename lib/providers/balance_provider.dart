// lib/providers/balance_provider.dart
//
// Per-wallet balance state. The wallet balance cache is the source
// of truth — both the active-wallet `balanceNotifierProvider` and
// the per-wallet `balanceForWalletProvider` read from it. Writes
// always target a specific walletId, so stream / poll callbacks
// that started before a wallet swap can't clobber the new wallet's
// state.
//
// History: this file used to hold a single active-wallet notifier
// that was rebuilt on every `activeWalletId` change. Sync writes
// targeted that one notifier — and after `await`s the active wallet
// might have changed, so the previous wallet's balance was written
// to the new wallet. Receives that arrived during a swap window
// silently disappeared. The cache-as-truth refactor makes those
// races impossible.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/services/wallet_balance_cache_service.dart';

/// Source of a balance update. The Breez wallet-info stream is
/// push-based and authoritative; the 5s poll re-reads via `getInfo()`
/// and can race a just-landed deposit, returning the pre-deposit
/// value. When the stream has fired recently, poll writes that
/// REGRESS the value are dropped to avoid flicker — a higher poll
/// value (incoming payment the stream might have missed) always
/// wins.
enum BalanceSource { stream, poll }

final balanceChangeProvider = StateProvider<BalanceChange?>((ref) => null);

/// In-memory cache of every wallet's balance, hydrated from Hive on
/// boot and written-through on every update. Drives the wallet
/// picker, home carousel, analytics, and (transitively) the
/// active-wallet `balanceNotifierProvider`.
final walletBalanceCacheProvider =
    StateNotifierProvider<WalletBalanceCacheNotifier, Map<String, WalletBalance>>(
        (ref) {
  return WalletBalanceCacheNotifier();
});

/// Active-wallet view of the balance cache. Equivalent to
/// `cache[settings.activeWalletId]` but exposes the same
/// `.notifier` API the codebase already uses for backwards
/// compatibility — the notifier forwards every write to the cache,
/// keyed by the *current* active wallet id at write time.
final balanceNotifierProvider =
    StateNotifierProvider<ActiveBalanceNotifier, WalletBalance>((ref) {
  return ActiveBalanceNotifier(ref);
});

/// Per-wallet read-side family. Use this when you need a specific
/// wallet's balance regardless of which wallet is currently active —
/// the cards in the picker, the cross-wallet Move sheet, etc.
final balanceForWalletProvider =
    Provider.family<WalletBalance, String>((ref, walletId) {
  final cache = ref.watch(walletBalanceCacheProvider);
  return cache[walletId] ?? WalletBalance.empty();
});

/// Read-side projection for the wallet the user is currently looking
/// at on the carousel — the display counterpart to
/// [balanceNotifierProvider]. Decoupled from `activeWalletId` so
/// swiping between wallets repaints the balance card immediately
/// (no 250 ms lag against the operational `activeWalletId` debounce).
/// Falls back to the active-wallet notifier when the viewed id
/// isn't yet set or has no cache entry.
final viewedWalletBalanceProvider = Provider<WalletBalance>((ref) {
  final viewedId = ref.watch(viewedWalletIdProvider);
  if (viewedId == null) return ref.watch(balanceNotifierProvider);
  final activeId =
      ref.watch(settingsProvider.select((s) => s.activeWalletId));
  // Viewing the active wallet → live notifier is authoritative.
  if (viewedId == activeId) return ref.watch(balanceNotifierProvider);
  // Viewing a non-active wallet (e.g. hardware xpub from the
  // portfolio): return its cache or EMPTY. Falling back to the
  // active wallet's balance here bled the spending wallet's
  // sats + history onto cold-wallet detail screens and the 1M
  // chart, even when the cold wallet was freshly imported with
  // no balance.
  final cache = ref.watch(walletBalanceCacheProvider);
  return cache[viewedId] ?? WalletBalance.empty();
});

/// An outgoing bitcoin send from the spending wallet that the Breez SDK
/// has accepted but whose deduction its `getInfo()` may not show yet.
///
/// Why this exists: on the client runtime `getInfo().balanceSats` is a
/// CACHED figure (`CachedAccountInfo`) that the SDK refreshes only on
/// `PaymentSucceeded`, a claimed deposit, an incoming payment, or its own
/// wallet sync (every 60 s, checked every 10 s). A send that is accepted
/// as PENDING (an on-chain exit always is, a Lightning send can be)
/// emits `PaymentPending`, which does not refresh that cache, so for up
/// to a minute or more `getInfo()` still counts the coins that already
/// left. The hold shows the committed figure meanwhile.
///
/// A hold only ever lowers the shown figure by its own send: money that
/// arrives while it is live raises its ceiling (see
/// `noteSparkReceives`), and it ends as soon as the send completes or
/// fails.
class _SparkSendHold {
  _SparkSendHold({
    required this.ceilingSats,
    required this.feeSats,
    required this.sdkSatsAtSend,
    required this.placedAt,
  });

  /// The most the wallet can hold once this send is out: the balance
  /// shown before it, less what it takes, never below 0, plus every
  /// receive that settled after the send.
  int ceilingSats;

  /// The fee part of the debit. The SDK may charge less (a re-quoted
  /// on-chain exit steps down, a Lightning route comes in cheaper), so
  /// an SDK figure within this much of [ceilingSats] already shows it.
  final int feeSats;

  /// What the SDK reported when the send was accepted, i.e. the stale
  /// figure that still counts the send.
  final int sdkSatsAtSend;

  final DateTime placedAt;
  DateTime? completedAt;

  /// Whether a receive at [at] settled after this send was placed.
  /// Payment times are whole seconds, so the send's own second counts
  /// as after.
  bool settledAfterPlaced(DateTime at) =>
      at.millisecondsSinceEpoch >= placedAt.millisecondsSinceEpoch ~/ 1000 * 1000;
}

class WalletBalanceCacheNotifier
    extends StateNotifier<Map<String, WalletBalance>> {
  WalletBalanceCacheNotifier({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(WalletBalanceCacheService.readAll());

  final DateTime Function() _clock;

  /// The Spark balance as the SDK last reported it, per wallet, before
  /// any pending-send hold. The shown `sparkBitcoinbalance` is this,
  /// capped by the holds below. Absent until the SDK reports once.
  final Map<String, int> _sparkSdkSats = {};

  /// Accepted outgoing sends per wallet, keyed by SDK payment id.
  final Map<String, Map<String, _SparkSendHold>> _sparkSendHolds = {};

  /// Settled incoming bitcoin payments already seen per wallet, so each
  /// one raises the live holds' ceilings once. See [noteSparkReceives].
  final Map<String, Set<String>> _sparkReceivesSeen = {};

  /// Ends a wallet's holds on time even when no balance write follows
  /// (off the sync routes nothing re-reads the balance every 2 s, and a
  /// capped figure must not outlive its hold).
  final Map<String, Timer> _sendHoldTimers = {};

  /// When the SDK's own Spark figure last went UP per wallet, i.e. when
  /// it last counted a receive. Read by the push pipeline's receive
  /// catch-up to tell whether the balance moved with a new receive.
  final Map<String, DateTime> _sparkSdkRaisedAt = {};

  /// A hold never outlives this, whatever else happens: after it the
  /// SDK figure wins again.
  static const _sendHoldMaxAge = Duration(minutes: 15);

  /// A completed send's hold ends at once: `PaymentSucceeded` has
  /// refreshed the SDK's balance and the app re-reads it before the
  /// payments list shows the send completed. Only when the SDK still
  /// reports exactly the pre-send figure (a read that raced that
  /// refresh) does the hold stay, for at most this long. It cannot hide
  /// a receive: any change in the SDK figure ends it, and receives the
  /// SDK has not counted yet raise its ceiling.
  static const _sendHoldCompletedGrace = Duration(seconds: 30);

  /// 5s window during which a stream-sourced value blocks a *lower*
  /// poll value from overwriting it. Was 15s; tightened so a missed
  /// stream event doesn't hide an incoming payment for too long.
  static const _streamTrustWindow = Duration(seconds: 5);

  /// Per-wallet stream freshness tracking. Each wallet's stream
  /// listener fires independently — pinning this to a single global
  /// timestamp leaked one wallet's stream-fresh state onto the
  /// others.
  final Map<String, DateTime> _lastStreamUpdate = {};

  /// Wallets whose next poll write should bypass the stream-fresh
  /// guard regardless of value direction. Set by Receive screens so
  /// the inevitable post-receive poll lands even if a stream value
  /// arrived right before. **Time-bounded** — the receive screen's
  /// 5 s tick re-arms this every cycle, and previously the bypass
  /// stayed armed for the screen's lifetime, blanket-licensing every
  /// regressing poll write (including stale SDK re-reads mid-reconcile
  /// on a fresh wallet's first receive). The 2 s window means the
  /// next poll after `primePoll` consumes it, and any subsequent
  /// regressing write must justify itself through the normal guard.
  final Map<String, DateTime> _bypassStreamFreshUntil = {};
  static const _bypassWindow = Duration(seconds: 2);

  /// Wallets that currently have a pending outgoing Spark payment in
  /// flight. While set, the Spark BTC balance is allowed to go DOWN
  /// (deduction landed) but never back UP — Spark's
  /// `walletInfoStream` periodically re-emits a stale pre-deduction
  /// balance during the pending window, which previously caused the
  /// home card balance to bounce between deducted and pre-send right
  /// up until confirmation. Set/cleared by the push pipeline based
  /// on `paymentsStream` state. See [setPendingOutgoingSparkSend].
  final Set<String> _pendingOutgoingSparkSend = {};

  /// Grace-window expiry for the pin. When the push pipeline reports
  /// "no more pending outgoing", we don't drop the pin immediately —
  /// the SDK's `walletInfoStream` can re-emit a stale pre-send value
  /// microseconds later. Holding the pin for [_pinHoldWindow] after
  /// the clear-call guarantees those late re-emissions still get
  /// blocked. See [_pinActive].
  final Map<String, DateTime> _pinHoldUntil = {};
  static const _pinHoldWindow = Duration(seconds: 3);

  bool _isStreamFresh(String walletId) {
    final last = _lastStreamUpdate[walletId];
    if (last == null) return false;
    return _clock().difference(last) < _streamTrustWindow;
  }

  /// When the Spark BTC balance last INCREASED (a receive). Used to
  /// suppress the SDK's transient post-receive poll 0 (see the
  /// zero-clobber guard) — but ONLY while a receive is recent. CLEARED
  /// on any balance decrease and when an outgoing send starts, so a
  /// genuine max-send-to-0 is never suppressed.
  final Map<String, DateTime> _lastReceiveAt = {};
  static const _receiveReconcileWindow = Duration(seconds: 90);

  bool _recentlyReceived(String walletId) {
    final last = _lastReceiveAt[walletId];
    if (last == null) return false;
    return _clock().difference(last) < _receiveReconcileWindow;
  }

  /// Bypass the stream-fresh guard for [walletId]'s next poll write.
  /// Auto-expires after [_bypassWindow] so a periodic re-prime can't
  /// blanket-license stale regressions for the lifetime of a screen.
  void primePoll(String walletId) {
    _bypassStreamFreshUntil[walletId] = _clock().add(_bypassWindow);
  }

  /// Returns true (and consumes the bypass) if [walletId] is within
  /// its primePoll window. Used at every guard site that would
  /// otherwise drop a regressing poll write.
  bool _consumeBypass(String walletId) {
    final until = _bypassStreamFreshUntil[walletId];
    if (until == null) return false;
    if (_clock().isAfter(until)) {
      _bypassStreamFreshUntil.remove(walletId);
      return false;
    }
    _bypassStreamFreshUntil.remove(walletId);
    return true;
  }

  void invalidateStreamFreshness(String walletId) {
    _lastStreamUpdate.remove(walletId);
    _bypassStreamFreshUntil[walletId] =
        _clock().add(_bypassWindow);
  }

  /// Mark / unmark that a wallet currently has at least one outgoing
  /// Spark payment in flight. While set, the Spark BTC balance is
  /// pinned non-increasing — i.e. once a deduction lands, a stale
  /// stream re-fire with the pre-deduct value can't push it back up.
  /// USDB and on-chain BTC slots are untouched. Driven by the push
  /// pipeline's `paymentsStream` listener.
  ///
  /// Clearing the pin doesn't immediately drop the protection — a
  /// [_pinHoldWindow] grace prevents stale stream re-emissions that
  /// land microseconds after the SDK reports no-pending from
  /// undoing the drain on screen.
  void setPendingOutgoingSparkSend(String walletId, bool active) {
    if (active) {
      _pendingOutgoingSparkSend.add(walletId);
      _pinHoldUntil.remove(walletId);
      // A send is starting — disarm the post-receive 0-guard so the
      // deduction (possibly all the way to 0) is never suppressed.
      _lastReceiveAt.remove(walletId);
    } else {
      _pinHoldUntil[walletId] = _clock().add(_pinHoldWindow);
      // Keep the wallet in the set; _pinActive resolves both flags.
    }
  }

  /// Whether [walletId] still has its pending-outgoing pin active —
  /// either because `paymentsStream` reports pending, or because the
  /// post-clear grace window hasn't elapsed yet. Lazy-cleans expired
  /// entries from both maps.
  bool _pinActive(String walletId) {
    if (!_pendingOutgoingSparkSend.contains(walletId)) return false;
    final until = _pinHoldUntil[walletId];
    if (until == null) return true; // active and not yet cleared
    if (_clock().isBefore(until)) return true; // in grace window
    _pendingOutgoingSparkSend.remove(walletId);
    _pinHoldUntil.remove(walletId);
    return false;
  }


  /// The Spark balance shown for [walletId] right now (holds applied).
  /// Callers snapshot it just before a send so its hold starts from what
  /// the person saw, including any earlier send still pending.
  int shownSparkSats(String walletId) =>
      state[walletId]?.sparkBitcoinbalance ?? 0;

  /// The Spark balance as the SDK last reported it for [walletId],
  /// before any send hold.
  int sparkSdkSats(String walletId) =>
      _sparkSdkSats[walletId] ?? shownSparkSats(walletId);

  /// When [walletId]'s SDK Spark figure last went up (a receive the SDK
  /// counted), or null when it has not this session.
  DateTime? sparkSdkRaisedAt(String walletId) => _sparkSdkRaisedAt[walletId];

  /// Shows an accepted outgoing send in [walletId]'s balance at once:
  /// the balance becomes [balanceBeforeSats] less [debitSats] (amount
  /// plus fee, or the whole amount when the fee comes out of it), never
  /// below 0, until the SDK's own figure shows the send.
  ///
  /// [key] is the SDK payment id, so the payments stream can release the
  /// hold when the send fails (the SDK figure, refund included, shows
  /// again) or completes. Nothing is held when the SDK figure already
  /// shows the send.
  void holdOutgoingSparkSend(
    String walletId, {
    required String key,
    required int balanceBeforeSats,
    required int debitSats,
    required int feeSats,
  }) {
    if (walletId.isEmpty || key.isEmpty || debitSats <= 0) return;
    // A send is starting: the post-receive 0-guard must never hide its
    // deduction (same as `setPendingOutgoingSparkSend`).
    _lastReceiveAt.remove(walletId);
    final current = state[walletId] ?? WalletBalance.empty();
    final sdkSats = _sparkSdkSats[walletId] ?? current.sparkBitcoinbalance;
    final before = balanceBeforeSats < 0 ? 0 : balanceBeforeSats;
    final ceiling = before > debitSats ? before - debitSats : 0;
    final fee = feeSats < 0 ? 0 : feeSats;
    if (sdkSats <= ceiling + fee) {
      // The SDK figure already shows this send.
      _refreshSparkShown(walletId);
      return;
    }
    _sparkSdkSats[walletId] = sdkSats;
    (_sparkSendHolds[walletId] ??= {})[key] = _SparkSendHold(
      ceilingSats: ceiling,
      feeSats: fee,
      sdkSatsAtSend: sdkSats,
      placedAt: _clock(),
    );
    _refreshSparkShown(walletId);
  }

  /// Applies an SDK balance read taken after a forced wallet sync that
  /// followed the send [key]. That read already counts the send, so the
  /// hold ends and the SDK figure is shown. A read that still equals the
  /// figure from before the send is taken as not yet refreshed and keeps
  /// the hold.
  void settleOutgoingSparkSend(String walletId, String key, int sdkSats) {
    final hold = _sparkSendHolds[walletId]?[key];
    if (hold != null &&
        sdkSats == hold.sdkSatsAtSend &&
        sdkSats > hold.ceilingSats + hold.feeSats) {
      return;
    }
    _sparkSendHolds[walletId]?.remove(key);
    updateSparkBitcoinbalance(walletId, sdkSats,
        source: BalanceSource.stream);
    _refreshSparkShown(walletId);
  }

  /// Payment states from the SDK payments stream for [walletId]'s sends.
  /// A failed send's hold ends at once (the SDK figure, refund included,
  /// shows again). So does a completed one, unless the SDK still reports
  /// exactly the pre-send figure; then it ends when that figure moves, or
  /// after [_sendHoldCompletedGrace].
  void reconcileSparkSendHolds(
    String walletId, {
    required Set<String> failed,
    required Set<String> completed,
  }) {
    final holds = _sparkSendHolds[walletId];
    if (holds == null || holds.isEmpty) return;
    holds.removeWhere((key, _) => failed.contains(key));
    final now = _clock();
    for (final entry in holds.entries) {
      if (completed.contains(entry.key)) entry.value.completedAt ??= now;
    }
    _refreshSparkShown(walletId);
  }

  /// Settled incoming bitcoin payments of [walletId], as the transaction
  /// list has them. A receive that settled after a send was placed
  /// raises that send's ceiling by its amount, so money that arrives
  /// while a send is pending shows at once, with the send still taken
  /// off. The SDK figure still caps the shown one, so a receive is never
  /// counted twice once the SDK has it. Each receive counts once; one
  /// that settled before the send is already in the balance it started
  /// from.
  void noteSparkReceives(
    String walletId,
    Iterable<({String id, int sats, DateTime at})> receives,
  ) {
    if (walletId.isEmpty) return;
    final seen = _sparkReceivesSeen[walletId] ??= <String>{};
    final holds = _sparkSendHolds[walletId];
    var raised = false;
    for (final r in receives) {
      if (!seen.add(r.id)) continue;
      if (holds == null || r.sats <= 0) continue;
      for (final h in holds.values) {
        if (!h.settledAfterPlaced(r.at)) continue;
        h.ceilingSats += r.sats;
        raised = true;
      }
    }
    if (raised) _refreshSparkShown(walletId);
  }

  /// Whether [walletId] has an accepted send whose deduction the SDK
  /// figure does not show yet.
  bool hasSparkSendHold(String walletId) {
    _sparkShown(walletId,
        _sparkSdkSats[walletId] ?? state[walletId]?.sparkBitcoinbalance ?? 0);
    return _sparkSendHolds[walletId]?.isNotEmpty ?? false;
  }

  /// The shown figure for an SDK figure [sdkSats]: capped by every live
  /// hold. Drops the holds that have ended.
  int _sparkShown(String walletId, int sdkSats) {
    final holds = _sparkSendHolds[walletId];
    if (holds == null || holds.isEmpty) return sdkSats;
    final now = _clock();
    holds.removeWhere((_, h) =>
        sdkSats <= h.ceilingSats + h.feeSats ||
        now.difference(h.placedAt) >= _sendHoldMaxAge ||
        (h.completedAt != null &&
            (sdkSats != h.sdkSatsAtSend ||
                now.difference(h.completedAt!) >= _sendHoldCompletedGrace)));
    if (holds.isEmpty) {
      _sparkSendHolds.remove(walletId);
      _sendHoldTimers.remove(walletId)?.cancel();
      return sdkSats;
    }
    _armSendHoldExpiry(walletId, holds.values, now);
    var shown = sdkSats;
    for (final h in holds.values) {
      if (h.ceilingSats < shown) shown = h.ceilingSats;
    }
    return shown < 0 ? 0 : shown;
  }

  /// Re-evaluates [walletId]'s holds when the first of them expires, so
  /// the capped figure gives way on time without another balance write.
  void _armSendHoldExpiry(
      String walletId, Iterable<_SparkSendHold> holds, DateTime now) {
    DateTime? next;
    for (final h in holds) {
      var end = h.placedAt.add(_sendHoldMaxAge);
      final completedAt = h.completedAt;
      if (completedAt != null) {
        final graceEnd = completedAt.add(_sendHoldCompletedGrace);
        if (graceEnd.isBefore(end)) end = graceEnd;
      }
      if (next == null || end.isBefore(next)) next = end;
    }
    if (next == null) return;
    final wait = next.difference(now);
    _sendHoldTimers.remove(walletId)?.cancel();
    _sendHoldTimers[walletId] =
        Timer(wait.isNegative ? Duration.zero : wait, () {
      _sendHoldTimers.remove(walletId);
      if (mounted) _refreshSparkShown(walletId);
    });
  }

  void _refreshSparkShown(String walletId) {
    final current = state[walletId] ?? WalletBalance.empty();
    final sdkSats = _sparkSdkSats[walletId] ?? current.sparkBitcoinbalance;
    final shown = _sparkShown(walletId, sdkSats);
    if (shown == current.sparkBitcoinbalance) return;
    _put(walletId, current.copyWith(sparkBitcoinbalance: shown));
  }

  void updateOnChainBtcBalance(String walletId, int sats) {
    final current = state[walletId] ?? WalletBalance.empty();
    if (current.onChainBtcBalance == sats) return;
    _put(walletId, current.copyWith(onChainBtcBalance: sats));
  }

  void updateSparkBitcoinbalance(
    String walletId,
    int sats, {
    BalanceSource source = BalanceSource.poll,
  }) {
    final current = state[walletId] ?? WalletBalance.empty();
    // Guards compare against the SDK's own last figure, not the shown
    // one: while a send hold caps the shown balance, a stale re-read of
    // the pre-send SDK figure is "no change", not an increase.
    final currentSdk = _sparkSdkSats[walletId] ?? current.sparkBitcoinbalance;
    if (currentSdk == sats) {
      _refreshSparkShown(walletId);
      return;
    }
    // Zero-clobber guard. The Spark SDK transiently returns 0 from
    // POLL reads while the SDK session is reconnecting (Home →
    // Portfolio → Home race on first boot). But a 0 emitted by the
    // walletInfoStream IS authoritative — that's the SDK telling us
    // the user just drained the wallet. Same when an outgoing Spark
    // send is in flight: a 0 means "yes you spent it all". And once
    // the stream-freshness window has elapsed (no contradicting
    // stream evidence in the last 5 s), a poll-sourced 0 is also
    // trusted — that's the case when the user sent everything and
    // the SDK steadied without re-emitting a walletInfoStream tick,
    // leaving the balance display stuck on the pre-send value.
    // Suppress a transient poll 0 ONLY right after a receive. The Spark
    // SDK returns a stale 0 from getInfo() (poll) while it reconciles
    // after a fresh wallet's first receive — for the whole session,
    // until restart — which clobbered the stream-credited balance and
    // made the home card flicker 10 → 0 → 10. We gate this on
    // `_recentlyReceived` (set on a balance INCREASE, CLEARED on any
    // decrease AND when an outgoing send starts) so it can NEVER
    // suppress a genuine "spent everything → 0": a max send disarms the
    // guard, the deduction lands, and the balance shows 0. (That was the
    // old "balance dropped to 0 but never showed 0" bug — explicitly
    // guarded against here.) `_isStreamFresh` was the previous gate but
    // its 5s window was shorter than the SDK's reconciliation, so 0s
    // slipped through. Stream-sourced 0s are authoritative and never
    // dropped (this is poll-only); `_pinActive` separately covers the
    // in-flight send window.
    if (sats == 0 &&
        currentSdk > 0 &&
        source == BalanceSource.poll &&
        !_pinActive(walletId) &&
        _recentlyReceived(walletId)) {
      return;
    }
    // SDK-wins policy: the optimistic "non-increasing pin" that used to
    // refuse balance INCREASES during a pending outgoing send was removed.
    // The spending balance now tracks the Breez SDK value directly — a
    // stream/poll value that raises the balance is applied as-is rather
    // than held back. This is the documented fix for the spending balance
    // showing a stale/held value. (It assumes the SDK no longer re-emits a
    // stale pre-deduction value mid-send; the v0.15.x upgrade is what makes
    // that safe. `_pinActive` is still consulted by the zero-clobber guard
    // above so a genuine drain-to-0 during a send is never suppressed.)
    // Stream-freshness guard. On a fresh wallet's first incoming
    // receive, the SDK's walletInfoStream credits the cache (e.g.
    // 0 → 10 000 sats) before the next 30 s background-poll tick
    // re-reads `getInfo()` and returns the SAME 10 000. So far so
    // good — but if the poll catches the SDK mid-reconcile, it can
    // return a STALE pre-receive value (often the cached 0 from
    // before connect()) which would overwrite the stream-credited
    // balance. Result: balance flips between 10 000 (stream) → 0
    // (poll) → 10 000 (next stream) → 0 (next poll), oscillating
    // until the SDK steadies and poll/stream agree. Block poll
    // writes that REGRESS the cached value within the freshness
    // window — a higher poll value still wins (handles the case
    // where the stream missed an event). Stream writes are never
    // dropped here. The receive-screen `primePoll` opt-out lets
    // the post-receive poll land regardless when the user is
    // actively expecting a refresh.
    if (source == BalanceSource.poll &&
        sats < currentSdk &&
        _isStreamFresh(walletId)) {
      if (_consumeBypass(walletId)) {
        // bypass consumed — fall through to write
      } else {
        return;
      }
    }
    // Track receive/spend direction for the post-receive 0-guard above.
    // An INCREASE = a receive (arm the guard); any DECREASE = a spend or
    // settle (disarm it, so a subsequent 0 — including the rest of a
    // max-send dropping to 0 — is never suppressed).
    if (sats > currentSdk) {
      _lastReceiveAt[walletId] = _clock();
      _sparkSdkRaisedAt[walletId] = _clock();
    } else if (sats < currentSdk) {
      _lastReceiveAt.remove(walletId);
    }
    if (source == BalanceSource.stream) {
      // Set the timestamp BEFORE writing so any concurrent poll
      // write that lands inside the same microtask flush sees the
      // fresh window. Without this ordering, a poll write that
      // raced the stream-write by a tick could still slip through.
      _lastStreamUpdate[walletId] = _clock();
    }
    _sparkSdkSats[walletId] = sats;
    _refreshSparkShown(walletId);
  }

  // `updateUsdbBalance` was removed with the Flashnet Earn product:
  // nothing writes the (deprecated, always-zero going forward)
  // `WalletBalance.usdbBalance` field any more.

  /// Wholesale replacement of a wallet's balance. Used by the wallet
  /// picker / on-import / wallet-deletion paths.
  void setBalance(String walletId, WalletBalance balance) {
    _sparkSdkSats.remove(walletId);
    _sparkSendHolds.remove(walletId);
    _sendHoldTimers.remove(walletId)?.cancel();
    _put(walletId, balance);
  }

  /// Zero out the legacy `onChainBtcBalance` slot for any walletId
  /// in [sparkHotWalletIds]. Spark hot wallets keep all BTC inside
  /// Spark; the on-chain field for them only ever held cross-write
  /// pollution from earlier sync races. Called on boot once the
  /// settings provider has resolved the wallet list — it's a no-op
  /// for cleanly-cached wallets, and erases the bad value for
  /// affected ones.
  void clearStaleSparkOnchain(Iterable<String> sparkHotWalletIds) {
    final next = {...state};
    var changed = false;
    for (final id in sparkHotWalletIds) {
      final current = next[id];
      if (current == null || current.onChainBtcBalance == 0) continue;
      next[id] = current.copyWith(onChainBtcBalance: 0);
      WalletBalanceCacheService.write(id, next[id]!);
      changed = true;
    }
    if (changed) state = next;
  }

  /// Drop a wallet's cached balance entirely. Called when the user
  /// deletes a wallet so the slot can't leak into a recycled id.
  void deleteWallet(String walletId) {
    if (!state.containsKey(walletId)) return;
    final next = {...state}..remove(walletId);
    state = next;
    _lastStreamUpdate.remove(walletId);
    _bypassStreamFreshUntil.remove(walletId);
    _pendingOutgoingSparkSend.remove(walletId);
    _pinHoldUntil.remove(walletId);
    _sparkSdkSats.remove(walletId);
    _sparkSendHolds.remove(walletId);
    _sendHoldTimers.remove(walletId)?.cancel();
    _sparkReceivesSeen.remove(walletId);
    _sparkSdkRaisedAt.remove(walletId);
    WalletBalanceCacheService.delete(walletId);
  }

  void _put(String walletId, WalletBalance balance) {
    state = {...state, walletId: balance};
    WalletBalanceCacheService.write(walletId, balance);
  }

  @override
  void dispose() {
    for (final timer in _sendHoldTimers.values) {
      timer.cancel();
    }
    _sendHoldTimers.clear();
    super.dispose();
  }
}

/// Backwards-compatible facade that hands sync code + UI the same
/// `.notifier.updateXxx(...)` shape they used before, while routing
/// every write to the cache keyed by the *current* active wallet
/// id. Reads mirror the active wallet's slot in the cache.
///
/// New code should prefer the explicit cache notifier
/// (`walletBalanceCacheProvider.notifier.updateXxx(walletId, ...)`)
/// or the per-wallet read family (`balanceForWalletProvider(id)`)
/// so writes can target a captured walletId directly.
class ActiveBalanceNotifier extends StateNotifier<WalletBalance> {
  final Ref ref;
  ProviderSubscription<Map<String, WalletBalance>>? _cacheSub;
  ProviderSubscription<String?>? _activeIdSub;

  ActiveBalanceNotifier(this.ref) : super(WalletBalance.empty()) {
    _activeIdSub = ref.listen<String?>(
      settingsProvider.select((s) => s.activeWalletId),
      (_, __) => _refresh(),
      fireImmediately: true,
    );
    _cacheSub = ref.listen<Map<String, WalletBalance>>(
      walletBalanceCacheProvider,
      (_, __) => _refresh(),
    );
  }

  void _refresh() {
    final id = ref.read(settingsProvider).activeWalletId;
    final cache = ref.read(walletBalanceCacheProvider);
    final next = id == null ? WalletBalance.empty() : (cache[id] ?? WalletBalance.empty());
    if (next != state) state = next;
  }

  String? get _activeId => ref.read(settingsProvider).activeWalletId;

  void updateOnChainBtcBalance(int sats) {
    final id = _activeId;
    if (id == null) return;
    ref
        .read(walletBalanceCacheProvider.notifier)
        .updateOnChainBtcBalance(id, sats);
  }

  void updateSparkBitcoinbalance(
    int sats, {
    BalanceSource source = BalanceSource.poll,
  }) {
    final id = _activeId;
    if (id == null) return;
    ref
        .read(walletBalanceCacheProvider.notifier)
        .updateSparkBitcoinbalance(id, sats, source: source);
  }

  void updateBalance(WalletBalance newBalance) {
    final id = _activeId;
    if (id == null) return;
    ref.read(walletBalanceCacheProvider.notifier).setBalance(id, newBalance);
  }

  void invalidateStreamFreshness() {
    final id = _activeId;
    if (id == null) return;
    ref
        .read(walletBalanceCacheProvider.notifier)
        .invalidateStreamFreshness(id);
  }

  @override
  void dispose() {
    _cacheSub?.close();
    _activeIdSub?.close();
    super.dispose();
  }
}
