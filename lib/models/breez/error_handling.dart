import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:kute/services/tracking_service.dart';

/// The SDK refused a payment because the balance cannot cover the amount
/// plus its fees ([SdkError_InsufficientFunds], or the same refusal said
/// in words by the engine underneath). Typed so a screen can answer it in
/// the user's language without reading the text; [toString] stays the
/// sentence it always was for everything that still reads it.
class SparkInsufficientFundsException implements Exception {
  const SparkInsufficientFundsException();

  static const message =
      "Insufficient balance. The amount plus network fees exceeds your balance. Try a smaller amount, or tap 100% to send everything.";

  @override
  String toString() => 'Exception: $message';
}

/// True when [error] is the SDK's not-enough-balance refusal, by type: the
/// raw [SdkError_InsufficientFunds] or what [handlePaymentException] turns
/// it into.
bool isSparkInsufficientFunds(Object? error) =>
    error is SparkInsufficientFundsException ||
    error is SdkError_InsufficientFunds;

/// Centralized error handler for Breez SDK operations.
/// Parses structured [SdkError] and raw exception strings into
/// user-friendly messages.
///
/// Every branch routes through `_throwParsedMessage` so the message
/// goes through the allowlist + final scrub before becoming an
/// Exception that might bubble up to Crashlytics. Previously the
/// `invalidUuid` / `invalidInput` / `networkError` / `storageError`
/// / `lnurlError` / `signer` branches inlined the raw `err.field0`
/// from the Rust bridge directly — and that field has historically
/// carried UTXO ids, deposit addresses, and invoice fragments.
Never handlePaymentException(Object e) {
  if (e is SdkError) {
    e.map(
      sparkError: (err) => _throwParsedMessage(err.field0),
      invalidUuid: (err) => _throwParsedMessage('Invalid ID: ${err.field0}'),
      invalidInput: (err) => _throwParsedMessage('Invalid input: ${err.field0}'),
      networkError: (err) => _throwParsedMessage('Network error: ${err.field0}'),
      storageError: (err) => _throwParsedMessage('Storage error: ${err.field0}'),
      chainServiceError: (err) => _throwParsedMessage(err.field0),
      maxDepositClaimFeeExceeded: (err) => throw Exception(
        "The claim requires ${err.requiredFeeSats} sats, above the approved fee limit.",
      ),
      missingUtxo: (err) => throw Exception("Transaction output missing (UTXO)."),
      // Both carry a raw txid; never inline it.
      depositClaimInProgress: (err) => throw Exception(
          "This deposit is already being claimed. Please wait a moment."),
      refundReplacementFeeTooLow: (err) => throw Exception(
          "The refund fee must be above the ${err.pendingFeeSats} sats of the pending refund. Required: ${err.requiredFeeSats} sats."),
      // Cross-chain routes (breez 0.26). The app's cross-chain sends go
      // through Orchestra directly, so these are exhaustiveness branches.
      crossChainAmountOutOfRange: (err) => throw Exception(err.tooSmall
          ? "This amount is below the route's minimum."
          : "This amount is above the route's maximum."),
      crossChainRouteUnavailable: (err) => throw Exception(err.temporary
          ? "This route is unavailable right now. Please try again later."
          : "This route is not available."),
      lnurlError: (err) => _throwParsedMessage('LNURL error: ${err.field0}'),
      signer: (err) => _throwParsedMessage('Signer error: ${err.field0}'),
      insufficientFunds: (err) =>
          throw const SparkInsufficientFundsException(),
      // Background auto-optimization (leaf/UTXO consolidation) signalling —
      // these aren't user-actionable payment failures, but `map` requires a
      // branch for every variant, so route them through a calm message.
      optimizationAlreadyRunning: (err) =>
          throw Exception("Wallet optimization is already in progress. Please try again in a moment."),
      optimizationCancelled: (err) =>
          throw Exception("Wallet optimization was cancelled."),
      // Unilateral-exit error (new in breez 0.23). The app never calls
      // prepareUnilateralExit/unilateralExit today, so this is a defensive
      // exhaustiveness branch.
      insufficientCpfpFunds: (err) => throw Exception(
          "Not enough funds to cover the exit fee. Required: ${err.requiredSat} sats."),
      generic: (err) => _throwParsedMessage(err.field0),
    );
  }
  _throwParsedMessage(e.toString());
  throw e;
}

/// Scrub a Breez SDK error string before letting it bubble up as an
/// Exception. Strips long hex tokens, bech32 LN/BTC strings, and
/// base58 addresses; caps total length. Mirrors the policy in
/// `TrackingService._safeReason` so messages can't carry payloads
/// into Crashlytics or any other sink.
String _scrubSdkMessage(String raw) {
  // The shared redactor first (keys, descriptors, addresses, invoices,
  // phrases, UUIDs; URLs cut to scheme + host), then the stricter rules.
  var s = TrackingService.scrubString(raw);
  s = s.replaceAll(RegExp(r'\b(?:0x)?[0-9a-fA-F]{12,}\b'), '<hex>');
  s = s.replaceAll(
      RegExp(r'\b(?:bc1|tb1|lnbc|lntb|lnbcrt)[0-9a-z]{20,}\b'), '<addr>');
  s = s.replaceAll(RegExp(r'\b[1-9A-HJ-NP-Za-km-z]{26,}\b'), '<addr>');
  if (s.length > 120) s = '${s.substring(0, 117)}...';
  return s;
}

void _throwParsedMessage(String msg) {
  final lowerMsg = msg.toLowerCase();

  // A. Handle Bitcoin Dust Error (Tuple format from backend)
  // Example: ('Output amount %d sats cannot be smaller than the minimal non dust amount %d sats', 10, 294)
  if (lowerMsg.contains("minimal non dust amount")) {
    // Try to extract the limit (the last number in the tuple)
    // Regex matches the comma followed by space and digits at the end of the tuple string
    final RegExp regex = RegExp(r',\s*(\d+)\s*\)$');
    final match = regex.firstMatch(msg);

    if (match != null) {
      final minSats = match.group(1);
      throw Exception("Amount is too small. Minimum allowed is $minSats sats.");
    }
    throw Exception("Amount is too small (Bitcoin Dust Limit).");
  }

  // B. Handle Insufficient Funds
  if (lowerMsg.contains("insufficient funds") || lowerMsg.contains("insufficient balance")) {
    throw const SparkInsufficientFundsException();
  }

  // C. Handle Route errors
  if (lowerMsg.contains("route not found") || lowerMsg.contains("no route")) {
    throw Exception("No route to destination. Recipient might be offline.");
  }

  // D. Generic Cleanup
  // Removes technical prefixes, then scrubs the message of addresses
  // / invoices / hex tokens so an unhandled bubble-up doesn't leak
  // payloads into Crashlytics.
  var cleanMsg = msg
      .replaceAll(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'^graphql error:\s*'), '')
      .replaceAll("Service error: service provider error: ", "");
  cleanMsg = _scrubSdkMessage(cleanMsg);

  throw Exception(cleanMsg);
}