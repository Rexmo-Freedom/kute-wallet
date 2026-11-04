// The Sal pill changes what it says with the primary button's morph
// (founder, 1 November 2026; kute_morph_label.dart): on the Dollars tab
// "Search investments or Manage with AI" ↔ "Search predictions or manage
// with AI". The
// old words slide up and out over 200 ms while the new ones rise from
// below on the chip spring, frame for frame as the button's words do; the
// width heads straight for the new words on the spring (the leaving ones
// never hold it); Reduce Motion swaps at once.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/theme/app_theme.dart';

const _investing = 'Search investments or Manage with AI';
const _predictions = 'Search predictions or Manage with AI';
// The test font draws every glyph a square, so the width checks use
// labels that fit the 390 px screen.
const _short = 'Ask Sal';
const _long = 'Search or ask Sal';

final _pill = find.byKey(const ValueKey('dock-search-pill'));

class _Labels {
  _Labels(this.pill, this.button);
  final ValueNotifier<String> pill;
  final ValueNotifier<String> button;
}

Future<_Labels> _pump(
  WidgetTester tester, {
  String pill = _investing,
  String button = 'Enter an amount',
  bool reduce = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final labels = _Labels(ValueNotifier(pill), ValueNotifier(button));
  addTearDown(labels.pill.dispose);
  addTearDown(labels.button.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [aiEnabledProvider.overrideWith((_) async => true)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: labels.pill,
                builder: (_, l, __) => KuteSalPill(label: l, onTap: () {}),
              ),
              const SizedBox(height: 40),
              ValueListenableBuilder<String>(
                valueListenable: labels.button,
                builder: (_, l, __) => KuteBarPrimaryButton(
                  barContext: KuteBarContext.primary(
                      label: l, disabledLabel: l, onPrimary: () {}),
                  onAsk: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  return labels;
}

/// How far [text] sits from [rest], as a share of its own height
/// (negative: above).
double _travel(WidgetTester tester, String text, double rest) {
  final rect = tester.getRect(find.text(text));
  return (rect.top - rest) / rect.height;
}

double _opacity(WidgetTester tester, String text) => tester
    .widget<FadeTransition>(find
        .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  testWidgets(
      'Investing to Predictions: the old words slide up and out, the new rise '
      'from below, frame for frame as the button\'s words', (tester) async {
    final labels = await _pump(tester);
    final pillRest = tester.getRect(find.text(_investing)).top;
    final buttonRest = tester.getRect(find.text('Enter an amount')).top;

    labels.pill.value = _predictions;
    labels.button.value = 'Continue';
    await tester.pump();

    var lastOld = 0.0;
    var lastNew = double.infinity;
    for (var t = 0; t < 8; t++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text(_investing).evaluate().isEmpty) break;
      final pillOld = _travel(tester, _investing, pillRest);
      final pillNew = _travel(tester, _predictions, pillRest);
      final buttonOld = _travel(tester, 'Enter an amount', buttonRest);
      final buttonNew = _travel(tester, 'Continue', buttonRest);
      // The same motion as the button's words, at the same moment.
      expect(pillOld, moreOrLessEquals(buttonOld, epsilon: 0.01),
          reason: 'old words at ${20 * (t + 1)} ms');
      expect(pillNew, moreOrLessEquals(buttonNew, epsilon: 0.01),
          reason: 'new words at ${20 * (t + 1)} ms');
      expect(_opacity(tester, _investing),
          moreOrLessEquals(_opacity(tester, 'Enter an amount'), epsilon: 0.01));
      expect(_opacity(tester, _predictions),
          moreOrLessEquals(_opacity(tester, 'Continue'), epsilon: 0.01));
      // The old words go up, the new come up from below.
      expect(pillOld, lessThan(0));
      expect(pillOld, lessThanOrEqualTo(lastOld));
      expect(pillNew, lessThan(lastNew));
      lastOld = pillOld;
      lastNew = pillNew;
    }
    expect(lastOld, lessThan(-0.1), reason: 'the old words moved up');

    // The old words are gone in 200 ms, before the new have settled.
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text(_investing), findsNothing);
    expect(find.text('Enter an amount'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_predictions), findsOneWidget);
    expect(_travel(tester, _predictions, pillRest),
        moreOrLessEquals(0, epsilon: 0.001));
  });

  testWidgets(
      'the width springs straight to the new words: the leaving ones never '
      'hold it', (tester) async {
    // The widths at rest, each label on its own.
    final labels = await _pump(tester, pill: _short);
    final narrow = tester.getSize(_pill).width;
    labels.pill.value = _long;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final wide = tester.getSize(_pill).width;
    expect(wide, lessThan(390 - 40), reason: 'the label fits the screen');
    expect(narrow, lessThan(wide - 60));

    // Wide to narrow: on the way down while the old words are still
    // leaving, and down within the spring's time.
    labels.pill.value = _short;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_long), findsOneWidget,
        reason: 'the old words still leaving');
    final mid = tester.getSize(_pill).width;
    expect(mid, lessThan(wide - 10));
    expect(mid, greaterThan(narrow - 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(_pill).width, moreOrLessEquals(narrow, epsilon: 0.5));

    // Narrow to wide: growing on the spring, there at the end.
    labels.pill.value = _long;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final growing = tester.getSize(_pill).width;
    expect(growing, greaterThan(narrow));
    expect(growing, lessThan(wide));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getSize(_pill).width, moreOrLessEquals(wide, epsilon: 0.5));
  });

  testWidgets('Reduce Motion: the new words and the new width at once',
      (tester) async {
    // The width saying the long label from the start.
    await _pump(tester, pill: _long, reduce: true);
    final wide = tester.getSize(_pill).width;

    final labels = await _pump(tester, pill: _short, reduce: true);
    final narrow = tester.getSize(_pill).width;
    expect(narrow, lessThan(wide));
    labels.pill.value = _long;
    await tester.pump();
    expect(find.text(_short), findsNothing, reason: 'no leaving words');
    expect(find.text(_long), findsOneWidget);
    expect(tester.getSize(_pill).width, wide, reason: 'no width spring');
    expect(find.byType(AnimatedSize), findsNothing);
    expect(_opacity(tester, _long), 1);
  });

  testWidgets('a second line arriving or leaving slides with the words',
      (tester) async {
    final sub = ValueNotifier<String?>('Send the market');
    addTearDown(sub.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [aiEnabledProvider.overrideWith((_) async => true)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<String?>(
                valueListenable: sub,
                builder: (_, s, __) => KuteSalPill(
                    label: 'Share with your friends', sublabel: s, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    sub.value = null;
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'frame $f');
    }
    expect(find.text('Send the market'), findsNothing);
    expect(find.text('Share with your friends'), findsOneWidget);
    // The shared pieces are what moved it.
    expect(find.byType(KuteMorphLabel), findsOneWidget);
  });
}
