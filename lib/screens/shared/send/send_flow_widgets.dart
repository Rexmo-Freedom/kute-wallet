// lib/screens/shared/send/send_flow_widgets.dart
//
// THE PIECES BOTH SEND FLOWS ARE BUILT FROM.
//
// Send bitcoin (`confirm_send.dart`) and Send dollars
// (`usd/usd_send_screen.dart`) are the same three screens to the person
// using them: an amount on the app's own keypad, a recipient field that
// recognises whatever is pasted or scanned, and a review with one Send
// button. They keep separate money paths on purpose (a dollar send must
// never fall back to spending bitcoin), so what they share is everything
// on screen: the frame, the recipient field, the list cards under it,
// the clipboard nudge and the review rows. Each widget here was lifted
// out of the bitcoin send as it was, so that flow renders exactly as
// before and the dollar flow cannot drift from it.
//
// Presentation only: no provider, no route table and no money call.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show groupTypedAmount;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';

/// The send stepper's body under the app bar: the screen gradient, the
/// step progress, the steps as pages the flow advances itself, and the
/// shared bottom action.
class SendStepperFrame extends StatelessWidget {
  const SendStepperFrame({
    super.key,
    required this.progress,
    required this.controller,
    required this.pages,
    required this.cta,
    this.onPageChanged,
  });

  /// The step progress bar (or an empty box for a one-step flow).
  final Widget progress;
  final PageController controller;
  final List<Widget> pages;

  /// The shared Continue under the pages. Each step decides whether it
  /// shows one.
  final Widget cta;
  final ValueChanged<int>? onPageChanged;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    // Bottom padding for the Continue CTA. iOS sits ~44dp above the
    // home indicator (was 32.h); Android adds the gesture-nav inset
    // on top of a 28.h baseline.
    final bottomPad = Platform.isAndroid
        ? 28.h + MediaQuery.of(context).padding.bottom
        : 44.h;
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // 20.w horizontal padding so the Continue CTA sits inside
          // the standard screen gutter instead of stretching nearly
          // edge-to-edge.
          padding: EdgeInsets.fromLTRB(
              20.w, 12.h, 20.w, bottomPad + (viewInsets > 0 ? viewInsets : 0)),
          child: Column(
            children: [
              progress,
              SizedBox(height: 12.h),
              Expanded(
                child: PageView(
                  controller: controller,
                  // Steps advance only via the Continue/Next buttons.
                  // Swiping must NOT skip a step — it would bypass the
                  // per-step validation and completion tracking.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: onPageChanged,
                  children: pages,
                ),
              ),
              cta,
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero figure's type: the one big number on the amount and review
/// steps.
TextStyle sendHeroAmountStyle(Color color) => TextStyle(
      color: color,
      fontSize: 56.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A typed decimal amount as one big static number with its currency
/// prefix. The raw string carries no thousands separators and is grouped
/// only for display, so the keypad can read it straight back.
class SendTypedAmountHero extends StatelessWidget {
  const SendTypedAmountHero({
    super.key,
    required this.prefix,
    required this.typed,
    this.overBalance = false,
  });

  final String prefix;
  final String typed;
  final bool overBalance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasDigits = typed.isNotEmpty && (double.tryParse(typed) ?? 0) != 0;
    final color = !hasDigits
        ? c.textTertiary
        : overBalance
            ? AppColors.marketDown
            : c.textPrimary;
    final amountTextStyle = sendHeroAmountStyle(color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(prefix, style: amountTextStyle),
        SizedBox(width: 6.w),
        Text(typed.isEmpty ? '0' : groupTypedAmount(typed),
            maxLines: 1, style: amountTextStyle),
      ],
    );
  }
}

/// The unit pill beside the amount hero. With [onTap] it is the control
/// that changes the unit; without one it only names it.
class SendAmountUnitPill extends StatelessWidget {
  final String code;
  final Widget icon;
  final VoidCallback? onTap;

  const SendAmountUnitPill(
      {super.key, required this.code, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.buttonBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.buttonBorder,
        child: Container(
          constraints: BoxConstraints(minHeight: 48.h),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.buttonBorder,
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            SizedBox(width: 8.w),
            Text(code,
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                    letterSpacing: -0.2)),
            if (onTap != null) ...[
              SizedBox(width: 6.w),
              Icon(Icons.expand_more_rounded,
                  color: c.textSecondary, size: 20.sp),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Recipient field of the Send to step. One tall surface card (56pt
/// minimum, hairline border, 14 radius) that holds the address or
/// invoice and the two ways to fill it: an inline Paste button and an
/// inline Scan button that live inside the field while it is empty.
/// Once text is in they give way to a validation tick plus a clear
/// button. No leading icon: the address itself is the focus and the
/// network is communicated by the badge below.
class SendRecipientField extends StatelessWidget {
  final TextEditingController controller;
  final AppColorsExtension colors;
  final ValueChanged<String> onChanged;

  /// Inline Paste: reads the clipboard and runs the flow's commit path.
  final VoidCallback onPaste;

  /// Inline Scan: opens the smart scanner in return-value mode.
  final VoidCallback onScan;

  /// Whether the current text is a recipient the flow recognises. Drives
  /// the green border and the tick.
  final bool isValid;

  /// Placeholder shown when the field is empty.
  final String? hintText;

  const SendRecipientField({
    super.key,
    required this.controller,
    required this.colors,
    required this.onChanged,
    required this.onPaste,
    required this.onScan,
    required this.isValid,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final addr = controller.text;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedContainer(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      constraints: BoxConstraints(minHeight: 56.h),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 6.w, 4.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isValid
              ? c.success
              : addr.isNotEmpty
                  ? c.border
                  : c.borderSubtle,
          width: isValid ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              cursorColor: c.accent,
              cursorWidth: 2.0,
              maxLines: 2,
              minLines: 1,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText ??
                    context.l10n.sendBitcoinLightningOrSparkAddressHint,
                hintMaxLines: 2,
                hintStyle: TextStyle(
                    color: c.textSecondary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                isDense: true,
              ),
            ),
          ),
          SizedBox(width: 4.w),
          // Trailing controls share one slot so the field never jumps:
          // Paste + Scan while empty, tick + clear once there is text.
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: addr.isEmpty
                ? Row(
                    key: const ValueKey('empty'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SendFieldIconButton(
                        icon: Icons.content_paste_rounded,
                        tooltip: context.l10n.paste,
                        colors: c,
                        onTap: onPaste,
                      ),
                      SendFieldIconButton(
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: context.l10n.scan,
                        colors: c,
                        onTap: onScan,
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('filled'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isValid)
                        Container(
                          margin: EdgeInsets.only(right: 4.w),
                          width: 24.sp,
                          height: 24.sp,
                          decoration: BoxDecoration(
                            color: c.success,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded,
                              color: Colors.white, size: 16.sp),
                        ),
                      SendFieldIconButton(
                        icon: Icons.cancel_rounded,
                        tooltip: context.l10n.close,
                        colors: c,
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 44pt icon button that sits inside the recipient field.
class SendFieldIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  const SendFieldIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 44.sp, minHeight: 44.sp),
      icon: Icon(icon, color: colors.textSecondary, size: 22.sp),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

/// Subtle pill that appears below the address field once the flow has
/// identified what was pasted: a filled check, the kind's icon and its
/// plain-words label. Animates in so the moment of recognition reads as
/// deliberate.
class SendDetectedBadge extends StatelessWidget {
  const SendDetectedBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.identity,
  });

  final String label;
  final IconData icon;

  /// The check disc's fill.
  final Color color;

  /// What the badge animates on. Defaults to [label].
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Container(
          key: ValueKey('detected-${identity ?? label}'),
          padding: EdgeInsets.fromLTRB(8.w, 6.h, 12.w, 6.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18.sp,
                height: 18.sp,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 12.sp,
                ),
              ),
              SizedBox(width: 8.w),
              Icon(icon, color: c.textSecondary, size: 14.sp),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of red copy under the recipient field: the reason the
/// entered recipient cannot be used. Continue stays dead beside it.
class SendRecipientError extends StatelessWidget {
  const SendRecipientError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.error,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Neutral list row used under the recipient field on the Send to
/// step (recent recipients, the destination card). Leading 40pt
/// artwork, title with optional subtitle, optional trailing amount and
/// date, chevron. Rows stack inside [SendToListCard] with hairline
/// dividers.
class SendToListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailingTitle;
  final String? trailingSubtitle;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  const SendToListRow({
    super.key,
    required this.leading,
    required this.title,
    required this.colors,
    required this.onTap,
    this.subtitle,
    this.trailingTitle,
    this.trailingSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The trailing column may never squeeze the recipient out on a
    // narrow screen or at a large text scale: cap it and ellipsize.
    final trailingMax = MediaQuery.sizeOf(context).width * 0.34;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            // Bare artwork, no tile or border behind it (user decision).
            SizedBox(
              width: 40.sp,
              height: 40.sp,
              child: Center(child: leading),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
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
                ],
              ),
            ),
            if (trailingTitle != null || trailingSubtitle != null) ...[
              SizedBox(width: 10.w),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: trailingMax),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingTitle != null)
                      Text(
                        trailingTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (trailingSubtitle != null) ...[
                      if (trailingTitle != null) SizedBox(height: 2.h),
                      Text(
                        trailingSubtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            SizedBox(width: 6.w),
            Icon(Icons.chevron_right_rounded,
                size: 20.sp, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Surface card that stacks [SendToListRow]s with hairline dividers
/// indented past the leading tile.
class SendToListCard extends StatelessWidget {
  final List<Widget> rows;
  final AppColorsExtension colors;

  /// Draws the border in the stronger border colour. Used while the
  /// entered address still needs a network pick, where the card is the
  /// only forward path.
  final bool emphasized;

  const SendToListCard({
    super.key,
    required this.rows,
    required this.colors,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: emphasized ? c.border : c.borderSubtle,
          width: emphasized ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: c.borderSubtle,
                indent: 68.w,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Section label above a list card on the Send to step.
class SendToSectionHeader extends StatelessWidget {
  const SendToSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Quiet one-line card under the recipient field while the clipboard
/// holds something payable: Use fills the field, the cross dismisses.
class SendClipboardNudge extends StatelessWidget {
  const SendClipboardNudge({
    super.key,
    required this.onUse,
    required this.onDismiss,
  });

  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 4.h, 4.w, 4.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.content_paste_rounded,
              size: 18.sp, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              context.l10n.sendClipboardAddressFound,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ),
          SizedBox(width: 6.w),
          InkWell(
            onTap: onUse,
            borderRadius: BorderRadius.circular(8.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              child: Text(
                context.l10n.useIt,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
          SendFieldIconButton(
            icon: Icons.close_rounded,
            tooltip: context.l10n.close,
            colors: c,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// The card the Review rows sit on.
class SendReviewCard extends StatelessWidget {
  const SendReviewCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: c.borderSubtle, width: 1.0),
      ),
      child: child,
    );
  }
}

/// A From or To row of the Review card. The label rides on the same
/// line as the value, the mark sits in a 28.sp slot.
class SendReviewSummaryRow extends StatelessWidget {
  const SendReviewSummaryRow({
    super.key,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String label;
  final String title;
  final String subtitle;
  final Widget icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      child: Row(
        children: [
          // Bare icon, no tinted halo: the mark IS the identity here.
          SizedBox(
            width: 28.sp,
            height: 28.sp,
            child: Center(child: icon),
          ),
          SizedBox(width: 10.w),
          Text(label,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              )),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(subtitle,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 6.w),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A label and its value on the Review fee card. [muted] renders the
/// quiet grey fee language — fees and ETAs are context, not the headline
/// numbers of the review card.
class SendReviewKVRow extends StatelessWidget {
  const SendReviewKVRow({
    super.key,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Text(label,
            style: TextStyle(
              color: muted ? c.textTertiary : c.textSecondary,
              fontSize: muted ? 13.sp : 15.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            )),
        SizedBox(width: 12.w),
        // The value is usually a short figure, but some callers pass a
        // whole sentence here when the fee cannot be worked out, so it
        // wraps and stays inside the row.
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: muted ? c.textTertiary : c.textPrimary,
                fontSize: muted ? 13.sp : 16.sp,
                fontWeight: muted ? FontWeight.w600 : FontWeight.w800,
                letterSpacing: -0.2,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      ],
    );
  }
}

/// A Review fee-card row whose value is the reason it cannot be shown,
/// in red.
class SendReviewErrorRow extends StatelessWidget {
  const SendReviewErrorRow(
      {super.key, required this.label, required this.error});

  final String label;
  final String error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            )),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            error,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.error,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small info line under the Review fee rows.
class SendReviewNote extends StatelessWidget {
  const SendReviewNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14.sp, color: c.textTertiary),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full destination string under the Review "To" row, wrapped so every
/// character is readable, with a Copy action.
class SendReviewFullAddress extends StatelessWidget {
  const SendReviewFullAddress({
    super.key,
    required this.address,
    this.onCopied,
  });

  final String address;

  /// Called after the address is on the clipboard (analytics; never the
  /// address itself).
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              address,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                height: 1.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: 6.h),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: address));
                  onCopied?.call();
                  if (!context.mounted) return;
                  showMessageSnackBarInfo(
                      context: context, message: context.l10n.copied);
                },
                borderRadius: BorderRadius.circular(8.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded,
                          size: 14.sp, color: c.textPrimary),
                      SizedBox(width: 4.w),
                      Text(
                        context.l10n.copy,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Review step's one primary action and the footnote under it.
class SendReviewAction extends StatelessWidget {
  const SendReviewAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.footnote,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String footnote;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(text: label, isLoading: loading, onPressed: onPressed),
        SizedBox(height: 8.h),
        Center(
          child: Text(
            footnote,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shortened destination for a one-line row: the first ten and last
/// eight characters.
String sendShortAddress(String addr) => addr.length > 22
    ? '${addr.substring(0, 10)}…${addr.substring(addr.length - 8)}'
    : addr;
