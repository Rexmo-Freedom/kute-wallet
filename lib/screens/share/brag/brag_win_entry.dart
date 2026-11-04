// lib/screens/share/brag/brag_win_entry.dart
//
// "BRAG ABOUT IT" ON A PAST WIN (founder, 4 November 2026: "Able to share
// past prediction brags also, won ones"). The door a surface that shows a
// won prediction in a sheet puts under its figures: the black share
// button ([ShareActionCard]), "Brag about it" over "A card with your
// result", opening the won card's
// preview (brag_preview_sheet.dart) with the data the surface built
// (brag_data.dart: bragWonPrediction, bragWonPosition). A surface that has
// no win to show (a loss, an open position, a win with no profit) gets
// null from those builders and draws nothing: [BragWinEntry.maybe].
//
// Used by the activity receipts of a won payout and of a won result
// (transactions_builder.dart); the resolved position page reaches the
// same preview through its floating bar ("Brag about it",
// position_detail_sheet.dart). The Portfolio's past positions can put
// [BragWinEntry.maybe] (or call showBragPreviewSheet with
// bragWonPosition's card) on a won row's detail.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_data.dart' show BragWin;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart'
    show showBragPreviewSheet;
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

class BragWinEntry extends StatelessWidget {
  const BragWinEntry({super.key, required this.data});

  /// The won card to open.
  final BragWin data;

  /// The entry for [data], or nothing when there is no win to brag about.
  static Widget maybe(BragWin? data, {EdgeInsetsGeometry? padding}) {
    if (data == null) return const SizedBox.shrink();
    final entry = BragWinEntry(data: data);
    return padding == null ? entry : Padding(padding: padding, child: entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ShareActionCard(
      key: const ValueKey('brag-win-entry'),
      keyPrefix: 'brag-win-entry',
      title: l10n.bragAboutIt,
      sub: l10n.bragPositionActionSub,
      onTap: () => unawaited(showBragPreviewSheet(context, data)),
    );
  }
}

/// Sal's face on the button.
const double kShareActionCardSal = 40;

/// The black share button the position page wore under its tiles until
/// 4 November 2026 (the share floats in the bar now): Sal's `share` face,
/// [title] over [sub], a chevron; [onTap] opens what it shares. A won
/// payout's receipt wears it. Its parts are keyed `{keyPrefix}-title`,
/// `{keyPrefix}-sub` and `{keyPrefix}-chevron`.
class ShareActionCard extends StatelessWidget {
  const ShareActionCard({
    super.key,
    required this.title,
    required this.sub,
    required this.onTap,
    required this.keyPrefix,
  });

  final String title;
  final String sub;
  final VoidCallback onTap;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : c.background;
    return Semantics(
      button: true,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
            decoration: AppDecorations.card(context,
                color: c.textPrimary, borderColor: c.textPrimary),
            child: Row(
              children: [
                SalSprite(
                  clip: 'share',
                  size: kShareActionCardSal,
                  fallback: KuteDogGlance(size: 30, color: ink),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: ValueKey('$keyPrefix-title'),
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
                        sub,
                        key: ValueKey('$keyPrefix-sub'),
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
                    key: ValueKey('$keyPrefix-chevron'),
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
