// The Dollars Send (the Bitcoin send's layout; founder, 1 November 2026;
// the approved hierarchy, 6 November 2026: "one question per level, people
// first"): "Send dollars", the search field ("Name, address or phone"),
// Frequent (the people), then under a small "More ways to send" label ONE
// row of small equal chips: "To your Bitcoin" (the Move money sheet,
// Dollars to Bitcoin), "Crypto address" (the coin sheet) and "Prediction"
// (the market search); no "Send to anyone" (a contact or a typed number
// sends by link); then All contacts. A typed address resolves first and
// the bar's Continue opens the dollar send on it; an address several
// networks take asks which one in the highlighted row; a send that went
// out, or a link created, closes the sheet. Nothing here reaches a money
// call: every door is a test seam.

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
    show SendToListCard, SendToListRow;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show
        SendCoinStack,
        SendSalShareGlyph,
        SendWayChip,
        SendWaysRow,
        kSendWayChipGap;
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

/// Every line break of the [RichText]s under [of] falls at a space, after a
/// hyphen or a slash ("Forudsigelse/investering") or inside Japanese: never
/// inside a word.
void _expectNoBrokenWord(WidgetTester tester, Finder of, String why) {
  final texts = find.descendant(of: of, matching: find.byType(RichText));
  final cjk = RegExp(r'[\u3000-\u9fff\uff00-\uffef]');
  for (var i = 0; i < texts.evaluate().length; i++) {
    final p = tester.renderObject<RenderParagraph>(texts.at(i));
    expect(p.didExceedMaxLines, isFalse, reason: '$why: a label is cut');
    final text = p.text.toPlainText();
    // The paragraph's own lines, laid out again as it laid them out.
    final painter = TextPainter(
      text: p.text,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
    )..layout(maxWidth: p.constraints.maxWidth);
    addTearDown(painter.dispose);
    var offset = 0;
    while (offset < text.length) {
      final line = painter.getLineBoundary(TextPosition(offset: offset));
      if (line.end <= offset) break;
      final next = line.end;
      if (next < text.length) {
        final before = text[next - 1];
        final after = text[next];
        expect(
            before.trim().isEmpty ||
                after.trim().isEmpty ||
                before == '-' ||
                before == '/' ||
                cjk.hasMatch(before),
            isTrue,
            reason: '$why: "$text" breaks inside a word');
      }
      offset = next;
      while (offset < text.length && text[offset].trim().isEmpty) {
        offset++;
      }
    }
  }
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
        'one question per level, people first: "Send dollars", the search '
        'field, then under a small "More ways to send" label ONE row of '
        'three small equal chips (To your Bitcoin, Crypto address, '
        'Prediction), then the Contacts; no big card grid, no "Send to" '
        'label, no Send to anyone, no inline grid '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      // The app's own type: the labels are measured in it.
      await tester.runAsync(_loadInter);
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
      // One small label over the chips; the old "Send to" grid is gone.
      expect(find.text(_l10n.sendMoreWaysToSend), findsOneWidget);
      expect(find.text(_l10n.sendToLabel), findsNothing);
      expect(find.text(_l10n.sendToAFriendLabel), findsNothing);
      expect(find.byType(KuteActionCardGrid), findsNothing);
      expect(find.byType(KuteActionCard), findsNothing);

      final row = find.byKey(const ValueKey('usd-withdraw-options'));
      expect(row, findsOneWidget);
      expect(tester.widget<SendWaysRow>(row).chips.map((c) => c.key),
          [_bitcoinRow, _alsoRow, _pickRow]);
      // No Send to anyone (founder, 5 November 2026: "makes no sense since
      // we have phone numbers"): a contact or a typed number sends by link.
      expect(find.byKey(_anyoneRow), findsNothing);
      expect(find.text(_l10n.shareSendToAnyone), findsNothing);
      expect(find.byType(SendSalShareGlyph), findsNothing);
      // Chips, none of the old list rows (the Contacts' own ask row is the
      // only one left).
      expect(
          find.byWidgetPredicate((w) =>
              w is SendToListRow &&
              w.key != const ValueKey('send-contacts-ask-row')),
          findsNothing);
      SendWayChip chip(Key key) => tester.widget<SendWayChip>(find.byKey(key));
      expect(chip(_bitcoinRow).label, _l10n.usdSendToYourBitcoin);
      expect(chip(_bitcoinRow).icon, isA<SvgPicture>());
      // The balance is read out, not printed: the chips stay equal.
      expect(chip(_bitcoinRow).semanticsLabel,
          '${_l10n.usdSendToYourBitcoin}, ${_l10n.usdBitcoinBalanceLine('\$60.00')}');
      expect(chip(_alsoRow).label, _l10n.sendWayCryptoAddress);
      expect(chip(_alsoRow).label, 'Crypto address');
      expect(chip(_alsoRow).icon, isA<SendCoinStack>());
      expect(chip(_alsoRow).semanticsLabel,
          '${_l10n.sendToCryptoAddress}, ${_l10n.sendAlsoSendsToList('USDC', 'USDT')}');
      expect(chip(_pickRow).label, _l10n.sendWayPrediction);
      expect(chip(_pickRow).label, 'Prediction or investment');
      expect(chip(_pickRow).semanticsLabel, _l10n.sendAnInvestmentOrPrediction);
      expect(chip(_pickRow).icon, isA<SearchChanceGauge>());

      // ONE row: the three side by side, left to right, equally wide and
      // tall, a third of the field's width each; no chevrons, no lines
      // under the labels.
      Rect r(Key key) => tester.getRect(find.byKey(key));
      final field =
          tester.getRect(find.byKey(const ValueKey('send-recipient-search')));
      final third = (field.width - 2 * kSendWayChipGap.w) / 3;
      for (final key in [_bitcoinRow, _alsoRow, _pickRow]) {
        expect(r(key).top, moreOrLessEquals(r(_bitcoinRow).top));
        expect(r(key).height, moreOrLessEquals(r(_bitcoinRow).height));
        expect(r(key).width, moreOrLessEquals(third, epsilon: 0.5));
        expect(
            find.descendant(
                of: find.byKey(key),
                matching: find.byIcon(Icons.chevron_right_rounded)),
            findsNothing);
      }
      expect(r(_bitcoinRow).left, moreOrLessEquals(field.left, epsilon: 0.5));
      expect(r(_bitcoinRow).right, lessThan(r(_alsoRow).left));
      expect(r(_alsoRow).right, lessThan(r(_pickRow).left));
      expect(r(_pickRow).right, moreOrLessEquals(field.right, epsilon: 0.5));
      // Compact: clearly smaller than the old squares.
      expect(r(_bitcoinRow).height, lessThan(100));
      expect(find.byKey(const ValueKey('send-ways-scroll')), findsNothing);
      // Top to bottom: the field, the label, the chips, the Contacts.
      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(top(find.byKey(const ValueKey('send-recipient-search'))),
          lessThan(top(find.text(_l10n.sendMoreWaysToSend))));
      expect(top(find.text(_l10n.sendMoreWaysToSend)),
          lessThan(r(_bitcoinRow).top));
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
      'Predictions and Investing closed to this person: no Prediction chip '
      '(its slip could only send the market\'s card); the other two share '
      'the row, half each, no empty third slot', (tester) async {
    final closed = runtimePolicyFixture(
        blocked: const {'polymarket.trade', 'hyperliquid.trade'},
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = closed;
    await tester.runAsync(closed.refresh);
    await tester.runAsync(_loadInter);
    await _pump(tester, spendingSats: 100000);
    expect(find.byKey(_pickRow), findsNothing);
    expect(find.byKey(_anyoneRow), findsNothing);
    for (final key in [_bitcoinRow, _alsoRow]) {
      expect(find.byKey(key), findsOneWidget);
    }
    final a = tester.getRect(find.byKey(_bitcoinRow));
    final b = tester.getRect(find.byKey(_alsoRow));
    final field =
        tester.getRect(find.byKey(const ValueKey('send-recipient-search')));
    expect(a.top, moreOrLessEquals(b.top));
    expect(a.height, moreOrLessEquals(b.height));
    expect(a.left, moreOrLessEquals(field.left, epsilon: 0.5));
    expect(b.right, moreOrLessEquals(field.right, epsilon: 0.5));
    for (final chip in [a, b]) {
      expect(chip.width,
          moreOrLessEquals((field.width - kSendWayChipGap.w) / 2,
              epsilon: 0.5));
    }
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt and a large text the chips never cut a word: the row '
      'scrolls sideways when the labels outgrow a third, nothing overflows',
      (tester) async {
    await tester.runAsync(_loadInter);
    await _pump(tester, spendingSats: 100000);
    tester.view.physicalSize = const Size(375, 667);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('send-ways-scroll')), findsOneWidget);
    for (final key in [_bitcoinRow, _alsoRow, _pickRow]) {
      _expectNoBrokenWord(tester, find.byKey(key), 'text x2');
    }
    final a = tester.getRect(find.byKey(_bitcoinRow));
    for (final key in [_alsoRow, _pickRow]) {
      expect(tester.getRect(find.byKey(key)).width,
          moreOrLessEquals(a.width));
      expect(tester.getRect(find.byKey(key)).top, moreOrLessEquals(a.top));
    }
    await _unmount(tester);
  });

  testWidgets(
      'people first: search < Frequent < the More ways to send chips < All '
      'contacts; typing hides Frequent',
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
    final label = find.text(_l10n.sendMoreWaysToSend);
    expect(tester.getBottomLeft(find.byKey(frequent)).dy,
        lessThanOrEqualTo(top(label)));
    expect(tester.getBottomLeft(label).dy,
        lessThanOrEqualTo(top(find.byKey(_bitcoinRow))));
    for (final key in [_bitcoinRow, _alsoRow, _pickRow]) {
      expect(tester.getBottomLeft(find.byKey(key)).dy,
          lessThan(top(find.byKey(const ValueKey('send-contacts-ask-row')))));
    }
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

  testWidgets(
      'To your Bitcoin opens Move money straight on the amount: Dollars to '
      'Bitcoin, pinned, nothing to pick in between', (tester) async {
    UsdWithdrawScreen.debugMoveSheetOpener = null;
    final moves = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    addTearDown(() => debugMoneyMovementSheetOpener = null);
    await _pump(tester, spendingSats: 100000);
    await tester.tap(find.byKey(_bitcoinRow));
    await tester.pump();
    expect(moves, hasLength(1));
    expect(moves.single.route,
        const MoneyMovementRoute(MoneyMovementAccount.dollars,
            MoneyMovementAccount.bitcoin));
    expect(moves.single.pinned, isTrue);
    expect(moves.single.entrySource, kUsdWithdrawBitcoinRowSource);
    expect(find.byType(UsdWithdrawScreen), findsOneWidget);
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
    // One recipient card: the chips are hidden meanwhile.
    expect(find.text(_l10n.sendRecipientSendingTo), findsOneWidget);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_l10n.sendMoreWaysToSend), findsNothing);
    expect(_primaryScopes(), hasLength(1));
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    kuteBarPrimaryContext(tester).onPrimary!();
    await _settle(tester);
    expect(sendsOpened, [('tron:USDT', tron)]);
    // Change empties the field and brings the chips back.
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
    // The highlighted row (the stronger border), right under the field.
    expect(
        tester
            .widget<SendToListCard>(find.ancestor(
                of: pick, matching: find.byType(SendToListCard)))
            .emphasized,
        isTrue);
    expect(tester.getTopLeft(pick).dy,
        lessThan(tester.getTopLeft(find.byKey(_bitcoinRow)).dy));
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
      'nothing offered: To your Bitcoin and Prediction or investment stay, '
      'two chips sharing the row, no address chip, the unavailable line '
      'under them',
      (tester) async {
    await _pump(tester, coins: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.byKey(_anyoneRow), findsNothing);
    expect(find.byKey(_pickRow), findsOneWidget);
    expect(find.byKey(_alsoRow), findsNothing);
    expect(
        tester
            .widget<SendWaysRow>(
                find.byKey(const ValueKey('usd-withdraw-options')))
            .chips,
        hasLength(2));
    expect(tester.getRect(find.byKey(_pickRow)).top,
        moreOrLessEquals(tester.getRect(find.byKey(_bitcoinRow)).top));
    expect(tester.getRect(find.byKey(_pickRow)).width,
        moreOrLessEquals(tester.getRect(find.byKey(_bitcoinRow)).width));
    expect(tester.getRect(find.byKey(_pickRow)).height,
        moreOrLessEquals(tester.getRect(find.byKey(_bitcoinRow)).height));
    expect(find.text(_l10n.usdSendDestinationsUnavailable), findsOneWidget);
    expect(
        tester.getTopLeft(find.text(_l10n.usdSendDestinationsUnavailable)).dy,
        greaterThan(tester.getRect(find.byKey(_pickRow)).bottom));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: the three chips fit '
      'across in one row (no sideways scroll), equal, every word whole '
      'inside its chip, nothing overflowing', (tester) async {
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
      expect(find.byKey(const ValueKey('send-ways-scroll')), findsNothing,
          reason: '$why: the chips do not fit across');
      expect(find.text(l10n.sendMoreWaysToSend), findsOneWidget, reason: why);
      final a = tester.getRect(find.byKey(_bitcoinRow));
      final b = tester.getRect(find.byKey(_alsoRow));
      final pick = tester.getRect(find.byKey(_pickRow));
      for (final box in [b, pick]) {
        expect(box.top, moreOrLessEquals(a.top), reason: why);
        expect(box.height, moreOrLessEquals(a.height), reason: why);
        expect(box.width, moreOrLessEquals(a.width), reason: why);
      }
      expect(pick.right, lessThanOrEqualTo(375), reason: why);
      for (final (key, label) in [
        (_bitcoinRow, l10n.usdSendToYourBitcoin),
        (_alsoRow, l10n.sendWayCryptoAddress),
        (_pickRow, l10n.sendWayPrediction),
      ]) {
        expect(
            find.descendant(of: find.byKey(key), matching: find.text(label)),
            findsOneWidget,
            reason: why);
        _expectNoBrokenWord(tester, find.byKey(key), why);
        final box = tester.getRect(find.byKey(key));
        final texts = find.descendant(
            of: find.byKey(key), matching: find.byType(RichText));
        for (var i = 0; i < texts.evaluate().length; i++) {
          final shown = tester.getRect(texts.at(i));
          expect(shown.right, lessThanOrEqualTo(box.right + 0.5),
              reason: why);
          expect(shown.bottom, lessThanOrEqualTo(box.bottom + 0.5),
              reason: '$why: a line runs past its chip');
        }
      }
      await _unmount(tester);
    }
  });
}
