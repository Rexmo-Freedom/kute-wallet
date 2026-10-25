// Legs from several balances run at once (founder, 25 October 2026): the
// journey draws them as parallel branches converging on Predictions, each
// filling at its own pace from its own station, says them together in
// the status line, then waits at Predictions until every leg's money is
// confirmed there ("Waiting for both to arrive") before the conversion
// and the order.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show fundedOrderGraph;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

const _run = MoneyStepStatus.running;
const _done = MoneyStepStatus.done;
const _wait = MoneyStepStatus.waiting;

/// \$9.18 on No: \$4.18 from Bitcoin straight in, \$5.00 from Investing.
MoneyStepGraph _bet({
  MoneyStepStatus bitcoin = _run,
  MoneyStepStatus investing = _run,
  MoneyStepStatus gather = _wait,
  MoneyStepStatus convert = _wait,
  MoneyStepStatus confirm = _wait,
  MoneyStepStatus place = _wait,
}) {
  final g = fundedOrderGraph(
    venue: OneBalanceVenue.predictions,
    orderUsd: 9.18,
    legs: const [
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 4.18,
          route: MoneyRoute.direct),
      MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          usd: 5),
    ],
  );
  return MoneyStepGraph([
    for (final s in g.steps)
      s.copyWith(
        status: switch (s.id) {
          'leg:bitcoin' => bitcoin,
          'leg:investing' => investing,
          'ready:gather' => gather,
          'ready:convert' => convert,
          'ready:confirm' => confirm,
          'place' => place,
          _ => s.status,
        },
        ref: s.id == 'ready:convert' && convert != _wait ? 'seen' : null,
      ),
  ]);
}

late AppLocalizations _en;

List<MoneyStepLine> _lines(MoneyStepGraph g) => moneyStepLines(_en, g, _usd,
    readyLabel: 'Getting your prediction ready',
    placeLine: 'Placing \$9.18 on No');

Widget _app(MoneyStepGraph g, {ThemeData? theme, Key? boundary}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: MoneyStepsView(
                        lines: _lines(g), graph: g, money: _usd),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// The one status line seen under the row.
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

Offset _station(WidgetTester tester, String id) => tester
    .getCenter(find.byKey(ValueKey('money-steps-station-$id')));

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

void main() {
  setUpAll(() async {
    _en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('the plan: two roads from two stations in the first column, both '
      'into Predictions; the wait before the conversion', () {
    final g = _bet();
    final plan = MoneyJourneyPlan.of(_lines(g), graph: g);
    expect(plan.roads, hasLength(2));
    final froms = plan.roads.map((r) => plan.stations[r.from]).toList();
    expect(froms.map((s) => s.place).toSet(),
        {MoneyPlace.bitcoin, MoneyPlace.investing});
    expect(froms.every((s) => s.column == 0), isTrue);
    expect(froms.map((s) => s.row).toSet(), {0, 1});
    expect(plan.roads.map((r) => r.to).toSet(), {plan.destination});
    expect(plan.stations[plan.destination!].place, MoneyPlace.predictions);
    // Both legs running at once.
    expect([for (final r in plan.roads) plan.lines[r.line].status],
        [_run, _run]);
    // The graph: the wait comes from either leg landing, the conversion
    // and the allowance only after it.
    expect(g.byId('ready:gather')!.after, ['leg:bitcoin', 'leg:investing']);
    expect(g.byId('ready:convert')!.after, ['ready:gather']);
    expect(g.byId('ready:approve')!.after, ['ready:gather']);
  });

  testWidgets(
      'two legs at once: two lines filling on their own, said together; '
      'then the wait, the conversion, the order', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_bet()));
    await tester.pump(const Duration(milliseconds: 600));
    final btc = _station(tester, 'bitcoin');
    final hl = _station(tester, 'investing');
    final pm = _station(tester, 'predictions');
    // Parallel branches: one column, two rows, converging on Predictions.
    expect(btc.dx, hl.dx);
    expect(btc.dy, isNot(hl.dy));
    expect(pm.dx, greaterThan(btc.dx));
    expect(pm.dy, closeTo((btc.dy + hl.dy) / 2, 0.01));
    expect(_motion(tester).litOf('leg:bitcoin'), greaterThan(0));
    expect(_motion(tester).litOf('leg:investing'), greaterThan(0));
    expect(_seen(tester),
        ['Moving \$4.18 from Bitcoin and \$5.00 from Investing']);
    // Each leg's own words stay there for a screen reader.
    expect(find.text('Moving \$4.18 from Bitcoin'), findsOneWidget);
    expect(find.text('Moving \$5.00 from Investing'), findsOneWidget);

    // Bitcoin lands first: its line fills, Investing's keeps its pace.
    await tester.pumpWidget(_app(_bet(bitcoin: _done, gather: _run)));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    expect(_motion(tester).litOf('leg:investing'), lessThan(1));
    expect(_seen(tester), ['Moving \$5.00 from Investing']);

    // Both landed, the venue has not seen all of it yet: the wait, and no
    // conversion line at all.
    await tester.pumpWidget(
        _app(_bet(bitcoin: _done, investing: _done, gather: _run)));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_seen(tester), ['Waiting for both to arrive']);
    expect(find.text('Converting to pUSD'), findsNothing);
    final lines =
        _lines(_bet(bitcoin: _done, investing: _done, gather: _run));
    final wait = lines.indexWhere((l) => l.id == 'ready:gather');
    expect(wait, greaterThan(0));
    expect(lines.indexWhere((l) => l.id == 'ready:convert'), -1);

    // Every leg's money there: the one conversion.
    await tester.pumpWidget(_app(_bet(
        bitcoin: _done, investing: _done, gather: _done, convert: _run)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_seen(tester), ['Converting to pUSD']);

    // Then the order.
    await tester.pumpWidget(_app(_bet(
        bitcoin: _done,
        investing: _done,
        gather: _done,
        convert: _done,
        confirm: _done,
        place: _run)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_seen(tester), ['Placing \$9.18 on No']);
    await tester.pumpWidget(_app(_bet(
        bitcoin: _done,
        investing: _done,
        gather: _done,
        convert: _done,
        confirm: _done,
        place: _done)));
    await tester.pump(const Duration(seconds: 3));
    expect(_seen(tester), ['Placed!']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  // Frames for a look by eye (written only when asked:
  // JOURNEY_FRAMES=<dir>).
  final framesDir = Platform.environment['JOURNEY_FRAMES'];
  testWidgets('frames', skip: framesDir == null, (tester) async {
    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.physicalSize = const Size(430 * 3, 932 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Directory(framesDir!).createSync(recursive: true);
    for (final dark in [false, true]) {
      final base = dark ? buildDarkTheme() : buildLightTheme();
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Inter'));
      final key = GlobalKey();
      Future<void> shot(String name, MoneyStepGraph g, Duration after) async {
        await tester.pumpWidget(DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Inter'),
            child: _app(g, theme: theme, boundary: key)));
        await tester.pump(after);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$framesDir/${dark ? 'dark' : 'light'}-$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      await shot('1-both-moving', _bet(), const Duration(milliseconds: 1500));
      await shot('2-bitcoin-landed', _bet(bitcoin: _done, gather: _run),
          const Duration(milliseconds: 1200));
      await shot(
          '3-waiting-for-both',
          _bet(bitcoin: _done, investing: _done, gather: _run),
          const Duration(milliseconds: 1200));
      await shot(
          '4-converting',
          _bet(bitcoin: _done, investing: _done, gather: _done, convert: _run),
          const Duration(milliseconds: 900));
      await shot(
          '5-placed',
          _bet(
              bitcoin: _done,
              investing: _done,
              gather: _done,
              convert: _done,
              confirm: _done,
              place: _done),
          const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
