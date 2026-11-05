// lib/screens/share/slip_share.dart
//
// SEND THIS PREDICTION FROM ITS SLIP (founder, 5 November 2026: "we are
// still not sending the prediction. I think the share button should be on
// this bet slip page actually, it carries all the information, even the
// amount. It's the best place to have the share"). The one place a
// prediction (or an investment) is composed for a friend is the slip
// itself: the bet slip (polymarket/components/bet_slip_sheet.dart) and the
// Investing order slip (hyperliquid/components/order_slip_sheet.dart) put
// the round Sal button at the right of their floating primary
// ([KuteBarShare.send], kute_bar_context.dart; the button itself is
// kute_bar_trade_row.dart's). A tap ([sendFromSlip]):
//
//   * THE VENUE CLOSED TO THIS PERSON (the slip's own open gate: the
//     region refusal and "Check connection", or any other policy refusal;
//     founder, 5 November 2026: "when the user is blocked on Polymarket he
//     cannot also send the actual prediction, just the card"): the market
//     send sheet (share_market_sheet.dart), the market's card and its link
//     only, no money and no pick. Same on Investing.
//   * NOTHING TYPED: a toast, "Enter an amount to send" (never a silent
//     no-op; the button stays where it is).
//   * UNDER THE MARKET'S MINIMUM: "Enter at least $1 to send".
//   * A SIDE NO LINK CAN CARRY (No on one candidate: a link names an
//     outcome of the event, and the Claim screen opens the slip on its
//     Yes): "Only Yes on {candidate} can be sent".
//   * Else Send to anyone (send_to_anyone_sheet.dart) on its last step,
//     THIS pick prefilled: the market, the outcome, the side and the
//     amount, the card as the hero, "Your friend gets $5 on Apple — Yes
//     at 62%", the name, Challenge them, the bar "Send prediction".
//
// The slip stays open under it: closing the send returns to the slip.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart'
    show
        kMarketLinkInvesting,
        kMarketLinkPredictions,
        kShareVenueHyperliquid,
        kShareVenuePolymarket,
        marketShareLink;
import 'package:kute/screens/shared/message_display.dart'
    show showMessageSnackBarInfo;

/// Where a slip's send went (the test seam's record).
enum SlipSendRoute { pick, market, enterAmount, minimum, yesOnly }

/// What a slip hands its round Sal button, read at the tap.
@immutable
class SlipSharePick {
  const SlipSharePick({
    required this.investing,
    required this.slug,
    required this.title,
    required this.outcome,
    required this.side,
    required this.sideLabel,
    required this.amountUsd,
    required this.minUsd,
    required this.minLabel,
    required this.blocked,
    this.outcomeIndex,
    this.marketLinkSlug,
    this.marketChance,
    this.price,
    this.imageUrl,
    this.ticker,
    this.wireCoin,
    this.coinCategory,
    this.coinIconUrl,
    this.entrySource = 'slip',
  });

  /// An Investing order slip's pick; else a prediction's.
  final bool investing;

  /// The event slug, or the Investing wire coin the Claim screen
  /// resolves.
  final String? slug;

  /// The slug the market's own link and card take, where it differs (an
  /// Investing market's display coin, as its page shares it); null:
  /// [slug].
  final String? marketLinkSlug;

  /// The market's name as the slip shows it.
  final String title;

  /// The outcome the link names ("Yes", a candidate, "Long"); null when
  /// the side picked is none a link can carry (No on a candidate).
  final String? outcome;
  final int? outcomeIndex;

  /// `buy` for a prediction, `long` or `short` on Investing.
  final String side;

  /// The side as the slip names it, for the toast ("Jon Ossoff").
  final String sideLabel;

  /// The slip's amount in dollars; 0 while nothing is typed.
  final double amountUsd;

  /// The market's minimum, and that minimum as the slip writes it.
  final double minUsd;
  final String minLabel;

  /// The slip's open gate refuses this person (see the file header).
  final bool blocked;

  /// The market card's figures, for the blocked path: the Yes side's
  /// chance (0–100) of a prediction market, an Investing price.
  final double? marketChance;
  final String? price;

  /// The market's picture; an Investing market's logo sources.
  final String? imageUrl;
  final String? ticker;
  final String? wireCoin;
  final String? coinCategory;
  final String? coinIconUrl;

  /// Send to anyone's entry source (analytics).
  final String entrySource;
}

/// The test seam: every send's route and the pick it was made with; the
/// sheets still open unless [debugOpen] is false.
abstract final class SlipShare {
  @visibleForTesting
  static void Function(SlipSendRoute route, SlipSharePick pick)? debugRoute;

  @visibleForTesting
  static bool debugOpen = true;
}

/// The slip's round Sal button: [pick] is read at the tap.
KuteBarShare slipShareButton(
        BuildContext context, SlipSharePick Function() pick) =>
    KuteBarShare(send: () => unawaited(sendFromSlip(context, pick())));

/// A tap on a slip's round Sal button (see the file header).
Future<void> sendFromSlip(BuildContext context, SlipSharePick pick) async {
  final l10n = context.l10n;
  void route(SlipSendRoute r) => SlipShare.debugRoute?.call(r, pick);
  final slug = pick.slug?.trim() ?? '';
  if (pick.blocked || slug.isEmpty) {
    // The market's card only: no money, no pick (a market the link cannot
    // name goes the same way).
    route(SlipSendRoute.market);
    if (!SlipShare.debugOpen) return;
    await openShareForMarket(
      context,
      title: pick.title,
      subtitle: null,
      deepLink: marketShareLink(
          venue: pick.investing ? kMarketLinkInvesting : kMarketLinkPredictions,
          slug: pick.marketLinkSlug ?? pick.slug),
      marketSlug: pick.marketLinkSlug ?? pick.slug,
      chance: pick.investing ? null : pick.marketChance,
      price: pick.investing ? pick.price : null,
      venue: pick.investing ? kShareVenueHyperliquid : kShareVenuePolymarket,
      imageUrl: pick.investing ? null : pick.imageUrl,
      ticker: pick.investing ? pick.ticker : null,
      wireCoin: pick.investing ? pick.wireCoin : null,
      coinCategory: pick.investing ? pick.coinCategory : null,
      coinIconUrl: pick.investing ? pick.coinIconUrl : null,
    );
    return;
  }
  final amount = pick.amountUsd;
  if (!amount.isFinite || amount <= 0) {
    route(SlipSendRoute.enterAmount);
    showMessageSnackBarInfo(
        context: context, message: l10n.slipShareEnterAmount);
    return;
  }
  if (amount + 1e-9 < pick.minUsd) {
    route(SlipSendRoute.minimum);
    showMessageSnackBarInfo(
        context: context, message: l10n.slipShareMinimum(pick.minLabel));
    return;
  }
  final outcome = pick.outcome?.trim() ?? '';
  if (outcome.isEmpty) {
    route(SlipSendRoute.yesOnly);
    showMessageSnackBarInfo(
        context: context, message: l10n.slipShareYesOnly(pick.sideLabel));
    return;
  }
  route(SlipSendRoute.pick);
  if (!SlipShare.debugOpen) return;
  await showSendToAnyoneSheet(
    context,
    kind: ShareLinkKind.dollars,
    marketSlug: slug,
    marketTitle: pick.title,
    venue: pick.investing ? kShareVenueHyperliquid : kShareVenuePolymarket,
    outcome: outcome,
    outcomeIndex: pick.outcomeIndex,
    side: pick.side,
    amountMinor: (amount * 100).round(),
    entrySource: pick.entrySource,
  );
}
