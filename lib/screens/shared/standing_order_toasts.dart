// lib/screens/shared/standing_order_toasts.dart
//
// A standing order's Sal toasts (founder, 9 November 2026, on 2.2.0 (95):
// "Placing your prediction / cancel should be Sal"). One toast per order,
// tagged by its venue and market ([tagFor]), that changes in place as the
// order moves:
//
//  * PLACING, once the person leaves the locked slip while its order is
//    still on its way (founder, 10 November 2026, on 2.2.0 (99): "on the
//    top when we close it we should say investment or prediction is
//    placing ... but we can swipe it away or close it"): "Placing your
//    prediction" / "Placing your investment" over the market. Sal and the
//    words only: no spinner, no clock or other "thinking" mark (founder,
//    on 2.2.0 (98)), no Cancel (Cancel lives in the order's journey, from
//    its Overview card). Sticky: it stays until the order ends, and the
//    person can swipe it up or close it with the X any time; the order
//    goes on either way. A tap opens the order's money journey. Never
//    while the slip is on screen.
//  * The END, in place of the placing toast when it is still up, else as
//    a new one: placed (Sal happy, the check, the one success haptic), not
//    placed (Sal sad, the "!", the failure tap; a tap opens the journey)
//    or cancelled (information). An order that ends with no result toast
//    (the person acted on it themselves) takes the placing toast with it
//    ([endQuietly]).
//  * PRICE MOVED past the approval: the shell's own (standing_orders_shell
//    .dart), with the same tag, so it too takes the placing toast's place.
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

  /// The tags whose toast on screen is the placing one (not yet changed
  /// into a result or the price-moved ask).
  static final Set<String> _placingTags = {};

  /// Whether the toast on screen for [order] is its placing toast.
  static bool isPlacing(StandingOrder order) {
    final tag = tagOf(order);
    if (!SalToast.isShowing(tag)) _placingTags.remove(tag);
    return _placingTags.contains(tag);
  }

  /// The tag's toast is about to say something else.
  static void markSaid(String tag) => _placingTags.remove(tag);

  /// [order] ended with no result toast of its own: its placing toast, if
  /// still up, goes.
  static void endQuietly(StandingOrder order) {
    if (!isPlacing(order)) return;
    final tag = tagOf(order);
    _placingTags.remove(tag);
    SalToast.dismissTag(tag);
  }

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

  /// The placing toast (see the file header). [order] null: the slip was
  /// left the instant of the accept and the standing order has no record
  /// yet; a tap looks it up by [venue] and [marketKey].
  static void placing(
    BuildContext? context,
    AppLocalizations l10n, {
    required StandingOrderVenue venue,
    required String marketKey,
    required String marketTitle,
    StandingOrder? order,
  }) {
    final tag = tagFor(venue, marketKey);
    SalToast.show(
      context,
      tag: tag,
      message: venue == StandingOrderVenue.predictions
          ? l10n.standingPlacingPrediction
          : l10n.standingPlacingInvestment,
      detail: order?.marketTitle ?? marketTitle,
      // Information's look: Sal's calm blink and no mark (no clock, no
      // spinner), no haptic.
      tone: SalToastTone.info,
      sticky: true,
      closable: true,
      onTap: () => openJourney(context,
          id: order?.id, venue: venue, marketKey: marketKey),
    );
    _placingTags.add(tag);
  }

  /// Tests: no placing toast remembered.
  @visibleForTesting
  static void debugReset() => _placingTags.clear();

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
    markSaid(tagOf(order));
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
    markSaid(tagOf(order));
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
    markSaid(tagOf(order));
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
