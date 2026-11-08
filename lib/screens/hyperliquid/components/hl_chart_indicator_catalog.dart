// lib/screens/hyperliquid/components/hl_chart_indicator_catalog.dart
//
// The Hyperliquid chart's curated indicators (founder, 4 November 2026:
// "advanced charts is not overall just adding lots of features"): the
// fifteen a perp trader actually reaches for on TradingView, Hyperliquid
// or Binance, each with TradingView's default settings, grouped as the
// Chart sheet shows them:
//
//   Trend       EMA 9/21 · SMA 50/200 · VWAP (anchored) · Supertrend 10/3
//               · Ichimoku 9/26/52/26 · Pivots (standard, daily)
//   Momentum    RSI 14 · MACD 12/26/9 · Stoch RSI 14/14/3/3 · ADX 14/14
//   Volatility  Bollinger bands 20/2 · ATR 14
//   Volume      Volume · OBV · Volume profile (visible range, 24 rows)
//
// Lines on the price: at most [kHlMaxPriceIndicators]; panes below it:
// at most [kHlMaxPanes] (Volume sits inside the price plot and counts as
// neither). Switching on one too many turns the oldest of its kind off.
// Settings are per market, stored only where they differ from the
// defaults, and clamped to sane ranges.

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;

/// The Chart sheet's indicator groups, in order.
enum HlIndGroup { trend, momentum, volatility, volume }

/// Where an indicator draws.
enum HlIndPlace {
  /// On the price, in its colours.
  price,

  /// In its own pane under the chart.
  pane,

  /// Volume's band at the foot of the price plot.
  volumeBand,
}

/// One setting of an indicator: a length, a multiplier, a row count.
class HlIndParam {
  const HlIndParam(
    this.id,
    this.defaultValue,
    this.min,
    this.max, {
    this.step = 1,
  });

  /// What it is (the settings sheet names it): 'length', 'fast', 'slow',
  /// 'signal', 'multiplier', 'rsiLength', 'stochLength', 'smoothK',
  /// 'smoothD', 'rows', 'smoothing', 'conversion', 'base', 'spanB',
  /// 'displacement'.
  final String id;
  final num defaultValue;
  final num min, max, step;

  bool get isInt => step is int && defaultValue is int;

  /// [v] on this setting's grid, inside its range.
  num clamp(num v) {
    if (!v.isFinite) return defaultValue;
    final c = v.clamp(min, max);
    final snapped = min + ((c - min) / step).round() * step;
    final bounded = snapped > max ? snapped - step : snapped;
    if (isInt) return bounded.round();
    return double.parse(bounded.toStringAsFixed(4));
  }
}

class HlIndSpec {
  const HlIndSpec({
    required this.key,
    required this.group,
    required this.place,
    required this.short,
    required this.colors,
    this.params = const [],
  });

  /// The stored key (ChartPreferences.indicators).
  final String key;
  final HlIndGroup group;
  final HlIndPlace place;

  /// Its trader's name, the same in every language ("RSI", "MACD").
  final String short;

  /// Its lines' colours, in the order it draws them.
  final List<Color> colors;
  final List<HlIndParam> params;

  List<num> get defaults => [for (final p in params) p.defaultValue];
}

// The palette (works on both themes): the shared chart indicator colours
// (kute_chart_indicators.dart) and a few more.
const Color kHlIndBlue = Color(0xFF3B82F6);
const Color kHlIndPurple = Color(0xFFA855F7);
const Color kHlIndAmber = Color(0xFFF59E0B);
const Color kHlIndOrange = Color(0xFFEA580C);
const Color kHlIndTeal = Color(0xFF14B8A6);
const Color kHlIndSlate = Color(0xFF94A3B8);
const Color kHlIndPink = Color(0xFFEC4899);
// Supertrend's two sides are the market's up and down colours, given by
// the chart (AppColors.marketUp / marketDown).

const List<HlIndSpec> kHlIndicatorCatalog = [
  // ── Trend ──
  HlIndSpec(
    key: 'ema',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'EMA',
    colors: [kHlIndBlue, kHlIndPurple],
    params: [HlIndParam('fast', 9, 2, 200), HlIndParam('slow', 21, 2, 400)],
  ),
  HlIndSpec(
    key: 'ma',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'SMA',
    colors: [kHlIndAmber, kHlIndOrange],
    params: [HlIndParam('fast', 50, 2, 400), HlIndParam('slow', 200, 2, 400)],
  ),
  HlIndSpec(
    key: 'vwap',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'VWAP',
    colors: [kHlIndTeal],
  ),
  HlIndSpec(
    key: 'st',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'Supertrend',
    colors: [],
    params: [
      HlIndParam('length', 10, 1, 100),
      HlIndParam('multiplier', 3.0, 0.5, 10.0, step: 0.5),
    ],
  ),
  // Its five lines: conversion, base, span A, span B and lagging; the
  // cloud between the spans is the market's up and down colours, softly.
  HlIndSpec(
    key: 'ichi',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'Ichimoku',
    colors: [kHlIndBlue, kHlIndOrange, kHlIndTeal, kHlIndPink, kHlIndSlate],
    params: [
      HlIndParam('conversion', 9, 1, 100),
      HlIndParam('base', 26, 1, 200),
      HlIndParam('spanB', 52, 1, 400),
      HlIndParam('displacement', 26, 1, 100),
    ],
  ),
  // Levels with the day's trend: in Trend, not a group of their own (one
  // card alone under a heading), and read from the real daily candles.
  HlIndSpec(
    key: 'pp',
    group: HlIndGroup.trend,
    place: HlIndPlace.price,
    short: 'Pivots',
    colors: [kHlIndAmber, kHlIndSlate],
  ),
  // ── Momentum ──
  HlIndSpec(
    key: 'rsi',
    group: HlIndGroup.momentum,
    place: HlIndPlace.pane,
    short: 'RSI',
    colors: [kHlIndPurple],
    params: [HlIndParam('length', 14, 2, 100)],
  ),
  HlIndSpec(
    key: 'macd',
    group: HlIndGroup.momentum,
    place: HlIndPlace.pane,
    short: 'MACD',
    colors: [kHlIndBlue, kHlIndOrange],
    params: [
      HlIndParam('fast', 12, 2, 100),
      HlIndParam('slow', 26, 2, 200),
      HlIndParam('signal', 9, 2, 50),
    ],
  ),
  HlIndSpec(
    key: 'srsi',
    group: HlIndGroup.momentum,
    place: HlIndPlace.pane,
    short: 'Stoch RSI',
    colors: [kHlIndBlue, kHlIndOrange],
    params: [
      HlIndParam('rsiLength', 14, 2, 100),
      HlIndParam('stochLength', 14, 2, 100),
      HlIndParam('smoothK', 3, 1, 20),
      HlIndParam('smoothD', 3, 1, 20),
    ],
  ),
  HlIndSpec(
    key: 'adx',
    group: HlIndGroup.momentum,
    place: HlIndPlace.pane,
    short: 'ADX',
    colors: [kHlIndPurple, kHlIndBlue, kHlIndOrange],
    params: [
      HlIndParam('length', 14, 2, 100),
      HlIndParam('smoothing', 14, 1, 100),
    ],
  ),
  // ── Volatility ──
  HlIndSpec(
    key: 'bb',
    group: HlIndGroup.volatility,
    place: HlIndPlace.price,
    short: 'BB',
    colors: [kHlIndSlate],
    params: [
      HlIndParam('length', 20, 2, 200),
      HlIndParam('multiplier', 2.0, 0.5, 5.0, step: 0.5),
    ],
  ),
  HlIndSpec(
    key: 'atr',
    group: HlIndGroup.volatility,
    place: HlIndPlace.pane,
    short: 'ATR',
    colors: [kHlIndPink],
    params: [HlIndParam('length', 14, 1, 100)],
  ),
  // ── Volume ──
  HlIndSpec(
    key: 'vol',
    group: HlIndGroup.volume,
    place: HlIndPlace.volumeBand,
    short: 'Vol',
    colors: [],
  ),
  HlIndSpec(
    key: 'obv',
    group: HlIndGroup.volume,
    place: HlIndPlace.pane,
    short: 'OBV',
    colors: [kHlIndBlue],
  ),
  HlIndSpec(
    key: 'vp',
    group: HlIndGroup.volume,
    place: HlIndPlace.price,
    short: 'VP',
    colors: [kHlIndAmber],
    params: [HlIndParam('rows', 24, 8, 60, step: 4)],
  ),
];

/// Every indicator key the chart knows.
final Set<String> kHlIndicatorKeys = {
  for (final s in kHlIndicatorCatalog) s.key,
};

/// Lines on the price at once (Volume profile counts; Volume does not).
const int kHlMaxPriceIndicators = 4;

/// Panes below the chart at once.
const int kHlMaxPanes = 2;

/// What a fresh chart shows.
const Set<String> kHlDefaultIndicators = {'vol'};

HlIndSpec? hlIndSpec(String key) {
  for (final s in kHlIndicatorCatalog) {
    if (s.key == key) return s;
  }
  return null;
}

/// [key]'s settings: [stored] where it holds a usable value for each, its
/// defaults otherwise, every one inside its range.
List<num> hlIndParams(String key, Map<String, List<num>> stored) {
  final spec = hlIndSpec(key);
  if (spec == null) return const [];
  final s = stored[key];
  return [
    for (var i = 0; i < spec.params.length; i++)
      spec.params[i].clamp(
          s != null && i < s.length ? s[i] : spec.params[i].defaultValue),
  ];
}

/// A setting as the legend writes it: "3", "2.5".
String hlParamText(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// The legend's / pane's title: "RSI 14", "MACD 12 26 9", "VWAP".
String hlIndTitle(String key, List<num> params) {
  final spec = hlIndSpec(key);
  if (spec == null) return key;
  return [spec.short, for (final p in params) hlParamText(p)].join(' ');
}

/// Switching [key] in [current] (its order is the order they were
/// switched on: the oldest first). Switching on one more than fits on the
/// price ([kHlMaxPriceIndicators]) or below it ([kHlMaxPanes]) turns the
/// oldest of that kind off; [replaced] names it.
({List<String> next, String? replaced}) hlToggleIndicator(
  Iterable<String> current,
  String key,
) {
  final next = [...current];
  if (next.remove(key)) return (next: next, replaced: null);
  String? replaced;
  final place = hlIndSpec(key)?.place;
  final limit = switch (place) {
    HlIndPlace.price => kHlMaxPriceIndicators,
    HlIndPlace.pane => kHlMaxPanes,
    _ => null,
  };
  if (limit != null) {
    final same = next.where((k) => hlIndSpec(k)?.place == place).toList();
    if (same.length >= limit) {
      replaced = same.first;
      next.remove(replaced);
    }
  }
  next.add(key);
  return (next: next, replaced: replaced);
}

/// How many bars before the first one on screen [key] needs for its
/// first value to be settled (its longest look-back; an EMA three times
/// its length, so it has forgotten its seed).
int hlIndWarmup(String key, List<num> p) {
  int at(int i) => i < p.length ? p[i].round() : 0;
  final int longer = math.max<int>(at(0), at(1));
  return switch (key) {
    'ema' => 3 * longer,
    'ma' => longer,
    'st' => 3 * at(0),
    'rsi' => 3 * at(0),
    'macd' => 3 * longer + at(2),
    'srsi' => 3 * at(0) + at(1) + at(2) + at(3),
    'bb' => at(0),
    'atr' => 3 * at(0),
    'ichi' => at(2) + at(3),
    'adx' => 3 * at(0) + 3 * at(1),
    _ => 0,
  };
}
