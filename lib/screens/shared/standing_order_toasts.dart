// lib/screens/shared/standing_order_toasts.dart
//
// A standing order's Sal toasts (founder, 9 November 2026, on 2.2.0 (95):
// "Placing your prediction / cancel should be Sal"). ONE toast for every
// standing order (founder, 10 November 2026, on 2.2.0 (101): "we only show
// the toolbar with one please"): they all share one tag ([tag]), so the
// toast on screen changes in place as the orders move, never a second one
// stacked or arriving under a leaving one. It remembers which order it is
// about ([isAbout]); its tap is that order's.
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
//    goes on either way. A tap opens that order's own slip again, locked
//    as it was left (the bet slip or the order ticket, green or red, its
//    journey running and its "OK"; founder, on 2.2.0 (101): "we should
//    just reuse the betslip, the red or green one"), never the white
//    journey sheet; the journey sheet only where the slip cannot be had.
//    Never while the slip is on screen. A second order left while the
//    first's placing toast is up takes its place: the newest one.
//  * The END of any order, in place of whatever the toast says now, else
//    as a new one: placed (Sal happy, the check, the one success haptic),
//    not placed (Sal sad, the "!", the failure tap; a tap opens the
//    journey) or cancelled (information). The haptic plays when the tone
//    changes, so two results landing together are felt once. Once it has
//    gone, an order still placing puts nothing back up. An order that
//    ends with no result toast (the person acted on it themselves) takes
//    the placing toast with it, when the toast is about that order
//    ([endQuietly]).
//  * PRICE MOVED past the approval: the shell's own (standing_orders_shell
//    .dart), on the same tag, so it too takes the toast's place.
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
  /// The one tag every standing order's toast is shown with (see the file
  /// header): the toast on screen changes in place, whichever order it
  /// is about.
  static const String tag = 'standing-order';

  /// The tag of [order]'s toast: the one tag ([tag]).
  static String tagOf(StandingOrder order) => tag;

  /// The order the toast on screen is about (venue and market); null:
  /// none said yet.
  static String? _about;

  /// Whether the toast on screen is a placing one (not yet changed into a
  /// result or the price-moved ask).
  static bool _placing = false;

  static String _keyFor(StandingOrderVenue venue, String marketKey) =>
      '${venue.name}-$marketKey';

  /// Whether the toast on screen is about the order on [venue] for
  /// [marketKey].
  static bool isAbout(StandingOrderVenue venue, String marketKey) =>
      SalToast.isShowing(tag) && _about == _keyFor(venue, marketKey);

  /// Whether the toast on screen is [order]'s placing toast.
  static bool isPlacing(StandingOrder order) {
    if (!SalToast.isShowing(tag)) _placing = false;
    return _placing && _about == _keyFor(order.venue, order.marketKey);
  }

  /// The toast is about to say something else about [order].
  static void markSaid(StandingOrder order) {
    _about = _keyFor(order.venue, order.marketKey);
    _placing = false;
  }

  /// [order] ended with no result toast of its own: its placing toast, if
  /// still up (and still about it), goes.
  static void endQuietly(StandingOrder order) {
    if (!isPlacing(order)) return;
    _placing = false;
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
  /// yet; a tap looks it up by [venue] and [marketKey]. [reopen] opens the
  /// slip that was left again, locked on this order (the slip's own,
  /// bet_slip_sheet.dart / order_slip_sheet.dart `_onLeave`); without one
  /// a tap opens the order's journey sheet.
  static void placing(
    BuildContext? context,
    AppLocalizations l10n, {
    required StandingOrderVenue venue,
    required String marketKey,
    required String marketTitle,
    StandingOrder? order,
    VoidCallback? reopen,
  }) {
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
      onTap: reopen ??
          () => openJourney(context,
              id: order?.id, venue: venue, marketKey: marketKey),
    );
    _about = _keyFor(venue, marketKey);
    _placing = true;
  }

  /// What a slip reopened on the order [id] on [venue] for [marketKey]
  /// looks past to follow exactly that one: every other order on the
  /// market (the slip's own "ended before" set). [id] null and no open
  /// order there yet (its record not written): [fallback], the set the
  /// left slip itself followed by. Null when the order has already ended:
  /// there is nothing to follow.
  static Set<String>? followSet(ProviderContainer container,
      StandingOrderVenue venue, String marketKey,
      {String? id, Set<String>? fallback}) {
    final all = container.read(standingOrdersProvider);
    final resolved = id ?? openOn(container, venue, marketKey)?.id;
    if (resolved == null) return fallback;
    final order = all.where((o) => o.id == resolved).firstOrNull;
    if (order == null || order.state.isTerminal) return null;
    return {
      for (final o in all)
        if (o.venue == venue && o.marketKey == marketKey && o.id != resolved)
          o.id,
    };
  }

  /// Tests: nothing remembered about the toast on screen.
  @visibleForTesting
  static void debugReset() {
    _about = null;
    _placing = false;
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

  /// The order filled.
  static void placed(BuildContext? context, AppLocalizations l10n,
      StandingOrder order) {
    markSaid(order);
    SalToast.show(
      context,
      tag: tag,
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
    markSaid(order);
    SalReactions.play(SalReaction.shakeNo);
    SalToast.show(
      context,
      tag: tag,
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
    markSaid(order);
    SalToast.show(
      context,
      tag: tag,
      message: order.venue == StandingOrderVenue.predictions
          ? l10n.standingPredictionCancelled
          : l10n.standingOrderCancelled,
      detail: order.marketTitle,
      tone: SalToastTone.info,
      closable: false,
    );
  }
}
