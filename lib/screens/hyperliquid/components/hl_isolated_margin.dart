// lib/screens/hyperliquid/components/hl_isolated_margin.dart
//
// The figures an isolated position's margin moves, worked out once for
// the position screen, the margin sheet and the Portfolio card, and what
// closing any position now gives back (its margin plus the profit or
// loss). Pure: nothing here reads or asks the venue.
//
// What the venue reports (clearinghouseState, checked against the live
// API on 5 Oct 2026): for an ISOLATED position `marginUsed` is the money
// in it, the margin put in plus the unrealised profit or loss
// (`leverage.rawUsd + positionValue` for a long, `rawUsd - positionValue`
// for a short). `positionValue` is the notional (size x mark) and does not
// move when margin is added or removed; `marginUsed`, the liquidation
// price and the cash do.

import 'dart:math' as math;

import 'package:kute/models/hyperliquid_market.dart';

/// The money in an isolated position: its margin plus the profit or loss,
/// following the live mid when there is one. Null for a cross position,
/// whose margin is shared with the whole account.
double? hlPositionMoney(HlPerpPosition p, {double? liveMid}) {
  if (p.isCross) return null;
  if (liveMid == null || !liveMid.isFinite || liveMid <= 0) {
    return p.marginUsed;
  }
  final livePnl = (liveMid - p.entryPx) * p.szi;
  return p.marginUsed + (livePnl - p.unrealizedPnl);
}

/// The profit or loss of [p] at the live mid, else the venue's snapshot.
double hlLivePnl(HlPerpPosition p, {double? liveMid}) =>
    liveMid == null || !liveMid.isFinite || liveMid <= 0
        ? p.unrealizedPnl
        : (liveMid - p.entryPx) * p.szi;

/// The user's own money behind [p], without the profit or loss: an
/// isolated position's margin (what was put in, with any margin added or
/// removed since), a cross position's collateral (the margin it ties up).
/// The base of the position's return.
double hlPositionMargin(HlPerpPosition p) =>
    p.isCross ? p.marginUsed : p.marginUsed - p.unrealizedPnl;

/// What closing [p] now gives back, before fees: its margin plus the
/// profit or loss at the live mid. The big number of the Portfolio card
/// and of the position screen ("If you close now"), never the notional
/// (size x price, the "Position size" row). For an isolated position it is
/// [hlPositionMoney].
double hlCloseValue(HlPerpPosition p, {double? liveMid}) =>
    hlPositionMargin(p) + hlLivePnl(p, liveMid: liveMid);

/// What can be taken out of an isolated position. The venue's transfer
/// rule: what stays must cover the larger of the initial margin of the
/// leverage setting and 10% of the position's notional
/// (`transfer_margin_required = max(initial_margin_required,
/// 0.1 * total_position_value)`). Floored to a cent, never below zero.
double hlRemovableMargin(HlPerpPosition p) {
  final lev = p.leverageValue > 0 ? p.leverageValue : 1;
  final notional = p.positionValue.abs();
  final required = math.max(notional / lev, 0.1 * notional);
  final free = p.marginUsed - required;
  return free > 0 ? (free * 100).floorToDouble() / 100 : 0;
}

/// The liquidation price after moving [delta] USD of margin (positive =
/// added): the margin change spread over the position size, away from the
/// price for added margin. Null without a liquidation price.
double? hlLiquidationAfter(HlPerpPosition p, double delta) {
  final liq = p.liquidationPx;
  final size = p.szi.abs();
  if (liq == null || !liq.isFinite || liq <= 0 || size <= 0) return null;
  final shifted = p.isLong ? liq - delta / size : liq + delta / size;
  return shifted > 0 ? shifted : null;
}

/// Whether margin can be moved on [p] from here: an isolated perp on the
/// very market it is held on, so the action signs against that
/// position's asset. The callers add the rest: the spending wallet only
/// (the Ledger signer has no reviewed path for updateIsolatedMargin) and
/// only while the position is open.
bool hlCanAdjustMargin(HlPerpPosition p, HlMarket? m) =>
    !p.isCross && m != null && !m.isSpot && m.wireCoin == p.coin;
