// The words on an activity row, kept apart from the widgets so every
// surface (Home, the wallets, Predictions, Investing, Ledger) names the
// same thing the same way, and so the copy can be tested without a
// widget tree.
//
// One row reads: a short verb-first title on one line ("Deposit",
// "Sold · G2", "Long BTC"), one line of context under it (the time, a
// short market label, where the money went), the amount, and at most one
// secondary figure. Long market titles, share counts and hashes belong
// to the detail sheet.

import 'package:kute/helpers/prediction_results.dart'
    show PredictionResult, predictionResults;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity, ActivityType;

/// Which way the money on a row moved, for the sign in front of its
/// amount. One rule on every surface: `+` when money arrives in the
/// balance the row belongs to (a receive, a sale, a payout), `−` when it
/// leaves (a send, a spot purchase, a lost prediction's stake), no sign
/// when nothing enters or leaves (a move between your own balances, a
/// conversion, a leveraged position's size, a prediction placed: its
/// stake moved into the position, it was not spent). The colour stays the
/// primary text colour; only profit and loss lines, and a prediction's
/// settled result (won green, lost red), are coloured.
enum ActivityFlow { moneyIn, moneyOut, neutral }

/// A market's title cut to what fits beside a crest: "ShindeN vs G2"
/// from "Counter-Strike: ShindeN vs G2 (BO3) - ESL Pro League Group
/// Stage", "Bitcoin 5:50–5:55" from "Bitcoin Up or Down - October 5,
/// 5:50AM-5:55AM ET". The full title stays on the detail sheet.
String shortMarketLabel(String? title) {
  var t = (title ?? '').trim();
  if (t.isEmpty) return '';
  // Crypto rounds: "<Asset> Up or Down - <date>, <start>-<end> ET".
  final round = RegExp(
          r'^(.+?) Up or Down\b.*?(\d{1,2}(?::\d{2})?)\s*(AM|PM)?\s*[-–]\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM)?',
          caseSensitive: false)
      .firstMatch(t);
  if (round != null) {
    final asset = round.group(1)!.trim();
    final start = round.group(2)!;
    final startHalf = round.group(3)?.toUpperCase();
    final end = round.group(4)!;
    final endHalf = round.group(5)?.toUpperCase();
    final sameHalf = startHalf == endHalf;
    final from = sameHalf || startHalf == null ? start : '$start$startHalf';
    final to = sameHalf || endHalf == null ? end : '$end$endHalf';
    return '$asset $from–$to';
  }
  // An hourly or daily round with a single time: "<Asset> Up or Down".
  final upDown =
      RegExp(r'^(.+?) Up or Down\b', caseSensitive: false).firstMatch(t);
  if (upDown != null) return upDown.group(1)!.trim();
  // "Counter-Strike: A vs B (BO3) - League": drop the game prefix, the
  // series note and the tournament.
  final colon = t.indexOf(': ');
  if (colon > 0 && colon <= 24 && t.substring(colon + 2).contains(' vs')) {
    t = t.substring(colon + 2);
  }
  final dash = t.indexOf(' - ');
  if (dash > 0) t = t.substring(0, dash);
  t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  return t;
}

/// Title and context line of a Predictions row, from the venue's record.
/// Only a redeem (or a result read from the resolved market,
/// [PredictionResult.activity]) says Won or Lost: a sale is what the
/// person did, never the market's result. A placed prediction carries no
/// sign: the stake moved into the position.
({String title, String subtitle, ActivityFlow flow}) predictionRowCopy(
  AppLocalizations l,
  Activity activity, {
  required String time,
}) {
  ActivityType? type;
  try {
    type = activity.activityType;
  } catch (_) {
    type = null;
  }
  final market = shortMarketLabel(activity.title);
  final outcome = (activity.outcome ?? '').trim();
  // What the title names after the verb: the outcome when there is one,
  // else the market, else the venue.
  final name = outcome.isNotEmpty
      ? outcome
      : market.isNotEmpty
          ? market
          : l.predictions;
  // The context line: the market and the time when the title named the
  // outcome, the time alone otherwise.
  final context =
      outcome.isNotEmpty && market.isNotEmpty ? '$market · $time' : time;
  switch (type) {
    case ActivityType.deposit:
      return (
        title: l.activityRowDeposit,
        subtitle: '${l.activityRowTo(l.predictions)} · $time',
        flow: ActivityFlow.neutral,
      );
    case ActivityType.withdraw:
      return (
        title: l.activityRowWithdraw,
        subtitle: '${l.activityRowFrom(l.predictions)} · $time',
        flow: ActivityFlow.neutral,
      );
    case ActivityType.trade:
      final sell = (activity.side ?? '').toUpperCase() == 'SELL';
      return (
        title: sell ? l.activityRowSold(name) : l.activityRowPrediction(name),
        subtitle: context,
        flow: sell ? ActivityFlow.moneyIn : ActivityFlow.neutral,
      );
    case ActivityType.redeem:
      final won = activity.usdcSize > 0.001;
      return (
        title: won ? l.activityRowWon(name) : l.activityRowLost(name),
        subtitle: context,
        flow: won ? ActivityFlow.moneyIn : ActivityFlow.neutral,
      );
    case ActivityType.merge:
      return (
        title: l.ledgerActivityMergedShares,
        subtitle: market.isNotEmpty ? market : time,
        flow: ActivityFlow.moneyIn,
      );
    case ActivityType.split:
      return (
        title: l.ledgerActivitySplitShares,
        subtitle: market.isNotEmpty ? market : time,
        flow: ActivityFlow.moneyOut,
      );
    default:
      return (
        title: l.activity,
        subtitle: market.isNotEmpty ? market : time,
        flow: ActivityFlow.neutral,
      );
  }
}

/// Net dollars put into a market: every BUY's outlay minus every SELL's
/// proceeds on [redeem]'s market in [history]. Matched by market only,
/// not outcome: a redeem can report the winning outcome's index while the
/// buys carry another, and a hedge on both sides is netted. 0 when there
/// is no trade history for the market.
double predictionStakeOnMarket(Iterable<Activity> history, Activity redeem) {
  final cid = redeem.conditionId;
  if (cid.isEmpty) return 0;
  double net = 0;
  for (final a in history) {
    if (a.conditionId != cid || a.type.toUpperCase() != 'TRADE') continue;
    final side = (a.side ?? '').toUpperCase();
    if (side == 'BUY') {
      net += a.usdcSize;
    } else if (side == 'SELL') {
      net -= a.usdcSize;
    }
  }
  return net;
}

/// Realised profit or loss of [sell]: its proceeds minus the average cost
/// of the shares sold, from the earlier BUYs of the same outcome in
/// [history]. Null when no buy is known.
double? predictionSalePnl(Iterable<Activity> history, Activity sell) {
  final cid = sell.conditionId;
  if (cid.isEmpty || sell.size <= 0) return null;
  double boughtUsd = 0;
  double boughtShares = 0;
  for (final a in history) {
    if (identical(a, sell) ||
        a.conditionId != cid ||
        a.type.toUpperCase() != 'TRADE' ||
        a.outcomeIndex != sell.outcomeIndex ||
        (a.side ?? '').toUpperCase() != 'BUY' ||
        a.timestamp > sell.timestamp) {
      continue;
    }
    boughtUsd += a.usdcSize;
    boughtShares += a.size;
  }
  if (boughtShares <= 0) return null;
  return sell.usdcSize - boughtUsd / boughtShares * sell.size;
}

/// The figures of a Predictions row: the amount, its sign, the realised
/// profit or loss for the line under it (null when there is none worth
/// showing), and whether it is a settled result, whose amount is coloured
/// (won green, lost red).
/// - A win shows the payout (+) and its profit over the stake.
/// - A loss shows what was lost as the amount itself (−stake), with
///   nothing under it; $0.00 only when the stake is unknown.
/// - A sale shows the proceeds (+) and its realised profit or loss.
/// - A prediction shows its stake, unsigned: the money went into the
///   position. Moves show the amount, unsigned.
/// [result] is the row's result read from the resolved market
/// ([predictionResults]): its own stake and payout stand in for the
/// history's.
({double amount, ActivityFlow flow, double? pnl, bool settled})
    predictionRowFigures(
  Activity activity,
  Iterable<Activity> history, {
  required ActivityFlow flow,
  PredictionResult? result,
}) {
  double? shown(double? pnl) =>
      pnl != null && pnl.abs() > 0.005 ? pnl : null;
  if (result != null) {
    return result.won
        ? (
            amount: result.payoutUsd,
            flow: ActivityFlow.moneyIn,
            pnl: shown(result.pnlUsd),
            settled: true,
          )
        : (
            amount: result.stakeUsd,
            flow: ActivityFlow.moneyOut,
            pnl: null,
            settled: true,
          );
  }
  final type = activity.type.toUpperCase();
  if (type == 'REDEEM') {
    final payout = activity.usdcSize;
    final stake = predictionStakeOnMarket(history, activity);
    if (payout > 0.001) {
      return (
        amount: payout,
        flow: ActivityFlow.moneyIn,
        pnl: stake > 0 ? shown(payout - stake) : null,
        settled: true,
      );
    }
    return stake > 0
        ? (amount: stake, flow: ActivityFlow.moneyOut, pnl: null, settled: true)
        : (
            amount: payout,
            flow: ActivityFlow.neutral,
            pnl: null,
            settled: false,
          );
  }
  if (type == 'TRADE' && (activity.side ?? '').toUpperCase() == 'SELL') {
    return (
      amount: activity.usdcSize,
      flow: flow,
      pnl: shown(predictionSalePnl(history, activity)),
      settled: false,
    );
  }
  return (amount: activity.usdcSize, flow: flow, pnl: null, settled: false);
}

/// Whether [fill] traded a spot token rather than a perpetual.
bool hlFillIsSpot(HlFill fill) =>
    fill.coin.startsWith('@') || fill.coin.contains('/');

/// Short title of an Investing fill: "Long BTC", "Short ETH", "Closed
/// BTC", "Reduced BTC", "Bought · HYPE", "Sold · HYPE". [coin] is the
/// display symbol.
String hlFillRowTitle(HlFill fill, String coin, AppLocalizations l) {
  if (fill.liquidated) return l.activityRowLiquidated(coin);
  if (hlFillIsSpot(fill)) {
    return fill.isBuy ? l.activityRowBought(coin) : l.activityRowSold(coin);
  }
  final before = fill.startPosition;
  if (before != null &&
      before.isFinite &&
      fill.sz > 0 &&
      (fill.side == 'B' || fill.side == 'A')) {
    final after = before + (fill.isBuy ? fill.sz : -fill.sz);
    if (after.abs() < 1e-10) return l.activityRowClosed(coin);
    final grew = before == 0 ||
        before.sign != after.sign ||
        after.abs() > before.abs();
    if (!grew) return l.activityRowReduced(coin);
    return after > 0 ? l.activityRowLong(coin) : l.activityRowShort(coin);
  }
  final direction = fill.dir.toLowerCase();
  if (direction.contains('close')) return l.activityRowClosed(coin);
  if (direction.contains('open long')) return l.activityRowLong(coin);
  if (direction.contains('open short')) return l.activityRowShort(coin);
  return fill.isBuy ? l.activityRowLong(coin) : l.activityRowShort(coin);
}

/// Money direction of an Investing fill: a spot purchase spends dollars,
/// a spot sale returns them; a perpetual's size moves nothing in or out.
ActivityFlow hlFillFlow(HlFill fill) {
  if (!hlFillIsSpot(fill)) return ActivityFlow.neutral;
  return fill.isBuy ? ActivityFlow.moneyOut : ActivityFlow.moneyIn;
}
