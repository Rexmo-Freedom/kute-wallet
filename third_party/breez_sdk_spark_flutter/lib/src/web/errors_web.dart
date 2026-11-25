// The wasm SDK throws its errors as JS `Error`s whose message is the Rust
// `Display` text (crates/breez-sdk/wasm/src/error.rs). These parsers turn
// that text back into the FRB error types the native bindings throw, so app
// code that catches e.g. `SdkError_InsufficientFunds` keeps working on web.
// Text that matches no known format becomes the `generic` variant.

import 'dart:typed_data';

import '../rust/errors.dart';
import '../rust/models.dart';
import 'js_values.dart';

String _rest(String s, String prefix) => s.substring(prefix.length);

RegExpMatch? _match(String pattern, String s) => RegExp(pattern, dotAll: true).firstMatch(s);

Fee? _debugFee(String s) {
  final fixed = _match(r'^Some\(Fixed \{ amount: (\d+) \}\)$', s);
  if (fixed != null) return Fee.fixed(amount: BigInt.parse(fixed.group(1)!));
  final rate = _match(r'^Some\(Rate \{ sat_per_vbyte: (\d+) \}\)$', s);
  if (rate != null) return Fee.rate(satPerVbyte: BigInt.parse(rate.group(1)!));
  return null;
}

/// Parses the `Display` text of `breez_sdk_spark::SdkError`.
SdkError parseSdkError(String msg) {
  if (msg.startsWith('SparkSdkError: ')) return SdkError.sparkError(_rest(msg, 'SparkSdkError: '));
  if (msg == 'Insufficient funds') return const SdkError.insufficientFunds();
  if (msg.startsWith('Insufficient funds for token ')) {
    return SdkError.insufficientFunds(tokenIdentifier: _rest(msg, 'Insufficient funds for token '));
  }
  if (msg.startsWith('Invalid UUID: ')) return SdkError.invalidUuid(_rest(msg, 'Invalid UUID: '));
  if (msg.startsWith('Invalid input: ')) return SdkError.invalidInput(_rest(msg, 'Invalid input: '));
  if (msg.startsWith('Cross-chain route temporarily unavailable: ')) {
    return SdkError.crossChainRouteUnavailable(
      reason: _rest(msg, 'Cross-chain route temporarily unavailable: '),
      temporary: true,
    );
  }
  if (msg.startsWith('Cross-chain route not supported: ')) {
    return SdkError.crossChainRouteUnavailable(
      reason: _rest(msg, 'Cross-chain route not supported: '),
      temporary: false,
    );
  }
  if (msg.startsWith('Network error: ')) return SdkError.networkError(_rest(msg, 'Network error: '));
  if (msg.startsWith('Storage error: ')) return SdkError.storageError(_rest(msg, 'Storage error: '));
  if (msg.startsWith('Chain service error: ')) {
    return SdkError.chainServiceError(_rest(msg, 'Chain service error: '));
  }
  final maxFee = _match(
    r'^Max deposit claim fee exceeded for utxo: (\w+):(\d+) with max fee: (.*) and required fee: (\d+) sats or (\d+) sats/vbyte$',
    msg,
  );
  if (maxFee != null) {
    return SdkError.maxDepositClaimFeeExceeded(
      tx: maxFee.group(1)!,
      vout: int.parse(maxFee.group(2)!),
      maxFee: _debugFee(maxFee.group(3)!),
      requiredFeeSats: BigInt.parse(maxFee.group(4)!),
      requiredFeeRateSatPerVbyte: BigInt.parse(maxFee.group(5)!),
    );
  }
  final missing = _match(r'^Missing utxo: (\w+):(\d+)$', msg);
  if (missing != null) {
    return SdkError.missingUtxo(tx: missing.group(1)!, vout: int.parse(missing.group(2)!));
  }
  final inProgress = _match(r'^Deposit claim already in progress: (\w+):(\d+)$', msg);
  if (inProgress != null) {
    return SdkError.depositClaimInProgress(tx: inProgress.group(1)!, vout: int.parse(inProgress.group(2)!));
  }
  final refund = _match(
    r'^A refund is already pending at (\d+) sats: a replacement must pay at least (\d+) sats$',
    msg,
  );
  if (refund != null) {
    return SdkError.refundReplacementFeeTooLow(
      pendingFeeSats: BigInt.parse(refund.group(1)!),
      requiredFeeSats: BigInt.parse(refund.group(2)!),
    );
  }
  if (msg.startsWith('Lnurl error: ')) return SdkError.lnurlError(_rest(msg, 'Lnurl error: '));
  if (msg.startsWith('Signer error: ')) return SdkError.signer(_rest(msg, 'Signer error: '));
  if (msg == 'Optimization is already in progress') return const SdkError.optimizationAlreadyRunning();
  if (msg == 'Optimization was cancelled by the SDK to free leaves') {
    return const SdkError.optimizationCancelled();
  }
  final cpfp = _match(r'^Insufficient CPFP funding: need at least (\d+) sats$', msg);
  if (cpfp != null) return SdkError.insufficientCpfpFunds(requiredSat: BigInt.parse(cpfp.group(1)!));
  if (msg.startsWith('Error: ')) return SdkError.generic(_rest(msg, 'Error: '));
  return SdkError.generic(msg);
}

/// Parses the `Display` text of `breez_sdk_spark::passkey::PrfProviderError`.
PrfProviderError? tryParsePrfProviderError(String msg) {
  if (msg == 'PRF not supported by authenticator') return const PrfProviderError.prfNotSupported();
  if (msg == 'User cancelled authentication') return const PrfProviderError.userCancelled();
  if (msg == 'Authenticator timed out') return const PrfProviderError.userTimedOut();
  const prefixes = {
    'Credential not found: ': PrfProviderError.credentialNotFound,
    'Authentication failed: ': PrfProviderError.authenticationFailed,
    'PRF evaluation failed: ': PrfProviderError.prfEvaluationFailed,
    'Configuration error: ': PrfProviderError.configuration,
    'Credential already exists: ': PrfProviderError.credentialAlreadyExists,
  };
  for (final e in prefixes.entries) {
    if (msg.startsWith(e.key)) return e.value(_rest(msg, e.key));
  }
  if (msg.startsWith('Passkey error: ')) {
    final inner = _rest(msg, 'Passkey error: ');
    return tryParsePrfProviderError(inner) ?? PrfProviderError.generic(inner);
  }
  return null;
}

PrfProviderError parsePrfProviderError(String msg) =>
    tryParsePrfProviderError(msg) ?? PrfProviderError.generic(msg);

/// Parses the `Display` text of `breez_sdk_spark::passkey::PasskeyError`.
PasskeyError parsePasskeyError(String msg) {
  if (msg.startsWith('PRF error: ')) {
    return PasskeyError.prf(parsePrfProviderError(_rest(msg, 'PRF error: ')));
  }
  if (msg.startsWith('Passkey created but derivation failed: ')) {
    // The credential id is not part of the error text the wasm SDK throws.
    return PasskeyError.createdButNotDerived(
      credentialId: Uint8List(0),
      source: parsePrfProviderError(_rest(msg, 'Passkey created but derivation failed: ')),
    );
  }
  const prefixes = {
    'Nostr relay connection failed: ': PasskeyError.relayConnectionFailed,
    'Nostr write failed: ': PasskeyError.nostrWriteFailed,
    'Nostr read failed: ': PasskeyError.nostrReadFailed,
    'Key derivation error: ': PasskeyError.keyDerivationError,
    'Invalid PRF output: ': PasskeyError.invalidPrfOutput,
    'Mnemonic error: ': PasskeyError.mnemonicError,
    'Invalid salt: ': PasskeyError.invalidSalt,
    'Invalid passkey configuration: ': PasskeyError.invalidConfig,
  };
  for (final e in prefixes.entries) {
    if (msg.startsWith(e.key)) return e.value(_rest(msg, e.key));
  }
  if (msg.startsWith('Passkey error: ')) {
    final inner = _rest(msg, 'Passkey error: ');
    final prf = tryParsePrfProviderError(inner);
    return prf != null ? PasskeyError.prf(prf) : PasskeyError.generic(inner);
  }
  return PasskeyError.generic(msg);
}

/// Error mapper for BreezSdk / SdkBuilder / TokenIssuer calls.
Object mapJsSdkError(Object error) {
  if (error is Error || error is Exception) return error;
  return parseSdkError(jsErrorInfo(error).message);
}

/// Error mapper for PasskeyClient / PasskeyLabels calls.
Object mapJsPasskeyError(Object error) {
  if (error is Error || error is Exception) return error;
  return parsePasskeyError(jsErrorInfo(error).message);
}
