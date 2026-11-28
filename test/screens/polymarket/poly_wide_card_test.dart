// The wide web Predictions page: the grid's card per kind (more outcomes,
// Yes / No, a match), its buttons asking for the slip with the right pick
// (and doing nothing else: no order is placed by a card), "+N more", the
// volume line, no bars / sparklines / move arrows and no advice or
// leverage wording; the featured card stepping through its set. The
// column rule gives four at 1440 with the sidebar, three at about 1100.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardPick;
import 'package:kute/screens/polymarket/components/poly_wide_card.dart';
import 'package:kute/theme/app_theme.dart';

Finder outcomeLines() => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('poly-wide-outcome-'));

Widget _host(Widget child, {double width = 300, double? height}) =>
    ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                  width: width,
                  height: height ?? kPolyWideCardHeight,
                  child: child),
            ),
          ),
        ),
      ),
    );

void _noAdviceOrLeverage(WidgetTester tester) {
  final words = RegExp(r'leverage|\d+x\b|recommend|should buy|advice',
      caseSensitive: false);
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    expect(words.hasMatch(t.data ?? ''), isFalse, reason: t.data);
  }
}

void main() {
  final picks = <PolyWidePick>[];
  var taps = 0;
  setUp(() {
    picks.clear();
    taps = 0;
  });

  Future<void> pump(WidgetTester tester, String title,
      List<PolymarketOutcome> outcomes,
      {double volume = 0}) async {
    await tester.pumpWidget(_host(PolyWideCard(
      title: title,
      outcomes: outcomes,
      volume: volume,
      onTap: () => taps++,
      onPick: picks.add,
    )));
  }

  testWidgets('many outcomes: the two leaders, each a small Yes and No',
      (tester) async {
    await pump(tester, 'Who will win the election?', const [
      PolymarketOutcome(name: 'Ana', price: 0.12),
      PolymarketOutcome(name: 'Bruno', price: 0.55),
      PolymarketOutcome(name: 'Carla', price: 0.25),
      PolymarketOutcome(name: 'Duarte', price: 0.08),
    ], volume: 1250000);
    expect(outcomeLines(), findsNWidgets(2));
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Carla'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
    expect(find.text('55%'), findsOneWidget);
    expect(find.byKey(const ValueKey('poly-wide-yes-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('poly-wide-no-1')), findsOneWidget);
    final footer =
        tester.widget<Text>(find.byKey(const ValueKey('poly-wide-footer')));
    expect(footer.data, contains('+2 more'));
    expect(footer.data, contains(r'$1.3M'));
    // No picture without a drawable one: the title takes its place.
    expect(find.byKey(const ValueKey('poly-wide-picture')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Icon), findsNothing);
    _noAdviceOrLeverage(tester);

    // Bruno (index 1 of the event) on No; Carla (index 2) on Yes.
    await tester.tap(find.byKey(const ValueKey('poly-wide-no-0')));
    await tester.tap(find.byKey(const ValueKey('poly-wide-yes-1')));
    expect(picks.map((p) => (p.pick, p.outcomeIndex, p.no)).toList(), [
      (null, 1, true),
      (null, 2, false),
    ]);
    expect(taps, 0, reason: 'a button opens the slip, not the market');
    await tester.tap(find.byKey(const ValueKey('poly-wide-card')));
    expect(taps, 1);
    expect(picks, hasLength(2));
  });

  testWidgets('Yes / No: the chance, one wide Yes and one wide No',
      (tester) async {
    await pump(tester, 'Will it rain in Lisbon tomorrow?', const [
      PolymarketOutcome(name: 'Yes', price: 0.38),
      PolymarketOutcome(name: 'No', price: 0.62),
    ]);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('poly-wide-chance')))
            .data,
        '38%');
    final yes = find.byKey(const ValueKey('poly-wide-yes'));
    final no = find.byKey(const ValueKey('poly-wide-no'));
    expect(yes, findsOneWidget);
    expect(no, findsOneWidget);
    // Side by side, sharing the card's width.
    expect(tester.getSize(yes).width, greaterThan(100));
    expect(tester.getTopLeft(yes).dy, tester.getTopLeft(no).dy);
    expect(find.textContaining('more'), findsNothing);
    expect(find.byKey(const ValueKey('poly-wide-footer')), findsNothing);
    _noAdviceOrLeverage(tester);
    await tester.tap(no);
    await tester.tap(yes);
    expect(picks.map((p) => (p.pick, p.outcomeIndex)).toList(), [
      (const PolyCardPick.side('no'), null),
      (const PolyCardPick.side('yes'), null),
    ]);
    expect(taps, 0);
  });

  testWidgets('a match: its two sides, each one button named for it',
      (tester) async {
    await pump(tester, 'Benfica vs Porto', const [
      PolymarketOutcome(name: 'Benfica', price: 0.58),
      PolymarketOutcome(name: 'Porto', price: 0.42),
    ]);
    expect(outcomeLines(), findsNWidgets(2));
    final a = find.byKey(const ValueKey('poly-wide-side-0'));
    final b = find.byKey(const ValueKey('poly-wide-side-1'));
    expect(find.descendant(of: a, matching: find.text('Benfica')),
        findsOneWidget);
    expect(
        find.descendant(of: b, matching: find.text('Porto')), findsOneWidget);
    expect(find.byKey(const ValueKey('poly-wide-yes')), findsNothing);
    _noAdviceOrLeverage(tester);
    await tester.tap(b);
    expect(picks.single.pick, const PolyCardPick.game(1));
  });

  testWidgets('featured: rows, volume, previous / next through the set',
      (tester) async {
    PolymarketEvent ev(String id, String title, double yes) => PolymarketEvent(
          id: id,
          slug: id,
          title: title,
          volume: 5000000,
          liquidity: 0,
          category: 'politics',
          conditionId: 'c-$id',
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: yes),
            PolymarketOutcome(name: 'No', price: 1 - yes),
          ],
        );
    final opened = <String>[];
    await tester.pumpWidget(_host(
      PolyWideFeatured(
        markets: [
          ev('a', 'Will the bill pass?', 0.7),
          ev('b', 'Will the summit happen?', 0.2),
        ],
        onOpen: (e) => opened.add(e.id),
        chart: false,
      ),
      width: 1000,
      height: kPolyWideFeaturedHeight,
    ));
    expect(find.text('Will the bill pass?'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.byKey(const ValueKey('poly-wide-featured-volume')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poly-wide-featured-next')));
    await tester.pump();
    expect(find.text('Will the summit happen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poly-wide-featured-next')));
    await tester.pump();
    expect(find.text('Will the bill pass?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poly-wide-featured-prev')));
    await tester.pump();
    expect(find.text('Will the summit happen?'), findsOneWidget);
    expect(opened, isEmpty, reason: 'stepping opens nothing');
    await tester.tap(find.byKey(const ValueKey('poly-wide-featured-title')));
    expect(opened, ['b']);
  });

  test('columns: 280 at the narrowest, 16 between', () {
    // 1440 window less the sidebar and gutters: about 1150 of content.
    expect(polyWideColumns(1150), 3);
    expect(polyWideColumns(1220), 4);
    expect(polyWideColumns(760), 2);
    expect(polyWideColumns(1600), 5);
    expect(polyWideColumns(200), 1);
  });
}
