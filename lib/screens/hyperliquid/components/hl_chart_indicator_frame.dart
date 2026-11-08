// lib/screens/hyperliquid/components/hl_chart_indicator_frame.dart
//
// The active indicators of one chart, computed: what the price painter,
// the legend and the panes under the chart draw. [HlIndicatorComputer]
// keeps each indicator's series until the tape or that indicator's own
// settings change, so switching one on, or scrubbing, recomputes nothing
// else; a live tick (a new tape) recomputes the few that are on, each in
// one pass over the tape. Series are computed over the WHOLE loaded tape
// (a panned view never restarts their warm-up at its left edge) and then
// sliced to the bars on screen ([HlIndicatorFrame.slice]). Ichimoku's
// cloud and Pivots' labels are the two things beyond plain lines and the
// one band; the price painter draws them under and over the lines.

import 'package:flutter/painting.dart' show Color;

import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/shared/charts/kute_chart_indicators.dart'
    show KuteIndicatorBand, KuteIndicatorOverlay;

/// One line an indicator draws, aligned to the bars (nan = no value).
class HlIndLine {
  const HlIndLine(this.values, this.color, {this.label});
  final List<double> values;
  final Color color;

  /// A level's quiet name, written where its newest stretch starts ("R1").
  final String? label;
}

/// Ichimoku's cloud: the fill between its two spans, [up] where span A
/// leads and [down] where span B does. Aligned to the bars.
class HlIndCloud {
  const HlIndCloud({
    required this.spanA,
    required this.spanB,
    required this.up,
    required this.down,
  });
  final List<double> spanA, spanB;
  final Color up, down;
}

/// A level's name to write on the plot, at [value], where its newest
/// stretch on screen starts (bar [start]).
typedef HlIndLevelLabel = ({
  String label,
  double value,
  int start,
  Color color,
});

/// One indicator, computed: its lines (and band, histogram, guide levels
/// and fixed range where it has them) and its title ("RSI 14").
class HlIndSeries {
  const HlIndSeries({
    required this.key,
    required this.title,
    required this.lines,
    this.band,
    this.histogram,
    this.levels = const [],
    this.range,
    this.cloud,
    this.legendLines,
  });

  final String key;
  final String title;
  final List<HlIndLine> lines;
  final KuteIndicatorBand? band;
  final List<double>? histogram;
  final List<double> levels;
  final (double, double)? range;

  /// Ichimoku's fill between its spans.
  final HlIndCloud? cloud;

  /// How many of [lines] the legend writes values for (null: all), so its
  /// one row stays whole: Pivots write P alone (the rest are labelled on
  /// the plot), Ichimoku its conversion and base lines.
  final int? legendLines;

  /// The bars [start, end) of every series.
  HlIndSeries slice(int start, int end) {
    List<double> cut(List<double> v) {
      if (start == 0 && end >= v.length) return v;
      if (start >= v.length) return const [];
      return v.sublist(start, end < v.length ? end : v.length);
    }

    final b = band;
    final h = histogram;
    return HlIndSeries(
      key: key,
      title: title,
      lines: [
        for (final l in lines)
          HlIndLine(cut(l.values), l.color, label: l.label),
      ],
      band: b == null
          ? null
          : KuteIndicatorBand(
              upper: cut(b.upper), lower: cut(b.lower), color: b.color),
      histogram: h == null ? null : cut(h),
      levels: levels,
      range: range,
      cloud: cloud == null
          ? null
          : HlIndCloud(
              spanA: cut(cloud!.spanA),
              spanB: cut(cloud!.spanB),
              up: cloud!.up,
              down: cloud!.down,
            ),
      legendLines: legendLines,
    );
  }

  /// The values the legend writes for bar [index] (the newest bar with a
  /// value when null), each in its line's colour. Supertrend writes the
  /// one side that is drawn there.
  List<(double, Color)> valuesAt(int? index) {
    var at = index;
    if (at == null && key == 'st') {
      // The newest bar either side is drawn on.
      final n = lines.isEmpty ? 0 : lines.first.values.length;
      for (var i = n - 1; i >= 0 && at == null; i--) {
        if (lines.any((l) => i < l.values.length && l.values[i].isFinite)) {
          at = i;
        }
      }
    }
    final out = <(double, Color)>[];
    final shown = legendLines == null ? lines : lines.take(legendLines!);
    for (final l in shown) {
      final v = _at(l.values, at);
      if (v != null) out.add((v, l.color));
    }
    return out;
  }

  static double? _at(List<double> values, int? index) {
    if (index != null) {
      if (index < 0 || index >= values.length) return null;
      final v = values[index];
      return v.isFinite ? v : null;
    }
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i].isFinite) return values[i];
    }
    return null;
  }
}

/// Everything the active indicators draw.
class HlIndicatorFrame {
  const HlIndicatorFrame({
    this.price = const [],
    this.panes = const [],
    this.profileRows,
    this.warmup = 0,
  });

  static const HlIndicatorFrame empty = HlIndicatorFrame();

  /// On the price, in the order they were switched on (Volume profile is
  /// drawn by its own layer from [profileRows] and is not here).
  final List<HlIndSeries> price;

  /// The panes under the chart, in the order they were switched on.
  final List<HlIndSeries> panes;

  /// Volume profile's rows while it is on, else null.
  final int? profileRows;

  /// Bars the indicators want loaded before the first one on screen.
  final int warmup;

  bool get isEmpty => price.isEmpty && panes.isEmpty && profileRows == null;

  /// The price lines as the price painter takes them, at [stroke].
  List<KuteIndicatorOverlay> overlays(double stroke) => [
        for (final s in price)
          for (final l in s.lines)
            KuteIndicatorOverlay(
                values: l.values, color: l.color, strokeWidth: stroke),
      ];

  /// The one band fill (Bollinger's), if on.
  KuteIndicatorBand? get band {
    for (final s in price) {
      if (s.band != null) return s.band;
    }
    return null;
  }

  /// What everything drawn on the price spans: the autoscale takes it in
  /// (a cloud's edges are its span lines). Named levels count their newest
  /// stretch on screen, today's pivots, not every older day's far-off ones
  /// (a flat line leaving the plot looks like nothing being cut).
  /// [loPositive] is the low of the values above zero, all a log axis can
  /// place. Nulls with none.
  ({double? lo, double? loPositive, double? hi}) get priceExtent {
    double? lo, loPositive, hi;
    for (final s in price) {
      for (final l in s.lines) {
        final values = l.label == null ? l.values : _newestStretch(l.values);
        for (final v in values) {
          if (!v.isFinite) continue;
          if (lo == null || v < lo) lo = v;
          if (hi == null || v > hi) hi = v;
          if (v > 0 && (loPositive == null || v < loPositive)) loPositive = v;
        }
      }
    }
    return (lo: lo, loPositive: loPositive, hi: hi);
  }

  /// The one cloud (Ichimoku's), if on.
  HlIndCloud? get cloud {
    for (final s in price) {
      if (s.cloud != null) return s.cloud;
    }
    return null;
  }

  /// The levels to name on the plot: each labelled line at the newest
  /// stretch it draws on screen.
  List<HlIndLevelLabel> get levelLabels {
    final out = <HlIndLevelLabel>[];
    for (final s in price) {
      for (final l in s.lines) {
        final name = l.label;
        if (name == null) continue;
        final v = l.values;
        final (:start, :end) = _stretch(v);
        if (end < 0) continue;
        out.add((label: name, value: v[end], start: start, color: l.color));
      }
    }
    return out;
  }

  /// Where [values]' newest run of values starts and ends; end −1 if none.
  static ({int start, int end}) _stretch(List<double> values) {
    var end = values.length - 1;
    while (end >= 0 && !values[end].isFinite) {
      end--;
    }
    var start = end;
    while (start > 0 && values[start - 1].isFinite) {
      start--;
    }
    return (start: start, end: end);
  }

  static List<double> _newestStretch(List<double> values) {
    final (:start, :end) = _stretch(values);
    return end < 0 ? const [] : values.sublist(start, end + 1);
  }

  HlIndicatorFrame slice(int start, int end) => HlIndicatorFrame(
        price: [for (final s in price) s.slice(start, end)],
        panes: [for (final s in panes) s.slice(start, end)],
        profileRows: profileRows,
        warmup: warmup,
      );
}

/// Computes [HlIndicatorFrame]s for one chart, keeping each indicator's
/// series for as long as the tape (by identity) and its settings hold.
class HlIndicatorComputer {
  List<HyperliquidCandle>? _tape;
  final Map<String, HlIndSeries> _memo = {};

  /// The series for [keys] (in order) over [candles] with [params] (the
  /// stored settings, [hlIndParams]). [up] / [down] colour Supertrend and
  /// Ichimoku's cloud. [daily] are the real daily candles Pivots read
  /// (none yet: no levels).
  HlIndicatorFrame compute(
    List<HyperliquidCandle> candles,
    Iterable<String> keys,
    Map<String, List<num>> params, {
    required Color up,
    required Color down,
    List<HyperliquidCandle> daily = const [],
  }) {
    if (!identical(candles, _tape)) {
      _tape = candles;
      _memo.clear();
    }
    final price = <HlIndSeries>[];
    final panes = <HlIndSeries>[];
    int? rows;
    var warmup = 0;
    final used = <String>{};
    for (final key in keys) {
      final spec = hlIndSpec(key);
      if (spec == null || spec.place == HlIndPlace.volumeBand) continue;
      final p = hlIndParams(key, params);
      final w = hlIndWarmup(key, p);
      if (w > warmup) warmup = w;
      if (key == 'vp') {
        rows = p.first.round();
        continue;
      }
      if (candles.isEmpty) continue;
      final memoKey = '$key|${p.join(',')}|${up.toARGB32()}|${down.toARGB32()}'
          '${key == 'pp' ? '|${identityHashCode(daily)}' : ''}';
      used.add(memoKey);
      final s = _memo.putIfAbsent(
          memoKey, () => _build(spec, p, candles, up, down, daily));
      (spec.place == HlIndPlace.pane ? panes : price).add(s);
    }
    _memo.removeWhere((k, _) => !used.contains(k));
    return HlIndicatorFrame(
      price: price,
      panes: panes,
      profileRows: rows,
      warmup: warmup,
    );
  }

  static HlIndSeries _build(
    HlIndSpec spec,
    List<num> p,
    List<HyperliquidCandle> candles,
    Color up,
    Color down,
    List<HyperliquidCandle> daily,
  ) {
    final title = hlIndTitle(spec.key, p);
    int i(int at) => p[at].round();
    final closes = [for (final k in candles) k.close];
    switch (spec.key) {
      case 'ema':
      case 'ma':
        final avg = spec.key == 'ema' ? hlEma : hlSma;
        return HlIndSeries(key: spec.key, title: title, lines: [
          HlIndLine(avg(closes, i(0)), spec.colors[0]),
          HlIndLine(avg(closes, i(1)), spec.colors[1]),
        ]);
      case 'vwap':
        return HlIndSeries(key: spec.key, title: title, lines: [
          HlIndLine(hlAnchoredVwap(candles), spec.colors[0]),
        ]);
      case 'st':
        final st = hlSupertrend(candles, period: i(0), factor: p[1].toDouble());
        final n = candles.length;
        final ups = List<double>.filled(n, double.nan);
        final downs = List<double>.filled(n, double.nan);
        for (var j = 0; j < n; j++) {
          final side = st.up[j];
          if (side == null) continue;
          (side ? ups : downs)[j] = st.line[j];
        }
        return HlIndSeries(key: spec.key, title: title, lines: [
          HlIndLine(ups, up),
          HlIndLine(downs, down),
        ]);
      case 'ichi':
        final ic = hlIchimoku(candles,
            conversion: i(0), base: i(1), spanB: i(2), displacement: i(3));
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(ic.conversion, spec.colors[0]),
            HlIndLine(ic.base, spec.colors[1]),
            HlIndLine(ic.spanA, up.withValues(alpha: 0.75)),
            HlIndLine(ic.spanB, down.withValues(alpha: 0.75)),
            HlIndLine(ic.lagging, spec.colors[4]),
          ],
          cloud: HlIndCloud(
              spanA: ic.spanA, spanB: ic.spanB, up: up, down: down),
          legendLines: 2,
        );
      case 'pp':
        final d = hlDailyPivots(candles, daily);
        final pivot = spec.colors[0];
        final quiet = spec.colors[1].withValues(alpha: 0.75);
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(d.p, pivot, label: 'P'),
            HlIndLine(d.r1, quiet, label: 'R1'),
            HlIndLine(d.r2, quiet, label: 'R2'),
            HlIndLine(d.r3, quiet, label: 'R3'),
            HlIndLine(d.s1, quiet, label: 'S1'),
            HlIndLine(d.s2, quiet, label: 'S2'),
            HlIndLine(d.s3, quiet, label: 'S3'),
          ],
          legendLines: 1,
        );
      case 'adx':
        final a = hlAdx(candles, length: i(0), smoothing: i(1));
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(a.adx, spec.colors[0]),
            HlIndLine(a.plusDi, spec.colors[1]),
            HlIndLine(a.minusDi, spec.colors[2]),
          ],
        );
      case 'bb':
        final b = hlBollinger(candles, period: i(0), mult: p[1].toDouble());
        final c = spec.colors[0];
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(b.basis, c.withValues(alpha: 0.7)),
            HlIndLine(b.upper, c),
            HlIndLine(b.lower, c),
          ],
          band: KuteIndicatorBand(upper: b.upper, lower: b.lower, color: c),
        );
      case 'rsi':
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [HlIndLine(hlRsi(closes, period: i(0)), spec.colors[0])],
          levels: const [30, 70],
          range: (0, 100),
        );
      case 'macd':
        final m = hlMacd(candles, fast: i(0), slow: i(1), signal: i(2));
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(m.macd, spec.colors[0]),
            HlIndLine(m.signal, spec.colors[1]),
          ],
          histogram: m.histogram,
          levels: const [0],
        );
      case 'srsi':
        final s = hlStochRsi(candles,
            rsiPeriod: i(0), stochPeriod: i(1), smoothK: i(2), smoothD: i(3));
        return HlIndSeries(
          key: spec.key,
          title: title,
          lines: [
            HlIndLine(s.k, spec.colors[0]),
            HlIndLine(s.d, spec.colors[1]),
          ],
          levels: const [20, 80],
          range: (0, 100),
        );
      case 'atr':
        return HlIndSeries(key: spec.key, title: title, lines: [
          HlIndLine(hlAtr(candles, period: i(0)), spec.colors[0]),
        ]);
      case 'obv':
        return HlIndSeries(key: spec.key, title: title, lines: [
          HlIndLine(hlObv(candles), spec.colors[0]),
        ]);
    }
    return HlIndSeries(key: spec.key, title: title, lines: const []);
  }
}
