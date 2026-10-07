// lib/screens/polymarket/components/slip_chrome.dart
//
// The chrome the two Polymarket tickets share. Buying (bet_slip_sheet)
// and selling (sell_sheet) are the same sheet with a different verb, so
// the header, the quick-percent chips, the Advanced row, the headline
// figure and the primary action live here once instead of drifting apart
// in two 2,000-line files.
//
// Everything below reads `context.colors`, so a ticket wrapped in
// `SideTintedSubtree` re-inks itself on the side colour for free. The
// only widget that needs to know it is sitting on a tint is the CTA,
// which inverts (see [PolySlipCta]).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/theme/app_theme.dart';

/// The ticket's title without the event repeated in front of it. A market
/// opened from an event arrives as "event: question", and on a
/// single-market event the two are the same words ("Villena: A vs B:
/// Villena: A vs B"), or the question already opens with the event. In
/// either case the question is shown once, on its own. Comparison ignores
/// case, runs of whitespace and trailing punctuation; anything else is
/// returned as given.
String polySlipTitle(String title) {
  String collapse(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  String norm(String s) =>
      collapse(s).replaceAll(RegExp(r'[\s.?!:;,\-\u2013\u2014]+$'), '');
  final wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  var from = 0;
  while (true) {
    final i = title.indexOf(':', from);
    if (i < 0) return title;
    from = i + 1;
    final head = norm(title.substring(0, i));
    final rest = title.substring(i + 1).trim();
    if (head.isEmpty || rest.isEmpty) continue;
    final tail = collapse(rest);
    if (norm(rest) == head) return rest;
    if (tail.startsWith(head) &&
        (tail.length == head.length ||
            !wordChar.hasMatch(tail[head.length]))) {
      return rest;
    }
  }
}

/// Identity row at the top of a ticket: market thumb + question, an
/// optional trailing chip (the buy slip's Ask Sal), then the close X.
/// The question ellipsizes so the trailing cluster never wraps.
class PolySlipHeader extends StatelessWidget {
  const PolySlipHeader({
    super.key,
    required this.marketQuestion,
    this.marketImage,
    this.trailing,
  });

  final String marketQuestion;
  final String? marketImage;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final img = marketImage;
    final marketQuestion = polySlipTitle(this.marketQuestion);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 12.w, 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (img != null && img.isNotEmpty) ...[
            PolyCrestImage(
              url: img,
              size: 36.sp,
              radius: 10.r,
              fallback: Container(
                width: 36.sp,
                height: 36.sp,
                color: c.surfaceLight,
              ),
            ),
            SizedBox(width: 10.w),
          ],
          Expanded(
            // The whole question, never cut: up to five lines, in a
            // smaller face the longer it runs.
            child: Text(
              marketQuestion,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: marketQuestion.length > 90
                    ? 14.sp
                    : marketQuestion.length > 48
                        ? 15.sp
                        : 17.sp,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                height: 1.3,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          if (trailing != null) ...[
            trailing!,
            SizedBox(width: 8.w),
          ],
          const KuteCloseButton(),
        ],
      ),
    );
  }
}

/// The ticket's one-line "Advanced" entry. A bare text row floated on the
/// tinted sheet with nothing to sit on, so it takes a secondary step.
///
/// [expanded] null means the row opens a separate page and the chevron
/// points right; a non-null value means it expands in place and the
/// chevron rotates.
class PolySlipAdvancedRow extends StatelessWidget {
  const PolySlipAdvancedRow({
    super.key,
    required this.onTap,
    this.trailingText,
    this.expanded,
  });

  final VoidCallback onTap;
  final String? trailingText;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = expanded;
    return Semantics(
      button: true,
      expanded: open,
      child: Material(
        color: c.surfaceLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
            side: BorderSide(color: c.border, width: 0.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 14.w),
            child: Row(children: [
              Icon(Icons.tune_rounded, size: 20.sp, color: c.textPrimary),
              SizedBox(width: 10.w),
              Expanded(
                  child: Text(context.l10n.walletsAdvanced,
                      style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary))),
              if (trailingText != null)
                Text(trailingText!,
                    style: TextStyle(fontSize: 14.sp, color: c.textSecondary)),
              SizedBox(width: 8.w),
              if (open == null)
                Icon(Icons.chevron_right_rounded,
                    size: 22.sp, color: c.textSecondary)
              else
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 22.sp, color: c.textSecondary),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The one headline number on the ticket under the amount: what the bet
/// pays if it wins, or what the sale puts back in the account.
/// [valueColor] overrides the figure's ink — the side-tinted sheet passes
/// its own, since green on green is not a number.
class PolySlipFigureRow extends StatelessWidget {
  const PolySlipFigureRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary)),
        ),
        SizedBox(width: 12.w),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedBalance(
              text: value,
              style: TextStyle(
                  color: valueColor ?? c.textPrimary,
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// The ticket's single primary action.
///
/// On a side-tinted sheet the CTA inverts: the sheet's ink becomes the
/// fill and the side colour becomes the label, so the one action still
/// reads as the one action. A red button on a red sheet does not.
class PolySlipCta extends StatelessWidget {
  const PolySlipCta({
    super.key,
    required this.color,
    required this.isBusy,
    required this.enabled,
    required this.onTap,
    required this.label,
    this.busyLabel,
  });

  final Color color;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onTap;
  final String label;

  /// Shown beside the spinner while [isBusy]. Defaults to the buy slip's
  /// "Placing order…".
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    // Reduce-motion: the enabled/colour fill tween is decorative.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final tint = SheetTint.maybeOf(context);
    final bg = tint == null
        ? (enabled ? color : color.withValues(alpha: 0.40))
        : tint.on.withValues(alpha: enabled ? 1 : 0.22);
    // Label contrast follows the fill (the deposit branch runs the dark
    // primary fill, which is WHITE in dark mode — white text there was
    // the old invisible-label bug class).
    final fg = tint == null
        ? contrastingOnColor(color)
        : (enabled ? tint.side : tint.on.withValues(alpha: 0.65));
    return SizedBox(
      width: double.infinity,
      height: 56.h,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16.r),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16.r),
              // The inverted CTA is the brightest thing on a saturated
              // sheet, so it gets a soft cast shadow instead of the
              // coloured glow — that lifts it off green/red the way the
              // glow lifts it off a white sheet. Neutral sheets keep the
              // original behaviour.
              boxShadow: !enabled
                  ? null
                  : tint != null
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : isDark
                          ? null
                          : [
                              BoxShadow(
                                color: color.withValues(alpha: 0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
            ),
            alignment: Alignment.center,
            // Going busy (or back) cross-fades the label and the spinner;
            // a label that only changes its amount updates in place.
            child: ArrivalSwitcher(
              state: isBusy,
              alignment: Alignment.center,
              animateSize: false,
              child: isBusy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LoadingAnimationWidget.staggeredDotsWave(
                          color: fg,
                          size: 22.sp,
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          busyLabel ?? context.l10n.betPlacingOrderEllipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What went wrong, told on the ticket the person is still looking at.
///
/// Replaces the locked panel both tickets used to swap themselves for: the
/// form stays where it was, the figures stay readable, and the retry is
/// the ticket's own CTA rather than a second button on a second design.
/// [details] is the raw diagnostic, folded away until asked for.
class PolySlipNotice extends StatefulWidget {
  const PolySlipNotice({
    super.key,
    required this.title,
    required this.message,
    this.details,
  });

  final String title;
  final String message;
  final String? details;

  @override
  State<PolySlipNotice> createState() => _PolySlipNoticeState();
}

class _PolySlipNoticeState extends State<PolySlipNotice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = widget.details;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 20.sp, color: c.textPrimary),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary)),
                    SizedBox(height: 4.h),
                    Text(widget.message,
                        style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (details != null && details.isNotEmpty) ...[
            SizedBox(height: 8.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.details,
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                  Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18.sp,
                      color: c.textSecondary),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: SelectableText(details,
                    style: TextStyle(fontSize: 12.sp, color: c.textSecondary)),
              ),
              crossFadeState:
                  _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
            ),
          ],
        ],
      ),
    );
  }
}

/// House-style grouping box for an Advanced page: neutral surface, a 0.5
/// hairline, 16 radius, generous padding and one title with an optional
/// trailing line (the Amount section's available figure).
///
/// Both Advanced pages are built from these, so the buying and the
/// selling page cannot drift into two designs the way the two sheets
/// did once already.
class PolySlipSection extends StatelessWidget {
  const PolySlipSection({
    super.key,
    this.title,
    this.trailing,
    required this.children,
  });

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(title!,
                      style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary)),
                ),
                if (trailing != null) ...[
                  SizedBox(width: 12.w),
                  Flexible(child: trailing!),
                ],
              ],
            ),
            SizedBox(height: 14.h),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// One read-only line inside a [PolySlipSection] or a
/// [PolySlipDetailsGroup]: a label and the figure it describes.
class PolySlipDetailRow extends StatelessWidget {
  const PolySlipDetailRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14.sp, color: c.textSecondary))),
        SizedBox(width: 12.w),
        Text(value,
            style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: c.textPrimary)),
      ],
    );
  }
}

/// The rare stuff, folded away. Nothing in here changes the order; it
/// only describes it. [open] and [onToggle] keep the disclosure on the
/// page's own state so it survives a rebuild.
class PolySlipDetailsGroup extends StatelessWidget {
  const PolySlipDetailsGroup({
    super.key,
    required this.open,
    required this.onToggle,
    required this.rows,
  });

  final bool open;
  final VoidCallback onToggle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16.r),
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Row(children: [
                  Expanded(
                    child: Text(context.l10n.details,
                        style: TextStyle(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary)),
                  ),
                  Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 22.sp,
                      color: c.textSecondary),
                ]),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: rows,
              ),
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

/// The typed amount on an Advanced page. The page has room for a real
/// field, so the figure is editable in place rather than through the
/// sheet's pinned keypad.
class PolySlipAmountField extends StatelessWidget {
  const PolySlipAmountField({
    super.key,
    required this.controller,
    required this.prefix,
    this.readOnly = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String prefix;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      // The same fill as the sections around it. It used to be a second,
      // darker grey, so an Advanced page showed two card colours side by
      // side; what marks this one out as the input is its type size and
      // its rim, not a different surface. The rim is the full border
      // rather than the sections' hairline, because this one is the
      // thing you touch.
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(
        children: [
          Text(prefix,
              style: TextStyle(
                  fontSize: 30.sp,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: inputFormatters,
              cursorColor: c.accent,
              style: TextStyle(
                  fontSize: 34.sp,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame an Advanced page sits in: the app palette rather than the
/// sheet's tint, a back button and a centred title. The page hands it
/// the ticket; the keyboard inset and the bottom safe area are the
/// frame's job, so neither page has to remember them.
class PolySlipAdvancedScaffold extends StatelessWidget {
  const PolySlipAdvancedScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.body,
    this.canPop = true,
  });

  final String title;
  final VoidCallback onBack;
  final Widget body;
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: KuteBackButton(onPressed: () {
          if (canPop) onBack();
        }),
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ),
      body: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(top: false, child: body),
      ),
    );
  }
}
