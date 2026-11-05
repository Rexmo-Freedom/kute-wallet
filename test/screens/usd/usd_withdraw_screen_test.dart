// The Dollars Send (the Bitcoin send's layout; founder, 1 November 2026;
// made clearer 4 November 2026: "too many options and buttons"; squares 5
// November 2026: "these should be cards like squares"): "Send dollars",
// the search field ("Name, address or phone"), then under one "Send to"
// label the big cards: "To your Bitcoin" (the Move money sheet, Dollars to
// Bitcoin) and "To a crypto address" (the coin sheet) as two squares, "Send
// an investment or prediction" (the market search) compact across the
// width under them; no "Send to anyone" (a contact or a typed number sends
// by link); then the Contacts. A typed address resolves first and
// the bar's Continue opens the dollar send on it; an address several
// networks take asks which one; a send that went out, or a link created,
// closes the sheet. Nothing here reaches a money call: every door is a
// test seam.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/screens/search/components/search_rows.dart'
    show SearchChanceGauge;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListRow;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendCoinStack, SendSalShareGlyph;
import 'package:kute/services/contacts/send_contacts_service.dart';
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
const _pickRow = ValueKey('usd-withdraw-pick');
const _anyoneRow = ValueKey('usd-withdraw-anyone');

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}
const _alsoRow = ValueKey('send-also-sends-to-row');
late FakeSendContactsGateway _gateway;
const _underneath = 'open withdraw';

/// Opens the Withdraw the way the dock does: a sheet over a screen.
Future<void> _pump(WidgetTester tester,
    {bool coins = true,
    int? spendingSats,
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
  late List<int> movesOpened;
  late List<int> picksOpened;
  late List<(String?, String?)> linksOpened;
  bool? sendResult;
  bool? linkResult;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The venues open: the prediction card's slip can send
    // (send_pick_market_sheet.dart, sendPickOffered).
    final policy = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    sendsOpened = [];
    movesOpened = [];
    picksOpened = [];
    linksOpened = [];
    sendResult = null;
    linkResult = null;
    _gateway = FakeSendContactsGateway(contacts: fakeContacts());
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    UsdWithdrawScreen.debugMoveSheetOpener = (_) async => movesOpened.add(1);
    UsdWithdrawScreen.debugSendOpener = (_, d, recipient) async {
      sendsOpened.add((d.id, recipient));
      return sendResult;
    };
    UsdWithdrawScreen.debugPickOpener = (_) async {
      picksOpened.add(1);
      return linkResult;
    };
    UsdWithdrawScreen.debugLinkOpener = (_, {contact, phone}) async {
      linksOpened.add((contact?.firstName, phone));
      return linkResult;
    };
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdWithdrawScreen.debugMoveSheetOpener = null;
    UsdWithdrawScreen.debugSendOpener = null;
    UsdWithdrawScreen.debugPickOpener = null;
    UsdWithdrawScreen.debugLinkOpener = null;
  });

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
        'the Bitcoin send\'s layout: "Send dollars", the search field, then '
        'under one "Send to" label the big cards (To your Bitcoin | To a '
        'crypto address as squares, Send an investment or prediction '
        'compact across the width under them; no Send to anyone), then the '
        'Contacts; no list rows, no "To a friend" label, no inline grid '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, spendingSats: 100000, dark: dark);
      final screen = find.byType(UsdWithdrawScreen);
      expect(ModalRoute.of(tester.element(screen))!.settings.name,
          kUsdWithdrawRouteName);
      expect(find.text(_l10n.sendDollarsTitle), findsOneWidget);
      expect(
          find.byKey(const ValueKey('send-recipient-search')), findsOneWidget);
      expect(find.text(_l10n.usdSendSearchHint), findsOneWidget);
      expect(
          find.byKey(const ValueKey('send-contacts-ask-row')), findsOneWidget);
      // One label over the grid.
      expect(find.text(_l10n.sendToLabel), findsOneWidget);
      expect(find.text(_l10n.sendToAFriendLabel), findsNothing);

      final grid = find.byKey(const ValueKey('usd-withdraw-options'));
      expect(grid, findsOneWidget);
      expect(tester.widget<KuteActionCardGrid>(grid).cards.map((c) => c.key),
          [_bitcoinRow, _alsoRow, _pickRow]);
      // No Send to anyone (founder, 5 November 2026: "makes no sense since
      // we have phone numbers"): a contact or a typed number sends by link.
      expect(find.byKey(_anyoneRow), findsNothing);
      expect(find.text(_l10n.shareSendToAnyone), findsNothing);
      expect(find.byType(SendSalShareGlyph), findsNothing);
      // Square cards, none of the old list rows (the Contacts' own ask
      // row is the only one left).
      expect(
          find.byWidgetPredicate((w) =>
              w is SendToListRow &&
              w.key != const ValueKey('send-contacts-ask-row')),
          findsNothing);
      KuteActionCard card(Key key) =>
          tester.widget<KuteActionCard>(find.byKey(key));
      expect(card(_bitcoinRow).title, _l10n.usdSendToYourBitcoin);
      expect(card(_bitcoinRow).subtitle, _l10n.usdBitcoinBalanceLine('\$60.00'));
      expect(card(_bitcoinRow).visual, isA<SvgPicture>());
      expect(card(_alsoRow).title, _l10n.sendToCryptoAddress);
      expect(card(_alsoRow).subtitle, _l10n.sendAlsoSendsToList('USDC', 'USDT'));
      expect(card(_alsoRow).visual, isA<SendCoinStack>());
      expect(card(_pickRow).title, _l10n.sendAnInvestmentOrPrediction);
      expect(card(_pickRow).title, 'Send an investment or prediction');
      expect(card(_pickRow).subtitle, _l10n.sendPickCardSub);
      expect(card(_pickRow).subtitle, 'Pick a market, side and amount');
      expect(card(_pickRow).visual, isA<SearchChanceGauge>());

      // Bitcoin | address as two squares on one row, equally tall; the
      // prediction card under them across both columns, compact (a
      // chevron, lower than the squares): never a square alone in half the
      // width. The field above, the Contacts below.
      Rect r(Key key) => tester.getRect(find.byKey(key));
      expect(r(_bitcoinRow).top, moreOrLessEquals(r(_alsoRow).top));
      expect(r(_bitcoinRow).height, moreOrLessEquals(r(_alsoRow).height));
      expect(r(_bitcoinRow).right, lessThan(r(_alsoRow).left));
      expect(r(_bitcoinRow).width, moreOrLessEquals(r(_alsoRow).width));
      expect(r(_pickRow).top, greaterThan(r(_bitcoinRow).bottom));
      expect(r(_pickRow).left, moreOrLessEquals(r(_bitcoinRow).left));
      expect(r(_pickRow).right, moreOrLessEquals(r(_alsoRow).right));
      expect(r(_pickRow).height, lessThan(r(_bitcoinRow).height));
      Finder chevronIn(Key key) => find.descendant(
          of: find.byKey(key),
          matching: find.byIcon(Icons.chevron_right_rounded));
      expect(chevronIn(_pickRow), findsOneWidget);
      expect(chevronIn(_bitcoinRow), findsNothing);
      expect(chevronIn(_alsoRow), findsNothing);
      // As tall as their content: the row ends one padding under the
      // taller card's last line; no floor, no half-empty square.
      double lastLine(Key key) {
        final texts =
            find.descendant(of: find.byKey(key), matching: find.byType(Text));
        var bottom = 0.0;
        for (var i = 0; i < texts.evaluate().length; i++) {
          bottom = math.max(bottom, tester.getRect(texts.at(i)).bottom);
        }
        return bottom;
      }
      expect(
          r(_bitcoinRow).bottom,
          moreOrLessEquals(
              math.max(lastLine(_bitcoinRow), lastLine(_alsoRow)) +
                  kKuteActionCardPadding +
                  1,
              epsilon: 1));
      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(top(find.byKey(const ValueKey('send-recipient-search'))),
          lessThan(top(find.text(_l10n.sendToLabel))));
      expect(top(find.text(_l10n.sendToLabel)), lessThan(r(_bitcoinRow).top));
      expect(r(_pickRow).bottom,
          lessThan(top(find.byKey(const ValueKey('send-contacts-ask-row')))));

      // No old card, no inline grid, no friend row.
      expect(find.text(_l10n.usdWithdrawToYourWallet), findsNothing);
      expect(find.byType(AppButton), findsNothing);
      expect(find.byType(CoinAssetGrid), findsNothing);
      expect(find.byKey(const ValueKey('send-to-friend-row')), findsNothing);
      // The bar: the default search, not a button.
      expect(_primaryScopes(), isEmpty);
      expect(sendsOpened, isEmpty);
      expect(movesOpened, isEmpty);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets(
      'Predictions and Investing closed to this person: no Send an '
      'investment or prediction card (its slip could only send the '
      'market\'s card); the other two stay, two squares', (tester) async {
    final closed = runtimePolicyFixture(
        blocked: const {'polymarket.trade', 'hyperliquid.trade'},
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = closed;
    await tester.runAsync(closed.refresh);
    await _pump(tester, spendingSats: 100000);
    expect(find.byKey(_pickRow), findsNothing);
    expect(find.byKey(_anyoneRow), findsNothing);
    for (final key in [_bitcoinRow, _alsoRow]) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(tester.getRect(find.byKey(_bitcoinRow)).top,
        moreOrLessEquals(tester.getRect(find.byKey(_alsoRow)).top));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt and a large text the cards wrap their words, never cut, '
      'and nothing overflows', (tester) async {
    await _pump(tester, spendingSats: 100000);
    tester.view.physicalSize = const Size(375, 667);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);
    for (final key in [_bitcoinRow, _alsoRow, _pickRow]) {
      final texts = find.descendant(
          of: find.byKey(key), matching: find.byType(Text));
      for (final e in texts.evaluate()) {
        final t = e.widget as Text;
        if (t.data == _l10n.sendAnInvestmentOrPrediction ||
            t.data == _l10n.sendPickCardSub ||
            t.data == _l10n.sendToCryptoAddress) {
          expect(t.overflow, isNull);
          expect(t.maxLines, isNull);
        }
      }
    }
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'Frequent stays on top: the recent recipients under the field, above '
      'the Send to card; All contacts below it; typing hides Frequent',
      (tester) async {
    const evm = '0x742d35cc6634c0532925a3b844bc454e4438f44e';
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
        withdrawalAddress: evm,
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
    expect(find.byKey(const ValueKey('send-frequent-recent:$evm')),
        findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.byKey(const ValueKey('send-recipient-search'))),
        lessThan(top(find.byKey(frequent))));
    expect(top(find.byKey(frequent)), lessThan(top(find.text(_l10n.sendToLabel))));
    expect(top(find.byKey(_alsoRow)),
        lessThan(top(find.byKey(const ValueKey('send-contacts-ask-row')))));
    // Once only: the Contacts below never repeat it.
    expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);

    await tester.enterText(
        find.descendant(
            of: find.byType(UsdWithdrawScreen),
            matching: find.byType(TextField)),
        'ana');
    await _settle(tester);
    expect(find.byKey(frequent), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('To your Bitcoin opens Move money from Dollars to Bitcoin',
      (tester) async {
    await _pump(tester, spendingSats: 100000);
    await tester.tap(find.byKey(_bitcoinRow));
    await tester.pump();
    expect(movesOpened, [1]);
    expect(
        TrackingService.takeEntrySource('move'), kUsdWithdrawBitcoinRowSource);
    await _unmount(tester);
  });

  testWidgets(
      'a typed number sends by link (the reason there is no Send to anyone '
      'card); a link created closes the sheet', (tester) async {
    linkResult = true;
    await _pump(tester);
    expect(find.byKey(_anyoneRow), findsNothing);
    await type(tester, '+351 999 888 777');
    final row = find.byKey(const ValueKey('send-phone-link-row'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(linksOpened, [(null, '+351999888777')]);
    expect(events.where((e) => e.$1 == 'send_recipient_picked').single.$2,
        containsPair('kind', 'phone'));
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'Send an investment or prediction opens the market search; a link '
      'created closes the sheet', (tester) async {
    linkResult = true;
    await _pump(tester);
    await tester.tap(find.byKey(_pickRow));
    await tester.pumpAndSettle();
    expect(picksOpened, [1]);
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'Also sends to opens the coin sheet; a coin on one network opens the '
      'dollar send on it', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_alsoRow));
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    await tester.tap(_tile('USDT'));
    await _settle(tester);
    expect(sendsOpened, [('tron:USDT', null)]);
    expect(
        TrackingService.takeEntrySource('usd_send'), kUsdWithdrawSheetSource);
    // The send was closed without going out: this sheet stays.
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a coin on several networks asks which one, then opens the send',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_alsoRow));
    await _settle(tester);
    await tester.tap(_tile('USDC'));
    await _settle(tester);
    expect(find.byType(PickerRow), findsNWidgets(3));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('base')));
    await _settle(tester);
    expect(sendsOpened, [('base:USDC', null)]);
    await _unmount(tester);
  });

  testWidgets('a send that went out closes the Dollars Send', (tester) async {
    sendResult = true;
    await _pump(tester);
    await tester.tap(find.byKey(_alsoRow));
    await _settle(tester);
    await tester.tap(_tile('USDT'));
    await tester.pumpAndSettle();
    expect(sendsOpened, hasLength(1));
    expect(find.byType(UsdWithdrawScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'a typed address resolves first (the coin on its network) and the '
      'bar\'s Continue opens the send on it', (tester) async {
    await _pump(tester);
    const tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
    await type(tester, tron);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    // One recipient card: the Send to card is hidden meanwhile.
    expect(find.text(_l10n.sendRecipientSendingTo), findsOneWidget);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_l10n.sendToLabel), findsNothing);
    expect(_primaryScopes(), hasLength(1));
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    kuteBarPrimaryContext(tester).onPrimary!();
    await _settle(tester);
    expect(sendsOpened, [('tron:USDT', tron)]);
    // Change empties the field and brings the Send to card back.
    await tester.tap(find.byKey(const ValueKey('send-recipient-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-recipient-card')), findsNothing);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'an address several networks take asks which one in the coin sheet, '
      'then opens the send with it', (tester) async {
    await _pump(tester);
    const evm = '0x742d35cc6634c0532925a3b844bc454e4438f44e';
    await type(tester, evm);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsNothing);
    final pick = find.byKey(const ValueKey('usd-withdraw-pick-network'));
    expect(pick, findsOneWidget);
    await tester.tap(pick);
    await _settle(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDT'), findsNothing);
    await tester.tap(_tile('USDC'));
    await _settle(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('base')));
    await _settle(tester);
    expect(sendsOpened, [('base:USDC', evm)]);
    await _unmount(tester);
  });

  testWidgets(
      'Contacts: a contact gets a claim link for dollars; a typed number no '
      'contact has offers "Send a link to +…"', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await _pump(tester);
    final maria = find.byKey(const ValueKey('send-person-contact:c2'));
    expect(maria, findsOneWidget);
    await tester.tap(maria);
    await _settle(tester);
    expect(linksOpened, [('Maria', null)]);

    await type(tester, '+351 999 888 777');
    final row = find.byKey(const ValueKey('send-phone-link-row'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await _settle(tester);
    expect(linksOpened.last, (null, '+351999888777'));
    await _unmount(tester);
  });

  testWidgets(
      'nothing offered: To your Bitcoin and the pick stay as two squares, no '
      'address card, the unavailable line under them', (tester) async {
    await _pump(tester, coins: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.byKey(_anyoneRow), findsNothing);
    expect(find.byKey(_pickRow), findsOneWidget);
    expect(find.byKey(_alsoRow), findsNothing);
    expect(
        tester
            .widget<KuteActionCardGrid>(
                find.byKey(const ValueKey('usd-withdraw-options')))
            .cards,
        hasLength(2));
    expect(tester.getRect(find.byKey(_pickRow)).top,
        moreOrLessEquals(tester.getRect(find.byKey(_bitcoinRow)).top));
    expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
    expect(
        tester.getTopLeft(find.text(_l10n.usdSendDestinationsUnavailable)).dy,
        greaterThan(tester.getRect(find.byKey(_pickRow)).bottom));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: two squares over '
      'the compact "Send an investment or prediction", every word whole '
      'inside its card, nothing overflowing', (tester) async {
    await tester.runAsync(_loadInter);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester,
          spendingSats: 123456789,
          size: const Size(375, 812),
          locale: locale);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: why);
      final a = tester.getRect(find.byKey(_bitcoinRow));
      final b = tester.getRect(find.byKey(_alsoRow));
      final pick = tester.getRect(find.byKey(_pickRow));
      expect(a.top, moreOrLessEquals(b.top), reason: why);
      expect(a.height, moreOrLessEquals(b.height), reason: why);
      expect(b.right, lessThanOrEqualTo(375), reason: why);
      expect(pick.top, greaterThan(a.bottom), reason: why);
      expect(pick.width, moreOrLessEquals(b.right - a.left), reason: why);
      expect(
          find.descendant(
              of: find.byKey(_pickRow),
              matching: find.text(l10n.sendAnInvestmentOrPrediction)),
          findsOneWidget,
          reason: why);
      expect(
          find.descendant(
              of: find.byKey(_pickRow),
              matching: find.text(l10n.sendPickCardSub)),
          findsOneWidget,
          reason: why);
      for (final (key, box) in [
        (_bitcoinRow, a),
        (_alsoRow, b),
        (_pickRow, pick),
      ]) {
        final texts = find.descendant(
            of: find.byKey(key), matching: find.byType(RichText));
        for (var i = 0; i < texts.evaluate().length; i++) {
          final p = tester.renderObject<RenderParagraph>(texts.at(i));
          expect(p.didExceedMaxLines, isFalse, reason: '$why: a line is cut');
          final shown = tester.getRect(texts.at(i));
          expect(shown.right, lessThanOrEqualTo(box.right + 0.5),
              reason: why);
          expect(shown.bottom, lessThanOrEqualTo(box.bottom + 0.5),
              reason: '$why: a line runs past its card');
        }
      }
      await _unmount(tester);
    }
  });
}
