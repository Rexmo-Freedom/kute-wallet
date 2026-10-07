// Max from Bitcoin must never flash "Insufficient balance".
//
// João's report: tapping Max on a Bitcoin source (buying Dollars, adding
// to Investing or Predictions) showed "Insufficient balance" for a
// fraction of a second. Max writes the whole spendable balance, and the
// move then spends it: once the sats left, the live balance dropped under
// the amount on screen while the sheet was still up with its spinner, and
// the sheet judged the amount it was already sending against what was
// left of it. A second way in: Max taken on a held price wrote the whole
// balance at that price, and a fresh price a little lower left an amount
// the balance no longer covered.
//
// These pump the real sheet frame by frame, and keep the real error for
// an amount the source cannot cover and for a move that stopped.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _balanceSats = 100000; // $100.00 at the sample price.
const _insufficient = 'Insufficient balance';

/// The Orchestra price sample for 100,000 sats at [usdPerBtc], in the
/// destination asset's own base units, answered after [delay].
MockClient _orchestra(
        {double usdPerBtc = _usdPerBtc, Duration delay = Duration.zero}) =>
    MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      await Future<void>.delayed(delay);
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final out = doubleToOrchestraAmount(_balanceSats / 1e8 * usdPerBtc, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

/// The app-wide price, without the Hive box behind the real notifier.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(_usdPerBtc.round())}));

  @override
  Future<void> updateRates() async {}
}

/// The Predictions account, awake, with its deposit wallet known.
class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa', proxyWalletAddress: '0xproxy');
}

/// The native Investing route, open.
class _Hypercore extends SparkHypercoreFundingService {
  _Hypercore(super.read);

  @override
  Future<void> ensureAvailable({required bool deposit}) async {}
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

/// Opens the sheet on [side] with [_balanceSats] in spending Bitcoin.
/// The spending SDK never answers, so a move that is started parks in
/// flight with the sheet's own processing state up: nothing can leave,
/// and the test decides when the balance it is spending drops.
///
/// [sdk] stands in for the spending SDK; left alone it never answers.
Future<ProviderContainer> _open(WidgetTester tester, MoveLockedSide side,
    {MockClient Function() orchestra = _orchestra,
    Completer<BreezSdkSpark>? sdk}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency()),
    polymarketTradingProvider.overrideWith(_Trading.new),
    polymarketBalanceProvider.overrideWith((_) => 0),
    sparkHypercoreFundingServiceProvider
        .overrideWith((ref) => _Hypercore(ref.read)),
    sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
            .watch(walletBalanceCacheProvider)['spending']
            ?.sparkBitcoinbalance ??
        0)),
    breezSDKProvider
        .overrideWith((_) => (sdk ?? Completer<BreezSdkSpark>()).future),
  ]);
  _setBalance(container, _balanceSats);
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DepositSheet(lockedSide: side),
        ),
      ),
    )),
    orchestra,
  );
  // The price sample lands.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

void _setBalance(ProviderContainer container, int sats) =>
    container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
        WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: sats));

/// Every frame for [duration], one at a time, noting whether the
/// insufficient-funds message was on screen in any of them.
Future<bool> _sawInsufficient(WidgetTester tester,
    {Duration duration = const Duration(seconds: 2)}) async {
  var saw = find.text(_insufficient).evaluate().isNotEmpty;
  const frame = Duration(milliseconds: 16);
  for (var t = Duration.zero; t < duration; t += frame) {
    await tester.pump(frame);
    saw = saw || find.text(_insufficient).evaluate().isNotEmpty;
  }
  return saw;
}

/// Unmounts the sheet and lets every refresh timer it started run out,
/// so nothing is left pending when the test ends.
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

/// The sheet's one action button ("Buy \$100", "Add \$100").
Finder get _cta => find.byType(AppButton).last;

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  // Door, and the verb its button states.
  const doors = {
    'Dollars': (MoveLockedSide.depositToUsd, 'Buy'),
    'Investing': (MoveLockedSide.depositToHyperliquid, 'Add'),
    'Predictions': (MoveLockedSide.depositToPredictions, 'Add'),
  };

  for (final MapEntry(key: name, value: (side, verb)) in doors.entries) {
    testWidgets('Bitcoin → $name: Max never shows insufficient funds',
        (tester) async {
      final container = await _open(tester, side);
      expect(find.text(_insufficient), findsNothing);

      await tester.tap(find.text('Max'));
      expect(await _sawInsufficient(tester), isFalse);
      // Max wrote the whole balance, at the sample price.
      expect(find.text('$verb \$100'), findsOneWidget);
      await _close(tester, container);
    });

    testWidgets(
        'Bitcoin → $name: a Max move in flight is not re-judged against '
        'the balance it is spending', (tester) async {
      final container = await _open(tester, side);
      await tester.tap(find.text('Max'));
      await tester.pump();
      await tester.tap(_cta);
      await tester.pump();
      expect(tester.widget<AppButton>(_cta).isLoading, isTrue,
          reason: 'the move is in flight');
      // The sats leave: the live balance drops under the amount on
      // screen while the sheet is still up with its spinner.
      _setBalance(container, 0);
      expect(await _sawInsufficient(tester), isFalse);
      expect(tester.widget<AppButton>(_cta).isLoading, isTrue);
      await _close(tester, container);
    });

    testWidgets(
        'Bitcoin → $name: the hold ends with the move; a failed move is '
        'judged against what is left', (tester) async {
      final sdk = Completer<BreezSdkSpark>();
      final container = await _open(tester, side, sdk: sdk);
      await tester.tap(find.text('Max'));
      await tester.pump();
      await tester.tap(_cta);
      await tester.pump();
      _setBalance(container, 0);
      expect(await _sawInsufficient(tester), isFalse);
      // The move stops with the balance gone: the real state shows.
      sdk.completeError(StateError('The spending wallet is disconnected.'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
      expect(find.text(_insufficient), findsWidgets);
      await _close(tester, container);
    });

    testWidgets(
        'Bitcoin → $name: Max taken on a held price follows the fresh one',
        (tester) async {
      // A first open leaves this route's price held for the next one.
      await _close(tester, await _open(tester, side));
      // The fresh sample lands two seconds in, ten percent lower.
      final container = await _open(tester, side,
          orchestra: () => _orchestra(
              usdPerBtc: _usdPerBtc * 0.9, delay: const Duration(seconds: 2)));
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(find.text('$verb \$100'), findsOneWidget);
      expect(
          await _sawInsufficient(tester, duration: const Duration(seconds: 3)),
          isFalse);
      // Still the whole balance, now at the fresh price.
      expect(find.text('$verb \$90'), findsOneWidget);
      await _close(tester, container);
    });

    testWidgets('Bitcoin → $name: an amount over the balance still says so',
        (tester) async {
      final container = await _open(tester, side);
      // $150 against $100.
      for (final key in ['1', '5', '0']) {
        await tester.tap(find.text(key).last);
        await tester.pump();
      }
      expect(find.text(_insufficient), findsWidgets);
      expect(find.text('Add funds'), findsOneWidget);
      expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
      await _close(tester, container);
    });
  }
}
