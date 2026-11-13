// A look by eye at the search sheet in send mode (founder, 8 November
// 2026, on the small "For Anna" chip it wore: "i still think for anna
// should be more clear and better"): the first steps' own heading, "Pick a
// gift for Anna", "Pick a gift" with no contact, the search line reading
// "Search predictions and investments", then Moving now and Trending
// predictions. Light and dark, with a name, without one, with a long name,
// in English and in two long languages (German, Polish, whose title names
// the recipient after a colon), on a small and a large phone, once with the
// keyboard up; and the plain search sheet beside them, which keeps its
// drag-handle row. Every frame
// lays out without an overflow; the PNGs are written only when asked:
//
//   SEND_PICK_SHEET_RENDER=<dir> flutter test \
//     test/render/send_pick_sheet_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show SheetTitleHeader;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/search_recent_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../screens/share/cards/share_card_test_fonts.dart';
import '../screens/share/share_test_harness.dart';

final _dir = Platform.environment['SEND_PICK_SHEET_RENDER'];

PolymarketEvent _event(String id, String title, double yes) => PolymarketEvent(
      id: id,
      slug: id,
      title: title,
      volume: 1000000,
      liquidity: 500000,
      category: 'politics',
      conditionId: 'c-$id',
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: yes),
        PolymarketOutcome(name: 'No', price: 1 - yes),
      ],
    );

final _events = [
  _event('fed', 'Will the Fed cut rates in December?', 0.62),
  _event('largest', 'Will Apple be the largest company in 2026?', 0.38),
  _event('btc', 'Will Bitcoin reach \$150k this year?', 0.21),
];

HlMarket _market(String coin, double change) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: coin.hashCode & 0xff,
      kind: HlMarketKind.perp,
      szDecimals: 4,
      maxLeverage: 25,
      onlyIsolated: false,
      markPx: 100 * (1 + change),
      midPx: 100 * (1 + change),
      prevDayPx: 100,
      dayNtlVlm: 1e9,
    );

final _markets = [
  _market('ETH', 0.042),
  _market('SOL', -0.067),
  _market('HYPE', 0.081),
  _market('XRP', -0.029),
  _market('DOGE', 0.055),
  _market('AVAX', -0.038),
];

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(events: _events, done: true);
}

final _overrides = <Override>[
  aiEnabledProvider.overrideWith((_) async => true),
  sportsLiveProvider.overrideWith(_Sports.new),
  unifiedSearchResultsProvider
      .overrideWith((_) async => UnifiedSearchResults.empty),
  globalMarketResultsProvider.overrideWith(
      (ref) => const AsyncValue.data(<GlobalMarketSearchResult>[])),
  globalHyperliquidResultsProvider
      .overrideWith((ref) => const AsyncValue.data(<HlMarketSearchResult>[])),
  hyperliquidAllMarketsProvider.overrideWith((_) => []),
  hyperliquidBrowseUniverseProvider
      .overrideWith((_) => AsyncValue.data(_markets)),
  hyperliquidSparklineStoreProvider.overrideWith(
      (_) => HlSparklineStore(fetch: (_) async => const [1.0, 2.0, 3.0])),
  polyBrowseFeedProvider.overrideWith(_Feed.new),
];

/// One frame: the sheet for [recipient] (send mode), or the plain search
/// sheet with [send] false.
class _Frame {
  const _Frame(this.tag,
      {this.recipient,
      this.locale = 'en',
      this.dark = false,
      this.send = true,
      this.keyboard = 0,
      this.size = const Size(402, 874)});
  final String tag;
  final String? recipient;
  final String locale;
  final bool dark;
  final bool send;
  final double keyboard;
  final Size size;
}

const _small = Size(375, 667);
const _long = 'Maria-Fernanda Alexandrina';

const _frames = [
  _Frame('named-light', recipient: 'Anna'),
  _Frame('named-dark', recipient: 'Anna', dark: true),
  _Frame('noname-light'),
  _Frame('noname-dark', dark: true),
  _Frame('longname-light', recipient: _long),
  _Frame('longname-dark', recipient: _long, dark: true),
  _Frame('named-small-light', recipient: 'Anna', size: _small),
  _Frame('longname-small-dark', recipient: _long, dark: true, size: _small),
  _Frame('de-named-light', recipient: 'Anna', locale: 'de'),
  _Frame('de-noname-dark', locale: 'de', dark: true),
  _Frame('de-longname-small-light',
      recipient: _long, locale: 'de', size: _small),
  _Frame('pl-named-small-light', recipient: 'Anna', locale: 'pl', size: _small),
  _Frame('de-longname-small-keyboard-dark',
      recipient: _long, locale: 'de', dark: true, keyboard: 260, size: _small),
  _Frame('plain-search-light', send: false),
  _Frame('plain-search-dark', send: false, dark: true),
];

void main() {
  // Moving now lists only markets with a logo of their own: the movers'
  // logos are known.
  setUp(() {
    for (final m in _markets) {
      HlIconAvailability.debugSeed(m);
    }
  });
  tearDown(HlIconPrefetch.debugReset);
  setUp(() async {
    setUpShareTest();
    WidgetsApp.debugAllowBannerOverride = false;
    final service = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = service;
    expect(await service.refresh(), isTrue);
    SearchRecentStore.entries.value = const [];
    OpenOnce.reset();
  });
  tearDown(() {
    tearDownShareTest();
    WidgetsApp.debugAllowBannerOverride = true;
    RuntimeCapabilitiesService.debugInstance = null;
    SearchRecentStore.entries.value = const [];
  });

  for (final frame in _frames) {
    final name = 'send-pick-sheet-${frame.tag}';
    testWidgets('render: $name', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      await tester.runAsync(loadShareCardSal);
      // The composer's Sal, decoded before the sheet draws it.
      await tester.runAsync(() async {
        for (final density in [1, 2, 3]) {
          await SalSpriteCache.clip('search', density);
        }
      });
      // Logical pixels, captured at 3x below.
      tester.view.physicalSize = frame.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final base = frame.dark ? buildDarkTheme() : buildLightTheme();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            locale: Locale(frame.locale),
            theme: base.copyWith(
                textTheme: base.textTheme.apply(fontFamily: 'Inter')),
            builder: withKuteShellBar,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => frame.send
                        ? showSendPickMarketSheet(context,
                            entrySource: 'render',
                            senderLabel: frame.recipient)
                        : showKuteSearch(context, source: 'render'),
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
      await settle(tester);
      if (frame.keyboard > 0) {
        tester.view.viewInsets = FakeViewPadding(bottom: frame.keyboard);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(find.byType(TextField));
        await settle(tester);
      }
      final error = tester.takeException();
      expect(error, isNull, reason: '$name overflowed: $error');
      expect(find.byType(SheetTitleHeader),
          frame.send ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
      final dir = _dir;
      if (dir == null) return;
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final image =
            await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(dir).createSync(recursive: true);
        File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
