// The Move sheet's amount screen: the quick-amount chips, the amount the
// button states, and the balance on the right of the route card.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/home/components/deposit/deposit_quick_amounts.dart';
import 'package:kute/screens/home/components/deposit/deposit_route_card.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/theme/app_theme.dart';

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );

void main() {
  final dollars = <int>[];
  final percents = <(double, String?)>[];
  List<AmountQuickChip> chips({required bool usd, int available = 30}) =>
      moveQuickAmountChips(
        amountIsUsd: usd,
        maxLabel: 'Max',
        exceedsAvailable: (v) => v > available,
        onDollars: dollars.add,
        onPercent: (ratio, {chip}) => percents.add((ratio, chip)),
      );
  setUp(() {
    dollars.clear();
    percents.clear();
  });

  test('a dollar route offers \$10, \$25, \$50 and Max', () {
    final row = chips(usd: true);
    expect(row.map((c) => c.label), [r'$10', r'$25', r'$50', 'Max']);
    // Above the balance reads dimmed; Max never does.
    expect(row.map((c) => c.dimmed), [false, false, true, false]);
  });

  test('a dollar chip types that figure as the keypad would', () {
    for (final chip in chips(usd: true).take(3)) {
      chip.onTap();
    }
    expect(dollars, [10, 25, 50]);
    expect(percents, isEmpty);
    expect(dollars.map(moveQuickAmountTyped), ['10', '25', '50']);
    // What the keypad itself writes for the same keys.
    expect(amountAppendKey(amountAppendKey('', '2'), '5'),
        moveQuickAmountTyped(25));
  });

  test('Max is the old 100% chip: the percent path at 1', () {
    chips(usd: true).last.onTap();
    chips(usd: false).last.onTap();
    expect(percents, [(1.0, 'max'), (1.0, 'max')]);
    expect(dollars, isEmpty);
  });

  test('a bitcoin-typed route keeps 25%, 50% and Max', () {
    final row = chips(usd: false);
    expect(row.map((c) => c.label), ['25%', '50%', 'Max']);
    row[0].onTap();
    row[1].onTap();
    expect(percents, [(0.25, null), (0.5, null)]);
  });

  test('a screen with no balance of its own gets fixed amounts, no Max', () {
    final row = moveQuickAmountChips(
      amountIsUsd: true,
      symbol: '€',
      withMax: false,
      maxLabel: 'Max',
      exceedsAvailable: (_) => false,
      onDollars: dollars.add,
      onPercent: (ratio, {chip}) => percents.add((ratio, chip)),
    );
    expect(row.map((c) => c.label), ['€10', '€25', '€50']);
    row[1].onTap();
    expect(dollars, [25]);
    expect(percents, isEmpty);
  });

  test('the button states whole dollars plainly and keeps real cents', () {
    expect(moveButtonUsd(50), r'$50');
    expect(moveButtonUsd(49.999), r'$50');
    expect(moveButtonUsd(12.34), r'$12.34');
    expect(moveButtonUsd(0.5), r'$0.50');
    expect(moveButtonUsd(1250), r'$1250');
  });

  testWidgets('button label joins the verb and the amount', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      l10n = AppLocalizations.of(context);
      return const SizedBox.shrink();
    })));
    expect(l10n.moveActionWithAmount(l10n.moveWithdraw, moveButtonUsd(50)),
        r'Withdraw $50');
    expect(l10n.moveActionWithAmount(l10n.moveAdd, moveButtonUsd(12.5)),
        r'Add $12.50');
  });

  testWidgets('chips fire their own tap, and none while disabled',
      (tester) async {
    await tester.pumpWidget(_host(AmountQuickChips(chips: chips(usd: true))));
    await tester.tap(find.text(r'$25'));
    // Dimmed stays tappable: the sheet answers an over-balance amount.
    await tester.tap(find.text(r'$50'));
    await tester.tap(find.text('Max'));
    expect(dollars, [25, 50]);
    expect(percents, [(1.0, 'max')]);

    await tester.pumpWidget(
        _host(AmountQuickChips(enabled: false, chips: chips(usd: true))));
    await tester.tap(find.text(r'$10'));
    await tester.tap(find.text('Max'));
    expect(dollars, [25, 50]);
    expect(percents, [(1.0, 'max')]);
  });

  testWidgets('the route card shows the balance on the right; tap fills',
      (tester) async {
    var filled = 0;
    var picked = 0;
    await tester.pumpWidget(_host(MoveRouteCard(
      from: MoveRouteEndpoint(
        name: 'Bitcoin',
        asset: 'lib/assets/bitcoin-icon.svg',
        available: r'$124.50',
        onAvailableTap: () => filled++,
        onTap: () => picked++,
      ),
    )));
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text(r'$124.50'), findsOneWidget);
    expect(find.text('available'), findsOneWidget);
    // One account of the asset: no account label.
    expect(find.textContaining('Spending'), findsNothing);
    expect(
        tester.getCenter(find.text(r'$124.50')).dx >
            tester.getCenter(find.text('Bitcoin')).dx,
        isTrue);
    await tester.tap(find.text(r'$124.50'));
    expect((filled, picked), (1, 0));
    await tester.tap(find.text('Bitcoin'));
    expect((filled, picked), (1, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a state still reads under the name, beside the account',
      (tester) async {
    await tester.pumpWidget(_host(const MoveRouteCard(
      from: MoveRouteEndpoint(
        name: 'Bitcoin',
        asset: 'lib/assets/bitcoin-icon.svg',
        origin: 'Spending',
        detail: 'Insufficient balance',
        detailIsError: true,
        available: r'$6.00',
      ),
      to: MoveRouteEndpoint(
          name: 'Investing', asset: 'lib/assets/hyperliquid-logo.svg'),
    )));
    expect(find.text('Spending · Insufficient balance', findRichText: true),
        findsOneWidget);
    expect(find.text(r'$6.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
