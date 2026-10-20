// The Close sheet on the shortest phone (375x667), at the app's own text
// size and a larger one: nothing slides under the pinned keypad and
// nothing is cut, typed or after a close that failed (its notice shown).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../services/support/fake_secret_store.dart';

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

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
  @override
  Future<HlOrderResult> closePosition({
    required String coin,
    double fraction = 1.0,
    double slippagePct = 1.0,
    required AuthGrant grant,
  }) async =>
      throw Exception('Order could not immediately match against any '
          'resting orders.');
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
  @override
  bool allows(String id) => true;
}

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);
  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
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
  unrealizedPnl: 1000,
  returnOnEquity: 0.15,
  liquidationPx: 58000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
  fundingSinceOpen: 1.25,
);

late FakeKeychain _keychain;

Future<void> _pump(WidgetTester tester, {double scale = 1.0}) async {
  await tester.pumpWidget(const SizedBox());
  // An iPhone SE / 8: the shortest phone the app runs on.
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.view.padding = const FakeViewPadding(top: 40);
  tester.view.viewPadding = const FakeViewPadding(top: 40);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            wallets: [WalletConfig(id: 'w1', name: 'Spending')],
            activeWalletId: 'w1',
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: true,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      authModelProvider.overrideWith((ref) => _QuickAuth(_keychain)),
      sessionAuthProvider.overrideWith((ref) =>
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_position]),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Builder(builder: (context) {
          final c = context.colors;
          return Scaffold(backgroundColor: c.background);
        }),
      ),
    ),
  ));
  await tester.pump();
  final ctx = tester.element(find.byType(Scaffold));
  // HlClosePositionSheet.show's own flags.
  showModalBottomSheet(
    context: ctx,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    routeSettings: const RouteSettings(name: HlClosePositionSheet.routeName),
    builder: (_) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: const HlClosePositionSheet(position: _position, market: _btc),
    ),
  );
  await _frames(tester);
  expect(find.byType(HlClosePositionSheet), findsOneWidget);
  expect(
      tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText,
      '33000');
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps Close, approves with the PIN, and lets the fake venue refuse.
Future<void> _fail(WidgetTester tester) async {
  await tester.tap(find.byType(PolySlipCta));
  await _frames(tester, 8);
  expect(find.byType(PinGateSheet), findsOneWidget);
  for (final d in '111111'.split('')) {
    await tester.tap(
        find.descendant(of: find.byType(PinGateSheet), matching: find.text(d)));
    await tester.pump();
  }
  await _frames(tester, 30);
  expect(find.byType(PinGateSheet), findsNothing);
  expect(find.byType(HlTradeErrorNotice), findsOneWidget);
}

/// The rect a widget paints in, in global coordinates.
Rect _rectOf(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The tile's figure: the largest text in it.
Rect _valueRect(WidgetTester tester, Finder tile) {
  final texts = find
      .descendant(of: tile, matching: find.byType(Text))
      .evaluate()
      .toList()
    ..sort((a, b) => ((b.widget as Text).style?.fontSize ?? 0)
        .compareTo((a.widget as Text).style?.fontSize ?? 0));
  return _rectOf(texts.first);
}

void _expectInside(Rect inner, Rect outer, String what) {
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.5),
      reason: '$what starts above the form');
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.5),
      reason: '$what runs past the bottom of the form');
}

Future<void> _loadFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
    final inter = FontLoader(family);
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  }
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Finder get _sheet => find.byType(HlClosePositionSheet);

Rect _viewport(WidgetTester tester) => tester.getRect(
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first);

void _expectTilesShown(WidgetTester tester) {
  final viewport = _viewport(tester);
  final keypadTop = tester.getRect(find.byType(AmountKeypad)).top;
  for (final key in ['hl-close-proceeds', 'hl-close-pnl']) {
    final tile = find.byKey(ValueKey(key));
    expect(tile, findsOneWidget);
    for (final (what, rect) in [
      (key, tester.getRect(tile)),
      ('$key figure', _valueRect(tester, tile)),
    ]) {
      _expectInside(rect, viewport, what);
      expect(rect.bottom, lessThanOrEqualTo(keypadTop + 0.5),
          reason: '$what is under the keypad');
    }
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    _keychain = FakeKeychain();
    _keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(
        local: _keychain.local, synced: _keychain.synced);
  });
  tearDown(SecretStores.debugReset);

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  for (final scale in [1.0, 1.3]) {
    group('a 375x667 phone at text size $scale', () {
      testWidgets(
          'the whole position typed: both tiles and their figures sit above '
          'the keypad', (tester) async {
        await _pump(tester, scale: scale);
        expect(tester.takeException(), isNull);
        _expectTilesShown(tester);
        await release(tester);
      });

      testWidgets(
          'a close that failed: the notice and both tiles stay above the '
          'pinned keypad, nothing cut', (tester) async {
        await _pump(tester, scale: scale);
        await _fail(tester);
        expect(tester.takeException(), isNull);
        _expectTilesShown(tester);
        final notice = tester.getRect(find.byType(HlTradeErrorNotice));
        _expectInside(notice, _viewport(tester), 'the notice');
        expect(
            notice.bottom,
            lessThanOrEqualTo(
                tester.getRect(find.byType(AmountKeypad)).top + 0.5),
            reason: 'the notice is under the keypad');
        await release(tester);
      });
    });
  }
}
