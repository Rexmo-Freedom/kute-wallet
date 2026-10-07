// A slip scrolls on a quiet frame. The screen it was opened from stays on
// stage under it, so that screen draws a tick's end state at once while
// it is covered (no roll, flash or glide running under the slip), and the
// close-position sheet scrolls its form the way the buy slip does: the
// header pinned, one clamping form of its own.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

const _resting = Color(0xFF111111);

final _price = ValueNotifier<double>(85806);

Color? _priceColor(WidgetTester tester) => tester
    .widget<RollingNumberText>(find.byType(RollingNumberText))
    .style
    .color;

Future<void> _openSheet(WidgetTester tester) async {
  showModalBottomSheet<void>(
    context: tester.element(find.byType(HlTickPrice)),
    useRootNavigator: true,
    isScrollControlled: true,
    enableDrag: false,
    builder: (_) => const SizedBox(height: 300, child: Text('slip')),
  );
  await tester.pumpAndSettle();
}

Future<void> _tick(WidgetTester tester, double price) async {
  _price.value = price;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

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

void main() {
  setUpAll(() async {
    // The app's bundled Inter, so the form measures as it does on a phone.
    final inter = FontLoader('Inter');
    for (final face in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(Future.value(ByteData.sublistView(
          File('lib/assets/fonts/Inter-$face.ttf').readAsBytesSync())));
    }
    await inter.load();
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('a screen under a slip', () {
    Future<void> pumpScreen(WidgetTester tester,
        {bool reduceMotion = false}) async {
      _price.value = 85806;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: KuteStillWhenCovered(
          child: Scaffold(
            body: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: _price,
                builder: (_, price, __) => HlTickPrice(
                  price: price,
                  text: '\$${price.toStringAsFixed(0)}',
                  style: const TextStyle(color: _resting, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('flashes and rolls a tick while it is on top',
        (tester) async {
      await pumpScreen(tester);
      await _tick(tester, 85700);
      expect(_priceColor(tester), AppColors.marketDown);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(_priceColor(tester), _resting);
    });

    testWidgets('draws a tick at once, and nothing keeps running, while a '
        'slip covers it', (tester) async {
      await pumpScreen(tester);
      await _openSheet(tester);

      await _tick(tester, 85700);
      // The new price, in its resting colour, in the one frame the tick
      // takes: no roll, no flash left to draw under the slip.
      expect(find.text('7'), findsWidgets);
      expect(_priceColor(tester), _resting);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // On top again, the screen moves as before.
      Navigator.of(tester.element(find.text('slip'))).pop();
      await tester.pumpAndSettle();
      await _tick(tester, 85900);
      expect(_priceColor(tester), AppColors.marketUp);
      await tester.pumpAndSettle();
    });

    testWidgets('Reduce Motion keeps the screen still on top too',
        (tester) async {
      await pumpScreen(tester, reduceMotion: true);
      await _tick(tester, 85700);
      expect(_priceColor(tester), _resting);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('the close sheet scrolls its form under a pinned header, the '
      'way the buy slip does', (tester) async {
    // A small phone with a large text size, where the form (in the app's
    // own font) is taller than the room it has. At the default size it
    // fits on a phone and does not scroll at all.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 20, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    enableDrag: false,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const HlClosePositionSheet(
                        position: _position, market: _btc),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = find.byType(HlClosePositionSheet);
    final form = find.descendant(
        of: sheet, matching: find.byType(SingleChildScrollView));
    expect(form, findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(form);
    expect(scroll.physics, isA<ClampingScrollPhysics>());
    expect(scroll.primary, isFalse);
    final position = tester
        .state<ScrollableState>(
            find.descendant(of: form, matching: find.byType(Scrollable)))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    final title = find.text('Close BTC');
    final amount = find.byType(BigAmountDisplay);
    final titleTop = tester.getTopLeft(title).dy;
    final amountTop = tester.getTopLeft(amount).dy;
    await tester.drag(form, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    // The form moved; the header did not.
    expect(tester.getTopLeft(amount).dy, lessThan(amountTop));
    expect(tester.getTopLeft(title).dy, titleTop);
  });
}
