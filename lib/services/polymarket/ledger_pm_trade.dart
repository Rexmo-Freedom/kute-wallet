import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_amounts.dart';

enum LedgerPmTradeRefusal {
  accountUnavailable,
  marketChanged,
  cashUnavailable,
  insufficientCash,
  allowanceRequired,
  /// The book cannot fill this market order within its price cap. Refused
  /// before the device is asked, instead of a FOK dying at the venue.
  liquidityUnavailable,
  /// The book moved past the signed maximum price between the review and
  /// the post ([LedgerPmTradeRefused.price] is where it went). Nothing was
  /// submitted.
  priceMoved,
}

class LedgerPmTradeRefused implements Exception {
  const LedgerPmTradeRefused(this.reason,
      {this.price, this.limit, this.retryPrice});
  final LedgerPmTradeRefusal reason;

  /// For [LedgerPmTradeRefusal.priceMoved]: the price the whole stake
  /// costs now, the signed maximum it passed, and the maximum a new
  /// review would name (polymarketBuyCap).
  final double? price, limit, retryPrice;
}

/// Exact decimal parsing for amounts read from the CLOB. Missing or malformed
/// values never become zero, and reservations round up rather than down.
BigInt ledgerPmDecimalUnits(Object? value, {int decimals = 6}) {
  if (decimals < 1) throw ArgumentError.value(decimals, 'decimals');
  final raw = value?.toString() ?? '';
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) {
    throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
  }
  final parts = raw.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals &&
      fraction.substring(decimals).contains(RegExp('[1-9]'))) {
    throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
  }
  return BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(fraction.padRight(decimals, '0').substring(0, decimals));
}

BigInt _integer(Object? value) {
  final raw = value?.toString() ?? '';
  if (!RegExp(r'^\d+$').hasMatch(raw)) {
    throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
  }
  return BigInt.parse(raw);
}

class LedgerPmBuyingPower {
  LedgerPmBuyingPower({
    required this.balance,
    required this.reserved,
    required Map<String, BigInt> allowances,
  }) : allowances = Map.unmodifiable(allowances);

  final BigInt balance;
  final BigInt reserved;

  /// pUSD allowances the CLOB reported, by lowercase spender address.
  final Map<String, BigInt> allowances;

  BigInt get spendable => balance > reserved ? balance - reserved : BigInt.zero;

  /// The pUSD the CLOB lets an order of this kind spend. A neg-risk order
  /// is checked against the Neg Risk Exchange AND the CLOB v1 Neg Risk
  /// Adapter (it refuses with "spender: 0xd91E…, allowance: 0" otherwise),
  /// so it is the smaller of the two. A spender the CLOB did not report
  /// counts as zero.
  BigInt allowance(bool negRisk) {
    BigInt of(String spender) =>
        allowances[spender.toLowerCase()] ?? BigInt.zero;
    if (!negRisk) return of(PolymarketConstants.exchangeAddress);
    final exchange = of(PolymarketConstants.negRiskExchangeAddress);
    final adapter = of(PolymarketConstants.legacyNegRiskAdapterAddress);
    return exchange < adapter ? exchange : adapter;
  }

  factory LedgerPmBuyingPower.fromClob({
    required String depositWallet,
    required Map<String, dynamic> collateral,
    required List<Map<String, dynamic>> orders,
  }) {
    final allowances = <String, BigInt>{};
    final rawAllowances = collateral['allowances'];
    if (rawAllowances is! Map) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
    }
    for (final entry in rawAllowances.entries) {
      final address = entry.key.toString().toLowerCase();
      if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(address) ||
          allowances.containsKey(address)) {
        throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
      }
      allowances[address] = _integer(entry.value);
    }
    var reserved = BigInt.zero;
    final seen = <String>{};
    final scale = BigInt.from(1000000);
    for (final order in orders) {
      final id = order['id']?.toString();
      final maker = order['maker_address']?.toString();
      final side = order['side']?.toString().toUpperCase();
      if (id == null ||
          !seen.add(id) ||
          !sameEvmAddress(maker ?? '', depositWallet) ||
          (side != 'BUY' && side != 'SELL')) {
        throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
      }
      if (side != 'BUY') continue;
      final original = ledgerPmDecimalUnits(order['original_size']);
      final matched = ledgerPmDecimalUnits(order['size_matched']);
      final price = ledgerPmDecimalUnits(order['price']);
      if (matched > original || price <= BigInt.zero || price >= scale) {
        throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
      }
      reserved += ((original - matched) * price + scale - BigInt.one) ~/ scale;
    }
    return LedgerPmBuyingPower(
      balance: _integer(collateral['balance']),
      reserved: reserved,
      allowances: allowances,
    );
  }
}

class LedgerPmMarketRules {
  const LedgerPmMarketRules({
    required this.tokenId,
    required this.conditionId,
    required this.tickSize,
    required this.minShares,
    required this.negRisk,
    this.asks = const [],
  });

  final String tokenId;
  final String conditionId;
  final String tickSize;
  final BigInt minShares;
  final bool negRisk;

  /// Executable asks, cheapest first, as (price, shares). REST books are
  /// not best-first, so they are sorted at read time like the hot wallet's.
  final List<(double, double)> asks;

  /// The marginal ask a market buy of [budgetUsd] reaches walking the
  /// book, or null when the book cannot absorb the whole stake.
  double? depthPriceFor(double budgetUsd) {
    if (!budgetUsd.isFinite || budgetUsd <= 0 || asks.isEmpty) return null;
    var remaining = budgetUsd;
    for (final (price, size) in asks) {
      remaining -= price * size;
      if (remaining <= 0) return price;
    }
    return null;
  }

  /// Checks a market buy of [budgetUsd] signed with a maximum price of
  /// [maxPriceMicros] against this (fresh) book, just before it is sent:
  /// the whole stake must still fill at or under it. Otherwise nothing is
  /// sent: [LedgerPmTradeRefusal.priceMoved] says where the price went and
  /// the maximum a new review would name at [slippagePct].
  void ensureFillsWithin(
      {required double budgetUsd,
      required BigInt maxPriceMicros,
      required double slippagePct}) {
    final depth = depthPriceFor(budgetUsd);
    if (depth == null) {
      throw const LedgerPmTradeRefused(
          LedgerPmTradeRefusal.liquidityUnavailable);
    }
    if (BigInt.from((depth * 1000000).round()) > maxPriceMicros) {
      throw LedgerPmTradeRefused(LedgerPmTradeRefusal.priceMoved,
          price: depth,
          limit: maxPriceMicros.toInt() / 1000000,
          retryPrice: polymarketBuyCap(
              ask: depth,
              slippagePct: slippagePct,
              tick: double.parse(tickSize)));
    }
  }

  bool sameRules(LedgerPmMarketRules other) =>
      tokenId == other.tokenId &&
      conditionId == other.conditionId &&
      tickSize == other.tickSize &&
      minShares == other.minShares &&
      negRisk == other.negRisk;

  PolymarketOrderAmounts amounts({
    required double budgetUsd,
    required double reviewedPrice,
    required bool isLimit,
    required double slippagePct,
  }) {
    if (!budgetUsd.isFinite ||
        budgetUsd <= 0 ||
        budgetUsd > 1000000000 ||
        !reviewedPrice.isFinite ||
        reviewedPrice <= 0 ||
        reviewedPrice >= 1 ||
        !slippagePct.isFinite ||
        slippagePct < 0 ||
        slippagePct > 20) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    final tick = double.parse(tickSize);
    // A market buy's cap follows the hot wallet's rule: the slippage
    // rounded down, with one tick of room at least (polymarketBuyCap).
    final bound = isLimit
        ? reviewedPrice
        : polymarketBuyCap(
            ask: reviewedPrice, slippagePct: slippagePct, tick: tick);
    final amounts = PolymarketOrderAmounts.encode(
      tickSize: tickSize,
      price: bound,
      size: budgetUsd / bound,
      isBuy: true,
      isMarket: !isLimit,
    );
    final budget = BigInt.from((budgetUsd * 1000000).floor());
    if (amounts.maker > budget || amounts.taker < minShares) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    return amounts;
  }
}

class LedgerPmMarketSource {
  LedgerPmMarketSource({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  Future<LedgerPmMarketRules> read(String tokenId, String conditionId) async {
    if (!RegExp(r'^\d+$').hasMatch(tokenId) ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(conditionId)) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    final responses = await Future.wait([
      _client.get(
          Uri.https('clob.polymarket.com', '/book', {'token_id': tokenId})),
      _client.get(Uri.https('clob.polymarket.com', '/markets/$conditionId')),
    ]).timeout(const Duration(seconds: 15));
    if (responses.any((response) => response.statusCode != 200)) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    final book = jsonDecode(responses[0].body) as Map<String, dynamic>;
    final market = jsonDecode(responses[1].body) as Map<String, dynamic>;
    final tokens = market['tokens'];
    if (book['asset_id']?.toString() != tokenId ||
        book['market']?.toString().toLowerCase() != conditionId.toLowerCase() ||
        market['condition_id']?.toString().toLowerCase() !=
            conditionId.toLowerCase() ||
        market['accepting_orders'] != true ||
        market['closed'] != false ||
        book['neg_risk'] is! bool ||
        tokens is! List ||
        !tokens.any((token) =>
            token is Map && token['token_id']?.toString() == tokenId)) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    final tick = book['tick_size']?.toString();
    if (!const {'0.1', '0.01', '0.005', '0.0025', '0.001', '0.0001'}
        .contains(tick)) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    final minShares = ledgerPmDecimalUnits(book['min_order_size']);
    if (minShares <= BigInt.zero) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
    }
    return LedgerPmMarketRules(
        tokenId: tokenId,
        conditionId: conditionId,
        tickSize: tick!,
        minShares: minShares,
        negRisk: book['neg_risk'] as bool,
        asks: parseAsks(book['asks']));
  }

  /// Sorted executable asks from a REST book. Malformed levels are dropped
  /// rather than trusted; a book with no readable ask yields none.
  static List<(double, double)> parseAsks(Object? raw) {
    if (raw is! List) return const [];
    final levels = <(double, double)>[];
    for (final level in raw) {
      if (level is! Map) continue;
      final price = double.tryParse('${level['price']}');
      final size = double.tryParse('${level['size']}');
      if (price == null ||
          size == null ||
          !price.isFinite ||
          !size.isFinite ||
          price <= 0 ||
          price >= 1 ||
          size <= 0) {
        continue;
      }
      levels.add((price, size));
    }
    levels.sort((a, b) => a.$1.compareTo(b.$1));
    return levels;
  }

  void close() => _client.close();
}
