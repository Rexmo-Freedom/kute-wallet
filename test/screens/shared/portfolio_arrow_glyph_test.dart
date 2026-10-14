import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/portfolio_arrow_glyph.dart';

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

Future<void> _pump(WidgetTester tester,
        {Listenable? pressed, bool reduce = false}) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Center(
          child: PortfolioArrowGlyph(
              color: Colors.black, size: 28, pressed: pressed),
        ),
      ),
    ));

Rect _clip(WidgetTester tester) {
  final clip = tester.widget<ClipRect>(find.descendant(
      of: find.byType(PortfolioArrowGlyph), matching: find.byType(ClipRect)));
  return clip.clipper!.getClip(const Size(100, 100));
}

void main() {
  test(
      'one play wipes the line out to the right, then draws it back in '
      'from the left, ending whole', () {
    expect(portfolioArrowSpan(0), (left: 0.0, right: 1.0));
    expect(portfolioArrowSpan(1), (left: 0.0, right: 1.0));
    final out = portfolioArrowSpan(0.2);
    expect(out.right, 1);
    expect(out.left, inExclusiveRange(0, 1));
    expect(portfolioArrowSpan(0.4), (left: 1.0, right: 1.0));
    final draw = portfolioArrowSpan(0.7);
    expect(draw.left, 0);
    expect(draw.right, inExclusiveRange(0, 1));
  });

  testWidgets(
      'a rising trend arrow that plays once on appearing, then '
      'rests whole until the next beat', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_clip(tester).width, lessThan(100));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_clip(tester), const Rect.fromLTRB(0, 0, 100, 100));
    // Nothing ticks between beats.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a press plays a quick one', (tester) async {
    final pressed = _Ping();
    addTearDown(pressed.dispose);
    await _pump(tester, pressed: pressed);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_clip(tester), const Rect.fromLTRB(0, 0, 100, 100));
    pressed.ping();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_clip(tester).width, lessThan(100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clip(tester), const Rect.fromLTRB(0, 0, 100, 100));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('holds still under Reduce Motion', (tester) async {
    await _pump(tester, reduce: true);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PortfolioArrowGlyph),
            matching: find.byType(ClipRect)),
        findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
  });
}
