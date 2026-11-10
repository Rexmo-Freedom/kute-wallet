// lib/screens/shared/standing_order_toasts.dart
//
// A standing order's Sal toasts (founder, 9 November 2026, on 2.2.0 (95):
// "Placing your prediction / cancel should be Sal. Also give it an X to
// close it"). One toast per order, tagged by its venue and market
// ([tagFor]), that changes in place as the order moves:
//
//  * PLACING, once the person leaves the slip while its order still runs
//    (the slip itself stays up, locked, from the accept: never both at
//    once; founder, 10 November 2026): "Placing your prediction" / "Placing
//    your order" over the market, the pending tone (Sal's blink, the
//    clock), sticky: it stays until the person closes it with the X or
//    the order ends. "Cancel" in the pill while the order has not left
//    for the venue (StandingOrder.canCancel); once posted it is gone. A
//    tap on the toast opens the order's money journey. The X only closes
//    the toast: the order goes on and stays on the Overview and in
//    Activity, and the placing toast does not come back for it.
//  * The END, in place of the placing toast when it is still up, else as
//    a new one: placed (Sal happy, the check), not placed (Sal sad, the
//    "!"; a tap opens the journey) or cancelled (information).
//  * PRICE MOVED past the approval: the shell's own (standing_orders_shell
//    .dart), with the same tag.
//
// Every toast draws on the root overlay (sal_toast.dart), so the slip's
// context being gone, or the shell having none, never drops one; sheets
// open from the root navigator (root_navigator.dart).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// The open order on [venue] for [marketKey], newest; null: none yet
  /// (the slip has just closed) or none any more.
  static StandingOrder? openOn(
      ProviderContainer container, StandingOrderVenue venue, String marketKey) {
    StandingOrder? found;
    for (final o in container.read(standingOrdersProvider)) {
      if (o.venue == venue && o.marketKey == marketKey && o.isOpen) found = o;
    }
    return found;
  }

  /// Opens the money journey of the order (by [id], else the open one on
  /// [venue] and [marketKey]) from the root navigator.
  static void openJourney(BuildContext? fallback,
      {String? id, StandingOrderVenue? venue, String? marketKey}) {
    final context = kuteRootContext(fallback);
    if (context == null) return;
    unawaited(StandingOrderJourneySheet.show(context,
        standingOrderId: id, venue: venue, marketKey: marketKey));
  }

  /// The placing toast (see the file header). [order] null: the slip was
  /// left the instant of the accept and the standing order has no record
  /// yet; it is looked up
  /// by [venue] and [marketKey] when Cancel or the tap needs it.
  static void placing(
    BuildContext? context,
    ProviderContainer container,
    AppLocalizations l10n, {
    required StandingOrderVenue venue,
    required String marketKey,
    required String marketTitle,
    StandingOrder? order,
  }) {
    final predictions = venue == StandingOrderVenue.predictions;
    final canCancel = order == null || order.canCancel;
    SalToast.show(
      context,
      tag: tagFor(venue, marketKey),
      message: predictions
          ? l10n.standingPlacingPrediction
          : l10n.standingPlacingOrder,
      detail: order?.marketTitle ?? marketTitle,
      tone: SalToastTone.pending,
      sticky: true,
      closable: true,
      onTap: () => openJourney(context,
          id: order?.id, venue: venue, marketKey: marketKey),
      actionLabel: canCancel ? l10n.cancel : null,
      onAction: canCancel
          ? () {
              final id =
                  order?.id ?? openOn(container, venue, marketKey)?.id;
              if (id == null) return;
              unawaited(
                  container.read(standingOrdersProvider.notifier).cancel(id));
            }
          : null,
    );
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
