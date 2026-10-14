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
              color: Colors.black, size: 30, pressed: pressed),
        ),
      ),
    ));

PortfolioGlyphPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byType(PortfolioArrowGlyph),
        matching: find.byType(CustomPaint)))
    .painter! as PortfolioGlyphPainter;

void main() {
  test('one play swaps the pie in and back, its turn ending where it began',
      () {
    for (final press in [false, true]) {
      expect(portfolioGlyphSwap(0, press: press), 0);
      expect(portfolioGlyphSwap(1, press: press), 0);
      expect(portfolioGlyphSwap(0.5, press: press), 1);
      expect(portfolioGlyphTurn(0.5, press: press), 1);
      // Two half turns: a whole turn, the rest frame again.
      expect(portfolioGlyphTurn(0.999, press: press), closeTo(2, 0.01));
      expect(portfolioGlyphTurn(1, press: press), 0);
    }
  });

  testWidgets(
      'one square glyph, playing the swap on appearing and then '
      'resting until the next beat', (tester) async {
    await _pump(tester);
    expect(
        tester.getSize(find.byType(PortfolioArrowGlyph)), const Size(30, 30));
    expect(_painter(tester).swap, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(_painter(tester).swap, 1);
    expect(_painter(tester).turn, 1);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_painter(tester).swap, 0);
    expect(_painter(tester).turn, 0);
    // Nothing ticks between beats.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a press plays a quick swap', (tester) async {
    final pressed = _Ping();
    addTearDown(pressed.dispose);
    await _pump(tester, pressed: pressed);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(_painter(tester).swap, 0);
    pressed.ping();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    expect(_painter(tester).swap, 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_painter(tester).swap, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('holds still under Reduce Motion', (tester) async {
    await _pump(tester, reduce: true);
    await tester.pump(const Duration(milliseconds: 800));
    expect(_painter(tester).swap, 0);
    expect(_painter(tester).turn, 0);
  });

  testWidgets('paints in light and dark without throwing', (tester) async {
    for (final color in [Colors.black, Colors.white]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: CustomPaint(
                  size: const Size.square(30),
                  painter:
                      PortfolioGlyphPainter(color, 3, swap: 0.5, turn: 0.7)))));
      expect(tester.takeException(), isNull);
    }
  });
}
