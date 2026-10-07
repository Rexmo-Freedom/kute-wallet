import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hot_twap_guard.dart';

/// Rejections are authoritative. A transport or unclassified failure is not
/// proof that nothing was submitted, so never promise safety or suggest an
/// immediate duplicate order for an unknown result.
String hlTradeErrorMessage(AppLocalizations l10n, Object error) {
  if (error is CapabilityUnavailableException) {
    return error.decision.messageIn(l10n);
  }
  if (error is LeverageCapExceededException) return error.messageIn(l10n);
  if (error is PendingHyperliquidTwapException) {
    return l10n.investingTwapPending;
  }
  if (error is ResolvedHyperliquidTwapException) {
    return switch (error.resolution) {
      HlTwapResolution.accepted => l10n.investingTwapPreviouslyAccepted,
      HlTwapResolution.rejected => l10n.investingTwapPreviouslyRejected,
      HlTwapResolution.expired => l10n.investingTwapPreviouslyExpired,
    };
  }
  if (error is HyperliquidMinNotionalException) {
    final minimum = error.minimumUsd;
    if (minimum == null || !minimum.isFinite || minimum <= 0) {
      return l10n.investingMinimumOrderUnknown;
    }
    return l10n.investingMinimumOrder(
        '\$${minimum.toStringAsFixed(minimum == minimum.roundToDouble() ? 0 : 2)}');
  }
  if (error is HyperliquidInsufficientMarginException) {
    return l10n.investingInsufficientBalance;
  }
  if (error is AuthGrantException) return l10n.investingApprovalExpired;
  if (error is HyperliquidRejectedException) {
    return hlRejectionCopy(l10n, error.reason) ?? l10n.investingTradeRejected;
  }
  return l10n.investingSubmissionUnknown;
}

/// Whether [error] is the venue minimum refusing an order (our own check
/// before sending, or the venue's "minimum value of $10"). Its friendly
/// line says everything: no raw details under it.
bool hlIsMinNotionalError(Object? error) =>
    error is HyperliquidMinNotionalException ||
    (error is HyperliquidRejectedException &&
        error.reason.toLowerCase().contains('minimum value'));

/// Plain words for the venue's common order rejections (its documented
/// error strings, matched case-insensitively), or null when the reason is
/// not one of them. The raw venue text stays available under "Details"
/// (HlTradeErrorNotice).
String? hlRejectionCopy(AppLocalizations l10n, String reason) {
  final r = reason.toLowerCase();
  if (r.contains('divisible by tick size')) return l10n.hlRejectTick;
  if (r.contains('minimum value of')) return l10n.hlRejectMinNotional;
  if (r.contains('open interest is capped') ||
      r.contains('at open interest cap') ||
      r.contains('open interest too quickly')) {
    return l10n.hlRejectOiCap;
  }
  if (r.contains('insufficient margin') ||
      r.contains('insufficient spot balance')) {
    return l10n.investingInsufficientBalance;
  }
  if (r.contains('reduce only order would increase position')) {
    return l10n.hlRejectReduceOnly;
  }
  if (r.contains('post only order would have immediately matched')) {
    return l10n.hlRejectPostOnly;
  }
  if (r.contains('could not immediately match') ||
      r.contains('no liquidity available')) {
    return l10n.hlRejectNoLiquidity;
  }
  if (r.contains('invalid tp/sl price')) return l10n.hlRejectTpsl;
  if (r.contains('too far from oracle')) return l10n.hlRejectOracle;
  return null;
}
