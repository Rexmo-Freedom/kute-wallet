// Sal's glyph-size dog on every Ask Sal entry point glances once when he
// appears, rests with nothing ticking, glances again after the interval,
// and holds still under Reduce Motion, while covered and in the background.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';

const _glance = Duration(milliseconds: kKuteDogGlanceMs);

Widget _host(Widget child, {GlobalKey<NavigatorState>? navigator}) =>
    MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(body: Center(child: child)),
    );

const _fixed = KuteDogGlance(
  size: 24,
  interval: Duration(seconds: 7),
  jitter: Duration.zero,
  firstDelayMax: Duration.zero,
);

void main() {
  testWidgets('glances on appearing, then rests with no frames',
      (tester) async {
    await tester.pumpWidget(_host(_fixed));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(_glance + const Duration(milliseconds: 50));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.getSize(find.byType(KuteDogGlance)), const Size.square(24));
  });

  testWidgets('glances again after the interval', (tester) async {
    await tester.pumpWidget(_host(_fixed));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 6800));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('by default the first glance lands within a small random beat',
      (tester) async {
    await tester.pumpWidget(_host(const Row(
        mainAxisSize: MainAxisSize.min,
        children: [KuteDogGlance(size: 24), KuteDogGlance(size: 24)])));
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    // The next play is 6 to 8 s away.
    await tester.pump(const Duration(milliseconds: 5900));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 2200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('under Reduce Motion he is the still frame for good',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(_fixed));
    expect(
        find.descendant(
            of: find.byType(KuteDogGlance),
            matching: find.byType(AnimatedBuilder)),
        findsNothing);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('holds still while another route covers his, and glances '
      'again once he is back on top', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(_fixed, navigator: navigator));
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Over'))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(tester.binding.hasScheduledFrame, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    // Back on top: one glance (pumpAndSettle ran it), then rest.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 7100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('holds still while the app is in the background',
      (tester) async {
    await tester.pumpWidget(_host(_fixed));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('paints at 1x, 2x and 3x without errors', (tester) async {
    for (final dpr in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(_fixed));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(KuteDogGlance)), const Size.square(24));
    }
  });
}
