// The Investing account's shared reads: one request in flight per account,
// a read sent under 950 ms ago answers the poll and the fresh read, and a
// failure (a 429 included) backs the fresh read off 1, 2, 4, 8, 15 s.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';

const _a = '0x1111111111111111111111111111111111111111';

HlAccountSnapshot _snap(double usd) => HlAccountSnapshot(
      accountValue: usd,
      withdrawable: usd,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

void main() {
  test('a read asked while one is in flight joins it', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var sent = 0;
      Future<HlAccountSnapshot> fetch() async {
        sent++;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _snap(1);
      }

      final a = reads.read(_a, fetch);
      final b = reads.read(_a.toUpperCase(), fetch, reuse: true);
      final c = reads.read(_a, fetch);
      async.elapse(const Duration(seconds: 1));
      expect(sent, 1);
      expect(identical(a, b) && identical(b, c), isTrue);
    });
  });

  test('reuse: a read sent under 950 ms ago answers; one past it does not; '
      'a forced read never reuses', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var sent = 0;
      Future<HlAccountSnapshot> fetch() async => _snap((++sent).toDouble());
      reads.read(_a, fetch);
      async.elapse(const Duration(milliseconds: 500));
      reads.read(_a, fetch, reuse: true);
      async.flushMicrotasks();
      expect(sent, 1);
      reads.read(_a, fetch);
      async.flushMicrotasks();
      expect(sent, 2, reason: 'without reuse it reads');
      async.elapse(const Duration(milliseconds: 960));
      reads.read(_a, fetch, reuse: true);
      async.flushMicrotasks();
      expect(sent, 3);
    });
  });

  test('failures back off 1, 2, 4, 8, 15, 15 s; a good read ends it', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var fail = true;
      Future<HlAccountSnapshot> fetch() async {
        if (fail) throw StateError('429');
        return _snap(1);
      }

      final seen = <Duration>[];
      for (var i = 0; i < 6; i++) {
        reads.read(_a, fetch).then((_) {}, onError: (Object _) {});
        async.flushMicrotasks();
        expect(reads.backingOff(_a), isTrue);
        seen.add(reads.backoffOf(_a));
        async.elapse(reads.backoffOf(_a));
        expect(reads.backingOff(_a), isFalse);
      }
      expect(seen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 15),
        Duration(seconds: 15),
      ]);
      expect(reads.failed, 6);
      fail = false;
      reads.read(_a, fetch);
      async.flushMicrotasks();
      expect(reads.backoffOf(_a), Duration.zero);
      expect(reads.lastOf(_a)!.withdrawable, 1);
    });
  });
}
