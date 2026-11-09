import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/theme/app_theme.dart';

// A Predictions row's icon (founder, 9 November 2026: "actually use the
// svgs from polymarket here", then, of the Esports screen: "i dont get why
// all sub categories are not getting a svg"), wherever the rows appear: the
// category sheet's grids and league level, the drill pills, the search's
// category row. In order, for every row of every topic:
//
//   1. polymarket.com's own SVG for the row, bundled
//      (lib/assets/polymarket_tags/README.md): the sports' and esports'
//      coloured glyphs, and the monochrome glyphs of the Crypto, Finance and
//      Weather side lists, drawn in the text's colour;
//   2. Polymarket's hosted image for the row: a league's or a coin's
//      ([PolySub.imageUrl]), Finance's side-list images, and for the
//      Politics, Geopolitics, Tech, Culture and Economy rows (the site draws
//      none) the image of one of the row's top markets, read 9 November 2026;
//   3. the topic's own glyph, also when an image fails or is offline.
//
// Always exactly [PolySubIcon.size] square, loaded or not, so nothing moves
// while an image lands.

const String _kDir = 'lib/assets/polymarket_tags';
const String _kSportsDir = '$_kDir/sports';
const String _kEsportsDir = '$_kDir/esports';
const String _kRowsDir = '$_kDir/rows';
const String _kS3 = 'https://polymarket-upload.s3.us-east-2.amazonaws.com';

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

/// THE MARKS THAT VANISH ON ONE THEME (founder, 9 November 2026: "some
/// icons don't look good on dark mode and some don't look good on white
/// mode"; every icon of the sheet and the drill rows rendered in both
/// themes and looked at). A coloured mark is never recoloured; one that
/// melts into a theme's surface sits on the other theme's logo plate
/// instead (the coin logos' plate, [HlCoinIcon]: the theme's surfaceLight),
/// a rounded square the size of the icon with the mark inside it:
///
///   * in dark mode, on the light plate: the Champions League's navy
///     starball (#123C74), Cricket's dark red (#bf0000), Darts' dark grey
///     (#62646a) and Overwatch's grey ring (#4a4c4e);
///   * in light mode, on the dark plate: Darts' light grey (#bfc3ca).
const Set<String> kPolyLightPlateOnDark = {
  '$_kSportsDir/ucl.svg',
  '$_kSportsDir/cricket.dark.svg',
  '$_kSportsDir/darts.dark.svg',
  '$_kEsportsDir/overwatch.svg',
};
const Set<String> kPolyDarkPlateOnLight = {
  '$_kSportsDir/darts.svg',
};

/// The plate bundled glyph [asset] sits on in the [dark] theme, or null
/// for one that reads on the theme's own surface (see
/// [kPolyLightPlateOnDark]).
Color? polyIconPlate(String asset, {required bool dark}) => dark
    ? (kPolyLightPlateOnDark.contains(asset)
        ? AppColorsExtension.light().surfaceLight
        : null)
    : (kPolyDarkPlateOnLight.contains(asset)
        ? AppColorsExtension.dark().surfaceLight
        : null);

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
  return '$_kSportsDir/$key${dark && _kDarkVariants.contains(key) ? '.dark' : ''}.svg';
}

/// What `lib/assets/polymarket_tags/esports/` holds: every game of
/// [kPolyEsportsGames] by its slug, in the site's colours, but StarCraft:
/// Brood War ([kPolyEsportsRowImages]).
Set<String> get kPolyEsportsIconKeys => {
      for (final g in kPolyEsportsGames)
        if (!kPolyEsportsRowImages.containsKey(g.slug)) g.slug,
    };

/// The games drawn from Polymarket's hosted image instead: Brood War's own
/// SVG is a 176 x 24 wordmark in #414141, unreadable at 20 pt and gone on
/// the dark plate; its card image on polymarket.com/esports stands in.
const Map<String, String> kPolyEsportsRowImages = {
  'starcraft-brood-war': '$_kS3/starcraftbroodwar-77405089c8.jpg',
};

/// The monochrome glyphs of `lib/assets/polymarket_tags/rows/`, by pill and
/// row key: the site's side-list icon of that row. Crypto's Yearly takes
/// the set's calendar with a dot: the site draws Daily's calendar for both.
const Map<PolyPill, Map<String, String>> kPolyRowGlyphs = {
  PolyPill.crypto: {
    '5m': '5m',
    '15m': '15m',
    '1h': '1h',
    '4h': '4h',
    'daily': 'daily',
    'weekly': 'weekly',
    'monthly': 'monthly',
    'yearly': 'calendar',
    'targets': 'targets',
    'pre-market': 'pre-market',
    'institutions': 'institutions',
    'industry': 'industry',
    'protocol-metrics': 'protocol-metrics',
  },
  PolyPill.finance: {
    'daily': 'daily',
    'weekly': 'weekly',
    'monthly': 'monthly',
    'privates': 'privates',
    'acquisitions': 'acquisitions',
    'ipo': 'ipo',
    'fed-rates': 'fed-rates',
    'prediction-markets': 'prediction-markets',
    'treasuries': 'treasuries',
    'kpis': 'kpis',
  },
  PolyPill.weather: {
    'temperature': 'temperature',
    'precipitation': 'precipitation',
    'drought': 'drought',
    'global': 'global',
    'tornadoes': 'tornadoes',
    'hurricanes': 'hurricanes',
    'earthquakes': 'earthquakes',
    'volcanoes': 'volcanoes',
    'pandemics': 'pandemics',
  },
};

/// The topic rows (Politics, Geopolitics, Tech, Culture, Economy) that draw
/// a glyph of the site's set rather than a market's image, by the row's tag
/// slug: the site's own Apple, TikTok and X marks, and the Finance side
/// list's glyph where the row is the same subject.
const Map<String, String> kPolyTopicRowGlyphs = {
  'apple': 'apple',
  'tiktok': 'tiktok',
  'tweets-markets': 'x',
  'fed-rates': 'fed-rates',
  'treasuries': 'treasuries',
  'prediction-markets': 'prediction-markets',
  'macro-indicators': 'kpis',
  'taxes': 'taxes',
};

/// Breaking's rows are the topics themselves: each draws its topic's glyph.
const Map<String, String> _kBreakingGlyphs = {
  'politics': 'politics',
  'world': 'geopolitics',
  'sports': 'sports',
  'crypto': 'crypto',
  'finance': 'finance',
  'tech': 'tech',
  'culture': 'culture',
};

/// Finance's side-list images, as polymarket.com/finance draws them.
const Map<String, String> kPolyFinanceRowImages = {
  'stocks': '$_kS3/equities-2-ea04b2d05c.png',
  'earnings': '$_kS3/equities-8d28bdc2cb.png',
  'indicies': '$_kS3/indicies-008ef3f0b8.png',
  'commodities': '$_kS3/commodites-2a76edec07.png',
  'forex': '$_kS3/currencies-481278de46.png',
};

/// The topic rows' images, by tag slug: one of the row's top markets'
/// (`/internal/view/category/<slug>`, 9 November 2026), the one that shows
/// the row's subject. A row the site adds later draws its topic's glyph.
/// Trending's themes that are no topic row (Anthropic IPO, Cabinet Shakeup
/// …) have theirs here too, from the same views on the same day; a theme
/// the site adds later draws Trending's glyph until its own list is loaded.
const Map<String, String> kPolyTopicRowImages = {
  'anthropic-ipo': '$_kS3/anthropic-ipo-closing-market-cap-jdfele1g0krx.png',
  'cabinet-shakeup': '$_kS3/pete-hegseth-out-as-secretary-of-defense-by-friday-RWimpJbOlkbf.jpg',
  'ai-bubble': '$_kS3/ai-industry-downturn-by-fFNK9rGi-70Y.jpg',
  'fed': '$_kS3/will-the-fed-raise-interest-rates-in-2025-PQTEYZMvmAGr.jpg',
  'new-zealand-election': '$_kS3/which-parties-will-be-part-of-the-next-government-of-new-zealand-JkhMvb-9VUVd.jpg',
  'south-africa-municipal-elections': '$_kS3/event-update-PBVHgDf-24YI.jpg',
  'spain-elections': '$_kS3/spainflagcrestcentre-241f86d478.jpg',
  'astra': '$_kS3/when-will-gpt-5-be-released-vIPhU76RogZc.jpg',
  'lol-worlds-2026': '$_kS3/event-art/esports/lol/worlds-2026-winner.png',
  'trump': '$_kS3/trump-out-as-president-by-march-31-c3SENQhH7Ao1.jpg',
  'midterms': '$_kS3/will-senate-pass-funding-bill-by-7NO2CCO7a2Mk.png',
  'competitive-races': '$_kS3/az-01-house-election-winner-f7Ie3Y-kl-3T.png',
  '2028-election': '$_kS3/presidential-election-winner-2024-afdda358-219d-448a-abb5-ba4d14118d71.png',
  'post-election': '$_kS3/pete-hegseth-out-as-secretary-of-defense-by-friday-RWimpJbOlkbf.jpg',
  'congress': '$_kS3/2026-midterms-house-turnout-LvRZgss0a2lN.png',
  'gov-shutdown': '$_kS3/govt+shutdown.jpeg',
  'senate-midterms': '$_kS3/f-74dbca06af.png',
  'house-elections': '$_kS3/state_flags/NC.png',
  'governor-midterms': '$_kS3/mi-f9cf816aa1.png',
  'derivatives': '$_kS3/democrats+2028+donkey.png',
  'global-elections': '$_kS3/spainflagcrestcentre-241f86d478.jpg',
  'israel-election': '$_kS3/who-will-be-the-next-prime-minister-of-israel-after-the-2026-election-lWDmU0z7U_Vj.png',
  'french-election': '$_kS3/france-presidential-election-2027-U5QY3acvfubZ.png',
  'brazil': '$_kS3/brazil-presidential-election-37lx5Jgvkbr8.png',
  'china': '$_kS3/november-inflation-china-monthly-4lMPpXprmgqE.jpg',
  'canada': '$_kS3/north-vancouvercapilano-by-election-winner-20260729185730213-VtM65YY3vjgN.png',
  'russia': '$_kS3/putin-out-as-president-of-russia-in-2025-nWuurkC8qfbi.jpg',
  'venezuela': '$_kS3/venezuela-leader-end-of-2026-lOfqbUxiKAsg.png',
  'epstein': '$_kS3/will-anyone-be-jailed-over-epstein-disclosures-sK0R4XPWIn6U.jpg',
  'iran': '$_kS3/iran-leader-ship-change-by-6HjLf457Nt35.jpg',
  'lebanon': '$_kS3/will-israel-strike-lebanon-on-431-QKZtCmgXI6x8.jpg',
  'oil': '$_kS3/crude-oil-9a850ce2a2.png',
  'ukraine': '$_kS3/zelenskyy-out-as-ukraine-president-by-october-31-vvfzvJSdhPij.jpg',
  'ukraine-map': '$_kS3/will-russia-capture-all-of-kostyantynivka-by-EaTom9xBb9aK.jpg',
  'cuba': '$_kS3/us-strike-on-cuba-by-EstR5MqlPUOe.jpg',
  'middle-east': '$_kS3/us-iran-final-nuclear-deal-by-20260621201254412-2M_GeQ8diXxj.jpg',
  'gaza': '$_kS3/israel-x-hamas-ceasefire-phase-ii-by-october-31-ihvZFCsuS8NH.jpg',
  'israel': '$_kS3/who-will-be-the-next-prime-minister-of-israel-after-the-2026-election-lWDmU0z7U_Vj.png',
  'syria': '$_kS3/houthi-syria-houthi-military-action-against-syria-flag-77d705fc14.jpg',
  'yemen': '$_kS3/yesy-57eeac9739.png',
  'turkey': '$_kS3/erdoan-out-in-2025-brAWCvEk1bDo.jpg',
  'sudan': '$_kS3/sudan-civil-war-ceasefire-in-2025-zeC8lKdFgQRs.jpg',
  'india-pakistan': '$_kS3/india-strike-on-pakistan-before-august-x85XQfgodtQ_.jpg',
  'ai': '$_kS3/ai-industry-downturn-by-fFNK9rGi-70Y.jpg',
  'elon-musk': '$_kS3/elon-musk-meets-with-putin-by-LVgqNUV89z2V.jpg',
  'app-store': '$_kS3/1-free-app-in-the-us-apple-app-store-on-october-10-VjezCsQutpq3.png',
  'spacex': '$_kS3/two-spacex-starships-dock-together-by-40lKMvipOIgS.jpg',
  'science': '$_kS3/new-pandemic-in-2025-LHjGCD7X6VYI.jpg',
  'openai': '$_kS3/when-will-gpt-5-be-released-vIPhU76RogZc.jpg',
  'big-tech': '$_kS3/will-jensen-huang-be-richest-person-on-december-31-iU8eWlv0KU_b.jpg',
  'art': '$_kS3/auction-sale-price-picasso-86f7712c69.jpg',
  'music': '$_kS3/grammys-album-of-the-year-nominations-9vEtmFPLWXgp.jpg',
  'celebrities': '$_kS3/jensen-huang-divorce-in-2026-TwqKa0CMsYm6.jpg',
  'awards': '$_kS3/oscars-2026-best-picture-nominations-uExlgIhppb3W.jpg',
  'mrbeast': '$_kS3/what-will-mrbeast-say-during-his-next-gaming-youtube-video-Ev9kDc7p0s1f.jpg',
  'movies': '$_kS3/next-james-bond-actor-d648bfbf-75d1-4a29-be40-7a50ea1c18e2.png',
  'box-office': '$_kS3/highest-grossing-movie-in-2025-23YRHKqq6Ete.jpg',
  'taylor-swift': '$_kS3/taylor-swift-pregnant-in-2025-5cpC3Ir4u5Pd.jpg',
  'gta-vi': '$_kS3/gta-vi-released-before-june-2026-igCgZsDMejF1.jpg',
  'youtube': '$_kS3/ethan-klein-livestream-ethan-klein-a44a3fb858.jpg',
  'reality-tv': '$_kS3/bachelorette-season-22-winner-cJVkpUJ73e3m.jpg',
  'aliens': '$_kS3/trump-declassifies-ufo-files-in-2025-t8Tno8ou_ycE.jpg',
  'courts': '$_kS3/scotus-accepts-sports-event-contract-case-by-july-31-2026-fYCnFfdr4Hha.jpg',
  'eurovision': '$_kS3/eurovision-2026-participants-Z7-PefArvWkx.jpg',
  'trade-war': '$_kS3/us-trade-deficit-in-2026-Hn37ZN5inoET.jpg',
  'inflation': '$_kS3/us-economic-state-at-the-end-of-2026-HW5PwA-mSi5Q.jpg',
  'gdp': '$_kS3/2026-world-gdp-growth-pDzq521t-cVH.png',
  'global-rates': '$_kS3/ecb-interest-rates-april-2025-DJ5nB6uaqtx5.png',
  'consumer': '$_kS3/university-of-michigan-consumer-sentiment-june-2026-cfoR9ndL6mq5.jpg',
  'housing': '$_kS3/mortgage-default-rate-exceeds-3pct-by-end-of-q4-2027-9RkpAMaCofma.jpg',
  'labor': '$_kS3/jolts-job-openings-april-2026--2HXZp9xl0Qn.png',
  'microstrategy': 'https://polymarket.com/images/logos/microstrategy.jpg',
};

/// The pills whose rows have icons of their own (the others have no rows).
/// Trending's row is the site's themes, each a tag of a topic row
/// (Midterms, Iran, AI …), so it resolves as a topic row does.
const Set<PolyPill> _kPillsWithRows = {
  PolyPill.trending,
  PolyPill.sports,
  PolyPill.esports,
  PolyPill.crypto,
  PolyPill.finance,
  PolyPill.weather,
  PolyPill.breaking,
  PolyPill.politics,
  PolyPill.geopolitics,
  PolyPill.tech,
  PolyPill.culture,
  PolyPill.economy,
};

const Set<PolyPill> _kTopicPills = {
  PolyPill.trending,
  PolyPill.politics,
  PolyPill.geopolitics,
  PolyPill.tech,
  PolyPill.culture,
  PolyPill.economy,
};

/// A topic's own glyph, the last resort of every row of it.
String polyPillGlyphAsset(PolyPill pill) => '$_kDir/${pill.key}.svg';

/// The bundled SVG of row [sub] of [pill], or null: coloured for Sports and
/// Esports (Call of Duty's in the text's colour, as the site's), in the
/// text's colour otherwise.
String? polySubIconAsset(PolyPill pill, PolySub sub, {bool dark = false}) {
  if (!_kPillsWithRows.contains(pill)) return null;
  switch (pill) {
    case PolyPill.sports:
      return polySportIconAsset(sub, dark: dark);
    case PolyPill.esports:
      return kPolyEsportsIconKeys.contains(sub.key)
          ? '$_kEsportsDir/${sub.key}.svg'
          : null;
    case PolyPill.breaking:
      final topic = _kBreakingGlyphs[sub.key];
      return topic == null ? null : '$_kDir/$topic.svg';
    default:
      final glyph = _kTopicPills.contains(pill)
          ? kPolyTopicRowGlyphs[sub.route]
          : kPolyRowGlyphs[pill]?[sub.key];
      return glyph == null ? null : '$_kRowsDir/$glyph.svg';
  }
}

/// Polymarket's hosted image for row [sub] of [pill], or null: the row's
/// own ([PolySub.imageUrl]: a league's, a game's, a coin's), else the dated
/// one of [kPolyFinanceRowImages] or [kPolyTopicRowImages]. Brood War's card
/// image goes first: Gamma's `sc` logo is StarCraft II's.
String? polySubImageUrl(PolyPill pill, PolySub sub) {
  if (!_kPillsWithRows.contains(pill)) return null;
  if (pill == PolyPill.esports) {
    final art = kPolyEsportsRowImages[sub.key];
    if (art != null) return art;
  }
  final own = sub.imageUrl;
  if (own != null && own.isNotEmpty) return own;
  if (pill == PolyPill.finance) return kPolyFinanceRowImages[sub.key];
  if (_kTopicPills.contains(pill)) return kPolyTopicRowImages[sub.route];
  return null;
}

/// The row's icon at [size]: [polySubIcon] picks the Sports one.
class PolySubIcon extends StatelessWidget {
  final PolyPill pill;
  final PolySub sub;
  final double size;

  const PolySubIcon(
      {super.key, required this.pill, required this.sub, required this.size});

  @override
  Widget build(BuildContext context) {
    final glyph = pill == PolyPill.sports
        ? PolySportTrophy(size: size)
        : PolyPillGlyph(pill: pill, size: size);
    final dark = context.isDark;
    final asset = polySubIconAsset(pill, sub, dark: dark);
    if (asset != null) {
      // A mark that vanishes on this theme sits on the other theme's plate
      // (see [kPolyLightPlateOnDark]), a little inside it.
      final plate = polyIconPlate(asset, dark: dark);
      final inset = plate == null ? 0.0 : size * 0.14;
      // By width alone inside the square: a wide mark (the UFC's wordmark)
      // would otherwise take its height and run out of the plate.
      return Container(
        key: ValueKey('poly-sub-icon-$asset'),
        width: size,
        height: size,
        padding: EdgeInsets.all(inset),
        decoration: plate == null
            ? null
            : BoxDecoration(
                color: plate,
                borderRadius: BorderRadius.circular(size * 0.25),
              ),
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: size - 2 * inset,
            // The site's monochrome glyphs (`currentColor`, and Futures) in
            // the text's colour; a Breaking row's topic glyph (black fills)
            // painted in it, as the topic's own card draws it.
            theme: SvgTheme(currentColor: context.colors.textPrimary),
            colorFilter: pill == PolyPill.breaking
                ? ColorFilter.mode(context.colors.textPrimary, BlendMode.srcIn)
                : null,
            placeholderBuilder: (_) =>
                SizedBox.square(dimension: size - 2 * inset),
            errorBuilder: (_, __, ___) => glyph,
          ),
        ),
      );
    }
    final url = polySubImageUrl(pill, sub);
    if (url == null || url.isEmpty) return glyph;
    return SizedBox.square(
      key: ValueKey('poly-sub-icon-$url'),
      dimension: size,
      child: PolyCrestImage(
        url: url,
        size: size,
        radius: 3,
        // A picture fills the square; a logo keeps its shape.
        fit: kPolyTopicRowImages.containsValue(url) ||
                kPolyEsportsRowImages.containsValue(url)
            ? BoxFit.cover
            : BoxFit.contain,
        fallback: glyph,
      ),
    );
  }
}

/// A Sports row's icon ([PolySubIcon] on [PolyPill.sports]).
class PolySportIcon extends PolySubIcon {
  const PolySportIcon({super.key, required super.sub, required super.size})
      : super(pill: PolyPill.sports);
}

/// Row [sub] of [pill]'s icon at [size]: [PolySportIcon] on Sports.
PolySubIcon polySubIcon(PolyPill pill, PolySub sub, double size) =>
    pill == PolyPill.sports
        ? PolySportIcon(sub: sub, size: size)
        : PolySubIcon(pill: pill, sub: sub, size: size);

/// Whether row [sub] of [pill] has an icon of its own (a bundled glyph or a
/// hosted image), rather than its topic's glyph.
bool polySubHasOwnIcon(PolyPill pill, PolySub sub) =>
    polySubIconAsset(pill, sub) != null || polySubImageUrl(pill, sub) != null;

/// A topic's monochrome glyph in the text's colour: a row with nothing
/// better, or whose image failed.
class PolyPillGlyph extends StatelessWidget {
  final PolyPill pill;
  final double size;

  const PolyPillGlyph({super.key, required this.pill, required this.size});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        polyPillGlyphAsset(pill),
        width: size,
        height: size,
        colorFilter:
            ColorFilter.mode(context.colors.textPrimary, BlendMode.srcIn),
      );
}

/// The Sports topic's monochrome trophy: a Sports row with nothing better.
class PolySportTrophy extends PolyPillGlyph {
  const PolySportTrophy({super.key, required super.size})
      : super(pill: PolyPill.sports);
}
