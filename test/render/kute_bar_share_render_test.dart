// A look by eye at the round share button's Sal (`face_share`,
// kute_bar_trade_row.dart, THE SHARE CLIP), written only when asked:
// FW11_SHARE_RENDER=<dir> flutter test
// test/render/kute_bar_share_render_test.dart. The real Inter face and the
// real Sal sheets, 390 wide at 3x, light and dark: a market's trade row
// (Invest | Short + the round button), a position's Close position with
// the round button at its right, and the button scaled to 44 and 36.

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
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
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
    await SalSpriteCache.clip(kSalShareButtonClip, 3);
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Widget _shareButton({bool brag = false}) => KuteBarShareButton(
      share: KuteBarShare(barContext: _market, brag: brag ? () {} : null),
      onTap: (_) {},
    );

/// The button drawn at [side] (52 is its own size).
Widget _scaled(double side) => SizedBox(
      width: side,
      height: side,
      child: FittedBox(child: _shareButton()),
    );

/// [at] into the 2 s loop: 2 s is frame 0 again (the rest pose).
Future<void> _shot(WidgetTester tester, String name, bool dark,
    {Duration at = const Duration(seconds: 2)}) async {
  tester.view.physicalSize = const Size(390 * 3, 300 * 3);
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
                children: [
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _scaled(52),
                      const SizedBox(width: 24),
                      _scaled(44),
                      const SizedBox(width: 24),
                      _scaled(36),
                    ],
                  ),
                ],
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

void main() {
  tearDown(() => SalSpriteCache.debugSetManifest(null));
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: the round share button, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'share-button-$mode', dark);
      // Mid-loop (frame 14): the arrow up out of the tray, the side-eye
      // down at it.
      await _shot(tester, 'share-button-$mode-mid', dark,
          at: const Duration(milliseconds: 2600));
    });
  }
}
