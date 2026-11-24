// A bet from a browse card on a laptop (founder, 24 November 2026, on a
// sports card's "Miami" button in Dollars › Predictions: "this is wrong
// ... when clicking here on the button directly. fix"): on EXPANDED a
// card's Yes / No or team button, and the Trending round card's Up / Down,
// open the market's (the round's) full page with the slip already open in
// its side panel on the side clicked, never a slip floating over the
// browse; back returns to the browse. The slip is counted once, from the
// card, as before (no page view besides). A phone and MEDIUM keep the slip
// as the sheet it was.
// Pictures only when asked (the behaviour checks always run):
//   CARD_BUTTONS_RENDER=<dir> flutter test \
//     test/render/card_buttons_full_render_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show PredictionsVenueFunder;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';
import '../screens/polymarket/crypto_next_round_card_test.dart'
    show CardWorld, roundStart;

final _dir = Platform.environment['CARD_BUTTONS_RENDER'];

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

PolymarketEvent _event(String slug, String title, String category,
        List<PolymarketOutcome> o) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: title,
      volume: 1e6,
      liquidity: 1e5,
      category: category,
      tags: const [],
      conditionId: slug,
      endDate: DateTime.utc(2030, 12, 31),
      outcomes: o,
    );

final _yesNo = _event('fed', 'Fed cuts rates in December?', 'politics', const [
  PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y', conditionId: 'f'),
  PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n', conditionId: 'f'),
]);

/// The founder's card: two teams, the market's own two outcomes.
final _twoWay =
    _event('gmiami', 'Miami (OH) vs. Western Michigan', 'sports', const [
  PolymarketOutcome(name: 'Miami (OH)', price: 0.36, tokenId: 'mia'),
  PolymarketOutcome(name: 'Western Michigan', price: 0.64, tokenId: 'wmu'),
]);

/// The fixture without its pictures (no image cache in a test).
Object? _noImages(Object? json) => switch (json) {
      final Map<String, dynamic> m => {
          for (final e in m.entries)
            if (!const {'image', 'icon', 'logo', 'imageUrl'}.contains(e.key))
              e.key: _noImages(e.value),
        },
      final List<dynamic> l => [for (final v in l) _noImages(v)],
      _ => json,
    };

/// A football match with a draw (three winner markets).
PolymarketEvent _threeWay() => PolymarketModel().parseEventsRaw([
      _noImages(jsonDecode(
          File('test/fixtures/polymarket_games/leeds_man_united.json')
              .readAsStringSync())) as Map<String, dynamic>,
    ]).single;

List<PolymarketPricePoint> _history(double last) {
  final now = DateTime.now();
  return [
    for (var i = 0; i < 60; i++)
      PolymarketPricePoint(
          timestamp: now.subtract(Duration(hours: 59 - i)),
          price: (last + (i % 7 - 3) * 0.004).clamp(0.01, 0.99)),
  ];
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name, Size size) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester
      .runAsync(() => boundary.toImage(pixelRatio: size.width > 600 ? 1 : 2)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

/// A browse page in miniature: [event]'s card wired as the Predictions
/// list wires it (polymarket_screen.dart's feed card), or the Trending
/// round card when [event] is null.
class _Browse extends StatelessWidget {
  const _Browse({this.event});

  final PolymarketEvent? event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: e == null
                  ? CryptoPredictBanner(
                      config: kCryptoPredictAssets.first,
                      showLiveIndicator: true,
                      compact: true,
                    )
                  : MarketCard(
                      title: e.displayTitle,
                      outcomes: e.outcomes,
                      volume: e.volume,
                      category: e.category,
                      endDate: e.endDate,
                      slug: e.slug,
                      onTap: () => MarketDetailSheet.show(context,
                          event: e, source: 'feed_card'),
                      onPickSide: (pick) => polyCardOpenSlip(context,
                          event: e, pick: pick, source: 'feed_card'),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  RuntimeCapabilitiesService? policy;
  late List<(String, Map<String, Object>?)> events;
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    kuteShellMounted.value = true;
    OpenOnce.reset();
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path);
  });
  tearDown(() {
    kuteShellMounted.value = false;
    PredictionsVenueFunder.debugRouteShare = null;
    TrackingService.debugTrackObserver = null;
    BetSlipSheet.debugClock = DateTime.now;
  });

  Future<void> pump(WidgetTester tester,
      {required Size size, bool dark = false, PolymarketEvent? event}) async {
    AffiliateService.debugSessionToken = 'test-session';
    final p = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = p;
    await tester.runAsync(() => p.refresh());
    policy = p;
    final world = CardWorld()
      ..now = roundStart.add(const Duration(minutes: 1, seconds: 10));
    world.install();
    world.quoteCurrent();
    world.listNext();
    BetSlipSheet.debugClock = () => world.now;
    await _fonts(tester);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sportsLiveProvider.overrideWith(_NoGames.new),
        polyGameTimelineProvider.overrideWith(_NoTimeline.new),
        polymarketClaimablePositionsProvider.overrideWithValue(const []),
        polymarketActivePositionsProvider.overrideWithValue(const []),
        polyWatchlistProvider.overrideWith(_NoStars.new),
        polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
        if (event != null)
          polyGameLinesProvider.overrideWith(
              (ref, slug) async => PolyGameLines.fromEvent(event)),
        polymarketMarketHistoryProvider
            .overrideWith((ref, params) async => _history(0.4)),
        ...world.overrides(),
      ],
      child: ScreenUtilInit(
        designSize: KuteLayout.designSizeFor(size),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: AppRouter.rootNavigatorKey,
          navigatorObservers: [KuteBarRouteObserver()],
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('shot'),
            child: Stack(children: [child!, const KuteShellBar()]),
          ),
          home: _Browse(event: event),
        ),
      ),
    ));
    await _settle(tester);
  }

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 31));
    policy?.dispose();
    policy = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  }

  BetSlipSheet slip(WidgetTester tester) =>
      tester.widget<BetSlipSheet>(find.byType(BetSlipSheet).last);

  final inPanel = find.byKey(const ValueKey('bet-slip-in-place'));

  /// The slip was counted once, from the card, as before; no page view
  /// besides, and nothing placed.
  void countedOnce(String source) {
    final names = events.map((e) => e.$1).toList();
    expect(names.where((n) => n == 'polymarket_bet_slip_opened'), hasLength(1),
        reason: '$names');
    expect(
        events
            .firstWhere((e) => e.$1 == 'polymarket_bet_slip_opened')
            .$2?['source'],
        source);
    expect(names, isNot(contains('polymarket_viewed')));
    expect(names.where((n) => n.contains('placed')), isEmpty);
  }

  // Each card's button: (name, event, the button's text, the slip's
  // outcome index, its token there).
  final cards = <(String, PolymarketEvent Function(), String, int, String)>[
    ('yesno_no', () => _yesNo, 'No 39¢', 1, 'n'),
    ('yesno_yes', () => _yesNo, 'Yes 62¢', 0, 'y'),
    ('game_miami', () => _twoWay, 'Miami 36¢', 0, 'mia'),
    ('game_wmu', () => _twoWay, 'W Michigan 64¢', 1, 'wmu'),
  ];

  /// The button on the card whose text starts like [label] (a team's
  /// short name may differ from the test's guess).
  Finder button(String label) {
    final exact = find.text(label);
    if (exact.evaluate().isNotEmpty) return exact;
    final cents = label.substring(label.lastIndexOf(' ') + 1);
    return find.textContaining(cents);
  }

  // ── Pictures (when asked) ───────────────────────────────────────────

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (name, size) in const [
      ('1440x900', Size(1440, 900)),
      ('1180x820', Size(1180, 820)),
    ]) {
      testWidgets('render: the Miami button opens the page $name $mode',
          skip: _dir == null, (tester) async {
        await pump(tester, size: size, dark: dark, event: _twoWay);
        await _shoot(tester, 'browse_game_${name}_$mode', size);
        await tester.tap(button('Miami 36¢'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_game_miami_${name}_$mode', size);
        await release(tester);
      });
      testWidgets('render: No opens the page on No $name $mode',
          skip: _dir == null, (tester) async {
        await pump(tester, size: size, dark: dark, event: _yesNo);
        await tester.tap(find.text('No 39¢'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_yesno_no_${name}_$mode', size);
        await release(tester);
      });
      testWidgets('render: a draw opens the match on the draw $name $mode',
          skip: _dir == null, (tester) async {
        await pump(tester, size: size, dark: dark, event: _threeWay());
        await tester.tap(find.textContaining('Draw '));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_threeway_draw_${name}_$mode', size);
        await release(tester);
      });
      testWidgets('render: the round card\'s Down $name $mode',
          skip: _dir == null, (tester) async {
        await pump(tester, size: size, dark: dark);
        await tester.tap(find.byKey(const ValueKey('crypto-round-down')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_round_down_${name}_$mode', size);
        await release(tester);
      });
    }
  }

  // ── Behaviour (always run) ──────────────────────────────────────────

  for (final (name, event, label, index, token) in cards) {
    testWidgets(
        'EXPANDED $name: the button opens the market\'s page with the slip '
        'in its side panel on that side; back returns to the browse',
        (tester) async {
      await pump(tester, size: const Size(1440, 900), event: event());
      await tester.tap(button(label));
      await _settle(tester);
      expect(find.byType(MarketDetailSheet), findsOneWidget);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      final panel = tester.getRect(inPanel);
      expect(panel.right, 1440);
      expect(panel.top, 0);
      expect(panel.bottom, 900);
      expect(slip(tester).initialOutcomeIndex, index);
      expect(slip(tester).outcomes[index].tokenId, token);
      expect(slip(tester).source, 'feed_card');
      countedOnce('feed_card');
      expect(tester.takeException(), isNull);
      // Back: the browse, as it was.
      AppRouter.rootNavigatorKey.currentState!.pop();
      await _settle(tester);
      expect(find.byType(MarketDetailSheet), findsNothing);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(find.byType(MarketCard), findsOneWidget);
      await release(tester);
    });
  }

  testWidgets(
      'EXPANDED: a three-way match\'s draw opens the match with the slip '
      'on the draw', (tester) async {
    await pump(tester, size: const Size(1440, 900), event: _threeWay());
    await tester.tap(find.textContaining('Draw '));
    await _settle(tester);
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    expect(inPanel, findsOneWidget);
    expect(slip(tester).initialOutcomeIndex, 1);
    expect(slip(tester).outcomeLabels?[1], 'Draw');
    countedOnce('feed_card');
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'EXPANDED: the Trending round card\'s Down opens the round\'s page '
      'with the slip on Down', (tester) async {
    await pump(tester, size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('crypto-round-down')));
    await _settle(tester);
    expect(find.byType(FiveMinMarketDetailSheet), findsOneWidget);
    expect(inPanel, findsOneWidget);
    expect(find.byType(BetSlipSheet), findsOneWidget);
    expect(slip(tester).initialOutcomeIndex, 1);
    expect(slip(tester).source, 'crypto_banner');
    countedOnce('crypto_banner');
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  for (final size in const [Size(430, 932), Size(820, 1180)]) {
    final w = size.width.toInt();
    for (final (name, event, label, index, token) in cards) {
      testWidgets('$w wide $name: the slip opens as before, no page',
          (tester) async {
        await pump(tester, size: size, event: event());
        await tester.tap(button(label));
        await _settle(tester);
        expect(find.byType(MarketDetailSheet), findsNothing);
        expect(inPanel, findsNothing);
        expect(slip(tester).initialOutcomeIndex, index);
        expect(slip(tester).outcomes[index].tokenId, token);
        countedOnce('feed_card');
        await release(tester);
      });
    }
    testWidgets('$w wide: the round card\'s Up opens the slip as before',
        (tester) async {
      await pump(tester, size: size);
      await tester.tap(find.byKey(const ValueKey('crypto-round-up')));
      await _settle(tester);
      expect(find.byType(FiveMinMarketDetailSheet), findsNothing);
      expect(inPanel, findsNothing);
      expect(slip(tester).initialOutcomeIndex, 0);
      await release(tester);
    });
  }
}
