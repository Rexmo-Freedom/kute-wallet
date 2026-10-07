// Frames of the CLOB market socket read into messages, on whichever
// isolate reads them (a big opening dump is read off the UI isolate).

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

Map<String, Object?> _book(String token) => {
      'event_type': 'book',
      'asset_id': token,
      'market': 'm',
      'timestamp': '1',
      'hash': 'h',
      'bids': [
        {'price': '0.40', 'size': '5'}
      ],
      'asks': [
        {'price': '0.44', 'size': '5'}
      ],
    };

void main() {
  test('an opening dump: one book per token, in order', () async {
    final frame = jsonEncode([for (var i = 0; i < 300; i++) _book('t$i')]);
    expect(frame.length, greaterThan(64 * 1024 ~/ 4));
    final here = polymarketWsMessagesOf(frame);
    final there = await Isolate.run(() => polymarketWsMessagesOf(frame));
    for (final messages in [here, there]) {
      expect(messages.length, 300);
      expect(messages.first.assetId, 't0');
      expect(messages.last.assetId, 't299');
      final book = messages.first as PolymarketBookMessage;
      expect((book.bestBid! + book.bestAsk!) / 2, closeTo(0.42, 1e-9));
    }
  });

  test('one object, a heartbeat, a malformed frame, an unknown event', () {
    expect(polymarketWsMessagesOf(jsonEncode(_book('a'))).single.assetId, 'a');
    expect(polymarketWsMessagesOf('PONG'), isEmpty);
    expect(polymarketWsMessagesOf('{"event_type":"tick_size_change"}'),
        isEmpty);
    expect(polymarketWsMessagesOf('[{"event_type":"book","bids":"x"}]'),
        isEmpty);
  });
}
