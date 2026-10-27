// The money journey in motion, the calm look (founder, 20 October 2026;
// connectors as "B2 · rounded elbows", 27 October): one coin glides along
// the running connector as it fills, rests above each station it reaches
// and cross-fades into that station's currency, and sinks into the
// destination (as its ring takes over while its own sub-steps run, else
// once everything is done); Sal walks the line behind it; a leg's sub-legs are waypoints on its connector, the
// destination's sub-steps dots under its name; one status line says the
// step at work. A stop just stops, a finished record replays once,
// silent, and each live moment is felt once, never for lines that were
// already done when the view appeared.

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
      MoneyStep(id: 'place', kind: MoneyStepKind.place, usd: 15, status: place),
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

Offset _at(WidgetTester tester, Finder f) => tester.getCenter(f);

/// The one status line on screen: the words seen under the row (every
/// other line is there unseen, for a screen reader).
String? _status(WidgetTester tester) {
  final words = find.byKey(const ValueKey('money-steps-words'));
  for (final e
      in find.descendant(of: words, matching: find.byType(Text)).evaluate()) {
    final text = (e.widget as Text).data ?? '';
    final veil = e.findAncestorWidgetOfExactType<Opacity>();
    if (text.isNotEmpty && (veil == null || veil.opacity > 0)) return text;
  }
  return null;
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

  group('the row', () {
    testWidgets(
        'serial legs: one station per place, left to right on one line, '
        'the coin on the running leg', (tester) async {
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
      final btc = _at(tester, _station('bitcoin'));
      final usd = _at(tester, _station('dollars'));
      final poly = _at(tester, _station('predictions'));
      expect(btc.dx, lessThan(usd.dx));
      expect(usd.dx, lessThan(poly.dx));
      expect({btc.dy, usd.dy, poly.dy}, hasLength(1), reason: 'one row');
      // Bitcoin's part is done; the money is in Dollars, not there yet.
      expect(find.byKey(const ValueKey('money-steps-station-done-bitcoin')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-steps-station-done-dollars')),
          findsNothing);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-step-running-1')), findsOneWidget);
      // One status line, the step at work in its own words; the others
      // are there for a screen reader, unseen.
      expect(_status(tester), 'Moving \$8.00 from Dollars → Predictions');
      expect(
          findMoneyStep('Moved \$8.00 from Bitcoin → Dollars'), findsOneWidget);
      expect(findMoneyStep('Placing \$8.00 on Yes'), findsOneWidget);
      // The coin travels the second leg now, in Dollars.
      expect(_motion(tester).travellerRoad, 'onward');
      expect(_motion(tester).travellerStation, 'predictions');
      expect(_motion(tester).coin!.place, MoneyPlace.dollars);
      // No map chrome: no chips, no percent, no amount on top.
      expect(find.byKey(const ValueKey('money-steps-chip')), findsNothing);
      expect(find.byKey(const ValueKey('money-steps-percent')), findsNothing);
      expect(find.byKey(const ValueKey('money-steps-amount')), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets(
        'parallel legs: each source on its own row, converging on the '
        'destination, one coin for the biggest leg', (tester) async {
      await tester.pumpWidget(_app(
          moneyStepLines(_en, _three(), _usd,
              placeLine: 'Placing \$15.00 on Yes'),
          graph: _three(),
          to: MoneyPlace.predictions));
      await tester.pump(const Duration(milliseconds: 100));
      final poly = _at(tester, _station('predictions'));
      final xs = [
        for (final id in ['bitcoin', 'dollars', 'investing'])
          _at(tester, _station(id)),
      ];
      // One column of sources, stacked: the same x, each its own row, the
      // destination on the middle one.
      for (final p in xs) {
        expect(p.dx, xs.first.dx);
        expect(p.dx, lessThan(poly.dx));
      }
      expect(xs[0].dy, lessThan(xs[1].dy));
      expect(xs[1].dy, lessThan(xs[2].dy));
      expect(poly.dy, closeTo(xs[1].dy, 0.01));
      // Each on its own row, a small gap between them (no longer
      // overlapped).
      final icon = tester.getSize(_station('bitcoin')).height;
      expect(xs[1].dy - xs[0].dy, greaterThan(icon));
      expect(xs[2].dy - xs[1].dy, greaterThan(icon));
      // One merge point on the destination's centre line, between the
      // column and the destination; nothing filled past it yet.
      final merge = tester.getTopLeft(
              find.byKey(const ValueKey('money-steps-map'))) +
          _motion(tester).mergePointOf('predictions')!;
      expect(merge.dy, closeTo(poly.dy, 0.01));
      expect(merge.dx, greaterThan(xs.first.dx));
      expect(merge.dx, lessThan(poly.dx));
      expect(_motion(tester).mergeLitOf('predictions'), 0);
      // Each source's amount under the start of its leg.
      for (final (id, amount) in [
        ('bitcoin', '\$8.00'),
        ('dollars', '\$5.00'),
        ('investing', '\$2.00'),
      ]) {
        final label = find.byKey(ValueKey('money-steps-leg-amount-$id'));
        expect(label, findsOneWidget);
        expect(find.descendant(of: label, matching: find.text(amount)),
            findsOneWidget);
      }
      // Their names together under the column, moved in from the edge.
      expect(find.text('Bitcoin · Dollars · Investing'), findsOneWidget);
      final plan = MoneyJourneyPlan.of(
          moneyStepLines(_en, _three(), _usd, placeLine: 'Place'),
          graph: _three(),
          to: MoneyPlace.predictions);
      expect(plan.roads.length, 3);
      expect(plan.roads.map((r) => r.to).toSet(), {plan.destination});
      // Each leg fills its own line at its own pace: all three running.
      for (final id in ['leg:bitcoin', 'leg:dollars', 'leg:investing']) {
        expect(_motion(tester).litOf(id), greaterThan(0));
      }
      // The coin takes the biggest leg, in its currency.
      expect(_motion(tester).travellerRoad, 'leg:bitcoin');
      expect(_motion(tester).coin!.place, MoneyPlace.bitcoin);
      // Every leg's words are there for a screen reader.
      expect(findMoneyStep('Moving \$5.00 from Dollars'), findsOneWidget);
      expect(findMoneyStep('Moving \$2.00 from Investing'), findsOneWidget);
    });

    testWidgets(
        'a leg with three sub-legs: two waypoints on its connector, the '
        'status follows the sub-phase', (tester) async {
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
      expect(_status(tester), 'HyperCore → Circle');
      expect(findMoneyStep('HyperCore → Circle · \$11.04'), findsOneWidget);

      await tester.pumpWidget(_app(lines(burned: true), graph: g(_run)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_status(tester), 'Circle → Arbitrum');
      expect(count('lightImpact'), 1, reason: 'the waypoint filled');
      expect(_motion(tester).litOf('cctp:burn'), 1);
      expect(_motion(tester).litOf('cctp:mint'), greaterThan(0));

      await tester
          .pumpWidget(_app(lines(burned: true, minted: true), graph: g(_run)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_status(tester), 'Arbitrum → Bitcoin');
      expect(count('selectionClick'), 0, reason: 'not at a station yet');

      await tester.pumpWidget(
          _app(lines(burned: true, minted: true, done: true), graph: g(_done)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(patterns('success'), 1);
      expect(_motion(tester).travellerRoad, isNull);
      expect(_motion(tester).travellerStation, 'bitcoin');
      // The success beat holds its own guard while it plays.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'the slips\' stage lines without a graph: one connector from the '
        'source to the venue, every stage a checkpoint under its own keys',
        (tester) async {
      await tester.pumpWidget(_app(const [
        MoneyStepLine('Adding \$6.00 to Investments', _run),
        MoneyStepLine('Preparing your order', _wait),
        MoneyStepLine('Opening \$20.00 Long BTC', _wait),
      ], to: MoneyPlace.investing, keys: MoneyStepsKeys.slip));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('slip-funding-steps')), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-waiting-1')),
          findsOneWidget);
      expect(find.text('Adding \$6.00 to Investments'), findsOneWidget);
      expect(find.text('Preparing your order'), findsOneWidget);
      expect(_status(tester), 'Adding \$6.00 to Investments');
      expect(_station('start'), findsOneWidget);
      expect(_station('investing'), findsOneWidget);
      expect(_motion(tester).travellerRoad, '#stage');
    });
  });

  testWidgets(
      'live: the coin glides to the destination and lands with a click, '
      'turns into its currency, each check is felt once, the last with the '
      'success beat, then the coin sinks in', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    // Appearing is not a moment: nothing felt yet.
    expect(impacts, isEmpty);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).travellerRoad, 'leg:bitcoin');
    final lit = _motion(tester).litOf('leg:bitcoin');
    expect(lit, greaterThan(0));
    expect(lit, lessThan(1), reason: 'it waits for the leg to land');
    expect(_motion(tester).coin!.place, MoneyPlace.bitcoin);
    // Sal walks behind the coin, then waits.
    expect(_motion(tester).walking, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_motion(tester).walking, isFalse);
    final sal = _motion(tester).travellerAt!;
    expect(sal.dx, lessThan(_motion(tester).coin!.at.dx),
        reason: 'behind the coin');
    expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
    expect(_status(tester), 'Moving \$8.00 from Bitcoin');
    expect(findMoneyStep('Getting your prediction ready'), findsOneWidget);

    // Bitcoin lands, the readiness runs.
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(milliseconds: 60));
    expect(impacts, isEmpty);
    await tester.pump(const Duration(milliseconds: 80));
    expect(count('lightImpact'), 1, reason: 'the step completed');
    expect(count('selectionClick'), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(count('selectionClick'), 1, reason: 'the coin lands');
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).travellerRoad, isNull);
    expect(_motion(tester).travellerStation, 'predictions');
    // It cross-fades into the destination's currency: dimmer midway.
    final landing = _motion(tester).coin!;
    expect(landing.place, MoneyPlace.bitcoin);
    expect(landing.alpha, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_motion(tester).coin!.place, MoneyPlace.predictions);
    // Then it sinks into Predictions as its ring takes over while it
    // works.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_motion(tester).coin, isNull);
    expect(_motion(tester).destinationRing, 1);
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-running-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-done-bitcoin')),
        findsOneWidget);
    expect(_status(tester), 'Confirming balance');

    // Everything lands at once: one success beat, no light tap on top.
    await tester.pumpWidget(_bet3(_done, _done, _done));
    await tester.pump(const Duration(milliseconds: 140));
    expect(patterns('success'), 1);
    expect(count('lightImpact'), 1);
    expect(_status(tester), 'Placed!');
    await tester.pump(const Duration(seconds: 1));
    expect(_motion(tester).coin, isNull);
    expect(_motion(tester).destinationRing, 0, reason: 'done: the check');
    expect(find.byKey(const ValueKey('money-steps-station-done-predictions')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(_motion(tester).travellerShown, isTrue, reason: 'Sal stays');
    expect(patterns('success'), 1);
    expect(find.byKey(const ValueKey('money-step-done-3')), findsOneWidget);
    expect(findMoneyStep('Placing \$15.00 on Yes'), findsOneWidget);
  });

  testWidgets(
      'two legs landing together are one light tap; a leg out of order '
      'does not move the coin off its leg', (tester) async {
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
    expect(count('selectionClick'), 0, reason: 'the coin stays on Bitcoin\'s');
    expect(_motion(tester).travellerRoad, 'leg:bitcoin');
    expect(find.byKey(const ValueKey('money-steps-station-done-dollars')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-done-investing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-done-bitcoin')),
        findsNothing);
  });

  testWidgets(
      'a record opened after it ended draws its final state, replays once, '
      'silent', (tester) async {
    await tester.pumpWidget(_bet3(_done, _done, _done));
    await tester.pump();
    expect(_motion(tester).replaying, isTrue);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).litOf('leg:bitcoin'), lessThan(1),
        reason: 'the connector fills in order');
    expect(_motion(tester).coin, isNotNull, reason: 'the coin goes along');
    await tester.pump(const Duration(seconds: 2));
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).replaying, isFalse);
    expect(_motion(tester).coin, isNull, reason: 'at rest: the coin is in');
    expect(_motion(tester).travellerStation, 'predictions');
    expect(_motion(tester).travellerRoad, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-done-predictions')),
        findsOneWidget);
    expect(_status(tester), 'Placed!');
    expect(tester.hasRunningAnimations, isFalse, reason: 'the clock rests');
  });

  testWidgets('lines already done when the view appears are never felt',
      (tester) async {
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(seconds: 2));
    expect(impacts, isEmpty);
    expect(bridge, isEmpty);
    expect(_motion(tester).replaying, isFalse);
    expect(_motion(tester).travellerStation, 'predictions');
    // The coin is in; Predictions' ring says it works.
    expect(_motion(tester).coin, isNull);
    expect(_motion(tester).destinationRing, 1);
  });

  testWidgets(
      'Reduce Motion: the final state at once, no clock running, no replay, '
      'the haptics still play', (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).walking, isFalse);

    await tester.pumpWidget(_bet3(_done, _run, _wait, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(count('lightImpact'), 1);
    expect(count('selectionClick'), 1);
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).travellerStation, 'predictions');
    expect(_motion(tester).coin, isNull, reason: 'in at once');
    expect(_motion(tester).destinationRing, 1, reason: 'no fade');

    await tester.pumpWidget(_bet3(_done, _done, _done, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(patterns('success'), 1);
    expect(_motion(tester).coin, isNull);
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
      'a stop at the destination: the failure tap plays once, a red "!" '
      'there, Sal stands still where the money stopped, nothing '
      'celebrates', (tester) async {
    await tester.pumpWidget(_bet3(_done, _run, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_done, _fail, _wait));
    await tester.pump(const Duration(milliseconds: 16));
    expect(softTaps(), 1);
    final sal = _motion(tester).travellerAt;
    await tester.pump(const Duration(seconds: 2));
    expect(_motion(tester).travellerAt, sal);
    expect(softTaps(), 1);
    expect(patterns('success'), 0);
    expect(count('lightImpact'), 0);
    expect(_motion(tester).travellerShown, isTrue);
    expect(_motion(tester).travellerStation, 'predictions');
    expect(find.byKey(const ValueKey('money-step-failed-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-failed-predictions')),
        findsOneWidget);
    expect(_status(tester), 'Confirming balance', reason: 'the stopped step');
  });

  testWidgets('a leg that stops: the status line reads it, a "!" at its source',
      (tester) async {
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_bet3(_fail, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 16));
    expect(softTaps(), 1);
    expect(_status(tester), '\$8.00 from Bitcoin didn\'t move');
    expect(find.byKey(const ValueKey('money-step-failed-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-failed-bitcoin')),
        findsOneWidget);
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
      'a screen reader hears every line in its final words and every '
      'station by name, though only the status line is seen', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bet3(_run, _wait, _wait));
    await tester.pump(const Duration(milliseconds: 100));
    for (final words in [
      'Moving \$8.00 from Bitcoin',
      'Getting your prediction ready',
      'Confirming balance',
      'Placing \$15.00 on Yes',
      'Bitcoin',
      'Predictions',
    ]) {
      expect(find.bySemanticsLabel(words), findsOneWidget, reason: words);
    }
    expect(_status(tester), 'Moving \$8.00 from Bitcoin');
    handle.dispose();
  });
}
