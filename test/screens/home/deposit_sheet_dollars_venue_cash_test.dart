// Buy bitcoin with Dollars past what Dollars hold: the venue cash in
// reach counts, the shortfall comes home first, and when it has not
// landed in time the purchase stops and says so (nothing is bought).

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
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';
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
    usdBalanceProvider.overrideWith((_) => _dollars),
    venueCashReachProvider.overrideWith((_) async => _reach),
    venueCashPullerProvider.overrideWith((_) => _puller!),
  ]);
  _setBalance(container, _balanceSats);
  // The price sample is read over the shared keep-alive client, which
  // `runWithClient` cannot reach; it answers from the same fake until the
  // test's tearDown clears it.
  SharedHttpClient.debugOverride = orchestra();
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

const double _dollars = 10;
const double _reach = 60;
VenueCashPuller? _puller;

/// Predictions cash the test sets, recording each pull.
class _Venue implements VenueCashSource {
  _Venue(this.available);

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;
  double available;
  final pulls = <double>[];

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

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
    SharedHttpClient.debugOverride = null;
    TrackingService.debugTrackObserver = null;
    _puller = null;
  });

  testWidgets(
      'Dollars → Bitcoin past Dollars: venue cash is in reach, the '
      'shortfall is pulled first, and a pull still on its way stops the '
      'purchase honestly', (tester) async {
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    final venue = _Venue(100);
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat);
    // $30 against $10 of Dollars and $60 of reach.
    for (final key in ['3', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    expect(find.text(_insufficient), findsNothing);
    expect(tester.widget<AppButton>(_cta).onPressed, isNotNull);

    await tester.tap(_cta);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 20 missing: 20 / 0.98 → $20.41 from Predictions, once.
    expect(venue.pulls, [20.41]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
        find.text('${l10n.oneBalanceComingBack(r'$20.41', l10n.predictions)}'
            '\n${l10n.activityBitcoinAddedPending}'),
        findsOneWidget);
    expect(events, contains('predictions_cash_pulled'));
    expect(events, isNot(contains('convert_success')));
    expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
    await _close(tester, container);
  });
}
