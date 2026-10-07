// lib/helpers/user_error_copy.dart
//
// Plain-language error copy for snackbars and banners. Raw exception text
// (class names, SDK dumps, stack fragments) never reaches the user as
// primary content: every catch block routes through [userErrorCopy] and
// passes a short, flow-specific fallback sentence. The raw text stays
// available through [errorDetailText] for a Details or nerd data expander
// and for tracking.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HyperliquidInsufficientMarginException;
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/polymarket_backend_service.dart'
    show GeoBlockException;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/seed_access.dart';

/// A failure whose sentence for the person is chosen where it is thrown.
///
/// [toString] stays English on purpose: error categories, logs and the
/// few places that match on exception text read it, and they must not
/// change with the app language. [userErrorCopy] shows [message], which
/// is in the app language.
class LocalizedError implements Exception {
  const LocalizedError(this.message, {required this.english});

  /// Builds both sentences from one ARB entry: [copy] in [l10n]'s
  /// language for the person, and in English for [toString].
  factory LocalizedError.from(
          AppLocalizations l10n, String Function(AppLocalizations) copy) =>
      LocalizedError(copy(l10n), english: copy(l10nForLanguage('en')));

  final String message;
  final String english;

  @override
  String toString() => english;
}

/// One sentence a person can act on, chosen from the error's type first
/// and from [fallback] (or a generic sentence) otherwise. Strings and
/// [FormatException]s written as user copy pass through unchanged; anything
/// that reads like an exception dump is replaced.
String userErrorCopy(BuildContext context, Object? error, {String? fallback}) {
  final l10n = context.l10n;
  final generic = fallback ?? l10n.errorCopyGeneric;
  if (error == null) return generic;
  if (error is LocalizedError) return error.message;
  // The policy's own sentence: the operator's words when it carries some,
  // Kute's wording for the reason code otherwise.
  if (error is CapabilityUnavailableException) {
    return error.decision.messageIn(l10n);
  }
  if (error is LeverageCapExceededException) return error.messageIn(l10n);
  if (error is ProviderAvailabilityException) {
    return error.availability.messageIn(l10n);
  }
  if (error is GeoBlockException) return l10n.tradingNotAvailableInRegion;
  if (error is HypercoreActivationFeeUnavailable) {
    return l10n.errorCopyActivationFeeUnavailable;
  }
  if (error is HypercoreActivationFeeChanged) {
    return l10n.errorCopyActivationFeeChanged;
  }
  if (error is HypercoreActivationFeeBalanceRequired) {
    return l10n.errorCopyActivationFeeBalanceRequired;
  }
  // The venue account does not hold the cash, read before anything was
  // signed (or the venue said so). Say that, not "could not be completed".
  if (error is HypercoreBalanceShortfall ||
      error is HyperliquidInsufficientMarginException) {
    return l10n.insufficientBalance;
  }
  if (error is SeedLockedException) return l10n.errorCopyLocked;
  if (error is SeedUnavailableException) return generic;
  if (error is SocketException || error is HandshakeException) {
    return l10n.errorCopyOffline;
  }
  if (error is http.ClientException) return l10n.errorCopyOffline;
  if (error is TimeoutException) return l10n.errorCopyTimeout;
  if (error is OnchainException) {
    return switch (error.code) {
      'network' => l10n.errorCopyOffline,
      'timeout' => l10n.errorCopyTimeout,
      'busy' => l10n.errorCopyBusy,
      'insufficient_funds' => l10n.errorCopyInsufficientFunds,
      // Codes that name one input the user can go back and correct.
      'invalid_address' => l10n.sendDestinationAddressIsInvalid,
      'invalid_amount' => l10n.sendAmountBelowNetworkMinimum,
      'invalid_fee_rate' => l10n.sendFeeEstimateFailed,
      // A refused request or an unbuildable transaction is not something
      // the person typed. Telling them to check their input left the
      // hardware send's fee row on that sentence with nothing to change;
      // the flow's own fallback says what actually could not be done.
      'invalid_request' || 'invalid_transaction' => generic,
      _ => generic,
    };
  }
  if (error is FormatException) {
    final message = error.message.trim();
    final known = _serviceSentence(l10n, message, generic);
    if (known != null) return known;
    return _readsAsUserCopy(message) ? message : l10n.errorCopyInvalidInput;
  }
  if (error is PlatformException) {
    final message = (error.message ?? '').trim();
    return _readsAsUserCopy(message) ? message : generic;
  }
  if (error is String) {
    final message = error.trim();
    final known = _serviceSentence(l10n, message, generic);
    if (known != null) return known;
    return _readsAsUserCopy(message) ? message : generic;
  }
  // Transport failures wrapped by other layers still carry their names.
  final lower = error.toString().toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('handshakeexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable')) {
    return l10n.errorCopyOffline;
  }
  if (lower.contains('timeoutexception') || lower.contains('timed out')) {
    return l10n.errorCopyTimeout;
  }
  return generic;
}

/// Fixed English sentences that services hand back as plain strings
/// (a Result's error, a thrown string, a FormatException's message). They stay English where they are
/// produced, because error categories and a few matches read that text,
/// and are put in the app language here. Technical ones take [generic].
String? _serviceSentence(
        AppLocalizations l10n, String message, String generic) =>
    switch (message) {
      'Network error. Please try again.' ||
      'Network error. Tap to retry.' =>
        l10n.errorCopyOffline,
      'Request timed out. Tap to retry.' => l10n.errorCopyTimeout,
      'Wallet locked. Please unlock first.' => l10n.errorCopyLocked,
      'Deposit terms changed. Please try again.' =>
        l10n.errorCopyDepositTermsChanged,
      'Reusable deposit terms changed. Use a one-time deposit address.' =>
        l10n.errorCopyReusableDepositTermsChanged,
      "Couldn't load fees. Try again." => l10n.errorCopyFeesUnavailable,
      'Enter a wallet name of up to 60 characters.' =>
        l10n.errorCopyWalletNameLength,
      'Choose a supported Bitcoin address type.' =>
        l10n.errorCopyUnsupportedAddressType,
      'Enter a valid 12-word recovery phrase.' =>
        l10n.errorCopyInvalidTwelveWords,
      // Blockstream Jade connection and PIN sentences (JadeService).
      'Bluetooth permission denied. Please enable it in Settings.' =>
        l10n.jadeBluetoothPermission,
      'Bluetooth is unavailable. Please turn on Bluetooth and try again.' =>
        l10n.jadeBluetoothOff,
      'Bluetooth scan failed. Please try again.' => l10n.jadeScanFailed,
      'Jade disconnected. Please reconnect and try again.' =>
        l10n.jadeDisconnected,
      'PIN authentication failed. Please try again.' => l10n.jadePinAuthFailed,
      'Jade not connected or authenticated' => l10n.jadeNotConnected,
      'Operation was cancelled on the Jade device.' =>
        l10n.jadeCancelledOnDevice,
      'Invalid parameters sent to Jade. Please try again.' =>
        l10n.jadeBadParams,
      'Communication error with Jade. Please reconnect.' =>
        l10n.jadeCommunicationError,
      'Jade is not unlocked. Please enter your PIN.' => l10n.jadeLocked,
      'Wrong PIN entered. Note: 3 failed attempts will reset the device.' =>
        l10n.jadeWrongPin,
      'Device is not a Blockstream Jade. Please check your device.' =>
        l10n.jadeNotAJade,
      'No Jade found. Please check:\n'
              '1. Jade is powered on\n'
              '2. Bluetooth is enabled on Jade and your phone\n\n'
              'Tip: You can also use QR Mode to scan your xpub.' =>
        l10n.jadeNotFound,
      'Cannot reach PIN server. Check your internet or use QR Mode.' =>
        l10n.jadePinServerUnreachable,
      'PIN server returned an empty response. '
              'Check your internet connection or try QR Mode.' =>
        l10n.jadePinServerEmpty,
      'Cannot reach Blockstream PIN server. '
              'Check your internet connection or use QR Mode instead.' =>
        l10n.jadePinServerBlockstream,
      'Failed to load currencies' ||
      'Failed to get exchange status' ||
      'Failed to get quote' ||
      'Service unavailable' ||
      'Limits unavailable' ||
      'Route catalog unavailable' ||
      'Deposit info unavailable' ||
      'Deposit request could not be completed' ||
      'Failed to create deposit address' =>
        generic,
      _ => null,
    };

/// Words from the rails' own vocabulary that must never reach a person.
///
/// The partner, the network the spending wallet runs on and the dollar
/// balance's token are each spelled differently on screen: the balance
/// is Dollars, and the rails behind it are not named at all. A provider
/// or guard sentence carrying one of these is therefore not copy, no
/// matter how well it reads.
const List<String> kInternalRailWords = [
  'spark',
  'flashnet',
  'orchestra',
  'usdb',
  'accumulation',
];

/// [userErrorCopy] for a message that came off a rail.
///
/// A provider's own sentence is usually the most useful thing anyone can
/// say about a refusal, so it wins whenever it reads as copy. The one
/// thing it may not do is name the rails' internal vocabulary, and a
/// sentence that does takes [fallback] instead.
///
/// Every screen that puts a swap, mint or quote failure in front of
/// someone goes through here rather than keeping its own word list, so
/// adding a word protects all of them at once.
String railSafeErrorCopy(
  BuildContext context,
  Object? error, {
  required String fallback,
}) {
  final copy = userErrorCopy(context, error, fallback: fallback);
  final lower = copy.toLowerCase();
  if (lower.startsWith('unsupported deposit source:') ||
      lower.startsWith('unsupported source chain:')) {
    return context.l10n.receiveCoinNetworkUnavailable;
  }
  return kInternalRailWords.any(lower.contains) ? fallback : copy;
}

/// The raw text for a Details expander or a tracking property. Trimmed of
/// the "Exception: " prefix Dart adds and capped so a banner cannot grow.
String errorDetailText(Object? error, {int maxLength = 300}) {
  if (error == null) return '';
  var text = error.toString().trim();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) text = text.substring(prefix.length);
  return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
}

/// True when a message was written for people: short, no class names, no
/// stack or code fragments.
/// Whether [message] is safe to put in front of a person: short, and
/// free of the markers that give away a thrown object rather than a
/// sentence. Exported so a caller holding a provider's own wording can
/// decide to show it instead of falling back to a generic line.
bool readsAsUserCopy(String message) => _readsAsUserCopy(message);

bool _readsAsUserCopy(String message) {
  if (message.isEmpty || message.length > 160) return false;
  final lower = message.toLowerCase();
  const markers = [
    'exception',
    'error:',
    'errno',
    'stacktrace',
    'stack trace',
    'null check',
    'bad state',
    'unhandled',
    'instance of',
    'dart:',
    'package:',
    '0x',
    '{',
    '}',
    '<',
    '>',
  ];
  for (final marker in markers) {
    if (lower.contains(marker)) return false;
  }
  return true;
}
