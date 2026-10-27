// A bet funded from more than Dollars lists every leg's fee in the one
// fee row's breakdown and adds them to its total (founder, 27 October
// 2026: "Sometimes the fees have multiple steps ... we must show the fee
// correctly").
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/screens/shared/slip_stat_tiles.dart';
import 'package:kute/services/one_balance/funding_fees.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _CurrencyNotifier() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

const _terms = PolymarketFeeTerms(
    rate: 0.03, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);

Widget _host(Widget child, {ThemeData? theme, GlobalKey? boundary}) {
  final app = ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            balancePrivacy: 0,
            biometricsEnabled: false,
            bitcoinElectrumNode: 'localhost',
            nodeType: 'Blockstream',
            reviewDone: false,
          ))),
      currencyProvider.overrideWith((ref) => _CurrencyNotifier()),
      polymarketFeeTermsProvider.overrideWith((ref, _) async => _terms),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: (theme ?? buildLightTheme())
            .copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
              child: Padding(padding: const EdgeInsets.all(20), child: child)),
        ),
      ),
    ),
  );
  return boundary == null ? app : RepaintBoundary(key: boundary, child: app);
}

/// The slip's two legs as it builds them: $4.00 from Bitcoin at a 2%
/// spread and the rest of the $10.30 move from Investing.
List<MoneyFeeLeg> _legs(AppLocalizations l10n) {
  final fees = estimateOrderFundingFees(
    fundUsd: 10.30,
    arrivingUsd: 10.10,
    dollarsUsd: 0,
    venue: OneBalanceVenue.predictions,
    bitcoinMaxUsd: 4.00,
    bitcoinSpread: 0.02,
    otherVenues: [
      (
        venue: OneBalanceVenue.investing,
        availableUsd: 20,
        eta: const Duration(minutes: 5),
        minimumUsd: 1.0,
      )
    ],
  );
  return [
    for (final leg in fees.legs)
      (label: fundingLegFeeLabel(l10n, leg.source), usd: leg.feeUsd),
  ];
}

Widget _slipFee(List<MoneyFeeLeg> legs) => SlipFigures(
      left: const SlipFigure(label: 'Shares', value: '40.00'),
      right: MoneyFeeFigure(
        child: PolymarketFeeSummary(
          tokenId: 'yes',
          shares: 40,
          price: 0.5,
          bitcoinFirst: false,
          showNote: false,
          moveFeeUsd: legs.fold<double>(0, (s, l) => s + l.usd),
          moveLegs: legs,
        ),
      ),
    );

void main() {
  setUp(() => Intl.defaultLocale = 'en_US');
  tearDown(() => Intl.defaultLocale = null);

  testWidgets('a two-leg bet lists each leg and adds them to the total',
      (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final legs = _legs(l10n);
    expect(
        legs.map((l) => l.label), ['Move from Bitcoin', 'Move from Investing']);
    await tester.pumpWidget(_host(_slipFee(legs)));
    await tester.pumpAndSettle();
    // $0.30 Polymarket + $0.04 Kute + $0.09 Bitcoin + $0.44 Investing.
    expect(find.text(r'$0.87'), findsOneWidget);
    await tester.tap(find.text(r'$0.87'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
    expect(sheet, findsOneWidget);
    for (final (label, amount) in [
      ('Polymarket fee', r'$0.30'),
      ('Kute fee', r'$0.04'),
      ('Move from Bitcoin', r'$0.09'),
      ('Move from Investing', r'$0.44'),
    ]) {
      expect(find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
          reason: label);
      expect(find.descendant(of: sheet, matching: find.text(amount)),
          findsOneWidget,
          reason: amount);
    }
    // One Dollars-only move keeps its single "Move fee" line.
    expect(find.descendant(of: sheet, matching: find.text('Move fee')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Investing order lists its legs the same way', (tester) async {
    await tester.pumpWidget(_host(const HyperliquidFeeSummary(
      notional: 20,
      spot: false,
      buy: true,
      builder: false,
      useHotAccount: false,
      moveFeeUsd: 0.60,
      moveLegs: [
        (label: 'Move from Dollars', usd: 0.10),
        (label: 'Move from Predictions', usd: 0.50),
      ],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$0.60'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Move from Dollars')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Move from Predictions')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Move fee')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A look by eye (written only when asked: BET_FEES_RENDER=<dir>).
  final renderDir = Platform.environment['BET_FEES_RENDER'];
  testWidgets('render: two-leg fee sheet, light, 390 wide',
      skip: renderDir == null, (tester) async {
    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final base = buildLightTheme();
    final theme =
        base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
    final key = GlobalKey();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Inter'),
        child: _host(_slipFee(_legs(l10n)), theme: theme, boundary: key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$0.87'));
    await tester.pumpAndSettle();
    Directory(renderDir!).createSync(recursive: true);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$renderDir/light-two-leg-fee-sheet.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
