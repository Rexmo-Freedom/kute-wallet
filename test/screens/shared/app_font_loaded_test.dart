import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

/// Inter is in the engine before any text is laid out (`main.dart` and the
/// tests that need it await [loadAppFonts]). When it landed mid-test instead, a
/// figure measured in the fallback font and then changed only in colour
/// (the P&L headline from red −$6.38 to green +$40.00, its `$` in place)
/// was repainted in Inter inside the old box: TextPainter's
/// `debugSize == size` assertion on CI.
void main() {
  // Loaded for this file the way main.dart loads it before the first
  // frame.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // First in the file, before any theme is built here: the font must
  // already be registered, not merely requested.
  test('the app font is loaded before the first layout', () {
    final painter = TextPainter(
      text: TextSpan(
          text: '.',
          style:
              TextStyle(fontFamily: GoogleFonts.inter().fontFamily, fontSize: 32)),
      textDirection: TextDirection.ltr,
    )..layout();
    // The test fallback font draws every glyph a full em wide; Inter's
    // full stop is under a third of one.
    expect(painter.width, lessThan(16));
    painter.dispose();
  });

  testWidgets('a figure that changes only colour repaints in its own box',
      (tester) async {
    Widget figure(String text, Color color) => MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RollingNumberText(
                  text: text,
                  dimColor: Colors.grey,
                  style: TextStyle(
                      fontSize: 31, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ),
          ),
        );
    final dollar = find.text(r'$');
    await tester.pumpWidget(figure('−\$6.38', Colors.red));
    final before = tester.getSize(dollar);
    await tester.pumpWidget(figure('+\$40.00', Colors.green));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(dollar), before);
    await tester.pump(const Duration(seconds: 1));
  });
}
