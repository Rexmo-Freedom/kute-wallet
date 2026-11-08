// Gating audit (fw36, v2.2): the money doors of the two homes, read
// against a real backend policy under the four ways it withholds a
// capability (a swap country block and its cascade, a platform rule, the
// switch off, coming soon). Blocks live only in the backend policy
// (founder decision, 27 October 2026); nothing here is decided by the app.
//
//   * Neither Receive has an own-money door any more (founder, 7 November
//     2026: "On bitcoin receive we get rid of from your dollars. On
//     dollars receive we get rid of from your bitcoin."): moving between
//     your own accounts is the two homes' Swap, and the Sends' own-account
//     moves below.
//   * The Bitcoin home's row: Swap is always live and opens the Swap screen
//     as the Dollars home's does, which says why under a block (money_
//     movement_sheet_test.dart); Purchase, Receive and Send stay open.
//   * Dollars Receive: "Dollars" (the dollar coins) and "Another
//     crypto" (the others) are cross-chain receives: a REGION block keeps
//     them (the coin's tap names the regions,
//     coin_asset_picker_policy_test.dart); any other refusal of the swap
//     master or of `crypto.deposit` takes them away, with the sheet's
//     unavailable line.
//   * Bitcoin Receive: "Bitcoin" is plain bitcoin, always there; "Another
//     crypto" follows the cross-chain rule above.
//   * The Sends have no chips any more (fw50, founder 7 November 2026: one
//     verb per intent) and no "Another crypto" card (founder, 7 November
//     2026: "another crypto should be implied not a button"): the field
//     recognises a crypto address however it arrives, and a cross-chain
//     send (never `crypto.deposit`) answers it by the same rules. Their
//     doors:
//   * Dollars Send: "Move to your Bitcoin" (the search's escape hatch, an
//     exit) always there; a typed 0x address asks its network under a
//     region block (the coins kept, a coin's tap names the regions), and
//     under any other swap refusal says why under the field, the
//     unavailable line under the empty field; the What step's gift ("A
//     prediction or investment") stays under a region block with neither
//     venue open (the swap cascade shuts both; its tap says why, send_what_
//     step_test.dart), and goes only when another refusal shuts both.
//   * Bitcoin Send: "Move to your Dollars" (a swap) always drawn, the Move
//     sheet says why; a typed 0x address asks its network, its "Where
//     to?" sheet listing the coins under a region block and saying why
//     under any other swap refusal (no Bitcoin Network row: plain bitcoin
//     is the send's own default); the gift as on Dollars. Plain bitcoin is
//     always open: the field takes an address whatever the policy says.

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
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteCompactActions, KuteDockAction;
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart'
    show bitcoinHomeDockActions, kBitcoinHomeSwapSource;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show CapabilityUnavailableSheet;
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
    show AnotherCryptoMarks;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/shared/send/send_what_step.dart'
    show kSendWhatGiftKey, kSendWhatMoneyKey;
import 'package:kute/screens/usd/usd_receive_screen.dart'
    show kUsdReceiveDollarsKey;
import 'package:kute/screens/usd/usd_withdraw_screen.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
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

// The doors, by key (the two own-money ones only to say they are gone).
const _usdDollars = kUsdReceiveDollarsKey;
const _usdFromBitcoin = ValueKey('usd-receive-from-bitcoin');
const _usdFromAnother = ValueKey('usd-receive-from-another');
const _btcFromDollars = ValueKey('bitcoin-receive-from-dollars');
const _btcFromAnother = ValueKey('bitcoin-receive-from-another');
const _btcBitcoin = ValueKey('bitcoin-receive-bitcoin');
// The Sends' doors: the search's own-account moves and a typed crypto
// address (no Send has an "Another crypto" card).
const _moveToBitcoin = ValueKey('send-move-to-bitcoin');
const _moveToDollars = ValueKey('send-move-to-dollars');
const _evmAddress = '0x742d35cc6634c0532925a3b844bc454e4438f44e';

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
        'nothing withheld: Dollars (the dollar coins) and Another crypto; no '
        'From your Bitcoin', (tester) async {
      await install(tester, null);
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdDollars), findsOneWidget);
      expect(find.byKey(_usdFromAnother), findsOneWidget);
      expect(find.byKey(_usdFromBitcoin), findsNothing);
      await _unmount(tester);
    });

    testWidgets(
        'swap country block (cascade to crypto deposits): every card stays, '
        'the coins\' taps say why', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdDollars), findsOneWidget,
          reason: 'a region block hides nothing; the coin tap says why');
      expect(find.byKey(_usdFromAnother), findsOneWidget,
          reason: 'a region block hides nothing; the coin tap says why');
      expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsNothing);
      expect(find.byKey(_usdFromBitcoin), findsNothing);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: Dollars and Another crypto go, '
          'with the unavailable line, never a silent empty sheet',
          (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showUsdReceiveSheet);
        expect(find.byKey(_usdDollars), findsNothing);
        expect(find.byKey(_usdFromAnother), findsNothing);
        expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
        expect(find.byKey(_usdFromBitcoin), findsNothing);
        await _unmount(tester);
      });
    }

    testWidgets(
        'crypto.deposit off (receives from another network only): Dollars '
        'and Another crypto go, with the unavailable line', (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showUsdReceiveSheet);
      expect(find.byKey(_usdDollars), findsNothing);
      expect(find.byKey(_usdFromAnother), findsNothing);
      expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('The Bitcoin home\'s row', () {
    /// Home's row, under a real policy, recording what it offers.
    Future<List<KuteDockAction>> pumpRow(WidgetTester tester) async {
      late List<KuteDockAction> actions;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(),
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
              body: Consumer(builder: (context, ref, _) {
                actions = bitcoinHomeDockActions(context, ref, _spending,
                    source: 'home');
                return KuteCompactActions(source: 'home', actions: actions);
              }),
            ),
          ),
        ),
      ));
      await tester.pump();
      return actions;
    }

    for (final (label, how, targets) in <(String, MarketDenial?, Set<String>)>[
      ('nothing withheld', null, const {}),
      ('swap country block', MarketDenial.swapCountryBlock, const {}),
      for (final how in _nonRegion)
        ('${how.label} on the swap master', how, const {kSwapMaster}),
    ]) {
      testWidgets(
          '$label: every button live; Swap opens the Swap screen pinned to '
          'Bitcoin → Dollars, no sheet in front of it (the screen says why, '
          'money_movement_sheet_test.dart); Receive opens', (tester) async {
        await install(tester, how, targets: targets);
        final moves = recordMoves();
        final actions = await pumpRow(tester);
        expect(actions.map((a) => a.trackingId),
            ['purchase', 'swap', 'receive', 'send']);
        for (final action in actions) {
          expect(action.onTap, isNotNull, reason: action.trackingId);
          expect(action.soon, isFalse, reason: action.trackingId);
        }
        await tester.tap(find.text(_l10n.swap));
        await tester.pump();
        expectPinned(moves, dollarsToBitcoin);
        expect(moves.single.entrySource, kBitcoinHomeSwapSource);
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);

        // Plain bitcoin is never gated.
        await tester.tap(find.text(_l10n.receive));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(_btcBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }
  });

  group('Bitcoin Receive or swap', () {
    testWidgets(
        'swap country block: Bitcoin (plain bitcoin, never gated) and Another '
        'crypto (kept by a region block), two squares; no From your Dollars',
        (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      await _pumpSheet(tester, showBitcoinReceiveSheet);
      final grid = tester.widget<KuteActionCardGrid>(
          find.byKey(const ValueKey('bitcoin-receive-options')));
      expect(grid.lead, isNull);
      expect(grid.cards.map((c) => c.key), [_btcBitcoin, _btcFromAnother]);
      expect(find.byKey(_btcFromDollars), findsNothing);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: Another crypto goes; Bitcoin '
          'stays, alone', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showBitcoinReceiveSheet);
        expect(find.byKey(_btcFromAnother), findsNothing);
        expect(find.byKey(_btcBitcoin), findsOneWidget);
        expect(find.byKey(_btcFromDollars), findsNothing);
        await _unmount(tester);
      });
    }

    testWidgets(
        'crypto.deposit coming soon: Another crypto goes; plain bitcoin '
        'stays', (tester) async {
      await install(tester, MarketDenial.comingSoon,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showBitcoinReceiveSheet);
      expect(find.byKey(_btcFromAnother), findsNothing);
      expect(find.byKey(_btcBitcoin), findsOneWidget);
      await _unmount(tester);
    });
  });

  /// Types [text] into the Send open on screen.
  Future<void> typeIn(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Whether the What step shows the gift: a typed number is a person,
  /// asked What (Money is always there).
  Future<bool> giftOffered(WidgetTester tester) async {
    await typeIn(tester, '+351 999 888 777');
    final row =
        find.byKey(const ValueKey('send-phone-link-row'), skipOffstage: false);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(kSendWhatMoneyKey), findsOneWidget);
    final offered = find.byKey(kSendWhatGiftKey).evaluate().isNotEmpty;
    Navigator.of(tester.element(find.byKey(kSendWhatMoneyKey))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await typeIn(tester, '');
    return offered;
  }

  /// No Send draws an "Another crypto" card, whatever the policy says.
  void expectNoCryptoCard() {
    expect(find.byKey(const ValueKey('send-another-crypto')), findsNothing);
    expect(find.byType(AnotherCryptoMarks), findsNothing);
  }

  /// Types a 0x address and presses the keyboard's Done: what a paste of
  /// it does.
  Future<void> submitEvm(WidgetTester tester) async {
    await typeIn(tester, _evmAddress);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Dollars Send doors', () {
    testWidgets(
        'swap country block: no card; a typed 0x address asks its network '
        'and Done opens the coin sheet with the coins kept (a region block '
        'hides nothing); Move to your Bitcoin stays and opens the Move '
        'sheet; the gift stays (the cascade shuts both venues, and a region '
        'block hides nothing), its tap saying why', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expectNoCryptoCard();
      expect(find.text(_l10n.usdSendDestinationsUnavailable), findsNothing);
      expect(await giftOffered(tester), isTrue);
      await submitEvm(tester);
      expect(find.byType(CoinAssetTile), findsWidgets,
          reason: 'a region block hides nothing; the coin tap says why');
      Navigator.of(tester.element(find.byType(CoinAssetTile).first)).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await typeIn(tester, 'bitcoin');
      await tester.tap(find.byKey(_moveToBitcoin));
      await tester.pump();
      // An exit: Dollars into Bitcoin, pinned; the sheet moves it.
      expectPinned(moves, dollarsToBitcoin);
      await _unmount(tester);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: the unavailable line under the '
          'empty field, a typed 0x address says why under it (never a '
          'silent drop) and Done opens nothing; Move to your Bitcoin and '
          'the gift stay', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpSheet(tester, showUsdWithdrawSheet);
        expectNoCryptoCard();
        expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
        expect(await giftOffered(tester), isTrue);
        await submitEvm(tester);
        expect(find.byKey(const ValueKey('send-inline-error')), findsOneWidget);
        expect(find.text(how.message), findsOneWidget);
        expect(find.byType(CoinAssetTile), findsNothing);
        await typeIn(tester, 'bitcoin');
        expect(find.byKey(_moveToBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets(
        'crypto.deposit off never touches a send: a typed 0x address still '
        'asks its network, the move and the gift stay', (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expectNoCryptoCard();
      expect(await giftOffered(tester), isTrue);
      await submitEvm(tester);
      expect(find.byType(CoinAssetTile), findsWidgets);
      Navigator.of(tester.element(find.byType(CoinAssetTile).first)).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await typeIn(tester, 'bitcoin');
      expect(find.byKey(_moveToBitcoin), findsOneWidget);
      await _unmount(tester);
    });

    for (final how in MarketDenial.values) {
      final region = how == MarketDenial.swapCountryBlock;
      testWidgets(
          '${how.label} on both venues\' trading: '
          '${region ? 'the gift stays' : 'no gift'}', (tester) async {
        await install(tester, how,
            targets: {'polymarket.trade', 'hyperliquid.trade'});
        await _pumpSheet(tester, showUsdWithdrawSheet);
        expect(await giftOffered(tester), region);
        await typeIn(tester, 'bitcoin');
        expect(find.byKey(_moveToBitcoin), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets('one venue open is enough for the gift', (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'hyperliquid.trade'});
      await _pumpSheet(tester, showUsdWithdrawSheet);
      expect(await giftOffered(tester), isTrue);
      await _unmount(tester);
    });
  });

  group('Bitcoin Send doors', () {
    testWidgets(
        'swap country block: no card; Move to your Dollars stays; a typed 0x '
        'address asks its network and Done lists the coins (a region block '
        'hides nothing), with no Bitcoin Network row; the gift stays, its '
        'tap saying why', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final moves = recordMoves();
      await _pumpBitcoinSend(tester);
      expectNoCryptoCard();
      expect(await giftOffered(tester), isTrue);
      await typeIn(tester, 'dollars');
      await tester.tap(find.byKey(_moveToDollars));
      await tester.pumpAndSettle();
      // A swap, pinned: the Move sheet says why (its own test).
      expectPinned(moves, bitcoinToDollars);
      // The coins stay listed, and only the coins: no Bitcoin Network row
      // (plain bitcoin is this send's own default); a coin's tap names
      // the regions (coin_asset_picker_policy_test.dart).
      await submitEvm(tester);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sendWhereTo), findsOneWidget);
      expect(find.byType(CoinAssetTile), findsWidgets);
      expect(find.text(_l10n.bitcoinNetwork), findsNothing);
      expect(find.text(_l10n.bitcoinLightningSpark), findsNothing);
    });

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master: no card, Move to your Dollars '
          'and the gift stay; plain bitcoin is untouched', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpBitcoinSend(tester);
        expectNoCryptoCard();
        expect(find.text(_l10n.sendWhereTo), findsNothing);
        expect(await giftOffered(tester), isTrue);
        await typeIn(tester, 'dollars');
        expect(find.byKey(_moveToDollars), findsOneWidget);
        // Plain bitcoin is untouched: the field still takes an address.
        await typeIn(tester, 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
        expect(find.byKey(const ValueKey('send-recipient-card')),
            findsOneWidget);
        expect(kuteBarPrimaryEnabled(tester), isTrue);
      });
    }

    for (final how in _nonRegion) {
      testWidgets(
          '${how.label} on the swap master, an address that needs a network '
          'typed: its highlighted row\'s sheet says why, with no coin and '
          'no Bitcoin Network row', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpBitcoinSend(tester);
        await tester.enterText(find.byType(TextField).first, _evmAddress);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_l10n.sendWhichNetworkIsThisAddressOn));
        await tester.pumpAndSettle();
        expect(find.text(_l10n.sendWhereTo), findsOneWidget);
        expect(find.text(how.message), findsOneWidget);
        expect(find.byType(CoinAssetTile), findsNothing);
        expect(find.text(_l10n.bitcoinNetwork), findsNothing);
      });

      testWidgets(
          '${how.label} on the swap master, the same address submitted with '
          'the keyboard\'s Done: the same sheet saying why, never a silent '
          'drop', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        await _pumpBitcoinSend(tester);
        await submitEvm(tester);
        await tester.pumpAndSettle();
        expect(find.text(_l10n.sendWhereTo), findsOneWidget);
        expect(find.text(how.message), findsOneWidget);
        expect(find.byType(CoinAssetTile), findsNothing);
      });
    }

    testWidgets(
        'crypto.deposit off never touches a send: a typed 0x address lists '
        'its coins, the move and the gift stay on the Bitcoin Send',
        (tester) async {
      await install(tester, MarketDenial.masterOff,
          targets: {'crypto.deposit'});
      await _pumpBitcoinSend(tester);
      expectNoCryptoCard();
      expect(await giftOffered(tester), isTrue);
      await typeIn(tester, 'dollars');
      expect(find.byKey(_moveToDollars), findsOneWidget);
      await submitEvm(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CoinAssetTile), findsWidgets);
    });
  });
}
