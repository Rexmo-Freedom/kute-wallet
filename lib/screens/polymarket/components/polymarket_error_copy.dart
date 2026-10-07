import 'package:flutter/widgets.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/polymarket_backend_service.dart'
    show GeoBlockException;

/// Exchange responses can include protocol fields and addresses. They stay in
/// Details; the primary message describes what the user can do next.
String polymarketErrorCopy(BuildContext context, Object error,
    {double? positionPrice}) {
  final l10n = context.l10n;
  if (error is GeoBlockException) return l10n.tradingNotAvailableInRegion;
  final text = error.toString().toLowerCase();
  if (text.contains('fok') ||
      text.contains('fully filled') ||
      text.contains('no bids matched')) {
    return positionPrice != null && positionPrice <= 0.02
        ? l10n.betSaleNoBuyers
        : l10n.betSaleTooThin;
  }
  if (text.contains('balance') || text.contains('allowance')) {
    return l10n.betSaleBalanceChanged;
  }
  if (text.contains('signature') ||
      text.contains('api key') ||
      text.contains('nonce')) {
    return l10n.betApprovalRefresh;
  }
  if (text.contains('does not exist') || text.contains('market closed')) {
    return l10n.betMarketEndedReview;
  }
  if (text.contains('not ready') || text.contains('not available')) {
    return l10n.betMarketNotReady;
  }
  return userErrorCopy(context, error, fallback: l10n.betActionNotCompleted);
}
