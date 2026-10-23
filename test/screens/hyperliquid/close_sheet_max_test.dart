// The Investing close sheet carries the buy slips' one small Max beside
// the figure, typed in dollars on its own keypad. The sheet opens on the
// whole position; after an edit Max fills the whole position again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
}

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

const _position = HlPerpPosition(
  coin: 'BTC',
  szi: 0.5,
  entryPx: 64000,
  positionValue: 32000,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: 58000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
  fundingSinceOpen: 1.25,
);

String _typed(WidgetTester tester) =>
    tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_position]),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: HlClosePositionSheet(position: _position, market: _btc),
        ),
      ),
    ),
  ));
}


/// Advanced is the pill on the amount's row, right of Max when Max shows,
/// reading "Advanced" with its sliders; the header has none.
void _expectAdvancedBesideMax(WidgetTester tester) {
  final button = find.byKey(const ValueKey('slip-advanced-button'));
  expect(find.descendant(of: find.byType(BigAmountDisplay), matching: button),
      findsOneWidget);
  expect(find.descendant(of: button, matching: find.text('Advanced')),
      findsOneWidget);
  expect(find.descendant(of: button, matching: find.byIcon(Icons.tune_rounded)),
      findsOneWidget);
  final max = find.byType(AmountMaxChip);
  if (max.evaluate().isNotEmpty) {
    final maxRect = tester.getRect(max);
    final pillRect = tester.getRect(button);
    expect(pillRect.left, greaterThan(maxRect.right));
    expect((pillRect.center.dy - maxRect.center.dy).abs(), lessThan(1));
    expect(pillRect.height, closeTo(maxRect.height, 1));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Advanced is a pill right of Max; a limit close says so in a chip '
      'under the amount and a dot on the pill', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('slip-advanced-button'));
    final chip = find.byKey(const ValueKey('slip-advanced-chip'));
    final dot = find.byKey(const ValueKey('slip-advanced-dot'));
    expect(button, findsOneWidget);
    // On the amount's row, right of Max: not in the header.
    _expectAdvancedBesideMax(tester);
    expect(chip, findsNothing);
    expect(dot, findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KuteBackButton));
    await tester.pumpAndSettle();
    expect(find.descendant(of: chip, matching: find.text('Limit')),
        findsOneWidget);
    expect(dot, findsOneWidget);
    // The chip opens Advanced too.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byType(KuteBackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one small Max beside the figure closes the whole position',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // The buy slips' header: the coin, the title and the round close X;
    // no leverage chip (the pill under it names the side and size).
    expect(find.byType(PolySlipHeader), findsOneWidget);
    expect(find.text('Close BTC'), findsOneWidget);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(find.text('5x'), findsNothing);
    expect(find.text('Long · 0.5 BTC'), findsOneWidget);

    final hero = find.byType(BigAmountDisplay);
    final max = find.descendant(of: hero, matching: find.byType(AmountMaxChip));
    expect(max, findsOneWidget);
    // Opens on the whole position, in dollars: 0.5 BTC at 66,000.
    final whole = _typed(tester);
    expect(whole, '33000');

    final pad = find.byType(AmountKeypad);
    await tester.tap(find.descendant(
        of: pad, matching: find.byIcon(Icons.backspace_rounded)));
    await tester.pump();

    // 3300 dollars of 33000 is a tenth of the position.
    expect(_typed(tester), '3300');
    expect(find.text('Close 10% now'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pump();
    expect(_typed(tester), whole);
    expect(find.text('Close 100% now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
