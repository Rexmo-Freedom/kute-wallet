import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/orchestra/arrival_target.dart';

void main() {
  group('grossUpSatsForTarget', () {
    test('scales a short estimate up to the target plus the buffer', () {
      // 10 000 sats are estimated to deliver $5.90; $6.00 was typed.
      final sats = grossUpSatsForTarget(
          sats: 10000, estimatedOut: 5.90, targetUsd: 6.00, maxSats: 1000000);
      expect(sats, (10000 * (6.00 / 5.90) * kArrivalTargetBuffer).ceil());
      // At the same rate the scaled send clears the target.
      expect(sats * 5.90 / 10000, greaterThanOrEqualTo(6.00));
    });

    test('never scales by more than the cap', () {
      expect(
          grossUpSatsForTarget(
              sats: 10000, estimatedOut: 0.06, targetUsd: 6, maxSats: 1000000),
          (10000 * kArrivalTargetMaxScale).ceil());
    });

    test('never above what the wallet can send, never below the input', () {
      expect(
          grossUpSatsForTarget(
              sats: 10000, estimatedOut: 5.90, targetUsd: 6, maxSats: 10100),
          10100);
      expect(
          grossUpSatsForTarget(
              sats: 10000, estimatedOut: 5.90, targetUsd: 6, maxSats: 9000),
          10000);
    });

    test('leaves an amount that already arrives, or an unusable point', () {
      for (final out in [6.0, 6.5, 0.0, -1.0, double.nan]) {
        expect(
            grossUpSatsForTarget(
                sats: 10000, estimatedOut: out, targetUsd: 6, maxSats: 99999),
            10000,
            reason: '$out');
      }
      expect(
          grossUpSatsForTarget(
              sats: 10000, estimatedOut: 5.9, targetUsd: 0, maxSats: 99999),
          10000);
    });
  });

  group('arrivalTargetShort', () {
    test('only more than a cent short asks again', () {
      expect(arrivalTargetShort(5.995, 6.00), isFalse);
      expect(arrivalTargetShort(5.99, 6.00), isFalse);
      expect(arrivalTargetShort(5.985, 6.00), isTrue);
      expect(arrivalTargetShort(6.01, 6.00), isFalse);
      expect(arrivalTargetShort(0, 6.00), isFalse);
    });
  });
}
