// The results of predictions held to a resolved market, for the
// Predictions activity.
//
// The venue's activity only records what the account did: a buy, a sale,
// a claim. A prediction that lost is never claimed (there is nothing to
// claim), so the history alone never says it lost: a lost Bitcoin 5-minute
// round showed only its "Prediction · Up" row. The positions say what the
// market decided, so each prediction still held when its market resolved
// gets one result row here, dated at the resolution:
//
// * a winner not yet claimed: "Won · Up", the payout and its profit (the
//   claim, once it lands, is the venue's own Won row and replaces it);
// * a loser, claimed (cleared) or not: "Lost · Up", the stake it lost.
//
// Resolution comes from the same two signals the Portfolio's resolved
// positions use: `redeemable` on a held position (kept sticky by the
// trading provider), and the settled CLOSED list, which only carries
// positions held to the result (a position sold before it is a "Sold"
// row, never a win or a loss). Price or time alone never decide it.
//
// The amounts agree with the Statistics tab's realised P&L
// (`PredictionRecord.decidedPnlUsd`): a held position settles at its
// payout less what the shares still held cost, and anything sold before
// the result is already the realised profit or loss of its Sold row.

import 'package:kute/models/polymarket_model.dart'
    show Activity, ClosedPosition, Position;

/// Under this many shares a position is dust (what a "sell all" leaves):
/// never a result. Mirrors `kPolyDustShares`.
const double kPredictionDustShares = 0.01;

/// A resolved market marks the winning outcome's token at 1 and the
/// losing one's at 0; within a cent of either, the outcome is decided.
const double kPredictionWonPrice = 0.99;
const double kPredictionLostPrice = 0.01;

/// What a position left before its result may have paid per share and
/// still read as held to it: within this of the settlement price.
const double kPredictionSaleTolerance = 0.05;

/// Whether [price] is a decided outcome's price (1 or 0, to the cent).
bool predictionPriceSettled(double price) =>
    price >= kPredictionWonPrice || price <= kPredictionLostPrice;

/// A position still held (`status=OPEN`): true won and false lost once its
/// market resolved (`redeemable`, priced 1 or 0); null while it can still
/// move, or resolved at neither.
bool? heldPredictionWon({required bool redeemable, required double curPrice}) {
  if (!redeemable) return null;
  if (curPrice >= kPredictionWonPrice) return true;
  if (curPrice <= kPredictionLostPrice) return false;
  return null;
}

/// Whether a settled closed position was left by selling (all of it, or
/// enough to move what it paid) rather than held to the result: what it
/// paid back per share over its life (the basis `totalSize * avgPrice`,
/// fees included, plus [realizedPnl], over [totalSize]) is more than
/// [kPredictionSaleTolerance] from the settlement price. A row sold
/// mid-market keeps following the market after the account left, so once
/// it settles it is priced 1 or 0 like one held to the result.
bool predictionClosedBySale({
  required double totalSize,
  required double avgPrice,
  required double realizedPnl,
  required double curPrice,
}) {
  if (totalSize <= 0) return false;
  final perShare = (totalSize * avgPrice + realizedPnl) / totalSize;
  final settlement = curPrice >= 0.5 ? 1.0 : 0.0;
  return (perShare - settlement).abs() > kPredictionSaleTolerance;
}

/// A closed position (`status=CLOSED`): true won and false lost when it
/// was held to a settled result, which is what puts it on the settled
/// CLOSED list; null when it was left before ([predictionClosedBySale],
/// or exited while the market still traded): a Sold, never a win or a
/// loss.
bool? closedPredictionWon({
  required double totalSize,
  required double avgPrice,
  required double realizedPnl,
  required double curPrice,
}) {
  if (!predictionPriceSettled(curPrice)) return null;
  if (predictionClosedBySale(
      totalSize: totalSize,
      avgPrice: avgPrice,
      realizedPnl: realizedPnl,
      curPrice: curPrice)) {
    return null;
  }
  return curPrice >= 0.5;
}

/// One prediction's result, known from its resolved market.
class PredictionResult {
  const PredictionResult({
    required this.activity,
    required this.won,
    required this.stakeUsd,
    required this.payoutUsd,
    this.claimable = false,
  });

  /// The result as a venue record (a REDEEM paying [payoutUsd], dated at
  /// the resolution) carrying the market, the outcome and the crest, so
  /// it is titled and drawn like every other Predictions row. Its
  /// transaction hash is empty: nothing happened on chain.
  final Activity activity;
  final bool won;

  /// What the shares held at the resolution cost.
  final double stakeUsd;

  /// What the market pays for them: the share count for a win, 0 for a
  /// loss.
  final double payoutUsd;

  /// A win the account can still claim.
  final bool claimable;

  double get pnlUsd => payoutUsd - stakeUsd;
  String get conditionId => activity.conditionId;
}

/// The results of the account's predictions held to a resolved market:
/// [open] and [closed] are its positions (`/v2/positions`, both arms),
/// [history] its activity. [clearing] holds markets whose claim already
/// went through and is waiting for the venue to catch up: still a win,
/// no longer claimable.
///
/// A market with a claim in [history] has its result there already (the
/// venue's Won row, or its zero "Lost" redeem where the surface keeps
/// those) and gets none here.
List<PredictionResult> predictionResults({
  required Iterable<Position> open,
  required Iterable<ClosedPosition> closed,
  required Iterable<Activity> history,
  Set<String> clearing = const {},
  DateTime? now,
}) {
  final claimed = <String>{};
  final lastEvent = <String, int>{};
  final soldShares = <String, double>{};
  for (final a in history) {
    final cid = a.conditionId;
    if (cid.isEmpty) continue;
    final type = a.type.toUpperCase();
    if (type == 'REDEEM') claimed.add(cid);
    if (a.timestamp > (lastEvent[cid] ?? 0)) lastEvent[cid] = a.timestamp;
    final token = a.asset;
    if (type == 'TRADE' &&
        (a.side ?? '').toUpperCase() == 'SELL' &&
        token != null &&
        token.isNotEmpty) {
      soldShares[token] = (soldShares[token] ?? 0) + a.size;
    }
  }
  final nowSec = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

  // The result's date: the resolution where the venue says when it was,
  // never in the future and never before the account's last record on
  // the market (the result follows the bet it settles).
  int dated(String cid, DateTime? resolvedAt) {
    var at = resolvedAt == null ? 0 : resolvedAt.millisecondsSinceEpoch ~/ 1000;
    if (at > nowSec) at = nowSec;
    final last = lastEvent[cid];
    if (last != null && at <= last) at = last + 1;
    if (at <= 0) at = nowSec;
    return at;
  }

  Activity record({
    required String proxyWallet,
    required String cid,
    required String token,
    required int outcomeIndex,
    required String outcome,
    required String title,
    required String slug,
    required String? icon,
    required String eventSlug,
    required double shares,
    required double payout,
    required int at,
  }) =>
      Activity(
        proxyWallet: proxyWallet,
        timestamp: at,
        conditionId: cid,
        type: 'REDEEM',
        size: shares,
        usdcSize: payout,
        transactionHash: '',
        asset: token,
        outcomeIndex: outcomeIndex,
        title: title,
        slug: slug,
        icon: icon,
        eventSlug: eventSlug,
        outcome: outcome,
      );

  final results = <PredictionResult>[];
  final seen = <String>{};
  for (final p in open) {
    final cid = p.conditionId;
    if (p.size < kPredictionDustShares || claimed.contains(cid)) continue;
    final won =
        heldPredictionWon(redeemable: p.redeemable, curPrice: p.curPrice);
    if (won == null) continue;
    if (!seen.add(p.asset)) continue;
    final stake = p.initialValue > 0 ? p.initialValue : p.size * p.avgPrice;
    final payout = won ? p.size : 0.0;
    if (!won && stake < 0.005) continue;
    results.add(PredictionResult(
      activity: record(
        proxyWallet: p.proxyWallet,
        cid: cid,
        token: p.asset,
        outcomeIndex: p.outcomeIndex,
        outcome: p.outcome,
        title: p.title,
        slug: p.slug,
        icon: p.icon,
        eventSlug: p.eventSlug,
        shares: p.size,
        payout: payout,
        at: dated(cid, DateTime.tryParse(p.endDate ?? '')),
      ),
      won: won,
      stakeUsd: stake,
      payoutUsd: payout,
      claimable: won && !clearing.contains(cid),
    ));
  }
  // A claimed win is the venue's own Won row; a settled loser is never
  // claimed with value, so it is only known from here.
  for (final p in closed) {
    final cid = p.conditionId;
    if (p.won || claimed.contains(cid) || !seen.add(p.asset)) continue;
    final held = p.size - (soldShares[p.asset] ?? 0);
    if (held < kPredictionDustShares) continue;
    final stake = held * p.avgPrice;
    if (stake < 0.005) continue;
    results.add(PredictionResult(
      activity: record(
        proxyWallet: p.proxyWallet,
        cid: cid,
        token: p.asset,
        outcomeIndex: p.outcomeIndex,
        outcome: p.outcome,
        title: p.title,
        slug: p.slug,
        icon: p.icon,
        eventSlug: p.eventSlug,
        shares: held,
        payout: 0,
        at: dated(cid, p.resolutionDate),
      ),
      won: false,
      stakeUsd: stake,
      payoutUsd: 0,
    ));
  }
  return results;
}
