// lib/screens/search/components/search_composer.dart
//
// THE SAL SHEET'S COMPOSER (founder, 31 October 2026: "it must be and look much
// better", then flat: no boxed input; 2 November 2026, after a filled field was
// tried: "I liked the previous one better ... same design, just make it look
// better"): one plain LINE pinned at the TOP of the search sheet, under the
// drag handle. Sal's `search` clip at 32 on the left, centred on the text, the
// text at 18 sp, the hint ("Search or Manage with AI", narrowed to the venue)
// in textSecondary so it reads as something to tap, a hairline in the border
// colour under the whole line, and the circular send arrow at the right that
// scales in only once there is text. The hint is never cut: the arrow's slot
// is closed while the line is empty, and a hint longer than the line (the
// venue hints in the longer languages) shrinks to fit it
// ([KuteSearchComposer.fittedHintStyle]). A tap anywhere on the line focuses
// it. The sheet's content scrolls under it. [scope] (the "All ⌄" chip while
// there is a query) sits before the arrow. The floating pill MORPHS into this
// line (search_morph.dart): its fill and hairline fade to the bare line as it
// travels, so the two read as one object. With Sal off (the AI kill switch) it
// is a plain search field with a clear ✕.
//
// [KuteSearchComposer.decoration] and the sizes here are what the morph
// draws its end state with; change them in one place.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

class KuteSearchComposer extends StatelessWidget {
  const KuteSearchComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.focusNode,
    this.onChanged,
    this.aiEnabled = true,
    this.hint,
    this.sendLabel,
    this.scope,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmit;
  final bool aiEnabled;

  /// Null: "Search or Manage with AI" with Sal, the wallet search hint
  /// without.
  final String? hint;
  final String? sendLabel;

  /// The scope chip at the right of the line ("All ⌄"), only with a query.
  final Widget? scope;

  /// The line's height (the hairline included).
  static const double height = 56;

  /// Sal's size at the left.
  static const double spriteSize = 32;

  /// The line's inset from the sheet's edges.
  static double gutter(BuildContext context) => 16.w;

  /// The space before Sal: none, he starts the line.
  static double leading(BuildContext context) => 0;

  /// The space between Sal and the text.
  static double gap(BuildContext context) => 12.w;

  /// The send arrow and the space before it; the slot is closed while the
  /// line is empty, so the hint has the whole line.
  static const double sendSize = 36;
  static double sendSlot(BuildContext context) => 8.w + sendSize;

  /// The hairline under the line: thin, but present enough to read as an
  /// input.
  static const double hairline = 0.8;

  /// The line's surface: nothing but the hairline under it; the morph
  /// lands on exactly this.
  static BoxDecoration decoration(BuildContext context) => BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.border, width: hairline),
        ),
      );

  /// The text's style, 18 sp.
  static TextStyle textStyle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 18.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.4,
      );

  /// The hint's style (the pill's label settles into it): the text's
  /// size in textSecondary.
  static TextStyle hintStyle(BuildContext context) =>
      textStyle(context).copyWith(color: context.colors.textSecondary);

  /// How wide the hint may run in a line [lineWidth] wide: Sal and the
  /// gap before it; the arrow's slot is closed while the hint shows.
  static double hintWidth(BuildContext context, double lineWidth) =>
      math.max(0.0, lineWidth - leading(context) - spriteSize - gap(context));

  /// [hintStyle], shrunk just enough for [hint] to sit on one line
  /// [maxWidth] wide: the hint is never cut.
  static TextStyle fittedHintStyle(
      BuildContext context, String hint, double maxWidth) {
    final style = hintStyle(context);
    if (!maxWidth.isFinite || maxWidth <= 0) return style;
    final painter = TextPainter(
      text: TextSpan(
          text: hint,
          style: Theme.of(context).textTheme.bodyLarge?.merge(style) ?? style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final needed = painter.width;
    painter.dispose();
    // A hair of room so rounding never wraps or clips the last glyph.
    final room = maxWidth - 2;
    if (needed <= room) return style;
    final scale = room / needed;
    return style.copyWith(
      fontSize: style.fontSize! * scale,
      letterSpacing: (style.letterSpacing ?? 0) * scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hintText = hint ??
        (aiEnabled
            ? context.l10n.searchOrManageAi
            : context.l10n.searchYourWallet);
    // The line itself is the root (no gutters here): the sheet insets it,
    // and the morph measures this box. A tap on Sal or around the text
    // focuses the field too.
    final line = Container(
      height: height,
      decoration: decoration(context),
      padding: EdgeInsets.only(left: leading(context)),
      child: Row(
        children: [
          if (aiEnabled)
            SalSprite(
              clip: 'search',
              size: spriteSize,
              fallback: SvgPicture.asset(kuteDogAsset(context),
                  width: spriteSize, height: spriteSize),
            )
          else
            SizedBox(
              width: spriteSize,
              child: Icon(Icons.search_rounded,
                  size: 24, color: c.textSecondary),
            ),
          SizedBox(width: gap(context)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmit(),
                textInputAction:
                    aiEnabled ? TextInputAction.send : TextInputAction.search,
                autocorrect: false,
                textAlignVertical: TextAlignVertical.center,
                style: textStyle(context),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  hintMaxLines: 1,
                  hintStyle:
                      fittedHintStyle(context, hintText, constraints.maxWidth),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (scope != null) ...[
            SizedBox(width: 8.w),
            scope!,
          ],
          // Only the button follows the text: typing never rebuilds the
          // sheet around the composer.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) =>
                _trailing(context, value.text.trim().isNotEmpty),
          ),
        ],
      ),
    );
    final node = focusNode;
    if (node == null) return line;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: node.requestFocus,
      child: line,
    );
  }

  Widget _trailing(BuildContext context, bool hasText) {
    final c = context.colors;
    if (!aiEnabled) {
      if (!hasText) return const SizedBox.shrink();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.clear();
          onChanged?.call('');
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.close_rounded, size: 20, color: c.textTertiary),
        ),
      );
    }
    // The slot opens as the arrow scales in, so while the line is empty
    // the hint has all of it.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: hasText ? sendSlot(context) : 0,
      height: sendSize,
      alignment: Alignment.centerRight,
      child: OverflowBox(
        alignment: Alignment.centerRight,
        minWidth: sendSize,
        maxWidth: sendSize,
        child: Semantics(
          button: true,
          enabled: hasText,
          label: sendLabel ?? context.l10n.salSendQuestion,
          child: AnimatedScale(
            scale: hasText ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: GestureDetector(
              // Haptics belong to the caller ([onSubmit]), which also runs
              // from the keyboard's action key.
              onTap: hasText ? onSubmit : null,
              child: Container(
                width: sendSize,
                height: sendSize,
                decoration: BoxDecoration(
                  color: context.ctaFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward_rounded,
                    size: 20, color: context.ctaOnColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
