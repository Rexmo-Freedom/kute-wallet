// ONE CHOREOGRAPHY FOR A SWITCH (founder, 6 November 2026: "why are the
// animations here when clicking the buttons not the same as the ones from
// these buttons, as in going to the next page?"). A pill of a switch, a
// category picked in the category sheet and a sheet's next page all move
// the same way (KuteMotion.switchIn): the new content fades in and slides
// 24 px from its side on the sheet spring, never an instant swap; the
// pill's words morph on the chip spring with the pill's own width. At
// once under Reduce Motion.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

Widget _app(Widget child, {bool reduce = false}) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(body: child),
        ),
      ),
    );

double _opacity(WidgetTester tester, Finder of) => tester
    .widget<FadeTransition>(
        find.descendant(of: of, matching: find.byType(FadeTransition)).first)
    .opacity
    .value;

double _shiftOf(WidgetTester tester, Finder of) {
  final transform = tester.widget<Transform>(
      find.descendant(of: of, matching: find.byType(Transform)).first);
  return transform.transform.getTranslation().x;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('SelectionFade (the Dollars page body)', () {
    Future<StateSetter> pump(WidgetTester tester,
        {required ValueNotifier<int> selection, bool reduce = false}) async {
      late StateSetter set;
      await tester.pumpWidget(_app(StatefulBuilder(builder: (context, s) {
        set = s;
        return SelectionFade(
          selection: selection.value,
          order: selection.value,
          child: Text('page ${selection.value}'),
        );
      }), reduce: reduce));
      return set;
    }

    testWidgets(
        'a later pill comes in from the right with a fade on the sheet '
        'spring, an earlier one from the left; a rebuild never replays',
        (tester) async {
      final selection = ValueNotifier(1);
      final set = await pump(tester, selection: selection);
      final fade = find.byType(SelectionFade);
      // At rest on its first build.
      expect(_opacity(tester, fade), 1);
      expect(_shiftOf(tester, fade), 0);

      set(() => selection.value = 2);
      await tester.pump();
      expect(_opacity(tester, fade), 0, reason: 'never an instant swap');
      expect(_shiftOf(tester, fade), KuteMotion.switchSlide);
      await tester.pump(const Duration(milliseconds: 60));
      final midOpacity = _opacity(tester, fade);
      final midShift = _shiftOf(tester, fade);
      expect(midOpacity, inExclusiveRange(0, 1));
      expect(midShift, inExclusiveRange(0, KuteMotion.switchSlide));
      await tester.pump(KuteMotion.switchDuration);
      expect(_opacity(tester, fade), 1);
      expect(_shiftOf(tester, fade), closeTo(0, 0.01));

      // Back to an earlier pill: from the left.
      set(() => selection.value = 0);
      await tester.pump();
      expect(_shiftOf(tester, fade), -KuteMotion.switchSlide);
      await tester.pumpAndSettle();
      expect(_shiftOf(tester, fade), closeTo(0, 0.01));

      // The same selection rebuilt (a data refresh): nothing moves.
      set(() {});
      await tester.pump();
      expect(_opacity(tester, fade), 1);
      expect(_shiftOf(tester, fade), 0);
    });

    testWidgets('Reduce Motion: the new page is at rest at once',
        (tester) async {
      final selection = ValueNotifier(0);
      final set = await pump(tester, selection: selection, reduce: true);
      set(() => selection.value = 1);
      await tester.pump();
      final fade = find.byType(SelectionFade);
      expect(_opacity(tester, fade), 1);
      expect(_shiftOf(tester, fade), 0);
      expect(find.text('page 1'), findsOneWidget);
    });
  });

  group('SliverSelectionFade (a list after a category pick)', () {
    testWidgets(
        'the list fades and slides in from the right as one group; a tap '
        'lands on the row where it is drawn; at rest after the spring',
        (tester) async {
      var selection = 'trending';
      final taps = <int>[];
      late StateSetter set;
      await tester.pumpWidget(_app(StatefulBuilder(builder: (context, s) {
        set = s;
        return CustomScrollView(slivers: [
          SliverSelectionFade(selection: selection, slivers: [
            SliverList.builder(
              itemCount: 20,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => taps.add(i),
                child: SizedBox(height: 50, child: Text('$selection $i')),
              ),
            ),
          ]),
        ]);
      })));
      RenderKuteSliverShift shift() => tester
          .renderObject<RenderKuteSliverShift>(find.byType(KuteSliverShift));
      SliverFadeTransition fade() => tester
          .widget<SliverFadeTransition>(find.byType(SliverFadeTransition));
      expect(shift().dx, 0);
      expect(fade().opacity.value, 1);

      set(() => selection = 'live');
      await tester.pump();
      expect(fade().opacity.value, 0, reason: 'never an instant swap');
      expect(shift().dx, KuteMotion.switchSlide);
      await tester.pump(const Duration(milliseconds: 60));
      expect(fade().opacity.value, inExclusiveRange(0, 1));
      expect(shift().dx, inExclusiveRange(0, KuteMotion.switchSlide));

      // Drawn shifted right: the row is painted, and tapped, where it is.
      final row = tester.getRect(find.text('live 2'));
      expect(row.left, closeTo(shift().dx, 0.01));
      await tester.tapAt(row.topLeft + const Offset(2, 10));
      expect(taps, [2]);

      await tester.pumpAndSettle();
      expect(fade().opacity.value, 1);
      expect(shift().dx, closeTo(0, 0.01));
      expect(tester.getRect(find.text('live 2')).left, closeTo(0, 0.01));
    });
  });

  group('the pill\'s words morph', () {
    List<KutePillItem> items(String? detail) => [
          const KutePillItem(label: 'Investing'),
          KutePillItem(label: 'Predictions', detail: detail, menu: true),
        ];

    Future<StateSetter> pump(WidgetTester tester, ValueNotifier<String> detail,
        {bool reduce = false}) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late StateSetter set;
      await tester.pumpWidget(_app(Center(
        child: StatefulBuilder(builder: (context, s) {
          set = s;
          return KutePillTabs(
            items: items(detail.value),
            selectedIndex: 1,
            onTap: (_) {},
          );
        }),
      ), reduce: reduce));
      await tester.pumpAndSettle();
      return set;
    }

    /// The box the words sit in (the clip of [_PillWords]).
    Finder box(String words) => find
        .ancestor(of: find.text(words), matching: find.byType(ClipRect))
        .first;

    /// How much the words are shrunk to fit (1: full size).
    double scaleOf(WidgetTester tester, String words) =>
        tester.getRect(find.text(words)).width /
        tester.renderObject<RenderBox>(find.text(words)).size.width;

    testWidgets(
        '"Predictions · Filter" → "Predictions · Live": the old words fade '
        'out over the new from the same start while the words\' box eases '
        'between their widths, then only the new words remain', (tester) async {
      final detail = ValueNotifier('Filter');
      final set = await pump(tester, detail);
      const from = 'Predictions · Filter';
      const to = 'Predictions · Live';
      expect(find.text(from), findsOneWidget);
      final fromWidth = tester.getRect(box(from)).width;

      set(() => detail.value = 'Live');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Both words on screen, the new fading in over the old.
      expect(find.text(from), findsOneWidget);
      expect(find.text(to), findsOneWidget);
      double opacityOf(String words) => tester
          .widget<FadeTransition>(find
              .ancestor(
                  of: find.text(words), matching: find.byType(FadeTransition))
              .first)
          .opacity
          .value;
      expect(opacityOf(to), inExclusiveRange(0, 1));
      expect(opacityOf(from), inExclusiveRange(0, 1));
      // The same start: "Predictions" does not move under the fade.
      expect(tester.getRect(find.text(to)).left,
          closeTo(tester.getRect(find.text(from)).left, 0.5));
      final midWidth = tester.getRect(box(to)).width;

      await tester.pumpAndSettle();
      expect(find.text(from), findsNothing);
      expect(find.text(to), findsOneWidget);
      final toWidth = tester.getRect(box(to)).width;
      expect(toWidth, lessThan(fromWidth));
      expect(midWidth, lessThan(fromWidth - 0.5), reason: 'on its way');
      expect(midWidth, greaterThan(toWidth + 0.5), reason: 'not yet at rest');
      // At rest the box is the words' own width, nothing cut.
      expect(
          toWidth,
          closeTo(
              tester.renderObject<RenderBox>(find.text(to)).size.width, 0.5));
    });

    testWidgets(
        'a longer context: the words grow with the pill and are never '
        'squeezed into a pill still on its way', (tester) async {
      final detail = ValueNotifier('Live');
      final set = await pump(tester, detail);
      const long = 'Politics · Elections';
      set(() => detail.value = long);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(scaleOf(tester, 'Predictions · $long'), closeTo(1, 0.02),
            reason: 'frame $i: full-size words');
      }
      await tester.pumpAndSettle();
      expect(scaleOf(tester, 'Predictions · $long'), closeTo(1, 0.001));
    });

    testWidgets('Reduce Motion: the new words at once', (tester) async {
      final detail = ValueNotifier('Filter');
      final set = await pump(tester, detail, reduce: true);
      set(() => detail.value = 'Live');
      await tester.pump();
      expect(find.text('Predictions · Filter'), findsNothing);
      expect(find.text('Predictions · Live'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
