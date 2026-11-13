// The Contacts list's rules (send_contacts_list.dart): the badge (Kute
// for a @paykute.com address or a Kute recipient, ⚡ for any other
// Lightning address or LNURL, none for a plain contact or a coin
// address), a typed phone number, the merge (recents first, a contact
// already listed by its Kute address once), filtering by name, number and
// address, and the layout: the recents as circles while there is no book,
// one list once there is. The recipient card: who a resolved destination
// is (a contact first, then a recent, else the shortened address), and
// the list never repeating them ("Other contacts"). The Review's From and
// To (SendReviewRoute): two squares, the same face as the card, an @
// address's name whole over "@domain" (sendAtAddressParts), any other
// address on one line in its middle form, the rail only when given, a tap
// on To showing the whole address with Copy.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
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
        List<SendPerson>? recents,
        bool split = false}) async {
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
                return CustomScrollView(slivers: [
                  // The Sends' shape: Frequent on its own above, the
                  // section without it.
                  if (split)
                    SliverToBoxAdapter(
                      child: SendFrequentSection(
                        query: query,
                        excludeAddress: excludeAddress,
                        recents: recents ?? _recents(),
                        onPerson: tapped.add,
                      ),
                    ),
                  if (split)
                    const SliverToBoxAdapter(
                        child: SizedBox(
                            key: ValueKey('between'), height: 40)),
                  SendContactsSection(
                    query: query,
                    excludeAddress: excludeAddress,
                    recents: recents ?? _recents(),
                    onPerson: tapped.add,
                    onPhoneLink: (_) {},
                    showFrequent: !split,
                  ),
                ]);
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
        'no book: Frequent (the recents as big circles) over the ask row; '
        'a circle pays it', (tester) async {
      final tapped = await pump(tester, gateway: FakeSendContactsGateway());
      expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('send-contacts-ask-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('send-contacts-list')), findsNothing);
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('send-frequent-row'))).dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('send-contacts-ask-row')))
              .dy));
      await tester.tap(
          find.byKey(const ValueKey('send-frequent-recent:alice@getalby.com')));
      expect(tapped.single.address, 'alice@getalby.com');
    });

    testWidgets(
        'with the book: Frequent on top, then All contacts A–Z under sticky '
        'letters, badges on the avatars, no chevrons', (tester) async {
      final tapped = await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [...fakeContacts(), _kuteContact]));
      final l10n = AppLocalizations.of(
          tester.element(find.byType(CustomScrollView)));
      expect(find.text(l10n.sendFrequent), findsOneWidget);
      expect(find.text(l10n.sendAllContacts), findsOneWidget);
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
      // Sal's face is the Kute badge.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-person-contact:k1')),
              matching: find.byKey(const ValueKey('send-sal-face'))),
          findsOneWidget);
      // A–Z: A (alice, Ana Costa), J, M, R (rita, Rui Santos), S.
      double top(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      for (final l in ['A', 'J', 'M', 'R', 'S']) {
        expect(find.byKey(ValueKey('send-letter-$l')), findsOneWidget);
      }
      expect(top(const ValueKey('send-letter-A')),
          lessThan(top(const ValueKey('send-letter-J'))));
      expect(top(const ValueKey('send-person-recent:alice@getalby.com')),
          lessThan(top(const ValueKey('send-person-contact:c1'))));
      expect(top(const ValueKey('send-letter-R')),
          lessThan(top(const ValueKey('send-person-recent:rita@paykute.com'))));
      expect(top(const ValueKey('send-person-recent:rita@paykute.com')),
          lessThan(top(const ValueKey('send-person-contact:c3'))));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-contacts-list')),
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('send-person-contact:c2')));
      expect(tapped.single.contact?.firstName, 'Maria');
      expect(tapped.single.direct, isFalse);
    });

    testWidgets(
        'a long book scrolls end to end under its sticky letters without a '
        'layout error, at fractional offsets', (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [
                for (var l = 0; l < 26; l++)
                  for (var i = 0; i < 3; i++)
                    SendContact(
                        id: 'z$l$i',
                        displayName:
                            '${String.fromCharCode(65 + l)}name $i',
                        firstName: 'N',
                        phone: '+351 9${l.toString().padLeft(2, '0')}$i'),
              ]));
      tester.view.physicalSize = const Size(375, 700);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.drag(
            find.byType(CustomScrollView), const Offset(0, -97.37));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      // The last letter's header sits pinned at the top while its rows
      // pass under it.
      expect(find.byKey(const ValueKey('send-letter-Z')), findsOneWidget);
      for (var i = 0; i < 60; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 83.1));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'split (the Sends): Frequent once, above whatever sits between, '
        'the section below without it; a circle still pays it',
        (tester) async {
      final tapped = await pump(tester,
          split: true,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [...fakeContacts(), _kuteContact]));
      expect(find.byKey(const ValueKey('send-frequent-section')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-frequent-row')), findsOneWidget);
      double top(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      expect(top(const ValueKey('send-frequent-row')),
          lessThan(top(const ValueKey('between'))));
      expect(top(const ValueKey('between')),
          lessThan(top(const ValueKey('send-letter-A'))));
      await tester.tap(
          find.byKey(const ValueKey('send-frequent-recent:alice@getalby.com')));
      expect(tapped.single.address, 'alice@getalby.com');
    });

    testWidgets('split: typing or a chosen recipient hides Frequent',
        (tester) async {
      await pump(tester,
          split: true, gateway: FakeSendContactsGateway(), query: 'ri');
      expect(find.byKey(const ValueKey('send-frequent-section')),
          findsNothing);
      await pump(tester,
          split: true,
          gateway: FakeSendContactsGateway(),
          query: 'alice@getalby.com',
          excludeAddress: 'alice@getalby.com');
      expect(find.byKey(const ValueKey('send-frequent-section')),
          findsNothing);
      expect(find.byKey(const ValueKey('send-frequent-row')), findsNothing);
    });

    testWidgets('typing hides Frequent; the matches are the A–Z rows',
        (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(
              permission: SendContactsPermission.granted,
              contacts: [...fakeContacts(), _kuteContact]),
          query: 'ri');
      expect(find.byKey(const ValueKey('send-frequent-row')), findsNothing);
      expect(find.byKey(const ValueKey('send-person-recent:rita@paykute.com')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-person-contact:c2')),
          findsOneWidget); // Maria
      expect(find.byKey(const ValueKey('send-person-contact:c1')),
          findsNothing);
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

    testWidgets(
        'no book: beside a chosen recent, the other recents as "Other '
        'contacts", no Frequent', (tester) async {
      await pump(tester,
          gateway: FakeSendContactsGateway(),
          query: 'alice@getalby.com',
          excludeAddress: 'alice@getalby.com');
      expect(find.byKey(const ValueKey('send-frequent-row')), findsNothing);
      expect(find.text('alice'), findsNothing);
      expect(find.byKey(const ValueKey('send-person-recent:rita@paykute.com')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-contacts-ask-row')), findsNothing);
    });
  });

  group('the look', () {
    test('Frequent: the recents newest first, a contact standing for its '
        'own address, at most 8', () {
      final f = sendFrequent(recents: [
        SendPerson.recent(address: 'joana@paykute.com', name: 'joana'),
        ..._recents(),
        for (var i = 0; i < 10; i++)
          SendPerson.recent(address: 'p$i@getalby.com', name: 'p$i'),
      ], contacts: [
        ...fakeContacts(),
        _kuteContact
      ]);
      expect(f, hasLength(kSendFrequentMax));
      expect(f.first.name, 'Joana Kute');
      expect(f.first.contact?.id, 'k1');
      expect(f[1].name, 'rita');
      expect(f[2].name, 'alice');
    });
    test('A–Z: filed by the first letter, accents folded, each letter by '
        'name, "#" last', () {
      final groups = sendAlphabetical([
        const SendPerson(id: '1', name: 'Rui'),
        const SendPerson(id: '2', name: 'Álvaro'),
        const SendPerson(id: '3', name: 'ana'),
        const SendPerson(id: '4', name: '+351 912'),
        const SendPerson(id: '5', name: 'Bea'),
      ]);
      expect([for (final g in groups) g.$1], ['A', 'B', 'R', '#']);
      expect([for (final p in groups.first.$2) p.name], ['ana', 'Álvaro']);
    });
    test('an initials avatar\'s tint is the same for a name every time, '
        'one of six', () {
      final a = sendAvatarTintIndex('Maria Alves');
      expect(sendAvatarTintIndex('Maria Alves'), a);
      expect(sendAvatarTintIndex('  maria alves '), a);
      for (final n in ['Ana', 'Rui', 'Joana Kute', 'x', '']) {
        expect(sendAvatarTintIndex(n), inInclusiveRange(0, 5));
      }
      final c = AppColorsExtension.light();
      expect(sendAvatarTint(c, 'Rui Santos'),
          c.chartCategorical[sendAvatarTintIndex('Rui Santos')]);
      // Not all one colour.
      expect(
          {for (final n in ['Ana', 'Rui', 'Maria', 'Joana', 'Bea', 'Tó'])
            sendAvatarTintIndex(n)}.length,
          greaterThan(1));
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
    test('an @ address splits into its name and its domain; nothing else '
        'does', () {
      expect(sendAtAddressParts('jay2290@paykute.com'),
          (name: 'jay2290', domain: 'paykute.com'));
      expect(sendAtAddressParts(' lightning:Jay2290@PayKute.com '),
          (name: 'Jay2290', domain: 'paykute.com'));
      expect(sendAtAddressParts('pipinho@walletofsatoshi.com'),
          (name: 'pipinho', domain: 'walletofsatoshi.com'));
      for (final other in [
        'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        'spark1pgss9qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
        '0x742d35cc6634c0532925a3b844bc454e4438f44e',
        'lnurl1dp68gurn8ghj7ctsdyh85etzv4jx2efwd9hj7',
        'lnbc1pvjluezsp5zyg3zyg3zyg3',
        'jay@localhost',
        '@paykute.com',
        '',
      ]) {
        expect(sendAtAddressParts(other), isNull, reason: other);
      }
    });
    test('the saved name: a contact\'s own, never a label that is only the '
        'handle or the address', () {
      final contact = sendMatchingPerson('joana@paykute.com',
          recents: _recents(), contacts: [_kuteContact]);
      expect(sendSavedName(contact, 'joana@paykute.com', handle: 'joana'),
          'Joana Kute');
      final recent = sendMatchingPerson('alice@getalby.com',
          recents: _recents(), contacts: fakeContacts());
      expect(sendSavedName(recent, 'alice@getalby.com', handle: 'alice'),
          isNull);
      expect(sendSavedName(null, 'x@y.io', handle: 'x'), isNull);
      expect(
          sendSavedName(
              SendPerson.recent(
                  address: 'x@y.io', name: 'x@y.io', secondary: 'x@y.io'),
              'x@y.io',
              handle: 'x'),
          isNull);
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
        {String? rail = 'Lightning',
        String? kindLine,
        SendPersonBadge? badge}) async {
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
                  kindLine: kindLine,
                  badge: badge,
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

    String secondLine(WidgetTester tester) => tester
        .widget<SendMiddleEllipsisText>(
            find.byKey(const ValueKey('send-recipient-address')))
        .text;

    testWidgets(
        'an address with no saved name says what it is under it, not itself',
        (tester) async {
      await pumpCard(tester, 'new@getalby.com',
          rail: null, kindLine: 'Lightning address');
      expect(secondLine(tester), 'Lightning address');
      expect(find.byKey(const ValueKey('send-badge-lightning')), findsOneWidget);
    });

    testWidgets('an email wears no Lightning badge', (tester) async {
      await pumpCard(tester, 'anna@gmail.com',
          rail: null,
          kindLine: 'Email, no Lightning address',
          badge: SendPersonBadge.none);
      expect(secondLine(tester), 'Email, no Lightning address');
      expect(find.byKey(const ValueKey('send-badge-lightning')), findsNothing);
    });

    testWidgets('a saved contact keeps its address under its name',
        (tester) async {
      await pumpCard(tester, 'joana@paykute.com',
          rail: null, kindLine: 'Lightning address');
      expect(name(tester), 'Joana Kute');
      expect(secondLine(tester), 'joana@paykute.com');
    });

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

    testWidgets(
        'with no rail the card draws no chip (progressive disclosure: '
        'Lightning or on-chain waits for Review)', (tester) async {
      await pumpCard(tester, 'joana@paykute.com', rail: null);
      expect(name(tester), 'Joana Kute');
      expect(find.byKey(const ValueKey('send-recipient-rail')), findsNothing);
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

  // The Review's From and To (founder, 7 November 2026: "make this more
  // with the square cards we have now"), both Sends alike.
  group('the review', () {
    const ln = 'pipinho@walletofsatoshi.com';
    const btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
    const from = ValueKey('send-review-from');
    const to = ValueKey('send-review-to');

    Future<List<String>> pump(WidgetTester tester, String address,
        {String? toLine,
        bool dark = false,
        double width = 375,
        double textScale = 1,
        bool withToggle = true}) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      // The app's own type: the squares' fit is measured in it.
      await tester.runAsync(() async {
        final inter = FontLoader('Inter');
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      });
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final calls = <String>[];
      final gateway = FakeSendContactsGateway(
          permission: SendContactsPermission.granted,
          contacts: [...fakeContacts(), _kuteContact]);
      var expanded = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [sendContactsGatewayProvider.overrideWithValue(gateway)],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(fontFamily: 'Inter', extensions: [
              dark ? AppColorsExtension.dark() : AppColorsExtension.light()
            ]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SendReviewRoute(
                      fromVisual: const Icon(Icons.pets_rounded, size: 36),
                      fromTitle: 'Bitcoin',
                      fromLine: 'Available · 361,694 sats',
                      toVisual: SendRecipientAvatar(
                        address: address,
                        railMark: const Icon(Icons.alternate_email_rounded),
                        recents: _recents(),
                      ),
                      address: address,
                      toLine: toLine,
                      expanded: expanded,
                      onToggle: withToggle
                          ? () {
                              calls.add('toggle');
                              setState(() => expanded = !expanded);
                            }
                          : null,
                      onCopied: () => calls.add('copied'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SendReviewRoute)));
      await container.read(sendContactsProvider.notifier).refresh();
      await tester.pump();
      return calls;
    }

    Finder inCard(ValueKey<String> card, Finder matching) =>
        find.descendant(of: find.byKey(card), matching: matching);

    String shownAddress(WidgetTester tester) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('send-review-to-address')),
            matching: find.byType(Text)))
        .data!;

    testWidgets(
        'From and To are two squares side by side, equally tall, no '
        'chevrons: the label over the main line; an @ address reads its '
        'name WHOLE over "@domain", never cut, no "Lightning"',
        (tester) async {
      await pump(tester, ln, toLine: 'Lightning');
      final a = tester.getRect(find.byKey(from));
      final b = tester.getRect(find.byKey(to));
      expect(a.top, b.top);
      expect(a.height, b.height);
      expect(b.left, greaterThan(a.right));
      expect(inCard(from, find.text('From')), findsOneWidget);
      expect(inCard(from, find.text('Bitcoin')), findsOneWidget);
      expect(inCard(from, find.text('Available · 361,694 sats')),
          findsOneWidget);
      expect(inCard(to, find.text('To')), findsOneWidget);
      expect(inCard(to, find.text('pipinho')), findsOneWidget);
      expect(inCard(to, find.text('@walletofsatoshi.com')), findsOneWidget);
      expect(inCard(to, find.text('Lightning')), findsNothing);
      expect(find.byKey(const ValueKey('send-review-to-address')),
          findsNothing);
      expect(inCard(to, find.textContaining('…')), findsNothing);
      expect(tester.widget<Text>(find.text('pipinho')).overflow, isNull);
      // The whole address is what is read out.
      expect(tester.getSemantics(find.byKey(to)),
          isSemantics(label: 'To, $ln', isButton: true));
      // A Lightning address nobody known has: the rail's mark, the ⚡.
      expect(inCard(to, find.byIcon(Icons.alternate_email_rounded)),
          findsOneWidget);
      expect(inCard(to, find.byKey(const ValueKey('send-badge-lightning'))),
          findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a plain bitcoin address has no line under it (the default network '
        'says nothing)', (tester) async {
      await pump(tester, btc);
      expect(inCard(to, find.text('To')), findsOneWidget);
      // Not an @ address: still ONE line in its middle form.
      expect(shownAddress(tester), contains('…'));
      expect(shownAddress(tester).startsWith('bc1q'), isTrue);
      expect(shownAddress(tester).endsWith('mdq'), isTrue);
      final line = tester.getRect(find.descendant(
          of: find.byKey(const ValueKey('send-review-to-address')),
          matching: find.byType(Text)));
      expect(line.height,
          lessThan(1.5 * tester.getRect(find.text('Bitcoin')).height));
      expect(inCard(to, find.byType(Text)), findsNWidgets(2),
          reason: 'the label and the address, nothing under them');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a saved contact\'s address wears the contact\'s face and badge, '
        'its name over "@paykute.com"', (tester) async {
      await pump(tester, 'joana@paykute.com', toLine: 'Lightning');
      expect(inCard(to, find.text('JK')), findsOneWidget);
      expect(inCard(to, find.byKey(const ValueKey('send-badge-kute'))),
          findsOneWidget);
      expect(inCard(to, find.text('Joana Kute')), findsOneWidget);
      expect(inCard(to, find.text('@paykute.com')), findsOneWidget);
      expect(inCard(to, find.text('joana')), findsNothing);
      expect(inCard(to, find.text('Lightning')), findsNothing);
      expect(tester.getSemantics(find.byKey(to)),
          isSemantics(label: 'To, Joana Kute, joana@paykute.com'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a Kute address nobody saved: the name before the @ whole, '
        '"@paykute.com" under it, the Kute badge; a tap still shows the '
        'whole address with Copy', (tester) async {
      const kute = 'jay2290@paykute.com';
      await pump(tester, kute, toLine: 'Lightning');
      expect(inCard(to, find.text('jay2290')), findsOneWidget);
      expect(inCard(to, find.text('@paykute.com')), findsOneWidget);
      expect(inCard(to, find.byKey(const ValueKey('send-badge-kute'))),
          findsOneWidget);
      await tester.tap(find.byKey(to));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-review-full-address')),
              matching: find.text(kute)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a name too long for a square at 320 pt: the pair goes full width '
        'and the name still reads whole', (tester) async {
      const long = 'satoshinakamotothegreatest@getalby.com';
      await pump(tester, long, toLine: 'Lightning', width: 320);
      expect(inCard(to, find.text('satoshinakamotothegreatest')),
          findsOneWidget);
      expect(inCard(to, find.text('@getalby.com')), findsOneWidget);
      // Two full-width cards, one over the other.
      expect(tester.getRect(find.byKey(to)).top,
          greaterThan(tester.getRect(find.byKey(from)).bottom));
      expect(inCard(to, find.textContaining('…')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a tap on To shows the whole address with Copy under the pair, Copy '
        'reports, a second tap hides it; From only states', (tester) async {
      final calls = await pump(tester, btc);
      expect(
          tester.getSemantics(find.byKey(from)),
          isSemantics(
              label: 'From, Bitcoin, Available · 361,694 sats',
              isButton: false));
      expect(tester.getSemantics(find.byKey(to)),
          isSemantics(label: 'To, $btc', isButton: true));
      await tester.tap(find.byKey(from));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(
          find.byKey(const ValueKey('send-review-full-address')), findsNothing);

      await tester.tap(find.byKey(to));
      await tester.pumpAndSettle();
      final full = find.byKey(const ValueKey('send-review-full-address'));
      expect(full, findsOneWidget);
      expect(find.descendant(of: full, matching: find.text(btc)),
          findsOneWidget);
      expect(tester.getRect(full).top,
          greaterThan(tester.getRect(find.byKey(to)).bottom));
      await tester.tap(find.text(_l10n.copy));
      await tester.pump();
      expect(calls, ['toggle', 'copied']);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.byKey(to));
      await tester.pumpAndSettle();
      expect(full, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with nothing to show, To only states', (tester) async {
      final calls = await pump(tester, btc, withToggle: false);
      expect(tester.getSemantics(find.byKey(to)),
          isSemantics(isButton: false));
      await tester.tap(find.byKey(to));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      testWidgets(
          '${dark ? 'dark' : 'light'}, 320 pt at 1.3x: nothing cut or '
          'overflowing; the pair stays squares or goes full width, never '
          'a chevron on From; the @ address whole, a bitcoin address in its '
          'middle form', (tester) async {
        await pump(tester, ln,
            toLine: 'Lightning', dark: dark, width: 320, textScale: 1.3);
        final title = tester.widget<Text>(find.text('Bitcoin'));
        expect(title.maxLines, isNull);
        expect(title.overflow, isNull);
        expect(inCard(from, find.byIcon(Icons.chevron_right_rounded)),
            findsNothing);
        expect(inCard(to, find.text('pipinho')), findsOneWidget);
        expect(inCard(to, find.text('@walletofsatoshi.com')), findsOneWidget);
        expect(inCard(to, find.textContaining('…')), findsNothing);
        expect(tester.takeException(), isNull);

        await pump(tester, btc, dark: dark, width: 320, textScale: 1.3);
        expect(shownAddress(tester), contains('…'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

final _l10n = lookupAppLocalizations(const Locale('en'));
