// lib/services/hardware/ledger/ledger_failure.dart
//
// Typed Ledger failures (Wallet hardening Phase 3, plan B2). Services
// return codes, never English strings; the UI maps a code to l10n through
// lib/screens/ledger/ledger_failure_copy.dart.
//
// Status words come from app-ethereum `doc/ethapp.adoc` (:1836-1855) and
// the Ledger OS. Rows marked "confirmed on device" in the plan (0x6807,
// 0x6984, 0x5501, the 0x6a80 setting case) are best knowledge until the
// physical device matrix (plan section D) records them.

import 'dart:async';

import 'package:ledger_flutter_plus/ledger_flutter_plus_dart.dart'
    show
        ConnectionLostException,
        DeviceNotConnectedException,
        DisposeException,
        LedgerDeviceException,
        LedgerManagerDisposedException,
        PermissionException;

enum LedgerFailureCode {
  locked,
  wrongApp,
  appNotInstalled,
  rejected,
  unsupportedAppVersion,
  dataRejected,
  payloadTooLarge,
  disconnected,
  wrongDevice,
  wrongSigner,
  timeout,
  busy,

  /// Bluetooth or USB permission was refused on the phone. Not a device
  /// status word; kept so the scan error is localized like every other
  /// Ledger failure instead of surfacing an English exception string.
  permissionDenied,
  unknown,
}

/// The Ledger apps Kute talks to. [deviceName] is the exact name the
/// Ledger OS reports in GET_APP_AND_VERSION and expects in OPEN_APP.
enum LedgerAppId {
  bitcoin('Bitcoin'),
  ethereum('Ethereum');

  const LedgerAppId(this.deviceName);
  final String deviceName;
}

/// Where a status word was received. OPEN_APP failures carry their own
/// meaning (app missing or open refused).
enum LedgerCommandPhase { command, openApp }

/// A non-0x9000 status word from one of our own APDU operations.
class LedgerStatusException implements Exception {
  const LedgerStatusException(this.statusWord);
  final int statusWord;

  @override
  String toString() =>
      'LedgerStatusException(0x${statusWord.toRadixString(16).padLeft(4, '0')})';
}

final class LedgerFailure implements Exception {
  const LedgerFailure(this.code, {this.statusWord, this.app});

  final LedgerFailureCode code;

  /// The raw status word when the failure came from the device.
  final int? statusWord;

  /// The app the failure concerns (for "open" and "install" copy).
  final LedgerAppId? app;

  /// Maps any error raised while talking to a Ledger to a typed failure.
  ///
  /// [appConfirmedOpen] is true once GET_APP_AND_VERSION confirmed the
  /// expected app is running. It decides whether 0x6d00 or 0x911c mean
  /// "wrong app" (nothing confirmed) or "app too old" (app confirmed), and
  /// keeps today's Bitcoin mapping of 0x6e00, 0x6e01, 0x6d02, 0x6511 and
  /// 0x6a87 to [LedgerFailureCode.wrongApp] when no app is confirmed.
  static LedgerFailure from(
    Object error, {
    bool appConfirmedOpen = false,
    LedgerCommandPhase phase = LedgerCommandPhase.command,
    LedgerAppId? app,
  }) {
    if (error is LedgerFailure) return error;
    if (error is TimeoutException) {
      return LedgerFailure(LedgerFailureCode.timeout, app: app);
    }
    if (error is ConnectionLostException ||
        error is DeviceNotConnectedException ||
        error is LedgerManagerDisposedException ||
        error is DisposeException) {
      return LedgerFailure(LedgerFailureCode.disconnected, app: app);
    }
    if (error is PermissionException) {
      return LedgerFailure(LedgerFailureCode.permissionDenied, app: app);
    }

    final sw = statusWordOf(error);
    if (sw != null) {
      return fromStatusWord(sw,
          appConfirmedOpen: appConfirmedOpen, phase: phase, app: app);
    }

    final text = error.toString();
    final lower = text.toLowerCase();
    // The connection's request queue throws StateError once disposed.
    if (error is StateError && lower.contains('requestqueue disposed')) {
      return LedgerFailure(LedgerFailureCode.disconnected, app: app);
    }
    if (lower.contains('scan_timeout') || lower.contains('timeoutexception')) {
      return LedgerFailure(LedgerFailureCode.timeout, app: app);
    }
    if (lower.contains('bluetooth permission') ||
        lower.contains('bluetooth permissions are required')) {
      return LedgerFailure(LedgerFailureCode.permissionDenied, app: app);
    }
    if (lower.contains('ledger not connected')) {
      return LedgerFailure(LedgerFailureCode.disconnected, app: app);
    }
    return LedgerFailure(LedgerFailureCode.unknown, app: app);
  }

  static LedgerFailure fromStatusWord(
    int sw, {
    bool appConfirmedOpen = false,
    LedgerCommandPhase phase = LedgerCommandPhase.command,
    LedgerAppId? app,
  }) {
    LedgerFailure f(LedgerFailureCode code) =>
        LedgerFailure(code, statusWord: sw, app: app);
    switch (sw) {
      case 0x5515:
      case 0x6b0c: // locked device on some OS versions (Ledger Live maps both)
        return f(LedgerFailureCode.locked);
      case 0x6985:
      case 0x6982:
      case 0x5501: // open-app refused on device (confirmed on device)
        return f(LedgerFailureCode.rejected);
      case 0x6807:
        return f(LedgerFailureCode.appNotInstalled);
      case 0x6984:
        return phase == LedgerCommandPhase.openApp
            ? f(LedgerFailureCode.appNotInstalled)
            : f(LedgerFailureCode.unknown);
      case 0x6a80:
        return f(LedgerFailureCode.dataRejected);
      case 0x6a84:
        return f(LedgerFailureCode.payloadTooLarge);
      case 0x6d00:
      case 0x911c:
        return appConfirmedOpen
            ? f(LedgerFailureCode.unsupportedAppVersion)
            : f(LedgerFailureCode.wrongApp);
      case 0x6e00:
      case 0x6e01:
      case 0x6d02:
      case 0x6511:
      case 0x6a87:
        return appConfirmedOpen
            ? f(LedgerFailureCode.unknown)
            : f(LedgerFailureCode.wrongApp);
      default:
        return f(LedgerFailureCode.unknown);
    }
  }

  static const _knownStatusWords = [
    '5515', '6b0c', '6985', '6982', '5501', '6807', '6984', '6a80', //
    '6a84', '6d00', '911c', '6e00', '6e01', '6d02', '6511', '6a87', '6b00',
  ];

  /// Extracts a status word from our typed exception, the SDK's device
  /// exception, or the `Exception('6985')` strings the Bitcoin plugin's
  /// transformer throws.
  static int? statusWordOf(Object error) {
    if (error is LedgerStatusException) return error.statusWord;
    if (error is LedgerDeviceException && error.errorCode != 0x6F00) {
      return error.errorCode;
    }
    final lower = error.toString().toLowerCase().trim();
    if (lower.contains('sw_incorrect_data')) return 0x6a80;
    final exact =
        RegExp(r'^(?:exception: )?([0-9a-f]{4})$').firstMatch(lower);
    if (exact != null) return int.parse(exact.group(1)!, radix: 16);
    for (final code in _knownStatusWords) {
      if (RegExp('(?:^|[^0-9a-f])$code(?:\$|[^0-9a-f])').hasMatch(lower)) {
        return int.parse(code, radix: 16);
      }
    }
    return null;
  }

  @override
  String toString() {
    final sw = statusWord == null
        ? ''
        : ', 0x${statusWord!.toRadixString(16).padLeft(4, '0')}';
    return 'LedgerFailure(${code.name}$sw)';
  }
}
