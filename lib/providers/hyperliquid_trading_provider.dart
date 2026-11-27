import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidModel;
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
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart'
    show hlProtectiveOrdersFor;
import 'package:kute/services/hyperliquid/hl_optimistic_margin.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_activity.dart';
import 'package:kute/services/one_balance/venue_cash_released.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart';
import 'package:kute/services/hyperliquid/hl_trigger_guard.dart';
import 'package:kute/services/hyperliquid/hl_twap_rules.dart';
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
import 'package:kute/services/polymarket/order_poll_gate.dart';

/// A batch cancel the venue answered per order, with some still open
/// after it: [cancelled] went, [stillOpen] did not (what was already gone
/// is neither).
class HlCancelPartialException implements Exception {
  const HlCancelPartialException({
    required this.cancelled,
    required this.stillOpen,
    required this.reason,
  });
  final int cancelled;
  final int stillOpen;
  final String reason;
  @override
  String toString() =>
      'HlCancelPartialException($cancelled cancelled, $stillOpen still open: '
      '$reason)';
}

/// What became of a closed position's left-over protective orders.
typedef HlLeftoverSweep = ({int cancelled, int failed});

class _FullCloseArm {
  const _FullCloseArm({
    required this.absSzi,
    required this.wasLong,
    this.oid,
    this.twapId,
  });

  /// The position's size and side when the closing order was sent.
  final double absSzi;
  final bool wasLong;

  /// The closing order's handle, while it may rest: its cancel disarms.
  final int? oid;
  final int? twapId;
}

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

/// How long a perp closed in full stays off the account's positions while
/// the venue's reads still show it at its size before the close
/// ([hlPositionsAfterCloses]).
const Duration kHlClosedInFullHold = Duration(seconds: 60);

/// A perp closed in full, as the close's fill came back: its signed size
/// before the close and when.
typedef HlClosedInFull = ({double szi, DateTime at});

/// The account's [positions] without the perps closed in full ([closed],
/// by coin) that a read still shows at exactly their size before the
/// close: a read from before the venue indexed the close (the poll in
/// flight, or the account's previous answer given again while it
/// refreshes). So a closed position leaves the Portfolio and the Overview
/// the moment the close fills, not on the next poll (founder, 10 November
/// 2026, on 2.2.0 (101): "after selling an investment ... it still shows
/// up in the Overview for some seconds"). Also the closes still held: one
/// is let go once a read shows its coin gone or at another size (the
/// close indexed, or a new position opened), or after
/// [kHlClosedInFullHold]. Pure for the tests.
({List<HlPerpPosition> positions, Map<String, HlClosedInFull> held})
    hlPositionsAfterCloses(
  List<HlPerpPosition> positions,
  Map<String, HlClosedInFull> closed, {
  required DateTime now,
}) {
  if (closed.isEmpty) return (positions: positions, held: closed);
  final held = <String, HlClosedInFull>{};
  final kept = <HlPerpPosition>[];
  for (final p in positions) {
    final c = closed[p.coin];
    if (c != null &&
        now.difference(c.at) < kHlClosedInFullHold &&
        (p.szi - c.szi).abs() <= 1e-9 * c.szi.abs()) {
      held[p.coin] = c;
      continue;
    }
    kept.add(p);
  }
  return (
    positions: kept.length == positions.length ? positions : kept,
    held: held,
  );
}

/// The perp → spot transfer a spot buy of [usd] needs before it is placed,
/// from a FRESH read of the account ([spotBalances], [perpWithdrawable]):
/// zero when spot USDC covers it, else the shortfall rounded up to a cent
/// and capped at what perps can give. Throws when spot and perps together
/// do not cover it (nothing is signed).
double hlSpotBuyPerpTransferUsd({
  required double usd,
  required List<HlSpotBalance> spotBalances,
  required double perpWithdrawable,
}) {
  double spotUsdc = 0;
  for (final b in spotBalances) {
    if (b.coin == 'USDC') {
      spotUsdc = b.available;
      break;
    }
  }
  if (spotUsdc + 1e-6 >= usd) return 0;
  final shortfall = usd - spotUsdc;
  if (perpWithdrawable + 1e-6 < shortfall) {
    throw const HyperliquidInsufficientMarginException(
        'Insufficient USDC across spot and perp for this order');
  }
  // Round up to a cent, capped at what perp can give — usdClassTransfer
  // THROWS on rejection, aborting the order before anything is placed.
  return math.min(perpWithdrawable, (shortfall * 100).ceilToDouble() / 100);
}

/// The margin mode a new perp position opens in when nothing chose one:
/// ISOLATED (founder decision, October 2026). The cash a position does not
/// use is then never cross collateral, so it stays free for orders and
/// can come home without moving a liquidation price. An open position
/// keeps its own mode.
const bool kHlDefaultCross = false;

/// Refuses a modify the chart must never send: a trailing stop (no fixed
/// price), a row whose type only the WebSocket has seen (it may be a stop
/// shown at its guard price), a trigger the venue does not name as a take
/// profit or stop, and any order whose kind differs from the account's
/// own row for it (a trigger must never be re-sent as a limit, which
/// would fill at once).
void hlCheckModifiable(HlOpenOrder order, List<HlOpenOrder> openOrders) {
  if (order.isTrailingStop) {
    throw StateError('A trailing stop cannot be moved by price.');
  }
  if (!order.detailsKnown) {
    throw StateError('This order is still loading. Try again in a moment.');
  }
  if (order.isTrigger && order.tpsl == null) {
    throw StateError('This order cannot be moved from the chart.');
  }
  for (final o in openOrders) {
    if (o.oid != order.oid) continue;
    if (!o.detailsKnown ||
        o.isTrigger != order.isTrigger ||
        o.isTrailingStop ||
        (o.isTrigger && o.tpsl != order.tpsl)) {
      throw StateError('This order cannot be moved from the chart.');
    }
  }
}

/// [TrailingStopGuard]'s venue read for an unclear trailing-stop send
/// signed at [sentAtMs]: found when a trailing stop on [market] placed at
/// or after it (a few seconds' clock slack) is resting or in the order
/// history; absent when both lists read and neither has it. A read that
/// fails throws (the guard keeps blocking).
Future<TrailingStopVenueState> hlLookupTrailingStop({
  required HyperliquidModel model,
  required String address,
  required HlMarket market,
  required int sentAtMs,
}) async {
  bool match(HlOpenOrder o) =>
      o.isTrailingStop &&
      (o.coin == market.wireCoin || o.coin == market.coin) &&
      o.timestamp >= sentAtMs - 10000;
  final dexes = market.dex.isEmpty ? const <String>[] : [market.dex];
  final open = await model.getOpenOrders(address, dexes: dexes);
  if (open.any(match)) return TrailingStopVenueState.found;
  final history = await model.getHistoricalOrders(address, dex: market.dex);
  if (history.any(match)) return TrailingStopVenueState.found;
  return TrailingStopVenueState.absent;
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

  /// The perp dexes [positions] were read from ('' = the main dex), as the
  /// account read covered them ([HlAccountSnapshot.positionDexes]). A
  /// market on any other dex has an unknown position, and so does every
  /// market while [isInitialized] is false (hl_exposure_rule.dart).
  final Set<String> positionDexes;
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
    this.positionDexes = const {''},
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
    Set<String>? positionDexes,
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
      positionDexes: positionDexes ?? this.positionDexes,
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
        setEquals(positionDexes, other.positionDexes) &&
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

  /// Tests only: an exchange (MockClient-backed) in place of the derived
  /// signer, so the order and cancel paths run for real against canned
  /// answers.
  @visibleForTesting
  void debugUseExchange(HyperliquidExchangeService exchange,
      {required String walletId}) {
    _exchange = exchange;
    _walletId = walletId;
  }

  /// Tests only: an account snapshot, as the account provider's poll
  /// delivers it.
  @visibleForTesting
  void debugApplySnapshot(HlAccountSnapshot snap) => _applySnapshot(snap);

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

  /// The perps closed in full whose stale reads stay off the positions
  /// ([hlPositionsAfterCloses]).
  Map<String, HlClosedInFull> _closedInFull = const {};

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
    // Arms belong to the account they were set on.
    _fullCloseArms.clear();
    _leftoverSweeps.clear();
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
    var accountRead = false;
    try {
      snap = await ref.read(hyperliquidAccountProvider.future);
      accountRead = true;
    } catch (_) {
      // Account fetch failed. The account is UNKNOWN, not empty: the state
      // stays uninitialized (no $0.00 counted as the venue's answer, the
      // Investments total keeps its stale shimmer) until the account
      // provider's retry tick, or the next refresh, lands a snapshot;
      // [_applySnapshot] initializes it then.
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
      (_) {
        if (!OrderPollGate.paused) _silentOrdersRefresh();
      },
    );

    return HyperliquidTradingState(
      isInitialized: accountRead,
      walletAddress: address,
      perpEquity: snap.accountValue,
      totalMarginUsed: snap.totalMarginUsed,
      withdrawable: snap.withdrawable,
      positions: snap.positions,
      positionDexes: snap.positionDexes,
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
    _disarmByOrder(twapId: twap.twapId);
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

    // A perp closed in full stays gone while a read still shows it at its
    // size before the close.
    final afterCloses =
        hlPositionsAfterCloses(snap.positions, _closedInFull, now: now);
    _closedInFull = afterCloses.held;

    // Optimistic margin after a fill: keep the figures shown at the fill
    // until the venue's own margin moves off the pre-fill baseline (it
    // indexed the fill) or the hold's TTL passes; then the snapshot wins.
    final hold = _optimisticMargin;
    final keepHold = hold != null &&
        !hold.reconciledBy(snap.totalMarginUsed, now: now);
    if (!keepHold) _optimisticMargin = null;

    final next = current.copyWith(
      perpEquity: snap.accountValue,
      totalMarginUsed: keepHold ? hold.totalMarginUsed : snap.totalMarginUsed,
      withdrawable: keepHold ? hold.withdrawable : snap.withdrawable,
      positions: afterCloses.positions,
      positionDexes: snap.positionDexes,
      spotBalances: snap.spotBalances,
      pendingCloseCoins: pending,
      // A real snapshot: the figures are the venue's answer now (a build
      // whose first read failed starts uninitialized).
      isInitialized: true,
    );
    if (next != current) _setData(next);
    // A whole position this app closed, now gone: its left-over stops go.
    _checkFullCloseArms(afterCloses.positions);
  }

  // ───────────────────── optimistic margin after a fill ─────────────────────

  /// [position] closed in full: off the positions now, and kept off while
  /// a read still shows it at its size ([hlPositionsAfterCloses]).
  void _dropClosedInFull(HlPerpPosition position) {
    final s = _current;
    if (s == null) return;
    _closedInFull = {
      ..._closedInFull,
      position.coin: (szi: position.szi, at: DateTime.now()),
    };
    _setData(s.copyWith(
      positions: [
        for (final p in s.positions)
          if (p.coin != position.coin) p,
      ],
    ));
    // Gone now: the closing order was this app's own (closePosition).
    _startLeftoverSweep(position.coin);
  }

  // ─────────── left-over protective orders after a full close ───────────
  //
  // ONE place for every path that ends with a position at zero: the close
  // sheet's market close, the order slip's close (closePosition), a limit
  // or TWAP close sized to the whole position, and an opposite-side order
  // on the slip that nets it to exactly zero. A reduce-only stop, take or
  // trailing stop left on a flat market could close a position opened
  // there later, so the coin's protective orders are cancelled, and only
  // when all of this holds:
  //
  //   * this app sent the order that closes the WHOLE position, in this
  //     session ([_armFullClose]; a partial close arms nothing);
  //   * the app saw the position open when it sent it, and now sees it
  //     gone (the fill of closePosition, or an account snapshot with no
  //     position on the coin: [_checkFullCloseArms]). A resting limit or
  //     a TWAP is never swept on acceptance, only once the position is
  //     actually gone;
  //   * the position is still gone after the open orders are read again
  //     right before the cancel.
  //
  // Only protective orders ([hlProtectiveOrdersFor]: trigger or trailing,
  // reduce-only or position TP/SL) are cancelled, never an entry or a
  // plain limit. The arm drops if its closing order is cancelled, or if
  // the position grows past what the close was sized for or flips side.
  // The user's own Confirm of that close is the consent: the close sheet
  // says so before it is sent ("Closing all of it also cancels its stop
  // and take-profit orders").

  final Map<String, _FullCloseArm> _fullCloseArms = {};
  final Map<String, Future<HlLeftoverSweep>> _leftoverSweeps = {};

  /// The cancel of [coin]'s left-over protective orders started when its
  /// position was seen gone after this app closed it, or null when none
  /// started (not closed in full here, or nothing to cancel). The close
  /// sheet awaits it for its receipt.
  Future<HlLeftoverSweep>? leftoverSweepFor(String coin) =>
      _leftoverSweeps[coin];

  /// Arms the sweep when the order this app just had accepted closes the
  /// whole of [held] ([orderIsBuy] on the other side, sized to it within
  /// one lot step; a reduce-only order sized past it also closes it).
  void _armFullClose({
    required HlMarket market,
    required HlPerpPosition? held,
    required bool orderIsBuy,
    required double size,
    required bool reduceOnly,
    int? oid,
    int? twapId,
  }) {
    if (market.isSpot || held == null || held.szi == 0) return;
    final plan = hlPositionPlan(
        position: held,
        orderIsLong: orderIsBuy,
        orderSize: size,
        szDecimals: market.szDecimals);
    final full = plan.effect == HlPositionEffect.close ||
        (reduceOnly && plan.effect == HlPositionEffect.flip);
    if (!full) return;
    _fullCloseArms[held.coin] = _FullCloseArm(
      absSzi: held.szi.abs(),
      wasLong: held.isLong,
      oid: oid,
      twapId: twapId,
    );
    // A fill can land (and a snapshot show it gone) before the order's
    // answer is back.
    final s = _current;
    if (s != null) _checkFullCloseArms(s.positions);
  }

  HlPerpPosition? _heldOn(HlMarket market) {
    if (market.isSpot) return null;
    for (final p in _current?.positions ?? const <HlPerpPosition>[]) {
      if (p.coin == market.wireCoin && p.szi != 0) return p;
    }
    return null;
  }

  /// An armed coin with no position left is swept; one that grew past
  /// the close or flipped side is disarmed.
  void _checkFullCloseArms(List<HlPerpPosition> positions) {
    if (_fullCloseArms.isEmpty) return;
    for (final coin in _fullCloseArms.keys.toList()) {
      final arm = _fullCloseArms[coin]!;
      HlPerpPosition? now;
      for (final p in positions) {
        if (p.coin == coin && p.szi != 0) {
          now = p;
          break;
        }
      }
      if (now == null) {
        _startLeftoverSweep(coin);
      } else if (now.isLong != arm.wasLong ||
          now.szi.abs() > arm.absSzi * (1 + 1e-9) + 1e-12) {
        _fullCloseArms.remove(coin);
      }
    }
  }

  void _disarmByOrder({int? oid, int? twapId}) {
    _fullCloseArms.removeWhere((_, arm) =>
        (oid != null && arm.oid == oid) ||
        (twapId != null && arm.twapId == twapId));
  }

  void _startLeftoverSweep(String coin) {
    _fullCloseArms.remove(coin);
    final sweep = _sweepLeftovers(coin);
    _leftoverSweeps[coin] = sweep;
    unawaited(sweep.then((_) {}, onError: (_) {}));
  }

  Future<HlLeftoverSweep> _sweepLeftovers(String coin) async {
    // The orders read again first: a stop first seen over the socket is
    // not described yet and would otherwise be missed.
    await _silentOrdersRefresh();
    final s = _current;
    if (s == null) return (cancelled: 0, failed: 0);
    // Never on a market where a position is open (again).
    if (s.positions.any((p) => p.coin == coin && p.szi != 0)) {
      return (cancelled: 0, failed: 0);
    }
    final leftovers = hlProtectiveOrdersFor(s.openOrders, coin);
    if (leftovers.isEmpty) return (cancelled: 0, failed: 0);
    try {
      final report = await _cancelListed(leftovers, reason: 'after_close');
      return (cancelled: report.cancelled.length, failed: report.failed.length);
    } catch (_) {
      // Unconfirmed: said as still open; the next read reconciles.
      return (cancelled: 0, failed: leftovers.length);
    }
  }

  HlOptimisticMargin? _optimisticMargin;

  void _holdOptimisticOpen(double marginUsd) {
    final s = _current;
    if (s == null || marginUsd <= 0) return;
    final hold = HlOptimisticMargin.afterOpen(
      withdrawable: s.withdrawable,
      totalMarginUsed: s.totalMarginUsed,
      marginUsd: marginUsd,
      at: DateTime.now(),
    );
    _optimisticMargin = hold;
    _setData(s.copyWith(
      withdrawable: hold.withdrawable,
      totalMarginUsed: hold.totalMarginUsed,
    ));
  }

  void _holdOptimisticClose(
      {required double marginReleasedUsd, required double realizedPnlUsd}) {
    final s = _current;
    if (s == null || marginReleasedUsd <= 0) return;
    final hold = HlOptimisticMargin.afterClose(
      withdrawable: s.withdrawable,
      totalMarginUsed: s.totalMarginUsed,
      marginReleasedUsd: marginReleasedUsd,
      realizedPnlUsd: realizedPnlUsd,
      at: DateTime.now(),
    );
    _optimisticMargin = hold;
    _setData(s.copyWith(
      withdrawable: hold.withdrawable,
      totalMarginUsed: hold.totalMarginUsed,
    ));
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
    // Order activity: Investing's cash stays put, and its idle window
    // (investing_sweep_rules.dart) starts again.
    VenueActivity.note(OneBalanceVenue.investing);
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

  /// Throws [HlTriggerCrossedException] when a protective trigger closing
  /// on [closeIsBuy] at [trigger] is on the wrong side of the freshest
  /// price ([_referencePx]): it would fire at once. No price, no check
  /// (the sheet checked it against the price it showed).
  void _ensureTriggerHolds(HlMarket market,
      {required bool closeIsBuy,
      required String tpsl,
      required double trigger}) {
    double mark;
    try {
      mark = _referencePx(market);
    } catch (_) {
      return;
    }
    if (hlTriggerCrossed(
        closeIsBuy: closeIsBuy, tpsl: tpsl, trigger: trigger, mark: mark)) {
      throw HlTriggerCrossedException(
          closeIsBuy: closeIsBuy, tpsl: tpsl, mark: mark);
    }
  }

  /// A direct deposit may credit either HyperCore clearinghouse. Move only
  /// the cash needed by this reviewed action into perps, after its grant was
  /// consumed. This never touches an external chain or an Arbitrum address.
  Future<void> _fundPerpAction(HlMarket market, double marginUsd,
      {int leverage = 1,
      double slippagePct = 0,
      bool includeBuilderFee = true,
      bool tradingFee = true}) async {
    // Moving Investing cash for an order holds it (InvestingCashLock), so
    // a send out of Investing never moves the same cash the other way.
    if (!InvestingCashLock.held) {
      return InvestingCashLock.run(() => _fundPerpAction(market, marginUsd,
          leverage: leverage,
          slippagePct: slippagePct,
          includeBuilderFee: includeBuilderFee,
          tradingFee: tradingFee));
    }
    final exchange = _exchange;
    final address = _address;
    if (exchange == null || address == null) {
      throw StateError('Account unavailable');
    }
    final model = ref.read(hyperliquidTradingModelProvider);
    // USDC funds USDC-settled dexes only (the fee read refuses the rest;
    // a fee-free margin move checks here), before anything moves.
    if (!tradingFee &&
        market.dex.isNotEmpty &&
        !await model.isUsdcCollateralDex(market.dex)) {
      throw const FormatException('USDC collateral terms unavailable');
    }
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
    if (shortfall <= 0) {
      OwnDexReadiness.ready();
      return;
    }
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
    OwnDexReadiness.waiting();
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
    // The money is in the dex; only its read lags. Nothing moves during
    // the wait, so it is long enough for a slow builder dex: the first
    // order on OPENAI used to give up after 8 s (and the second attempt,
    // finding the cash there, went through).
    await waitForOwnDexCash(
      requiredUsd: requiredUsd,
      maxWait: kOwnDexCreditWait,
      availableUsd: () async =>
          (await model.getDexClearinghouse(address, market.dex)).withdrawable,
    );
    OwnDexReadiness.ready();
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
      final lev = HlIntents.clampLeverage(market, leverage);
      // The exposure rule (hl_exposure_rule.dart), before anything is
      // funded or signed: on a market held above 1x or in cross only a
      // reduction goes, reduce-only; an add, a flip or an unknown position
      // is refused here. A plain order on a flat, loaded account reads
      // nothing more.
      final exposure = await exposureFor(market,
          isBuy: isLong,
          size: sizeFromUsd(
              usd: marginUsd * lev,
              px: _referencePx(market),
              szDecimals: market.szDecimals));
      final reduceOnly = exposure.check.mustReduceOnly;
      exposure.check.ensureAllows(
          // A reduction carries no TP/SL bracket: that is an open's.
          sentReduceOnly: takeProfitPx == null && stopLossPx == null);
      HlBuilderFee? builder;
      // Funding through placement holds the Investing cash
      // (InvestingCashLock): a Swap or Send pulling Investing cash at the
      // same moment waits for the order instead of moving the cash it is
      // funding the order with back out of the builder dex.
      final result = await InvestingCashLock.run(() async {
        // A reduction needs no margin and makes no leverage write.
        if (!reduceOnly) {
          await _fundPerpAction(market, marginUsd,
              leverage: lev, slippagePct: slippagePct);

          // 1) Leverage + margin mode: 1x isolated on a flat market, never
          //    on a held position.
          await _ensureLeverage(market, exposure.held, lev, isCross);
        }

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
        builder = await _builderFee();
        final orderCloid = cloid ?? newHlCloid();
        return _sendReconciled(
          () => ex.placeMarketOrder(
            market: market,
            isBuy: isLong,
            size: size,
            referencePx: refPx,
            slippage: slippagePct / 100,
            reduceOnly: reduceOnly,
            takeProfitPx: takeProfitPx,
            stopLossPx: stopLossPx,
            cloid: orderCloid,
            builder: builder,
          ),
          cloid: orderCloid,
          market: market,
          action: reduceOnly ? 'close' : 'open',
        );
      });

      // The exchange took the order: nothing below may turn that into a
      // failure (it is bookkeeping, and a throw from it used to reach the
      // slip as "failed").
      _afterAccepted(() {
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
          reduceOnly: reduceOnly,
          isCross: kHlCrossMarginOffered && (isCross ?? kHlDefaultCross) && !market.onlyIsolated,
          hasTp: hasTp,
          hasSl: hasSl,
          filled: result.isFilled,
          walletKind: 'hot',
          marketType: _marketType(market),
          builderFeeApplied: builder != null,
        );
        _trackTpslLegFailure(market, result,
            wantedTpsl: hasTp || hasSl, parentType: 'market');
        // A fill that adds margin: an open on a flat market, or an add to a
        // 1x isolated position (the exposure rule refuses adds to anything
        // else), so its margin is the filled notional at 1x. A reduction
        // locks none.
        if (result.isFilled && !reduceOnly) {
          // Margin locked by the fill, shown now; the next account poll
          // reconciles (see _applySnapshot).
          final filledMargin = result.avgPx > 0
              ? result.filledSz * result.avgPx / lev
              : marginUsd;
          _holdOptimisticOpen(filledMargin);
        }
        _afterAction();
      });
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
        // A fresh read, like the perp path's: a buy funded from Dollars
        // a moment ago credited after the last poll, and the held state
        // would call that money missing.
        var spotBalances = current.spotBalances;
        var perpWithdrawable = current.withdrawable;
        final address = _address;
        if (address != null) {
          try {
            final snap = await ref
                .read(hyperliquidTradingModelProvider)
                .getAccountSnapshot(address);
            spotBalances = snap.spotBalances;
            perpWithdrawable = snap.withdrawable;
          } catch (_) {
            // The held state stands in; the venue refuses what it lacks.
          }
        }
        final xfer = hlSpotBuyPerpTransferUsd(
            usd: usd,
            spotBalances: spotBalances,
            perpWithdrawable: perpWithdrawable);
        if (xfer > 0) {
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
      final orderCloid = cloid ?? newHlCloid();
      final result = await _sendReconciled(
        () => ex.placeMarketOrder(
          market: market,
          isBuy: isBuy,
          size: size,
          referencePx: refPx,
          slippage: slippagePct / 100,
          cloid: orderCloid,
          builder: builder,
        ),
        cloid: orderCloid,
        market: market,
        action: isBuy ? 'open' : 'close',
      );

      // Taken by the exchange: bookkeeping only from here (never a
      // failure).
      _afterAccepted(() {
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
      });
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
      // A sweep from an earlier close of this coin is not this close's.
      _leftoverSweeps.remove(coin);

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
      // multiple of the lot size). A partial is sized the way the venue
      // checks it ([hlPartialCloseSize]): one asked at the minimum or more
      // goes out at the first step that clears it at the IOC's price, so
      // a typed $10 close on a coarse-stepped market is not refused.
      final refPx = _referencePx(market);
      final size = hlMarketCloseSize(
          position: pos,
          fraction: clamped,
          market: market,
          referencePx: refPx,
          slippagePct: slippagePct);

      _closeBaselines[coin] = (absSzi: pos.szi.abs(), at: DateTime.now());
      _setData(state0.copyWith(
        pendingCloseCoins: {...state0.pendingCloseCoins, coin},
      ));
      marked = true;

      final builder = await _builderFee();
      final cloid = newHlCloid();
      // No answer from the venue (a slow builder dex can take the close
      // past the POST's budget): it may well have gone through. Found on
      // the account, the close is done as it stands; nowhere for the
      // whole window, not placed; unreadable, unconfirmed. Never sent
      // again.
      final result = await _sendReconciled(
        () => ex.placeMarketOrder(
          market: market,
          isBuy: !pos.isLong,
          size: size,
          referencePx: refPx,
          slippage: slippagePct / 100,
          reduceOnly: true,
          cloid: cloid,
          builder: builder,
        ),
        cloid: cloid,
        market: market,
        action: 'close',
      );

      _afterAccepted(() {
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
        if (result.isFilled &&
            pos.szi.abs() > 0 &&
            result.filledSz >= pos.szi.abs() * (1 - 1e-9)) {
          // Closed in full: the position leaves the lists now, not on the
          // next account poll ([hlPositionsAfterCloses]).
          _dropClosedInFull(pos);
        }
        if (result.isFilled && pos.szi.abs() > 0) {
          // Margin released (and PnL realised) by the fill, shown now; the
          // next account poll reconciles (see _applySnapshot).
          final closedFraction =
              (result.filledSz / pos.szi.abs()).clamp(0.0, 1.0).toDouble();
          _holdOptimisticClose(
            marginReleasedUsd: pos.marginUsed * closedFraction,
            realizedPnlUsd: pos.unrealizedPnl * closedFraction,
          );
        }
        _afterAction();
        // The margin (and any profit) is idle venue cash now: the sweeper
        // brings it home to Dollars at once instead of on its next pass.
        if (result.isFilled) {
          VenueCashReleased.emit(OneBalanceVenue.investing, 'close');
        }
      });
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

  /// [send] with its answer reconciled ([hlSendReconciled]): an order
  /// whose send got no verdict is looked up by [cloid] on the account
  /// before anything is said, with "Confirming with the exchange…" on the
  /// slip meanwhile ([hlConfirmingOrdersProvider]).
  Future<HlOrderResult> _sendReconciled(
    Future<HlOrderResult> Function() send, {
    required String cloid,
    List<String>? cloids,
    int? scaleLegs,
    required HlMarket market,
    required String action,
    Future<HlSentOrderTrace> Function(List<String> cloids, HlMarket m)?
        lookup,
  }) =>
      hlSendReconciled(
        send: send,
        cloid: cloid,
        cloids: cloids,
        scaleLegs: scaleLegs,
        market: market,
        lookup: lookup ?? ref.read(hlSentOrderTraceProvider),
        action: action,
        onConfirming: (on) {
          if (_disposed) return;
          final confirming = ref.read(hlConfirmingOrdersProvider.notifier);
          final now = {...confirming.state};
          on ? now.add(cloid) : now.remove(cloid);
          confirming.state = now;
          // By market too: a fresh ticket on it waits for this lookup.
          final markets = ref.read(hlConfirmingMarketsProvider.notifier);
          final byMarket = {...markets.state};
          on ? byMarket[cloid] = market.wireCoin : byMarket.remove(cloid);
          markets.state = byMarket;
        },
      );

  /// Bookkeeping after the exchange took an order (analytics, the
  /// optimistic margin, a refresh): never thrown out of, since the order
  /// is placed whatever happens here.
  void _afterAccepted(void Function() bookkeeping) {
    try {
      bookkeeping();
    } catch (e) {
      if (kDebugMode) debugPrint('[hl] after-accept bookkeeping threw: $e');
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
  /// An OPEN POSITION's leverage and margin mode are never changed: an
  /// order on a market with a position (opened here or elsewhere, at any
  /// leverage, cross or isolated) leaves the venue setting alone and trades
  /// at the position's own setting. On a flat market the write is always
  /// made (the resting value is unknown) and is always 1x isolated:
  /// leverage and cross margin are blocked in this app
  /// ([kHlMaxOfferedLeverage], [kHlCrossMarginOffered]).
  ///
  /// [held] is the position on [market] as positively known
  /// ([heldPositionFor]): an unknown position is refused before this
  /// ([hlExposureCheck]), never read as flat.
  Future<void> _ensureLeverage(
    HlMarket market,
    HlHeldPosition held,
    int lev,
    bool? isCross,
  ) async {
    if (market.isSpot) return;
    if (!held.known) {
      throw const HlExposureRefusedException(
          HlExposureRefusal.positionUnknown);
    }
    final write = leverageWriteFor(market, held.positions, lev);
    if (write == null) return;
    final appLev = write.leverage;
    final effCross = write.isCross;
    // The region's leverage cap, checked before the venue is asked to set
    // the leverage; the Ledger order path makes the same check.
    RuntimeCapabilitiesService.instance.ensureLeverageAllowed(appLev);
    await _exchange!.updateLeverage(
      assetId: market.assetId,
      isCross: effCross,
      leverage: appLev,
    );
    // A side effect of placing an order, not a user choice.
    TrackingService.hyperliquidLeverageAdjusted(
        coin: market.coin,
        leverage: appLev,
        source: 'order_auto',
        isCross: effCross);
  }

  /// The leverage write an order on [market] makes before it is placed:
  /// none on spot or while a position is open on the market (whatever its
  /// leverage or margin mode, it is never rewritten), else 1x isolated.
  @visibleForTesting
  static ({int leverage, bool isCross})? leverageWriteFor(
      HlMarket market, List<HlPerpPosition> positions, int requested) {
    if (market.isSpot) return null;
    for (final p in positions) {
      if (p.coin == market.wireCoin && p.szi != 0) return null;
    }
    return (
      leverage: hlAppLeverage(requested, market.maxLeverage),
      isCross: kHlCrossMarginOffered,
    );
  }

  /// The position on [market] as this account's state positively knows it:
  /// unknown while the account has not been read (or the last read
  /// failed), and for a market on a dex the read did not cover (the full
  /// read covers the main dex and the USDC-settled builder dexes).
  HlHeldPosition heldPositionKnown(HlMarket market) {
    if (market.isSpot) return const HlHeldPosition.flat();
    final s = _current;
    if (s == null || !s.isInitialized || !s.positionDexes.contains(market.dex)) {
      return const HlHeldPosition.unknown();
    }
    return HlHeldPosition.fromPositions(market, s.positions);
  }

  /// [heldPositionKnown], else one fresh read of [market]'s dex
  /// (`clearinghouseState` for that dex: the position's size, leverage and
  /// margin mode). Unknown when that read fails too. The plain first order
  /// on a loaded account reads nothing here.
  Future<HlHeldPosition> heldPositionFor(HlMarket market) async {
    final known = heldPositionKnown(market);
    if (known.known) return known;
    final address = _address ?? _current?.walletAddress;
    if (address == null) return const HlHeldPosition.unknown();
    try {
      final snap = await ref
          .read(hyperliquidTradingModelProvider)
          .getDexClearinghouse(address, market.dex);
      return HlHeldPosition.fromSnapshot(market, snap);
    } catch (_) {
      return const HlHeldPosition.unknown();
    }
  }

  /// [hlExposureCheck] for an order on [market], against the position as
  /// positively known ([heldPositionFor]). Every order that can open or
  /// add perp exposure asks this before anything is funded or signed.
  Future<({HlExposureCheck check, HlHeldPosition held})> exposureFor(
    HlMarket market, {
    required bool isBuy,
    required double size,
    bool reduceOnly = false,
  }) async {
    if (market.isSpot || reduceOnly) {
      return (
        check: hlExposureCheck(
            market: market,
            held: const HlHeldPosition.unknown(),
            isBuy: isBuy,
            size: size,
            reduceOnly: reduceOnly),
        held: const HlHeldPosition.unknown(),
      );
    }
    final held = await heldPositionFor(market);
    return (
      check: hlExposureCheck(
          market: market, held: held, isBuy: isBuy, size: size),
      held: held,
    );
  }

  /// Test seam: the signer an order is placed with, so a test can drive
  /// the real order path against a fake venue (no mnemonic, no network).
  @visibleForTesting
  void debugAttachExchange(HyperliquidExchangeService exchange,
      {required String walletId}) {
    _exchange = exchange;
    _walletId = walletId;
    _address = exchange.walletAddress;
  }

  // `_tryAttachTpSl` (the post-open best-effort trigger attach) is gone:
  // TP/SL now rides in the SAME 'normalTpsl'-grouped action as the
  // parent order, so the exchange sizes triggers to the actual fill,
  // OCO-cancels them, and a placement problem surfaces on the result
  // instead of vanishing into a silent catch.

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
          HlIntents.clampLeverage(market, leverage);
      final coinSize = size ??
          sizeFromUsd(
              usd: (marginUsd ?? 0) * lev,
              px: px,
              szDecimals: market.szDecimals);
      final asksTpsl = (takeProfitPx != null && takeProfitPx > 0) ||
          (stopLossPx != null && stopLossPx > 0);
      // The exposure rule, before the leverage write or any funding: on a
      // market held above 1x or in cross only a reduction goes, and it
      // goes reduce-only; an add, a flip or an unknown position stops here.
      final exposure = await exposureFor(market,
          isBuy: isLong, size: coinSize, reduceOnly: reduceOnly);
      exposure.check
          .ensureAllows(sentReduceOnly: reduceOnly || !asksTpsl);
      final sendReduceOnly = reduceOnly || exposure.check.mustReduceOnly;
      if (!sendReduceOnly) {
        await _ensureLeverage(market, exposure.held, lev, isCross);
      }
      if (!market.isSpot && !sendReduceOnly) {
        await _fundPerpAction(market, marginUsd ?? coinSize * px / lev,
            leverage: lev);
      }
      final builder = await _builderFee();
      final wantsTpsl = !sendReduceOnly && asksTpsl;
      // TP/SL rides in the SAME 'normalTpsl'-grouped action (see
      // placeMarketOrder): fill-sized, OCO, never silently missing.
      final orderCloid = cloid ?? newHlCloid();
      // The position as the app saw it when it sent the order: a limit
      // that closes all of it arms the left-over sweep.
      final held = _heldOn(market);
      final result = await _sendReconciled(
        () => wantsTpsl
            ? ex.placeOrderWithTpsl(
                market: market,
                isBuy: isLong,
                px: roundPrice(px,
                    szDecimals: market.szDecimals, isSpot: market.isSpot),
                sz: roundSize(coinSize, market.szDecimals),
                tif: postOnly ? 'Alo' : tif,
                takeProfitPx: takeProfitPx,
                stopLossPx: stopLossPx,
                cloid: orderCloid,
                builder: builder,
              )
            : ex.placeLimitOrder(
                assetId: market.assetId,
                isBuy: isLong,
                px: roundPrice(px,
                    szDecimals: market.szDecimals, isSpot: market.isSpot),
                sz: roundSize(coinSize, market.szDecimals),
                tif: postOnly ? 'Alo' : tif,
                reduceOnly: sendReduceOnly,
                cloid: orderCloid,
                builder: builder,
              ),
        cloid: orderCloid,
        market: market,
        action: sendReduceOnly ? 'close' : 'open',
      );
      final notional = coinSize * px;
      _afterAccepted(() {
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
          reduceOnly: sendReduceOnly,
          isCross: _crossFor(market, isCross, reduceOnly: sendReduceOnly),
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
        _armFullClose(
          market: market,
          held: held,
          orderIsBuy: isLong,
          size: flooredSize(coinSize, market.szDecimals),
          reduceOnly: reduceOnly,
          oid: result.oid,
        );
        _afterAction();
      });
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
    // Triggers only protect a held perp position: an entry stop would open
    // exposure at the venue's resting leverage and margin mode (this path
    // writes neither), and spot triggers are not offered.
    if (!reduceOnly || market.isSpot) {
      throw ArgumentError(
          'Trigger orders are reduce-only exits on a perp position');
    }
    await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(_orderCapabilities(market, reduceOnly));
    // The side rule once more against the freshest price here, right
    // before signing: crossed since the sheet checked it, nothing is sent.
    _ensureTriggerHolds(market,
        closeIsBuy: isLong, tpsl: tpsl, trigger: triggerPx);
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    _setData(current.copyWith(isPlacingOrder: true));
    try {
      await ensureOnboarded();
      final ex = _exchange!;
      // Phase 1b.3: consume the grant before anything is signed.
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
      // One cloid for the trigger, so a send with no answer is looked up
      // on the account before anything is said, and never sent twice.
      final orderCloid = cloid ?? newHlCloid();
      final result = await _sendReconciled(
        () => ex.placeTriggerOrder(
          market: market,
          isBuy: isLong,
          size: size,
          triggerPx: triggerPx,
          isMarket: isMarket,
          tpsl: tpsl,
          limitPx: limitPx,
          reduceOnly: reduceOnly,
          cloid: orderCloid,
          builder: builder,
        ),
        cloid: orderCloid,
        market: market,
        action: 'trigger',
      );
      // Taken by the exchange: bookkeeping only from here (never a
      // failure).
      _afterAccepted(() {
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
      });
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
    final current = state.valueOrNull ?? const HyperliquidTradingState();
    hlCheckModifiable(order, current.openOrders);
    final tpsl = order.isTrigger ? order.tpsl : null;
    // A protective trigger moved past the price fires at once: checked
    // against the freshest price here, right before signing.
    if (tpsl != null && (order.reduceOnly || order.isPositionTpsl)) {
      _ensureTriggerHolds(market,
          closeIsBuy: order.isBuy, tpsl: tpsl, trigger: newPx);
    }
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
      final cloid = newHlCloid();
      // An unclear answer (a timeout, a dropped connection) is looked up
      // before anything is said ([hlTraceModifyOf]): by the new cloid AND
      // by the order's own oid, since the venue's docs say neither which
      // cloid the modified order carries nor whether its oid changes.
      // Moved (either way), the move went through; the old order resting
      // at its old price for the whole window, it is as it was; anything
      // else, unconfirmed. Never "failed" for a move the venue may have
      // made, which would invite a second one.
      final movedTo = double.parse(tpsl != null
          ? roundPrice(newPx,
              szDecimals: market.szDecimals, isSpot: market.isSpot)
          : px);
      final modifyLookup = ref.read(hlModifyTraceProvider);
      final HlOrderResult result;
      try {
        result = await _sendReconciled(
          () => ex.modifyOrder(
            oid: order.oid,
            market: market,
            isBuy: order.isBuy,
            size: order.sz,
            px: px,
            reduceOnly: order.reduceOnly,
            orderType: type,
            cloid: cloid,
          ),
          cloid: cloid,
          market: market,
          action: 'modify',
          lookup: (_, m) => modifyLookup(order, cloid, movedTo, m),
        );
      } on HyperliquidOrderNotPlacedException {
        unawaited(_silentOrdersRefresh());
        rethrow;
      } on HyperliquidOrderUnconfirmedException {
        unawaited(_silentOrdersRefresh());
        rethrow;
      }
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
          HlIntents.clampLeverage(market, leverage);
      final avgPx = (startPx + endPx) / 2;
      final notional = totalUsd * lev;
      final totalSize = sizeFromUsd(
        usd: notional,
        px: avgPx > 0 ? avgPx : startPx,
        szDecimals: market.szDecimals,
      );
      // The exposure rule, before the leverage write or any funding (see
      // placeLimit): the whole ladder is judged at its total size.
      final exposure = await exposureFor(market,
          isBuy: isLong, size: totalSize, reduceOnly: reduceOnly);
      exposure.check.ensureAllows(sentReduceOnly: true);
      final sendReduceOnly = reduceOnly || exposure.check.mustReduceOnly;
      if (!sendReduceOnly) {
        await _ensureLeverage(market, exposure.held, lev, isCross);
      }
      if (!market.isSpot && !sendReduceOnly) {
        await _fundPerpAction(market, totalUsd, leverage: lev);
      }
      final builder = await _builderFee();
      // Every leg carries its own cloid (derived from one base), so a send
      // with no answer is looked up on the account by all of them before
      // anything is said: the legs go out as one signed action, so one
      // found means the venue took it. Never sent twice.
      // The base is the cloid the caller sent ([HlResendCloids.current] of
      // the slip's): "Confirming…" is keyed on it, as the slip watches it,
      // and every lookup reads the legs derived from it.
      final baseCloid = cloid ?? newHlCloid();
      final legCloids = hlScaleLegCloids(baseCloid, count);
      final result = await _sendReconciled(
        () => ex.placeScaleOrder(
          market: market,
          isBuy: isLong,
          totalSize: totalSize,
          startPx: startPx,
          endPx: endPx,
          count: count,
          reduceOnly: sendReduceOnly,
          legCloids: legCloids,
          builder: builder,
        ),
        cloid: baseCloid,
        cloids: legCloids,
        // Found after no answer: "N of M" as the answer says it.
        scaleLegs: count,
        market: market,
        action: sendReduceOnly ? 'close' : 'open',
      );
      _afterAccepted(() {
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
          reduceOnly: sendReduceOnly,
          isCross: _crossFor(market, isCross, reduceOnly: sendReduceOnly),
          filled: result.isFilled,
          walletKind: 'hot',
          marketType: _marketType(market),
          builderFeeApplied: builder != null,
        );
        if (result.legsMissing) {
          TrackingService.track('hyperliquid_scale_legs_refused', params: {
            'coin': market.coin,
            'legs_placed': result.legsPlaced ?? 0,
            'legs_total': result.legsTotal ?? count,
          });
        }
        _afterAction();
      });
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
          HlIntents.clampLeverage(market, leverage);
      // The venue's TWAP bounds (HlTwapRules), checked BEFORE the leverage
      // write or any money moves: a TWAP the venue would refuse never
      // touches the account.
      final refPx = _referencePx(market);
      final coinSize = size ??
          sizeFromUsd(
              usd: (marginUsd ?? 0) * lev,
              px: refPx,
              szDecimals: market.szDecimals);
      if (!HlTwapRules.minutesValid(durationMinutes)) {
        throw HyperliquidRejectedException(
            'TWAP duration must be between ${HlTwapRules.minMinutes} '
            'minutes and 7 days');
      }
      // The exposure rule, before the leverage write or any funding (see
      // placeLimit).
      final exposure = await exposureFor(market,
          isBuy: isLong, size: coinSize, reduceOnly: reduceOnly);
      exposure.check.ensureAllows(sentReduceOnly: true);
      final sendReduceOnly = reduceOnly || exposure.check.mustReduceOnly;
      ensureSubmissionCurrent();
      if (!sendReduceOnly &&
          !HlTwapRules.meetsMinimum(referencePx: refPx, size: coinSize)) {
        throw HyperliquidMinNotionalException(
            'TWAP notional \$${(refPx * coinSize).toStringAsFixed(2)} is below '
            'the \$${HlTwapRules.minNotionalUsd.toStringAsFixed(0)} TWAP minimum',
            minimumUsd: HlTwapRules.minNotionalUsd);
      }
      final twapHeld = _heldOn(market);
      final result = await HotHyperliquidTwapGuard().run(
        walletId: walletId!,
        address: ex.walletAddress,
        coin: market.coin,
        ensureCurrent: ensureSubmissionCurrent,
        send: (beforeSubmit, beforeSend) async {
          ensureSubmissionCurrent();
          if (!sendReduceOnly) {
            await _ensureLeverage(market, exposure.held, lev, isCross);
          }
          ensureSubmissionCurrent();
          if (!market.isSpot && !sendReduceOnly) {
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
            reduceOnly: sendReduceOnly,
            beforeSubmit: beforeSubmit,
            beforeSend: beforeSend,
          );
        },
      );
      // Taken by the exchange: bookkeeping only from here (never a
      // failure).
      _afterAccepted(() {
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
          reduceOnly: sendReduceOnly,
          isCross: _crossFor(market, isCross, reduceOnly: sendReduceOnly),
          filled: result.isFilled,
          walletKind: 'hot',
          marketType: _marketType(market),
          // The twapOrder action carries no builder field.
          builderFeeApplied: false,
        );
      });
      // The result's oid IS the twapId (see _twapResultFromBody) — the
      // only handle twapCancel accepts. Remember it or the TWAP is
      // unstoppable the moment this sheet closes.
      _afterAccepted(() {
        final twapId = result.oid;
        if (twapId != null && _address != null) {
          _showRunningTwap(HlRunningTwap(
            twapId: twapId,
            assetId: market.assetId,
            coin: market.coin,
            address: ex.walletAddress,
            isBuy: isLong,
            reduceOnly: sendReduceOnly,
            size: coinSize,
            durationMinutes: durationMinutes,
            startedAt: DateTime.now(),
          ));
        }
        // A TWAP that closes the whole position: its left-over stops go
        // once the position is actually gone, never on acceptance.
        _armFullClose(
          market: market,
          held: twapHeld,
          orderIsBuy: isLong,
          size: flooredSize(coinSize, market.szDecimals),
          reduceOnly: reduceOnly,
          twapId: twapId,
        );
        _afterAction();
      });
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
      final lookup = _trailingStopLookup(ex.walletAddress, market);
      await TrailingStopGuard().ensureAvailable(
        address: ex.walletAddress,
        assetId: market.assetId,
        lookup: lookup,
      );
      verifyAccount();
      final lev = HlIntents.clampLeverage(market, leverage);
      // The exposure rule for a stop that is not reduce-only, before the
      // leverage write or any funding (see placeLimit).
      final exposure = await exposureFor(market,
          isBuy: isLong, size: size, reduceOnly: reduceOnly);
      exposure.check.ensureAllows(sentReduceOnly: true);
      final sendReduceOnly = reduceOnly || exposure.check.mustReduceOnly;
      verifyAccount();
      if (!sendReduceOnly) {
        await _ensureLeverage(market, exposure.held, lev, isCross);
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
          .ensureAllAllowed(_orderCapabilities(market, sendReduceOnly));
      verifyAccount();
      final refPx = _referencePx(market);
      final result = await ex.placeTrailingStopOrder(
        market: market,
        isBuy: isLong,
        size: size,
        trail: trail,
        reduceOnly: sendReduceOnly,
        referencePrice: refPx,
        beforeSend: verifyAccount,
        lookup: lookup,
      );
      _afterAccepted(() {
        final notional = size * refPx;
        TrackingService.hyperliquidOrderPlaced(
          coin: market.coin,
          kind: market.isSpot ? 'spot' : 'perp',
          isBuy: isLong,
          leverage: lev,
          marginUsd: lev > 0 ? notional / lev : notional,
          notionalUsd: notional,
          orderType: 'trailing',
          reduceOnly: sendReduceOnly,
          isCross: _crossFor(market, isCross, reduceOnly: sendReduceOnly),
          filled: result.isFilled,
          walletKind: 'hot',
          marketType: _marketType(market),
          // This action carries no builder field.
          builderFeeApplied: false,
        );
        _afterAction();
      });
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

  /// How an unclear trailing-stop send on [market] is looked up
  /// ([TrailingStopGuard]): a trailing stop on the asset placed at or after
  /// the send, resting (frontendOpenOrders) or in the order history
  /// (historicalOrders: it triggered, filled or was cancelled), means it
  /// landed; neither list having it, both read cleanly, means it did not.
  TrailingStopLookup _trailingStopLookup(String address, HlMarket market) =>
      (sentAtMs) => hlLookupTrailingStop(
            model: ref.read(hyperliquidTradingModelProvider),
            address: address,
            market: market,
            sentAtMs: sentAtMs,
          );

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
    // A whole-position close the user cancelled closes nothing.
    _disarmByOrder(oid: oid);

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
    // The cash the order reserved is idle again: the sweeper may bring it
    // home.
    VenueCashReleased.emit(OneBalanceVenue.investing, 'cancel');
  }

  /// Cancels [orders] (one coin's left-over protective triggers, or the
  /// stops a new stop replaces) in one signed batch action, the cancel-all
  /// path scoped to them. Returns how many THIS action cancelled; an order
  /// the venue says was no longer resting (already cancelled, filled or
  /// never placed) is done, pruned and not counted. Throws
  /// [HlCancelPartialException] when any order is still open after it, and
  /// the venue's own error when the acknowledgement is unclear or an
  /// order's asset is unresolved, so the caller reports it rather than
  /// leave a stop that could later close a new position.
  Future<int> cancelOrdersList(List<HlOpenOrder> orders,
      {String reason = 'after_close'}) async {
    if (orders.isEmpty) return 0;
    final report = await _cancelListed(orders, reason: reason);
    if (report.failed.isNotEmpty) {
      throw HlCancelPartialException(
        cancelled: report.cancelled.length,
        stillOpen: report.failed.length,
        reason: report.failed.first.reason,
      );
    }
    return report.cancelled.length;
  }

  /// [orders] cancelled in one batch, read per order: what was cancelled
  /// or already gone leaves local state at once; what the venue refused
  /// stays listed. Throws only when nothing can be said (asset unresolved,
  /// no clear acknowledgement).
  Future<HlCancelReport> _cancelListed(List<HlOpenOrder> orders,
      {required String reason}) async {
    final cancels = <({int assetId, int oid})>[];
    final coins = {for (final o in orders) o.coin};
    final coin = coins.length == 1 ? coins.first : '';
    HlCancelReport report;
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.cancel');
      await ensureOnboarded();
      for (final o in orders) {
        final market = ref.read(hyperliquidWireMarketProvider(o.coin));
        if (market != null) cancels.add((assetId: market.assetId, oid: o.oid));
      }
      if (cancels.length != orders.length) {
        throw const HlCancellationIncompleteException();
      }
      try {
        report = await _exchange!.cancelOrdersReport(cancels);
      } finally {
        unawaited(_silentOrdersRefresh());
      }
    } catch (e) {
      _trackCancelFailed(scope: reason, coin: coin, error: e);
      rethrow;
    }
    _pruneCancelled(report);
    if (report.cancelled.isNotEmpty) {
      TrackingService.hyperliquidOrderCancelled(
        coin: coins.length == 1 ? coins.first : 'multiple',
        scope: reason,
        walletKind: 'hot',
        extra: {
          'count': report.cancelled.length,
          if (report.gone.isNotEmpty) 'already_gone': report.gone.length,
        },
      );
    }
    if (report.failed.isNotEmpty) {
      _trackCancelFailed(
          scope: reason,
          coin: coin,
          error: HyperliquidRejectedException(report.failed.first.reason));
    }
    return report;
  }

  /// What a cancel took off the book leaves local state now (the refresh
  /// it started confirms), and any full-close arm on those orders drops.
  void _pruneCancelled(HlCancelReport report) {
    final done = report.done;
    if (done.isEmpty) return;
    // Only what this cancel took off: an order already gone may have
    // filled, the close it armed included.
    for (final oid in report.cancelled) {
      _disarmByOrder(oid: oid);
    }
    final current = _current;
    if (current != null) {
      _setData(current.copyWith(
        openOrders:
            current.openOrders.where((o) => !done.contains(o.oid)).toList(),
      ));
    }
  }

  /// Cancels every resting order in one signed batch action. Returns how
  /// many this action cancelled (an order already gone is pruned, not
  /// counted); throws [HlCancelPartialException] when any order is still
  /// open after it.
  Future<int> cancelAllOrders() async {
    final cancels = <({int assetId, int oid})>[];
    final coins = <String>{};
    HlCancelReport report;
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
        report = await _exchange!.cancelOrdersReport(cancels);
      } finally {
        // The refresh confirms what the per-order answer already said.
        unawaited(_silentOrdersRefresh());
      }
    } catch (e) {
      _trackCancelFailed(
          scope: 'all', coin: coins.length == 1 ? coins.first : '', error: e);
      rethrow;
    }
    _pruneCancelled(report);
    final count = report.cancelled.length;
    if (count > 0) {
      TrackingService.track('hl_cancel_all_orders', params: {
        'count': count,
        'count_bucket': _countBucket(count),
      });
      TrackingService.hyperliquidOrderCancelled(
        coin: coins.length == 1 ? coins.first : 'multiple',
        scope: 'all',
        walletKind: 'hot',
      );
      VenueCashReleased.emit(OneBalanceVenue.investing, 'cancel');
    }
    if (report.failed.isNotEmpty) {
      final error = HlCancelPartialException(
        cancelled: count,
        stillOpen: report.failed.length,
        reason: report.failed.first.reason,
      );
      _trackCancelFailed(
          scope: 'all', coin: coins.length == 1 ? coins.first : '', error: error);
      throw error;
    }
    return count;
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
          // The WS payload carries only the basic order (WsBasicOrder:
          // coin, side, limitPx, sz, oid, timestamp, origSz, cloid);
          // everything else is kept from the REST row (tif and position
          // TP/SL included, so a later modify re-sends the right time in
          // force). A row REST has not described yet is marked unknown:
          // listed, never drawn as a movable line nor modified, so a stop
          // is never mistaken for a limit at its guard price.
          reduceOnly: prev?.reduceOnly ?? u.reduceOnly ?? false,
          orderType: prev?.orderType ?? '',
          isTrigger: prev?.isTrigger ?? false,
          triggerPx: prev?.triggerPx,
          tif: prev?.tif ?? 'Gtc',
          isPositionTpsl: prev?.isPositionTpsl ?? false,
          detailsKnown: prev?.detailsKnown ?? false,
        );
        touched = true;
      } else {
        // A closing order cancelled or rejected (here or elsewhere) no
        // longer closes the position: its arm drops. A fill keeps it.
        if (u.status != 'filled' && u.status != 'triggered') {
          _disarmByOrder(oid: u.oid);
        }
        if (byOid.remove(u.oid) != null) touched = true;
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
    return kHlCrossMarginOffered && (isCross ?? kHlDefaultCross) && !m.onlyIsolated;
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
    // The order went out and nobody has heard back: not a failure. The
    // lookup reported it (hl_order_outcome_reconciled).
    if (e is HyperliquidOrderUnconfirmedException) return;
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
    // Proven not placed after an unanswered send: named by what the send
    // met (the timeout, the dropped connection, the gateway).
    if (e is HyperliquidOrderNotPlacedException && e.cause != null) {
      return _reasonFor(e.cause!);
    }
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

/// The size a market close of [fraction] of [position] goes out with on
/// [market]: the whole position exactly at (nearly) 100%, else
/// [hlPartialCloseSize] at [referencePx] and the IOC's own price. A
/// partial that still cannot clear the venue minimum (asked below it)
/// throws [HyperliquidMinNotionalException] before anything is signed:
/// the venue would refuse it with the same words.
double hlMarketCloseSize({
  required HlPerpPosition position,
  required double fraction,
  required HlMarket market,
  required double referencePx,
  double slippagePct = 1.0,
}) {
  final whole = position.szi.abs();
  if (fraction >= 0.999) return whole;
  final checkPx = hlMinCheckPx(
      referencePx: referencePx,
      isBuy: !position.isLong,
      slippage: slippagePct / 100,
      szDecimals: market.szDecimals,
      isSpot: false);
  final size = hlPartialCloseSize(
      requestedSz: whole * fraction,
      positionSz: whole,
      referencePx: referencePx,
      checkPx: checkPx,
      szDecimals: market.szDecimals);
  if (size < whole && !meetsMinNotional(px: checkPx, sz: size)) {
    throw HyperliquidMinNotionalException(
        'close notional \$${(size * checkPx).toStringAsFixed(2)} is below '
        'the \$${HyperliquidConstants.minOrderNotionalUsd.toStringAsFixed(0)} '
        'minimum',
        minimumUsd: HyperliquidConstants.minOrderNotionalUsd);
  }
  return size;
}

final hyperliquidTradingProvider = AsyncNotifierProvider.autoDispose<
    HyperliquidTradingNotifier, HyperliquidTradingState>(
  HyperliquidTradingNotifier.new,
);

/// The position on a market as positively known: the account's state, else
/// one fresh read of the market's dex, else unknown
/// ([HyperliquidTradingNotifier.heldPositionFor]). What the order slip and
/// a queued Investing order judge the exposure rule (hl_exposure_rule.dart)
/// on before anything is approved or moved. Overridden in tests.
///
/// Answers at once (no future) when the state already knows the position,
/// so a queued order on a loaded account is queued in the same turn as
/// before.
final hlHeldPositionProvider =
    Provider<FutureOr<HlHeldPosition> Function(HlMarket market)>((ref) =>
        (market) {
          final n = ref.read(hyperliquidTradingProvider.notifier);
          final known = n.heldPositionKnown(market);
          if (known.known) return known;
          return n.heldPositionFor(market);
        });

/// Display-only fallback. Never use this provider to size, authorize or send
/// an order/move: [hyperliquidTradingProvider] remains the live execution state.
final hyperliquidDisplayTradingProvider =
    Provider.autoDispose<AsyncValue<HyperliquidTradingState>>((ref) {
  final display = ref.watch(hyperliquidDisplayAccountProvider);
  final actual = ref.watch(hyperliquidTradingProvider);
  if (!actual.isLoading &&
      !actual.hasError &&
      actual.valueOrNull?.isInitialized == true) {
    return actual;
  }
  return display.whenData((snapshot) => HyperliquidTradingState(
            isInitialized: true,
            perpEquity: snapshot.accountValue,
            totalMarginUsed: snapshot.totalMarginUsed,
            withdrawable: snapshot.withdrawable,
            positions: snapshot.positions,
            spotBalances: snapshot.spotBalances,
          ));
});
