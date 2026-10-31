// lib/screens/shared/kute_share_actions.dart
//
// The bar context of a market or position page (founder, 31 October
// 2026): the bar reads "Share with your friends" with a line under it, and
// its Sal sheet opens on a market preview card and two action rows,
// "Share the market" (or "Share this position") and "Send this
// prediction" ("Send this investment" on Investing), with the prompts
// tuned to the page. The share row opens the market share sheet
// (screens/share/share_market_sheet.dart: preview card, Share link with
// the sender's referral code, Send this prediction); the send row opens
// Send to anyone with THE PICK on the link: the market, the outcome
// ("Yes", a candidate, Long / Short) and the side, so the recipient's
// Claim screen can open the slip ready to place
// (screens/share/send_to_anyone_sheet.dart, claim_screen.dart).
//
// THE PICK is the side the page shows: on a prediction market its leading
// outcome ([polymarketLeadingPick]: Yes or No by the chance, the top
// candidate of a multi-outcome event); on a prediction position the
// position's outcome; on an Investing market Long; on an Investing
// position its side.
//
// THE MARKET LINK. The app has no market deep link yet (incoming links are
// referral codes and `/c/{id}` claims, app_router.dart), so a shared
// market points at the backend, which has to route it:
//
//     https://backend.kutewallet.com/m/predictions/{event slug}
//     https://backend.kutewallet.com/m/investing/{coin}
//
// [kKuteMarketLinkBase] + `/m/` + [venue] + `/` + [slug]; the referral
// code is added as `?ref=CODE` by the share sheet. Send to anyone gets
// the same slug (a Predictions event slug, an Investing coin), which the
// backend accepts as `[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}`.
//
// Both rows run from the market page's own context one microtask after
// the tap: the Sal sheet pops itself right after a row's onTap, and a
// sheet pushed inside onTap would be the one popped.
//
// [KuteMarketBarContext] and [KuteMarketBarAction] extend the bar's plain
// model (kute_bar_context.dart, untouched) with what the Sal sheet draws
// for a market: the preview card and each row's leading glyph.

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
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
/// slug the link opens the venue.
String marketShareLink({required String venue, required String? slug}) {
  final s = slug?.trim() ?? '';
  if (s.isEmpty) return '$kKuteMarketLinkBase/m/$venue';
  return '$kKuteMarketLinkBase/m/$venue/${Uri.encodeComponent(s)}';
}

/// The share-link venue for a market-link venue segment.
String shareVenueFor(String linkVenue) => linkVenue == kMarketLinkInvesting
    ? kShareVenueHyperliquid
    : kShareVenuePolymarket;

/// The leading outcome of a prediction event, the pick a market page
/// shares by default: Yes or No by which is ahead on a binary market, the
/// top candidate otherwise. [chance] is that outcome's chance, 0–100.
({String label, int index, double chance})? polymarketLeadingPick(
    PolymarketEvent event) {
  final outcomes = event.outcomes;
  if (outcomes.isEmpty) return null;
  if (event.isBinary) {
    final yes = event.yesPrice;
    final pickYes = yes >= 0.5;
    final index = outcomes
        .indexWhere((o) => o.name.toLowerCase() == (pickYes ? 'yes' : 'no'));
    return (
      label: pickYes ? 'Yes' : 'No',
      index: index < 0 ? 0 : index,
      chance: (pickYes ? yes : 1 - yes).clamp(0.0, 1.0) * 100,
    );
  }
  var best = 0;
  for (var i = 1; i < outcomes.length; i++) {
    if (outcomes[i].price > outcomes[best].price) best = i;
  }
  return (
    label: outcomes[best].name,
    index: best,
    chance: outcomes[best].price.clamp(0.0, 1.0) * 100,
  );
}

/// What the Sal sheet's preview card shows for the market under the bar:
/// the title (two lines), one line under it ("Yes 62%", "$67,420.00",
/// "Long") and the market's picture: [imageUrl] for a prediction market,
/// the coin icon for [coin] on Investing.
@immutable
class KuteBarPreview {
  const KuteBarPreview({
    required this.title,
    this.line,
    this.imageUrl,
    this.coin,
  });

  final String title;
  final String? line;
  final String? imageUrl;
  final String? coin;
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
    required this.preview,
  });

  final KuteBarPreview preview;
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
/// sheet's preview card when the page has it at hand.
///
/// The pick: [outcome] is the label the page shows selected ("Yes", a
/// candidate, "Long"; Investing defaults to Long), [outcomeIndex] its
/// index in the event's outcomes (prediction markets; null when the page
/// has only the label), [outcomeChance] its chance 0–100 for the preview
/// line, [side] `buy` for a prediction outcome, `long` or `short` on
/// Investing. [imageUrl] is the market's picture for the preview card
/// (Investing draws the coin icon from [slug]).
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
  required List<String> prompts,
  double? chance,
  String? price,
  String? outcome,
  int? outcomeIndex,
  double? outcomeChance,
  String? side,
  String? imageUrl,
  double actionRowHeight = 0,
}) {
  final l10n = context.l10n;
  final cleanSlug = (slug?.trim().isEmpty ?? true) ? null : slug!.trim();
  final deepLink = marketShareLink(venue: venue, slug: cleanSlug);
  final investing = venue == kMarketLinkInvesting;
  final shareVenue = shareVenueFor(venue);
  final pickSide = side ?? (investing ? 'long' : 'buy');
  final pickLabel = outcome ?? (investing ? l10n.longLabel : null);
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
  return KuteMarketBarContext(
    label: l10n.barShareWithFriends,
    sublabel: position ? l10n.barSharePositionSub : l10n.barShareMarketSub,
    clip: 'share',
    category: category,
    searchHint: searchHint,
    source: source,
    prompts: prompts,
    preview: KuteBarPreview(
      title: title,
      line: previewLine,
      imageUrl: investing ? null : imageUrl,
      coin: investing ? cleanSlug : null,
    ),
    actionRowHeight: actionRowHeight,
    actions: [
      KuteMarketBarAction(
        label: position ? l10n.shareThisPosition : l10n.shareTheMarket,
        sublabel: position ? l10n.shareThisPositionSub : l10n.shareTheMarketSub,
        icon: Icons.ios_share_rounded,
        onTap: (_) => _afterSalSheet(context, () {
          unawaited(openShareForMarket(
            context,
            title: title,
            subtitle: subtitle,
            deepLink: deepLink,
            marketSlug: cleanSlug,
            chance: chance,
            price: price,
            venue: shareVenue,
            outcome: pickLabel,
            outcomeIndex: outcomeIndex,
            side: pickSide,
          ));
        }),
      ),
      KuteMarketBarAction(
        label: investing ? l10n.sendThisInvestment : l10n.sendThisPrediction,
        sublabel: l10n.sendThisPickSub,
        salClip: 'share',
        onTap: (_) => _afterSalSheet(context, () {
          unawaited(showSendToAnyoneSheet(
            context,
            kind: ShareLinkKind.dollars,
            marketSlug: cleanSlug,
            marketTitle: title,
            venue: shareVenue,
            outcome: pickLabel,
            outcomeIndex: outcomeIndex,
            side: pickSide,
            entrySource: 'market_bar',
          ));
        }),
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
