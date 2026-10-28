// The one widget every funded order shows its step graph with (founder,
// 15 October 2026: "on the progress we show what is happening. Pulling
// money from bitcoin balance, from predictions and all that. It must be
// clear to the user. and when they are completed also"): one line per
// source with its own state, the venue's readiness as sub-steps under its
// stage line, the order last; lines complete independently. Drawn in the
// calm look (20 October 2026): one status line seen, every line there for
// a screen reader.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/slip_shortfall.dart' show SlipFundingSteps;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show fundedOrderGraph;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/money_steps_finders.dart';

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

MoneyStepGraph _bet({
  MoneyStepStatus bitcoin = MoneyStepStatus.running,
  MoneyStepStatus dollars = MoneyStepStatus.running,
  MoneyStepStatus investing = MoneyStepStatus.running,
  MoneyStepStatus gather = MoneyStepStatus.waiting,
  MoneyStepStatus convert = MoneyStepStatus.waiting,
  String? convertRef,
  MoneyStepStatus confirm = MoneyStepStatus.waiting,
  MoneyStepStatus place = MoneyStepStatus.waiting,
}) {
  final g = fundedOrderGraph(
    venue: OneBalanceVenue.predictions,
    orderUsd: 15,
    legs: const [
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 8),
      MoneyStep(
          id: 'leg:dollars',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.dollars,
          usd: 5),
      MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          usd: 2),
    ],
  );
  return MoneyStepGraph([
    for (final s in g.steps)
      s.copyWith(
        status: switch (s.id) {
          'leg:bitcoin' => bitcoin,
          'leg:dollars' => dollars,
          'leg:investing' => investing,
          'ready:gather' => gather,
          'ready:convert' => convert,
          'ready:confirm' => confirm,
          'place' => place,
          _ => s.status,
        },
        ref: s.id == 'ready:convert' ? convertRef : null,
      ),
  ]);
}

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ));

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// The words seen under the row: the one status line (every other line
/// is there unseen, for a screen reader).
List<String> _seen(WidgetTester tester) => [
      for (final e in find
          .descendant(
              of: find.byKey(const ValueKey('money-steps-words')),
              matching: find.byType(Text))
          .evaluate())
        if (((e.widget as Text).data ?? '').isNotEmpty &&
            (e.findAncestorWidgetOfExactType<Opacity>()?.opacity ?? 1) > 0)
          (e.widget as Text).data!
    ];

void main() {
  test(
      'every source on its own line, readiness under its stage, the order '
      'last', () async {
    final l10n = await _l10n();
    final lines = moneyStepLines(l10n, _bet(), _usd,
        readyLabel: 'Getting your prediction ready',
        placeLine: 'Placing \$15.00 on Yes');
    expect([
      for (final l in lines) l.text
    ], [
      'Moving \$8.00 from Bitcoin',
      'Moving \$5.00 from Dollars',
      'Moving \$2.00 from Investing',
      'Getting your prediction ready',
      // Three legs converge: the venue waits for all of them first.
      'Waiting for all of it to arrive',
      // The conversion and the allowance show only once they happen.
      'Confirming balance',
      'Placing \$15.00 on Yes',
    ]);
    expect([for (final l in lines) l.sub],
        [false, false, false, false, true, true, false]);
  });

  test('lines complete on their own, in whatever order the legs land',
      () async {
    final l10n = await _l10n();
    List<(String, MoneyStepStatus)> at(MoneyStepGraph g) => [
          for (final l in moneyStepLines(l10n, g, _usd,
              readyLabel: 'Ready', placeLine: 'Place'))
            (l.text, l.status)
        ];
    // Dollars land first; Bitcoin and Investing still moving.
    expect(at(_bet(dollars: MoneyStepStatus.done)).take(3), [
      ('Moving \$8.00 from Bitcoin', MoneyStepStatus.running),
      ('Moved \$5.00 from Dollars', MoneyStepStatus.done),
      ('Moving \$2.00 from Investing', MoneyStepStatus.running),
    ]);
    // Then Investing: the venue waits for the bitcoin too, nothing
    // converts yet (founder, 25 October 2026).
    final waiting = at(_bet(
        dollars: MoneyStepStatus.done,
        investing: MoneyStepStatus.done,
        gather: MoneyStepStatus.running));
    expect(waiting[2], ('Moved \$2.00 from Investing', MoneyStepStatus.done));
    expect(waiting[3], ('Ready', MoneyStepStatus.running));
    expect(waiting[4],
        ('Waiting for all of it to arrive', MoneyStepStatus.running));
    expect(waiting.any((l) => l.$1 == 'Converting to pUSD'), isFalse);
    // Every leg landed and the venue saw all of it: the one conversion.
    final converting = at(_bet(
        bitcoin: MoneyStepStatus.done,
        dollars: MoneyStepStatus.done,
        investing: MoneyStepStatus.done,
        gather: MoneyStepStatus.done,
        convert: MoneyStepStatus.running,
        convertRef: 'seen'));
    expect(converting[4], ('All of it arrived', MoneyStepStatus.done));
    expect(converting[5], ('Converting to pUSD', MoneyStepStatus.running));
    // Then the order.
    final placed = at(_bet(
        bitcoin: MoneyStepStatus.done,
        dollars: MoneyStepStatus.done,
        investing: MoneyStepStatus.done,
        gather: MoneyStepStatus.done,
        convert: MoneyStepStatus.done,
        confirm: MoneyStepStatus.done,
        place: MoneyStepStatus.done));
    expect(placed.first, ('Moved \$8.00 from Bitcoin', MoneyStepStatus.done));
    expect(placed.last, ('Place', MoneyStepStatus.done));
    expect(
        placed.contains(('Converted to pUSD', MoneyStepStatus.done)), isTrue);
  });

  test('failed and fallen-back lines say so', () async {
    final l10n = await _l10n();
    final failed =
        moneyStepLines(l10n, _bet(investing: MoneyStepStatus.failed), _usd);
    expect(failed[2].text, '\$2.00 from Investing didn\'t move');
    expect(failed[2].status, MoneyStepStatus.failed);
    final g = _bet().fallBack('leg:bitcoin', const [
      MoneyStep(
          id: 'leg:bitcoin>dollars',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          to: MoneyPlace.dollars,
          usd: 8,
          status: MoneyStepStatus.running),
    ]);
    final lines = moneyStepLines(l10n, g, _usd);
    // No reason recorded (an older record): neutral, never "busy".
    expect(lines[0].text, 'Bitcoin going via Dollars');
    expect(lines[0].status, MoneyStepStatus.fellBack);
    expect(lines[1].text, 'Moving \$8.00 from Bitcoin → Dollars');
  });

  test('a fallen-back line says the real reason', () async {
    final l10n = await _l10n();
    String line(String? reason) => moneyStepLines(
            l10n,
            _bet().fallBack(
                'leg:bitcoin',
                const [
                  MoneyStep(
                      id: 'leg:bitcoin>dollars',
                      kind: MoneyStepKind.leg,
                      from: MoneyPlace.bitcoin,
                      to: MoneyPlace.dollars,
                      usd: 8),
                ],
                reason: reason),
            _usd)
        .first
        .text;
    // Transient: the only "busy".
    expect(line('network'), 'Bitcoin route busy, going via Dollars');
    expect(line('timeout'), 'Bitcoin route busy, going via Dollars');
    // The route itself is off.
    expect(line('route_unavailable'),
        'Bitcoin route unavailable, going via Dollars');
    expect(line('settlement_routeUnavailable'),
        'Bitcoin route unavailable, going via Dollars');
    expect(line('refused_recently'),
        'Bitcoin route unavailable, going via Dollars');
    // Under the direct route's minimum.
    expect(line('below the Predictions minimum'),
        'Too small to go straight from Bitcoin, going via Dollars');
    // Nothing to act on: the wallet's own guard (the founder's case on 15
    // October 2026), an account read, the approval, an unknown code.
    for (final r in [
      'wallet_guard_recipient_not_own',
      'account_unavailable',
      'settlement_declined',
      'unknown',
      'direct_refused',
      null,
    ]) {
      expect(line(r), 'Bitcoin going via Dollars', reason: '$r');
    }
  });

  testWidgets(
      'the widget: one status line seen, every line there for a screen '
      'reader with its state, no list under the row', (tester) async {
    final l10n = await _l10n();
    final handle = tester.ensureSemantics();
    await _pump(
        tester,
        MoneyStepsView(
          lines: moneyStepLines(
              l10n,
              _bet(
                  dollars: MoneyStepStatus.done,
                  investing: MoneyStepStatus.failed),
              _usd,
              readyLabel: 'Getting your prediction ready',
              placeLine: 'Placing \$15.00 on Yes'),
          note: 'Your \$13 is in Predictions.',
        ));
    await tester.pump();
    // After a stop the status line is the surface's own line.
    expect(_seen(tester), ['Your \$13 is in Predictions.']);
    expect(find.byKey(const ValueKey('money-steps-note')), findsOneWidget);
    // Every line is there, unseen, with its state.
    expect(find.text('Moving \$8.00 from Bitcoin'), findsOneWidget);
    expect(find.text('Moved \$5.00 from Dollars'), findsOneWidget);
    expect(find.text('Confirming balance'), findsOneWidget);
    expect(find.bySemanticsLabel('Moving \$8.00 from Bitcoin'), findsOneWidget);
    expect(find.bySemanticsLabel('Placing \$15.00 on Yes'), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-done-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-failed-2')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('money-step-ready:confirm')), findsOneWidget);
    // No list, tree or chip under the row.
    expect(find.byKey(const ValueKey('money-steps-checkpoints-title')),
        findsNothing);
    expect(find.byKey(const ValueKey('money-steps-chip')), findsNothing);
    handle.dispose();
  });

  testWidgets(
      'the slips\' steps widget renders the graph when the record has '
      'one, and its old stage lines otherwise', (tester) async {
    await _pump(
        tester,
        SlipFundingSteps(
          steps: const [
            'Getting your prediction ready',
            'Placing \$15.00 on Yes'
          ],
          active: 0,
          graph: _bet(),
          money: _usd,
        ));
    await tester.pump();
    expect(find.byKey(const ValueKey('money-steps')), findsOneWidget);
    // A leg is a road on the map: its words are its semantics there.
    expect(findMoneyStep('Moving \$2.00 from Investing'), findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-investing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('money-steps-station-predictions')),
        findsOneWidget);
    await _pump(
        tester,
        const SlipFundingSteps(
          steps: ['Getting your prediction ready', 'Placing \$15.00 on Yes'],
          active: 0,
        ));
    await tester.pump();
    expect(find.byKey(const ValueKey('slip-funding-steps')), findsOneWidget);
  });
  test(
      'the allowance shows only once the venue asked for it: started '
      'alongside the legs, it neither shows nor spins the stage', () async {
    final l10n = await _l10n();
    MoneyStepGraph withApprove(MoneyStepStatus status, {String? ref}) =>
        MoneyStepGraph([
          for (final s in _bet().steps)
            s.id == 'ready:approve' ? s.copyWith(status: status, ref: ref) : s,
        ]);
    List<(String, MoneyStepStatus)> at(MoneyStepGraph g) => [
          for (final l in moneyStepLines(l10n, g, _usd,
              readyLabel: 'Ready', placeLine: 'Place'))
            (l.text, l.status)
        ];
    // The founder's slip: Bitcoin still moving, the allowance step started
    // but never reported by the venue.
    final unseen = at(withApprove(MoneyStepStatus.running));
    expect(unseen.map((l) => l.$1), isNot(contains('Approving spend')));
    expect(unseen, contains(('Ready', MoneyStepStatus.waiting)));
    // Reported: shown, and the stage runs with it.
    final seen = at(withApprove(MoneyStepStatus.running, ref: 'seen'));
    expect(seen, contains(('Approving spend', MoneyStepStatus.running)));
    expect(seen, contains(('Ready', MoneyStepStatus.running)));
  });

  group('the journey plan', () {
    test('a send: the legs home, then one road out to the recipient', () async {
      final l10n = await _l10n();
      final g = MoneyStepGraph([
        const MoneyStep(
            id: 'leg:predictions',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.predictions,
            to: MoneyPlace.dollars,
            usd: 20,
            status: MoneyStepStatus.done),
        const MoneyStep(
            id: 'send',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: 50,
            status: MoneyStepStatus.running),
      ]);
      final plan = MoneyJourneyPlan.of(moneyStepLines(l10n, g, _usd),
          graph: g, toLabel: 'Alice', money: _usd);
      expect(plan.stations.map((s) => s.id).toList(),
          ['predictions', 'dollars', 'outside']);
      expect(plan.stations.last.label, 'Alice');
      expect(plan.stations.map((s) => s.column).toList(), [0, 1, 2]);
      expect(plan.destination, 2);
      expect(plan.roads.length, 2);
      expect(plan.checkpoints, isEmpty);
      expect(plan.chain, [0, 1]);
      expect(plan.headline, '\$50.00');
    });

    test('more than three sources: the rest are listed, not drawn', () async {
      final l10n = await _l10n();
      final g = MoneyStepGraph([
        for (final (id, place) in [
          ('leg:bitcoin', MoneyPlace.bitcoin),
          ('leg:dollars', MoneyPlace.dollars),
          ('leg:investing', MoneyPlace.investing),
          ('leg:predictions', MoneyPlace.predictions),
        ])
          MoneyStep(
              id: id,
              kind: MoneyStepKind.leg,
              from: place,
              to: MoneyPlace.bitcoin,
              usd: 1,
              status: MoneyStepStatus.running),
        const MoneyStep(
            id: 'arrive', kind: MoneyStepKind.arrive, to: MoneyPlace.bitcoin),
      ]);
      // Bitcoin's own leg into Bitcoin: dropped from the map, listed.
      final plan = MoneyJourneyPlan.of(moneyStepLines(l10n, g, _usd), graph: g);
      expect(plan.stations.where((s) => s.column == 0).length,
          lessThanOrEqualTo(MoneyJourneyPlan.maxRows));
      expect(plan.checkpoints, contains(0));
      expect(plan.checkpoints, contains(4));
      expect(plan.destination, isNotNull);
      expect(plan.stations[plan.destination!].place, MoneyPlace.bitcoin);
    });

    test('a route change is listed, its replacement legs are the roads',
        () async {
      final l10n = await _l10n();
      final g = _bet().fallBack('leg:bitcoin', const [
        MoneyStep(
            id: 'leg:bitcoin>dollars',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.bitcoin,
            to: MoneyPlace.dollars,
            usd: 8,
            status: MoneyStepStatus.running),
      ]);
      final lines = moneyStepLines(l10n, g, _usd, placeLine: 'Place');
      final plan = MoneyJourneyPlan.of(lines, graph: g);
      expect(plan.checkpoints.map((i) => lines[i].text),
          contains('Bitcoin going via Dollars'));
      expect(plan.roads.map((r) => lines[r.line].id),
          containsAll(['leg:bitcoin>dollars', 'leg:dollars', 'leg:investing']));
      expect(plan.stations[plan.destination!].place, MoneyPlace.predictions);
    });

    test('no graph: one stage road, every line a checkpoint', () {
      const lines = [
        MoneyStepLine('Adding \$6.00 to Investments', MoneyStepStatus.done),
        MoneyStepLine('Preparing your order', MoneyStepStatus.running),
      ];
      final plan = MoneyJourneyPlan.of(lines,
          from: MoneyPlace.bitcoin, to: MoneyPlace.investing);
      expect(plan.stations.map((s) => s.place).toList(),
          [MoneyPlace.bitcoin, MoneyPlace.investing]);
      expect(plan.roads.single.line, -1);
      expect(plan.roads.single.segments, [0, 1]);
      expect(plan.checkpoints, [0, 1]);
      expect(plan.headline, '\$6.00');
      expect(plan.hasGraph, isFalse);
    });
  });

  group('the calm look', () {
    Future<void> pumpLines(WidgetTester tester, List<MoneyStepLine> lines,
            {MoneyStepGraph? graph, ThemeData? theme}) =>
        tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: theme ?? buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
                body: MoneyStepsView(lines: lines, graph: graph, money: _usd)),
          ),
        ));

    testWidgets(
        'the stage and its sub-steps say themselves only in the status '
        'line; the running sub-step is the one seen', (tester) async {
      // A phone's screen, so the height below is the real one.
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = await _l10n();
      final g = MoneyStepGraph([
        for (final s in _bet(
                dollars: MoneyStepStatus.done,
                investing: MoneyStepStatus.done,
                bitcoin: MoneyStepStatus.done,
                convert: MoneyStepStatus.done)
            .steps)
          s.id == 'ready:confirm'
              ? s.copyWith(status: MoneyStepStatus.running)
              : s,
      ]);
      await pumpLines(
          tester,
          moneyStepLines(l10n, g, _usd,
              readyLabel: 'Getting your prediction ready',
              placeLine: 'Placing \$15.00 on Yes'),
          graph: g);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_seen(tester), ['Confirming balance']);
      expect(find.text('Converted to pUSD'), findsOneWidget);
      expect(find.text('Getting your prediction ready'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      // The money is in Predictions: every source's part is done.
      for (final id in ['bitcoin', 'dollars', 'investing']) {
        expect(find.byKey(ValueKey('money-steps-station-done-$id')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('money-steps-station-done-predictions')),
          findsNothing);
      // Three sources, each on its own row with a small gap (B2, 27
      // October 2026): about 160 high, still short of a sheet's keypad.
      // Two sources stay about 125 (money_journey_parallel_test).
      expect(tester.getSize(find.byKey(const ValueKey('money-steps'))).height,
          lessThan(170));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('dark mode draws the same row in its own colours',
        (tester) async {
      final l10n = await _l10n();
      await pumpLines(
          tester,
          moneyStepLines(l10n, _bet(), _usd,
              readyLabel: 'Ready', placeLine: 'Place'),
          graph: _bet(),
          theme: buildDarkTheme());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('money-steps-map')), findsOneWidget);
      // Three legs at once say so together.
      expect(_seen(tester), ['Moving \$15.00 from 3 balances']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
