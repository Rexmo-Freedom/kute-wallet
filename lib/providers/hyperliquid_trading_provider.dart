import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/revenue/hyperliquid_revenue.dart';
// lib/providers/hyperliquid_trading_provider.dart
//
// The write path's front door — mirrors PolymarketTradingNotifier's
// shape: a value-equality state struct fanned in from the polled account
// provider, plus the money-moving methods (open/close/cancel/spot/
// withdraw) that sign via HyperliquidExchangeService.
//
// Key derivation: the signer is derived ON DEMAND from the spending
// wallet's mnemonic (same m/44'/60'/0'/0/0 EOA as Polymarket) the first
// time an action needs it, held only in a private notifier field inside
// the exchange service — NEVER in provider state, never persisted.
// Provisioning (ensureOnboarded) also writes the 'hl_enabled_<walletId>'
// flag that gates the home-pill badge poll and fires the
// hyperliquid_trading_enabled analytics event exactly once.
//
// Analytics contract owned here: hyperliquidOrderPlaced/orderFailed/
// positionClosed/leverageAdjusted/orderCancelled/tradingEnabled/
// withdraw* fire from THIS notifier with reasons drawn from
// TrackingErrorReasons. HyperliquidSignatureRejectedException goes to
// crash reporting (recordCrash) — it's an engineering defect, never a
// user error, and never a toast.
//
// Builder fee: HyperliquidFundingService.getBuilder() (backend only; null
// = no builder, so the order carries none and nothing is approved) →
// attached to orders as `builder.asOrderFee` only once the user has
// approved that same address (hasApprovedBuilderFee; a rotated address
// reads as unapproved and is approved again in _builderFee before the
// order goes out); ensureBuilderFeeApproved() is exposed for the
// deposit flow to call after the first perp credit lands (an unfunded
// account can't post user-signed actions) and is retried
// opportunistically before orders when still unapproved.
//
// Step-up v2 (Wallet Hardening Phase 1b.3): every order, leverage and
// withdraw method takes a required `AuthGrant`. It rebuilds its
// intent from its own arguments (lib/helpers/venue_intents.dart) and
// consumes the grant before anything is signed, so a changed amount,
// leverage, side or market throws `ReauthRequired` and nothing is sent.
// Cancels, the builder fee approval, onboarding and the internal spot to
// perp sweep stay session only.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hot_twap_guard.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_referral_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart'
    show HlBuilderFee, limitOrderType, triggerOrderType;
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlOrderUpdate;
import 'package:kute/services/passkey_service.dart'
    show resolveBip39MnemonicFor;
import 'package:kute/services/tracking_error_reasons.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_owner_link_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

/// The selected cancel-all set could not be resolved completely; no request
/// was sent and all local orders remain visible.
class HlCancellationIncompleteException implements Exception {
  const HlCancellationIncompleteException();
}

/// A TWAP this app started, tracked client-side: HL exposes no info
/// call listing running TWAPs and they never show in frontendOpenOrders,
/// so the twapId returned at placement is the only cancel handle.
class HlRunningTwap {
  final int twapId;
  final int assetId;
  final String coin;
  final String address;
  final bool isBuy;
  final bool reduceOnly;
  final double size;
  final int durationMinutes;
  final DateTime startedAt;

  const HlRunningTwap({
    required this.twapId,
    required this.assetId,
    required this.coin,
    required this.address,
    required this.isBuy,
    required this.reduceOnly,
    required this.size,
    required this.durationMinutes,
    required this.startedAt,
  });

  DateTime get endsAt => startedAt.add(Duration(minutes: durationMinutes));
  bool get expired => DateTime.now().isAfter(endsAt);

  Map<String, dynamic> toJson() => {
        'twapId': twapId,
        'assetId': assetId,
        'coin': coin,
        'address': address,
        'isBuy': isBuy,
        'reduceOnly': reduceOnly,
        'size': size,
        'durationMinutes': durationMinutes,
        'startedAt': startedAt.millisecondsSinceEpoch,
      };

  static HlRunningTwap? fromJson(Map<String, dynamic> j) {
    final twapId = j['twapId'];
    if (twapId is! int) return null;
    return HlRunningTwap(
      twapId: twapId,
      assetId: (j['assetId'] as num?)?.toInt() ?? 0,
      coin: (j['coin'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      isBuy: j['isBuy'] == true,
      reduceOnly: j['reduceOnly'] == true,
      size: (j['size'] as num?)?.toDouble() ?? 0,
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['startedAt'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HlRunningTwap &&
      other.twapId == twapId &&
      other.assetId == assetId &&
      other.coin == coin &&
      other.address == address;

  @override
  int get hashCode => Object.hash(twapId, assetId, coin, address);
}

/// The live position an isolated-margin change lands on, or a
/// [StateError] before anything is signed. [market] must be the very
/// instrument [position] is held on (its wire coin, e.g. 'xyz:TSLA'), so
/// the asset id the action signs against is that position's and no other
/// (a same-symbol market on another dex, or spot, never receives the
/// margin), and the position must still be open on the same side,
/// isolated.
HlPerpPosition isolatedMarginTarget({
  required HlMarket market,
  required HlPerpPosition position,
  required List<HlPerpPosition> live,
}) {
  if (market.isSpot || market.wireCoin != position.coin) {
    throw StateError('Position changed. Review again.');
  }
  final current = live.where((p) => p.coin == market.wireCoin).firstOrNull;
  if (current == null ||
      current.szi == 0 ||
      current.isLong != position.isLong ||
      current.isCross) {
    throw StateError('Position changed. Review again.');
  }
  return current;
}

class HyperliquidTradingState {
  /// True once the spending wallet's address resolved — browsing works
  /// regardless; this only gates account-scoped UI (balances card).
  final bool isInitialized;

  /// The user's EOA — the Hyperliquid account address itself (no proxy).
  final String? walletAddress;

  /// Perp account equity (marginSummary.accountValue), USD.
  final double perpEquity;
  final double totalMarginUsed;

  /// Perp USDC available for withdrawal / new margin, USD.
  final double withdrawable;
  final List<HlPerpPosition> positions;
  final List<HlSpotBalance> spotBalances;
  final List<HlOpenOrder> openOrders;

  /// Newest-first fills (REST-seeded, WS-appended). Caps at 200.
  final List<HlFill> recentFills;

  /// Coins with a reduce-only close in flight. Their cards render a
  /// "Closing…" state (instead of being optimistically removed) until
  /// the account snapshot confirms the size actually dropped. Mirrors
  /// PolymarketTradingState.pendingSaleTokens.
  final Set<String> pendingCloseCoins;

  /// TWAPs this app started that should still be running (start time +
  /// duration not yet elapsed). HL has no info call that lists running
  /// TWAPs and they never appear in frontendOpenOrders, so the twapId
  /// captured at placement is the ONLY handle for twapCancel — kept
  /// here and persisted to Hive so a restart can still stop them.
  final List<HlRunningTwap> runningTwaps;
  final String? error;
  final bool isPlacingOrder;

  const HyperliquidTradingState({
    this.isInitialized = false,
    this.walletAddress,
    this.perpEquity = 0,
    this.totalMarginUsed = 0,
    this.withdrawable = 0,
    this.positions = const [],
    this.spotBalances = const [],
    this.openOrders = const [],
    this.recentFills = const [],
    this.pendingCloseCoins = const {},
    this.runningTwaps = const [],
    this.error,
    this.isPlacingOrder = false,
  });

  double get availableUsdc =>
      hypercoreAvailableUsdc(withdrawable, spotBalances);

  HyperliquidTradingState copyWith({
    bool? isInitialized,
    String? walletAddress,
    double? perpEquity,
    double? totalMarginUsed,
    double? withdrawable,
    List<HlPerpPosition>? positions,
    List<HlSpotBalance>? spotBalances,
    List<HlOpenOrder>? openOrders,
    List<HlFill>? recentFills,
    Set<String>? pendingCloseCoins,
    List<HlRunningTwap>? runningTwaps,
    String? error,
    bool? isPlacingOrder,
  }) {
    return HyperliquidTradingState(
      isInitialized: isInitialized ?? this.isInitialized,
      walletAddress: walletAddress ?? this.walletAddress,
      perpEquity: perpEquity ?? this.perpEquity,
      totalMarginUsed: totalMarginUsed ?? this.totalMarginUsed,
      withdrawable: withdrawable ?? this.withdrawable,
      positions: positions ?? this.positions,
      spotBalances: spotBalances ?? this.spotBalances,
      openOrders: openOrders ?? this.openOrders,
      recentFills: recentFills ?? this.recentFills,
      pendingCloseCoins: pendingCloseCoins ?? this.pendingCloseCoins,
      runningTwaps: runningTwaps ?? this.runningTwaps,
      // Same reset semantics as PolymarketTradingState: any copyWith
      // that doesn't pass `error` clears it.
      error: error,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
    );
  }

  // Value-equality so an idle account tick that produced identical data
  // doesn't notify every consumer — same GC rationale as
  // PolymarketTradingState (lines 121-136 there). The HL model structs
  // don't override ==, so the list comparisons go through the field-wise
  // helpers in hyperliquid_account_provider.dart.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HyperliquidTradingState) return false;
    return isInitialized == other.isInitialized &&
        walletAddress == other.walletAddress &&
        perpEquity == other.perpEquity &&
        totalMarginUsed == other.totalMarginUsed &&
        withdrawable == other.withdrawable &&
        error == other.error &&
        isPlacingOrder == other.isPlacingOrder &&
        setEquals(pendingCloseCoins, other.pendingCloseCoins) &&
        hlPerpPositionListEquals(positions, other.positions) &&
        hlSpotBalanceListEquals(spotBalances, other.spotBalances) &&
        hlOpenOrderListEquals(openOrders, other.openOrders) &&
        listEquals(runningTwaps, other.runningTwaps) &&
        hlFillListEquals(recentFills, other.recentFills);
  }

  @override
  int get hashCode => Object.hash(
        isInitialized,
        walletAddress,
        perpEquity,
        totalMarginUsed,
        withdrawable,
        error,
        isPlacingOrder,
        pendingCloseCoins.length,
        positions.length,
        spotBalances.length,
        openOrders.length,
        recentFills.length,
        runningTwaps.length,
      );
}

/// 16-byte client order id ('0x' + 32 hex chars), unique per submit.
/// Attached to orders so WS userFills events can be matched back to the
/// exact placement tile.
String newHlCloid() {
  final rng = math.Random.secure();
  final buf = StringBuffer('0x');
  for (var i = 0; i < 32; i++) {
    buf.write(rng.nextInt(16).toRadixString(16));
  }
  return buf.toString();
}

class HyperliquidTradingNotifier
    extends AutoDisposeAsyncNotifier<HyperliquidTradingState> {
  HyperliquidExchangeService? _exchange;

  /// The hot account key, kept beside [_exchange] (same lifetime, never in
  /// state, never persisted) for the venue ownership link only.
  EthPrivateKey? _hotKey;
  String? _walletId;
  String? _address;
  Timer? _ordersTimer;
  bool _disposed = false;
  bool _onboardInFlight = false;

  /// Whether a funded snapshot has already asked for the referrer check
  /// in this notifier's life (see [setReferrerIfNeeded]).
  bool _referrerChecked = false;

  /// Builder (HIP-3) dexes whose resting orders are read alongside the
  /// main dex: every dex the account holds anything on (snapshot
  /// activeDexes), the dex of every open position, and every dex that
  /// still has a known order. See [HyperliquidModel.getOpenOrders].
  Set<String> _orderDexes = const {};

  static Set<String> _dexesFor(
      HlAccountSnapshot snap, List<HlOpenOrder> orders) {
    String? dexOf(String coin) {
      final i = coin.indexOf(':');
      return i > 0 ? coin.substring(0, i) : null;
    }

    return {
      ...snap.activeDexes,
      for (final p in snap.positions)
        if (dexOf(p.coin) case final d?) d,
      for (final o in orders)
        if (dexOf(o.coin) case final d?) d,
    };
  }

  /// |szi| at close-request time per coin, driving pendingCloseCoins
  /// reconciliation: the "Closing…" state clears when the snapshot shows
  /// the size actually dropped (or after a 120 s safety TTL so a close
  /// that silently failed doesn't pin the card forever).
  final Map<String, ({double absSzi, DateTime at})> _closeBaselines = {};

  /// Safe state write — long-running async work can outlive this
  /// autoDispose notifier (user navigates away mid-order); writing to a
  /// disposed notifier throws. Same guard as PM's _setData.
  void _setData(HyperliquidTradingState newState) {
    if (_disposed) return;
    try {
      state = AsyncData(newState);
    } catch (_) {
      // Riverpod threw after disposal — nothing to update.
    }
  }

  /// Safe state READ for post-await code paths — reading `state` on a
  /// disposed notifier throws just like writing does.
  HyperliquidTradingState? get _current {
    if (_disposed) return null;
    try {
      return state.valueOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<HyperliquidTradingState> build() async {
    // keepAlive: the notifier caches the derived signer and the fills
    // ring; tearing it down every time the last trading widget unmounts
    // would force a mnemonic re-derivation (seconds of blank state) on
    // remount. Torn down only by explicit invalidation (wallet switch).
    ref.keepAlive();
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _ordersTimer?.cancel();
      _exchange = null; // drop the signer with the notifier
      _hotKey = null;
    });

    // Fan-in from the polled account snapshot — registered before any
    // await so it's bound synchronously during build.
    ref.listen(hyperliquidAccountProvider, (_, next) {
      final snap = next.valueOrNull;
      if (snap != null) {
        _applySnapshot(snap);
        _checkReferrerOnce(snap);
      }
    });

    final address = await ref.watch(hyperliquidAddressProvider.future);
    if (address == null) {
      return const HyperliquidTradingState();
    }
    _address = address;

    var snap = HlAccountSnapshot.empty;
    try {
      snap = await ref.read(hyperliquidAccountProvider.future);
    } catch (_) {
      // Account fetch failed — the poll loop in the account provider
      // self-heals; start with an empty snapshot rather than erroring
      // the whole trading surface.
    }

    _checkReferrerOnce(snap);
    _orderDexes = _dexesFor(snap, const []);

    var orders = <HlOpenOrder>[];
    var fills = <HlFill>[];
    final model = ref.read(hyperliquidTradingModelProvider);
    try {
      final results = await Future.wait<Object>([
        model
            .getOpenOrders(address, dexes: _orderDexes)
            .catchError((_) => <HlOpenOrder>[]),
        model.getUserFills(address).catchError((_) => <HlFill>[]),
      ]);
      orders = results[0] as List<HlOpenOrder>;
      fills = results[1] as List<HlFill>;
    } catch (_) {}

    final twaps = await _loadPersistedTwaps(address);

    // Orders/fills stay fresh on a modest 30 s cadence; WS user events
    // (hyperliquid_user_events_provider) patch them in real time.
    _ordersTimer?.cancel();
    _ordersTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _silentOrdersRefresh(),
    );

    return HyperliquidTradingState(
      isInitialized: true,
      walletAddress: address,
      perpEquity: snap.accountValue,
      totalMarginUsed: snap.totalMarginUsed,
      withdrawable: snap.withdrawable,
      positions: snap.positions,
      spotBalances: snap.spotBalances,
      openOrders: orders,
      recentFills: _capFills(fills),
      runningTwaps: twaps,
    );
  }

  // ───────────────────────── running TWAPs ────────────────────────────

  static const _kTwapBoxName = HotHyperliquidTwapGuard.runningBoxName;

  Future<Box<String>> _twapsBox() => Hive.openBox<String>(_kTwapBoxName);

  /// Restores this address's not-yet-elapsed TWAPs; GCs the rest.
  Future<List<HlRunningTwap>> _loadPersistedTwaps(String address) async {
    try {
      // Repair a confirmed checkpoint before reading the cancel handles.
      // Failed recovery never clears the guard or hides other persisted TWAPs.
      try {
        await HotHyperliquidTwapGuard().restoreAccepted(address);
      } catch (_) {}
      final box = await _twapsBox();
      final live = <int, HlRunningTwap>{};
      final cancelled = <int>{};
      final stale = <dynamic>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null) continue;
        HlRunningTwap? t;
        try {
          final row = jsonDecode(raw) as Map<String, dynamic>;
          if (row['cancelled'] == true) {
            if (row['address']?.toString().toLowerCase() ==
                    address.toLowerCase() &&
                row['twapId'] is int) {
              cancelled.add(row['twapId'] as int);
            }
            continue;
          }
          t = HlRunningTwap.fromJson(row);
        } catch (_) {}
        if (t == null || t.expired) {
          stale.add(key);
          continue;
        }
        if (t.address.toLowerCase() == address.toLowerCase()) {
          live[t.twapId] = t;
        }
      }
      for (final k in stale) {
        await box.delete(k);
      }
      final result =
          live.values.where((t) => !cancelled.contains(t.twapId)).toList();
      result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// The guard has already flushed the cancellation handle before this update.
  void _showRunningTwap(HlRunningTwap twap) {
    final current = _current;
    if (current != null &&
        current.walletAddress?.toLowerCase() == twap.address.toLowerCase()) {
      _setData(current.copyWith(runningTwaps: [
        twap,
        ...current.runningTwaps.where((t) => t.twapId != twap.twapId),
      ]));
    }
  }

  Future<void> _forgetTwap(HlRunningTwap twap) async {
    final box = await _twapsBox();
    // Keep a scoped tombstone so an accepted checkpoint cannot restore a
    // cancellation that the venue already acknowledged, even after restart.
    await box.put(
        '${twap.address.toLowerCase()}:${twap.twapId}',
        jsonEncode({
          ...twap.toJson(),
          'address': twap.address.toLowerCase(),
          'cancelled': true,
        }));
    await box.flush();
    final current = _current;
    if (current != null &&
        current.walletAddress?.toLowerCase() == twap.address.toLowerCase()) {
      _setData(current.copyWith(
        runningTwaps:
            current.runningTwaps.where((t) => t.twapId != twap.twapId).toList(),
      ));
    }
  }

  /// Drops elapsed TWAPs from state (persistence GCs on next load).
  void _pruneExpiredTwaps() {
    final current = _current;
    if (current == null) return;
    final live = current.runningTwaps.where((t) => !t.expired).toList();
    if (live.length != current.runningTwaps.length) {
      _setData(current.copyWith(runningTwaps: live));
    }
  }

  /// Stops a running TWAP. The remaining un-executed size simply never
  /// trades; already-filled slices keep their fills.
  Future<void> cancelTwap(HlRunningTwap twap) async {
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.cancel');
      await ensureOnboarded();
      await _exchange!.cancelTwap(assetId: twap.assetId, twapId: twap.twapId);
    } catch (e) {
      _trackCancelFailed(scope: 'twap', coin: twap.coin, error: e);
      rethrow;
    }
    TrackingService.track('hl_twap_cancelled', params: {'coin': twap.coin});
    TrackingService.hyperliquidOrderCancelled(
      coin: twap.coin,
      scope: 'twap',
      orderType: 'twap',
      walletKind: 'hot',
    );
    await _forgetTwap(twap);
  }

  static List<HlFill> _capFills(List<HlFill> fills) =>
      fills.length <= 200 ? fills : fills.sublist(0, 200);

  // ───────────────────────── snapshot fan-in ─────────────────────────

  void _applySnapshot(HlAccountSnapshot snap) {
    if (_disposed) return;
    final current = state.valueOrNull;
    if (current == null) return;

    // Reconcile "Closing…" markers: drop a coin once the snapshot shows
    // its size actually dropped (close settled) or after the safety TTL.
    final pending = Set<String>.from(current.pendingCloseCoins);
    final now = DateTime.now();
    _closeBaselines.removeWhere((coin, baseline) {
      HlPerpPosition? pos;
      for (final p in snap.positions) {
        if (p.coin == coin) {
          pos = p;
          break;
        }
      }
      final settled = pos == null || pos.szi.abs() < baseline.absSzi - 1e-9;
      final expired =
          now.difference(baseline.at) > const Duration(seconds: 120);
      if (settled || expired) {
        pending.remove(coin);
        return true;
      }
      return false;
    });

    _orderDexes = _dexesFor(snap, current.openOrders);

    final next = current.copyWith(
      perpEquity: snap.accountValue,
      totalMarginUsed: snap.totalMarginUsed,
      withdrawable: snap.withdrawable,
      positions: snap.positions,
      spotBalances: snap.spotBalances,
      pendingCloseCoins: pending,
    );
    if (next == current) return;
    _setData(next);
  }

  Future<void> _silentOrdersRefresh() async {
    if (_disposed) return;
    final address = _address;
    final current = state.valueOrNull;
    if (address == null || current == null) return;
    _pruneExpiredTwaps();
    try {
      final model = ref.read(hyperliquidTradingModelProvider);
      final results = await Future.wait<Object>([
        model.getOpenOrders(address, dexes: _orderDexes),
        model.getUserFills(address),
      ]);
      final orders = results[0] as List<HlOpenOrder>;
      final fills = _capFills(results[1] as List<HlFill>);
      final latest = _current;
      if (latest == null) return;
      if (hlOpenOrderListEquals(latest.openOrders, orders) &&
          hlFillListEquals(latest.recentFills, fills)) {
        return;
      }
      _setData(latest.copyWith(openOrders: orders, recentFills: fills));
    } catch (_) {
      // Silent — background refresh must not surface errors.
    }
  }

  /// Full refresh: account snapshot (via the account provider so its
  /// timers stay authoritative) + open orders + fills.
  Future<void> refresh() async {
    if (_disposed) return;
    ref.invalidate(hyperliquidAccountProvider);
    await _silentOrdersRefresh();
  }

  /// Post-action refresh: immediate account invalidate + staggered
  /// order/fill polls so the exchange's own indexing lag is covered.
  void _afterAction() {
    ref.invalidate(hyperliquidAccountProvider);
    for (final delay in const [1, 4]) {
      Future.delayed(Duration(seconds: delay), () {
        if (_disposed) return;
        unawaited(_silentOrdersRefresh());
      });
    }
  }

  // ─────────────────────────── onboarding ───────────────────────────

  /// Derives the signer from the spending wallet's mnemonic and marks
  /// this wallet HL-enabled (`hl_enabled_<walletId>` — the same flag the
  /// badge poll gates on). Pure local work, safe to call repeatedly;
  /// fires hyperliquid_trading_enabled exactly once per wallet. The
  /// derived key lives only inside the exchange service on this
  /// notifier — never in provider state.
  Future<void> ensureOnboarded() async {
    if (_exchange != null) return;
    while (_onboardInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_exchange != null) return;
    }
    _onboardInFlight = true;
    try {
      final settings = ref.read(settingsProvider);
      final spending = pickSpendingWallet(settings);
      if (spending == null) {
        throw StateError('No spending wallet available');
      }
      final session = ref.read(seedSessionProvider);
      if (!session.unlocked) throw const SeedLockedException();
      final mnemonic = await resolveBip39MnemonicFor(spending,
          access: SeedAccess.automatic, session: session);
      if (mnemonic == null) {
        throw StateError('Could not decrypt spending wallet mnemonic');
      }

      final account =
          await HyperliquidOnboardingService.provisionHyperliquidAccount(
        mnemonic: mnemonic,
        walletId: spending.id,
        evmDerivationVersion: spending.evmDerivationVersion,
      );
      _exchange = HyperliquidExchangeService(
        credentials: account.credentials,
        walletAddress: account.address,
      );
      _hotKey = account.credentials;
      _walletId = spending.id;
      _address ??= account.address;
      // Once per wallet on this device. The old `!isEnabled` check almost
      // never passed: the enabled flag is set earlier, elsewhere.
      if (OnceFlagsService.claimOnce('hl_trading_enabled_${spending.id}')) {
        TrackingService.hyperliquidTradingEnabled(walletKind: 'hot');
      }
    } finally {
      _onboardInFlight = false;
    }
  }

  /// One-time builder-fee approval. MUST run after the first deposit
  /// credit lands (an unfunded account can't post user-signed actions) —
  /// the deposit flow calls this right after waitForPerpCredit succeeds.
  /// Also retried opportunistically before orders while unapproved.
  /// Returns true when approved or no builder is configured.
  Future<bool> ensureBuilderFeeApproved({HlBuilderInfo? reviewed}) async {
    try {
      await ensureOnboarded();
      final ex = _exchange;
      final walletId = _walletId;
      if (ex == null || walletId == null) return false;
      // Two attempts, briefly apart. The common failure is a deposit
      // that has credited the balance the app can see but has not yet
      // settled far enough for the venue to accept a user-signed
      // action, and that resolves in seconds. One shot turned a
      // moment's lag into a permanently unapproved account, because
      // nothing retried until the next order.
      for (var attempt = 0; attempt < 2; attempt++) {
        final ok = await HyperliquidOnboardingService.ensureBuilderFeeApproved(
          exchange: ex,
          walletAddress: ex.walletAddress,
          walletId: walletId,
          reviewed: reviewed,
        );
        if (ok) {
          if (OnceFlagsService.claimOnce('hl_builder_fee_approved_$walletId')) {
            TrackingService.track('hl_builder_fee_approved',
                params: {'attempt': attempt + 1});
          }
          return true;
        }
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Names Kute as this account's Hyperliquid referrer when the backend
  /// publishes a referral code and the account has none. Silent and
  /// best-effort: never throws, never blocks trading, and the service
  /// records one attempt per account (HyperliquidReferralService).
  Future<void> setReferrerIfNeeded() async {
    try {
      await ensureOnboarded();
      final ex = _exchange;
      if (ex == null) return;
      await HyperliquidReferralService.ensureReferrerSet(exchange: ex);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// The first funded snapshot asks once, so an account funded on another
  /// screen (or before this build) is covered before its first trade.
  void _checkReferrerOnce(HlAccountSnapshot snap) {
    if (_referrerChecked || _disposed) return;
    final funded = snap.accountValue > 0 ||
        snap.spotBalances.any((b) => b.total > 0);
    if (!funded) return;
    _referrerChecked = true;
    unawaited(setReferrerIfNeeded());
    unawaited(_linkVenueOwner());
  }

  /// Proves to the backend, once per account, that this hot wallet owns
  /// its Hyperliquid account, so builder-fee trades are credited to the
  /// user (VenueOwnerLinkService). Hot accounts only: a Ledger signer or
  /// hardware spending wallet sends nothing. Silent; never throws.
  Future<void> _linkVenueOwner() async {
    try {
      await ensureOnboarded();
      final key = _hotKey;
      final ex = _exchange;
      if (key == null || ex == null || ex.externalSigner != null) return;
      final spending = pickSpendingWallet(ref.read(settingsProvider));
      if (spending == null || spending.isHardware) return;
      await VenueOwnerLinkService.ensureLinked(
          venue: VenueOwnerLinkService.hyperliquid, key: key);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Registers the builder once an account has funds. Safe to call on
  /// every deposit: it returns immediately when already approved.
  Future<void> approveBuilderAfterFunding() async {
    unawaited(_linkVenueOwner());
    try {
      await ensureOnboarded();
      final ex = _exchange;
      final walletId = _walletId;
      if (ex == null || walletId == null) return;
      // Same moment the venue first accepts a signed action, and before
      // the first trade: name the referrer too.
      await HyperliquidReferralService.ensureReferrerSet(exchange: ex);
      await HyperliquidOnboardingService.approveAfterFunding(
        exchange: ex,
        walletAddress: ex.walletAddress,
        walletId: walletId,
      );
    } catch (_) {
      // Never surfaces on a completed deposit.
    }
  }

  /// Attach the published fee only after its approval scope is satisfied.
  /// Never silently omit a configured fee on an otherwise accepted order.
  ///
  /// The retry passes [builder] as the reviewed config. Without it the
  /// service only signs inside the legacy pinned scope and answers false
  /// for anything else, so an account that had not been approved by some
  /// earlier path could never approve itself here: the order died on
  /// "approve the trading fee" with nothing on screen to approve. The
  /// config it authorizes is the one this order is about to carry, read
  /// from the same call that produced the fee.
  Future<HlBuilderFee?> _builderFee() async {
    final builder = await HyperliquidFundingService.getBuilder();
    if (builder == null) return null;
    final walletId = _walletId;
    if (walletId == null) throw StateError('Investing account unavailable.');
    if (!await HyperliquidOnboardingService.hasApprovedBuilderFee(walletId) &&
        !await ensureBuilderFeeApproved(reviewed: builder)) {
      // The builder stays attached to every order, so a missing
      // approval is a hard stop rather than a quietly free trade.
      //
      // This used to be unreachable-in-practice by design: the approval
      // is meant to happen once, right after the first deposit credits,
      // long before anyone reaches an order slip. It was never wired to
      // run there, so the first attempt was always at order time on an
      // account that had just been funded, which is the moment the
      // venue is least likely to accept it. That hook now exists
      // (HyperliquidOnboardingService.approveAfterFunding), and this
      // retries too, so reaching this line means the venue refused
      // repeatedly and the reason is in lastFailure.
      //
      // EXCEPT in a debug build, where the order goes through with no
      // builder attached. A development wallet cannot approve a builder
      // that has not met the venue's own requirement for one, and
      // nobody testing a trade should be stopped by Kute's revenue
      // plumbing. Release keeps the hard stop: shipping a build that
      // silently forgoes the fee is how the fee quietly stops arriving.
      if (kDebugMode) {
        debugPrint('[hl-builder-fee] debug build: placing with no builder. '
            'Reason the approval failed: '
            '${HyperliquidOnboardingService.lastFailure}');
        return null;
      }
      throw StateError(
          'Approve the current Kute trading fee before placing an order.');
    }
    return builder.asOrderFee;
  }

  // ───────────────────────────── orders ─────────────────────────────

  /// Reference price for sizing/slippage: live WS mid when available,
  /// else the market snapshot's mid/mark.
  double _referencePx(HlMarket market) {
    double? live;
    try {
      live = ref.read(hyperliquidLivePricesProvider).mid(market.coin);
    } catch (_) {}
    final px = live ?? (market.midPx > 0 ? market.midPx : market.markPx);
    if (px <= 0) {
      throw StateError('No reference price for ${market.coin}');
    }
    return px;
  }

  /// A direct deposit may credit either HyperCore clearinghouse. Move only
  /// the cash needed by this reviewed action into perps, after its grant was
  /// consumed. This never touches an external chain or an Arbitrum address.
  Future<void> _fundPerpAction(HlMarket market, double marginUsd,
      {int leverage = 1,
      double slippagePct = 0,
      bool includeBuilderFee = true,
      bool tradingFee = true}) async {
    final exchange = _exchange;
    final address = _address;
    if (exchange == null || address == null) {
      throw StateError('Account unavailable');
    }
    final model = ref.read(hyperliquidTradingModelProvider);
    var snapshot = await model.getAccountSnapshot(address);
    final feeRate =
        tradingFee ? await model.getPerpTakerFundingRate(address, market) : 0.0;
    final builder = includeBuilderFee ? await _builderFee() : null;
    final notional = marginUsd * leverage * (1 + slippagePct / 100);
    final requiredUsd = marginUsd * (1 + slippagePct / 100) +
        notional * (feeRate + (builder?.feeTenthsBp ?? 0) / 100000);
    final destinationCash = market.dex.isEmpty
        ? 0.0
        : (await model.getDexClearinghouse(address, market.dex)).withdrawable;
    final requiredAtBase = math.max(
        0.0,
        requiredUsd -
            destinationCash -
            hypercoreAvailableUsdc(0, snapshot.spotBalances));
    await collectOwnDexCash(
        model: model,
        exchange: exchange,
        requiredDefaultUsd: requiredAtBase,
        excludeDex: market.dex);
    snapshot = await model.getAccountSnapshot(address);
    if (market.dex.isEmpty) {
      final amount = hypercorePerpFundingAmount(
          requiredUsd: requiredUsd,
          perpAvailable: snapshot.withdrawable,
          spot: snapshot.spotBalances);
      if (amount > 0) {
        await exchange.usdClassTransfer(amount: amount, toPerp: true);
      }
      return;
    }
    final target = await model.getDexClearinghouse(address, market.dex);
    var shortfall = requiredUsd - target.withdrawable;
    if (shortfall <= 0) return;
    final spot = hypercoreAvailableUsdc(0, snapshot.spotBalances);
    if (snapshot.withdrawable + spot + 1e-6 < shortfall) {
      throw const HyperliquidInsufficientMarginException(
          'Insufficient available collateral for margin and fees');
    }
    // Both legs stay at the signed account. Fresh reads on each attempt
    // account for previous funding, including a transfer with a lost reply.
    final fromPerps =
        (math.min(shortfall, snapshot.withdrawable) * 1e6).floorToDouble() /
            1e6;
    if (fromPerps > 0) {
      await exchange.moveOwnUsdc(
          sourceDex: '', destinationDex: market.dex, amount: fromPerps);
      shortfall -= fromPerps;
    }
    final fromSpot = (math.min(shortfall, spot) * 1e6).floorToDouble() / 1e6;
    if (fromSpot > 0) {
      await exchange.moveOwnUsdc(
          sourceDex: 'spot', destinationDex: market.dex, amount: fromSpot);
    }
  }

  /// Opens (or adds to) a perp position: adjusts leverage first when it
  /// differs from the resting setting, then fires an IOC "market" order
  /// sized `marginUsd × leverage / px`. Returns the exchange result
  /// (filled or resting); throws the HyperliquidRejectedException
  /// taxonomy on rejection — the order slip renders the message.
  Future<HlOrderResult> openPosition({
    required HlMarket market,
    required bool isLong,
    required double marginUsd,
    required int leverage,
    double slippagePct = 1.0,
    bool? isCross,
    double? takeProfitPx,
    double? stopLossPx,
    String? source,
    String? cloid,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(hlOpenCapabilities(market));
    if (leverage > 1 ||
        isCross == true ||
        takeProfitPx != null ||
        stopLossPx != null ||
        slippagePct != 1.0) {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('trading.advanced');
    }
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.openPosition(
          walletId: _walletId ?? '',
          market: market,
          isLong: isLong,
          marginUsd: marginUsd,
          leverage: leverage,
          slippagePct: slippagePct,
          isCross: isCross,
          takeProfitPx: takeProfitPx,
          stopLossPx: stopLossPx,
        ),
        allowed: _hlOrderActions,
      );
      final lev = leverage.clamp(1, market.maxLeverage).toInt();
      await _fundPerpAction(market, marginUsd,
          leverage: lev, slippagePct: slippagePct);

      // 1) Leverage + margin mode (writes only when the resting per-asset
      //    setting differs; always writes when flat).
      await _ensureLeverage(market, current, lev, isCross,
            changeOpenPosition: changeOpenPosition);

      // 2) Size from margin × leverage at the live reference price.
      final refPx = _referencePx(market);
      final size = sizeFromUsd(
        usd: marginUsd * lev,
        px: refPx,
        szDecimals: market.szDecimals,
      );

      // 3) IOC limit priced through the book. TP/SL rides in the SAME
      //    'normalTpsl'-grouped action: the exchange sizes the triggers
      //    to the actual fill, activates them on it, and OCO-cancels
      //    them against each other — the old two-step attach could
      //    silently fail and leave the user believing a stop-loss
      //    existed that didn't.
      final builder = await _builderFee();
      final result = await ex.placeMarketOrder(
        market: market,
        isBuy: isLong,
        size: size,
        referencePx: refPx,
        slippage: slippagePct / 100,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
        cloid: cloid ?? newHlCloid(),
        builder: builder,
      );

      final hasTp = takeProfitPx != null;
      final hasSl = stopLossPx != null;
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: 'perp',
        isBuy: isLong,
        leverage: lev,
        marginUsd: marginUsd,
        notionalUsd: marginUsd * lev,
        source: source,
        providerOrderId: result.oid?.toString(),
        orderType: 'market',
        isCross: (isCross ?? true) && !market.onlyIsolated,
        hasTp: hasTp,
        hasSl: hasSl,
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        builderFeeApplied: builder != null,
      );
      _trackTpslLegFailure(market, result,
          wantedTpsl: hasTp || hasSl, parentType: 'market');
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: 'open',
          orderType: 'market',
          isBuy: isLong,
          notionalUsd: marginUsd * leverage,
          leverage: leverage);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Spot "market" buy/sell for [usd] notional. Deposits credit the PERP
  /// clearinghouse, so a buy whose spot USDC is short is funded by a
  /// perp→spot usdClassTransfer FIRST — and the order is aborted if that
  /// transfer fails (the transfer throws before any order is signed).
  Future<HlOrderResult> placeSpotOrder({
    required HlMarket market,
    required bool isBuy,
    required double usd,
    double slippagePct = 1.0,
    String? source,
    String? cloid,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance
        .ensureAllowed(isBuy ? 'hyperliquid.trade' : 'hyperliquid.close');
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.spotOrder(
          walletId: _walletId ?? '',
          market: market,
          isBuy: isBuy,
          usd: usd,
          slippagePct: slippagePct,
        ),
        allowed: _hlOrderActions,
      );

      if (isBuy) {
        double spotUsdc = 0;
        for (final b in current.spotBalances) {
          if (b.coin == 'USDC') {
            spotUsdc = b.available;
            break;
          }
        }
        if (spotUsdc + 1e-6 < usd) {
          final shortfall = usd - spotUsdc;
          if (current.withdrawable + 1e-6 < shortfall) {
            throw const HyperliquidInsufficientMarginException(
                'Insufficient USDC across spot and perp for this order');
          }
          // Round the transfer up to a cent, capped at what perp can
          // give — usdClassTransfer THROWS on rejection, aborting the
          // order before anything is placed.
          final xfer = math.min(
            current.withdrawable,
            (shortfall * 100).ceilToDouble() / 100,
          );
          await collectOwnDexCash(
              model: ref.read(hyperliquidTradingModelProvider),
              exchange: ex,
              requiredDefaultUsd: xfer);
          await ex.usdClassTransfer(amount: xfer, toPerp: false);
        }
      }

      final refPx = _referencePx(market);
      var size = sizeFromUsd(
        usd: usd,
        px: refPx,
        szDecimals: market.szDecimals,
      );
      if (!isBuy) {
        // Selling "everything" via a USD amount can round a hair above
        // the held balance — clamp to what's actually available.
        for (final b in current.spotBalances) {
          if (b.coin == market.coin && b.available > 0) {
            size = math.min(size, flooredSize(b.available, market.szDecimals));
            break;
          }
        }
      }

      final builder = await _builderFee();
      final result = await ex.placeMarketOrder(
        market: market,
        isBuy: isBuy,
        size: size,
        referencePx: refPx,
        slippage: slippagePct / 100,
        cloid: cloid ?? newHlCloid(),
        builder: builder,
      );

      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: 'spot',
        isBuy: isBuy,
        leverage: 1,
        marginUsd: usd,
        notionalUsd: usd,
        source: source,
        providerOrderId: result.oid?.toString(),
        orderType: 'market',
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: 'spot',
        builderFeeApplied: builder != null,
      );
      // Spot-sale proceeds land on the SPOT side, which nothing in the
      // app can withdraw (the withdraw cap reads perp withdrawable
      // only) — sweep them to perp so selling a holding is money the
      // user can actually take out. Best-effort; a failure leaves the
      // USDC in spot exactly as before, retried on the next sell.
      if (!isBuy && result.isFilled) {
        unawaited(_sweepSpotUsdcToPerp());
      }
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: isBuy ? 'open' : 'close',
          orderType: 'market',
          isBuy: isBuy,
          notionalUsd: usd,
          leverage: 1);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Moves ALL spendable spot USDC to the perp side (see the sell path
  /// above). Sweeping the whole balance rather than just the sale's
  /// proceeds is deliberate: resting spot USDC has no purpose in this
  /// app — buys auto-fund from perp — so any residue is equally stuck.
  Future<void> _sweepSpotUsdcToPerp() async {
    try {
      final address = _address;
      final ex = _exchange;
      if (address == null || ex == null) return;
      // Give the fill a beat to settle into the clearinghouse state.
      await Future<void>.delayed(const Duration(seconds: 2));
      final model = ref.read(hyperliquidTradingModelProvider);
      final snap = await model.getAccountSnapshot(address);
      double spotUsdc = 0;
      for (final b in snap.spotBalances) {
        if (b.coin == 'USDC') {
          spotUsdc = b.available;
          break;
        }
      }
      final amount = (spotUsdc * 100).floorToDouble() / 100;
      if (amount < 0.01) return;
      await ex.usdClassTransfer(amount: amount, toPerp: true);
      _afterAction();
    } catch (_) {
      // Funds stay in spot exactly as before this sweep existed.
    }
  }

  /// Closes [fraction] of the open perp position on [coin] with a
  /// reduce-only IOC order. The coin joins pendingCloseCoins ("Closing…"
  /// card state) until the account snapshot confirms the size dropped.
  Future<HlOrderResult> closePosition({
    required String coin,
    double fraction = 1.0,
    double slippagePct = 1.0,
    required AuthGrant grant,
  }) async {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    HlPerpPosition? position;
    var marked = false;
    // Every step sits inside the try so a close stopped before signing
    // (capability, no position, onboarding, market, grant) still reports.
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.close');
      if (slippagePct != 1.0) {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      }
      final state0 = state.valueOrNull ?? const HyperliquidTradingState();
      for (final p in state0.positions) {
        if (p.coin == coin) {
          position = p;
          break;
        }
      }
      final pos = position;
      if (pos == null) {
        throw StateError('No open position for $coin');
      }

      await ensureOnboarded();
      final ex = _exchange!;
      final market = await _resolvePerpMarket(coin);
      // Phase 1b.3: consume before the close is signed.
      GrantGuard.consume(
        grant,
        HlIntents.close(
          walletId: _walletId ?? '',
          market: market,
          positionIsLong: pos.isLong,
          fraction: fraction,
          slippagePct: slippagePct,
        ),
        allowed: _hlOrderActions,
      );
      // Full closes send the exact exchange-reported size (already a
      // multiple of the lot size); partials floor to szDecimals.
      final size = clamped >= 0.999
          ? pos.szi.abs()
          : flooredSize(pos.szi.abs() * clamped, market.szDecimals);

      _closeBaselines[coin] = (absSzi: pos.szi.abs(), at: DateTime.now());
      _setData(state0.copyWith(
        pendingCloseCoins: {...state0.pendingCloseCoins, coin},
      ));
      marked = true;

      final builder = await _builderFee();
      final refPx = _referencePx(market);
      final result = await ex.placeMarketOrder(
        market: market,
        isBuy: !pos.isLong,
        size: size,
        referencePx: refPx,
        slippage: slippagePct / 100,
        reduceOnly: true,
        cloid: newHlCloid(),
        builder: builder,
      );

      TrackingService.hyperliquidPositionClosed(
        coin: coin,
        fractionPct: (clamped * 100).round().clamp(1, 100),
        payoutUsd: result.filledSz * result.avgPx,
        pnlUsd: pos.unrealizedPnl * clamped,
        providerOrderId: result.oid?.toString(),
        wasLong: pos.isLong,
        leverage: pos.leverageValue,
        walletKind: 'hot',
        orderType: 'market',
        notionalUsd: size * refPx,
      );
      _afterAction();
      return result;
    } catch (e, st) {
      if (marked) {
        // Roll the "Closing…" marker back so the card is actionable again.
        _closeBaselines.remove(coin);
        final s = _current;
        if (s != null) {
          _setData(s.copyWith(
            pendingCloseCoins: {...s.pendingCloseCoins}..remove(coin),
          ));
        }
      }
      final pos = position;
      _reportOrderFailure(coin, e, st,
          action: 'close',
          orderType: 'market',
          isBuy: pos == null ? null : !pos.isLong,
          notionalUsd: pos == null ? null : pos.positionValue.abs() * clamped,
          leverage: pos?.leverageValue);
      rethrow;
    }
  }

  /// Writes the per-asset leverage + margin mode when it differs from the
  /// resting setting (always written when flat — the resting value is
  /// unknown). Isolated is forced when the market is isolated-only. No-op
  /// for spot. Centralises what openPosition used to inline so every order
  /// method applies the margin mode consistently.
  /// The policy gates an order needs: an exit (reduce-only) answers to
  /// closing alone; anything else is new exposure and needs opening
  /// investments plus, on a stock-linked perp, the stock-perp gate.
  static List<String> _orderCapabilities(HlMarket market, bool reduceOnly) =>
      reduceOnly ? const ['hyperliquid.close'] : hlOpenCapabilities(market);

  ///
  /// An OPEN POSITION's leverage and margin mode are never changed as a
  /// side effect: unless [changeOpenPosition] (the person moved the
  /// ticket's leverage or margin mode themselves, and the grant they
  /// approved carries those values), an order on a market with a position
  /// leaves the venue setting alone and trades at the position's own
  /// leverage. The ticket starts from the position's values anyway.
  Future<void> _ensureLeverage(
    HlMarket market,
    HyperliquidTradingState current,
    int lev,
    bool? isCross, {
    bool changeOpenPosition = false,
  }) async {
    if (market.isSpot) return;
    // The region's leverage cap, checked before the venue is asked to set
    // the leverage; the Ledger order path makes the same check.
    RuntimeCapabilitiesService.instance.ensureLeverageAllowed(lev);
    HlPerpPosition? existing;
    for (final p in current.positions) {
      if (p.coin == market.wireCoin) {
        existing = p;
        break;
      }
    }
    if (existing != null && !changeOpenPosition) return;
    final effCross =
        (isCross ?? existing?.isCross ?? true) && !market.onlyIsolated;
    if (existing == null ||
        existing.leverageValue != lev ||
        existing.isCross != effCross) {
      await _exchange!.updateLeverage(
        assetId: market.assetId,
        isCross: effCross,
        leverage: lev,
      );
      // A side effect of placing an order, not a user choice.
      TrackingService.hyperliquidLeverageAdjusted(
          coin: market.coin,
          leverage: lev,
          source: 'order_auto',
          isCross: effCross);
    }
  }

  // `_tryAttachTpSl` (the post-open best-effort trigger attach) is gone:
  // TP/SL now rides in the SAME 'normalTpsl'-grouped action as the
  // parent order, so the exchange sizes triggers to the actual fill,
  // OCO-cancels them, and a placement problem surfaces on the result
  // instead of vanishing into a silent catch.

  /// Applies the perp margin mode + leverage for [market] on its own
  /// (updateLeverage). Isolated is forced when the market is isolated-only.
  /// No-op for spot. Exposed for the order slip's margin-mode toggle.
  Future<void> setMarginMode({
    required HlMarket market,
    required bool isCross,
    required int leverage,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(hlOpenCapabilities(market));
    if (market.isSpot) return;
    await ensureOnboarded();
    // Phase 1b.3: a leverage or margin mode change on its own needs its
    // own grant (an order's grant covers the write inside the order).
    GrantGuard.consume(
      grant,
      HlIntents.marginMode(
        walletId: _walletId ?? '',
        market: market,
        isCross: isCross,
        leverage: leverage,
      ),
      allowed: _hlOrderActions,
    );
    final lev = leverage.clamp(1, market.maxLeverage).toInt();
    RuntimeCapabilitiesService.instance.ensureLeverageAllowed(lev);
    await _exchange!.updateLeverage(
      assetId: market.assetId,
      isCross: isCross && !market.onlyIsolated,
      leverage: lev,
    );
    TrackingService.hyperliquidLeverageAdjusted(
        coin: market.coin,
        leverage: lev,
        source: 'user',
        isCross: isCross && !market.onlyIsolated);
  }

  /// Places a resting/marketable limit order. Sizing accepts either an
  /// explicit coin [size] or a USD [marginUsd] (× leverage / px). Sets the
  /// perp leverage/margin-mode first (unless [reduceOnly]). [postOnly]
  /// forces tif 'Alo'. Optional [takeProfitPx]/[stopLossPx] attach
  /// reduce-only triggers after the order (best-effort). Returns filled or
  /// resting.
  Future<HlOrderResult> placeLimit({
    required HlMarket market,
    required bool isLong,
    double? marginUsd,
    double? size,
    int leverage = 1,
    bool? isCross,
    required double px,
    String tif = 'Gtc',
    bool postOnly = false,
    bool reduceOnly = false,
    double? takeProfitPx,
    double? stopLossPx,
    String? source,
    String? cloid,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.limit(
          walletId: _walletId ?? '',
          market: market,
          isLong: isLong,
          marginUsd: marginUsd,
          size: size,
          leverage: leverage,
          isCross: isCross,
          px: px,
          tif: tif,
          postOnly: postOnly,
          reduceOnly: reduceOnly,
          takeProfitPx: takeProfitPx,
          stopLossPx: stopLossPx,
        ),
        allowed: _hlOrderActions,
      );
      final lev =
          market.isSpot ? 1 : leverage.clamp(1, market.maxLeverage).toInt();
      if (!reduceOnly) {
        await _ensureLeverage(market, current, lev, isCross,
            changeOpenPosition: changeOpenPosition);
      }
      final coinSize = size ??
          sizeFromUsd(
              usd: (marginUsd ?? 0) * lev,
              px: px,
              szDecimals: market.szDecimals);
      if (!market.isSpot && !reduceOnly) {
        await _fundPerpAction(market, marginUsd ?? coinSize * px / lev,
            leverage: lev);
      }
      final builder = await _builderFee();
      final wantsTpsl = !reduceOnly &&
          ((takeProfitPx != null && takeProfitPx > 0) ||
              (stopLossPx != null && stopLossPx > 0));
      // TP/SL rides in the SAME 'normalTpsl'-grouped action (see
      // placeMarketOrder): fill-sized, OCO, never silently missing.
      final result = wantsTpsl
          ? await ex.placeOrderWithTpsl(
              market: market,
              isBuy: isLong,
              px: roundPrice(px,
                  szDecimals: market.szDecimals, isSpot: market.isSpot),
              sz: roundSize(coinSize, market.szDecimals),
              tif: postOnly ? 'Alo' : tif,
              takeProfitPx: takeProfitPx,
              stopLossPx: stopLossPx,
              cloid: cloid ?? newHlCloid(),
              builder: builder,
            )
          : await ex.placeLimitOrder(
              assetId: market.assetId,
              isBuy: isLong,
              px: roundPrice(px,
                  szDecimals: market.szDecimals, isSpot: market.isSpot),
              sz: roundSize(coinSize, market.szDecimals),
              tif: postOnly ? 'Alo' : tif,
              reduceOnly: reduceOnly,
              cloid: cloid ?? newHlCloid(),
              builder: builder,
            );
      final notional = coinSize * px;
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        isBuy: isLong,
        leverage: lev,
        marginUsd: marginUsd ?? (lev > 0 ? notional / lev : notional),
        notionalUsd: notional,
        source: source,
        providerOrderId: result.oid?.toString(),
        orderType: 'limit',
        reduceOnly: reduceOnly,
        isCross: _crossFor(market, isCross, reduceOnly: reduceOnly),
        hasTp: wantsTpsl && takeProfitPx != null && takeProfitPx > 0,
        hasSl: wantsTpsl && stopLossPx != null && stopLossPx > 0,
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        builderFeeApplied: builder != null,
        limitPrice: px,
      );
      _trackTpslLegFailure(market, result,
          wantedTpsl: wantsTpsl, parentType: 'limit');
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: reduceOnly ? 'close' : 'open',
          orderType: 'limit',
          isBuy: isLong,
          notionalUsd: size != null ? size * px : (marginUsd ?? 0) * leverage,
          leverage: leverage);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Places a stop / take-profit trigger order (Stop-Market/Take-Market
  /// when [isMarket], else Stop-Limit/Take-Limit resting at [limitPx]).
  /// [isLong] is the ORDER side (buy=true); [tpsl] ∈ {'tp','sl'}. Defaults
  /// reduce-only (the common "protect a position" case).
  Future<HlOrderResult> placeTrigger({
    required HlMarket market,
    required bool isLong,
    required double size,
    required double triggerPx,
    required bool isMarket,
    required String tpsl,
    double? limitPx,
    bool reduceOnly = true,
    String? source,
    String? cloid,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.trigger(
          walletId: _walletId ?? '',
          market: market,
          isLong: isLong,
          size: size,
          triggerPx: triggerPx,
          isMarket: isMarket,
          tpsl: tpsl,
          limitPx: limitPx,
          reduceOnly: reduceOnly,
        ),
        allowed: _hlOrderActions,
      );
      final builder = await _builderFee();
      final result = await ex.placeTriggerOrder(
        market: market,
        isBuy: isLong,
        size: size,
        triggerPx: triggerPx,
        isMarket: isMarket,
        tpsl: tpsl,
        limitPx: limitPx,
        reduceOnly: reduceOnly,
        cloid: cloid ?? newHlCloid(),
        builder: builder,
      );
      final notional = size * triggerPx;
      // A trigger protecting a position carries that position's leverage
      // and the share of its margin the trigger covers.
      HlPerpPosition? position;
      if (!market.isSpot) {
        for (final p in current.positions) {
          if (p.coin == market.wireCoin) {
            position = p;
            break;
          }
        }
      }
      final posLev = position?.leverageValue ?? 1;
      final posAbs = position?.szi.abs() ?? 0;
      final marginUsd = position != null && posAbs > 0
          ? position.marginUsed * (size / posAbs).clamp(0.0, 1.0)
          : notional;
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        isBuy: isLong,
        leverage: position != null ? posLev : 1,
        marginUsd: marginUsd,
        notionalUsd: notional,
        source: source,
        providerOrderId: result.oid?.toString(),
        orderType: tpsl,
        reduceOnly: reduceOnly,
        isCross: position?.isCross,
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        builderFeeApplied: builder != null,
        limitPrice: isMarket ? null : limitPx,
      );
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: 'trigger',
          orderType: tpsl,
          isBuy: isLong,
          notionalUsd: size * triggerPx);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Moves a resting order to [newPx] with the venue's atomic modify. A
  /// limit keeps its side, remaining size, reduce-only flag and time in
  /// force; a trigger keeps its kind and moves its trigger price, with a
  /// limit trigger's resting price shifted by the same amount. The grant
  /// covers exactly this order and price.
  Future<HlOrderResult> modifyOrder({
    required HlMarket market,
    required HlOpenOrder order,
    required double newPx,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, order.reduceOnly));
    if (order.isTrailingStop) {
      throw StateError('A trailing stop cannot be moved by price.');
    }
    final tpsl = order.isTrigger ? order.tpsl : null;
    if (order.isTrigger && tpsl == null) {
      throw StateError('This order cannot be moved from the chart.');
    }
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      GrantGuard.consume(
        grant,
        HlIntents.modify(
          walletId: _walletId ?? '',
          market: market,
          oid: order.oid,
          isLong: order.isBuy,
          size: order.sz,
          px: newPx,
          reduceOnly: order.reduceOnly,
          tif: order.tif,
          tpsl: tpsl,
          isMarket: order.isMarketTrigger,
        ),
        allowed: _hlOrderActions,
      );
      final String px;
      final Map<String, dynamic> type;
      if (tpsl != null) {
        final trig = roundPrice(newPx,
            szDecimals: market.szDecimals, isSpot: market.isSpot);
        if (order.isMarketTrigger) {
          px = slippagePrice(
              referencePx: newPx,
              isBuy: order.isBuy,
              slippage: 0.05,
              szDecimals: market.szDecimals,
              isSpot: market.isSpot);
        } else {
          final shifted =
              order.limitPx + (newPx - (order.triggerPx ?? order.limitPx));
          px = roundPrice(shifted > 0 ? shifted : newPx,
              szDecimals: market.szDecimals, isSpot: market.isSpot);
        }
        type = triggerOrderType(
            isMarket: order.isMarketTrigger, triggerPx: trig, tpsl: tpsl);
      } else {
        px = roundPrice(newPx,
            szDecimals: market.szDecimals, isSpot: market.isSpot);
        type = limitOrderType(order.tif);
      }
      final result = await ex.modifyOrder(
        oid: order.oid,
        market: market,
        isBuy: order.isBuy,
        size: order.sz,
        px: px,
        reduceOnly: order.reduceOnly,
        orderType: type,
        cloid: newHlCloid(),
      );
      TrackingService.track('hyperliquid_order_modified', params: {
        'coin': market.coin,
        'trigger': tpsl != null,
      });
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: 'modify',
          orderType: tpsl ?? 'limit',
          isBuy: order.isBuy,
          notionalUsd: order.sz * newPx);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Places a scale order — [count] resting legs spread evenly across
  /// [startPx]..[endPx], splitting the [totalUsd] margin (× leverage =
  /// notional) equally. Sets leverage/margin-mode first (unless
  /// [reduceOnly]).
  Future<HlOrderResult> placeScale({
    required HlMarket market,
    required bool isLong,
    required double totalUsd,
    required double startPx,
    required double endPx,
    required int count,
    int leverage = 1,
    bool? isCross,
    bool reduceOnly = false,
    String? source,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.scale(
          walletId: _walletId ?? '',
          market: market,
          isLong: isLong,
          totalUsd: totalUsd,
          startPx: startPx,
          endPx: endPx,
          count: count,
          leverage: leverage,
          isCross: isCross,
          reduceOnly: reduceOnly,
        ),
        allowed: _hlOrderActions,
      );
      final lev =
          market.isSpot ? 1 : leverage.clamp(1, market.maxLeverage).toInt();
      if (!reduceOnly) {
        await _ensureLeverage(market, current, lev, isCross,
            changeOpenPosition: changeOpenPosition);
      }
      final avgPx = (startPx + endPx) / 2;
      final notional = totalUsd * lev;
      final totalSize = sizeFromUsd(
        usd: notional,
        px: avgPx > 0 ? avgPx : startPx,
        szDecimals: market.szDecimals,
      );
      if (!market.isSpot && !reduceOnly) {
        await _fundPerpAction(market, totalUsd, leverage: lev);
      }
      final builder = await _builderFee();
      final result = await ex.placeScaleOrder(
        market: market,
        isBuy: isLong,
        totalSize: totalSize,
        startPx: startPx,
        endPx: endPx,
        count: count,
        reduceOnly: reduceOnly,
        builder: builder,
      );
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        isBuy: isLong,
        leverage: lev,
        marginUsd: totalUsd,
        notionalUsd: notional,
        source: source,
        providerOrderId: result.oid?.toString(),
        orderType: 'scale',
        reduceOnly: reduceOnly,
        isCross: _crossFor(market, isCross, reduceOnly: reduceOnly),
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        builderFeeApplied: builder != null,
      );
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: reduceOnly ? 'close' : 'open',
          orderType: 'scale',
          isBuy: isLong,
          notionalUsd: totalUsd * leverage,
          leverage: leverage);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Places a TWAP order — the exchange works [marginUsd]×leverage (or an
  /// explicit coin [size]) over [durationMinutes] (5 minutes..7 days). Sets
  /// leverage/margin-mode first (unless [reduceOnly]). Signed via the L1
  /// twapOrder action.
  Future<HlOrderResult> placeTwap({
    required HlMarket market,
    required bool isLong,
    double? marginUsd,
    double? size,
    int leverage = 1,
    bool? isCross,
    required int durationMinutes,
    bool randomize = false,
    bool reduceOnly = false,
    String? source,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) async {
    final requestedWalletId =
        pickSpendingWallet(ref.read(settingsProvider))?.id;
    final sessionAuth = ref.read(sessionAuthProvider);
    void ensureCurrent() {
      if (_disposed || sessionAuth == null) throw const SeedLockedException();
      if (!ref.read(sessionUnlockedProvider) ||
          !identical(ref.read(sessionAuthProvider), sessionAuth)) {
        throw const SeedLockedException();
      }
      if (requestedWalletId == null ||
          pickSpendingWallet(ref.read(settingsProvider))?.id !=
              requestedWalletId) {
        throw StateError('Wallet changed before timed order submission');
      }
    }

    ensureCurrent();
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    ensureCurrent();
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      ensureCurrent();
      final ex = _exchange!;
      final walletId = _walletId;
      void ensureSubmissionCurrent() {
        ensureCurrent();
        if (walletId != requestedWalletId ||
            _walletId != walletId ||
            !identical(_exchange, ex) ||
            _address?.toLowerCase() != ex.walletAddress.toLowerCase()) {
          throw StateError('Timed order account changed');
        }
      }

      ensureSubmissionCurrent();
      // Phase 1b.3: consume the grant before anything is signed. The
      // order's grant also covers its leverage write and funding
      // transfer.
      GrantGuard.consume(
        grant,
        HlIntents.twap(
          walletId: _walletId ?? '',
          market: market,
          isLong: isLong,
          marginUsd: marginUsd,
          size: size,
          leverage: leverage,
          isCross: isCross,
          durationMinutes: durationMinutes,
          randomize: randomize,
          reduceOnly: reduceOnly,
        ),
        allowed: _hlOrderActions,
      );
      final lev =
          market.isSpot ? 1 : leverage.clamp(1, market.maxLeverage).toInt();
      late final double refPx;
      late final double coinSize;
      final result = await HotHyperliquidTwapGuard().run(
        walletId: walletId!,
        address: ex.walletAddress,
        coin: market.coin,
        ensureCurrent: ensureSubmissionCurrent,
        send: (beforeSubmit, beforeSend) async {
          ensureSubmissionCurrent();
          if (!reduceOnly) {
            await _ensureLeverage(market, current, lev, isCross,
            changeOpenPosition: changeOpenPosition);
          }
          ensureSubmissionCurrent();
          refPx = _referencePx(market);
          coinSize = size ??
              sizeFromUsd(
                  usd: (marginUsd ?? 0) * lev,
                  px: refPx,
                  szDecimals: market.szDecimals);
          if (!market.isSpot && !reduceOnly) {
            await _fundPerpAction(market, marginUsd ?? coinSize * refPx / lev,
                leverage: lev);
          }
          ensureSubmissionCurrent();
          return ex.placeTwapOrder(
            market: market,
            isBuy: isLong,
            size: coinSize,
            durationMinutes: durationMinutes,
            referencePx: refPx,
            randomize: randomize,
            reduceOnly: reduceOnly,
            beforeSubmit: beforeSubmit,
            beforeSend: beforeSend,
          );
        },
      );
      final notional = coinSize * refPx;
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        isBuy: isLong,
        leverage: lev,
        marginUsd: marginUsd ?? (lev > 0 ? notional / lev : notional),
        notionalUsd: notional,
        source: source,
        orderType: 'twap',
        reduceOnly: reduceOnly,
        isCross: _crossFor(market, isCross, reduceOnly: reduceOnly),
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        // The twapOrder action carries no builder field.
        builderFeeApplied: false,
      );
      // The result's oid IS the twapId (see _twapResultFromBody) — the
      // only handle twapCancel accepts. Remember it or the TWAP is
      // unstoppable the moment this sheet closes.
      final twapId = result.oid;
      if (twapId != null && _address != null) {
        _showRunningTwap(HlRunningTwap(
          twapId: twapId,
          assetId: market.assetId,
          coin: market.coin,
          address: ex.walletAddress,
          isBuy: isLong,
          reduceOnly: reduceOnly,
          size: coinSize,
          durationMinutes: durationMinutes,
          startedAt: DateTime.now(),
        ));
      }
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: 'twap',
          orderType: 'twap',
          isBuy: isLong,
          notionalUsd: marginUsd != null ? marginUsd * leverage : null,
          leverage: leverage);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  Future<HlOrderResult> placeTrailingStop({
    required HlMarket market,
    required bool isLong,
    required double size,
    required HlTrailingStop trail,
    int leverage = 1,
    bool? isCross,
    bool reduceOnly = false,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) async {
    final requested = pickSpendingWallet(ref.read(settingsProvider))?.id;
    final auth = ref.read(sessionAuthProvider);
    void ensureCurrent() {
      if (_disposed ||
          auth == null ||
          !ref.read(sessionUnlockedProvider) ||
          !identical(ref.read(sessionAuthProvider), auth) ||
          requested == null ||
          pickSpendingWallet(ref.read(settingsProvider))?.id != requested) {
        throw const SeedLockedException();
      }
    }

    ensureCurrent();
    trail.validate(
      market: market,
      isBuy: isLong,
      referencePrice: _referencePx(market),
    );
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    ensureCurrent();
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    if (current.isPlacingOrder) {
      throw StateError('An order is already being submitted.');
    }
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      ensureCurrent();
      final ex = _exchange!;
      void verifyAccount() {
        ensureCurrent();
        if (_walletId != requested ||
            !identical(_exchange, ex) ||
            _address?.toLowerCase() != ex.walletAddress.toLowerCase()) {
          throw StateError('Account changed. Review the trailing stop again.');
        }
      }

      verifyAccount();
      GrantGuard.consume(
        grant,
        HlIntents.trailingStop(
          walletId: requested!,
          market: market,
          isLong: isLong,
          size: size,
          trail: trail,
          leverage: leverage,
          isCross: isCross,
          reduceOnly: reduceOnly,
        ),
        allowed: _hlOrderActions,
      );
      await TrailingStopGuard().ensureAvailable(
        address: ex.walletAddress,
        assetId: market.assetId,
      );
      verifyAccount();
      final lev = leverage.clamp(1, market.maxLeverage).toInt();
      if (!reduceOnly) {
        await _ensureLeverage(market, current, lev, isCross,
            changeOpenPosition: changeOpenPosition);
        verifyAccount();
        await _fundPerpAction(
          market,
          size * _referencePx(market) / lev,
          leverage: lev,
          includeBuilderFee: false,
        );
      }
      verifyAccount();
      await RuntimeCapabilitiesService.instance.ensureAllowed(
        'trading.advanced',
      );
      await RuntimeCapabilitiesService.instance
          .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
      verifyAccount();
      final refPx = _referencePx(market);
      final result = await ex.placeTrailingStopOrder(
        market: market,
        isBuy: isLong,
        size: size,
        trail: trail,
        reduceOnly: reduceOnly,
        referencePrice: refPx,
        beforeSend: verifyAccount,
      );
      final notional = size * refPx;
      TrackingService.hyperliquidOrderPlaced(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        isBuy: isLong,
        leverage: lev,
        marginUsd: lev > 0 ? notional / lev : notional,
        notionalUsd: notional,
        orderType: 'trailing',
        reduceOnly: reduceOnly,
        isCross: _crossFor(market, isCross, reduceOnly: reduceOnly),
        filled: result.isFilled,
        walletKind: 'hot',
        marketType: _marketType(market),
        // This action carries no builder field.
        builderFeeApplied: false,
      );
      _afterAction();
      return result;
    } catch (e, st) {
      _reportOrderFailure(market.coin, e, st,
          action: 'trailing',
          orderType: 'trailing',
          isBuy: isLong,
          leverage: leverage);
      rethrow;
    } finally {
      final s = _current;
      if (s != null && s.isPlacingOrder) {
        _setData(s.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Adds ([usd] > 0) or removes ([usd] < 0) margin on the ISOLATED
  /// position on [market] (updateIsolatedMargin). Leverage, size and side
  /// are untouched; only the margin behind the position moves, and with it
  /// the liquidation price. The grant binds the market, the side and the
  /// exact amount and is consumed before anything is signed. Adding draws
  /// on the account's own cash (moved to the market's dex first when it is
  /// a builder dex); removing returns it there. Never reached for Ledger:
  /// the Ledger signer has no reviewed path for this action.
  Future<void> adjustIsolatedMargin({
    required HlMarket market,
    required HlPerpPosition position,
    required double usd,
    required AuthGrant grant,
  }) async {
    if (market.isSpot || position.isCross || usd == 0 || !usd.isFinite) {
      throw StateError('Margin can only be moved on an isolated position.');
    }
    if (usd < 0 && market.isolatedMarginLocked) {
      throw StateError('This market does not allow removing margin.');
    }
    // Adding margin only lowers risk; removing it raises the leverage, so
    // it answers to the same gates as opening.
    await RuntimeCapabilitiesService.instance.ensureAllAllowed(usd > 0
        ? const ['hyperliquid.close']
        : hlOpenCapabilities(market));
    await ensureOnboarded();
    final ex = _exchange!;
    GrantGuard.consume(
      grant,
      HlIntents.isolatedMargin(
        walletId: _walletId ?? '',
        market: market,
        positionIsLong: position.isLong,
        usd: usd,
      ),
      allowed: _hlOrderActions,
    );
    // The position must still be there, on the same side, isolated, and
    // be the very instrument [market] signs against.
    isolatedMarginTarget(
      market: market,
      position: position,
      live: _current?.positions ?? const <HlPerpPosition>[],
    );
    final amount = (usd.abs() * 1e6).floorToDouble() / 1e6;
    if (usd > 0) {
      // Moving margin is not a trade: no exchange or Kute fee is charged,
      // so exactly the amount is gathered (a fee on top made Max fail as
      // "insufficient" before anything was signed).
      await _fundPerpAction(market, amount,
          includeBuilderFee: false, tradingFee: false);
    }
    await ex.updateIsolatedMargin(
        assetId: market.assetId, usd: usd > 0 ? amount : -amount);
    _afterAction();
  }

  /// Cancels one resting order. [coin] is analytics-only; resolved from
  /// openOrders when omitted.
  Future<void> cancelOrder({
    required int assetId,
    required int oid,
    String? coin,
  }) async {
    HlOpenOrder? row;
    for (final o in _current?.openOrders ?? const <HlOpenOrder>[]) {
      if (o.oid == oid) {
        row = o;
        break;
      }
    }
    final resolved = (coin == null || coin.isEmpty) ? (row?.coin ?? '') : coin;
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.cancel');
      await ensureOnboarded();
      await _exchange!.cancelOrder(assetId: assetId, oid: oid);
    } catch (e) {
      _trackCancelFailed(scope: 'single', coin: resolved, error: e);
      rethrow;
    }

    final current = _current;
    TrackingService.hyperliquidOrderCancelled(
      coin: resolved,
      scope: 'single',
      orderType: row == null ? null : _openOrderType(row),
      walletKind: 'hot',
    );

    if (current != null) {
      _setData(current.copyWith(
        openOrders: current.openOrders.where((o) => o.oid != oid).toList(),
      ));
    }
    unawaited(_silentOrdersRefresh());
  }

  /// Cancels every resting order in one signed batch action.
  Future<int> cancelAllOrders() async {
    final cancels = <({int assetId, int oid})>[];
    final coins = <String>{};
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.cancel');
      final orders = _current?.openOrders ?? const <HlOpenOrder>[];
      if (orders.isEmpty) return 0;
      await ensureOnboarded();

      for (final o in orders) {
        coins.add(o.coin);
        // Orders carry WIRE coins ('xyz:TSLA', '@107'): resolve exactly,
        // never by display name.
        final market = ref.read(hyperliquidWireMarketProvider(o.coin));
        if (market != null) cancels.add((assetId: market.assetId, oid: o.oid));
      }
      if (cancels.length != orders.length) {
        // Cancel-all must not silently skip an order whose asset is
        // unresolved. Nothing has been submitted; keep every order
        // available for review.
        throw const HlCancellationIncompleteException();
      }
      try {
        await _exchange!.cancelOrders(cancels);
      } finally {
        // A mixed batch can cancel some orders before reporting a
        // rejection. Only an authoritative refresh may reconcile that
        // partial outcome.
        unawaited(_silentOrdersRefresh());
      }
    } catch (e) {
      _trackCancelFailed(
          scope: 'all', coin: coins.length == 1 ? coins.first : '', error: e);
      rethrow;
    }
    TrackingService.track('hl_cancel_all_orders', params: {
      'count': cancels.length,
      'count_bucket': _countBucket(cancels.length),
    });
    TrackingService.hyperliquidOrderCancelled(
      coin: coins.length == 1 ? coins.first : 'multiple',
      scope: 'all',
      walletKind: 'hot',
    );

    final current = _current;
    if (current != null) {
      final gone = {for (final c in cancels) c.oid};
      _setData(current.copyWith(
        openOrders:
            current.openOrders.where((o) => !gone.contains(o.oid)).toList(),
      ));
    }
    return cancels.length;
  }

  // ─────────────────────── WS event integration ───────────────────────
  // Called by hyperliquid_user_events_provider so open orders / fills
  // update in real time instead of waiting for the next 30 s poll.

  /// Applies orderUpdates frames: 'open' upserts, every terminal status
  /// (filled/canceled/rejected/marginCanceled/…) removes. The periodic
  /// poll remains the reconciliation backstop.
  void applyOrderUpdates(List<HlOrderUpdate> updates) {
    if (_disposed || updates.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;

    final byOid = <int, HlOpenOrder>{
      for (final o in current.openOrders) o.oid: o,
    };
    var touched = false;
    var sawUnknownOpen = false;
    for (final u in updates) {
      if (u.status == 'open') {
        final prev = byOid[u.oid];
        if (prev == null) sawUnknownOpen = true;
        byOid[u.oid] = HlOpenOrder(
          coin: u.coin,
          oid: u.oid,
          isBuy: u.isBuy,
          limitPx: u.limitPx,
          sz: u.sz,
          origSz: u.origSz,
          timestamp: u.timestamp,
          cloid: u.cloid,
          // The WS payload carries only the basic order; everything else
          // is kept from the REST row (tif and position TP/SL included,
          // so a later modify re-sends the right time in force).
          reduceOnly: prev?.reduceOnly ?? false,
          orderType: prev?.orderType ?? 'Limit',
          isTrigger: prev?.isTrigger ?? false,
          triggerPx: prev?.triggerPx,
          tif: prev?.tif ?? 'Gtc',
          isPositionTpsl: prev?.isPositionTpsl ?? false,
        );
        touched = true;
      } else if (byOid.remove(u.oid) != null) {
        touched = true;
      }
    }
    if (!touched) return;
    final orders = byOid.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _setData(current.copyWith(openOrders: orders));
    // A brand-new order seen only via WS carries default orderType /
    // trigger fields (the update payload doesn't include them) — pull
    // the full row from REST now instead of waiting out the 30 s poll,
    // so a fresh stop order doesn't render as "Limit" meanwhile.
    if (sawUnknownOpen) unawaited(_silentOrdersRefresh());
  }

  /// Prepends live WS fills to the recentFills ring (deduped on
  /// oid+time+size — partial fills of one order arrive as distinct
  /// events sharing an oid).
  void recordFills(List<HlFill> fills) {
    if (_disposed || fills.isEmpty) return;
    final address = _address;
    if (address != null) {
      unawaited(HyperliquidRevenue.recordFills(address, fills));
    }
    final current = state.valueOrNull;
    if (current == null) return;
    bool seen(HlFill f) => current.recentFills.any((e) =>
        e.oid == f.oid && e.time == f.time && e.sz == f.sz && e.px == f.px);
    final fresh = fills.where((f) => !seen(f)).toList();
    if (fresh.isEmpty) return;
    _setData(current.copyWith(
      recentFills: _capFills([...fresh.reversed, ...current.recentFills]),
    ));
  }

  // ──────────────────────────── failures ────────────────────────────

  /// The perp market the close path resolves for [coin]. Review sheets use
  /// it to build the same close intent `closePosition` rebuilds.
  Future<HlMarket> resolvePerpMarket(String coin) => _resolvePerpMarket(coin);

  Future<HlMarket> _resolvePerpMarket(String coin) async {
    // Positions carry the wire coin; match it exactly first so a builder
    // dex listing of the same ticker (flx:BTC) is never picked for BTC.
    final exact = ref.read(hyperliquidWireMarketProvider(coin));
    if (exact != null && !exact.isSpot) return exact;
    final perps = await ref.read(hyperliquidPerpMarketsProvider.future);
    for (final m in perps) {
      if (m.wireCoin == coin || (m.dex.isEmpty && m.coin == coin)) return m;
    }
    throw StateError('Unknown Hyperliquid market: $coin');
  }

  /// 'spot', 'perp', or the HIP-3 builder dex name for a builder market.
  static String _marketType(HlMarket m) =>
      m.isSpot ? 'spot' : (m.dex.isEmpty ? 'perp' : m.dex);

  /// The margin mode the order actually used: null for spot and for
  /// reduce-only orders (which never write the margin mode).
  static bool? _crossFor(HlMarket m, bool? isCross, {bool reduceOnly = false}) {
    if (m.isSpot || reduceOnly) return null;
    return (isCross ?? true) && !m.onlyIsolated;
  }

  static String _openOrderType(HlOpenOrder o) {
    if (o.isTrailingStop) return 'trailing';
    if (o.isTrigger) return o.tpsl ?? 'trigger';
    return 'limit';
  }

  static String _countBucket(int n) {
    if (n <= 1) return '1';
    if (n <= 5) return '2-5';
    if (n <= 10) return '6-10';
    return '11+';
  }

  /// A cancel that did not go through. No order ids leave the device.
  void _trackCancelFailed({
    required String scope,
    required String coin,
    required Object error,
  }) {
    TrackingService.track('hyperliquid_cancel_failed', params: {
      'scope': scope,
      if (coin.isNotEmpty) 'coin': coin,
      'reason': error is HlCancellationIncompleteException
          ? 'asset_unresolved'
          : TrackingService.errorCategory(error),
      'wallet_kind': 'hot',
    });
  }

  /// The parent order was accepted but its TP/SL leg was rejected (the
  /// exchange service folds that into [HlOrderResult.error]).
  void _trackTpslLegFailure(
    HlMarket market,
    HlOrderResult result, {
    required bool wantedTpsl,
    required String parentType,
  }) {
    if (!wantedTpsl || result.error == null) return;
    TrackingService.track('hyperliquid_tpsl_failed', params: {
      'coin': market.coin,
      'parent_type': parentType,
      'wallet_kind': 'hot',
    });
  }

  void _reportOrderFailure(
    String coin,
    Object e,
    StackTrace st, {
    required String action,
    String? orderType,
    bool? isBuy,
    double? notionalUsd,
    int? leverage,
  }) {
    // A grant failure (Phase 1b.3) threw before anything was signed. The
    // UI shows C8 or stops quietly; it is still reported, with its stage,
    // so every order that did not go out is visible.
    if (e is AuthGrantException) {
      TrackingService.hyperliquidOrderFailed(
        coin: coin,
        reason: switch (e) {
          ReauthRequired() => 'approval_details_changed',
          GrantRevoked() => 'approval_revoked',
          GrantExpired() => 'approval_expired',
          GrantConsumed() => 'approval_consumed',
        },
        action: action,
        orderType: orderType,
        isBuy: isBuy,
        notionalUsd: notionalUsd,
        leverage: leverage,
        walletKind: 'hot',
        extra: hlFailureParams(e),
      );
      return;
    }
    if (e is HyperliquidSignatureRejectedException) {
      // The exchange recovered a DIFFERENT address from our signature —
      // a signing bug on OUR side. Engineering alert via crash
      // reporting; never a user-facing toast.
      TrackingService.recordCrash(e, st,
          reason: 'hyperliquid_signature_rejected');
    }
    TrackingService.hyperliquidOrderFailed(
      coin: coin,
      reason: _reasonFor(e),
      action: action,
      orderType: orderType,
      isBuy: isBuy,
      notionalUsd: notionalUsd,
      leverage: leverage,
      walletKind: 'hot',
      extra: hlFailureParams(e),
    );
  }

  /// Maps the exchange-service error taxonomy onto the canonical
  /// TrackingErrorReasons vocabulary.
  String _reasonFor(Object e) {
    if (e is HyperliquidSignatureRejectedException) {
      return TrackingErrorReasons.signatureInvalid;
    }
    if (e is HyperliquidMinNotionalException) {
      return TrackingErrorReasons.amountBelowMin;
    }
    if (e is HyperliquidInsufficientMarginException) {
      return TrackingErrorReasons.insufficientFunds;
    }
    if (e is HyperliquidRejectedException) {
      return e.reason.toLowerCase().contains('nonce')
          ? TrackingErrorReasons.nonceRejected
          : TrackingErrorReasons.orderRejected;
    }
    if (e is TimeoutException) return TrackingErrorReasons.networkTimeout;
    if (HyperliquidExchangeService.isOfflineError(e)) {
      return TrackingErrorReasons.networkOffline;
    }
    if (e is HyperliquidApiException) return TrackingErrorReasons.httpError;
    return TrackingErrorReasons.unknown;
  }
}

/// Actions accepted by the order, close and leverage executors.
const Set<SensitiveAction> _hlOrderActions = {SensitiveAction.hlOrder};

final hyperliquidTradingProvider = AsyncNotifierProvider.autoDispose<
    HyperliquidTradingNotifier, HyperliquidTradingState>(
  HyperliquidTradingNotifier.new,
);
