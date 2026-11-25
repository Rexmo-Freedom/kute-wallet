// lib/screens/usd/dollars_desk_nav_icons.dart
//
// THE LEFT NAVIGATION'S ICONS (founder, 25 November 2026, of the
// sidebar's Sports list: "also why no icons here?"). Every item of the
// laptop's left navigation (dollars_desk_nav.dart) leads with one, as
// Polymarket's and Robinhood's left navigation do; the phone's and the
// narrower laptop's chips stay words alone.
//
//   * The sections: the venues' own marks, as the Portfolio's "By
//     product" rows draw them (Hyperliquid for Investing, Polymarket for
//     Predictions); the Overview a neutral dashboard glyph.
//   * The categories: one quiet monochrome glyph each, drawn in the
//     item's own words' colour (tertiary at rest, primary picked):
//     Polymarket's own glyphs for its topics (lib/assets/polymarket_tags,
//     the ones the category sheet's cards wear), the same Trending and
//     Watchlist glyphs on Investing, Material's line icons for the rest.
//     All of them in one table, [kDeskNavMarks], keyed by the category's
//     stable id (never its translated label), with [kDeskNavDefaultMark].
//   * A Predictions subcategory or theme with art of its own (a sport's or
//     an esport's coloured glyph, a league's logo, a theme's image) draws
//     it as the category sheet does (poly_sport_icon.dart), the image as a
//     small rounded tile; while it loads, or when there is none, the
//     row's first letter on a quiet tile.
//
// Every icon sits in one [kDeskNavIconSlot] column, so the words of one
// list line up whatever the icon.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/polymarket_artwork.dart';
import 'package:kute/platform/web_image.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/theme/app_theme.dart';

/// The column every item's icon sits in.
const double kDeskNavIconSlot = 20;

/// A monochrome glyph's size inside [kDeskNavIconSlot].
const double kDeskNavGlyph = 18;

/// Between the icon's column and the words.
const double kDeskNavIconGap = 10;

const String _kTags = 'lib/assets/polymarket_tags';

/// The sports' and esports' glyphs drawn in the words' colour (the site
/// draws them in `currentColor`); every other one keeps its colours.
const Set<String> _kMonochromeArt = {
  '$_kTags/sports/futures.svg',
  '$_kTags/esports/call-of-duty.svg',
};

/// One item's mark: a Material glyph, a monochrome SVG (painted in the
/// words' colour) or a venue's coloured mark.
class DeskNavMark {
  const DeskNavMark.icon(IconData this.icon)
      : asset = null,
        coloured = false;
  const DeskNavMark.glyph(String this.asset)
      : icon = null,
        coloured = false;
  const DeskNavMark.venue(String this.asset)
      : icon = null,
        coloured = true;

  final IconData? icon;
  final String? asset;
  final bool coloured;
}

/// THE TABLE: every item's mark by its stable id (see the file header):
/// `section:<tab>`, `hl:<tab>` and `hl:sub:<sub>` (Investing's categories
/// and their subcategories), `poly:<pill>` (Predictions' topics) and
/// `poly:sub:all` (a topic's "All …").
const Map<String, DeskNavMark> kDeskNavMarks = {
  // The sections.
  'section:activity': DeskNavMark.icon(Icons.space_dashboard_outlined),
  'section:investing': DeskNavMark.venue('lib/assets/hyperliquid-logo.svg'),
  'section:predictions': DeskNavMark.venue('lib/assets/polymarket-logo.svg'),
  // Investing.
  'hl:trending': DeskNavMark.glyph('$_kTags/trending.svg'),
  'hl:watchlist': DeskNavMark.glyph('$_kTags/watchlist.svg'),
  'hl:watchlist-create': DeskNavMark.icon(Icons.add_circle_outline_rounded),
  'hl:perps': DeskNavMark.icon(Icons.all_inclusive_rounded),
  'hl:spot': DeskNavMark.icon(Icons.token_outlined),
  'hl:crypto': DeskNavMark.icon(Icons.currency_bitcoin_rounded),
  'hl:tradfi': DeskNavMark.icon(Icons.account_balance_outlined),
  'hl:pre_launch': DeskNavMark.icon(Icons.hourglass_empty_rounded),
  'hl:sub:all': DeskNavMark.icon(Icons.format_list_bulleted_rounded),
  'hl:sub:stocks': DeskNavMark.icon(Icons.candlestick_chart_outlined),
  'hl:sub:indices': DeskNavMark.icon(Icons.show_chart_rounded),
  'hl:sub:commodities': DeskNavMark.icon(Icons.diamond_outlined),
  'hl:sub:fx': DeskNavMark.icon(Icons.currency_exchange_rounded),
  'hl:sub:preipo': DeskNavMark.icon(Icons.rocket_launch_outlined),
  'hl:sub:layer1': DeskNavMark.icon(Icons.looks_one_outlined),
  'hl:sub:layer2': DeskNavMark.icon(Icons.looks_two_outlined),
  'hl:sub:defi': DeskNavMark.icon(Icons.hub_outlined),
  'hl:sub:ai': DeskNavMark.icon(Icons.auto_awesome_outlined),
  'hl:sub:meme': DeskNavMark.icon(Icons.sentiment_satisfied_alt_outlined),
  'hl:sub:gaming': DeskNavMark.icon(Icons.sports_esports_outlined),
  'hl:sub:other': DeskNavMark.icon(Icons.more_horiz_rounded),
  // Predictions: the topics' own glyphs, the 5 minute rounds' timer.
  'poly:trending': DeskNavMark.glyph('$_kTags/trending.svg'),
  'poly:five-minute': DeskNavMark.icon(Icons.timer_outlined),
  'poly:watchlist': DeskNavMark.glyph('$_kTags/watchlist.svg'),
  'poly:breaking': DeskNavMark.glyph('$_kTags/breaking.svg'),
  'poly:new': DeskNavMark.glyph('$_kTags/new.svg'),
  'poly:live': DeskNavMark.glyph('$_kTags/live.svg'),
  'poly:politics': DeskNavMark.glyph('$_kTags/politics.svg'),
  'poly:sports': DeskNavMark.glyph('$_kTags/sports.svg'),
  'poly:crypto': DeskNavMark.glyph('$_kTags/crypto.svg'),
  'poly:esports': DeskNavMark.glyph('$_kTags/esports.svg'),
  // Polymarket's Finance glyph is its Politics building again.
  'poly:finance': DeskNavMark.icon(Icons.paid_outlined),
  'poly:geopolitics': DeskNavMark.glyph('$_kTags/geopolitics.svg'),
  'poly:tech': DeskNavMark.glyph('$_kTags/tech.svg'),
  'poly:elections': DeskNavMark.glyph('$_kTags/elections.svg'),
  'poly:culture': DeskNavMark.glyph('$_kTags/culture.svg'),
  'poly:economy': DeskNavMark.glyph('$_kTags/economy.svg'),
  'poly:weather': DeskNavMark.glyph('$_kTags/weather.svg'),
  'poly:mentions': DeskNavMark.glyph('$_kTags/mentions.svg'),
  'poly:art': DeskNavMark.glyph('$_kTags/art.svg'),
  'poly:sub:all': DeskNavMark.icon(Icons.format_list_bulleted_rounded),
};

/// An id the table does not name: a quiet dot.
const DeskNavMark kDeskNavDefaultMark =
    DeskNavMark.icon(Icons.fiber_manual_record_outlined);

/// The section's mark by its [InvestmentsTab] key.
Widget deskNavSectionIcon(String tab) => DeskNavIcon('section:$tab');

/// An Investing category's mark.
Widget deskNavHlTabIcon(HlBrowseTab t) => DeskNavIcon('hl:${t.key}');

/// An Investing subcategory's mark.
Widget deskNavHlSubIcon(HlBrowseSub s) => DeskNavIcon('hl:sub:${s.key}');

/// A Predictions topic's mark.
Widget deskNavPolyPillIcon(PolyPill p) => DeskNavIcon('poly:${p.key}');

/// The mark of row [sub] of [pill] (a topic's subcategory, or one of
/// Trending's themes): "All …" the table's; a row with a monochrome glyph
/// of the site's set that glyph in the words' colour; a coloured glyph or
/// an image the category sheet's own ([PolySubIcon]); else [label]'s
/// first letter on a quiet tile.
Widget deskNavPolySubIcon(PolyPill pill, PolySub sub, String label) {
  if (sub.key == pill.defaultSub) return const DeskNavIcon('poly:sub:all');
  return _DeskNavPolySubIcon(pill: pill, sub: sub, label: label);
}

/// An item's mark from [kDeskNavMarks], in the words' colour (the
/// ambient [IconTheme], which the item sets).
class DeskNavIcon extends StatelessWidget {
  const DeskNavIcon(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final mark = kDeskNavMarks[id] ?? kDeskNavDefaultMark;
    final color = IconTheme.of(context).color ?? context.colors.textTertiary;
    final asset = mark.asset;
    final Widget child;
    if (mark.icon != null) {
      child = Icon(mark.icon,
          size: mark.icon == kDeskNavDefaultMark.icon ? 8 : kDeskNavGlyph,
          color: color);
    } else if (mark.coloured) {
      child = SvgPicture.asset(asset!,
          width: kDeskNavIconSlot, height: kDeskNavIconSlot);
    } else {
      child = DeskNavGlyph(asset: asset!, color: color);
    }
    return SizedBox.square(
      key: ValueKey('desk-nav-icon-$id'),
      dimension: kDeskNavIconSlot,
      child: Center(child: child),
    );
  }
}

/// A monochrome SVG of the site's set in [color].
class DeskNavGlyph extends StatelessWidget {
  const DeskNavGlyph({super.key, required this.asset, required this.color});

  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        asset,
        width: kDeskNavGlyph,
        height: kDeskNavGlyph,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// [label]'s first letter on a quiet rounded tile in the words' colour:
/// a row with no art of its own, or while its image loads.
class DeskNavLetterTile extends StatelessWidget {
  const DeskNavLetterTile({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.colors.textTertiary;
    final letter = label.trim().isEmpty
        ? ''
        : String.fromCharCode(label.trim().runes.first).toUpperCase();
    return Container(
      width: kDeskNavGlyph,
      height: kDeskNavGlyph,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class _DeskNavPolySubIcon extends StatelessWidget {
  const _DeskNavPolySubIcon(
      {required this.pill, required this.sub, required this.label});

  final PolyPill pill;
  final PolySub sub;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.colors.textTertiary;
    final dark = context.isDark;
    final asset = polySubIconAsset(pill, sub, dark: dark);
    final Widget child;
    if (asset != null) {
      // The sports' and esports' coloured glyphs as the sheet draws them
      // (their plates on the theme that hides them); the site's
      // monochrome row glyphs in the words' colour.
      final coloured = (asset.contains('/sports/') ||
              asset.contains('/esports/')) &&
          !_kMonochromeArt.contains(asset);
      child = coloured
          ? polySubIcon(pill, sub, kDeskNavGlyph)
          : DeskNavGlyph(asset: asset, color: color);
    } else {
      final url = polySubImageUrl(pill, sub);
      final letter = DeskNavLetterTile(label: label);
      if (url == null || url.isEmpty) {
        child = letter;
      } else {
        // A picture fills the tile; a logo keeps its shape.
        final fit = kPolyTopicRowImages.containsValue(url) ||
                kPolyEsportsRowImages.containsValue(url)
            ? BoxFit.cover
            : BoxFit.contain;
        final normalized = polymarketArtworkUrl(url);
        child = normalized == null
            ? letter
            : kIsWeb
                // The browser's <img> (no CORS on Polymarket's hosts), the
                // letter while it loads and if it fails.
                ? WebNetworkImage(
                    url: normalized,
                    width: kDeskNavIconSlot,
                    height: kDeskNavIconSlot,
                    fit: fit,
                    borderRadius: BorderRadius.circular(5),
                    placeholder: letter,
                    error: letter,
                  )
                : PolyCrestImage(
                    url: url,
                    size: kDeskNavIconSlot,
                    radius: 5,
                    fit: fit,
                    fallback: letter,
                  );
      }
    }
    return SizedBox.square(
      key: ValueKey('desk-nav-icon-poly:${pill.key}:${sub.key}'),
      dimension: kDeskNavIconSlot,
      child: Center(child: child),
    );
  }
}
