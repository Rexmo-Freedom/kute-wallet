// The top bar's hub glyph: a rounded "+" with a gear badge. It paints in
// light and dark at any pixel ratio; the two swap prominence (the gear
// grows in, a hold, then the "+" again) when it appears and then now and
// then, a quick swap on each press, nothing ticking in between; it holds still under Reduce Motion,
// while its tickers are off and (for new plays) while a route covers it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/theme/app_theme.dart';

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

Widget _app({
  bool dark = false,
  bool reduce = false,
  bool ticking = true,
  Listenable? pressed,
  Duration interval = const Duration(seconds: 9),
}) =>
    MaterialApp(
      theme: ThemeData(
          extensions: [dark ? AppColorsExtension.dark() : AppColorsExtension.light()]),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: TickerMode(
            enabled: ticking,
            child: Center(
              child: HubPlusGearGlyph(
                color: context.colors.textPrimary,
                pressed: pressed,
                interval: interval,
              ),
            ),
          ),
        ),
      ),
    );

AnimationController _controller(WidgetTester tester) => tester
    .widget<AnimatedBuilder>(find.descendant(
        of: find.byType(HubPlusGearGlyph),
        matching: find.byType(AnimatedBuilder)))
    .animation as AnimationController;

void main() {
  testWidgets('paints every frame in light and dark at 1x, 2x and 3x',
      (tester) async {
    for (final dark in [false, true]) {
      for (final dpr in [1.0, 2.0, 3.0]) {
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(dark: dark));
        expect(tester.getSize(find.byType(HubPlusGearGlyph)),
            const Size.square(24));
        for (var ms = 0; ms <= 1800; ms += 50) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('plays once on appearing, rests, and plays again later',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_controller(tester).isAnimating, isTrue);
    // One swap and back, under two seconds.
    expect(_controller(tester).duration, const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 850));
    expect(_controller(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
    // Nothing ticks between plays.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 9));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a press plays a quick swap', (tester) async {
    final pressed = _Ping();
    addTearDown(pressed.dispose);
    await tester.pumpWidget(_app(pressed: pressed));
    await tester.pumpAndSettle();
    expect(_controller(tester).isAnimating, isFalse);
    pressed.ping();
    await tester.pump();
    expect(_controller(tester).isAnimating, isTrue);
    expect(_controller(tester).duration, const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(_controller(tester).isAnimating, isFalse);
  });

  testWidgets('under Reduce Motion it holds still, presses too',
      (tester) async {
    final pressed = _Ping();
    addTearDown(pressed.dispose);
    await tester.pumpWidget(_app(reduce: true, pressed: pressed));
    expect(
        find.descendant(
            of: find.byType(HubPlusGearGlyph),
            matching: find.byType(AnimatedBuilder)),
        findsNothing);
    pressed.ping();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('holds still while its tickers are off, plays when they come '
      'back', (tester) async {
    final ticking = ValueNotifier(false);
    addTearDown(ticking.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: ticking,
        builder: (_, on, __) => _app(ticking: on)));
    await tester.pump(const Duration(seconds: 30));
    expect(_controller(tester).isAnimating, isFalse);
    expect(_controller(tester).value, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    ticking.value = true;
    await tester.pump();
    expect(_controller(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
    expect(_controller(tester).isAnimating, isFalse);
  });

  testWidgets('a covering route lets the play in flight finish, starts no '
      'new one, and coming back plays once', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: HubPlusGearGlyph(color: context.colors.textPrimary),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controller(tester).isAnimating, isTrue);
    key.currentState!.push(PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => const SizedBox.expand()));
    await tester.pump();
    // Still playing under the new route.
    expect(_controller(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
    key.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(_controller(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
  });
}
