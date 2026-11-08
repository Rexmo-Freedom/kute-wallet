// A look by eye at the Sends' Review (founder, 7 November 2026, the
// Bitcoin Send's Review: "make this more with the square cards we have
// now"): From and To as two squares (SendReviewRoute,
// send_contacts_list.dart) over the fee card on the same soft card, light
// and dark, written only when asked: SEND_REVIEW_RENDER=<dir>.
//
//   * "lightning": to a Lightning address, "Lightning" under it;
//   * "onchain": to a bitcoin address, no line (the default network), the
//     To square tapped: the whole address with its Copy under the pair;
//   * "crosschain": to a 0x address, "USDC on Base" under it;
//   * "dollars": the Dollars Send, the coin chip under the hero, no line;
//   * "at kute", "at long", "at contact" (founder, 7 November 2026: "try
//     not to trim when its a @ address, or just have the name before the
//     @"): a Kute address (jay2290@paykute.com), a long domain
//     (pipinho@walletofsatoshi.com) and a saved contact's Kute address
//     (Joana Kute), each at 320, 375 and 430 pt, at 1x and 1.3x text.
//
// The page is laid out as the Review step lays it out (the stepper's 20
// gutter, the hero, the squares, the fee card, the footnote); shadows are
// drawn as on a phone. One render per run is safest:
//   for v in lightning onchain crosschain dollars; do for m in light dark; \
//     do SEND_REVIEW_RENDER=<dir> flutter test \
//     test/render/send_review_render_test.dart --plain-name "$v $m"; done; done

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kInvestmentsIcon;
import 'package:kute/screens/shared/asset_network_picker.dart'
    show ChainAvatarIcon;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/usd/usd_send_screen.dart'
    show usdSendDestinationMark;
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart'
    show UsdSendDestination;
import 'package:kute/theme/app_theme.dart';

import '../mocks/fake_send_contacts_gateway.dart';

/// The saved contact the "at contact" review pays.
const _joana = SendContact(
    id: 'k1',
    displayName: 'Joana Kute',
    firstName: 'Joana',
    phone: '+351 914 444 444',
    lightningAddress: 'joana@paykute.com');

final _dir = Platform.environment['SEND_REVIEW_RENDER'];

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

const _usdcBase = UsdSendDestination(
  assetCode: 'USDC',
  displayName: 'USD Coin',
  displaySymbol: 'USDC',
  chain: 'base',
  chainDisplayName: 'Base',
  decimals: 6,
);

/// One Review: [hero] (and [chip] under it), the squares, the fee rows.
class _Review extends StatefulWidget {
  const _Review({
    required this.hero,
    required this.route,
    required this.fees,
    this.chip,
  });

  final String hero;
  final Widget? chip;
  final SendReviewRoute Function(bool expanded, VoidCallback toggle) route;
  final List<(String, String)> fees;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
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
              child: Text(widget.hero,
                  style: sendHeroAmountStyle(c.textPrimary)),
            ),
          ),
          if (widget.chip != null) ...[
            SizedBox(height: 4.h),
            Center(child: widget.chip),
          ],
          SizedBox(height: 20.h),
          widget.route(
              expanded, () => setState(() => expanded = !expanded)),
          SizedBox(height: 14.h),
          SendReviewCard(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Column(children: [
              for (var i = 0; i < widget.fees.length; i++) ...[
                if (i == widget.fees.length - 1 && i > 0) ...[
                  SizedBox(height: 12.h),
                  Divider(height: 1, color: c.borderSubtle),
                  SizedBox(height: 12.h),
                ] else if (i > 0)
                  SizedBox(height: 10.h),
                SendReviewKVRow(
                  label: widget.fees[i].$1,
                  value: widget.fees[i].$2,
                  muted: i < widget.fees.length - 1,
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: 120.h),
        ],
      ),
    );
  }
}

Widget _app(bool dark, Widget review) => ProviderScope(
      overrides: [
        sendContactsGatewayProvider.overrideWithValue(FakeSendContactsGateway(
            permission: SendContactsPermission.granted, contacts: [_joana])),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: review),
        ),
      ),
    );

Widget _sal(bool dark) => SvgPicture.asset(
    dark ? 'lib/assets/kute_dog_dark.svg' : 'lib/assets/kute_dog.svg',
    width: SendReviewRoute.visualSize,
    height: SendReviewRoute.visualSize);

/// The Bitcoin Send's rail mark in a 40 avatar, as confirm_send.dart
/// draws it.
Widget _glyph(IconData icon, Color color) =>
    Icon(icon, color: color, size: (40 * 24 / 44).sp);

/// A Lightning address's Review, as the Bitcoin Send draws it.
Widget _atReview(bool dark, String address) => _Review(
      hero: '5 sats',
      fees: const [
        ('Routing fee', '0 sats'),
        ('Estimated time', 'Instant'),
        ('Total', r'5 sats · $0.00'),
      ],
      route: (expanded, toggle) => SendReviewRoute(
        fromVisual: _sal(dark),
        fromTitle: 'Bitcoin',
        fromLine: 'Available · 361,694 sats',
        toVisual: SendRecipientAvatar(
          address: address,
          railMark:
              _glyph(Icons.alternate_email_rounded, const Color(0xFFB388FF)),
          recents: const [],
          size: kKuteActionCardVisualSize,
        ),
        address: address,
        toLine: 'Lightning',
        expanded: expanded,
        onToggle: toggle,
      ),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final atCases = <String, String>{
    'kute': 'jay2290@paykute.com',
    'long': 'pipinho@walletofsatoshi.com',
    'contact': 'joana@paykute.com',
  };
  for (final MapEntry(key: name, value: address) in atCases.entries) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3]) {
        for (final dark in [false, true]) {
          final mode = dark ? 'dark' : 'light';
          final tag = '${width.round()}_${scale == 1.0 ? 'x1' : 'x13'}_$mode';
          testWidgets('render: at $name $tag', skip: _dir == null,
              (tester) async {
            await _fonts(tester);
            tester.view.physicalSize = Size(width, width == 430 ? 932 : 760);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);
            await tester.pumpWidget(_app(dark, _atReview(dark, address)));
            final container = ProviderScope.containerOf(
                tester.element(find.byType(SendReviewRoute)));
            await container.read(sendContactsProvider.notifier).refresh();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byKey(const ValueKey('send-review-route')),
                findsOneWidget);
            await _shoot(tester, 'send_review_at_${name}_$tag');
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  final cases = <String, Widget Function(bool dark)>{
    'lightning': (dark) => _Review(
          hero: '5 sats',
          fees: const [
            ('Routing fee', '0 sats'),
            ('Estimated time', 'Instant'),
            ('Total', r'5 sats · $0.00'),
          ],
          route: (expanded, toggle) => SendReviewRoute(
            fromVisual: _sal(dark),
            fromTitle: 'Bitcoin',
            fromLine: 'Available · 361,694 sats',
            toVisual: SendRecipientAvatar(
              address: 'pipinho@walletofsatoshi.com',
              railMark: _glyph(
                  Icons.alternate_email_rounded, const Color(0xFFB388FF)),
              recents: const [],
              size: kKuteActionCardVisualSize,
            ),
            address: 'pipinho@walletofsatoshi.com',
            toLine: 'Lightning',
            expanded: expanded,
            onToggle: toggle,
          ),
        ),
    'onchain': (dark) => _Review(
          hero: '25,000 sats',
          fees: const [
            ('Network fee', '312 sats'),
            ('Estimated time', '~30 min'),
            ('Total', r'25,312 sats · $25.21'),
          ],
          route: (expanded, toggle) => SendReviewRoute(
            fromVisual: _sal(dark),
            fromTitle: 'Bitcoin',
            fromLine: 'Available · 361,694 sats',
            toVisual: SendRecipientAvatar(
              address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
              railMark: _glyph(
                  Icons.currency_bitcoin_rounded, const Color(0xFFF7931A)),
              recents: const [],
              size: kKuteActionCardVisualSize,
            ),
            address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
            expanded: expanded,
            onToggle: toggle,
          ),
        ),
    'crosschain': (dark) => _Review(
          hero: '20,000 sats',
          fees: const [
            ('You receive', '≈ 19.71 USDC'),
            ('Estimated time', '~2 min'),
            ('Total', r'20,000 sats · $19.92'),
          ],
          route: (expanded, toggle) => SendReviewRoute(
            fromVisual: _sal(dark),
            fromTitle: 'Bitcoin',
            fromLine: 'Available · 361,694 sats',
            toVisual: SendRecipientAvatar(
              address: '0x742d35cc6634c0532925a3b844bc454e4438f44e',
              railMark: ChainAvatarIcon(
                  chainId: 'USDC', label: 'USDC', size: 40 * 28 / 44),
              recents: const [],
              size: kKuteActionCardVisualSize,
            ),
            address: '0x742d35cc6634c0532925a3b844bc454e4438f44e',
            toLine: 'USDC on Base',
            expanded: expanded,
            onToggle: toggle,
          ),
        ),
    'dollars': (dark) => _Review(
          hero: r'$100.00',
          chip: SendAmountUnitPill(
            code: 'USDC · Base',
            icon: usdSendDestinationMark(_usdcBase, size: 22),
            onTap: () {},
          ),
          fees: const [
            ('You receive', '≈ 99.90 USDC'),
          ],
          route: (expanded, toggle) => SendReviewRoute(
            fromVisual: KuteActionCardIcon(kInvestmentsIcon,
                size: SendReviewRoute.visualSize),
            fromTitle: 'Dollars',
            fromLine: r'Available · $100.00',
            toVisual: usdSendDestinationMark(_usdcBase,
                size: kKuteActionCardVisualSize),
            address: '0x742d35cc6634c0532925a3b844bc454e4438f44e',
            expanded: expanded,
            onToggle: toggle,
          ),
        ),
  };

  for (final entry in cases.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: ${entry.key} $mode', skip: _dir == null,
          (tester) async {
        await _fonts(tester);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(dark, entry.value(dark)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('send-review-route')), findsOneWidget);
        if (entry.key == 'onchain') {
          await tester.tap(find.byKey(const ValueKey('send-review-to')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const ValueKey('send-review-full-address')),
              findsOneWidget);
        }
        await _shoot(tester, 'send_review_${entry.key}_$mode');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
