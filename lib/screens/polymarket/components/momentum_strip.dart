// Momentum under a match's odds chart, drawn as a graph the way football
// "attack momentum" graphics read: a smooth filled wave around a solid
// centre line, ABOVE the line in one side's colour while that side is
// gaining win chance and BELOW it in the other's. The first side's name
// sits over the plot and the second's under it, each in its colour, so
// up and down need no legend. The axis is the game itself, from kickoff:
// while a game with a clock is in play it runs to the game's usual length,
// so the graph fills from left to right: it stops at now with a small dot,
// and the centre line runs on fainter over what is still to play. Heights
// are relative to the game's own biggest swing. A score is a dot on the
// centre line; a period or a map is named under the plot where there is
// room for its name, with a thin tick across the plot for each one named.
// Under it, as plain captions: an esports series' maps and, when the odds
// say so, the pressure line.
//
// Everything here is read from the market's odds (and the score feed for
// where the score changed). Nothing tracks the ball. The numbers come
// ready from polyGameMomentumProvider; this widget only paints them. It
// shows nothing before kickoff or until a few minutes of the game have a
// price. The first time the wave is drawn it grows out of the centre line
// (300ms, once per mount, at once under Reduce Motion); later reads redraw
// it in place.
//
// Analytics: live_momentum_viewed once per mount, live_pressure_shown once
// per pressure episode (sport, league, category; no ids).


import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/polymarket/live_game/game_esports.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_pressure.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A score (a dot on the centre line) or, with [divider], a period change
/// or a map starting on the time axis. [label] names it under the plot
/// ("HT", "Q3", "Map 2"); it gets its tick across the plot only when that
/// name is shown.
typedef MomentumNotch = ({int tMs, Color color, bool divider, String? label});

class PolyMomentumStrip extends ConsumerStatefulWidget {
  final PolyMomentumKey momentumKey;
  final String nameA;
  final String nameB;
  final Color colorA;
  final Color colorB;

  /// Where the score changed, drawn on the centre line; a period change
  /// and a set or a map won are ticks across the plot.
  final List<MomentumNotch> notches;

  /// What to write under the two ends of the axis ("0'" and "90'" for a
  /// football match); null for none.
  final String? startLabel;
  final String? endLabel;

  /// An esports series, for the map row. Null for other sports.
  final EsportsSeries? series;
  final String? homeName;
  final String? awayName;

  /// Sport, league and category, sent with this widget's events.
  final Map<String, Object> analytics;

  const PolyMomentumStrip({
    super.key,
    required this.momentumKey,
    required this.nameA,
    required this.nameB,
    required this.colorA,
    required this.colorB,
    this.notches = const [],
    this.startLabel,
    this.endLabel,
    this.series,
    this.homeName,
    this.awayName,
    this.analytics = const {},
  });

  @override
  ConsumerState<PolyMomentumStrip> createState() => _PolyMomentumStripState();
}

class _PolyMomentumStripState extends ConsumerState<PolyMomentumStrip>
    with SingleTickerProviderStateMixin {
  /// The last strip with bars, kept while a new read is under way (the
  /// totals line changing re-reads the series).
  MomentumStrip? _held;
  bool _viewed = false;
  PressureSide? _pressureShown;

  /// The wave grows out of the centre line the first time it is drawn,
  /// once per mount: later reads redraw it in place. Under Reduce Motion
  /// it is drawn whole at once.
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _growCurve =
      CurvedAnimation(parent: _grow, curve: Curves.easeOutCubic);
  bool _grown = false;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  /// Starts the grow-in on the first frame with a wave.
  void _growOnce() {
    if (_grown) return;
    _grown = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _grow.value = 1;
    } else {
      _grow.forward(from: 0);
    }
  }

  bool get _live => widget.momentumKey.endMs == null;

  void _trackViewed(MomentumStrip strip) {
    if (_viewed) return;
    _viewed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.track('live_momentum_viewed', params: {
        ...widget.analytics,
        'is_live': _live,
        'bucket_minutes': strip.bucketMs ~/ 60000,
        'has_totals': widget.momentumKey.overToken != null,
      });
    });
  }

  void _trackPressure(PressureSignal? signal) {
    if (signal == null) {
      _pressureShown = null;
      return;
    }
    if (_pressureShown == signal.side) return;
    _pressureShown = signal.side;
    final params = <String, Object>{
      ...widget.analytics,
      'confirmed_by_totals': signal.confirmedByTotals,
      'minutes': signal.minutes,
      'drift_points': double.parse((signal.drift * 100).toStringAsFixed(1)),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.track('live_pressure_shown', params: params);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final momentum = ref.watch(polyGameMomentumProvider(widget.momentumKey));
    var strip = momentum.strip;
    if (!strip.isEmpty) {
      _held = strip;
    } else if (!momentum.loaded && _held != null) {
      strip = _held!;
    }
    final series = widget.series;
    final hasMaps = series != null && !series.isEmpty;
    final drawn = strip.readable;
    // Nothing honest to draw yet (no price history for the game window,
    // or the game has only just started).
    if (!drawn && !hasMaps) return const SizedBox.shrink();
    if (drawn) {
      _trackViewed(strip);
      _growOnce();
    }
    // Reduce Motion turned on mid-grow: the wave is whole at once.
    if (_grow.isAnimating && MediaQuery.disableAnimationsOf(context)) {
      _grow.value = 1;
    }
    final pressure = _live && drawn ? momentum.pressure : null;
    _trackPressure(pressure);

    final caption = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.3,
    );
    Widget side(String name, Color color) => Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: caption.copyWith(color: color),
        );
    return Padding(
      padding: EdgeInsets.only(top: 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.polyMomentumTitle,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (drawn) ...[
            SizedBox(height: 10.h),
            // Up is the first side, down the second: each named inside
            // the plot on its own edge, in its colour. The wave keeps
            // clear of the two bands the names sit in.
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final labels = _axisLabels(context, strip, caption, width);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(width, 96.h),
                          painter: _MomentumPainter(
                            strip: strip,
                            colorA: widget.colorA,
                            colorB: widget.colorB,
                            line: c.borderSubtle,
                            ground: context.isDark
                                ? c.gradientBottom
                                : c.background,
                            notches: widget.notches,
                            ticks: [
                              for (final l in labels)
                                if (l.tMs != null) l.tMs!,
                            ],
                            live: _live,
                            band: 18.h,
                            grow: _growCurve,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: side(widget.nameA, widget.colorA),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: side(widget.nameB, widget.colorB),
                      ),
                    ],
                  ),
                  if (labels.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: SizedBox(
                        height: 16.h,
                        width: width,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final l in labels)
                              Positioned(
                                left: l.left,
                                top: 0,
                                child: Text(l.text, maxLines: 1, style: caption),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
          if (hasMaps) ...[
            SizedBox(height: 8.h),
            Text(_mapsLine(l10n, series), style: caption),
          ],
          if (pressure != null) ...[
            SizedBox(height: 8.h),
            Text(_pressureLine(l10n, pressure), style: caption),
          ],
        ],
      ),
    );
  }

  /// The names under the plot that fit in [width]: the axis's two ends and
  /// each named tick, measured in [style] and placed under its instant (a
  /// tick's name is centred on it, kept inside the plot). A name that
  /// would run into another is left out, the ends and the latest period
  /// first ([momentumAxisLabelsKept]). [tMs] is set on a tick's name.
  List<({double left, String text, int? tMs})> _axisLabels(BuildContext context,
      MomentumStrip strip, TextStyle style, double width) {
    final span = strip.axisEndMs - strip.startMs;
    final scaler = MediaQuery.textScalerOf(context);
    // Measured in the face the names are drawn in.
    final drawn = DefaultTextStyle.of(context).style.merge(style);
    double measure(String text) => (TextPainter(
          text: TextSpan(text: text, style: drawn),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout())
            .width;

    final all = <({double left, double right, String text, int? tMs})>[];
    void add(String text, double at, {int? tMs}) {
      final w = measure(text);
      final left = at == 0.0
          ? 0.0
          : at == 1.0
              ? width - w
              : (at * width - w / 2).clamp(0.0, width - w < 0 ? 0.0 : width - w);
      all.add((left: left, right: left + w, text: text, tMs: tMs));
    }

    if (widget.startLabel != null) add(widget.startLabel!, 0.0);
    int? latest;
    for (final n in widget.notches) {
      final label = n.label;
      if (label == null || label.isEmpty || span <= 0) continue;
      if (n.tMs <= strip.startMs || n.tMs >= strip.axisEndMs) continue;
      latest = all.length;
      add(label, (n.tMs - strip.startMs) / span, tMs: n.tMs);
    }
    if (widget.endLabel != null) add(widget.endLabel!, 1.0);
    final kept = momentumAxisLabelsKept(
      [for (final l in all) (left: l.left, right: l.right)],
      gap: 8.w,
      latest: latest,
    );
    return [
      for (final i in kept) (left: all[i].left, text: all[i].text, tMs: all[i].tMs)
    ];
  }

  /// "Pressure: Portugal. Read from the odds only: …", as one caption.
  String _pressureLine(AppLocalizations l10n, PressureSignal signal) {
    final a = signal.side == PressureSide.a;
    final points = formatPolyPoints(signal.drift * 100);
    final minutes = '${signal.minutes}';
    final label = l10n.polyPressureLabel(a ? widget.nameA : widget.nameB);
    final why = signal.confirmedByTotals
        ? l10n.polyPressureCaptionTotals(points, minutes)
        : l10n.polyPressureCaption(points, minutes);
    return '$label. $why';
  }

  /// The series map by map as one caption ("Map 1: Team Liquid · Map 2
  /// live 0–0"): what went before the timeline starts, each map seen won,
  /// and the map in play.
  String _mapsLine(AppLocalizations l10n, EsportsSeries series) => [
        if (series.earlierHome + series.earlierAway > 0)
          l10n.polyMapsEarlier('${series.earlierHome}–${series.earlierAway}'),
        for (final m in series.maps)
          if (m.live)
            '${l10n.polyMarkerMap('${m.number}')} '
                '${l10n.polyPillLive.toLowerCase()} '
                '${m.mapHome ?? 0}–${m.mapAway ?? 0}'
          else
            () {
              final team = m.winner == null
                  ? null
                  : (m.winner! > 0 ? widget.homeName : widget.awayName);
              return team == null || team.isEmpty
                  ? l10n.polyMarkerMapWon('${m.number}')
                  : '${l10n.polyMarkerMap('${m.number}')}: $team';
            }(),
      ].join(' · ');
}

class _MomentumPainter extends CustomPainter {
  final MomentumStrip strip;
  final Color colorA;
  final Color colorB;

  /// The centre line and the period ticks (the sheet's divider colour).
  final Color line;

  /// The sheet's ground, ringing a score dot so it reads over a bar.
  final Color ground;
  final List<MomentumNotch> notches;

  /// The instants (epoch ms) that get a tick across the plot: the periods
  /// named under it.
  final List<int> ticks;

  /// The game is in play: the wave stops at now, with a dot.
  final bool live;

  /// The height kept free at the top and the bottom for the sides' names.
  final double band;

  /// How far the wave has grown out of the centre line (0..1): 1 at rest.
  final Animation<double> grow;

  _MomentumPainter({
    required this.strip,
    required this.colorA,
    required this.colorB,
    required this.line,
    required this.ground,
    required this.notches,
    required this.ticks,
    required this.live,
    required this.band,
    required this.grow,
  }) : super(repaint: grow);

  @override
  void paint(Canvas canvas, Size size) {
    final span = strip.axisEndMs - strip.startMs;
    if (span <= 0 || strip.bars.isEmpty) return;
    final mid = size.height / 2;
    // Whole at rest; on first show the wave rises out of the centre line.
    final g = grow.value;
    final half = g >= 1 ? mid - band : (mid - band) * g;
    double x(int tMs) => (tMs - strip.startMs) / span * size.width;

    // The wave: one point per bucket at its middle, joined by a smooth
    // curve and closed along the centre line. Above the line it is side
    // A's, below it side B's.
    final wave = momentumWave(strip);
    final points = <Offset>[
      for (var i = 0; i < strip.bars.length; i++)
        Offset(
          x((strip.bars[i].startMs + strip.bars[i].endMs) ~/ 2),
          mid - wave[i] * half,
        ),
    ];
    if (points.isNotEmpty) {
      final left = x(strip.bars.first.startMs);
      final right = x(strip.bars.last.endMs);
      final path = Path()
        ..moveTo(left, mid)
        ..lineTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final between = Offset(
            (prev.dx + points[i].dx) / 2, (prev.dy + points[i].dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, between.dx, between.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      // A game in play keeps its height up to now and stops there; a
      // finished one comes back to the line.
      if (live) path.lineTo(right, points.last.dy);
      path
        ..lineTo(right, mid)
        ..close();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, size.width, mid));
      canvas.drawPath(path, Paint()..color = colorA);
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, mid, size.width, size.height));
      canvas.drawPath(path, Paint()..color = colorB);
      canvas.restore();
    }
    // The centre line across the whole game: fainter over the part still
    // to be played.
    final now = live ? x(strip.endMs).clamp(0.0, size.width) : size.width;
    final hairline = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(now, mid), hairline);
    if (now < size.width) {
      canvas.drawLine(
        Offset(now, mid),
        Offset(size.width, mid),
        Paint()
          ..color = line.withValues(alpha: line.a * 0.5)
          ..strokeWidth = 1,
      );
    }
    final tick = Paint()
      ..color = line
      ..strokeWidth = 0.5;
    for (final t in ticks) {
      if (t < strip.startMs || t > strip.axisEndMs) continue;
      canvas.drawLine(
          Offset(x(t), band), Offset(x(t), size.height - band), tick);
    }
    for (final n in notches) {
      if (n.divider || n.tMs < strip.startMs || n.tMs > strip.axisEndMs) {
        continue;
      }
      final nx = x(n.tMs);
      canvas.drawCircle(Offset(nx, mid), 4.5, Paint()..color = ground);
      canvas.drawCircle(Offset(nx, mid), 3.5, Paint()..color = n.color);
    }
    // Now: a small dot where the wave stops, in the colour of the side
    // it is with.
    if (live && points.isNotEmpty) {
      final tip = Offset(now, points.last.dy);
      final color = tip.dy < mid - 0.5
          ? colorA
          : tip.dy > mid + 0.5
              ? colorB
              : line;
      canvas.drawCircle(tip, 4, Paint()..color = ground);
      canvas.drawCircle(tip, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MomentumPainter old) =>
      !identical(old.strip, strip) ||
      !identical(old.notches, notches) ||
      !listEquals(old.ticks, ticks) ||
      old.live != live ||
      old.colorA != colorA ||
      old.colorB != colorB ||
      old.line != line ||
      old.ground != ground ||
      old.band != band ||
      old.grow != grow;
}
