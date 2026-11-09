// ConnectionHealth: when an order may blame the connection, and when it may
// not. A fake clock; no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/http/connection_health.dart';

void main() {
  late DateTime now;
  late ConnectionHealth health;
  setUp(() {
    now = DateTime(2026, 11, 9, 12);
    health = ConnectionHealth(now: () => now);
  });
  void fail(String host, [int times = 2]) {
    for (var i = 0; i < times; i++) {
      health.noteFailed(host);
    }
  }

  test('starts healthy', () => expect(health.isSlow, isFalse));

  test('two failing hosts read slow', () {
    fail('clob.polymarket.com');
    expect(health.isSlow, isFalse);
    fail('polygon-rpc.com');
    expect(health.isSlow, isTrue);
  });

  test('one dead provider never trips it, however dead', () {
    fail('dead.provider.test', 500);
    expect(health.isSlow, isFalse);
    health.noteAnswered('gamma.test');
    expect(health.isSlow, isFalse);
  });

  test('one failure per host is not enough', () {
    fail('a.test', 1);
    fail('b.test', 1);
    expect(health.isSlow, isFalse);
  });

  test('two dead providers on a phone that reaches everything else: not slow',
      () {
    fail('dead-a.test');
    fail('dead-b.test');
    health.noteAnswered('gamma.test');
    health.noteAnswered('clob.test');
    health.noteAnswered('backend.test');
    expect(health.isSlow, isFalse);
  });

  test('a host mostly answering is not failing', () {
    for (var i = 0; i < 3; i++) {
      health.noteAnswered('a.test');
      health.noteAnswered('b.test');
    }
    fail('a.test');
    fail('b.test');
    expect(health.isSlow, isFalse);
  });

  test('failures age out of the window', () {
    fail('a.test');
    fail('b.test');
    expect(health.isSlow, isTrue);
    now = now.add(ConnectionHealth.window + const Duration(seconds: 1));
    expect(health.isSlow, isFalse);
  });

  test('failures inside the window still count across a whole retry wait', () {
    fail('a.test');
    fail('b.test');
    now = now.add(const Duration(seconds: 90));
    expect(health.isSlow, isTrue);
  });

  test('recovers as soon as the hosts answer again', () {
    fail('a.test', 5);
    fail('b.test', 5);
    expect(health.isSlow, isTrue);
    health.noteAnswered('a.test');
    expect(health.isSlow, isFalse);
  });

  test('a network change forgets the old network', () {
    fail('a.test');
    fail('b.test');
    health.reset();
    expect(health.isSlow, isFalse);
  });
}
