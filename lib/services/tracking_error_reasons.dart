/// Canonical analytics error-reason taxonomy. Every `*Failed` event
/// param `reason` should be one of these strings — keeps BigQuery
/// funnel queries from bucketing two synonyms separately and lets
/// support filter "show me everyone who hit `insufficient_funds` in
/// the last 24h" without rebuilding the dimension.
///
/// Add new reasons here when a NEW class of failure shows up.
/// Don't reuse existing values for new meanings — historical data
/// already lives at that key.
class TrackingErrorReasons {
  TrackingErrorReasons._();

  // ─── Money-side ────────────────────────────────────────────────
  static const insufficientFunds = 'insufficient_funds';
  static const slippageExceeded = 'slippage_exceeded';
  static const feeTooHigh = 'fee_too_high';
  static const amountBelowMin = 'amount_below_min';
  static const amountAboveMax = 'amount_above_max';
  static const balanceMismatch = 'balance_mismatch';
  static const payoutSendFailed = 'payout_send_failed';

  // ─── Market / order ────────────────────────────────────────────
  static const marketClosed = 'market_closed';
  static const marketResolved = 'market_resolved';
  static const orderRejected = 'order_rejected';
  static const orderExpired = 'order_expired';
  static const orderCancelled = 'order_cancelled';
  static const noPayoutCredited = 'no_payout_credited';
  static const quoteExpired = 'quote_expired';

  // ─── Exchange signing / sequencing (Hyperliquid) ───────────────
  /// The exchange rejected our nonce (stale/out-of-order). Distinct
  /// from order_rejected: it is retryable and never the user's fault.
  static const nonceRejected = 'nonce_rejected';

  /// The exchange couldn't recover our address from the signature
  /// ("User or API Wallet … does not exist"). This is an engineering
  /// defect (byte-order/serialization bug), never user error — alert on
  /// any occurrence.
  static const signatureInvalid = 'signature_invalid';

  // ─── Network / infra ───────────────────────────────────────────
  static const networkTimeout = 'network_timeout';
  static const networkOffline = 'network_offline';
  static const rpcError = 'rpc_error';
  static const sdkNotReady = 'sdk_not_ready';
  static const apiUnavailable = 'api_unavailable';
  static const httpError = 'http_error';

  // ─── Compliance / auth ─────────────────────────────────────────
  static const kycRequired = 'kyc_required';
  static const kycRejected = 'kyc_rejected';
  static const regionRestricted = 'region_restricted';
  static const unauthorized = 'unauthorized';
  static const sessionExpired = 'session_expired';
  static const selfReferralRejected = 'self_referral_rejected';
  static const codeNotFound = 'code_not_found';

  // ─── User-driven ───────────────────────────────────────────────
  static const userCanceled = 'user_canceled';
  static const userAbandoned = 'user_abandoned';
  static const userDeclinedBiometric = 'user_declined_biometric';

  // ─── Other ─────────────────────────────────────────────────────
  /// Use when a failure path is genuinely "we don't know yet". Adding
  /// a new reason later doesn't require backfilling old `unknown`
  /// rows — they stay opaque, which is honest.
  static const unknown = 'unknown';
}
