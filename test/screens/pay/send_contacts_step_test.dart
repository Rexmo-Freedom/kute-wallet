// The bitcoin send's recipient-first Send to step (send_recipient_step
// .dart): "Send" as the title with no step bar, the search field with
// Paste and Scan inside, and ONE link row on the Send to card, "Send to a
// friend" with Sal's share face (no Send to anyone row, no Contacts
// section). The row prompts for the contacts permission on tap (never on
// open) and opens the contacts picker with "Someone else" at its top; the
// picker offers Settings once refused for good and asks again after a
// refusal the system allows; a typed name lists the matching contacts
// inline under the field; a picked contact starts Send to anyone with
// the first name as the label and the number kept on the phone only;
// "Someone else" starts it plain.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCloseButton;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendSalShareGlyph;
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

Future<void> _pump(WidgetTester tester) async {
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

  testWidgets(
      'the step: "Send" centred over a circled close, no step bar, the '
      'search field with Paste and Scan inside, one "Send to a friend" row '
      'with Sal\'s share face on the card, no Send to anyone, no Contacts',
      (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.send), findsOneWidget);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(find.byType(StepperProgress), findsNothing);
    expect(find.byKey(const ValueKey('send-recipient-search')), findsOneWidget);
    expect(find.text(_l10n.sendRecipientSearchHint), findsOneWidget);
    expect(find.byKey(const ValueKey('send-field-paste')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-field-scan')), findsOneWidget);
    expect(find.text(_l10n.sendToLabel), findsOneWidget);
    final friend = find.byKey(const ValueKey('send-to-friend-row'));
    expect(friend, findsOneWidget);
    expect(find.text(_l10n.sendToAFriend), findsOneWidget);
    expect(find.text(_l10n.sendToAFriendSub), findsOneWidget);
    expect(find.descendant(of: friend, matching: find.byType(SendSalShareGlyph)),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-to-anyone-row')), findsNothing);
    expect(_text(_l10n.shareSendToAnyone), findsNothing);
    expect(_text(_l10n.sendContacts), findsNothing);
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsNothing);
    // Bitcoin stays bitcoin: no prediction or investment row here.
    expect(find.byKey(const ValueKey('send-pick-market-row')), findsNothing);
  });

  testWidgets(
      'before the permission: "Send to a friend" prompts on tap only, then '
      'opens the picker with "Someone else" first and the contacts under',
      (tester) async {
    await _pump(tester);
    expect(_gateway.prompts, 0);
    expect(find.text('Maria Alves'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('send-to-friend-row')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 1);
    expect(_paramsOf('send_contacts_permission').single,
        containsPair('granted', true));
    final someoneElse = find.byKey(const ValueKey('send-contacts-someone-else'));
    expect(someoneElse, findsOneWidget);
    expect(find.text(_l10n.sendSomeoneElse), findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-picker-search')),
        findsOneWidget);
    expect(_text('Ana Costa'), findsOneWidget);
    expect(_text('Maria Alves'), findsOneWidget);
    expect(_text('Rui Santos'), findsOneWidget);
    // "Someone else" sits above the first contact.
    expect(
        tester.getTopLeft(someoneElse).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('send-contact-pick-c1')))
            .dy));
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsNothing);
  });

  testWidgets('refused for good: the picker offers Settings, no prompt',
      (tester) async {
    _gateway.permission = SendContactsPermission.blocked;
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('send-to-friend-row')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 0);
    expect(find.byKey(const ValueKey('send-contacts-someone-else')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-settings')),
        findsOneWidget);
    expect(find.text(_l10n.sendAllowContactsInSettings), findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-picker-search')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('send-contacts-settings')));
    await tester.pumpAndSettle();
    expect(_gateway.settingsOpened, 1);
    expect(_gateway.prompts, 0);
  });

  testWidgets('a refusal the system can ask again: the picker asks again',
      (tester) async {
    _gateway.answer = SendContactsPermission.denied;
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('send-to-friend-row')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 1);
    expect(_paramsOf('send_contacts_permission').single,
        containsPair('granted', false));
    expect(find.byKey(const ValueKey('send-contacts-someone-else')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsOneWidget);
    expect(_text('Maria Alves'), findsNothing);

    _gateway.answer = SendContactsPermission.granted;
    await tester.tap(find.byKey(const ValueKey('send-contacts-ask')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 2);
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsNothing);
    expect(_text('Maria Alves'), findsOneWidget);
  });

  testWidgets(
      'with the book in hand a typed name lists the matches inline, with no '
      'Contacts header, and a picked contact opens Send to anyone with the '
      'first name, the number staying on the phone', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await _pump(tester);
    // Nothing of the book while the field is empty.
    expect(_text('Maria Alves'), findsNothing);
    expect(_text(_l10n.sendContacts), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'mar');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-contact-matches'), skipOffstage: false),
        findsOneWidget);
    expect(_text('Maria Alves'), findsOneWidget);
    expect(_text('Rui Santos'), findsNothing);
    expect(_text('Ana Costa'), findsNothing);
    expect(_text(_l10n.sendContacts), findsNothing);

    // Digits match the number too.
    await tester.enterText(find.byType(TextField).first, '913');
    await tester.pumpAndSettle();
    expect(_text('Rui Santos'), findsOneWidget);
    expect(_text('Maria Alves'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'mar');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_text('Maria Alves'));
    await tester.pumpAndSettle();
    await tester.tap(_text('Maria Alves'));
    await tester.pumpAndSettle();
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(_paramsOf('send_recipient_picked').single,
        containsPair('kind', 'contact'));
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.kind.name, 'bitcoin');
    expect(sheet.senderLabel, 'Maria');
    expect(sheet.recipientPhone, '+351 912 345 678');
    // The number is never an event param.
    for (final e in _events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
  });

  testWidgets(
      '"Someone else" in the picker opens the plain Send to anyone sheet',
      (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('send-to-friend-row')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 0);
    await tester.tap(find.byKey(const ValueKey('send-contacts-someone-else')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-contacts-picker-search')),
        findsNothing);
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.kind.name, 'bitcoin');
    expect(sheet.senderLabel, isNull);
    expect(sheet.recipientPhone, isNull);
    expect(_paramsOf('send_recipient_picked'), isEmpty);
  });
}
