import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/kute_motion.dart';

// A slip's button that becomes another button (the minimum giving way to
// the "Add $X · …" door as the amount is typed) used to cross-fade, the
// two labels laid over each other mid-way. Sequential: the old one is
// gone before the new one shows.

Widget _host(String state, String label) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: ArrivalSwitcher(
            state: state,
            alignment: Alignment.bottomCenter,
            animateSize: false,
            sequential: true,
            child: Text(label),
          ),
        ),
      ),
    );

/// How visible [text] is: every fade above it, multiplied (the most
/// visible copy, when one is fading out while another fades in).
double _opacity(WidgetTester tester, String text) {
  var most = 0.0;
  for (final element in find.text(text).evaluate()) {
    var opacity = 1.0;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition) opacity *= widget.opacity.value;
      return true;
    });
    if (opacity > most) most = opacity;
  }
  return most;
}

void main() {
  testWidgets('a sequential swap never shows two labels at once',
      (tester) async {
    const before = r'Minimum $10.29';
    const after = r'Add $1.00 · Long $12.00';
    await tester.pumpWidget(_host('trade', before));
    expect(_opacity(tester, before), 1);

    await tester.pumpWidget(_host('deposit', after));
    var sawBoth = false;
    var sawNew = false;
    for (var t = 0; t <= 320; t += 8) {
      final a = _opacity(tester, before);
      final b = _opacity(tester, after);
      if (a > 0 && b > 0) sawBoth = true;
      if (b > 0) sawNew = true;
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(sawBoth, isFalse);
    expect(sawNew, isTrue);
    await tester.pumpAndSettle();
    expect(find.text(before), findsNothing);
    expect(_opacity(tester, after), 1);

    // Swapped back halfway through: still never both.
    await tester.pumpWidget(_host('trade', before));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(_host('deposit', after));
    for (var t = 0; t <= 400; t += 8) {
      expect(
          _opacity(tester, before) > 0 && _opacity(tester, after) > 0, isFalse,
          reason: 'at $t ms');
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same state updates the label in place, no fade',
      (tester) async {
    await tester.pumpWidget(_host('trade', r'Long $12.00'));
    await tester.pumpWidget(_host('trade', r'Long $12.50'));
    expect(find.text(r'Long $12.00'), findsNothing);
    expect(_opacity(tester, r'Long $12.50'), 1);
  });
}
