// The Investments Withdraw: the Deposit's sheet turned around. Its first
// step is "To your wallet" over the Bitcoin card (the Move money sheet,
// Dollars to Bitcoin), then "To another wallet or exchange" over the coins
// the dollars can be sent out as; a coin opens the dollar send with that
// coin picked, and a send that went out closes this sheet. Nothing here
// reaches a money call: both doors are test seams.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListRow, SendToSectionHeader;
import 'package:kute/screens/usd/usd_withdraw_screen.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart'
    show UsdSendDestination;
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

OrchestraRoutesCatalog _catalog({bool coins = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (coins) ...[
            _row('arbitrum', 'USDC'),
            _row('base', 'USDC'),
            _row('ethereum', 'USDC'),
            _row('tron', 'USDT'),
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

const _bitcoinRow = ValueKey('usd-withdraw-to-bitcoin');
const _bitcoinButton = ValueKey('usd-withdraw-to-bitcoin-button');
const _underneath = 'open withdraw';

/// Opens the Withdraw the way the dock does: a sheet over a screen.
Future<void> _pump(WidgetTester tester,
    {bool coins = true, int? spendingSats, bool dark = false}) async {
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
          .overrideWith((_) => _Routes(_catalog(coins: coins))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // Bitcoin at $60,000; the spending balance only when given.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            if (spendingSats != null)
              'spending': WalletBalance(
                  onChainBtcBalance: 0, sparkBitcoinbalance: spendingSats),
          })),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [
              dark ? AppColorsExtension.dark() : AppColorsExtension.light()
            ]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showUsdWithdrawSheet(context),
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Finder _tile(String symbol) => find.widgetWithText(CoinAssetTile, symbol).first;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<UsdSendDestination> sendsOpened;
  late List<int> movesOpened;
  bool? sendResult;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    sendsOpened = [];
    movesOpened = [];
    sendResult = null;
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    UsdWithdrawScreen.debugMoveSheetOpener = (_) async => movesOpened.add(1);
    UsdWithdrawScreen.debugSendOpener = (_, d) async {
      sendsOpened.add(d);
      return sendResult;
    };
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdWithdrawScreen.debugMoveSheetOpener = null;
    UsdWithdrawScreen.debugSendOpener = null;
  });

  for (final dark in [false, true]) {
    testWidgets(
        'opens as the Deposit\'s sheet: "To your wallet" over the Bitcoin '
        'card, then "To another wallet or exchange" over the coins '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, spendingSats: 100000, dark: dark);
      // The Deposit's frame and its read-only balance pill, naming the
      // balance the money leaves from.
      final frame = find.byType(ReceiveSheetFrame);
      expect(frame, findsOneWidget);
      expect(ModalRoute.of(tester.element(frame))!.settings.name,
          kUsdWithdrawRouteName);
      final pill =
          tester.widget<AccountSwitcherPill>(find.byType(AccountSwitcherPill));
      expect(pill.label, _l10n.assetDollars);
      expect(pill.readOnly, isTrue);

      final yours = find.text(_l10n.usdWithdrawToYourWallet);
      final row = find.byKey(_bitcoinRow);
      final another = find.text(_l10n.usdWithdrawToAnotherWallet);
      final grid = find.byKey(const ValueKey('usd-withdraw-coin-grid'));
      expect(yours, findsOneWidget);
      expect(row, findsOneWidget);
      expect(another, findsOneWidget);
      expect(grid, findsOneWidget);
      expect(_tile('USDC'), findsOneWidget);
      expect(_tile('USDT'), findsOneWidget);
      // Top to bottom, as the Deposit.
      expect(tester.getTopLeft(yours).dy, lessThan(tester.getTopLeft(row).dy));
      expect(tester.getBottomLeft(row).dy,
          lessThan(tester.getTopLeft(another).dy));
      expect(
          tester.getTopLeft(another).dy, lessThan(tester.getTopLeft(grid).dy));

      // The Bitcoin card: the Bitcoin mark's card, "Bitcoin" over the
      // spending balance, and the Withdraw now button.
      final card = tester.widget<SendToListRow>(row);
      expect(card.title, _l10n.bitcoin);
      expect(card.subtitle, '\$60.00');
      final button = tester.widget<AppButton>(find.descendant(
          of: find.byKey(_bitcoinButton), matching: find.byType(AppButton)));
      expect(button.text, _l10n.usdWithdrawNow);
      expect(button.compact, isTrue);

      // The theme's own colours: the labels in the tertiary ink.
      final colors =
          dark ? AppColorsExtension.dark() : AppColorsExtension.light();
      final header = find.descendant(
          of: find.byType(SendToSectionHeader).first,
          matching: find.byType(Text));
      expect(tester.widget<Text>(header).style!.color, colors.textTertiary);

      // Nothing opened by itself; Investments never says Send or Receive.
      expect(sendsOpened, isEmpty);
      expect(movesOpened, isEmpty);
      expect(find.text(_l10n.send), findsNothing);
      expect(find.text(_l10n.receive), findsNothing);
      expect(events.map((e) => e.$1), isNot(contains('usd_send_opened')));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  for (final target in ['card', 'button']) {
    testWidgets(
        'tapping the Bitcoin $target opens Move money from Dollars to '
        'Bitcoin', (tester) async {
      await _pump(tester, spendingSats: 100000);
      await tester.tap(target == 'card'
          ? find.descendant(
              of: find.byKey(_bitcoinRow), matching: find.text(_l10n.bitcoin))
          : find.byKey(_bitcoinButton));
      await tester.pump();
      expect(movesOpened, [1]);
      expect(sendsOpened, isEmpty);
      expect(TrackingService.takeEntrySource('move'),
          kUsdWithdrawBitcoinRowSource);
      await _unmount(tester);
    });
  }

  testWidgets(
      'a coin on one network opens the dollar send on that coin, under the '
      'Withdraw sheet\'s entry source', (tester) async {
    await _pump(tester);
    await tester.tap(_tile('USDT'));
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsNothing);
    expect(sendsOpened.map((d) => d.id), ['tron:USDT']);
    expect(
        TrackingService.takeEntrySource('usd_send'), kUsdWithdrawSheetSource);
    final picked =
        events.where((e) => e.$1 == 'coin_picker_coin_picked').single.$2!;
    expect(picked['flow'], 'usd_withdraw');
    expect(picked['asset'], 'USDT');
    // The send was closed without going out: this sheet stays.
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'swaps blocked for a named region: the coins stay; a tap says why '
      'and opens no send', (tester) async {
    const regions = {'label': 'the European Union, the UK and Switzerland'};
    final policy = runtimePolicyFixture(blocked: {
      'orchestra.swap',
      'orchestra.swap.stablecoins',
    }, reasons: {
      'orchestra.swap': 'country_blocked',
      'orchestra.swap.stablecoins': 'country_blocked',
    }, decorations: {
      'orchestra.swap': {'regions': regions},
      'orchestra.swap.stablecoins': {
        'blockedBy': 'orchestra.swap',
        'regions': regions
      },
    });
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    await _pump(tester);
    expect(_tile('USDC'), findsOneWidget);
    expect(_tile('USDT'), findsOneWidget);
    await tester.tap(_tile('USDT'));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    expect(
        find.text(
            'Not available in the European Union, the UK and Switzerland'),
        findsOneWidget);
    expect(find.text("If this isn't where you are, check your VPN settings."),
        findsOneWidget);
    expect(sendsOpened, isEmpty);
    expect(
        events
            .where((e) => e.$1 == 'capability_region_blocked')
            .map((e) => e.$2)
            .toList(),
        [
          {
            'capability': 'orchestra.swap',
            'blocked_by': 'none',
            'surface': 'usd_withdraw',
          }
        ]);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
    policy.dispose();
  });

  testWidgets('a coin on several networks asks which one, then opens the send',
      (tester) async {
    await _pump(tester);
    await tester.tap(_tile('USDC'));
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.byType(PickerRow), findsNWidgets(3));
    expect(sendsOpened, isEmpty);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('base')));
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsNothing);
    expect(sendsOpened.map((d) => d.id), ['base:USDC']);
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a send that went out closes the Withdraw sheet', (tester) async {
    sendResult = true;
    await _pump(tester);
    await tester.tap(_tile('USDT'));
    await tester.pumpAndSettle();
    expect(sendsOpened, hasLength(1));
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'nothing offered: the Bitcoin card still leads, then the unavailable '
      'line instead of the coins', (tester) async {
    await _pump(tester, coins: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.text(_l10n.usdWithdrawToAnotherWallet), findsNothing);
    expect(find.byType(CoinAssetGrid), findsNothing);
    expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
