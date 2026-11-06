// lib/helpers/squarified_treemap.dart
//
// The squarified treemap (Bruls, Huizing and van Wijk, "Squarified
// Treemaps", 2000): a rectangle cut into one tile per weight, each tile's
// area in proportion to its weight, the tiles kept as close to squares as
// the greedy row rule allows. Pure geometry, no Flutter widgets: the
// Investing market map (hl_market_map.dart) lays its groups and its tiles
// with it.
//
// The rule: the weights, largest first, are laid in rows along the
// shorter side of the space left. A weight joins the current row while
// that does not worsen the row's worst aspect ratio; otherwise the row is
// fixed and the next one starts in what remains. The last row takes the
// whole remaining space, and the last tile of every row runs to the row's
// end, so the tiles fill the rectangle exactly with no float gap.
//
// Deterministic: equal weights keep their input order, and the same
// weights in the same rectangle always give the same tiles.

import 'dart:math' as math;
import 'dart:ui' show Rect;

/// One tile per entry of [weights], in the same order, inside [bounds]:
/// each tile's area is its weight's share of [bounds]' area, the tiles do
/// not overlap and together they cover [bounds]. A weight that is not a
/// positive finite number gets an empty tile at [bounds]' top-left corner
/// and takes no area.
List<Rect> squarify(List<double> weights, Rect bounds) {
  final empty = Rect.fromLTWH(bounds.left, bounds.top, 0, 0);
  final out = List<Rect>.filled(weights.length, empty);
  if (weights.isEmpty || bounds.width <= 0 || bounds.height <= 0) return out;

  bool usable(double w) => w.isFinite && w > 0;
  final order = [
    for (var i = 0; i < weights.length; i++)
      if (usable(weights[i])) i,
  ]..sort((a, b) {
      final c = weights[b].compareTo(weights[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  if (order.isEmpty) return out;

  final total = order.fold<double>(0, (s, i) => s + weights[i]);
  final scale = bounds.width * bounds.height / total;
  final areas = [for (final i in order) weights[i] * scale];

  var rest = bounds;
  var start = 0;
  while (start < order.length) {
    final side = math.min(rest.width, rest.height);
    var end = start + 1;
    var sum = areas[start];
    var lo = sum;
    var hi = sum;
    var worst = _worstRatio(sum, lo, hi, side);
    while (end < order.length) {
      final a = areas[end];
      final s = sum + a;
      final l = math.min(lo, a);
      final h = math.max(hi, a);
      final w = _worstRatio(s, l, h, side);
      if (w > worst) break;
      sum = s;
      lo = l;
      hi = h;
      worst = w;
      end++;
    }
    rest = _layRow(
      [for (var k = start; k < end; k++) order[k]],
      areas.sublist(start, end),
      sum,
      rest,
      out,
      last: end == order.length,
    );
    start = end;
  }
  return out;
}

/// The worst aspect ratio (long side over short side, at least 1) of a
/// row of areas [sum] in total, the smallest [lo] and the largest [hi],
/// laid along a side of length [side].
double _worstRatio(double sum, double lo, double hi, double side) {
  if (side <= 0 || sum <= 0 || lo <= 0) return double.infinity;
  final s2 = sum * sum;
  final w2 = side * side;
  return math.max(w2 * hi / s2, s2 / (w2 * lo));
}

/// Lays the row [ids] (their [areas], [sum] in all) along the shorter side
/// of [rest] into [out], and returns the space left after it. The [last]
/// row takes the whole of [rest].
Rect _layRow(
    List<int> ids, List<double> areas, double sum, Rect rest, List<Rect> out,
    {required bool last}) {
  // Wider than tall: the row is a column at the left, spanning the
  // height. Taller than wide: a row at the top, spanning the width.
  final column = rest.width >= rest.height;
  final span = column ? rest.height : rest.width;
  final room = column ? rest.width : rest.height;
  final thick = last ? room : math.min(room, sum / span);
  var at = column ? rest.top : rest.left;
  final stop = column ? rest.bottom : rest.right;
  for (var k = 0; k < ids.length; k++) {
    final length = k == ids.length - 1 ? stop - at : areas[k] / sum * span;
    out[ids[k]] = column
        ? Rect.fromLTWH(rest.left, at, thick, length)
        : Rect.fromLTWH(at, rest.top, length, thick);
    at += length;
  }
  return column
      ? Rect.fromLTRB(rest.left + thick, rest.top, rest.right, rest.bottom)
      : Rect.fromLTRB(rest.left, rest.top + thick, rest.right, rest.bottom);
}
