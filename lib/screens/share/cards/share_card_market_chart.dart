// lib/screens/share/cards/share_card_market_chart.dart
//
// THE MARKET'S CHART ON A PREDICTION CARD (founder, 2 November 2026: "on
// the entire market both graphs also. Like if Lula vs Bolsonaro, make the
// graphs clear", then "the graph should actually be the graph from the
// market"). A market shared without a pick draws the market page's own
// chart (market_chart.dart), still and at the card's scale:
//
//   * THE SAME LINES: the outcomes the page charts, most likely first (two,
//     a third only when it is worth reading, share_card_sources.dart), each
//     its real price history over the range the page opens on, on one
//     time axis, the scale fitted to them as the page fits it
//     (polyChartDomain).
//   * THE SAME COLOURS, adapted to the card's ground: each line's colour
//     as the page draws it, lifted only as far as it needs to read on the
//     card's blue ([shareCardLineOn], 3:1 for a line).
//   * THE SAME LABELS: each line ends in a pill in its colour reading the
//     outcome's short name and its chance ("Lula da Silva 41%"), named as
//     the page's tags name it (polyTagStyle), in a column of their own at
//     the right where the lines stop, stacked clear of each other.
//   * NO CLUTTER: no grid, no axis, only a faint 50% line when the scale
//     holds it, its label at the plot's right as the page writes its
//     levels (left out where a line ends on it).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/polymarket/components/market_chart.dart'
    show polyChartDomain;
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart'
    show polyChartOutcomeName, polyChartShortName;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';

/// The most lines a card's chart draws.
const int kShareCardChartMaxLines = 3;

/// A third line is drawn only at this chance or more (0–100): under it
/// the chart reads as two.
const double kShareCardChartThirdLine = 10;

/// The sizes the pills step down through, largest first (the page's
/// 10.5 to 9 at the card's scale).
const List<double> kShareCardChartTagSizes = [15, 14, 13];

/// The widest a pill may be, a share of the chart's width.
const double kShareCardChartTagShare = 0.5;

/// The contrast a line keeps with the card's ground.
const double kShareCardLineContrast = 3;

/// The WCAG contrast of [a] on [b] (1 to 21).
double shareCardContrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [color] as it reads on [ground]: itself when it already has [min]
/// contrast there, else lifted (or deepened on a light ground) in
/// lightness, its hue and saturation kept, as far as it needs.
Color shareCardLineOn(Color color, Color ground,
    {double min = kShareCardLineContrast}) {
  if (shareCardContrast(color, ground) >= min) return color;
  final lighten = ground.computeLuminance() < 0.4;
  final hsl = HSLColor.fromColor(color);
  var l = hsl.lightness;
  var out = color;
  while (shareCardContrast(out, ground) < min && l > 0 && l < 1) {
    l = (l + (lighten ? 0.01 : -0.01)).clamp(0.0, 1.0);
    out = hsl.withLightness(l).toColor();
  }
  return out;
}

/// The text on a pill filled with [fill]: white or the deep ink, whichever
/// reads better.
Color shareCardPillText(Color fill) {
  const deep = Color(0xFF0B1533);
  return shareCardContrast(Colors.white, fill) >=
          shareCardContrast(deep, fill)
      ? Colors.white
      : deep;
}

class ShareCardMarketChart extends StatelessWidget {
  const ShareCardMarketChart({
    super.key,
    required this.lines,
    required this.palette,
    required this.chanceText,
    required this.drawLabel,
  });

  final List<ShareCardOutcomeLine> lines;
  final ShareCardPalette palette;

  /// A chance (0–100) as the card writes it ("41%", "41 %").
  final String Function(double chance) chanceText;

  /// A three-way match's draw, in the card's language.
  final String drawLabel;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final labels = [
        for (final l in lines) l.draw ? drawLabel : l.name,
      ];
      final pcts = [for (final l in lines) chanceText(l.chance)];
      final tags = shareCardChartTags(
        labels: labels,
        pcts: pcts,
        maxPill: width * kShareCardChartTagShare,
        measure: (text, size) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: _tagStyle(size, Colors.white)),
            textDirection: dir,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        },
      );
      return CustomPaint(
        key: const ValueKey('share-card-market-chart'),
        size: Size.infinite,
        painter: ShareCardMarketChartPainter(
          lines: lines,
          colors: [
            for (final l in lines) shareCardLineOn(l.color, palette.background)
          ],
          names: tags.names,
          pcts: pcts,
          fontSize: tags.fontSize,
          ground: palette.background,
          ink: palette.ink,
          direction: dir,
        ),
      );
    });
  }
}

/// The pills' names and size, named as the page's tags name them
/// (poly_chart_tags.dart): each outcome's short name ("Lula da Silva" for
/// "Luiz Inácio Lula da Silva", "Democratic"), two that read the same by
/// their whole names; the largest of [kShareCardChartTagSizes] every pill
/// fits [maxPill] at, a name that fits at none dropping its leading
/// words, then left out (the pill writes its chance alone). [measure] is
/// a text's width at a size; [pcts] the chances as written.
({double fontSize, List<String> names}) shareCardChartTags({
  required List<String> labels,
  required List<String> pcts,
  required double maxPill,
  required double Function(String text, double size) measure,
}) {
  final shorts = [for (final l in labels) polyChartShortName(l)];
  final count = <String, int>{};
  for (final n in shorts) {
    if (n.isNotEmpty) count.update(n.toLowerCase(), (c) => c + 1, ifAbsent: () => 1);
  }
  final wanted = [
    for (var i = 0; i < labels.length; i++)
      shorts[i].isNotEmpty && count[shorts[i].toLowerCase()]! > 1
          ? polyChartOutcomeName(labels[i])
          : shorts[i],
  ];
  const pad = ShareCardMarketChartPainter.padH * 2;
  bool fits(String name, String pct, double size) =>
      measure(name.isEmpty ? pct : '$name $pct', size) + pad <= maxPill;
  // The name and the same without its leading words ("Inácio Lula da
  // Silva", "Lula da Silva", "Silva"), never from a lowercase particle.
  List<String> shorter(String name) {
    if (name.isEmpty) return const [''];
    final words = name.split(RegExp(r'\s+'));
    return [
      name,
      for (var i = 1; i < words.length; i++)
        if (words[i].isNotEmpty && words[i][0] != words[i][0].toLowerCase())
          words.sublist(i).join(' '),
      '',
    ];
  }

  for (final size in kShareCardChartTagSizes) {
    final whole = [
      for (var i = 0; i < wanted.length; i++)
        shorter(wanted[i]).first,
    ];
    var ok = true;
    for (var i = 0; i < whole.length && ok; i++) {
      ok = fits(whole[i], pcts[i], size);
    }
    if (ok) return (fontSize: size, names: whole);
  }
  final size = kShareCardChartTagSizes.last;
  return (
    fontSize: size,
    names: [
      for (var i = 0; i < wanted.length; i++)
        shorter(wanted[i]).firstWhere((n) => fits(n, pcts[i], size),
            orElse: () => ''),
    ],
  );
}

TextStyle _tagStyle(double size, Color color) => shareCardText(
    size, FontWeight.w700, color,
    spacing: -0.1, height: 1.0, tabular: true);

class ShareCardMarketChartPainter extends CustomPainter {
  ShareCardMarketChartPainter({
    required this.lines,
    required this.colors,
    required this.names,
    required this.pcts,
    required this.fontSize,
    required this.ground,
    required this.ink,
    required this.direction,
  });

  final List<ShareCardOutcomeLine> lines;
  final List<Color> colors;

  /// Each line's pill's name ('' writes the chance alone).
  final List<String> names;
  final List<String> pcts;
  final double fontSize;
  final Color ground;
  final Color ink;
  final TextDirection direction;

  static const double _stroke = 3.5;
  static const double _dot = 5;
  static const double padH = 7;
  static const double _padV = 6;
  static const double _lead = 8;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || size.isEmpty) return;
    // The pills, measured: the column is as wide as the widest.
    final pills = <TextPainter>[];
    for (var i = 0; i < lines.length; i++) {
      final text = names[i].isEmpty ? pcts[i] : '${names[i]} ${pcts[i]}';
      pills.add(TextPainter(
        text: TextSpan(
            text: text,
            style: _tagStyle(fontSize, shareCardPillText(colors[i]))),
        textDirection: direction,
        maxLines: 1,
      )..layout());
    }
    var column = 0.0;
    for (final p in pills) {
      column = math.max(column, p.width + padH * 2);
    }
    final pillH = pills.first.height + _padV * 2;
    final plotW = math.max(1.0, size.width - column - _lead);
    // Room top and bottom for a pill centred on a line's end.
    final top = pillH / 2;
    final bottom = size.height - pillH / 2;
    final plotH = math.max(1.0, bottom - top);

    // One time axis for every line; the scale fitted to them.
    var t0 = lines.first.points.first.t, t1 = lines.first.points.last.t;
    var lo = 1.0, hi = 0.0;
    for (final l in lines) {
      for (final p in l.points) {
        t0 = math.min(t0, p.t);
        t1 = math.max(t1, p.t);
        lo = math.min(lo, p.p);
        hi = math.max(hi, p.p);
      }
    }
    final domain = polyChartDomain(lo, hi);
    final span = math.max(1, t1 - t0);
    double x(int t) => (t - t0) / span * plotW;
    double y(double p) =>
        top +
        (1 - (p - domain.minY) / (domain.maxY - domain.minY)) * plotH;

    // The lines' ends (their dots, at the plot's right).
    final ends = <Offset>[];
    for (var i = 0; i < lines.length; i++) {
      final pts = lines[i].points;
      ends.add(Offset(x(pts.last.t), y(pts.last.p)));
    }

    // The faint 50% line, when the scale holds it; its label at the
    // plot's right over it, as the page writes its levels, unless a
    // line ends there.
    if (domain.minY < 0.5 && domain.maxY > 0.5) {
      final y50 = y(0.5);
      canvas.drawLine(
          Offset(0, y50),
          Offset(plotW, y50),
          Paint()
            ..color = ink.withValues(alpha: 0.2)
            ..strokeWidth = 1);
      final tp = TextPainter(
        text: TextSpan(
            text: '50%',
            style: shareCardText(11, FontWeight.w600,
                ink.withValues(alpha: 0.55),
                height: 1.0, tabular: true)),
        textDirection: direction,
      )..layout();
      final label = Rect.fromLTWH(plotW - tp.width - _dot * 3,
          y50 - tp.height - 3, tp.width, tp.height);
      final clear = ends.every((e) =>
          (e.dy - label.center.dy).abs() > tp.height / 2 + _dot + 6);
      if (clear) tp.paint(canvas, label.topLeft);
      tp.dispose();
    }

    // The lines, least likely first so the leader is drawn over them.
    for (var i = lines.length - 1; i >= 0; i--) {
      final pts = lines[i].points;
      final path = Path()..moveTo(x(pts.first.t), y(pts.first.p));
      for (var j = 1; j < pts.length; j++) {
        path.lineTo(x(pts[j].t), y(pts[j].p));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
    for (var i = lines.length - 1; i >= 0; i--) {
      canvas.drawCircle(ends[i], _dot + 2, Paint()..color = ground);
      canvas.drawCircle(ends[i], _dot, Paint()..color = colors[i]);
    }

    // The pills at the right, each centred on its line's end, stacked
    // clear of each other inside the plot.
    final order = [for (var i = 0; i < lines.length; i++) i]
      ..sort((a, b) => ends[a].dy.compareTo(ends[b].dy));
    final ys = <int, double>{};
    var prev = double.negativeInfinity;
    for (final i in order) {
      final c = math.max(ends[i].dy, prev + pillH + _gap);
      ys[i] = c;
      prev = c;
    }
    // Pushed past the bottom: the stack moves up as one.
    final over = prev - bottom;
    if (over > 0) {
      for (final i in order) {
        ys[i] = ys[i]! - over;
      }
    }
    final under = top - ys[order.first]!;
    if (under > 0) {
      for (final i in order) {
        ys[i] = ys[i]! + under;
      }
    }
    final left = plotW + _lead;
    for (var i = 0; i < lines.length; i++) {
      final p = pills[i];
      final w = p.width + padH * 2;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, ys[i]! - pillH / 2, w, pillH),
          Radius.circular(pillH / 2));
      canvas.drawRRect(r, Paint()..color = colors[i]);
      p.paint(canvas, Offset(left + padH, ys[i]! - p.height / 2));
      p.dispose();
    }
  }

  @override
  bool shouldRepaint(ShareCardMarketChartPainter old) =>
      !identical(old.lines, lines) ||
      old.fontSize != fontSize ||
      old.ground != ground ||
      old.ink != ink ||
      old.names.join('|') != names.join('|') ||
      old.pcts.join('|') != pcts.join('|');
}

