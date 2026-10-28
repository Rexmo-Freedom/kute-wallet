// lib/services/one_balance/funding_fees.dart
//
// What funding an order costs, leg by leg (founder, 27 October 2026:
// "Sometimes the fees have multiple steps — on deposit from Investing, and
// the auto deposits that have several swaps — we must show the fee
// correctly").
//
// A slip short of venue cash funds the order from Dollars first, then
// Bitcoin, then the other venue's cash ([planOrderSources], the order
// `decideOrderSources` and the funding runners use), every leg at once.
// Each leg has its own cost:
//
//   * Dollars → the venue: the Dollars route's own share (the venue
//     funder's live estimate, Kute's fee inside it), on what Dollars give;
//   * Bitcoin → the venue: the Bitcoin conversion's spread (Orchestra's
//     own estimate when read, Kute's fee inside it, else
//     [BitcoinLegRules.fallbackSpread]) on what that leg lands;
//   * the other venue → the venue (Investing → Predictions over HyperCore
//     and Circle CCTP, Predictions → Investing over Orchestra): what the
//     pull planner grosses the leg up by ([kVenuePullCost], the same
//     figure the one approval binds).
//
// The slip used to price the whole move as if it all left Dollars (the
// Dollars route's share on the full amount), so a bet funded from Bitcoin
// left out the conversion, one funded from Investing left out the
// HyperCore/CCTP cost and charged the Dollars share on money that never
// passed through Dollars. [estimateOrderFundingFees] adds every leg, in
// dollars, parallel legs included; the slips list each one in the fee
// sheet and add them to the one fee row. Pure; nothing is quoted or
// moved here.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegRules;
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashLastReadProvider, venueCashSeedProvider;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart'
    show planOrderSources;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashCandidate,
        VenuePullCost,
        kVenuePullCost,
        planDollarsShortfall,
        venueCashReachUsd;

/// Where a funding leg's money comes from.
enum FundingLegSource { dollars, bitcoin, predictions, investing }

/// One leg of an order's funding: [sentUsd] leaves [source], [feeUsd] of
/// it is the leg's cost (estimated), to the cent up, so the lines of the
/// fee sheet add up to its total.
@immutable
class FundingLegFee {
  const FundingLegFee(this.source,
      {required this.sentUsd, required this.feeUsd});

  final FundingLegSource source;
  final double sentUsd;
  final double feeUsd;

  @override
  bool operator ==(Object other) =>
      other is FundingLegFee &&
      other.source == source &&
      other.sentUsd == sentUsd &&
      other.feeUsd == feeUsd;

  @override
  int get hashCode => Object.hash(source, sentUsd, feeUsd);

  @override
  String toString() =>
      'FundingLegFee(${source.name}, sent: $sentUsd, fee: $feeUsd)';
}

/// Every leg of an order's funding and their fees together.
@immutable
class OrderFundingFees {
  const OrderFundingFees(this.legs);

  static const OrderFundingFees none = OrderFundingFees([]);

  final List<FundingLegFee> legs;

  bool get isEmpty => legs.isEmpty;

  /// Only Dollars move: the slip keeps its one "Move fee" detail.
  bool get dollarsOnly =>
      legs.length == 1 && legs.single.source == FundingLegSource.dollars;

  /// Every leg's fee added (each already to the cent up).
  double get totalUsd =>
      _ceilCents(legs.fold<double>(0, (sum, leg) => sum + leg.feeUsd));

  @override
  String toString() => 'OrderFundingFees($legs, total: $totalUsd)';
}

double _clean(double v) => v.isFinite && v > 0 ? v : 0;

/// The funding legs of an order as PostHog properties, for the slips'
/// submitted events (staged, so the placed / failed event carries them
/// too): `funding_fee_estimated_usd` (every leg's fee added; an estimate,
/// named as one), `funding_legs` (how many legs) and `funding_sources`
/// (the legs' sources in order, comma-joined fixed ids: `dollars`,
/// `bitcoin`, `predictions`, `investing`). Empty when nothing moves.
/// Never a balance. Pure.
Map<String, Object> fundingFeeAnalytics(OrderFundingFees? fees) {
  if (fees == null || fees.isEmpty) return const {};
  return {
    'funding_fee_estimated_usd': fees.totalUsd,
    'funding_legs': fees.legs.length,
    'funding_sources': fees.legs.map((l) => l.source.name).join(','),
  };
}

double _ceilCents(double usd) {
  if (!usd.isFinite || usd <= 0) return 0;
  return ((usd * 100) - 1e-6).ceil() / 100;
}

FundingLegSource _sourceOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => FundingLegSource.predictions,
      OneBalanceVenue.investing => FundingLegSource.investing,
    };

/// The fees of funding a move of [fundUsd] into [venue], leg by leg.
///
/// [fundUsd] and [arrivingUsd] are the slip's plan for the move as if it
/// all left Dollars (the venue funder's estimate: [fundUsd] leaves,
/// [arrivingUsd] lands); their ratio is the Dollars route's share.
/// [dollarsUsd] is what Dollars hold, [bitcoinMaxUsd] the most a Bitcoin
/// leg lands ([bitcoinMaxLandingUsd]) and [otherVenues] the venues' free
/// cash ([venueCashCandidatesNow]); [venue] itself is never a source.
/// [bitcoinSpread]: the conversion's share (Orchestra's estimate when
/// read). [pullCost] is the pull planner's allowance per venue.
///
/// The sources follow [planOrderSources] (Dollars, then Bitcoin, then the
/// other venue's cash for the rest). Where the sources cannot cover the
/// move ("Add $X"), the legs that can are still priced.
OrderFundingFees estimateOrderFundingFees({
  required double fundUsd,
  required double arrivingUsd,
  required double dollarsUsd,
  required OneBalanceVenue venue,
  double bitcoinMaxUsd = 0,
  double bitcoinSpread = BitcoinLegRules.fallbackSpread,
  List<VenueCashCandidate> otherVenues = const [],
  VenuePullCost Function(OneBalanceVenue venue)? pullCost,
}) {
  final fund = _clean(fundUsd);
  if (fund <= 0) return OrderFundingFees.none;
  final arriving = _clean(arrivingUsd);
  final routeShare =
      arriving <= 0 || arriving >= fund ? 0.0 : 1 - arriving / fund;
  final others = [
    for (final s in otherVenues)
      if (s.venue != venue) s,
  ];
  final cost = pullCost ??
      (OneBalanceVenue v) => kVenuePullCost[v] ?? (share: 0.02, fixedUsd: 0.30);
  final split = planOrderSources(
    fundUsd: fund,
    dollarsUsd: dollarsUsd,
    bitcoinMaxUsd: bitcoinMaxUsd,
    otherVenueUsd:
        venueCashReachUsd(dollarsUsd: 0, sources: others, costOf: cost),
    bitcoinMinimumUsd: BitcoinLegRules.routeMinimumUsd,
  );
  final legs = <FundingLegFee>[];
  if (split.dollarsUsd > 0) {
    final sent = split.dollarsUsd;
    // All of the move from Dollars: exactly the plan's own figure.
    final fee = sent + 1e-9 >= fund ? fund - arriving : sent * routeShare;
    legs.add(FundingLegFee(FundingLegSource.dollars,
        sentUsd: sent, feeUsd: _ceilCents(fee)));
  }
  if (split.bitcoinUsd > 0) {
    final spread =
        bitcoinSpread.isFinite && bitcoinSpread >= 0 && bitcoinSpread < 0.5
            ? bitcoinSpread
            : BitcoinLegRules.fallbackSpread;
    final lands = split.bitcoinUsd;
    final sent = lands / (1 - spread);
    legs.add(FundingLegFee(FundingLegSource.bitcoin,
        sentUsd: sent, feeUsd: _ceilCents(sent - lands)));
  }
  if (split.otherVenueUsd > 0) {
    final pulls = planDollarsShortfall(
      neededUsd: split.otherVenueUsd,
      dollarsUsd: 0,
      sources: others,
      costOf: cost,
    ).pulls;
    for (final p in pulls) {
      legs.add(FundingLegFee(_sourceOf(p.venue),
          sentUsd: p.usd, feeUsd: _ceilCents(p.usd - p.arrivingUsd)));
    }
  }
  return OrderFundingFees(List.unmodifiable(legs));
}

/// The Bitcoin conversion's share from Orchestra's estimate: [sats] at
/// [usdPerBtc] were worth that much, [estimatedOutUsd] lands. Null when
/// the figures cannot say (the fallback spread then stands).
double? bitcoinSpreadFrom(
    {required int sats,
    required double usdPerBtc,
    required double estimatedOutUsd}) {
  if (sats <= 0 || !usdPerBtc.isFinite || usdPerBtc <= 0) return null;
  final worth = sats / 1e8 * usdPerBtc;
  if (!estimatedOutUsd.isFinite || estimatedOutUsd <= 0 || worth <= 0) {
    return null;
  }
  final spread = 1 - estimatedOutUsd / worth;
  return spread.isFinite && spread >= 0 && spread < 0.5 ? spread : null;
}

/// The venues' free cash as the app last read it (the engine's last
/// read for the spending wallet, else the one-balance seed). Never reads
/// anything new.
List<VenueCashCandidate> venueCashCandidatesNow(
    T Function<T>(ProviderListenable<T> provider) read) {
  try {
    final walletId = pickSpendingWallet(read(settingsProvider))?.id;
    final last = read(venueCashLastReadProvider);
    if (last != null && last.walletId == walletId) return last.candidates;
    return read(venueCashSeedProvider);
  } catch (_) {
    return const [];
  }
}
