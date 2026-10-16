import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

Widget _app(Widget child,
        {bool reduceMotion = false, bool tickers = true, bool dark = false}) =>
    MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: TickerMode(
            enabled: tickers,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );

Widget _figure(String text, {required bool stale}) => StaleShimmer(
      stale: stale,
      child: RollingNumberText(
        text: text,
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800),
      ),
    );

/// The sweep's layer under the figure, if it is painting one.
ShaderMaskLayer? _sweepLayer(WidgetTester tester) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find
      .descendant(
          of: find.byType(StaleShimmer), matching: find.byType(RepaintBoundary))
      .first);
  ShaderMaskLayer? found;
  void visit(Layer? layer) {
    while (layer != null) {
      if (layer is ShaderMaskLayer) found ??= layer;
      if (layer is ContainerLayer) visit(layer.firstChild);
      layer = layer.nextSibling;
    }
  }

  visit(boundary.debugLayer);
  return found;
}

void main() {
  testWidgets('a stale figure sweeps and keeps its digits findable',
      (tester) async {
    await tester.pumpWidget(_app(_figure(r'$12.34', stale: true)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(_sweepLayer(tester), isNotNull);
    expect(tester.binding.hasScheduledFrame, isTrue);
    // Digits stay real text: each reel is a Text the finder can reach.
    expect(find.text('1'), findsWidgets);
    expect(find.text(r'$'), findsOneWidget);
  });

  testWidgets('a fresh figure paints plainly and leaves no ticker',
      (tester) async {
    await tester.pumpWidget(_app(_figure(r'$12.34', stale: false)));
    await tester.pumpAndSettle();

    expect(_sweepLayer(tester), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('going fresh stops the sweep and the digits still roll',
      (tester) async {
    await tester.pumpWidget(_app(_figure(r'$12.34', stale: true)));
    await tester.pump(const Duration(milliseconds: 300));
    final reel = tester.element(find.byType(RollingNumberText));

    await tester.pumpWidget(_app(_figure(r'$56.78', stale: false)));
    // The figure kept its element (its reels), so the new digits roll in.
    expect(tester.element(find.byType(RollingNumberText)), same(reel));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();

    expect(_sweepLayer(tester), isNull);
    expect(find.text('5'), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Reduce Motion holds a stale figure still', (tester) async {
    await tester
        .pumpWidget(_app(_figure(r'$12.34', stale: true), reduceMotion: true));
    await tester.pumpAndSettle();

    expect(_sweepLayer(tester), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('a muted subtree schedules no sweep frames', (tester) async {
    await tester
        .pumpWidget(_app(_figure(r'$12.34', stale: true), tickers: false));
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the sweep stops in the background and resumes after',
      (tester) async {
    await tester.pumpWidget(_app(_figure(r'$12.34', stale: true)));
    await tester.pump(const Duration(milliseconds: 200));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final controllerRunning = tester.binding.transientCallbackCount > 0;
    expect(controllerRunning, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_sweepLayer(tester), isNotNull);
  });

  testWidgets('the highlight lightens the dimmed colour in both themes',
      (tester) async {
    for (final dark in [false, true]) {
      late Color base, highlight;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          base = context.colors.textSecondary;
          highlight = StaleShimmer.highlightFor(context, base);
          return const SizedBox();
        }),
        dark: dark,
      ));
      expect(highlight.computeLuminance(), greaterThan(base.computeLuminance()),
          reason: dark ? 'dark' : 'light');
    }
  });
}
