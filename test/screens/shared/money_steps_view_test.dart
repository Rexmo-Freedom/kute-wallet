// The one widget every funded order shows its step graph with (founder,
// 15 October 2026: "on the progress we show what is happening. Pulling
// money from bitcoin balance, from predictions and all that. It must be
// clear to the user. and when they are completed also"): one line per
// source with its own state, the venue's readiness as sub-steps under its
// stage line, the order last; lines complete independently.

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

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

MoneyStepGraph _bet({
  MoneyStepStatus bitcoin = MoneyStepStatus.running,
  MoneyStepStatus dollars = MoneyStepStatus.running,
  MoneyStepStatus investing = MoneyStepStatus.running,
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
      // The conversion and the allowance show only once they happen.
      'Confirming balance',
      'Placing \$15.00 on Yes',
    ]);
    expect([for (final l in lines) l.sub],
        [false, false, false, false, true, false]);
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
    // Then Investing, then the conversion runs: the stage runs with it.
    final converting = at(_bet(
        dollars: MoneyStepStatus.done,
        investing: MoneyStepStatus.done,
        convert: MoneyStepStatus.running,
        convertRef: 'seen'));
    expect(
        converting[2], ('Moved \$2.00 from Investing', MoneyStepStatus.done));
    expect(converting[3], ('Ready', MoneyStepStatus.running));
    expect(converting[4], ('Converting to pUSD', MoneyStepStatus.running));
    // The order goes while the bitcoin is still landing.
    final placed = at(_bet(
        dollars: MoneyStepStatus.done,
        investing: MoneyStepStatus.done,
        convert: MoneyStepStatus.done,
        confirm: MoneyStepStatus.done,
        place: MoneyStepStatus.done));
    expect(
        placed.first, ('Moving \$8.00 from Bitcoin', MoneyStepStatus.running));
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
      'the widget: a spinner per running line, a check per done one, '
      'the error sign on a failed one, indented sub-steps', (tester) async {
    final l10n = await _l10n();
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
    expect(find.text('Moving \$8.00 from Bitcoin'), findsOneWidget);
    expect(find.text('Moved \$5.00 from Dollars'), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-done-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-failed-2')), findsOneWidget);
    expect(find.text('Your \$13 is in Predictions.'), findsOneWidget);
    final sub = tester.widget<Padding>(
        find.byKey(const ValueKey('money-step-ready:confirm')));
    expect((sub.padding as EdgeInsets).left, greaterThan(0));
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
    expect(find.text('Moving \$2.00 from Investing'), findsOneWidget);
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

  group('the steps as a tree', () {
    Future<void> pumpLines(WidgetTester tester, List<MoneyStepLine> lines,
            {ThemeData? theme}) =>
        tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: theme ?? buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: MoneyStepsView(lines: lines)),
          ),
        ));

    Iterable<MoneyStepTreePainter> painters(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<MoneyStepTreePainter>();

    testWidgets(
        'a stage with sub-steps: the trunk from the stage, ├ into each, └ '
        'into the last; same signs and words as before', (tester) async {
      final l10n = await _l10n();
      final lines = moneyStepLines(
          l10n,
          MoneyStepGraph([
            for (final s in _bet(
                    dollars: MoneyStepStatus.done,
                    investing: MoneyStepStatus.done,
                    convert: MoneyStepStatus.done)
                .steps)
              s.id == 'ready:confirm'
                  ? s.copyWith(status: MoneyStepStatus.running)
                  : s,
          ]),
          _usd,
          readyLabel: 'Getting your prediction ready',
          placeLine: 'Placing \$15.00 on Yes');
      await pumpLines(tester, lines);
      await tester.pump();
      expect(find.byKey(const ValueKey('money-step-tree-ready')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-tree-ready:convert')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-tree-ready:confirm')),
          findsOneWidget);
      // Legs and the order are not in the tree.
      expect(find.byKey(const ValueKey('money-step-tree-leg:bitcoin')),
          findsNothing);
      expect(find.byKey(const ValueKey('money-step-tree-place')), findsNothing);
      expect(painters(tester).map((p) => p.role).toList(), [
        MoneyStepTreeRole.parent,
        MoneyStepTreeRole.child,
        MoneyStepTreeRole.lastChild,
      ]);
      // The lines' own quiet colour, no fill, no box.
      final c = buildLightTheme().extension<AppColorsExtension>()!;
      expect(
          painters(tester).every((p) => p.color == c.textTertiary), isTrue);
      expect(find.text('Converted to pUSD'), findsOneWidget);
      expect(find.text('Confirming balance'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      // Sub-steps keep their indent, the accessibility text is the words.
      final sub = tester.widget<Padding>(
          find.byKey(const ValueKey('money-step-ready:confirm')));
      expect((sub.padding as EdgeInsets).left, greaterThan(0));
      expect(find.bySemanticsLabel('Confirming balance'), findsOneWidget);
    });

    testWidgets('no sub-steps, no connectors (a move, the Activity detail)',
        (tester) async {
      final l10n = await _l10n();
      await pumpLines(
          tester, moneyStepLines(l10n, _bet(), _usd, placeLine: 'Place'));
      await tester.pump();
      expect(painters(tester), isEmpty);
      expect(find.text('Confirming balance'), findsOneWidget);
    });

    testWidgets('dark mode draws the same tree in its own colours',
        (tester) async {
      final l10n = await _l10n();
      await pumpLines(
          tester,
          moneyStepLines(l10n, _bet(), _usd,
              readyLabel: 'Ready', placeLine: 'Place'),
          theme: buildDarkTheme());
      await tester.pump();
      expect(painters(tester).map((p) => p.role).toList(),
          [MoneyStepTreeRole.parent, MoneyStepTreeRole.lastChild]);
      final dark = buildDarkTheme().extension<AppColorsExtension>()!;
      expect(painters(tester).every((p) => p.color == dark.textTertiary),
          isTrue);
    });

    test('the painter draws only lines, and repaints only on a change', () {
      const a = MoneyStepTreePainter(
          role: MoneyStepTreeRole.child,
          color: Colors.grey,
          trunkX: 6.5,
          indent: 22,
          signHalf: 7);
      expect(a.shouldRepaint(a), isFalse);
      expect(
          a.shouldRepaint(const MoneyStepTreePainter(
              role: MoneyStepTreeRole.lastChild,
              color: Colors.grey,
              trunkX: 6.5,
              indent: 22,
              signHalf: 7)),
          isTrue);
    });
  });
}
