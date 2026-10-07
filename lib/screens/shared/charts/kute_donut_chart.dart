// lib/screens/shared/charts/kute_donut_chart.dart
//
// The engine's donut: a ring of slices for an allocation (the Portfolio's
// Open tab, Predictions and Investing). In the engine's idiom:
//
//   * the data painter sits behind a RepaintBoundary and never reads
//     Theme/MediaQuery: the hosting widget resolves colours once per build
//     and hands them down;
//   * one entrance: the slices sweep in clockwise from twelve o'clock
//     (600ms easeOutCubic), drawn at once under Reduce Motion;
//   * value changes (live prices) morph each slice's share over ~450ms
//     easeOutCubic, keyed by the slice's id, so a tick never restarts the
//     sweep and a slice that changes rank glides to its new place;
//   * the venue charts' gestures: a tap picks the slice under the finger
//     (the centre or outside the ring clears), a long press then slide
//     walks the ring; selection haptics throttled to ~10/s, as the scrub;
//   * the picked slice pops out and thickens (~180ms), the one it replaced
//     settles back at the same time;
//   * every slice is its own semantics node (its label, selectable by a
//     tap), so a screen reader reads the ring slice by slice.
//
// The ring's colours are the theme's categorical chart palette
// (AppColorsExtension.chartCategorical: five hues and a muted grey for
// "Other", stepped per mode, never the accent or the market up/down pair).
// [KuteCategoryColorSlots] hands them out: the first time a donut draws,
// slot order is slice order (the largest slice takes the first hue); from
// then on a category keeps its hue while values move, so a slice that
// changes rank never repaints.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';


/// Which palette slot each category of a donut wears. Colour follows the
/// category, never its rank: a category keeps its slot for as long as it
/// stays in the donut, a newcomer takes the lowest free slot, and the
/// grouped "Other" always wears the palette's last (grey) slot. The first
/// assignment is rank order, so slot order starts out as slice order.
class KuteCategoryColorSlots {
  final Map<Object, int> _slots = {};

  /// Forget every assignment (another set of categories in the same place).
  void reset() => _slots.clear();

  /// The slot of each of [named] (the categories with their own slice,
  /// largest first). A slot past the palette's hues (a sixth category
  /// kept because it alone would have been "Other") wears the grey.
  Map<Object, int> assign(List<Object> named) {
    final present = named.toSet();
    _slots.removeWhere((key, _) => !present.contains(key));
    for (final key in named) {
      if (_slots.containsKey(key)) continue;
      final taken = _slots.values.toSet();
      var slot = 0;
      while (taken.contains(slot)) {
        slot++;
      }
      _slots[key] = slot;
    }
    return Map.unmodifiable(_slots);
  }

  /// The colour of a named category's [slot] or, with [other], the grey
  /// last slot, from the theme's categorical [palette].
  static Color colorOf(List<Color> palette, {int? slot, bool other = false}) {
    if (palette.isEmpty) return Colors.transparent;
    if (other || slot == null || slot >= palette.length - 1) {
      return palette.last;
    }
    return palette[slot];
  }
}

/// One slice of a [KuteDonutChart]. [id] keeps its identity across value
/// changes (the morph and the selection follow it); [value] is any
/// non-negative weight, the ring shows each slice's share of the sum.
class KuteDonutSegment {
  final Object id;
  final double value;
  final Color color;

  /// What a screen reader says for the slice ("Bitcoin, 42%, $1,234").
  final String semanticsLabel;

  const KuteDonutSegment({
    required this.id,
    required this.value,
    required this.color,
    required this.semanticsLabel,
  });
}

/// Where a point falls on a donut.
enum KuteDonutZone { centre, ring, outside }

/// The ring's geometry inside a canvas of [size]: the slice stroke runs on
/// a circle of [radius] around [center], [thickness] wide; [pop] and
/// [extra] are the room kept for a picked slice (pushed out by [pop],
/// [extra] thicker).
class KuteDonutGeometry {
  final Offset center;
  final double radius;
  final double thickness;
  final double pop;
  final double extra;

  const KuteDonutGeometry._(
      this.center, this.radius, this.thickness, this.pop, this.extra);

  factory KuteDonutGeometry.of(Size size,
      {required double thickness, double pop = 4, double extra = 6}) {
    final maxR = math.min(size.width, size.height) / 2;
    final radius = math.max(0.0, maxR - pop - (thickness + extra) / 2);
    return KuteDonutGeometry._(
        size.center(Offset.zero), radius, thickness, pop, extra);
  }

  double get inner => radius - thickness / 2;
  double get outer => radius + thickness / 2;
}

/// Angle of [p] around [g]'s centre, clockwise from twelve o'clock, in
/// [0, 2π).
double kuteDonutAngle(Offset p, KuteDonutGeometry g) {
  final d = p - g.center;
  var a = math.atan2(d.dy, d.dx) + math.pi / 2;
  if (a < 0) a += 2 * math.pi;
  if (a >= 2 * math.pi) a -= 2 * math.pi;
  return a;
}

/// Which of [fractions] (shares summing to 1, in ring order from twelve
/// o'clock) lies at [angle]. Null when there are none.
int? kuteDonutIndexAtAngle(double angle, List<double> fractions) {
  if (fractions.isEmpty) return null;
  final t = angle / (2 * math.pi);
  var acc = 0.0;
  for (var i = 0; i < fractions.length; i++) {
    acc += fractions[i];
    if (t < acc) return i;
  }
  return fractions.length - 1;
}

/// Where [p] falls: inside the hole, on the ring (with [slack] px of
/// forgiveness either side, so a thin ring is easy to hit) or outside it.
KuteDonutZone kuteDonutZoneAt(Offset p, KuteDonutGeometry g,
    {double slack = 12}) {
  final r = (p - g.center).distance;
  if (r < g.inner - slack) return KuteDonutZone.centre;
  if (r > g.outer + g.pop + g.extra / 2 + slack) return KuteDonutZone.outside;
  return KuteDonutZone.ring;
}

/// Shares of [values] (non-positive and non-finite weights count as zero),
/// summing to 1; all zeros when nothing is positive.
List<double> kuteDonutFractions(List<double> values) {
  final clean = [for (final v in values) v.isFinite && v > 0 ? v : 0.0];
  final total = clean.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return List.filled(values.length, 0);
  return [for (final v in clean) v / total];
}

class KuteDonutChart extends StatefulWidget {
  /// The slices in ring order, clockwise from twelve o'clock.
  final List<KuteDonutSegment> segments;

  /// The picked slice's id, or null. The host owns the selection (a legend
  /// picks the same slice).
  final Object? selectedId;

  /// A gesture picked [id] (null: the centre or outside the ring was
  /// tapped, which clears). Only called when it changes the selection.
  final ValueChanged<Object?> onSelected;

  /// What sits in the hole (the total, or the picked slice).
  final Widget? center;

  final double diameter;
  final double thickness;

  /// The faint full ring behind the slices (seen while they sweep in).
  final Color trackColor;

  /// What a screen reader says for the chart as a whole.
  final String? semanticsLabel;

  const KuteDonutChart({
    super.key,
    required this.segments,
    required this.onSelected,
    required this.trackColor,
    this.selectedId,
    this.center,
    this.diameter = 176,
    this.thickness = 18,
    this.semanticsLabel,
  });

  @override
  State<KuteDonutChart> createState() => _KuteDonutChartState();
}

class _KuteDonutChartState extends State<KuteDonutChart>
    with TickerProviderStateMixin {
  static const _sweepDuration = Duration(milliseconds: 600);
  static const _morphDuration = Duration(milliseconds: 450);
  static const _popDuration = Duration(milliseconds: 180);

  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: _sweepDuration);
  late final Animation<double> _sweepCurve =
      CurvedAnimation(parent: _sweep, curve: Curves.easeOutCubic);

  late final AnimationController _morph =
      AnimationController(vsync: this, duration: _morphDuration, value: 1);
  late final Animation<double> _morphCurve =
      CurvedAnimation(parent: _morph, curve: Curves.easeOutCubic);

  late final AnimationController _pop =
      AnimationController(vsync: this, duration: _popDuration, value: 1);
  late final Animation<double> _popCurve =
      CurvedAnimation(parent: _pop, curve: Curves.easeOutCubic);

  bool _reduceMotion = false;
  bool _entranceStarted = false;

  /// The morph's two ends, by slice id: share and colour. [_order] is the
  /// ring order drawn (the target's, then any slice on its way out).
  Map<Object, (double, Color)> _from = {};
  Map<Object, (double, Color)> _to = {};
  List<Object> _order = [];

  Object? _previousSelected;
  DateTime _lastHaptic = DateTime(0);

  @override
  void initState() {
    super.initState();
    _to = _targetOf(widget.segments);
    _from = _to;
    _order = [for (final s in widget.segments) s.id];
    _morph.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Slices that left are gone once the morph lands.
        _order = _order.where(_to.containsKey).toList();
        _from = _to;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (_reduceMotion) {
        _sweep.value = 1;
      } else {
        _sweep.forward();
      }
    } else if (_reduceMotion) {
      _sweep.value = 1;
      _morph.value = 1;
      _pop.value = 1;
    }
  }

  static Map<Object, (double, Color)> _targetOf(List<KuteDonutSegment> s) {
    final f = kuteDonutFractions([for (final x in s) x.value]);
    return {for (var i = 0; i < s.length; i++) s[i].id: (f[i], s[i].color)};
  }

  /// The shares and colours on screen right now (mid-morph included).
  Map<Object, (double, Color)> _current() {
    final t = _morphCurve.value;
    return {
      for (final id in _order)
        id: (
          lerpDouble(_from[id]?.$1 ?? 0, _to[id]?.$1 ?? 0, t)!,
          Color.lerp(_from[id]?.$2 ?? _to[id]?.$2, _to[id]?.$2 ?? _from[id]?.$2,
                  t) ??
              Colors.transparent,
        ),
    };
  }

  @override
  void didUpdateWidget(covariant KuteDonutChart old) {
    super.didUpdateWidget(old);
    final target = _targetOf(widget.segments);
    final order = [for (final s in widget.segments) s.id];
    final same = _sameTarget(target, order);
    if (!same) {
      if (_reduceMotion) {
        _from = target;
        _to = target;
        _order = order;
        _morph.value = 1;
      } else {
        // Start from what is on screen, so data landing mid-morph
        // retargets the tween instead of jumping.
        final now = _current();
        _from = now;
        _to = target;
        _order = [...order, ...now.keys.where((id) => !target.containsKey(id))];
        _morph.forward(from: 0);
      }
    }
    if (old.selectedId != widget.selectedId) {
      _previousSelected = old.selectedId;
      if (_reduceMotion) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    }
  }

  bool _sameTarget(Map<Object, (double, Color)> target, List<Object> order) {
    final drawn = _order.where(_to.containsKey).toList();
    if (drawn.length != order.length) return false;
    for (var i = 0; i < order.length; i++) {
      if (drawn[i] != order[i]) return false;
      final a = _to[order[i]]!;
      final b = target[order[i]]!;
      if ((a.$1 - b.$1).abs() > 1e-6 || a.$2 != b.$2) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _sweep.dispose();
    _morph.dispose();
    _pop.dispose();
    super.dispose();
  }

  // ── gestures ──────────────────────────────────────────────────────

  KuteDonutGeometry get _geometry =>
      KuteDonutGeometry.of(Size.square(widget.diameter),
          thickness: widget.thickness);

  /// The slice at [p], by the shares the ring is heading to.
  Object? _idAt(Offset p) {
    final segments = widget.segments;
    final i = kuteDonutIndexAtAngle(kuteDonutAngle(p, _geometry),
        kuteDonutFractions([for (final s in segments) s.value]));
    return i == null ? null : segments[i].id;
  }

  void _pick(Object? id, {bool throttle = false}) {
    if (id == widget.selectedId) return;
    if (id != null) {
      // Throttled while walking the ring, as the line chart's scrub.
      final now = DateTime.now();
      if (!throttle || now.difference(_lastHaptic).inMilliseconds > 100) {
        HapticFeedback.selectionClick();
        _lastHaptic = now;
      }
    }
    widget.onSelected(id);
  }

  void _onTapUp(TapUpDetails d) {
    final zone = kuteDonutZoneAt(d.localPosition, _geometry);
    _pick(zone == KuteDonutZone.ring ? _idAt(d.localPosition) : null);
  }

  void _onWalk(Offset p) {
    // Once walking, the angle alone picks: the finger can drift off the
    // ring without dropping the slice. The very middle has no angle.
    if ((p - _geometry.center).distance < 4) return;
    _pick(_idAt(p), throttle: true);
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    final labels = {for (final s in segments) s.id: s.semanticsLabel};
    final ring = AnimatedBuilder(
      animation: Listenable.merge([_sweep, _morph, _pop]),
      builder: (context, _) {
        final now = _current();
        return CustomPaint(
          size: Size.square(widget.diameter),
          painter: KuteDonutPainter(
            arcs: [
              for (final id in _order)
                KuteDonutArc(
                  id: id,
                  fraction: now[id]!.$1,
                  color: now[id]!.$2,
                  pop: id == widget.selectedId
                      ? _popCurve.value
                      : id == _previousSelected
                          ? 1 - _popCurve.value
                          : 0,
                ),
            ],
            sweep: _sweepCurve.value,
            thickness: widget.thickness,
            trackColor: widget.trackColor,
            selectedId: widget.selectedId,
            semanticsLabels: labels,
            onSemanticsTap: (id) => _pick(id),
          ),
        );
      },
    );
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: widget.diameter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onLongPressStart: (d) => _onWalk(d.localPosition),
          onLongPressMoveUpdate: (d) => _onWalk(d.localPosition),
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(child: ring),
              if (widget.center != null)
                // The hole: the host's label, kept inside the ring; under
                // large text it scales down as one block, never spilling
                // over the slices.
                SizedBox.square(
                  dimension: math.max(0, _geometry.inner * 2 - 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.max(0, _geometry.inner * 2 - 16)),
                      child: widget.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slice as painted: its share of the ring, its colour and how far it
/// is popped out (0 resting, 1 picked).
class KuteDonutArc {
  final Object id;
  final double fraction;
  final Color color;
  final double pop;

  const KuteDonutArc({
    required this.id,
    required this.fraction,
    required this.color,
    this.pop = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is KuteDonutArc &&
      other.id == id &&
      other.fraction == fraction &&
      other.color == color &&
      other.pop == pop;

  @override
  int get hashCode => Object.hash(id, fraction, color, pop);
}

/// The donut's data painter. Slices run clockwise from twelve o'clock with
/// a hairline gap between them (none for a lone slice); [sweep] (0 → 1)
/// reveals the ring for the entrance. Never reads Theme.
class KuteDonutPainter extends CustomPainter {
  final List<KuteDonutArc> arcs;
  final double sweep;
  final double thickness;
  final Color trackColor;

  /// Gap between neighbouring slices, in px along the ring.
  final double gap;

  /// Semantics: one node per slice that has a label.
  final Object? selectedId;
  final Map<Object, String> semanticsLabels;
  final ValueChanged<Object>? onSemanticsTap;

  KuteDonutPainter({
    required this.arcs,
    required this.sweep,
    required this.thickness,
    required this.trackColor,
    this.gap = 2,
    this.selectedId,
    this.semanticsLabels = const {},
    this.onSemanticsTap,
  });

  KuteDonutGeometry _geometry(Size size) =>
      KuteDonutGeometry.of(size, thickness: thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _geometry(size);
    if (g.radius <= 0) return;
    canvas.drawCircle(
      g.center,
      g.radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
    final visible = arcs.where((a) => a.fraction > 0).length;
    final gapAngle = visible > 1 ? gap / g.radius : 0.0;
    final limit = 2 * math.pi * sweep.clamp(0.0, 1.0);
    var start = 0.0;
    for (final arc in arcs) {
      final span = 2 * math.pi * arc.fraction;
      final from = start;
      start += span;
      if (span <= 0 || from >= limit) continue;
      final to = math.min(from + span, limit);
      // The gap is split either side of the slice, but never eats a sliver
      // whole: a tiny slice keeps at least a hair of colour.
      final half = math.min(gapAngle / 2, (to - from) * 0.3);
      final a0 = from + half;
      final a1 = to - half;
      if (a1 <= a0) continue;
      final mid = (a0 + a1) / 2 - math.pi / 2;
      final push = g.pop * arc.pop;
      final c = g.center + Offset(math.cos(mid), math.sin(mid)) * push;
      final w = thickness + g.extra * arc.pop;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: g.radius + g.extra * arc.pop / 2),
        a0 - math.pi / 2,
        a1 - a0,
        false,
        Paint()
          ..color = arc.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.butt,
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final g = _geometry(size);
        final nodes = <CustomPainterSemantics>[];
        var start = 0.0;
        for (final arc in arcs) {
          final span = 2 * math.pi * arc.fraction;
          final mid = start + span / 2 - math.pi / 2;
          start += span;
          final label = semanticsLabels[arc.id];
          if (label == null || span <= 0) continue;
          final at = g.center + Offset(math.cos(mid), math.sin(mid)) * g.radius;
          nodes.add(CustomPainterSemantics(
            key: ValueKey<Object>(arc.id),
            rect: Rect.fromCircle(center: at, radius: thickness),
            properties: SemanticsProperties(
              label: label,
              selected: arc.id == selectedId,
              button: true,
              textDirection: TextDirection.ltr,
              onTap:
                  onSemanticsTap == null ? null : () => onSemanticsTap!(arc.id),
            ),
          ));
        }
        return nodes;
      };

  @override
  bool shouldRepaint(covariant KuteDonutPainter old) =>
      old.sweep != sweep ||
      old.thickness != thickness ||
      old.trackColor != trackColor ||
      old.gap != gap ||
      !_sameArcs(old.arcs, arcs);

  @override
  bool shouldRebuildSemantics(covariant KuteDonutPainter oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.semanticsLabels.length != semanticsLabels.length ||
      semanticsLabels.entries
          .any((e) => oldDelegate.semanticsLabels[e.key] != e.value) ||
      !_sameArcs(oldDelegate.arcs, arcs);

  static bool _sameArcs(List<KuteDonutArc> a, List<KuteDonutArc> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
