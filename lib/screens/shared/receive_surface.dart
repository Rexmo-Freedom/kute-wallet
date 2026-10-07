// lib/screens/shared/receive_surface.dart
//
// THE RECEIVE SURFACE, WRITTEN ONCE.
//
// Two screens hand out an address: the bitcoin receive
// (`screens/receive/components/confirm_receive.dart`) and the dollar
// receive (`screens/usd/usd_receive_screen.dart`). They do the same job
// and they were built a year apart, so they had drifted into two
// different-looking answers to one question: a 280dp white QR plate on
// one and an unsized code on the other, a chromeless monospace address
// with its own copy button on one and a bordered plate with a plain
// glyph on the other, an action row under the address on one and a
// stacked pair pinned to the floor on the other.
//
// The bitcoin screen is the reference. Everything it does that the other
// one should do too lives here, as a widget rather than as a number
// copied across two files, because a shared number is the only thing
// that keeps two screens from drifting apart again.
//
// Presentation only. Nothing here knows about a rail, a provider or a
// balance: the screens resolve their own payloads and pass finished
// strings and callbacks in.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/fee_copy.dart' show feeRateText;
import 'package:kute/theme/app_theme.dart';

/// The receive surface's vertical rhythm, so the two screens cannot
/// disagree about how far apart their own parts sit.
abstract final class ReceiveGaps {
  /// QR plate to the caption that explains why it is still loading.
  static double get qrToCaption => 12.h;

  /// QR plate to the address under it.
  static double get qrToAddress => 24.h;

  /// Address to the Share/Copy row.
  static double get addressToActions => 14.h;

  /// Between any two blocks below the actions.
  static double get block => 12.h;

  /// Breathing room under the last block inside the scroll view.
  static double get tail => 16.h;
}

/// The white plate the QR sits on. Fixed square, generous radius, and a
/// small inner padding so the code dominates the frame instead of
/// floating in a bed of whitespace. White is not a themed colour here on
/// purpose: a QR needs the contrast in both themes.
class ReceiveQrPlate extends StatelessWidget {
  const ReceiveQrPlate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 280.w,
        height: 280.w,
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: child,
      ),
    );
  }
}

/// What fills the plate while the address is still being resolved. Put
/// it inside a [ReceiveQrPlate] so the page keeps its shape and nothing
/// jumps when the real code lands.
class ReceiveQrShimmer extends StatelessWidget {
  const ReceiveQrShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade600 : Colors.grey.shade100,
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
  }
}

/// The quiet line under the plate that says why it is still shimmering,
/// or what the code on it is for.
class ReceiveCaption extends StatelessWidget {
  const ReceiveCaption({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 13.sp,
          height: 1.4,
        ),
      ),
    );
  }
}

/// The one fee line beside a reusable deposit address: the Kute rate the
/// address's own terms charge, taken from what arrives. [bps] is the rate
/// the screen read from those terms; null (unknown or no fee) renders
/// nothing, never a guess. A gap above it is included so a screen adds
/// the line in one place.
class ReceiveKuteFeeCaption extends StatelessWidget {
  const ReceiveKuteFeeCaption({super.key, required this.bps});

  final int? bps;

  @override
  Widget build(BuildContext context) {
    final rate = bps;
    if (rate == null || rate <= 0) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: ReceiveGaps.block),
      child: ReceiveCaption(
          text: context.l10n.receiveKuteFeeOnArrival(feeRateText(rate))),
    );
  }
}

/// The address itself, under the QR.
///
/// No plate and no rail icon: the code above already says which rail
/// this is, and a border around the address only competed with it. A
/// long opaque string (on-chain, Spark, LNURL, an EVM deposit address)
/// is shown on ONE line with a middle ellipsis and its first and last
/// characters highlighted, which is what a person actually checks. A
/// human-readable address (`name@paykute.com`) is never abbreviated:
/// the whole point of it is that someone can read and type it, so it
/// renders whole and the font shrinks to fit.
///
/// The whole row copies on tap; the trailing button is the same action
/// made visible.
class ReceiveAddressLine extends StatelessWidget {
  const ReceiveAddressLine({
    super.key,
    required this.address,
    required this.onCopy,
    this.onEdit,
    this.compact = false,
  });

  /// The string on screen.
  final String address;

  /// Tapping the row, or its copy button.
  final VoidCallback onCopy;

  /// A pencil before the copy button. Only the Lightning address has
  /// anything to rename, so everything else leaves this null.
  final VoidCallback? onEdit;

  /// Smaller type and smaller buttons. Currently unused by either
  /// screen: both render the address at full size so it stays the
  /// second thing the eye lands on after the code.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bool isHumanReadable = address.contains('@');
    // Letters highlighted inside an email read like a render bug, so a
    // human-readable address keeps one colour.
    final highlightColor = isHumanReadable ? c.textPrimary : Colors.orange;
    final double fontSize = compact ? 14.sp : 17.sp;
    final double iconButtonSize = compact ? 28.sp : 36.sp;
    final double iconGlyphSize = compact ? 14.sp : 18.sp;
    final showEdit = onEdit != null;

    return GestureDetector(
      onTap: onCopy,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconsWidth = 8.w +
                iconButtonSize +
                (showEdit ? 8.w + iconButtonSize : 0);
            final availableWidth = constraints.maxWidth - iconsWidth;

            final style = TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: -0.2,
            );

            final Widget addressWidget;
            if (isHumanReadable) {
              addressWidget = FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  address,
                  maxLines: 1,
                  softWrap: false,
                  style: style.copyWith(color: c.textPrimary),
                ),
              );
            } else {
              const ellipsis = '...';
              final ellipsisWidth = _measureText(ellipsis, style);
              final charWidth = _measureText('a', style);
              // A 4-char safety margin. Sub-pixel layout plus monospace
              // kerning used to clip the last character of the suffix at
              // certain widths, and losing the checksum tail costs far
              // more than a couple of middle characters.
              final maxChars =
                  ((availableWidth - ellipsisWidth) / charWidth).floor() - 4;

              String displayText;
              int keepStart;
              int keepEnd;
              if (address.length <= maxChars + 3 || maxChars < 8) {
                displayText = address;
                keepStart = 0;
                keepEnd = 0;
              } else {
                keepStart = (maxChars * 0.55).floor();
                keepEnd = maxChars - keepStart;
                displayText =
                    '${address.substring(0, keepStart)}$ellipsis${address.substring(address.length - keepEnd)}';
              }

              final highlightChars = 5.clamp(0, address.length ~/ 3);
              List<TextSpan> spans = [];

              if (keepStart > 0 && keepEnd > 0) {
                final startHighlight = highlightChars.clamp(0, keepStart);
                spans.add(TextSpan(
                    text: displayText.substring(0, startHighlight),
                    style: TextStyle(color: highlightColor)));
                spans.add(TextSpan(
                    text: displayText.substring(startHighlight, keepStart),
                    style: TextStyle(color: c.textPrimary)));
                spans.add(TextSpan(
                    text: ellipsis, style: TextStyle(color: c.textTertiary)));
                final endPart =
                    displayText.substring(keepStart + ellipsis.length);
                final endHighlightStart =
                    endPart.length - highlightChars.clamp(0, endPart.length);
                spans.add(TextSpan(
                    text: endPart.substring(0, endHighlightStart),
                    style: TextStyle(color: c.textPrimary)));
                spans.add(TextSpan(
                    text: endPart.substring(endHighlightStart),
                    style: TextStyle(color: highlightColor)));
              } else {
                final startH = highlightChars.clamp(0, displayText.length);
                final endH = highlightChars.clamp(0, displayText.length);
                if (displayText.length > startH + endH) {
                  spans.add(TextSpan(
                      text: displayText.substring(0, startH),
                      style: TextStyle(color: highlightColor)));
                  spans.add(TextSpan(
                      text: displayText.substring(
                          startH, displayText.length - endH),
                      style: TextStyle(color: c.textPrimary)));
                  spans.add(TextSpan(
                      text: displayText.substring(displayText.length - endH),
                      style: TextStyle(color: highlightColor)));
                } else {
                  spans.add(TextSpan(
                      text: displayText,
                      style: TextStyle(color: c.textPrimary)));
                }
              }

              addressWidget = RichText(
                text: TextSpan(style: style, children: spans),
                maxLines: 1,
                overflow: TextOverflow.clip,
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: addressWidget),
                if (showEdit) ...[
                  SizedBox(width: 10.w),
                  ReceiveAddressIconButton(
                    icon: Icons.edit_rounded,
                    size: iconButtonSize,
                    glyphSize: iconGlyphSize,
                    onTap: onEdit!,
                  ),
                ],
                SizedBox(width: 8.w),
                ReceiveAddressIconButton(
                  icon: Icons.copy_rounded,
                  size: iconButtonSize,
                  glyphSize: iconGlyphSize,
                  onTap: onCopy,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A square tap target beside the address. Neutral fill, no tint.
class ReceiveAddressIconButton extends StatelessWidget {
  const ReceiveAddressIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size,
    this.glyphSize,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double? size;
  final double? glyphSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final btnSize = size ?? 36.sp;
    final iconSize = glyphSize ?? 18.sp;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: btnSize,
        height: btnSize,
        decoration: BoxDecoration(
          color: c.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, size: iconSize, color: c.textPrimary),
      ),
    );
  }
}

/// Share and Copy, side by side, directly under the address.
///
/// They sit in the page rather than pinned to the floor because they
/// act on the thing above them: the exact payload the QR encodes. A
/// pinned pair reads as "finish the flow", which is the wrong promise
/// on a screen where the job is done the moment the code is on screen.
///
/// [trailing] takes a third pill (the bitcoin screen's request-amount
/// control). With one present the row is tight, so the labels lose
/// their icons and drop a point.
class ReceiveActionPills extends StatelessWidget {
  const ReceiveActionPills({
    super.key,
    required this.onShare,
    required this.onCopy,
    this.trailing,
  });

  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final extra = trailing;
    final dense = extra != null;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: AppButton(
            onPressed: onShare,
            text: context.l10n.share,
            icon: dense ? null : Icons.ios_share_rounded,
            compact: true,
            fontSize: dense ? 14.sp : 15.sp,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          flex: 3,
          child: AppButton(
            onPressed: onCopy,
            text: context.l10n.copy,
            icon: dense ? null : Icons.copy_rounded,
            variant: AppButtonVariant.secondary,
            compact: true,
            fontSize: dense ? 14.sp : 15.sp,
          ),
        ),
        if (extra != null) ...[
          SizedBox(width: 8.w),
          Expanded(flex: 4, child: extra),
        ],
      ],
    );
  }
}

double _measureText(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
