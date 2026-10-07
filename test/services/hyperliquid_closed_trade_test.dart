import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid_closed_trade.dart';

HlFill fill(int id, double start, double size, String side, double pnl,
        {String token = 'USDC', bool liquidated = false}) =>
    HlFill.fromJson({
      'coin': 'BTC',
      'px': '100',
      'sz': '$size',
      'side': side,
      'time': id * 1000,
      'closedPnl': '$pnl',
      'fee': '1',
      'builderFee': '.5',
      'feeToken': token,
      'oid': id,
      'tid': id,
      'hash': 'x',
      'startPosition': '$start',
      'dir': start == 0 ? 'Open Long' : 'Close Long',
      if (liquidated) 'liquidation': {},
    });
void main() {
  test('complete lifecycle includes opening and partial-close fees once', () {
    final fills = [
      fill(1, 0, 2, 'B', 0),
      fill(2, 2, 1, 'A', 10),
      fill(3, 1, 1, 'A', 20)
    ];
    final trade = HlClosedTrade.fromFills(fills.reversed.toList(), fills.last)!;
    expect(trade.gross, 30);
    expect(trade.fees, 3);
    expect(trade.net(-2), 25);
    expect(trade.net(2), 29);
    expect(HlClosedTrade.fromFills(fills, fills[1]), isNull);
  });
  test(
      'missing opening, gaps, unsupported fees and liquidation stay provisional',
      () {
    final close = fill(3, 1, 1, 'A', 20);
    expect(HlClosedTrade.fromFills([close], close), isNull);
    expect(
        HlClosedTrade.fromFills([fill(1, 0, 2, 'B', 0), close], close), isNull);
    final bad = fill(3, 1, 1, 'A', 20, token: 'BTC');
    expect(HlClosedTrade.fromFills([fill(1, 0, 1, 'B', 0), bad], bad), isNull);
    final liquidation = fill(3, 1, 1, 'A', 20, liquidated: true);
    expect(
        HlClosedTrade.fromFills(
            [fill(1, 0, 1, 'B', 0), liquidation], liquidation),
        isNull);
  });
  test('short lifecycle works and missing fee data cannot create a win', () {
    final open = fill(1, 0, 1, 'A', 0);
    final close = fill(2, -1, 1, 'B', 4);
    expect(HlClosedTrade.fromFills([open, close], close)!.net(-1), 1);
    final unknownFee = HlFill.fromJson({
      'coin': 'BTC', 'sz': '1', 'side': 'B', 'time': 2000,
      'startPosition': '-1', 'closedPnl': '4', 'feeToken': 'USDC',
      'tid': 2, 'dir': 'Close Short',
    });
    expect(HlClosedTrade.fromFills([open, unknownFee], unknownFee), isNull);
  });
  test('funding includes only matching coin with signed cash', () async {
    final model = HyperliquidModel(client: MockClient((r) async {
      final body = jsonDecode(r.body);
      expect(body['startTime'], 1000);
      expect(body['endTime'], 4000);
      return http.Response(
          jsonEncode([
            {
              'time': 2000,
              'delta': {'type': 'funding', 'coin': 'BTC', 'usdc': '-2'}
            },
            {
              'time': 3000,
              'delta': {'type': 'funding', 'coin': 'BTC', 'usdc': '1'}
            },
            {
              'time': 3000,
              'delta': {'type': 'funding', 'coin': 'ETH', 'usdc': '50'}
            },
          ]),
          200);
    }));
    expect(await model.getTradeFunding('wallet', 'BTC', 1000, 4000), -1);
  });
  test('truncated and boundary-ambiguous funding is not labeled net profit',
      () async {
    for (final data in [
      List.filled(500, {}),
      [
        {
          'time': 1000,
          'delta': {'type': 'funding', 'coin': 'BTC', 'usdc': '1'}
        }
      ]
    ]) {
      final model = HyperliquidModel(
          client:
              MockClient((_) async => http.Response(jsonEncode(data), 200)));
      await expectLater(model.getTradeFunding('wallet', 'BTC', 1000, 4000),
          throwsFormatException);
    }
  });
}
