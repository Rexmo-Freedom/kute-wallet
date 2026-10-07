// lib/screens/polymarket/components/poly_chart_tags.dart
//
// The right-edge value tags of a Predictions chart (market_chart.dart):
// where each sits and what it says. Each line ends in a pill in its own
// colour reading the outcome's short name and its chance ("Sakatsume
// 72.5%", "Yes 18%"), so a chart with several lines reads without matching
// colours to the list under it. The pills keep one column at the plot's
// right edge (never spread sideways over the lines) and the shared tag
// rule (kute_chart_tag_layout.dart) keeps them apart.
//
// Where lines end close together:
//   * the pills never overlap each other and never sit on another line's
//     end dot: the dots of lines that end together are one wall, and their
//     pills stack above and under it, the higher lines' above, each as
//     close to its own line's end as the others allow, all inside the plot
//     (a stack near the top or the bottom goes to the side with room);
//   * three or more pills in one stack would hide the ends of those lines
//     behind a block of names, so there each pill may be at most a tenth
//     of the plot wider than its bare chance: the names are cut short, and
//     when a name would keep fewer than [kPolyTagMinNameChars] letters the
//     stack writes the chances alone (the list under the chart names
//     every line in its colour);
//   * when the column cannot hold every tag near its line, the least
//     likely lines lose theirs first: never a pile of pills.
// Any one pill is at most [kPolyTagMaxWidthShare] of the plot wide; a
// longer name ends in an ellipsis.

import 'dart:math' as math;

import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';

/// The widest a value tag may be, as a share of the plot's width.
const double kPolyTagMaxWidthShare = 0.45;

/// How much wider than its bare chance a pill in a stack of three or more
/// may be, as a share of the plot's width.
const double kPolyTagStackExtraShare = 0.10;

/// The fewest letters of a name a cut-short pill keeps; with fewer, the
/// stack writes its chances alone.
const int kPolyTagMinNameChars = 4;

/// The most tags one chart draws.
const int kPolyTagMaxTags = 5;

/// The farthest a tag's middle may sit from its line's end, in tag
/// heights; a tag that would be pushed further reads as another line's.
const double kPolyTagMaxShift = 2.0;

/// An outcome's name as the chart's own labels write it short: a name of
/// up to twelve characters as it is ("Draw", "Yes", "Real Madrid"), a
/// longer one without its first word, which for a person is the surname
/// ("Himeno Sakatsume" -> "Sakatsume", "Los Angeles Lakers" -> "Angeles
/// Lakers"). Not cut to a width: the painter does that.
String polyChartShortName(String label) {
  final trimmed = label.trim();
  if (trimmed.length <= 12) return trimmed;
  final words = trimmed.split(RegExp(r'\s+'));
  return words.length > 1 ? words.sublist(1).join(' ') : trimmed;
}

/// One line's end, as the tag layout reads it: the [y] of its end on the
/// plot, its [price] (the more likely lines keep their tags first), the
/// [pct] its tag writes and its short [name] ('' writes the chance alone).
typedef PolyTagLine = ({double y, double price, String pct, String name});

/// One tag to draw: the line it belongs to ([index] into the lines given),
/// the pill's [top], its [text] and the pill's [width].
typedef PolyTagPlacement = ({
  int index,
  double top,
  String text,
  double width,
});

/// The value tags for [lines] (each line whose end is on screen) on a
/// plot [plotWidth] wide and [drawH] tall, with pills [tagHeight] tall.
/// [measure] is the width of a pill's text; [padH] the pill's padding
/// each side; [dotRadius] the end dot's. See the file comment.
List<PolyTagPlacement> polyLayoutValueTags({
  required List<PolyTagLine> lines,
  required double plotWidth,
  required double drawH,
  required double tagHeight,
  required double Function(String text) measure,
  double padH = 5,
  double dotRadius = 4,
  double gap = 2,
}) {
  if (lines.isEmpty || drawH <= tagHeight || plotWidth <= 0) return const [];
  // The more likely lines first; equal ones in the order given.
  final byPrice = [for (var i = 0; i < lines.length; i++) i]
    ..sort((a, b) {
      final c = lines[b].price.compareTo(lines[a].price);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var n = math.min(kPolyTagMaxTags, lines.length); n >= 1; n--) {
    final tops = _place(
      lines: lines,
      tagged: byPrice.take(n).toList(),
      drawH: drawH,
      h: tagHeight,
      dotRadius: dotRadius,
      gap: gap,
      strict: n > 1,
    );
    if (tops == null) continue;
    return _texts(
      lines: lines,
      tops: tops,
      plotWidth: plotWidth,
      h: tagHeight,
      measure: measure,
      padH: padH,
      gap: gap,
    );
  }
  return const [];
}

/// The tops of the [tagged] lines' tags, or null when they do not fit
/// (overlap, outside the plot, on another line's dot or too far from
/// their own line). A lone tag ([strict] false) always fits somewhere.
Map<int, double>? _place({
  required List<PolyTagLine> lines,
  required List<int> tagged,
  required double drawH,
  required double h,
  required double dotRadius,
  required double gap,
  required bool strict,
}) {
  final maxTop = drawH - h;
  double clampTop(double t) => t.clamp(0.0, math.max(0.0, maxTop)).toDouble();
  // Lines whose ends sit close enough that a pill on one would cover
  // another's dot are one group; the groups top to bottom.
  final reach = h / 2 + dotRadius + 1;
  final order = [for (var i = 0; i < lines.length; i++) i]
    ..sort((a, b) {
      final c = lines[a].y.compareTo(lines[b].y);
      if (c != 0) return c;
      final p = lines[b].price.compareTo(lines[a].price);
      return p != 0 ? p : a.compareTo(b);
    });
  final groups = <List<int>>[];
  for (final i in order) {
    if (groups.isNotEmpty && lines[i].y - lines[groups.last.last].y < reach) {
      groups.last.add(i);
    } else {
      groups.add([i]);
    }
  }

  final isTagged = {...tagged};
  final walls = <KuteTagSlot>[];
  final wanted = <int, double>{};
  for (final g in groups) {
    final mine = [for (final i in g) if (isTagged.contains(i)) i];
    if (g.length == 1) {
      // A line alone: its tag on its end, as ever; an untagged one's dot
      // is kept clear.
      final i = g.first;
      if (mine.isEmpty) {
        walls.add((
          top: lines[i].y - dotRadius - 1,
          height: 2 * dotRadius + 2,
        ));
      } else {
        wanted[i] = clampTop(lines[i].y - h / 2);
      }
      continue;
    }
    // Lines ending together: their dots one wall, the higher lines' tags
    // above it and the lower ones' under it, as the room allows.
    final wallTop = lines[g.first].y - dotRadius - 1;
    final wallBottom = lines[g.last].y + dotRadius + 1;
    walls.add((top: wallTop, height: wallBottom - wallTop));
    if (mine.isEmpty) continue;
    final fitAbove = ((wallTop - gap + gap) / (h + gap)).floor();
    final fitBelow = ((drawH - wallBottom - gap + gap) / (h + gap)).floor();
    var above = 0;
    for (final i in mine) {
      if (g.indexOf(i) < g.length / 2) above++;
    }
    above = math.min(above, math.max(0, fitAbove));
    if (mine.length - above > fitBelow) {
      above = math.min(mine.length, mine.length - math.max(0, fitBelow));
    }
    for (var k = 0; k < mine.length; k++) {
      final i = mine[k];
      wanted[i] = k < above ? wallTop - gap - h : wallBottom + gap;
    }
  }

  final ids = wanted.keys.toList();
  final tops = kuteLayoutTags(
    [for (final i in ids) (top: wanted[i]!, height: h)],
    fixed: walls,
    maxBottom: drawH,
    gap: gap,
  );
  final out = {for (var k = 0; k < ids.length; k++) ids[k]: tops[k]};
  if (!strict) return out;

  // Check what the layout made of it.
  const eps = 0.5;
  final placed = out.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  for (var k = 0; k < placed.length; k++) {
    final top = placed[k].value;
    if (top < -eps || top + h > drawH + eps) return null;
    if (k > 0 && top < placed[k - 1].value + h + gap - eps) return null;
    final i = placed[k].key;
    if (((top + h / 2) - lines[i].y).abs() > kPolyTagMaxShift * h + eps) {
      return null;
    }
    for (var j = 0; j < lines.length; j++) {
      if (j == i) continue;
      final y = lines[j].y;
      if (y + dotRadius > top + eps && y - dotRadius < top + h - eps) {
        return null;
      }
    }
  }
  return out;
}

/// What each placed tag writes, and its width. See the file comment.
List<PolyTagPlacement> _texts({
  required List<PolyTagLine> lines,
  required Map<int, double> tops,
  required double plotWidth,
  required double h,
  required double Function(String text) measure,
  required double padH,
  required double gap,
}) {
  final placed = tops.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  // Stacks: pills less than a pill's height apart (against each other,
  // or either side of the dots they were moved off).
  final runs = <List<int>>[];
  final touch = h + gap;
  double? lastBottom;
  for (final e in placed) {
    if (lastBottom != null && e.value - lastBottom <= touch) {
      runs.last.add(e.key);
    } else {
      runs.add([e.key]);
    }
    lastBottom = e.value + h;
  }

  final maxW = plotWidth * kPolyTagMaxWidthShare;
  final out = <PolyTagPlacement>[];
  for (final run in runs) {
    final stacked = run.length >= 3;
    final texts = <int, String>{};
    var bare = false;
    for (final i in run) {
      final pct = lines[i].pct;
      final name = lines[i].name.trim();
      final pctW = measure(pct) + padH * 2;
      final cap = stacked
          ? math.min(maxW, pctW + plotWidth * kPolyTagStackExtraShare)
          : maxW;
      final fitted = name.isEmpty ? null : _fit(name, pct, cap - padH * 2, measure);
      if (name.isNotEmpty && fitted == null) {
        if (stacked) bare = true;
        texts[i] = pct;
      } else {
        texts[i] = fitted ?? pct;
      }
    }
    for (final i in run) {
      final text = bare ? lines[i].pct : texts[i]!;
      out.add((
        index: i,
        top: tops[i]!,
        text: text,
        width: measure(text) + padH * 2,
      ));
    }
  }
  return out;
}

/// "[name] [pct]" within [maxW], the name cut short with an ellipsis when
/// it must be; null when fewer than [kPolyTagMinNameChars] of its letters
/// would be left.
String? _fit(String name, String pct, double maxW,
    double Function(String text) measure) {
  final whole = '$name $pct';
  if (measure(whole) <= maxW) return whole;
  final chars = name.runes.toList();
  var lo = kPolyTagMinNameChars, hi = chars.length - 1;
  String? best;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final cut = String.fromCharCodes(chars.take(mid)).trimRight();
    final t = '$cut… $pct';
    if (measure(t) <= maxW) {
      best = t;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}
