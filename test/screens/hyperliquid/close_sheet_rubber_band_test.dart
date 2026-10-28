// The placement's rubber band on the Investing close ticket (founder, 14
// October 2026): while the close is placing the CTA is drawn up; closed,
// it lets go with the spring snap and a light tap, and the confirmation
// comes once the snap has played (a bounded wait); refused, it releases
// softly with no overshoot and the reason shows; under Reduce Motion it
// never moves and nothing waits.
//
// Driven end to end on the hot path: the approval is the Kute PIN
// (biometrics off), and the exchange call is held by the test.

import 'dart:async';

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
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

/// The exchange call, held until the test answers it.
class _Exchange {
  final answer = Completer<HlOrderResult>();
  int closes = 0;
}

/// A fresh notifier whenever the provider builds one (it may be rebuilt),
/// all answering through the one [_Exchange].
class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.exchange);
  final _Exchange exchange;

  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, withdrawable: 100);

  @override
  Future<HlOrderResult> closePosition({
    required String coin,
    double fraction = 1.0,
    double slippagePct = 1.0,
    required AuthGrant grant,
  }) {
    exchange.closes++;
    return exchange.answer.future;
  }
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
  @override
  bool allows(String id) => true;
  @override
  RuntimeCapabilities? get snapshot => null;
  @override
  Future<void> ensureAllowed(String id,
      {Duration maxAge = Duration.zero}) async {}
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
);

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

final _cta = find.byType(PolySlipCta);

RubberBandProgressState _band(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(
        find.descendant(of: _cta, matching: find.byType(RubberBandProgress)));

Future<void> _frames(WidgetTester tester, int n,
    [Duration step = const Duration(milliseconds: 50)]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(step);
  }
}

void main() {
  late FakeKeychain keychain;
  late List<MethodCall> platform;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    RuntimeCapabilitiesService.debugInstance = _Allowed();
    // The confirmation's own success feedback is not this test's subject.
    KuteConfirmation.debugFeedbackOverride = () async {};
  });

  tearDown(() {
    SecretStores.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
    KuteConfirmation.debugFeedbackOverride = null;
  });

  Future<_Exchange> pump(WidgetTester tester,
      {bool reduceMotion = false}) async {
    tester.view.physicalSize = const Size(430, 932) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    platform = [];
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = [];
    addTearDown(() => ContinuousHaptics.debugLog = null);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platform.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final trading = _Exchange();
    final container = ProviderContainer(overrides: [
      authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      hyperliquidTradingProvider.overrideWith(() => _Trading(trading)),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_position]),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      aiEnabledProvider.overrideWith((_) async => false),
    ]);
    addTearDown(container.dispose);
    container.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: const Scaffold(
            body: HlClosePositionSheet(position: _position, market: _btc),
          ),
        ),
      ),
    ));
    await _frames(tester, 6);
    return trading;
  }

  /// Taps Close and approves it with the PIN; the close is then placing,
  /// held by the test.
  Future<void> closeAndApprove(WidgetTester tester, _Exchange trading) async {
    expect(_band(tester).stretch, 0, reason: 'at rest before the tap');
    await tester.tap(_cta);
    for (var i = 0;
        i < 40 && find.byType(PinGateSheet).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PinGateSheet), findsOneWidget);
    await _frames(tester, 16);
    for (final d in '111111'.split('')) {
      await tester.tap(find.descendant(
          of: find.byType(PinGateSheet), matching: find.text(d)));
      await tester.pump();
    }
    for (var i = 0; i < 40 && trading.closes == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(trading.closes, 1);
    await _frames(tester, 20);
    expect(find.byType(PinGateSheet), findsNothing);
    expect(tester.widget<PolySlipCta>(_cta).isBusy, isTrue);
  }

  // The whoosh and the snap, through the haptics bridge's test seam.
  int snapTaps() =>
      ContinuousHaptics.debugLog!.where((c) => c.method == 'snap').length;

  testWidgets(
      'closing pulls the CTA up; closed, it snaps back with a light tap, '
      'then the confirmation shows', (tester) async {
    final trading = await pump(tester);
    await closeAndApprove(tester, trading);
    // Approved and sent: at least the sent step's tension, built on by
    // time, never past full tension.
    expect(_band(tester).stretch,
        greaterThan(rubberBandStretchFor(0.65) - 0.005));
    expect(
        _band(tester).stretch,
        lessThanOrEqualTo(
            RubberBandProgress.defaultMaxStretch + RubberBandProgress.breath));
    expect(_band(tester).ticking, isTrue);
    final tapsBefore = snapTaps();

    trading.answer.complete(const HlOrderResult(
        kind: HlOrderResultKind.filled, filledSz: 0.5, avgPx: 66000));
    await tester.pump();
    // The CTA snaps while the ticket still holds the close: no
    // confirmation yet.
    final cta = tester.widget<PolySlipCta>(_cta);
    expect(cta.isBusy, isTrue);
    expect(cta.bandOutcome, RubberBandOutcome.success);
    var min = double.infinity;
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
      expect(find.byType(KuteConfirmation), findsNothing,
          reason: 'not before the snap has played');
    }
    expect(min, lessThan(0), reason: 'the snap overshoots past rest');
    expect(snapTaps() - tapsBefore, 1);
    // Bounded: the confirmation follows once the snap's moment is over.
    await tester.pump(RubberBand.snapSettle);
    await tester.pump();
    expect(find.byType(KuteConfirmation), findsOneWidget);
    // A filled close is a success: the size closed as the hero.
    final sheet = tester.widget<KuteConfirmation>(find.byType(KuteConfirmation));
    expect(sheet.resolvedTone, KuteConfirmationTone.success);
    expect(sheet.amount, contains('0.5'));
    await _frames(tester, 40);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refused: a soft release, never past rest, then the reason',
      (tester) async {
    final trading = await pump(tester);
    await closeAndApprove(tester, trading);
    expect(_band(tester).stretch, greaterThan(0));
    final tapsBefore = snapTaps();

    trading.answer.completeError(StateError('Order rejected'));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_band(tester).stretch, greaterThanOrEqualTo(-1e-9),
          reason: 'never past rest');
    }
    await _frames(tester, 20);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(snapTaps(), tapsBefore, reason: 'no snap tap on a refusal');
    final cta = tester.widget<PolySlipCta>(_cta);
    expect(cta.isBusy, isFalse);
    expect(cta.bandOutcome, isNull);
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: the CTA never moves while closing',
      (tester) async {
    final trading = await pump(tester, reduceMotion: true);
    await closeAndApprove(tester, trading);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_band(tester).stretch, 0);
    }
    expect(_band(tester).ticking, isFalse);
    trading.answer.complete(const HlOrderResult(
        kind: HlOrderResultKind.filled, filledSz: 0.5, avgPx: 66000));
    // Nothing waits for a snap that is not drawn.
    await tester.pump();
    await tester.pump();
    expect(find.byType(KuteConfirmation), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_band(tester).stretch, 0);
    }
    expect(tester.takeException(), isNull);
  });
}
