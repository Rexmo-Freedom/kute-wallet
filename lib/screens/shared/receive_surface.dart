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
// stacked pair pinned to the floor on the other. Their Share is the bar now
// (KuteBarContext.primary, founder, 8 November 2026): each screen says what the
// bar reads in each of its states, so no button lives here.
//
// The bitcoin screen is the reference. Everything it does that the other
// one should do too lives here, as a widget rather than as a number
// copied across two files, because a shared number is the only thing
// that keeps two screens from drifting apart again.
//
// The one-time receive of another coin (`screens/receive/
// quoted_receive_screen.dart`) wears the plate and the address line too,
// and fits its plate to the room left ([ReceiveQrPlate.side]).
//
// Presentation only. Nothing here knows about a rail, a provider or a
// balance: the screens resolve their own payloads and pass finished
// strings and callbacks in.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show
        AppBottomSheetCloseButton,
        AppBottomSheetContainer,
        AppBottomSheetHeader;
import 'package:kute/screens/shared/kute_back_button.dart'
    show kKuteNavHitSize, kuteNavTitleLift;
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
///
/// [fitContent] sizes the sheet to its content instead (still capped at
/// the same height): a body of a few choices, the Dollars Add's two cards
/// (founder, 5 November 2026: a tall sheet with "a big empty area"). Being
/// short, such a sheet hides the floating bar while it is up (the
/// container's short-sheet rule, KuteSheetBarFit). Its [child] must size
/// itself (no Expanded inside).
class ReceiveSheetFrame extends StatelessWidget {
  const ReceiveSheetFrame({
    super.key,
    required Widget this.leading,
    this.title,
    this.semanticTitle,
    this.fitContent = false,
    required this.child,
  })  : heading = null,
        onClose = null;

  /// A sheet's FIRST step (the Bitcoin and Dollars Receives, the Dollars
  /// Send's Who step): the [SheetTitleHeader], [heading] big on the left
  /// and the compact close X at the top right ([onClose]), in place of the
  /// row with the X on the left. Its [child] starts [sheetStepContentTop]
  /// under it.
  const ReceiveSheetFrame.titled({
    super.key,
    required String this.heading,
    required VoidCallback this.onClose,
    this.fitContent = false,
    required this.child,
  })  : leading = null,
        title = null,
        semanticTitle = null;

  final Widget? leading;
  final Widget? title;

  /// What a screen reader calls the sheet when [title] is null.
  final String? semanticTitle;

  /// The first step's big title ([ReceiveSheetFrame.titled]).
  final String? heading;

  /// The first step's close ([ReceiveSheetFrame.titled]).
  final VoidCallback? onClose;

  /// As tall as the content rather than the full receive height.
  final bool fitContent;

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
        mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null)
            SheetTitleHeader(title: heading!, onClose: onClose!)
          else
            ReceiveSheetHeader(
                leading: leading!, title: title, semanticTitle: semanticTitle),
          if (fitContent) Flexible(child: child) else Expanded(child: child),
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

/// The diameter of the first steps' compact close X ([SheetTitleHeader]),
/// in design units: smaller than the canonical 40 circle, as an iOS sheet's
/// close is, its touch target still 44.
const double kSheetTitleCloseSize = 32;

/// Where a first step's content starts under its [SheetTitleHeader]: the
/// send steps' own start under their header (SendStepPage,
/// send_flow_widgets.dart: 4 and its one-pixel heading line), so the Bitcoin
/// Send, whose Who step is a page of its stepper, and the sheets whose first
/// step is the whole sheet start their content at the same height.
double get sheetStepContentTop => 4.h + 1;

/// THE FIRST STEP'S HEADER (founder, 7 November 2026, twice, of the Send
/// and Receive sheets' headers, a big round X on the left over a small
/// centred "Send": "here the send buttons and such as i said it is strange
/// the size"). The first step of both Sends (the Who step) and of both
/// Receives wears the What sheet's own heading (AppBottomSheetHeader,
/// send_what_step.dart): the drag handle, the title big on the left (28,
/// w800), and the close X at its top right, iOS-sheet style: the app's
/// round X ([AppBottomSheetCloseButton]) at the compact
/// [kSheetTitleCloseSize], its circle's right edge on the content's right
/// edge, centred on the title's first line; then the content,
/// [sheetStepContentTop] under it. [handleAbove]: the sheet's frame drew
/// the handle (the send sheet, send_sheet.dart), in the same place.
///
/// [SheetTitleHeader.inner] is an inner step of the same sheet (the
/// Bitcoin Send's Amount and Review): the inner steps' own header, [leading]
/// (the back chevron, or the X where that step opened the send) at the
/// left and [innerTitle] centred, laid on the line the big title sits on,
/// in a header exactly as tall, so nothing under it moves between steps.
class SheetTitleHeader extends StatelessWidget {
  const SheetTitleHeader({
    super.key,
    required this.title,
    required VoidCallback this.onClose,
    this.handleAbove = false,
  })  : leading = null,
        innerTitle = null;

  const SheetTitleHeader.inner({
    super.key,
    required this.title,
    required Widget this.leading,
    required Widget this.innerTitle,
    this.handleAbove = false,
  }) : onClose = null;

  /// The first step's title; on an inner step, what sizes the header.
  final String title;
  final VoidCallback? onClose;
  final bool handleAbove;
  final Widget? leading;
  final Widget? innerTitle;

  /// The key of the compact close X.
  static const Key closeKey = ValueKey('sheet-title-close');

  /// How far the close's box sits under where the heading puts it: the
  /// heading centres a 44 point target on the title's first line, and the
  /// box is 44 design units, smaller on a narrow phone; half the difference
  /// centres it exactly.
  static double _boxDrop() => (kKuteNavHitSize - kKuteNavHitSize.w) / 2;

  Widget _heading(BuildContext context, {required bool inner}) {
    // The X's 44 box is wider than its circle: shifted by the difference so
    // the circle's right edge meets the content's right edge, and centred
    // on the title's first line.
    final inset = (kKuteNavHitSize - kSheetTitleCloseSize).w / 2;
    return AppBottomSheetHeader(
      title: title,
      showDragHandle: !handleAbove,
      handleAbove: handleAbove,
      titleIsHeader: !inner,
      trailing: Transform.translate(
        offset: Offset(inset, _boxDrop()),
        child: AppBottomSheetCloseButton(
          key: inner ? null : closeKey,
          size: kSheetTitleCloseSize,
          onPressed: onClose ?? () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = leading;
    if (lead == null) return _heading(context, inner: false);
    // The row AppBottomSheetHeader lays its close in: the handle's room
    // (when it draws one), then its title's top less the lift that centres
    // a 44 target on the title's first line, centred as the close is.
    final top = 20.h;
    final lift = math.min(top, kuteNavTitleLift(context, 28.sp, height: 1.05));
    final handle = handleAbove ? 0.0 : 12.h + 4.h;
    return Stack(
      children: [
        // The first step's header, unseen: the room this one takes.
        ExcludeSemantics(
          child: Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _heading(context, inner: true),
          ),
        ),
        Positioned(
          left: 12.w,
          right: 12.w,
          top: handle + top - lift + _boxDrop(),
          height: kKuteNavHitSize.w,
          child: Row(
            children: [
              SizedBox(width: 44.w, child: Center(child: lead)),
              Expanded(child: Center(child: innerTitle)),
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

  /// Address to what stands under it.
  static double get addressToActions => 14.h;

  /// Between any two blocks below the actions.
  static double get block => 12.h;

  /// Breathing room under the last block inside the scroll view.
  static double get tail => 16.h;
}

/// The QR plate's side: as large as the receive sheet allows, 87% of
/// its width, never under 260 nor over 380 points. The sheet spans the
/// screen, so the screen's width is the sheet's. At 390pt that is about
/// 339pt, which still leaves the address above the fold on a 390x844
/// phone, and still fits inside both screens' side padding.
double receiveQrSide(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.87).clamp(260.0, 380.0);

/// The least a plate fitted to its page shrinks to ([ReceiveQrPlate.side]).
/// An address's code is about 33 modules a side, so even here each module
/// is about 4 points across, well inside what a phone camera reads.
const double kReceiveQrMinSide = 176;

/// The white plate the QR sits on. A square [receiveQrSide] wide (or
/// [side], for a page that fits it to the room left), generous radius, and
/// a small inner padding so the code dominates the frame instead of
/// floating in a bed of whitespace (the code keeps its own quiet zone
/// inside it). White is not a themed colour here on purpose: a QR needs
/// the contrast in both themes.
class ReceiveQrPlate extends StatelessWidget {
  const ReceiveQrPlate({super.key, this.side, required this.child});

  final double? side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final side = this.side ?? receiveQrSide(context);
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

double _measureText(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
