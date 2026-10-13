// The Investments receive: the dock's Receive opens it straight on the
// address step with a coin already picked (the one last used, else USDC
// on Solana, Base or Polygon, else the first offered), and both steps
// carry "From your Bitcoin" at the top, which opens the Investments
// deposit from the spending bitcoin. Nothing here reaches a money call:
// the wallet never answers, so the address step stays on its loading
// shape.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide, MovePickerRow;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'package:money2/money2.dart';

import '../../helpers/runtime_policy_fixture.dart';

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog({bool solana = true, bool stables = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (stables) ...[
            _row('arbitrum', 'USDC'),
            _row('base', 'USDC'),
            _row('polygon', 'USDC'),
            if (solana) _row('solana', 'USDC'),
            _row('ethereum', 'USDT'),
          ],
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
    );

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

OrchestraReceiveOption _option(String chain, String asset,
        {bool reusable = true}) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
      reusableAddress: reusable,
    );

final _l10n = AppLocalizationsEn();

Future<void> _pump(WidgetTester tester,
    {bool autoPickCoin = true,
    bool solana = true,
    bool stables = true,
    int? spendingSats}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      orchestraSupportedRoutesProvider.overrideWith(
          (_) => _Routes(_catalog(solana: solana, stables: stables))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // Bitcoin at $60,000; the spending balance only when given.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            if (spendingSats != null)
              'spending': WalletBalance(
                  onChainBtcBalance: 0, sparkBitcoinbalance: spendingSats),
          })),
      // The wallet never answers: the address step stays on its loading
      // shape and no address is ever asked for.
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UsdReceiveScreen(autoPickCoin: autoPickCoin),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Unmounts the screen and lets its timers (the shimmer, the sheet) go.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Map<String, Object>? _selected(List<(String, Map<String, Object>?)> events) =>
    events.where((e) => e.$1 == 'usd_receive_coin_selected').single.$2;

void main() {
  late List<(String, Map<String, Object>?)> events;
  late Map<String, String> store;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    store = {};
    UsdReceiveLastCoin.debugStore = store;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdReceiveScreen.debugDepositSheetOpener = null;
    UsdReceiveLastCoin.debugStore = null;
  });

  group('usdReceivePreselect', () {
    final offered = [
      _option('arbitrum', 'USDC'),
      _option('base', 'USDC'),
      _option('polygon', 'USDC'),
      _option('solana', 'USDC'),
    ];
    String? pickId(List<OrchestraReceiveOption> o, {String? lastUsed}) {
      final pick = usdReceivePreselect(o, lastUsed: lastUsed);
      return pick == null ? null : usdReceiveCoinId(pick.option);
    }

    test('the one last used, while still offered as a reusable address', () {
      final pick = usdReceivePreselect(offered, lastUsed: 'arbitrum:USDC')!;
      expect(usdReceiveCoinId(pick.option), 'arbitrum:USDC');
      expect(pick.reason, 'last_used');
    });

    test('else USDC on Solana, then Base, then Polygon', () {
      expect(pickId(offered), 'solana:USDC');
      expect(usdReceivePreselect(offered)!.reason, 'default');
      // A last-used coin no longer offered falls through to the defaults.
      expect(pickId(offered, lastUsed: 'tron:USDT'), 'solana:USDC');
      final noSolana = offered.where((o) => o.chain != 'solana').toList();
      expect(pickId(noSolana), 'base:USDC');
      final polygonLeft = [
        _option('arbitrum', 'USDT'),
        _option('polygon', 'USDC'),
      ];
      expect(pickId(polygonLeft), 'polygon:USDC');
      // A one-time Solana route is no default: Base takes it.
      expect(
          pickId([
            _option('solana', 'USDC', reusable: false),
            _option('base', 'USDC'),
          ]),
          'base:USDC');
    });

    test('else the first offered coin; one-time routes are never picked', () {
      final pick = usdReceivePreselect([
        _option('polygon', 'USDC', reusable: false),
        _option('arbitrum', 'USDT'),
      ])!;
      expect(usdReceiveCoinId(pick.option), 'arbitrum:USDT');
      expect(pick.reason, 'default');
      expect(pickId([_option('polygon', 'USDC', reusable: false)]), isNull);
      expect(pickId(const []), isNull);
    });
  });

  testWidgets(
      'the dock\'s Receive opens on the address step with USDC on Solana '
      'picked, and remembers it', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.usdReceiveShareStep), findsOneWidget);
    expect(find.text(_l10n.usdFlowStepCoin), findsNothing);
    expect(find.text(_l10n.usdReceiveCreating), findsOneWidget);
    expect(_selected(events), {
      'asset': 'USDC',
      'chain': 'solana',
      'address_kind': 'reusable',
      'preselected': true,
      'preselect_reason': 'default',
    });
    expect(store, {'last': 'solana:USDC'});
    // No balance read yet: the Bitcoin row's plain subtitle.
    expect(
        tester
            .widget<MovePickerRow>(
                find.byKey(const ValueKey('usd-receive-from-bitcoin')))
            .subtitle,
        _l10n.depositFromSpendingWallet);

    // Back lands on the coin step, whose picker still changes it.
    await tester.tap(find.byType(KuteBackButton));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_l10n.usdFlowStepCoin), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the coin last received with wins', (tester) async {
    store['last'] = 'polygon:USDC';
    await _pump(tester);
    expect(find.text(_l10n.usdReceiveShareStep), findsOneWidget);
    expect(_selected(events), {
      'asset': 'USDC',
      'chain': 'polygon',
      'address_kind': 'reusable',
      'preselected': true,
      'preselect_reason': 'last_used',
    });
    await _unmount(tester);
  });

  testWidgets('without Solana it is USDC on Base', (tester) async {
    await _pump(tester, solana: false);
    expect(_selected(events)!['chain'], 'base');
    expect(_selected(events)!['preselect_reason'], 'default');
    await _unmount(tester);
  });

  testWidgets('nothing offered: today\'s coin step, nothing picked',
      (tester) async {
    await _pump(tester, stables: false);
    expect(find.text(_l10n.usdReceiveShareStep), findsNothing);
    expect(events.where((e) => e.$1 == 'usd_receive_coin_selected'), isEmpty);
    expect(
        events.map((e) => e.$1), contains('usd_receive_coin_picker_opened'));
    await _unmount(tester);
  });

  testWidgets('opened without the dock it starts on the coin step',
      (tester) async {
    await _pump(tester, autoPickCoin: false);
    expect(find.text(_l10n.usdReceiveShareStep), findsNothing);
    expect(events.where((e) => e.$1 == 'usd_receive_coin_selected'), isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      '"From your Bitcoin" sits at the top and opens the Investments '
      'deposit from the spending bitcoin', (tester) async {
    final opened = <MoveLockedSide>[];
    UsdReceiveScreen.debugDepositSheetOpener =
        (_, {required lockedSide}) async => opened.add(lockedSide);
    await _pump(tester, spendingSats: 100000);
    final row = find.byKey(const ValueKey('usd-receive-from-bitcoin'));
    expect(row, findsOneWidget);
    final picker = tester.widget<MovePickerRow>(row);
    expect(picker.title, _l10n.usdReceiveFromYourBitcoin);
    expect(picker.asset, 'lib/assets/bitcoin-icon.svg');
    // The spending bitcoin in dollars, as the Move sheet's row reads it.
    expect(picker.subtitle, 'Your spending wallet · \$60.00');
    // Above the step heading.
    expect(tester.getTopLeft(row).dy,
        lessThan(tester.getTopLeft(find.text(_l10n.usdReceiveShareStep)).dy));

    await tester.tap(row);
    await tester.pump();
    expect(opened, [MoveLockedSide.depositToUsd]);
    expect(TrackingService.takeEntrySource('move'), 'usd_receive_bitcoin_row');

    // The coin step carries it too.
    await tester.tap(find.byType(KuteBackButton));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_l10n.usdFlowStepCoin), findsOneWidget);
    expect(row, findsOneWidget);
    await _unmount(tester);
  });
}
