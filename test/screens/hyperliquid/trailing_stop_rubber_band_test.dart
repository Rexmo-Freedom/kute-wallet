// The placement's rubber band on the trailing-stop ticket (founder, 14
// October 2026: "also on placing stocks or predictions while it is
// placing"): while the order is placing the CTA is drawn up; placed, it
// snaps (overshoot, a light tap) back to rest, and the result is handed
// on once the snap has played (bounded); refused, it lets go softly with
// no overshoot; under Reduce Motion it never moves and nothing waits.
//
// Driven end to end on the hot path: the approval is the Kute PIN
// (biometrics off), and the venue call is held by the test so the wait
// can be read.

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
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/trailing_stop_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

/// The venue call, held until the test answers it.
class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.answer);
  final Completer<HlOrderResult> answer;
  int placed = 0;

  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, withdrawable: 100);

  @override
  Future<HlOrderResult> placeTrailingStop({
    required HlMarket market,
    required bool isLong,
    required double size,
    required HlTrailingStop trail,
    int leverage = 1,
    bool? isCross,
    bool reduceOnly = false,
    bool changeOpenPosition = false,
    required AuthGrant grant,
  }) {
    placed++;
    return answer.future;
  }
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

RubberBandProgressState _band(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(find.byType(RubberBandProgress));

Future<void> _frames(WidgetTester tester, int n,
    [Duration step = const Duration(milliseconds: 50)]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(step);
  }
}

/// The activation switch sits in the Advanced section's tinted box, so
/// ListTile's debug check ("background color or ink splashes may be
/// invisible") reports on every build of the ticket, here and in a debug
/// app alike. Not this test's subject: that one report is set aside, and
/// anything else still fails the test.
Future<void> _withoutListTileNote(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if ('${details.exception}'
        .contains('ListTile background color or ink splashes')) {
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
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
  });

  tearDown(() {
    SecretStores.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
  });

  /// The embedded ticket (inside the Advanced card), so the CTA stays on
  /// screen after the order is placed and its snap can be read.
  Future<(_Trading, List<HlOrderResult>)> pump(WidgetTester tester,
      {bool reduceMotion = false}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final trading = _Trading(Completer<HlOrderResult>());
    final results = <HlOrderResult>[];
    final container = ProviderContainer(overrides: [
      authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      hyperliquidTradingProvider.overrideWith(() => trading),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
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
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: HlTrailingStopSheet(
                market: _btc,
                size: 0.01,
                isBuy: false,
                reduceOnly: true,
                leverage: 5,
                isCross: false,
                walletId: 'w1',
                ledger: false,
                embedded: true,
                onResult: results.add,
              ),
            ),
          ),
        ),
      ),
    ));
    await _frames(tester, 4);
    return (trading, results);
  }

  /// Taps Place and approves it with the PIN; the order is then placing,
  /// held by the test.
  Future<void> placeAndApprove(WidgetTester tester, _Trading trading) async {
    expect(_band(tester).stretch, 0, reason: 'at rest before the tap');
    await tester.tap(find.byType(PolySlipCta));
    for (var i = 0;
        i < 40 && find.byType(PinGateSheet).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PinGateSheet), findsOneWidget);
    // Let the PIN sheet slide in.
    await _frames(tester, 16);
    for (final d in '111111'.split('')) {
      await tester.tap(find.descendant(
          of: find.byType(PinGateSheet), matching: find.text(d)));
      await tester.pump();
    }
    for (var i = 0; i < 40 && trading.placed == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(trading.placed, 1);
    // The PIN sheet slides away while the order places.
    await _frames(tester, 20);
    expect(find.byType(PinGateSheet), findsNothing);
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).isBusy, isTrue);
  }

  // The whoosh and the snap, through the haptics bridge's test seam.
  int snapTaps() =>
      ContinuousHaptics.debugLog!.where((c) => c.method == 'snap').length;

  testWidgets(
      'placing pulls the CTA up; placed, it snaps back past rest with a '
      'light tap, then hands the result on', (tester) async {
    await _withoutListTileNote(() async {
      final (trading, results) = await pump(tester);
      await placeAndApprove(tester, trading);
      // Approved and sent: at least the sent step's tension, built on by
      // time, never past full tension.
      expect(_band(tester).stretch,
          greaterThan(rubberBandStretchFor(0.65) - 0.005));
      expect(_band(tester).stretch,
          lessThanOrEqualTo(RubberBandProgress.defaultMaxStretch +
              RubberBandProgress.breath));
      expect(_band(tester).ticking, isTrue);
      final tapsBefore = snapTaps();

      trading.answer
          .complete(const HlOrderResult(kind: HlOrderResultKind.resting));
      var min = double.infinity;
      // The snap plays first: the result waits, the CTA still holds it.
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final s = _band(tester).stretch;
        if (s < min) min = s;
        expect(results, isEmpty, reason: 'not before the snap has played');
      }
      expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).isBusy,
          isTrue);
      expect(min, lessThan(0), reason: 'the snap overshoots past rest');
      expect(snapTaps() - tapsBefore, 1);
      // Bounded: handed on once the snap's moment is over.
      await tester.pump(RubberBand.snapSettle);
      await tester.pump();
      expect(results, hasLength(1));
      await _frames(tester, 40);
      expect(_band(tester).stretch, 0);
      expect(_band(tester).ticking, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('refused: a soft release, never past rest, then the error',
      (tester) async {
    await _withoutListTileNote(() async {
      final (trading, results) = await pump(tester);
      await placeAndApprove(tester, trading);
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
      expect(results, isEmpty);
      expect(
          tester.widget<PolySlipCta>(find.byType(PolySlipCta)).isBusy, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Reduce Motion: the CTA never moves while placing',
      (tester) async {
    await _withoutListTileNote(() async {
      final (trading, results) = await pump(tester, reduceMotion: true);
      await placeAndApprove(tester, trading);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_band(tester).stretch, 0);
      }
      expect(_band(tester).ticking, isFalse);
      trading.answer
          .complete(const HlOrderResult(kind: HlOrderResultKind.resting));
      // Nothing waits for a snap that is not drawn.
      await tester.pump();
      await tester.pump();
      expect(results, hasLength(1));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_band(tester).stretch, 0);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
