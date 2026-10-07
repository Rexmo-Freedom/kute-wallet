// lib/services/orchestra/orchestra_quote_gate.dart
//
// The only place the app asks Orchestra for a quote. [fetchVerified]
// never hands back a quote that skipped [verifyOrchestraQuote], and
// [ensurePayable] re-checks expiry and amount right before the payment
// call, for flows that persist a row or wait for a tap in between.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraDecimalsMismatch, pinnedOrchestraDecimals;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/handlers/response_handlers.dart' show Result;
import 'package:kute/models/orchestra_model.dart' show OrchestraQuote;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/settlement_http.dart'
    show callWithIdempotencyKey, clockSkewFromHeaders;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

/// The quote request itself failed (network, backend or Flashnet error).
/// Distinct from a [WalletGuardException], which means a quote arrived
/// and was refused.
class OrchestraQuoteFailure implements Exception {
  const OrchestraQuoteFailure(this.message, {this.routeError});

  final String message;

  /// Set when Flashnet refused the amount or the route with a known code.
  /// The UI shows its copy instead of [message].
  final RouteQuoteError? routeError;

  @override
  String toString() => message;
}

class OrchestraQuoteGate {
  OrchestraQuoteGate._();

  /// Spark on this app always runs on mainnet (lib/models/breez/init.dart).
  static const bool _sparkMainnet = true;

  /// Quotes [request] and verifies the response. [flow] names the calling
  /// flow for the rejection event. Throws [WalletGuardException] when the
  /// quote is refused and [OrchestraQuoteFailure] when none arrived.
  static Future<VerifiedOrchestraQuote> fetchVerified(
    OrchestraQuoteRequest request,
    OrchestraQuoteBounds bounds, {
    required String flow,
    int? slippageBps,
    String? idempotencyKey,
    DateTime Function() clock = DateTime.now,
    bool mainnet = _sparkMainnet,
  }) async {
    void reportRejection(WalletGuardException e) {
      TrackingService.orchestraQuoteRejected(
        flow: flow,
        route: request.routeLabel,
        reason: e.reason.code,
      );
    }

    if (orchestraDecimalsMismatch(request.sourceChain, request.sourceAsset) ||
        orchestraDecimalsMismatch(
            request.destinationChain, request.destinationAsset)) {
      const rejection =
          WalletGuardException(WalletGuardReason.decimalsMismatch);
      reportRejection(rejection);
      throw rejection;
    }

    final fetched = await fetchVerifiedWithSkew(
      request,
      bounds,
      flow: flow,
      slippageBps: slippageBps,
      idempotencyKey: idempotencyKey,
      clock: clock,
      mainnet: mainnet,
      retryTransport: false,
    );
    return fetched.quote;
  }

  /// [fetchVerified] that also returns the server clock skew from the
  /// quote response's `Date` header (null when the header is missing).
  /// With [retryTransport] a timeout, 5xx or 429 is retried with the same
  /// idempotency key (Phase 5 plan B7), and expiry is verified against the
  /// clock when the last attempt returned.
  static Future<({VerifiedOrchestraQuote quote, Duration? skew})>
      fetchVerifiedWithSkew(
    OrchestraQuoteRequest request,
    OrchestraQuoteBounds bounds, {
    required String flow,
    int? slippageBps,
    String? idempotencyKey,
    DateTime Function() clock = DateTime.now,
    bool mainnet = _sparkMainnet,
    bool retryTransport = true,
  }) async {
    void reportRejection(WalletGuardException e) {
      TrackingService.orchestraQuoteRejected(
        flow: flow,
        route: request.routeLabel,
        reason: e.reason.code,
      );
    }

    if (orchestraDecimalsMismatch(request.sourceChain, request.sourceAsset) ||
        orchestraDecimalsMismatch(
            request.destinationChain, request.destinationAsset)) {
      const rejection =
          WalletGuardException(WalletGuardReason.decimalsMismatch);
      reportRejection(rejection);
      throw rejection;
    }

    Future<Result<OrchestraQuote>> send(String? key) =>
        OrchestraService.createQuote(
          sourceChain: request.sourceChain,
          sourceAsset: request.sourceAsset,
          destinationChain: request.destinationChain,
          destinationAsset: request.destinationAsset,
          amount: request.amountBaseUnits.toString(),
          recipientAddress: request.recipientAddress,
          refundAddress: request.refundAddress,
          deliveryMode: request.deliveryMode,
          slippageBps: slippageBps,
          idempotencyKey: key,
        );

    final Result<OrchestraQuote> result;
    if (retryTransport) {
      final call = await callWithIdempotencyKey<OrchestraQuote>(
        key: idempotencyKey ?? OrchestraService.generateIdempotencyKey(),
        call: send,
      );
      result = call.result;
    } else {
      result = await send(idempotencyKey);
    }
    final receivedAt = clock();
    final quote = result.data;
    if (!result.isSuccess || quote == null) {
      final code = RouteQuoteErrorCode.fromCode(result.errorCode);
      throw OrchestraQuoteFailure(
        result.error ?? 'Failed to get quote',
        routeError: code == null ? null : RouteQuoteError(code),
      );
    }
    try {
      final verified = verifyOrchestraQuote(
        request,
        quote,
        now: receivedAt,
        bounds: bounds,
        mainnet: mainnet,
      );
      return (
        quote: verified,
        skew: clockSkewFromHeaders(result.headers, receivedAt: receivedAt),
      );
    } on WalletGuardException catch (e) {
      reportRejection(e);
      rethrow;
    }
  }

  /// Dollar assets whose unit is $1, so a BTC leg against them has a
  /// reference price. The dollar account's own token belongs here: it is
  /// a first-class Orchestra asset with pinned 6 decimals, and without it
  /// a bitcoin-to-dollars quote would be refused as `no_reference_price`.
  static const Set<String> _usdStablecoins = {
    'USDC',
    'USDC.E',
    'USDT',
    'USDB',
  };

  /// [request]'s amount valued at [usdPerBtc] (the local price), in the
  /// destination asset's smallest unit. Only BTC to a USD stablecoin and
  /// back have a reference, and only when both legs have pinned decimals
  /// (catalog decimals come from the backend and would scale the value).
  /// Any other pair, or no usable price, answers null. The guard no longer
  /// refuses on this value (see "NO OUTPUT FLOOR" in
  /// orchestra_quote_guard.dart); it only rides along in the bounds.
  @visibleForTesting
  static double? referenceOutputUnits(
    OrchestraQuoteRequest request, {
    required double usdPerBtc,
  }) {
    final source = request.sourceAsset.trim().toUpperCase();
    final destination = request.destinationAsset.trim().toUpperCase();
    // A bitcoin leg is priced; a dollar-to-dollar leg is at par and needs
    // no price, so the missing-price rejection applies only to the legs
    // that actually use one.
    final pricedLeg = source == 'BTC' || destination == 'BTC';
    if (pricedLeg && (!usdPerBtc.isFinite || usdPerBtc <= 0)) return null;
    final sourceDecimals =
        pinnedOrchestraDecimals(request.sourceChain, source);
    final destinationDecimals =
        pinnedOrchestraDecimals(request.destinationChain, destination);
    if (sourceDecimals == null || destinationDecimals == null) return null;
    final input =
        request.amountBaseUnits.toDouble() / math.pow(10, sourceDecimals);
    final double output;
    if (source == 'BTC' && _usdStablecoins.contains(destination)) {
      output = input * usdPerBtc;
    } else if (_usdStablecoins.contains(source) && destination == 'BTC') {
      output = input / usdPerBtc;
    } else if (_usdStablecoins.contains(source) &&
        _usdStablecoins.contains(destination)) {
      // Dollar to dollar, at par. Both units are $1 by construction, so
      // the reference needs no price at all and the only thing the floor
      // has to absorb is the route's fee. Without this branch the dollar
      // balance could not fund anything: every dollars-to-dollars quote
      // would be refused as `no_reference_price`.
      output = input;
    } else {
      return null;
    }
    return output * math.pow(10, destinationDecimals);
  }

  /// Default bounds for [request], with the input valued at the local
  /// [usdPerBtc] price for reference.
  static OrchestraQuoteBounds boundsFor(
    OrchestraQuoteRequest request, {
    required double usdPerBtc,
  }) =>
      OrchestraQuoteBounds.forSource(
        request.sourceChain,
        inputValueInOutputUnits:
            referenceOutputUnits(request, usdPerBtc: usdPerBtc),
      );

  /// For a quote kept on screen until a later tap. Returns [stored] when
  /// it is still payable for [amountBaseUnits]. When it expired or the
  /// amount changed, fetches exactly one replacement through [requote]
  /// and returns it with `refreshed: true`; the caller shows it and waits
  /// for another confirmation instead of paying.
  static Future<({VerifiedOrchestraQuote quote, bool refreshed})>
      confirmStored(
    VerifiedOrchestraQuote stored, {
    required BigInt amountBaseUnits,
    required Future<VerifiedOrchestraQuote> Function() requote,
    DateTime Function() clock = DateTime.now,
  }) async {
    try {
      ensurePayable(stored, amountBaseUnits: amountBaseUnits, now: clock());
      return (quote: stored, refreshed: false);
    } on WalletGuardException catch (e) {
      if (e.reason != WalletGuardReason.quoteExpired &&
          e.reason != WalletGuardReason.amountMismatch) {
        rethrow;
      }
    }
    return (quote: await requote(), refreshed: true);
  }

  /// Runs immediately before paying [quote]: the amount about to be paid
  /// must equal the quoted amount, and the quote must still be outside
  /// its expiry margin.
  static void ensurePayable(
    VerifiedOrchestraQuote quote, {
    required BigInt amountBaseUnits,
    required DateTime now,
  }) {
    if (!quote.expiresAt.isAfter(now.add(quote.expiryMargin))) {
      throw const WalletGuardException(WalletGuardReason.quoteExpired);
    }
    if (amountBaseUnits != quote.amountIn) {
      throw const WalletGuardException(WalletGuardReason.amountMismatch);
    }
  }
}
