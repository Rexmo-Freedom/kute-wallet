// A look by eye at the Sal sheet's send cards on a market (light and
// dark, English and German), written only when asked: R4_BAR_RENDER=<dir>.
// The event page (Michigan Senate Election Winner, several outcomes) holds
// the one full-width "Send the market" card; a single Yes/No market keeps
// both cards (founder, 2 November 2026). The bars are built as the market
// page builds them (marketBarContext). One render per run (a second sheet
// in the same process captures blank), so:
//   for v in 'event en light' 'single de dark' ...; do R4_BAR_RENDER=<dir> \
//     flutter test test/render/sal_sheet_cards_render_test.dart \
//     --plain-name "$v"; done

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

/// The page's bar: the event ([single] false) or one Yes/No market.
KuteMarketBarContext _bar(BuildContext context, {required bool single}) =>
    marketBarContext(
      context,
      title: single
          ? 'Will Abdul El-Sayed win the Michigan Senate election?'
          : 'Michigan Senate Election Winner',
      venue: kMarketLinkPredictions,
      slug: 'michigan-senate-election-winner',
      chance: single ? 64 : null,
      outcome: single ? 'Yes' : 'Abdul El-Sayed (D)',
      outcomeIndex: 0,
      outcomeChance: 64,
      side: 'buy',
      position: false,
      category: SearchCategory.predictions,
      searchHint: null,
      source: 'predictions',
      sendPick: single,
    ) as KuteMarketBarContext;

void main() {
  for (final (single, locale, dark) in [
    for (final single in [false, true])
      for (final locale in ['en', 'de'])
        for (final dark in [false, true]) (single, locale, dark),
  ]) {
    final mode = dark ? 'dark' : 'light';
    final page = single ? 'single' : 'event';
    testWidgets('render: Sal sheet send cards, $page $locale $mode',
        skip: _dir == null, (tester) async {
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
            locale: Locale(locale),
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
                    barContext: _bar(context, single: single),
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
        File('$_dir/sal-sheet-cards-$page-$locale-$mode.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
