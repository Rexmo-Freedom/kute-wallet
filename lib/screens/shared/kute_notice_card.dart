// lib/screens/shared/kute_notice_card.dart
//
// THE HOME NOTICE CARD: the Bitcoin home's "Back up your wallet / In case
// you lose your phone" row ([SecurityActionCard], home_wallet_switcher.dart),
// drawn here so another notice (the web's "get the app",
// get_app_notice.dart) is the same card and not a lookalike. One compact
// neutral row in the app's card chrome: Sal in his circle, a title and one
// line, then the filled action pill(s), and optionally a close control.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// One filled pill of a [KuteNoticeCard].
class KuteNoticeAction {
  const KuteNoticeAction({
    required this.label,
    this.onTap,
    this.busy = false,
    this.key,
  });

  final String label;

  /// Its own tap. Null: the pill is only the visible action of a card
  /// whose whole row is the target ([KuteNoticeCard.onTap]).
  final VoidCallback? onTap;
  final bool busy;
  final Key? key;
}

class KuteNoticeCard extends StatelessWidget {
  const KuteNoticeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.titleMaxLines = 1,
    this.onTap,
    this.onClose,
    this.closeLabel,
    this.closeKey,
  });

  final String title;

  /// The one line under the title; null for a notice that is one sentence
  /// (it then takes [titleMaxLines] lines of the title).
  final String? subtitle;
  final int titleMaxLines;
  final List<KuteNoticeAction> actions;

  /// The whole row's tap, or null.
  final VoidCallback? onTap;

  /// The close control at the row's end, or none.
  final VoidCallback? onClose;
  final String? closeLabel;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final close = onClose;
    final sal = Container(
      width: 36.sp,
      height: 36.sp,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      // Sal in the circle (founder, 31 October 2026): surprised
      // once as the card appears, then held on that last frame;
      // the shield until the sheets exist.
      child: ClipOval(
        child: SalSprite(
          clip: 'surprise',
          loop: false,
          size: 36.sp,
          fallback: Icon(Icons.shield_outlined,
              color: c.textSecondary, size: 18.sp),
        ),
      ),
    );
    final texts = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: titleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2)),
          if (subtitle != null) ...[
            SizedBox(height: 2.h),
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.3)),
          ],
        ],
      ),
    );
    final closeControl = close == null
        ? null
        : Semantics(
            button: true,
            label: closeLabel,
            excludeSemantics: true,
            child: GestureDetector(
              key: closeKey,
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: Padding(
                padding: EdgeInsets.all(6.sp),
                child: Icon(Icons.close_rounded,
                    color: c.textTertiary, size: 18.sp),
              ),
            ),
          );
    final pills = [
      for (final action in actions) ...[
        SizedBox(width: 8.w),
        _pill(context, action),
      ],
    ];
    Widget oneRow() => Row(
          children: [
            sal,
            SizedBox(width: 12.w),
            texts,
            ...pills,
            if (closeControl != null) ...[
              SizedBox(width: 4.w),
              closeControl,
            ],
          ],
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        // Same chrome as every other card in the app (floating shadow
        // card in light, hairline surface in dark).
        decoration: AppDecorations.card(context),
        // One row, as the backup reminder is; with more than one pill
        // and too little width for them beside the words, the pills take
        // a second line under the words, at the row's end.
        child: actions.length <= 1
            ? oneRow()
            : LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= _twoActionsRowMinWidth.w) {
            return oneRow();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  sal,
                  SizedBox(width: 12.w),
                  texts,
                  if (closeControl != null) ...[
                    SizedBox(width: 4.w),
                    closeControl,
                  ],
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: pills,
              ),
            ],
          );
        }),
      ),
    );
  }

  /// The card's inner width under which two pills move under the words.
  static const double _twoActionsRowMinWidth = 520;

  Widget _pill(BuildContext context, KuteNoticeAction action) {
    final pill = Container(
      key: action.onTap == null ? action.key : null,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: context.ctaFill,
        borderRadius: AppRadius.buttonBorder,
      ),
      child: action.busy
          ? LoadingAnimationWidget.staggeredDotsWave(
              color: context.ctaOnColor, size: 13.sp)
          : Text(
              action.label,
              maxLines: 1,
              style: TextStyle(
                color: context.ctaOnColor,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                height: 1.0,
              ),
            ),
    );
    final onTap = action.onTap;
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: action.key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
