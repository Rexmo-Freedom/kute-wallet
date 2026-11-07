// Gating audit (fw36, v2.2): the money doors of the two homes, read
// against a real backend policy under the four ways it withholds a
// capability (a swap country block and its cascade, a platform rule, the
// switch off, coming soon). Blocks live only in the backend policy
// (founder decision, 27 October 2026); nothing here is decided by the app.
//
//   * Dollars Receive ("Receive or swap"): "From your Bitcoin" is a swap
//     (Bitcoin into Dollars): the card stays and the Move sheet it opens
//     says why (money_movement_sheet_test.dart, the fw36 group). "From
//     another wallet or exchange" is a cross-chain receive: a REGION
//     block keeps it (the coin's tap names the regions,
//     coin_asset_picker_policy_test.dart); any other refusal of the swap
//     master or of `crypto.deposit` takes it away, with the sheet's
//     unavailable line.
//   * Bitcoin Receive or swap: "From your Dollars" is an exit (Dollars
//     into Bitcoin) and "Bitcoin" is plain bitcoin: both always there.
//     Its figure is all the dollar money that can move to Bitcoin (fw46):
//     the venues' cash stays in under a swap country block (their
//     withdraws are exits too) and goes only for a venue whose own
//     withdraw a platform rule or a switch withholds. "From another
//     asset" follows the cross-chain rule above.
//   * Dollars Send chips: "To your Bitcoin" (an exit) always there;
//     "Crypto address" (a cross-chain send: never `crypto.deposit`) kept
//     by a region block, gone for any other swap refusal; "Prediction"
//     gone while neither venue may take a new position (the swap cascade
//     shuts both).
//   * Bitcoin Send chips: "To Dollars" (a swap) always drawn, the Move
//     sheet says why; "Crypto address" as on Dollars: kept by a region
//     block (the coins listed, a coin's tap names the regions), gone for
//     any other swap refusal (its sheet has no Bitcoin Network row, plain
//     bitcoin being the send's own default, so it would open empty);
//     "Prediction" as on Dollars.

import 'dart:async';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' show Contact;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart' show CoinAssetTile;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show
        MoneyMovementAccount,
        MoneyMovementRequest,
        MoneyMovementRoute,
        debugMoneyMovementSheetOpener;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendCoinStack, SendWaysRow;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/usd/usd_withdraw_screen.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashLastReadProvider;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show kVenuePullEta;
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import '../helpers/kute_bar_test_support.dart';
import '../mocks/fake_send_contacts_gateway.dart';
import '../mocks/fake_share_links_api.dart';
import 'market_gating_fixtures.dart';

final _l10n = AppLocalizationsEn();

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

class _NoContacts extends SparkContactsNotifier {
  @override
  Future<List<Contact>> build() async => const [];
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

/// A live catalogue: bitcoin and dollars on Spark and three other coins.
OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('base', 'USDC'),
          _row('tron', 'USDT'),
          _row('ethereum', 'ETH', decimals: 18),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
    );

final _spending = WalletConfig(id: 'spending', name: 'Spending');

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [_spending],
    );

late FakeSendContactsGateway _gateway;

List<Override> _overrides() => [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      selectedAccountProvider.overrideWithValue(BtcSpendingAccount(_spending)),
      swapOffersEnabledProvider.overrideWithValue(true),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(_catalog())),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // Every coin reaches Dollars through a reusable address.
      standingDestinationsProvider.overrideWith((_) async => {'spark:USDB'}),
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
      usdBalanceProvider.overrideWithValue(4.75),
      usdBalanceUnknownProvider.overrideWithValue(false),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            'spending': WalletBalance(
                onChainBtcBalance: 0, sparkBitcoinbalance: 100000),
          })),
      sendContactsGatewayProvider.overrideWithValue(_gateway),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders(const [])),
      sparkContactsProvider.overrideWith(_NoContacts.new),
      // The wallet never answers: no address is ever asked for.
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    ];

const _underneath = 'open';

/// Opens [open] as a sheet over a screen, the way the dock does.
Future<void> _pumpSheet(WidgetTester tester, void Function(BuildContext) open,
    {List<Override> extra = const []}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [..._overrides(), ...extra],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        builder: withKuteShellBar,
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
                onPressed: () => open(context),
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

/// Opens the Bitcoin Send (its own sheet route), as the dock does.
Future<void> _pumpBitcoinSend(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 812) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.pushNamed('pay_send'),
            child: const Text(_underneath),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/send',
      name: 'pay_send',
      pageBuilder: (context, state) => SendSheetPage<void>(
        key: state.pageKey,
        name: state.name,
        child: const ConfirmSend(),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ..._overrides(),
      shareLinksApiProvider.overrideWithValue(FakeShareLinksApi()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        builder: withKuteShellBar,
        routerConfig: router,
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_underneath));
  await tester.pumpAndSettle();
  expect(find.byType(ConfirmSend), findsOneWidget);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

// The doors, by key.
const _usdFromBitcoin = ValueKey('usd-receive-from-bitcoin');
const _usdFromAnother = ValueKey('usd-receive-from-another');
const _btcFromDollars = ValueKey('bitcoin-receive-from-dollars');
const _btcFromAnother = ValueKey('bitcoin-receive-from-another');
const _btcBitcoin = ValueKey('bitcoin-receive-bitcoin');
const _usdToBitcoin = ValueKey('usd-withdraw-to-bitcoin');
const _usdCrypto = ValueKey('send-also-sends-to-row');
const _usdPick = ValueKey('usd-withdraw-pick');
const _btcToDollars = ValueKey('send-to-dollars');
const _btcCrypto = ValueKey('send-also-sends-to-row');
const _btcPick = ValueKey('send-pick');

/// The refusals of the swap master that are not a region block.
const _nonRegion = [
  MarketDenial.masterOff,
  MarketDenial.platform,
  MarketDenial.comingSoon,
];

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('fw36_money_doors');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalSpriteCache.debugSetManifest(null);
    TrackingService.setDisabled(true);
    ShareLinksStore.debugMemory = <String, String>{};
    _gateway = FakeSendContactsGateway(contacts: fakeContacts());
  });

  tearDown(() {
    uninstallMarketGatingPolicy();
    SalSpriteCache.debugReset();
    ShareLinksStore.debugMemory = null;
    TrackingService.setDisabled(false);
    debugMoneyMovementSheetOpener = null;
  });

  /// Every own-account door opens Move money straight on the amount,
  /// pinned in its direction (showOwnMoneyMove): recorded here; what the
  /// sheet then allows is money_movement_sheet_test.dart's fw36 group.
  List<MoneyMovementRequest> recordMoves() {
    final moves = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    return moves;
  }

  const bitcoinToDollars = MoneyMovementRoute(
      MoneyMovementAccount.bitcoin, MoneyMovementAccount.dollars);
  const dollarsToBitcoin = MoneyMovementRoute(
      MoneyMovementAccount.dollars, MoneyMovementAccount.bitcoin);

  void expectPinned(List<MoneyMovementRequest> moves, MoneyMovementRoute r) {
    expect(moves, hasLength(1));
    expect(moves.single.route, r);
    expect(moves.single.pinned, isTrue);
  }

  Future<void> install(WidgetTester tester, MarketDenial? how,
          {Set<String> targets = const {}}) =>
      tester.runAsync(() => installMarketGatingPolicy(how, targets: targets));

  group('Dollars Receive or swap', () {
    testWidgets(
        'nothing withheld: From your Bitcoin and From another wallet or '
        'exchange', (tester) async {
      await install(tester, null);
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdFromBitcoin), findsOneWidget);
      expect(find.byKey(_usdFromAnother), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets(
        'swap country block (cascade to crypto deposits): both cards stay; '
        'From your Bitcoin opens the Move sheet, which says why',
        (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdFromBitcoin), findsOneWidget);
      expect(find.byKey(_usdFromAnother), findsOneWidget,
          reason: 'a region block hides nothing; the coin tap says why');
      expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsNothing);
      await tester.tap(find.byKey(_usdFromBitcoin));
      await tester.pump();
      // A swap: Bitcoin into Dollars, pinned; the sheet refuses it with
      // the named regions and Check connection.
      expectPinned(moves, bitcoinToDollars);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: From another wallet or exchange '
          'goes, with the unavailable line; From your Bitcoin stays',
          (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showUsdReceiveSheet);
        expect(find.byKey(_usdFromAnother), findsNothing);
        expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
        expect(find.byKey(_usdFromBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets(
        'crypto.deposit off (receives from another network only): From '
        'another wallet or exchange goes; From your Bitcoin stays',
        (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdFromAnother), findsNothing);
      expect(find.byKey(_usdFromBitcoin), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Bitcoin Receive or swap', () {
    testWidgets(
        'swap country block: From your Dollars (an exit), From another '
        'asset (kept by a region block) and Bitcoin; From your Dollars '
        'opens the Move sheet, Dollars to Bitcoin', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpSheet(tester, showBitcoinReceiveSheet);
      final grid = tester.widget<KuteActionCardGrid>(
          find.byKey(const ValueKey('bitcoin-receive-options')));
      // Bitcoin leads (plain bitcoin, never gated), the two doors under it.
      expect(grid.lead?.key, _btcBitcoin);
      expect(grid.cards.map((c) => c.key), [_btcFromDollars, _btcFromAnother]);
      await tester.tap(find.byKey(_btcFromDollars));
      await tester.pump();
      // An exit: Dollars into Bitcoin, pinned; the sheet moves it.
      expectPinned(moves, dollarsToBitcoin);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: From another asset goes; From '
          'your Dollars and Bitcoin stay', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showBitcoinReceiveSheet);
        expect(find.byKey(_btcFromAnother), findsNothing);
        expect(find.byKey(_btcFromDollars), findsOneWidget);
        expect(find.byKey(_btcBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }

    // $4.75 of Dollars, $20 on Predictions and $40 on Investing, as the
    // engine last read them.
    final venueCash = venueCashLastReadProvider.overrideWith((_) => (
          walletId: 'spending',
          candidates: [
            (
              venue: OneBalanceVenue.predictions,
              availableUsd: 20.0,
              eta: kVenuePullEta[OneBalanceVenue.predictions]!,
              minimumUsd: 1.0,
            ),
            (
              venue: OneBalanceVenue.investing,
              availableUsd: 40.0,
              eta: kVenuePullEta[OneBalanceVenue.investing]!,
              minimumUsd: 5.0,
            ),
          ],
        ));
    String? fromDollarsLine(WidgetTester tester) =>
        tester.widget<KuteActionCard>(find.byKey(_btcFromDollars)).subtitle;

    testWidgets(
        'swap country block: From your Dollars still counts both venues\' '
        'cash (their withdraws are exits, as Dollars into Bitcoin is)',
        (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      await _pumpSheet(tester, showBitcoinReceiveSheet, extra: [venueCash]);
      // 4.75 + 20 x 0.98 + (40 x 0.98 - 0.30).
      expect(fromDollarsLine(tester), _l10n.hlYieldAvailableLine(r'$63.25'));
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on hyperliquid.withdraw: Investing\'s cash leaves '
          'the From your Dollars figure; the card stays and opens the move',
          (tester) async {
        await install(tester, how, targets: {'hyperliquid.withdraw'});
        final moves = recordMoves();
        await _pumpSheet(tester, showBitcoinReceiveSheet, extra: [venueCash]);
        expect(fromDollarsLine(tester), _l10n.hlYieldAvailableLine(r'$24.35'));
        await tester.tap(find.byKey(_btcFromDollars));
        await tester.pump();
        expectPinned(moves, dollarsToBitcoin);
        await _unmount(tester);
      });
    }

    testWidgets(
        'crypto.deposit coming soon: From another asset goes; plain '
        'bitcoin and the Dollars exit stay', (tester) async {
      await install(tester, MarketDenial.comingSoon,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showBitcoinReceiveSheet);
      expect(find.byKey(_btcFromAnother), findsNothing);
      expect(find.byKey(_btcFromDollars), findsOneWidget);
      expect(find.byKey(_btcBitcoin), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Dollars Send chips', () {
    List<Key?> chips(WidgetTester tester) => tester
        .widget<SendWaysRow>(find.byKey(const ValueKey('usd-withdraw-options')))
        .chips
        .map((c) => c.key)
        .toList();

    testWidgets(
        'swap country block: To your Bitcoin and Crypto address stay; no '
        'Prediction (the cascade shuts both venues); To your Bitcoin opens '
        'the Move sheet', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expect(chips(tester), [_usdToBitcoin, _usdCrypto]);
      expect(find.text(_l10n.usdSendDestinationsUnavailable), findsNothing);
      await tester.tap(find.byKey(_usdToBitcoin));
      await tester.pump();
      // An exit: Dollars into Bitcoin, pinned; the sheet moves it.
      expectPinned(moves, dollarsToBitcoin);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: Crypto address goes with the '
          'unavailable line; To your Bitcoin and Prediction stay',
          (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showUsdWithdrawSheet);
        expect(chips(tester), [_usdToBitcoin, _usdPick]);
        expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets('crypto.deposit off never touches a send: all three chips stay',
        (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expect(chips(tester), [_usdToBitcoin, _usdCrypto, _usdPick]);
      await _unmount(tester);
    });

    for (final how in MarketDenial.values) {
      testWidgets('${how.label} on both venues\' trading: no Prediction chip',
          (tester) async {
        await install(tester, how,
            targets: {'polymarket.trade', 'hyperliquid.trade'});
        await _pumpSheet(tester, showUsdWithdrawSheet);
        expect(find.byKey(_usdPick), findsNothing);
        expect(find.byKey(_usdToBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets('one venue open is enough for the Prediction chip',
        (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'hyperliquid.trade'});
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expect(find.byKey(_usdPick), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Bitcoin Send chips', () {
    List<Key?> chips(WidgetTester tester) => tester
        .widget<SendWaysRow>(find.byKey(const ValueKey('send-to-options')))
        .chips
        .map((c) => c.key)
        .toList();

    testWidgets(
        'swap country block: To Dollars and Crypto address stay, the coins '
        'stacked (a region block hides nothing); no Prediction',
        (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpBitcoinSend(tester);
      expect(chips(tester), [_btcToDollars, _btcCrypto]);
      expect(
          find.descendant(
              of: find.byKey(_btcCrypto), matching: find.byType(SendCoinStack)),
          findsOneWidget);
      await tester.tap(find.byKey(_btcToDollars));
      await tester.pumpAndSettle();
      // A swap, pinned: the Move sheet says why (its own test).
      expectPinned(moves, bitcoinToDollars);
      // The coins stay listed, and only the coins: no Bitcoin Network row
      // (plain bitcoin is this send's own default); a coin's tap names
      // the regions (coin_asset_picker_policy_test.dart).
      await tester.tap(find.byKey(_btcCrypto));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sendWhereTo), findsOneWidget);
      expect(find.byType(CoinAssetTile), findsWidgets);
      expect(find.text(_l10n.bitcoinNetwork), findsNothing);
      expect(find.text(_l10n.bitcoinLightningSpark), findsNothing);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: no coin to offer and no Bitcoin '
          'Network row on its sheet, so Crypto address goes rather than '
          'open an empty sheet; To Dollars and Prediction stay',
          (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpBitcoinSend(tester);
        expect(chips(tester), [_btcToDollars, _btcPick]);
        expect(find.byKey(_btcCrypto), findsNothing);
        expect(find.byType(SendCoinStack), findsNothing);
        expect(find.text(_l10n.sendWhereTo), findsNothing);
        // Plain bitcoin is untouched: the field still takes an address.
        expect(find.byKey(const ValueKey('send-recipient-search')),
            findsOneWidget);
      });
    }

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master, an address that needs a network '
          'pasted: its highlighted row\'s sheet says why, with no coin and '
          'no Bitcoin Network row', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpBitcoinSend(tester);
        await tester.enterText(find.byType(TextField).first,
            '0x742d35cc6634c0532925a3b844bc454e4438f44e');
        await tester.pumpAndSettle();
        await tester.tap(find.text(_l10n.sendWhichNetworkIsThisAddressOn));
        await tester.pumpAndSettle();
        expect(find.text(_l10n.sendWhereTo), findsOneWidget);
        expect(find.text(how.message), findsOneWidget);
        expect(find.byType(CoinAssetTile), findsNothing);
        expect(find.text(_l10n.bitcoinNetwork), findsNothing);
      });
    }

    testWidgets(
        'crypto.deposit off never touches a send: all three Bitcoin Send '
        'chips stay', (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpBitcoinSend(tester);
      expect(chips(tester), [_btcToDollars, _btcCrypto, _btcPick]);
    });
  });
}
