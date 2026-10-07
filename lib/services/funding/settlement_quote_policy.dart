// lib/services/funding/settlement_quote_policy.dart
//
// Quote timing policy (Phase 5 plan B5). Pure: no network, no Riverpod.
//
//  - Skew-corrected now: the quote response's `Date` header gives the
//    server clock; a missing header adds a 10 s margin.
//  - Minimum time left on a quote per moment and payer (F1 defaults).
//  - Terms classification, used only to decide whether a Phase 1b grant
//    still covers a refreshed quote and which copy the re-review shows.
//    A refreshed quote after review ALWAYS needs another review tap.

/// Who moves the funds for an operation.
enum SettlementPayer {
  /// Hot Spark send.
  sparkHot,

  /// Polygon relayer submission (hot or Ledger batch).
  polygonRelayer,

  /// Ledger Bitcoin PSBT.
  ledgerBitcoin,

  /// Ledger HyperCore action.
  ledgerHypercore,
}

/// The moment a quote's remaining life is checked.
enum SettlementMoment {
  beforeReview('before_review'),
  beforeSend('before_send'),
  beforeDevicePrompt('before_device_prompt'),
  afterDeviceSigned('after_device_signed');

  const SettlementMoment(this.code);

  /// Analytics value.
  final String code;
}

/// Added to every margin when the quote response had no usable `Date`.
const Duration kSettlementMissingSkewMargin = Duration(seconds: 10);

class SettlementQuotePolicy {
  const SettlementQuotePolicy._();

  /// The minimum time that must remain on a quote at [moment] (B5 table).
  static Duration minimumRemaining(
      SettlementMoment moment, SettlementPayer payer) {
    switch (moment) {
      case SettlementMoment.beforeReview:
        return const Duration(seconds: 60);
      case SettlementMoment.beforeSend:
        switch (payer) {
          case SettlementPayer.sparkHot:
            return const Duration(seconds: 15);
          case SettlementPayer.polygonRelayer:
            return const Duration(seconds: 60);
          case SettlementPayer.ledgerBitcoin:
          case SettlementPayer.ledgerHypercore:
            return const Duration(seconds: 90);
        }
      case SettlementMoment.beforeDevicePrompt:
        return const Duration(seconds: 90);
      case SettlementMoment.afterDeviceSigned:
        switch (payer) {
          case SettlementPayer.polygonRelayer:
            return const Duration(seconds: 60);
          case SettlementPayer.sparkHot:
            return const Duration(seconds: 15);
          case SettlementPayer.ledgerBitcoin:
          case SettlementPayer.ledgerHypercore:
            return const Duration(seconds: 20);
        }
    }
  }

  /// The local clock corrected by [skew] (server minus local).
  static DateTime effectiveNow(DateTime localNow, Duration? skew) =>
      localNow.add(skew ?? Duration.zero);

  /// Whether a quote expiring at [expiresAt] still has the margin required
  /// at [moment]. A null [skew] means the response had no usable `Date`
  /// header, which adds [kSettlementMissingSkewMargin].
  static bool hasMargin({
    required DateTime expiresAt,
    required DateTime localNow,
    required Duration? skew,
    required SettlementMoment moment,
    required SettlementPayer payer,
  }) {
    var margin = minimumRemaining(moment, payer);
    if (skew == null) margin += kSettlementMissingSkewMargin;
    return expiresAt.isAfter(effectiveNow(localNow, skew).add(margin));
  }
}

/// The terms a review or a grant covered, in smallest units. No addresses
/// beyond the final recipient, which the step-up binding uses (F3). The
/// deposit address is deliberately not part of these terms.
class SettlementReviewedTerms {
  const SettlementReviewedTerms({
    required this.quoteId,
    required this.recipient,
    required this.routeVersion,
    required this.routeLabel,
    required this.amountIn,
    required this.estimatedOut,
    required this.feeBps,
  });

  final String quoteId;
  final String recipient;
  final String? routeVersion;
  final String routeLabel;
  final BigInt amountIn;
  final BigInt estimatedOut;
  final int feeBps;
}

enum SettlementTermsChange {
  /// Same recipient, route and amount; output not lower, fee not higher.
  withinGrant,

  /// Output lower, fee higher, or recipient, route or amount changed.
  outsideGrant,
}

/// Classifies a refreshed quote against the reviewed one. Only decides
/// grant coverage and copy; it never skips the re-review.
SettlementTermsChange classifySettlementTermsChange(
  SettlementReviewedTerms reviewed,
  SettlementReviewedTerms refreshed,
) {
  if (refreshed.recipient.trim() != reviewed.recipient.trim() ||
      refreshed.routeVersion != reviewed.routeVersion ||
      refreshed.routeLabel != reviewed.routeLabel ||
      refreshed.amountIn != reviewed.amountIn) {
    return SettlementTermsChange.outsideGrant;
  }
  if (refreshed.estimatedOut < reviewed.estimatedOut ||
      refreshed.feeBps > reviewed.feeBps) {
    return SettlementTermsChange.outsideGrant;
  }
  return SettlementTermsChange.withinGrant;
}
