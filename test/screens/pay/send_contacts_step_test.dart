// The Bitcoin Send's Who step (send_recipient_step.dart) with CONTACTS
// LIKE REVOLUT (founder, 1 November 2026; send_contacts_list.dart) and the
// approved Send (founder, 7 November 2026: "ok do it, just make sure that
// people realise they can send to different cryptos also"):
//
//   * the search field takes everything ("Name, phone or any crypto
//     address": Lightning addresses of any domain, invoices, bitcoin and
//     crypto addresses, Paste and Scan); while it is empty a quiet line
//     under it names the coins ("Send to Bitcoin, USDC, USD and USDT") and
//     opens the "Where to?" sheet as a browse list, gone when no coin can
//     be offered;
//   * NO CHIPS: no "To your Dollars", no "Crypto address", no "Prediction
//     or investment". Typed, an own account's name finds the move ("Move to
//     your Dollars");
//   * a paste goes straight on: a bitcoin address to the amount, a 0x
//     address to the network question ("Where to?" filtered to it);
//   * a person (a contact, a typed number) is asked What (send_what_step
//     .dart), on the app's cards with no toggle: this Send's Bitcoin (a
//     Kute contact paid at their address, anyone else by link), or a
//     prediction or investment (the search in send mode, the person
//     prefilled); the floating bar is the sheet's Back.

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' show Contact;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/balance_model.dart' show WalletBalance;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/balance_provider.dart'
    show WalletBalanceCacheNotifier, walletBalanceCacheProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart' show CoinAssetTile;
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard;
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show
        MoneyMovementAccount,
        MoneyMovementRequest,
        MoneyMovementRoute,
        debugMoneyMovementSheetOpener;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendCoinStack, SendCryptoHint;
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet, kSendWhatGiftKey, kSendWhatMoneyKey;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePillTabs;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard, KuteActionCardGrid, KuteActionCardIcon;
import 'package:kute/screens/search/components/search_rows.dart'
    show SearchChanceGauge;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/spark_contacts_fixtures.dart';
import '../../mocks/fake_send_contacts_gateway.dart';
import '../../mocks/fake_share_links_api.dart';

final _l10n = AppLocalizationsEn();

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
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );

late FakeSendContactsGateway _gateway;
late FakeShareLinksApi _api;
late List<(String, Map<String, Object>?)> _events;

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

/// A live routes catalogue, for the coin picker; [wide] as wide as the
/// real one (USDC, USDT and ETH first, and nineteen coins more).
OrchestraRoutesCatalog _catalog({bool wide = false}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('arbitrum', 'USDC'),
          _row('base', 'USDC'),
          _row('tron', 'USDT'),
          if (wide) ...[
            for (final chain in ['ethereum', 'optimism', 'polygon', 'solana'])
              _row(chain, 'USDC'),
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
      fetchedAt: DateTime(2026, 10, 31),
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

/// The spending wallet's balances, as given.
class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

/// Lightning addresses this wallet paid (the Frequent row).
class _Paid extends SparkContactsNotifier {
  @override
  Future<List<Contact>> build() async => [
        contact('rita@paykute.com', 300),
        contact('alice@getalby.com', 200),
      ];
}

Future<void> _pump(WidgetTester tester,
    {bool catalog = false,
    bool wide = false,
    bool recents = false,
    int? spendingSats,
    Locale? locale,
    Size size = const Size(375, 812)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.pushNamed('pay_send'),
            child: const Text('Open send'),
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
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sendContactsGatewayProvider.overrideWithValue(_gateway),
      shareLinksApiProvider.overrideWithValue(_api),
      if (recents) sparkContactsProvider.overrideWith(_Paid.new),
      if (spendingSats != null)
        walletBalanceCacheProvider.overrideWith((_) => _Balances({
              'spending': WalletBalance(
                  onChainBtcBalance: 0, sparkBitcoinbalance: spendingSats),
            })),
      if (catalog || wide) ...[
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog(wide: wide))),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
      ],
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
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open send'));
  await tester.pumpAndSettle();
  expect(find.byType(ConfirmSend), findsOneWidget);
}

/// A text on the step, under the fold of the medium sheet or not.
Finder _text(String text) => find.text(text, skipOffstage: false);

Iterable<Map<String, Object>?> _paramsOf(String event) =>
    _events.where((e) => e.$1 == event).map((e) => e.$2);

/// The app's own type, Inter: the hint's line is measured in it.
Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// The clipboard holds [text] (Paste reads it).
void _clipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return {'text': text};
    if (call.method == 'Clipboard.hasStrings') return {'value': true};
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

/// The stepper's page (0 Send to, 1 Amount, 2 Review).
double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

/// The destination the send holds (the field's, kept by the provider once
/// Send to has scrolled away).
String _address(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(ConfirmSend)))
    .read(sendTxProvider)
    .address;

const _hint = ValueKey('send-crypto-hint');
const _field = ValueKey('send-recipient-search');
const _evm = '0x742d35cc6634c0532925a3b844bc454e4438f44e';
const _btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

/// The keys and words of the chips this step no longer has.
const _oldChips = [
  ValueKey('send-to-options'),
  ValueKey('send-to-dollars'),
  ValueKey('send-also-sends-to-row'),
  ValueKey('send-pick'),
];
const _oldChipWords = [
  'More ways to send',
  'To your Dollars',
  'Crypto address',
  'Prediction or investment',
];

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_contacts_step');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // No sprite sheets: a decoded loop would tick for ever under
    // pumpAndSettle; the glyphs fall back to their icons.
    SalSpriteCache.debugSetManifest(null);
    _gateway = FakeSendContactsGateway(contacts: fakeContacts());
    _api = FakeShareLinksApi();
    _events = [];
    TrackingService.debugTrackObserver = (e, p) => _events.add((e, p));
    ShareLinksStore.debugMemory = <String, String>{};
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SalSpriteCache.debugReset();
    ShareLinksStore.debugMemory = null;
    ConfirmSend.debugPickOpener = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  /// A loaded policy (with none the swap gates fail closed and no coin is
  /// offered); [also] adds the venues' browse capabilities.
  Future<void> policy(WidgetTester tester,
      {Set<String> blocked = const {}, bool venues = true}) async {
    AffiliateService.debugSessionToken = 'test-session';
    final p = runtimePolicyFixture(
        blocked: blocked,
        also: venues
            ? const {'polymarket.browse', 'hyperliquid.browse'}
            : const {});
    RuntimeCapabilitiesService.debugInstance = p;
    await tester.runAsync(p.refresh);
  }

  const ask = ValueKey('send-contacts-ask-row');
  Finder person(String id) =>
      find.byKey(ValueKey('send-person-contact:$id'), skipOffstage: false);

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
  }

  Future<void> tapPerson(WidgetTester tester, String id) async {
    await tester.ensureVisible(person(id));
    await tester.pumpAndSettle();
    await tester.tap(person(id));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the step: "Send", the search field saying it takes any crypto '
      'address, Paste and Scan, the Contacts with "See your contacts" '
      'first; no chips and no "Send to a friend" row', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.send), findsOneWidget);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(find.byType(StepperProgress), findsNothing);
    expect(find.byKey(_field), findsOneWidget);
    expect(find.text(_l10n.sendRecipientSearchHint), findsOneWidget);
    expect(_l10n.sendRecipientSearchHint, 'Name, phone or any crypto address');
    expect(find.byKey(const ValueKey('send-field-paste')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-field-scan')), findsOneWidget);
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(ask), findsOneWidget);
    expect(_text(_l10n.sendContactsSeeYours), findsOneWidget);
    expect(find.byKey(const ValueKey('send-to-friend-row')), findsNothing);
    expect(find.byKey(const ValueKey('send-pick-market-row')), findsNothing);
    expect(find.byType(KuteActionCardGrid), findsNothing);
    for (final key in _oldChips) {
      expect(find.byKey(key, skipOffstage: false), findsNothing);
    }
    // No catalogue: no coin to offer, so no hint (it would open empty).
    expect(find.byKey(_hint), findsNothing);
    // Never a prompt on open.
    expect(_gateway.prompts, 0);
  });

  testWidgets(
      'no own-account, crypto or prediction chips, whatever is offered: the '
      'crypto hint is the one line under the field', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true, recents: true);
    for (final key in _oldChips) {
      expect(find.byKey(key, skipOffstage: false), findsNothing);
    }
    for (final words in _oldChipWords) {
      expect(_text(words), findsNothing, reason: words);
    }
    expect(find.byKey(_hint), findsOneWidget);
    expect(find.byKey(const ValueKey('send-move-results')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'people first: search < the crypto hint < Frequent < All contacts; '
      'typing hides Frequent and the hint', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true, recents: true);
    const frequent = ValueKey('send-frequent-section');
    expect(find.byKey(frequent), findsOneWidget);
    expect(find.byKey(const ValueKey('send-frequent-recent:rita@paykute.com')),
        findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    double bottom(Finder f) => tester.getBottomLeft(f).dy;
    expect(bottom(find.byKey(_field)),
        lessThanOrEqualTo(top(find.byKey(_hint)) + 0.01));
    expect(bottom(find.byKey(_hint)),
        lessThanOrEqualTo(top(find.byKey(frequent)) + 0.01));
    expect(bottom(find.byKey(frequent)), lessThan(top(find.byKey(ask))));
    // Once only: the Contacts below never repeat it.
    expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);

    await type(tester, 'ri');
    expect(find.byKey(frequent), findsNothing);
    expect(find.byKey(_hint), findsNothing);
  });

  testWidgets(
      'the crypto hint: the coins stacked as the Receive card stacks them '
      'and "Send to Bitcoin, USDC, USD and USDT"; read out whole',
      (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    final hint = find.byKey(_hint);
    expect(
        find.descendant(of: hint, matching: find.byType(SendCoinStack)),
        findsOneWidget);
    final line =
        tester.widget<Text>(find.byKey(const ValueKey('send-crypto-hint-line')));
    expect(line.data,
        _l10n.sendCryptoHint(_l10n.sendAlsoSendsToList('Bitcoin, USDC, USD', 'USDT')));
    expect(line.data, 'Send to Bitcoin, USDC, USD and USDT');
    expect(line.maxLines, 1);
    expect(tester.getSemantics(hint),
        matchesSemantics(label: line.data, isButton: true, hasTapAction: true));
  });

  testWidgets(
      'with the wide catalogue: "Send to Bitcoin, USDC, USDT, ETH and 18 '
      'more", the count from the same coins the sheet lists', (tester) async {
    await policy(tester);
    await _pump(tester, wide: true);
    final line =
        tester.widget<Text>(find.byKey(const ValueKey('send-crypto-hint-line')));
    expect(line.data, 'Send to Bitcoin, USDC, USDT, ETH and 19 more');
    await tester.tap(find.byKey(_hint));
    await tester.pumpAndSettle();
    // Bitcoin's own Dollars row (USD) is a coin of the sheet too: 22 coins,
    // three named, nineteen more.
    expect(find.byType(CoinAssetTile), findsNWidgets(22));
  });

  testWidgets(
      'the hint opens "Where to?" as a browse list of the coins only (no '
      'Bitcoin Network row), tracked as the crypto hint; a coin picked '
      'turns the field into its address field', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    await _pump(tester, catalog: true);
    expect(person('c1'), findsOneWidget);
    await tester.tap(find.byKey(_hint));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendWhereTo), findsOneWidget);
    expect(find.text(_l10n.sendWhereShouldTheMoneyLand), findsOneWidget);
    expect(find.text(_l10n.bitcoinNetwork), findsNothing);
    expect(find.text(_l10n.bitcoinLightningSpark), findsNothing);
    expect(find.byType(PickerRow), findsNothing);
    expect(
        tester
            .widgetList<CoinAssetTile>(find.byType(CoinAssetTile))
            .map((t) => t.label)
            .toList(),
        ['USDC', 'USD', 'USDT']);
    expect(_paramsOf('send_asset_shortcut_tapped').single,
        {'asset_code': 'other', 'flow': 'send', 'source': 'crypto_hint'});

    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
    await tester.pumpAndSettle();
    // Two networks: which one.
    await tester.tap(find.text('base').first);
    await tester.pumpAndSettle();
    // The field's hint is that coin's address now; no Contacts, no hint.
    expect(find.text(_l10n.sendAssetOnNetworkAddressHint('USDC', 'base')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-section')), findsNothing);
    expect(person('c1'), findsNothing);
    expect(find.byKey(_hint), findsNothing);
    final coin = find.byKey(const ValueKey('send-to-coin-card'));
    expect(coin, findsOneWidget);
    expect(tester.widget<SendToListCard>(coin).emphasized, isFalse);
    final change = find.byKey(const ValueKey('send-to-coin-change'));
    expect(find.descendant(of: coin, matching: change), findsOneWidget);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(person('c1'), findsOneWidget);
    expect(find.byKey(_hint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'no coin offered under the policy (the swap switched off): no hint, '
      'never an empty sheet; the field still takes bitcoin', (tester) async {
    await policy(tester, blocked: const {'orchestra.swap'});
    await _pump(tester, catalog: true);
    expect(find.byKey(_hint), findsNothing);
    expect(find.byType(SendCryptoHint), findsNothing);
    expect(find.text(_l10n.sendWhereTo), findsNothing);
    await type(tester, _btc);
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
  });

  testWidgets(
      'No "To a friend · Send to anyone" card on a bitcoin send (founder, 5 '
      'November 2026: a contact or a typed phone number is a person)',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('send-friend-card')), findsNothing);
    expect(find.byKey(const ValueKey('send-to-anyone-row')), findsNothing);
    expect(_text(_l10n.shareSendToAnyone), findsNothing);
    expect(find.byKey(ask), findsOneWidget);
  });

  testWidgets(
      '"See your contacts" prompts on tap only; granted, the book is the '
      'list, plain contacts with no badge', (tester) async {
    await _pump(tester);
    expect(_text('Maria Alves'), findsNothing);
    await tester.tap(find.byKey(ask));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 1);
    expect(_paramsOf('send_contacts_permission').single,
        containsPair('granted', true));
    expect(find.byKey(ask), findsNothing);
    expect(person('c1'), findsOneWidget);
    expect(person('c2'), findsOneWidget);
    expect(person('c3'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-badge-kute'), skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('send-badge-lightning'), skipOffstage: false),
        findsNothing);
  });

  testWidgets('refused for good: the row offers Settings, no prompt',
      (tester) async {
    _gateway.permission = SendContactsPermission.blocked;
    await _pump(tester);
    expect(_text(_l10n.sendAllowContactsInSettings), findsOneWidget);
    await tester.tap(find.byKey(ask));
    await tester.pumpAndSettle();
    expect(_gateway.settingsOpened, 1);
    expect(_gateway.prompts, 0);
  });

  testWidgets(
      'a non-Kute contact becomes a link: the text filters by name and by '
      'number; the contact asks What, this Send\'s Bitcoin, and Bitcoin '
      'opens Send to anyone in bitcoin with the first name, the number '
      'staying on the phone', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    await _pump(tester);
    expect(person('c2'), findsOneWidget);

    await type(tester, 'mar');
    expect(person('c2'), findsOneWidget);
    expect(person('c1'), findsNothing);
    expect(person('c3'), findsNothing);

    await type(tester, '913');
    expect(person('c3'), findsOneWidget);
    expect(person('c2'), findsNothing);

    await type(tester, 'mar');
    await tapPerson(tester, 'c2');
    expect(find.byType(SendWhatSheet), findsOneWidget);
    expect(find.text(_l10n.sendWhatTitle('Maria Alves')), findsOneWidget);
    expect(find.text(_l10n.sendWhatSubtitle), findsOneWidget);
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    await tester.tap(find.byKey(kSendWhatMoneyKey));
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'contact'));
    expect(_paramsOf('send_what_picked').single,
        {'what': 'money', 'home': 'bitcoin', 'from': 'bitcoin'});
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.kind, ShareLinkKind.bitcoin);
    expect(sheet.senderLabel, 'Maria');
    expect(sheet.recipientPhone, '+351 912 345 678');
    for (final e in _events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
  });

  testWidgets(
      'the What step on the Bitcoin Send: no toggle and no Dollars, the '
      'Bitcoin card (its mark, "Bitcoin", the sats available line) and the '
      'gift on the app\'s cards, the gift glyph not the gauge; the bar is '
      'Back, which closes it with no answer', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    await _pump(tester, spendingSats: 328686);
    await tapPerson(tester, 'c2');
    final sheet = find.byType(SendWhatSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    // The money is the Send's own: no From, no toggle, no Dollars, no
    // "Money".
    expect(inSheet(find.byType(KutePillTabs)), findsNothing);
    expect(inSheet(find.text(_l10n.portfolioBalanceDollars)), findsNothing);
    expect(inSheet(find.text('Money')), findsNothing);
    expect(inSheet(find.text('From')), findsNothing);
    // Two of the app's cards, laid out by the grid.
    expect(inSheet(find.byType(KuteActionCardGrid)), findsOneWidget);
    expect(inSheet(find.byType(KuteActionCard)), findsNWidgets(2));
    final money = find.byKey(kSendWhatMoneyKey);
    expect(
        find.descendant(of: money, matching: find.text(_l10n.bitcoin)),
        findsOneWidget);
    expect(
        find.descendant(
            of: money, matching: find.textContaining('328,686 sats available')),
        findsOneWidget);
    final gift = find.byKey(kSendWhatGiftKey);
    expect(find.descendant(of: gift, matching: find.text(_l10n.sendWhatGift)),
        findsOneWidget);
    expect(
        find.descendant(
            of: gift, matching: find.text(_l10n.sendToAFriendSub)),
        findsOneWidget);
    expect(
        tester
            .widget<KuteActionCardIcon>(find.descendant(
                of: gift, matching: find.byType(KuteActionCardIcon)))
            .icon,
        Icons.card_giftcard_rounded);
    expect(inSheet(find.byType(SearchChanceGauge)), findsNothing);
    // "A prediction or investment" never reads on one line at half the
    // width: two compact full-width cards, one over the other.
    expect(tester.getSize(money).width,
        moreOrLessEquals(tester.getSize(gift).width));
    expect(tester.getTopLeft(gift).dy,
        greaterThan(tester.getBottomLeft(money).dy));

    // The bar is the sheet's Back (Sal's face on it), clear of the cards.
    expect(kuteBarPrimaryWithText(_l10n.back), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    expect(tester.getRect(gift).bottom,
        lessThanOrEqualTo(tester.getRect(kuteBarPrimary).top));
    await tester.tap(kuteBarPrimary);
    await tester.pumpAndSettle();
    expect(find.byType(SendWhatSheet), findsNothing);
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(_paramsOf('send_what_picked'), isEmpty);
    expect(kuteBarPrimaryWithText(_l10n.back), findsNothing);
    expect(_page(tester), moreOrLessEquals(0));
  });

  testWidgets(
      'the What step\'s gift path opens the search in send mode with the '
      'contact; a link created closes the send', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    final picks = <(String?, String?)>[];
    var created = false;
    ConfirmSend.debugPickOpener = (_, {senderLabel, recipientPhone}) async {
      picks.add((senderLabel, recipientPhone));
      return created;
    };
    await _pump(tester);
    await tapPerson(tester, 'c2');
    expect(find.text(_l10n.sendWhatGift), findsOneWidget);
    await tester.tap(find.byKey(kSendWhatGiftKey));
    await tester.pumpAndSettle();
    expect(picks, [('Maria', '+351 912 345 678')]);
    expect(_paramsOf('send_what_picked').single,
        {'what': 'gift', 'home': 'bitcoin'});
    // Closed without a link: the send stays.
    expect(find.byType(ConfirmSend), findsOneWidget);
    created = true;
    await tapPerson(tester, 'c2');
    await tester.tap(find.byKey(kSendWhatGiftKey));
    await tester.pumpAndSettle();
    expect(picks, hasLength(2));
    expect(find.byType(ConfirmSend), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Predictions and Investing closed to this person: the What step has '
      'no gift, Money only', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester,
        blocked: const {'polymarket.trade', 'hyperliquid.trade'});
    await _pump(tester);
    await tapPerson(tester, 'c2');
    expect(find.byKey(kSendWhatMoneyKey), findsOneWidget);
    expect(find.byKey(kSendWhatGiftKey), findsNothing);
  });

  testWidgets(
      'a contact with a Kute Lightning address wears the Kute badge; Money '
      'from Bitcoin pays them directly: the address fills the field and the '
      'send goes on to the amount', (tester) async {
    _gateway
      ..permission = SendContactsPermission.granted
      ..contacts = [
        ...fakeContacts(),
        const SendContact(
            id: 'k1',
            displayName: 'Joana Kute',
            firstName: 'Joana',
            phone: '+351 914 444 444',
            lightningAddress: 'joana@paykute.com'),
      ];
    await policy(tester);
    await _pump(tester);
    expect(
        find.descendant(
            of: person('k1'),
            matching: find.byKey(const ValueKey('send-badge-kute'))),
        findsOneWidget);
    await tapPerson(tester, 'k1');
    await tester.tap(find.byKey(kSendWhatMoneyKey));
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(_address(tester), 'joana@paykute.com');
    expect(_page(tester), moreOrLessEquals(1));
  });

  testWidgets(
      'a resolved destination is ONE recipient card: the contact named, not '
      'listed again, no rail chip (Lightning or on-chain waits for Review), '
      'the hint hidden; Change brings both back', (tester) async {
    _gateway
      ..permission = SendContactsPermission.granted
      ..contacts = [
        ...fakeContacts(),
        const SendContact(
            id: 'k1',
            displayName: 'Joana Kute',
            firstName: 'Joana',
            phone: '+351 914 444 444',
            lightningAddress: 'joana@paykute.com'),
      ];
    await policy(tester);
    await _pump(tester, catalog: true);
    expect(find.byKey(_hint), findsOneWidget);
    await type(tester, 'joana@paykute.com');
    final card = find.byKey(const ValueKey('send-recipient-card'));
    expect(card, findsOneWidget);
    expect(_text(_l10n.sendRecipientSendingTo), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('send-recipient-name')))
            .data,
        'Joana Kute');
    expect(
        find.descendant(
            of: card, matching: find.byKey(const ValueKey('send-badge-kute'))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-recipient-rail')), findsNothing);
    expect(find.text(_l10n.sendRailLightning), findsNothing);
    // Not twice: the list drops her and reads "Other contacts".
    expect(find.byKey(const ValueKey('send-person-contact:k1')), findsNothing);
    expect(person('c1'), findsOneWidget);
    expect(_text(_l10n.sendOtherContacts), findsOneWidget);
    expect(find.byKey(_hint), findsNothing);
    // Typed, it waits for the bar: Continue.
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    expect(_page(tester), 0);

    await tester.tap(find.byKey(const ValueKey('send-recipient-change')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(card, findsNothing);
    expect(find.byKey(_hint), findsOneWidget);
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(const ValueKey('send-person-contact:k1'),
            skipOffstage: false),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a typed 0x address several networks take asks in the highlighted row '
      'right under the field, the hint gone; cleared, it comes back',
      (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    await type(tester, _evm);
    expect(find.byKey(_hint), findsNothing);
    final question = _text(_l10n.sendWhichNetworkIsThisAddressOn);
    expect(question, findsOneWidget);
    final card =
        find.ancestor(of: question, matching: find.byType(SendToListCard));
    expect(tester.widget<SendToListCard>(card).emphasized, isTrue);
    final field = tester.getRect(find.byKey(_field));
    expect(tester.getRect(card).top - field.bottom, lessThan(16));
    // Typed, nothing opens by itself.
    expect(find.text(_l10n.sendWhereTo), findsNothing);
    await type(tester, '');
    expect(find.byKey(_hint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pasting a bitcoin address goes straight to the amount (the input '
      'decides the rail), tracked as an address', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    _clipboard(tester, _btc);
    await tester.tap(find.byKey(const ValueKey('send-field-paste')));
    await tester.pumpAndSettle();
    expect(_address(tester), _btc);
    expect(_page(tester), moreOrLessEquals(1));
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'address'));
    expect(find.text(_l10n.sendWhereTo), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pasting a 0x address asks for the network: "Where to?" opens on its '
      'own, filtered to what fits the address (USDC on EVM, never USDT on '
      'Tron); the send stays on Who', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    _clipboard(tester, _evm);
    await tester.tap(find.byKey(const ValueKey('send-field-paste')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendWhereTo), findsOneWidget);
    final tiles = tester
        .widgetList<CoinAssetTile>(find.byType(CoinAssetTile))
        .map((t) => t.label)
        .toList();
    expect(tiles, contains('USDC'));
    expect(tiles, isNot(contains('USDT')));
    expect(_page(tester), 0);
    // Closed unanswered, the question stays under the field.
    Navigator.of(tester.element(find.byType(CoinAssetTile).first)).pop();
    await tester.pumpAndSettle();
    expect(_text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '"dollars" in the field shows "Move to your Dollars", which opens Move '
      'money straight on the amount, Bitcoin to Dollars, pinned',
      (tester) async {
    await policy(tester);
    final moves = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    addTearDown(() => debugMoneyMovementSheetOpener = null);
    await _pump(tester, catalog: true);
    await type(tester, 'dollars');
    final row = find.byKey(const ValueKey('send-move-to-dollars'));
    expect(row, findsOneWidget);
    expect(find.text(_l10n.sendMoveToYourDollars), findsOneWidget);
    expect(find.text(_l10n.usdReceiveFromYourBitcoin), findsOneWidget);
    expect(find.byKey(const ValueKey('send-move-to-bitcoin')), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(moves, hasLength(1));
    expect(moves.single.route,
        const MoneyMovementRoute(
            MoneyMovementAccount.bitcoin, MoneyMovementAccount.dollars));
    expect(moves.single.pinned, isTrue);
    expect(moves.single.entrySource, kBitcoinSendSearchSource);
    expect(TrackingService.takeEntrySource('move'), kBitcoinSendSearchSource);
    expect(find.byType(ConfirmSend), findsOneWidget);
  });

  testWidgets(
      '"my bitcoin" finds "Move to your Bitcoin" (Dollars to Bitcoin); a '
      'start of a name ("dol") finds it too; an address or a name finds '
      'nothing', (tester) async {
    await policy(tester);
    final moves = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    addTearDown(() => debugMoneyMovementSheetOpener = null);
    await _pump(tester, catalog: true);
    await type(tester, 'my bitcoin');
    expect(find.byKey(const ValueKey('send-move-to-bitcoin')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-move-to-dollars')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('send-move-to-bitcoin')));
    await tester.pumpAndSettle();
    expect(moves.single.route,
        const MoneyMovementRoute(
            MoneyMovementAccount.dollars, MoneyMovementAccount.bitcoin));

    await type(tester, 'dol');
    expect(find.byKey(const ValueKey('send-move-to-dollars')), findsOneWidget);
    for (final text in ['maria', _evm, 'ri']) {
      await type(tester, text);
      expect(find.byKey(const ValueKey('send-move-results')), findsNothing,
          reason: text);
    }
  });

  testWidgets('the localized account name finds the move ("dólares")',
      (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true, locale: const Locale('pt'));
    await type(tester, 'meus dólares');
    expect(find.byKey(const ValueKey('send-move-to-dollars')), findsOneWidget);
    expect(find.text(l10nForLanguage('pt').sendMoveToYourDollars),
        findsOneWidget);
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: the crypto hint is '
      'one line, never cut, beside its coins, and the field\'s placeholder '
      'is whole', (tester) async {
    await tester.runAsync(_loadInter);
    await policy(tester);
    final cut = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester, locale: locale, wide: true);
      expect(tester.takeException(), isNull, reason: why);
      final hint = find.byKey(_hint);
      expect(hint, findsOneWidget, reason: why);
      final line = find.byKey(const ValueKey('send-crypto-hint-line'));
      expect(tester.widget<Text>(line).data,
          l10n.sendCryptoHintMore('${l10n.bitcoin}, USDC, USDT, ETH', 19),
          reason: why);
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: line, matching: find.byType(RichText)));
      if (p.didExceedMaxLines) cut.add('$why hint: ${p.text.toPlainText()}');
      expect(tester.getRect(hint).right, lessThanOrEqualTo(375), reason: why);
      final placeholder = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byKey(_field),
          matching: find.text(l10n.sendRecipientSearchHint)));
      if (placeholder.didExceedMaxLines) {
        cut.add('$why placeholder: ${l10n.sendRecipientSearchHint}');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    expect(cut, isEmpty, reason: cut.join('\n'));
  });

  testWidgets(
      'a typed number no contact has offers "Send a link to +…": a person, '
      'asked What, Money its link with no name', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    await _pump(tester);
    await type(tester, '+351 999 888 777');
    final row =
        find.byKey(const ValueKey('send-phone-link-row'), skipOffstage: false);
    expect(row, findsOneWidget);
    expect(_text(_l10n.sendLinkToPhone('+351999888777')), findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendWhatTitle('+351999888777')), findsOneWidget);
    await tester.tap(find.byKey(kSendWhatMoneyKey));
    await tester.pumpAndSettle();
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.senderLabel, isNull);
    expect(sheet.recipientPhone, '+351999888777');
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'phone'));

    // A number a contact has is that contact, not a link row.
    Navigator.of(tester.element(find.byType(SendToAnyoneSheet))).pop();
    await tester.pumpAndSettle();
    await type(tester, '912 345 678');
    expect(find.byKey(const ValueKey('send-phone-link-row')), findsNothing);
    expect(person('c2'), findsOneWidget);
  });

  testWidgets(
      'at 375 pt the Send to step is ONE scroll to the sheet\'s bottom edge: '
      'no band reserved above the bar, and the last contact scrolls fully '
      'clear of it', (tester) async {
    _gateway
      ..permission = SendContactsPermission.granted
      ..contacts = [
        for (var i = 0; i < 30; i++)
          SendContact(
              id: 'm$i',
              displayName: 'Person ${i.toString().padLeft(2, '0')}',
              firstName: 'Person',
              phone: '+351 91${i.toString().padLeft(7, '0')}'),
      ];
    await _pump(tester);
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(ConfirmSend)));
    if (route is SendSheetRoute) route.sheetController.expand();
    await tester.pumpAndSettle();

    final scroll = find.byKey(const ValueKey('send-to-scroll'));
    expect(scroll, findsOneWidget);
    // Nothing reserved under the page: the scroll runs to the bottom.
    expect(tester.getRect(scroll).bottom, moreOrLessEquals(812, epsilon: 1));

    // To the end: the last row sits wholly above the bar.
    await tester.drag(scroll, const Offset(0, -6000));
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('send-person-contact:m29'));
    expect(last, findsOneWidget);
    final row = tester.getRect(last);
    final bar = tester.getRect(kuteBarPrimary);
    expect(row.bottom, lessThanOrEqualTo(bar.top));
    expect(row.top, greaterThanOrEqualTo(tester.getRect(scroll).top));
    expect(tester.takeException(), isNull);
  });

  // THE FIELD KEEPS EVERYTHING (founder): with the contacts granted, a
  // destination still resolves first and Continue works.
  for (final (what, text) in [
    ('a Lightning address on another domain', 'alice@getalby.com'),
    (
      'an invoice',
      'lnbc2500u1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu'
    ),
    ('a bitcoin address', _btc),
  ]) {
    testWidgets(
        '$what typed with the contacts granted resolves and Continue works',
        (tester) async {
      _gateway.permission = SendContactsPermission.granted;
      await _pump(tester);
      expect(person('c1'), findsOneWidget);
      await type(tester, text);
      expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('send-phone-link-row')), findsNothing);
      expect(kuteBarPrimaryEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
