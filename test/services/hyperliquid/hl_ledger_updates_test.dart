// The Investing account's cash moving outside trading (a deposit
// credited, a withdrawal) arrives on the user socket as
// `userNonFundingLedgerUpdates`: the history frame at subscribe time is
// marked as a snapshot (never news), the live frames are not.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

void main() {
  test('ledger frames decode with their snapshot flag and update count',
      () async {
    final ws = HyperliquidWebSocket(url: 'wss://example.invalid');
    addTearDown(ws.dispose);
    final got = <HlLedgerUpdatesMessage>[];
    final sub = ws.messages.listen((m) {
      if (m is HlLedgerUpdatesMessage) got.add(m);
    }, onError: (Object _) {});
    addTearDown(sub.cancel);

    ws.debugReceive('{"channel":"userNonFundingLedgerUpdates","data":'
        '{"isSnapshot":true,"user":"0xabc","nonFundingLedgerUpdates":'
        '[{"time":1,"hash":"0x1","delta":{"type":"deposit","usdc":"5.0"}},'
        '{"time":2,"hash":"0x2","delta":{"type":"withdraw","usdc":"1.0"}}]}}');
    ws.debugReceive('{"channel":"userNonFundingLedgerUpdates","data":'
        '{"user":"0xabc","nonFundingLedgerUpdates":'
        '[{"time":3,"hash":"0x3","delta":{"type":"send","usdc":"11.2"}}]}}');
    // Malformed frames are dropped.
    ws.debugReceive('{"channel":"userNonFundingLedgerUpdates","data":[]}');
    await Future<void>.delayed(Duration.zero);

    expect(got, hasLength(2));
    expect(got[0].isSnapshot, isTrue);
    expect(got[0].count, 2);
    expect(got[1].isSnapshot, isFalse);
    expect(got[1].count, 1);
  });
}
