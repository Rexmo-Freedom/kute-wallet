import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_glass.dart';
import 'package:kute/theme/app_theme.dart';

/// The one composer search and Sal share: a Liquid Glass field (Apple glass
/// on iOS, tonal on Android), the Kute dog leading it, and a ctaFill circle
/// that scales in once there is text and sends. While Sal is answering
/// ([loading]) the same circle holds a stop square instead. With
/// [aiEnabled] false it is a plain search field with a clear button.
///
/// Haptics belong to the callers ([onSubmit] / [onStop]), which also run
/// from the keyboard's action key.
class KuteComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onStop;
  final bool aiEnabled;
  final bool loading;
  final bool enabled;
  final int? maxLength;

  /// Null shows "Search or ask Sal" with [aiEnabled], and the wallet
  /// search hint without it, in the app language.
  final String? hint;
  final String? sendLabel;
  final String? stopLabel;

  const KuteComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.focusNode,
    this.onChanged,
    this.onStop,
    this.aiEnabled = true,
    this.loading = false,
    this.enabled = true,
    this.maxLength,
    this.hint,
    this.sendLabel,
    this.stopLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: KuteGlass(
        borderRadius: BorderRadius.circular(16.r),
        padding: EdgeInsets.fromLTRB(14.w, 4.h, 6.w, 4.h),
        child: Row(
          children: [
            if (aiEnabled)
              SvgPicture.asset(kuteDogAsset(context),
                  width: 24.sp, height: 24.sp)
            else
              Icon(Icons.search_rounded, size: 22.sp, color: c.textTertiary),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmit(),
                textInputAction:
                    aiEnabled ? TextInputAction.send : TextInputAction.search,
                autocorrect: false,
                inputFormatters: maxLength == null
                    ? null
                    : [LengthLimitingTextInputFormatter(maxLength)],
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint ??
                      (aiEnabled
                          ? context.l10n.searchOrAskSalShort
                          : context.l10n.searchYourWallet),
                  hintStyle: TextStyle(
                    color: c.textPrimary.withValues(alpha: 0.65),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            SizedBox(width: 6.w),
            // Only the button follows the text: typing never rebuilds the
            // screen around the composer.
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
      if (!hasText) return SizedBox(width: 36.sp);
      return GestureDetector(
        onTap: () {
          controller.clear();
          onChanged?.call('');
        },
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child:
              Icon(Icons.close_rounded, size: 20.sp, color: c.textTertiary),
        ),
      );
    }
    final stop = loading && onStop != null;
    final visible = stop || (hasText && enabled && !loading);
    return Semantics(
      button: true,
      enabled: visible,
      label: stop ? stopLabel : sendLabel,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTap: !visible ? null : (stop ? onStop : onSubmit),
          child: Container(
            width: 36.sp,
            height: 36.sp,
            decoration: BoxDecoration(
              color: context.ctaFill,
              shape: BoxShape.circle,
            ),
            child: Icon(
                stop ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 20.sp,
                color: context.ctaOnColor),
          ),
        ),
      ),
    );
  }
}
