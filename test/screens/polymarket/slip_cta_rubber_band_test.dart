// Every placement wears the rubber band (founder: "not just send flows,
// but also on placing stocks or predictions while it is placing"): the
// slips' one button is drawn up while it places, snaps back once it placed
// and lets go softly when it did not.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/theme/app_theme.dart';

Widget _host(
        {required bool busy,
        RubberBandOutcome? outcome,
        bool band = true,
        bool reduceMotion = false}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PolySlipCta(
              color: Colors.green,
              isBusy: busy,
              enabled: !busy,
              onTap: () {},
              label: r'Place $10.00 on Yes',
              busyLabel: 'Placing order…',
              band: band,
              bandOutcome: outcome,
            ),
          ),
        ),
      ),
    );

RubberBandProgressState _band(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(find.byType(RubberBandProgress));

Future<void> _frames(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });
  // The whoosh and the snap, through the haptics bridge's test seam.
  Iterable<ContinuousHapticsCall> snapTaps() =>
      ContinuousHaptics.debugLog!.where((c) => c.method == 'snap');

  testWidgets('an unfunded bet: pulled while it places, building with time',
      (tester) async {
    await tester.pumpWidget(_host(busy: false));
    await _frames(tester, 4);
    // At rest before the tap: nothing ticks.
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 10);
    final early = _band(tester).stretch;
    expect(early, greaterThan(0));
    await _frames(tester, 60);
    final later = _band(tester).stretch;
    expect(later, greaterThan(early - RubberBandProgress.breath));
    expect(later, lessThanOrEqualTo(RubberBandProgress.defaultMaxStretch));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the tap is felt at once: at least 4% within 300 ms',
      (tester) async {
    await tester.pumpWidget(_host(busy: false));
    await _frames(tester, 2);
    await tester.pumpWidget(_host(busy: true));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_band(tester).stretch, greaterThanOrEqualTo(0.04));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('placed while still busy: the snap plays before it lets go',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 30);
    // A sheet sets the outcome and keeps busy up (its in-flight guard)
    // while RubberBand.settle runs.
    await tester
        .pumpWidget(_host(busy: true, outcome: RubberBandOutcome.success));
    var min = double.infinity;
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
    }
    expect(min, lessThan(0), reason: 'the snap overshoots');
    expect(snapTaps(), hasLength(1));
    await tester.pumpWidget(
        _host(busy: false, outcome: RubberBandOutcome.success));
    await _frames(tester);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(snapTaps(), hasLength(1), reason: 'one snap, one tap');
  });

  testWidgets('placed: a spring snap back to rest and one light tap',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 40);
    await tester.pumpWidget(
        _host(busy: false, outcome: RubberBandOutcome.success));
    var min = double.infinity;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
    }
    expect(min, lessThan(0), reason: 'the snap overshoots');
    await _frames(tester);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(snapTaps(), hasLength(1));
  });

  testWidgets('not placed: let go softly, never past rest, no tap',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 40);
    await tester.pumpWidget(_host(busy: false));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_band(tester).stretch, greaterThanOrEqualTo(-1e-9));
    }
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(snapTaps(), isEmpty);
  });

  testWidgets('Reduce Motion: the button never moves', (tester) async {
    await tester.pumpWidget(_host(busy: true, reduceMotion: true));
    await _frames(tester, 20);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inside a funded order\'s band: never a second one',
      (tester) async {
    await tester.pumpWidget(_host(busy: true, band: false));
    await _frames(tester, 4);
    expect(find.byType(RubberBandProgress), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
