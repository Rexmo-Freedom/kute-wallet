// The bitcoin send's recipient-first Send to step (send_recipient_step
// .dart): "Send" as the title with no step bar, the search field with
// Paste and Scan inside, the Send to card with Send to anyone, and the
// Contacts section in every state of the permission: the "Send to a
// friend" row that prompts on tap (never on open), the Settings row once
// refused for good, the matches filtered by the field, and a picked
// contact starting Send to anyone with the first name as the label and
// the number kept on the phone only.

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
    _gateway = FakeSendContactsGateway(contacts: fakeContacts());
    _api = FakeShareLinksApi();
    _events = [];
    TrackingService.debugTrackObserver = (e, p) => _events.add((e, p));
    ShareLinksStore.debugMemory = <String, String>{};
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    ShareLinksStore.debugMemory = null;
  });

  testWidgets(
      'the step: "Send" centred over a circled close, no step bar, the '
      'search field with Paste and Scan inside, Send to anyone on the card',
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
    expect(find.byKey(const ValueKey('send-to-anyone-row')), findsOneWidget);
    // Bitcoin stays bitcoin: no prediction or investment row here.
    expect(find.byKey(const ValueKey('send-pick-market-row')), findsNothing);
  });

  testWidgets(
      'before the permission: "Send to a friend" prompts on tap only, and '
      'a granted prompt lists the contacts', (tester) async {
    await _pump(tester);
    expect(_gateway.prompts, 0);
    expect(find.text(_l10n.sendContacts), findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsOneWidget);
    expect(find.text(_l10n.sendToAFriend), findsOneWidget);
    expect(find.text('Maria Alves'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('send-contacts-ask')));
    await tester.pumpAndSettle();
    expect(_gateway.prompts, 1);
    expect(_paramsOf('send_contacts_permission').single,
        containsPair('granted', true));
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsNothing);
    expect(_text('Ana Costa'), findsOneWidget);
    expect(_text('Maria Alves'), findsOneWidget);
    expect(_text('Rui Santos'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-contacts-see-all'), skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('refused for good: the row opens Settings', (tester) async {
    _gateway.permission = SendContactsPermission.blocked;
    await _pump(tester);
    expect(find.byKey(const ValueKey('send-contacts-settings')),
        findsOneWidget);
    expect(find.text(_l10n.sendAllowContactsInSettings), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-contacts-settings')));
    await tester.pumpAndSettle();
    expect(_gateway.settingsOpened, 1);
    expect(_gateway.prompts, 0);
  });

  testWidgets('a refusal the system can ask again keeps the ask row',
      (tester) async {
    _gateway.answer = SendContactsPermission.denied;
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('send-contacts-ask')));
    await tester.pumpAndSettle();
    expect(_paramsOf('send_contacts_permission').single,
        containsPair('granted', false));
    expect(find.byKey(const ValueKey('send-contacts-ask')), findsOneWidget);
  });

  testWidgets(
      'with the book in hand the field filters the contacts by name, and a '
      'picked contact opens Send to anyone with the first name, the number '
      'staying on the phone', (tester) async {
    _gateway.permission = SendContactsPermission.granted;
    await _pump(tester);
    expect(_text('Maria Alves'), findsOneWidget);
    expect(_text('Rui Santos'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'mar');
    await tester.pumpAndSettle();
    expect(_text('Maria Alves'), findsOneWidget);
    expect(_text('Rui Santos'), findsNothing);
    expect(_text('Ana Costa'), findsNothing);

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
}
