import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/theme/app_theme.dart';

// A Sports row's icon (founder, 9 November 2026: "actually use the svgs from
// polymarket here"), wherever the rows appear: the category sheet's Sports
// grid and league level, the drill pills, the search's category row. In
// order: Polymarket's own coloured glyph for the sport or league, bundled
// (lib/assets/polymarket_tags/README.md); else the league's Gamma `image`;
// else, or when that image fails, the Sports trophy. Always exactly [size]
// square, loaded or not, so nothing moves while an image lands.

const String _kDir = 'lib/assets/polymarket_tags/sports';

/// What `lib/assets/polymarket_tags/sports/` holds: Live, Futures, every
/// sport of [kPolySportGroups], and the pinned leagues with a vector of the
/// mark the site draws (by Gamma `/sports` code).
const Set<String> kPolySportIconKeys = {
  'live',
  'futures',
  ...kPolySportGroups,
  'nfl',
  'ufc',
  'ucl',
};

/// The glyphs whose colour differs in dark mode, as the site's does.
const Set<String> _kDarkVariants = {
  'tennis',
  'cricket',
  'football',
  'hockey',
  'table-tennis',
  'darts',
  'baseball',
  'handball',
  'motorsports',
  'cycling',
  'chess',
};

/// The bundled glyph of [sub], by its key (a sport, Live, Futures) or its
/// route (a league's Gamma code; its key is `series:<id>`). Null when none
/// is bundled.
String? polySportIconAsset(PolySub sub, {bool dark = false}) {
  final key = kPolySportIconKeys.contains(sub.key)
      ? sub.key
      : kPolySportIconKeys.contains(sub.route)
          ? sub.route
          : null;
  if (key == null) return null;
  return '$_kDir/$key${dark && _kDarkVariants.contains(key) ? '.dark' : ''}.svg';
}

class PolySportIcon extends StatelessWidget {
  final PolySub sub;
  final double size;

  const PolySportIcon({super.key, required this.sub, required this.size});

  @override
  Widget build(BuildContext context) {
    final trophy = PolySportTrophy(size: size);
    final asset = polySportIconAsset(sub, dark: context.isDark);
    if (asset != null) {
      // By width alone inside the square: a wide mark (the UFC's wordmark)
      // would otherwise take its height and run out of the plate.
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: size,
            // Futures is the one glyph in the text's colour, as on the site.
            theme: SvgTheme(currentColor: context.colors.textPrimary),
            placeholderBuilder: (_) => SizedBox.square(dimension: size),
            errorBuilder: (_, __, ___) => trophy,
          ),
        ),
      );
    }
    final url = sub.imageUrl;
    if (url == null || url.isEmpty) return trophy;
    return PolyCrestImage(
      url: url,
      size: size,
      radius: 3,
      fit: BoxFit.contain,
      fallback: trophy,
    );
  }
}

/// The Sports topic's monochrome trophy: a row with nothing better.
class PolySportTrophy extends StatelessWidget {
  final double size;

  const PolySportTrophy({super.key, required this.size});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'lib/assets/polymarket_tags/sports.svg',
        width: size,
        height: size,
        colorFilter:
            ColorFilter.mode(context.colors.textPrimary, BlendMode.srcIn),
      );
}
