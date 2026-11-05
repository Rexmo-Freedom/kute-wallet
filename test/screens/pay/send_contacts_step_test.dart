// The bitcoin send's recipient-first Send to step with CONTACTS LIKE
// REVOLUT (founder, 1 November 2026; send_contacts_list.dart): the search
// field keeps everything it took (Lightning addresses of any domain,
// invoices, bitcoin addresses, Paste and Scan) and ONE Contacts list sits
// under it: no "Send to a friend" row. Until the permission is granted
// the list leads with "See your contacts" (a prompt on tap only; Settings
// once refused for good); with the book, the contacts, filtered by what
// is typed. A plain contact starts Send to anyone with the first name and
// the number kept on the phone; a contact with a Kute Lightning address
// wears the Kute badge and is paid directly; a typed number no contact has
// offers "Send a link to +…".

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
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart' show CoinAssetTile;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendAlsoSendsToRow, SendCoinStack;
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

/// A live routes catalogue, for the coin picker.
OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('arbitrum', 'USDC'),
          _row('base', 'USDC'),
          _row('tron', 'USDT'),
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
    {bool catalog = false, bool recents = false}) async {
  tester.view.physicalSize = const Size(1125, 2436);
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
      if (catalog) ...[
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
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
  });

  const ask = ValueKey('send-contacts-ask-row');
  Finder person(String id) =>
      find.byKey(ValueKey('send-person-contact:$id'), skipOffstage: false);

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the step: "Send", the search field with its hint, Paste and Scan, '
      'the Contacts list with "See your contacts" first, and no "Send to a '
      'friend" row', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.send), findsOneWidget);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(find.byType(StepperProgress), findsNothing);
    expect(find.byKey(const ValueKey('send-recipient-search')), findsOneWidget);
    expect(find.text(_l10n.sendRecipientSearchHint), findsOneWidget);
    expect(find.byKey(const ValueKey('send-field-paste')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-field-scan')), findsOneWidget);
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(ask), findsOneWidget);
    expect(_text(_l10n.sendContactsSeeYours), findsOneWidget);
    expect(find.byKey(const ValueKey('send-to-friend-row')), findsNothing);
    expect(find.byKey(const ValueKey('send-pick-market-row')), findsNothing);
    // Top to bottom: the field, the Send to card, then the Contacts (a
    // growing list never hides "Also sends to").
    final sendTo = find.text(_l10n.sendToLabel);
    expect(sendTo, findsOneWidget);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('send-recipient-search')))
            .dy,
        lessThan(tester.getTopLeft(sendTo).dy));
    expect(tester.getTopLeft(sendTo).dy,
        lessThan(tester.getTopLeft(find.byKey(ask)).dy));
    // Never a prompt on open.
    expect(_gateway.prompts, 0);
  });

  testWidgets(
      'Frequent stays on top: the recents under the field, above the Send '
      'to card, All contacts below it; typing hides Frequent',
      (tester) async {
    await _pump(tester, recents: true);
    const frequent = ValueKey('send-frequent-section');
    expect(find.byKey(frequent), findsOneWidget);
    expect(find.byKey(const ValueKey('send-frequent-recent:rita@paykute.com')),
        findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    final sendTo = find.text(_l10n.sendToLabel);
    expect(top(find.byKey(const ValueKey('send-recipient-search'))),
        lessThan(top(find.byKey(frequent))));
    expect(top(find.byKey(frequent)), lessThan(top(sendTo)));
    expect(top(sendTo), lessThan(top(find.byKey(ask))));
    // Once only: the Contacts below never repeat it.
    expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);

    await type(tester, 'ri');
    expect(find.byKey(frequent), findsNothing);
  });

  testWidgets(
      'No "To a friend · Send to anyone" card on a bitcoin send (founder, 5 '
      'November 2026: a contact or a typed phone number already sends by '
      'link)', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('send-friend-card')), findsNothing);
    expect(find.byKey(const ValueKey('send-to-anyone-row')), findsNothing);
    expect(_text(_l10n.shareSendToAnyone), findsNothing);
    // The Contacts and their phone links stay.
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
      'with the book, the text filters by name and by number; a plain '
      'contact opens Send to anyone with the first name, the number '
      'staying on the phone', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
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
    await tester.ensureVisible(person('c2'));
    await tester.pumpAndSettle();
    await tester.tap(person('c2'));
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'contact'));
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.kind.name, 'bitcoin');
    expect(sheet.senderLabel, 'Maria');
    expect(sheet.recipientPhone, '+351 912 345 678');
    for (final e in _events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
  });

  testWidgets(
      'a contact with a Kute Lightning address wears the Kute badge and is '
      'paid directly: the address fills the field and resolves',
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
    await _pump(tester);
    expect(
        find.descendant(
            of: person('k1'),
            matching: find.byKey(const ValueKey('send-badge-kute'))),
        findsOneWidget);
    await tester.ensureVisible(person('k1'));
    await tester.pumpAndSettle();
    await tester.tap(person('k1'));
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'joana@paykute.com');
  });

  testWidgets(
      'a resolved destination is ONE recipient card: the contact named, '
      'not listed again, the Send to card hidden; Change brings both back',
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
    await _pump(tester);
    expect(find.text(_l10n.sendToLabel), findsOneWidget);
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
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('send-recipient-rail')),
            matching: find.text(_l10n.sendRailLightning)),
        findsOneWidget);
    // Not twice: the list drops her and reads "Other contacts".
    expect(find.byKey(const ValueKey('send-person-contact:k1')), findsNothing);
    expect(person('c1'), findsOneWidget);
    expect(_text(_l10n.sendOtherContacts), findsOneWidget);
    expect(find.text(_l10n.sendToLabel), findsNothing);
    // The bar stays Continue.
    expect(kuteBarPrimaryEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('send-recipient-change')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(card, findsNothing);
    expect(find.text(_l10n.sendToLabel), findsOneWidget);
    expect(_text(_l10n.sendAllContacts), findsOneWidget);
    expect(find.byKey(const ValueKey('send-person-contact:k1'),
            skipOffstage: false),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a coin chosen on Send to ("USDC · base") makes the send address-only: '
      'no Contacts; the card shows the coin with Change, which brings them '
      'back', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    addTearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });
    await tester.runAsync(policy.refresh);
    await _pump(tester, catalog: true);
    expect(person('c1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-also-sends-to-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
    await tester.pumpAndSettle();
    // Two networks: which one ("Which network?").
    await tester.tap(find.text('base').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-contacts-section')), findsNothing);
    expect(person('c1'), findsNothing);
    expect(find.textContaining('USDC ·'), findsOneWidget);
    final change = find.byKey(const ValueKey('send-to-coin-change'));
    expect(change, findsOneWidget);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(person('c1'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-to-coin-change')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the Send to option is the app\'s big card, the only one, so full '
      'width and compact (founder: "here no need to be as big"): the coins '
      'at its left, "Also sends to" over the list, a chevron at its right, '
      'as tall as that; an address that needs a network asks in the '
      'emphasized row; a coin chosen is the compact card again',
      (tester) async {
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    addTearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });
    await tester.runAsync(policy.refresh);
    await _pump(tester, catalog: true);
    const options = ValueKey('send-to-options');
    const also = ValueKey('send-also-sends-to-row');
    final grid = tester.widget<KuteActionCardGrid>(find.byKey(options));
    expect(grid.cards.map((c) => c.key), [also]);
    final card = tester.widget<KuteActionCard>(find.byKey(also));
    expect(card.title, _l10n.sendToCryptoAddress);
    expect(card.subtitle, _l10n.sendAlsoSendsToList('USDC, USD', 'USDT'));
    expect(card.visual, isA<SendCoinStack>());
    // Full width: as wide as the search field above it; compact, as tall
    // as the coins or the two lines of text and the padding, no taller
    // (not the ~170 square it was).
    final field = tester.getRect(find.byKey(const ValueKey('send-recipient-search')));
    final rect = tester.getRect(find.byKey(also));
    expect(rect.width, moreOrLessEquals(field.width, epsilon: 1));
    expect(rect.left, moreOrLessEquals(field.left, epsilon: 1));
    Rect inCard(Finder f) =>
        tester.getRect(find.descendant(of: find.byKey(also), matching: f));
    final title = inCard(find.text(_l10n.sendToCryptoAddress));
    final list = inCard(find.text(_l10n.sendAlsoSendsToList('USDC, USD', 'USDT')));
    final coins = inCard(find.byType(SendCoinStack));
    final chevron = inCard(find.byIcon(Icons.chevron_right_rounded));
    final text = list.bottom - title.top;
    expect(
        rect.height,
        moreOrLessEquals(
            (text > kKuteActionCardVisualSlot
                    ? text
                    : kKuteActionCardVisualSlot) +
                2 * (kKuteActionCardPadding + 1),
            epsilon: 1));
    expect(rect.height, lessThan(110));
    // The coins at the left, the words beside them, the chevron at the
    // right, level with the card's middle.
    expect(coins.left - rect.left,
        moreOrLessEquals(kKuteActionCardPadding + 1, epsilon: 1));
    expect(title.left, greaterThan(coins.right));
    expect(chevron.left, greaterThan(list.right - 1));
    expect(chevron.center.dy, moreOrLessEquals(rect.center.dy, epsilon: 1));
    expect(find.byType(SendAlsoSendsToRow), findsNothing);

    // An address several networks take: the question, as the emphasized
    // row (the one forward path), not a card.
    await type(tester, '0x742d35cc6634c0532925a3b844bc454e4438f44e');
    expect(find.byKey(options), findsNothing);
    expect(_text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget);
    expect(
        tester
            .widget<SendToListCard>(find.ancestor(
                of: _text(_l10n.sendWhichNetworkIsThisAddressOn),
                matching: find.byType(SendToListCard)))
            .emphasized,
        isTrue);
    // Cleared: the square again; a coin chosen from it is the card,
    // full width, with Change beside the label.
    await type(tester, '');
    expect(find.byKey(also), findsOneWidget);
    await tester.tap(find.byKey(also));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('base').first);
    await tester.pumpAndSettle();
    const coin = ValueKey('send-to-coin-card');
    expect(
        tester.widget<KuteActionCardGrid>(find.byKey(options)).cards.map((c) => c.key),
        [coin]);
    expect(tester.widget<KuteActionCard>(find.byKey(coin)).title,
        startsWith('USDC ·'));
    expect(tester.getRect(find.byKey(coin)).width,
        moreOrLessEquals(field.width, epsilon: 1));
    expect(tester.getRect(find.byKey(coin)).height, lessThan(110));
    expect(
        find.descendant(
            of: find.byKey(coin),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-to-coin-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(also), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a typed number no contact has offers "Send a link to +…": Send to '
      'anyone for that number, no name', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
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
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.senderLabel, isNull);
    expect(sheet.recipientPhone, '+351999888777');

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
    ('a bitcoin address', 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
  ]) {
    testWidgets(
        '$what pasted with the contacts granted resolves and Continue works',
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
