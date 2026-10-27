// The Sell sheet on the shortest phone (375x667), at the app's own text
// size and a larger one: nothing slides under the pinned keypad and
// nothing is cut, typed or after a sale that failed (its notice shown).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/runtime_policy_fixture.dart';
import '../../services/support/fake_secret_store.dart';

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<void> refresh() async {}
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(isAuthenticated: true, usdcBalance: 5);
  @override
  String? get signingWalletId => 'w1';
  @override
  Future<Map<String, dynamic>> placeOrder({
    required String tokenId,
    required OrderSide side,
    required double size,
    required double price,
    bool negRisk = false,
    PolymarketMarketBuyQuote? marketQuote,
    OrderType orderType = OrderType.fok,
    double? spendUsd,
    String? marketTitle,
    String? marketImage,
    String? marketOutcome,
    String? conditionId,
    String? eventSlug,
    String? endDate,
    String? marketCategory,
    String? source,
    String? entrySource,
    Map<String, Object>? analytics,
    required AuthGrant grant,
    void Function(String step)? onStep,
  }) async =>
      throw Exception('Order rejected.');
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => 2.4;
}

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);
  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

const _position = PolymarketPosition(
  marketId: 'condition',
  marketQuestion: 'Will the Fed cut rates at the December meeting?',
  outcome: 'Yes',
  size: 18.6,
  avgPrice: 0.13,
  currentPrice: 0.15,
  pnl: 0,
  pnlPercent: 0,
  isResolved: false,
  tokenId: 'yes',
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
      polymarketTradingProvider.overrideWith(_Trading.new),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      livePriceProvider.overrideWith(_Prices.new),
      currencyProvider.overrideWith((_) => _Currency()),
      aiEnabledProvider.overrideWith((ref) async => false),
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
  // SellSheet.show's own flags.
  showModalBottomSheet(
    context: ctx,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    routeSettings: const RouteSettings(name: SellSheet.routeName),
    builder: (_) => const SellSheet(position: _position),
  );
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Types "2" on the sheet's own keypad: a partial sale.
Future<void> _type(WidgetTester tester) async {
  final pad = find.byType(AmountKeypad);
  await tester.tap(find.descendant(of: pad, matching: find.text('2')));
  await tester.pump();
  await _frames(tester, 3);
}

/// Taps Sell, approves with the PIN, and lets the fake venue refuse.
Future<void> _fail(WidgetTester tester) async {
  await tester.tap(find.byType(PolySlipCta));
  await _frames(tester, 8);
  expect(find.byType(PinGateSheet), findsOneWidget);
  for (final d in '111111'.split('')) {
    await tester.tap(
        find.descendant(of: find.byType(PinGateSheet), matching: find.text(d)));
    await tester.pump();
  }
  await _frames(tester, 60);
  expect(find.byType(PinGateSheet), findsNothing);
  expect(find.byType(PolySlipNotice), findsOneWidget);
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

Finder get _sheet => find.byType(SellSheet);

Rect _viewport(WidgetTester tester) => tester.getRect(
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first);

double _overflow(WidgetTester tester) => tester
    .state<ScrollableState>(
        find.descendant(of: _sheet, matching: find.byType(Scrollable)).first)
    .position
    .maxScrollExtent;

void _expectTilesShown(WidgetTester tester, {required bool keypadPinned}) {
  final viewport = _viewport(tester);
  final keypadTop = tester.getRect(find.byType(AmountKeypad)).top;
  for (final key in ['poly-sell-proceeds', 'poly-sell-pnl']) {
    final tile = find.byKey(ValueKey(key));
    expect(tile, findsOneWidget);
    for (final (what, rect) in [
      (key, tester.getRect(tile)),
      ('$key figure', _valueRect(tester, tile)),
    ]) {
      _expectInside(rect, viewport, what);
      if (keypadPinned) {
        expect(rect.bottom, lessThanOrEqualTo(keypadTop + 0.5),
            reason: '$what is under the keypad');
      }
    }
  }
}

void main() {
  late RuntimeCapabilitiesService policy;
  setUpAll(_loadFonts);
  setUp(() {
    _keychain = FakeKeychain();
    _keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(
        local: _keychain.local, synced: _keychain.synced);
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
  });
  tearDown(() {
    SecretStores.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    policy.dispose();
  }

  for (final scale in [1.0, 1.3]) {
    group('a 375x667 phone at text size $scale', () {
      testWidgets('typed: both tiles and their figures sit above the keypad',
          (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pump(tester, scale: scale);
        await _type(tester);
        expect(tester.takeException(), isNull);
        _expectTilesShown(tester, keypadPinned: true);
        await release(tester);
      });

      testWidgets(
          'a sale that failed: the notice, the tiles and the keypad all fit, '
          'nothing cut', (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pump(tester, scale: scale);
        await _type(tester);
        await _fail(tester);
        expect(tester.takeException(), isNull);
        // After a message the keypad scrolls with the form; it all fits,
        // so nothing scrolls out of sight.
        expect(_overflow(tester), lessThanOrEqualTo(0.5));
        _expectTilesShown(tester, keypadPinned: false);
        final viewport = _viewport(tester);
        _expectInside(tester.getRect(find.byType(PolySlipNotice)), viewport,
            'the notice');
        _expectInside(
            tester.getRect(find.byType(AmountKeypad)), viewport, 'the keypad');
        await release(tester);
      });
    });
  }
}
