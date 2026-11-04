// lib/screens/polymarket/components/us_state_map.dart
//
// A map of the US states, the width it is given (never zoomed or
// panned): each state filled in the colour it is given, the rest in the
// neutral grey, the states' codes written where they fit, and a tap on a
// state handed back by its USPS code. A small state (Rhode Island,
// Delaware) also takes a tap near it. Each state that takes a tap is its
// own button for a screen reader, labelled by the caller.
//
// The outlines are the Census Bureau's (us_map_geometry.dart, public
// domain). Drawn on a canvas: 51 paths, read once.

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show polyWhiteContrast;
import 'package:kute/screens/polymarket/components/us_map_geometry.dart';
import 'package:kute/theme/app_theme.dart';

/// A path of [kUsStatePaths] ("M1 2L3 4 5 6Z…": absolute M, L and Z
/// only) as a [Path].
Path usMapPath(String d) {
  final path = Path();
  var command = 'M';
  double? x;
  for (final m in RegExp(r'[MLZ]|-?\d+(?:\.\d+)?').allMatches(d)) {
    final t = m.group(0)!;
    if (t == 'M' || t == 'L') {
      command = t;
      continue;
    }
    if (t == 'Z') {
      path.close();
      continue;
    }
    final v = double.parse(t);
    if (x == null) {
      x = v;
      continue;
    }
    if (command == 'M') {
      path.moveTo(x, v);
      command = 'L';
    } else {
      path.lineTo(x, v);
    }
    x = null;
  }
  return path;
}

/// Every state's outline, in map units, by USPS code.
final Map<String, Path> _statePaths = {
  for (final e in kUsStatePaths.entries) e.key: usMapPath(e.value),
};

/// How far (in logical pixels) from a small state's middle a tap still
/// picks it.
const double kUsMapTapSlop = 14;

/// The state [local] (a point on a map [width] wide) falls in, among
/// [tappable]: the state under it, else the nearest one whose middle is
/// within [kUsMapTapSlop]. Null for anywhere else.
String? usMapStateAt(Offset local, double width, Set<String> tappable) {
  if (width <= 0) return null;
  final scale = width / kUsMapWidth;
  final p = local / scale;
  for (final code in tappable) {
    if (_statePaths[code]?.contains(p) ?? false) return code;
  }
  String? nearest;
  var best = kUsMapTapSlop / scale;
  for (final code in tappable) {
    final at = kUsStateLabelPoints[code]?.at;
    if (at == null) continue;
    final d = (at - p).distance;
    if (d < best) {
      best = d;
      nearest = code;
    }
  }
  return nearest;
}

class UsStateMap extends StatelessWidget {
  /// Each coloured state's fill, by USPS code; any other state is grey.
  final Map<String, Color> fills;

  /// The states a tap picks.
  final Set<String> tappable;

  /// The states whose code is written on them (where it fits).
  final Set<String> labelled;

  /// The state outlined as picked; null for none.
  final String? selected;

  final ValueChanged<String>? onTapState;

  /// What a screen reader says for each state of [tappable].
  final Map<String, String> semanticLabels;

  const UsStateMap({
    super.key,
    required this.fills,
    this.tappable = const {},
    this.labelled = const {},
    this.selected,
    this.onTapState,
    this.semanticLabels = const {},
  });

  /// The grey of a state with nothing to show.
  static Color neutralOf(BuildContext context) =>
      context.isDark ? const Color(0xFF3B4148) : const Color(0xFFE3E6EB);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final size = Size(width, width * kUsMapHeight / kUsMapWidth);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTapState == null
            ? null
            : (d) {
                final code = usMapStateAt(d.localPosition, width, tappable);
                if (code == null) return;
                HapticFeedback.selectionClick();
                onTapState!(code);
              },
        child: CustomPaint(
          size: size,
          painter: _UsMapPainter(
            fills: fills,
            neutral: neutralOf(context),
            edge: context.isDark ? c.gradientBottom : c.background,
            outline: c.textPrimary,
            labelled: labelled,
            selected: selected,
            labelStyle: DefaultTextStyle.of(context).style.copyWith(
              fontSize: 9.5.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1,
              decoration: TextDecoration.none,
            ),
            tappable: tappable,
            semanticLabels: semanticLabels,
            onTapState: onTapState,
            direction: direction,
          ),
        ),
      );
    });
  }
}

class _UsMapPainter extends CustomPainter {
  final Map<String, Color> fills;
  final Color neutral;
  final Color edge;
  final Color outline;
  final Set<String> labelled;
  final String? selected;
  final TextStyle labelStyle;
  final Set<String> tappable;
  final Map<String, String> semanticLabels;
  final ValueChanged<String>? onTapState;
  final TextDirection direction;

  _UsMapPainter({
    required this.fills,
    required this.neutral,
    required this.edge,
    required this.outline,
    required this.labelled,
    required this.selected,
    required this.labelStyle,
    required this.tappable,
    required this.semanticLabels,
    required this.onTapState,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / kUsMapWidth;
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = edge
      ..strokeWidth = 0.9 / scale
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(scale);
    for (final e in _statePaths.entries) {
      fill.color = fills[e.key] ?? neutral;
      canvas.drawPath(e.value, fill);
      canvas.drawPath(e.value, border);
    }
    final picked = selected == null ? null : _statePaths[selected];
    if (picked != null) {
      canvas.drawPath(
          picked,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline
            ..strokeWidth = 2 / scale
            ..strokeJoin = StrokeJoin.round);
    }
    canvas.restore();
    // The codes, where a code fits inside its state.
    final minRoom = (labelStyle.fontSize ?? 10) * 0.75;
    for (final code in labelled) {
      final point = kUsStateLabelPoints[code];
      if (point == null || point.room * scale < minRoom) continue;
      final under = fills[code] ?? neutral;
      final tp = TextPainter(
        text: TextSpan(
          text: code,
          style: labelStyle.copyWith(
            color: polyWhiteContrast(under) >= 3
                ? Colors.white
                : const Color(0xFF1D2024),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          point.at * scale - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
        final scale = size.width / kUsMapWidth;
        final codes = tappable.toList()..sort();
        return [
          for (final code in codes)
            if (_statePaths[code] != null)
              CustomPainterSemantics(
                key: ValueKey<String>('us-state-$code'),
                rect: _scaled(_statePaths[code]!.getBounds(), scale),
                properties: SemanticsProperties(
                  label: semanticLabels[code] ?? code,
                  textDirection: direction,
                  button: true,
                  selected: code == selected,
                  onTap: onTapState == null ? null : () => onTapState!(code),
                ),
              ),
        ];
      };

  static Rect _scaled(Rect r, double s) =>
      Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);

  @override
  bool shouldRepaint(_UsMapPainter old) =>
      !mapEquals(old.fills, fills) ||
      old.neutral != neutral ||
      old.edge != edge ||
      old.outline != outline ||
      !setEquals(old.labelled, labelled) ||
      old.selected != selected ||
      old.labelStyle != labelStyle;

  @override
  bool shouldRebuildSemantics(_UsMapPainter old) =>
      !setEquals(old.tappable, tappable) ||
      !mapEquals(old.semanticLabels, semanticLabels) ||
      old.selected != selected ||
      old.onTapState != onTapState;
}
