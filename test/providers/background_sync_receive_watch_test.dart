// A deposit to a receive address is read on every screen, not only where
// the full sync runs (Home and the wallet detail): the money is sent while
// the person sits on the receive sheet or anywhere else, and its Activity
// row must appear there. Before, the continuous loop did nothing off those
// routes until a row was pending, and a deposit had no row until the
// sweep (which only that loop ran) had seen it.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart';

void main() {
  tearDown(ReceiveAddressWatch.reset);

  SyncTick tick(
          {bool onSyncRoute = false,
          bool pending = false,
          bool watching = false}) =>
      BackgroundSyncService.syncTickFor(
          onSyncRoute: onSyncRoute,
          pendingActivity: pending,
          watchingReceiveAddresses: watching);

  test('off Home, a receive address just shown is still polled', () {
    expect(tick(watching: true), SyncTick.receiveAddresses);
    expect(tick(), SyncTick.idle, reason: 'nothing to watch: nothing runs');
    expect(tick(onSyncRoute: true), SyncTick.full);
    expect(tick(pending: true, watching: true), SyncTick.full,
        reason: 'a deposit on its way keeps the full sync running');
  });

  test('the watch lasts its window after an address is shown', () {
    var now = DateTime(2026, 10, 18, 20, 20);
    ReceiveAddressWatch.clock = () => now;
    expect(ReceiveAddressWatch.watching, isFalse);
    ReceiveAddressWatch.shown();
    expect(ReceiveAddressWatch.watching, isTrue);
    now = now.add(ReceiveAddressWatch.window - const Duration(minutes: 1));
    expect(ReceiveAddressWatch.watching, isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(ReceiveAddressWatch.watching, isFalse);
  });

  test('the standing sweep runs every 30 s while watched or in flight', () {
    expect(standingSweepInterval(watching: true, inFlight: false),
        const Duration(seconds: 30));
    expect(standingSweepInterval(watching: false, inFlight: true),
        const Duration(seconds: 30));
    expect(standingSweepInterval(watching: false, inFlight: false),
        const Duration(minutes: 1));
  });
}
