// lib/screens/ledger/ledger_failure_copy.dart
//
// Maps typed Ledger failure codes to localized copy. Services never
// return English strings; every Ledger error the user sees goes through
// here. Anything that is not a Ledger failure (a dropped connection, a
// timeout, an unexpected exception) goes through the app-wide
// plain-language helper, so raw exception text never reaches the user.

import 'package:flutter/widgets.dart';

import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

String ledgerFailureMessage(
  AppLocalizations l10n,
  LedgerFailure failure, {
  LedgerAppId fallbackApp = LedgerAppId.bitcoin,
}) {
  final app = (failure.app ?? fallbackApp).deviceName;
  switch (failure.code) {
    case LedgerFailureCode.locked:
      return l10n.ledgerErrorLocked;
    case LedgerFailureCode.wrongApp:
      return l10n.ledgerErrorOpenApp(app);
    case LedgerFailureCode.appNotInstalled:
      return l10n.ledgerErrorInstallApp(app);
    case LedgerFailureCode.unsupportedAppVersion:
      return l10n.ledgerErrorUpdateApp(app);
    case LedgerFailureCode.rejected:
      return l10n.ledgerErrorRejected;
    case LedgerFailureCode.dataRejected:
      return l10n.ledgerErrorDataRejected;
    case LedgerFailureCode.payloadTooLarge:
      return l10n.ledgerErrorPayloadTooLarge;
    case LedgerFailureCode.disconnected:
      return l10n.ledgerErrorDisconnected;
    case LedgerFailureCode.wrongDevice:
      return l10n.ledgerErrorWrongDevice;
    case LedgerFailureCode.wrongSigner:
      return l10n.ledgerErrorWrongSigner;
    case LedgerFailureCode.timeout:
      return l10n.ledgerErrorTimeout;
    case LedgerFailureCode.busy:
      return l10n.ledgerErrorBusy;
    case LedgerFailureCode.permissionDenied:
      return l10n.ledgerErrorPermission;
    case LedgerFailureCode.unknown:
      // The status word is not user copy; [ledgerFailureDetail] carries it
      // for a nerd data row and the analytics payload.
      return l10n.ledgerErrorUnknown;
  }
}

/// The device status word as a short technical line ("Ledger code 6A80")
/// for a collapsed nerd data section. Null when the failure carries none.
String? ledgerFailureDetail(AppLocalizations l10n, LedgerFailure failure) {
  final sw = failure.statusWord;
  if (sw == null) return null;
  return l10n.ledgerFailureCodeDetail(
      sw.toRadixString(16).padLeft(4, '0').toUpperCase());
}

/// Technical detail for the nerd data section under [ledgerErrorCopy]:
/// the status word when the device answered with one, otherwise the raw
/// text of an error that has no typed mapping. Null when there is nothing
/// worth showing beyond the sentence.
String? ledgerErrorDetail(BuildContext context, Object error) {
  if (error is CapabilityUnavailableException) return null;
  final failure = LedgerFailure.from(error);
  final code = ledgerFailureDetail(context.l10n, failure);
  if (code != null) return code;
  if (failure.code != LedgerFailureCode.unknown) return null;
  final text = errorDetailText(error);
  return text.isEmpty ? null : text;
}

/// Convenience for code without a BuildContext: maps any error first.
String ledgerErrorMessage(
  AppLocalizations l10n,
  Object error, {
  LedgerAppId fallbackApp = LedgerAppId.bitcoin,
}) =>
    error is CapabilityUnavailableException
        ? error.decision.messageIn(l10n)
        : ledgerFailureMessage(l10n, LedgerFailure.from(error),
            fallbackApp: fallbackApp);

/// The catch-block entry point for screens and sheets. A typed Ledger
/// failure keeps its own sentence; everything else (offline, timeouts,
/// unexpected exceptions) goes through [userErrorCopy] with [fallback] or
/// the generic Ledger sentence, so no exception text is shown. The raw
/// text stays available through [errorDetailText] for a nerd data row.
String ledgerErrorCopy(
  BuildContext context,
  Object error, {
  LedgerAppId fallbackApp = LedgerAppId.bitcoin,
  String? fallback,
}) {
  final l10n = context.l10n;
  if (error is CapabilityUnavailableException) {
    return error.decision.messageIn(l10n);
  }
  final failure = LedgerFailure.from(error);
  if (failure.code != LedgerFailureCode.unknown || failure.statusWord != null) {
    return ledgerFailureMessage(l10n, failure, fallbackApp: fallbackApp);
  }
  return userErrorCopy(context, error,
      fallback: fallback ?? l10n.ledgerErrorUnknown);
}
