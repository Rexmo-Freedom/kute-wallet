// lib/screens/polymarket/components/outcome_leading.dart
//
// What leads an outcome row in a market's list of outcomes: the outcome's
// own image when it has one, and otherwise no thumbnail, only a small dot
// in the colour of the outcome's line on the chart (nothing when the
// chart draws no line for it). Rows of one list keep one leading width,
// so names line up whether or not a row has an image.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/services/polymarket/market_card_shape.dart'
    show polyRealOutcomes;
import 'package:kute/theme/app_theme.dart';

/// How many outcomes a many-outcome chart draws a line for.
const int kPolyChartMaxLines = 6;

/// The colours of a many-outcome chart's lines and of their rows' dots,
/// most likely outcome first. Any two of the first eight are far apart
/// (a CIELAB distance of 30 or more, tested): the sixth used to be a
/// second light blue, a shade from the first, so with six lines on the
/// chart two could not be told apart. The sixth and the eighth are the
/// app's own info blue and its deep orange. Never the green and red of up
/// and down. A game's teams have their own (kGameSideColors).
const List<Color> kPolyOutcomeColors = [
  Color(0xFF4FC3F7), // sky blue
  Color(0xFFCE93D8), // purple
  Color(0xFFFFB74D), // orange
  Color(0xFF81C784), // green
  Color(0xFFE57373), // red
  Color(0xFF007AFF), // AppColors.info
  Color(0xFF4DB6AC), // teal
  Color(0xFFFF6B00), // AppColors.seedsigner
  Color(0xFFB388FF), // AppColors.krux
  Color(0xFFFF8A65), // coral
];

/// The colour of one side of an Up or Down market (a crypto price over
/// fifteen minutes, an hour, a day): the app's up colour for Up and its
/// down colour for Down, as the five-minute round's own sheet draws them,
/// on the chart's line and tag, the row and the headline. Null for any
/// other market, whose outcomes take the palette: [outcomes] must be
/// exactly the two sides.
Color? polyUpDownColor(String name, List<PolymarketOutcome> outcomes) {
  if (outcomes.length != 2) return null;
  final names = {for (final o in outcomes) o.name.trim().toLowerCase()};
  if (names.length != 2 || !names.contains('up') || !names.contains('down')) {
    return null;
  }
  return switch (name.trim().toLowerCase()) {
    'up' => AppColors.marketUp,
    'down' => AppColors.marketDown,
    _ => null,
  };
}

/// The contrast of white text on [fill] (WCAG 2: 1 to 21).
double polyWhiteContrast(Color fill) => 1.05 / (fill.computeLuminance() + 0.05);

final Map<int, Color> _fills = {};

/// The solid fill of an outcome's button and of the bet slip opened on it,
/// for an outcome whose chart line is [line]: the line's own hue and
/// saturation, its lightness lowered only as far as white text on it needs
/// to read at 4.5:1. The palette's light tones (sky blue, orange) come out
/// a deeper blue and amber, still that line's colour; a line already dark
/// enough is its own fill. The same in light and dark mode: the text on
/// it is always white.
Color polyOutcomeFill(Color line) => _fills.putIfAbsent(line.toARGB32(), () {
      if (polyWhiteContrast(line) >= 4.5) return line;
      final hsl = HSLColor.fromColor(line);
      var l = hsl.lightness;
      var fill = line;
      while (l > 0 && polyWhiteContrast(fill) < 4.5) {
        l = (l - 0.005).clamp(0.0, 1.0);
        fill = hsl.withLightness(l).toColor();
      }
      return fill;
    });

/// The outcomes a many-outcome chart draws, most likely first, each with
/// its line's colour: the first [max] that have a token take [palette] in
/// order (an Up or Down market's two sides the up and down colours,
/// [polyUpDownColor]). The chart and the list of outcomes both read this, so a row's
/// dot is always its own line's colour.
List<({PolymarketOutcome outcome, Color color})> polyChartedOutcomes(
  List<PolymarketOutcome> outcomes,
  List<Color> palette, {
  int max = kPolyChartMaxLines,
}) {
  // Never a filler with no market behind it while real outcomes exist.
  final sorted = [...polyRealOutcomes(outcomes)]
    ..sort((a, b) => b.price.compareTo(a.price));
  final out = <({PolymarketOutcome outcome, Color color})>[];
  for (final o in sorted) {
    if (out.length >= max) break;
    final token = o.tokenId;
    if (token == null || token.isEmpty) continue;
    out.add((
      outcome: o,
      color: polyUpDownColor(o.name, outcomes) ??
          palette[out.length % palette.length],
    ));
  }
  return out;
}

class PolyOutcomeLeading extends StatelessWidget {
  /// The outcome's own image (Gamma `groupItemImage`: a flag, a crest, a
  /// portrait); null or empty when it has none.
  final String? imageUrl;

  /// The colour of this outcome's line on the chart; null when the chart
  /// draws no line for it.
  final Color? lineColor;

  /// Whether any row of the list has an image: the rows without one then
  /// keep the image's width, with the dot in its middle.
  final bool listHasImages;

  const PolyOutcomeLeading({
    super.key,
    required this.imageUrl,
    required this.lineColor,
    required this.listHasImages,
  });

  static bool hasImage(String? url) => url != null && url.trim().isNotEmpty;

  /// Whether the rows of a list lead with anything at all. A list with no
  /// image and no charted outcome is text only, flush left.
  static bool listLeads({required bool anyImage, required bool anyLine}) =>
      anyImage || anyLine;

  /// The width every row's leading takes: the image's when the list has
  /// images, the dot's otherwise.
  static double slotWidth({required bool listHasImages}) =>
      listHasImages ? 28.sp : 8.w;

  @override
  Widget build(BuildContext context) {
    final color = lineColor;
    final dot = color == null
        ? null
        : Container(
            key: const ValueKey('outcome-line-dot'),
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          );
    final size = slotWidth(listHasImages: listHasImages);
    final plain = SizedBox(
      width: size,
      height: size,
      child: dot == null ? null : Center(child: dot),
    );
    if (!listHasImages || !hasImage(imageUrl)) return plain;
    // SVG-aware (logos and flags come as `.svg` too). An image that fails
    // to load reads like a row that has none.
    return PolyCrestImage(
      url: imageUrl!,
      size: size,
      radius: 8.r,
      fallback: plain,
    );
  }
}
