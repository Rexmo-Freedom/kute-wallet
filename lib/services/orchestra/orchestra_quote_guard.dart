import 'package:flutter/foundation.dart';
// lib/services/orchestra/orchestra_quote_guard.dart
//
// The one validator every Orchestra quote passes before it is paid. The
// backend proxy is a passthrough, so the quote is compared only with what
// the app asked for, local constants and the independently fetched local
// price. Pure: no network, no Riverpod, no widgets.

import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

/// Whose address the quote delivers to.
enum RecipientKind { ownSpark, ownEvm, ownPmWallet, external }

class OrchestraQuoteRequest {
  const OrchestraQuoteRequest({
    required this.sourceChain,
    required this.sourceAsset,
    required this.destinationChain,
    required this.destinationAsset,
    required this.amountBaseUnits,
    required this.recipientAddress,
    required this.refundAddress,
    required this.recipientKind,
    this.ownAddress,
    this.deliveryMode,
    this.externalDepositMemo = false,
  });

  final String sourceChain;
  final String sourceAsset;
  final String destinationChain;
  final String destinationAsset;

  /// Exact-in amount in the source asset's smallest unit.
  final BigInt amountBaseUnits;
  final String recipientAddress;
  final String refundAddress;
  final RecipientKind recipientKind;

  /// Leave existing transfer behavior unchanged unless a flow explicitly
  /// requests variable delivery for a route without fixed delivery support.
  final String? deliveryMode;

  /// Only a receive surface that displays, persists and exports the memo may opt in.
  final bool externalDepositMemo;

  /// The app-resolved own address for every `own*` [recipientKind]; the
  /// recipient must equal it. Null for [RecipientKind.external].
  final String? ownAddress;

  /// Analytics label, e.g. `spark_btc>polygon_usdc.e`. No amounts or
  /// addresses.
  String get routeLabel =>
      '${sourceChain}_$sourceAsset>${destinationChain}_$destinationAsset'
          .toLowerCase();
}

class OrchestraQuoteBounds {
  const OrchestraQuoteBounds({
    this.maxFeeBps = defaultMaxFeeBps,
    this.minOutRatio = defaultMinOutRatio,
    required this.inputValueInOutputUnits,
    required this.expiryMargin,
  });

  /// Bounds with the default expiry margin for [sourceChain]: Spark
  /// sources pay instantly, anything else (the Polygon relayer) needs
  /// more headroom because late funding is repriced or rejected.
  factory OrchestraQuoteBounds.forSource(
    String sourceChain, {
    required double? inputValueInOutputUnits,
    int maxFeeBps = defaultMaxFeeBps,
    double minOutRatio = defaultMinOutRatio,
  }) =>
      OrchestraQuoteBounds(
        maxFeeBps: maxFeeBps,
        minOutRatio: minOutRatio,
        inputValueInOutputUnits: inputValueInOutputUnits,
        expiryMargin: sourceChain.trim().toLowerCase() == 'spark'
            ? sparkSourceExpiryMargin
            : relayerSourceExpiryMargin,
      );

  /// Safety ceiling on the total fee a quote may carry before the app
  /// refuses to fund it. A guard against a bad or compromised quote, not
  /// Kute's fee: the fee itself always comes from the backend quote.
  static const int defaultMaxFeeBps = 400;

  /// Retained so existing callers and stored bounds still compile, and
  /// so the reference price keeps reaching the analytics for a refused
  /// quote. Nothing in [verifyOrchestraQuote] consults it: see the note
  /// there on why an output ratio cannot tell a small deposit paying a
  /// bridge apart from a bad route.
  static const double defaultMinOutRatio = 0.5;
  static const Duration sparkSourceExpiryMargin = Duration(seconds: 15);
  static const Duration relayerSourceExpiryMargin = Duration(seconds: 60);

  /// Flashnet quotes are valid for 2 minutes. A later `expiresAt` is
  /// capped at this long after the quote was verified, so a stored quote
  /// cannot be paid at a stale price.
  static const Duration maxQuoteLifetime = Duration(minutes: 2);

  final int maxFeeBps;
  final double minOutRatio;

  /// The request amount valued at the local price, in the destination
  /// asset's smallest unit. Null or non-positive means no local price.
  final double? inputValueInOutputUnits;
  final Duration expiryMargin;
}

/// A quote that passed [verifyOrchestraQuote]. Only this library can
/// construct one.
class VerifiedOrchestraQuote {
  VerifiedOrchestraQuote._({
    required this.quote,
    required this.request,
    required this.amountIn,
    required this.expiresAt,
    required this.expiryMargin,
  });

  final OrchestraQuote quote;
  final OrchestraQuoteRequest request;
  final BigInt amountIn;
  final DateTime expiresAt;
  final Duration expiryMargin;

  String get quoteId => quote.quoteId;
  String get depositAddress => quote.depositAddress;
}

final RegExp _unsignedInteger = RegExp(r'^\d+$');

BigInt? _parseBaseUnits(String? raw) {
  final s = raw?.trim() ?? '';
  return _unsignedInteger.hasMatch(s) ? BigInt.parse(s) : null;
}

/// The largest millisecond timestamp [DateTime] can represent.
const int _maxEpochMilliseconds = 8640000000000000;

/// Unix seconds or milliseconds, or ISO-8601. An ISO string without a
/// zone designator is read as UTC, never device-local time.
DateTime? _parseExpiry(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (_unsignedInteger.hasMatch(s)) {
    final n = int.tryParse(s);
    if (n == null) return null;
    final ms = n >= 100000000000 ? n : n * 1000;
    if (ms > _maxEpochMilliseconds) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  final parsed = DateTime.tryParse(s);
  if (parsed == null || parsed.isUtc) return parsed;
  return DateTime.tryParse('${s}Z');
}

bool _sameAddressOnChain(String chain, String a, String b) {
  final slug = chain.trim().toLowerCase();
  if (slug == 'spark') return sameSparkAddress(a, b);
  if (kEvmAddressChains.contains(slug)) return sameEvmAddress(a, b);
  return a.trim() == b.trim();
}

bool _sameLabel(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

Never _reject(WalletGuardReason reason, [String? field]) =>
    throw WalletGuardException(reason, field: field);

/// Checks [quote] against [request], the pins and the local price, in the
/// order of the Phase 2 plan (D6). Throws [WalletGuardException] on the
/// first failed rule.
VerifiedOrchestraQuote verifyOrchestraQuote(
  OrchestraQuoteRequest request,
  OrchestraQuote quote, {
  required DateTime now,
  required OrchestraQuoteBounds bounds,
  required bool mainnet,
}) {
  if (quote.quoteId.trim().isEmpty) {
    _reject(WalletGuardReason.quoteMissingId);
  }

  if (formatMatchesChain(request.sourceChain, quote.depositAddress,
          mainnet: mainnet) !=
      AddressFormatMatch.ok) {
    _reject(WalletGuardReason.depositAddressFormat);
  }

  final memo = quote.depositMemo ?? '';
  if (memo.isNotEmpty) {
    final chain = request.sourceChain.toLowerCase();
    final valid = chain == 'xrp'
        ? RegExp(r'^\d{1,10}$').hasMatch(memo) &&
            BigInt.parse(memo) <= BigInt.from(4294967295)
        : chain == 'ton' &&
            memo.length <= 128 &&
            !memo.runes.any((c) => c < 32 || c == 127);
    if (!request.externalDepositMemo || !valid) {
      _reject(WalletGuardReason.depositMemoPresent);
    }
  }

  final amountIn = quote.present.contains('amountIn')
      ? _parseBaseUnits(quote.amountIn)
      : null;
  if (amountIn == null || amountIn != request.amountBaseUnits) {
    _reject(WalletGuardReason.amountMismatch);
  }

  final expiresAt = _parseExpiry(quote.expiresAt);
  if (expiresAt == null || !expiresAt.isAfter(now.add(bounds.expiryMargin))) {
    _reject(WalletGuardReason.quoteExpired);
  }

  if (formatMatchesChain(request.sourceChain, request.refundAddress,
          mainnet: mainnet) !=
      AddressFormatMatch.ok) {
    _reject(WalletGuardReason.refundAddressChain);
  }
  if (formatMatchesChain(request.destinationChain, request.recipientAddress,
          mainnet: mainnet) !=
      AddressFormatMatch.ok) {
    _reject(WalletGuardReason.recipientAddressChain);
  }
  if (request.recipientKind != RecipientKind.external) {
    final own = request.ownAddress;
    if (own == null ||
        !_sameAddressOnChain(
            request.destinationChain, request.recipientAddress, own)) {
      _reject(WalletGuardReason.recipientNotOwn);
    }
  }

  if (!quote.present.contains('feeBps') ||
      quote.feeBps < 0 ||
      (quote.present.contains('appFees') && quote.appFeeBps == null) ||
      quote.combinedFeeBps > bounds.maxFeeBps) {
    _reject(WalletGuardReason.feeAboveCap);
  }

  // STRICT OUTPUT PARSING. The quoted output is what the person is shown
  // before signing, so it must be a real positive amount in base units.
  // A missing, empty, non-integer, signed or zero estimate, or a locked
  // minimum that is present but not such an amount, is a malformed
  // quote and is refused. This checks the quote's own statement, not a
  // ratio against a reference (see below).
  final estimatedOut = quote.present.contains('estimatedOut')
      ? _parseBaseUnits(quote.estimatedOut)
      : null;
  if (estimatedOut == null || estimatedOut <= BigInt.zero) {
    _reject(WalletGuardReason.outputMalformed, 'estimated_out');
  }
  if (quote.present.contains('lockedMinAmountOut')) {
    final locked = _parseBaseUnits(quote.lockedMinAmountOut);
    if (locked == null || locked <= BigInt.zero) {
      _reject(WalletGuardReason.outputMalformed, 'locked_min_amount_out');
    }
  }

  // NO OUTPUT FLOOR. Nothing here refuses a quote for delivering less
  // than some ratio of what this side thinks the input is worth.
  //
  // There used to be two such rules and both were wrong in the same way.
  // They measured the quote against a number this app computed — its own
  // price feed, or the estimate the lock is a floor of — and then refused
  // the transfer when the two disagreed. What they actually caught was
  // the cost of the route. Into HyperCore that cost is close to fixed:
  // measured live, a 1000 dollar deposit keeps 99.8 percent, 100 keeps
  // 98.7, 10 keeps 87.6 and 5 keeps 75.2. Nothing is broken at 5 dollars;
  // it is a small deposit paying a bridge. A ratio rule cannot tell those
  // apart from a hostile route, so it refused honest transfers, and the
  // person was told their amount was too small by a wallet that would not
  // move their own money.
  //
  // What remains is what the quote itself states and this side can check
  // without inventing a reference: the declared fee against [maxFeeBps]
  // above, the amount in, the expiry, the addresses and every echoed
  // field. The size of the outcome is the person's call, and the sheet
  // shows it to them before they sign.
  if (kDebugMode) {
    debugPrint('[quote-guard] ${request.routeLabel}: '
        'in=${quote.amountIn} estimatedOut=${quote.estimatedOut} '
        'locked=${quote.lockedMinAmountOut ?? '-'} '
        'feeBps=${quote.combinedFeeBps}');
  }

  void echo(String field, String? value, bool Function(String) matches) {
    if (value != null && !matches(value)) {
      _reject(WalletGuardReason.echoMismatch, field);
    }
  }

  echo('source_chain', quote.sourceChain,
      (v) => _sameLabel(v, request.sourceChain));
  echo('source_asset', quote.sourceAsset,
      (v) => _sameLabel(v, request.sourceAsset));
  echo('destination_chain', quote.destinationChain,
      (v) => _sameLabel(v, request.destinationChain));
  echo('destination_asset', quote.destinationAsset,
      (v) => _sameLabel(v, request.destinationAsset));
  echo(
      'recipient_address',
      quote.recipientAddress,
      (v) => _sameAddressOnChain(
          request.destinationChain, v, request.recipientAddress));
  echo(
      'refund_address',
      quote.refundAddress,
      (v) =>
          _sameAddressOnChain(request.sourceChain, v, request.refundAddress));

  final latestExpiry = now.add(OrchestraQuoteBounds.maxQuoteLifetime);
  return VerifiedOrchestraQuote._(
    quote: quote,
    request: request,
    amountIn: amountIn,
    expiresAt: expiresAt.isAfter(latestExpiry) ? latestExpiry : expiresAt,
    expiryMargin: bounds.expiryMargin,
  );
}
