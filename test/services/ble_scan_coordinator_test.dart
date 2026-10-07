import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/bluetooth/ble_scan_coordinator.dart';

void main() {
  test('an old discovery screen cannot stop the next scanner', () async {
    final events = <String>[];
    final coordinator = BleScanCoordinator(stopRadio: () async {
      events.add('stop');
    });
    final ledger = coordinator.acquire();
    expect(
        await coordinator.start(ledger, () async {
          events.add('ledger');
        }),
        true);
    final jade = coordinator.acquire();
    expect(ledger.isCurrent, false);
    expect(
        await coordinator.start(jade, () async {
          events.add('jade');
        }),
        true);
    final afterJadeStarted = List<String>.from(events);
    await coordinator.stop(ledger);
    expect(events, afterJadeStarted);
    expect(jade.isCurrent, true);
    await coordinator.stop(jade);
    expect(events.last, 'stop');
    expect(jade.isCurrent, false);
  });

  test(
      'ownership changes during native startup finish cleanup before the next start',
      () async {
    final events = <String>[];
    final coordinator = BleScanCoordinator(stopRadio: () async {
      events.add('stop');
    });
    final entered = Completer<void>();
    final release = Completer<void>();
    final oldLease = coordinator.acquire();
    final oldStart = coordinator.start(oldLease, () async {
      events.add('old-start');
      entered.complete();
      await release.future;
    });
    await entered.future;
    final currentLease = coordinator.acquire();
    final currentStart = coordinator.start(currentLease, () async {
      events.add('new-start');
    });
    await coordinator.stop(oldLease);
    release.complete();
    expect(await oldStart, false);
    expect(await currentStart, true);
    expect(events.last, 'new-start');
    expect(events.where((event) => event == 'new-start').length, 1);
  });

  test('a failed scan does not block the next owner', () async {
    final coordinator = BleScanCoordinator(stopRadio: () async {});
    final failedLease = coordinator.acquire();
    await expectLater(
        coordinator.start(failedLease, () async {
          throw StateError('scan failed');
        }),
        throwsStateError);
    final nextLease = coordinator.acquire();
    expect(await coordinator.start(nextLease, () async {}), true);
  });
}
