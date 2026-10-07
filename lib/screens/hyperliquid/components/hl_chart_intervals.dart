// lib/screens/hyperliquid/components/hl_chart_intervals.dart
//
// The Hyperliquid chart "layout", TradingView style: ONE chart style and
// ONE candle interval for every Hyperliquid market (hot wallet and Ledger
// sheets alike). Changing the symbol keeps both, as TradingView keeps the
// layout's chart type and interval when you switch symbol.
//
//   * [kHlCandleIntervals]: the interval row every style shows (1m 5m 15m
//     1h 4h 1D 1W), all intervals Hyperliquid's candleSnapshot serves.
//     The style only changes how each bar is drawn; line, area and
//     baseline draw its close.
//   * [hlChartLayoutProvider]: the saved choice, read synchronously from
//     the 'settings' Hive box (opened at app start) so the very first
//     frame of a chart already shows it. Older builds kept a style per
//     market and a candle size in its own box; the first read migrates
//     the style the user had picked (else candles) and that candle size
//     (else 1h).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

typedef HlCandleInterval = ({String label, String interval, int minutes});

const List<HlCandleInterval> kHlCandleIntervals = [
  (label: '1m', interval: '1m', minutes: 1),
  (label: '5m', interval: '5m', minutes: 5),
  (label: '15m', interval: '15m', minutes: 15),
  (label: '1h', interval: '1h', minutes: 60),
  (label: '4h', interval: '4h', minutes: 240),
  (label: '1D', interval: '1d', minutes: 1440),
  (label: '1W', interval: '1w', minutes: 10080),
];

const String kHlDefaultChartStyle = 'candles';
const String kHlDefaultCandleInterval = '1h';

/// Every style the chart draws (HlChartStyle names).
const Set<String> kHlChartStyles = {
  'candles',
  'hollow',
  'bars',
  'heikinAshi',
  'line',
  'area',
  'baseline',
};

/// Bars the live seed asks for: enough to open on ~100 bars with room to
/// pan before the first older page is needed.
const int kHlCandleSeedBars = 240;

HlCandleInterval hlCandleInterval(String interval) {
  for (final iv in kHlCandleIntervals) {
    if (iv.interval == interval) return iv;
  }
  return kHlCandleIntervals[3];
}

/// Trailing window (hours) that holds [kHlCandleSeedBars] bars.
int hlCandleWindowHours(HlCandleInterval iv) =>
    math.max(1, (kHlCandleSeedBars * iv.minutes / 60).ceil());

/// Every interval candleSnapshot serves, by bucket length.
const Map<int, String> _intervalByMinutes = {
  1: '1m',
  3: '3m',
  5: '5m',
  15: '15m',
  30: '30m',
  60: '1h',
  120: '2h',
  240: '4h',
  480: '8h',
  720: '12h',
  1440: '1d',
  4320: '3d',
  10080: '1w',
};

/// The Hyperliquid interval a bar belongs to, read from its own open and
/// close times (the venue closes a bucket 1ms before the next opens).
String? hlIntervalOfBar(DateTime openTime, DateTime closeTime) {
  final ms = closeTime.difference(openTime).inMilliseconds + 1;
  final minutes = (ms / 60000).round();
  return _intervalByMinutes[minutes];
}

int hlIntervalMinutes(String interval) {
  for (final e in _intervalByMinutes.entries) {
    if (e.value == interval) return e.key;
  }
  return 60;
}

/// The global chart layout: style + candle interval.
class HlChartLayout {
  const HlChartLayout({
    this.style = kHlDefaultChartStyle,
    this.interval = kHlDefaultCandleInterval,
  });

  /// HlChartStyle name.
  final String style;

  /// Hyperliquid interval string ('1m' … '1w').
  final String interval;

  HlChartLayout copyWith({String? style, String? interval}) => HlChartLayout(
        style: style ?? this.style,
        interval: interval ?? this.interval,
      );
}

class HlChartLayoutNotifier extends Notifier<HlChartLayout> {
  static const String _box = 'settings';
  static const String _styleKey = 'hlChartLayoutStyle';
  static const String _intervalKey = 'hlChartLayoutInterval';

  static bool _isInterval(Object? v) =>
      v is String && kHlCandleIntervals.any((iv) => iv.interval == v);
  static bool _isStyle(Object? v) => v is String && kHlChartStyles.contains(v);

  bool _touched = false;

  @override
  HlChartLayout build() {
    // Synchronous: the settings box is opened during app start, so the
    // first chart frame already has the saved layout (no default flash).
    try {
      if (Hive.isBoxOpen(_box)) {
        final box = Hive.box(_box);
        final style = box.get(_styleKey);
        final interval = box.get(_intervalKey);
        if (_isStyle(style) && _isInterval(interval)) {
          return HlChartLayout(
              style: style as String, interval: interval as String);
        }
      }
    } catch (_) {
      // Fall through to the migration and defaults.
    }
    unawaited(_migrate());
    return const HlChartLayout();
  }

  /// First run of the global layout: carry over what older builds saved
  /// (a style per market, the last candle size), then persist it so this
  /// runs once.
  Future<void> _migrate() async {
    String? style;
    String? interval;
    try {
      final prefs = await Hive.openBox<String>('hl_chart_preferences');
      for (final encoded in prefs.values) {
        final raw = jsonDecode(encoded);
        if (raw is! Map) continue;
        final s = raw['style'];
        // 'area' was the untouched default; anything else was picked.
        if (_isStyle(s) && s != 'area') {
          style = s as String;
          break;
        }
      }
    } catch (_) {}
    try {
      final box = await Hive.openBox<String>('hl_chart_candle_interval');
      final last = box.get('last');
      if (_isInterval(last)) interval = last;
    } catch (_) {}
    // A choice made while this ran wins over the old saved one.
    final next =
        _touched ? state : state.copyWith(style: style, interval: interval);
    state = next;
    await _save(next);
  }

  Future<void> _save(HlChartLayout layout) async {
    try {
      final box = await Hive.openBox(_box);
      await box.put(_styleKey, layout.style);
      await box.put(_intervalKey, layout.interval);
    } catch (_) {
      // The chart works without a saved layout.
    }
  }

  void setStyle(String style) {
    if (!_isStyle(style) || style == state.style) return;
    _touched = true;
    state = state.copyWith(style: style);
    unawaited(_save(state));
  }

  void setInterval(String interval) {
    if (!_isInterval(interval) || interval == state.interval) return;
    _touched = true;
    state = state.copyWith(interval: interval);
    unawaited(_save(state));
  }
}

/// The one chart layout every Hyperliquid chart uses.
final hlChartLayoutProvider =
    NotifierProvider<HlChartLayoutNotifier, HlChartLayout>(
        HlChartLayoutNotifier.new);
