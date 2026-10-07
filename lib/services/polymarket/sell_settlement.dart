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

  /// Some shares sold; the rest of a limit sell still rests on the book.
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

  /// 'mined', 'confirmed', 'position' (the account shows it), 'timeout'
  /// (matched, chain not seen in time) or 'none' (nothing sold).
  final String confirmedBy;

  /// From the POST's answer to the match (zero when it matched at once).
  final Duration timeToMatch;

  /// From the match to [confirmedBy]; null when nothing was confirmed.
  final Duration? timeToConfirm;

  /// The venue held the order for a live game's delay.
  final bool delayed;

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

  /// How long to wait, after the match, for the trade to be mined.
  final Duration confirmTimeout;

  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  static const _eps = 0.000001;

  static double _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
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
        while (_now().difference(start) < matchTimeout) {
          if (cancelled?.call() ?? false) break;
          Map<String, dynamic>? order;
          try {
            order = await readOrder(orderId);
          } catch (_) {
            order = null; // Unreachable for a moment; ask again.
          }
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
          await _sleep(pollEvery);
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
    var confirmedBy = 'timeout';
    var failed = false;
    double? tradeProceeds;
    while (_now().difference(matchedAt) < confirmTimeout) {
      if (cancelled?.call() ?? false) break;
      if (tradeIds.isEmpty && orderId != null && orderId.isNotEmpty) {
        try {
          final order = await readOrder(orderId);
          for (final t in (order?['associate_trades'] as List?) ?? const []) {
            if (t != null && '$t'.isNotEmpty) tradeIds.add('$t');
          }
        } catch (_) {}
      }
      final read = readTrade;
      if (read != null && tradeIds.isNotEmpty) {
        final statuses = <String>[];
        double sum = 0;
        var priced = true;
        for (final id in tradeIds) {
          Map<String, dynamic>? trade;
          try {
            trade = await read(id);
          } catch (_) {
            trade = null;
          }
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
        if (priced && sum > 0) tradeProceeds = sum;
        if (statuses.contains('FAILED')) {
          failed = true;
          break;
        }
        if (statuses.every((s) => s == 'MINED' || s == 'CONFIRMED')) {
          confirmedBy = statuses.every((s) => s == 'CONFIRMED')
              ? 'confirmed'
              : 'mined';
          break;
        }
      }
      final moved = positionMoved;
      if (moved != null) {
        var yes = false;
        try {
          yes = await moved();
        } catch (_) {}
        if (yes) {
          confirmedBy = 'position';
          break;
        }
      }
      await _sleep(pollEvery);
    }
    if (cancelled?.call() ?? false) confirmedBy = 'none';
    final timeToConfirm =
        confirmedBy == 'none' ? null : _now().difference(matchedAt);

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
              : (resting ? PmSellResult.partial : PmSellResult.filled)),
      offeredShares: offeredShares,
      soldShares: sold,
      proceeds: failed ? null : proceeds,
      firstStatus: firstStatus,
      confirmedBy: failed ? 'none' : confirmedBy,
      timeToMatch: timeToMatch,
      timeToConfirm: failed ? null : timeToConfirm,
      delayed: delayed,
    );
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
