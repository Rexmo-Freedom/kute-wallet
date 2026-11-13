// The deposit-address poll never drops the address a deposit is on its way
// to: losing it made the deposit's "Receiving" row vanish.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/background_sync_provider.dart'
    show trimSparkAddressRing;

void main() {
  test('the oldest go first, but never one with a deposit on its way', () {
    final ring = ['a6', 'a5', 'a4', 'a3', 'a2', 'a1'];
    trimSparkAddressRing(ring, keep: const {}, max: 5, hardMax: 10);
    expect(ring, ['a6', 'a5', 'a4', 'a3', 'a2']);

    final pinned = ['a7', 'a6', 'a5', 'a4', 'a3', 'a1'];
    trimSparkAddressRing(pinned, keep: const {'a1'}, max: 5, hardMax: 10);
    // a3 goes instead of a1, which a deposit was sent to.
    expect(pinned, ['a7', 'a6', 'a5', 'a4', 'a1']);

    final crowded = ['n', 'p1', 'p2', 'p3', 'p4', 'p5'];
    trimSparkAddressRing(crowded,
        keep: const {'p1', 'p2', 'p3', 'p4', 'p5'}, max: 5, hardMax: 10);
    // Every older one is waiting on a deposit: the ring runs long.
    expect(crowded, hasLength(6));

    final over = [for (var i = 12; i > 0; i--) 'x$i'];
    trimSparkAddressRing(over, keep: over.toSet(), max: 5, hardMax: 10);
    expect(over, hasLength(10));
  });
}
