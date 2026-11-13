// lib/screens/share/slip_share.dart
//
// SEND A PREDICTION OR AN INVESTMENT, FROM A SLIP IN SEND MODE (founder,
// 7 November 2026, superseding the slips' round Sal button: "This share
// here should only be for sharing the market. Don't have the share on the
// slip, only in Send should it be to send to someone"; "just get rid of
// the button to share the actual prediction on the buy, just keep it on
// the send"). A slip has no share button. A pick is sent only from Send:
// the search sheet in send mode opens a market page in send mode, and its
// slip (polymarket/components/bet_slip_sheet.dart, hyperliquid/components
// /order_slip_sheet.dart) runs in send mode (send_pick_session.dart): its
// PRIMARY is the send itself ([slipSendCta]), never an order:
//
//   * "Send $50 · Short AMD", "Send $10 · Yes": a tap ([sendFromSlip])
//     opens Send to anyone (send_to_anyone_sheet.dart) on its last step,
//     THIS pick prefilled: the market, the outcome, the side and the
//     amount, the gift card as the hero, the name (the contact picked on
//     Send, if any), Challenge them, the bar "Send prediction". The link
//     created closes the slip, the market pages and the search sheet, and
//     the Send screen reads it as a send that went out.
//   * DISABLED, saying what to do (as the slip's own button does): nothing
//     typed "Enter an amount to send", under the market's minimum "Enter
//     at least $1 to send", a side no link can carry (No on one candidate:
//     a link names an outcome of the event, and the Claim screen opens the
//     slip on its Yes) "Only Yes on {candidate} can be sent".
//   * THE AMOUNT IS JUDGED AS AN ORDER'S IS (founder, 8 November 2026: "just
//     literally do like normal fills"): the slip's Available, Max and this
//     refusal read [giftSpendableProvider] (one_balance/gift_funding.dart),
//     Dollars plus what Bitcoin lands plus the venue cash net of its moves.
//     More than that is disabled, "Lower the amount" ([SlipSendRoute.
//     overReach]), and no link is made. A balance not known yet is never
//     judged. Nothing moves at this step: "Send now" funds it once the
//     friend claims.
//   * THE SLIP IS THE GATE (founder, 8 November 2026: "only on the last
//     screen, the bet slip, show this error"; replaces "Send the market"
//     on a refusal): the slip's own open gate refusing this market is
//     [SlipSharePick.blocked], route [SlipSendRoute.refused]. The slip wears
//     its usual reason, its one button "Check connection" on a region
//     refusal (the send again once that finds it open), the send disabled
//     on any other. No sheet opens and no link is ever created for it; each
//     slip also asks its gate again at the tap, since the answer at open
//     lands behind the first frame.
//   * NO INVESTMENT OR NO PICK TO NAME (a spot sale, [SlipSharePick.
//     cardOnly], or a market with no slug): "Send the market", the market
//     send sheet (share_market_sheet.dart), the market's card and its link
//     only, no money and no pick.

import 'package:flutter/widgets.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardUsdCents;
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
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
enum SlipSendRoute {
  pick,
  market,
  refused,
  enterAmount,
  minimum,
  yesOnly,
  overReach,
}

/// What a slip in send mode sends, read at the tap.
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
    this.cardOnly = false,
    this.outcomeIndex,
    this.marketLinkSlug,
    this.marketChance,
    this.price,
    this.imageUrl,
    this.ticker,
    this.wireCoin,
    this.coinCategory,
    this.coinIconUrl,
    this.entrySource = kSendModeSlipSource,
    this.reachUsd,
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

  /// The slip's open gate refuses this market here: nothing is sent (see
  /// the file header).
  final bool blocked;

  /// Nothing but the market's card can be sent: a spot sale.
  final bool cardOnly;

  /// The market card's figures, for the card's path: the Yes side's
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

  /// The most this person can send ([giftSpendableProvider]). Null while
  /// not known: never judged.
  final double? reachUsd;

  /// The amount in cents, as the link carries it.
  int get amountMinor => (amountUsd * 100).round();
}

/// The test seam: every send's route and the pick it was made with; the
/// sheets still open unless [debugOpen] is false.
abstract final class SlipShare {
  @visibleForTesting
  static void Function(SlipSendRoute route, SlipSharePick pick)? debugRoute;

  @visibleForTesting
  static bool debugOpen = true;
}

/// Where a send with [pick] goes (see the file header).
SlipSendRoute slipSendRoute(SlipSharePick pick) {
  final slug = pick.slug?.trim() ?? '';
  if (pick.blocked) return SlipSendRoute.refused;
  if (pick.cardOnly || slug.isEmpty) return SlipSendRoute.market;
  final amount = pick.amountUsd;
  if (!amount.isFinite || amount <= 0) return SlipSendRoute.enterAmount;
  if (amount + 1e-9 < pick.minUsd) return SlipSendRoute.minimum;
  if ((pick.outcome?.trim() ?? '').isEmpty) return SlipSendRoute.yesOnly;
  final reach = pick.reachUsd;
  if (reach != null && amount > reach + 1e-9) return SlipSendRoute.overReach;
  return SlipSendRoute.pick;
}

/// A slip's primary in send mode (see the file header): its [label],
/// whether it is [enabled], and while it is not, what to do
/// ([disabledLabel]).
typedef SlipSendCta = ({
  String label,
  bool enabled,
  String? disabledLabel,
  SlipSendRoute route,
});

/// The primary of a slip in send mode for [pick]: "Send $50 · Short AMD",
/// "Send $10 · Yes"; "Send the market" where only the card can go; disabled
/// on a refusal (the slip's reason above it) and with the step to take
/// otherwise.
SlipSendCta slipSendCta(AppLocalizations l10n, SlipSharePick pick) {
  final route = slipSendRoute(pick);
  final side = pick.investing
      ? l10n.shareCardPositionInvest(pick.sideLabel, pick.title)
      : pick.sideLabel;
  final amount = pick.amountUsd.isFinite && pick.amountUsd > 0
      ? shareCardUsdCents(l10n.localeName, pick.amountMinor)
      : null;
  final send = amount == null ? side : l10n.slipSendCta(amount, side);
  return switch (route) {
    SlipSendRoute.market => (
        label: l10n.shareTheMarket,
        enabled: true,
        disabledLabel: null,
        route: route,
      ),
    SlipSendRoute.pick => (
        label: send,
        enabled: true,
        disabledLabel: null,
        route: route,
      ),
    SlipSendRoute.refused => (
        label: send,
        enabled: false,
        disabledLabel: null,
        route: route,
      ),
    SlipSendRoute.enterAmount => (
        label: send,
        enabled: false,
        disabledLabel: l10n.slipShareEnterAmount,
        route: route,
      ),
    SlipSendRoute.minimum => (
        label: send,
        enabled: false,
        disabledLabel: l10n.slipShareMinimum(pick.minLabel),
        route: route,
      ),
    SlipSendRoute.yesOnly => (
        label: send,
        enabled: false,
        disabledLabel: l10n.slipSendYesOnly(pick.sideLabel),
        route: route,
      ),
    SlipSendRoute.overReach => (
        label: send,
        enabled: false,
        disabledLabel: l10n.barNeedLowerAmount,
        route: route,
      ),
  };
}

/// A tap on a slip's primary in send mode (see the file header). [session]
/// is the send it belongs to: the contact picked on Send prefills the
/// name, and the link created closes the flow ([SendPickSession.finish]).
/// The primary is disabled while the amount or the side cannot be sent;
/// a tap that still gets here says so in a toast.
Future<void> sendFromSlip(BuildContext context, SlipSharePick pick,
    {SendPickSession? session}) async {
  final l10n = context.l10n;
  final route = slipSendRoute(pick);
  SlipShare.debugRoute?.call(route, pick);
  final slug = pick.slug?.trim() ?? '';
  switch (route) {
    case SlipSendRoute.refused:
      // Never a link for a refused market: the slip already says why.
      return;
    case SlipSendRoute.market:
      // The market's card only: no money, no pick (a market the link
      // cannot name goes the same way).
      if (!SlipShare.debugOpen) return;
      return openShareForMarket(
        context,
        title: pick.title,
        subtitle: null,
        deepLink: marketShareLink(
            venue:
                pick.investing ? kMarketLinkInvesting : kMarketLinkPredictions,
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
    case SlipSendRoute.enterAmount:
      showMessageSnackBarInfo(
          context: context, message: l10n.slipShareEnterAmount);
      return;
    case SlipSendRoute.minimum:
      showMessageSnackBarInfo(
          context: context, message: l10n.slipShareMinimum(pick.minLabel));
      return;
    case SlipSendRoute.yesOnly:
      showMessageSnackBarInfo(
          context: context, message: l10n.slipShareYesOnly(pick.sideLabel));
      return;
    case SlipSendRoute.overReach:
      // Never a link for more than the person can reach.
      showMessageSnackBarInfo(
          context: context, message: l10n.sendMoreThanAvailable);
      return;
    case SlipSendRoute.pick:
      break;
  }
  if (!SlipShare.debugOpen) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final created = await showSendToAnyoneSheet(
    context,
    kind: ShareLinkKind.dollars,
    marketSlug: slug,
    marketTitle: pick.title,
    venue: pick.investing ? kShareVenueHyperliquid : kShareVenuePolymarket,
    outcome: pick.outcome!.trim(),
    outcomeIndex: pick.outcomeIndex,
    side: pick.side,
    amountMinor: pick.amountMinor,
    senderLabel: session?.recipientName,
    recipientPhone: session?.recipientPhone,
    entrySource: pick.entrySource,
  );
  if (created == true && session != null && navigator.mounted) {
    session.finish(navigator);
  }
}
