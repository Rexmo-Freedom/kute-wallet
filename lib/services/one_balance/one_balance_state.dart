// lib/services/one_balance/one_balance_state.dart
//
// The one-balance model: everything the user owns in dollars, split only
// by where it is right now. "Dollars" is the spending account (spendable
// at once), "invested" is money sitting in a venue, "in flight" is money
// on a rail between the two, and "waiting" is venue cash the sweeper has
// not brought home yet. The four add up to the total; nothing is counted
// twice because each dollar is in exactly one of them.
//
// Pure value types, no Riverpod: the provider that fills them lives in
// `lib/providers/one_balance_provider.dart`.

import 'package:kute/services/one_balance/money_steps.dart' show MoneyStep;
import 'package:flutter/foundation.dart' show immutable, listEquals, mapEquals;

/// Where invested money can live. The spending account is not a venue:
/// it is the "dollars" side every move starts from or comes back to.
enum OneBalanceVenue { predictions, investing }

/// The venue's name in analytics: the same `venue` values the venue
/// deposit, withdraw and order-funding events already carry.
extension OneBalanceVenueAnalytics on OneBalanceVenue {
  String get analyticsName => switch (this) {
        OneBalanceVenue.predictions => 'polymarket',
        OneBalanceVenue.investing => 'hyperliquid',
      };
}

/// What a dollar in flight is doing.
enum InFlightKind {
  /// Leaving Dollars for a venue (an order being funded, a top-up).
  toVenue,

  /// Leaving a venue for Dollars (a sweep, a withdrawal).
  fromVenue,

  /// Arriving in Dollars from outside the wallet (a receive still
  /// confirming). No venue.
  incomingDollars,
}

/// The order a sum on a rail is for: what the person is doing, in the
/// words the header shows ("Placing $5 on Yes · Lakers", "Opening $5 NVDA
/// order", "Adding $5 margin to BTC"), from the funded-order record that
/// owns the rail's row.
@immutable
class InFlightOrder {
  const InFlightOrder({
    required this.id,
    required this.venue,
    required this.orderUsd,
    required this.side,
    required this.market,
    this.margin = false,
    this.transfer = false,
    this.legs = const [],
  });

  /// The funded order's local id (one line per order).
  final String id;
  final OneBalanceVenue venue;

  /// The bet's stake or the order's margin.
  final double orderUsd;

  /// "Yes", "Long", ...
  final String side;

  /// A short name of the market.
  final String market;

  /// Margin added to an isolated Investing position ([orderUsd] is the
  /// margin), not an order.
  final bool margin;

  /// Cash being transferred into the venue, with no approved order.
  final bool transfer;

  /// The order's legs from its step graph (`FundedOrderRecord.steps`),
  /// each with its own state: the header names each source under the
  /// order while the slip is closed. Empty for a record without a graph.
  final List<MoneyStep> legs;

  String get _legsKey =>
      [for (final l in legs) '${l.id}:${l.status.name}:${l.usd}'].join('|');

  @override
  bool operator ==(Object other) =>
      other is InFlightOrder &&
      other.id == id &&
      other.venue == venue &&
      other.orderUsd == orderUsd &&
      other.side == side &&
      other.market == market &&
      other.margin == margin &&
      other.transfer == transfer &&
      other._legsKey == _legsKey;

  @override
  int get hashCode => Object.hash(
      id, venue, orderUsd, side, market, margin, transfer, _legsKey);
}

/// One sum of money on a rail. Rows with the same kind and venue are not
/// merged here; the provider decides how coarse the list is.
@immutable
class InFlightMove {
  const InFlightMove({
    required this.kind,
    required this.usd,
    this.venue,
    this.order,
  }) : assert(kind == InFlightKind.incomingDollars || venue != null,
            'a venue move needs a venue');

  final InFlightKind kind;

  /// Null only for [InFlightKind.incomingDollars].
  final OneBalanceVenue? venue;

  final double usd;

  /// The order this money is for (an order funded from Dollars, or from
  /// Bitcoin through Dollars), when one is: the header names the order,
  /// not the rail. Null for money on a rail for no order.
  final InFlightOrder? order;

  /// Whether the header gives this move a line of its own: the order it
  /// funds, or dollars arriving from outside. Money moving between the
  /// person's own accounts for no order (a sweep home, a move with no
  /// order) leaves the total unchanged and is plumbing: no line.
  bool get hasLine => order != null || kind == InFlightKind.incomingDollars;

  InFlightMove copyWith({
    InFlightKind? kind,
    OneBalanceVenue? venue,
    double? usd,
    InFlightOrder? order,
  }) =>
      InFlightMove(
        kind: kind ?? this.kind,
        venue: venue ?? this.venue,
        usd: usd ?? this.usd,
        order: order ?? this.order,
      );

  @override
  bool operator ==(Object other) =>
      other is InFlightMove &&
      other.kind == kind &&
      other.venue == venue &&
      other.usd == usd &&
      other.order == order;

  @override
  int get hashCode => Object.hash(kind, venue, usd, order);

  @override
  String toString() => 'InFlightMove(${kind.name}, ${venue?.name}, $usd'
      '${order == null ? '' : ', order'})';
}

/// The whole picture at one instant.
///
/// [investingKnown] and [predictionsKnown] say whether the venue read
/// behind [investedUsd] has answered; while a venue is unknown its share
/// is counted as zero rather than hiding the total, and the UI decides
/// whether to say so.
@immutable
class OneBalanceState {
  const OneBalanceState({
    this.dollarsUsd = 0,
    this.dollarsKnown = true,
    this.investedUsd = 0,
    this.inFlight = const <InFlightMove>[],
    this.waiting = const <OneBalanceVenue, double>{},
    this.investingKnown = false,
    this.predictionsKnown = false,
    this.venueCash = const <OneBalanceVenue, double>{},
    this.investedByVenue = const <OneBalanceVenue, double>{},
  });

  /// [investedUsd] venue by venue (the Portfolio's tiles: what each venue
  /// holds in positions, open orders' reserved cash included). Adds up to
  /// [investedUsd]; empty in states built without it.
  final Map<OneBalanceVenue, double> investedByVenue;

  /// Unreserved cash at a venue that the sweeper is not moving, by venue:
  /// cash a venue keeps by design (Investing until it sits idle, a venue
  /// in use) and dust below every route minimum. Part of [availableUsd],
  /// since an order or a bet there, a send or the other venue draws on it
  /// when Dollars fall short. Never waiting, never moving, never invested.
  final Map<OneBalanceVenue, double> venueCash;

  /// Total of [venueCash].
  double get venueCashUsd {
    var sum = 0.0;
    for (final usd in venueCash.values) {
      if (usd.isFinite && usd > 0) sum += usd;
    }
    return sum;
  }

  /// Spendable now, on the spending account.
  final double dollarsUsd;

  /// Display freshness only; never authorizes a payment or replaces a reading.
  final bool dollarsKnown;

  /// Held by the venues: positions, equity, cash reserved for open orders
  /// and fills the positions read has not listed yet, across every venue
  /// that has answered. Never idle cash, dust included: that is
  /// [venueCash].
  final double investedUsd;

  /// Money on a rail, in either direction.
  final List<InFlightMove> inFlight;

  /// Venue cash the sweeper owes back to Dollars, by venue. Never dust:
  /// cash below the route minimum is [venueCash] (Available) instead.
  final Map<OneBalanceVenue, double> waiting;

  final bool investingKnown;
  final bool predictionsKnown;

  /// Everything, wherever it is.
  double get totalUsd {
    var total = dollarsUsd + investedUsd;
    for (final move in inFlight) {
      total += move.usd;
    }
    for (final usd in waiting.values) {
      total += usd;
    }
    return total + venueCashUsd;
  }

  /// What a new order can draw on: the spending account plus the cash
  /// the venues keep ([venueCash]).
  double get availableUsd => dollarsUsd + venueCashUsd;

  /// What the header's in-flight lines carry
  /// (`InvestmentBalanceHeader.inFlightLines`): the moves that have a line
  /// ([InFlightMove.hasLine]) and what the sweeper still owes back. Money
  /// moving between the person's own accounts for no order has no line:
  /// it stays in Available ([oneBalanceSplit]).
  double get onLinesUsd {
    var sum = 0.0;
    for (final move in inFlight) {
      if (move.hasLine && move.usd.isFinite && move.usd > 0) sum += move.usd;
    }
    for (final usd in waiting.values) {
      if (usd.isFinite && usd > 0) sum += usd;
    }
    return sum;
  }

  /// Total of the in-flight rows, all kinds.
  double get inFlightUsd {
    var sum = 0.0;
    for (final move in inFlight) {
      sum += move.usd;
    }
    return sum;
  }

  /// Total owed back by the venues.
  double get waitingUsd {
    var sum = 0.0;
    for (final usd in waiting.values) {
      sum += usd;
    }
    return sum;
  }

  OneBalanceState copyWith({
    double? dollarsUsd,
    double? investedUsd,
    List<InFlightMove>? inFlight,
    Map<OneBalanceVenue, double>? waiting,
    bool? dollarsKnown,
    bool? investingKnown,
    bool? predictionsKnown,
    Map<OneBalanceVenue, double>? venueCash,
    Map<OneBalanceVenue, double>? investedByVenue,
  }) =>
      OneBalanceState(
        venueCash: venueCash ?? this.venueCash,
        investedByVenue: investedByVenue ?? this.investedByVenue,
        dollarsUsd: dollarsUsd ?? this.dollarsUsd,
        dollarsKnown: dollarsKnown ?? this.dollarsKnown,
        investedUsd: investedUsd ?? this.investedUsd,
        inFlight: inFlight ?? this.inFlight,
        waiting: waiting ?? this.waiting,
        investingKnown: investingKnown ?? this.investingKnown,
        predictionsKnown: predictionsKnown ?? this.predictionsKnown,
      );

  @override
  bool operator ==(Object other) =>
      other is OneBalanceState &&
      other.dollarsUsd == dollarsUsd &&
      other.dollarsKnown == dollarsKnown &&
      other.investedUsd == investedUsd &&
      listEquals(other.inFlight, inFlight) &&
      mapEquals(other.waiting, waiting) &&
      mapEquals(other.venueCash, venueCash) &&
      mapEquals(other.investedByVenue, investedByVenue) &&
      other.investingKnown == investingKnown &&
      other.predictionsKnown == predictionsKnown;

  @override
  int get hashCode => Object.hash(
        dollarsUsd,
        dollarsKnown,
        investedUsd,
        Object.hashAll(inFlight),
        Object.hashAll(waiting.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            venueCash.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            investedByVenue.entries.map((e) => Object.hash(e.key, e.value))),
        investingKnown,
        predictionsKnown,
      );

  @override
  String toString() => 'OneBalanceState(dollars: $dollarsUsd, '
      'invested: $investedUsd, inFlight: $inFlight, waiting: $waiting, '
      'venueCash: $venueCash, investedByVenue: $investedByVenue, '
      'investingKnown: $investingKnown, predictionsKnown: $predictionsKnown)';
}

/// The Dollars hero's "Invested $X · Available $Y" for a [total] the hero
/// prints (founder, 4 November 2026: "it should show invested and
/// available in a good way at the bottom"), so that what the line says
/// ADDS UP to the figure over it, to the cent, in the currency on screen:
///
///   Invested  = the venues' positions and reserved order cash
///               ([OneBalanceState.investedUsd]);
///   Available = the rest of the total, less [onLinesUsd] (the money the
///               in-flight lines under it name, [OneBalanceState.onLinesUsd]):
///               Dollars, the cash the venues keep, and money moving
///               between the person's own accounts for no order.
///
/// So Invested + Available + the lines' money is the total, always: no
/// second definition of Available to drift from the figure (the old
/// "Available" summed Dollars and venue cash on its own and missed a sweep
/// on its way home).
///
/// Each figure is rounded to the cent in the currency on screen ([rate]
/// from US dollars, 1 for USD) and Available is what is left of the
/// total's cents, so the two printed amounts never disagree with the
/// printed total by a rounding cent. Returned in US dollars, for the
/// formatter. Pure for the tests.
({double investedUsd, double availableUsd}) oneBalanceSplit({
  required double totalUsd,
  required double investedUsd,
  double onLinesUsd = 0,
  double rate = 1,
}) {
  double clean(double v) => v.isFinite && v > 0 ? v : 0;
  final r = rate.isFinite && rate > 0 ? rate : 1.0;
  int cents(double usd) => (clean(usd) * r * 100).round();
  final total = cents(totalUsd);
  final invested = cents(investedUsd).clamp(0, total);
  final lines = cents(onLinesUsd).clamp(0, total - invested);
  final available = total - invested - lines;
  return (
    investedUsd: invested / 100 / r,
    availableUsd: available / 100 / r,
  );
}
