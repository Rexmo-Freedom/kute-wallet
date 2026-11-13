// lib/screens/shared/standing_order_slips.dart
//
// THE ONE WAY BACK TO A STANDING ORDER (founder, 11 November 2026, on
// 2.2.0 (104), of the white "Placing your prediction" sheet the Overview's
// Placing card opened: "this screen should not exist, it should be the
// same one as this one. Say OK, don't allow for cancel. Tapping to open
// the one placing should and must re-enable the haptics, and should be
// green or red depending"). Every tap on an order still on its way (Sal's
// placing toast, the Overview's card, the Activity row, a result toast)
// opens the order's own slip again, locked on it as it was left: the bet
// slip or the order ticket, green or red by its side exactly as the slip
// colours it, the money's journey running with its haptics, and "OK",
// which only leaves it. There is no white journey sheet and no Cancel: an
// accepted order is never cancelled by the person (expiry, a moved price
// and failures still end it, standing_orders_provider.dart).
//
//  * CAPTURED: the slip that was left hands its own reopen over
//    ([remember], bet_slip_sheet.dart / order_slip_sheet.dart `_onLeave`):
//    the very market, side and stake it showed, its outcomes, labels and
//    colours. Used while it is about that order.
//  * REBUILT FROM THE RECORD when nothing was captured (the order was
//    accepted before the app restarted, or its slip was never left that
//    way): the market is read again (Predictions: the event by its slug,
//    the outcome found by the order's token, the side bought on it;
//    Investing: the very market the order was approved on, by its
//    position coin, as a resume finds it), then the slip opens locked on
//    the order with its stake. Nothing new is counted or gated: it is the
//    same slip, nothing can be placed from it while the order goes on.
//  * PRICE MOVED past the approval: the tap is the approval's own (the
//    slip at the new price, unlocked, its Confirm and Face ID place it
//    from the money already on the venue), as Sal's price-moved toast
//    does ([approveAtNewPrice]).
//  * ENDED: a stop the slip still shows (the funded move's failed step,
//    where the money is, try again) opens that slip; anything else
//    (placed, or not placed with nothing on the slip to say) opens
//    nothing: a placed order's card is the position's own row, whose tap
//    opens the position.
//
// One slip at a time: while a slip is already on screen nothing opens over
// it, so two slips never run their haptics together (the toast plays none
// while an order places).
//
// The slip or the toast, never both (founder, 11 November 2026, on 2.2.0
// (109): a reopened ticket under "Placing your investment", "so
// confusing"): opening the slip again puts the order's placing toast away
// ([StandingOrderToasts.hideFor]); leaving it puts the toast back up while
// the order is still on its way. Nothing here opens a slip by itself:
// only a tap (the toast, the Overview's card, the Activity row).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart'
    show HlOrderSlipSheet;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/shared/standing_order_toasts.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/theme/app_theme.dart' show AppColors;

/// Opens a left slip again on the root navigator, following exactly the
/// orders [follow] does not list (the slip's "ended before" set).
typedef StandingSlipOpener = Future<void> Function(
    BuildContext root, Set<String> follow);

class _Captured {
  const _Captured(this.orderId, this.endedBefore, this.open);
  final String? orderId;
  final Set<String>? endedBefore;
  final StandingSlipOpener open;
}

abstract final class StandingOrderSlips {
  /// The slips left while their order goes on, by venue and market.
  static final Map<String, _Captured> _captured = {};

  /// A rebuild under way: a second tap waits for it.
  static bool _opening = false;

  /// How long the market may take to read before the reopen gives up.
  static const Duration _readTimeout = Duration(seconds: 8);

  static String _keyFor(StandingOrderVenue venue, String marketKey) =>
      '${venue.name}-$marketKey';

  /// The slip on [venue] for [marketKey] was left while its order (by
  /// [orderId]; null: its record not written yet) goes on: [open] opens
  /// it again. [endedBefore] is what the slip itself followed by (for a
  /// reopen before the order has its record).
  static void remember({
    required StandingOrderVenue venue,
    required String marketKey,
    String? orderId,
    Set<String>? endedBefore,
    required StandingSlipOpener open,
  }) {
    _captured[_keyFor(venue, marketKey)] =
        _Captured(orderId, endedBefore, open);
  }

  /// [order] ended: a slip captured for it (or for its market before its
  /// record existed) is not reopened on a later order.
  static void forget(StandingOrder order) {
    final key = _keyFor(order.venue, order.marketKey);
    final captured = _captured[key];
    if (captured == null) return;
    if (captured.orderId == null || captured.orderId == order.id) {
      _captured.remove(key);
    }
  }

  /// Tests: nothing captured (a fresh app).
  @visibleForTesting
  static void debugReset() {
    _captured.clear();
    _opening = false;
  }

  /// Opens the order (by [id], else the open one on [venue] and
  /// [marketKey]) again: its locked slip, green or red, its journey and
  /// "OK" (see the file header). Never the white journey sheet, never a
  /// Cancel.
  static Future<void> reopen(BuildContext? context,
      {String? id, StandingOrderVenue? venue, String? marketKey}) async {
    if (_opening) return;
    final root = kuteRootContext(context);
    if (root == null) return;
    final container = ProviderScope.containerOf(root, listen: false);
    final all = container.read(standingOrdersProvider);
    final order = id != null
        ? all.where((o) => o.id == id).firstOrNull
        : venue != null && marketKey != null
            ? StandingOrderToasts.openOn(container, venue, marketKey)
            : null;
    final v = order?.venue ?? venue;
    final key = order?.marketKey ?? marketKey;
    if (v == null || key == null) return;
    // One slip at a time: never a second over one on screen.
    if (_slipOnTop(root)) return;
    if (order != null && order.state == StandingOrderState.needsApproval) {
      return approveAtNewPrice(root, order);
    }
    final captured = _captured[_keyFor(v, key)];
    final usable = captured != null &&
        (captured.orderId == null || captured.orderId == order?.id);
    final follow = StandingOrderToasts.followSet(container, v, key,
        id: order?.id, fallback: usable ? captured.endedBefore : null);
    if (follow == null) {
      // Ended: its slip only where the slip still shows the stop.
      if (order == null || !_stopOnSlip(container, order)) return;
      return _rebuild(root, container, order, {
        for (final o in all)
          if (o.venue == order.venue &&
              o.marketKey == order.marketKey &&
              o.id != order.id)
            o.id,
      });
    }
    if (usable) {
      StandingOrderToasts.hideFor(v, key);
      return captured.open(root, follow);
    }
    // Nothing on record yet and nothing captured: nothing to open.
    if (order == null) return;
    return _rebuild(root, container, order, follow);
  }

  /// The order on [venue] still being placed among [all] (the newest open
  /// one not resting on the book): the one a second order (or bet) there
  /// waits for, one at a time (founder, 11 November 2026: "while one is
  /// placing can't place another. Just be clear about this"). Null:
  /// nothing on record to open.
  static StandingOrder? placingOn(
      List<StandingOrder> all, StandingOrderVenue venue) {
    StandingOrder? found;
    for (final o in all) {
      if (o.venue == venue &&
          o.isOpen &&
          o.state != StandingOrderState.posted) {
        found = o;
      }
    }
    return found;
  }

  /// A second slip held while [order] is being placed: that slip goes and
  /// [order]'s own opens in its place, locked on it ([reopen]; one slip at
  /// a time).
  static void openInstead(BuildContext slip, StandingOrder order) {
    final root = kuteRootContext(slip);
    Navigator.of(slip).pop();
    unawaited(reopen(root, id: order.id));
  }

  /// The price moved past what was approved: the standing order ends
  /// there (quietly: no result toast) and the slip opens at the new
  /// price, unlocked, for its own Confirm and Face ID to place it from
  /// the money already on the venue. Sal's price-moved toast and a tap on
  /// the order waiting for it both come here.
  static Future<void> approveAtNewPrice(
      BuildContext? context, StandingOrder order) async {
    final root = kuteRootContext(context);
    if (root == null) return;
    final container = ProviderScope.containerOf(root, listen: false);
    unawaited(container.read(standingOrdersProvider.notifier).advance(
        order.id, StandingOrderState.failed,
        failureCode: 'price_moved', quiet: true));
    if (order.venue != StandingOrderVenue.predictions) return;
    final price = order.movedToPrice ?? order.approvedPrice;
    final slip = await _guarded(
        () => _predictionSlip(container, order, price: price));
    if (slip == null || !root.mounted) return;
    final at = kuteRootContext(root);
    if (at == null) return;
    final s = slip.slip;
    unawaited(BetSlipSheet.show(
      at,
      marketQuestion: s.marketQuestion,
      marketSlug: s.marketSlug,
      marketImage: s.marketImage,
      outcomes: s.outcomes,
      initialOutcomeIndex: slip.index,
      initialBuyNo: slip.buyNo,
      outcomeColors: s.outcomeColors,
      marketEndAt: s.marketEndAt,
      marketCategory: s.marketCategory,
      negRisk: s.negRisk,
      initialAmountUsd: order.amountUsd,
      event: s.event,
      source: 'standing_order',
    ));
  }

  /// Whether a slip (the bet slip or the order ticket) is the top route.
  static bool _slipOnTop(BuildContext root) {
    final nav = Navigator.maybeOf(root, rootNavigator: true);
    if (nav == null) return false;
    String? top;
    nav.popUntil((route) {
      top = route.settings.name;
      return true;
    });
    return top == BetSlipSheet.routeName || top == HlOrderSlipSheet.routeName;
  }

  /// Whether [order]'s slip still shows how it stopped: its funded move's
  /// failed step on that market.
  static bool _stopOnSlip(ProviderContainer container, StandingOrder order) {
    if (order.state != StandingOrderState.failed) return false;
    final progress = FundedOrdersNotifier.progressOn(
        container.read(fundedOrdersProvider),
        order.venue == StandingOrderVenue.predictions
            ? OneBalanceVenue.predictions
            : OneBalanceVenue.investing,
        order.marketKey,
        DateTime.now());
    return progress != null && progress.failed;
  }

  static Future<T?> _guarded<T>(Future<T?> Function() run) async {
    _opening = true;
    try {
      return await run().timeout(_readTimeout);
    } catch (_) {
      return null;
    } finally {
      _opening = false;
    }
  }

  /// The slip rebuilt from [order]'s record (see the file header), opened
  /// locked on it, following what [follow] does not list.
  static Future<void> _rebuild(BuildContext root, ProviderContainer container,
      StandingOrder order, Set<String> follow) async {
    switch (order.venue) {
      case StandingOrderVenue.predictions:
        final slip = await _guarded(() => _predictionSlip(container, order));
        if (!root.mounted) return;
        final at = kuteRootContext(root);
        if (slip == null || at == null || _slipOnTop(at)) return;
        StandingOrderToasts.hideFor(order.venue, order.marketKey);
        await BetSlipSheet.reopenStanding(at, slip.slip,
            selectedIndex: slip.index,
            buyNo: slip.buyNo,
            amountUsd: order.amountUsd,
            endedBefore: follow);
      case StandingOrderVenue.investing:
        final markets = await _guarded(() => container
            .read(standingHlMarketsProvider)(spot: order.marketKind == 'spot'));
        final market = markets == null
            ? null
            : StandingOrdersNotifier.resumeMarketFor(order, markets);
        if (!root.mounted) return;
        final at = kuteRootContext(root);
        // The very market it was approved on, or nothing: never a guess.
        if (market == null || at == null || _slipOnTop(at)) return;
        StandingOrderToasts.hideFor(order.venue, order.marketKey);
        await HlOrderSlipSheet.reopenStanding(
            at,
            HlOrderSlipSheet(
                market: market,
                source: 'standing_order',
                entrySource: order.entrySource),
            isLong: order.isBuy,
            marginUsd: order.amountUsd,
            endedBefore: follow);
    }
  }

  /// The bet slip [order] was accepted on, from its record: the event read
  /// by its slug, the outcome by the order's token and the side bought on
  /// it. Where the event cannot be read (or no longer lists the token),
  /// the record alone: its side as the one outcome, in the side's colour
  /// (green for Yes, Up and Over and every other side, red for No, Down
  /// and Under). [price] in place of the approved one (a moved price).
  static Future<({BetSlipSheet slip, int index, bool buyNo})> _predictionSlip(
      ProviderContainer container, StandingOrder order,
      {double? price}) async {
    final event = await _readEvent(container, order.eventSlug);
    final pick = event == null ? null : pickOf(event.outcomes, order.marketKey);
    if (event != null && pick != null) {
      return (
        slip: BetSlipSheet(
          marketQuestion: order.marketTitle.isNotEmpty
              ? order.marketTitle
              : event.displayTitle,
          marketSlug: event.slug,
          marketImage: order.marketImage ?? event.imageUrl,
          outcomes: event.outcomes,
          marketEndAt: order.marketEndAt ?? event.endDate,
          marketCategory: order.marketCategory ?? event.category,
          negRisk: event.negRisk,
          source: 'standing_order',
          event: event,
        ),
        index: pick.index,
        buyNo: pick.buyNo,
      );
    }
    const negatives = {'no', 'down', 'under'};
    final negative =
        negatives.contains(order.sideLabel.trim().toLowerCase());
    return (
      slip: BetSlipSheet(
        marketQuestion: order.marketTitle,
        marketSlug: order.eventSlug,
        marketImage: order.marketImage,
        outcomes: [
          PolymarketOutcome(
            name: order.sideLabel,
            price: price ?? order.approvedPrice,
            tokenId: order.marketKey,
          ),
        ],
        outcomeColors: [negative ? AppColors.marketDown : AppColors.marketUp],
        marketEndAt: order.marketEndAt,
        marketCategory: order.marketCategory,
        negRisk: order.negRisk,
        source: 'standing_order',
      ),
      index: 0,
      buyNo: false,
    );
  }

  static Future<PolymarketEvent?> _readEvent(
      ProviderContainer container, String? slug) async {
    if (slug == null || slug.isEmpty) return null;
    // Held while it is read: the provider lets go of an unwatched read.
    final sub = container.listen(
        polymarketEventDetailsProvider(slug).future, (_, __) {});
    try {
      return await sub.read();
    } catch (_) {
      return null;
    } finally {
      sub.close();
    }
  }

  /// Where [token] sits among [outcomes]: the outcome whose own token it
  /// is (a binary market's Yes or No, a candidate's Yes), else the one
  /// whose No it is (a candidate's No). Null: not listed.
  @visibleForTesting
  static ({int index, bool buyNo})? pickOf(
      List<PolymarketOutcome> outcomes, String token) {
    for (var i = 0; i < outcomes.length; i++) {
      if (outcomes[i].tokenId == token) return (index: i, buyNo: false);
    }
    for (var i = 0; i < outcomes.length; i++) {
      if (outcomes[i].noTokenId == token) return (index: i, buyNo: true);
    }
    return null;
  }
}
