// lib/screens/shared/standing_order_toasts.dart
//
// A standing order's Sal toasts (founder, 9 November 2026, on 2.2.0 (95):
// "Placing your prediction / cancel should be Sal"). One toast per order,
// tagged by its venue and market ([tagFor]), and only to say how it ENDED
// (founder, 10 November 2026, on 2.2.0 (98): no "thinking" placing
// indicator once the slip is gone; the Overview card is where progress
// lives, its journey keeps Cancel):
//
//  * placed (Sal happy, the check, the one success haptic), not placed
//    (Sal sad, the "!", the failure tap; a tap opens the journey) or
//    cancelled (information);
//  * PRICE MOVED past the approval: the shell's own (standing_orders_shell
//    .dart), with the same tag, so the end changes it in place.
//
// No toast while the order is on its way: the locked slip says it while it
// is open, and once it is left the order's one card on the Dollars
// Overview says Placing (dollars_activity_tab.dart).
//
// Every toast draws on the root overlay (sal_toast.dart), so the slip's
// context being gone, or the shell having none, never drops one; sheets
// open from the root navigator (root_navigator.dart).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';

abstract final class StandingOrderToasts {
  /// The one toast of the order on [venue] for [marketKey].
  static String tagFor(StandingOrderVenue venue, String marketKey) =>
      'standing-${venue.name}-$marketKey';

  static String tagOf(StandingOrder order) =>
      tagFor(order.venue, order.marketKey);

  /// Opens the money journey of the order (by [id], else the open one on
  /// [venue] and [marketKey]) from the root navigator.
  static void openJourney(BuildContext? fallback,
      {String? id, StandingOrderVenue? venue, String? marketKey}) {
    final context = kuteRootContext(fallback);
    if (context == null) return;
    unawaited(StandingOrderJourneySheet.show(context,
        standingOrderId: id, venue: venue, marketKey: marketKey));
  }

  /// The order filled.
  static void placed(BuildContext? context, AppLocalizations l10n,
      StandingOrder order) {
    SalToast.show(
      context,
      tag: tagOf(order),
      message: order.venue == StandingOrderVenue.predictions
          ? l10n.standingPredictionPlaced
          : l10n.standingOrderPlaced,
      detail: order.marketTitle,
      tone: SalToastTone.success,
      closable: false,
    );
  }

  /// The order was not placed; a tap opens its journey, where it says why
  /// and where the money is.
  static void failed(BuildContext? context, AppLocalizations l10n,
      StandingOrder order) {
    SalReactions.play(SalReaction.shakeNo);
    SalToast.show(
      context,
      tag: tagOf(order),
      message: order.venue == StandingOrderVenue.predictions
          ? l10n.standingPredictionFailed
          : l10n.standingOrderFailed,
      detail: order.marketTitle,
      tone: SalToastTone.failure,
      onTap: () => openJourney(context, id: order.id),
    );
  }

  /// The person cancelled it (from the toast or the journey).
  static void cancelled(BuildContext? context, AppLocalizations l10n,
      StandingOrder order) {
    SalToast.show(
      context,
      tag: tagOf(order),
      message: order.venue == StandingOrderVenue.predictions
          ? l10n.standingPredictionCancelled
          : l10n.standingOrderCancelled,
      detail: order.marketTitle,
      tone: SalToastTone.info,
      closable: false,
    );
  }
}
