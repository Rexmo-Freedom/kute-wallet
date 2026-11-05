// A look by eye at Send this prediction's last step (founder, 5 November
// 2026: "more clear we are sending the prediction"), opened as the slip's
// round Sal button opens it: the card as the hero, what the friend gets,
// the name, Challenge them, the bar "Send prediction"; light and dark, on
// a small and a large phone, with and without the keyboard. Every frame
// lays out without an overflow; the PNGs are written only when asked:
//
//   SEND_PREDICTION_RENDER=<dir> flutter test \
//     test/render/send_prediction_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/services/api/share_links_api.dart'
    show shareLinksApiProvider;
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../screens/share/cards/share_card_test_fonts.dart';
import '../screens/share/share_test_harness.dart';

final _dir = Platform.environment['SEND_PREDICTION_RENDER'];

final _apple = PolymarketEvent(
  id: 'apple',
  slug: 'apple-largest-company-2026',
  title: 'Will Apple be the largest company in the world by end of 2026?',
  volume: 1000,
  liquidity: 1000,
  category: 'tech',
  tags: const [],
  endDate: DateTime(2026, 12, 31),
  conditionId: 'c-a',
  outcomes: const [
    PolymarketOutcome(
        name: 'Yes', price: 0.616, tokenId: 'a-y', conditionId: 'c-a'),
    PolymarketOutcome(
        name: 'No', price: 0.384, tokenId: 'a-n', conditionId: 'c-a'),
  ],
);

void main() {
  late ShareTestEnv env;
  setUp(() {
    env = setUpShareTest();
    WidgetsApp.debugAllowBannerOverride = false;
  });
  tearDown(() {
    tearDownShareTest();
    WidgetsApp.debugAllowBannerOverride = true;
  });

  for (final (size, keyboard) in const [
    (Size(375, 667), 0.0),
    (Size(375, 667), 260.0),
    (Size(402, 874), 0.0),
    (Size(402, 874), 336.0),
  ]) {
    for (final dark in [false, true]) {
      final name = 'send-prediction-${size.width.round()}x'
          '${size.height.round()}-${keyboard > 0 ? 'keyboard' : 'open'}-'
          '${dark ? 'dark' : 'light'}';
      testWidgets('render: $name', (tester) async {
        await tester.runAsync(loadShareCardFonts);
        await tester.runAsync(loadShareCardSal);
        // Logical pixels, captured at 3x below.
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final base = dark ? buildDarkTheme() : buildLightTheme();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            shareLinksApiProvider.overrideWithValue(env.fake),
            polymarketEventDetailsProvider
                .overrideWith((ref, slug) async => _apple),
          ],
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              theme: base.copyWith(
                  textTheme: base.textTheme.apply(fontFamily: 'Inter')),
              builder: withKuteShellBar,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showSendToAnyoneSheet(
                        context,
                        kind: ShareLinkKind.dollars,
                        marketSlug: _apple.slug,
                        marketTitle: _apple.title,
                        venue: 'polymarket',
                        outcome: 'Yes',
                        outcomeIndex: 0,
                        side: 'buy',
                        amountMinor: 500,
                        entrySource: 'render',
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await settle(tester);
        await tester.tap(find.text('open'));
        await settle(tester);
        if (keyboard > 0) {
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(tester.view.resetViewInsets);
          await tester.tap(find.byKey(const ValueKey('share-name-field')));
          await settle(tester);
          await tester.enterText(
              find.byKey(const ValueKey('share-name-field')), 'Ana');
          await settle(tester);
        }
        final error = tester.takeException();
        expect(error, isNull, reason: '$name overflowed: $error');
        expect(kuteBarPrimaryWithText('Send prediction'), findsOneWidget);
        final dir = _dir;
        if (dir == null) return;
        final view = tester.binding.renderViews.first;
        final layer = view.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final image = await layer.toImage(Offset.zero & view.size,
              pixelRatio: 3);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(dir).createSync(recursive: true);
          File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      });
    }
  }
}
