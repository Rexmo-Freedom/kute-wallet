// lib/screens/share/share_market_sheet.dart
//
// SHARE A MARKET. [openShareForMarket] is the hook a market page's Share
// entry calls (the market detail header rows belong to another branch;
// this file only has to exist for them to wire). A compact sheet: a
// preview card (title, subtitle, the chance or the price, the "kute."
// wordmark) over two buttons:
//
//   * Share link: the OS share sheet with "Look at this on Kute: {title}
//     {deepLink}", the sender's referral code on the link as `?ref=CODE`
//     (the affiliate code AffiliateService already holds).
//   * Send dollars for this: Send to anyone (send_to_anyone_sheet.dart)
//     for dollars, the market slug on the link.
//
// `share_market_opened {market}` once per open. Never the link.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_wordmark.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The market share sheet's route name.
const String kShareMarketRouteName = 'share_market';

/// Opens the share sheet for one market. [chance] is 0–100 for a
/// prediction market; [price] a formatted price for a trading market.
Future<void> openShareForMarket(
  BuildContext context, {
  required String title,
  required String? subtitle,
  required String deepLink,
  required String? marketSlug,
  double? chance,
  String? price,
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

class ShareMarketSheet extends ConsumerWidget {
  const ShareMarketSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.deepLink,
    required this.marketSlug,
    this.chance,
    this.price,
  });

  final String title;
  final String? subtitle;
  final String deepLink;
  final String? marketSlug;
  final double? chance;
  final String? price;

  /// Test seam: what Share link hands the OS. Null opens the share sheet.
  @visibleForTesting
  static Future<String> Function(String text)? debugSharer;

  String get _link =>
      shareLinkWithReferral(deepLink, code: AffiliateService.affiliateCode);

  Future<void> _share(BuildContext context) async {
    final text = context.l10n.shareMarketLookAt(title, _link);
    final debug = debugSharer;
    try {
      final String result;
      if (debug != null) {
        result = await debug(text);
      } else {
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null
            ? (box.localToGlobal(ui.Offset.zero) & box.size)
            : (ui.Offset.zero & const ui.Size(1, 1));
        final r = await SharePlus.instance
            .share(ShareParams(text: text, sharePositionOrigin: origin));
        result = r.status.name;
      }
      TrackingService.track('share_market_link_shared', params: {
        'market': marketSlug ?? 'none',
        'result': result,
      });
    } catch (_) {
      TrackingService.track('share_market_link_shared', params: {
        'market': marketSlug ?? 'none',
        'result': 'error',
      });
    }
  }

  Future<void> _sendDollars(BuildContext context) async {
    final navigator = Navigator.of(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    navigator.pop();
    await showSendToAnyoneSheet(
      root,
      kind: ShareLinkKind.dollars,
      marketSlug: marketSlug,
      entrySource: 'share_market',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final String? figure = chance != null
        ? l10n.shareMarketChance(chance!.round().toString())
        : price;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
              title: l10n.share, icon: Icons.ios_share_rounded),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The preview: what the recipient's link opens.
                Container(
                  key: const ValueKey('share-market-preview'),
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: c.borderSubtle, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          if (figure != null)
                            Expanded(
                              child: Text(
                                figure,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 22.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          KuteWordmark(size: 18.sp, color: c.textTertiary),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.h),
                AppButton(
                  key: const ValueKey('share-market-link'),
                  text: l10n.shareMarketShareLink,
                  onPressed: () => unawaited(_share(context)),
                ),
                SizedBox(height: 8.h),
                AppTextButton(
                  key: const ValueKey('share-market-send-dollars'),
                  text: l10n.shareMarketSendDollars,
                  onPressed: () => unawaited(_sendDollars(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
