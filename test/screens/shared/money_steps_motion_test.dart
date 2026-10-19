// The money journey in motion (founder, 19 October 2026: "make sure we
// have Sal; make it fun and engaging"): Sal rides the biggest leg's road
// to the destination and hops as he lands, the other legs' coins run
// their own roads, a leg's sub-legs are waypoints on its road, the
// destination's sub-steps are checkpoints under the map, success rains
// confetti, a stop shakes, a finished record replays once, and each live
// moment is felt once, never for lines that were already done when the
// view appeared.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/move_steps_view.dart' show cctpLegLines;
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/money_steps_finders.dart';

const _run = MoneyStepStatus.running;
const _wait = MoneyStepStatus.waiting;
const _done = MoneyStepStatus.done;
const _fail = MoneyStepStatus.failed;

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// A bet funded from Bitcoin: the leg, the readiness (one sub-step), the
/// order.
MoneyStepGraph _bet(MoneyStepStatus a, MoneyStepStatus b, MoneyStepStatus c) =>
    MoneyStepGraph([
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 8,
          status: a),
      MoneyStep(id: 'ready:confirm', kind: MoneyStepKind.confirm, status: b),
      MoneyStep(id: 'place', kind: MoneyStepKind.place, usd: 15, status: c),
    ]);

List<MoneyStepLine> _betLines(MoneyStepGraph g) => moneyStepLines(_en, g, _usd,
    readyLabel: 'Getting your prediction ready',
    placeLine: 'Placing \$15.00 on Yes');

/// Three sources into Predictions, then the order.
MoneyStepGraph _three(
        {MoneyStepStatus bitcoin = _run,
        MoneyStepStatus dollars = _run,
        MoneyStepStatus investing = _run,
        MoneyStepStatus place = _wait}) =>
    MoneyStepGraph([
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 8,
          status: bitcoin),
      MoneyStep(
          id: 'leg:dollars',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.dollars,
          usd: 5,
          status: dollars),
      MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          usd: 2,
          status: investing),
      MoneyStep(
          id: 'place', kind: MoneyStepKind.place, usd: 15, status: place),
    ]);

// One theme for every pump: a new one would animate the app's theme.
final ThemeData _theme = buildLightTheme();

Widget _app(List<MoneyStepLine> lines,
        {MoneyStepGraph? graph,
        MoneyPlace? to,
        bool still = false,
        bool failureHaptic = true,
        bool haptics = true,
        MoneyStepsKeys keys = MoneyStepsKeys.money}) =>
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
                  graph: graph,
                  to: to,
                  money: _usd,
                  haptics: haptics,
                  failureHaptic: failureHaptic,
                  keys: keys,
                ),
              ),
            ),
          ),
        ),
      ),
    );

Widget _bet3(MoneyStepStatus a, MoneyStepStatus b, MoneyStepStatus c,
        {bool still = false, bool failureHaptic = true, bool haptics = true}) =>
    _app(_betLines(_bet(a, b, c)),
        graph: _bet(a, b, c),
        still: still,
        failureHaptic: failureHaptic,
        haptics: haptics);

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

Finder _station(String id) => find.byKey(ValueKey('money-steps-station-$id'));

double _x(WidgetTester tester, Finder f) => tester.getCenter(f).dx;

String? _status(WidgetTester tester) {
  final f = find.byKey(const ValueKey('money-steps-status'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

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
    expect(moneyCountUpText('Placing \$1,234.50 on Yes', 0),
        'Placing \$0.00 on Yes');
    expect(moneyCountUpText('Placing \$1,234.50 on Yes', 1),
        'Placing \$1,234.50 on Yes');
    expect(moneyCountUpText('Placing \$2,000 on Yes', 0.5),
        'Placing \$1,000 on Yes');
    expect(moneyCountUpText('5,30 € from Dollars', 0.5), '2,65 € from Dollars');
    expect(moneyCountUpText('Confirming balance', 0.3), 'Confirming balance');
    expect(moneyCountUpHasAmount('Converting to pUSD'), isFalse);
    expect(moneyCountUpHasAmount('Arbitrum → Dollars · \$20.69'), isTrue);
  });

  group('the map', () {
    testWidgets(
        'serial legs: one station per place, left to right, one road each',
        (tester) async {
      final g = MoneyStepGraph([
        const MoneyStep(
            id: 'leg:bitcoin',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.bitcoin,
            to: MoneyPlace.dollars,
            usd: 8,
            status: _done),
        const MoneyStep(
            id: 'onward',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            to: MoneyPlace.predictions,
            usd: 8,
            status: _run),
        const MoneyStep(
            id: 'place', kind: MoneyStepKind.place, usd: 8, status: _wait),
      ]);
      await tester.pumpWidget(_app(
          moneyStepLines(_en, g, _usd, placeLine: 'Placing \$8.00 on Yes'),
          graph: g));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_station('bitcoin'), findsOneWidget);
      expect(_station('dollars'), findsOneWidget);
      expect(_station('predictions'), findsOneWidget);
      expect(_x(tester, _station('bitcoin')),
          lessThan(_x(tester, _station('dollars'))));
      expect(_x(tester, _station('dollars')),
          lessThan(_x(tester, _station('predictions'))));
      // The legs are roads (their words on the map), the order a
      // checkpoint listed under it.
      expect(find.byKey(const ValueKey('money-steps-road-leg:bitcoin')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-steps-road-onward')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-running-1')), findsOneWidget);
      expect(find.text('Placing \$8.00 on Yes'), findsOneWidget);
      expect(find.text('At Predictions'), findsOneWidget);
      // The status names the sub-phase at work; the amount is the order's.
      expect(_status(tester), 'Moving \$8.00 from Dollars → Predictions');
      expect(find.text('\$8.00'), findsOneWidget);
      // Sal rides the second road now, having reached Dollars.
      expect(_motion(tester).travellerRoad, 'onward');
      expect(_motion(tester).travellerStation, 'predictions');
    });

    testWidgets('parallel legs: three roads converge on the destination',
        (tester) async {
      await tester.pumpWidget(_app(
          moneyStepLines(_en, _three(), _usd,
              placeLine: 'Placing \$15.00 on Yes'),
          graph: _three(),
          to: MoneyPlace.predictions));
      await tester.pump(const Duration(milliseconds: 100));
      for (final id in ['bitcoin', 'dollars', 'investing']) {
        expect(_station(id), findsOneWidget);
        expect(_x(tester, _station(id)),
            lessThan(_x(tester, _station('predictions'))));
      }
      // Stacked in one column.
      expect(_x(tester, _station('bitcoin')), _x(tester, _station('dollars')));
      final plan = MoneyJourneyPlan.of(
          moneyStepLines(_en, _three(), _usd, placeLine: 'Place'),
          graph: _three(),
          to: MoneyPlace.predictions);
      expect(plan.roads.length, 3);
      expect(plan.roads.map((r) => r.to).toSet(), {plan.destination});
      expect(plan.stations.where((s) => s.column == 0).length, 3);
      // Sal takes the biggest leg.
      expect(_motion(tester).travellerRoad, 'leg:bitcoin');
      // The destination counts the legs in.
      expect(find.text('0 of 3 arrived'), findsOneWidget);
      // Every leg's words are there for a screen reader.
      expect(findMoneyStep('Moving \$5.00 from Dollars'), findsOneWidget);
    });

    testWidgets(
        'a leg with three sub-legs: two waypoints on its road, in order, '
        'and the status follows the sub-phase', (tester) async {
      MoneyStepGraph g(MoneyStepStatus s) => MoneyStepGraph([
            MoneyStep(
                id: 'leg:investing',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.investing,
                to: MoneyPlace.bitcoin,
                usd: 11.04,
                status: s),
          ]);
      List<MoneyStepLine> lines(
              {bool burned = false, bool minted = false, bool done = false}) =>
          [
            ...moneyStepLines(_en, g(done ? _done : _run), _usd),
            ...cctpLegLines(
                _en,
                (
                  burned: burned,
                  minted: minted,
                  ordered: false,
                  failed: false,
                  sentUsd: 11.04,
                  mintUsd: 10.84,
                ),
                destination: 'Bitcoin',
                rowDone: done,
                rowFailed: false,
                money: _usd),
          ];
      await tester.pumpWidget(_app(lines(), graph: g(_run)));
      await tester.pump(const Duration(milliseconds: 100));
      final plan = MoneyJourneyPlan.of(lines(), graph: g(_run));
      expect(plan.roads.single.segments.length, 3);
      expect(plan.roads.single.waypoints.map((w) => w.label).toList(),
          ['Circle', 'Arbitrum']);
      expect(plan.roads.single.waypoints.map((w) => w.amount).toList(),
          ['\$11.04', '\$10.84']);
      final circle = tester.getCenter(
          find.byKey(const ValueKey('money-steps-road-cctp:burn')));
      final arbitrum = tester.getCenter(
          find.byKey(const ValueKey('money-steps-road-cctp:mint')));
      expect(circle.dx, lessThan(arbitrum.dx));
      expect(_x(tester, _station('investing')), lessThan(circle.dx));
      expect(arbitrum.dx, lessThan(_x(tester, _station('bitcoin'))));
      expect(_status(tester), 'HyperCore → Circle');
      expect(findMoneyStep('HyperCore → Circle · \$11.04'), findsOneWidget);

      await tester.pumpWidget(_app(lines(burned: true), graph: g(_run)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_status(tester), 'Circle → Arbitrum');
      expect(count('lightImpact'), 1, reason: 'the waypoint lit');
      expect(_motion(tester).litOf('cctp:burn'), 1);
      expect(_motion(tester).litOf('cctp:mint'), greaterThan(0));

      await tester.pumpWidget(
          _app(lines(burned: true, minted: true), graph: g(_run)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_status(tester), 'Arbitrum → Bitcoin');
      expect(count('selectionClick'), 0, reason: 'not at a station yet');

      await tester.pumpWidget(_app(
          lines(burned: true, minted: true, done: true),
          graph: g(_done)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(patterns('success'), 1);
      expect(_motion(tester).travellerRoad, isNull);
      expect(_motion(tester).travellerStation, 'bitcoin');
      // The success beat holds its own guard while it plays.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'the slips\' stage lines without a graph: one road from the source '
        'to the venue, every stage a checkpoint under their own keys',
        (tester) async {
      await tester.pumpWidget(_app(
          const [
            MoneyStepLine('Adding \$6.00 to Investments', _run),
            MoneyStepLine('Preparing your order', _wait),
            MoneyStepLine('Opening \$20.00 Long BTC', _wait),
          ],
          to: MoneyPlace.investing,
          keys: MoneyStepsKeys.slip));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('slip-funding-steps')), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-waiting-1')),
          findsOneWidget);
      expect(find.text('Adding \$6.00 to Investments'), findsOneWidget);
      expect(_station('start'), findsOneWidget);
      expect(_station('investing'), findsOneWidget);
      expect(_motion(tester).travellerRoad, '#stage');
      expect(_status(tester), isNull, reason: 'the stage speaks for itself');
    });
  });

  testWidgets(
      'live: Sal rides to the destination and hops as he lands, each check '
      'is felt once, the last lands with the success beat and confetti',
      (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    // Appearing is not a moment: nothing felt yet.
    expect(impacts, isEmpty);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).travellerRoad, 'leg:bitcoin');
    final lit = _motion(tester).litOf('leg:bitcoin');
    expect(lit, greaterThan(0));
    expect(lit, lessThan(1), reason: 'he waits for the leg to land');
    expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
    expect(find.text('Getting your prediction ready'), findsOneWidget);
    expect(find.text('\$15.00'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);

    // Bitcoin lands, the readiness runs.
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(milliseconds: 60));
    expect(impacts, isEmpty, reason: 'the station pops first');
    await tester.pump(const Duration(milliseconds: 80));
    expect(count('lightImpact'), 1, reason: 'the station turned gold');
    expect(count('selectionClick'), 0);
    await tester.pump(const Duration(milliseconds: 260));
    expect(count('selectionClick'), 1, reason: 'Sal lands on Predictions');
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).travellerRoad, isNull);
    expect(_motion(tester).travellerStation, 'predictions');
    await tester.pump(const Duration(seconds: 1));
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-running-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-chip')), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    // Everything lands at once: one success beat, no light tap on top.
    await tester.pumpWidget(_bet3(_done, _done, _done));
    await tester.pump(const Duration(milliseconds: 140));
    expect(patterns('success'), 1);
    expect(count('lightImpact'), 1);
    expect(_status(tester), 'Placed!');
    expect(find.text('100%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_motion(tester).travellerShown, isTrue, reason: 'he cheers');
    await tester.pump(const Duration(seconds: 3));
    expect(_motion(tester).travellerShown, isTrue, reason: 'and stays, happy');
    expect(patterns('success'), 1);
    expect(find.byKey(const ValueKey('money-step-done-3')), findsOneWidget);
    expect(find.text('Placing \$15.00 on Yes'), findsOneWidget);
  });

  testWidgets(
      'two legs landing together are one light tap; a leg out of order '
      'does not move Sal off his road', (tester) async {
    Widget at(MoneyStepStatus d, MoneyStepStatus i) => _app(
        moneyStepLines(_en, _three(dollars: d, investing: i), _usd,
            placeLine: 'Placing \$15.00 on Yes'),
        graph: _three(dollars: d, investing: i),
        to: MoneyPlace.predictions);
    await tester.pumpWidget(at(_run, _run));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(at(_done, _done));
    await tester.pump(const Duration(milliseconds: 600));
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 0, reason: 'Sal stays on Bitcoin\'s road');
    expect(_motion(tester).travellerRoad, 'leg:bitcoin');
    expect(find.text('2 of 3 arrived'), findsOneWidget);
  });

  testWidgets('a tap on Sal makes him jump, with a click', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    final map = tester.getTopLeft(find.byKey(const ValueKey('money-steps-map')));
    final sal = _motion(tester).travellerAt!;
    await tester.tapAt(map + sal + const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_motion(tester).jumping, isTrue);
    expect(count('selectionClick'), 1);
    // A tap elsewhere on the map does nothing.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(map + const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_motion(tester).jumping, isFalse);
    expect(count('selectionClick'), 1);
  });

  testWidgets(
      'a record opened after it ended draws its final state, replays once, '
      'silent', (tester) async {
    await tester.pumpWidget(_bet3(_done, _done, _done));
    await tester.pump();
    expect(_motion(tester).replaying, isTrue);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).litOf('leg:bitcoin'), lessThan(1),
        reason: 'the road lights in order');
    await tester.pump(const Duration(seconds: 2));
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).replaying, isFalse);
    expect(_motion(tester).travellerStation, 'predictions');
    expect(_motion(tester).travellerRoad, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
    expect(_status(tester), 'Placed!');
  });

  testWidgets('lines already done when the view appears are never felt',
      (tester) async {
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(_motion(tester).replaying, isFalse);
    expect(_motion(tester).travellerStation, 'predictions');
  });

  testWidgets(
      'Reduce Motion: the final state at once, no clock running, no replay, '
      'the haptics still play', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_motion(tester).travellerShown, isTrue, reason: 'Sal just sits');

    await tester.pumpWidget(_bet3(_done, _run, _wait, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).travellerStation, 'predictions');

    await tester.pumpWidget(_bet3(_done, _done, _done, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(patterns('success'), 1);
    expect(_motion(tester).travellerShown, isTrue);
    // The success beat holds its own guard while it plays.
    await tester.pump(const Duration(seconds: 1));

    // A finished record: no replay.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_bet3(_done, _done, _done, still: true));
    await tester.pump();
    expect(_motion(tester).replaying, isFalse);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
      'a stop: the checkpoint and its station shake, the failure tap plays '
      'once, Sal sits there sad, nothing celebrates', (tester) async {
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_done, _fail, _wait));
    await tester.pump(const Duration(milliseconds: 16));
    expect(softTaps(), 1);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_motion(tester).shakeOf('ready:confirm'), isNot(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_motion(tester).shakeOf('ready:confirm'), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 1);
    expect(patterns('success'), 0);
    expect(count('lightImpact'), 0);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).travellerStation, 'predictions');
    expect(find.byKey(const ValueKey('money-step-failed-2')), findsOneWidget);
    expect(_status(tester), isNull, reason: 'the checkpoint says it');
  });

  testWidgets('a leg that stops: the road reads it on top', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_fail, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 16));
    expect(softTaps(), 1);
    expect(_status(tester), '\$8.00 from Bitcoin didn\'t move');
    expect(find.byKey(const ValueKey('money-step-failed-0')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 1);
  });

  testWidgets(
      'a surface that plays the failure tap itself keeps the steps quiet '
      'on a stop', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait, failureHaptic: false));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_fail, _wait, _wait, failureHaptic: false));
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 0);
  });

  testWidgets('a stop right after a band let go is one tap, not two',
      (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    // The band around the steps let go in the same frame.
    KuteHaptics.noteFailureRelease();
    await tester.pumpWidget(_bet3(_fail, _wait, _wait));
    await tester.pump(const Duration(seconds: 2));
    expect(softTaps(), 0);
  });

  testWidgets('haptics off: the surface owns the feel', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait, haptics: false));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_done, _done, _done, haptics: false));
    await tester.pump(const Duration(seconds: 3));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
  });

  testWidgets(
      'the amount counts up on screen while the words a screen reader hears '
      'stay the final ones', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('\$15.00'), findsOneWidget);
    expect(find.bySemanticsLabel('\$15.00'), findsOneWidget);
    expect(findMoneyStep('Moving \$8.00 from Bitcoin'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('\$15.00'), findsOneWidget);
    handle.dispose();
  });
}
