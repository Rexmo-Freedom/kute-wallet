// A queued scale order is looked up by its legs' ids (derived from the
// cloid each send went under), never by the base cloid no leg carries; a
// single order by each send's own cloid.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show hlScaleLegCloids;

void main() {
  const base = '0x0123456789abcdef0123456789abcd7f';

  setUp(HlResendCloids.reset);
  tearDown(HlResendCloids.reset);

  test('a single order: the own cloid of every send', () {
    final again = HlResendCloids.renew(base);
    expect(hlSentOrderCloids(base), [base, again]);
  });

  test('a scale order: the legs derived from the cloid sent', () {
    final ids = hlSentOrderCloids(base, scaleLegs: 3);
    expect(ids, hlScaleLegCloids(base, 3));
    expect(ids, isNot(contains(base)));
    expect(ids, hasLength(3));
  });

  test('the slip sends the current cloid; its legs are what the lookup '
      'reads', () {
    final sent = HlResendCloids.current(base);
    expect(hlSentOrderCloids(base, scaleLegs: 5),
        containsAll(hlScaleLegCloids(sent, 5)));
  });
}
