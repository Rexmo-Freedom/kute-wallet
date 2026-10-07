// A header title shrinks to fit its lines instead of being cut: whole at
// 320, 375 and 430 wide, at the standard text size and at 1.3x, never
// drawn under 70% of its standard size, and ellipsized only past that.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/fitted_title.dart';

const _long = 'Counter-Strike: PARIVISION vs Natus Vincere (BO3) - '
    'ESL Pro League Season 22';

const _style = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.3,
  height: 1.2,
);

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

/// A market header at [width], sized as the app sizes it (its 430-wide
/// design scaled to the width, as ScreenUtil's .w and .sp do): close
/// button, image, the title at 18.sp, the star.
Future<void> _pumpHeader(WidgetTester tester,
    {required double width,
    double scale = 1,
    String text = _long,
    int maxLines = 2}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final k = width / 430;
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Inter'),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const SizedBox(width: 36, height: 36),
                SizedBox(width: 8 * k),
                SizedBox(width: 32 * k, height: 32 * k),
                SizedBox(width: 8 * k),
                Expanded(
                  child: FittedTitle(text,
                      key: const ValueKey('title'),
                      style: _style.copyWith(fontSize: 18 * k),
                      maxLines: maxLines),
                ),
                SizedBox(width: 8 * k),
                const SizedBox(width: 22, height: 22),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
}

Finder get _text => find.descendant(
    of: find.byKey(const ValueKey('title')), matching: find.byType(Text));

double _size(WidgetTester tester) =>
    tester.widget<Text>(_text).style!.fontSize!;

bool _cut(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(_text).didExceedMaxLines;

void main() {
  testWidgets('a title that fits keeps its size', (tester) async {
    await _loadInter(tester);
    await _pumpHeader(tester, width: 430, text: 'Fed decision in October?');
    expect(_size(tester), 18);
    expect(_cut(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
          'the long game title at ${width.toInt()} wide, text x$scale: '
          'whole on two lines', (tester) async {
        await _loadInter(tester);
        await _pumpHeader(tester, width: width, scale: scale);
        final base = 18 * width / 430;
        expect(_cut(tester), isFalse);
        expect(tester.widget<Text>(_text).data, _long);
        expect(_size(tester), lessThan(base));
        // Drawn no smaller than 70% of the standard 18.sp.
        expect(
            _size(tester) * scale, greaterThanOrEqualTo(base * 0.7 - 0.01));
        // Two lines, not one squeezed line.
        final lines = tester
            .renderObject<RenderParagraph>(_text)
            .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: _long.length))
            .map((b) => b.top.round())
            .toSet();
        expect(lines, hasLength(2));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a one-line ticker shrinks on its line', (tester) async {
    await _loadInter(tester);
    await _pumpHeader(tester,
        width: 320, text: 'SUPERLONGTICKERNAME', maxLines: 1);
    expect(_cut(tester), isFalse);
    expect(_size(tester), lessThan(18 * 320 / 430));
  });

  testWidgets('past the floor the title ends in an ellipsis', (tester) async {
    await _loadInter(tester);
    await _pumpHeader(tester, width: 320, text: List.filled(12, _long).join());
    expect(_size(tester), closeTo(18 * 320 / 430 * 0.7, 1e-9));
    expect(_cut(tester), isTrue);
    expect(tester.widget<Text>(_text).overflow, TextOverflow.ellipsis);
  });

  test('the measure alone: largest size that fits, the floor otherwise', () {
    final roomy = fittedTitleFontSize(
        text: 'Short', style: _style, maxWidth: 400);
    expect(roomy, 18);
    final tight = fittedTitleFontSize(
        text: List.filled(40, 'word').join(' '), style: _style, maxWidth: 50);
    expect(tight, closeTo(12.6, 1e-9));
    // Under 1.3x the floor is the same size on screen.
    final scaled = fittedTitleFontSize(
        text: List.filled(40, 'word').join(' '),
        style: _style,
        maxWidth: 50,
        textScaler: const TextScaler.linear(1.3));
    expect(scaled * 1.3, closeTo(12.6, 1e-9));
  });
}
