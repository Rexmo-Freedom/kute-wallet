// The Bitcoin Send's Who step (send_recipient_step.dart) with CONTACTS
// LIKE REVOLUT (founder, 1 November 2026; send_contacts_list.dart) and the
// approved Send (founder, 7 November 2026: "ok do it, just make sure that
// people realise they can send to different cryptos also"):
//
//   * the search field takes everything ("Name, phone or any crypto
//     address": Lightning addresses of any domain, invoices, bitcoin and
//     crypto addresses, Paste and Scan) and recognises it as it is typed;
//     no "Another crypto" card under it (founder, 7 November 2026:
//     "another crypto should be implied not a button"): the logos of what
//     it takes while it is empty (founder, 8 November 2026), then the
//     contacts;
//   * NO CHIPS: no "To your Dollars", no "Crypto address", no "Prediction
//     or investment". Typed, an own account's name finds the move ("Move to
//     your Dollars");
//   * a paste goes straight on: a bitcoin address to the amount, a 0x
//     address to the network question ("Where to?" filtered to it); typed,
//     the keyboard's Done does the same;
//   * a person (a contact, a typed number) is sent bitcoin, straight on
//     (founder, 8 November 2026: "just assume that it is bitcoin, so this
//     picker is not necessary"): a Kute contact paid at their address, anyone
//     else by link; no What sheet and no gift, whatever the policy says (the
//     Dollars Send's What: send_what_step_test.dart).

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
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
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
    show AnotherCryptoMarks, SendRecipientSearchField;
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet, kSendWhatGiftKey;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show CapabilityUnavailableSheet;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard, KuteActionCardGrid;
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

/// The app's own type, Inter: the field's placeholder is measured in it.
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

/// No Send has an "Another crypto" card any more (the Receive sheets keep
/// theirs): absent, by its old key, its marks and its title.
void _expectNoAnotherCrypto() {
  expect(find.byKey(const ValueKey('send-another-crypto')), findsNothing);
  expect(find.byType(AnotherCryptoMarks), findsNothing);
  expect(find.text(_l10n.receiveAnotherCrypto), findsNothing);
}
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
    expect(find.byKey(const ValueKey('send-accepted-coins')), findsOneWidget);
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(ask), findsOneWidget);
    expect(_text(_l10n.sendContactsSeeYours), findsOneWidget);
    expect(find.byKey(const ValueKey('send-to-friend-row')), findsNothing);
    expect(find.byKey(const ValueKey('send-pick-market-row')), findsNothing);
    expect(find.byType(KuteActionCardGrid), findsNothing);
    for (final key in _oldChips) {
      expect(find.byKey(key, skipOffstage: false), findsNothing);
    }
    _expectNoAnotherCrypto();
    // Never a prompt on open.
    expect(_gateway.prompts, 0);
  });

  testWidgets(
      'no own-account, crypto or prediction chips and no Another crypto '
      'card, whatever is offered (founder: "another crypto should be '
      'implied not a button"): no card under the field at all',
      (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true, wide: true, recents: true);
    for (final key in _oldChips) {
      expect(find.byKey(key, skipOffstage: false), findsNothing);
    }
    for (final words in _oldChipWords) {
      expect(_text(words), findsNothing, reason: words);
    }
    _expectNoAnotherCrypto();
    expect(find.byType(KuteActionCardGrid), findsNothing);
    expect(find.byType(KuteActionCard), findsNothing);
    expect(find.byKey(const ValueKey('send-move-results')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'people first: the contacts right under the field, search < Frequent '
      '< All contacts; typing hides Frequent', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true, recents: true);
    const frequent = ValueKey('send-frequent-section');
    expect(find.byKey(frequent), findsOneWidget);
    expect(find.byKey(const ValueKey('send-frequent-recent:rita@paykute.com')),
        findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    double bottom(Finder f) => tester.getBottomLeft(f).dy;
    // Frequent follows the field with only the section's own gap.
    expect(top(find.byKey(frequent)) - bottom(find.byKey(_field)),
        inInclusiveRange(0, 40));
    expect(bottom(find.byKey(frequent)), lessThan(top(find.byKey(ask))));
    // Once only: the Contacts below never repeat it.
    expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);

    await type(tester, 'ri');
    expect(find.byKey(frequent), findsNothing);
  });

  testWidgets(
      'no coin offered under the policy (the swap switched off): nothing '
      'under the field; the field still takes bitcoin', (tester) async {
    await policy(tester, blocked: const {'orchestra.swap'});
    await _pump(tester, catalog: true);
    _expectNoAnotherCrypto();
    expect(find.byType(KuteActionCard), findsNothing);
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
      'number; a tap goes straight on to Send to anyone in bitcoin with the '
      'first name, the number staying on the phone; no What, nothing counted '
      'as picked', (tester) async {
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
    expect(find.byType(SendWhatSheet), findsNothing);
    expect(find.text(_l10n.sendWhatSubtitle), findsNothing);
    expect(find.byKey(kSendWhatGiftKey), findsNothing);
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'contact'));
    expect(_paramsOf('send_what_picked'), isEmpty);
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

  for (final (why, blocked) in const [
    ('nothing withheld', <String>{}),
    ('both venues\' trade refused', {'polymarket.trade', 'hyperliquid.trade'}),
    ('both venues\' browse switched off',
        {'polymarket.browse', 'hyperliquid.browse'}),
    ('one venue\'s browse switched off', {'polymarket.browse'}),
  ]) {
    testWidgets(
        '$why: a person on the Bitcoin Send still goes straight on to the '
        'bitcoin link, no What, no gift and no Unavailable sheet',
        (tester) async {
      _gateway.permission = SendContactsPermission.granted;
      await policy(tester, blocked: blocked);
      await _pump(tester);
      await tapPerson(tester, 'c2');
      expect(find.byType(SendWhatSheet), findsNothing);
      expect(find.byKey(kSendWhatGiftKey), findsNothing);
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(
          tester
              .widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet))
              .kind,
          ShareLinkKind.bitcoin);
      expect(_paramsOf('send_what_picked'), isEmpty);
    });
  }

  testWidgets(
      'the bitcoin link closed with none created: the send stays; a link '
      'created closes the send', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await policy(tester);
    await _pump(tester);
    await tapPerson(tester, 'c2');
    Navigator.of(tester.element(find.byType(SendToAnyoneSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(_page(tester), moreOrLessEquals(0));
    await tapPerson(tester, 'c2');
    Navigator.of(tester.element(find.byType(SendToAnyoneSheet))).pop(true);
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSend), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a contact with a Kute Lightning address wears the Kute badge; a tap '
      'pays them directly: the address fills the field and the send goes on '
      'to the amount, no What and no link', (tester) async {
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
    expect(find.byType(SendWhatSheet), findsNothing);
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(_address(tester), 'joana@paykute.com');
    expect(_page(tester), moreOrLessEquals(1));
    expect(_paramsOf('send_what_picked'), isEmpty);
  });

  testWidgets(
      'a resolved destination is ONE recipient card: the contact named, not '
      'listed again, no rail chip (Lightning or on-chain waits for Review), '
      'nothing under the field; Change brings the contacts back',
      (tester) async {
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
    // Typed, it waits for the bar: Continue (or the keyboard's Done).
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    expect(_page(tester), 0);

    await tester.tap(find.byKey(const ValueKey('send-recipient-change')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(card, findsNothing);
    _expectNoAnotherCrypto();
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(const ValueKey('send-person-contact:k1'),
            skipOffstage: false),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a typed 0x address several networks take asks in the highlighted row '
      'right under the field as it is typed; the keyboard\'s Done opens '
      '"Where to?" filtered to it, as a paste does', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    await type(tester, _evm);
    final question = _text(_l10n.sendWhichNetworkIsThisAddressOn);
    expect(question, findsOneWidget);
    final card =
        find.ancestor(of: question, matching: find.byType(SendToListCard));
    expect(tester.widget<SendToListCard>(card).emphasized, isTrue);
    final field = tester.getRect(find.byKey(_field));
    expect(tester.getRect(card).top - field.bottom, lessThan(16));
    // Typed, nothing opens by itself while typing.
    expect(find.text(_l10n.sendWhereTo), findsNothing);
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    // Done: the paste's next step, the sheet filtered to the address.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendWhereTo), findsOneWidget);
    final tiles = tester
        .widgetList<CoinAssetTile>(find.byType(CoinAssetTile))
        .map((t) => t.label)
        .toList();
    expect(tiles, contains('USDC'));
    expect(tiles, isNot(contains('USDT')));
    expect(_page(tester), 0);
    // A network picked: the recipient card, the coin on its network, and
    // Continue goes on.
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('base').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-recipient-card')), findsOneWidget);
    expect(_text(_l10n.sendAssetOnNetwork('USDC', 'base')), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    // The coin chosen, the field's hint is just "Address", as on the Dollars
    // Send's address step.
    expect(
        tester
            .widget<SendRecipientSearchField>(
                find.byType(SendRecipientSearchField))
            .hintText,
        'Address');
    _expectNoAnotherCrypto();
    expect(tester.takeException(), isNull);
  });

  // Typed, every rail the send pays as it is shows as one recipient card
  // as it is typed, and the keyboard's Done goes on to the amount as a
  // paste does (founder: "it should just auto recognise").
  for (final (what, typed) in const [
    ('a bitcoin address (bech32)', _btc),
    ('a bitcoin address (legacy)', '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2'),
    ('a Lightning address', 'alice@getalby.com'),
    ('an LNURL',
        'lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns'),
    ('a Spark address',
        'sp1pgssyuuuhnrrdjswal5c3s3rafw9w3y5dd4cjy3duxlf7hjzkp0rqx6dj6mrhu'),
  ]) {
    testWidgets(
        'typed, $what shows as the recipient card as it is typed and the '
        'keyboard\'s Done goes on to the amount, tracked as an address',
        (tester) async {
      await policy(tester);
      await _pump(tester, catalog: true);
      await type(tester, typed);
      expect(find.byKey(const ValueKey('send-recipient-card')),
          findsOneWidget, reason: what);
      expect(_text(_l10n.sendWhichNetworkIsThisAddressOn), findsNothing);
      expect(kuteBarPrimaryEnabled(tester), isTrue);
      expect(_page(tester), 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_page(tester), moreOrLessEquals(1), reason: what);
      expect(_address(tester), typed);
      expect(_paramsOf('send_recipient_picked').single,
          containsPair('kind', 'address'));
      expect(find.text(_l10n.sendWhereTo), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // Typed, an address another network's coins land on asks which, as it
  // is typed; Done opens "Where to?" filtered to its family.
  for (final (what, typed, coin, notCoin) in const [
    ('a Solana address', '7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV', 'SOL',
        'TRX'),
    ('a Tron address', 'TJCnKsPa7y5okkXvQAidZBzqx3QyQ6sxMW', 'TRX', 'SOL'),
  ]) {
    testWidgets(
        'typed, $what asks for the network as it is typed; Done opens '
        '"Where to?" with its own coins only', (tester) async {
      await policy(tester);
      await _pump(tester, wide: true);
      await type(tester, typed);
      expect(_text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget,
          reason: what);
      expect(find.byKey(const ValueKey('send-recipient-card')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sendWhereTo), findsOneWidget);
      final tiles = tester
          .widgetList<CoinAssetTile>(find.byType(CoinAssetTile))
          .map((t) => t.label)
          .toList();
      expect(tiles, contains(coin), reason: what);
      expect(tiles, isNot(contains(notCoin)), reason: what);
      expect(tiles, isNot(contains('ETH')), reason: what);
      expect(_page(tester), 0);
    });
  }

  testWidgets(
      'typed (or pasted into the field), a cross-chain payment URI is '
      'reduced to its bare address as the Paste button does, and asks the '
      'network', (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    await type(tester, 'ethereum:$_evm@8453');
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        _evm);
    expect(_text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget);
    // Half a scheme being typed is left alone.
    await type(tester, 'ethereum:');
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'ethereum:');
  });

  testWidgets(
      'typed, an address no coin matches keeps its row ("Address not '
      'identified"), and Done neither goes on nor opens a sheet',
      (tester) async {
    await policy(tester);
    await _pump(tester, catalog: true);
    await type(tester, 'zz9notanaddressatall0000000');
    expect(_text(_l10n.sendAddressNotIdentified), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_page(tester), 0);
    expect(find.text(_l10n.sendWhereTo), findsNothing);
    expect(_paramsOf('send_recipient_picked'), isEmpty);
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
      'at 375 pt, in Inter, in every shipped language: the field\'s '
      'placeholder ("Name, phone or any crypto address", what says the field '
      'takes any crypto now that no card does) is whole, and no Another '
      'crypto card', (tester) async {
    await tester.runAsync(_loadInter);
    await policy(tester);
    final cut = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester, locale: locale, wide: true);
      expect(tester.takeException(), isNull, reason: why);
      expect(find.byType(AnotherCryptoMarks), findsNothing, reason: why);
      expect(find.text(l10n.receiveAnotherCrypto), findsNothing, reason: why);
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
      'straight on to its bitcoin link with no name', (tester) async {
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
    expect(find.byType(SendWhatSheet), findsNothing);
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.kind, ShareLinkKind.bitcoin);
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

  // REVIEW IN SQUARES (founder, 7 November 2026: "make this more with the
  // square cards we have now"): From and To side by side, the To square
  // wearing the Who step's face and the rail only where it is not the
  // default ("Bitcoin Network" under a bitcoin address said nothing). An @
  // address is never cut (founder, 7 November 2026: "try not to trim when
  // its a @ address"): the saved contact's name whole over "@domain", no
  // "Lightning".
  for (final (what, text, title, line, badge) in [
    (
      'a Kute contact\'s Lightning address',
      'joana@paykute.com',
      'Joana Kute',
      '@paykute.com',
      'send-badge-kute'
    ),
    ('a bitcoin address', _btc, null, null, null),
  ]) {
    testWidgets(
        'Review to $what: From and To are two squares, '
        '${title ?? 'the address in its middle form'}, '
        '${line ?? 'no line'} under it, no chevrons', (tester) async {
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
      await type(tester, text);
      await tester.tap(kuteBarPrimary);
      await tester.pumpAndSettle();
      expect(_page(tester), moreOrLessEquals(1));
      for (final d in '50'.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(kuteBarPrimary);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_page(tester), moreOrLessEquals(2));

      final from = find.byKey(const ValueKey('send-review-from'));
      final to = find.byKey(const ValueKey('send-review-to'));
      Finder inside(Finder card, Finder f) =>
          find.descendant(of: card, matching: f);
      expect(tester.getRect(from).top, tester.getRect(to).top);
      expect(tester.getRect(from).height, tester.getRect(to).height);
      expect(inside(from, find.text(_l10n.from)), findsOneWidget);
      expect(inside(from, find.text('Bitcoin')), findsOneWidget);
      expect(
          inside(from,
              find.textContaining(_l10n.sendAvailableBalanceSubtitle(''))),
          findsOneWidget);
      expect(inside(to, find.text(_l10n.to)), findsOneWidget);
      if (title != null) {
        // The name whole, never the address cut in its middle.
        expect(inside(to, find.text(title)), findsOneWidget);
        expect(find.byKey(const ValueKey('send-review-to-address')),
            findsNothing);
        expect(inside(to, find.text(_l10n.sendRailLightning)), findsNothing);
      } else {
        final shown = tester
            .widget<Text>(inside(
                find.byKey(const ValueKey('send-review-to-address')),
                find.byType(Text)))
            .data!;
        expect(shown.startsWith(text.substring(0, 4)), isTrue);
        expect(shown.endsWith(text.substring(text.length - 3)), isTrue);
      }
      expect(inside(to, find.text(_l10n.bitcoinNetwork)), findsNothing);
      if (line != null) {
        expect(inside(to, find.text(line)), findsOneWidget);
      }
      if (badge != null) {
        expect(inside(to, find.byKey(ValueKey(badge))), findsOneWidget);
        expect(inside(to, find.text('JK')), findsOneWidget);
      } else {
        expect(inside(to, find.text(_l10n.sendRailLightning)), findsNothing);
        expect(inside(to, find.text(_l10n.sendRailBitcoinOnchain)),
            findsNothing);
      }
      final route = find.byKey(const ValueKey('send-review-route'));
      expect(inside(route, find.byIcon(Icons.chevron_right_rounded)),
          findsNothing);
      expect(inside(route, find.byIcon(Icons.keyboard_arrow_down_rounded)),
          findsNothing);

      // A tap on To shows the whole destination with Copy.
      await tester.tap(to);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          inside(find.byKey(const ValueKey('send-review-full-address')),
              find.text(text)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
