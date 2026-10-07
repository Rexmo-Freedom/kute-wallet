// lib/helpers/hyperliquid_order_status.dart
//
// Plain words for the statuses Hyperliquid's `orderUpdates` channel gives
// an order the venue ended or fired on its own (Hyperliquid docs, "Info
// endpoint" → order status values): marginCanceled, reduceOnlyCanceled,
// siblingFilledCanceled, openInterestCapCanceled, delistedCanceled,
// liquidatedCanceled, selfTradeCanceled, scheduledCancel, triggered, and
// the *Rejected family. 'open', 'filled' and 'canceled' (the person's own
// cancel) are not venue decisions and get no reason.

import 'package:kute/l10n/l10n.dart';

/// True when [status] is the venue ending or triggering an order on its
/// own, rather than the order resting, filling or being cancelled by the
/// person.
bool hlStatusIsVenueDecision(String status) =>
    status.isNotEmpty &&
    status != 'open' &&
    status != 'filled' &&
    status != 'canceled';

/// The reason a venue decision means for the person, in [l10n].
String hlOrderStatusReason(AppLocalizations l10n, String status) =>
    switch (status) {
      'marginCanceled' => l10n.hlOrderEndedMargin,
      'reduceOnlyCanceled' => l10n.hlOrderEndedReduceOnly,
      'siblingFilledCanceled' => l10n.hlOrderEndedSibling,
      'openInterestCapCanceled' => l10n.hlOrderEndedOiCap,
      'delistedCanceled' => l10n.hlOrderEndedDelisted,
      'liquidatedCanceled' => l10n.hlOrderEndedLiquidated,
      'selfTradeCanceled' => l10n.hlOrderEndedSelfTrade,
      'scheduledCancel' => l10n.hlOrderEndedScheduled,
      'triggered' => l10n.hlOrderEndedTriggered,
      _ when status.endsWith('Rejected') => l10n.hlOrderEndedRejected,
      _ => l10n.hlOrderEndedOther,
    };

/// The venue decisions worth an in-app alert on their own. The rest are
/// shown in the orders list only: a sibling cancelled after its TP/SL
/// filled, or orders cancelled by a liquidation or a closed position,
/// follow an event that already has its own alert.
const Set<String> kHlAlertingCancelStatuses = {
  'marginCanceled',
  'openInterestCapCanceled',
  'delistedCanceled',
  'selfTradeCanceled',
};
