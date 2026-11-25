// lib/screens/shared/activity_curation.dart
//
// What the Bitcoin home's Activity shows, and how "See all" folds money
// moving between the person's own accounts (founder, 1 November 2026:
// the home shows a curated slice, the rest is behind See all):
//
//   * PLUMBING is money moving between the person's own accounts: Bitcoin
//     to Dollars and back, Dollars or Bitcoin into Predictions or
//     Investing and out again, a venue's own deposit and withdrawal
//     records, a multi-source move that is not a send, a sweep home.
//     ([activityPlumbingLeg]). The home never lists it.
//   * ACTIONS are everything else: sends, receives, bets placed, sold,
//     won or lost, Investing opens, closes and reductions, share links
//     sent and claimed (they are sends and receives).
//   * A funding chain that paid for an action folds INTO the action's row
//     ([curateAllActivity]): Bitcoin → Dollars → Predictions to place a
//     bet is the one "Prediction · No" row, its context line led by a
//     quiet "Paid from Bitcoin". Only legs that end where the action spent
//     (a bet: Predictions; an Investing open: Investing), in the half hour
//     before it, fold; a hop through Dollars folds only when its dollar
//     figures agree with the next leg's. What does not fold stays a row of
//     its own in See all.
//   * The home: the newest [kHomeActivityRows] actions
//     ([homeActivityEntries]): the first [kHomeActivityLatest] as square
//     tiles ("Latest"), the rest as plain rows ("Earlier"). No Today card
//     (founder, 1 November 2026: less clutter).

import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/polymarket_model.dart' show ActivityType;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/all_activity.dart' show AllActivityEntry;
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show MultiSourceMoveTransaction;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
import 'package:kute/services/orchestra_routes.dart'
    show isOrchestraUsdLikeCoin;

/// Actions the Bitcoin home's Activity shows before "See all".
const int kHomeActivityRows = 6;

/// Of those, the newest this many are the "Latest" squares, two by two;
/// the rest are the "Earlier" rows.
const int kHomeActivityLatest = 4;

/// How long before an action a funding leg may have left to fold into it.
const Duration kActivityFundingWindow = Duration(minutes: 30);

/// How long after an action its funding leg may be stamped (the venue's
/// own deposit record lands a moment after the order went).
const Duration kActivityFundingLag = Duration(minutes: 2);

/// One of the person's own accounts.
enum ActivityAccount { bitcoin, dollars, investing, predictions }

/// Where a plumbing row moved money: from which of the person's accounts
/// (more than one for a multi-source move; empty when the record does not
/// say), to which, and its dollar figures where it has them.
typedef ActivityLeg = ({
  List<ActivityAccount> froms,
  ActivityAccount? to,
  double? usdIn,
  double? usdOut,
});

/// A stable key for [e], to look up what [curateAllActivity] says of it.
String activityEntryKey(AllActivityEntry e) {
  final tx = e.tx;
  if (tx != null) return 'tx:${tx.runtimeType}:${tx.id}';
  final f = e.fill!;
  return 'fill:${f.hash}:${f.oid}:${f.time}:${f.sz}:${f.tradeId ?? ''}';
}

/// The account a coin on a network sits in, when it is one of the
/// person's own: bitcoin anywhere is Bitcoin, dollars on Spark are
/// Dollars, Polygon is Predictions, HyperCore Investing.
ActivityAccount? _accountOf(String coin, String network) {
  final c = coin.trim().toUpperCase();
  final n = network.trim().toUpperCase();
  if (swapAssetIsBitcoin(c)) return ActivityAccount.bitcoin;
  if (n == 'POLYGON') return ActivityAccount.predictions;
  if (n.startsWith('HYPER')) return ActivityAccount.investing;
  if (n == 'SPARK' && isOrchestraUsdLikeCoin(c)) return ActivityAccount.dollars;
  return null;
}

ActivityAccount _venueAccount(OneBalanceVenue v) => switch (v) {
      OneBalanceVenue.predictions => ActivityAccount.predictions,
      OneBalanceVenue.investing => ActivityAccount.investing,
    };

/// An Orchestra dollar figure: six-decimal base units or plain dollars
/// (the same reading the activity rows make).
double? _usd(String field) {
  final raw = double.tryParse(field) ?? 0;
  if (!raw.isFinite || raw <= 0) return null;
  return (raw >= 10000 && raw == raw.roundToDouble()) ? raw / 1e6 : raw;
}

bool _dollarCoin(String coin) =>
    isOrchestraUsdLikeCoin(coin.trim()) || coin.trim().toUpperCase() == 'PUSD';

ActivityType? _polyType(PolymarketTransaction tx) {
  try {
    return tx.activityType;
  } catch (_) {
    return null;
  }
}

/// The leg [e] is when it is plumbing (see the file header), else null.
ActivityLeg? activityPlumbingLeg(
  AllActivityEntry e, {
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  final tx = e.tx;
  if (tx == null) return null;
  if (tx is SwapOrderTransaction) {
    final d = tx.details;
    if (d.isCashAppPurchase) return null;
    final kind = classify(d);
    if (kind.isExternal || kind == SwapActivityKind.purchase) return null;
    var from = _accountOf(d.coinFrom, d.networkFrom);
    var to = _accountOf(d.coinTo, d.networkTo);
    switch (kind) {
      case SwapActivityKind.predictionsDeposit:
        to = ActivityAccount.predictions;
      case SwapActivityKind.predictionsWithdrawal:
        from = ActivityAccount.predictions;
      case SwapActivityKind.investingDeposit:
        to = ActivityAccount.investing;
      case SwapActivityKind.investingWithdrawal:
        from = ActivityAccount.investing;
      case SwapActivityKind.dollarDeposit:
        to = ActivityAccount.dollars;
        from ??= ActivityAccount.bitcoin;
      case SwapActivityKind.dollarWithdrawal:
        from = ActivityAccount.dollars;
        to ??= ActivityAccount.bitcoin;
      default:
        break;
    }
    return (
      froms: [if (from != null && from != to) from],
      to: to,
      usdIn: _dollarCoin(d.coinFrom) ? _usd(d.depositAmount) : null,
      usdOut: _dollarCoin(d.coinTo) ? _usd(d.withdrawalAmount) : null,
    );
  }
  if (tx is PolymarketTransaction) {
    if (tx.result != null) return null;
    return switch (_polyType(tx)) {
      ActivityType.deposit => (
          froms: const <ActivityAccount>[],
          to: ActivityAccount.predictions,
          usdIn: tx.usdcAmount,
          usdOut: tx.usdcAmount,
        ),
      ActivityType.withdraw => (
          froms: const [ActivityAccount.predictions],
          to: null,
          usdIn: tx.usdcAmount,
          usdOut: tx.usdcAmount,
        ),
      _ => null,
    };
  }
  if (tx is MultiSourceMoveTransaction) {
    final m = tx.move;
    if (m.forAction == VenueCashFor.send) return null;
    final to = switch (m.destination) {
      VenueCashDestination.dollars => ActivityAccount.dollars,
      VenueCashDestination.bitcoin => ActivityAccount.bitcoin,
      VenueCashDestination.predictions => ActivityAccount.predictions,
      VenueCashDestination.investing => ActivityAccount.investing,
    };
    final froms = <ActivityAccount>[
      if (m.dollarsUsd > 0 && to != ActivityAccount.dollars)
        ActivityAccount.dollars,
    ];
    for (final leg in m.okLegs) {
      final a = _venueAccount(leg.venue);
      if (a != to && !froms.contains(a)) froms.add(a);
    }
    return (
      froms: froms,
      to: to,
      usdIn: m.totalUsd > 0 ? m.totalUsd : null,
      usdOut: m.deliveredUsd > 0 ? m.deliveredUsd : null,
    );
  }
  return null;
}

/// The account an action spent from, when funding legs can fold into it:
/// a prediction placed spends Predictions; an Investing open or a spot
/// buy spends Investing. Sales, closes, payouts and the wallet's own
/// sends and receives fold nothing.
ActivityAccount? _spendsFrom(AllActivityEntry e) {
  final fill = e.fill;
  if (fill != null) {
    final dir = fill.dir.trim();
    return dir.startsWith('Open') || dir == 'Buy'
        ? ActivityAccount.investing
        : null;
  }
  final tx = e.tx;
  if (tx is PolymarketTransaction &&
      tx.result == null &&
      _polyType(tx) == ActivityType.trade &&
      (tx.activity.side ?? '').toUpperCase() != 'SELL') {
    return ActivityAccount.predictions;
  }
  return null;
}

/// A hop through an intermediate account folds only when what reached it
/// ([upstream]) roughly matches what left it for the action ([downstream]).
bool _hopMatches(double upstream, double downstream) =>
    upstream >= downstream * 0.75 - 1 && upstream <= downstream * 1.25 + 1;

/// The Activity after folding: [entries] newest first with every folded
/// funding leg gone (what See all lists), and for each action that took
/// legs, where its money came from ([paidFrom], by [activityEntryKey]).
class CuratedActivity {
  const CuratedActivity({required this.entries, this.paidFrom = const {}});

  final List<AllActivityEntry> entries;
  final Map<String, List<ActivityAccount>> paidFrom;

  List<ActivityAccount>? paidFromOf(AllActivityEntry e) =>
      paidFrom[activityEntryKey(e)];
}

/// Folds each funding chain into the action it paid for (see the file
/// header). [entries] are newest first ([mergeAllActivity]); the order is
/// kept. Each leg folds into one action at most: the first one after it.
CuratedActivity curateAllActivity(
  List<AllActivityEntry> entries, {
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  final legs = <int, ActivityLeg>{};
  for (var i = 0; i < entries.length; i++) {
    final leg = activityPlumbingLeg(entries[i], classify: classify);
    if (leg != null) legs[i] = leg;
  }
  if (legs.isEmpty) return CuratedActivity(entries: entries);

  final folded = <int>{};
  final paidFrom = <String, List<ActivityAccount>>{};
  // Oldest action first, so a leg goes to the first action after it.
  for (var i = entries.length - 1; i >= 0; i--) {
    final venue = _spendsFrom(entries[i]);
    if (venue == null) continue;
    final origins = <ActivityAccount>[];
    final visited = <ActivityAccount>{venue};
    var frontier = <({ActivityAccount target, DateTime time, double? usd})>[
      (target: venue, time: entries[i].time, usd: null),
    ];
    while (frontier.isNotEmpty) {
      final next = <({ActivityAccount target, DateTime time, double? usd})>[];
      for (final f in frontier) {
        var found = false;
        for (final j in legs.keys) {
          if (folded.contains(j)) continue;
          final leg = legs[j]!;
          if (leg.to != f.target) continue;
          final t = entries[j].time;
          if (t.isAfter(f.time.add(kActivityFundingLag)) ||
              t.isBefore(f.time.subtract(kActivityFundingWindow))) {
            continue;
          }
          final upstream = leg.usdOut;
          if (f.usd != null &&
              upstream != null &&
              !_hopMatches(upstream, f.usd!)) {
            continue;
          }
          folded.add(j);
          found = true;
          for (final from in leg.froms) {
            if (from != ActivityAccount.bitcoin && visited.add(from)) {
              next.add((target: from, time: t, usd: leg.usdIn));
            } else if (from == ActivityAccount.bitcoin &&
                !origins.contains(from)) {
              origins.add(from);
            }
          }
        }
        // An account the chain passed through with nothing feeding it is
        // where the money came from.
        if (!found && f.target != venue && !origins.contains(f.target)) {
          origins.add(f.target);
        }
      }
      frontier = next;
    }
    if (origins.isNotEmpty) paidFrom[activityEntryKey(entries[i])] = origins;
  }

  final kept = <AllActivityEntry>[
    for (var i = 0; i < entries.length; i++)
      if (!folded.contains(i)) entries[i],
  ];
  return CuratedActivity(
      entries: _dropVenueRecordTwins(kept, classify), paidFrom: paidFrom);
}

/// A venue's own deposit or withdrawal record listed beside the
/// conversion that made it (within half an hour, same side) is the same
/// move twice: the conversion's row names both ends, so the record goes.
List<AllActivityEntry> _dropVenueRecordTwins(List<AllActivityEntry> entries,
    SwapActivityKind Function(SwapOrder order) classify) {
  final swaps = <({DateTime time, bool deposit})>[];
  for (final e in entries) {
    final tx = e.tx;
    if (tx is! SwapOrderTransaction) continue;
    final kind = classify(tx.details);
    if (kind.isPredictions) {
      swaps.add((time: e.time, deposit: kind.isDeposit));
    }
  }
  if (swaps.isEmpty) return entries;
  bool twin(AllActivityEntry e) {
    final tx = e.tx;
    if (tx is! PolymarketTransaction || tx.result != null) return false;
    final type = _polyType(tx);
    if (type != ActivityType.deposit && type != ActivityType.withdraw) {
      return false;
    }
    final deposit = type == ActivityType.deposit;
    return swaps.any((s) =>
        s.deposit == deposit &&
        s.time.difference(e.time).abs() <= kActivityFundingWindow);
  }

  return [
    for (final e in entries)
      if (!twin(e)) e
  ];
}

/// The home's rows: the newest [limit] actions of [curated], plumbing left
/// to See all.
List<AllActivityEntry> homeActivityEntries(
  CuratedActivity curated, {
  int limit = kHomeActivityRows,
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  final out = <AllActivityEntry>[];
  for (final e in curated.entries) {
    if (out.length >= limit) break;
    if (activityPlumbingLeg(e, classify: classify) != null) continue;
    out.add(e);
  }
  return out;
}
