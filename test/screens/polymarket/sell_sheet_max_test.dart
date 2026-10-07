// The Predictions sell sheet carries the buy slips' one small Max beside
// the figure: it fills the whole position (every share), and restores that
// after the figure is edited. A position with nothing to sell has none.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/theme/app_theme.dart';

class _FakeTrading extends PolymarketTradingNotifier {
  @override
  Future<void> refresh() async {}

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

PolymarketPosition _position({double size = 18.6}) => PolymarketPosition(
      marketId: 'condition',
      marketQuestion: 'Will the U.S. invade Iran before 2027?',
      outcome: 'Yes',
      size: size,
      avgPrice: 0.15,
      currentPrice: 0.15,
      pnl: 0,
      pnlPercent: 0,
      isResolved: false,
      tokenId: 'yes',
    );

Future<void> _pump(WidgetTester tester, PolymarketPosition position) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [polymarketTradingProvider.overrideWith(_FakeTrading.new)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SellSheet(position: position)),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester) async {
  // Unmount so the sheet's book refresh timer stops.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

String _typed(WidgetTester tester) =>
    tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('one small Max beside the figure sells the whole position',
      (tester) async {
    await _pump(tester, _position());
    final hero = find.byType(BigAmountDisplay);
    final max = find.descendant(of: hero, matching: find.byType(AmountMaxChip));
    expect(max, findsOneWidget);
    expect(_typed(tester), isEmpty);

    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pump();
    // 18.6 shares at 15c.
    expect(_typed(tester), '2.79');
    expect(find.textContaining('18.60'), findsWidgets);

    // Edited down, Max brings the whole position back.
    final pad = find.byType(AmountKeypad);
    await tester.tap(find.descendant(
        of: pad, matching: find.byIcon(Icons.backspace_rounded)));
    await tester.pump();
    expect(_typed(tester), '2.7');
    await tester.tap(max);
    await tester.pump();
    expect(_typed(tester), '2.79');
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('nothing to sell, no Max', (tester) async {
    await _pump(tester, _position(size: 0));
    expect(find.byType(AmountMaxChip), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
}
