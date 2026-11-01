// lib/screens/share/share_market_sheet.dart
//
// SHARE A MARKET. [openShareForMarket] is the hook a market page's Share
// entry calls (the market detail header rows belong to another branch;
// this file only has to exist for them to wire). A compact sheet: THE
// SHARE CARD first (founder, 1 November 2026: sharing always shows the
// card; cards/share_cards.dart): the actual stock on Investing (its logo,
// name, the price and today's change in the headline, the 30-day line),
// the prediction market's odds by topic on Predictions, live from the
// providers (cards/share_card_sources.dart), over two buttons:
//
//   * Share, the bar: the card as a PNG in the OS share sheet with the
//     card's headline, Sal's line and "Look at this on Kute: {title}
//     {deepLink}" (shareCardMessage), the sender's referral code on
//     the link as `?ref=CODE` (the affiliate code AffiliateService already
//     holds) and drawn on the card's footer.
//   * Send this prediction (Send this investment on Investing): Send to
//     anyone (send_to_anyone_sheet.dart) for dollars with the pick on the
//     link: the market slug and title, the venue, the outcome and side the
//     page showed (kute_share_actions.dart).
//
// `share_market_opened {market}` once per open. Never the link.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardMessage;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/tracking_service.dart';

/// The market share sheet's route name.
const String kShareMarketRouteName = 'share_market';

/// Opens the share sheet for one market. [chance] is 0–100 for a
/// prediction market; [price] a formatted price for a trading market.
/// [venue], [outcome], [outcomeIndex] and [side] are the pick the send
/// button carries (see the file header). [imageUrl] is a prediction
/// market's picture; [ticker], [wireCoin], [coinCategory] and
/// [coinIconUrl] an Investing market's logo and ticker, for the card
/// until the providers have the market.
Future<void> openShareForMarket(
  BuildContext context, {
  required String title,
  required String? subtitle,
  required String deepLink,
  required String? marketSlug,
  double? chance,
  String? price,
  String? venue,
  String? outcome,
  int? outcomeIndex,
  String? side,
  String? imageUrl,
  String? ticker,
  String? wireCoin,
  String? coinCategory,
  String? coinIconUrl,
}) {
  ShareLinkEvents.marketOpened(marketSlug: marketSlug);
  return showAppBottomSheet<void>(
    context: context,
    routeSettings: const RouteSettings(name: kShareMarketRouteName),
    builder: (_) => ShareMarketSheet(
      title: title,
      subtitle: subtitle,
      deepLink: deepLink,
      marketSlug: marketSlug,
      chance: chance,
      price: price,
      venue: venue,
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: side,
      imageUrl: imageUrl,
      ticker: ticker,
      wireCoin: wireCoin,
      coinCategory: coinCategory,
      coinIconUrl: coinIconUrl,
    ),
  );
}

/// [deepLink] with the referral code appended as `ref`, when the wallet
/// has one. Other query parameters are kept.
String shareLinkWithReferral(String deepLink, {String? code}) {
  final c = code?.trim() ?? '';
  if (c.isEmpty) return deepLink;
  final uri = Uri.tryParse(deepLink);
  if (uri == null) return deepLink;
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'ref': c}).toString();
}

class ShareMarketSheet extends ConsumerStatefulWidget {
  const ShareMarketSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.deepLink,
    required this.marketSlug,
    this.chance,
    this.price,
    this.venue,
    this.outcome,
    this.outcomeIndex,
    this.side,
    this.imageUrl,
    this.ticker,
    this.wireCoin,
    this.coinCategory,
    this.coinIconUrl,
  });

  final String title;
  final String? subtitle;
  final String deepLink;
  final String? marketSlug;
  final double? chance;
  final String? price;

  /// The pick the send button carries (see the file header).
  final String? venue;
  final String? outcome;
  final int? outcomeIndex;
  final String? side;

  /// What the page had for the card (see openShareForMarket).
  final String? imageUrl;
  final String? ticker;
  final String? wireCoin;
  final String? coinCategory;
  final String? coinIconUrl;

  bool get investing => venue == 'hyperliquid';

  /// The card: the actual stock on Investing, the market's odds on
  /// Predictions, live from the providers.
  ShareCardData card(ShareCardWatch watch) {
    final code = AffiliateService.affiliateCode;
    final slug = marketSlug ?? '';
    if (investing && slug.isNotEmpty) {
      return investmentCardFor(
        watch,
        coin: slug,
        title: title,
        ticker: ticker,
        wireCoin: wireCoin,
        iconUrl: coinIconUrl,
        category: coinCategory,
        referralCode: code,
      );
    }
    // Shared without a pick: the market's leading outcome. The chance the
    // page had is the Yes side's on a binary market.
    return predictionCardFor(
      watch,
      slug: marketSlug,
      title: title,
      chance: chance,
      imageUrl: imageUrl,
      referralCode: code,
    );
  }

  @override
  ConsumerState<ShareMarketSheet> createState() => _ShareMarketSheetState();
}

class _ShareMarketSheetState extends ConsumerState<ShareMarketSheet> {
  final GlobalKey _boundary = GlobalKey();
  final int _seed = ShareCardShare.seed();
  bool _busy = false;

  String get _link => shareLinkWithReferral(widget.deepLink,
      code: AffiliateService.affiliateCode);

  Future<void> _share(ShareCardData data) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final text = shareCardMessage(
        l10n, data, l10n.shareMarketLookAt(widget.title, _link));
    final result =
        await shareCardImage(context, _boundary, text: text, name: data.kind);
    TrackingService.track('share_market_link_shared', params: {
      'market': widget.marketSlug ?? 'none',
      'result': result,
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendPick(BuildContext context) async {
    final navigator = Navigator.of(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    navigator.pop();
    await showSendToAnyoneSheet(
      root,
      kind: ShareLinkKind.dollars,
      marketSlug: widget.marketSlug,
      marketTitle: widget.title,
      venue: widget.venue,
      outcome: widget.outcome,
      outcomeIndex: widget.outcomeIndex,
      side: widget.side,
      entrySource: 'share_market',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = widget.card(<T>(p) => ref.watch(p));
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Founder (1 November 2026): on Predictions and Investing the
          // word is never "Share" for the sheet; the card's button is.
          AppBottomSheetHeader(
              title: l10n.sendToAFriend, icon: Icons.ios_share_rounded),
          ShareCardPreviewBox(
            key: const ValueKey('share-market-preview'),
            data: data,
            boundaryKey: _boundary,
            heightFraction: 0.48,
            lineSeed: _seed,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The second button stays on the sheet, as a text button
                // above the bar.
                AppTextButton(
                  key: const ValueKey('share-market-send-pick'),
                  text: widget.investing
                      ? l10n.sendThisInvestment
                      : l10n.sendThisPrediction,
                  onPressed: () => unawaited(_sendPick(context)),
                ),
                // THE BAR IS THE BUTTON (kute_bar_context.dart): Share
                // sends the card with the link; the sheet keeps clear of
                // it.
                KuteBarContextScope(
                  barContext: KuteBarContext.primary(
                    label: l10n.share,
                    onPrimary: () => unawaited(_share(data)),
                    busy: _busy,
                    category: widget.investing
                        ? SearchCategory.perpetuals
                        : SearchCategory.predictions,
                    source: 'share_market',
                    disabledLabel: null,
                  ),
                  child: SizedBox(height: kuteBarScrollClearance.h),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
