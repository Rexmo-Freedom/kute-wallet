// lib/services/orchestra/own_bitcoin_deliveries.dart
//
// Which Spark receives are the wallet's own Orchestra deliveries to
// Bitcoin, so Activity lists each such move once: the move's row (a
// withdrawal from Investments, a purchase from Dollars, a multi-source
// move whose legs these rows are) and never a "Received ₿" row beside it.
//
// A receive is a delivery when:
//
//  1. the delivery reconciler linked it to the row it settled
//     (`PolymarketSparkTxsService.orchestraDeliveryLinks`): that row is on
//     the list, by id, by the order its quote became, or by its settlement
//     operation. Deterministic, whenever it landed, and it survives a
//     restart. A row takes every receive linked to it: a payout split
//     across several transfers is one row.
//     One link is not taken at its word: a receive linked to a row it does
//     not fit, while it is the exact figure of another listed row of the
//     wallet's that has no receive at all ([crossedDeliveryLinks]). A Swap
//     paid from two places delivers twice within the minute, and the
//     reconciler once settled the slower leg on the faster leg's receive;
//     the slower leg's own delivery then stood alone as "Received ₿".
//     Such a receive goes to the row it is the delivery of, and the row it
//     was linked to claims its own by amount and time like any other.
//  2. otherwise, a row delivering bitcoin to the wallet's own Spark balance
//     claims it by amount and time, from [kOwnDeliveryEarlyMargin] before
//     the row to [kOwnDeliveryArrivalWindow] after it (the reconciler's own
//     window; a day for a Circle CCTP leg, held for screening):
//       a. one receive within two percent of the row's figure, the closest
//          amount first, then the closest time, one to one;
//       b. else, the row oldest first, the set of two to [kMaxDeliveryLegs]
//          receives that adds up to its figure, when it comes closer than
//          any single receive (a split payout, a leg landing late); else
//          one receive within the estimate's band (ten percent for the
//          wallet's own withdrawal, whose figure is the quote's estimate
//          until polled).
//     A row whose linked legs fall short of the figure the reconciler saw
//     when it linked them ([OrchestraDeliveryLink.expectedSats]) claims the
//     rest the same way, held to two percent of the whole.
//  3. otherwise, for the wallet's own moves to Bitcoin only (its own
//     withdrawal kinds, or a row settling to its own address; never a row
//     only a bet-flow tag ties to it), by the dollars that left for it:
//     one receive whose dollar value when it landed ([ReceivedUsd], its
//     fiat snapshot) is what that many dollars buy less the route's fees
//     ([plausibleDeliveryUsd]), from [kOwnDeliveryEarlyMargin] before the
//     row to [kOwnDeliveryUsdWindow] after it (a day for a Circle CCTP
//     leg). This is how a row whose bitcoin figure is not known yet (a
//     CCTP leg out of Investing that Orchestra reports done with no
//     figure) finds its receive without the reconciler, and how a
//     delivery the fees took more than the estimate's band from, or that
//     landed after the amount window, still folds in. A row that already
//     has a figure also needs the receive within half to five quarters of
//     it. The closest dollar value first, then the closest time, the
//     oldest row first.
//     An unlinked receive later than the windows keeps its own row, and so
//     does one a row has no room left for: amount and time alone never
//     hide money that may have come from outside, and a receive whose
//     dollar value is not known is never matched by it.
//
// A receive nothing claims keeps its own row. Pure, so the lists and the
// tests read the same answer.

import 'dart:math' as math;

import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show OwnSparkArrivals;
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;
import 'package:kute/services/polymarket_spark_txs_service.dart'
    show OrchestraDeliveryLink;
import 'package:kute/services/security/address_guard.dart'
    show sparkIdentityPubkeyHex;
import 'package:kute/services/tx_fiat_snapshot_service.dart'
    show TxFiatSnapshotService;

/// How long after one of the wallet's own deliveries to Bitcoin started an
/// unlinked receive may still be matched to it by amount: the delivery
/// reconciler's window. A linked receive folds in whenever it landed.
const Duration kOwnDeliveryArrivalWindow = Duration(minutes: 90);

/// A Circle CCTP move out of Investing may be held for screening before it
/// delivers (the first CCTP sweep landed 42 minutes after it left); its
/// legs are matched by amount for up to a day.
const Duration kOwnCctpDeliveryArrivalWindow = Duration(hours: 24);

/// A row stamped a little after its money moved (written when the flow
/// returned) may see its receive land just before it.
const Duration kOwnDeliveryEarlyMargin = Duration(minutes: 10);

/// How long after one of the wallet's own moves to Bitcoin started a
/// receive may still be matched to it by the dollars that left for it
/// ([plausibleDeliveryUsd]): Orchestra can hold a delivery well past the
/// amount window. A Circle CCTP leg keeps its day
/// ([kOwnCctpDeliveryArrivalWindow]).
const Duration kOwnDeliveryUsdWindow = Duration(hours: 6);

/// The dollar value a receive had when it landed (its fiat snapshot, else
/// its sats at the current price), null when not known. The wallet's own
/// moves to Bitcoin are matched by it ([plausibleDeliveryUsd]).
typedef ReceivedUsd = double? Function(SparkTransaction rx);

/// [ReceivedUsd] from the wallet's own records: the receive's fiat
/// snapshot (its dollar value when the wallet first saw it,
/// [TxFiatSnapshotService]), else its sats at [currentBtcUsd] (0 when the
/// price is not known: null then).
ReceivedUsd snapshotReceivedUsd({double currentBtcUsd = 0}) => (rx) {
      final snap = TxFiatSnapshotService.snapshot(rx.id);
      if (snap != null && snap.usd > 0) return snap.usd;
      if (!currentBtcUsd.isFinite || currentBtcUsd <= 0) return null;
      return rx.amountSats.abs() / 1e8 * currentBtcUsd;
    };

const Set<String> _dollarCoins = {
  'USDC',
  'USDC.E',
  'USDT',
  'DAI',
  'USD',
  'USDB',
  'PUSD',
};

/// The dollars that left for [d] when its source is a dollar coin (USDC
/// on HyperCore or Polygon, USDB, pUSD): six-decimal base units or plain
/// dollars, the same reading the rows make. Null otherwise.
double? deliverySentUsd(SwapOrder d) {
  final coin = d.coinFrom.trim().toUpperCase();
  if (!_dollarCoins.contains(coin)) return null;
  final raw = double.tryParse(d.depositAmount) ?? 0;
  if (!raw.isFinite || raw <= 0) return null;
  return (raw >= 10000 && raw == raw.roundToDouble()) ? raw / 1e6 : raw;
}

/// Whether a receive worth [receivedUsd] when it landed can be what
/// [sentUsd] dollars bought: the route's fees (the CCTP forward fee,
/// Orchestra's and Kute's) keep it under what left, a quarter at most plus
/// 75 cents on a small move, and the price moving while it travelled (or
/// before the wallet first saw it) keeps it within eight percent above.
bool plausibleDeliveryUsd(double receivedUsd, double sentUsd) =>
    sentUsd > 0 &&
    receivedUsd > 0 &&
    receivedUsd >= sentUsd * 0.75 - 0.75 &&
    receivedUsd <= sentUsd * 1.08 + 0.25;

/// Whether [address] is one of [own] (lowercased), either spelling of a
/// Spark address included (`sp1…` and `spark1…` encode the same key, and
/// the SDK's spelling is not always the one a provider echoes back).
bool settlesToOwnAddress(String address, Set<String> own) {
  final a = address.trim().toLowerCase();
  if (a.isEmpty || own.isEmpty) return false;
  if (own.contains(a)) return true;
  final key = sparkIdentityPubkeyHex(a);
  if (key == null) return false;
  for (final o in own) {
    if (sparkIdentityPubkeyHex(o) == key) return true;
  }
  return false;
}

/// An Orchestra BTC figure in sats: Flashnet's sats (a whole number of at
/// least one) or a BTC decimal (the status poll's).
int orchestraBtcFieldToSats(String btcField) {
  final raw = double.tryParse(btcField) ?? 0;
  if (!raw.isFinite || raw <= 0) return 0;
  return (raw >= 1 && raw == raw.roundToDouble())
      ? raw.round()
      : (raw * 100000000).round();
}

/// The kinds that are the wallet's own money coming home to its own Spark
/// balance by construction: the flow resolved the recipient to the
/// wallet's address before anything moved.
const Set<SwapActivityKind> _ownWithdrawalKinds = {
  SwapActivityKind.dollarWithdrawal,
  SwapActivityKind.investingWithdrawal,
  SwapActivityKind.predictionsWithdrawal,
};

/// A withdrawal may reach the wallet as several Spark transfers (Orchestra
/// and the venues split a payout); at most this many are read as one
/// delivery.
const int kMaxDeliveryLegs = 4;

/// The tight match: a delivered amount within two percent of what the row
/// says (one sat at least). A leg or a set of legs this close is the row's.
/// Whether [rx] is an on-chain deposit claimed into Spark, which no
/// Orchestra delivery ever is (they arrive over Spark or Lightning).
bool isOnChainDeposit(SparkTransaction rx) =>
    rx.sparkType == SparkTransactionType.bitcoin;

int tightDeliveryTolerance(int sats) => math.max(1, (sats * 0.02).round());

/// The legs among [candidates] that together deliver [target] sats within
/// [tolerance]: the set of two to [maxLegs] receives whose sum is closest to
/// [target], fewer legs on a tie, then the set that finished soonest. Null
/// when no set comes within [tolerance]. Only receives smaller than the
/// target can be a part of it; the closest twelve by time are read, which
/// bounds the search.
List<SparkTransaction>? matchDeliveryLegSet(
  int target,
  int tolerance,
  List<SparkTransaction> candidates, {
  required DateTime from,
  int maxLegs = kMaxDeliveryLegs,
}) {
  if (target <= 0) return null;
  final parts = [
    for (final rx in candidates)
      if (rx.amountSats.abs() > 0 && rx.amountSats.abs() < target) rx,
  ]..sort((a, b) => a.timestamp.difference(from).inMilliseconds.abs().compareTo(
      b.timestamp.difference(from).inMilliseconds.abs()));
  final pool = parts.length > 12 ? parts.sublist(0, 12) : parts;
  List<SparkTransaction>? best;
  int? bestDiff;
  DateTime? bestEnd;
  void consider(List<SparkTransaction> set) {
    final sum = set.fold<int>(0, (s, rx) => s + rx.amountSats.abs());
    final diff = (sum - target).abs();
    if (diff > tolerance) return;
    final end = set
        .map((rx) => rx.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final better = best == null ||
        diff < bestDiff! ||
        (diff == bestDiff &&
            (set.length < best!.length ||
                (set.length == best!.length && end.isBefore(bestEnd!))));
    if (better) {
      best = List.of(set);
      bestDiff = diff;
      bestEnd = end;
    }
  }

  void walk(int start, List<SparkTransaction> set, int sum) {
    if (set.length >= 2) consider(set);
    if (set.length == maxLegs) return;
    for (var i = start; i < pool.length; i++) {
      final next = sum + pool[i].amountSats.abs();
      // Every leg adds money: past the target and its tolerance no wider
      // set can come back.
      if (next > target + tolerance) continue;
      set.add(pool[i]);
      walk(i + 1, set, next);
      set.removeLast();
    }
  }

  walk(0, <SparkTransaction>[], 0);
  return best;
}

/// The receives among [receives] that are deliveries of [exchanges] (the
/// surface's conversion rows), each mapped to the row it belongs to. A row
/// may take several receives (a payout split across transfers); a receive
/// belongs to one row at most.
///
/// [betFlowOrderIds] are orders the bet and claim flows tagged (ownership
/// without an own settle address); [links] the reconciler's links;
/// [receivedUsd] each receive's dollar value when it landed (step 3 of the
/// file header; without it nothing is matched by dollars).
Map<String, String> ownBitcoinDeliveryReceives(
  List<SwapOrderTransaction> exchanges,
  Iterable<SparkTransaction> receives, {
  required Set<String> ownAddresses,
  required SwapActivityKind Function(SwapOrder order) classify,
  Set<String> betFlowOrderIds = const {},
  Map<String, OrchestraDeliveryLink> links = const {},
  ReceivedUsd? receivedUsd,
}) {
  final claimed = <String, String>{};
  // An on-chain deposit is never a delivery: Orchestra pays the wallet
  // over Spark or Lightning. Matching one by amount and time (or a link a
  // mistaken match left) hid a claimed deposit from Activity entirely.
  final inbound = [
    for (final rx in receives)
      if (rx.type == TransactionType.received && !isOnChainDeposit(rx)) rx,
  ];
  if (inbound.isEmpty || exchanges.isEmpty) return claimed;

  // Whether [d] is the wallet's own money coming home: one of its own
  // withdrawal kinds (never to a Spark address known not to be its own),
  // or a row settling to its own address.
  ({bool ownWithdrawal, bool toSelf}) ownership(SwapOrder d) {
    final toSelf = settlesToOwnAddress(d.withdrawalAddress, ownAddresses);
    // A Spark address the wallet knows is not its own: someone else's
    // money, whatever the flow says.
    final foreign = !toSelf &&
        ownAddresses.isNotEmpty &&
        sparkIdentityPubkeyHex(d.withdrawalAddress.trim()) != null;
    return (
      ownWithdrawal: d.isOrchestra &&
          _ownWithdrawalKinds.contains(classify(d)) &&
          !foreign,
      toSelf: toSelf,
    );
  }

  // 1. The reconciler's links: the row it settled, wherever its id went.
  // Every receive linked to a listed row folds into it, however many legs
  // the payout took and whenever each landed. A link crossed over from
  // another of the wallet's rows goes to the row it is the delivery of.
  final linkedSats = <String, int>{};
  final linkedExpected = <String, int>{};
  // What a row lost to a crossed link: the sats it was settled on by
  // mistake and the figure it was matched against then (0: not recorded).
  final crossedAway = <String, ({int sats, int expected})>{};
  if (links.isNotEmpty) {
    final crossed = {
      for (final c in crossedDeliveryLinks(exchanges, inbound,
          links: links,
          owns: (ex) {
            final own = ownership(ex.details);
            return own.ownWithdrawal || own.toSelf;
          }))
        c.receiveId: c,
    };
    for (final rx in inbound) {
      final link = links[rx.id];
      if (link == null) continue;
      final cross = crossed[rx.id];
      if (cross != null) {
        claimed[rx.id] = cross.toRow;
        linkedSats[cross.toRow] =
            (linkedSats[cross.toRow] ?? 0) + rx.amountSats.abs();
        final lost = crossedAway[cross.fromRow];
        crossedAway[cross.fromRow] = (
          sats: (lost?.sats ?? 0) + rx.amountSats.abs(),
          expected: math.max(lost?.expected ?? 0, cross.expectedSats ?? 0),
        );
        continue;
      }
      final ex = _linkedRow(link, exchanges);
      if (ex == null) continue;
      claimed[rx.id] = ex.id;
      linkedSats[ex.id] = (linkedSats[ex.id] ?? 0) + rx.amountSats.abs();
      final expected = link.expectedSats;
      if (expected != null && expected > (linkedExpected[ex.id] ?? 0)) {
        linkedExpected[ex.id] = expected;
      }
    }
  }

  // 2. Amount and time. Each row the wallet owns that delivers bitcoin to
  // its own Spark balance names what it still waits for (its whole figure,
  // or what its linked legs left short of the figure the reconciler saw)
  // and the window its legs may land in.
  final wants = <({
    SwapOrderTransaction ex,
    int target,
    int tight,
    int loose,
    Duration window,
  })>[];
  // The wallet's own moves to Bitcoin paid in dollars, for step 3.
  final byUsd = <({
    SwapOrderTransaction ex,
    double sentUsd,
    int fieldSats,
    Duration window,
  })>[];
  for (final ex in exchanges) {
    final d = ex.details;
    if (d.coinTo.toUpperCase() != 'BTC') continue;
    // Only a delivery to the Spark balance is a Spark receive: bitcoin
    // settled on-chain (a Ledger, another wallet) never is.
    final to = d.networkTo.toUpperCase();
    if (to != 'SPARK' && to != 'LIGHTNING') continue;
    if (OwnSparkArrivals.failedStatuses.contains(d.status)) continue;
    var fieldSats = orchestraBtcFieldToSats(d.withdrawalAmount);
    final linked = linkedSats[ex.id] ?? 0;
    // A row settled on a receive that was another row's delivery reads
    // that receive's figure, not its own: it waits for what it said it
    // would deliver when it was matched.
    final lost = crossedAway[ex.id];
    if (lost != null &&
        lost.expected > 0 &&
        (fieldSats - lost.sats).abs() <= tightDeliveryTolerance(lost.sats)) {
      fieldSats = lost.expected;
    }
    final expected = math.max(fieldSats, linkedExpected[ex.id] ?? 0);
    final (:ownWithdrawal, :toSelf) = ownership(d);
    final cctp = _isCctp(d);
    if ((ownWithdrawal || toSelf) && linked == 0) {
      final sentUsd = deliverySentUsd(d);
      if (sentUsd != null) {
        byUsd.add((
          ex: ex,
          sentUsd: sentUsd,
          fieldSats: fieldSats,
          window: cctp ? kOwnCctpDeliveryArrivalWindow : kOwnDeliveryUsdWindow,
        ));
      }
    }
    // A row whose bitcoin figure is not known yet claims nothing by amount.
    if (expected <= 0) continue;
    final tagged = betFlowOrderIds.contains(ex.id);
    // Amount and time alone can coincide: the row must be the wallet's.
    if (!ownWithdrawal && !toSelf && !tagged && linked == 0) continue;
    final tight = tightDeliveryTolerance(expected);
    if (linked > 0) {
      // Linked legs already account for the row: nothing more to claim.
      final remaining = expected - linked;
      if (remaining <= tight) continue;
      // The rest of a split payout: held to the tight match on the whole.
      wants.add((
        ex: ex,
        target: remaining,
        tight: tight,
        loose: tight,
        window: _deliveryWindow(d, ownWithdrawal || toSelf || linked > 0),
      ));
      continue;
    }
    // A withdrawal's stored figure is the quote's estimate until the poll
    // writes the delivered one: a wider match than an exact settled
    // amount is held to.
    // A Circle CCTP leg's figure is what its order reported delivering,
    // never an estimate, and its window is long: the tight match only.
    wants.add((
      ex: ex,
      target: expected,
      tight: tight,
      loose: ownWithdrawal && !cctp
          ? math.max(1, (expected * 0.10).round())
          : tight,
      window: _deliveryWindow(d, ownWithdrawal || toSelf),
    ));
  }
  if (wants.isEmpty && byUsd.isEmpty) return claimed;

  bool inWindow(SparkTransaction rx, SwapOrderTransaction ex, Duration w) {
    final delta = rx.timestamp.difference(ex.timestamp);
    return delta >= -kOwnDeliveryEarlyMargin && delta <= w;
  }

  // 2a. One receive close to a row's figure (two percent): the closest
  // amount first, then the closest time, one to one.
  final done = <String>{};
  final pairs = <({String rx, String ex, int diff, int delta})>[];
  for (final w in wants) {
    for (final rx in inbound) {
      if (claimed.containsKey(rx.id)) continue;
      final diff = (rx.amountSats.abs() - w.target).abs();
      if (diff > w.tight) continue;
      if (!inWindow(rx, w.ex, w.window)) continue;
      pairs.add((
        rx: rx.id,
        ex: w.ex.id,
        diff: diff,
        delta: rx.timestamp.difference(w.ex.timestamp).inMilliseconds.abs(),
      ));
    }
  }
  pairs.sort((a, b) {
    final byDiff = a.diff.compareTo(b.diff);
    return byDiff != 0 ? byDiff : a.delta.compareTo(b.delta);
  });
  for (final p in pairs) {
    if (claimed.containsKey(p.rx) || done.contains(p.ex)) continue;
    claimed[p.rx] = p.ex;
    done.add(p.ex);
  }

  // 2b. A row still waiting, oldest first: the set of legs that adds up to
  // its figure when it comes closer than any single receive (a payout split
  // across transfers, one landing late), else one receive within the
  // estimate's band.
  final waiting = [
    for (final w in wants)
      if (!done.contains(w.ex.id)) w,
  ]..sort((a, b) => a.ex.timestamp.compareTo(b.ex.timestamp));
  for (final w in waiting) {
    final candidates = [
      for (final rx in inbound)
        if (!claimed.containsKey(rx.id) && inWindow(rx, w.ex, w.window)) rx,
    ];
    if (candidates.isEmpty) continue;
    SparkTransaction? single;
    var singleDiff = 0;
    for (final rx in candidates) {
      final diff = (rx.amountSats.abs() - w.target).abs();
      if (diff > w.loose) continue;
      if (single == null ||
          diff < singleDiff ||
          (diff == singleDiff &&
              rx.timestamp.difference(w.ex.timestamp).abs() <
                  single.timestamp.difference(w.ex.timestamp).abs())) {
        single = rx;
        singleDiff = diff;
      }
    }
    final set = matchDeliveryLegSet(w.target, w.loose, candidates,
        from: w.ex.timestamp);
    final setDiff = set == null
        ? null
        : (set.fold<int>(0, (s, rx) => s + rx.amountSats.abs()) - w.target)
            .abs();
    if (set != null && (single == null || setDiff! < singleDiff)) {
      for (final rx in set) {
        claimed[rx.id] = w.ex.id;
      }
    } else if (single != null) {
      claimed[single.id] = w.ex.id;
    }
  }

  // 3. The wallet's own moves to Bitcoin still without a receive, oldest
  // first: by the dollars that left for them.
  if (receivedUsd == null || byUsd.isEmpty) return claimed;
  final served = claimed.values.toSet();
  final usdOf = <String, double?>{};
  double? valueOf(SparkTransaction rx) =>
      usdOf.putIfAbsent(rx.id, () => receivedUsd(rx));
  byUsd.sort((a, b) => a.ex.timestamp.compareTo(b.ex.timestamp));
  for (final w in byUsd) {
    if (served.contains(w.ex.id)) continue;
    // What the dollars buy, give or take: the fees take a little.
    final aim = w.sentUsd * 0.985;
    SparkTransaction? best;
    var bestDiff = 0.0;
    for (final rx in inbound) {
      if (claimed.containsKey(rx.id)) continue;
      if (!inWindow(rx, w.ex, w.window)) continue;
      final value = valueOf(rx);
      if (value == null || !plausibleDeliveryUsd(value, w.sentUsd)) continue;
      if (w.fieldSats > 0) {
        final ratio = rx.amountSats.abs() / w.fieldSats;
        if (ratio < 0.5 || ratio > 1.25) continue;
      }
      final diff = (value - aim).abs();
      if (best == null ||
          diff < bestDiff - 1e-9 ||
          ((diff - bestDiff).abs() <= 1e-9 &&
              rx.timestamp.difference(w.ex.timestamp).abs() <
                  best.timestamp.difference(w.ex.timestamp).abs())) {
        best = rx;
        bestDiff = diff;
      }
    }
    if (best != null) {
      claimed[best.id] = w.ex.id;
      served.add(w.ex.id);
    }
  }
  return claimed;
}

/// How long after [d] started its legs may land and still be matched by
/// amount: a day for a Circle CCTP move (held for screening, like its
/// dollar twin), the reconciler's window for the wallet's own deliveries,
/// half an hour for a row only a bet-flow tag ties to the wallet.
Duration _deliveryWindow(SwapOrder d, bool own) {
  if (!own) return const Duration(minutes: 30);
  return _isCctp(d) ? kOwnCctpDeliveryArrivalWindow : kOwnDeliveryArrivalWindow;
}

/// Whether [d] is a Circle CCTP move out of Investing.
bool _isCctp(SwapOrder d) =>
    (d.routeVersion ?? '').startsWith('hypercore_cctp_to_');

/// The row among [exchanges] that [link] names: by the id it had when it
/// was matched, by the order its quote became, or by its settlement
/// operation. Only a row delivering bitcoin; null when it is not listed.
SwapOrderTransaction? _linkedRow(
    OrchestraDeliveryLink link, List<SwapOrderTransaction> exchanges) {
  final order = link.orderId;
  final resolved = order == null ? null : OrchestraOrderIds.resolve(order);
  for (final ex in exchanges) {
    if (ex.details.coinTo.toUpperCase() != 'BTC') continue;
    final op = ex.details.operationId;
    if (ex.id == order ||
        ex.id == resolved ||
        (link.operationId != null && op == link.operationId)) {
      return ex;
    }
  }
  return null;
}

/// A delivery link that crossed over between two of the wallet's rows:
/// [receiveId] is linked to [fromRow] and is the delivery of [toRow].
/// [sats] is the receive's amount, [expectedSats] what [fromRow] said it
/// would deliver when it was matched (null when not recorded).
typedef CrossedDeliveryLink = ({
  String receiveId,
  String fromRow,
  String toRow,
  int sats,
  int? expectedSats,
});

/// The links among [links] that name the wrong row of two deliveries
/// landing close together (a Swap paid from two places): the receive is
/// linked to one row, and
///
///  * it is not what that row said it would deliver when it was matched
///    (more than two percent off the recorded expectation), and that row's
///    linked receives do not add up to the expectation either (a payout
///    split across transfers is left alone);
///  * another listed row [owns] says is the wallet's delivers bitcoin to
///    Spark, has a figure, has no receive linked to it, and the receive is
///    that figure within two percent, inside that row's window
///    ([kOwnDeliveryEarlyMargin] before it to [kOwnDeliveryArrivalWindow]
///    after it, a day for a Circle CCTP leg);
///  * no unlinked receive in that window fits that row as well (as close
///    in amount and no further from it in time): it really is without its
///    delivery.
///
/// A row takes one crossed receive at most, the closest amount first. An
/// exact figure on a row with nothing else to show for it is as tight as
/// amount and time get; a receive from outside is never touched by this
/// (only receives the reconciler already linked are read). Pure, so
/// Activity and the reconciler read the same answer.
List<CrossedDeliveryLink> crossedDeliveryLinks(
  List<SwapOrderTransaction> exchanges,
  Iterable<SparkTransaction> receives, {
  required Map<String, OrchestraDeliveryLink> links,
  bool Function(SwapOrderTransaction ex)? owns,
}) {
  if (links.isEmpty || exchanges.length < 2) return const [];
  final inbound = [
    for (final rx in receives)
      if (rx.type == TransactionType.received && !isOnChainDeposit(rx)) rx,
  ];
  // Each linked receive's row, and what every row has linked to it.
  final rowOf = <String, SwapOrderTransaction>{};
  final linkedSum = <String, int>{};
  final expectedOf = <String, int>{};
  for (final rx in inbound) {
    final link = links[rx.id];
    if (link == null) continue;
    final ex = _linkedRow(link, exchanges);
    if (ex == null) continue;
    rowOf[rx.id] = ex;
    linkedSum[ex.id] = (linkedSum[ex.id] ?? 0) + rx.amountSats.abs();
    final expected = link.expectedSats;
    if (expected != null && expected > (expectedOf[ex.id] ?? 0)) {
      expectedOf[ex.id] = expected;
    }
  }
  if (rowOf.isEmpty) return const [];
  // The rows without any receive that know what they delivered.
  final bare = <({SwapOrderTransaction ex, int sats, Duration window})>[];
  for (final ex in exchanges) {
    final d = ex.details;
    if (d.coinTo.toUpperCase() != 'BTC') continue;
    final to = d.networkTo.toUpperCase();
    if (to != 'SPARK' && to != 'LIGHTNING') continue;
    if (OwnSparkArrivals.failedStatuses.contains(d.status)) continue;
    if (linkedSum.containsKey(ex.id)) continue;
    final sats = orchestraBtcFieldToSats(d.withdrawalAmount);
    if (sats <= 0) continue;
    if (owns != null && !owns(ex)) continue;
    bare.add((
      ex: ex,
      sats: sats,
      window:
          _isCctp(d) ? kOwnCctpDeliveryArrivalWindow : kOwnDeliveryArrivalWindow,
    ));
  }
  if (bare.isEmpty) return const [];
  bool inWindow(SparkTransaction rx, SwapOrderTransaction ex, Duration w) {
    final delta = rx.timestamp.difference(ex.timestamp);
    return delta >= -kOwnDeliveryEarlyMargin && delta <= w;
  }

  final pairs = <({SparkTransaction rx, SwapOrderTransaction to, int diff})>[];
  for (final rx in inbound) {
    final from = rowOf[rx.id];
    if (from == null) continue;
    final sats = rx.amountSats.abs();
    final expected = expectedOf[from.id];
    if (expected != null) {
      final tight = tightDeliveryTolerance(expected);
      // It is what its row was waiting for, alone or with its other legs.
      if ((sats - expected).abs() <= tight) continue;
      if ((linkedSum[from.id]! - expected).abs() <= tight) continue;
    }
    for (final b in bare) {
      if (b.ex.id == from.id) continue;
      final diff = (sats - b.sats).abs();
      final tight = tightDeliveryTolerance(b.sats);
      if (diff > tight || !inWindow(rx, b.ex, b.window)) continue;
      // The row has a receive of its own to claim, as close in amount
      // and no further from it in time: nothing crossed over.
      final gap = rx.timestamp.difference(b.ex.timestamp).abs();
      final hasOwn = inbound.any((other) =>
          other.id != rx.id &&
          !rowOf.containsKey(other.id) &&
          (other.amountSats.abs() - b.sats).abs() <= diff &&
          inWindow(other, b.ex, b.window) &&
          other.timestamp.difference(b.ex.timestamp).abs() <= gap);
      if (hasOwn) continue;
      pairs.add((rx: rx, to: b.ex, diff: diff));
    }
  }
  pairs.sort((a, b) => a.diff.compareTo(b.diff));
  final out = <CrossedDeliveryLink>[];
  final taken = <String>{};
  final moved = <String>{};
  for (final p in pairs) {
    if (moved.contains(p.rx.id) || !taken.add(p.to.id)) continue;
    moved.add(p.rx.id);
    final from = rowOf[p.rx.id]!;
    out.add((
      receiveId: p.rx.id,
      fromRow: from.id,
      toRow: p.to.id,
      sats: p.rx.amountSats.abs(),
      expectedSats: expectedOf[from.id],
    ));
  }
  return out;
}

/// One of the wallet's deliveries to Bitcoin that knows its figure and has
/// no receive linked to it yet: the row, the figure in sats, when the row
/// started and how long after that its receive may land.
typedef OwnDeliveryFigure = ({
  String rowId,
  int sats,
  DateTime rowAt,
  Duration window,
});

/// [e] as an [OwnDeliveryFigure], or null when it is not one: an Orchestra
/// row delivering bitcoin to Spark that did not fail, is not a send to
/// someone else, has a figure, and that no receive is linked to ([linked]:
/// the row ids and operations the reconciler's links name).
OwnDeliveryFigure? ownDeliveryFigureOf(SwapOrder e,
    {required Set<String> linked}) {
  if (!e.isOrchestra ||
      e.coinTo.toUpperCase() != 'BTC' ||
      e.networkTo.toUpperCase() != 'SPARK' ||
      e.activityDirection == 'send' ||
      OwnSparkArrivals.failedStatuses.contains(e.status)) {
    return null;
  }
  if (linked.contains(e.id) ||
      (e.operationId != null && linked.contains(e.operationId))) {
    return null;
  }
  final sats = orchestraBtcFieldToSats(e.withdrawalAmount);
  if (sats <= 0) return null;
  return (
    rowId: e.id,
    sats: sats,
    rowAt: DateTime.fromMillisecondsSinceEpoch(e.timestamp),
    window:
        _isCctp(e) ? kOwnCctpDeliveryArrivalWindow : kOwnDeliveryArrivalWindow,
  );
}

/// The receives among [receives] the delivery reconciler must not settle
/// row [rowId] on (waiting for [targetSats], 0 when its figure is not
/// known), because another of the wallet's own deliveries ([others]) has
/// the better claim: the receive landed in that row's window, is within
/// ten percent of its figure (the band an estimate is held to), and is
/// closer to it, in proportion, than to [targetSats].
///
/// Without this a leg still on its way was settled on its sibling's
/// receive: the reconciler takes, for a row with no closer match, the
/// receive within half to five quarters of its figure (a first leg of a
/// split payout), and two legs of one Swap land within the minute. The
/// leg then read the sibling's amount and "Completed" before its money
/// arrived, and its own delivery stood beside the move as "Received ₿".
/// Pure.
Set<String> receivesSpokenFor({
  required String rowId,
  required int targetSats,
  required Iterable<OwnDeliveryFigure> others,
  required Iterable<SparkTransaction> receives,
}) {
  final spoken = <String>{};
  for (final rx in receives) {
    final sats = rx.amountSats.abs();
    if (sats <= 0) continue;
    for (final o in others) {
      if (o.rowId == rowId || o.sats <= 0) continue;
      final delta = rx.timestamp.difference(o.rowAt);
      if (delta < -kOwnDeliveryEarlyMargin || delta > o.window) continue;
      final theirs = (sats - o.sats).abs();
      if (theirs > math.max(1, (o.sats * 0.10).round())) continue;
      if (targetSats <= 0 ||
          theirs / o.sats < (sats - targetSats).abs() / targetSats) {
        spoken.add(rx.id);
        break;
      }
    }
  }
  return spoken;
}

/// The delivery reconciler's pick of the receives among [receives] that
/// settle a row stamped [rowAt] waiting for [targetSats] (0 when its
/// figure is not known yet): those landing from two minutes before the row
/// to [window] after it ([kOwnDeliveryArrivalWindow]; a Circle CCTP leg
/// passes its day), then
///
///  * one receive within two percent of the figure;
///  * else the set of two to [kMaxDeliveryLegs] receives adding up to it
///    within ten percent (a payout split across transfers);
///  * else, when [band] (an estimate not yet split into legs), the receive
///    closest in time within half to five quarters of the figure: a first
///    leg of a split payout settles the row and the rest follows it
///    (the link keeps the figure it was matched against);
///  * with no figure and the dollars that left for the row known
///    ([sentUsd]), the receive whose dollar value when it landed
///    ([receivedUsd]) is what those dollars buy ([plausibleDeliveryUsd]),
///    the closest value first, then the closest time: never just any
///    receive, which settled a CCTP leg on another leg's delivery or on
///    money from outside (and left its own delivery listed beside it);
///  * with no figure and no dollars to go by, the receive closest in time.
///
/// Null when nothing qualifies. Pure, so the reconciler and its tests read
/// the same answer.
List<SparkTransaction>? reconcilerDeliveryLegs({
  required int targetSats,
  required DateTime rowAt,
  required List<SparkTransaction> receives,
  bool band = true,
  Duration window = kOwnDeliveryArrivalWindow,
  double? sentUsd,
  ReceivedUsd? receivedUsd,
}) {
  final candidates = [
    for (final rx in receives)
      if (rx.amountSats > 0 &&
          !isOnChainDeposit(rx) &&
          !rx.timestamp.isBefore(rowAt.subtract(const Duration(minutes: 2))) &&
          !rx.timestamp.isAfter(rowAt.add(window)))
        rx,
  ];
  if (candidates.isEmpty) return null;
  int deltaOf(SparkTransaction rx) =>
      rx.timestamp.difference(rowAt).inMilliseconds.abs();
  SparkTransaction? closest(bool Function(SparkTransaction rx) ok) {
    SparkTransaction? best;
    for (final rx in candidates) {
      if (!ok(rx)) continue;
      if (best == null || deltaOf(rx) < deltaOf(best)) best = rx;
    }
    return best;
  }

  if (targetSats <= 0) {
    if (sentUsd != null && sentUsd > 0 && receivedUsd != null) {
      final aim = sentUsd * 0.985;
      SparkTransaction? best;
      var bestDiff = 0.0;
      for (final rx in candidates) {
        final value = receivedUsd(rx);
        if (value == null || !plausibleDeliveryUsd(value, sentUsd)) continue;
        final diff = (value - aim).abs();
        if (best == null ||
            diff < bestDiff - 1e-9 ||
            ((diff - bestDiff).abs() <= 1e-9 && deltaOf(rx) < deltaOf(best))) {
          best = rx;
          bestDiff = diff;
        }
      }
      return best == null ? null : [best];
    }
    final any = closest((_) => true);
    return any == null ? null : [any];
  }
  final tight = tightDeliveryTolerance(targetSats);
  SparkTransaction? exact;
  var exactDiff = 0;
  for (final rx in candidates) {
    final diff = (rx.amountSats - targetSats).abs();
    if (diff > tight) continue;
    if (exact == null ||
        diff < exactDiff ||
        (diff == exactDiff && deltaOf(rx) < deltaOf(exact))) {
      exact = rx;
      exactDiff = diff;
    }
  }
  if (exact != null) return [exact];
  final set = matchDeliveryLegSet(
      targetSats, math.max(1, (targetSats * 0.10).round()), candidates,
      from: rowAt);
  if (set != null) return set;
  if (!band) return null;
  final inBand = closest((rx) {
    final ratio = rx.amountSats / targetSats;
    return ratio >= 0.5 && ratio <= 1.25;
  });
  return inBand == null ? null : [inBand];
}
