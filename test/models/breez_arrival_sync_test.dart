import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';

void main() {
  group('syncUntilBalanceRises', () {
    late List<Duration> sleeps;
    late int syncs;

    setUp(() {
      sleeps = [];
      syncs = 0;
    });

    Future<bool> run(List<Map<String, BigInt>> readings) {
      var read = 0;
      return syncUntilBalanceRises(
        readBalances: () async =>
            readings[read < readings.length ? read++ : readings.length - 1],
        sync: () async => syncs++,
        sleep: (d) async => sleeps.add(d),
      );
    }

    test('one sync when the arrival shows straight away', () async {
      final rose = await run([
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(5000000)},
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(11000000)},
      ]);
      expect(rose, isTrue);
      expect(syncs, 1);
      expect(sleeps, isEmpty);
    });

    test('syncs again after 2, 5 and 10 s while nothing rose', () async {
      final rose = await run([
        {'sats': BigInt.from(1000)},
      ]);
      expect(rose, isFalse);
      expect(syncs, 4);
      expect(sleeps, kArrivalSyncRetryDelays);
    });

    test('stops at the sync that shows it', () async {
      final rose = await run([
        {'sats': BigInt.from(1000)},
        {'sats': BigInt.from(1000)},
        // A first dollar balance counts as a rise.
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(6000000)},
      ]);
      expect(rose, isTrue);
      expect(syncs, 2);
      expect(sleeps, [kArrivalSyncRetryDelays.first]);
    });

    test('a spend elsewhere is not an arrival', () async {
      final rose = await run([
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(6000000)},
        {'sats': BigInt.from(900), 'usdb': BigInt.from(6000000)},
      ]);
      expect(rose, isFalse);
      expect(syncs, 4);
    });
  });
}
