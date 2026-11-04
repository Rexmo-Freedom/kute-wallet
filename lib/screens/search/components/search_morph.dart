// lib/screens/search/components/search_morph.dart
//
// THE PILL BECOMES THE COMPOSER (founder, 31 October 2026): tapping the
// floating Sal pill (kute_shell_bar.dart) does not open a sheet with a
// field in it; the pill itself travels. Its rect tweens (position, width,
// corner) to the composer LINE at the TOP of the sheet, under the drag
// handle, on the sheet spring ([KuteMotion.sheetIn], the same curve the
// sheet rises on behind it); the pill's fill, hairline and shadow fade to
// the line's bare hairline underneath, Sal shrinks from the pill's 38 to
// the line's 32, the pill's label settles into the hint. Closing runs it
// back on the settle easing ([KuteMotion.sheetOut]) as the sheet drops.
//
// Built as an OVERLAY RECT TWEEN, not a Hero: a modal bottom sheet is a
// PopupRoute, and Flutter's HeroController only flies between PageRoutes.
// One [OverlayEntry] on the root navigator's overlay draws the travelling
// pill above the sheet and its barrier ([_MorphBox], pointer-transparent);
// the real pill and the real composer are transparent while it runs
// ([kuteSearchMorphing]; the bar reads it, the composer reads it), so
// there is one object on screen at any moment. The composer's rest rect
// is known before the sheet has laid out ([composerRestRect]: the sheet's
// top at its 96% (or the status bar), the handle row under it, the line's
// gutters and height), so the travel starts on the same frame as the
// sheet. Closing measures both ends: the composer where it is and the
// pill where it rests.
//
// Reduce Motion never gets here: the bar opens a plain sheet.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_rows.dart'
    show kSearchSheetFraction, kSearchSheetHandleRow;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/theme/kute_overlay_surface.dart';

/// True while the pill is travelling (either way). The shell bar's pill
/// and the sheet's composer draw transparent while it is.
final ValueNotifier<bool> kuteSearchMorphing = ValueNotifier<bool>(false);

/// Where the pill starts: its rect in the root overlay's coordinates, the
/// label it wears, and a way to read its rect again when the sheet closes
/// (the pill may have moved; null falls back to [rect]).
class KuteSearchMorphSource {
  const KuteSearchMorphSource({
    required this.rect,
    required this.label,
    this.rectNow,
  });

  final Rect rect;
  final String label;
  final Rect? Function()? rectNow;
}

abstract final class KuteSearchMorph {
  static OverlayEntry? _entry;
  static Completer<void>? _done;

  /// The composer line's rect once the sheet has settled, before it
  /// exists: the sheet stands at [kSearchSheetFraction] of the screen (or
  /// under the status bar when that is lower; the sheet opens with
  /// useSafeArea), the handle row is its first row and the line the
  /// second, inset by the composer's gutters.
  static Rect composerRestRect(BuildContext overlayContext) {
    final box = overlayContext.findRenderObject() as RenderBox?;
    final size =
        box?.hasSize == true ? box!.size : MediaQuery.sizeOf(overlayContext);
    final topInset = MediaQuery.paddingOf(overlayContext).top;
    final gutter = KuteSearchComposer.gutter(overlayContext);
    final sheetTop =
        math.max(size.height * (1 - kSearchSheetFraction), topInset);
    final top = sheetTop + kSearchSheetHandleRow.h;
    return Rect.fromLTRB(
        gutter, top, size.width - gutter, top + KuteSearchComposer.height);
  }

  /// [box]'s rect in [overlay]'s coordinates (null when either is not
  /// laid out).
  static Rect? rectOf(RenderObject? box, OverlayState overlay) {
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final ancestor = overlay.context.findRenderObject();
    if (ancestor is! RenderBox) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: ancestor);
    return origin & box.size;
  }

  /// Runs the travel from [from] to [to] over [overlay]; completes when it
  /// has landed. [opening] picks the sheet spring in, the settle out. A
  /// travel still running is cut: the new one starts where it stands.
  static Future<void> run(
    OverlayState overlay, {
    required Rect from,
    required Rect to,
    required bool opening,
    required String label,
    required String hint,
  }) {
    cancel();
    final done = Completer<void>();
    _done = done;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _MorphBox(
        from: from,
        to: to,
        opening: opening,
        label: label,
        hint: hint,
        onDone: () {
          if (_entry == entry) {
            _entry = null;
            _done = null;
          }
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    return done.future;
  }

  /// Removes a travelling pill mid-way (the sheet closed before it
  /// landed); its future completes.
  static void cancel() {
    final entry = _entry;
    final done = _done;
    _entry = null;
    _done = null;
    if (entry != null && entry.mounted) entry.remove();
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Whether a travel is on screen (tests).
  static bool get running => _entry != null;
}

/// The travelling pill: the rect, the surface (the pill's fill and
/// hairline fading to the line's), Sal's size, the inset before him and
/// the label's style all read off one curved [AnimationController].
class _MorphBox extends StatefulWidget {
  const _MorphBox({
    required this.from,
    required this.to,
    required this.opening,
    required this.label,
    required this.hint,
    required this.onDone,
  });

  final Rect from;
  final Rect to;
  final bool opening;
  final String label;
  final String hint;
  final VoidCallback onDone;

  @override
  State<_MorphBox> createState() => _MorphBoxState();
}

class _MorphBoxState extends State<_MorphBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.opening
        ? KuteMotion.sheetInDuration
        : KuteMotion.sheetOutDuration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: widget.opening ? KuteMotion.sheetIn : KuteMotion.sheetOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Pill-end values (kute_bottom_action_bar.dart, KuteSalPill) and
    // composer-end values (search_composer.dart). "Pill" is the start when
    // opening and the end when closing.
    const pillRadius = 28.0; // _kDockPillTallHeight / 2
    const pillSprite = 38.0;
    final pillLead = 8.w;
    final pillLabel = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
    const composerSprite = KuteSearchComposer.spriteSize;
    final composerLead = KuteSearchComposer.leading(context);
    // The hint at the size the composer will draw it (shrunk to its line
    // when it is long), so the travel lands on exactly the composer's words.
    final composerRect = widget.opening ? widget.to : widget.from;
    final hintStyle = KuteSearchComposer.fittedHintStyle(
        context,
        widget.hint,
        KuteSearchComposer.hintWidth(context, composerRect.width));
    // The line's end: no fill, no corner, no shadow, a uniform hairline
    // gone to nothing (a rounded box cannot wear a one-sided border, so
    // the line's own hairline underneath is drawn apart and fades in).
    final lineDecoration = BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.transparent, width: 0),
    );
    final hairlineColor = c.border;
    const hairline = KuteSearchComposer.hairline;
    // The pill's surface (kute_bottom_action_bar.dart): white over a
    // hairline with a soft shadow in light, one step up in dark.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pillDecoration = BoxDecoration(
      color: isLight ? Colors.white : c.surface,
      borderRadius: BorderRadius.circular(pillRadius),
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
    final opening = widget.opening;
    final rectTween = RectTween(begin: widget.from, end: widget.to);
    // The row inside is laid out at the wider end's width throughout and
    // clipped by the box, so a narrow start (the folded pill, the header
    // circle) never squeezes it.
    final wide = math.max(widget.from.width, widget.to.width);
    // On the root overlay, outside every page's Material: the theme's
    // text, never the error style's double underline (kute_overlay_surface.dart).
    return KuteOverlaySurface(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            // How far towards the composer's look (1 = composer), so the
            // same lerps serve both directions.
            final k = (opening ? t : 1 - t).clamp(0.0, 1.0);
            final rect = rectTween.evaluate(_t) ?? widget.to;
            // The pill's surface becomes the line's: the fill, the corner
            // and the shadow go, the hairline settles under the line.
            final decoration =
                BoxDecoration.lerp(pillDecoration, lineDecoration, k) ??
                    lineDecoration;
            // Sal never taller than the box leaves him (a 40 circle holds
            // him at 30), centred in it.
            final sprite = math.min(lerpDouble(pillSprite, composerSprite, k)!,
                math.max(0.0, rect.height - 10));
            final lead = math.min(lerpDouble(pillLead, composerLead, k)!,
                math.max(0.0, (rect.height - sprite) / 2));
            // The pill's text fades through the first half, the hint rises
            // through the second, so the two never lie over each other.
            final labelOpacity = (1 - k * 2).clamp(0.0, 1.0);
            final hintOpacity = (k * 2 - 1).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Container(
                    decoration: decoration,
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Opacity(
                            opacity: k,
                            child: Container(
                                height: hairline, color: hairlineColor),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.only(left: lead),
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: wide,
                              maxWidth: wide,
                              child: Row(
                                children: [
                                  SalSprite(
                                    clip: 'search',
                                    size: sprite,
                                    fallback: SvgPicture.asset(
                                        kuteDogAsset(context),
                                        width: sprite,
                                        height: sprite),
                                  ),
                                  SizedBox(
                                      width: lerpDouble(6.w,
                                          KuteSearchComposer.gap(context), k)),
                                  Expanded(
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        if (labelOpacity > 0)
                                          Opacity(
                                            opacity: labelOpacity,
                                            child: Text(
                                              widget.label,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.fade,
                                              style: pillLabel,
                                            ),
                                          ),
                                        if (hintOpacity > 0)
                                          Opacity(
                                            opacity: hintOpacity,
                                            child: Text(
                                              widget.hint,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.visible,
                                              style: hintStyle,
                                            ),
                                          ),
                                      ],
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
