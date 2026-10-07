// A prediction reads the same result in the Predictions activity and in
// the Statistics drill-down: both parse the same `/v2/positions` row, and
// both decide it by prediction_results.dart.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, debugParseOpenPositions, debugParseSettledClosedPositions;
import 'package:kute/screens/shared/activity_row_copy.dart';
import 'package:kute/services/portfolio/portfolio_category_items.dart';
import 'package:kute/services/portfolio/portfolio_performance_service.dart'
    show parsePolymarketPositionsPage;

const _wallet = '0x00000000000000000000000000000000000000aa';
const _betAt = 1759662180;
final _now = DateTime.utc(2026, 10, 7);
final _en = l10nForLanguage('en');

/// One `/v2/positions` row of [token] (its own market), as the venue sends
/// it on either arm.
Map<String, dynamic> _row(
  String token, {
  required double price,
  required double totalSize,
  required double avgPrice,
  double size = 0,
  double realized = 0,
  bool redeemable = false,
}) =>
    {
      'proxy_wallet': _wallet,
      'token_id': token,
      'condition_id': '0x$token',
      'current_size': size,
      'avg_price': avgPrice,
      'entry_cost_usdc': size * avgPrice,
      'current_value': size * price,
      'unrealized_pnl': size * price - size * avgPrice,
      'percent_pnl': 0,
      'total_size': totalSize,
      'realized_pnl': realized,
      'percent_realized_pnl': 0,
      'current_price': price,
      'redeemable': redeemable,
      'mergeable': false,
      'title': 'Market $token',
      'slug': 'market-$token',
      'event_slug': 'event-$token',
      'outcome': 'Up',
      'outcome_index': 0,
      'opposite_outcome': 'Down',
      'opposite_token_id': '$token-down',
      'end_date': '2026-10-05T11:05:00Z',
      'negative_risk': false,
      'first_entry_at': _betAt,
      'last_event_at': _betAt + 600,
    };

Activity _act(String token, String type,
        {String? side, double size = 0, double usdc = 0, int at = _betAt}) =>
    Activity(
      proxyWallet: _wallet,
      timestamp: at,
      conditionId: '0x$token',
      type: type,
      size: size,
      usdcSize: usdc,
      transactionHash: '0x$token$type$at',
      asset: token,
      side: side,
      outcomeIndex: 0,
      title: 'Market $token',
      outcome: 'Up',
    );

void main() {
  test('every position reads the same result in Activity and the drill-down',
      () {
    final open = [
      // Held to a win, not claimed yet.
      _row('heldWon',
          price: 1, totalSize: 5, avgPrice: .6, size: 5, redeemable: true),
      // Held to a loss, never claimed.
      _row('heldLost',
          price: 0, totalSize: 6.3, avgPrice: 3.21 / 6.3, size: 6.3,
          redeemable: true),
      // Resolved at neither 1 nor 0: not decided by price alone.
      _row('heldSplit',
          price: .6, totalSize: 5, avgPrice: .5, size: 5, redeemable: true),
      // Still trading.
      _row('live', price: .6, totalSize: 5, avgPrice: .5, size: 5),
    ];
    final closed = [
      // Held to a win and claimed.
      _row('claimedWon', price: 1, totalSize: 5, avgPrice: .6, realized: 2),
      // Held to a loss.
      _row('closedLost',
          price: 0, totalSize: 6.3, avgPrice: 3.21 / 6.3, realized: -3.21),
      // Sold at 70¢ before the side won.
      _row('soldThenWon', price: 1, totalSize: 10, avgPrice: .5, realized: 2),
      // Sold at 90¢ before the side lost.
      _row('soldThenLost', price: 0, totalSize: 10, avgPrice: .5, realized: 4),
      // Sold while the market still traded.
      _row('soldLive', price: .4, totalSize: 10, avgPrice: .5, realized: -1),
    ];
    final history = <Activity>[
      for (final r in [...open, ...closed])
        _act(r['token_id'] as String, 'TRADE',
            side: 'BUY',
            size: (r['total_size'] as num).toDouble(),
            usdc: ((r['total_size'] as num) * (r['avg_price'] as num))
                .toDouble()),
      _act('claimedWon', 'REDEEM', size: 5, usdc: 5, at: _betAt + 600),
      _act('soldThenWon', 'TRADE',
          side: 'SELL', size: 10, usdc: 7, at: _betAt + 60),
      _act('soldThenLost', 'TRADE',
          side: 'SELL', size: 10, usdc: 9, at: _betAt + 60),
      _act('soldLive', 'TRADE',
          side: 'SELL', size: 10, usdc: 4, at: _betAt + 60),
    ];

    String body(List<Map<String, dynamic>> rows) => jsonEncode({'data': rows});

    // The Predictions activity: the venue's rows plus the result rows.
    final results = predictionResults(
      open: debugParseOpenPositions(body(open)),
      closed: debugParseSettledClosedPositions(body(closed)),
      history: history,
      now: _now,
    );
    final rows = [...history, for (final r in results) r.activity];
    String activity(String token) {
      final mine = rows.where((a) => a.asset == token).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final title = predictionRowCopy(_en, mine.last, time: '').title;
      return title.split(' · ').first;
    }

    // The drill-down: the Statistics records of the same rows.
    final records = [
      ...parsePolymarketPositionsPage({'data': open},
              expectedAddress: _wallet, open: true)
          .records,
      ...parsePolymarketPositionsPage({'data': closed},
              expectedAddress: _wallet, open: false)
          .records,
    ];
    String drill(PredictionLineResult r) => switch (r) {
          PredictionLineResult.won => 'Won',
          PredictionLineResult.lost => 'Lost',
          PredictionLineResult.sold => 'Sold',
          PredictionLineResult.open => 'Prediction',
        };

    final seen = <String, String>{
      for (final r in records)
        r.tokenId: '${activity(r.tokenId)} / ${drill(predictionLineResult(r))}',
    };
    expect(seen, {
      'heldWon': 'Won / Won',
      'heldLost': 'Lost / Lost',
      'heldSplit': 'Prediction / Prediction',
      'live': 'Prediction / Prediction',
      'claimedWon': 'Won / Won',
      'closedLost': 'Lost / Lost',
      'soldThenWon': 'Sold / Sold',
      'soldThenLost': 'Sold / Sold',
      'soldLive': 'Sold / Sold',
    });
  });
}
