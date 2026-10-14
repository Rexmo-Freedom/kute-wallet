// The Investments receive: every way in (the dock's Receive included)
// opens on the coin step, "From your Bitcoin" first, which opens the
// Investments deposit from the spending bitcoin, then "Also accepts" over
// the coin grid. Nothing is picked for the person: a coin they tap shows
// its address. Nothing here reaches a money call: the wallet never
// answers, so the address step stays on its loading shape.

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
    show MoveLockedSide;
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showUsdReceiveSheet;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveQrPlate, ReceiveSheetFrame;
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListRow;
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

OrchestraRoutesCatalog _catalog({bool stables = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (stables) ...[
            _row('arbitrum', 'USDC'),
            _row('base', 'USDC'),
            _row('polygon', 'USDC'),
            _row('solana', 'USDC'),
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

final _l10n = AppLocalizationsEn();

const _bitcoinRow = ValueKey('usd-receive-from-bitcoin');

/// Opens the receive the way the dock does: a sheet over a screen, at a
/// 390pt-wide phone.
Future<void> _pump(WidgetTester tester,
    {bool stables = true, int? spendingSats}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
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
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(stables: stables))),
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
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showUsdReceiveSheet(context),
                child: const Text(_underneath),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text(_underneath));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _underneath = 'open receive';

/// Unmounts the screen and lets its timers (the shimmer, the sheet) go.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Finder _tile(String symbol) => find.widgetWithText(CoinAssetTile, symbol).first;

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdReceiveScreen.debugDepositSheetOpener = null;
  });

  Iterable<String> names() => events.map((e) => e.$1);

  testWidgets(
      'opens on the coin step: "From your Bitcoin" first, "Also accepts" '
      'and the coin grid below, nothing picked and no sheet over it',
      (tester) async {
    await _pump(tester);
    final row = find.byKey(_bitcoinRow);
    expect(row, findsOneWidget);
    final accepts = find.text(_l10n.receiveAlsoAccepts);
    expect(accepts, findsOneWidget);
    expect(find.byType(CoinAssetGrid), findsOneWidget);
    expect(_tile('USDC'), findsOneWidget);
    expect(_tile('USDT'), findsOneWidget);
    // Top to bottom: the Bitcoin row, the heading, the grid.
    expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(accepts).dy));
    expect(tester.getTopLeft(accepts).dy,
        lessThan(tester.getTopLeft(find.byType(CoinAssetGrid)).dy));

    // No address, no auto pick, no sheet.
    expect(find.text(_l10n.usdReceiveShareStep), findsNothing);
    expect(find.text(_l10n.usdReceiveCreating), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    expect(names(), isNot(contains('usd_receive_coin_picker_opened')));
    expect(find.byType(CoinAssetPickerSheet), findsNothing);
    expect(names(), contains('usd_receive_opened'));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      '"From your Bitcoin" is a full list row with the spending balance and '
      'opens the Investments deposit from the spending bitcoin',
      (tester) async {
    final opened = <MoveLockedSide>[];
    UsdReceiveScreen.debugDepositSheetOpener =
        (_, {required lockedSide}) async => opened.add(lockedSide);
    await _pump(tester, spendingSats: 100000);
    final row = tester.widget<SendToListRow>(find.byKey(_bitcoinRow));
    expect(row.title, _l10n.usdReceiveFromYourBitcoin);
    // The spending bitcoin in dollars, as the Move sheet's row reads it.
    expect(row.subtitle, 'Your spending wallet · \$60.00');
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.byKey(_bitcoinRow));
    await tester.pump();
    expect(opened, [MoveLockedSide.depositToUsd]);
    expect(TrackingService.takeEntrySource('move'), 'usd_receive_bitcoin_row');
    await _unmount(tester);
  });

  testWidgets('without a balance the row says just the spending wallet',
      (tester) async {
    await _pump(tester);
    expect(tester.widget<SendToListRow>(find.byKey(_bitcoinRow)).subtitle,
        _l10n.depositFromSpendingWallet);
    await _unmount(tester);
  });

  testWidgets(
      'a coin on one network goes straight to its address inside the same '
      'sheet; the Bitcoin row is not repeated there and Back returns to the '
      'coin step, still inside the sheet', (tester) async {
    await _pump(tester);
    final sheet = ModalRoute.of(tester.element(find.byKey(_bitcoinRow)));
    expect(sheet, isA<ModalBottomSheetRoute<void>>());
    expect(find.byType(KuteCloseButton), findsOneWidget);
    await tester.tap(_tile('USDT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_l10n.usdReceiveShareStep), findsOneWidget);
    expect(find.text(_l10n.usdReceiveCreating), findsOneWidget);
    expect(find.byKey(_bitcoinRow), findsNothing);
    // The address step is the same sheet, not a pushed screen.
    expect(
        ModalRoute.of(tester.element(find.text(_l10n.usdReceiveShareStep))),
        same(sheet));
    // The QR plate is as large as fits: at least 240pt on a 390pt phone.
    final plate = tester.getSize(find
        .descendant(
            of: find.byType(ReceiveQrPlate), matching: find.byType(Container))
        .first);
    expect(plate.height, plate.width);
    expect(plate.width, greaterThanOrEqualTo(240));
    expect(plate.width, lessThanOrEqualTo(320));
    final selected =
        events.where((e) => e.$1 == 'usd_receive_coin_selected').single.$2;
    expect(selected, {
      'asset': 'USDT',
      'chain': 'ethereum',
      'address_kind': 'reusable',
      'preselected': false,
      'preselect_reason': 'none',
    });

    await tester.tap(find.byType(KuteCircleBackButton));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_l10n.usdReceiveShareStep), findsNothing);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.text(_l10n.receiveAlsoAccepts), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byKey(_bitcoinRow))), same(sheet));

    // On the coin step the header's close closes the sheet.
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the sheet opens with presentation: sheet and swipes away',
      (tester) async {
    await _pump(tester);
    final opened =
        events.where((e) => e.$1 == 'usd_receive_opened').single.$2!;
    expect(opened['presentation'], 'sheet');
    expect(opened['source'], 'usd');
    // Tall: about 90% of the screen.
    final frame = tester.getSize(find.byType(ReceiveSheetFrame));
    expect(frame.height, greaterThan(844 * 0.8));
    expect(frame.height, lessThanOrEqualTo(844 * 0.9 + 0.5));

    await tester.fling(
        find.byType(StepperProgress), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.byType(UsdReceiveScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(names(), contains('usd_receive_abandoned'));
    await _unmount(tester);
  });

  testWidgets(
      'a coin on several networks asks which one, then shows that address',
      (tester) async {
    await _pump(tester);
    await tester.tap(_tile('USDC'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(names(), contains('usd_receive_coin_picker_opened'));
    expect(names(), isNot(contains('usd_receive_coin_selected')));

    // Open on USDC's networks, not on the sheet's grid.
    final networks = find.byType(PickerRow);
    expect(networks, findsNWidgets(4));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('solana')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_l10n.usdReceiveShareStep), findsOneWidget);
    final selected =
        events.where((e) => e.$1 == 'usd_receive_coin_selected').single.$2!;
    expect(selected['chain'], 'solana');
    expect(selected['preselected'], false);
    expect(selected['preselect_reason'], 'none');
    await _unmount(tester);
  });

  testWidgets('nothing offered: the Bitcoin row still leads, then the note',
      (tester) async {
    await _pump(tester, stables: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
    expect(find.byType(CoinAssetGrid), findsNothing);
    expect(find.text(_l10n.usdReceiveShareStep), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });
}
