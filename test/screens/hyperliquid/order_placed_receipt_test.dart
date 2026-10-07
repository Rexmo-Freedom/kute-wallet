import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/theme/app_theme.dart';

HlPerpPosition _held(double szi) => HlPerpPosition(
      coin: 'BTC',
      szi: szi,
      entryPx: 60000,
      positionValue: szi.abs() * 60000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: szi.abs() * 60000,
      leverageType: 'isolated',
      leverageValue: 1,
      maxLeverage: 40,
    );

/// The plan the slip sends against [szi] held, then sized on the fill the
/// way the slip's receipt is.
HlPositionPlan? _filled(double szi,
    {required bool orderIsLong,
    required double orderSize,
    required double filled}) {
  final sent = hlPositionPlan(
    position: _held(szi),
    orderIsLong: orderIsLong,
    orderSize: orderSize,
    szDecimals: 5,
  );
  return hlFilledPlan(sent, sizeFilled: filled, szDecimals: 5);
}

HlFill _fill(double sz, {double closedPnl = 0, double fee = 0}) => HlFill(
      coin: 'BTC',
      px: 60000,
      sz: sz,
      side: 'A',
      time: 0,
      closedPnl: closedPnl,
      fee: fee,
      feeToken: 'USDC',
      oid: 7,
      hash: '',
      dir: 'Close Long',
      cloid: null,
    );

void main() {
  final rootKey = GlobalKey<NavigatorState>();

  setUp(() => KuteConfirmation.debugFeedbackOverride = () async {});
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  Future<void> pumpReceipt(
    WidgetTester tester, {
    bool isLong = false,
    bool isSpot = false,
    double sizeFilled = 0.05,
    HlPositionPlan? plan,
    double? realizedPnl,
  }) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        navigatorKey: rootKey,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('host')),
      ),
    ));
    pushHlOrderPlacedOverlay(
      navigator: rootKey.currentState!,
      coin: 'BTC',
      isLong: isLong,
      leverage: 1,
      isSpot: isSpot,
      sizeFilled: sizeFilled,
      avgPx: 60000,
      notionalUsd: sizeFilled * 60000,
      positionPlan: plan,
      realizedPnl: realizedPnl,
    );
    await tester.pumpAndSettle();
  }

  group('filled receipt against a held position', () {
    testWidgets('an open keeps the opened-order chip', (tester) async {
      await pumpReceipt(tester);
      expect(find.text('Short · 1×'), findsOneWidget);
      expect(find.text('Position size'), findsOneWidget);
      expect(find.text('Realized P&L'), findsNothing);
    });

    testWidgets('a reduce says what is left of the long and what it realised',
        (tester) async {
      final plan =
          _filled(0.1, orderIsLong: false, orderSize: 0.05, filled: 0.05);
      expect(plan!.effect, HlPositionEffect.reduce);
      await pumpReceipt(tester, plan: plan, realizedPnl: 12.5);
      expect(find.text('Reduced long · 0.05 BTC'), findsOneWidget);
      expect(find.text('Short · 1×'), findsNothing);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Realized P&L'), findsOneWidget);
      expect(find.text(r'+$12.50'), findsOneWidget);
    });

    testWidgets('a close says Closed long with a realised loss',
        (tester) async {
      final plan = _filled(0.1, orderIsLong: false, orderSize: 0.1, filled: 0.1);
      expect(plan!.effect, HlPositionEffect.close);
      await pumpReceipt(tester, sizeFilled: 0.1, plan: plan, realizedPnl: -3.2);
      expect(find.text('Closed long'), findsOneWidget);
      expect(find.text('Realized P&L'), findsOneWidget);
      expect(find.text(r'−$3.20'), findsOneWidget);
    });

    testWidgets('a close of a short says Closed short', (tester) async {
      final plan =
          _filled(-0.1, orderIsLong: true, orderSize: 0.1, filled: 0.1);
      await pumpReceipt(tester, isLong: true, sizeFilled: 0.1, plan: plan);
      expect(find.text('Closed short'), findsOneWidget);
      expect(find.text('Long · 1×'), findsNothing);
      // No fills in hand: no realised line rather than a guess.
      expect(find.text('Realized P&L'), findsNothing);
    });

    testWidgets('a flip names the new side and its size', (tester) async {
      final plan =
          _filled(0.1, orderIsLong: false, orderSize: 0.15, filled: 0.15);
      expect(plan!.effect, HlPositionEffect.flip);
      await pumpReceipt(tester, sizeFilled: 0.15, plan: plan, realizedPnl: 4);
      expect(find.text('Flipped to short · 0.05 BTC'), findsOneWidget);
      expect(find.text(r'+$4.00'), findsOneWidget);
    });

    testWidgets('an add says Added to long, without a realised line',
        (tester) async {
      final plan = _filled(0.1, orderIsLong: true, orderSize: 0.05, filled: 0.05);
      expect(plan!.effect, HlPositionEffect.add);
      await pumpReceipt(tester, isLong: true, plan: plan, realizedPnl: 1);
      expect(find.text('Added to long'), findsOneWidget);
      expect(find.text('Position size'), findsOneWidget);
      expect(find.text('Realized P&L'), findsNothing);
    });

    testWidgets('spot keeps Bought / Sold', (tester) async {
      final plan =
          _filled(0.1, orderIsLong: false, orderSize: 0.05, filled: 0.05);
      await pumpReceipt(tester, isSpot: true, plan: plan);
      expect(find.text('Reduced long · 0.05 BTC'), findsNothing);
    });

    testWidgets('the chip is localized', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('de'));
      final plan = _filled(0.1, orderIsLong: false, orderSize: 0.1, filled: 0.1);
      expect(hlFillEffectLabel(l10n, plan, 'BTC'), 'Long geschlossen');
    });
  });

  group('the receipt follows what filled, not what was asked', () {
    test('a close filled short of the position is a reduce', () {
      final plan =
          _filled(0.1, orderIsLong: false, orderSize: 0.1, filled: 0.06);
      expect(plan!.effect, HlPositionEffect.reduce);
      expect(plan.remaining, closeTo(0.04, 1e-12));
    });

    test('a flip filled within the position is a close', () {
      final plan =
          _filled(-0.1, orderIsLong: true, orderSize: 0.15, filled: 0.1);
      expect(plan!.effect, HlPositionEffect.close);
      expect(plan.heldSide, 'short');
    });

    test('an open has no effect to say', () {
      final sent = hlPositionPlan(
          position: null, orderIsLong: true, orderSize: 0.1, szDecimals: 5);
      expect(hlFilledPlan(sent, sizeFilled: 0.1, szDecimals: 5), isNull);
      expect(hlFilledPlan(null, sizeFilled: 0.1, szDecimals: 5), isNull);
    });
  });

  group('hlRealizedFromFills', () {
    test('closedPnl net of fees over the whole fill', () {
      final pnl = hlRealizedFromFills([
        _fill(0.03, closedPnl: 9, fee: 0.5),
        _fill(0.02, closedPnl: 6, fee: 0.25),
      ], 0.05);
      expect(pnl, closeTo(14.25, 1e-9));
    });

    test('null while the fills do not cover the filled size', () {
      expect(hlRealizedFromFills([_fill(0.03, closedPnl: 9)], 0.05), isNull);
      expect(hlRealizedFromFills(const [], 0.05), isNull);
    });
  });
}
