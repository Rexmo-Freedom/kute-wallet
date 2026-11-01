// The Contacts list's rules (send_contacts_list.dart): the badge (Kute
// for a @paykute.com address or a Kute recipient, ⚡ for any other
// Lightning address or LNURL, none for a plain contact or a coin
// address), a typed phone number, the merge (recents first, a contact
// already listed by its Kute address once), filtering by name, number and
// address, and the layout: the recents as circles while there is no book,
// one list once there is. The recipient card: who a resolved destination
// is (a contact first, then a recent, else the shortened address), and
// the list never repeating them ("Other contacts").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendRecentCircles;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../mocks/fake_send_contacts_gateway.dart';

const _kuteContact = SendContact(
    id: 'k1',
    displayName: 'Joana Kute',
    firstName: 'Joana',
    phone: '+351 914 444 444',
    lightningAddress: 'joana@paykute.com');

List<SendPerson> _recents() => [
      SendPerson.recent(
          address: 'rita@paykute.com',
          name: 'rita',
          secondary: 'rita@paykute.com'),
      SendPerson.recent(
          address: 'alice@getalby.com',
          name: 'alice',
          secondary: 'alice@getalby.com'),
      SendPerson.recent(
          address: 'spark1pgss9qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
          name: 'spark1…qqqq',
          icon: Icons.bolt_rounded),
    ];

void main() {
  group('the badge', () {
    test('Kute for a @paykute.com address, whatever its case', () {
      expect(sendBadgeFor('joana@paykute.com'), SendPersonBadge.kute);
      expect(sendBadgeFor('Joana@PayKute.com'), SendPersonBadge.kute);
    });
    test('Kute for a recipient known as Kute', () {
      expect(
          sendBadgeFor('spark1abc', kuteRecipient: true), SendPersonBadge.kute);
    });
    test('⚡ for any other Lightning address or an LNURL', () {
      expect(sendBadgeFor('alice@getalby.com'), SendPersonBadge.lightning);
      expect(
          sendBadgeFor('bob@walletofsatoshi.com'), SendPersonBadge.lightning);
      expect(sendBadgeFor('LNURL1DP68GURN8GHJ7'), SendPersonBadge.lightning);
    });
    test('none for a plain contact, a coin or a bitcoin address', () {
      expect(sendBadgeFor(null), SendPersonBadge.none);
      expect(sendBadgeFor(''), SendPersonBadge.none);
      expect(sendBadgeFor('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
          SendPersonBadge.none);
      expect(sendBadgeFor('0x742d35cc6634c0532925a3b844bc454e4438f44e'),
          SendPersonBadge.none);
      expect(
          SendPerson.contact(fakeContacts().first).badge, SendPersonBadge.none);
      expect(SendPerson.contact(_kuteContact).badge, SendPersonBadge.kute);
    });
  });

  test('a typed phone number, and what is not one', () {
    expect(sendTypedPhone('+351 912 345 678'), '+351912345678');
    expect(sendTypedPhone('912-345-678'), '912345678');
    expect(sendTypedPhone('(912) 345 678'), '912345678');
    expect(sendTypedPhone('12345'), isNull);
    expect(sendTypedPhone('maria'), isNull);
    expect(sendTypedPhone('alice@getalby.com'), isNull);
    expect(
        sendTypedPhone('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'), isNull);
  });

  test('a plain contact is a link; a Kute contact and a recent pay directly',
      () {
    expect(SendPerson.contact(fakeContacts().first).direct, isFalse);
    expect(SendPerson.contact(_kuteContact).direct, isTrue);
    expect(SendPerson.contact(_kuteContact).address, 'joana@paykute.com');
    expect(_recents().every((p) => p.direct), isTrue);
  });

  test(
      'the merge: recents first, then the contacts, a Kute contact already '
      'listed as a recent once', () {
    final people = sendPeople(
      recents: [
        SendPerson.recent(address: 'joana@paykute.com', name: 'joana'),
        ..._recents(),
      ],
      contacts: [...fakeContacts(), _kuteContact],
    );
    expect(people.map((p) => p.id).take(4), [
      'recent:joana@paykute.com',
      'recent:rita@paykute.com',
      'recent:alice@getalby.com',
      startsWith('recent:spark1'),
    ]);
    expect(people.where((p) => p.contact?.id == 'k1'), isEmpty);
    expect(people.skip(4).map((p) => p.name),
        ['Ana Costa', 'Maria Alves', 'Rui Santos']);
  });

  test('filtering by name, by number and by address', () {
    final maria = SendPerson.contact(fakeContacts()[1]);
    expect(maria.matches('mar'), isTrue);
    expect(maria.matches('912 345'), isTrue);
    expect(maria.matches('ana'), isFalse);
    final alice = _recents()[1];
    expect(alice.matches('getalby'), isTrue);
    expect(alice.matches('alice@getalby.com'), isTrue);
    expect(alice.matches('rita'), isFalse);
  });

  group('the section', () {
    Future<List<SendPerson>> pump(WidgetTester tester,
        {required FakeSendContactsGateway gateway,
        String query = '',
        String? excludeAddress,
        List<SendPerson>? recents}) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tapped = <SendPerson>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [sendContactsGatewayProvider.overrideWithValue(gateway)],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(builder: (context, ref, _) {
                return SingleChildScrollView(
                  child: SendContactsSection(
                    query: query,
                    excludeAddress: excludeAddress,
                    recents: recents ?? _recents(),
                    onPerson: tapped.add,
                    onPhoneLink: (_) {},
                  ),
                );
              }),
            ),
          ),
        ),
      ));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SendContactsSection)));
      await container.read(sendContactsProvider.notifier).refresh();
      await tester.pump();
      return tapped;
    }

    testWidgets(
        'no book: the ask row and the recents as circles; a circle pays it',
        (tester) async {
      final tapped = await pump(tester, gateway: FakeSendContactsGateway());
      expect(
          find.byKey(const ValueKey('send-contacts-ask-row')), findsOneWidget);
      expect(find.byType(SendRecentCircles), findsOneWidget);
      expect(find.byKey(const ValueKey('send-contacts-list')), findsNothing);
      await tester.tap(find.text('alice'));
      expect(tapped.single.address, 'alice@getalby.com');
    });

    testWidgets(
        'with the book: ONE list, recents first with their badges, then the '
        'contacts; no circles', (tester) async {
      final tapped = await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [...fakeContacts(), _kuteContact]));
      expect(find.byType(SendRecentCircles), findsNothing);
      expect(find.byKey(const ValueKey('send-contacts-ask-row')), findsNothing);
      expect(find.byKey(const ValueKey('send-contacts-list')), findsOneWidget);
      Finder badge(String id, String kind) => find.descendant(
          of: find.byKey(ValueKey('send-person-$id')),
          matching: find.byKey(ValueKey('send-badge-$kind')));
      expect(badge('recent:rita@paykute.com', 'kute'), findsOneWidget);
      expect(badge('recent:alice@getalby.com', 'lightning'), findsOneWidget);
      expect(badge('contact:k1', 'kute'), findsOneWidget);
      expect(badge('contact:c1', 'kute'), findsNothing);
      expect(badge('contact:c1', 'lightning'), findsNothing);
      final top = tester
          .getTopLeft(
              find.byKey(const ValueKey('send-person-recent:rita@paykute.com')))
          .dy;
      expect(
          top,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('send-person-contact:c1')))
              .dy));
      await tester.tap(find.byKey(const ValueKey('send-person-contact:c2')));
      expect(tapped.single.contact?.firstName, 'Maria');
      expect(tapped.single.direct, isFalse);
    });

    testWidgets('a typed number a contact has is that contact, no link row',
        (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: fakeContacts()),
          query: '912345678');
      expect(find.byKey(const ValueKey('send-phone-link-row')), findsNothing);
      expect(
          find.byKey(const ValueKey('send-person-contact:c2')), findsOneWidget);
    });

    testWidgets('a typed number no contact has: the link row first',
        (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: fakeContacts()),
          query: '+44 7700 900123');
      expect(find.byKey(const ValueKey('send-phone-link-row')), findsOneWidget);
    });

    testWidgets(
        'a chosen recipient is never listed twice: the rest read "Other '
        'contacts", unfiltered by the address in the field', (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [...fakeContacts(), _kuteContact]),
          query: 'joana@paykute.com',
          excludeAddress: 'Joana@PayKute.com');
      final l10n = AppLocalizations.of(
          tester.element(find.byType(SendContactsSection)));
      expect(find.text(l10n.sendOtherContacts), findsOneWidget);
      expect(find.text(l10n.sendContacts), findsNothing);
      expect(
          find.byKey(const ValueKey('send-person-contact:k1')), findsNothing);
      expect(
          find.byKey(const ValueKey('send-person-contact:c1')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('send-person-recent:rita@paykute.com')),
          findsOneWidget);
    });

    testWidgets('no book: the chosen recent leaves the circles',
        (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(),
          query: 'alice@getalby.com',
          excludeAddress: 'alice@getalby.com');
      expect(find.byType(SendRecentCircles), findsOneWidget);
      expect(find.text('alice'), findsNothing);
      expect(find.text('rita'), findsOneWidget);
      expect(find.byKey(const ValueKey('send-contacts-ask-row')), findsNothing);
    });
  });

  group('the recipient', () {
    test('a contact with the address first, its name and photo', () {
      final m = sendMatchingPerson('lightning:JOANA@paykute.com',
          recents: [
            SendPerson.recent(address: 'joana@paykute.com', name: 'joana')
          ],
          contacts: [_kuteContact]);
      expect(m?.contact?.id, 'k1');
      expect(sendRecipientName(m, 'joana@paykute.com'), 'Joana Kute');
    });
    test('else the recent, by its label', () {
      final m = sendMatchingPerson('alice@getalby.com',
          recents: _recents(), contacts: fakeContacts());
      expect(m?.address, 'alice@getalby.com');
      expect(sendRecipientName(m, 'alice@getalby.com'), 'alice');
    });
    test('nobody known: the shortened address', () {
      const addr = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
      final m = sendMatchingPerson(addr,
          recents: _recents(), contacts: fakeContacts());
      expect(m, isNull);
      expect(sendRecipientName(m, addr), sendShortAddress(addr));
    });
    test('an address too long for two lines is cut in the middle, both ends '
        'kept', () {
      const addr = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
      const style = TextStyle(fontSize: 13);
      expect(
          SendMiddleEllipsisText.fit(addr,
              style: style,
              maxWidth: 2000,
              maxLines: 2,
              textScaler: TextScaler.noScaling),
          addr);
      final cut = SendMiddleEllipsisText.fit(addr,
          style: style,
          maxWidth: 120,
          maxLines: 2,
          textScaler: TextScaler.noScaling);
      expect(cut, contains('\u2026'));
      expect(cut.startsWith('bc1q'), isTrue);
      expect(cut.endsWith('mdq'), isTrue);
      expect(cut.length, lessThan(addr.length));
    });

    Future<void> pumpCard(WidgetTester tester, String address,
        {String rail = 'Lightning'}) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FakeSendContactsGateway(
          permission: SendContactsPermission.granted,
          contacts: [...fakeContacts(), _kuteContact]);
      await tester.pumpWidget(ProviderScope(
        overrides: [sendContactsGatewayProvider.overrideWithValue(gateway)],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: SendRecipientCard(
                  address: address,
                  rail: rail,
                  railMark: const Icon(Icons.bolt_rounded),
                  recents: _recents(),
                  onChange: () {},
                ),
              ),
            ),
          ),
        ),
      ));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SendRecipientCard)));
      await container.read(sendContactsProvider.notifier).refresh();
      await tester.pump();
    }

    String name(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('send-recipient-name')))
        .data!;

    testWidgets('the card names a contact, wears its Kute badge and the rail',
        (tester) async {
      await pumpCard(tester, 'joana@paykute.com');
      expect(name(tester), 'Joana Kute');
      expect(find.byKey(const ValueKey('send-badge-kute')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-recipient-rail')),
              matching: find.text('Lightning')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-recipient-change')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the card names a recent by its label, ⚡ on its avatar',
        (tester) async {
      await pumpCard(tester, 'alice@getalby.com');
      expect(name(tester), 'alice');
      expect(
          find.byKey(const ValueKey('send-badge-lightning')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'nobody known: the shortened address as the name, the rail\'s mark '
        'as the avatar, nothing overflows at 375 pt x1.3', (tester) async {
      const addr = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
      await pumpCard(tester, addr, rail: 'Bitcoin · on-chain');
      expect(name(tester), sendShortAddress(addr));
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
