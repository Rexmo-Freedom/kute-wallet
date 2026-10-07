import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus_dart.dart';

LedgerFailureCode _code(
  Object error, {
  bool confirmed = false,
  LedgerCommandPhase phase = LedgerCommandPhase.command,
}) =>
    LedgerFailure.from(error, appConfirmedOpen: confirmed, phase: phase).code;

void main() {
  group('status words (plan B2 table)', () {
    test('0x5515 is locked', () {
      expect(_code(const LedgerStatusException(0x5515)),
          LedgerFailureCode.locked);
    });

    test('Bitcoin wrong-app words map to wrongApp when no app is confirmed',
        () {
      for (final sw in [0x6e00, 0x6e01, 0x6d02, 0x6511, 0x6a87]) {
        expect(_code(LedgerStatusException(sw)), LedgerFailureCode.wrongApp,
            reason: sw.toRadixString(16));
      }
    });

    test('the same words inside a confirmed app are not "wrong app"', () {
      for (final sw in [0x6e00, 0x6e01, 0x6d02, 0x6511, 0x6a87]) {
        expect(_code(LedgerStatusException(sw), confirmed: true),
            LedgerFailureCode.unknown);
      }
    });

    test('OPEN_APP failures mean the app is not installed', () {
      expect(
          _code(const LedgerStatusException(0x6807),
              phase: LedgerCommandPhase.openApp),
          LedgerFailureCode.appNotInstalled);
      expect(
          _code(const LedgerStatusException(0x6984),
              phase: LedgerCommandPhase.openApp),
          LedgerFailureCode.appNotInstalled);
      expect(_code(const LedgerStatusException(0x6984)),
          LedgerFailureCode.unknown);
    });

    test('0x6985, 0x6982 and the open-app refusal 0x5501 are rejections', () {
      for (final sw in [0x6985, 0x6982, 0x5501]) {
        expect(_code(LedgerStatusException(sw)), LedgerFailureCode.rejected);
      }
      expect(
          _code(const LedgerStatusException(0x5501),
              phase: LedgerCommandPhase.openApp),
          LedgerFailureCode.rejected);
    });

    test('0x6d00 and 0x911c: wrong app before, unsupported version after', () {
      for (final sw in [0x6d00, 0x911c]) {
        expect(_code(LedgerStatusException(sw)), LedgerFailureCode.wrongApp);
        expect(_code(LedgerStatusException(sw), confirmed: true),
            LedgerFailureCode.unsupportedAppVersion);
      }
    });

    test('0x6a80 is dataRejected and 0x6a84 is payloadTooLarge', () {
      expect(_code(const LedgerStatusException(0x6a80)),
          LedgerFailureCode.dataRejected);
      expect(_code(const LedgerStatusException(0x6a84)),
          LedgerFailureCode.payloadTooLarge);
    });

    test('anything else is unknown and keeps its status word', () {
      final f = LedgerFailure.from(const LedgerStatusException(0x6b00));
      expect(f.code, LedgerFailureCode.unknown);
      expect(f.statusWord, 0x6b00);
    });
  });

  group('library exceptions and triggers', () {
    test('connection loss and a closed connection are disconnected', () {
      expect(_code(ConnectionLostException(connectionType: ConnectionType.ble)),
          LedgerFailureCode.disconnected);
      expect(
          _code(DeviceNotConnectedException(
              connectionType: ConnectionType.usb, requestedOperation: 'x')),
          LedgerFailureCode.disconnected);
      expect(_code(LedgerManagerDisposedException(ConnectionType.ble)),
          LedgerFailureCode.disconnected);
      expect(_code(StateError('RequestQueue disposed')),
          LedgerFailureCode.disconnected);
    });

    test('the SDK device exception carries its status word', () {
      expect(
          _code(LedgerDeviceException(
              errorCode: 0x6985, connectionType: ConnectionType.usb)),
          LedgerFailureCode.rejected);
    });

    test('permission refusals are localized, not raw strings', () {
      expect(_code(PermissionException(connectionType: ConnectionType.ble)),
          LedgerFailureCode.permissionDenied);
      expect(
          _code(Exception(
              'Bluetooth permission denied. Please go to Settings > Kute.')),
          LedgerFailureCode.permissionDenied);
    });

    test('timeout', () {
      expect(_code(TimeoutException('slow')), LedgerFailureCode.timeout);
      expect(_code(Exception('scan_timeout')), LedgerFailureCode.timeout);
    });

    test('Bitcoin plugin transformer strings keep today\'s mapping', () {
      expect(_code(Exception('6985')), LedgerFailureCode.rejected);
      expect(_code(Exception('6e01')), LedgerFailureCode.wrongApp);
      expect(_code(Exception('5515')), LedgerFailureCode.locked);
      expect(_code(Exception('SW_INCORRECT_DATA')),
          LedgerFailureCode.dataRejected);
      expect(_code(Exception('something else')), LedgerFailureCode.unknown);
      expect(LedgerFailure.from(Exception('something else')).statusWord,
          isNull);
    });

    test('typed failures pass through unchanged', () {
      for (final code in [
        LedgerFailureCode.wrongDevice,
        LedgerFailureCode.wrongSigner,
        LedgerFailureCode.busy,
      ]) {
        final f = LedgerFailure(code);
        expect(identical(LedgerFailure.from(f), f), isTrue);
      }
    });
  });
}
