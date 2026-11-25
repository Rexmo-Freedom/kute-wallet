// The Bitcoin Send with a payee Branta verifies (services/branta; founder,
// 12 November 2026): a Branta `bitcoin:` code typed or pasted into the
// field is kept bare by Send (the address only), yet the recipient card
// names the payee, by the code's own Branta params; a Lightning invoice
// is verified as itself. A plain address looks exactly as before, with
// no lookup. Analytics: `verified_payee`, a yes/no, never the address,
// the code's id or secret, nor the payee's name.

import 'dart:convert';
import 'dart:io';

import 'package:branta/branta.dart' hide Platform;
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
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../mocks/fake_send_contacts_gateway.dart';

final _l10n = AppLocalizationsEn();

const _addr = 'bc1qgw3dzmhnyvcswc9r0v0z0ajtp8ulm4nuyeahwr';
const _id = '6SpYCe23r79x0t8rNvmjWqhrg8hen4xz';
const _secret = '05eb145d-b5cb-452a-9256-0bdfd9a15ffa';
const _code = 'bitcoin:$_addr?branta_id=$_id&branta_secret=$_secret';
const _invoice =
    'lnbc10u1p4w23tzpp50uc6g4020tt3ffp5xfpp83k0lcv2spytpymuupqrnsj0eth8jqgsd'
    'qhgfexzmn5vys8xarpva5kuecxq97zvuqsp5tj2a5fd84lhdddzfqz2lwmjqg7n9gp28yy5';
const _plain = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

VerifyResult _match(String value, DestinationType type) => VerifyResult(
      status: VerifyStatus.match,
      payments: [
        Payment(
          destinations: [
            Destination(value: value, type: type, isEncrypted: false)
          ],
          platform: 'Strike',
          platformLogoUrl: 'https://guardrail.branta.pro/s.png',
        ),
      ],
      matchedDestinations: [
        Destination(value: value, type: type, isEncrypted: false)
      ],
      verifyUrl: '',
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 812) * 3;
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
      sendContactsGatewayProvider.overrideWithValue(
          FakeSendContactsGateway(contacts: const [])),
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

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pumpAndSettle();
}

Finder get _card => find.byKey(const ValueKey('send-recipient-card'),
    skipOffstage: false);

void main() {
  late Directory hiveDir;
  late BrantaPayeeService saved;
  late List<(String, Map<String, Object>?)> events;
  late List<String> inputs;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_branta');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalSpriteCache.debugSetManifest(null);
    BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(_png);
    saved = BrantaPayeeService.shared;
    inputs = [];
    BrantaPayeeService.shared = BrantaPayeeService(verifier: (input) async {
      inputs.add(input);
      if (input.toLowerCase().startsWith('lnbc')) {
        return _match(_invoice, DestinationType.bolt11);
      }
      return _match(_addr, DestinationType.bitcoinAddress);
    });
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SalSpriteCache.debugReset();
    BrantaPayeeLogo.debugImageProvider = null;
    BrantaPayeeService.shared = saved;
  });

  void expectNoLeak() {
    final forbidden = [
      _addr,
      _addr.substring(0, 14),
      _id.toLowerCase(),
      _secret,
      _invoice.substring(0, 24),
      'strike',
      'branta',
    ];
    for (final (name, params) in events) {
      final text =
          '$name ${jsonEncode(params?.map((k, v) => MapEntry(k, '$v')))}'
              .toLowerCase();
      for (final f in forbidden) {
        expect(text.contains(f), isFalse,
            reason: 'event "$name" carried "$f": $text');
      }
    }
  }

  testWidgets(
      'a Branta bitcoin: code: Send keeps the bare address, the card names '
      'the payee by the code', (tester) async {
    await _pump(tester);
    await _type(tester, _code);
    // The field holds the address alone (Send's own strip) ...
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!
        .text, _addr);
    // ... and the card the payee, looked up by the code as typed.
    expect(_card, findsOneWidget);
    expect(
        find.descendant(of: _card, matching: find.text('Strike')),
        findsOneWidget);
    expect(find.text(_l10n.sendVerifiedByBranta, skipOffstage: false),
        findsOneWidget);
    expect(
        find.descendant(
            of: _card,
            matching: find.byKey(const ValueKey('send-branta-logo'))),
        findsOneWidget);
    expect(inputs.toSet(), {_code});
    expectNoLeak();
  });

  testWidgets('a Lightning invoice: verified as itself', (tester) async {
    await _pump(tester);
    await _type(tester, _invoice);
    expect(find.descendant(of: _card, matching: find.text('Strike')),
        findsOneWidget);
    expect(inputs.toSet(), {_invoice});
    expectNoLeak();
  });

  testWidgets('a plain address: no lookup, the card as before',
      (tester) async {
    await _pump(tester);
    await _type(tester, _plain);
    expect(_card, findsOneWidget);
    expect(find.text('Strike', skipOffstage: false), findsNothing);
    expect(find.text(_l10n.sendVerifiedByBranta, skipOffstage: false),
        findsNothing);
    expect(inputs, isEmpty);
    final flags = events
        .where((e) => e.$2?.containsKey('verified_payee') ?? false)
        .map((e) => e.$2!['verified_payee'])
        .toSet();
    expect(flags, isNot(contains(true)));
  });

  test('the Send funnel property is a bool, never anything else', () {
    // The source carries it as brantaVerifiedPayee(...), a bool.
    final src = File('lib/screens/pay/components/confirm_send.dart')
        .readAsStringSync();
    expect(src, contains("'verified_payee': brantaVerifiedPayee("));
    final usd = File('lib/screens/usd/usd_send_screen.dart').readAsStringSync();
    expect(usd, contains("'verified_payee': d != null &&"));
    // Nothing in Branta's own code reaches analytics.
    for (final path in [
      'lib/services/branta/branta_payee_service.dart',
      'lib/screens/shared/send/send_branta_payee.dart',
    ]) {
      expect(File(path).readAsStringSync(), isNot(contains('TrackingService')),
          reason: path);
    }
  });
}
