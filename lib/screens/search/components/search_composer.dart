// lib/screens/search/components/search_composer.dart
//
// THE SAL SHEET'S COMPOSER (founder, 31 October 2026: "it must be and look
// much better"): one 52 px field pinned at the foot of the search sheet,
// above the keyboard. The floating pill's own fill and hairline, squared
// to the lists' 16 radius: the pill MORPHS into this (search_morph.dart),
// so the two must read as one object. Sal's `search` clip at 28 on the
// left, the hint "Search or ask Sal", and the circular send arrow at the
// right that scales in once there is text. With Sal off (the AI kill
// switch) it is a plain search field with a clear ✕.
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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmit;
  final bool aiEnabled;

  /// Null: "Search or ask Sal" with Sal, the wallet search hint without.
  final String? hint;
  final String? sendLabel;

  /// The field's height.
  static const double height = 52;

  /// Sal's size at the left.
  static const double spriteSize = 28;

  /// The field's inset from the sheet's edges.
  static double gutter(BuildContext context) => 16.w;

  /// The space before Sal.
  static double leading(BuildContext context) => 14.w;

  /// The field's corner.
  static double radius(BuildContext context) => 16.r;

  /// The field's surface: the floating pill's fill and hairline (white
  /// over a hairline in light, one step up from the sheet in dark), at the
  /// lists' corner; the morph lands on exactly this.
  static BoxDecoration decoration(BuildContext context,
      {double? borderRadius}) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: isLight ? Colors.white : c.surfaceLight,
      borderRadius: BorderRadius.circular(borderRadius ?? radius(context)),
      border: Border.all(
        color: isLight ? c.border : c.borderSubtle,
        width: isLight ? 1.0 : 0.5,
      ),
      boxShadow: isLight
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }

  /// The hint's style (the pill's label settles into it).
  static TextStyle hintStyle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter(context)),
      child: Container(
        height: height,
        decoration: decoration(context),
        padding: EdgeInsets.only(left: leading(context), right: 8.w),
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
              Icon(Icons.search_rounded, size: 22, color: c.textTertiary),
            SizedBox(width: 10.w),
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
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint ??
                      (aiEnabled
                          ? context.l10n.searchOrAskSalShort
                          : context.l10n.searchYourWallet),
                  hintStyle: hintStyle(context),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
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
      ),
    );
  }

  Widget _trailing(BuildContext context, bool hasText) {
    final c = context.colors;
    if (!aiEnabled) {
      if (!hasText) return const SizedBox(width: 36);
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
