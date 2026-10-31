// lib/screens/shared/kute_share_actions.dart
//
// The bar context of a market or position page (founder, 31 October
// 2026): the bar reads "Share with your friends" with a line under it, and
// its Sal sheet opens on two recommended rows, "Share the market" (or
// "Share this position") and "Send dollars for this market", with the
// prompts tuned to the page. The share row opens the market share sheet
// (screens/share/share_market_sheet.dart: preview card, Share link with
// the sender's referral code, Send dollars); the send row opens Send to
// anyone for dollars with the market on the link
// (screens/share/send_to_anyone_sheet.dart).
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

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kute/l10n/l10n.dart';
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

/// The link for one market: [venue] is [kMarketLinkPredictions] or
/// [kMarketLinkInvesting], [slug] the event slug or the coin; without a
/// slug the link opens the venue.
String marketShareLink({required String venue, required String? slug}) {
  final s = slug?.trim() ?? '';
  if (s.isEmpty) return '$kKuteMarketLinkBase/m/$venue';
  return '$kKuteMarketLinkBase/m/$venue/${Uri.encodeComponent(s)}';
}

/// The bar context of a market ([position] false) or position page.
/// [chance] is the Yes side's chance (0–100) of a prediction market,
/// [price] the formatted price of a trading market; either feeds the share
/// sheet's preview card when the page has it at hand.
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
  double actionRowHeight = 0,
}) {
  final l10n = context.l10n;
  final cleanSlug = (slug?.trim().isEmpty ?? true) ? null : slug!.trim();
  final deepLink = marketShareLink(venue: venue, slug: cleanSlug);
  return KuteBarContext(
    label: l10n.barShareWithFriends,
    sublabel: position ? l10n.barSharePositionSub : l10n.barShareMarketSub,
    clip: 'share',
    category: category,
    searchHint: searchHint,
    source: source,
    prompts: prompts,
    actionRowHeight: actionRowHeight,
    actions: [
      KuteBarAction(
        label: position ? l10n.shareThisPosition : l10n.shareTheMarket,
        sublabel: position ? l10n.shareThisPositionSub : l10n.shareTheMarketSub,
        onTap: (_) => _afterSalSheet(context, () {
          unawaited(openShareForMarket(
            context,
            title: title,
            subtitle: subtitle,
            deepLink: deepLink,
            marketSlug: cleanSlug,
            chance: chance,
            price: price,
          ));
        }),
      ),
      KuteBarAction(
        label: l10n.sendDollarsForMarket,
        sublabel: l10n.sendDollarsForMarketSub,
        onTap: (_) => _afterSalSheet(context, () {
          unawaited(showSendToAnyoneSheet(
            context,
            kind: ShareLinkKind.dollars,
            marketSlug: cleanSlug,
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
