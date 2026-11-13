// THE INVESTING WATCHLIST (founder, 13 November 2026: "on Investing, when
// we click on the filters we should have 'create a watchlist'. The
// watchlist, after it is created, should be the one it always opens with.
// Only on Investing. Watchlist creation should be a bottom modal sheet.
// Also we should show [it] with the design of the 4 main squares after it
// is created").
//
//   * the filter sheet's "Create a watchlist" card opens the watchlist
//     sheet; ticks and Done make the watchlist and close both sheets on it;
//   * the card then reads Watchlist with its count and an Edit;
//   * Investing opens on the Watchlist on every way in, and after a
//     restart; emptied, it opens on Trending and the card reads "Create a
//     watchlist" again;
//   * the Watchlist view: its first four markets as the Moving now
//     squares (two for two or three), the rest as rows, an Edit row;
//   * a market page's star is the same list;
//   * Predictions is unchanged;
//   * nothing cut at 320 pt and 1.5× text, light and dark.
//
// Renders, light and dark, when asked:
//   WATCHLIST_RENDER_OUT=<dir> flutter test \
//     test/screens/usd/investing_watchlist_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconAvailability;
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart';
import 'package:kute/screens/hyperliquid/components/hl_watchlist_sheet.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'investments_harness.dart';

final _out = Platform.environment['WATCHLIST_RENDER_OUT'] ?? '';

final AppLocalizations _l10n = l10nForLanguage('en');

HlMarket _market(String coin,
        {String category = 'crypto',
        String dex = '',
        double vlm = 1e6,
        double px = 100,
        double prev = 98}) =>
    HlMarket(
      coin: coin,
      wireCoin: dex.isEmpty ? coin : '$dex:$coin',
      assetId: coin.hashCode & 0xffff,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: category,
      dex: dex,
      isHip3: dex.isNotEmpty,
    );

final _universe = [
  _market('BTC', vlm: 9e9, px: 97250, prev: 95100),
  _market('ETH', vlm: 4e9, px: 3412.5, prev: 3480),
  _market('SOL', vlm: 2e9, px: 182.4, prev: 176.2),
  _market('XRP', vlm: 1e9, px: 2.41, prev: 2.39),
  _market('DOGE', vlm: 5e8, px: 0.3812, prev: 0.3601),
  _market('NEAR', vlm: 3e8, px: 5.62, prev: 5.81),
  _market('LINK', vlm: 2e8, px: 23.18, prev: 22.6),
  _market('AVAX', vlm: 1e8, px: 38.9, prev: 40.2),
  _market('TSLA', category: 'stocks', dex: 'xyz', vlm: 7e8, px: 412.3),
  _market('GOLD', category: 'commodities', dex: 'xyz', vlm: 6e8, px: 2650),
];

HlMarket _m(String coin) => _universe.firstWhere((m) => m.coin == coin);

/// The stars, in memory across a "restart" (a new ProviderScope), as the
/// box keeps them on a phone.
class _MemoryStars extends HlWatchlistNotifier {
  static List<String> stored = const [];

  @override
  List<String> build() => stored;

  @override
  bool toggle(HlMarket m) {
    final key = hlWatchlistKey(m);
    final added = !state.contains(key);
    state = added
        ? [key, ...state]
        : [
            for (final s in state)
              if (s != key) s
          ];
    stored = state;
    return added;
  }

  @override
  void replaceAll(List<String> keys) {
    state = [...keys];
    stored = state;
  }
}

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void unwatchAll() {}
}

List<Override> get _overrides => [
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(_universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
    ];

const Widget _page = Scaffold(body: UsdAccountScreen());

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _pumpPage(WidgetTester tester,
    {Size size = const Size(390, 844),
    bool dark = false,
    double textScale = 1,
    Widget child = _page}) async {
  await pumpInvestments(tester,
      browseInvesting: true,
      size: size,
      dark: dark,
      textScale: textScale,
      hlStars: _MemoryStars.new,
      overrides: _overrides,
      child: child);
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

/// The picked pill's words ("Investing · Filter").
Finder _pillWords(String text) => find.descendant(
    of: find.byType(KutePillTabs).first, matching: find.text(text));

Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));
Finder _row(String coin) => find.byKey(ValueKey('hl-watchlist-row-perp-$coin'));

Future<void> _enterInvesting(WidgetTester tester) async {
  await tapAndPump(tester, investmentsPill(_l10n.trading));
  await _frames(tester);
}

Future<void> _openFilter(WidgetTester tester) async {
  await tapAndPump(tester, investmentsPill(_l10n.trading));
  await _frames(tester);
}

Future<void> _tick(WidgetTester tester, String coin) async {
  await tester.ensureVisible(_row(coin));
  await tester.pump();
  await tester.tap(_row(coin));
  await tester.pump();
}

bool _ticked(WidgetTester tester, String coin) => find
    .descendant(
        of: _row(coin), matching: find.byIcon(Icons.check_circle_rounded))
    .evaluate()
    .isNotEmpty;

Future<void> _done(WidgetTester tester) async {
  kuteBarPrimaryContext(tester).onPrimary!();
  await _frames(tester, 12);
}

/// The coins of the Watchlist's squares, in order.
List<String> _squares(WidgetTester tester) => [
      for (final c in tester.widgetList<HlMovingNowCard>(find.descendant(
          of: find.byKey(const ValueKey('hl-watchlist-squares')),
          matching: find.byType(HlMovingNowCard))))
        c.market.coin,
    ];

/// The coins of the browser's rows, in order.
List<String> _rows(WidgetTester tester) => [
      for (final c in tester.widgetList<HlMarketCard>(find.descendant(
          of: find.byType(HyperliquidScreen),
          matching: find.byType(HlMarketCard, skipOffstage: false))))
        c.market.coin,
    ];

/// Text painted under [root] that is cut: past its lines or clipped.
List<String> _cut(WidgetTester tester, Finder root) {
  final out = <String>[];
  for (final e in find
      .descendant(of: root, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty) continue;
    if (p.didExceedMaxLines) {
      out.add('"$text" exceeds its ${p.maxLines} line(s)');
      continue;
    }
    if ((p.maxLines == 1 || !p.softWrap) &&
        p.getMaxIntrinsicWidth(double.infinity) > p.size.width + 0.5) {
      out.add('"$text" clipped');
    }
  }
  return out;
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_out.isEmpty) return;
  await _frames(tester, 4);
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    // The glyphs (the "+", the checks): the SDK's Material icon font.
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  setUp(() {
    _MemoryStars.stored = const [];
    HlIconAvailability.debugEveryLogoKnown = true;
  });
  tearDown(() => HlIconAvailability.debugEveryLogoKnown = false);

  testWidgets(
      'create from the filter sheet: Investing opens on the Watchlist, its '
      'first four as squares and the rest as rows, on every way in and '
      'after a restart', (tester) async {
    final events = recordEvents();
    final container = await _pumpPage(tester);
    await _enterInvesting(tester);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.trending);
    expect(_pillWords('${_l10n.trading} · ${_l10n.categoryFilterPrompt}'),
        findsOneWidget);

    // The filter sheet: "Create a watchlist" with its "+", no Watchlist.
    await _openFilter(tester);
    expect(_tile('watchlist-create'), findsOneWidget);
    expect(_tile('watchlist'), findsNothing);
    expect(
        find.descendant(
            of: _tile('watchlist-create'),
            matching: find.text(_l10n.hlWatchlistCreate)),
        findsOneWidget);
    expect(
        find.descendant(
            of: _tile('watchlist-create'),
            matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget);

    // The watchlist sheet, a bottom sheet over the filter sheet.
    await tester.tap(_tile('watchlist-create'));
    await _frames(tester);
    expect(find.byType(HlWatchlistSheet), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hl-watchlist-sheet-header')),
            matching: find.text(_l10n.hlWatchlistCreate)),
        findsOneWidget);
    expect(find.text(_l10n.hlWatchlistCreateHint), findsOneWidget);
    expect(kuteBarPrimaryContext(tester).label, _l10n.done);
    expect(_ticked(tester, 'BTC'), isFalse);

    for (final coin in ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE']) {
      await _tick(tester, coin);
      expect(_ticked(tester, coin), isTrue);
    }
    // A search: LINK alone answers "link"; ticked from there.
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('hl-watchlist-search')),
            matching: find.byType(TextField)),
        'link');
    await tester.pump();
    expect(_row('LINK'), findsOneWidget);
    expect(_row('BTC'), findsNothing);
    await _tick(tester, 'LINK');
    // Nothing is written before Done.
    expect(container.read(hlWatchlistProvider), isEmpty);

    await _done(tester);
    expect(find.byType(HlWatchlistSheet), findsNothing);
    expect(_tile('watchlist-create'), findsNothing, reason: 'both sheets shut');
    expect(container.read(hlWatchlistProvider), [
      'perp:LINK',
      'perp:DOGE',
      'perp:XRP',
      'perp:SOL',
      'perp:ETH',
      'perp:BTC',
    ]);
    expect(
        container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.watchlist);
    expect(
        _pillWords(
            '${_l10n.trading} · ${HlBrowseTab.watchlist.localizedLabel(_l10n)}'),
        findsOneWidget);
    expect(_squares(tester), ['LINK', 'DOGE', 'XRP', 'SOL']);
    expect(_rows(tester), ['ETH', 'BTC']);
    expect(find.byKey(const ValueKey('hl-watchlist-edit')), findsOneWidget);

    // The events: exact counts, the public symbol, never an id.
    final opened = events.where((e) => e.$1 == 'watchlist_sheet_opened');
    expect(opened.single.$2, {
      'venue': 'hyperliquid',
      'mode': 'create',
      'source': 'category_sheet',
      'list_size': 0,
    });
    final toggled = events.where((e) => e.$1 == 'watchlist_toggled').toList();
    expect(toggled.map((e) => e.$2!['coin']),
        ['LINK', 'DOGE', 'XRP', 'SOL', 'ETH', 'BTC']);
    for (final e in toggled) {
      expect(e.$2, containsPair('venue', 'hyperliquid'));
      expect(e.$2, containsPair('action', 'added'));
      expect(e.$2, containsPair('source', 'watchlist_sheet'));
      expect(e.$2, containsPair('list_size', 6));
      expect(e.$2, containsPair('kind', 'perp'));
    }
    expect(events.where((e) => e.$1 == 'watchlist_saved').single.$2, {
      'venue': 'hyperliquid',
      'mode': 'create',
      'source': 'category_sheet',
      'added': 6,
      'removed': 0,
      'list_size': 6,
    });
    expect(events.where((e) => e.$1 == 'hl_category_pill_tapped').single.$2,
        {'section': 'watchlist'});

    // The filter card now: the Watchlist, its count, an Edit.
    await _openFilter(tester);
    expect(_tile('watchlist-create'), findsNothing);
    expect(_tile('watchlist'), findsOneWidget);
    expect(
        find.descendant(
            of: _tile('watchlist'),
            matching: find.textContaining(_l10n.categoryStatMarkets(6))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('category-tile-watchlist-edit')),
        findsOneWidget);
    // Another pick; leaving and coming back opens on the Watchlist again.
    await tester.tap(_tile(HlBrowseTab.perps.key));
    await _frames(tester);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.perps);
    await tapAndPump(tester, investmentsPill(_l10n.overview));
    await _enterInvesting(tester);
    expect(
        container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.watchlist);
    await unmountInvestments(tester);

    // A restart: a new app, the stars kept; Investing opens on them.
    final again = await _pumpPage(tester);
    expect(again.read(hlBrowseSelectionProvider).tab, HlBrowseTab.watchlist);
    await _enterInvesting(tester);
    expect(_squares(tester), ['LINK', 'DOGE', 'XRP', 'SOL']);
    expect(_rows(tester), ['ETH', 'BTC']);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Watchlist view: two squares for three (no lone half square), '
      'Edit opens the same sheet; emptied, Investing opens on Trending and '
      'the card reads "Create a watchlist" again', (tester) async {
    _MemoryStars.stored = ['perp:SOL', 'perp:ETH', 'perp:BTC'];
    final events = recordEvents();
    final container = await _pumpPage(tester);
    await _enterInvesting(tester);
    expect(_squares(tester), ['SOL', 'ETH']);
    expect(_rows(tester), ['BTC']);

    await tester.ensureVisible(find.byKey(const ValueKey('hl-watchlist-edit')));
    await tester.tap(find.byKey(const ValueKey('hl-watchlist-edit')));
    await _frames(tester);
    expect(find.byType(HlWatchlistSheet), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hl-watchlist-sheet-header')),
            matching: find.text(_l10n.polyPillWatchlist)),
        findsOneWidget);
    expect(find.text(_l10n.hlWatchlistCreateHint), findsNothing);
    // The watchlist's markets lead, ticked, in its order.
    for (final coin in ['SOL', 'ETH', 'BTC']) {
      expect(_ticked(tester, coin), isTrue);
    }
    expect(
        tester.getTopLeft(_row('SOL')).dy < tester.getTopLeft(_row('ETH')).dy,
        isTrue);
    expect(_ticked(tester, 'XRP'), isFalse);

    // One off: one row, no squares (never a lone half square).
    await _tick(tester, 'SOL');
    await _tick(tester, 'ETH');
    await _done(tester);
    expect(container.read(hlWatchlistProvider), ['perp:BTC']);
    expect(find.byKey(const ValueKey('hl-watchlist-squares')), findsNothing);
    expect(_rows(tester), ['BTC']);

    // A swipe or the close keeps it as it was.
    await tester.ensureVisible(find.byKey(const ValueKey('hl-watchlist-edit')));
    await tester.tap(find.byKey(const ValueKey('hl-watchlist-edit')));
    await _frames(tester);
    await _tick(tester, 'BTC');
    await tester.tap(find.byType(AppBottomSheetCloseButton));
    await _frames(tester);
    expect(container.read(hlWatchlistProvider), ['perp:BTC']);

    // Emptied: Trending, and Investing opens there next time.
    await tester.ensureVisible(find.byKey(const ValueKey('hl-watchlist-edit')));
    await tester.tap(find.byKey(const ValueKey('hl-watchlist-edit')));
    await _frames(tester);
    await _tick(tester, 'BTC');
    await _done(tester);
    expect(container.read(hlWatchlistProvider), isEmpty);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.trending);
    expect(_pillWords('${_l10n.trading} · ${_l10n.categoryFilterPrompt}'),
        findsOneWidget);
    await tapAndPump(tester, investmentsPill(_l10n.overview));
    await _enterInvesting(tester);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.trending);
    await _openFilter(tester);
    expect(_tile('watchlist-create'), findsOneWidget);
    expect(_tile('watchlist'), findsNothing);

    final saved = [
      for (final e in events)
        if (e.$1 == 'watchlist_saved') e.$2
    ];
    expect(saved, [
      {
        'venue': 'hyperliquid',
        'mode': 'edit',
        'source': 'watchlist_view',
        'added': 0,
        'removed': 2,
        'list_size': 1,
      },
      {
        'venue': 'hyperliquid',
        'mode': 'edit',
        'source': 'watchlist_view',
        'added': 0,
        'removed': 1,
        'list_size': 0,
      },
    ]);
    await unmountInvestments(tester);
  });

  testWidgets(
      'a market page\'s star is the same list: starred, it is ticked in the '
      'sheet; unticked there, the star goes out; and the first star made '
      'away from Investing opens it on the Watchlist', (tester) async {
    final page = Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Column(
          children: [
            const Expanded(child: UsdAccountScreen()),
            HlWatchStar(market: _m('TSLA')),
            TextButton(
              onPressed: () =>
                  showHlWatchlistSheet(context, source: 'watchlist_view'),
              child: const Text('Open watchlist'),
            ),
          ],
        ),
      ),
    );
    final container = await _pumpPage(tester, child: page);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.trending);

    // Starred on the market page while Investing is not on screen.
    await tester.tap(find.byType(HlWatchStar));
    await tester.pump();
    expect(container.read(hlWatchlistProvider), ['perp:xyz:TSLA']);
    await _enterInvesting(tester);
    expect(
        container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.watchlist);

    await tester.tap(find.text('Open watchlist'));
    await _frames(tester);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hl-watchlist-row-perp-xyz:TSLA')),
            matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('hl-watchlist-row-perp-xyz:TSLA')));
    await tester.pump();
    await _done(tester);
    expect(container.read(hlWatchlistProvider), isEmpty);
    expect(
        find.descendant(
            of: find.byType(HlWatchStar),
            matching: find.byIcon(Icons.star_border_rounded)),
        findsOneWidget);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Predictions is unchanged: its sheet has no "Create a watchlist" and '
      'it keeps opening on Trending', (tester) async {
    _MemoryStars.stored = ['perp:BTC', 'perp:ETH'];
    final container = await _pumpPage(tester);
    await tapAndPump(tester, investmentsPill(_l10n.predictions));
    await _frames(tester);
    expect(container.read(polyBrowseSelectionProvider).pill, PolyPill.trending);
    await tapAndPump(tester, investmentsPill(_l10n.predictions));
    await _frames(tester);
    expect(_tile('watchlist-create'), findsNothing);
    expect(_tile(PolyPill.watchlist.key), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await _frames(tester);
    await _enterInvesting(tester);
    expect(
        container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.watchlist);
    await tapAndPump(tester, investmentsPill(_l10n.predictions));
    expect(container.read(polyBrowseSelectionProvider).pill, PolyPill.trending);
    await unmountInvestments(tester);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets(
        'nothing cut at 320 pt and 1.5× text, $theme: the filter sheet, the '
        'create sheet, the Watchlist view', (tester) async {
      final cut = <String>[];
      final container = await _pumpPage(tester,
          size: const Size(320, 700), dark: dark, textScale: 1.5);
      await _enterInvesting(tester);
      await _openFilter(tester);
      cut.addAll(_cut(tester, find.byType(AppBottomSheetContainer))
          .map((c) => 'filter (create): $c'));
      await tester.tap(_tile('watchlist-create'));
      await _frames(tester);
      cut.addAll(_cut(tester, find.byType(HlWatchlistSheet))
          .map((c) => 'create sheet: $c'));
      for (final coin in ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE']) {
        await _tick(tester, coin);
      }
      await _done(tester);
      expect(container.read(hlWatchlistProvider), hasLength(5));
      cut.addAll(
          _cut(tester, find.byType(HyperliquidScreen)).map((c) => 'view: $c'));
      await _openFilter(tester);
      cut.addAll(_cut(tester, find.byType(AppBottomSheetContainer))
          .map((c) => 'filter (watchlist): $c'));
      expect(cut, isEmpty, reason: cut.join('\n'));
      await unmountInvestments(tester);
    });

    testWidgets(
        'renders, $theme: the filter sheet with each card, the '
        'create sheet, the Watchlist view', (tester) async {
      if (_out.isEmpty) return;
      await _pumpPage(tester, size: const Size(390, 844), dark: dark);
      await _enterInvesting(tester);
      await _openFilter(tester);
      await _shot(tester, 'filter_create_$theme');
      await tester.tap(_tile('watchlist-create'));
      await _frames(tester);
      for (final coin in ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE']) {
        await _tick(tester, coin);
      }
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, 'create_sheet_$theme');
      await _done(tester);
      await _shot(tester, 'watchlist_view_$theme');
      await _openFilter(tester);
      await _shot(tester, 'filter_watchlist_$theme');
      await tester
          .tap(find.byKey(const ValueKey('category-tile-watchlist-edit')));
      await _frames(tester);
      await _shot(tester, 'edit_sheet_$theme');
      await unmountInvestments(tester);
    });
  }
}
