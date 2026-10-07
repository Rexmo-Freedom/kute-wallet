// An Investing position on the Portfolio, in the Investing list card's
// language: logo, name over one short line ("Long 5x · Liq 12% away", the
// distance alone amber inside 10% and red inside 5%), and on the right the
// user's money in it, what closing now gives back (margin plus P&L), with
// the profit or loss and its return on the margin under it. No notional,
// size or entry on the card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

HlPerpPosition _position({double szi = 0.5, double? liq = 58000}) =>
    HlPerpPosition(
      coin: 'BTC',
      szi: szi,
      entryPx: 64000,
      positionValue: 33000,
      unrealizedPnl: 1000,
      returnOnEquity: 0.15,
      liquidationPx: liq,
      marginUsed: 6600,
      leverageType: 'cross',
      leverageValue: 5,
      maxLeverage: 40,
    );

Future<void> _pump(WidgetTester tester, HlPerpPosition position,
    {double? mid, double width = 390, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => mid),
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HlPortfolioPositionCard(position: position),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The card's one caption line, written out.
String _caption(WidgetTester tester) => tester
    .widget<Text>(find.byWidgetPredicate((w) =>
        w is Text &&
        RegExp(r'^(Long|Short) \d+x').hasMatch(w.textSpan?.toPlainText() ?? '')))
    .textSpan!
    .toPlainText();

/// The live figures on the card: the money in it, then the P&L.
List<RollingNumberText> _figures(WidgetTester tester) => tester
    .widgetList<RollingNumberText>(find.descendant(
        of: find.byType(PortfolioCardValue),
        matching: find.byType(RollingNumberText)))
    .toList();

/// The colour of the "… away" span of the card's caption.
Color? _distanceColor(WidgetTester tester) {
  final text = tester.widget<Text>(find.byWidgetPredicate((w) =>
      w is Text && (w.textSpan?.toPlainText() ?? '').contains('Liq')));
  Color? found;
  text.textSpan!.visitChildren((span) {
    if (span is TextSpan && (span.text ?? '').endsWith('away')) {
      found = span.style?.color;
    }
    return true;
  });
  return found;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a long: name, "Long 5x · Liq 12% away", money in it over '
      'the P&L', (tester) async {
    await _pump(tester, _position());
    expect(find.byType(HlCoinIcon), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    // Mark 66,000 (33,000 / 0.5): 8,000 away is 12%, neutral.
    expect(_caption(tester), 'Long 5x · Liq 12% away');
    expect(_distanceColor(tester), isNull);
    // The size, the entry and the liquidation price live on the position
    // screen, not on the card.
    expect(find.textContaining('Entry'), findsNothing);
    expect(find.textContaining(r'$58,000'), findsNothing);
    expect(find.textContaining(r'$33,000'), findsNothing);
    // No button on the card.
    expect(find.text('Add margin'), findsNothing);

    final c = AppColorsExtension.light();
    final texts = _figures(tester);
    // Cross: the collateral (6,600) plus the P&L (1,000) is what closing
    // gives back; the P&L's return is on the collateral.
    expect(texts[0].text, r'$7,600.00');
    expect(texts[0].style.color, c.textPrimary);
    expect(texts[1].text, r'+$1,000.00 (+15.2%)');
    expect(texts[1].style.color, AppColors.marketUp);
    // Right-aligned: the figure ends past the name.
    expect(tester.getTopRight(find.byType(PortfolioCardValue)).dx,
        greaterThan(tester.getTopRight(find.text('Bitcoin')).dx));
    expect(tester.takeException(), isNull);
  });

  // An isolated 1x short like João's: notional $10.31 at the mark, his
  // margin (with the margin he added) plus a $0.90 profit is $11.20 in it.
  // The venue reports an isolated position's marginUsed as margin plus the
  // snapshot P&L.
  const short = HlPerpPosition(
    coin: 'BTC',
    szi: -0.000083,
    entryPx: 135000,
    positionValue: 10.31,
    unrealizedPnl: 0.895,
    returnOnEquity: 0.08,
    liquidationPx: 262000,
    marginUsed: 11.20,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 40,
  );

  testWidgets('a 1x short: the money closing gives back, not the position '
      'size', (tester) async {
    await _pump(tester, short);
    final texts = _figures(tester);
    expect(texts[0].text, r'$11.20');
    expect(find.textContaining(r'$10.31'), findsNothing);
    // The return on the margin put in (11.20 - 0.895 = 10.305).
    expect(texts[1].text, r'+$0.90 (+8.7%)');
    expect(texts[1].style.color, AppColors.marketUp);
    // 262,000 against the snapshot mark 124,217: 111% away.
    expect(_caption(tester), 'Short 1x · Liq 111% away');
  });

  testWidgets('the live mid moves the P&L and the money, never the margin',
      (tester) async {
    await _pump(tester, short, mid: 130000);
    // (130,000 - 135,000) x -0.000083 = +0.415 on the 10.305 margin.
    expect(_figures(tester)[0].text, r'$10.72');
    expect(_figures(tester)[1].text, r'+$0.42 (+4.0%)');
  });

  testWidgets('a short that is losing at the live mid: down colour, no liq '
      'when the venue gives none', (tester) async {
    await _pump(tester, _position(szi: -0.5, liq: null), mid: 66000);
    expect(_caption(tester), 'Short 5x');
    expect(find.textContaining('Liq'), findsNothing);
    final pnl = _figures(tester)[1];
    expect(pnl.text, startsWith('−'));
    expect(pnl.style.color, AppColors.marketDown);
  });

  testWidgets('near liquidation: one decimal, amber under 10%, red under 5%',
      (tester) async {
    await _pump(tester, _position(liq: 62000), mid: 66000);
    expect(_caption(tester), 'Long 5x · Liq 6.1% away');
    expect(_distanceColor(tester), AppColorsExtension.light().warning);

    await _pump(tester, _position(liq: 63500), mid: 66000);
    expect(_caption(tester), 'Long 5x · Liq 3.8% away');
    expect(_distanceColor(tester), AppColors.marketDown);
  });

  testWidgets('a narrow phone at large text: nothing overflows',
      (tester) async {
    await _pump(tester, _position(), width: 320, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
