// lib/screens/shared/kute_share_actions.dart
//
// The bar context of a market or position page (founder, 31 October
// 2026): the bar reads "Share with your friends" with a line under it, and
// its Sal sheet opens on two recommended rows, "Share the market" (or
// "Share this position") and "Send dollars for this market", with the
// prompts tuned to the page. The share row goes through the OS share
// sheet with "{title} on Kute: {link}?ref={code}" (share_plus); the send
// row is a hook that says "Coming soon" until the Dollars send-to-anyone
// entry is merged (see kute_bar_context.dart).

import 'package:flutter/widgets.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:share_plus/share_plus.dart';

KuteBarContext marketBarContext(
  BuildContext context, {
  required String title,
  required String path,
  required String? code,
  required bool position,
  required SearchCategory category,
  required String? searchHint,
  required String source,
  required List<String> prompts,
}) {
  final l10n = context.l10n;
  final link = '$kKuteShareLinkBase$path${code == null ? '' : '?ref=$code'}';
  return KuteBarContext(
    label: l10n.barShareWithFriends,
    sublabel: position ? l10n.barSharePositionSub : l10n.barShareMarketSub,
    clip: 'share',
    category: category,
    searchHint: searchHint,
    source: source,
    prompts: prompts,
    actions: [
      KuteBarAction(
        label: position ? l10n.shareThisPosition : l10n.shareTheMarket,
        sublabel: position ? l10n.shareThisPositionSub : l10n.shareTheMarketSub,
        onTap: (_) {
          // ignore: discarded_futures
          SharePlus.instance
              .share(ShareParams(text: l10n.shareMarketText(title, link)));
        },
      ),
      KuteBarAction(
        label: l10n.sendDollarsForMarket,
        sublabel: l10n.sendDollarsForMarketSub,
        // TODO(share): the Dollars send-to-anyone entry, once merged.
        onTap: (sheetContext) => showMessageSnackBarInfo(
            context: sheetContext, message: l10n.comingSoon),
      ),
    ],
  );
}
