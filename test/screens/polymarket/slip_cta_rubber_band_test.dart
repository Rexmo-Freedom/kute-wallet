// Every placement wears the rubber band (founder: "not just send flows,
// but also on placing stocks or predictions while it is placing"): the
// slips' one button is drawn up while it places, snaps back once it placed
// and lets go softly when it did not.
//
// Since 31 October 2026 the slip draws no button of its own: `PolySlipCta`
// declares the action and the shell bar IS the button
// (kute_shell_bar.dart, shell_bar_harness.dart). The band the CTA used to
// wrap around its own button (`RubberBandBusy`) went with that button; a
// funded order's band stays around the slip's steps
// (`bet-slip-funded-progress`, covered by bet_slip_deposit_door_loading_
// test.dart). What this file keeps is the placement's busy run as the bar
// shows it: the busy label and the ring while it places, taps ignored,
// the button back once it ended, and nothing of the band's haptics (the
// snap, the soft tap) played by the CTA itself any more.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/shell_bar_harness.dart';

var _taps = 0;

Widget _host(
        {required bool busy,
        RubberBandOutcome? outcome,
        bool band = true,
        bool reduceMotion = false}) =>
    // The bar and the CTA's scope read the context stack (a provider).
    ProviderScope(
        child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Reduce Motion reaches the bar too: the MediaQuery wraps the
        // bar's layer, not only the navigator.
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: shellBarBuilder(context, child)),
        navigatorObservers: shellBarObservers(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PolySlipCta(
              color: Colors.green,
              isBusy: busy,
              enabled: !busy,
              onTap: () => _taps++,
              label: r'Place $10.00 on Yes',
              busyLabel: 'Placing order…',
              band: band,
              bandOutcome: outcome,
            ),
          ),
        ),
      ),
    ));

Future<void> _frames(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The bar's progress ring, inside its button.
Finder _ring() => find.descendant(
    of: findBarPrimary(), matching: find.byType(CircularProgressIndicator));

/// The bar reads the bet, enabled, no ring: the button at rest.
void _expectAtRest(WidgetTester tester) {
  expect(barIsPrimary(tester), isTrue);
  expect(barPrimaryBusy(tester), isFalse);
  expect(barPrimaryEnabled(tester), isTrue);
  expect(barPrimaryLabel(tester), r'Place $10.00 on Yes');
  expect(barPrimaryText(r'Place $10.00 on Yes'), findsOneWidget);
  expect(_ring(), findsNothing);
}

/// The bar reads the busy label beside its ring, not tappable.
void _expectPlacing(WidgetTester tester) {
  expect(barIsPrimary(tester), isTrue);
  expect(barPrimaryBusy(tester), isTrue);
  expect(barPrimaryEnabled(tester), isFalse);
  expect(barPrimaryLabel(tester), 'Placing order…');
  expect(barPrimaryText('Placing order…'), findsOneWidget);
  expect(barPrimaryText(r'Place $10.00 on Yes'), findsNothing);
  expect(_ring(), findsOneWidget);
}

void main() {
  late List<MethodCall> calls;
  setUp(() {
    _taps = 0;
    calls = [];
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    installShellBar();
  });
  // The whoosh and the snap, through the haptics bridge's test seam.
  Iterable<ContinuousHapticsCall> snapTaps() =>
      ContinuousHaptics.debugLog!.where((c) => c.method == 'snap');

  testWidgets(
      'an unfunded bet: the bar is the bet at rest, and while it places it '
      'is drawn busy, the ring and the busy label, for as long as it runs',
      (tester) async {
    await tester.pumpWidget(_host(busy: false));
    await _frames(tester, 4);
    // At rest before the tap: the bet, tappable, nothing spinning.
    _expectAtRest(tester);
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 10);
    _expectPlacing(tester);
    // Still placing much later: the same busy bar, never a dead button.
    await _frames(tester, 60);
    _expectPlacing(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the tap is felt at once: the bar is busy within 300 ms',
      (tester) async {
    await tester.pumpWidget(_host(busy: false));
    await _frames(tester, 2);
    _expectAtRest(tester);
    await tester.pumpWidget(_host(busy: true));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    _expectPlacing(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'placed while still busy: the bar stays busy until the sheet lets go, '
      'then is the button again', (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 30);
    // A sheet sets the outcome and keeps busy up (its in-flight guard)
    // while RubberBand.settle runs: the bar keeps spinning meanwhile.
    await tester
        .pumpWidget(_host(busy: true, outcome: RubberBandOutcome.success));
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectPlacing(tester);
    }
    await tester.pumpWidget(
        _host(busy: false, outcome: RubberBandOutcome.success));
    await _frames(tester);
    _expectAtRest(tester);
    // The CTA draws no band of its own any more: no snap from it.
    expect(snapTaps(), isEmpty);
  });

  testWidgets('placed: the bar comes back to rest as the bet, tappable',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 40);
    _expectPlacing(tester);
    await tester.pumpWidget(
        _host(busy: false, outcome: RubberBandOutcome.success));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _frames(tester);
    _expectAtRest(tester);
    await tapBarPrimary(tester);
    expect(_taps, 1);
  });

  testWidgets(
      'not placed: the bar is the bet again, never a dead button, no tap',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 40);
    _expectPlacing(tester);
    await tester.pumpWidget(_host(busy: false));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // Never disabled on the way back: busy, or the bet.
      expect(barPrimaryBusy(tester) || barPrimaryEnabled(tester), isTrue);
    }
    _expectAtRest(tester);
    expect(snapTaps(), isEmpty);
  });

  testWidgets('while busy, taps are ignored', (tester) async {
    await tester.pumpWidget(_host(busy: true));
    await _frames(tester, 10);
    _expectPlacing(tester);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 4);
    expect(_taps, 0);
    _expectPlacing(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reduce Motion: the busy bar is drawn, nothing moves',
      (tester) async {
    await tester.pumpWidget(_host(busy: true, reduceMotion: true));
    await _frames(tester, 20);
    _expectPlacing(tester);
    // The button's own fill tween is off: it switches at once.
    expect(tester.widget<AnimatedContainer>(findBarPrimary()).duration,
        Duration.zero);
    expect(find.byType(RubberBandProgress), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inside a funded order\'s band: never a second one',
      (tester) async {
    await tester.pumpWidget(_host(busy: true, band: false));
    await _frames(tester, 4);
    expect(find.byType(RubberBandProgress), findsNothing);
    // The same declaration to the bar whether or not an outer band runs.
    _expectPlacing(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
