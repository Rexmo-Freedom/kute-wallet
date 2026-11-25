// lib/screens/shared/kute_share_actions.dart
//
// The bar context of a market or position page (founder, 31 October
// 2026): the bar reads "Send to a friend" with a line under it. (Founder,
// 1 November 2026: on Predictions and Investing the word is never
// "Share", always send to a friend.)
//
// STRAIGHT INTO SENDING THE MARKET (founder, 5 November 2026: "the other
// shares are just sharing the market, no picker"; "so we can take the
// user straight into that"). A tap on the page's round Sal button (a
// trade row's, kute_bar_trade_row.dart) or on its Sal pill (an event, a
// game) opens the market send sheet at once
// ([KuteMarketBarContext.shareMarket], the context's
// [KuteBarContext.directAction]; screens/share/share_market_sheet.dart:
// the market's card, Share with the sender's referral code): no Sal sheet
// and no "Send the market / Send a prediction" picker in between. On an
// open position in profit the round button opens the brag card instead
// (position_share_card.dart).
//
// A PREDICTION IS SENT FROM SEND ONLY (founder, 7 November 2026: "only in
// Send should it be to send to someone"): Send's market search opens the
// market in send mode, and its slip's primary sends THAT prediction, its
// market, side and amount (screens/share/slip_share.dart). Nothing here
// composes a pick any more.
//
// The Sal sheet still draws the market's preview and its one card ("Send
// the market", or "Send this position"; "Show off this position" beside
// it on an open position) where something opens it with this context
// (a long press on a primary button).
//
// THE MARKET LINK. The app has no market deep link yet (incoming links are
// referral codes and `/c/{id}` claims, app_router.dart), so a shared
// market points at the backend, which has to route it:
//
//     https://backend.kutewallet.com/m/predictions/{event slug}
//     https://backend.kutewallet.com/m/investing/{coin}
//
// [kKuteMarketLinkBase] + `/m/` + [venue] + `/` + [slug]; the referral
// code is added as `?ref=CODE` by the share sheet.
//
// ONE MARKET OF AN EVENT (founder, 7 November 2026: "sharing here should
// be just the yes or no. only here is the full market"). A candidate
// opened as its own Yes / No page (the ↑76,000 row of "What price will
// Bitcoin hit November 2-8?") shares THAT market: its card is the
// market's question and its Yes chance (share_card_sources.dart,
// predictionCardFor's `candidate`), and its link names it as a send-a-pick
// link does, by the candidate's name on the event:
//
//     https://backend.kutewallet.com/m/predictions/{event slug}?outcome={name}
//
// The event page (all its outcomes) keeps sharing the whole event.
//
// A Sal sheet card runs from the market page's own context one microtask
// after the tap: the Sal sheet pops itself right after a row's onTap, and
// a sheet pushed inside onTap would be the one popped.
//
// [KuteMarketBarContext] and [KuteMarketBarAction] extend the bar's plain
// model (kute_bar_context.dart) with what the Sal sheet draws for a
// market: the preview card and each row's leading glyph.
//
// BRAG (founder, 1 November 2026: "open positions and the portfolio should
// also be shareable with a friend, to brag"). An OPEN position page passes
// [marketBarContext]'s `brag`, the card's data built on demand
// (screens/share/brag/brag_data.dart): [KuteMarketBarContext.primaryAction]
// opens the brag preview at once, for the page's share card ("Brag about
// it" in profit, screens/share/brag/position_share_card.dart). A settled
// position passes none.
//
// SHARE CARDS (founder, 1 November 2026): the market send sheet ends on a
// 4:5 share card (screens/share/cards/): the market page hands over its
// picture and logo for it.

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/brag/brag_data.dart' show BragData;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart'
    show showBragPreviewSheet;
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

/// Where a shared market's link points (see the file header).
const String kKuteMarketLinkBase = 'https://backend.kutewallet.com';

/// The venue segment of a market link.
const String kMarketLinkPredictions = 'predictions';
const String kMarketLinkInvesting = 'investing';

/// The venue a share link names: the wire values the backend takes.
const String kShareVenuePolymarket = 'polymarket';
const String kShareVenueHyperliquid = 'hyperliquid';

/// The link for one market: [venue] is [kMarketLinkPredictions] or
/// [kMarketLinkInvesting], [slug] the event slug or the coin; without a
/// slug the link opens the venue. [outcome] names one market of the event
/// (a candidate by its name on the event, see the file header): the link
/// is then about that market alone.
String marketShareLink(
    {required String venue, required String? slug, String? outcome}) {
  final s = slug?.trim() ?? '';
  if (s.isEmpty) return '$kKuteMarketLinkBase/m/$venue';
  final base = '$kKuteMarketLinkBase/m/$venue/${Uri.encodeComponent(s)}';
  final o = outcome?.trim() ?? '';
  if (o.isEmpty) return base;
  return Uri.parse(base)
      .replace(queryParameters: {'outcome': o}).toString();
}

/// The share-link venue for a market-link venue segment.
String shareVenueFor(String linkVenue) => linkVenue == kMarketLinkInvesting
    ? kShareVenueHyperliquid
    : kShareVenuePolymarket;

/// What the Sal sheet's preview card shows for the market under the bar:
/// the title (two lines), one line under it ("Yes 62%", "$67,420.00",
/// "Long") and the market's picture: [imageUrl] for a prediction market,
/// the coin icon for [coin] on Investing.
@immutable
class KuteBarPreview {
  const KuteBarPreview({
    required this.title,
    this.subtitle,
    this.line,
    this.imageUrl,
    this.coin,
    this.wireCoin,
    this.coinCategory,
    this.coinIconUrl,
  });

  /// The name the market page's header gives it: the event title, or an
  /// Investing market's display name ("Nasdaq 100").
  final String title;

  /// The quieter line under it: an Investing market's ticker ("XYZ100")
  /// when the title is its display name.
  final String? subtitle;
  final String? line;
  final String? imageUrl;

  /// An Investing market's logo, drawn exactly as its page header draws
  /// it (HlCoinIcon): the display coin, the wire coin a builder-dex market
  /// trades under ("xyz:XYZ100"), its category and its logo URL.
  final String? coin;
  final String? wireCoin;
  final String? coinCategory;
  final String? coinIconUrl;
}

/// A market page's bar context: the plain context plus the preview card
/// the Sal sheet draws on top.
class KuteMarketBarContext extends KuteBarContext {
  const KuteMarketBarContext({
    required super.label,
    super.sublabel,
    super.clip,
    super.actions,
    super.prompts,
    super.category,
    super.searchHint,
    super.source,
    super.actionRowHeight,
    super.route,
    super.placement,
    required this.preview,
    this.primaryAction,
    this.shareMarket,
  });

  final KuteBarPreview preview;

  /// An open position's brag preview, for the share card (the round Sal
  /// button runs it in profit, position_share_card.dart); null: none.
  final VoidCallback? primaryAction;

  /// The market send sheet for this page's market (see the file header):
  /// what a tap on the pill or the round Sal button opens, no Sal sheet in
  /// between.
  final VoidCallback? shareMarket;

  @override
  VoidCallback? get directAction => shareMarket;

  /// The scope binds the context to its route (kute_bar_context.dart);
  /// the preview rides along.
  @override
  KuteBarContext boundTo(Route<dynamic>? route) => KuteMarketBarContext(
        label: label,
        sublabel: sublabel,
        clip: clip,
        actions: actions,
        prompts: prompts,
        category: category,
        searchHint: searchHint,
        source: source,
        actionRowHeight: actionRowHeight,
        route: route,
        placement: placement,
        preview: preview,
        primaryAction: primaryAction,
        shareMarket: shareMarket,
      );
}

/// An action row with its leading glyph: [salClip] draws Sal's face
/// (SalSprite), else [icon] in the tinted circle.
class KuteMarketBarAction extends KuteBarAction {
  const KuteMarketBarAction({
    required super.label,
    super.sublabel,
    required super.onTap,
    this.icon,
    this.salClip,
  });

  final IconData? icon;
  final String? salClip;
}

/// The bar context of a market ([position] false) or position page.
/// [chance] is the Yes side's chance (0–100) of a prediction market,
/// [price] the formatted price of a trading market; either feeds the share
/// sheet's card when the page has it at hand.
///
/// [outcome] and [outcomeChance] (0–100) are a position's own side, for
/// the preview line ("Yes 64%", "Long"). [imageUrl] is the market's
/// picture for the card (Investing draws the coin icon from [slug]).
///
/// [candidate]: the page is one market of the event [slug] names, opened
/// as its own Yes / No page (the candidate by its name on the event): the
/// share is that market alone, its card and its link (see the file
/// header). Null: the whole event (or a plain market).
KuteBarContext marketBarContext(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String venue,
  required String? slug,
  required bool position,
  required SearchCategory category,
  required String? searchHint,
  required String source,
  List<String> prompts = const [],
  double? chance,
  String? price,
  String? outcome,
  double? outcomeChance,
  String? imageUrl,
  // An Investing market as its page header shows it: the display name
  // ([title] is then "Nasdaq 100") with the ticker under it, and the
  // logo's sources (HlCoinIcon).
  String? ticker,
  String? wireCoin,
  String? coinCategory,
  String? coinIconUrl,
  double actionRowHeight = 0,
  // The page's Sal control: the floating pill, or the circle in the page's
  // header (market, position and event pages; see KuteBarPlacement).
  KuteBarPlacement placement = KuteBarPlacement.bottom,
  // An open position's brag card, built when asked (see the file header).
  BragData Function()? brag,
  String? candidate,
}) {
  final l10n = context.l10n;
  final cleanSlug = (slug?.trim().isEmpty ?? true) ? null : slug!.trim();
  final investing = venue == kMarketLinkInvesting;
  final oneMarket = investing || (candidate?.trim().isEmpty ?? true)
      ? null
      : candidate!.trim();
  final deepLink =
      marketShareLink(venue: venue, slug: cleanSlug, outcome: oneMarket);
  final shareVenue = shareVenueFor(venue);
  // A position's side, for the preview line.
  final pickLabel = position
      ? (outcome ?? (investing ? l10n.longLabel : null))
      : null;
  final String? previewLine;
  if (pickLabel != null && outcomeChance != null) {
    previewLine = '$pickLabel ${outcomeChance.round()}%';
  } else if (price != null && price.isNotEmpty) {
    previewLine = pickLabel == null ? price : '$pickLabel · $price';
  } else if (pickLabel != null) {
    previewLine = pickLabel;
  } else if (chance != null) {
    previewLine = l10n.shareMarketChance(chance.round().toString());
  } else {
    previewLine = subtitle;
  }
  void openBrag() {
    final build = brag;
    if (build == null || !context.mounted) return;
    unawaited(showBragPreviewSheet(context, build()));
  }

  // The market send sheet (see the file header).
  void openMarketShare() {
    if (!context.mounted) return;
    unawaited(openShareForMarket(
      context,
      title: title,
      subtitle: subtitle,
      deepLink: deepLink,
      marketSlug: cleanSlug,
      chance: chance,
      price: price,
      venue: shareVenue,
      candidate: oneMarket,
      // The share card's picture until the providers have the market
      // (screens/share/cards/share_card_sources.dart).
      imageUrl: investing ? null : imageUrl,
      ticker: investing ? ticker : null,
      wireCoin: investing ? wireCoin : null,
      coinCategory: investing ? coinCategory : null,
      coinIconUrl: investing ? coinIconUrl : null,
    ));
  }

  return KuteMarketBarContext(
    primaryAction: brag == null ? null : openBrag,
    shareMarket: openMarketShare,
    label: l10n.barShareWithFriends,
    // No second line for a market (founder, 11 November 2026: no "They
    // get a link to look at it").
    sublabel: position ? l10n.barSharePositionSub : null,
    clip: 'share',
    category: category,
    searchHint: searchHint,
    source: source,
    prompts: prompts,
    placement: placement,
    preview: KuteBarPreview(
      title: title,
      subtitle: ticker != null && ticker != title ? ticker : null,
      line: previewLine,
      imageUrl: investing ? null : imageUrl,
      coin: investing ? cleanSlug : null,
      wireCoin: investing ? wireCoin : null,
      coinCategory: investing ? coinCategory : null,
      coinIconUrl: investing ? coinIconUrl : null,
    ),
    actionRowHeight: actionRowHeight,
    actions: [
      KuteMarketBarAction(
        label: position ? l10n.shareThisPosition : l10n.shareTheMarket,
        sublabel: position ? l10n.shareThisPositionSub : null,
        icon: Icons.ios_share_rounded,
        onTap: (_) => _afterSalSheet(context, openMarketShare),
      ),
      if (brag != null)
        KuteMarketBarAction(
          label: l10n.bragPositionAction,
          sublabel: l10n.bragPositionActionSub,
          salClip: 'wink',
          onTap: (_) => _afterSalSheet(context, openBrag),
        ),
    ],
  );
}

/// Runs [body] on the market page once the Sal sheet's own pop has gone
/// through (see the file header), and only while the page is still there.
void _afterSalSheet(BuildContext pageContext, VoidCallback body) {
  scheduleMicrotask(() {
    if (!pageContext.mounted) return;
    body();
  });
}
