// The payee Branta names, on Send's existing cards
// (send_branta_payee.dart; founder, 12 November 2026): the recipient card,
// the Review's To square (its avatar too), the Dollars Send's resolved row
// and its coin visual. Verified: the logo in the avatar's circle, the
// name, "Verified by Branta", the address still read. Unverified, or with
// no rail: exactly as before, and no lookup at all without a rail. A
// swapped address: the inline warning. A logo that fails keeps the rail's
// mark, in a circle of the same size.

import 'dart:convert';
import 'dart:typed_data';

import 'package:branta/branta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendResolvedRow;
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../mocks/fake_send_contacts_gateway.dart';

const _invoice = 'lnbc17760n1p4r4flypp5k56kq3v2935rl3glkqu9vngfueud2zj87hjcff3t0k';
const _addr = 'bc1q6745z6cy3u0k9nprurh3x804c4r7u3u8vxca2n';
const _code = 'bitcoin:$_addr?branta_id=Qy4e&branta_secret=f9b0';
const _evm = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
const _logo = 'https://guardrail.branta.pro/logo.png';

final _l10n = AppLocalizationsEn();

/// A 1×1 PNG, the logo drawn from memory.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

VerifyResult _match(String value, DestinationType type) => VerifyResult(
      status: VerifyStatus.match,
      payments: [
        Payment(
          destinations: [
            Destination(value: value, type: type, isEncrypted: false)
          ],
          platform: 'Bitfinex',
          platformLogoUrl: _logo,
        ),
      ],
      matchedDestinations: [
        Destination(value: value, type: type, isEncrypted: false)
      ],
      verifyUrl: '',
    );

/// The service the widgets read, answering [answer] and counting lookups.
class _Branta {
  _Branta(this.answer);
  VerifyResult Function(String input) answer;
  int calls = 0;
  late final service = BrantaPayeeService(verifier: (input) async {
    calls++;
    return answer(input);
  });
}

Future<void> _pump(WidgetTester tester, _Branta branta, Widget child,
    {bool dark = false}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sendContactsGatewayProvider.overrideWithValue(FakeSendContactsGateway(
          permission: SendContactsPermission.granted, contacts: const [])),
      brantaPayeeServiceProvider.overrideWithValue(branta.service),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    ),
  ));
  // The lookup answers on a microtask; the card redraws after it.
  await tester.pump();
  await tester.pump();
}

Widget _card(String address, {BrantaRail? rail}) => SendRecipientCard(
      address: address,
      railMark: const Icon(Icons.bolt_rounded, key: ValueKey('rail-mark')),
      recents: const [],
      onChange: () {},
      brantaRail: rail,
    );

Widget _review(String address, {BrantaRail? rail}) => SendReviewRoute(
      fromVisual: const Icon(Icons.pets_rounded, size: 36),
      fromTitle: 'Bitcoin',
      fromLine: 'Available · 361,694 sats',
      toVisual: SendRecipientAvatar(
        address: address,
        railMark: const Icon(Icons.bolt_rounded, key: ValueKey('rail-mark')),
        recents: const [],
        brantaRail: rail,
      ),
      address: address,
      toLine: 'Lightning',
      brantaRail: rail,
    );

String _name(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('send-recipient-name')))
    .data!;

void main() {
  setUp(() {
    BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(_png);
  });
  tearDown(() => BrantaPayeeLogo.debugImageProvider = null);

  group('the recipient card', () {
    testWidgets('verified: the logo in the circle, the name, the line, the '
        'address', (tester) async {
      final branta = _Branta((_) => _match(_invoice, DestinationType.bolt11));
      await _pump(tester, branta, _card(_invoice, rail: BrantaRail.lightning));
      expect(_name(tester), 'Bitfinex');
      expect(find.text(_l10n.sendVerifiedByBranta), findsOneWidget);
      expect(find.byKey(const ValueKey('send-branta-logo')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-avatar-circle')),
              matching: find.byKey(const ValueKey('send-branta-logo'))),
          findsOneWidget);
      // The address is still read, on one line.
      final line = tester.widget<SendMiddleEllipsisText>(
          find.byKey(const ValueKey('send-recipient-address')));
      expect(line.text, _invoice);
      expect(line.maxLines, 1);
      expect(branta.calls, 1);
    });

    testWidgets('a scanned on-chain code: verified by its Branta params',
        (tester) async {
      final branta =
          _Branta((_) => _match(_addr, DestinationType.bitcoinAddress));
      branta.service.noteInput(_code);
      await _pump(
          tester, branta, _card(_addr, rail: BrantaRail.bitcoinOnchain));
      expect(_name(tester), 'Bitfinex');
    });

    testWidgets('unverified: exactly as before', (tester) async {
      final branta = _Branta(
          (_) => const VerifyResult(status: VerifyStatus.unknown, verifyUrl: ''));
      await _pump(tester, branta, _card(_invoice, rail: BrantaRail.lightning));
      expect(_name(tester), sendShortAddress(_invoice));
      expect(find.text(_l10n.sendVerifiedByBranta), findsNothing);
      expect(find.byKey(const ValueKey('send-branta-logo')), findsNothing);
      expect(find.byKey(const ValueKey('rail-mark')), findsOneWidget);
      expect(find.text(_l10n.sendBrantaTampered), findsNothing);
      expect(
          tester
              .widget<SendMiddleEllipsisText>(
                  find.byKey(const ValueKey('send-recipient-address')))
              .maxLines,
          2);
    });

    testWidgets('no rail: no lookup, the card as it always was',
        (tester) async {
      final branta = _Branta((_) => _match(_invoice, DestinationType.bolt11));
      await _pump(tester, branta, _card(_invoice));
      expect(branta.calls, 0);
      expect(find.text(_l10n.sendVerifiedByBranta), findsNothing);
    });

    testWidgets('verified for another rail: nothing', (tester) async {
      final branta =
          _Branta((_) => _match(_evm, DestinationType.usdtPolygon));
      branta.service.noteInput('pol:$_evm?branta_id=a&branta_secret=b');
      await _pump(tester, branta, _card(_evm, rail: BrantaRail.usdcPolygon));
      expect(find.text('Bitfinex'), findsNothing);
      expect(find.text(_l10n.sendVerifiedByBranta), findsNothing);
    });

    testWidgets('a swapped address: the inline warning, no payee',
        (tester) async {
      final branta = _Branta((_) =>
          const VerifyResult(status: VerifyStatus.tampered, verifyUrl: ''));
      branta.service.noteInput(_code);
      await _pump(
          tester, branta, _card(_addr, rail: BrantaRail.bitcoinOnchain));
      expect(find.text(_l10n.sendBrantaTampered), findsOneWidget);
      expect(find.byKey(const ValueKey('send-inline-error')), findsOneWidget);
      expect(find.text(_l10n.sendVerifiedByBranta), findsNothing);
      expect(_name(tester), sendShortAddress(_addr));
    });

    testWidgets('a logo that fails keeps the rail mark, the circle unchanged',
        (tester) async {
      BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(
          Uint8List.fromList(const [1, 2, 3]));
      final branta = _Branta((_) => _match(_invoice, DestinationType.bolt11));
      await _pump(tester, branta, _card(_invoice, rail: BrantaRail.lightning));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump();
      expect(_name(tester), 'Bitfinex');
      expect(find.byKey(const ValueKey('rail-mark')), findsOneWidget);
      // The avatar's own circle, 44 across as always; the logo's box
      // fills it inside its hairline border.
      final circle =
          tester.getRect(find.byKey(const ValueKey('send-avatar-circle')));
      expect(circle.size, Size(44.sp, 44.sp));
      final logo =
          tester.getRect(find.byKey(const ValueKey('send-branta-logo')));
      expect(circle.inflate(0.01).contains(logo.topLeft), isTrue);
      expect(circle.inflate(0.01).contains(logo.bottomRight), isTrue);
      expect(logo.width, closeTo(circle.width, 1.01));
    });

    testWidgets('dark: the same verified card', (tester) async {
      final branta = _Branta((_) => _match(_invoice, DestinationType.bolt11));
      await _pump(tester, branta, _card(_invoice, rail: BrantaRail.lightning),
          dark: true);
      expect(_name(tester), 'Bitfinex');
      expect(find.text(_l10n.sendVerifiedByBranta), findsOneWidget);
    });
  });

  group('the Review', () {
    testWidgets('verified: the name over "Verified by Branta" and the short '
        'address; the To avatar wears the logo', (tester) async {
      final branta = _Branta((_) => _match(_invoice, DestinationType.bolt11));
      await _pump(
          tester, branta, _review(_invoice, rail: BrantaRail.lightning));
      expect(find.text('Bitfinex'), findsOneWidget);
      expect(
          find.text('${_l10n.sendVerifiedByBranta}\n'
              '${sendShortAddress(_invoice)}'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-review-to-address')),
          findsNothing);
      expect(find.text('Lightning'), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('send-review-to')),
              matching: find.byKey(const ValueKey('send-branta-logo'))),
          findsOneWidget);
      // One lookup feeds both the square and its avatar.
      expect(branta.calls, 1);
    });

    testWidgets('unverified: the address in its middle form, the rail line',
        (tester) async {
      final branta = _Branta(
          (_) => const VerifyResult(status: VerifyStatus.unknown, verifyUrl: ''));
      await _pump(
          tester, branta, _review(_invoice, rail: BrantaRail.lightning));
      expect(find.byKey(const ValueKey('send-review-to-address')),
          findsOneWidget);
      expect(find.text('Lightning'), findsOneWidget);
      expect(find.text('Bitfinex'), findsNothing);
      expect(find.byKey(const ValueKey('send-branta-logo')), findsNothing);
    });

    testWidgets('a swapped address: the warning under the squares',
        (tester) async {
      final branta = _Branta((_) =>
          const VerifyResult(status: VerifyStatus.tampered, verifyUrl: ''));
      branta.service.noteInput(_code);
      await _pump(tester, branta, _review(_addr, rail: BrantaRail.bitcoinOnchain));
      expect(find.text(_l10n.sendBrantaTampered), findsOneWidget);
      expect(find.byKey(const ValueKey('send-review-to-address')),
          findsOneWidget);
    });
  });

  group('the Dollars Send', () {
    testWidgets('the resolved row and the coin visual: USDC on Polygon',
        (tester) async {
      final branta =
          _Branta((_) => _match(_evm, DestinationType.usdcPolygon));
      branta.service.noteInput('pol:$_evm?branta_id=a&branta_secret=b');
      final rail = brantaRailFor(assetCode: 'USDC', chain: 'polygon');
      await _pump(
          tester,
          branta,
          Column(children: [
            SendResolvedRow(
              leading: const Icon(Icons.attach_money, key: ValueKey('coin')),
              address: _evm,
              rail: 'USDC on Polygon',
              brantaRail: rail,
            ),
            SendBrantaPayeeVisual(
              address: _evm,
              brantaRail: rail,
              size: 40,
              child: const Icon(Icons.attach_money, key: ValueKey('coin2')),
            ),
          ]));
      expect(find.text('Bitfinex'), findsOneWidget);
      expect(
          find.text('${_l10n.sendVerifiedByBranta} · '
              '${sendShortAddress(_evm)}'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-branta-logo')), findsNWidgets(2));
    });

    testWidgets('USDC on Base: no rail, the row as it always was',
        (tester) async {
      final branta =
          _Branta((_) => _match(_evm, DestinationType.usdcPolygon));
      final rail = brantaRailFor(assetCode: 'USDC', chain: 'base');
      expect(rail, isNull);
      await _pump(
          tester,
          branta,
          SendResolvedRow(
            leading: const Icon(Icons.attach_money, key: ValueKey('coin')),
            address: _evm,
            rail: 'USDC on Base',
            brantaRail: rail,
          ));
      expect(find.text(sendShortAddress(_evm)), findsOneWidget);
      expect(find.text('USDC on Base'), findsOneWidget);
      expect(find.byKey(const ValueKey('coin')), findsOneWidget);
      expect(branta.calls, 0);
    });
  });

  test('every locale says it', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.sendVerifiedByBranta, contains('Branta'),
          reason: locale.toString());
      expect(l10n.sendBrantaTampered, contains('Branta'),
          reason: locale.toString());
      if (locale.languageCode != 'en') {
        expect(l10n.sendVerifiedByBranta,
            isNot(AppLocalizationsEn().sendVerifiedByBranta),
            reason: locale.toString());
      }
    }
  });
}
