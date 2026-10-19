// The steps tree in motion (founder, 19 October 2026: "more fun and
// better animation"): Sal rides the line to the running step, checks pop,
// the last one celebrates, a stop shakes, and each live moment is felt
// once, never for lines that were already done when the view appeared.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';

const _run = MoneyStepStatus.running;
const _wait = MoneyStepStatus.waiting;
const _done = MoneyStepStatus.done;
const _fail = MoneyStepStatus.failed;

List<MoneyStepLine> _lines(MoneyStepStatus a, MoneyStepStatus b,
        MoneyStepStatus c) =>
    [
      MoneyStepLine('Moving \$8.00 from Bitcoin', a, id: 'a'),
      MoneyStepLine('Getting your prediction ready', b, id: 'b'),
      MoneyStepLine('Confirming balance', b == _done ? _done : c,
          sub: true, id: 'b:confirm'),
      MoneyStepLine('Placing \$15.00 on Yes', c, id: 'c'),
    ];

// One theme for every pump: a new one would animate the app's theme.
final ThemeData _theme = buildLightTheme();

Widget _app(List<MoneyStepLine> lines,
        {bool still = false, bool failureHaptic = true, bool haptics = true}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: _theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: MoneyStepsView(
                  lines: lines,
                  haptics: haptics,
                  failureHaptic: failureHaptic,
                ),
              ),
            ),
          ),
        ),
      ),
    );

MoneyStepsMotionPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<MoneyStepsMotionPainter>()
    .single;

void main() {
  final impacts = <String>[];
  final bridge = <ContinuousHapticsCall>[];

  setUp(() {
    impacts.clear();
    bridge.clear();
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = bridge;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        impacts.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() {
    KuteHaptics.debugReset();
    ContinuousHaptics.debugLog = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  int count(String type) =>
      impacts.where((i) => i == 'HapticFeedbackType.$type').length;
  int patterns(String name) =>
      bridge.where((c) => c.pattern?.name == name).length;
  int softTaps() => bridge.where((c) => c.method == 'softTap').length;

  test('amounts count up in their own format', () {
    expect(moneyCountUpText('Moving \$8.00 from Bitcoin', 0.5),
        'Moving \$4.00 from Bitcoin');
    expect(moneyCountUpText('Placing \$1,234.50 on Yes', 0), 'Placing \$0.00 on Yes');
    expect(moneyCountUpText('Placing \$1,234.50 on Yes', 1),
        'Placing \$1,234.50 on Yes');
    expect(moneyCountUpText('Placing \$2,000 on Yes', 0.5),
        'Placing \$1,000 on Yes');
    expect(moneyCountUpText('5,30 € from Dollars', 0.5), '2,65 € from Dollars');
    expect(moneyCountUpText('Confirming balance', 0.3), 'Confirming balance');
    expect(moneyCountUpHasAmount('Converting to pUSD'), isFalse);
    expect(moneyCountUpHasAmount('Arbitrum → Dollars · \$20.69'), isTrue);
  });

  testWidgets(
      'live: Sal rides to the running step, each check is felt once, the '
      'last lands with the success beat, then everything rests',
      (tester) async {
    await tester.pumpWidget(_app(_lines(_run, _wait, _wait)));
    await tester.pump(const Duration(milliseconds: 600));
    // Appearing is not a moment: nothing felt yet.
    expect(impacts, isEmpty);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).travellerTarget, 'a');
    // The same words, the same signs' keys.
    expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
    expect(find.text('Moving \$8.00 from Bitcoin'), findsOneWidget);

    // Bitcoin lands, the readiness runs.
    await tester.pumpWidget(_app(_lines(_done, _run, _wait)));
    expect(_motion(tester).travellerTarget, 'b');
    await tester.pump(const Duration(milliseconds: 60));
    expect(impacts, isEmpty, reason: 'the ring closes first');
    await tester.pump(const Duration(milliseconds: 80));
    expect(count('lightImpact'), 1, reason: 'the check pops');
    expect(count('selectionClick'), 0);
    await tester.pump(const Duration(milliseconds: 260));
    expect(count('selectionClick'), 1, reason: 'Sal lands on the next step');
    await tester.pump(const Duration(seconds: 1));
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);

    // Everything lands at once: one success beat, no light tap on top.
    await tester.pumpWidget(_app(_lines(_done, _done, _done)));
    await tester.pump(const Duration(milliseconds: 140));
    expect(patterns('success'), 1);
    expect(count('lightImpact'), 1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_motion(tester).travellerShown, isTrue, reason: 'he cheers');
    await tester.pump(const Duration(seconds: 2));
    expect(_motion(tester).travellerShown, isFalse, reason: 'and hops away');
    expect(tester.hasRunningAnimations, isFalse);
    expect(patterns('success'), 1);
    expect(find.byKey(const ValueKey('money-step-done-3')), findsOneWidget);
    expect(find.text('Placing \$15.00 on Yes'), findsOneWidget);
  });

  testWidgets(
      'two lines landing together are one light tap; a running line out of '
      'order does not move Sal', (tester) async {
    final start = [
      const MoneyStepLine('Moving \$8.00 from Bitcoin', _run, id: 'a'),
      const MoneyStepLine('Moving \$5.00 from Dollars', _run, id: 'b'),
      const MoneyStepLine('Moving \$2.00 from Investing', _run, id: 'c'),
      const MoneyStepLine('Placing \$15.00 on Yes', _wait, id: 'd'),
    ];
    await tester.pumpWidget(_app(start));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_app([
      start[0],
      const MoneyStepLine('Moved \$5.00 from Dollars', _done, id: 'b'),
      const MoneyStepLine('Moved \$2.00 from Investing', _done, id: 'c'),
      start[3],
    ]));
    await tester.pump(const Duration(milliseconds: 600));
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 0, reason: 'Sal stays on Bitcoin');
    expect(_motion(tester).travellerTarget, 'a');
  });

  testWidgets(
      'a record opened after it ended draws its final state, still and '
      'silent', (tester) async {
    await tester.pumpWidget(_app(_lines(_done, _done, _done)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_motion(tester).travellerShown, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
  });

  testWidgets('lines already done when the view appears are never felt',
      (tester) async {
    await tester.pumpWidget(_app(_lines(_done, _run, _wait)));
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(_motion(tester).travellerTarget, 'b');
  });

  testWidgets(
      'Reduce Motion: the final state at once, no clock running, the '
      'haptics still play', (tester) async {
    await tester.pumpWidget(_app(_lines(_run, _wait, _wait), still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_motion(tester).travellerShown, isTrue, reason: 'Sal just sits');

    await tester.pumpWidget(_app(_lines(_done, _run, _wait), still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(_motion(tester).travellerTarget, 'b');

    await tester.pumpWidget(_app(_lines(_done, _done, _done), still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(patterns('success'), 1);
    expect(_motion(tester).travellerShown, isFalse);
    // The success beat holds its own guard while it plays.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'a stop: the line shakes, the failure tap plays once, Sal stays '
      'there dimmed, nothing celebrates', (tester) async {
    await tester.pumpWidget(_app(_lines(_done, _run, _wait)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_app([
      ..._lines(_done, _run, _wait).take(2),
      const MoneyStepLine('Confirming balance', _fail,
          sub: true, id: 'b:confirm'),
      const MoneyStepLine('Placing \$15.00 on Yes', _wait, id: 'c'),
    ]));
    await tester.pump(const Duration(milliseconds: 16));
    expect(softTaps(), 1);
    expect(_motion(tester).travellerTarget, 'b:confirm');
    await tester.pump(const Duration(milliseconds: 40));
    expect(_motion(tester).shakeOf('b:confirm'), isNot(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_motion(tester).shakeOf('b:confirm'), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 1);
    expect(patterns('success'), 0);
    expect(count('lightImpact'), 0);
    expect(_motion(tester).travellerShown, isTrue);
    expect(find.byKey(const ValueKey('money-step-failed-2')), findsOneWidget);
  });

  testWidgets(
      'a surface that plays the failure tap itself keeps the steps quiet '
      'on a stop', (tester) async {
    await tester.pumpWidget(
        _app(_lines(_run, _wait, _wait), failureHaptic: false));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(
        _app(_lines(_fail, _wait, _wait), failureHaptic: false));
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 0);
  });

  testWidgets('a stop right after a band let go is one tap, not two',
      (tester) async {
    await tester.pumpWidget(_app(_lines(_run, _wait, _wait)));
    await tester.pump(const Duration(milliseconds: 600));
    // The band around the steps let go in the same frame.
    KuteHaptics.noteFailureRelease();
    await tester.pumpWidget(_app(_lines(_fail, _wait, _wait)));
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 0);
  });

  testWidgets('haptics off: the surface owns the feel', (tester) async {
    await tester.pumpWidget(_app(_lines(_run, _wait, _wait), haptics: false));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_app(_lines(_done, _done, _done), haptics: false));
    await tester.pump(const Duration(seconds: 3));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
  });

  testWidgets(
      'an amount counts up on screen while the words a screen reader hears '
      'stay the final ones', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_lines(_run, _wait, _wait)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Moving \$8.00 from Bitcoin'), findsOneWidget);
    expect(find.bySemanticsLabel('Moving \$8.00 from Bitcoin'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('Moving \$8.00 from Bitcoin'), findsOneWidget);
    handle.dispose();
  });
}
