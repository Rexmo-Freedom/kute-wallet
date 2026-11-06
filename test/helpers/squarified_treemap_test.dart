// The squarified treemap (lib/helpers/squarified_treemap.dart): every
// tile's area in proportion to its weight, no two tiles overlapping, the
// tiles covering the rectangle exactly, the paper's own example laid out
// as the paper draws it, and the same weights always giving the same
// tiles.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/squarified_treemap.dart';

double _area(Rect r) => r.width * r.height;

double _overlap(Rect a, Rect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  return w > 0 && h > 0 ? w * h : 0;
}

/// Checks the three promises for [weights] in [bounds].
void _expectTreemap(List<double> weights, Rect bounds) {
  final tiles = squarify(weights, bounds);
  expect(tiles, hasLength(weights.length));
  final total = weights.fold<double>(0, (s, w) => s + w);
  final area = _area(bounds);
  for (var i = 0; i < tiles.length; i++) {
    // Proportional.
    expect(_area(tiles[i]),
        moreOrLessEquals(weights[i] / total * area, epsilon: area * 1e-9));
    // Inside.
    expect(tiles[i].left, greaterThanOrEqualTo(bounds.left - 1e-9));
    expect(tiles[i].top, greaterThanOrEqualTo(bounds.top - 1e-9));
    expect(tiles[i].right, lessThanOrEqualTo(bounds.right + 1e-9));
    expect(tiles[i].bottom, lessThanOrEqualTo(bounds.bottom + 1e-9));
  }
  // No overlaps.
  for (var i = 0; i < tiles.length; i++) {
    for (var j = i + 1; j < tiles.length; j++) {
      expect(_overlap(tiles[i], tiles[j]), lessThan(area * 1e-9),
          reason: 'tiles $i and $j overlap');
    }
  }
  // Fills: the areas add up to the rectangle's, and every point of it
  // (off any edge) is in a tile.
  expect(tiles.fold<double>(0, (s, r) => s + _area(r)),
      moreOrLessEquals(area, epsilon: area * 1e-9));
  for (var x = 0; x < 37; x++) {
    for (var y = 0; y < 41; y++) {
      final p = Offset(bounds.left + (x + 0.371) / 37 * bounds.width,
          bounds.top + (y + 0.613) / 41 * bounds.height);
      expect(tiles.any((t) => t.contains(p)), isTrue, reason: 'a hole at $p');
    }
  }
}

void main() {
  test('the paper\'s example: 6 6 4 3 2 2 1 in a 6 by 4 rectangle', () {
    final tiles =
        squarify([6, 6, 4, 3, 2, 2, 1], const Rect.fromLTWH(0, 0, 6, 4));
    void at(int i, double l, double t, double w, double h) {
      expect(tiles[i].left, moreOrLessEquals(l, epsilon: 1e-9));
      expect(tiles[i].top, moreOrLessEquals(t, epsilon: 1e-9));
      expect(tiles[i].width, moreOrLessEquals(w, epsilon: 1e-9));
      expect(tiles[i].height, moreOrLessEquals(h, epsilon: 1e-9));
    }

    // The two sixes as a column at the left, then the four and the three
    // as a row over the rest, then the twos and the one as columns.
    at(0, 0, 0, 3, 2);
    at(1, 0, 2, 3, 2);
    at(2, 3, 0, 4 / (7 / 3), 7 / 3);
    at(3, 3 + 4 / (7 / 3), 0, 3 / (7 / 3), 7 / 3);
    at(4, 3, 7 / 3, 1.2, 5 / 3);
    at(5, 4.2, 7 / 3, 1.2, 5 / 3);
    at(6, 5.4, 7 / 3, 0.6, 5 / 3);
  });

  test('areas proportional, no overlaps, the rectangle filled', () {
    _expectTreemap([6, 6, 4, 3, 2, 2, 1], const Rect.fromLTWH(0, 0, 6, 4));
    // A market-shaped tail: one giant, a few big, many small.
    final market = <double>[
      3156.0,
      910,
      879,
      873,
      852,
      664,
      521,
      515,
      475,
      354,
      268,
      264,
      244,
      239,
      235,
      229,
      217,
      194,
      165,
      127,
      104,
      104,
      102,
      91,
      87,
      80,
      80,
      76,
      73,
      65,
      63,
      62,
      53,
      53,
      46,
      40,
      37,
      36,
      35,
      32,
      32,
      31,
      24,
      21,
      19,
    ];
    _expectTreemap(market, const Rect.fromLTWH(10, 20, 334, 334));
    _expectTreemap(market, const Rect.fromLTWH(0, 0, 120, 400));
    // Unsorted input lays out the same way, each tile still its own.
    _expectTreemap(
        market.reversed.toList(), const Rect.fromLTWH(0, 0, 300, 200));
    _expectTreemap([1], const Rect.fromLTWH(5, 5, 50, 10));
  });

  test('equal weights in a square make squares, in input order', () {
    final tiles =
        squarify(List.filled(16, 1.0), const Rect.fromLTWH(0, 0, 4, 4));
    for (final t in tiles) {
      expect(t.width, moreOrLessEquals(1, epsilon: 1e-9));
      expect(t.height, moreOrLessEquals(1, epsilon: 1e-9));
    }
    // Ties keep their input order: the first tile is the top-left one.
    expect(tiles.first.topLeft, Offset.zero);
  });

  test('the same weights always give the same tiles', () {
    final weights = <double>[5, 3, 3, 2, 1, 1, 0.5];
    const r = Rect.fromLTWH(0, 0, 200, 150);
    final a = squarify(weights, r);
    final b = squarify([...weights], r);
    expect(a, b);
    // A weight's tile is the same wherever it sits in the input.
    final shuffled = <double>[1, 5, 0.5, 3, 2, 1, 3];
    final c = squarify(shuffled, r);
    expect(c[1], a[0]);
    expect(c[4], a[3]);
    expect(c[2], a[6]);
  });

  test(
      'a weight that is not positive takes no room; nothing to lay out '
      'is no tile', () {
    const r = Rect.fromLTWH(10, 10, 100, 50);
    final tiles = squarify([3, 0, -2, double.nan, double.infinity, 1], r);
    for (final i in [1, 2, 3, 4]) {
      expect(tiles[i].isEmpty, isTrue);
      expect(tiles[i].topLeft, r.topLeft);
    }
    expect(_area(tiles[0]) + _area(tiles[5]),
        moreOrLessEquals(_area(r), epsilon: 1e-6));
    expect(_area(tiles[0]), moreOrLessEquals(_area(r) * 0.75, epsilon: 1e-6));
    expect(squarify(const [], r), isEmpty);
    expect(squarify([1, 2], Rect.zero).every((t) => t.isEmpty), isTrue);
    expect(squarify([0, 0], r).every((t) => t.isEmpty), isTrue);
  });
}
