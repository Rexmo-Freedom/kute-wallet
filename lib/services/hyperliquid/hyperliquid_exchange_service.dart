import 'trailing_stop.dart';
import 'trailing_stop_guard.dart';
import 'package:kute/services/hardware/evm_signer.dart';
// lib/services/hyperliquid/hyperliquid_exchange_service.dart
//
// The write path: signs Hyperliquid actions locally (hyperliquid_signing)
// and POSTs them to /exchange. One instance per signer (the user's EOA —
// same derivation as Polymarket, m/44'/60'/0'/0/0).
//
// Error taxonomy, because the exchange returns HTTP 200 for business
// rejections and the provider layer needs to tell them apart:
//   * HyperliquidApiException          — HTTP != 200 or unparseable body;
//   * HyperliquidRejectedException     — status:'err' or a statuses[i].error
//     entry, with subclasses:
//       - HyperliquidMinNotionalException        ("minimum value of $10")
//       - HyperliquidInsufficientMarginException (margin/balance)
//       - HyperliquidSignatureRejectedException  ("… does not exist" — the
//         exchange recovered a DIFFERENT address from our signature, i.e. a
//         signing bug on OUR side. This is an engineering alert, never a
//         user error; report it loudly, don't retry.)
//   * network/timeout errors propagate raw — use [isOfflineError] to keep
//     expected connectivity failures out of crash reporting.
//
// Nonces are ms timestamps made strictly monotonic per instance
// (max(now, last+1)); a nonce rejection is retried exactly ONCE with a
// fresh nonce + fresh signature (covers clock skew between two rapid
// actions), anything else is not our race to win.

import 'dart:async';
import 'dart:convert';
import 'package:kute/services/revenue/hyperliquid_revenue.dart';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking/order_ack_latency.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

// ─────────────────────────── error taxonomy ────────────────────────────

/// HTTP-level failure from POST /exchange (non-200, or a 200 whose body
/// doesn't match any known response shape).
class HyperliquidApiException implements Exception {
  final int statusCode;
  final String body;

  const HyperliquidApiException({required this.statusCode, required this.body});

  @override
  String toString() => 'HyperliquidApiException($statusCode): $body';
}

/// The submitted TWAP has no valid acknowledgement. It may already be running;
/// this is not a rejection and must never trigger an automatic resubmission.
class HyperliquidTwapSubmissionUnknownException
    extends HyperliquidApiException {
  const HyperliquidTwapSubmissionUnknownException()
      : super(statusCode: 200, body: 'Unconfirmed TWAP submission');
}

/// The exchange accepted the request but rejected the action
/// (status:'err' or a per-order error status).
class HyperliquidRejectedException implements Exception {
  final String reason;

  const HyperliquidRejectedException(this.reason);

  @override
  String toString() => '$runtimeType: $reason';
}

/// Order notional below the exchange minimum (~$10).
class HyperliquidMinNotionalException extends HyperliquidRejectedException {
  const HyperliquidMinNotionalException(super.reason, {this.minimumUsd});

  final double? minimumUsd;
}

/// Not enough perp margin / spot balance to place the order.
class HyperliquidInsufficientMarginException
    extends HyperliquidRejectedException {
  const HyperliquidInsufficientMarginException(super.reason);
}

/// "User or API Wallet 0x… does not exist" — the exchange recovered a
/// different signer from our signature than the account we meant. This is
/// the classic Hyperliquid signature-bug signature (msgpack field-order
/// drift, wrong chain source, …): an ENGINEERING ALERT, not a user error.
/// Never retried; surface to crash reporting.
class HyperliquidSignatureRejectedException
    extends HyperliquidRejectedException {
  const HyperliquidSignatureRejectedException(super.reason);
}

/// The exchange rejected the nonce (clock skew or a reused nonce). Hot
/// accounts retry once with a fresh nonce; with `allowNonceRetry` off (a
/// Ledger) it is rethrown so the user approves again instead of the app
/// silently re-prompting the device.
class HyperliquidNonceRejectedException extends HyperliquidRejectedException {
  const HyperliquidNonceRejectedException(super.reason);
}

/// A signed action about to be POSTed. Handed to `onBeforePost` after the
/// signature exists and before any network request, so a caller can bind
/// the payload to a reviewed intent and persist a submission record.
class HlPendingPost {
  const HlPendingPost({required this.action, required this.nonce});
  final Map<String, dynamic> action;
  final int nonce;
}

// ─────────────────────────── order results ─────────────────────────────

enum HlOrderResultKind {
  resting,
  filled,

  /// Not produced by this service (order errors THROW the taxonomy above);
  /// reserved for callers that fold caught rejections back into a result.
  error,
}

class HlOrderResult {
  final HlOrderResultKind kind;
  final int? oid;
  final String? cloid;

  /// Filled size / average fill price; 0 for purely resting orders.
  final double filledSz;
  final double avgPx;
  final String? error;

  const HlOrderResult({
    required this.kind,
    this.oid,
    this.cloid,
    this.filledSz = 0,
    this.avgPx = 0,
    this.error,
  });

  bool get isFilled => kind == HlOrderResultKind.filled;
}

// ────────────────────────────── service ────────────────────────────────

class HyperliquidExchangeService {
  HyperliquidExchangeService({
    EthPrivateKey? credentials,
    this.externalSigner,
    required this.walletAddress,
    this.allowNonceRetry = true,
    this.signatureChainId,
    http.Client? httpClient,
    this.onBeforePost,
  })  : _credentials = credentials,
        _httpClient = httpClient {
    if (credentials != null) {
      LedgerOperationScope.assertHotAllowed(
          HotSigningAction.hyperliquidHotCredentials);
    }
    if ((credentials == null) == (externalSigner == null)) {
      throw ArgumentError('Exactly one signing authority is required');
    }
    // An external signer is pinned to the account it signs for.
    final signer = externalSigner;
    if (signer != null && !sameEvmAddress(signer.address, walletAddress)) {
      throw ArgumentError(
          'walletAddress must equal the external signer address');
    }
  }

  final EthPrivateKey? _credentials;
  final EvmExternalSigner? externalSigner;

  /// Hot accounts retry a nonce rejection once. A Ledger passes false: the
  /// rejection surfaces as [HyperliquidNonceRejectedException] and the
  /// device is never prompted twice for one tap.
  final bool allowNonceRetry;

  /// User-signed action chain ID. Null keeps the documented default,
  /// Arbitrum 42161 (0xa4b1); a Ledger passes it explicitly.
  final int? signatureChainId;

  final http.Client? _httpClient;

  /// Called with each signed action right before its POST (see
  /// [HlPendingPost]). A throw aborts the POST.
  final Future<void> Function(HlPendingPost post)? onBeforePost;

  int get _userSignedChainId =>
      signatureChainId ?? HyperliquidConstants.signatureChainId;

  /// The signer's own EOA (== the Hyperliquid account address).
  final String walletAddress;

  int _lastNonce = 0;

  /// Strictly monotonic ms nonce — two actions signed within the same
  /// millisecond must not collide.
  int nextNonce() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastNonce = now > _lastNonce ? now : _lastNonce + 1;
    return _lastNonce;
  }

  /// True when [e] is an expected connectivity failure (no internet, DNS
  /// failure, stalled/timed-out request) rather than a real bug — same
  /// predicate as polymarket_trading_provider, duplicated here so the
  /// provider layer can classify this service's raw network errors without
  /// a service→provider import.
  static bool isOfflineError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('connection refused') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception') ||
        s.contains('xmlhttprequest');
  }

  // ───────────────────────────── orders ────────────────────────────────

  /// Places one limit order. [px] and [sz] must already be wire-rounded
  /// strings (roundPrice/roundSize). [tif] ∈ {'Gtc','Ioc','Alo'}.
  ///
  /// Returns resting{oid} or filled{totalSz, avgPx}; a per-order error
  /// status THROWS the mapped [HyperliquidRejectedException] subclass.
  Future<HlOrderResult> placeLimitOrder({
    required int assetId,
    required bool isBuy,
    required String px,
    required String sz,
    String tif = 'Gtc',
    bool reduceOnly = false,
    String? cloid,
    HlBuilderFee? builder,
  }) async {
    const allowedTifs = {'Gtc', 'Ioc', 'Alo'};
    if (!allowedTifs.contains(tif)) {
      throw ArgumentError('invalid tif: $tif');
    }
    final action = buildOrderAction(
      orders: [
        HlOrderWire(
          assetId: assetId,
          isBuy: isBuy,
          px: px,
          sz: sz,
          reduceOnly: reduceOnly,
          orderType: limitOrderType(tif),
          cloid: cloid,
        ),
      ],
      builder: builder,
    );
    final body = await _submitL1Action(action);
    return _orderResultFromBody(body, cloid: cloid);
  }

  /// "Market" order — an IOC limit priced through the book at
  /// referencePx*(1±slippage). Size/price are wire-rounded here from the
  /// market's szDecimals. Enforces the $10 min notional locally (skipped
  /// for reduceOnly so dust positions can still be closed).
  ///
  /// With [takeProfitPx]/[stopLossPx] set the whole bracket goes out as
  /// ONE `normalTpsl`-grouped action (see [placeOrderWithTpsl]).
  Future<HlOrderResult> placeMarketOrder({
    required HlMarket market,
    required bool isBuy,
    required double size,
    required double referencePx,
    double slippage = 0.01,
    bool reduceOnly = false,
    double? takeProfitPx,
    double? stopLossPx,
    String? cloid,
    HlBuilderFee? builder,
  }) async {
    final px = slippagePrice(
      referencePx: referencePx,
      isBuy: isBuy,
      slippage: slippage,
      szDecimals: market.szDecimals,
      isSpot: market.isSpot,
    );
    final sz = roundSize(size, market.szDecimals);
    if (!reduceOnly &&
        !meetsMinNotional(px: double.parse(px), sz: double.parse(sz))) {
      throw HyperliquidMinNotionalException(
          'order notional \$${(double.parse(px) * double.parse(sz)).toStringAsFixed(2)} '
          'is below the \$${HyperliquidConstants.minOrderNotionalUsd.toStringAsFixed(0)} minimum',
          minimumUsd: HyperliquidConstants.minOrderNotionalUsd);
    }
    if ((takeProfitPx != null && takeProfitPx > 0) ||
        (stopLossPx != null && stopLossPx > 0)) {
      return placeOrderWithTpsl(
        market: market,
        isBuy: isBuy,
        px: px,
        sz: sz,
        tif: 'Ioc',
        reduceOnly: reduceOnly,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
        cloid: cloid,
        builder: builder,
      );
    }
    return placeLimitOrder(
      assetId: market.assetId,
      isBuy: isBuy,
      px: px,
      sz: sz,
      tif: 'Ioc',
      reduceOnly: reduceOnly,
      cloid: cloid,
      builder: builder,
    );
  }

  Future<void> cancelOrder({required int assetId, required int oid}) async {
    final body = await _submitL1Action(
        buildCancelAction([(assetId: assetId, oid: oid)]));
    _requireCancelSuccess(body, expectedCount: 1);
  }

  /// Move a resting order to new terms with the venue's own modify, which
  /// swaps the order atomically. [px] and the trigger price inside
  /// [orderType] must already be wire-rounded; [size] is rounded here.
  /// The venue may answer with a fresh order status (resting, or filled
  /// when the new price crosses) or a bare acknowledgement.
  Future<HlOrderResult> modifyOrder({
    required int oid,
    required HlMarket market,
    required bool isBuy,
    required double size,
    required String px,
    required bool reduceOnly,
    required Map<String, dynamic> orderType,
    String? cloid,
  }) async {
    final action = buildModifyAction(
      oid: oid,
      order: HlOrderWire(
        assetId: market.assetId,
        isBuy: isBuy,
        px: px,
        sz: roundSize(size, market.szDecimals),
        reduceOnly: reduceOnly,
        orderType: orderType,
        cloid: cloid,
      ),
    );
    final body = await _submitL1Action(action);
    if (body['status'] != 'ok') {
      throw HyperliquidApiException(statusCode: 200, body: jsonEncode(body));
    }
    final response = body['response'];
    if (response is Map<String, dynamic> && response['type'] == 'order') {
      return _orderResultFromBody(body, cloid: cloid);
    }
    if (response is String) throw _rejectionFromReason(response);
    _throwOnStatusError(body);
    return HlOrderResult(
        kind: HlOrderResultKind.resting, oid: oid, cloid: cloid);
  }

  /// Batch cancel — one signed L1 action for the whole list (the
  /// cancel action is natively a list; cancel-all costs one submit).
  Future<void> cancelOrders(List<({int assetId, int oid})> cancels) async {
    if (cancels.isEmpty) return;
    final expectedCount = cancels.length;
    final body = await _submitL1Action(buildCancelAction(cancels));
    _requireCancelSuccess(body, expectedCount: expectedCount);
  }

  Future<void> cancelByCloid({
    required int assetId,
    required String cloid,
  }) async {
    final body = await _submitL1Action(
        buildCancelByCloidAction([(assetId: assetId, cloid: cloid)]));
    _requireCancelSuccess(body, expectedCount: 1);
  }

  Future<void> updateLeverage({
    required int assetId,
    required bool isCross,
    required int leverage,
  }) async {
    final body = await _submitL1Action(buildUpdateLeverageAction(
      assetId: assetId,
      isCross: isCross,
      leverage: leverage,
    ));
    _throwOnStatusError(body);
  }

  /// Add (positive [usd]) or remove (negative) isolated margin on a position.
  Future<void> updateIsolatedMargin({
    required int assetId,
    required double usd,
  }) async {
    final ntli = (usd * 1e6).round();
    final body = await _submitL1Action(
        buildUpdateIsolatedMarginAction(assetId: assetId, ntli: ntli));
    _throwOnStatusError(body);
  }

  /// A stop / take-profit order. [isMarket] true = Stop-Market / Take-Market
  /// (fills at the oracle on trigger); false = Stop-Limit / Take-Limit (rests
  /// a limit at [limitPx] once triggered). [tpsl] is 'tp' (take-profit) or
  /// 'sl' (stop-loss). Both prices are wire-rounded from the market meta.
  Future<HlOrderResult> placeTriggerOrder({
    required HlMarket market,
    required bool isBuy,
    required double size,
    required double triggerPx,
    required bool isMarket,
    required String tpsl, // 'tp' | 'sl'
    double? limitPx, // required when !isMarket
    bool reduceOnly = true,
    String? cloid,
    HlBuilderFee? builder,
  }) async {
    if (tpsl != 'tp' && tpsl != 'sl') {
      throw ArgumentError('tpsl must be tp|sl, got $tpsl');
    }
    final trig = roundPrice(triggerPx,
        szDecimals: market.szDecimals, isSpot: market.isSpot);
    // Market triggers still carry a (slippage-guarded) limit px on the wire;
    // limit triggers use the caller's resting price.
    final px = isMarket
        ? slippagePrice(
            referencePx: triggerPx,
            isBuy: isBuy,
            slippage: 0.05,
            szDecimals: market.szDecimals,
            isSpot: market.isSpot)
        : roundPrice(limitPx ?? triggerPx,
            szDecimals: market.szDecimals, isSpot: market.isSpot);
    final action = buildOrderAction(
      orders: [
        HlOrderWire(
          assetId: market.assetId,
          isBuy: isBuy,
          px: px,
          sz: roundSize(size, market.szDecimals),
          reduceOnly: reduceOnly,
          orderType:
              triggerOrderType(isMarket: isMarket, triggerPx: trig, tpsl: tpsl),
          cloid: cloid,
        ),
      ],
      builder: builder,
    );
    final body = await _submitL1Action(action);
    return _orderResultFromBody(body, cloid: cloid);
  }

  /// Parent order + optional TP/SL triggers in ONE `normalTpsl`-grouped
  /// action. The exchange owns the bracket lifecycle: children
  /// size-match the parent's FILLED size, activate on its fill, and
  /// cancel each other (OCO) — so a partial parent fill can never leave
  /// an oversized trigger, and a filled take-profit can never leave the
  /// stop-loss resting. This replaces the old two-step "place then
  /// best-effort attach", whose silent failure left users believing a
  /// stop-loss existed that didn't.
  ///
  /// [px]/[sz] must already be wire-rounded; trigger prices are rounded
  /// here. With neither trigger set this degrades to a plain 'na' order.
  Future<HlOrderResult> placeOrderWithTpsl({
    required HlMarket market,
    required bool isBuy,
    required String px,
    required String sz,
    required String tif,
    bool reduceOnly = false,
    double? takeProfitPx,
    double? stopLossPx,
    String? cloid,
    HlBuilderFee? builder,
  }) async {
    const allowedTifs = {'Gtc', 'Ioc', 'Alo'};
    if (!allowedTifs.contains(tif)) {
      throw ArgumentError('invalid tif: $tif');
    }
    final wires = <HlOrderWire>[
      HlOrderWire(
        assetId: market.assetId,
        isBuy: isBuy,
        px: px,
        sz: sz,
        reduceOnly: reduceOnly,
        orderType: limitOrderType(tif),
        cloid: cloid,
      ),
    ];
    void addTrigger(double triggerPx, String tpsl) {
      final trig = roundPrice(triggerPx,
          szDecimals: market.szDecimals, isSpot: market.isSpot);
      // Market triggers carry a slippage-guard limit px on the wire,
      // exactly like placeTriggerOrder's isMarket path.
      final guardPx = slippagePrice(
        referencePx: triggerPx,
        isBuy: !isBuy,
        slippage: 0.05,
        szDecimals: market.szDecimals,
        isSpot: market.isSpot,
      );
      wires.add(HlOrderWire(
        assetId: market.assetId,
        isBuy: !isBuy,
        px: guardPx,
        sz: sz,
        reduceOnly: true,
        orderType:
            triggerOrderType(isMarket: true, triggerPx: trig, tpsl: tpsl),
      ));
    }

    if (takeProfitPx != null && takeProfitPx > 0) {
      addTrigger(takeProfitPx, 'tp');
    }
    if (stopLossPx != null && stopLossPx > 0) {
      addTrigger(stopLossPx, 'sl');
    }
    final body = await _submitL1Action(buildOrderAction(
      orders: wires,
      grouping: wires.length > 1 ? 'normalTpsl' : 'na',
      builder: builder,
    ));
    // The parent is statuses[0] (throws if IT errored); the trigger
    // children acknowledge behind it. A grouped action should be
    // atomic, but if the exchange ever accepts the parent while
    // erroring a child, that must surface on the result rather than
    // vanish OR masquerade as a failed placement: the position IS open
    // at that point, so we return the parent with the child's error
    // attached for the caller to show.
    final result = _orderResultFromBody(body, cloid: cloid);
    final childError = _firstStatusErrorAfter(body, index: 0);
    if (childError != null) {
      return HlOrderResult(
        kind: result.kind,
        oid: result.oid,
        cloid: result.cloid,
        filledSz: result.filledSz,
        avgPx: result.avgPx,
        error: 'TP/SL was not placed: $childError',
      );
    }
    return result;
  }

  /// A "scale" order — [count] resting limit legs evenly spread across
  /// [startPx]..[endPx], splitting [totalSize] equally. One signed action.
  Future<HlOrderResult> placeScaleOrder({
    required HlMarket market,
    required bool isBuy,
    required double totalSize,
    required double startPx,
    required double endPx,
    required int count,
    bool reduceOnly = false,
    HlBuilderFee? builder,
  }) async {
    if (count < 2) throw ArgumentError('scale order needs >= 2 legs');
    final legSize = totalSize / count;
    final step = (endPx - startPx) / (count - 1);
    final orders = <HlOrderWire>[
      for (var i = 0; i < count; i++)
        HlOrderWire(
          assetId: market.assetId,
          isBuy: isBuy,
          px: roundPrice(startPx + step * i,
              szDecimals: market.szDecimals, isSpot: market.isSpot),
          sz: roundSize(legSize, market.szDecimals),
          reduceOnly: reduceOnly,
          orderType: limitOrderType('Gtc'),
        ),
    ];
    final body = await _submitL1Action(
        buildOrderAction(orders: orders, builder: builder));
    // A scale action returns one status PER LEG. Inspecting only the
    // first told the user "Scaled orders placed" while later legs
    // rejected on margin or price band — iterate them all: throw when
    // NOTHING placed, and report "n of m" with the first error when
    // only some did.
    final statuses = _statusesOf(body);
    var placed = 0;
    String? firstError;
    for (final st in statuses) {
      if (st is Map<String, dynamic> && st['error'] != null) {
        firstError ??= st['error'].toString();
      } else {
        placed++;
      }
    }
    if (placed == 0 && firstError != null) {
      throw _rejectionFromReason(firstError);
    }
    final result = _orderResultFromBody(body, cloid: null);
    if (firstError != null) {
      return HlOrderResult(
        kind: result.kind,
        oid: result.oid,
        cloid: result.cloid,
        filledSz: result.filledSz,
        avgPx: result.avgPx,
        error: 'Only $placed of ${orders.length} legs placed. $firstError',
      );
    }
    return result;
  }

  /// The exchange's documented TWAP bounds. These are SERVER rules, not
  /// preferences: a shorter/cheaper TWAP passes any looser local check
  /// and then rejects server-side with a raw error.
  static const int minTwapMinutes = 5;
  static const int maxTwapMinutes = 7 * 24 * 60; // 7 days
  static const double minTwapNotionalUsd = 100;

  /// A TWAP order — the exchange slices [size] into sub-orders spread over
  /// [durationMinutes] and works them itself. Signed as an L1 action via
  /// the shared _submitL1Action path (same signature scheme as `order`).
  /// Enforces the documented $100 minimum notional and 5 min .. 7 day
  /// duration locally so a doomed TWAP fails with a sentence instead of
  /// a server rejection.
  ///
  /// Returns a resting-kind result carrying the exchange's `twapId` as the
  /// oid on success; a per-action error status THROWS the mapped rejection.
  /// TWAP has no client order ID and is never automatically retried. Callers
  /// persist through [beforeSubmit] and recheck the session in [beforeSend].
  Future<HlOrderResult> placeTwapOrder({
    required HlMarket market,
    required bool isBuy,
    required double size,
    required int durationMinutes,
    required double referencePx,
    bool randomize = false,
    bool reduceOnly = false,
    Future<void> Function(HlPendingPost post)? beforeSubmit,
    void Function()? beforeSend,
  }) async {
    if (durationMinutes < minTwapMinutes || durationMinutes > maxTwapMinutes) {
      throw HyperliquidRejectedException(
          'TWAP duration must be between $minTwapMinutes minutes and 7 days');
    }
    final sz = roundSize(size, market.szDecimals);
    if (!reduceOnly && referencePx * double.parse(sz) < minTwapNotionalUsd) {
      throw HyperliquidMinNotionalException(
          'TWAP notional \$${(referencePx * double.parse(sz)).toStringAsFixed(2)} '
          'is below the \$${minTwapNotionalUsd.toStringAsFixed(0)} TWAP minimum',
          minimumUsd: minTwapNotionalUsd);
    }
    final action = buildTwapOrderAction(
      assetId: market.assetId,
      isBuy: isBuy,
      sizeWire: sz,
      reduceOnly: reduceOnly,
      minutes: durationMinutes,
      randomize: randomize,
    );
    final body = await _submitL1Action(
      action,
      retryNonce: false,
      beforeSubmit: beforeSubmit,
      beforeSend: beforeSend,
    );
    return _twapResultFromBody(body);
  }

  /// Native perp-only trailing stop. The venue maintains the trail while the
  /// app is closed. No builder/cloid fields are supported by this action.
  Future<HlOrderResult> placeTrailingStopOrder({
    required HlMarket market,
    required bool isBuy,
    required double size,
    required HlTrailingStop trail,
    required double referencePrice,
    bool reduceOnly = false,
    void Function()? beforeSend,
  }) async {
    trail.validate(
      market: market,
      isBuy: isBuy,
      referencePrice: referencePrice,
    );
    final sz = roundSize(size, market.szDecimals);
    if (!reduceOnly &&
        !meetsMinNotional(px: referencePrice, sz: double.parse(sz))) {
      throw const HyperliquidMinNotionalException(
        'Order is below the market minimum',
      );
    }
    final action = trail.action(
      market: market,
      isBuy: isBuy,
      size: sz,
      reduceOnly: reduceOnly,
    );
    return TrailingStopGuard().run(
      address: walletAddress,
      assetId: market.assetId,
      send: (persist, markStarted) async {
        final body = await _submitL1Action(
          action,
          retryNonce: false,
          beforeSubmit: persist,
          beforeSend: () {
            beforeSend?.call();
            markStarted();
          },
        );
        final response = body['response'];
        if (body['status'] != 'ok' || response is! Map<String, dynamic>) {
          throw const PendingTrailingStopException();
        }
        // The exchange's generic L1 acknowledgement confirms submission only,
        // never a fill. Order-shaped responses retain their actual order ID.
        if (response['type'] == 'order') return _orderResultFromBody(body);
        bool containsError(Object? value) {
          if (value is Map) {
            return value.containsKey('error') ||
                value.values.any(containsError);
          }
          return value is List && value.any(containsError);
        }

        if (!const ['default', 'trailingStop'].contains(response['type']) ||
            containsError(response)) {
          throw const PendingTrailingStopException();
        }
        return HlOrderResult(kind: HlOrderResultKind.resting);
      },
    );
  }

  /// Stops a running TWAP. Response mirrors twapOrder's
  /// `response.data.status` shape ('success' or {error}); throws the
  /// mapped rejection on error.
  Future<void> cancelTwap({
    required int assetId,
    required int twapId,
  }) async {
    final body = await _submitL1Action(
        buildTwapCancelAction(assetId: assetId, twapId: twapId));
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final status = (data is Map<String, dynamic>) ? data['status'] : null;
    if (body['status'] != 'ok' ||
        response is! Map<String, dynamic> ||
        response['type'] != 'twapCancel') {
      throw const HyperliquidApiException(
          statusCode: 200,
          body: 'Unconfirmed TWAP cancellation acknowledgement');
    }
    if (status is Map<String, dynamic> &&
        status.length == 1 &&
        status['error'] is String &&
        (status['error'] as String).isNotEmpty) {
      throw _rejectionFromReason(status['error'] as String);
    }
    if (status != 'success') {
      throw const HyperliquidApiException(
          statusCode: 200,
          body: 'Unconfirmed TWAP cancellation acknowledgement');
    }
  }

  // ─────────────────────── user-signed actions ─────────────────────────

  /// Moves USDC between the perp and spot clearinghouses. Note the signed
  /// `nonce` field IS the POSTed nonce (protocol requirement).
  Future<void> usdClassTransfer({
    required double amount,
    required bool toPerp,
    void Function()? beforeSend,
  }) async {
    await _withNonceRetry((nonce) async {
      final action = buildUsdClassTransferAction(
        amount: _usdWire(amount),
        toPerp: toPerp,
        nonce: nonce,
      );
      final sig = await signUserSignedAction(
        credentials: _credentials,
        externalSigner: externalSigner,
        action: action,
        fields: usdClassTransferSignTypes,
        primaryType: usdClassTransferPrimaryType,
        isMainnet: HyperliquidConstants.isMainnet,
        signatureChainId: _userSignedChainId,
      );
      // signUserSignedAction augmented `action` in place — POST that map.
      return _post(
          action: action, signature: sig, nonce: nonce, beforeSend: beforeSend);
    });
  }

  /// Move USDC between clearinghouses on this exact account. No arbitrary
  /// destination address, subaccount, token or automatic retry is exposed.
  Future<void> moveOwnUsdc(
      {required String sourceDex,
      required String destinationDex,
      required double amount,
      void Function()? beforeSend}) async {
    bool validDex(String value) =>
        value.isEmpty || RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value);
    if (!validDex(sourceDex) ||
        !validDex(destinationDex) ||
        sourceDex == destinationDex ||
        !amount.isFinite ||
        amount <= 0) {
      throw ArgumentError('Invalid same-account funding');
    }
    final nonce = nextNonce();
    final action = <String, dynamic>{
      'type': 'agentSendAsset',
      'destination': walletAddress.toLowerCase(),
      'sourceDex': sourceDex,
      'destinationDex': destinationDex,
      'token': 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054',
      'amount': _usdWire(amount),
      'fromSubAccount': '',
      'nonce': nonce,
    };
    final sig = await signL1Action(
        credentials: _credentials,
        externalSigner: externalSigner,
        action: action,
        nonce: nonce,
        isMainnet: HyperliquidConstants.isMainnet);
    final response = await _post(
        action: action, signature: sig, nonce: nonce, beforeSend: beforeSend);
    if (response['status'] != 'ok') {
      throw HyperliquidApiException(
          statusCode: 200, body: jsonEncode(response));
    }
  }

  /// Native perpetuals USDC transfer. The amount is already formatted from exact base
  /// units. Never retries: a timeout leaves the settlement pending for a public
  /// ledger lookup, instead of risking a second transfer with a fresh nonce.
  Future<int> usdSend({
    required String destination,
    required String amount,
    void Function()? beforeSend,
  }) async {
    if (!isEvmAddress(destination) ||
        !RegExp(r'^\d+(?:\.\d{1,6})?$').hasMatch(amount) ||
        (double.tryParse(amount) ?? 0) <= 0) {
      throw ArgumentError('Invalid native transfer');
    }
    final nonce = nextNonce();
    final action = buildUsdSendAction(
        destination: destination.toLowerCase(), amount: amount, time: nonce);
    final signature = await signUserSignedAction(
      credentials: _credentials,
      externalSigner: externalSigner,
      action: action,
      fields: usdSendSignTypes,
      primaryType: usdSendPrimaryType,
      isMainnet: HyperliquidConstants.isMainnet,
      signatureChainId: _userSignedChainId,
    );
    final response = await _post(
        action: action,
        signature: signature,
        nonce: nonce,
        beforeSend: beforeSend);
    if (response['status'] != 'ok') {
      throw HyperliquidApiException(
          statusCode: 200, body: jsonEncode(response));
    }
    return nonce;
  }

  /// Native spot transfer. The amount is already formatted from exact base
  /// units. Never retries: a timeout leaves the settlement pending for a public
  /// ledger lookup, instead of risking a second transfer with a fresh nonce.
  Future<int> spotSend({
    required String destination,
    required String token,
    required String amount,
    void Function()? beforeSend,
  }) async {
    if (!isEvmAddress(destination) ||
        !RegExp(r'^\d+(?:\.\d{1,8})?$').hasMatch(amount) ||
        (double.tryParse(amount) ?? 0) <= 0) {
      throw ArgumentError('Invalid native transfer');
    }
    final nonce = nextNonce();
    final action = buildSpotSendAction(
        destination: destination.toLowerCase(),
        token: token,
        amount: amount,
        time: nonce);
    final signature = await signUserSignedAction(
      credentials: _credentials,
      externalSigner: externalSigner,
      action: action,
      fields: spotSendSignTypes,
      primaryType: spotSendPrimaryType,
      isMainnet: HyperliquidConstants.isMainnet,
      signatureChainId: _userSignedChainId,
    );
    final response = await _post(
        action: action,
        signature: signature,
        nonce: nonce,
        beforeSend: beforeSend);
    if (response['status'] != 'ok') {
      throw HyperliquidApiException(
          statusCode: 200, body: jsonEncode(response));
    }
    return nonce;
  }

  /// Withdraws perp USDC to [destination] on Arbitrum (~$1 exchange fee,
  /// arrives in a few minutes). The signed `time` field IS the POSTed
  /// nonce (protocol requirement). Callers pass an
  /// `HlWithdrawDestination.address`; the format check here is the last
  /// backstop before signing.
  Future<void> withdraw3({
    required double amount,
    required String destination,
  }) async {
    if (!isEvmAddress(destination)) {
      TrackingService.hlWithdrawDestinationRejected(kind: 'withdraw3');
      throw const WalletGuardException(
          WalletGuardReason.withdrawDestinationRejected,
          field: 'withdraw3');
    }
    await _withNonceRetry((nonce) async {
      final action = buildWithdraw3Action(
        destination: destination,
        amount: _usdWire(amount),
        time: nonce,
      );
      final sig = await signUserSignedAction(
        credentials: _credentials,
        externalSigner: externalSigner,
        action: action,
        fields: withdrawSignTypes,
        primaryType: withdrawPrimaryType,
        isMainnet: HyperliquidConstants.isMainnet,
        signatureChainId: _userSignedChainId,
      );
      return _post(action: action, signature: sig, nonce: nonce);
    });
  }

  /// Approves [builder] to attach up to [maxFeeRate] (e.g. '0.01%') to the
  /// user's orders. Requires the account to already exist on the exchange
  /// (i.e. after the first deposit lands).
  Future<void> approveBuilderFee({
    required String builder,
    required String maxFeeRate,
  }) async {
    await _withNonceRetry((nonce) async {
      final action = buildApproveBuilderFeeAction(
        builder: builder.toLowerCase(),
        maxFeeRate: maxFeeRate,
        nonce: nonce,
      );
      final sig = await signUserSignedAction(
        credentials: _credentials,
        externalSigner: externalSigner,
        action: action,
        fields: approveBuilderFeeSignTypes,
        primaryType: approveBuilderFeePrimaryType,
        isMainnet: HyperliquidConstants.isMainnet,
        signatureChainId: _userSignedChainId,
      );
      return _post(action: action, signature: sig, nonce: nonce);
    });
  }

  /// Names [code]'s owner as this account's Hyperliquid referrer. An L1
  /// action signed by the account's own key, as the Python SDK's
  /// `set_referrer` does. The venue accepts it only from an account that
  /// already exists (funded) and keeps the first referrer it records.
  Future<void> setReferrer({required String code}) async {
    final body = await _submitL1Action(buildSetReferrerAction(code: code));
    _throwOnStatusError(body);
  }

  // ────────────────────────── internals ────────────────────────────────

  /// Signs and posts an L1 action, optionally retrying one nonce rejection.
  Future<Map<String, dynamic>> _submitL1Action(
    Map<String, dynamic> action, {
    bool retryNonce = true,
    Future<void> Function(HlPendingPost post)? beforeSubmit,
    void Function()? beforeSend,
  }) async {
    Future<Map<String, dynamic>> attempt(int nonce) async {
      final sig = await signL1Action(
        credentials: _credentials,
        externalSigner: externalSigner,
        action: action,
        nonce: nonce,
        isMainnet: HyperliquidConstants.isMainnet,
      );
      return _post(
        action: action,
        signature: sig,
        nonce: nonce,
        beforeSubmit: beforeSubmit,
        beforeSend: beforeSend,
      );
    }

    return retryNonce ? _withNonceRetry(attempt) : attempt(nextNonce());
  }

  /// Runs [attempt] with a fresh nonce; on a nonce rejection (and ONLY a
  /// nonce rejection) retries exactly once with a newer nonce — the
  /// attempt closure re-signs, so the retry is a fully fresh submission.
  Future<Map<String, dynamic>> _withNonceRetry(
      Future<Map<String, dynamic>> Function(int nonce) attempt) async {
    try {
      return await attempt(nextNonce());
    } on HyperliquidRejectedException catch (e) {
      if (e is HyperliquidSignatureRejectedException ||
          !_isNonceRejection(e.reason)) {
        rethrow;
      }
      if (!allowNonceRetry) {
        if (e is HyperliquidNonceRejectedException) rethrow;
        throw HyperliquidNonceRejectedException(e.reason);
      }
      return attempt(nextNonce());
    }
  }

  /// POSTs a signed action. Returns the decoded body when status:'ok';
  /// maps everything else to the taxonomy in the file header.
  Future<Map<String, dynamic>> _post({
    required Map<String, dynamic> action,
    required HlSignature signature,
    required int nonce,
    Future<void> Function(HlPendingPost post)? beforeSubmit,
    void Function()? beforeSend,
  }) async {
    final hook = onBeforePost;
    if (hook != null) await hook(HlPendingPost(action: action, nonce: nonce));
    if (beforeSubmit != null) {
      await beforeSubmit(HlPendingPost(action: action, nonce: nonce));
    }
    final accountingIdentity =
        await HyperliquidRevenue.remember(walletAddress, action);
    const headers = {'content-type': 'application/json'};
    final body = jsonEncode({
      'action': action,
      'nonce': nonce,
      'signature': signature.toJson(),
      'vaultAddress': null,
    });
    final client = _httpClient;
    // Submit → ack latency for order actions only (durations + categorical
    // kind; nothing from the order itself). Reported once per POST from
    // whichever branch ends it.
    final orderKind = OrderAckLatency.hyperliquidOrderKind(action);
    final ack = Stopwatch();
    void reportAck(String outcome) {
      if (orderKind == null || !ack.isRunning) return;
      ack.stop();
      OrderAckLatency.record(
        venue: 'hyperliquid',
        orderKind: orderKind,
        durationMs: ack.elapsedMilliseconds,
        outcome: outcome,
      );
    }

    // No await between the final wallet/session check and transport dispatch.
    beforeSend?.call();
    ack.start();
    final http.Response resp;
    try {
      resp = await (client != null
              ? client.post(HyperliquidConstants.exchangeUri,
                  headers: headers, body: body)
              : http.post(HyperliquidConstants.exchangeUri,
                  headers: headers, body: body))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      reportAck('timeout');
      rethrow;
    } catch (_) {
      reportAck('error');
      rethrow;
    }
    if (resp.statusCode != 200) {
      reportAck('error');
      throw HyperliquidApiException(
          statusCode: resp.statusCode, body: resp.body);
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      reportAck('error');
      throw HyperliquidApiException(statusCode: 200, body: resp.body);
    }
    if (decoded is! Map<String, dynamic>) {
      reportAck('error');
      throw HyperliquidApiException(statusCode: 200, body: resp.body);
    }
    if (decoded['status'] == 'err') {
      reportAck('rejected');
      if ((action['type'] == 'twapOrder' || action['type'] == 'trailingStop') &&
          (decoded['response'] is! String ||
              (decoded['response'] as String).trim().isEmpty)) {
        throw const HyperliquidTwapSubmissionUnknownException();
      }
      throw _rejectionFromReason(
          decoded['response']?.toString() ?? 'unknown rejection');
    }
    reportAck('ok');
    if (accountingIdentity != null) {
      await HyperliquidRevenue.remember(walletAddress, action,
          response: decoded, accountingIdentity: accountingIdentity);
    }
    return decoded;
  }

  /// The raw `response.data.statuses` list, or const [] when absent.
  List<dynamic> _statusesOf(Map<String, dynamic> body) {
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final statuses = (data is Map<String, dynamic>) ? data['statuses'] : null;
    return statuses is List ? statuses : const [];
  }

  /// First error string among statuses AFTER [index], or null. Used by
  /// the grouped TP/SL path to surface a child rejection without
  /// discarding an already-accepted parent.
  String? _firstStatusErrorAfter(Map<String, dynamic> body,
      {required int index}) {
    final statuses = _statusesOf(body);
    for (var i = index + 1; i < statuses.length; i++) {
      final st = statuses[i];
      if (st is Map<String, dynamic> && st['error'] != null) {
        return st['error'].toString();
      }
    }
    return null;
  }

  /// statuses[0] of an order response → result, or throws the mapped
  /// rejection for an error status.
  HlOrderResult _orderResultFromBody(
    Map<String, dynamic> body, {
    String? cloid,
  }) {
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final statuses = (data is Map<String, dynamic>) ? data['statuses'] : null;
    if (statuses is! List || statuses.isEmpty) {
      throw HyperliquidApiException(statusCode: 200, body: jsonEncode(body));
    }
    final st = statuses.first;
    if (st is Map<String, dynamic>) {
      final resting = st['resting'];
      if (resting is Map<String, dynamic>) {
        return HlOrderResult(
          kind: HlOrderResultKind.resting,
          oid: (resting['oid'] as num?)?.toInt(),
          cloid: (resting['cloid'] as String?) ?? cloid,
        );
      }
      final filled = st['filled'];
      if (filled is Map<String, dynamic>) {
        return HlOrderResult(
          kind: HlOrderResultKind.filled,
          oid: (filled['oid'] as num?)?.toInt(),
          cloid: (filled['cloid'] as String?) ?? cloid,
          filledSz: double.tryParse(filled['totalSz']?.toString() ?? '') ?? 0,
          avgPx: double.tryParse(filled['avgPx']?.toString() ?? '') ?? 0,
        );
      }
      final error = st['error'];
      if (error != null) throw _rejectionFromReason(error.toString());
    }
    // Trigger orders acknowledge with bare strings.
    if (st == 'waitingForFill' || st == 'waitingForTrigger') {
      return HlOrderResult(kind: HlOrderResultKind.resting, cloid: cloid);
    }
    throw HyperliquidApiException(statusCode: 200, body: jsonEncode(body));
  }

  /// twapOrder responds with `response.data.status` = {running:{twapId}}
  /// on success or {error:'…'} on rejection (NOT the `statuses` list an
  /// `order` action returns). Maps that to a resting result / rejection.
  HlOrderResult _twapResultFromBody(Map<String, dynamic> body) {
    const unknown = HyperliquidTwapSubmissionUnknownException();
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final status = (data is Map<String, dynamic>) ? data['status'] : null;
    if (body['status'] != 'ok' ||
        response is! Map<String, dynamic> ||
        response['type'] != 'twapOrder' ||
        status is! Map<String, dynamic> ||
        status.length != 1) {
      throw unknown;
    }
    final error = status['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw _rejectionFromReason(error);
    }
    final running = status['running'];
    final twapId = running is Map<String, dynamic> ? running['twapId'] : null;
    if (twapId is! int || twapId <= 0) throw unknown;
    return HlOrderResult(kind: HlOrderResultKind.resting, oid: twapId);
  }

  /// A cancellation is confirmed only by one exact success per requested
  /// order. Missing, extra or unknown statuses cannot justify removing orders
  /// from local state or displaying a cancellation receipt.
  void _requireCancelSuccess(Map<String, dynamic> body,
      {required int expectedCount}) {
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final statuses = (data is Map<String, dynamic>) ? data['statuses'] : null;
    const unknown = HyperliquidApiException(
        statusCode: 200, body: 'Unconfirmed cancellation acknowledgement');
    if (body['status'] != 'ok' ||
        response is! Map<String, dynamic> ||
        response['type'] != 'cancel' ||
        statuses is! List ||
        statuses.length != expectedCount ||
        expectedCount <= 0) {
      throw unknown;
    }
    for (final status in statuses) {
      if (status == 'success') continue;
      if (status is! Map<String, dynamic> ||
          status.length != 1 ||
          status['error'] is! String ||
          (status['error'] as String).isEmpty) {
        throw unknown;
      }
    }
    for (final status in statuses) {
      if (status is Map<String, dynamic>) {
        throw _rejectionFromReason(status['error'] as String);
      }
    }
  }

  /// Legacy acknowledgement handling for non-cancellation actions.
  /// Cancellations use the strict operation-specific validators above.
  void _throwOnStatusError(Map<String, dynamic> body) {
    final response = body['response'];
    final data = (response is Map<String, dynamic>) ? response['data'] : null;
    final statuses = (data is Map<String, dynamic>) ? data['statuses'] : null;
    if (statuses is! List) return;
    for (final st in statuses) {
      if (st is Map<String, dynamic> && st['error'] != null) {
        throw _rejectionFromReason(st['error'].toString());
      }
    }
  }

  HyperliquidRejectedException _rejectionFromReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('minimum value')) {
      final match = RegExp(r'minimum value(?: of)?\s*\$([0-9]+(?:\.[0-9]+)?)',
              caseSensitive: false)
          .firstMatch(reason);
      return HyperliquidMinNotionalException(reason,
          minimumUsd: match == null ? null : double.tryParse(match.group(1)!));
    }
    if (lower.contains('insufficient margin') ||
        lower.contains('insufficient spot balance') ||
        lower.contains('insufficient balance')) {
      return HyperliquidInsufficientMarginException(reason);
    }
    if (lower.contains('does not exist')) {
      return HyperliquidSignatureRejectedException(reason);
    }
    if (_isNonceRejection(reason)) {
      return HyperliquidNonceRejectedException(reason);
    }
    return HyperliquidRejectedException(reason);
  }

  bool _isNonceRejection(String reason) {
    final lower = reason.toLowerCase();
    return lower.contains('invalid nonce') ||
        lower.contains('nonce') && lower.contains('already') ||
        lower.contains('duplicate nonce');
  }

  /// USD amount → wire string, pre-rounded to USDC's 6 decimals so
  /// floatToWire's drift guard can't trip on binary-float artifacts.
  String _usdWire(double amount) {
    if (amount <= 0) {
      throw ArgumentError('amount must be positive, got $amount');
    }
    return floatToWire(double.parse(amount.toStringAsFixed(6)));
  }
}
