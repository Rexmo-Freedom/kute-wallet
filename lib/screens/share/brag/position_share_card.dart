// lib/screens/share/brag/position_share_card.dart
//
// THE SHARE CARD ON A POSITION PAGE (founder, 1 November 2026: the small
// "Your avg" chart under the Worth now / If it wins tiles goes, and the
// header's "Send to a friend" pill on a position page crowded "You hold
// No" beside the figure). One full-width card in the tiles' own style
// (AppDecorations.card): Sal's `share` face at 40 on the left, the title
// and a quiet line, a chevron.
//
//   * An open position in profit: "Brag about it"; a tap opens its brag
//     preview (the bar context's primaryAction, kute_share_actions.dart).
//   * Otherwise "Send to a friend"; a tap opens the position's Sal sheet
//     (send the market, send this prediction, and for an open position
//     "Show off this position").
//
// Market pages keep their header pill; only position pages draw this.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show openKuteBarSheet;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/kute_share_actions.dart'
    show KuteMarketBarContext;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// Sal's face on the card.
const double kPositionShareCardSal = 40;

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

  VoidCallback? get _bragAction {
    final ctx = bar;
    return brag && ctx is KuteMarketBarContext ? ctx.primaryAction : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final bragAction = _bragAction;
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
            decoration: AppDecorations.card(context),
            child: Row(
              children: [
                SalSprite(
                  clip: 'share',
                  size: kPositionShareCardSal,
                  fallback: KuteDogGlance(size: 30, color: c.textSecondary),
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
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        l10n.positionShareCardSub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
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
                    size: 22, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
