// The Dollars Send: the same Who step as the Bitcoin Send (founder, 7
// November 2026, the approved Send: "ok do it, just make sure that people
// realise they can send to different cryptos also"): "Send", as the
// Bitcoin Send says it (7 November 2026: "these receive and send from
// dollars seem too small and strange"), the search field ("Name, phone or
// any crypto address"), then Frequent and the Contacts: no "Another
// crypto" card (founder, 7 November 2026: "another crypto should be
// implied not a button"); with no coin offered, the unavailable line under
// the empty field. NO CHIPS: no "To your Bitcoin", no "Crypto address", no
// "Prediction or investment". Typed, an own account's name finds the move
// ("Move to your Bitcoin"). The input decides the rail, however it
// arrives: an address the dollar send takes opens it on its amount (a
// paste at once, typed through Continue or the keyboard's Done), one
// several networks take asks which, one only bitcoin pays goes to the
// Bitcoin Send. A person (a contact, a typed number) is asked What: this Send's
// Dollars (no toggle) or a gift. The bar is the step's Continue, as on the
// Bitcoin Send: off, it says what to do ("Add who to send to"). A send
// that went out, or a link created, closes the sheet.
// Nothing here reaches a money call: every door is a test seam.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePillTabs;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show AnotherCryptoMarks;
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet, kSendWhatGiftKey, kSendWhatMoneyKey;
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show
        MoneyMovementAccount,
        MoneyMovementRequest,
        MoneyMovementRoute,
        debugMoneyMovementSheetOpener;
import 'package:kute/screens/usd/usd_withdraw_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../mocks/fake_send_contacts_gateway.dart';

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

OrchestraRoutesCatalog _catalog({bool coins = true, bool wide = false}) =>
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
          if (wide) ...[
            for (final chain in ['optimism', 'polygon']) _row(chain, 'USDC'),
            for (final chain in ['ethereum', 'bsc', 'arbitrum'])
              _row(chain, 'USDT'),
            for (final chain in ['ethereum', 'base', 'arbitrum'])
              _row(chain, 'ETH', decimals: 18),
            for (final (chain, asset) in const [
              ('solana', 'SOL'),
              ('bsc', 'BNB'),
              ('polygon', 'POL'),
              ('tron', 'TRX'),
              ('litecoin', 'LTC'),
              ('zcash', 'ZEC'),
              ('ethereum', 'DAI'),
              ('ethereum', 'LINK'),
              ('ethereum', 'UNI'),
              ('ethereum', 'AAVE'),
              ('arbitrum', 'ARB'),
              ('optimism', 'OP'),
              ('ethereum', 'PEPE'),
              ('ethereum', 'SHIB'),
              ('avalanche', 'AVAX'),
              ('ethereum', 'MKR'),
              ('ethereum', 'LDO'),
              ('ethereum', 'WLD'),
            ])
              _row(chain, asset, decimals: 18),
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

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

late FakeSendContactsGateway _gateway;
const _underneath = 'open withdraw';
/// No Send has an "Another crypto" card any more (the Receive sheets keep
/// theirs): absent, by its old key, its marks and its title.
void _expectNoAnotherCrypto() {
  expect(find.byKey(const ValueKey('send-another-crypto')), findsNothing);
  expect(find.byType(AnotherCryptoMarks), findsNothing);
  expect(find.text(_l10n.receiveAnotherCrypto), findsNothing);
}
const _field = ValueKey('send-recipient-search');
const _evm = '0x742d35cc6634c0532925a3b844bc454e4438f44e';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

/// The keys and words of the chips this sheet no longer has.
const _oldChips = [
  ValueKey('usd-withdraw-options'),
  ValueKey('usd-withdraw-to-bitcoin'),
  ValueKey('send-also-sends-to-row'),
  ValueKey('usd-withdraw-pick'),
  ValueKey('usd-withdraw-anyone'),
];
const _oldChipWords = [
  'More ways to send',
  'To your Bitcoin',
  'Crypto address',
  'Prediction or investment',
];

/// Opens the Withdraw the way the dock does: a sheet over a screen.
Future<void> _pump(WidgetTester tester,
    {bool coins = true,
    bool wide = false,
    int? spendingSats,
    double? dollars,
    bool dark = false,
    Size size = const Size(390, 844),
    Locale? locale,
    List<SwapOrder> orders = const []}) async {
  tester.view.physicalSize = size;
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
      sendContactsGatewayProvider.overrideWithValue(_gateway),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders(orders)),
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(coins: coins, wide: wide))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // Bitcoin at $60,000; the spending balance only when given.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            if (spendingSats != null)
              'spending': WalletBalance(
                  onChainBtcBalance: 0, sparkBitcoinbalance: spendingSats),
          })),
      // The Dollars balance, as the SDK answered it, only when given.
      if (dollars != null) ...[
        usdBalanceProvider.overrideWithValue(dollars),
        usdBalanceUnknownProvider.overrideWithValue(false),
      ],
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
        locale: locale,
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

/// The clipboard holds [text] (Paste reads it).
void _clipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return {'text': text};
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

/// The primary bar contexts the sheet declares (the bar as a button).
List<KuteBarContext> _primaryScopes() => [
      for (final e in find
          .byWidgetPredicate(
              (w) => w is KuteBarContextScope && w.barContext.isPrimary)
          .evaluate())
        (e.widget as KuteBarContextScope).barContext
    ];

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<(String, String?)> sendsOpened;
  late List<(String?, String?)> picksOpened;
  late List<(ShareLinkKind, String?, String?)> linksOpened;
  late List<String> bitcoinSends;
  bool? sendResult;
  bool? linkResult;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The venues open: the What step's gift can be sent
    // (send_pick_market_sheet.dart, sendPickOffered).
    final policy = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    sendsOpened = [];
    picksOpened = [];
    linksOpened = [];
    bitcoinSends = [];
    sendResult = null;
    linkResult = null;
    _gateway = FakeSendContactsGateway(contacts: fakeContacts());
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    UsdWithdrawScreen.debugSendOpener = (_, d, recipient) async {
      sendsOpened.add((d.id, recipient));
      return sendResult;
    };
    UsdWithdrawScreen.debugPickOpener =
        (_, {senderLabel, recipientPhone}) async {
      picksOpened.add((senderLabel, recipientPhone));
      return linkResult;
    };
    UsdWithdrawScreen.debugLinkOpener =
        (_, {required kind, contact, phone}) async {
      linksOpened.add((kind, contact?.firstName, phone));
      return linkResult;
    };
    UsdWithdrawScreen.debugBitcoinSendOpener =
        (_, address) => bitcoinSends.add(address);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdWithdrawScreen.debugSendOpener = null;
    UsdWithdrawScreen.debugPickOpener = null;
    UsdWithdrawScreen.debugLinkOpener = null;
    UsdWithdrawScreen.debugBitcoinSendOpener = null;
  });

  Iterable<Map<String, Object>?> paramsOf(String event) =>
      events.where((e) => e.$1 == event).map((e) => e.$2);

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
        find.descendant(
            of: find.byType(UsdWithdrawScreen),
            matching: find.byType(TextField)),
        text);
    await _settle(tester);
  }

  for (final dark in [false, true]) {
    testWidgets(
        'the Who step: "Send", the search field saying it takes any '
        'crypto address, the Scan QR Code row, then the Contacts: no Another '
        'crypto card, no chips, no Send to anyone '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, spendingSats: 100000, dark: dark);
      final screen = find.byType(UsdWithdrawScreen);
      expect(ModalRoute.of(tester.element(screen))!.settings.name,
          kUsdWithdrawRouteName);
      expect(
          find.descendant(of: screen, matching: find.text(_l10n.send)),
          findsOneWidget);
      expect(find.text(_l10n.sendDollarsTitle), findsNothing);
      expect(find.byKey(_field), findsOneWidget);
      expect(find.text(_l10n.sendRecipientSearchHint), findsOneWidget);
      expect(
          find.byKey(const ValueKey('send-contacts-ask-row')), findsOneWidget);
      for (final key in _oldChips) {
        expect(find.byKey(key), findsNothing);
      }
      for (final words in _oldChipWords) {
        expect(find.text(words), findsNothing, reason: words);
      }
      expect(find.text(_l10n.sendToLabel), findsNothing);
      expect(find.byType(CoinAssetGrid), findsNothing);
      expect(find.byKey(const ValueKey('send-to-friend-row')), findsNothing);

      // No card under the field (founder: "another crypto should be
      // implied not a button"): the logos of what it takes, the Scan QR
      // Code row, the Contacts right under it.
      _expectNoAnotherCrypto();
      final coins = find.byKey(const ValueKey('send-accepted-coins'));
      expect(coins, findsOneWidget);
      expect(
          find.descendant(
              of: coins, matching: find.byKey(const ValueKey('send-accepted-coin-BTC'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: coins,
              matching: find.byKey(const ValueKey('send-accepted-coin-Lightning'))),
          findsOneWidget);
      expect(find.byType(KuteActionCardGrid), findsNothing);
      expect(find.byType(KuteActionCard), findsNothing);
      expect(find.text(_l10n.usdSendDestinationsUnavailable), findsNothing);
      double top(Finder f) => tester.getTopLeft(f).dy;
      final scan = find.byKey(const ValueKey('send-field-scan'));
      expect(scan, findsOneWidget);
      expect(find.text(_l10n.scanQrCode), findsOneWidget);
      expect(top(scan), greaterThan(tester.getBottomLeft(coins).dy));
      expect(top(find.text(_l10n.sendAllContacts)) - tester.getBottomLeft(scan).dy,
          inInclusiveRange(0, 76));
      // Typing hides it with the logos; the field's clear brings it back.
      await tester.enterText(find.byType(TextField).first, 'mar');
      await _settle(tester);
      expect(scan, findsNothing);
      expect(coins, findsNothing);
      await tester.tap(find.byKey(const ValueKey('send-field-clear')));
      await _settle(tester);
      expect(scan, findsOneWidget);

      // The bar: the step's Continue, as on the Bitcoin Send's Who step,
      // off and saying what to do.
      expect(_primaryScopes(), hasLength(1));
      expect(kuteBarPrimaryEnabled(tester), isFalse);
      expect(kuteBarPrimaryContext(tester).primaryLabel,
          _l10n.barNeedRecipient);
      expect(sendsOpened, isEmpty);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets(
      'nothing offered: the unavailable line under the empty field says why '
      '(the placeholder promises any crypto address)', (tester) async {
    await _pump(tester, coins: false);
    _expectNoAnotherCrypto();
    expect(find.byType(KuteActionCard), findsNothing);
    expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
    expect(
        tester.getTopLeft(find.text(_l10n.usdSendDestinationsUnavailable)).dy,
        greaterThan(tester.getRect(find.byKey(_field)).bottom));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'people first: search < Frequent < All contacts; a recent opens the '
      'send on its coin and address; typing hides Frequent',
      (tester) async {
    await _pump(tester, spendingSats: 100000, orders: [
      SwapOrder(
        id: 'sent-1',
        coinFrom: 'USDB',
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'ARBITRUM',
        depositAddress: 'deposit',
        depositAmount: '12.00',
        withdrawalAmount: '12.00',
        status: 'finished',
        timestamp: DateTime(2026, 11, 1).millisecondsSinceEpoch,
        withdrawalAddress: _evm,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: 'refund',
        provider: 'Orchestra',
        activityDirection: 'send',
      ),
    ]);
    const frequent = ValueKey('send-frequent-section');
    expect(find.byKey(frequent), findsOneWidget);
    expect(find.text(_l10n.sendFrequent), findsOneWidget);
    final recent = find.byKey(const ValueKey('send-frequent-recent:$_evm'));
    expect(recent, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.byKey(_field)), lessThan(top(find.byKey(frequent))));
    expect(tester.getBottomLeft(find.byKey(frequent)).dy,
        lessThan(top(find.byKey(const ValueKey('send-contacts-ask-row')))));
    // Once only: the Contacts below never repeat it.
    expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);

    // A recent is paid directly: the send on its coin and address.
    await tester.tap(recent);
    await _settle(tester);
    expect(sendsOpened, [('arbitrum:USDC', _evm)]);

    await type(tester, 'ana');
    expect(find.byKey(frequent), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      '"bitcoin" in the field shows "Move to your Bitcoin", which opens Move '
      'money straight on the amount: Dollars to Bitcoin, pinned',
      (tester) async {
    final moves = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    addTearDown(() => debugMoneyMovementSheetOpener = null);
    await _pump(tester, spendingSats: 100000);
    await type(tester, 'bitcoin');
    final row = find.byKey(const ValueKey('send-move-to-bitcoin'));
    expect(row, findsOneWidget);
    expect(find.text(_l10n.sendMoveToYourBitcoin), findsOneWidget);
    expect(find.text(_l10n.receiveFromYourDollars), findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    expect(moves, hasLength(1));
    expect(moves.single.route,
        const MoneyMovementRoute(
            MoneyMovementAccount.dollars, MoneyMovementAccount.bitcoin));
    expect(moves.single.pinned, isTrue);
    expect(moves.single.entrySource, kUsdWithdrawSearchSource);
    expect(TrackingService.takeEntrySource('move'), kUsdWithdrawSearchSource);
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);

    // "my dollars" the other way: Bitcoin into Dollars.
    await type(tester, 'my dollars');
    await tester.tap(find.byKey(const ValueKey('send-move-to-dollars')));
    await tester.pump();
    expect(moves.last.route,
        const MoneyMovementRoute(
            MoneyMovementAccount.bitcoin, MoneyMovementAccount.dollars));
    await _unmount(tester);
  });

  testWidgets(
      'a typed number is a person: What, this Send\'s Dollars (its mark, '
      '"Dollars", "\$12.34 available"; no toggle, no Bitcoin), the dollar '
      'link to it; a link created closes the sheet',
      (tester) async {
    linkResult = true;
    await _pump(tester, dollars: 12.349, spendingSats: 400000);
    await type(tester, '+351 999 888 777');
    final row = find.byKey(const ValueKey('send-phone-link-row'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final sheet = find.byType(SendWhatSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.byType(KutePillTabs)),
        findsNothing);
    expect(find.descendant(of: sheet, matching: find.text(_l10n.bitcoin)),
        findsNothing);
    expect(find.descendant(of: sheet, matching: find.byType(KuteActionCard)),
        findsNWidgets(2));
    final money = find.byKey(kSendWhatMoneyKey);
    // Dollars and the gift: two equal squares side by side.
    final gift = find.byKey(kSendWhatGiftKey);
    expect(tester.getSize(money), tester.getSize(gift));
    expect(tester.getTopLeft(gift).dy,
        moreOrLessEquals(tester.getTopLeft(money).dy));
    expect(tester.getTopLeft(gift).dx,
        greaterThan(tester.getTopRight(money).dx));
    expect(
        find.descendant(
            of: money, matching: find.text(_l10n.portfolioBalanceDollars)),
        findsOneWidget);
    expect(
        find.descendant(
            of: money,
            matching: find.text(_l10n.hlYieldAvailableLine('\$12.34'))),
        findsOneWidget);
    await tester.tap(money);
    await tester.pumpAndSettle();
    expect(linksOpened, [(ShareLinkKind.dollars, null, '+351999888777')]);
    expect(paramsOf('send_recipient_picked').single,
        containsPair('kind', 'phone'));
    expect(paramsOf('send_what_picked').single,
        {'what': 'money', 'home': 'dollars', 'from': 'dollars'});
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'a contact: What\'s gift opens the search in send mode with them; '
      'Dollars is the dollar link, never a bitcoin one',
      (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await _pump(tester);
    final maria = find.byKey(const ValueKey('send-person-contact:c2'));
    await tester.tap(maria);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSendWhatGiftKey));
    await tester.pumpAndSettle();
    expect(picksOpened, [('Maria', '+351 912 345 678')]);
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);

    await tester.tap(maria);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSendWhatMoneyKey));
    await tester.pumpAndSettle();
    expect(linksOpened, [(ShareLinkKind.dollars, 'Maria', null)]);
    expect(paramsOf('send_what_picked').last,
        {'what': 'money', 'home': 'dollars', 'from': 'dollars'});
    expect(bitcoinSends, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'a Kute contact: Dollars is a dollar link (a Kute address takes no '
      'dollars), never the Bitcoin Send on their address', (tester) async {
    _gateway
      ..permission = SendContactsPermission.granted
      ..contacts = [
        const SendContact(
            id: 'k1',
            displayName: 'Joana Kute',
            firstName: 'Joana',
            phone: '+351 914 444 444',
            lightningAddress: 'joana@paykute.com'),
      ];
    await _pump(tester);
    final joana = find.byKey(const ValueKey('send-person-contact:k1'));
    await tester.tap(joana);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSendWhatMoneyKey));
    await tester.pumpAndSettle();
    expect(linksOpened, [(ShareLinkKind.dollars, 'Joana', null)]);
    expect(bitcoinSends, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'Predictions and Investing closed to this person: the What step has '
      'no gift', (tester) async {
    final closed = runtimePolicyFixture(
        blocked: const {'polymarket.trade', 'hyperliquid.trade'},
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = closed;
    await tester.runAsync(closed.refresh);
    await _pump(tester);
    await type(tester, '+351 999 888 777');
    await tester.tap(find.byKey(const ValueKey('send-phone-link-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(kSendWhatMoneyKey), findsOneWidget);
    expect(find.byKey(kSendWhatGiftKey), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'a typed address resolves first (the coin on its network) and the '
      'bar\'s Continue opens the send on it; a send that went out closes '
      'the sheet', (tester) async {
    sendResult = true;
    await _pump(tester);
    await type(tester, _tron);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    expect(find.text(_l10n.sendRecipientSendingTo), findsOneWidget);
    expect(_primaryScopes(), hasLength(1));
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    // Typed: nothing opens until Continue.
    expect(sendsOpened, isEmpty);
    kuteBarPrimaryContext(tester).onPrimary!();
    await tester.pumpAndSettle();
    expect(sendsOpened, [('tron:USDT', _tron)]);
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'Change on the recipient card empties the field and brings the '
      'Contacts back, no card', (tester) async {
    await _pump(tester);
    await type(tester, _tron);
    await tester.tap(find.byKey(const ValueKey('send-recipient-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-recipient-card')), findsNothing);
    expect(find.text(_l10n.sendAllContacts), findsOneWidget);
    _expectNoAnotherCrypto();
    await _unmount(tester);
  });

  testWidgets(
      'typed, the keyboard\'s Done goes on as a paste does: an address one '
      'network takes opens the send on its amount, a 0x address asks its '
      'network, a Lightning address goes to the Bitcoin Send; an address no '
      'route takes stays with its line', (tester) async {
    await _pump(tester);
    await type(tester, _tron);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    expect(sendsOpened, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(sendsOpened, [('tron:USDT', _tron)]);
    expect(paramsOf('send_recipient_picked').single,
        containsPair('kind', 'address'));

    await type(tester, _evm);
    expect(find.byKey(const ValueKey('usd-withdraw-pick-network')),
        findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDT'), findsNothing);
    // The coin sheet's own event, with no source (the card's is gone).
    expect(paramsOf('usd_withdraw_coin_sheet_opened'), hasLength(1));
    expect(paramsOf('usd_withdraw_coin_sheet_opened').single?['source'],
        isNull);
    Navigator.of(tester.element(find.byType(CoinAssetPickerSheet))).pop();
    await _settle(tester);

    await type(tester, 'alice@getalby.com');
    expect(find.text(_l10n.usdReceiveFromYourBitcoin), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(bitcoinSends, ['alice@getalby.com']);

    await type(tester, 'zz9notanaddressatall0000000');
    expect(find.byKey(const ValueKey('send-inline-error')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(sendsOpened, hasLength(1));
    expect(bitcoinSends, hasLength(1));
    expect(find.byType(CoinAssetPickerSheet), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'a typed address several networks take asks which one in the coin '
      'sheet, then opens the send with it', (tester) async {
    await _pump(tester);
    await type(tester, _evm);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsNothing);
    final pick = find.byKey(const ValueKey('usd-withdraw-pick-network'));
    expect(pick, findsOneWidget);
    expect(
        tester
            .widget<SendToListCard>(
                find.ancestor(of: pick, matching: find.byType(SendToListCard)))
            .emphasized,
        isTrue);
    // The bar says the step to take, as on the Bitcoin Send.
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    expect(kuteBarPrimaryContext(tester).primaryLabel, _l10n.barNeedNetwork);
    await tester.tap(pick);
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDT'), findsNothing);
    await tester.tap(_tile('USDC'));
    await _settle(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('base')));
    await _settle(tester);
    expect(sendsOpened, [('base:USDC', _evm)]);
    await _unmount(tester);
  });

  testWidgets(
      'pasting an address one network takes goes straight to the send, on '
      'its amount; pasting a 0x address asks for the network at once',
      (tester) async {
    await _pump(tester);
    _clipboard(tester, _tron);
    await tester.tap(find.byKey(const ValueKey('send-field-paste')));
    await _settle(tester);
    expect(sendsOpened, [('tron:USDT', _tron)]);
    expect(paramsOf('send_recipient_picked').single,
        containsPair('kind', 'address'));

    await type(tester, '');
    _clipboard(tester, _evm);
    await tester.tap(find.byKey(const ValueKey('send-field-paste')));
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDT'), findsNothing);
    expect(sendsOpened, hasLength(1));
    await _unmount(tester);
  });

  testWidgets(
      'the input decides the rail: a bitcoin address no dollar route takes '
      'is the Bitcoin Send\'s ("From your Bitcoin" on its card); pasted, a '
      'Lightning address goes there at once', (tester) async {
    await _pump(tester);
    await type(tester, _btc);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    expect(find.text(_l10n.usdReceiveFromYourBitcoin), findsOneWidget);
    expect(find.byKey(const ValueKey('send-inline-error')), findsNothing);
    kuteBarPrimaryContext(tester).onPrimary!();
    await _settle(tester);
    expect(bitcoinSends, [_btc]);

    await type(tester, '');
    _clipboard(tester, 'alice@getalby.com');
    await tester.tap(find.byKey(const ValueKey('send-field-paste')));
    await _settle(tester);
    expect(bitcoinSends, [_btc, 'alice@getalby.com']);
    expect(sendsOpened, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: the placeholder is '
      'whole (it is what says the field takes any crypto), no Another '
      'crypto card', (tester) async {
    await tester.runAsync(_loadInter);
    final cut = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester,
          wide: true, size: const Size(375, 812), locale: locale);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: why);
      expect(find.byType(AnotherCryptoMarks), findsNothing, reason: why);
      expect(find.text(l10n.receiveAnotherCrypto), findsNothing, reason: why);
      final placeholder = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byKey(_field),
          matching: find.text(l10n.sendRecipientSearchHint)));
      if (placeholder.didExceedMaxLines) cut.add('$why placeholder');
      await _unmount(tester);
    }
    expect(cut, isEmpty, reason: cut.join(', '));
  });
}
