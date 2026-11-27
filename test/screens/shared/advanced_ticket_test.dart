// The Advanced tickets' shared pieces (advanced_ticket.dart): each renders
// in light and dark, calls back, and the odds rail snaps to the tick.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/advanced_ticket.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool dark = false, Size size = const Size(400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    ),
  ));
  await tester.pump();
}

void main() {
  test('the odds rail snaps to the tick inside [tick, 1 - tick]', () {
    expect(advancedSnapOdds(0.537, 0.01), 0.54);
    expect(advancedSnapOdds(0.0, 0.01), 0.01);
    expect(advancedSnapOdds(1.0, 0.01), 0.99);
    expect(advancedSnapOdds(0.0034, 0.001), 0.003);
    expect(advancedSnapOdds(0.56, 0.1), 0.6);
  });

  test('price map pills never come closer than the minimum gap', () {
    final ys = AdvancedPriceMap.layout([100, 100.2, 100.1, 80, 120], 132);
    final sorted = [...ys]..sort();
    for (var i = 1; i < sorted.length; i++) {
      expect(sorted[i] - sorted[i - 1],
          greaterThanOrEqualTo(AdvancedPriceMap.minGap - 1e-9));
    }
    expect(sorted.first, greaterThanOrEqualTo(0));
  });

  for (final dark in [false, true]) {
    testWidgets('the pieces render and call back (${dark ? 'dark' : 'light'})',
        (tester) async {
      var type = 0;
      final steps = <int>[];
      var toggled = false;
      int? chip;
      double? odds;
      final controller = TextEditingController();
      await _pump(
          tester,
          SingleChildScrollView(
            child: Column(children: [
              AdvancedHeroAmount(controller: controller, caption: 'Available'),
              AdvancedTypeTiles(
                options: const [
                  AdvancedTypeOption(
                      label: 'Market', glyph: AdvancedTypeGlyph.market),
                  AdvancedTypeOption(
                      label: 'Limit', glyph: AdvancedTypeGlyph.limit),
                  AdvancedTypeOption(
                      label: 'Scale', glyph: AdvancedTypeGlyph.scale),
                  AdvancedTypeOption(label: 'TWAP', glyph: AdvancedTypeGlyph.twap),
                ],
                selected: 0,
                onSelected: (i) => type = i,
                sideColor: AppColors.marketUp,
                explanation: 'Explains.',
              ),
              AdvancedStepper(
                  label: 'Limit price',
                  value: '53¢',
                  onStep: steps.add,
                  trailing: 'Market 53.5%'),
              AdvancedToggleRow(
                icon: Icons.shield_outlined,
                title: 'Stop loss',
                subtitle: 'Sells if it falls',
                value: true,
                onChanged: (v) => toggled = v,
                children: const [Text('folded open')],
              ),
              AdvancedChips(
                  labels: const ['1%', '2%'],
                  selected: null,
                  onSelected: (i) => chip = i),
              const AdvancedSummaryCard(
                headline: AdvancedSummaryRow('Payout if you win', r'$18.86'),
                headlineColor: AppColors.marketUp,
                rows: [AdvancedSummaryRow('Shares', '18.86')],
              ),
              AdvancedPriceMap(
                now: 100,
                entry: 100,
                formatPrice: (p) => p.toStringAsFixed(0),
                levels: const [
                  AdvancedPriceLevel(
                      price: 110, kind: AdvancedLevelKind.takeProfit, label: 'TP'),
                  AdvancedPriceLevel(
                      price: 95, kind: AdvancedLevelKind.stopLoss, label: 'SL'),
                ],
              ),
              SizedBox(
                width: 300,
                child: AdvancedOddsTrack(
                  price: 0.5,
                  market: 0.55,
                  tick: 0.01,
                  sideColor: AppColors.marketUp,
                  onChanged: (p) => odds = p,
                  marketLabel: 'Market 55%',
                  fillsFrom: 0.56,
                  thumbLabel: 'Rests',
                ),
              ),
            ]),
          ),
          dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text(r'$0'), findsOneWidget);
      await tester.tap(find.text('Limit'));
      expect(type, 1);
      await tester.tap(find.byKey(const ValueKey('advanced-stepper-plus')));
      await tester.tap(find.byKey(const ValueKey('advanced-stepper-minus')));
      expect(steps, [1, -1]);
      expect(find.text('folded open'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(toggled, isFalse);
      await tester.tap(find.byKey(const ValueKey('advanced-chip-1')));
      expect(chip, 1);
      expect(find.text('TP 110 · +10.0%'), findsOneWidget);
      expect(find.text('SL 95 · -5.00%'), findsOneWidget);
      final rail = find.byKey(const ValueKey('advanced-odds-rail'));
      await tester.ensureVisible(rail);
      final box = tester.getRect(rail);
      // A tap at about a quarter of the rail: snapped to a whole cent.
      await tester.tapAt(Offset(box.left + 18 + (box.width - 36) * 0.251, box.center.dy));
      expect(odds, isNotNull);
      expect((odds! * 100 - (odds! * 100).roundToDouble()).abs(), lessThan(1e-9));
      expect(odds, closeTo(0.25, 0.011));
      // The hero focuses its input on a tap; typing lands in the controller.
      await tester.tap(find.byKey(const ValueKey('advanced-hero-amount')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(controller.text, '12');
      expect(find.text(r'$12'), findsOneWidget);
    });
  }

  testWidgets('the frame floats its primary over a fade, no bar',
      (tester) async {
    await _pump(
        tester,
        AdvancedTicketFrame(
          title: 'Advanced prediction',
          onBack: () {},
          primaryHeight: 72,
          primary: const SizedBox(height: 72, child: Text('pill')),
          children: [for (var i = 0; i < 30; i++) Text('row $i')],
        ));
    final fade = tester.getRect(find.byKey(const ValueKey('advanced-ticket-fade')));
    final pill = tester.getRect(find.byKey(const ValueKey('advanced-ticket-primary')));
    // The primary sits over the content's foot, inside the fade.
    expect(pill.bottom, closeTo(fade.bottom, 1));
    expect(fade.height, greaterThanOrEqualTo(AdvancedTicketFrame.fadeHeight));
    expect(find.text('Advanced prediction'), findsOneWidget);
  });
}
