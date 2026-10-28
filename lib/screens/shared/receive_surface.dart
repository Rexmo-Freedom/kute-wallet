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
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show AppBottomSheetContainer;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// How tall the receive sheet stands, as a share of the screen.
const double kReceiveSheetMaxHeight = 0.9;

/// The receive sheet's frame, the same for both receives: the app's sheet
/// container and drag handle, then the header row the full-screen
/// receives had in their app bar ([leading] on the left, [title] centred),
/// then the body filling the rest. Swipe down closes it like every sheet.
///
/// The sheet itself says "receive", so a receive passes no visible
/// [title] unless the slot carries something to act on (the bitcoin
/// receive's "Receive into" pill). Without one, [semanticTitle] still
/// names the sheet to a screen reader, as a header, from the same slot.
class ReceiveSheetFrame extends StatelessWidget {
  const ReceiveSheetFrame({
    super.key,
    required this.leading,
    this.title,
    this.semanticTitle,
    required this.child,
  });

  final Widget leading;
  final Widget? title;

  /// What a screen reader calls the sheet when [title] is null.
  final String? semanticTitle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: kReceiveSheetMaxHeight,
      // Pure white in light mode, the same white as the QR plate, so the
      // plate has no visible edge on the sheet (founder decision). Dark
      // mode keeps the theme's sheet surface.
      color: context.isDark ? null : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReceiveSheetHeader(
              leading: leading, title: title, semanticTitle: semanticTitle),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The receive sheets' header: the drag handle, then the row with
/// [leading] (the close X) on the left and [title] centred. Every receive
/// sheet wears it, so the X sits in the same top-left place on all of
/// them: [ReceiveSheetFrame] draws it, and the receive's content-sized
/// sheets (the return address, Request amount) put it over their own
/// heading. Without a [title], [semanticTitle] names the sheet to a
/// screen reader; with neither, the slot is empty room.
class ReceiveSheetHeader extends StatelessWidget {
  const ReceiveSheetHeader({
    super.key,
    required this.leading,
    this.title,
    this.semanticTitle,
  });

  final Widget leading;
  final Widget? title;
  final String? semanticTitle;

  @override
  Widget build(BuildContext context) {
    final visibleTitle = title;
    final label = semanticTitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: AppDecorations.dragHandle(context),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
          child: Row(
            children: [
              SizedBox(width: 44.w, child: Center(child: leading)),
              Expanded(
                child: visibleTitle != null
                    ? Center(child: visibleTitle)
                    : label != null
                        ? Semantics(
                            container: true,
                            header: true,
                            label: label,
                            child: SizedBox(height: 44.w),
                          )
                        : SizedBox(height: 44.w),
              ),
              SizedBox(width: 44.w),
            ],
          ),
        ),
      ],
    );
  }
}

/// The receive surface's vertical rhythm, so the two screens cannot
/// disagree about how far apart their own parts sit.
abstract final class ReceiveGaps {
  /// QR plate to the caption that explains why it is still loading.
  static double get qrToCaption => 12.h;

  /// QR plate to the address under it.
  static double get qrToAddress => 24.h;

  /// Address to the Share button.
  static double get addressToActions => 14.h;

  /// Between any two blocks below the actions.
  static double get block => 12.h;

  /// Breathing room under the last block inside the scroll view.
  static double get tail => 16.h;
}

/// The QR plate's side: as large as the receive sheet allows, 87% of
/// its width, never under 260 nor over 380 points. The sheet spans the
/// screen, so the screen's width is the sheet's. At 390pt that is about
/// 339pt, which still leaves the address and the Share button above
/// the fold on a 390x844 phone, and still fits inside both screens'
/// side padding.
double receiveQrSide(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.87).clamp(260.0, 380.0);

/// The white plate the QR sits on. A square [receiveQrSide] wide,
/// generous radius, and a small inner padding so the code dominates the
/// frame instead of floating in a bed of whitespace (the code keeps its
/// own quiet zone inside it). White is not a themed colour here on
/// purpose: a QR needs the contrast in both themes.
class ReceiveQrPlate extends StatelessWidget {
  const ReceiveQrPlate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final side = receiveQrSide(context);
    return Center(
      child: Container(
        width: side,
        height: side,
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
  const ReceiveCaption({
    super.key,
    required this.text,
    this.emphasised = false,
  });

  final String text;

  /// The one line that reads louder than the rest (a one-time address's
  /// countdown): the same size, a stronger colour and weight.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: emphasised ? c.textSecondary : c.textTertiary,
          fontSize: 13.sp,
          fontWeight: emphasised ? FontWeight.w700 : null,
          height: 1.4,
        ),
      ),
    );
  }
}

/// The smallest deposit the address above takes ("Minimum $1.00"), in
/// the caption style. Null [amount] renders nothing. A gap above it is
/// included so a screen adds the line in one place.
class ReceiveMinimumCaption extends StatelessWidget {
  const ReceiveMinimumCaption({super.key, required this.amount});

  /// The formatted minimum ("$1.00").
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final value = amount;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('receive-minimum'),
      padding: EdgeInsets.only(top: 8.h),
      child: ReceiveCaption(text: context.l10n.amountMinimumInline(value)),
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
            final iconsWidth =
                8.w + iconButtonSize + (showEdit ? 8.w + iconButtonSize : 0);
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

/// Share, full width, directly under the address. Copy lives on the
/// address line itself (the row and its copy button), so the row under
/// it is Share alone (founder decision October 2026: a second Copy was
/// redundant).
///
/// It sits in the page rather than pinned to the floor because it acts
/// on the thing above it: the exact payload the QR encodes. A pinned
/// button reads as "finish the flow", which is the wrong promise on a
/// screen where the job is done the moment the code is on screen.
///
/// Anything else the receive can do with that code (the bitcoin
/// screen's request amount) sits under it as a quiet text action, never
/// as a second button beside it.
class ReceiveActionPills extends StatelessWidget {
  const ReceiveActionPills({
    super.key,
    required this.onShare,
  });

  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onShare,
      text: context.l10n.share,
      icon: Icons.ios_share_rounded,
      compact: true,
      fontSize: 15.sp,
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
