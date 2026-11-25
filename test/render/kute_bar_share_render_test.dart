// A look by eye at the round share button (kute_bar_trade_row.dart, THE
// SHARE BADGE), written only when asked: FW11_SHARE_RENDER=<dir> flutter
// test test/render/kute_bar_share_render_test.dart. The real Inter face and
// the real Sal sheets, 390 wide at 3x, light and dark: a market's trade row
// (Invest | Short + the round button), a position's Close position with the
// round button at its right, the button at 52, 44 and 36; at rest and on
// Sal's blink (the badge's arrow up). Plus the choices weighed: Sal at 30 /
// 32 / 34 in the circle, and the badge's ring white or the dark surface.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_badge.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

final _dir = Platform.environment['FW11_SHARE_RENDER'];

const _market = KuteBarContext(
  label: 'Send to a friend',
  sublabel: 'Send the market',
  clip: 'share',
);

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final manifest =
        jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>;
    SalSpriteCache.debugSetManifest(manifest);
    for (final clip in ['idle', 'curious', 'think', 'search', 'happy']) {
      await SalSpriteCache.clip(clip, 3);
    }
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Widget _shareButton() => KuteBarShareButton(
      share: const KuteBarShare(barContext: _market),
      onTap: (_) {},
    );

/// [child] (a 52 button) drawn at [side].
Widget _scaled(double side, Widget child) =>
    SizedBox(width: side, height: side, child: FittedBox(child: child));

/// The round button as the share button builds it, with Sal at [sal] and
/// the badge's ring in [ring].
Widget _variant(double sal, Color ring) => KuteSalPill(
      label: 'Send to a friend',
      clip: kSalShareButtonClip,
      collapsed: true,
      salSize: sal,
      badge: KuteShareBadge(ringColor: ring),
      onTap: () {},
    );

Widget _sizes(Widget Function() button) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _scaled(52, button()),
        const SizedBox(width: 28),
        _scaled(44, button()),
        const SizedBox(width: 28),
        _scaled(36, button()),
      ],
    );

Future<void> _shot(WidgetTester tester, String name, bool dark,
    List<Widget> Function(BuildContext) rows,
    {double height = 300, Duration at = const Duration(seconds: 2)}) async {
  tester.view.physicalSize = Size(390 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: key,
        child: Builder(
          builder: (context) => ColoredBox(
            color: context.colors.background,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: rows(context),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(at);
  Directory(_dir!).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
}

List<Widget> _bar(BuildContext context) => [
      KuteBarTradeRow(
        barContext: KuteBarContext.trade(
          trades: [
            KuteBarTrade(
                id: 'invest',
                label: 'Invest',
                fill: AppColors.marketUp,
                flex: 2,
                onTap: () {}),
            KuteBarTrade(
                id: 'short',
                label: 'Short',
                fill: AppColors.marketDown,
                onTap: () {}),
          ],
          share: const KuteBarShare(barContext: _market),
        ),
        onShare: (_) {},
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: KuteBarPrimaryButton(
              barContext: KuteBarContext.primary(
                label: 'Close position',
                onPrimary: () {},
                disabledLabel: 'Position closed',
                style: KuteBarPrimaryStyle.destructive,
              ),
              onAsk: () {},
            ),
          ),
          KuteBarShareSlot(
            share: KuteBarShare(barContext: _market, brag: () {}),
            onTap: (_) {},
          ),
        ],
      ),
      _sizes(_shareButton),
    ];

void main() {
  tearDown(() => SalSpriteCache.debugSetManifest(null));
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: the round share button, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      // Frame 0: Sal's level stare, the arrow at rest.
      await _shot(tester, 'share-badge-$mode', dark, _bar);
      // Frame 38: his lids shut on the blink, the arrow up.
      await _shot(tester, 'share-badge-$mode-blink', dark, _bar,
          at: const Duration(milliseconds: 3600));
    });

    testWidgets('render: the choices weighed, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(
          tester,
          'share-badge-variants-$mode',
          dark,
          (context) => [
                for (final sal in [30.0, 32.0, 34.0])
                  _sizes(() => _variant(sal, Colors.white)),
                if (dark) _sizes(() => _variant(32, context.colors.surface)),
              ],
          height: dark ? 400 : 300);
    });
  }
}
