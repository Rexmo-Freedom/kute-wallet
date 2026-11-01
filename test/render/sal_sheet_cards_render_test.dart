// A look by eye at the Sal sheet's send cards on a market (light and
// dark), written only when asked: R4_BAR_RENDER=<dir>.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

final _dir = Platform.environment['R4_BAR_RENDER'];

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Advisor extends AdvisorSessionNotifier {
  @override
  AdvisorSessionState build() => const AdvisorSessionState();
  @override
  Future<void> ask(String query,
          {AdvisorContext? context,
          String input = 'typed',
          String? template,
          int? chipIndex,
          String? locale}) async {}
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: Sal sheet send cards, $mode', skip: _dir == null,
        (tester) async {
      await tester.runAsync(() async {
        final inter = FontLoader('Inter')
          ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
          ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
        await inter.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        SalSpriteCache.debugSetManifest(jsonDecode(await rootBundle
            .loadString('$kSalSpriteDir/manifest.json')) as Map<String, dynamic>);
        for (final c in ['share', 'happy', 'search', 'idle']) {
          await SalSpriteCache.clip(c, 3);
        }
      });
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final base = dark ? buildDarkTheme() : buildLightTheme();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          aiEnabledProvider.overrideWith((_) async => false),
          advisorSessionProvider.overrideWith(_Advisor.new),
          sportsLiveProvider.overrideWith(_Sports.new),
          unifiedSearchResultsProvider
              .overrideWith((_) async => UnifiedSearchResults.empty),
          globalMarketResultsProvider
              .overrideWith((_) => const AsyncValue.data([])),
          globalHyperliquidResultsProvider
              .overrideWith((_) => const AsyncValue.data([])),
          hyperliquidAllMarketsProvider.overrideWith((_) => []),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
                textTheme: base.textTheme.apply(fontFamily: 'Inter')),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                RepaintBoundary(key: key, child: child),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showKuteSearch(
                    context,
                    source: 'predictions',
                    barContext: KuteMarketBarContext(
                      label: 'Send to a friend',
                      preview: const KuteBarPreview(
                          title: 'LoL Worlds: Gen.G vs Bilibili Gaming',
                          line: 'Gen.G · 47%'),
                      actions: [
                        KuteMarketBarAction(
                          label: 'Send the market',
                          sublabel: 'A link they can open, with your code',
                          icon: Icons.ios_share_rounded,
                          onTap: (_) {},
                        ),
                        KuteMarketBarAction(
                          label: 'Send this prediction',
                          sublabel: 'They get your pick, ready to place',
                          salClip: 'share',
                          onTap: (_) {},
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open search'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open search'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      Directory(_dir!).createSync(recursive: true);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/sal-sheet-cards-$mode.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
