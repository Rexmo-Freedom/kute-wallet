// lib/screens/shared/charts/kute_chart_tag_layout.dart
//
// The one rule every chart's right-edge tags are laid out by: the latest
// price's own tag (the Investing live price, a Predictions line's value)
// and the trade lines' tags (entry, average price, liquidation, take
// profit, stop loss, working orders, the Predictions "Bought" lines), and
// the market-signal levels.
//
//   * Fixed tags never move: the latest price's tag sits on its line,
//     over the latest point, and nothing is ever drawn over it.
//   * Every other tag keeps the place on its own line when that place is
//     free. Tags that would overlap are moved apart by the least that
//     clears them, keeping the order of their lines; a tag that would
//     cover a fixed tag goes to the side of it its own line is on (or to
//     the other side when that side has no room).
//   * Everything stays inside the plot's price area (top .. maxBottom),
//     never over a volume strip or a pane under it: an off-scale line's
//     tag is pinned to that edge by its painter, with an arrow.
//   * A tag whose line is within [kuteTagMergePx] of the latest price is
//     the same level on screen: its painter writes it as "Entry ≈"
//     beside the latest price's tag rather than repeating a figure that
//     reads the same.

import 'dart:math' as math;

/// A tag in the right-edge column: its top and its height, in px.
typedef KuteTagSlot = ({double top, double height});

/// Lines closer than this to the latest price are the same level on
/// screen (see the file comment).
const double kuteTagMergePx = 4;

/// The tops for [tags] (in the order given) so that none overlaps
/// another or any of [fixed], each as close to its wanted top as that
/// allows, inside [minTop]..[maxBottom]. See the file comment.
List<double> kuteLayoutTags(
  List<KuteTagSlot> tags, {
  List<KuteTagSlot> fixed = const [],
  double minTop = 0,
  required double maxBottom,
  double gap = 2,
}) {
  if (tags.isEmpty) return const [];
  final walls = [...fixed]..sort((a, b) => a.top.compareTo(b.top));
  // The free stretches of the column between the fixed tags.
  final segments = <({double top, double bottom})>[];
  var from = minTop;
  for (final w in walls) {
    segments.add((top: from, bottom: w.top - gap));
    from = math.max(from, w.top + w.height + gap);
  }
  segments.add((top: from, bottom: maxBottom));

  // Each tag goes to the stretch its line is in; one that would cover a
  // fixed tag goes to the side its line is on, or the other side when
  // that one cannot hold it.
  final segmentOf = List<int>.filled(tags.length, 0);
  for (var i = 0; i < tags.length; i++) {
    final t = tags[i];
    final centre = t.top + t.height / 2;
    var s = 0;
    while (s < walls.length &&
        centre > walls[s].top + walls[s].height / 2) {
      s++;
    }
    // [s] is the stretch under the last fixed tag whose middle is above
    // this tag's middle. Over the wall above it, or under the one below?
    final room = segments[s].bottom - segments[s].top;
    if (room < t.height) {
      final up = s > 0 ? segments[s - 1] : null;
      final down = s + 1 < segments.length ? segments[s + 1] : null;
      if (up != null && up.bottom - up.top >= t.height) {
        s = s - 1;
      } else if (down != null && down.bottom - down.top >= t.height) {
        s = s + 1;
      }
    }
    segmentOf[i] = s;
  }

  final out = [for (final t in tags) t.top];
  for (var s = 0; s < segments.length; s++) {
    final members = [
      for (var i = 0; i < tags.length; i++)
        if (segmentOf[i] == s) i
    ];
    if (members.isEmpty) continue;
    _spread(tags, out, members, segments[s].top, segments[s].bottom, gap);
  }
  return out;
}

/// Moves [members] of [tags] apart inside [top]..[bottom], in the order of
/// their wanted tops, by the least that clears them.
void _spread(List<KuteTagSlot> tags, List<double> out, List<int> members,
    double top, double bottom, double gap) {
  members.sort((a, b) {
    final byTop = tags[a].top.compareTo(tags[b].top);
    return byTop != 0 ? byTop : a.compareTo(b);
  });
  // Into the stretch, from its ceiling down: a tag starts no higher than
  // the one above it ends.
  var least = top;
  for (final i in members) {
    if (out[i] < least) out[i] = least;
    least = out[i] + tags[i].height + gap;
  }
  // Back up from the floor, for a column pushed past it.
  var floor = bottom;
  for (var k = members.length - 1; k >= 0; k--) {
    final i = members[k];
    final lowest = math.max(top, floor - tags[i].height);
    if (out[i] > lowest) out[i] = lowest;
    floor = out[i] - gap;
  }
}
