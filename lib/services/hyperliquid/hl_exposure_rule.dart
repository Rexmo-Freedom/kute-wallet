// lib/services/hyperliquid/hl_exposure_rule.dart
//
// LEVERAGE IS BLOCKED IN THIS APP. The app never writes more than 1x
// isolated, but an order on a market whose position is already held above
// 1x or in cross (opened elsewhere) trades at that position's own setting:
// an add, or the part of a flip past the position, would be new exposure
// margined at the venue's leverage, or backed by the whole account.
//
// So the one rule every order that can open or add perp exposure answers
// to, before anything is funded or signed:
//
// * spot, or an order sent reduce-only: never new exposure;
// * a perp whose position on that dex is not positively known (the account
//   not read yet, the read failed, a dex the account read does not cover):
//   refused, never treated as "no position";
// * no position, or one at 1x isolated: allowed;
// * a position above 1x or in cross: only an order on its closing side no
//   larger than the position, and that goes out reduce-only. An add or a
//   flip is refused.
//
// Close, reduce, protect, trailing stops and add margin are exits and never
// come here. The order slip shows the refusal inline (button disabled,
// before Face ID); the trading notifier, the queued-order auto-fire and the
// Ledger order path refuse with [HlExposureRefusedException] before any
// money moves or anything is signed.

import 'dart:math' as math;

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';

/// The position held on one market, as far as it is known.
class HlHeldPosition {
  const HlHeldPosition.unknown()
      : known = false,
        position = null;

  const HlHeldPosition.flat()
      : known = true,
        position = null;

  const HlHeldPosition.of(HlPerpPosition this.position) : known = true;

  /// The positions on [market]'s dex were read: whatever they hold.
  factory HlHeldPosition.fromPositions(
      HlMarket market, Iterable<HlPerpPosition> positions) {
    for (final p in positions) {
      // Positions carry the wire coin ('xyz:TSLA').
      if (p.coin == market.wireCoin && p.szi != 0) return HlHeldPosition.of(p);
    }
    return const HlHeldPosition.flat();
  }

  /// [snapshot] is the account as read (null: not read). It knows
  /// [market]'s position only when it read that market's dex
  /// ([HlAccountSnapshot.positionDexes]).
  factory HlHeldPosition.fromSnapshot(
      HlMarket market, HlAccountSnapshot? snapshot) {
    if (market.isSpot) return const HlHeldPosition.flat();
    if (snapshot == null || !snapshot.positionDexes.contains(market.dex)) {
      return const HlHeldPosition.unknown();
    }
    return HlHeldPosition.fromPositions(market, snapshot.positions);
  }

  final bool known;

  /// The open position (non-zero size), or null when flat or unknown.
  final HlPerpPosition? position;

  /// The positions to pass to the leverage write: none when flat.
  List<HlPerpPosition> get positions => [if (position != null) position!];
}

/// A position the app would not have opened: above 1x, or cross margin.
bool hlPositionIsLeveraged(HlPerpPosition p) =>
    p.isCross || p.leverageValue > 1;

enum HlExposureVerdict {
  /// Goes out as asked.
  allowed,

  /// Allowed only reduce-only on the wire (it cannot add exposure).
  reduceOnly,

  /// Not sent.
  refused,
}

enum HlExposureRefusal {
  /// The position on this market could not be read.
  positionUnknown,

  /// The position uses leverage or cross margin, and the order would add
  /// to it or flip it.
  leveragedPosition,
}

class HlExposureCheck {
  const HlExposureCheck._(this.verdict, {this.refusal, this.position});

  const HlExposureCheck.allowed({HlPerpPosition? position})
      : this._(HlExposureVerdict.allowed, position: position);

  const HlExposureCheck.reduceOnly(HlPerpPosition? position)
      : this._(HlExposureVerdict.reduceOnly, position: position);

  const HlExposureCheck.refused(HlExposureRefusal refusal,
      {HlPerpPosition? position})
      : this._(HlExposureVerdict.refused,
            refusal: refusal, position: position);

  final HlExposureVerdict verdict;
  final HlExposureRefusal? refusal;

  /// The position the order was judged against, when one is held.
  final HlPerpPosition? position;

  bool get isRefused => verdict == HlExposureVerdict.refused;
  bool get mustReduceOnly => verdict == HlExposureVerdict.reduceOnly;

  /// Whether an order sent with [sentReduceOnly] passes: an order the rule
  /// allows only reduce-only and that is not sent so does not.
  bool allows({required bool sentReduceOnly}) =>
      verdict == HlExposureVerdict.allowed ||
      (verdict == HlExposureVerdict.reduceOnly && sentReduceOnly);

  /// The refusal for an order sent with [sentReduceOnly], or null when it
  /// passes.
  HlExposureRefusal? refusalFor({required bool sentReduceOnly}) {
    if (allows(sentReduceOnly: sentReduceOnly)) return null;
    return refusal ?? HlExposureRefusal.leveragedPosition;
  }

  /// Throws [HlExposureRefusedException] unless an order sent with
  /// [sentReduceOnly] passes.
  void ensureAllows({required bool sentReduceOnly}) {
    final r = refusalFor(sentReduceOnly: sentReduceOnly);
    if (r != null) throw HlExposureRefusedException(r);
  }
}

/// THE rule (see the header): an order of [size] coins on the [isBuy] side
/// of [market], against what is [held] there. [reduceOnly] is an order the
/// caller already sends reduce-only.
HlExposureCheck hlExposureCheck({
  required HlMarket market,
  required HlHeldPosition held,
  required bool isBuy,
  required double size,
  bool reduceOnly = false,
}) {
  if (market.isSpot) return const HlExposureCheck.allowed();
  if (reduceOnly) return HlExposureCheck.reduceOnly(held.position);
  if (!held.known) {
    return const HlExposureCheck.refused(HlExposureRefusal.positionUnknown);
  }
  final pos = held.position;
  if (pos == null || pos.szi == 0) return const HlExposureCheck.allowed();
  if (!hlPositionIsLeveraged(pos)) return HlExposureCheck.allowed(position: pos);
  if (pos.isLong == isBuy) {
    return HlExposureCheck.refused(HlExposureRefusal.leveragedPosition,
        position: pos);
  }
  // On the closing side: up to the position (one size step of rounding
  // either way is still the close the slip names), never past it.
  final step = math.pow(10, -market.szDecimals).toDouble();
  if (size > 0 && size <= pos.szi.abs() + step + 1e-12) {
    return HlExposureCheck.reduceOnly(pos);
  }
  return HlExposureCheck.refused(HlExposureRefusal.leveragedPosition,
      position: pos);
}

/// An order refused by [hlExposureCheck], before anything was funded or
/// signed.
class HlExposureRefusedException implements Exception {
  const HlExposureRefusedException(this.refusal);
  final HlExposureRefusal refusal;

  String messageIn(AppLocalizations l10n) => hlExposureRefusalText(l10n, refusal);

  @override
  String toString() => switch (refusal) {
        HlExposureRefusal.positionUnknown =>
          'Could not read the position on this market',
        HlExposureRefusal.leveragedPosition =>
          'This position uses leverage: it can only be reduced or closed',
      };
}

/// The inline sentence for [refusal].
String hlExposureRefusalText(AppLocalizations l10n, HlExposureRefusal refusal) =>
    switch (refusal) {
      HlExposureRefusal.positionUnknown => l10n.hlExpoPositionUnknown,
      HlExposureRefusal.leveragedPosition => l10n.hlExpoLeveragedPosition,
    };
