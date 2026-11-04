// lib/screens/share/brag/position_share_card.dart
//
// THE SHARE ON A POSITION PAGE (founder, 1 November 2026). "Brag about
// it" on an open position in profit (a tap opens its brag preview, the
// bar context's primaryAction, kute_share_actions.dart), else "Send to a
// friend" (a tap opens the position's Sal sheet: send the market, send
// this prediction, and for an open position "Show off this position").
//
//   * INVESTING (Hyperliquid) position page: [PositionSharePill] at the
//     top right beside the big figure, the market pages' header button
//     exactly (KuteSalHeaderButton's look: fully rounded, the textPrimary
//     fill, Sal's face 26 and the label at w600, 40 tall), in the page's
//     KuteFigureShareRow. Not in profit, it IS the header button.
//   * PREDICTIONS position page: [PositionShareCard], one full-width
//     BLACK button under the Worth now / If it wins tiles: the textPrimary
//     fill, the title and the quiet line in the contrast ink, Sal's
//     `share` face at 40 on the left, a chevron in the ink.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteSalHeaderButton, openKuteBarSheet;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/kute_share_actions.dart'
    show KuteMarketBarContext;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// Sal's face on the card.
const double kPositionShareCardSal = 40;

/// The page's brag action: an open position in profit whose context has
/// the card's action; else null (the Sal sheet).
VoidCallback? _bragAction(KuteBarContext bar, bool brag) =>
    brag && bar is KuteMarketBarContext ? bar.primaryAction : null;

/// The black button's ink: white on the light page, the page colour on
/// the dark one (textPrimary is white there), as the header button.
Color _ink(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : context.colors.background;

class PositionShareCard extends StatelessWidget {
  const PositionShareCard({
    super.key,
    required this.bar,
    required this.brag,
  });

  /// The page's bar context (its Sal sheet, and the brag preview as its
  /// primaryAction on an open position).
  final KuteBarContext bar;

  /// The brag variant: an open position in profit.
  final bool brag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final bragAction = _bragAction(bar, brag);
    final ink = _ink(context);
    return Semantics(
      button: true,
      child: KutePressable(
        child: GestureDetector(
          key: const ValueKey('position-share-card'),
          behavior: HitTestBehavior.opaque,
          onTap: bragAction ??
              () => unawaited(openKuteBarSheet(bar, source: context)),
          child: Container(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
            decoration: AppDecorations.card(context,
                color: c.textPrimary, borderColor: c.textPrimary),
            child: Row(
              children: [
                SalSprite(
                  clip: 'share',
                  size: kPositionShareCardSal,
                  fallback: KuteDogGlance(size: 30, color: ink),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bragAction != null
                            ? l10n.bragAboutIt
                            : l10n.shareHeaderLabel,
                        key: const ValueKey('position-share-card-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        l10n.positionShareCardSub,
                        key: const ValueKey('position-share-card-sub'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.72),
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right_rounded,
                    key: const ValueKey('position-share-card-chevron'),
                    size: 22,
                    color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Investing position page's share at the top right, beside the big
/// figure: "Brag about it" (opens the card) in the header button's look
/// on an open position in profit; otherwise the header button itself
/// ("Send to a friend" / "Share", the Sal sheet).
class PositionSharePill extends StatelessWidget {
  const PositionSharePill({super.key, required this.bar, required this.brag});

  final KuteBarContext bar;
  final bool brag;

  @override
  Widget build(BuildContext context) {
    final bragAction = _bragAction(bar, brag);
    if (bragAction == null) return KuteSalHeaderButton(barContext: bar);
    final c = context.colors;
    final ink = _ink(context);
    final label = context.l10n.bragAboutIt;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: KutePressable(
        child: GestureDetector(
          key: const ValueKey('position-share-pill'),
          behavior: HitTestBehavior.opaque,
          onTap: bragAction,
          child: Container(
            height: KuteSalHeaderButton.height,
            padding: const EdgeInsetsDirectional.only(
              start: KuteSalHeaderButton.paddingStart,
              end: KuteSalHeaderButton.paddingEnd,
            ),
            decoration: BoxDecoration(
              color: c.textPrimary,
              borderRadius:
                  BorderRadius.circular(KuteSalHeaderButton.height / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SalSprite(
                  clip: 'share',
                  size: KuteSalHeaderButton.salSize,
                  fallback: KuteDogGlance(size: 22, color: ink),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    key: const ValueKey('position-share-pill-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KuteSalHeaderButton.labelStyle(ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
