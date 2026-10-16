// lib/screens/shared/charts/kute_chart_signals.dart
//
// The market-signals layer of the chart stack: optional, quiet marks
// about the MARKET (never the user's own trades, which are the trade
// lines layer). All of it is off until the host hands something in:
//
//   * levels: a thin dotted line at a price (Predictions odds at a
//     strike), its tag in the chart's tag column past the end of the
//     data, like the trade lines' tags. A level outside the visible
//     prices is pinned to the nearest edge of the column with an arrow.
//   * dates: a dashed vertical line at a time (a funding flip, a Fed
//     decision), its name in the signal band under the plot. A date
//     ahead of the newest bar can be pinned to the band's right end as a
//     tag instead, since the plot ends at the live bar.
//   * dots: a small ring at a time and price (an unusually large trade).
//   * caption: one line of text (open interest), in the band under the
//     plot.
//
// No label is written over the candles or the line, and none is cut: a
// label that does not fit writes its shorter text ([ChartSignalLevel.
// shortLabel], [ChartSignalDate.shortLabel]), then steps its font down
// ([kuteSignalFontSizes]), and only then is left out (its line stays).
//
// Layering contract: [KuteChartSignalsPainter] is a Positioned.fill
// sibling above the trade lines and below the crosshair, inside its own
// RepaintBoundary, mapped through the SAME geometry resolver the drawings
// and trade lines use, on the plot's width ([tagColumn] narrower than its
// canvas). [KuteChartSignalBandPainter] paints the band under the plot,
// [kuteSignalBandRows] rows tall. Everything is drawn in the host's
// neutral and up/down colours at low weight so the price stays the
// subject.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';

/// A horizontal level. [id] comes back from a tap on its tag.
class ChartSignalLevel {
  const ChartSignalLevel({
    required this.id,
    required this.price,
    required this.label,
    this.shortLabel,
  });
  final String id;
  final double price;
  final String label;

  /// What the tag writes when [label] does not fit the column ("↑ 56%").
  final String? shortLabel;
}

/// A vertical date mark. [id] non-null makes its pinned tag tappable.
class ChartSignalDate {
  const ChartSignalDate({
    required this.timeMs,
    required this.label,
    this.shortLabel,
    this.id,
    this.pinWhenAhead = false,
  });
  final int timeMs;
  final String label;

  /// What the band writes when [label] does not fit ("Fed decision").
  final String? shortLabel;
  final String? id;

  /// Show as a tag at the band's right end while the date is ahead of
  /// the plot.
  final bool pinWhenAhead;
}

/// A ring at one trade.
class ChartSignalDot {
  const ChartSignalDot({
    required this.timeMs,
    required this.price,
    required this.isBuy,
  });
  final int timeMs;
  final double price;
  final bool isBuy;
}

/// Everything the layer draws. The host builds one and keeps its identity
/// until something in it changes: the painter repaints on identity.
class ChartSignals {
  const ChartSignals({
    this.levels = const [],
    this.dates = const [],
    this.dots = const [],
    this.caption,
  });
  final List<ChartSignalLevel> levels;
  final List<ChartSignalDate> dates;
  final List<ChartSignalDot> dots;
  final String? caption;

  bool get isEmpty =>
      levels.isEmpty && dates.isEmpty && dots.isEmpty && caption == null;

  static const none = ChartSignals();
}

/// Colours the host resolves from its theme once per build.
class ChartSignalPalette {
  const ChartSignalPalette({
    required this.neutral,
    required this.up,
    required this.down,
    required this.tagBackground,
  });
  final Color neutral, up, down, tagBackground;

  @override
  bool operator ==(Object other) =>
      other is ChartSignalPalette &&
      other.neutral == neutral &&
      other.up == up &&
      other.down == down &&
      other.tagBackground == tagBackground;

  @override
  int get hashCode => Object.hash(neutral, up, down, tagBackground);
}

/// Where a tappable tag was painted last frame.
class ChartSignalHit {
  const ChartSignalHit(this.id, this.rect);
  final String id;
  final Rect rect;
}

/// The font sizes a signal label may be written in, largest first: a
/// label that does not fit at one, in its long or short text, steps down.
const List<double> kuteSignalFontSizes = [9.5, 9.0, 8.5];

/// One row of the signal band under the plot.
const double kuteSignalBandRowHeight = 17;

/// A tag's padding each side, and around its text top and bottom.
const double _kTagPadH = 4;
const double _kTagPadV = 2;

TextPainter _signalText(String text, Color color, double fontSize) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kuteChartFontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

/// The texts a label may write, in the order they are tried: [label],
/// then [short], at each of [kuteSignalFontSizes] in turn.
List<({String text, double fontSize})> kuteSignalCandidates(
    String label, String? short) {
  return [
    for (final fs in kuteSignalFontSizes) ...[
      (text: label, fontSize: fs),
      if (short != null && short != label) (text: short, fontSize: fs),
    ],
  ];
}

/// The first of [candidates] whose tag ([tag]: padded and bordered) or
/// text is at most [room] wide, laid out; null when none is.
TextPainter? _fit(
    List<({String text, double fontSize})> candidates, double room, Color color,
    {bool tag = true}) {
  for (final c in candidates) {
    final tp = _signalText(c.text, color, c.fontSize);
    final w = tp.width + (tag ? _kTagPadH * 2 : 0);
    if (w <= room + 0.01) return tp;
    tp.dispose();
  }
  return null;
}

/// The arrow a level's tag starts with when its price is off the scale.
String _arrow(bool above, bool below) => above ? '▲ ' : (below ? '▼ ' : '');

/// How wide a tag column must be for [levels]' tags, lead included, when
/// it may be at most [maxWidth]: each tag writes the first of its texts
/// ([kuteSignalCandidates], with the off-scale arrow, so the column does
/// not change as a level scrolls off) that fits; 0 when none of them is
/// wider than nothing.
double kuteSignalLevelColumnWidth(
  List<ChartSignalLevel> levels, {
  required double maxWidth,
  double lead = 8,
}) {
  var widest = 0.0;
  for (final l in levels) {
    final tp = _fit(
        kuteSignalCandidates(
            '▲ ${l.label}', l.shortLabel == null ? null : '▲ ${l.shortLabel}'),
        maxWidth - lead,
        const Color(0xFF000000));
    if (tp == null) continue;
    widest = math.max(widest, tp.width + _kTagPadH * 2);
    tp.dispose();
  }
  return widest == 0 ? 0 : widest + lead;
}

class KuteChartSignalsPainter extends CustomPainter {
  KuteChartSignalsPainter({
    required this.signals,
    required this.palette,
    required this.resolveGeometry,
    required this.repaintKey,
    required this.hits,
    required this.tagColumn,
    this.tagLead = 8,
    this.fixedTags,
  });

  final ChartSignals signals;
  final ChartSignalPalette palette;
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;
  final Object? repaintKey;

  /// Filled during paint with each tappable tag's rect. Shared list,
  /// cleared and refilled every paint.
  final List<ChartSignalHit> hits;

  /// The width of the chart's tag column at the canvas's right: the plot
  /// ends where it starts, and the level tags sit in it, [tagLead] past
  /// the end of the data.
  final double tagColumn;
  final double tagLead;

  /// The tags already in the column (the latest price's, the trade
  /// lines'): no level tag is laid over them.
  final List<KuteTagSlot> Function(Size size, KuteDrawingGeometry geom)?
      fixedTags;

  /// A small bordered tag with its top-left at [at]; returns its rect.
  Rect _tag(Canvas canvas, TextPainter tp, Offset at) {
    final rect = Rect.fromLTWH(
        at.dx, at.dy, tp.width + _kTagPadH * 2, tp.height + _kTagPadV * 2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
        rrect, Paint()..color = palette.tagBackground.withValues(alpha: 0.85));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = palette.neutral.withValues(alpha: 0.35));
    tp.paint(canvas, Offset(rect.left + _kTagPadH, rect.top + _kTagPadV));
    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    if (signals.isEmpty) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;
    final w = size.width;
    // The plot (the data's width) and where the column's tags start.
    final plotW = math.max(1.0, w - tagColumn);
    final tagsLeft = tagColumn > 0 ? plotW + tagLead : w;
    final priceH = geom.priceH;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, priceH));
    final line = Paint()
      ..color = palette.neutral.withValues(alpha: 0.32)
      ..strokeWidth = 1;

    // Dates in view: a dashed vertical line; their names are the band's.
    for (final d in signals.dates) {
      final x = geom.xForTime(d.timeMs);
      if (x < 0 || x > plotW) continue;
      for (double y = 0; y < priceH; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, priceH)), line);
      }
    }

    // Levels: a dotted line up to the column and a tag in it; pinned to
    // the column's top or foot when off the scale.
    final room = w - tagsLeft;
    final tags = <({String id, TextPainter text, double top})>[];
    for (final l in signals.levels) {
      final rawY = geom.yForPrice(l.price);
      if (!rawY.isFinite) continue;
      final above = rawY < 0, below = rawY > priceH;
      if (!above && !below) {
        for (double x = 0; x < tagsLeft; x += 6) {
          canvas.drawLine(
              Offset(x, rawY), Offset(math.min(x + 2, tagsLeft), rawY), line);
        }
      }
      final arrow = _arrow(above, below);
      final tp = _fit(
          kuteSignalCandidates('$arrow${l.label}',
              l.shortLabel == null ? null : '$arrow${l.shortLabel}'),
          room,
          palette.neutral);
      if (tp == null) continue;
      final h = tp.height + _kTagPadV * 2;
      final floor = math.max(0.0, priceH - h);
      final top = above
          ? 0.0
          : below
              ? floor
              : (rawY - h / 2).clamp(0.0, floor).toDouble();
      tags.add((id: l.id, text: tp, top: top));
    }
    if (tags.isNotEmpty) {
      final fixed = fixedTags?.call(size, geom) ?? const <KuteTagSlot>[];
      final slots = [
        for (final t in tags)
          (top: t.top, height: t.text.height + _kTagPadV * 2),
      ];
      final tops =
          kuteLayoutTags(slots, fixed: fixed, maxBottom: priceH, gap: 1.5);
      // A tag the column cannot hold clear of the others is left out.
      final placed = <KuteTagSlot>[...fixed];
      for (var i = 0; i < tags.length; i++) {
        final slot = (top: tops[i], height: slots[i].height);
        final clash = placed.any((p) =>
            slot.top < p.top + p.height && slot.top + slot.height > p.top);
        if (clash || slot.top < 0 || slot.top + slot.height > priceH + 0.01) {
          continue;
        }
        placed.add(slot);
        final rect = _tag(canvas, tags[i].text, Offset(tagsLeft, tops[i]));
        hits.add(ChartSignalHit(tags[i].id, rect));
      }
    }

    // Dots: a ring where a large trade printed.
    for (final d in signals.dots) {
      final x = geom.xForTime(d.timeMs);
      final y = geom.yForPrice(d.price);
      if (x < 0 || x > plotW || !y.isFinite || y < 0 || y > priceH) continue;
      final color = d.isBuy ? palette.up : palette.down;
      canvas.drawCircle(Offset(x, y), 4,
          Paint()..color = palette.tagBackground.withValues(alpha: 0.7));
      canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = color.withValues(alpha: 0.9));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KuteChartSignalsPainter old) =>
      !identical(old.signals, signals) ||
      old.repaintKey != repaintKey ||
      old.palette != palette ||
      old.tagColumn != tagColumn;
}

// ───────────────────────────── signal band ─────────────────────────────

/// Rows the band under the plot takes for [signals] (each
/// [kuteSignalBandRowHeight] tall): one for the dates' names and the
/// upcoming dates' tags when there are dates, one for the caption.
int kuteSignalBandRows(ChartSignals signals) =>
    (signals.dates.isNotEmpty ? 1 : 0) + (signals.caption != null ? 1 : 0);

/// The band under the plot: the names of the dates in view, each under
/// its line; the tags of the dates ahead of the plot at its right end
/// (tappable); and the caption on a row of its own. Nothing here is over
/// the data. A name that would run into another (or into a tag) writes
/// its shorter text, then a smaller font, and is otherwise left out; the
/// tags keep their place first, then the latest names.
class KuteChartSignalBandPainter extends CustomPainter {
  KuteChartSignalBandPainter({
    required this.signals,
    required this.palette,
    required this.xForTime,
    required this.plotWidth,
    required this.hits,
    required this.repaintKey,
  });

  final ChartSignals signals;
  final ChartSignalPalette palette;

  /// The x of a time on the plot, the plot's own mapping; null when
  /// there is none this frame.
  final double? Function(int timeMs) xForTime;

  /// The plot's width: a date further right is ahead of it.
  final double plotWidth;

  /// Filled during paint with each tappable tag's rect, in the band's
  /// coordinates.
  final List<ChartSignalHit> hits;
  final Object? repaintKey;

  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    final w = size.width;
    var rowTop = 0.0;
    if (signals.dates.isNotEmpty) {
      _paintDates(canvas, w, rowTop);
      rowTop += kuteSignalBandRowHeight;
    }
    final caption = signals.caption;
    if (caption != null) {
      final tp = _fit(kuteSignalCandidates(caption, null), w, palette.neutral,
          tag: false);
      if (tp != null) {
        tp.paint(canvas,
            Offset(0, rowTop + (kuteSignalBandRowHeight - tp.height) / 2));
      }
    }
  }

  void _paintDates(Canvas canvas, double w, double top) {
    // Spans of the row already written, to keep the next ones off them.
    final taken = <({double left, double right})>[];
    bool free(double left, double right) =>
        left >= 0 &&
        right <= w + 0.01 &&
        !taken.any((t) => left < t.right + _gap && right + _gap > t.left);

    // The dates ahead of the plot: tags from the right end leftwards.
    var right = w;
    for (final d in signals.dates) {
      if (!d.pinWhenAhead) continue;
      final x = xForTime(d.timeMs);
      if (x == null || x <= plotWidth) continue;
      final tp = _fit(
          kuteSignalCandidates('${d.label} ›',
              d.shortLabel == null ? null : '${d.shortLabel} ›'),
          right,
          palette.neutral);
      if (tp == null) continue;
      final tagW = tp.width + _kTagPadH * 2;
      final tagH = tp.height + _kTagPadV * 2;
      final rect = Rect.fromLTWH(
          right - tagW,
          top + math.max(0.0, (kuteSignalBandRowHeight - tagH) / 2),
          tagW,
          tagH);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect,
          Paint()..color = palette.tagBackground.withValues(alpha: 0.85));
      canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = palette.neutral.withValues(alpha: 0.35));
      tp.paint(canvas, Offset(rect.left + _kTagPadH, rect.top + _kTagPadV));
      taken.add((left: rect.left, right: rect.right));
      if (d.id != null) hits.add(ChartSignalHit(d.id!, rect));
      right = rect.left - _gap;
    }

    // The names of the dates in view, the latest first, each starting
    // just right of its line (kept inside the row).
    final inView = [
      for (final d in signals.dates)
        if (xForTime(d.timeMs) case final x? when x >= 0 && x <= plotWidth)
          (date: d, x: x),
    ]..sort((a, b) => b.x.compareTo(a.x));
    for (final e in inView) {
      for (final c in kuteSignalCandidates(e.date.label, e.date.shortLabel)) {
        final tp = _signalText(c.text, palette.neutral, c.fontSize);
        final left =
            (e.x + 3).clamp(0.0, math.max(0.0, w - tp.width)).toDouble();
        if (free(left, left + tp.width)) {
          tp.paint(canvas,
              Offset(left, top + (kuteSignalBandRowHeight - tp.height) / 2));
          taken.add((left: left, right: left + tp.width));
          break;
        }
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant KuteChartSignalBandPainter old) =>
      !identical(old.signals, signals) ||
      old.repaintKey != repaintKey ||
      old.palette != palette ||
      old.plotWidth != plotWidth;
}

/// The tappable tag containing [pos], topmost first, or null.
ChartSignalHit? kuteHitTestSignalTags(List<ChartSignalHit> hits, Offset pos,
    {double tolerance = 8}) {
  for (var i = hits.length - 1; i >= 0; i--) {
    if (hits[i].rect.inflate(tolerance).contains(pos)) return hits[i];
  }
  return null;
}
