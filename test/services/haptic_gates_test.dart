import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/haptic_gates.dart';

void main() {
  group('OddsTickGate', () {
    test('ticks on a one-point move, not on a smaller one', () {
      final gate = OddsTickGate();
      expect(gate.onPrice(0.50, 0), isFalse); // the anchor
      expect(gate.onPrice(0.505, 2000), isFalse);
      expect(gate.onPrice(0.51, 4000), isTrue);
      expect(gate.onPrice(0.515, 6000), isFalse); // from the new anchor
      expect(gate.onPrice(0.50, 8000), isTrue); // down counts too
    });

    test('never more than one tick a second, however fast the price runs',
        () {
      final gate = OddsTickGate();
      gate.onPrice(0.50, 0);
      var ticks = 0;
      // A point every 100 ms for 5 seconds.
      for (var i = 1; i <= 50; i++) {
        if (gate.onPrice(0.50 + i * 0.01, i * 100)) ticks++;
      }
      expect(ticks, lessThanOrEqualTo(5));
      expect(ticks, greaterThanOrEqualTo(4));
    });

    test('a move inside the gap ticks once the gap has passed', () {
      final gate = OddsTickGate();
      gate.onPrice(0.50, 0);
      expect(gate.onPrice(0.52, 100), isTrue);
      expect(gate.onPrice(0.55, 500), isFalse); // inside the second
      expect(gate.onPrice(0.55, 1200), isTrue); // still 3 points away
    });
  });

  group('RoundHeartbeatGate', () {
    bool due(RoundHeartbeatGate gate, int s,
            {bool holds = true, bool visible = true, bool foreground = true}) =>
        gate.due(
            secondsRemaining: s,
            holdsPosition: holds,
            visible: visible,
            foreground: foreground);

    test('beats once a second for the last ten seconds only', () {
      final gate = RoundHeartbeatGate();
      var beats = 0;
      for (var s = 300; s >= 0; s--) {
        if (due(gate, s)) beats++;
        if (due(gate, s)) beats++; // the same second seen twice
      }
      expect(beats, 10);
      expect(due(RoundHeartbeatGate(), 11), isFalse);
      expect(due(RoundHeartbeatGate(), 10), isTrue);
      expect(due(RoundHeartbeatGate(), 1), isTrue);
      expect(due(RoundHeartbeatGate(), 0), isFalse);
    });

    test('needs a position, the screen in front and the app foregrounded',
        () {
      expect(due(RoundHeartbeatGate(), 5, holds: false), isFalse);
      expect(due(RoundHeartbeatGate(), 5, visible: false), isFalse);
      expect(due(RoundHeartbeatGate(), 5, foreground: false), isFalse);
    });

    test('the next round beats again', () {
      final gate = RoundHeartbeatGate();
      expect(due(gate, 1), isTrue);
      expect(due(gate, 0), isFalse);
      expect(due(gate, 300), isFalse);
      expect(due(gate, 1), isTrue);
    });
  });

  group('comboLegChange', () {
    ({String key, bool won, bool lost}) leg(String key,
            {bool won = false, bool lost = false}) =>
        (key: key, won: won, lost: lost);

    test('a leg open before and won now is a win, once', () {
      final next = [leg('c:0', won: true), leg('c:1')];
      expect(
          comboLegChange(
              previousOpen: {'c:0': true, 'c:1': true}, next: next),
          ComboLegChange.won);
      // The following refresh sees it already settled.
      expect(
          comboLegChange(
              previousOpen: {'c:0': false, 'c:1': true}, next: next),
          isNull);
    });

    test('a lost leg outranks a won one in the same refresh', () {
      expect(
          comboLegChange(previousOpen: {
            'c:0': true,
            'c:1': true
          }, next: [
            leg('c:0', won: true),
            leg('c:1', lost: true)
          ]),
          ComboLegChange.lost);
    });

    test('a leg never seen open (first load, new combo) is no change', () {
      expect(
          comboLegChange(
              previousOpen: const {}, next: [leg('c:0', won: true)]),
          isNull);
    });

    test('a void or still-open leg is no change', () {
      expect(
          comboLegChange(
              previousOpen: {'c:0': true, 'c:1': true},
              next: [leg('c:0'), leg('c:1')]),
          isNull);
    });
  });

  group('IncomingPaymentGate', () {
    final start = DateTime(2026, 10, 4, 12);
    ({String id, DateTime at}) pay(String id, DateTime at) => (id: id, at: at);

    test('the first observation is history and stays quiet', () {
      final gate = IncomingPaymentGate(startedAt: start);
      expect(
          gate.observe([pay('a', start.add(const Duration(seconds: 5)))]),
          isFalse);
    });

    test('a new payment of this session fires once', () {
      final gate = IncomingPaymentGate(startedAt: start);
      gate.observe(const []);
      final p = pay('a', start.add(const Duration(minutes: 3)));
      expect(gate.observe([p]), isTrue);
      expect(gate.observe([p]), isFalse);
      expect(
          gate.observe([p, pay('b', start.add(const Duration(minutes: 4)))]),
          isTrue);
    });

    test('a backlog streaming in after an empty first read stays quiet', () {
      final gate = IncomingPaymentGate(startedAt: start);
      gate.observe(const []);
      expect(
          gate.observe([
            pay('old1', start.subtract(const Duration(days: 30))),
            pay('old2', start.subtract(const Duration(minutes: 10))),
          ]),
          isFalse);
      // And never fires for them later either.
      expect(
          gate.observe(
              [pay('old1', start.subtract(const Duration(days: 30)))]),
          isFalse);
    });
  });

  test('OncePerKey lets each key through once', () {
    final once = OncePerKey<int>();
    expect(once.first(1), isTrue);
    expect(once.first(1), isFalse);
    expect(once.first(2), isTrue);
  });
}
