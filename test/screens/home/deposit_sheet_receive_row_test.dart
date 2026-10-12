// The Investments deposit sheet is where Receive lives (owner decision,
// October 2026: the Investments dock reads Deposit · Send · search, and
// the dock's Receive moved into the deposit sheet). The sheet's From
// picker leads with a Receive row — the Dollars receive screen, an
// address for whatever coin is being sent — over the ways to pay
// (Bitcoin, Cash App while offered). Picking it closes the sheet and
// opens the receive screen's own route, with the sheet as the entry
// source. A venue door's picker carries no such row.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _balanceSats = 100000;

/// What the receive route shows in this test: the real screen needs the
/// SDK and the Orchestra catalogue; the route being reached is the point.
const _receiveKey = ValueKey('receive-dollars-route');

/// The Orchestra price sample, in the destination asset's base units.
MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final out = doubleToOrchestraAmount(
          _balanceSats / 1e8 * _usdPerBtc, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(_usdPerBtc.round())}));

  @override
  Future<void> updateRates() async {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa', proxyWalletAddress: '0xproxy');
}

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

/// Mounts the app's router with the sheet pushed over its home the way
/// [showDepositSheet] pushes it (a full-screen page on the root
/// navigator), and the Dollars receive route beside it.
Future<ProviderContainer> _open(
    WidgetTester tester, MoveLockedSide side) async {
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
    breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
  ]);
  container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
      WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: _balanceSats));
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => DepositSheet(lockedSide: side),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/receive_dollars',
      name: 'receiveDollars',
      builder: (_, __) =>
          const Scaffold(body: SizedBox.expand(key: _receiveKey)),
    ),
  ]);
  addTearDown(router.dispose);
  SharedHttpClient.debugOverride = _orchestra();
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    )),
    _orchestra,
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

/// Opens the From picker: the route card's Bitcoin row.
Future<void> _openFromPicker(WidgetTester tester) async {
  await tester.tap(find.text('Bitcoin').first);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

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
    TrackingService.takeEntrySource('usd_receive');
  });

  testWidgets(
      'the Investments deposit\'s From picker leads with Receive, which '
      'closes the sheet and opens the Dollars receive screen from the sheet',
      (tester) async {
    final container = await _open(tester, MoveLockedSide.depositToUsd);
    expect(find.byType(DepositSheet), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(DepositSheet)));

    await _openFromPicker(tester);
    // Receive first, in the picker's own row style: the inflow arrow,
    // "Receive" and the receive screen's opening line, over Bitcoin.
    final receive = find.text(l10n.receive);
    expect(receive, findsOneWidget);
    expect(find.text(l10n.usdReceivePickCoin), findsOneWidget);
    expect(find.byIcon(Icons.south_west_rounded), findsOneWidget);
    // The picker's Bitcoin row is the one under Receive (the route card
    // behind the picker names Bitcoin too, higher up the page).
    final bitcoinRow = find.text('Bitcoin').last;
    expect(tester.getTopLeft(receive).dy,
        lessThan(tester.getTopLeft(bitcoinRow).dy));
    expect(tester.getTopLeft(bitcoinRow).dy - tester.getTopLeft(receive).dy,
        lessThan(120));
    // A way in, not a source to pay from: never marked selected.
    expect(find.text(l10n.moveSelectedBadge), findsNothing);

    await tester.tap(receive);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byKey(_receiveKey), findsOneWidget);
    expect(find.byType(DepositSheet, skipOffstage: false), findsNothing);
    expect(TrackingService.takeEntrySource('usd_receive'), 'deposit_sheet');
    expect(tester.takeException(), isNull);
    await _close(tester, container);
  });

  testWidgets('a venue deposit\'s From picker carries no Receive row',
      (tester) async {
    final container = await _open(tester, MoveLockedSide.depositToHyperliquid);
    final l10n = AppLocalizations.of(tester.element(find.byType(DepositSheet)));
    await _openFromPicker(tester);
    expect(find.text('Bitcoin'), findsWidgets);
    expect(find.text(l10n.receive), findsNothing);
    expect(find.text(l10n.usdReceivePickCoin), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester, container);
  });
}
