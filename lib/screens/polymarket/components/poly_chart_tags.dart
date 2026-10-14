// lib/screens/polymarket/components/poly_chart_tags.dart
//
// The value tags of a Predictions chart (market_chart.dart): where each
// sits and what it says. Each line ends in a pill in its own colour
// reading the outcome's short name and its chance ("Sakatsume 72.5%",
// "Yes 18%"), so a chart with several lines reads without matching colours
// to the list under it.
//
// The pills keep a column of their own at the chart's right, past the
// end of the lines ([polyTagStyle]): the lines stop short of it, so no
// pill ever covers a line. The column is there only while the pills are:
// panned back in time it eases shut and the lines take the chart's full
// width (market_chart.dart). It is as wide as the widest pill the
// chart can write (its name and the widest chance, "99.55%"), and never
// more than [kPolyTagMaxGutterShare] of the chart:
//   * a name is the outcome's short name ([polyChartShortName]); one that
//     reads as a market question ("Will Flávio Bolsonaro win the 2026
//     Brazilian presidential election?") writes the candidate it is about;
//     two lines whose short names read the same write their whole names,
//     or the first name as an initial ("F. Bolsonaro", "M. Bolsonaro");
//   * a name that does not fit drops its leading words ("Inácio Lula da
//     Silva" -> "Lula da Silva"), then the column's font steps down
//     ([kPolyTagFontSizes]), and a name that fits at none of them is left
//     out: that pill writes its chance alone (the list under the chart
//     names every line in its colour). A pill's text is never cut.
//
// Where lines end close together the shared tag rule
// (kute_chart_tag_layout.dart) keeps the pills apart:
//   * the pills never overlap each other and never sit level with another
//     line's end dot: the dots of lines that end together are one wall,
//     and their pills stack above and under it, the higher lines' above,
//     each as close to its own line's end as the others allow, all inside
//     the plot (a stack near the top or the bottom goes to the side with
//     room);
//   * when the column cannot hold every tag near its line, the least
//     likely lines lose theirs first: never a pile of pills.

import 'dart:math' as math;

import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';

/// The widest the tag column may be, as a share of the chart's width.
const double kPolyTagMaxGutterShare = 0.34;

/// The font sizes the tags may be written in, largest first: the column
/// steps down through them before a name is left out.
const List<double> kPolyTagFontSizes = [10.5, 10.0, 9.5, 9.0];

/// The room between a line's end (its dot) and its pill.
const double kPolyTagLead = 8;

/// The widest chance a tag writes (two decimals over 99%: "99.55%"): the
/// column is sized for it, so a pill never outgrows the column as the
/// price moves.
const String kPolyTagPctTemplate = '00.00%';

/// The most tags one chart draws.
const int kPolyTagMaxTags = 5;

/// The farthest a tag's middle may sit from its line's end, in tag
/// heights; a tag that would be pushed further reads as another line's.
const double kPolyTagMaxShift = 2.0;

/// The verbs a "Will (candidate) (verb) …?" market question goes on with
/// after the candidate's name.
const Set<String> _kQuestionVerbs = {
  'advance', 'announce', 'appear', 'attend', 'be', 'beat', 'become',
  'close', 'come', 'defeat', 'drop', 'end', 'endorse', 'face', 'fall',
  'finish', 'get', 'go', 'have', 'hit', 'hold', 'join', 'land', 'launch',
  'lead', 'leave', 'lose', 'make', 'meet', 'move', 'pass', 'place',
  'qualify', 'reach', 'receive', 'release', 'remain', 'resign', 'return',
  'rise', 'run', 'say', 'score', 'sign', 'stay', 'top', 'visit', 'win',
};

/// The outcome a chart line stands for, as a name: [label] itself or,
/// when it is a market question ("Will Flávio Bolsonaro win the 2026
/// Brazilian presidential election?"), the candidate it asks about
/// ("Flávio Bolsonaro"); '' for a question that names none.
String polyChartOutcomeName(String label) {
  final trimmed = label.trim();
  if (!trimmed.endsWith('?')) return trimmed;
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length < 3 || words.first.toLowerCase() != 'will') return '';
  for (var i = 2; i < words.length && i <= 7; i++) {
    if (_kQuestionVerbs.contains(words[i].toLowerCase())) {
      return words.sublist(1, i).join(' ');
    }
  }
  return '';
}

/// An outcome's name as the chart's own labels write it short: a name of
/// up to twelve characters as it is ("Draw", "Yes", "Real Madrid"), a
/// longer one without its first word, which for a person is the surname
/// ("Himeno Sakatsume" -> "Sakatsume", "Los Angeles Lakers" -> "Angeles
/// Lakers"). A market question writes the candidate it asks about
/// ([polyChartOutcomeName]). Not fitted to a width: [polyTagStyle] does
/// that.
String polyChartShortName(String label) {
  final trimmed = polyChartOutcomeName(label);
  if (trimmed.length <= 12) return trimmed;
  final words = trimmed.split(RegExp(r'\s+'));
  return words.length > 1 ? words.sublist(1).join(' ') : trimmed;
}

/// How a chart writes its value tags: the [fontSize] of every pill, the
/// width of the tag column at the chart's right ([gutter], from the end
/// of the lines to the chart's edge) and the name each line's pill writes
/// ([names], in the order of the labels given; '' writes the chance
/// alone).
typedef PolyTagStyle = ({double fontSize, double gutter, List<String> names});

/// The tag column for lines labelled [labels] on a chart [width] wide.
/// [measure] is the width of a text at a font size; [padH] a pill's
/// padding each side; [minGutter] the least the lines stop short of the
/// chart's edge. See the file comment.
PolyTagStyle polyTagStyle({
  required List<String> labels,
  required double width,
  required double Function(String text, double fontSize) measure,
  double padH = 5,
  double minGutter = 12,
}) {
  final minFont = kPolyTagFontSizes.last;
  final maxPill = width * kPolyTagMaxGutterShare - kPolyTagLead;
  double need(String name, double fs) =>
      measure(name.isEmpty ? kPolyTagPctTemplate : '$name $kPolyTagPctTemplate',
          fs) +
      padH * 2;

  // The short names; two that read the same write their whole names.
  final shorts = [for (final l in labels) polyChartShortName(l)];
  final count = <String, int>{};
  for (final n in shorts) {
    if (n.isEmpty) continue;
    count.update(n.toLowerCase(), (c) => c + 1, ifAbsent: () => 1);
  }
  final names = <String>[
    for (var i = 0; i < labels.length; i++)
      (shorts[i].isNotEmpty && count[shorts[i].toLowerCase()]! > 1
              ? _wholeNames(polyChartOutcomeName(labels[i]))
              : _shorterNames(shorts[i]))
          .firstWhere((c) => need(c, minFont) <= maxPill, orElse: () => ''),
  ];

  final fontSize = kPolyTagFontSizes.firstWhere(
      (fs) => names.every((n) => need(n, fs) <= maxPill),
      orElse: () => minFont);
  var pill = need('', fontSize);
  for (final n in names) {
    pill = math.max(pill, need(n, fontSize));
  }
  return (
    fontSize: fontSize,
    gutter: math.max(minGutter, pill + kPolyTagLead),
    names: names,
  );
}

/// [name], then the same without its leading words, one at a time
/// ("Inácio Lula da Silva", "Lula da Silva", "Silva"), skipping those that
/// would start on a lowercase particle ("da Silva").
List<String> _shorterNames(String name) {
  if (name.isEmpty) return const [''];
  final words = name.split(RegExp(r'\s+'));
  return [
    name,
    for (var i = 1; i < words.length; i++)
      if (words[i].isNotEmpty && words[i][0] != words[i][0].toLowerCase())
        words.sublist(i).join(' '),
  ];
}

/// A whole [name] that must stay told apart from another line's: as it
/// is, then with its first word as an initial ("Flávio Bolsonaro", "F.
/// Bolsonaro").
List<String> _wholeNames(String name) {
  final words = name.split(RegExp(r'\s+'));
  if (words.length < 2 || words.first.isEmpty) return [name];
  return [
    name,
    '${String.fromCharCode(words.first.runes.first)}. '
        '${words.sublist(1).join(' ')}',
  ];
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
/// plot [drawH] tall, with pills [tagHeight] tall and at most [maxWidth]
/// wide (the tag column's, [polyTagStyle]). [measure] is the width of a
/// pill's text; [padH] the pill's padding each side; [dotRadius] the end
/// dot's. See the file comment.
List<PolyTagPlacement> polyLayoutValueTags({
  required List<PolyTagLine> lines,
  required double maxWidth,
  required double drawH,
  required double tagHeight,
  required double Function(String text) measure,
  double padH = 5,
  double dotRadius = 4,
  double gap = 2,
}) {
  if (lines.isEmpty || drawH <= tagHeight || maxWidth <= 0) return const [];
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
      maxWidth: maxWidth,
      measure: measure,
      padH: padH,
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

/// What each placed tag writes, and its width: its name and chance when
/// that fits in [maxWidth], its chance alone otherwise. Never cut.
List<PolyTagPlacement> _texts({
  required List<PolyTagLine> lines,
  required Map<int, double> tops,
  required double maxWidth,
  required double Function(String text) measure,
  required double padH,
}) {
  final placed = tops.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final out = <PolyTagPlacement>[];
  for (final e in placed) {
    final line = lines[e.key];
    final name = line.name.trim();
    final whole = '$name ${line.pct}';
    final text = name.isNotEmpty && measure(whole) + padH * 2 <= maxWidth + 0.01
        ? whole
        : line.pct;
    out.add((
      index: e.key,
      top: e.value,
      text: text,
      width: measure(text) + padH * 2,
    ));
  }
  return out;
}
