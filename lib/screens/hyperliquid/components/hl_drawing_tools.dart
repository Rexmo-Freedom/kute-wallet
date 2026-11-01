// lib/screens/hyperliquid/components/hl_drawing_tools.dart
//
// The pieces of the Advanced chart's drawing tools that are not the
// chart itself: the rail's buttons and their glyphs (drawn here, in the
// chart's thin-line language, so each tool reads at a glance), the small
// floating toolbar over a selected drawing, and the loupe that shows the
// exact point under the finger while one is placed or moved.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/shared/charts/kute_chart_indicators.dart'
    show kuteIndEma9Color;
import 'package:kute/theme/app_theme.dart';

/// The app's selected-pill look (the range row's thumb in
/// kute_trend_chart.dart): white with a hairline and a soft shadow in
/// light, the surface with a subtler hairline in dark.
BoxDecoration hlSelectedPillDecoration(BuildContext context,
    {required double radius}) {
  final c = context.colors;
  final light = !context.isDark;
  return BoxDecoration(
    color: light ? Colors.white : c.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: light ? c.border : c.borderSubtle,
      width: light ? 1.0 : 0.5,
    ),
    boxShadow: [
      BoxShadow(
        color: light
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.transparent,
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

// ───────────────────────────── glyphs ─────────────────────────────

/// What a rail glyph pictures. [cursor] is the select/edit crosshair.
enum HlRailGlyph {
  cursor,
  trendline,
  level,
  rect,
  fibonacci,
  measure,
  text,
  solidLine,
  dashedLine,
  extendRight,
}

/// The rail glyph for a drawing tool (the tools off the rail borrow the
/// nearest one, for the toolbar's hint only).
HlRailGlyph hlGlyphForTool(ChartDrawingTool? tool) {
  switch (tool) {
    case null:
      return HlRailGlyph.cursor;
    case ChartDrawingTool.level:
    case ChartDrawingTool.horizontalRay:
      return HlRailGlyph.level;
    case ChartDrawingTool.rect:
    case ChartDrawingTool.parallelChannel:
      return HlRailGlyph.rect;
    case ChartDrawingTool.fibonacci:
      return HlRailGlyph.fibonacci;
    case ChartDrawingTool.priceRange:
    case ChartDrawingTool.dateRange:
    case ChartDrawingTool.dateAndPriceRange:
    case ChartDrawingTool.longPosition:
    case ChartDrawingTool.shortPosition:
      return HlRailGlyph.measure;
    case ChartDrawingTool.text:
      return HlRailGlyph.text;
    case ChartDrawingTool.trendline:
    case ChartDrawingTool.ray:
    case ChartDrawingTool.extendedLine:
    case ChartDrawingTool.verticalLine:
      return HlRailGlyph.trendline;
  }
}

/// A 20 x 20 line drawing of one tool, 1.5 px strokes with round caps.
class HlGlyph extends StatelessWidget {
  const HlGlyph(this.glyph, {super.key, required this.color, this.size = 20});
  final HlRailGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _GlyphPainter(glyph, color),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final HlRailGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void dot(Offset o, [double r = 2.1]) {
      canvas.drawCircle(o, r, fill);
    }

    switch (glyph) {
      case HlRailGlyph.cursor:
        // A crosshair: four arms around an open centre and its point.
        canvas.drawLine(const Offset(10, 2.5), const Offset(10, 7), line);
        canvas.drawLine(const Offset(10, 13), const Offset(10, 17.5), line);
        canvas.drawLine(const Offset(2.5, 10), const Offset(7, 10), line);
        canvas.drawLine(const Offset(13, 10), const Offset(17.5, 10), line);
        dot(const Offset(10, 10), 1.1);
      case HlRailGlyph.trendline:
        canvas.drawLine(const Offset(5, 15), const Offset(15, 5), line);
        dot(const Offset(4.5, 15.5));
        dot(const Offset(15.5, 4.5));
      case HlRailGlyph.level:
        canvas.drawLine(const Offset(2.5, 10), const Offset(7.4, 10), line);
        canvas.drawLine(const Offset(12.6, 10), const Offset(17.5, 10), line);
        canvas.drawCircle(const Offset(10, 10), 2.4, line);
      case HlRailGlyph.rect:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(4, 5.5, 16, 14.5), const Radius.circular(1)),
            line);
        dot(const Offset(4, 5.5), 1.9);
        dot(const Offset(16, 14.5), 1.9);
      case HlRailGlyph.fibonacci:
        for (final y in [4.0, 8.0, 12.0, 16.0]) {
          canvas.drawLine(Offset(3, y), Offset(17, y), line);
        }
        canvas.drawLine(
            const Offset(4, 16),
            const Offset(16, 4),
            Paint()
              ..color = color.withValues(alpha: 0.55)
              ..strokeWidth = 1.1
              ..strokeCap = StrokeCap.round);
      case HlRailGlyph.measure:
        // A ruler laid on the diagonal, its ticks along one edge.
        canvas.save();
        canvas.translate(10, 10);
        canvas.rotate(-0.785398);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset.zero, width: 19, height: 7.5),
                const Radius.circular(1.5)),
            line);
        for (var i = -2; i <= 2; i++) {
          final x = i * 3.4;
          canvas.drawLine(Offset(x, -3.75),
              Offset(x, i.isEven ? -0.6 : -1.9), line..strokeWidth = 1.2);
        }
        canvas.restore();
      case HlRailGlyph.text:
        canvas.drawLine(const Offset(4.5, 4.5), const Offset(15.5, 4.5), line);
        canvas.drawLine(const Offset(10, 4.5), const Offset(10, 16), line);
        canvas.drawLine(const Offset(7.5, 16), const Offset(12.5, 16), line);
      case HlRailGlyph.solidLine:
        canvas.drawLine(const Offset(3, 10), const Offset(17, 10), line);
      case HlRailGlyph.dashedLine:
        for (final x in [3.0, 8.5, 14.0]) {
          canvas.drawLine(Offset(x, 10), Offset(x + 3, 10), line);
        }
      case HlRailGlyph.extendRight:
        canvas.drawLine(const Offset(3.5, 14), const Offset(10, 10), line);
        dot(const Offset(3.5, 14), 1.8);
        dot(const Offset(10, 10), 1.8);
        canvas.drawLine(
            const Offset(10, 10),
            const Offset(17, 5.7),
            Paint()
              ..color = color.withValues(alpha: 0.6)
              ..strokeWidth = 1.5
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(const Offset(17, 5.7), const Offset(13.6, 5.2), line);
        canvas.drawLine(const Offset(17, 5.7), const Offset(15.8, 8.9), line);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

// ───────────────────────────── rail ─────────────────────────────

/// One tool on the rail: its glyph, its name on a long press, and the
/// app's white pill while it is the tool in hand. [sticky] adds a small
/// lock: the tool stays in hand after each drawing (a double tap).
class HlRailButton extends StatelessWidget {
  const HlRailButton({
    super.key,
    required this.label,
    required this.onTap,
    this.glyph,
    this.icon,
    this.selected = false,
    this.sticky = false,
  }) : assert(glyph != null || icon != null);

  final HlRailGlyph? glyph;
  final IconData? icon;
  final String label;
  final bool selected;
  final bool sticky;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = onTap == null
        ? c.textTertiary.withValues(alpha: 0.4)
        : selected
            ? c.textPrimary
            : c.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 42,
            child: Center(
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 38,
                height: 34,
                decoration: selected
                    ? hlSelectedPillDecoration(context, radius: 17)
                    : BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                            color: Colors.transparent, width: 1),
                      ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (glyph != null)
                      HlGlyph(glyph!, color: color)
                    else
                      Icon(icon, size: 19, color: color),
                    if (sticky)
                      Positioned(
                        right: 3,
                        bottom: 2,
                        child: Icon(Icons.lock_rounded,
                            key: const ValueKey('hl-rail-sticky'),
                            size: 9,
                            color: c.textPrimary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── toolbar ─────────────────────────────

/// A colour the toolbar offers: its ARGB (null = the neutral default)
/// and its name.
typedef HlDrawingSwatch = ({int? value, String label});

/// The five drawing colours, from the chart's own palette: the neutral
/// default (null, the theme's secondary text), the market's green and
/// red, amber and the indicators' blue.
List<HlDrawingSwatch> hlDrawingSwatches(AppLocalizations l10n) => [
      (value: null, label: l10n.chartNeutralColor),
      (value: AppColors.marketUp.toARGB32(), label: l10n.chartUpColor),
      (value: AppColors.marketDown.toARGB32(), label: l10n.chartDownColor),
      (value: AppColors.warning.toARGB32(), label: l10n.chartHighlightColor),
      (value: kuteIndEma9Color.toARGB32(), label: l10n.chartBlueColor),
    ];

/// The small toolbar floating over a selected drawing: its colour, solid
/// or dashed, extend (trend lines), edit (notes), lock, duplicate and
/// delete. The colour button opens the five swatches in its place.
class HlDrawingToolbar extends StatefulWidget {
  const HlDrawingToolbar({
    super.key,
    required this.drawing,
    required this.swatches,
    required this.labels,
    required this.onColor,
    required this.onToggleDashed,
    required this.onToggleLock,
    required this.onDuplicate,
    required this.onDelete,
    this.onToggleExtend,
    this.onEditNote,
  });

  final ChartDrawing drawing;
  final List<HlDrawingSwatch> swatches;
  final HlDrawingToolbarLabels labels;
  final ValueChanged<int?> onColor;
  final VoidCallback onToggleDashed;
  final VoidCallback onToggleLock;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onToggleExtend;
  final VoidCallback? onEditNote;

  @override
  State<HlDrawingToolbar> createState() => _HlDrawingToolbarState();
}

/// The toolbar's words (tooltips and screen-reader labels).
class HlDrawingToolbarLabels {
  const HlDrawingToolbarLabels({
    required this.color,
    required this.solid,
    required this.dashed,
    required this.extend,
    required this.lock,
    required this.unlock,
    required this.duplicate,
    required this.delete,
    required this.editNote,
  });
  final String color;
  final String solid;
  final String dashed;
  final String extend;
  final String lock;
  final String unlock;
  final String duplicate;
  final String delete;
  final String editNote;
}

class _HlDrawingToolbarState extends State<HlDrawingToolbar> {
  bool _palette = false;

  @override
  void didUpdateWidget(covariant HlDrawingToolbar old) {
    super.didUpdateWidget(old);
    if (old.drawing.id != widget.drawing.id) _palette = false;
  }

  Widget _button({
    required Key key,
    required String tip,
    required Widget child,
    required VoidCallback onTap,
    bool on = false,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on ? true : null,
      label: tip,
      excludeSemantics: true,
      child: Tooltip(
        message: tip,
        triggerMode: TooltipTriggerMode.longPress,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? c.textPrimary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _swatchDot(int? value, {double size = 16, bool picked = false}) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value == null ? c.textSecondary : Color(value),
        shape: BoxShape.circle,
        border: picked
            ? Border.all(color: c.textPrimary, width: 2)
            : Border.all(color: c.border, width: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.drawing;
    final l = widget.labels;
    final icon = c.textSecondary;
    final children = _palette
        ? [
            for (var i = 0; i < widget.swatches.length; i++)
              _button(
                key: ValueKey('hl-drawing-swatch-$i'),
                tip: widget.swatches[i].label,
                on: false,
                onTap: () {
                  setState(() => _palette = false);
                  widget.onColor(widget.swatches[i].value);
                },
                child: _swatchDot(widget.swatches[i].value,
                    size: 18, picked: widget.swatches[i].value == d.colorValue),
              ),
          ]
        : [
            _button(
              key: const ValueKey('hl-drawing-toolbar-color'),
              tip: l.color,
              onTap: () => setState(() => _palette = true),
              child: _swatchDot(d.colorValue),
            ),
            _button(
              key: const ValueKey('hl-drawing-toolbar-style'),
              tip: d.dashed ? l.solid : l.dashed,
              on: d.dashed,
              onTap: widget.onToggleDashed,
              child: HlGlyph(
                  d.dashed ? HlRailGlyph.dashedLine : HlRailGlyph.solidLine,
                  color: icon),
            ),
            if (widget.onToggleExtend != null)
              _button(
                key: const ValueKey('hl-drawing-toolbar-extend'),
                tip: l.extend,
                on: d.extend,
                onTap: widget.onToggleExtend!,
                child: HlGlyph(HlRailGlyph.extendRight,
                    color: d.extend ? c.textPrimary : icon),
              ),
            if (widget.onEditNote != null)
              _button(
                key: const ValueKey('hl-drawing-toolbar-note'),
                tip: l.editNote,
                onTap: widget.onEditNote!,
                child: Icon(Icons.edit_outlined, size: 18, color: icon),
              ),
            _button(
              key: const ValueKey('hl-drawing-toolbar-lock'),
              tip: d.locked ? l.unlock : l.lock,
              on: d.locked,
              onTap: widget.onToggleLock,
              child: Icon(
                  d.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 17,
                  color: d.locked ? c.textPrimary : icon),
            ),
            _button(
              key: const ValueKey('hl-drawing-toolbar-duplicate'),
              tip: l.duplicate,
              onTap: widget.onDuplicate,
              child: Icon(Icons.copy_rounded, size: 17, color: icon),
            ),
            _button(
              key: const ValueKey('hl-drawing-toolbar-delete'),
              tip: l.delete,
              onTap: widget.onDelete,
              child: Icon(Icons.delete_outline_rounded,
                  size: 19, color: AppColors.marketDown),
            ),
          ];
    return Container(
      key: const ValueKey('hl-drawing-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: hlSelectedPillDecoration(context, radius: 20),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Places the toolbar over [anchor] (the selected drawing's box on the
/// plot): centred on it and above it, below it when there is no room
/// above, always inside the plot.
class HlDrawingToolbarLayout extends SingleChildLayoutDelegate {
  HlDrawingToolbarLayout({required this.anchor, required this.plotHeight});
  final Rect anchor;
  final double plotHeight;

  static const double gap = 14;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final child = childSize;
    final maxX = (size.width - child.width - 4).clamp(4.0, double.infinity);
    final x = (anchor.center.dx - child.width / 2).clamp(4.0, maxX);
    final bottom = plotHeight.clamp(0.0, size.height);
    var y = anchor.top - gap - child.height;
    if (y < 4) y = anchor.bottom + gap;
    final maxY = (bottom - child.height - 4).clamp(4.0, double.infinity);
    return Offset(x, y.clamp(4.0, maxY));
  }

  @override
  bool shouldRelayout(covariant HlDrawingToolbarLayout old) =>
      old.anchor != anchor || old.plotHeight != plotHeight;
}

// ───────────────────────────── loupe ─────────────────────────────

/// A round magnifier held above the finger while a point is placed or
/// moved, centred on the exact point that will land (after the magnet),
/// with a hairline crosshair on it. Mounted over the plot only while a
/// finger is down; shown and hidden without animation.
class HlDrawingLoupe extends StatelessWidget {
  const HlDrawingLoupe({
    super.key,
    required this.point,
    required this.plot,
  });

  /// The point, in plot coordinates.
  final Offset point;

  /// The plot's size (the price area: width x price height).
  final Size plot;

  static const double diameter = 92;
  static const double lift = 84;

  /// Where the loupe's centre goes for [point] on a [plot]: above the
  /// finger, beside it when the top is too close, inside the plot.
  static Offset centerFor(Offset point, Size plot) {
    const r = diameter / 2;
    var center = Offset(point.dx, point.dy - lift);
    if (center.dy < r) {
      // No room above: hold it to the side away from the nearer edge.
      final left = point.dx > plot.width / 2;
      center = Offset(point.dx + (left ? -lift : lift), point.dy);
    }
    final maxX = (plot.width - r).clamp(r, double.infinity);
    final maxY = (plot.height - r).clamp(r, double.infinity);
    return Offset(center.dx.clamp(r, maxX), center.dy.clamp(r, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = !context.isDark;
    final center = centerFor(point, plot);
    return Stack(
      children: [
        Positioned(
          left: center.dx - diameter / 2,
          top: center.dy - diameter / 2,
          child: RawMagnifier(
            key: const ValueKey('hl-drawing-loupe'),
            size: const Size.square(diameter),
            magnificationScale: 1.8,
            focalPointOffset: point - center,
            decoration: MagnifierDecoration(
              shape: CircleBorder(
                side: BorderSide(
                    color: light ? c.border : c.borderSubtle,
                    width: light ? 1 : 0.5),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.10 : 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: CustomPaint(
              size: const Size.square(diameter),
              painter: _LoupeCrossPainter(c.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoupeCrossPainter extends CustomPainter {
  _LoupeCrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final o = size.center(Offset.zero);
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(o.translate(-14, 0), o.translate(-4, 0), p);
    canvas.drawLine(o.translate(4, 0), o.translate(14, 0), p);
    canvas.drawLine(o.translate(0, -14), o.translate(0, -4), p);
    canvas.drawLine(o.translate(0, 4), o.translate(0, 14), p);
    canvas.drawCircle(o, 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LoupeCrossPainter old) => old.color != color;
}
