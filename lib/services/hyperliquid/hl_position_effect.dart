// lib/services/hyperliquid/hl_position_effect.dart
//
// What a perp order does to the position already held in its market.
// Hyperliquid keeps one net position per market and account (one-way
// mode), so an order on the other side of a held position nets against
// it: it reduces it, closes it, or closes it and opens the rest on the new
// side (a flip). The Investing order slip names that on its button and in
// a line under the amount, sends a reduce or a close reduce-only (no venue
// minimum, no margin to fund) and records it as `position_effect`.

import 'dart:math' as math;

import 'package:kute/models/hyperliquid_market.dart';

enum HlPositionEffect { open, add, reduce, close, flip }

class HlPositionPlan {
  const HlPositionPlan(
    this.effect, {
    this.position,
    this.heldSize = 0,
    this.orderSize = 0,
  });

  const HlPositionPlan.open() : this(HlPositionEffect.open);

  final HlPositionEffect effect;
  final HlPerpPosition? position;

  /// The held position's size, unsigned.
  final double heldSize;

  /// The floored size the order sends.
  final double orderSize;

  /// A reduce or a close: an exit, sent reduce-only, with no venue minimum
  /// and no margin to fund.
  bool get isExit =>
      effect == HlPositionEffect.reduce || effect == HlPositionEffect.close;

  /// A position on the other side of the order is held.
  bool get opposes => isExit || effect == HlPositionEffect.flip;

  bool get heldLong => position?.isLong ?? false;

  /// 'long' or 'short', for the select in the slip's strings.
  String get heldSide => heldLong ? 'long' : 'short';

  /// What is left of the position after a reduce.
  double get remaining => math.max(0, heldSize - orderSize);

  /// What a flip opens on the new side, past the position.
  double get remainder => math.max(0, orderSize - heldSize);

  /// The share of the position an exit closes: all of it for a close
  /// (the venue's exact size), the order's share for a reduce.
  double get closeFraction =>
      effect == HlPositionEffect.close || heldSize <= 0
          ? 1.0
          : (orderSize / heldSize).clamp(0.0, 1.0).toDouble();
}

/// The plan for an order of [orderSize] (floored, in coins) on the
/// [orderIsLong] side against [position]: open with none, add on the same
/// side, and on the other side a close when the order is within one size
/// step of the position, a reduce under it and a flip over it.
HlPositionPlan hlPositionPlan({
  required HlPerpPosition? position,
  required bool orderIsLong,
  required double orderSize,
  required int szDecimals,
}) {
  final pos = position;
  if (pos == null || pos.szi == 0) return const HlPositionPlan.open();
  final held = pos.szi.abs();
  if (pos.isLong == orderIsLong) {
    return HlPositionPlan(HlPositionEffect.add,
        position: pos, heldSize: held, orderSize: orderSize);
  }
  final step = math.pow(10, -szDecimals).toDouble();
  final HlPositionEffect effect;
  if (orderSize > 0 && (orderSize - held).abs() <= step + 1e-12) {
    effect = HlPositionEffect.close;
  } else if (orderSize < held) {
    effect = HlPositionEffect.reduce;
  } else {
    effect = HlPositionEffect.flip;
  }
  return HlPositionPlan(effect,
      position: pos, heldSize: held, orderSize: orderSize);
}

/// What a fill of [sizeFilled] did to the position [sent] was planned
/// against: the same plan, on the same side, sized on what actually filled
/// (an IOC can fill short of the order, so a planned close can be a reduce
/// and a planned flip a close). Null for an open or no plan.
HlPositionPlan? hlFilledPlan(
  HlPositionPlan? sent, {
  required double sizeFilled,
  required int szDecimals,
}) {
  if (sent == null || sent.position == null) return null;
  if (sent.effect == HlPositionEffect.open) return null;
  return hlPositionPlan(
    position: sent.position,
    orderIsLong:
        sent.effect == HlPositionEffect.add ? sent.heldLong : !sent.heldLong,
    orderSize: sizeFilled,
    szDecimals: szDecimals,
  );
}
