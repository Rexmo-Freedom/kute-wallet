// How far a position is from liquidation, said one way everywhere:
// "$78,400 · 12% away", one decimal under 10%, whole above; only the
// distance coloured, amber inside the liquidation-risk alert's 10% and
// red inside its 5%. The position screen's row carries "Add margin" only
// for an isolated position the app can move margin on.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/theme/app_theme.dart';

HlPerpPosition _position({String type = 'isolated', double? liq = 300}) =>
    HlPerpPosition(
      coin: 'xyz:TSLA',
      szi: 2,
      entryPx: 350,
      positionValue: 740,
      unrealizedPnl: 40,
      returnOnEquity: 0.2,
      liquidationPx: liq,
      marginUsed: 200,
      leverageType: type,
      leverageValue: 5,
      maxLeverage: 10,
    );

HlMarket _market({
  String wireCoin = 'xyz:TSLA',
  HlMarketKind kind = HlMarketKind.perp,
}) =>
    HlMarket(
      coin: 'TSLA',
      wireCoin: wireCoin,
      assetId: 110001,
      kind: kind,
      szDecimals: 3,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 370,
      midPx: 370,
      prevDayPx: 360,
      dayNtlVlm: 1,
      dex: 'xyz',
      isHip3: true,
    );

Future<void> _pumpRow(WidgetTester tester,
    {required double? liq, required double mark, VoidCallback? onAdd}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => PositionRowsCard(rows: [
            hlLiquidationRow(context,
                liquidation: liq, mark: mark, onAddMargin: onAdd),
          ]),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The colour of the "… away" span of the one rich liquidation text.
Color? _distanceColor(WidgetTester tester) {
  final text = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null));
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

  group('distance', () {
    test('is |mark − liquidation| / mark', () {
      expect(hlLiquidationDistance(mark: 100, liq: 88), closeTo(0.12, 1e-9));
      expect(hlLiquidationDistance(mark: 100, liq: 112), closeTo(0.12, 1e-9));
      expect(hlLiquidationDistance(mark: 100, liq: null), isNull);
      expect(hlLiquidationDistance(mark: 0, liq: 50), isNull);
    });

    test('one decimal under 10%, whole above', () {
      expect(formatHlLiqDistance(0.124), '12%');
      expect(formatHlLiqDistance(0.126), '13%');
      expect(formatHlLiqDistance(0.10), '10%');
      expect(formatHlLiqDistance(0.0742), '7.4%');
      expect(formatHlLiqDistance(0.031), '3.1%');
    });

    test(
        'colour: neutral, amber inside 10%, red inside 5% (the alert '
        'thresholds)', () {
      final c = AppColorsExtension.light();
      expect(kHlLiquidationRiskDistance, 0.10);
      expect(kHlLiquidationRiskUrgent, 0.05);
      expect(hlLiqDistanceColor(0.12, c), isNull);
      expect(hlLiqDistanceColor(0.1001, c), isNull);
      expect(hlLiqDistanceColor(0.10, c), c.warning);
      expect(hlLiqDistanceColor(0.07, c), c.warning);
      expect(hlLiqDistanceColor(0.0501, c), c.warning);
      expect(hlLiqDistanceColor(0.05, c), AppColors.marketDown);
      expect(hlLiqDistanceColor(0.01, c), AppColors.marketDown);
    });

    test('the mark is the live mid, else notional / size', () {
      expect(hlPositionMark(_position(), liveMid: 380), 380);
      expect(hlPositionMark(_position()), 370);
      expect(hlLiquidationPrice(_position()), 300);
      expect(hlLiquidationPrice(_position(liq: null)), isNull);
      expect(hlLiquidationPrice(_position(liq: 0)), isNull);
    });
  });

  group('margin button only on isolated', () {
    test('an isolated perp on its own market', () {
      expect(hlCanAdjustMargin(_position(), _market()), isTrue);
    });
    test('cross, spot, another market or none: no button', () {
      expect(hlCanAdjustMargin(_position(type: 'cross'), _market()), isFalse);
      expect(hlCanAdjustMargin(_position(), _market(kind: HlMarketKind.spot)),
          isFalse);
      expect(
          hlCanAdjustMargin(_position(), _market(wireCoin: 'TSLA')), isFalse);
      expect(hlCanAdjustMargin(_position(), null), isFalse);
    });
  });

  group('the Liquidation row', () {
    testWidgets('safe: price and distance, neutral, with Add margin',
        (tester) async {
      var taps = 0;
      await _pumpRow(tester, liq: 78400, mark: 89100, onAdd: () => taps++);
      expect(find.text('Liquidation'), findsOneWidget);
      expect(find.text(r'$78,400 · 12% away'), findsOneWidget);
      expect(_distanceColor(tester), isNull);
      expect(find.byType(KutePill), findsOneWidget);
      expect(find.text('Add margin'), findsOneWidget);
      await tester.tap(find.text('Add margin'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('near: one decimal, amber under 10%, red under 5%',
        (tester) async {
      await _pumpRow(tester, liq: 92.6, mark: 100, onAdd: () {});
      expect(find.text(r'$92.60 · 7.4% away'), findsOneWidget);
      expect(_distanceColor(tester), AppColorsExtension.light().warning);

      await _pumpRow(tester, liq: 96.9, mark: 100, onAdd: () {});
      expect(find.text(r'$96.90 · 3.1% away'), findsOneWidget);
      expect(_distanceColor(tester), AppColors.marketDown);
    });

    testWidgets(
        'a narrow phone: the button goes under the figure, nothing '
        'overflows', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpRow(tester, liq: 78400, mark: 89100, onAdd: () {});
      expect(tester.takeException(), isNull);
      expect(find.text('Add margin'), findsOneWidget);
      // Right-aligned with the figure.
      expect(tester.getTopRight(find.byType(KutePill)).dx,
          closeTo(tester.getTopRight(find.text(r'$78,400 · 12% away')).dx, 1));
    });

    testWidgets('cross: the same row, no button', (tester) async {
      await _pumpRow(tester, liq: 92.6, mark: 100);
      expect(find.text(r'$92.60 · 7.4% away'), findsOneWidget);
      expect(_distanceColor(tester), AppColorsExtension.light().warning);
      expect(find.byType(KutePill), findsNothing);
      expect(find.text('Add margin'), findsNothing);
    });

    testWidgets('no liquidation price: said in the caption style, no colour',
        (tester) async {
      await _pumpRow(tester, liq: null, mark: 100);
      expect(find.text('No liquidation price'), findsOneWidget);
      expect(find.textContaining('away'), findsNothing);
      expect(find.byType(KutePill), findsNothing);
    });
  });
}
