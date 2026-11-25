// A look by eye at a payee Branta verifies (founder, 12 November 2026;
// send_branta_payee.dart), light and dark, written only when asked:
// SEND_BRANTA_RENDER=<dir>. The payee is Branta's own staging sample
// ("Branta", its logo read from SEND_BRANTA_LOGO=<png> when given, else a
// plain painted mark):
//
//   * "review_lightning": the Bitcoin Send's Review paying a Lightning
//     invoice: the To square wears the logo, the name, "Verified by
//     Branta" over the short invoice;
//   * "review_usdc_polygon": the Dollars Send's Review, USDC on Polygon;
//   * "card": the Who step's recipient card, verified, over the same card
//     unverified (the look it keeps), and the swapped-address warning.
//
//   for v in review_lightning review_usdc_polygon card; do for m in light \
//     dark; do SEND_BRANTA_RENDER=<dir> flutter test \
//     test/render/send_branta_render_test.dart --plain-name "$v $m"; done; done

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:branta/branta.dart' hide Platform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/kute_dog_asset.dart' show kuteDogLightAsset;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kInvestmentsIcon;
import 'package:kute/screens/pay/components/confirm_send.dart'
    show sendReviewFromMark;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/usd/usd_send_screen.dart'
    show usdSendDestinationMark;
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart'
    show UsdSendDestination;
import 'package:kute/theme/app_theme.dart';

import '../mocks/fake_send_contacts_gateway.dart';

final _dir = Platform.environment['SEND_BRANTA_RENDER'];
final _logoPath = Platform.environment['SEND_BRANTA_LOGO'];

const _invoice =
    'lnbc10u1p4w23tzpp50uc6g4020tt3ffp5xfpp83k0lcv2spytpymuupqrnsj0eth8jqgsd'
    'qhgfexzmn5vys8xarpva5kuecxq97zvuqsp5tj2a5fd84lhdddzfqz2lwmjqg7n9gp28yy5';
const _evm = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
const _addr = 'bc1qgw3dzmhnyvcswc9r0v0z0ajtp8ulm4nuyeahwr';
const _unverified = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

const _usdcPolygon = UsdSendDestination(
  assetCode: 'USDC',
  displayName: 'USD Coin',
  displaySymbol: 'USDC',
  chain: 'polygon',
  chainDisplayName: 'Polygon',
  decimals: 6,
);

VerifyResult _match(String value, DestinationType type) => VerifyResult(
      status: VerifyStatus.match,
      payments: [
        Payment(
          destinations: [
            Destination(value: value, type: type, isEncrypted: false)
          ],
          platform: 'Branta',
          platformLogoUrl: 'https://guardrail.branta.pro/logo.png',
        ),
      ],
      matchedDestinations: [
        Destination(value: value, type: type, isEncrypted: false)
      ],
      verifyUrl: '',
    );

/// Branta's answers for the page: the invoice, the Polygon address and
/// [_addr] verified; [_unverified] unknown; the swapped code tampered.
BrantaPayeeService _branta() {
  final service = BrantaPayeeService(verifier: (input) async {
    final lower = input.toLowerCase();
    if (lower.contains('swapped')) {
      return const VerifyResult(status: VerifyStatus.tampered, verifyUrl: '');
    }
    if (lower.startsWith('lnbc')) {
      return _match(_invoice, DestinationType.bolt11);
    }
    if (lower.startsWith('pol:')) {
      return _match(_evm, DestinationType.usdcPolygon);
    }
    return _match(_addr, DestinationType.bitcoinAddress);
  });
  service
    ..noteInput('pol:$_evm?branta_id=a&branta_secret=b')
    ..noteInput('bitcoin:$_addr?branta_id=a&branta_secret=b')
    ..noteInput('bitcoin:$_unverified?branta_id=swapped&branta_secret=b');
  return service;
}

Future<Uint8List> _logo(WidgetTester tester) async {
  final path = _logoPath;
  if (path != null && File(path).existsSync()) {
    return File(path).readAsBytesSync();
  }
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128),
        Paint()..color = Colors.white);
    canvas.drawRect(const Rect.fromLTWH(24, 40, 80, 48),
        Paint()..color = const Color(0xFFB8903C));
    final image = await recorder.endRecording().toImage(128, 128);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }))!;
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

/// One Review page as the steps lay it out: the hero, the squares, the
/// fee card, the footnote.
Widget _review(BuildContext context,
    {required String hero,
    required Widget route,
    required List<(String, String)> fees,
    Widget? chip}) {
  final c = context.colors;
  return Container(
    decoration: AppDecorations.screenGradient(context),
    padding: EdgeInsets.fromLTRB(20.w, 60.h, 20.w, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Center(
              child: Text(hero, style: sendHeroAmountStyle(c.textPrimary))),
        ),
        if (chip != null) ...[
          SizedBox(height: 4.h),
          Center(child: chip),
        ],
        SizedBox(height: 20.h),
        route,
        SizedBox(height: 14.h),
        SendReviewCard(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Column(children: [
            for (var i = 0; i < fees.length; i++) ...[
              if (i > 0) SizedBox(height: 10.h),
              SendReviewKVRow(
                label: fees[i].$1,
                value: fees[i].$2,
                muted: i < fees.length - 1,
              ),
            ],
          ]),
        ),
        const Spacer(),
        Center(
          child: Text(
            context.l10n.sendFundsLeaveYourWalletImmediately,
            style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500),
          ),
        ),
        SizedBox(height: 120.h),
      ],
    ),
  );
}

final _cases = <String, Widget Function(BuildContext context)>{
  'review_lightning': (context) => _review(
        context,
        hero: '1,000 sats',
        fees: const [
          ('Routing fee', '0 sats'),
          ('Estimated time', 'Instant'),
          ('Total', r'1,000 sats · $0.99'),
        ],
        route: SendReviewRoute(
          fromVisual: sendReviewFromMark(kuteDogLightAsset),
          fromTitle: 'Bitcoin',
          fromLine: 'Available · 361,694 sats',
          toVisual: SendRecipientAvatar(
            address: _invoice,
            railMark: Icon(Icons.bolt_rounded,
                color: const Color(0xFFFFB300), size: (40 * 24 / 44).sp),
            recents: const [],
            size: kKuteActionCardVisualSize,
            brantaRail: BrantaRail.lightning,
          ),
          address: _invoice,
          toLine: 'Lightning',
          brantaRail: BrantaRail.lightning,
        ),
      ),
  'review_usdc_polygon': (context) => _review(
        context,
        hero: r'$50.00',
        chip: SendAmountUnitPill(
          code: 'USDC · Polygon',
          icon: usdSendDestinationMark(_usdcPolygon, size: 22),
          onTap: () {},
        ),
        fees: const [('You receive', '≈ 49.95 USDC')],
        route: SendReviewRoute(
          fromVisual: KuteActionCardIcon(kInvestmentsIcon,
              size: SendReviewRoute.visualSize),
          fromTitle: 'Dollars',
          fromLine: r'Available · $100.00',
          toVisual: SendBrantaPayeeVisual(
            address: _evm,
            brantaRail: BrantaRail.usdcPolygon,
            size: kKuteActionCardVisualSize,
            child: usdSendDestinationMark(_usdcPolygon,
                size: kKuteActionCardVisualSize),
          ),
          address: _evm,
          brantaRail: BrantaRail.usdcPolygon,
        ),
      ),
  'card': (context) => Container(
        decoration: AppDecorations.screenGradient(context),
        padding: EdgeInsets.fromLTRB(20.w, 60.h, 20.w, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SendRecipientCard(
              address: _addr,
              railMark: Icon(Icons.currency_bitcoin_rounded,
                  color: const Color(0xFFF7931A), size: 24.sp),
              recents: const [],
              onChange: () {},
              brantaRail: BrantaRail.bitcoinOnchain,
            ),
            SizedBox(height: 24.h),
            SendRecipientCard(
              address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
              railMark: Icon(Icons.currency_bitcoin_rounded,
                  color: const Color(0xFFF7931A), size: 24.sp),
              recents: const [],
              onChange: () {},
              brantaRail: BrantaRail.bitcoinOnchain,
            ),
            SizedBox(height: 24.h),
            SendRecipientCard(
              address: _unverified,
              railMark: Icon(Icons.currency_bitcoin_rounded,
                  color: const Color(0xFFF7931A), size: 24.sp),
              recents: const [],
              onChange: () {},
              brantaRail: BrantaRail.bitcoinOnchain,
            ),
          ],
        ),
      ),
};

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => BrantaPayeeLogo.debugImageProvider = null);

  for (final entry in _cases.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: ${entry.key} $mode', skip: _dir == null,
          (tester) async {
        await _fonts(tester);
        final logo = await _logo(tester);
        BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(logo);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sendContactsGatewayProvider.overrideWithValue(
                FakeSendContactsGateway(
                    permission: SendContactsPermission.granted,
                    contacts: const [])),
            brantaPayeeServiceProvider.overrideWithValue(_branta()),
          ],
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                  body: Builder(builder: (context) => entry.value(context))),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
        // The logo decodes off the frame.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Branta'), findsWidgets);
        await _shoot(tester, 'send_branta_${entry.key}_$mode');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
