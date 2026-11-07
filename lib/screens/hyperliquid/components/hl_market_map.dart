// lib/screens/hyperliquid/components/hl_market_map.dart
//
// The market map: a card under the Investing list (founder, 6 November
// 2026, with a stock heatmap for reference: "add another card on
// Investing, we must make a graph like this for the stocks and stuff,
// like the red or green ones"). A squarified treemap
// (squarified_treemap.dart) of the markets the app lists, red for down and
// green for up.
//
// What it shows (hlMarketMapEntries):
//   * the markets of the browse universe in four asset classes, Stocks
//     (with the pre-IPO companies), Indices, Commodities and Crypto
//     (HlMarketMapGroup); FX and the venues' unclassed markets are left
//     out. Thin markets ([HlMarket.isLowLiquidity]), markets with no 24h
//     change to show and spot tokens Hyperliquid's own app does not verify
//     ([hlSpotIsVerified]) are never on it;
//   * one tile per underlying ([hlUnderlyingKey]): of gold on three
//     builders, the most traded;
//   * the [kHlMarketMapMaxTiles] most traded, with a hysteresis: a market
//     already on the map stays while it ranks in the top
//     [kHlMarketMapStayTiles], so two markets trading places at the edge
//     do not reshuffle the map's tail on every refresh.
//
// Size: a tile's area is its market's 24 h notional volume
// ([HlMarket.dayNtlVlm]), the number the Trending ranking uses. The venue
// gives no market capitalisation, and open interest exists for perps only
// (a spot token has none), so volume is the one size every tile has. One
// scale for the whole map: the classes' blocks are as big as their
// markets' volume together, so the map reads like the reference (the
// biggest names the biggest tiles), each block labelled over its tiles
// when there is more than one.
//
// Colour: the 24 h change of the live price (as the rows read it),
// marketDown for down and marketUp for up, mixed from a neutral grey by
// the size of the move ([hlMarketMapIntensity]): grey at a change the row
// prints as 0.0 %, full colour from ±[kHlMarketMapChangeCap] (5 %), a
// curve in between so the day's ordinary moves are seen. Opaque mixes, no
// alpha tint. The text on a tile is white or the ink, whichever reads.
//
// Labels (hlMarketMapLabelFor), by the room a tile has: the logo, the
// ticker and the change on the big ones; the ticker over the change on
// the middle ones; the ticker alone; nothing on the smallest, colour
// only. Every label is measured before it is drawn, at the viewer's text
// size, so text never clips: a label that does not fit drops a level.
// Indices and commodities show their name (Nasdaq 100, Gold) where it
// fits, their tickers (XYZ100, CL) being no name for anyone.
//
// Live: the layout is made from the markets and their sizes only, and
// kept while the same markets are on the map and no tile's share of it
// has moved by [kHlMarketMapRelayoutShare] (HlMarketMapLayout.fits); the
// live prices repaint the colours and the changes in place. One painter
// (HlMarketMapPainter) draws the tiles and the text; the logos are the
// only widgets on it (HlCoinIcon, a handful), and a tap is hit-tested on
// the layout. A tile opens its market's sheet, the list rows' handler,
// with 'market_map' as the entry source.
//
// On the default view only (Trending at its default list), as the big
// squares: a category the person picks is the full plain list (founder,
// 1 November 2026), and a card under a list of a hundred rows would never
// be seen. No 24h / today switch: the venue's numbers carry the previous
// day's price and nothing for today's open, so the header names the
// window, 24h, in the quiet weight.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/squarified_treemap.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hlSpotIsVerified;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show hlArrowPct;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteChartFontFamily;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';

/// The most tiles the map shows (a market enters when it ranks here).
const int kHlMarketMapMaxTiles = 48;

/// A market on the map stays while it ranks in this many.
const int kHlMarketMapStayTiles = 56;

/// Under this many markets there is no map at all.
const int kHlMarketMapMinTiles = 8;

/// The 24 h change from which a tile wears the full colour: ±5 %.
const double kHlMarketMapChangeCap = 0.05;

/// The share of the map a tile may gain or lose before the map is laid
/// out again: one percent of its area.
const double kHlMarketMapRelayoutShare = 0.01;

/// The least area a tile is given, in logical pixels: a smaller market
/// is left off rather than drawn as a sliver.
const double kHlMarketMapMinTileArea = 110;

/// The map's height over its width.
const double kHlMarketMapAspect = 1.0;

/// The [HlMarketDetailSheet] entry source a tile reports.
const String kHlMarketMapSource = 'market_map';

/// Between two tiles, and between two blocks, in logical pixels.
const double _kTileGap = 2;
const double _kBlockGap = 4;

/// Inside a tile, around its label; around a lone ticker on a small one.
const double _kLabelPad = 4;
const double _kTightPad = 2;

/// The widest change a label is measured for: two figures.
const String _kChangeTemplate = '▼ 88.8%';

/// The asset classes the map groups its tiles in, in this order when two
/// blocks weigh the same.
enum HlMarketMapGroup { stocks, indices, commodities, crypto }

extension HlMarketMapGroupLabel on HlMarketMapGroup {
  String label(AppLocalizations l10n) => switch (this) {
        HlMarketMapGroup.stocks => l10n.investingStocks,
        HlMarketMapGroup.indices => l10n.investingIndices,
        HlMarketMapGroup.commodities => l10n.investingCommodities,
        HlMarketMapGroup.crypto => l10n.investingCrypto,
      };
}

/// The block [m] belongs in, or null when the map leaves it out (FX, a
/// builder's unclassed market).
HlMarketMapGroup? hlMarketMapGroupOf(HlMarket m) => switch (m.category) {
      'stocks' || 'preipo' => HlMarketMapGroup.stocks,
      'indices' => HlMarketMapGroup.indices,
      'commodities' => HlMarketMapGroup.commodities,
      'crypto' => HlMarketMapGroup.crypto,
      _ => null,
    };

/// A market's key on the map (the list rows' key).
String hlMarketMapId(HlMarket m) => '${m.kind.name}:${m.wireCoin}';

/// The 24 h change at the snapshot price (the ranking's), null when there
/// is none to show.
double? _snapshotChange(HlMarket m) =>
    m.dayChangeAtOrNull(m.midPx > 0 ? m.midPx : m.markPx);

/// True when [m] may be a tile: in one of the map's classes, traded (not
/// thin), with a 24 h change to show, and no spot token the venue's own
/// app does not verify (anyone may deploy a token called NVDA).
bool hlMarketMapCandidate(HlMarket m) =>
    hlMarketMapGroupOf(m) != null &&
    m.dayNtlVlm.isFinite &&
    m.dayNtlVlm > 0 &&
    !m.isLowLiquidity &&
    (!m.isSpot || hlSpotIsVerified(m)) &&
    _snapshotChange(m) != null;

/// One market on the map, in its block.
class HlMarketMapEntry {
  const HlMarketMapEntry({required this.market, required this.group});

  final HlMarket market;
  final HlMarketMapGroup group;

  /// The tile's size: 24 h notional volume.
  double get weight => market.dayNtlVlm;

  String get id => hlMarketMapId(market);
}

/// The map's markets from [universe], most traded first (ties by key):
/// the candidates ([hlMarketMapCandidate]), one per underlying (its
/// primary listing, [hlPrimaryListings], the one search and the lists
/// show), the top [max] by 24 h volume, and of the markets in [previous]
/// (the map on screen) those still in the top [stay] as well.
List<HlMarketMapEntry> hlMarketMapEntries(
  List<HlMarket> universe, {
  Set<String> previous = const {},
  int max = kHlMarketMapMaxTiles,
  int stay = kHlMarketMapStayTiles,
}) {
  final ranked = hlPrimaryListings([
    for (final m in universe)
      if (hlMarketMapCandidate(m)) m,
  ])
    ..sort((a, b) {
      final v = b.dayNtlVlm.compareTo(a.dayNtlVlm);
      return v != 0 ? v : hlMarketMapId(a).compareTo(hlMarketMapId(b));
    });
  return [
    for (var i = 0; i < ranked.length; i++)
      if (i < max || (i < stay && previous.contains(hlMarketMapId(ranked[i]))))
        HlMarketMapEntry(
            market: ranked[i], group: hlMarketMapGroupOf(ranked[i])!),
  ];
}

// ─────────────────────────────── layout ───────────────────────────────

/// One tile: its market's key and its rectangle (gaps not taken out).
class HlMarketMapTile {
  const HlMarketMapTile({required this.id, required this.rect});
  final String id;
  final Rect rect;
}

/// One class's block: its rectangle, the label strip over its tiles (null
/// when it has none) and its tiles.
class HlMarketMapBlock {
  const HlMarketMapBlock({
    required this.group,
    required this.rect,
    required this.header,
    required this.tiles,
  });

  final HlMarketMapGroup group;
  final Rect rect;
  final Rect? header;
  final List<HlMarketMapTile> tiles;
}

/// The map's geometry: blocks and tiles for markets and their sizes, in a
/// [size]. Made by [compute]; kept while it [fits] what the map shows.
class HlMarketMapLayout {
  HlMarketMapLayout._(this.size, this.blocks, this._shares);

  final Size size;
  final List<HlMarketMapBlock> blocks;

  /// The share of the whole weight each market had when this was made,
  /// by key, every market given (a market too small for a tile included).
  final Map<String, double> _shares;

  Iterable<HlMarketMapTile> get tiles sync* {
    for (final b in blocks) {
      yield* b.tiles;
    }
  }

  /// The tile under [p], or null (a block's label strip, outside).
  HlMarketMapTile? tileAt(Offset p) {
    for (final b in blocks) {
      if (!b.rect.contains(p)) continue;
      for (final t in b.tiles) {
        if (t.rect.contains(p)) return t;
      }
    }
    return null;
  }

  /// Whether this layout still holds [entries] in [size]: the same size,
  /// the same markets, and no market's share of the whole moved by
  /// [kHlMarketMapRelayoutShare] or more since it was made.
  bool fits(List<HlMarketMapEntry> entries, Size size) {
    if (size != this.size || entries.length != _shares.length) return false;
    final shares = _sharesOf(entries);
    for (final e in shares.entries) {
      final was = _shares[e.key];
      if (was == null || (e.value - was).abs() >= kHlMarketMapRelayoutShare) {
        return false;
      }
    }
    return true;
  }

  static Map<String, double> _sharesOf(List<HlMarketMapEntry> entries) {
    final total = entries.fold<double>(0, (s, e) => s + e.weight);
    return {
      for (final e in entries) e.id: total > 0 ? e.weight / total : 0,
    };
  }

  /// Lays [entries] out in [size]. The classes' blocks first (a
  /// squarified treemap of their volume together, with room for each
  /// block's label strip added so its tiles keep the map's one scale),
  /// then each block's tiles in what is left under its strip. A single
  /// class is one block with no strip. The smallest markets are left off
  /// while their tile would be under [minTileArea].
  static HlMarketMapLayout compute(
    List<HlMarketMapEntry> entries,
    Size size, {
    double minTileArea = kHlMarketMapMinTileArea,
  }) {
    final shares = _sharesOf(entries);
    final rect = Offset.zero & size;
    final area = size.width * size.height;

    // Largest first, ties by key: the same markets always lay out the same.
    final sorted = [...entries]..sort((a, b) {
        final v = b.weight.compareTo(a.weight);
        return v != 0 ? v : a.id.compareTo(b.id);
      });
    var kept = sorted.length;
    var total = sorted.fold<double>(0, (s, e) => s + e.weight);
    while (kept > 1 &&
        total > 0 &&
        sorted[kept - 1].weight / total * area < minTileArea) {
      total -= sorted[kept - 1].weight;
      kept--;
    }
    final placed = sorted.take(kept).toList();

    final groups = [
      for (final g in HlMarketMapGroup.values)
        if (placed.any((e) => e.group == g)) g,
    ];
    final members = {
      for (final g in groups)
        g: [
          for (final e in placed)
            if (e.group == g) e
        ],
    };
    double sumOf(HlMarketMapGroup g) =>
        members[g]!.fold<double>(0, (s, e) => s + e.weight);

    final blocks = <HlMarketMapBlock>[];
    if (groups.isEmpty || area <= 0) {
      return HlMarketMapLayout._(size, blocks, shares);
    }
    if (groups.length == 1) {
      final g = groups.single;
      blocks.add(_block(g, rect, null, members[g]!));
      return HlMarketMapLayout._(size, blocks, shares);
    }

    // No group titles on the blocks (founder, 6 November 2026: "not
    // titles like crypto and such"): the blocks keep their own areas.
    double headerOf(Rect r) => 0;
    final sums = [for (final g in groups) sumOf(g)];
    // First pass: blocks by volume alone, to know which carry a strip and
    // how wide it is; then the strips' area added to their blocks, so the
    // tiles under them keep the map's one scale.
    final first = squarify(sums, rect);
    final strips = [
      for (var i = 0; i < groups.length; i++)
        headerOf(first[i]) * first[i].width,
    ];
    final weighed = sums.fold<double>(0, (s, v) => s + v);
    if (weighed <= 0) return HlMarketMapLayout._(size, blocks, shares);
    final k =
        math.max(0.0, area - strips.fold<double>(0, (s, v) => s + v)) / weighed;
    final rects = squarify(
        [for (var i = 0; i < groups.length; i++) k * sums[i] + strips[i]],
        rect);
    for (var i = 0; i < groups.length; i++) {
      final r = rects[i];
      final h = headerOf(r);
      blocks.add(_block(
        groups[i],
        r,
        h > 0 ? Rect.fromLTWH(r.left, r.top, r.width, h) : null,
        members[groups[i]]!,
      ));
    }
    return HlMarketMapLayout._(size, blocks, shares);
  }

  static HlMarketMapBlock _block(HlMarketMapGroup group, Rect rect,
      Rect? header, List<HlMarketMapEntry> members) {
    final inner = header == null
        ? rect
        : Rect.fromLTRB(rect.left, header.bottom, rect.right, rect.bottom);
    final cells = squarify([for (final e in members) e.weight], inner);
    return HlMarketMapBlock(
      group: group,
      rect: rect,
      header: header,
      tiles: [
        for (var i = 0; i < members.length; i++)
          HlMarketMapTile(id: members[i].id, rect: cells[i]),
      ],
    );
  }
}

// ─────────────────────────────── colour ───────────────────────────────

/// How much colour a change of [change] (a fraction) wears, 0 to 1: none
/// at a change the row prints as 0.0 % (or none known), all of it from
/// ±[kHlMarketMapChangeCap], and a curve in between (the 0.7th power), so
/// a 1 % day is seen and a 3 % day is not a 6 % one.
double hlMarketMapIntensity(double? change) {
  if (change == null || !change.isFinite || change.abs() < 0.0005) return 0;
  final t = (change.abs() / kHlMarketMapChangeCap).clamp(0.0, 1.0);
  return math.pow(t, 0.7).toDouble();
}

/// The grey a flat tile wears: a step off the card in each mode.
Color hlMarketMapNeutral({required bool dark}) =>
    dark ? const Color(0xFF3A3F46) : const Color(0xFFE4E7EB);

/// A tile's fill for [change]: the neutral grey mixed towards marketUp
/// (up) or marketDown (down) by [hlMarketMapIntensity]. Opaque.
Color hlMarketMapFill(double? change, {required bool dark}) {
  final t = hlMarketMapIntensity(change);
  final neutral = hlMarketMapNeutral(dark: dark);
  if (t == 0) return neutral;
  final full = change! > 0 ? AppColors.marketUp : AppColors.marketDown;
  return Color.lerp(neutral, full, t)!;
}

/// The ink drawn on [fill]: white where white reads (3:1 at least, the
/// large-text contrast), else the light theme's text colour.
Color hlMarketMapInk(Color fill) {
  final l = fill.computeLuminance();
  final onWhite = 1.05 / (l + 0.05);
  return onWhite >= 3 ? Colors.white : const Color(0xFF1D2024);
}

// ─────────────────────────────── labels ───────────────────────────────

/// How much of a tile's label is drawn.
enum HlMarketMapLabelLevel { none, ticker, tickerChange, logo }

/// A tile's label: its [level], the [title] it shows (a ticker or a
/// name), and the sizes it is drawn at.
class HlMarketMapLabel {
  const HlMarketMapLabel({
    required this.level,
    this.title = '',
    this.titleSize = 0,
    this.changeSize = 0,
    this.iconSize = 0,
  });

  static const none = HlMarketMapLabel(level: HlMarketMapLabelLevel.none);

  final HlMarketMapLabelLevel level;
  final String title;
  final double titleSize;
  final double changeSize;
  final double iconSize;
}

/// The size [text] takes at [fontSize] and [weight], on one line.
typedef HlMarketMapMeasure = Size Function(
    String text, double fontSize, FontWeight weight);

/// The ticker a tile shows: the market's symbol, a Unit-bridged token as
/// the asset it holds (UBTC: BTC).
String hlMarketMapTicker(HlMarket m) =>
    m.isSpot && m.unitAssetName != null && m.coin.length > 1
        ? m.coin.substring(1)
        : m.coin;

/// The short names the map falls back to where an index's or a
/// commodity's full name does not fit (Brent oil: Brent), the names the
/// trade itself uses.
const Map<String, String> _kHlMapShortNames = {
  'BRENTOIL': 'Brent',
  'CL': 'WTI',
  'NATGAS': 'Nat gas',
  'XYZ100': 'Nasdaq',
};

/// The titles a tile may show, the first that fits: an index's or a
/// commodity's name (Nasdaq 100, Brent oil), then its short name
/// (Nasdaq, Brent), before its ticker.
List<String> hlMarketMapTitles(HlMarket m, HlMarketMapGroup group) {
  final ticker = hlMarketMapTicker(m);
  final named = group == HlMarketMapGroup.indices ||
      group == HlMarketMapGroup.commodities;
  final titles = <String>[
    if (named) ...[
      if (hlFriendlyName(m.coin) case final name?) name,
      if (_kHlMapShortNames[m.coin] case final short?) short,
    ],
    ticker,
  ];
  return [
    for (var i = 0; i < titles.length; i++)
      if (titles.indexOf(titles[i]) == i) titles[i],
  ];
}

/// The label a tile of [rect] can carry, measured with [measure] (at the
/// viewer's text size): the logo, a title and the change when all three
/// fit, else the title over the change, else the title alone, else none.
/// Each level tries the [titles] in turn and a smaller face before giving
/// up; the change is measured at its widest ([_kChangeTemplate]).
HlMarketMapLabel hlMarketMapLabelFor(
    Rect rect, List<String> titles, HlMarketMapMeasure measure) {
  final w = rect.width - _kTileGap - _kLabelPad * 2;
  final h = rect.height - _kTileGap - _kLabelPad * 2;
  final side = math.min(rect.width, rect.height);
  if (w <= 0 || h <= 0 || titles.isEmpty) return HlMarketMapLabel.none;

  // The big tiles: logo, title, change.
  if (side >= 64) {
    final icon = (side * 0.24).clamp(18.0, 30.0);
    for (final title in titles) {
      for (var size = (side * 0.16).clamp(12.0, 18.0); size >= 12; size -= 1) {
        final change = math.max(10.0, size * 0.8);
        final t = measure(title, size, FontWeight.w700);
        final c = measure(_kChangeTemplate, change, FontWeight.w600);
        if (math.max(t.width, c.width) <= w &&
            icon + 4 + t.height + 1 + c.height <= h) {
          return HlMarketMapLabel(
            level: HlMarketMapLabelLevel.logo,
            title: title,
            titleSize: size,
            changeSize: change,
            iconSize: icon,
          );
        }
      }
    }
  }
  // The middle ones: title over change.
  for (final title in titles) {
    for (var size = (side * 0.26).clamp(9.0, 14.0); size >= 9; size -= 0.5) {
      final change = math.max(8.0, size * 0.86);
      final t = measure(title, size, FontWeight.w700);
      final c = measure(_kChangeTemplate, change, FontWeight.w600);
      if (math.max(t.width, c.width) <= w && t.height + 1 + c.height <= h) {
        return HlMarketMapLabel(
          level: HlMarketMapLabelLevel.tickerChange,
          title: title,
          titleSize: size,
          changeSize: change,
        );
      }
    }
  }
  // The small ones: the title alone, closer to the edges and down to the
  // smallest face.
  final tw = rect.width - _kTileGap - _kTightPad * 2;
  final th = rect.height - _kTileGap - _kTightPad * 2;
  for (final title in titles) {
    for (var size = (side * 0.3).clamp(8.0, 13.0); size >= 8; size -= 0.5) {
      final t = measure(title, size, FontWeight.w700);
      if (t.width <= tw && t.height <= th) {
        return HlMarketMapLabel(
          level: HlMarketMapLabelLevel.ticker,
          title: title,
          titleSize: size,
        );
      }
    }
  }
  return HlMarketMapLabel.none;
}

/// The vertical stack a label takes in its tile: where the logo, the
/// title and the change go, centred.
({Rect icon, Offset title, Offset change}) _labelPlacement(
    Rect tile, HlMarketMapLabel label, Size title, Size change) {
  final icon = label.level == HlMarketMapLabelLevel.logo ? label.iconSize : 0.0;
  final hasChange = label.level == HlMarketMapLabelLevel.logo ||
      label.level == HlMarketMapLabelLevel.tickerChange;
  final height = icon +
      (icon > 0 ? 4 : 0) +
      title.height +
      (hasChange ? 1 + change.height : 0);
  final top = tile.center.dy - height / 2;
  final cx = tile.center.dx;
  return (
    icon: Rect.fromLTWH(cx - icon / 2, top, icon, icon),
    title: Offset(cx - title.width / 2, top + icon + (icon > 0 ? 4 : 0)),
    change: Offset(cx - change.width / 2,
        top + icon + (icon > 0 ? 4 : 0) + title.height + 1),
  );
}

// ─────────────────────────────── text ────────────────────────────────

/// Laid-out text for the painter, kept between frames (the tickers never
/// change, the changes repeat), bounded.
class HlMarketMapText {
  HlMarketMapText({this.scale = 1}) : scaler = TextScaler.linear(scale);

  /// The viewer's text size, which every label is set and measured at.
  final double scale;
  final TextScaler scaler;

  final Map<(String, double, FontWeight, int), TextPainter> _cache = {};

  TextPainter painter(
      String text, double size, FontWeight weight, Color color) {
    if (_cache.length > 400) {
      for (final p in _cache.values) {
        p.dispose();
      }
      _cache.clear();
    }
    return _cache.putIfAbsent(
      (text, size, weight, color.toARGB32()),
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: color,
            fontSize: scaler.scale(size),
            fontWeight: weight,
            letterSpacing: -0.2,
            height: 1.15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
    );
  }

  Size measure(String text, double size, FontWeight weight) =>
      painter(text, size, weight, Colors.white).size;

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

// ─────────────────────────────── painter ──────────────────────────────

/// Draws the map: each block's label, then its tiles in their colours
/// with their labels. The logos are widgets laid over it.
class HlMarketMapPainter extends CustomPainter {
  HlMarketMapPainter({
    required this.layout,
    required this.markets,
    required this.labels,
    required this.mids,
    required this.dark,
    required this.text,
    required this.groupLabel,
    required this.groupLabelColor,
    this.pressed,
    this.onOpen,
  });

  final HlMarketMapLayout layout;

  /// The tiles' markets, by key (the latest snapshot of each).
  final Map<String, HlMarket> markets;
  final Map<String, HlMarketMapLabel> labels;

  /// The live mids, by display coin.
  final Map<String, double> mids;
  final bool dark;
  final HlMarketMapText text;
  final String Function(HlMarketMapGroup group) groupLabel;
  final Color groupLabelColor;

  /// The tile under the finger.
  final String? pressed;

  /// Opens a tile's market (assistive tech's tap).
  final void Function(String id)? onOpen;

  /// [m]'s 24 h change at its live price, as the row reads it.
  double? changeOf(HlMarket m) {
    final mid = mids[m.coin];
    return m.dayChangeAtOrNull(mid ?? (m.midPx > 0 ? m.midPx : m.markPx));
  }

  /// The fill of the tile [id] at the live price.
  Color fillOf(String id) {
    final m = markets[id];
    return hlMarketMapFill(m == null ? null : changeOf(m), dark: dark);
  }

  String _changeText(double? change) =>
      change == null ? '—' : hlArrowPct(change);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (final block in layout.blocks) {
      final header = block.header;
      if (header != null) {
        final room = math.max(0.0, header.width - _kBlockGap - 4);
        TextPainter label(double size) => TextPainter(
              text: TextSpan(
                text: groupLabel(block.group),
                style: TextStyle(
                  fontFamily: kuteChartFontFamily,
                  color: groupLabelColor,
                  fontSize: text.scaler.scale(size),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              ellipsis: '…',
            )..layout(maxWidth: room);
        var tp = label(11);
        for (var size = 10.5; tp.didExceedMaxLines && size >= 9; size -= 0.5) {
          tp.dispose();
          tp = label(size);
        }
        if (tp.height <= header.height) {
          tp.paint(
              canvas,
              Offset(header.left + _kBlockGap / 2 + 2,
                  header.center.dy - tp.height / 2));
        }
        tp.dispose();
      }
      for (final tile in block.tiles) {
        final m = markets[tile.id];
        if (m == null) continue;
        final change = changeOf(m);
        var fill = hlMarketMapFill(change, dark: dark);
        if (tile.id == pressed) {
          fill = Color.alphaBlend(Colors.black.withValues(alpha: 0.14), fill);
        }
        final r = _tileRect(tile.rect);
        if (r.isEmpty) continue;
        final radius = math.min(4.0, r.shortestSide * 0.2);
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)),
            paint..color = fill);

        final label = labels[tile.id] ?? HlMarketMapLabel.none;
        if (label.level == HlMarketMapLabelLevel.none) continue;
        final ink = hlMarketMapInk(fill);
        final title =
            text.painter(label.title, label.titleSize, FontWeight.w700, ink);
        final hasChange = label.level != HlMarketMapLabelLevel.ticker;
        final changeTp = hasChange
            ? text.painter(_changeText(change), label.changeSize,
                FontWeight.w600, ink.withValues(alpha: 0.86))
            : null;
        final at =
            _labelPlacement(r, label, title.size, changeTp?.size ?? Size.zero);
        title.paint(canvas, at.title);
        if (changeTp != null) {
          // A change past two figures (▲ 120.0%) is wider than the label
          // was measured for: it is drawn smaller rather than clipped.
          final room = r.width - _kLabelPad * 2;
          if (changeTp.width > room && changeTp.width > 0) {
            final s = room / changeTp.width;
            canvas.save();
            canvas.translate(r.center.dx, at.change.dy);
            canvas.scale(s, s);
            changeTp.paint(canvas, Offset(-changeTp.width / 2, 0));
            canvas.restore();
          } else {
            changeTp.paint(canvas, at.change);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(HlMarketMapPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      !identical(oldDelegate.markets, markets) ||
      !identical(oldDelegate.labels, labels) ||
      !identical(oldDelegate.mids, mids) ||
      oldDelegate.dark != dark ||
      oldDelegate.pressed != pressed ||
      oldDelegate.groupLabelColor != groupLabelColor;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
        for (final tile in layout.tiles)
          if (markets[tile.id] != null)
            CustomPainterSemantics(
              key: ValueKey('hl-map-${tile.id}'),
              rect: tile.rect,
              properties: SemanticsProperties(
                label: '${_spokenName(markets[tile.id]!)}, '
                    '${_changeText(changeOf(markets[tile.id]!))}',
                textDirection: TextDirection.ltr,
                button: true,
                onTap: onOpen == null ? null : () => onOpen!(tile.id),
              ),
            ),
      ];

  @override
  bool shouldRebuildSemantics(HlMarketMapPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      !identical(oldDelegate.markets, markets) ||
      !identical(oldDelegate.mids, mids);
}

/// What assistive tech calls a tile's market: the list row's name.
String _spokenName(HlMarket m) =>
    hlFriendlyName(m.coin) ?? m.unitAssetName ?? hlMarketMapTicker(m);

/// A tile's drawn rectangle: its cell less half the gap on every side.
Rect _tileRect(Rect cell) {
  final r = cell.deflate(_kTileGap / 2);
  return r.width <= 0 || r.height <= 0 ? Rect.zero : r;
}

// ─────────────────────────────── the card ─────────────────────────────

/// The market map card (see the file header): "Market map" and the
/// window over the map of [universe]. [loading] while the builder
/// markets are still to be read, a skeleton in the map's shape (the
/// card's height, so nothing moves when the map lands); nothing at all
/// with under [kHlMarketMapMinTiles] markets to show, until it has been
/// shown.
class HlMarketMapCard extends ConsumerStatefulWidget {
  const HlMarketMapCard({
    super.key,
    required this.universe,
    this.loading = false,
    this.onTap,
  });

  final List<HlMarket> universe;
  final bool loading;

  /// Account-scoped callers supply their own navigation. The default
  /// opens the spending account's market sheet, as a list row does.
  final void Function(HlMarket market)? onTap;

  @override
  ConsumerState<HlMarketMapCard> createState() => _HlMarketMapCardState();
}

class _HlMarketMapCardState extends ConsumerState<HlMarketMapCard> {
  List<HlMarket>? _entriesFor;
  List<HlMarketMapEntry> _entries = const [];
  Map<String, HlMarket> _markets = const {};
  Map<String, HlMarketMapGroup> _groups = const {};

  HlMarketMapLayout? _layout;
  Map<String, HlMarketMapLabel> _labels = const {};
  HlMarketMapLayout? _labelledFor;

  HlMarketMapText? _text;
  String? _pressed;
  Set<String> _watched = const {};

  /// Whether the map has been on screen in this mount.
  bool _shown = false;

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  /// The map's markets, once per universe (a 30 s refresh), keeping the
  /// markets on screen while they still rank ([hlMarketMapEntries]).
  void _syncEntries() {
    if (identical(_entriesFor, widget.universe)) return;
    _entriesFor = widget.universe;
    _entries = hlMarketMapEntries(widget.universe,
        previous: {for (final e in _entries) e.id});
    _markets = {for (final e in _entries) e.id: e.market};
    _groups = {for (final e in _entries) e.id: e.group};
    _watchCoins();
  }

  /// Registers the tiles' coins with the live prices (additive; the
  /// screen releases the socket).
  void _watchCoins() {
    final ids = _markets.keys.toSet();
    if (ids.length == _watched.length && ids.containsAll(_watched)) return;
    _watched = ids;
    final markets = _markets.values.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || markets.isEmpty) return;
      ref.read(hyperliquidLivePricesProvider.notifier).watchCoins(
        [for (final m in markets) m.coin],
        wire: {for (final m in markets) m.coin: m.wireCoin},
      );
    });
  }

  HlMarketMapLayout _layoutFor(Size size) {
    final held = _layout;
    if (held != null && held.fits(_entries, size)) return held;
    return _layout = HlMarketMapLayout.compute(_entries, size);
  }

  HlMarketMapText _textFor(double scale) {
    final held = _text;
    if (held != null && held.scale == scale) return held;
    held?.dispose();
    _labelledFor = null;
    return _text = HlMarketMapText(scale: scale);
  }

  Map<String, HlMarketMapLabel> _labelsFor(
      HlMarketMapLayout layout, HlMarketMapText text) {
    if (identical(_labelledFor, layout)) return _labels;
    _labelledFor = layout;
    final labels = <String, HlMarketMapLabel>{};
    final big = <HlMarket>[];
    for (final tile in layout.tiles) {
      final m = _markets[tile.id];
      if (m == null) continue;
      final label = hlMarketMapLabelFor(
          tile.rect, hlMarketMapTitles(m, _groups[tile.id]!), text.measure);
      labels[tile.id] = label;
      if (label.level == HlMarketMapLabelLevel.logo) big.add(m);
    }
    // The big tiles' logos, disk first, so they draw on the first frame.
    if (big.isNotEmpty) unawaited(HlIconPrefetch.prefetch(big));
    return _labels = labels;
  }

  void _open(String id) {
    final m = _markets[id];
    if (m == null) return;
    HapticFeedback.mediumImpact();
    final tap = widget.onTap;
    if (tap != null) {
      tap(m);
    } else {
      // hyperliquid_market_viewed fires once, from the sheet, with the
      // map as its entry source.
      HlMarketDetailSheet.show(context, market: m, source: kHlMarketMapSource);
    }
  }

  void _press(String? id) {
    if (_pressed != id) setState(() => _pressed = id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.loading) return const _HlMarketMapSkeleton();
    _syncEntries();
    // Shown from [kHlMarketMapMinTiles] markets; once on screen it stays
    // while it has one, so a short re-read never takes the card's height
    // from under a list scrolled past it.
    if (_entries.length < (_shown ? 1 : kHlMarketMapMinTiles)) {
      return const SizedBox.shrink();
    }
    _shown = true;

    // The viewer's text size, up to 1.3 (a bigger one leaves fewer
    // labels, never clipped ones).
    final scale =
        (MediaQuery.textScalerOf(context).scale(100) / 100).clamp(1.0, 1.3);
    return _HlMarketMapFrame(
      key: const ValueKey('hl-market-map'),
      map: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final size = Size(width, (width * kHlMarketMapAspect).roundToDouble());
        final layout = _layoutFor(size);
        final text = _textFor(scale);
        final labels = _labelsFor(layout, text);
        final dark = context.isDark;
        final c = context.colors;
        return Consumer(builder: (context, ref, _) {
          // Repaints only when one of the tiles' own mids moves.
          final coins = [for (final m in _markets.values) m.coin];
          ref.watch(hyperliquidLivePricesProvider.select(
              (s) => Object.hashAll([for (final k in coins) s.mids[k]])));
          final mids = ref.read(hyperliquidLivePricesProvider).mids;
          final painter = HlMarketMapPainter(
            layout: layout,
            markets: _markets,
            labels: labels,
            mids: mids,
            dark: dark,
            text: text,
            groupLabel: (g) => g.label(l10n),
            groupLabelColor: c.textSecondary,
            pressed: _pressed,
            onOpen: _open,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _press(layout.tileAt(d.localPosition)?.id),
            onTapCancel: () => _press(null),
            onTapUp: (d) {
              _press(null);
              final tile = layout.tileAt(d.localPosition);
              if (tile != null) _open(tile.id);
            },
            child: RepaintBoundary(
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: painter)),
                    // The logos: the one widget a tile gets, on the big
                    // tiles only.
                    for (final tile in layout.tiles)
                      if (labels[tile.id]?.level == HlMarketMapLabelLevel.logo)
                        _logo(tile, labels[tile.id]!, text),
                  ],
                ),
              ),
            ),
          );
        });
      }),
    );
  }

  Widget _logo(
      HlMarketMapTile tile, HlMarketMapLabel label, HlMarketMapText text) {
    final m = _markets[tile.id]!;
    final r = _tileRect(tile.rect);
    final title = text.measure(label.title, label.titleSize, FontWeight.w700);
    final change =
        text.measure(_kChangeTemplate, label.changeSize, FontWeight.w600);
    final at = _labelPlacement(r, label, title, change);
    return Positioned.fromRect(
      key: ValueKey('hl-map-logo-${tile.id}'),
      rect: at.icon,
      child: IgnorePointer(
        child: ClipOval(
          child: HlCoinIcon(
            coin: m.coin,
            wireCoin: m.wireCoin,
            category: m.category,
            iconUrl: m.iconUrl,
            size: label.iconSize,
          ),
        ),
      ),
    );
  }
}

/// The card around the map: the grouped card's ground and [map], with no
/// title (founder, 6 November 2026: "don't call it market map, just have
/// the card there").
class _HlMarketMapFrame extends StatelessWidget {
  const _HlMarketMapFrame({super.key, required this.map});

  final Widget map;

  @override
  Widget build(BuildContext context) {
    return PremiumGroupContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(10.w),
            child: map,
          ),
        ],
      ),
    );
  }
}

/// The map loading: the card with bones laid as a small treemap.
class _HlMarketMapSkeleton extends StatelessWidget {
  const _HlMarketMapSkeleton();

  static const _weights = [5.0, 3.0, 2.5, 2.0, 1.5, 1.2, 1.0, 0.8];

  @override
  Widget build(BuildContext context) {
    return _HlMarketMapFrame(
      key: const ValueKey('hl-market-map-loading'),
      map: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final size = Size(width, (width * kHlMarketMapAspect).roundToDouble());
        final cells = squarify(_weights, Offset.zero & size);
        return KuteSkeleton(
          child: SizedBox.fromSize(
            size: size,
            child: Stack(children: [
              for (final cell in cells)
                Positioned.fromRect(
                  rect: _tileRect(cell),
                  child: SkeletonBar(
                      _tileRect(cell).width, _tileRect(cell).height,
                      radius: 4),
                ),
            ]),
          ),
        );
      }),
    );
  }
}
