// The Share button beside a page's big number says "Send to a friend"
// where those words fit beside the figure, else "Share" (founder, 1
// November 2026): the same button, Sal and the words, never an ellipsis.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

const _bar = KuteBarContext(label: 'Send to a friend', clip: 'share');
final _label = find.byKey(const ValueKey('kute-sal-header-label'));

Future<void> _pump(WidgetTester tester, Widget child,
    {double textScale = 1}) async {
  // The app's own face, so the words measure as they do on a phone (the
  // test font's square glyphs are twice as wide).
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
          fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
}

Widget _row(String figure) => KuteFigureShareRow(
      gap: 8,
      figure: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(figure,
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
      ),
      share: const KuteSalHeaderButton(barContext: _bar),
    );

String _shown(WidgetTester tester) => tester.widget<Text>(_label).data!;

void _expectWhole(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: _label, matching: find.byType(RichText)));
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'never an ellipsis');
}

void main() {
  testWidgets('a short figure: "Send to a friend" beside it, whole',
      (tester) async {
    await _pump(tester, _row(r'$1.23'));
    expect(_shown(tester), 'Send to a friend');
    _expectWhole(tester);
  });

  testWidgets('a long figure: "Share", the same button, whole',
      (tester) async {
    await _pump(tester, _row(r'$123,456,789.12'));
    expect(_shown(tester), 'Share');
    _expectWhole(tester);
    expect(find.byKey(const ValueKey('kute-sal-header-button')),
        findsOneWidget);
  });

  testWidgets('a larger text scale turns a figure that fitted into "Share"',
      (tester) async {
    await _pump(tester, _row(r'$66,012.5'));
    expect(_shown(tester), 'Send to a friend');
    await _pump(tester, _row(r'$66,012.5'), textScale: 1.6);
    expect(_shown(tester), 'Share');
    _expectWhole(tester);
  });

  testWidgets('a bounded box (a game sheet title row) gets "Share"',
      (tester) async {
    await _pump(
        tester,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: const KuteSalHeaderButton(barContext: _bar),
        ));
    expect(_shown(tester), 'Share');
    _expectWhole(tester);
  });
}
