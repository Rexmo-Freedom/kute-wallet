// lib/screens/search/components/search_composer.dart
//
// THE SAL SHEET'S COMPOSER (founder, 31 October 2026: "it must be and look much
// better"; 2 November 2026: "should be more evident to click, right now the
// text is too light"): one FIELD pinned at the TOP of the search sheet, under
// the drag handle, filled and rounded like the app's other inputs
// (app_text_field.dart: surfaceLight, the 1 px border, [AppRadius.lg]). Sal's
// `search` clip at 28 inside its left edge, the text at 17 sp (the hint
// "Search or manage with AI" in textSecondary), and the circular send arrow
// inside its right edge that scales in only once there is text; a tap anywhere
// on it focuses the field. The sheet's content scrolls under it. [scope] (the
// "All ⌄" chip while there is a query) sits before the arrow. The floating
// pill MORPHS into this field (search_morph.dart): its fill, corner and
// hairline settle into the field's as it travels, so the two read as one
// object. With Sal off (the AI kill switch) it is a plain search field with a
// clear ✕.
//
// [KuteSearchComposer.decoration] and the sizes here are what the morph
// draws its end state with; change them in one place.

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

  /// Null: "Search or manage with AI" with Sal, the wallet search hint
  /// without.
  final String? hint;
  final String? sendLabel;

  /// The scope chip at the right of the line ("All ⌄"), only with a query.
  final Widget? scope;

  /// The field's height (its border included).
  static const double height = 56;

  /// Sal's size at the left.
  static const double spriteSize = 28;

  /// The field's inset from the sheet's edges.
  static double gutter(BuildContext context) => 16.w;

  /// The space inside the field before Sal.
  static double leading(BuildContext context) => 14.w;

  /// The space inside the field after the send arrow.
  static double trailing(BuildContext context) => 10.w;

  /// The field's surface, the app's input (app_text_field.dart): the
  /// morph lands on exactly this.
  static BoxDecoration decoration(BuildContext context) => BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.border, width: 1),
      );

  /// The text's style, 17 sp.
  static TextStyle textStyle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 17.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.3,
      );

  /// The hint's style (the pill's label settles into it): the text's
  /// size in textSecondary, strong enough to read as a field to tap.
  static TextStyle hintStyle(BuildContext context) =>
      textStyle(context).copyWith(color: context.colors.textSecondary);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The field itself is the root (no gutters here): the sheet insets it,
    // and the morph measures this box. A tap on Sal or the padding focuses
    // the field too.
    final field = Container(
      height: height,
      decoration: decoration(context),
      padding: EdgeInsets.only(
          left: leading(context), right: trailing(context)),
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
            Icon(Icons.search_rounded, size: 24, color: c.textSecondary),
          SizedBox(width: 12.w),
          Expanded(
            child: TextField(
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
                hintText: hint ??
                    (aiEnabled
                        ? context.l10n.searchOrManageAi
                        : context.l10n.searchYourWallet),
                hintStyle: hintStyle(context),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (scope != null) ...[
            SizedBox(width: 8.w),
            scope!,
          ],
          SizedBox(width: 6.w),
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
    if (node == null) return field;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: node.requestFocus,
      child: field,
    );
  }

  Widget _trailing(BuildContext context, bool hasText) {
    final c = context.colors;
    if (!aiEnabled) {
      if (!hasText) return const SizedBox.shrink();
      return GestureDetector(
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
    return Semantics(
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.ctaFill,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_upward_rounded,
                size: 20, color: context.ctaOnColor),
          ),
        ),
      ),
    );
  }
}
