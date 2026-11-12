// A contrast check over everything lettered under a widget: each Text and
// Icon on screen (both end in a RichText) is read with the fill it sits
// on, the way the eye meets it: its own colour through every Opacity
// above it, over the fills between it and the page composited in order.
//
// A sheet that changes its colour (the bet slip on an outcome's line) is
// checked with this instead of a list of the widgets someone remembered:
// a label added later is walked too.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One lettered thing and what is under it.
class InkReading {
  InkReading(this.what, this.ink, this.fill, this.isIcon);

  /// The text, or the icon's code point.
  final String what;

  /// The ink as it lands on [fill] (opacity and alpha already blended).
  final Color ink;

  /// The opaque fill under it.
  final Color fill;
  final bool isIcon;

  double get ratio => contrastRatio(ink, fill);

  @override
  String toString() =>
      '${isIcon ? 'icon' : 'text'} "$what" ${_hex(ink)} on ${_hex(fill)} '
      '= ${ratio.toStringAsFixed(2)}:1';
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

/// The WCAG 2 contrast of two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [top] painted over the opaque [under].
Color _over(Color top, Color under, [double opacity = 1]) =>
    Color.alphaBlend(top.withValues(alpha: top.a * opacity), under);

/// The fill a widget paints behind its child, if it is one of the boxes
/// the app fills with (a Container is a DecoratedBox or a ColoredBox, a
/// Material a PhysicalModel or PhysicalShape).
Color? _fillOf(Widget w) {
  if (w is ColoredBox) return w.color;
  if (w is DecoratedBox && w.position == DecorationPosition.background) {
    final d = w.decoration;
    if (d is BoxDecoration) return d.color;
    if (d is ShapeDecoration) return d.color;
  }
  if (w is PhysicalModel) return w.color;
  if (w is PhysicalShape) return w.color;
  return null;
}

double? _opacityOf(Widget w) {
  if (w is Opacity) return w.opacity;
  if (w is FadeTransition) return w.opacity.value;
  return null;
}

/// Every Text and Icon under [root] that is on screen, each with the fill
/// under it. [page] is the opaque colour behind everything (what shows
/// through where nothing above [root] is filled).
List<InkReading> readInks(WidgetTester tester, Finder root,
    {required Color page}) {
  final out = <InkReading>[];
  final texts = find.descendant(
      of: root, matching: find.byType(RichText), matchRoot: true);
  for (final element in texts.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || box.size.isEmpty) continue;
    // The chain above it, innermost first: fills and opacities.
    final chain = <({Color? fill, double? opacity})>[];
    element.visitAncestorElements((a) {
      final w = a.widget;
      final fill = _fillOf(w);
      final opacity = _opacityOf(w);
      if (fill != null || opacity != null) {
        chain.add((fill: fill, opacity: opacity));
      }
      return true;
    });
    // Outermost first: each fill is seen through the opacities above it.
    var under = page;
    var seenThrough = 1.0;
    for (final link in chain.reversed) {
      if (link.opacity case final o?) seenThrough *= o;
      if (link.fill case final f?) under = _over(f, under, seenThrough);
    }
    if (seenThrough < 0.05) continue; // Faded out: not on screen.

    final rich = element.widget as RichText;
    final isIcon = element.findAncestorWidgetOfExactType<Icon>() != null &&
        rich.text.toPlainText().runes.every((r) => r >= 0xE000);
    void visit(InlineSpan span, Color? inherited) {
      if (span is! TextSpan) return;
      final color = span.style?.color ?? inherited;
      final text = span.text;
      if (text != null && text.trim().isNotEmpty && color != null) {
        out.add(InkReading(
          isIcon
              ? 'U+${text.runes.first.toRadixString(16).toUpperCase()}'
              : text,
          _over(color, under, seenThrough),
          under,
          isIcon,
        ));
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, color);
      }
    }

    visit(rich.text, null);
  }
  return out;
}

/// Every Text under [root] reads at [text]:1 or better on its fill and
/// every Icon at [icon]:1. Returns the readings, for a count.
List<InkReading> expectInksRead(WidgetTester tester, Finder root,
    {required Color page, double text = 4.5, double icon = 3, String? reason}) {
  final inks = readInks(tester, root, page: page);
  final poor = [
    for (final i in inks)
      if (i.ratio < (i.isIcon ? icon : text)) i,
  ];
  expect(poor, isEmpty,
      reason: '${reason ?? 'contrast'}:\n${poor.join('\n')}');
  return inks;
}
