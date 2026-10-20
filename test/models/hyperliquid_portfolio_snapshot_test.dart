// An Investing account read (a deposit's credit, the slip's order) asks
// the main account and the builder dexes at once, not one after the other,
// and still fails whole when either half fails.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';

void main() {
  Map<String, dynamic> clearinghouse(double withdrawable) => {
        'marginSummary': {
          'accountValue': '$withdrawable',
          'totalMarginUsed': '0',
          'totalNtlPos': '0',
          'totalRawUsd': '$withdrawable',
        },
        'crossMarginSummary': {
          'accountValue': '$withdrawable',
          'totalMarginUsed': '0',
          'totalNtlPos': '0',
          'totalRawUsd': '$withdrawable',
        },
        'withdrawable': '$withdrawable',
        'assetPositions': [],
      };

  ({MockClient client, List<String> calls, Completer<void> mainHeld})
      venue({bool failMain = false}) {
    final calls = <String>[];
    final mainHeld = Completer<void>();
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final type = body['type'] as String;
      final dex = body['dex'] as String?;
      calls.add(dex == null ? type : '$type:$dex');
      switch (type) {
        case 'clearinghouseState':
          if (dex == null) {
            await mainHeld.future;
            if (failMain) return http.Response('down', 500);
            return http.Response(jsonEncode(clearinghouse(10)), 200);
          }
          return http.Response(jsonEncode(clearinghouse(2)), 200);
        case 'spotClearinghouseState':
          return http.Response(jsonEncode({'balances': []}), 200);
        case 'perpDexs':
          return http.Response(
              jsonEncode([
                null,
                {'name': 'xyz', 'fullName': 'XYZ'},
              ]),
              200);
        case 'meta':
          return http.Response(
              jsonEncode({'universe': [], 'collateralToken': 0}), 200);
      }
      return http.Response('[]', 200);
    });
    return (client: client, calls: calls, mainHeld: mainHeld);
  }

  test('the builder dexes are read while the main account is still out',
      () async {
    final v = venue();
    final model = HyperliquidModel(client: v.client);
    final read = model.getPortfolioSnapshot('0xabc');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(v.calls, contains('clearinghouseState:xyz'),
        reason: 'the dex read did not wait for the main account');
    v.mainHeld.complete();
    final snap = await read;
    expect(snap.withdrawable, 12);
  });

  test('a main account read that fails fails the whole snapshot', () async {
    final v = venue(failMain: true);
    final model = HyperliquidModel(client: v.client);
    final read = model.getPortfolioSnapshot('0xabc');
    v.mainHeld.complete();
    await expectLater(read, throwsA(anything));
  });
}
