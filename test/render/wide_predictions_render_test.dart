// A look by eye at the Predictions market pages on the wide layouts
// (platform/kute_layout.dart; founder, 24 November 2026: "showing the
// graphs on the left with the interfaces on the right"): a Yes / No
// market (with and without a position), a multi-outcome event, a
// football match and a five-minute round, at 1440x900 and 1180x820
// (EXPANDED: the page left, the bet slip open in place right), 820x1180
// (MEDIUM: the phone's column, centred) and 430x932 (a phone, as before),
// light and dark. Written only when asked (the behaviour checks at the
// end always run):
//   WIDE_PREDICTIONS_RENDER=<dir> flutter test \
//     test/render/wide_predictions_render_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, MethodChannel, rootBundle;
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
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show PredictionsVenueFunder;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';
import '../screens/polymarket/crypto_next_round_card_test.dart'
    show CardWorld, roundStart;

final _dir = Platform.environment['WIDE_PREDICTIONS_RENDER'];

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

const _rules = 'This market will resolve to "Yes" if the President of the '
    'United States, or an official US government agency, publicly confirms '
    'the existence of extraterrestrial life or technology by December 31, '
    '2026, 11:59 PM ET. Otherwise, this market will resolve to "No".';

final _aliens = PolymarketEvent(
  id: 'aliens',
  slug: 'will-the-us-confirm-that-aliens-exist-before-2027',
  title: 'Will the US confirm that aliens exist before 2027?',
  volume: 1200000,
  liquidity: 50000,
  category: 'science',
  tags: const [],
  endDate: DateTime(2027, 1, 1),
  conditionId: 'c-aliens',
  description: _rules,
  outcomes: const [
    PolymarketOutcome(
        name: 'Yes', price: 0.06, tokenId: 'y', conditionId: 'c-aliens'),
    PolymarketOutcome(
        name: 'No', price: 0.94, tokenId: 'n', conditionId: 'c-aliens'),
  ],
);

final _election = PolymarketEvent(
  id: 'el',
  slug: 'presidential-election-winner-2028',
  title: 'Presidential Election Winner 2028',
  volume: 9200000,
  liquidity: 900000,
  category: 'politics',
  tags: const [],
  endDate: DateTime(2028, 11, 7),
  conditionId: 'c-el',
  description: 'Resolves to the winner of the 2028 US presidential election.',
  outcomes: [
    for (final (i, (name, p)) in const [
      ('J.D. Vance', 0.29),
      ('Gavin Newsom', 0.21),
      ('Alexandria Ocasio-Cortez', 0.08),
      ('Marco Rubio', 0.06),
      ('Josh Shapiro', 0.05),
      ('Pete Buttigieg', 0.04),
      ('Andy Beshear', 0.03),
    ].indexed)
      PolymarketOutcome(
        name: name,
        question: 'Will $name win the 2028 US Presidential Election?',
        price: p,
        tokenId: 'el$i-y',
        noTokenId: 'el$i-n',
        conditionId: 'c-el$i',
      ),
  ],
);

/// The fixture without its pictures (no image cache in a test): the
/// crests fall back to their initials.
Object? _noImages(Object? json) => switch (json) {
      final Map<String, dynamic> m => {
          for (final e in m.entries)
            if (!const {'image', 'icon', 'logo', 'imageUrl'}.contains(e.key))
              e.key: _noImages(e.value),
        },
      final List<dynamic> l => [for (final v in l) _noImages(v)],
      _ => json,
    };

PolymarketEvent _game() => PolymarketModel().parseEventsRaw([
      _noImages(jsonDecode(
          File('test/fixtures/polymarket_games/leeds_man_united.json')
              .readAsStringSync())) as Map<String, dynamic>,
    ]).single;

const _alienPosition = PolymarketPosition(
  marketId: 'c-aliens',
  marketQuestion: 'Will the US confirm that aliens exist before 2027?',
  outcome: 'Yes',
  size: 120,
  avgPrice: 0.05,
  currentPrice: 0.06,
  pnl: 1.2,
  pnlPercent: 20,
  isResolved: false,
  tokenId: 'y',
);

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

/// A made-up but plausible history for [token] ending now at [last]:
/// a soft walk, the same for a token on every run.
List<PolymarketPricePoint> _history(String token, double last) {
  final now = DateTime.now();
  var seed = token.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
  double rnd() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff - 0.5;
  }

  const n = 160;
  final walk = <double>[last];
  for (var i = 1; i < n; i++) {
    walk.add((walk.last + rnd() * 0.02 - 0.0004).clamp(0.01, 0.99));
  }
  return [
    for (var i = 0; i < n; i++)
      PolymarketPricePoint(
          timestamp: now.subtract(Duration(hours: (n - 1 - i) * 1)),
          price: walk[n - 1 - i]),
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

const _sizes = [
  ('1440x900', Size(1440, 900)),
  ('1180x820', Size(1180, 820)),
  ('820x1180', Size(820, 1180)),
  ('430x932', Size(430, 932)),
];

Future<void> _pump(WidgetTester tester,
    {required Size size,
    required bool dark,
    required List<Override> overrides,
    required Route<void> Function() route}) async {
  await _fonts(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polyWatchlistProvider.overrideWith(_NoStars.new),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      ...overrides,
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
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pump();
  AppRouter.rootNavigatorKey.currentState!.push(route());
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  RuntimeCapabilitiesService? policy;
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    kuteShellMounted.value = true;
    OpenOnce.reset();
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    // The crests' image cache asks for a directory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path);
  });
  tearDown(() {
    kuteShellMounted.value = false;
    PredictionsVenueFunder.debugRouteShare = null;
    BetSlipSheet.debugClock = DateTime.now;
  });

  Future<void> allow(WidgetTester tester) async {
    AffiliateService.debugSessionToken = 'test-session';
    final p = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = p;
    await tester.runAsync(() => p.refresh());
    policy = p;
  }

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    policy?.dispose();
    policy = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  }

  final markets =
      <(String, PolymarketEvent Function(), List<PolymarketPosition>)>[
    ('yesno', () => _aliens, const []),
    ('yesno_position', () => _aliens, const [_alienPosition]),
    ('event', () => _election, const []),
    ('football', _game, const []),
  ];

  for (final (sizeName, size) in _sizes) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      for (final (name, event, positions) in markets) {
        testWidgets('render: $name $sizeName $mode', skip: _dir == null,
            (tester) async {
          await allow(tester);
          final world = CardWorld();
          final e = event();
          await _pump(tester,
              size: size,
              dark: dark,
              overrides: [
                ...world.overrides(),
                polyGameLinesProvider.overrideWith(
                    (ref, slug) async => PolyGameLines.fromEvent(e)),
                polymarketActivePositionsProvider.overrideWithValue(positions),
                polymarketMarketHistoryProvider
                    .overrideWith((ref, params) async {
                  final o = [
                    for (final o in e.outcomes) ...[
                      (o.tokenId, o.price),
                      (o.noTokenId, 1 - o.price),
                    ],
                  ].where((t) => t.$1 == params.tokenId).firstOrNull;
                  return _history(params.tokenId, o?.$2 ?? 0.5);
                }),
              ],
              route: () => MaterialPageRoute<void>(
                  settings:
                      const RouteSettings(name: MarketDetailSheet.routeName),
                  builder: (_) => MarketDetailSheet(event: e)));
          expect(tester.takeException(), isNull);
          await _shoot(tester, '${name}_${sizeName}_$mode', size);
          await release(tester);
        });
      }

      testWidgets('render: round5m $sizeName $mode', skip: _dir == null,
          (tester) async {
        await allow(tester);
        final world = CardWorld()
          ..now = roundStart.add(const Duration(minutes: 1, seconds: 10));
        world.install();
        world.quoteCurrent();
        world.listNext();
        BetSlipSheet.debugClock = () => world.now;
        final event = PolymarketEvent(
          id: 'btc5',
          slug: 'btc-updown-5m-${roundStart.millisecondsSinceEpoch ~/ 1000}',
          title: 'Bitcoin Up or Down',
          volume: 0,
          liquidity: 100000,
          category: 'crypto',
          tags: const [],
          endDate: roundStart.add(const Duration(minutes: 5)),
          conditionId: 'cur-cond',
          outcomes: const [
            PolymarketOutcome(name: 'Up', price: 0.6, tokenId: 'cur-up'),
            PolymarketOutcome(name: 'Down', price: 0.4, tokenId: 'cur-down'),
          ],
        );
        await _pump(tester,
            size: size,
            dark: dark,
            overrides: world.overrides(),
            route: () => MaterialPageRoute<void>(
                settings: const RouteSettings(
                    name: FiveMinMarketDetailSheet.routeName),
                builder: (_) => FiveMinMarketDetailSheet(event: event)));
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'round5m_${sizeName}_$mode', size);
        await release(tester);
      });
    }
  }

  // ── Behaviour (always run) ──────────────────────────────────────────

  Future<void> pumpMarket(WidgetTester tester, Size size, PolymarketEvent e,
      {List<PolymarketPosition> positions = const []}) async {
    await allow(tester);
    final world = CardWorld();
    await _pump(tester,
        size: size,
        dark: false,
        overrides: [
          ...world.overrides(),
          polyGameLinesProvider
              .overrideWith((ref, slug) async => PolyGameLines.fromEvent(e)),
          polymarketActivePositionsProvider.overrideWithValue(positions),
          polymarketMarketHistoryProvider.overrideWith(
              (ref, params) async => _history(params.tokenId, 0.3)),
        ],
        route: () => MaterialPageRoute<void>(
            settings: const RouteSettings(name: MarketDetailSheet.routeName),
            builder: (_) => MarketDetailSheet(event: e)));
  }

  testWidgets(
      'wide: EXPANDED opens the slip in place on Yes, its button in '
      'it and no trade row; a keyboard types the amount', (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens,
        positions: const [_alienPosition]);
    expect(find.byKey(const ValueKey('bet-slip-in-place')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('poly-slip-cta-in-place')), findsOneWidget);
    expect(find.byKey(const ValueKey('kute-bar-trade-row')), findsNothing);
    // The trade row's round Sal button, beside Place in the pane.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-slip-cta-in-place')),
            matching: find.byKey(const ValueKey('kute-bar-share-slot'))),
        findsOneWidget);
    // The position's card under the slip.
    expect(find.byKey(const ValueKey('wide-position-y')), findsOneWidget);
    expect(find.text('Place minimum on Yes'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining(r'$25'), findsWidgets);
    expect(find.text('Place minimum on Yes'), findsNothing);
    await release(tester);
  });

  testWidgets('wide: a tap on an event\'s outcome picks it in the slip',
      (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _election);
    expect(find.text('Will J.D. Vance win the 2028 US Presidential Election?'),
        findsOneWidget);
    await tester.tap(find.text('Gavin Newsom').last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
        find.text('Will Gavin Newsom win the 2028 US Presidential Election?'),
        findsOneWidget);
    // Still one page: the outcome's own page was not pushed.
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    await release(tester);
  });

  testWidgets('wide: a phone keeps the trade row and no slip in place',
      (tester) async {
    await pumpMarket(tester, const Size(430, 932), _aliens);
    expect(find.byKey(const ValueKey('bet-slip-in-place')), findsNothing);
    expect(find.byKey(const ValueKey('kute-bar-trade-row')), findsOneWidget);
    await release(tester);
  });
}
