import 'package:kute/services/hyperliquid/trailing_stop.dart';
// lib/helpers/venue_intents.dart
//
// Step-up v2 venue binding (Wallet Hardening Phase 1b.3 to 1b.5).
//
// One place turns venue parameters into a [SensitiveIntent]. The review UI
// builds the intent it asks the user to approve, and the executor rebuilds
// the intent it is about to submit, through the SAME helpers with the SAME
// arguments. Representations therefore match exactly and only real drift
// (D-12) re-auths.
//
// Two executor styles:
//   * Full rebuild (Hyperliquid and Polymarket orders): the
//     executor calls the builder below with its own arguments, then
//     [GrantGuard.check] on laddered retries and [GrantGuard.consume] on
//     the submit.
//   * Derived (withdrawals): the executor cannot know everything the user
//     reviewed (for example the final recipient behind a provider deposit
//     address), so it overrides only what it knows on the grant's bound
//     intent with [GrantGuard.derive].
//
// Chained grants ([GrantGuard.chain]) let one approval cover several
// executor calls that each need their own single-use grant: builder legs
// (one grant bound to the leg list) and autofire (the 30 min confirm-time
// grant is consumed, then a child grant bound to the exact order is handed
// to the executor).
//
// Also here: the Hyperliquid Builder run intents ([HlBuilderIntents]), the
// Polymarket grant helpers ([PmGrants], [PmLadderGrant]) and the Orchestra
// settlement intent ([OrchestraGrants]).
//
// Privacy: nothing here is tracked or logged.

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;

/// Venue strings used in intents.
abstract final class IntentVenue {
  static const hyperliquid = 'hyperliquid';
  static const polymarket = 'polymarket';
  static const orchestra = 'orchestra';
  static const spark = 'spark';
  static const bitcoin = 'bitcoin';
  static const lightning = 'lightning';
  static const local = 'local';
}

/// Unit conversions shared by review and executor.
abstract final class IntentUnits {
  /// USD stablecoin base units (6 decimals), rounded up. Zero for
  /// non-positive or non-finite input.
  static BigInt usd(double usd) {
    if (!usd.isFinite || usd <= 0) return BigInt.zero;
    return BigInt.from((usd * 1000000).ceil());
  }

  /// Coin or share size in 1e8 fixed units, rounded up.
  static BigInt size(double size) {
    if (!size.isFinite || size <= 0) return BigInt.zero;
    return BigInt.from((size * 100000000).ceil());
  }

  /// Percent to basis points.
  static int bps(double pct) => (pct * 100).round();

  /// A fraction in 0..1 as basis points (0..10000).
  static BigInt fractionBps(double fraction) =>
      BigInt.from((fraction.clamp(0.0, 1.0) * 10000).round());
}

/// Extra limit keys used by the venue builders. Keys not in [IntentLimit]
/// are bound exactly.
abstract final class VenueLimit {
  /// `spot` or `perp`.
  static const marketType = 'marketType';

  /// `cross`, `isolated` or null (executor default).
  static const marginMode = 'marginMode';
  static const tif = 'tif';
  static const takeProfitPx = 'takeProfitPx';
  static const stopLossPx = 'stopLossPx';
  static const startPx = 'startPx';
  static const endPx = 'endPx';
  static const count = 'count';
  static const durationMinutes = 'durationMinutes';
  static const randomize = 'randomize';
  static const triggerPx = 'triggerPx';
  static const isMarket = 'isMarket';
  static const tpsl = 'tpsl';

  /// The venue order id a modify replaces.
  static const orderId = 'orderId';

  /// Amount unit for Hyperliquid orders: `usd` (6 decimals) or `coin`
  /// (1e8).
  static const sizeUnit = 'sizeUnit';

  /// Polymarket order type name (fok, fak, gtc, ...).
  static const orderType = 'orderType';

  /// Polymarket withdrawals: true sends USDC.e, false swaps to native USDC.
  static const bridged = 'bridged';

  /// Hyperliquid withdrawals: `own_eoa` or `accumulation`.
  static const destinationKind = 'destinationKind';
}

/// Hyperliquid intents (`hlOrder`, `venueWithdraw`).
///
/// Pass exactly the arguments passed to the matching
/// `HyperliquidTradingNotifier` method (before any defaulting), plus the
/// spending wallet id. [HlMarket] clamps leverage the same way the notifier
/// does.
abstract final class HlIntents {
  static const kindPerp = 'perp';

  /// `placeSpotOrder`. The D-11 allowance scope reads this value.
  static const kindSpot = 'spot';
  static const kindLimit = 'limit';
  static const kindScale = 'scale';
  static const kindTwap = 'twap';
  static const kindTrigger = 'trigger';
  static const kindClose = 'close';

  /// `modifyOrder` (a resting order moved to a new price).
  static const kindModify = 'modify';

  /// `setMarginMode` (a leverage or margin mode change on its own).
  static const kindLeverage = 'leverage';

  /// `adjustIsolatedMargin` (margin added to or removed from an isolated
  /// position).
  static const kindMargin = 'margin';

  static String side(bool isBuy, {required bool isSpot}) =>
      isSpot ? (isBuy ? 'buy' : 'sell') : (isBuy ? 'long' : 'short');

  static int clampLeverage(HlMarket market, int leverage) =>
      market.isSpot ? 1 : leverage.clamp(1, market.maxLeverage).toInt();

  static SensitiveIntent _order({
    required String walletId,
    required HlMarket market,
    required bool isBuy,
    required String orderKind,
    required BigInt amountMax,
    required String sizeUnit,
    int leverage = 1,
    bool? isCross,
    double? slippagePct,
    bool reduceOnly = false,
    double? limitPrice,
    Map<String, Object?> extra = const {},
  }) {
    return SensitiveIntent(
      action: SensitiveAction.hlOrder,
      walletId: walletId,
      venue: IntentVenue.hyperliquid,
      destination: market.coin,
      asset: market.coin,
      amountMax: amountMax,
      limits: {
        IntentLimit.side: side(isBuy, isSpot: market.isSpot),
        IntentLimit.orderKind: orderKind,
        IntentLimit.leverage: clampLeverage(market, leverage),
        IntentLimit.reduceOnly: reduceOnly,
        VenueLimit.marketType: market.isSpot ? 'spot' : 'perp',
        VenueLimit.sizeUnit: sizeUnit,
        VenueLimit.marginMode: isCross == null
            ? null
            : (isCross && !market.onlyIsolated ? 'cross' : 'isolated'),
        if (slippagePct != null)
          IntentLimit.maxSlippageBps: IntentUnits.bps(slippagePct),
        if (limitPrice != null) IntentLimit.limitPrice: limitPrice,
        ...extra,
      },
    );
  }

  /// `openPosition`.
  static SensitiveIntent openPosition({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    required double marginUsd,
    required int leverage,
    double slippagePct = 1.0,
    bool? isCross,
    double? takeProfitPx,
    double? stopLossPx,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindPerp,
        amountMax: IntentUnits.usd(marginUsd),
        sizeUnit: 'usd',
        leverage: leverage,
        isCross: isCross,
        slippagePct: slippagePct,
        extra: {
          VenueLimit.takeProfitPx: takeProfitPx,
          VenueLimit.stopLossPx: stopLossPx,
        },
      );

  /// `placeSpotOrder`.
  static SensitiveIntent spotOrder({
    required String walletId,
    required HlMarket market,
    required bool isBuy,
    required double usd,
    double slippagePct = 1.0,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isBuy,
        orderKind: kindSpot,
        amountMax: IntentUnits.usd(usd),
        sizeUnit: 'usd',
        slippagePct: slippagePct,
      );

  /// `placeLimit`. Coin [size] wins over [marginUsd], as in the notifier.
  static SensitiveIntent limit({
    required String walletId,
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
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindLimit,
        amountMax: size != null
            ? IntentUnits.size(size)
            : IntentUnits.usd(marginUsd ?? 0),
        sizeUnit: size != null ? 'coin' : 'usd',
        leverage: leverage,
        isCross: isCross,
        reduceOnly: reduceOnly,
        limitPrice: px,
        extra: {
          VenueLimit.tif: postOnly ? 'Alo' : tif,
          VenueLimit.takeProfitPx: takeProfitPx,
          VenueLimit.stopLossPx: stopLossPx,
        },
      );

  /// `placeTrigger`.
  static SensitiveIntent trigger({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    required double size,
    required double triggerPx,
    required bool isMarket,
    required String tpsl,
    double? limitPx,
    bool reduceOnly = true,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindTrigger,
        amountMax: IntentUnits.size(size),
        sizeUnit: 'coin',
        reduceOnly: reduceOnly,
        limitPrice: limitPx,
        extra: {
          VenueLimit.triggerPx: triggerPx,
          VenueLimit.isMarket: isMarket,
          VenueLimit.tpsl: tpsl,
        },
      );

  /// `modifyOrder`. [px] is the new resting price (limit) or the new
  /// trigger price; the remaining size and side are the order's own.
  static SensitiveIntent modify({
    required String walletId,
    required HlMarket market,
    required int oid,
    required bool isLong,
    required double size,
    required double px,
    required bool reduceOnly,
    String tif = 'Gtc',
    String? tpsl,
    bool isMarket = false,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindModify,
        amountMax: IntentUnits.size(size),
        sizeUnit: 'coin',
        reduceOnly: reduceOnly,
        limitPrice: px,
        extra: {
          VenueLimit.orderId: oid,
          VenueLimit.tif: tif,
          if (tpsl != null) VenueLimit.tpsl: tpsl,
          if (tpsl != null) VenueLimit.triggerPx: px,
          if (tpsl != null) VenueLimit.isMarket: isMarket,
        },
      );

  /// `placeScale`.
  static SensitiveIntent scale({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    required double totalUsd,
    required double startPx,
    required double endPx,
    required int count,
    int leverage = 1,
    bool? isCross,
    bool reduceOnly = false,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindScale,
        amountMax: IntentUnits.usd(totalUsd),
        sizeUnit: 'usd',
        leverage: leverage,
        isCross: isCross,
        reduceOnly: reduceOnly,
        extra: {
          VenueLimit.startPx: startPx,
          VenueLimit.endPx: endPx,
          VenueLimit.count: count,
        },
      );

  /// `placeTwap`. Coin [size] wins over [marginUsd], as in the notifier.
  static SensitiveIntent twap({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    double? marginUsd,
    double? size,
    int leverage = 1,
    bool? isCross,
    required int durationMinutes,
    bool randomize = false,
    bool reduceOnly = false,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: kindTwap,
        amountMax: size != null
            ? IntentUnits.size(size)
            : IntentUnits.usd(marginUsd ?? 0),
        sizeUnit: size != null ? 'coin' : 'usd',
        leverage: leverage,
        isCross: isCross,
        reduceOnly: reduceOnly,
        extra: {
          VenueLimit.durationMinutes: durationMinutes,
          VenueLimit.randomize: randomize,
        },
      );

  static SensitiveIntent trailingStop({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    required double size,
    required HlTrailingStop trail,
    int leverage = 1,
    bool? isCross,
    bool reduceOnly = false,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: isLong,
        orderKind: 'trailingStop',
        amountMax: IntentUnits.size(size),
        sizeUnit: 'coin',
        leverage: leverage,
        isCross: isCross,
        reduceOnly: reduceOnly,
        extra: trail.intentFields,
      );

  /// `closePosition`. [positionIsLong] is the side of the position being
  /// closed; the order side is the opposite. The amount is the fraction in
  /// basis points.
  static SensitiveIntent close({
    required String walletId,
    required HlMarket market,
    required bool positionIsLong,
    double fraction = 1.0,
    double slippagePct = 1.0,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: !positionIsLong,
        orderKind: kindClose,
        amountMax: IntentUnits.fractionBps(fraction),
        sizeUnit: 'fraction_bps',
        reduceOnly: true,
        slippagePct: slippagePct,
      );

  /// `setMarginMode`.
  static SensitiveIntent marginMode({
    required String walletId,
    required HlMarket market,
    required bool isCross,
    required int leverage,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: true,
        orderKind: kindLeverage,
        amountMax: BigInt.zero,
        sizeUnit: 'none',
        leverage: leverage,
        isCross: isCross,
      );

  /// `adjustIsolatedMargin`: [usd] added to (positive) or removed from
  /// (negative) the isolated position on [market]. The grant binds the
  /// market, the position's side, the direction and the exact amount.
  static SensitiveIntent isolatedMargin({
    required String walletId,
    required HlMarket market,
    required bool positionIsLong,
    required double usd,
  }) =>
      _order(
        walletId: walletId,
        market: market,
        isBuy: positionIsLong,
        orderKind: kindMargin,
        amountMax: IntentUnits.usd(usd.abs()),
        sizeUnit: 'usd',
        isCross: false,
        extra: {'margin_direction': usd >= 0 ? 'add' : 'remove'},
      );

  /// `withdrawToArbitrum` review intent. [destination] is the Arbitrum
  /// address for `own_eoa`, or the FINAL recipient (the user's own Spark
  /// address) for `accumulation`, never the accumulation deposit address.
  /// [action] is `venueWithdraw`, or `moveTransfer` from the Move sheet.
  static SensitiveIntent withdraw({
    required String walletId,
    required double usd,
    required String destination,
    required String destinationKind,
    SensitiveAction action = SensitiveAction.venueWithdraw,
    Map<String, Object?> extra = const {},
  }) =>
      SensitiveIntent(
        action: action,
        walletId: walletId,
        venue: IntentVenue.hyperliquid,
        destination: destination,
        asset: 'USDC',
        amountMax: IntentUnits.usd(usd),
        limits: {
          VenueLimit.destinationKind: destinationKind,
          if (destinationKind == 'accumulation')
            IntentLimit.provider: IntentVenue.orchestra,
          ...extra,
        },
      );
}

/// Polymarket intents (`pmBet`, `pmSell`, `venueWithdraw`).
abstract final class PmIntents {
  /// USD cost for a buy (6 decimals), share size for a sell (1e8).
  static BigInt orderAmount({
    required bool isBuy,
    required double size,
    required double price,
  }) =>
      isBuy ? IntentUnits.usd(size * price) : IntentUnits.size(size);

  /// `placeOrder`. The executor rebuilds this with the order's own size,
  /// price and type. The review side binds the CAP of what the order
  /// (or its slippage ladder) may reach: [amountMax] the largest cost or
  /// share size, [limitPrice] the worst price (highest for a buy, lowest
  /// for a sell). Pass [maxSlippageBps] only on the review side.
  static SensitiveIntent order({
    required String walletId,
    required String tokenId,
    required bool isBuy,
    required BigInt amountMax,
    required double limitPrice,
    required String orderType,
    int? maxSlippageBps,
  }) =>
      SensitiveIntent(
        action: isBuy ? SensitiveAction.pmBet : SensitiveAction.pmSell,
        walletId: walletId,
        venue: IntentVenue.polymarket,
        destination: tokenId,
        asset: isBuy ? 'PUSD' : 'SHARES',
        amountMax: amountMax,
        limits: {
          IntentLimit.side: isBuy ? 'buy' : 'sell',
          IntentLimit.limitPrice: limitPrice,
          VenueLimit.orderType: orderType,
          if (maxSlippageBps != null)
            IntentLimit.maxSlippageBps: maxSlippageBps,
        },
      );
}

/// Executor-side grant enforcement.
abstract final class GrantGuard {
  /// The grant's bound intent with every field the executor knows
  /// replaced. [limits] entries override bound entries by key. The action
  /// is always the grant's; pass the accepted actions to [check].
  static SensitiveIntent derive(
    AuthGrant grant, {
    String? walletId,
    String? venue,
    String? account,
    String? destination,
    String? asset,
    BigInt? amountMax,
    Map<String, Object?> limits = const {},
  }) {
    final b = grant.boundIntent;
    return SensitiveIntent(
      action: b.action,
      walletId: walletId ?? b.walletId,
      venue: venue ?? b.venue,
      account: account ?? b.account,
      destination: destination ?? b.destination,
      asset: asset ?? b.asset,
      amountMax: amountMax ?? b.amountMax,
      limits: {...b.limits, ...limits},
    );
  }

  static void _requireAction(AuthGrant grant, Set<SensitiveAction> allowed) {
    if (!allowed.contains(grant.action)) {
      throw ReauthRequired(const {DriftField.action});
    }
  }

  /// [AuthGrants.check] plus an action gate. For laddered retries.
  static void check(
    AuthGrant grant,
    SensitiveIntent actual, {
    required Set<SensitiveAction> allowed,
  }) {
    _requireAction(grant, allowed);
    if (actual.action != grant.action) {
      throw ReauthRequired(const {DriftField.action});
    }
    AuthGrants.check(grant, actual);
  }

  /// [AuthGrants.consume] plus an action gate. For the submit.
  static void consume(
    AuthGrant grant,
    SensitiveIntent actual, {
    required Set<SensitiveAction> allowed,
  }) {
    _requireAction(grant, allowed);
    if (actual.action != grant.action) {
      throw ReauthRequired(const {DriftField.action});
    }
    AuthGrants.consume(grant, actual);
  }

  /// Issues a single-use child grant bound to [child], carrying the
  /// parent's method and never outliving it. Call only right after the
  /// parent was checked or consumed against an intent that covers [child]
  /// (a builder leg of the approved leg list, or the exact autofire order).
  static AuthGrant chain(AuthGrant parent, SensitiveIntent child) {
    final now = AuthGrants.clock();
    final remaining = parent.expiresAt.difference(now);
    if (parent.revoked || remaining <= Duration.zero) {
      throw const GrantExpired();
    }
    final ttl =
        remaining < AuthGrants.defaultTtl ? remaining : AuthGrants.defaultTtl;
    return AuthGrants.issue(child.copyWith(ttl: ttl),
        method: parent.method, now: now);
  }

  /// Canonical form of one leg for a leg-list intent: the leg intent's
  /// canonical JSON. Bind `IntentLimit.legs` to the list of these.
  static String legKey(SensitiveIntent leg) => leg.canonicalJson;
}

// ── Hyperliquid Builder ─────────────────────────────────────────────

/// Portfolio Builder intents (`hlOrder`).
abstract final class HlBuilderIntents {
  /// `orderKind` of the run intent.
  static const kindBuilder = 'builder';

  /// One Builder leg exactly as `placeTradeBuilderLeg` places it: a spot
  /// buy through `placeSpotOrder`, or a 1x perp open through
  /// `openPosition`, both at the notifier's default slippage.
  static SensitiveIntent leg({
    required String walletId,
    required HlMarket market,
    required bool isLong,
    required double usd,
  }) =>
      market.isSpot
          ? HlIntents.spotOrder(
              walletId: walletId,
              market: market,
              isBuy: true,
              usd: usd,
            )
          : HlIntents.openPosition(
              walletId: walletId,
              market: market,
              isLong: isLong,
              marginUsd: usd,
              leverage: 1,
            );

  /// The run intent the user approves once: the exact leg list (in order)
  /// and the total of the legs' amounts.
  static SensitiveIntent legList({
    required String walletId,
    required List<SensitiveIntent> legs,
  }) {
    var total = BigInt.zero;
    for (final l in legs) {
      total += l.amountMax;
    }
    return SensitiveIntent(
      action: SensitiveAction.hlOrder,
      walletId: walletId,
      venue: IntentVenue.hyperliquid,
      asset: 'USDC',
      amountMax: total,
      limits: {
        IntentLimit.orderKind: kindBuilder,
        IntentLimit.legs: [for (final l in legs) GrantGuard.legKey(l)],
      },
    );
  }
}

// ── Polymarket ──────────────────────────────────────────────────────

/// Polymarket grant helpers shared by the review UI and the executors.
abstract final class PmGrants {
  static const Set<SensitiveAction> betActions = {SensitiveAction.pmBet};
  static const Set<SensitiveAction> sellActions = {SensitiveAction.pmSell};

  /// Grants `withdrawUsdc` accepts: a Predictions withdrawal, the `send`
  /// grant from confirm_send, or a Move sheet grant.
  static const Set<SensitiveAction> withdrawActions = {
    SensitiveAction.venueWithdraw,
    SensitiveAction.send,
    SensitiveAction.moveTransfer,
  };

  static Set<SensitiveAction> orderActions(bool isBuy) =>
      isBuy ? betActions : sellActions;

  /// Micro-USD cost of [size] shares at [price], to the nearest micro, so
  /// float noise on a cost exactly at the cap never reads as an increase.
  /// Review caps use `IntentUnits.usd` (rounded up).
  static BigInt buyCostMicros(double size, double price) {
    final micros = size * price * 1000000;
    if (!micros.isFinite || micros <= 0) return BigInt.zero;
    return BigInt.from(micros.round());
  }

  /// What an order binds as its amount: the cost for a buy, the share size
  /// (1e8) for a sell.
  static BigInt orderAmount({
    required bool isBuy,
    required double size,
    required double price,
  }) =>
      isBuy ? buyCostMicros(size, price) : IntentUnits.size(size);

  /// The intent `placeOrder` is about to submit, rebuilt from its own
  /// arguments. [orderType] is the `OrderType` name. The executor cannot
  /// measure slippage, so a `maxSlippageBps` bound on [grant] is carried
  /// over; the price cap is what enforces it.
  static SensitiveIntent executedOrder(
    AuthGrant grant, {
    required String walletId,
    required String tokenId,
    required bool isBuy,
    required double size,
    required double price,
    required String orderType,
  }) {
    final base = PmIntents.order(
      walletId: walletId,
      tokenId: tokenId,
      isBuy: isBuy,
      amountMax: orderAmount(isBuy: isBuy, size: size, price: price),
      limitPrice: price,
      orderType: orderType,
    );
    final slippage = grant.boundIntent.limits[IntentLimit.maxSlippageBps];
    if (slippage == null) return base;
    return base.copyWith(
      limits: {...base.limits, IntentLimit.maxSlippageBps: slippage},
    );
  }

  /// Review intent for a buy. [maxCostUsd] is the largest cost any rung may
  /// spend and [worstPrice] the highest rung price.
  static SensitiveIntent betReview({
    required String walletId,
    required String tokenId,
    required double maxCostUsd,
    required double worstPrice,
    required String orderType,
  }) =>
      PmIntents.order(
        walletId: walletId,
        tokenId: tokenId,
        isBuy: true,
        amountMax: IntentUnits.usd(maxCostUsd),
        limitPrice: worstPrice,
        orderType: orderType,
      );

  /// Review intent for selling [shares]. [worstPrice] is the lowest rung
  /// price.
  static SensitiveIntent sellReview({
    required String walletId,
    required String tokenId,
    required double shares,
    required double worstPrice,
    required String orderType,
  }) =>
      PmIntents.order(
        walletId: walletId,
        tokenId: tokenId,
        isBuy: false,
        amountMax: IntentUnits.size(shares),
        limitPrice: worstPrice,
        orderType: orderType,
      );

  /// The run intent a Predictions Builder approves once: the exact list of
  /// leg review intents (in order) and the total of their caps.
  static SensitiveIntent builderRun({
    required String walletId,
    required List<SensitiveIntent> legs,
  }) {
    var total = BigInt.zero;
    for (final l in legs) {
      total += l.amountMax;
    }
    return SensitiveIntent(
      action: SensitiveAction.pmBet,
      walletId: walletId,
      venue: IntentVenue.polymarket,
      asset: 'PUSD',
      amountMax: total,
      limits: {
        IntentLimit.orderKind: HlBuilderIntents.kindBuilder,
        IntentLimit.legs: [for (final l in legs) GrantGuard.legKey(l)],
      },
    );
  }

  /// `orderKind` of a combo (parlay) bet or close.
  static const kindCombo = 'combo';

  /// One combo bet (Polymarket Combos RFQ): the exact canonical leg list,
  /// the most it may cost with fees ([maxStakeE6], pUSD base units) and the
  /// least it must pay out if every leg wins ([minPayoutE6], combo shares
  /// in base units). The review binds the shown quote; the executor binds
  /// the quote it signs, which may only cost less and pay out more.
  static SensitiveIntent comboBet({
    required String walletId,
    required List<String> legPositionIds,
    required BigInt maxStakeE6,
    required BigInt minPayoutE6,
  }) =>
      SensitiveIntent(
        action: SensitiveAction.pmBet,
        walletId: walletId,
        venue: IntentVenue.polymarket,
        asset: 'PUSD',
        amountMax: maxStakeE6,
        limits: {
          IntentLimit.orderKind: kindCombo,
          IntentLimit.side: 'buy',
          IntentLimit.legs: legPositionIds,
          IntentLimit.minReceive: minPayoutE6,
        },
      );

  /// Closing one combo early: sell at most [sharesE6] of combo
  /// [positionId] for at least [minProceedsE6] pUSD (both base units).
  static SensitiveIntent comboClose({
    required String walletId,
    required String positionId,
    required BigInt sharesE6,
    required BigInt minProceedsE6,
  }) =>
      SensitiveIntent(
        action: SensitiveAction.pmSell,
        walletId: walletId,
        venue: IntentVenue.polymarket,
        destination: positionId,
        asset: 'SHARES',
        amountMax: sharesE6,
        limits: {
          IntentLimit.orderKind: kindCombo,
          IntentLimit.side: 'sell',
          IntentLimit.minReceive: minProceedsE6,
        },
      );

  /// Cents covering [micros], rounded up, for the D-11 allowance (which
  /// refuses base units above the stated cents).
  static int usdCentsCeil(BigInt micros) =>
      ((micros + BigInt.from(9999)) ~/ BigInt.from(10000)).toInt();

  /// Re-check inside the SAME `placeOrder` call that consumed [grant] (its
  /// self-heal retries): revocation, expiry and drift exactly like
  /// `AuthGrants.check`, with the consumed flag that call set expected.
  /// Never use it anywhere else.
  static void checkRetry(AuthGrant grant, SensitiveIntent actual) {
    if (grant.revoked) throw const GrantRevoked();
    if (grant.isExpiredAt(AuthGrants.clock())) throw const GrantExpired();
    final drift = AuthGrants.driftBetween(grant.boundIntent, actual);
    if (drift.isNotEmpty) throw ReauthRequired(drift);
  }

  /// True when [grant] approved an Orchestra-funded move.
  static bool isOrchestraFunded(AuthGrant grant) {
    final bound = grant.boundIntent;
    return bound.venue == IntentVenue.orchestra ||
        bound.limits[IntentLimit.provider] == IntentVenue.orchestra;
  }

  /// The intent `withdrawUsdc` checks and consumes. The wallet stays as
  /// bound; the Safe ([account]) is what the funds leave from.
  ///
  /// Predictions money only leaves the Safe through an Orchestra venue
  /// withdrawal: the grant must be Orchestra-funded and the send
  /// quote-bound ([quoteBound]). The per-quote deposit address is never
  /// bound. Any other grant re-authenticates, so no
  /// grant can send the balance to an address of its own.
  static SensitiveIntent executedWithdraw(
    AuthGrant grant, {
    required String account,
    required BigInt amountMicros,
    required bool bridged,
    required bool quoteBound,
  }) {
    final bound = grant.boundIntent.limits;
    final bridgedLimit = <String, Object?>{
      if (bound.containsKey(VenueLimit.bridged)) VenueLimit.bridged: bridged,
    };
    final asset = bridged ? 'USDC.e' : 'USDC';
    if (!isOrchestraFunded(grant) || !quoteBound) {
      throw ReauthRequired(const {DriftField.route});
    }
    return GrantGuard.derive(
      grant,
      account: account,
      asset: asset,
      amountMax: amountMicros,
      limits: bridgedLimit,
    );
  }
}

/// One approval covering a laddered Polymarket order. The approval binds the
/// ladder's cap; every rung is checked against it and gets a single-use
/// child grant bound to exactly that rung.
class PmLadderGrant {
  PmLadderGrant(this.approval);

  final AuthGrant approval;

  /// The child grant for one rung. Throws `ReauthRequired` when the rung is
  /// past the approved cap, or `GrantExpired` when the approval lapsed.
  AuthGrant rung({
    required String walletId,
    required String tokenId,
    required bool isBuy,
    required double size,
    required double price,
    required String orderType,
  }) {
    final actual = PmGrants.executedOrder(
      approval,
      walletId: walletId,
      tokenId: tokenId,
      isBuy: isBuy,
      size: size,
      price: price,
      orderType: orderType,
    );
    GrantGuard.check(approval, actual, allowed: PmGrants.orderActions(isBuy));
    return GrantGuard.chain(approval, actual);
  }

  /// Ends the approval once the ladder stops (filled, failed or abandoned).
  void close() {
    if (!approval.consumed) approval.revoke();
  }
}

// ── Orchestra ───────────────────────────────────────────────────────

/// Grants for moves an Orchestra settlement funds: Move sheet dispatchers,
/// Predictions deposits and withdrawals.
abstract final class OrchestraGrants {
  /// The intent a settlement runner step-up hook approves, built from its
  /// [auth] terms: the final recipient plus the route label and route
  /// version, the quoted amount, the minimum receive and the fee cap in
  /// basis points. Never the per-quote deposit address (the Phase 2 quote
  /// gate checks that).
  static SensitiveIntent settlement(
    SettlementAuthorizationIntent auth, {
    required SensitiveAction action,
    required String asset,
    String? account,
    Map<String, Object?> limits = const {},
  }) {
    final sep = auth.destination.lastIndexOf('|');
    final recipient =
        sep < 0 ? auth.destination : auth.destination.substring(0, sep);
    final version = sep < 0 ? '' : auth.destination.substring(sep + 1);
    return SensitiveIntent.orchestraFunded(
      action: action,
      walletId: auth.walletId,
      account: account,
      finalRecipient: recipient.trim(),
      routeVersion:
          version.isEmpty ? auth.routeLabel : '${auth.routeLabel}|$version',
      asset: asset,
      amountMax: auth.amountIn,
      limits: {
        IntentLimit.minReceive: auth.minReceive,
        IntentLimit.maxFee: auth.maxFeeBps,
        ...limits,
        if (auth.sourceFeeBaseUnits != null)
          'sourceFeeBaseUnits': auth.sourceFeeBaseUnits!.toString(),
        if (auth.sourceFeeAsset != null) 'sourceFeeAsset': auth.sourceFeeAsset,
      },
    );
  }
}
