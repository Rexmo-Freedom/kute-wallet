// lib/services/polymarket/sell_settlement.dart
//
// What became of a sell order after the CLOB answered the POST.
//
// The POST's answer is not the end of a sale. The venue replies `matched`
// (sold now), `delayed` (a sports market in play holds marketable orders
// for its in-play delay, `seconds_delay`, before matching them; a market
// sell can still be killed when the delay ends), or `live` (a limit sell
// resting on the book, perhaps partly filled). A matched trade then goes
// MATCHED -> MINED -> CONFIRMED on chain, or FAILED / RETRYING.
//
// The sell sheet used to treat anything but an immediate `matched` with
// echoed amounts as unknown: it polled the Data API positions (refreshed
// every other second, cached 5 s, a position moves ~2-8 s after the match)
// for up to 30 s and then closed into "Sale status pending". This reads
// the venue itself instead: the order (`GET /data/order/{id}`: status,
// size_matched, associate_trades) until it has matched or ended, then the
// trades (`GET /data/trades?id=`) until they are on chain.
//
// Measured on 2026-10-05 (public market socket + Polygon receipts + the
// Data API, 40 trades): a match is mined 1.2-3.7 s later (p50 ~1.8 s), and
// the Data API positions show it 2.3-8.4 s after the match (p50 ~5 s). So
// waiting for MINED costs about two seconds and proves the sale landed;
// CONFIRMED (finality) is not awaited, MINED is enough.
//
// A buy is followed the same way ([PmSellSettlementWatcher.watch] with
// `buy: true`): the shares it got and what they cost, from the same reads.
//
// EVERY STAGE HAS ONE WALL-CLOCK DEADLINE (founder, 10 November 2026:
// "what is it confirming? why does it stay confirming on sold?"). Each
// read is cut at what is left of its stage ([matchTimeout] from the POST,
// [confirmTimeout] from the match), the trades are read together, and a
// sleep never runs past the deadline: a read used to wait out its own
// HTTP timeout (an order 15 s, each trade 8 s, one after the other) and
// the deadline was only looked at between polls, so on a slow phone link
// the sell ticket sat on "Sold · confirming" for half a minute.
//
// THE RECEIPT ON THE MATCH ([PmSellSettlementWatcher.receiptOnMatch], the
// sell ticket's): a matched sell is sold, the venue's match. The stage
// ends as soon as the sale's proceeds are known from the venue (the POST's
// echo, at once, or a trade's prices), `confirmedBy` 'matched', and the
// chain is followed after it ([PmSellSettlement.chain]): it speaks only
// if a trade then FAILED.
//
// Read-only: nothing here signs, submits, cancels or retries an order.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// A step the sale reached while it is still in flight.
enum PmSellStage {
  /// The venue is holding the order for a live game's in-play delay.
  delayed,

  /// Shares sold; the trade is on its way on chain.
  matched,
}

enum PmSellResult {
  /// Every share offered was sold.
  filled,

  /// Some shares sold. The rest of a limit sell still rests on the book;
  /// the rest of a market (fill-and-kill) sell was killed and stays held.
  partial,

  /// Nothing sold yet; the whole limit sell rests on the book.
  resting,

  /// Accepted, but nothing matched (a market sell killed when a live
  /// game's delay ended, or a limit sell cancelled before any fill).
  notFilled,

  /// The match did not settle on chain (trade FAILED). Shares stay held.
  failed,

  /// The venue did not say in time what became of the order.
  unknown,
}

class PmSellSettlement {
  const PmSellSettlement({
    required this.result,
    required this.offeredShares,
    required this.soldShares,
    required this.firstStatus,
    required this.confirmedBy,
    required this.timeToMatch,
    this.proceeds,
    this.timeToConfirm,
    this.delayed = false,
    this.chain,
  });

  final PmSellResult result;
  final double offeredShares;

  /// Shares the venue reports sold, or bought for a buy (`makingAmount` /
  /// `takingAmount` or `size_matched`).
  final double soldShares;

  /// USDC received for [soldShares] (paid, for a buy), from the venue's own
  /// figures (the POST's echo or the trades). Null when the venue gave none.
  final double? proceeds;

  /// The POST's status, lowercased ('matched', 'delayed', 'live', '').
  final String firstStatus;

  /// 'mined', 'confirmed', 'position' (the account shows it), 'matched'
  /// (the receipt shown on the venue's match, its proceeds known, the
  /// chain not seen yet: [PmSellSettlementWatcher.receiptOnMatch]),
  /// 'timeout' (matched, the stage's deadline reached first) or 'none'
  /// (nothing sold).
  final String confirmedBy;

  /// From the POST's answer to the match (zero when it matched at once).
  final Duration timeToMatch;

  /// From the match to [confirmedBy]; null when nothing was confirmed.
  final Duration? timeToConfirm;

  /// The venue held the order for a live game's delay.
  final bool delayed;

  /// Matched and not on chain yet when the watch returned
  /// ([confirmedBy] 'matched' or 'timeout', with a receipt on the match):
  /// what the chain then says of the trades, [PmSellResult.failed] when
  /// one FAILED, [PmSellResult.filled] once all are mined, null when it
  /// did not say within [PmSellSettlementWatcher.chainTimeout]. Null when
  /// nothing is left to follow. Never throws.
  final Future<PmSellResult?>? chain;

  double get remainingShares => math.max(0, offeredShares - soldShares);

  /// Average price per share sold, when the proceeds are known.
  double? get averagePrice =>
      proceeds != null && soldShares > 0 ? proceeds! / soldShares : null;

  /// How the order ended, for analytics: exact figures, never ids.
  Map<String, Object> analyticsParams() => {
        'fill_outcome': switch (result) {
          PmSellResult.filled => 'filled',
          PmSellResult.partial => 'partial',
          PmSellResult.resting => 'resting',
          PmSellResult.notFilled => 'not_filled',
          PmSellResult.failed => 'failed_onchain',
          PmSellResult.unknown => 'unknown',
        },
        'order_status': firstStatus.isEmpty ? 'none' : firstStatus,
        'live_delay': delayed,
        'confirmed_by': confirmedBy,
        'time_to_match_ms': timeToMatch.inMilliseconds,
        if (timeToConfirm != null)
          'time_to_confirm_ms': timeToConfirm!.inMilliseconds,
        'shares_filled': (soldShares * 1e6).round() / 1e6,
        if (proceeds != null) 'notional_usd': (proceeds! * 100).round() / 100,
      };
}

/// Watches one accepted sell order until it has sold (and is on chain),
/// rests, or ended without a fill.
class PmSellSettlementWatcher {
  PmSellSettlementWatcher({
    required this.readOrder,
    this.readTrade,
    this.positionMoved,
    this.pollEvery = const Duration(seconds: 1),
    this.matchTimeout = const Duration(seconds: 15),
    this.confirmTimeout = const Duration(seconds: 12),
    this.receiptOnMatch = false,
    this.chainTimeout = const Duration(seconds: 90),
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  })  : _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _now = now ?? DateTime.now;

  /// `GET /data/order/{id}`; null when the venue has no such order (yet).
  final Future<Map<String, dynamic>?> Function(String orderId) readOrder;

  /// `GET /data/trades?id=`; null when unknown. Without it the sale is
  /// confirmed by [positionMoved] or not at all.
  final Future<Map<String, dynamic>?> Function(String tradeId)? readTrade;

  /// True once the account's position reflects the sale.
  final Future<bool> Function()? positionMoved;

  final Duration pollEvery;

  /// How long to wait for a held (delayed) or unreadable order to settle.
  final Duration matchTimeout;

  /// How long to wait, after the match, for the trade to be mined: the
  /// whole stage, wall clock, reads included (see the file header).
  final Duration confirmTimeout;

  /// End the stage after the match as soon as the proceeds are known
  /// ('matched'), and follow the chain after it ([PmSellSettlement.chain]).
  final bool receiptOnMatch;

  /// How long [PmSellSettlement.chain] follows the trades.
  final Duration chainTimeout;

  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  static const _eps = 0.000001;

  static double _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  /// [read], cut at [deadline] (null past it, or on an error).
  Future<T?> _within<T>(Future<T?> Function() read, DateTime deadline) async {
    final left = deadline.difference(_now());
    if (left <= Duration.zero) return null;
    try {
      // Re-typed first: a reader's own non-nullable future cannot take the
      // timeout's null.
      return await read()
          .then<T?>((value) => value)
          .timeout(left, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  /// One poll's pause, never past [deadline].
  Future<void> _pause(DateTime deadline) {
    final left = deadline.difference(_now());
    return _sleep(left < pollEvery ? left : pollEvery);
  }

  static String? orderIdOf(Map<String, dynamic> response) =>
      (response['orderID'] ?? response['orderId'] ?? response['order_id'])
          ?.toString();

  Future<PmSellSettlement> watch({
    required Map<String, dynamic> response,
    required String tokenId,
    required double offeredShares,
    required bool resting,
    bool buy = false,
    void Function(PmSellStage stage, double soldShares)? onStage,
    bool Function()? cancelled,
  }) async {
    final start = _now();
    final orderId = orderIdOf(response)?.toLowerCase();
    final firstStatus = response['status']?.toString().toLowerCase() ?? '';
    // A sell makes shares and takes USDC; a buy makes USDC, takes shares.
    final making = _num(response['makingAmount'] ?? response['making_amount']);
    final taking = _num(response['takingAmount'] ?? response['taking_amount']);
    final echoShares = buy ? taking : making;
    final echoUsdc = buy ? making : taking;
    // A buy can get more shares than it priced at its cap (better prices),
    // so only a sell is bounded by what it offered.
    final echoValid = echoShares.isFinite &&
        echoUsdc.isFinite &&
        echoShares > 0 &&
        echoUsdc > 0 &&
        (buy || echoShares <= offeredShares + _eps);
    final tradeIds = <String>{
      if (response['tradeIDs'] is List)
        for (final t in response['tradeIDs'] as List)
          if (t != null && '$t'.isNotEmpty) '$t',
    };
    var delayed = firstStatus == 'delayed';
    if (delayed) onStage?.call(PmSellStage.delayed, 0);

    // ── Has it matched? ───────────────────────────────────────────────
    double sold;
    var orderStatus = '';
    var settledOrder = false;
    if (firstStatus == 'matched' &&
        echoValid &&
        (!resting || echoShares >= offeredShares - 0.01)) {
      // Sold in full on the POST itself, the venue's own numbers echoed.
      sold = echoShares;
      orderStatus = 'MATCHED';
      settledOrder = true;
    } else {
      sold = 0;
      if (orderId != null && orderId.isNotEmpty) {
        final deadline = start.add(matchTimeout);
        while (_now().isBefore(deadline)) {
          if (cancelled?.call() ?? false) break;
          // Unreachable for a moment, or past the deadline: null.
          final order = await _within(() => readOrder(orderId), deadline);
          if (order != null) {
            orderStatus = order['status']?.toString().toUpperCase() ?? '';
            for (final t in (order['associate_trades'] as List?) ?? const []) {
              if (t != null && '$t'.isNotEmpty) tradeIds.add('$t');
            }
            final matched = _num(order['size_matched']);
            if (orderStatus == 'DELAYED') {
              if (!delayed) {
                delayed = true;
                onStage?.call(PmSellStage.delayed, 0);
              }
            } else if (orderStatus == 'MATCHED') {
              sold = matched > 0 ? matched : _num(order['original_size']);
              settledOrder = true;
              break;
            } else if (orderStatus == 'LIVE') {
              // A limit sell resting (perhaps partly filled) is an answer.
              if (resting) {
                sold = matched;
                settledOrder = true;
                break;
              }
            } else if (const {'CANCELED', 'CANCELLED', 'UNMATCHED', 'EXPIRED'}
                .contains(orderStatus)) {
              sold = matched;
              settledOrder = true;
              break;
            }
          }
          await _pause(deadline);
        }
      }
    }
    final matchedAt = _now();
    final timeToMatch = matchedAt.difference(start);

    if (!settledOrder) {
      return PmSellSettlement(
        result: PmSellResult.unknown,
        offeredShares: offeredShares,
        soldShares: 0,
        firstStatus: firstStatus,
        confirmedBy: 'none',
        timeToMatch: timeToMatch,
        delayed: delayed,
      );
    }
    sold = buy
        ? math.max(0.0, sold)
        : sold.clamp(0.0, offeredShares).toDouble();
    if (sold <= _eps) {
      return PmSellSettlement(
        result: resting && orderStatus == 'LIVE'
            ? PmSellResult.resting
            : PmSellResult.notFilled,
        offeredShares: offeredShares,
        soldShares: 0,
        firstStatus: firstStatus,
        confirmedBy: 'none',
        timeToMatch: timeToMatch,
        delayed: delayed,
      );
    }
    onStage?.call(PmSellStage.matched, sold);

    // ── Is it on chain? ───────────────────────────────────────────────
    // One deadline for the whole stage (see the file header).
    final deadline = matchedAt.add(confirmTimeout);
    final echoProceeds = echoValid && (echoShares - sold).abs() <= 0.01;
    var confirmedBy = 'timeout';
    var failed = false;
    var chainSeen = false;
    double? tradeProceeds;
    while (_now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) break;
      // The receipt on the match: sold, and the venue said for how much.
      if (receiptOnMatch && (echoProceeds || tradeProceeds != null)) {
        confirmedBy = 'matched';
        break;
      }
      if (tradeIds.isEmpty && orderId != null && orderId.isNotEmpty) {
        final order = await _within(() => readOrder(orderId), deadline);
        for (final t in (order?['associate_trades'] as List?) ?? const []) {
          if (t != null && '$t'.isNotEmpty) tradeIds.add('$t');
        }
      }
      final read = readTrade;
      if (read != null && tradeIds.isNotEmpty) {
        final status = await _readTrades(read, tradeIds,
            orderId: orderId, tokenId: tokenId, deadline: deadline);
        if (status.proceeds != null) tradeProceeds = status.proceeds;
        if (status.failed) {
          failed = true;
          break;
        }
        if (status.onChain != null) {
          confirmedBy = status.onChain!;
          chainSeen = true;
          break;
        }
      }
      final moved = positionMoved;
      if (moved != null) {
        final yes = await _within(moved, deadline) ?? false;
        if (yes) {
          confirmedBy = 'position';
          break;
        }
      }
      if (receiptOnMatch && (echoProceeds || tradeProceeds != null)) {
        confirmedBy = 'matched';
        break;
      }
      await _pause(deadline);
    }
    final stopped = cancelled?.call() ?? false;
    if (stopped) confirmedBy = 'none';
    final timeToConfirm =
        confirmedBy == 'none' ? null : _now().difference(matchedAt);

    // Sold and not seen on chain yet: the chain is followed after the
    // receipt, and speaks only if a trade then FAILED.
    final follow = readTrade;
    final Future<PmSellResult?>? chain = receiptOnMatch &&
            !failed &&
            !stopped &&
            !chainSeen &&
            follow != null &&
            (tradeIds.isNotEmpty || (orderId != null && orderId.isNotEmpty))
        ? _followChain(follow,
            tradeIds: tradeIds, orderId: orderId, tokenId: tokenId)
        : null;

    // The proceeds are the venue's: the POST's echo when it describes
    // exactly these shares, else the trades' own prices. Never the limit.
    double? proceeds;
    if (echoValid && (echoShares - sold).abs() <= 0.01) {
      proceeds = echoUsdc;
    } else if (tradeProceeds != null) {
      proceeds = tradeProceeds;
    }

    return PmSellSettlement(
      result: failed
          ? PmSellResult.failed
          : (sold >= offeredShares - 0.01
              ? PmSellResult.filled
              : PmSellResult.partial),
      offeredShares: offeredShares,
      soldShares: sold,
      proceeds: failed ? null : proceeds,
      firstStatus: firstStatus,
      confirmedBy: failed ? 'none' : confirmedBy,
      timeToMatch: timeToMatch,
      timeToConfirm: failed ? null : timeToConfirm,
      delayed: delayed,
      chain: chain,
    );
  }

  /// One read of [ids], together, each cut at [deadline]: whether one
  /// FAILED, whether all are on chain ('mined' or 'confirmed'), and the
  /// proceeds when every trade said them.
  Future<({bool failed, String? onChain, double? proceeds})> _readTrades(
    Future<Map<String, dynamic>?> Function(String) read,
    Set<String> ids, {
    required String? orderId,
    required String tokenId,
    required DateTime deadline,
  }) async {
    final trades = await Future.wait(
        [for (final id in ids) _within(() => read(id), deadline)]);
    final statuses = <String>[];
    double sum = 0;
    var priced = true;
    for (final trade in trades) {
      if (trade == null) {
        statuses.add('');
        priced = false;
        continue;
      }
      statuses.add(trade['status']?.toString().toUpperCase() ?? '');
      final part = orderId == null
          ? null
          : tradeProceedsFor(trade, orderId: orderId, tokenId: tokenId);
      if (part == null) {
        priced = false;
      } else {
        sum += part;
      }
    }
    return (
      failed: statuses.contains('FAILED'),
      onChain: statuses.isNotEmpty &&
              statuses.every((s) => s == 'MINED' || s == 'CONFIRMED')
          ? (statuses.every((s) => s == 'CONFIRMED') ? 'confirmed' : 'mined')
          : null,
      proceeds: priced && sum > 0 ? sum : null,
    );
  }

  /// After a receipt on the match: the trades read until all are mined
  /// ([PmSellResult.filled]), one FAILED ([PmSellResult.failed]), or
  /// [chainTimeout] passes (null). Never throws.
  Future<PmSellResult?> _followChain(
    Future<Map<String, dynamic>?> Function(String) read, {
    required Set<String> tradeIds,
    required String? orderId,
    required String tokenId,
  }) async {
    final ids = {...tradeIds};
    final deadline = _now().add(chainTimeout);
    try {
      while (_now().isBefore(deadline)) {
        if (ids.isEmpty && orderId != null && orderId.isNotEmpty) {
          final order = await _within(() => readOrder(orderId), deadline);
          for (final t in (order?['associate_trades'] as List?) ?? const []) {
            if (t != null && '$t'.isNotEmpty) ids.add('$t');
          }
        }
        if (ids.isNotEmpty) {
          final status = await _readTrades(read, ids,
              orderId: orderId, tokenId: tokenId, deadline: deadline);
          if (status.failed) return PmSellResult.failed;
          if (status.onChain != null) return PmSellResult.filled;
        }
        await _pause(deadline);
      }
    } catch (_) {}
    return null;
  }

  /// USDC one trade paid [orderId] for selling [tokenId], from the trade's
  /// own matched amounts and prices. As the taker the order was matched
  /// against `maker_orders`: a maker buying the same outcome pays its price,
  /// a maker selling the other outcome (a merge) leaves 1 - its price. As a
  /// maker, its own entry in `maker_orders` says what it sold and at what.
  /// A buy is the mirror (a maker selling the same outcome is paid its
  /// price; a maker buying the other outcome, a mint, leaves 1 - its
  /// price), so the same sum is what a buy paid. Null when the trade does
  /// not say.
  static double? tradeProceedsFor(Map<String, dynamic> trade,
      {required String orderId, required String tokenId}) {
    final id = orderId.toLowerCase();
    final makers = (trade['maker_orders'] as List?) ?? const [];
    final taker = trade['taker_order_id']?.toString().toLowerCase();
    double sum = 0;
    if (taker == id) {
      if (makers.isEmpty) {
        final size = _num(trade['size']), price = _num(trade['price']);
        return size > 0 && price > 0 ? size * price : null;
      }
      for (final m in makers) {
        if (m is! Map) return null;
        final amount = _num(m['matched_amount']);
        final price = _num(m['price']);
        if (amount <= 0 || price <= 0 || price >= 1) return null;
        final sameOutcome = m['asset_id']?.toString() == tokenId;
        sum += amount * (sameOutcome ? price : 1 - price);
      }
      return sum > 0 ? sum : null;
    }
    var found = false;
    for (final m in makers) {
      if (m is! Map || m['order_id']?.toString().toLowerCase() != id) continue;
      final amount = _num(m['matched_amount']);
      final price = _num(m['price']);
      if (amount <= 0 || price <= 0) return null;
      sum += amount * price;
      found = true;
    }
    return found ? sum : null;
  }
}

/// The in-play order delay, in seconds, of the market [conditionId] while
/// its game is on; 0 when it has none or the game has not started. Read
/// from the CLOB's market record (`sd`, `gst`). Never throws.
Future<int> pmLiveOrderDelaySeconds(String conditionId,
    {http.Client? client, DateTime? now}) async {
  if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(conditionId)) return 0;
  final own = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse('https://clob.polymarket.com/clob-markets/$conditionId'))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return 0;
    final body = jsonDecode(response.body);
    if (body is! Map) return 0;
    final delay = PmSellSettlementWatcher._num(body['sd']).round();
    if (delay <= 0) return 0;
    final start = DateTime.tryParse('${body['gst'] ?? ''}');
    if (start == null || start.isAfter(now ?? DateTime.now())) return 0;
    return delay;
  } catch (_) {
    return 0;
  } finally {
    if (own) c.close();
  }
}
