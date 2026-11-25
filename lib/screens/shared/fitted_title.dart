// lib/screens/shared/fitted_title.dart
//
// A screen header's title that shrinks to fit instead of being cut: up to
// [FittedTitle.maxLines] lines at the style's size, and when the whole
// title would not fit in them, a smaller size, down to [minScale] of it
// (70% by default). Only a title still too long at that floor ends in an
// ellipsis. The floor is the size drawn on screen: under a larger text
// setting the title gives back that extra scale first, so it is never
// drawn under 70% of its size at the standard setting, and never cut
// while that keeps it whole.
//
// Measured with a TextPainter at the width the title is given, with the
// text scale, direction and locale the Text itself is drawn with, so it
// wraps across its lines exactly as measured (unlike a FittedBox, which
// would squeeze one line).

import 'package:flutter/material.dart';

/// The largest font size, from [style]'s own down to the floor, at which
/// [text] fits in [maxLines] lines of [maxWidth]; the floor when none
/// does (the title then ends in an ellipsis). The floor is [minScale] of
/// the style's size as drawn at the standard text setting: under a larger
/// [textScaler] the extra scale can be given back first. Steps of half a
/// point.
double fittedTitleFontSize({
  required String text,
  required TextStyle style,
  required double maxWidth,
  int maxLines = 2,
  double minScale = 0.7,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
  Locale? locale,
  StrutStyle? strutStyle,
  TextHeightBehavior? textHeightBehavior,
}) {
  final base = style.fontSize ?? 14.0;
  final scale = textScaler.scale(base) / base;
  final floor = base * minScale / (scale > 1 ? scale : 1);
  if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) return base;
  final painter = TextPainter(
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
    locale: locale,
    strutStyle: strutStyle,
    textHeightBehavior: textHeightBehavior,
  );
  try {
    bool fits(double size) {
      painter.text = TextSpan(text: text, style: style.copyWith(fontSize: size));
      painter.layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines;
    }

    for (var size = base; size > floor; size -= 0.5) {
      if (fits(size)) return size;
    }
    return floor;
  } finally {
    painter.dispose();
  }
}

/// Whether [text] fits whole in [maxLines] lines of [maxWidth] at [style]'s
/// own size (no shrinking, no ellipsis): what a header checks before it
/// gives part of the title's row to something else.
bool fittedTitleFitsWhole({
  required String text,
  required TextStyle style,
  required double maxWidth,
  int maxLines = 2,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
  Locale? locale,
  TextHeightBehavior? textHeightBehavior,
}) {
  if (!maxWidth.isFinite) return true;
  if (maxWidth <= 0) return text.isEmpty;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
    locale: locale,
    textHeightBehavior: textHeightBehavior,
  )..layout(maxWidth: maxWidth);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

/// A header title that keeps every word on screen: it wraps to [maxLines]
/// and, rather than cutting, shrinks to fit them down to [minScale] of
/// [style]'s size ([fittedTitleFontSize]).
class FittedTitle extends StatelessWidget {
  const FittedTitle(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
    this.minScale = 0.7,
    this.textAlign,
    this.longMaxLines,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double minScale;

  /// How the lines sit in the width (a team's name under its crest is
  /// centred); the ambient alignment when null.
  final TextAlign? textAlign;

  /// The lines a title still too long at the floor may take before it is
  /// cut (a fixture and its market at 320 pt under a large text size);
  /// [maxLines] stays the limit when null.
  final int? longMaxLines;

  @override
  Widget build(BuildContext context) {
    // The style the Text below is drawn with (the ambient one merged in),
    // so the measure and the drawing agree.
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final heightBehavior = DefaultTextHeightBehavior.maybeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = fittedTitleFontSize(
        text: text,
        style: effective,
        maxWidth: constraints.maxWidth,
        maxLines: maxLines,
        minScale: minScale,
        textScaler: textScaler,
        textDirection: direction,
        locale: locale,
        textHeightBehavior: heightBehavior,
      );
      var lines = maxLines;
      final long = longMaxLines;
      if (long != null &&
          long > maxLines &&
          !fittedTitleFitsWhole(
            text: text,
            style: effective.copyWith(fontSize: size),
            maxWidth: constraints.maxWidth,
            maxLines: maxLines,
            textScaler: textScaler,
            textDirection: direction,
            locale: locale,
            textHeightBehavior: heightBehavior,
          )) {
        lines = long;
      }
      return Text(
        text,
        maxLines: lines,
        textAlign: textAlign,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(fontSize: size),
      );
    });
  }
}
