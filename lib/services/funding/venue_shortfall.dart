// lib/services/funding/venue_shortfall.dart
//
// Top up from the slip (founder decision, October 2026). Pure: no Flutter,
// no Riverpod, no network.
//
// A Predictions bet or an Investing order on the spending wallet that needs
// more venue cash than is ready keeps its "Deposit to …" button. The tap
// opens the Move sheet to that venue prefilled with the order's own amount
// (the figure the person typed, never a fraction of it), on the one
// spending source that covers it alone:
//
//   1. Dollars, when Dollars alone cover the top-up;
//   2. otherwise spending Bitcoin, when Bitcoin alone covers it;
//   3. otherwise the Move sheet's own default source.
//
// The person confirms the deposit in the Move sheet as usual, comes back to
// the same slip and places the order themselves. While that deposit is on
// its way the slip says so instead of offering a second one
// ([fundingState]). Nothing here moves money.

import 'dart:math' as math;

/// The spending balance a slip top-up opens on.
enum ShortfallSource {
  dollars('dollars'),
  bitcoin('bitcoin');

  const ShortfallSource(this.code);

  /// Analytics value (`suggested_source`).
  final String code;
}

/// What a short slip's button is while it is short of venue cash.
enum SlipFundingState {
  /// Nothing on its way: "Deposit to predict" / "Deposit to invest".
  deposit,

  /// A deposit on its way covers the shortfall: "Deposit incoming".
  incoming,

  /// A deposit is on its way but falls short: "Deposit incoming" plus a
  /// small "Add more" for the rest.
  incomingShort,
}

/// The slip's prefill and why (analytics `prefill_rule`).
typedef SlipTopUp = ({double usd, String rule});

abstract final class ShortfallRules {
  /// The Move sheet's smallest dollar move.
  static const double minTopUpUsd = 1.0;

  /// `prefill_rule` values.
  static const String ruleOrderAmount = 'order_amount';
  static const String ruleOrderPlusFee = 'order_plus_fee';
  static const String ruleRemaining = 'remaining';

  /// Below this, a pending figure is dust and not "a deposit on its way".
  static const double _dustUsd = 0.01;

  /// Venue cash the order needs beyond what is ready, rounded up to the
  /// cent. Zero when the ready cash covers it.
  static double shortfallUsd({
    required double requiredUsd,
    required double readyUsd,
  }) {
    if (!requiredUsd.isFinite || requiredUsd <= 0) return 0;
    final ready = readyUsd.isFinite && readyUsd > 0 ? readyUsd : 0.0;
    final gap = requiredUsd - ready;
    if (gap <= 1e-6) return 0;
    return _ceilCents(gap);
  }

  /// The share of a deposit the route is assumed to keep while no
  /// estimate for it could be read. Observed combined fees run near 1%;
  /// the quote guard refuses anything over 4%.
  static const double fallbackRouteFee = 0.02;

  /// Above this, a route fee figure is not believed (a decimals slip in an
  /// estimate) and [fallbackRouteFee] is used instead.
  static const double _maxRouteFee = 0.04;

  /// The share of [sentUsd] the deposit route keeps, from an estimate that
  /// lands [arrivingUsd] for it. Null when the figures are not usable.
  static double? routeFeeFrom({
    required double sentUsd,
    required double arrivingUsd,
  }) {
    if (!sentUsd.isFinite || sentUsd <= 0) return null;
    if (!arrivingUsd.isFinite || arrivingUsd <= 0) return null;
    final fee = 1 - arrivingUsd / sentUsd;
    if (fee < 0) return 0;
    return fee > _maxRouteFee ? null : fee;
  }

  static double _routeFee(double routeFee) =>
      routeFee.isFinite && routeFee > 0 && routeFee <= _maxRouteFee
          ? routeFee
          : (routeFee.isFinite && routeFee <= 0 ? 0 : fallbackRouteFee);

  /// The most a deposit quote can charge in all (provider plus Kute), in
  /// basis points: the quote guard refuses anything above it.
  static const int _maxFeeBps = 400;

  /// The share of a deposit that arrives: the route keeps [routeFee] of
  /// what is sent, then Kute's app fee ([kuteFeeBps], the rate the
  /// deposit's estimate reports in `X-Kute-App-Fee-Bps`, referral discount
  /// already off) is taken from what remains, the way the provider applies
  /// both. A Kute rate above what a quote can carry is counted at that
  /// ceiling rather than believed.
  static double _keep(double routeFee, int kuteFeeBps) {
    final kute = kuteFeeBps.clamp(0, _maxFeeBps) / 10000;
    return (1 - _routeFee(routeFee)) * (1 - kute);
  }

  /// What the Move sheet is prefilled with: the order's own amount
  /// ([orderUsd], what the person typed), up to the cent, when the ready
  /// cash plus what ARRIVES from that amount ([routeFee], the share the
  /// deposit route keeps, is taken off it) covers [requiredUsd], the order
  /// with the slip's own fee estimate. Otherwise the typed amount plus
  /// exactly what is missing, grossed up by the route fee and the Kute fee
  /// ([kuteFeeBps]) so the extra arrives too, rounded up to the cent (the
  /// Move sheet's dollar unit, coarser than any source's base unit): one
  /// deposit always covers the order. Never under the Move minimum, no
  /// other headroom.
  ///
  /// Balance $3, order $5: $5. Balance $0, order $5 with a $0.08 slip fee
  /// on a route keeping 0.6%: $5.12, of which about $5.09 arrives. Balance
  /// $0, order $20 at 50 bps of Kute fee: $20.11, of which $20.00 arrives.
  static SlipTopUp topUp({
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    double routeFee = 0,
    int kuteFeeBps = 0,
  }) {
    if (!orderUsd.isFinite || orderUsd <= 0) {
      return (usd: 0, rule: ruleOrderAmount);
    }
    final ready = readyUsd.isFinite && readyUsd > 0 ? readyUsd : 0.0;
    final needed =
        requiredUsd.isFinite && requiredUsd > orderUsd ? requiredUsd : orderUsd;
    final keep = _keep(routeFee, kuteFeeBps);
    final arriving = orderUsd * keep;
    if (ready + arriving + 1e-6 >= needed) {
      return (
        usd: math.max(minTopUpUsd, _ceilCents(orderUsd)),
        rule: ruleOrderAmount
      );
    }
    final missing = needed - ready - arriving;
    return (
      usd: math.max(minTopUpUsd, _ceilCents(orderUsd + missing / keep)),
      rule: ruleOrderPlusFee
    );
  }

  /// [topUp]'s amount alone.
  static double topUpUsd({
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    double routeFee = 0,
    int kuteFeeBps = 0,
  }) =>
      topUp(
              orderUsd: orderUsd,
              requiredUsd: requiredUsd,
              readyUsd: readyUsd,
              routeFee: routeFee,
              kuteFeeBps: kuteFeeBps)
          .usd;

  /// What "Add more" prefills while [incomingUsd] is on its way and falls
  /// short of [shortfallUsd]: the rest, grossed up by [routeFee] and the
  /// Kute fee ([kuteFeeBps]) so it arrives whole, up to the cent, never
  /// under the Move minimum. Zero when the incoming deposit covers it.
  static double remainingTopUpUsd({
    required double shortfallUsd,
    required double incomingUsd,
    double routeFee = 0,
    int kuteFeeBps = 0,
  }) {
    if (!shortfallUsd.isFinite || shortfallUsd <= 0) return 0;
    final incoming = incomingUsd.isFinite && incomingUsd > 0 ? incomingUsd : 0;
    final rest = shortfallUsd - incoming;
    if (rest <= 1e-6) return 0;
    return math.max(
        minTopUpUsd, _ceilCents(rest / _keep(routeFee, kuteFeeBps)));
  }

  /// The short slip's button. [incomingUsd] is the venue deposit already on
  /// its way for this wallet; [shortfallUsd] what the order still needs
  /// (zero with nothing typed, where any deposit on its way covers it).
  static SlipFundingState fundingState({
    required double shortfallUsd,
    required double incomingUsd,
  }) {
    if (!incomingUsd.isFinite || incomingUsd < _dustUsd) {
      return SlipFundingState.deposit;
    }
    final short = shortfallUsd.isFinite && shortfallUsd > 0 ? shortfallUsd : 0;
    return incomingUsd + 1e-6 >= short
        ? SlipFundingState.incoming
        : SlipFundingState.incomingShort;
  }

  /// The one source that covers [topUpUsd] on its own, or null for the
  /// Move sheet's default. Dollars come first. Never a split.
  static ShortfallSource? chooseSource({
    required double topUpUsd,
    required double dollarsUsd,
    required double bitcoinUsd,
  }) {
    if (!topUpUsd.isFinite || topUpUsd <= 0) return null;
    if (dollarsUsd.isFinite && dollarsUsd + 1e-9 >= topUpUsd) {
      return ShortfallSource.dollars;
    }
    if (bitcoinUsd.isFinite && bitcoinUsd + 1e-9 >= topUpUsd) {
      return ShortfallSource.bitcoin;
    }
    return null;
  }

  /// The venue cash an Investing order takes: the margin with its price
  /// headroom, plus taker and builder fees on the notional (the inverse of
  /// `hypercoreMaxOrderUsd`, matching `_fundPerpAction`).
  static double hyperliquidRequiredUsd({
    required double marginUsd,
    int leverage = 1,
    double slippagePct = 0,
    double feeCeiling = 0.0019,
  }) {
    if (!marginUsd.isFinite || marginUsd <= 0) return 0;
    final slip =
        1 + (slippagePct.isFinite && slippagePct > 0 ? slippagePct : 0) / 100;
    final lev = leverage < 1 ? 1 : leverage;
    return marginUsd * slip * (1 + lev * feeCeiling);
  }

  static double _ceilCents(double usd) =>
      ((usd * 100) - 1e-9).ceilToDouble() / 100;
}
