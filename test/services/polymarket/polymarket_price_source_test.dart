import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart';

void main() {
  group('PmReferenceFeedRetry', () {
    test('transient failures back off 2 s, 4 s, ... capped at 30 s', () {
      final retry = PmReferenceFeedRetry();
      final delays = [for (var i = 0; i < 17; i++) retry.next().inSeconds];
      expect(delays.take(5), [2, 4, 6, 8, 10]);
      expect(delays.last, 30);
      expect(delays.every((d) => d <= 30), isTrue);
      expect(retry.failures, 17);
    });

    test('a price point resets the count', () {
      final retry = PmReferenceFeedRetry()
        ..next()
        ..next()
        ..next();
      retry.reset();
      expect(retry.failures, 0);
      expect(retry.next(), const Duration(seconds: 2));
    });

    test('a hard failure waits the long delay and still counts', () {
      final retry = PmReferenceFeedRetry();
      expect(retry.next(hard: true), kPmReferenceHardRetryDelay);
      expect(retry.failures, 1);
      expect(retry.next(), const Duration(seconds: 4));
    });
  });
}
