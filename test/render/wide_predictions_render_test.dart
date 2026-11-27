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

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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
import 'package:kute/screens/polymarket/components/game_side_button.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show MarketChart;
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart'
    show KuteScrubCard;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart'
    show SellSheet;
import 'package:kute/platform/kute_wide_frames.dart' show KuteSideFlow;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketBookMessage, PolymarketLiveBooks, PolymarketOrderSummary;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCloseButton;
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

/// The Advanced limit pages' captures (ap_*), written only when asked:
///   ADVANCED_LIMIT_RENDER=<dir> flutter test \
///     test/render/wide_predictions_render_test.dart
final _apDir = Platform.environment['ADVANCED_LIMIT_RENDER'];

/// The redesigned Advanced pages' captures (Spot, Limit resting, Limit
/// filling at once, a validation line; phones, a small phone and the wide
/// panel; light and dark), written only when asked:
///   ADVANCED_UI_RENDER=<dir> flutter test \
///     test/render/wide_predictions_render_test.dart --plain-name "render: ui"
final _uiDir = Platform.environment['ADVANCED_UI_RENDER'];

/// The placement engine, faked at its edges: the intent as prepared, an
/// approval bound to it, and a venue that answers that the limit rests.
class _RestingController extends PolymarketBetController {
  _RestingController(super.ref);
  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent,
          {bool requireFreshCollateral = false}) async =>
      intent;
  @override
  SensitiveIntent? reviewIntent(PendingBetIntent intent) => PmGrants.betReview(
      walletId: 'w',
      tokenId: intent.tokenId,
      maxCostUsd: intent.amount + 1,
      worstPrice: intent.limitPrice,
      orderType: 'gtc');
  @override
  void prefetchForSend(PendingBetIntent intent) {}
  @override
  Future<AuthGrantException?> place(String mode,
      {required AuthGrant grant,
      bool successHaptic = true,
      String? entrySource,
      bool requireFreshCollateral = false}) async {
    ref
        .read(pendingPolymarketBetProvider.notifier)
        .updateStatus(PendingBetStatus.done);
    return null;
  }
}

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

/// An event of [n] dated outcomes (out by a date), as the founder's
/// "out as CEO again?" page.
PolymarketEvent _dated(int n) => PolymarketEvent(
      id: 'dated$n',
      slug: 'ceo-out-again-$n',
      title: 'Jensen Huang out as NVIDIA CEO again?',
      volume: 5300000,
      volume24hr: 41000,
      liquidity: 210000,
      category: 'business',
      tags: const [],
      endDate: DateTime(2027, 12, 31),
      conditionId: 'c-dated$n',
      description: 'Resolves to Yes if he leaves the role by the date.',
      outcomes: [
        for (var i = 0; i < n; i++)
          PolymarketOutcome(
            name: 'Month ${i + 1}, 2027',
            question: 'Out by month ${i + 1}, 2027?',
            price: (0.04 + i * 0.02).clamp(0.01, 0.99).toDouble(),
            tokenId: 'd$n-$i-y',
            noTokenId: 'd$n-$i-n',
            conditionId: 'c-d$n-$i',
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

PolymarketEvent _game([String name = 'leeds_man_united']) =>
    PolymarketModel().parseEventsRaw([
      _noImages(jsonDecode(File('test/fixtures/polymarket_games/$name.json')
          .readAsStringSync())) as Map<String, dynamic>,
    ]).single;

PolymarketEvent _tennis() => _game('tennis_fils_fritz');

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

Future<void> _shoot(WidgetTester tester, String name, Size size,
    {String? dir}) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester
      .runAsync(() => boundary.toImage(pixelRatio: size.width > 600 ? 1 : 2)))!;
  final to = dir ?? _dir!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(to).createSync(recursive: true);
    File('$to/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
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
  ('1280x800', Size(1280, 800)),
  ('1180x820', Size(1180, 820)),
  ('1920x1080', Size(1920, 1080)),
  ('2400x1200', Size(2400, 1200)),
  ('1000x700', Size(1000, 700)),
  ('820x1180', Size(820, 1180)),
  ('430x932', Size(430, 932)),
];

/// The windows the open side panel is shot at too.
const _openSizes = {'1440x900', '1000x700', '1920x1080'};

/// Opens the slip on the page as a click would on EXPANDED: the right
/// column's first button, else (an event) the first outcome row's Yes.
Future<bool> _openPanel(WidgetTester tester) async {
  final buttons = find.descendant(
      of: find.byKey(const ValueKey('poly-desk-buttons')),
      matching: find.byType(GestureDetector));
  final round = find.descendant(
      of: find.byKey(const ValueKey('crypto-round-desk-column')),
      matching: find.byKey(const ValueKey('crypto-round-up')));
  final Finder target;
  if (buttons.evaluate().isNotEmpty) {
    target = buttons.first;
  } else if (round.evaluate().isNotEmpty) {
    target = round;
  } else {
    final yes = find.textContaining('Yes');
    if (yes.evaluate().isEmpty) return false;
    target = yes.first;
  }
  await tester.tap(target, warnIfMissed: false);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

Future<void> _pump(WidgetTester tester,
    {required Size size,
    required bool dark,
    required List<Override> overrides,
    required Route<void> Function() route,
    bool account = false}) async {
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
  // The Predictions account as the app has it once Predictions was opened
  // (the shell builds it): the market page lists its resting orders.
  if (account) {
    final container = ProviderScope.containerOf(
        AppRouter.rootNavigatorKey.currentContext!);
    container.listen(polymarketTradingProvider, (_, __) {});
    await tester.pump();
  }
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
    ('event3', () => _dated(3), const []),
    ('event12', () => _dated(12), const []),
    ('football', _game, const []),
    ('tennis', _tennis, const []),
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
          if (size.width >= 900 && _openSizes.contains(sizeName)) {
            if (await _openPanel(tester)) {
              expect(tester.takeException(), isNull);
              await _shoot(tester, '${name}_${sizeName}_${mode}_open', size);
            }
          }
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
        if (size.width >= 900 && _openSizes.contains(sizeName)) {
          if (await _openPanel(tester)) {
            expect(tester.takeException(), isNull);
            await _shoot(tester, 'round5m_${sizeName}_${mode}_open', size);
          }
        }
        await release(tester);
      });
    }
  }

  // ── Behaviour (always run) ──────────────────────────────────────────

  Future<void> pumpMarket(WidgetTester tester, Size size, PolymarketEvent e,
      {List<PolymarketPosition> positions = const [],
      List<Order> orders = const [],
      List<Override> extra = const [],
      bool dark = false}) async {
    await allow(tester);
    final world = CardWorld()..orders = orders;
    await _pump(tester,
        account: orders.isNotEmpty,
        size: size,
        dark: dark,
        overrides: [
          ...world.overrides(),
          polyGameLinesProvider
              .overrideWith((ref, slug) async => PolyGameLines.fromEvent(e)),
          polymarketActivePositionsProvider.overrideWithValue(positions),
          polymarketMarketHistoryProvider.overrideWith(
              (ref, params) async => _history(params.tokenId, 0.3)),
          ...extra,
        ],
        route: () => MaterialPageRoute<void>(
            settings: const RouteSettings(name: MarketDetailSheet.routeName),
            builder: (_) => MarketDetailSheet(event: e)));
  }

  // THE POINTER KIND DECIDES on the Predictions chart too: hovering a
  // mouse shows the crosshair, a finger's touch does not; the wheel over
  // the chart zooms rather than scrolling the page.
  testWidgets('wide: a mouse hover shows the chart crosshair, the wheel '
      'does not scroll the page', (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens);
    final chart = find.byType(MarketChart).first;
    final at = tester.getCenter(chart);
    expect(find.byType(KuteScrubCard), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at - const Offset(40, 0));
    await mouse.moveTo(at);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KuteScrubCard), findsOneWidget);
    await mouse.moveTo(const Offset(5, 895));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KuteScrubCard), findsNothing);
    await mouse.removePointer();
    final scrollable = tester.state<ScrollableState>(find
        .ancestor(of: chart, matching: find.byType(Scrollable))
        .first);
    final before = scrollable.position.pixels;
    final wheel = TestPointer(9, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(at));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scrollable.position.pixels, before);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final slipPanel = find.byKey(const ValueKey('bet-slip-in-place'));

  BetSlipSheet slipOf(WidgetTester tester) =>
      tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));

  testWidgets(
      'wide: at rest no slip, the right column\'s buttons; Yes opens the '
      'side panel, window edge to edge, on Yes', (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens);
    expect(slipPanel, findsNothing);
    expect(find.byType(BetSlipSheet), findsNothing);
    final column = tester.getRect(find.byKey(const ValueKey('poly-desk-column')));
    // The column at the window's right gutter.
    expect(column.right, 1440 - 24);
    await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
    await settle(tester);
    // The slip is the side panel: the window's right edge, top to bottom.
    final slip = tester.getRect(slipPanel);
    expect(slip.bottom, 900);
    expect(slip.top, 0);
    expect(slip.right, 1440);
    expect(slipOf(tester).initialOutcomeIndex, 0);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets('wide: No opens the panel on No; its X, Escape and the back '
      'each close it', (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens);
    Future<void> open() async {
      await tester.tap(find.byKey(const ValueKey('kute-bar-trade-no')));
      await settle(tester);
      expect(slipPanel, findsOneWidget);
      expect(slipOf(tester).initialOutcomeIndex, 1);
    }

    await open();
    // The X in the panel's header.
    await tester.tap(find.descendant(
        of: slipPanel, matching: find.byType(KuteCloseButton)));
    await settle(tester);
    expect(slipPanel, findsNothing);
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(slipPanel, findsNothing);
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    await open();
    // The browser's back (the route's own back): the panel first.
    await AppRouter.rootNavigatorKey.currentState!.maybePop();
    await settle(tester);
    expect(slipPanel, findsNothing);
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    // Then the page.
    await AppRouter.rootNavigatorKey.currentState!.maybePop();
    await settle(tester);
    expect(find.byType(MarketDetailSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'wide: EXPANDED opens the slip in place on Yes, its button in '
      'it and no trade row; a keyboard types the amount', (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens,
        positions: const [_alienPosition]);
    // At rest the position is the column's row.
    expect(find.byKey(const ValueKey('desk-position-y')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
    await settle(tester);
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
    // At rest: no slip, and no pair of buttons for an event of many
    // outcomes; the column starts with its figures.
    expect(find.byType(BetSlipSheet), findsNothing);
    expect(find.byKey(const ValueKey('poly-desk-buttons')), findsNothing);
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

  // "The actual predictions should be on the right side" (founder, 25
  // November 2026): what is bet on is the right column's, the figures are
  // under the chart, once; every page keeps the window's left gutter.
  final deskColumn = find.byKey(const ValueKey('poly-desk-column'));
  final figures = find.byKey(const ValueKey('poly-desk-figures'));

  void figuresUnderChart(WidgetTester tester) {
    expect(figures, findsOneWidget);
    expect(find.descendant(of: deskColumn, matching: figures), findsNothing);
    expect(find.text('Liquidity'), findsOneWidget);
    final chart = tester.getRect(find.byType(MarketChart).first);
    expect(tester.getRect(figures).top, greaterThan(chart.bottom - 1));
    expect(tester.getRect(figures).right,
        lessThan(tester.getRect(deskColumn).left));
    expect(chart.left, greaterThanOrEqualTo(24));
  }

  for (final n in [3, 12]) {
    testWidgets('wide: an event of $n: its outcomes in the column, the '
        'figures under the chart; a click opens the panel on it',
        (tester) async {
      await pumpMarket(tester, const Size(1440, 900), _dated(n));
      expect(tester.takeException(), isNull);
      figuresUnderChart(tester);
      final row = find.text('Month 2, 2027');
      expect(row, findsOneWidget);
      expect(find.descendant(of: deskColumn, matching: row), findsOneWidget);
      expect(
          find.descendant(
              of: deskColumn,
              matching: find.byKey(const ValueKey('poly-market-options'))),
          findsOneWidget);
      // The header's title keeps the gutter.
      expect(tester.getRect(find.text('Jensen Huang out as NVIDIA CEO again?'))
          .left, greaterThanOrEqualTo(24));
      await tester.tap(row);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(slipPanel, findsOneWidget);
      expect(find.text('Out by month 2, 2027?'), findsOneWidget);
      expect(find.byType(MarketDetailSheet), findsOneWidget);
      await release(tester);
    });
  }

  testWidgets('wide: a game: its markets in the column under the sides',
      (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _tennis());
    expect(tester.takeException(), isNull);
    figuresUnderChart(tester);
    expect(
        find.descendant(
            of: deskColumn,
            matching: find.byKey(const ValueKey('poly-desk-buttons'))),
        findsOneWidget);
    expect(find.descendant(of: deskColumn, matching: find.text('More markets')),
        findsOneWidget);
    expect(find.text('More markets'), findsOneWidget);
    // The Winner row is the column's sides, not twice.
    final sideA = tester.widget<PolyGameSideButton>(
        find.byKey(const ValueKey('poly-desk-side-a')));
    expect(
        find.byWidgetPredicate(
            (w) => w is PolyGameSideButton && w.label == sideA.label),
        findsOneWidget);
    await release(tester);
  });

  testWidgets('wide: a Yes / No market: its figures under the chart too',
      (tester) async {
    await pumpMarket(tester, const Size(1440, 900), _aliens,
        positions: const [_alienPosition]);
    figuresUnderChart(tester);
    expect(find.descendant(
            of: deskColumn,
            matching: find.byKey(const ValueKey('desk-position-y'))),
        findsOneWidget);
    await release(tester);
  });

  testWidgets('wide: a phone keeps the trade row and no slip in place',
      (tester) async {
    await pumpMarket(tester, const Size(430, 932), _aliens);
    expect(find.byKey(const ValueKey('bet-slip-in-place')), findsNothing);
    expect(find.byKey(const ValueKey('kute-bar-trade-row')), findsOneWidget);
    await release(tester);
  });

  // ── Advanced limits (the audit before `trading.advanced` is on) ─────

  // A resting limit buy on the aliens market's Yes, and one on another
  // market that must not show here.
  final restingYes = Order(
    id: 'rest-y',
    market: 'c-aliens',
    assetId: 'y',
    owner: 'x',
    side: 'BUY',
    price: '0.04',
    originalSize: '250',
    sizeMatched: '40',
    outcome: 'Yes',
    timestamp: '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7200}',
  );
  final restingElsewhere = Order(
    id: 'rest-other',
    market: 'c-other',
    assetId: 'other',
    owner: 'x',
    side: 'BUY',
    price: '0.5',
    originalSize: '10',
    sizeMatched: '0',
    outcome: 'Yes',
  );

  Future<void> openAdvancedLimit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('slip-advanced-button')).first);
    await settle(tester);
    await tester.ensureVisible(find.text('Limit').last);
    await tester.tap(find.text('Limit').last);
    await settle(tester);
  }

  /// Places the limit on the Advanced page through the slip's own path:
  /// the approval is the test's seam, the venue a fake that answers that it
  /// rests (nothing is signed or sent).
  Future<void> placeRestingLimit(WidgetTester tester) async {
    await openAdvancedLimit(tester);
    await tester.enterText(find.byType(TextField).last, '5');
    await settle(tester);
    final cta = find.textContaining(r'Place $5.00 limit at');
    await tester.ensureVisible(cta.last);
    await tester.tap(cta.last);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<Override> placing() => [
        polymarketBetControllerProvider.overrideWith(_RestingController.new),
      ];

  testWidgets(
      'P7 wide: a limit placed from Advanced over the slip in place keeps '
      'the market page and its slip (through the placement)', (tester) async {
    debugPmBetApproval = (review) async =>
        AuthGrants.issue(review, method: AuthGrantMethod.allowance);
    addTearDown(() => debugPmBetApproval = null);
    await pumpMarket(tester, const Size(1440, 900), _aliens, extra: placing());
    await placeRestingLimit(tester);
    expect(find.text('Advanced prediction'), findsNothing);
    expect(find.byType(MarketDetailSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('bet-slip-in-place')), findsOneWidget);
    // The resting receipt and its rows.
    expect(find.text('Until canceled'), findsOneWidget);
    expect(find.text('Reserved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'P7 phone: the same placement closes the slip and the market sheet, '
      'as before', (tester) async {
    debugPmBetApproval = (review) async =>
        AuthGrants.issue(review, method: AuthGrantMethod.allowance);
    addTearDown(() => debugPmBetApproval = null);
    await pumpMarket(tester, const Size(430, 932), _aliens, extra: placing());
    await placeRestingLimit(tester);
    expect(find.text('Advanced prediction'), findsNothing);
    expect(find.byType(MarketDetailSheet), findsNothing);
    expect(find.text('Until canceled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets('P7 phone: Advanced over the sheet slip is not marked',
      (tester) async {
    await pumpMarket(tester, const Size(430, 932), _aliens);
    await openAdvancedLimit(tester);
    expect(find.text('Advanced prediction'), findsOneWidget);
    expect(find.byKey(const ValueKey('prediction-advanced-over-in-place')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'resting orders: the market page lists this market\'s, phone and '
      'wide (the right column at rest, the side panel\'s footer open)',
      (tester) async {
    await pumpMarket(tester, const Size(430, 932), _aliens,
        orders: [restingYes, restingElsewhere]);
    final listed = find.byKey(const ValueKey('poly-market-orders'));
    await tester.scrollUntilVisible(listed, 200,
        scrollable: find.byType(Scrollable).first);
    expect(listed, findsOneWidget);
    expect(find.byKey(const ValueKey('market-order-rest-y')), findsOneWidget);
    expect(find.byKey(const ValueKey('market-order-rest-other')), findsNothing);
    await release(tester);

    await pumpMarket(tester, const Size(1440, 900), _aliens,
        orders: [restingYes, restingElsewhere]);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-desk-column')),
            matching: find.byKey(const ValueKey('market-order-rest-y'))),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
    await settle(tester);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('slip-panel-footer')),
            matching: find.byKey(const ValueKey('market-order-rest-y'))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('market-order-rest-other')), findsNothing);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  const apSizes = [('phone', Size(430, 932)), ('wide', Size(1440, 900))];
  for (final (form, size) in apSizes) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: ap market with a resting order $form $mode',
          skip: _apDir == null, (tester) async {
        await pumpMarket(tester, size, _aliens,
            orders: [restingYes], dark: dark);
        if (form == 'phone') {
          final listed = find.byKey(const ValueKey('poly-market-orders'));
          await tester.scrollUntilVisible(listed, 200,
              scrollable: find.byType(Scrollable).first);
          await settle(tester);
          await _shoot(tester, 'ap_market_resting_${form}_$mode', size,
              dir: _apDir);
        } else {
          await _shoot(tester, 'ap_market_resting_${form}_$mode', size,
              dir: _apDir);
          await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
          await settle(tester);
          await _shoot(tester, 'ap_market_resting_${form}_${mode}_open', size,
              dir: _apDir);
        }
        expect(tester.takeException(), isNull);
        await release(tester);
      });

      testWidgets('render: ap buy advanced limit $form $mode',
          skip: _apDir == null, (tester) async {
        await pumpMarket(tester, size, _aliens,
            orders: [restingYes], dark: dark);
        await openAdvancedLimit(tester);
        await _shoot(tester, 'ap_buy_advanced_${form}_$mode', size,
            dir: _apDir);
        expect(tester.takeException(), isNull);
        await release(tester);
      });

      testWidgets('render: ap sell advanced limit $form $mode',
          skip: _apDir == null, (tester) async {
        await pumpMarket(tester, size, _aliens,
            positions: const [_alienPosition],
            orders: [
              Order(
                id: 'rest-sell',
                market: 'c-aliens',
                assetId: 'y',
                owner: 'x',
                side: 'SELL',
                price: '0.12',
                originalSize: '50',
                sizeMatched: '0',
                outcome: 'Yes',
              ),
            ],
            dark: dark);
        final nav = AppRouter.rootNavigatorKey.currentState!;
        if (size.width >= 900) KuteSideFlow.arm();
        SellSheet.show(nav.context,
            position: _alienPosition, startWithLimit: true);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _shoot(tester, 'ap_sell_advanced_${form}_$mode', size,
            dir: _apDir);
        expect(tester.takeException(), isNull);
        await release(tester);
      });
    }
  }

  // ── The redesigned Advanced pages (advanced_ticket.dart) ─────────────

  /// The aliens market's Yes book on the feed: bid 5¢, ask 7¢.
  void seedYesBook() =>
      PolymarketLiveBooks.instance.debugSeed(PolymarketBookMessage(
        assetId: 'y',
        market: 'm',
        timestamp: 0,
        hash: '',
        bids: [PolymarketOrderSummary(price: 0.05, size: 500)],
        asks: [PolymarketOrderSummary(price: 0.07, size: 500)],
      ));

  Future<void> openAdvancedPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('kute-bar-trade-yes')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('slip-advanced-button')).first);
    await settle(tester);
  }

  Future<void> typeAmount(WidgetTester tester, String amount) async {
    await tester.enterText(find.byType(TextField).last, amount);
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
  }

  Future<void> chooseLimit(WidgetTester tester) async {
    final limit = find.text('Limit').last;
    await tester.ensureVisible(limit);
    await tester.tap(limit);
    await settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    final f = find.byKey(key);
    if (f.evaluate().isEmpty) return;
    await tester.ensureVisible(f);
    await settle(tester);
  }

  const uiSizes = [
    ('phone', Size(402, 874), [false, true]),
    ('small', Size(375, 667), [false]),
    ('wide', Size(1440, 900), [false, true]),
  ];
  for (final (form, size, modes) in uiSizes) {
    for (final dark in modes) {
      final mode = dark ? 'dark' : 'light';
      final tag = '${form}_$mode';
      testWidgets('render: ui buy empty and spot $tag', skip: _uiDir == null,
          (tester) async {
        seedYesBook();
        await pumpMarket(tester, size, _aliens, dark: dark);
        await openAdvancedPage(tester);
        await _shoot(tester, 'buy_empty_$tag', size, dir: _uiDir);
        await typeAmount(tester, '25');
        await _shoot(tester, 'buy_spot_$tag', size, dir: _uiDir);
        await scrollTo(tester, const ValueKey('bet-slip-advanced-summary'));
        await _shoot(tester, 'buy_spot_summary_$tag', size, dir: _uiDir);
        expect(tester.takeException(), isNull);
        await release(tester);
      });

      testWidgets('render: ui buy limit $tag', skip: _uiDir == null,
          (tester) async {
        seedYesBook();
        await pumpMarket(tester, size, _aliens, dark: dark);
        await openAdvancedPage(tester);
        await typeAmount(tester, '25');
        await chooseLimit(tester);
        // The page from its top, as it opens on Limit.
        final scroll = tester.state<ScrollableState>(find.descendant(
            of: find.byKey(const ValueKey('prediction-advanced-form-scroll')),
            matching: find.byType(Scrollable)).first);
        scroll.position.jumpTo(0);
        await settle(tester);
        await _shoot(tester, 'buy_limit_top_$tag', size, dir: _uiDir);
        // Resting: the seed (6¢) is under the 7¢ ask.
        await scrollTo(tester, const ValueKey('advanced-odds-track'));
        await _shoot(tester, 'buy_limit_resting_$tag', size, dir: _uiDir);
        // Filling at once: one step up, to the ask.
        await tester.tap(find.byKey(const ValueKey('advanced-stepper-plus')));
        await settle(tester);
        await _shoot(tester, 'buy_limit_fills_now_$tag', size, dir: _uiDir);
        await scrollTo(tester, const ValueKey('bet-slip-advanced-summary'));
        await _shoot(tester, 'buy_limit_summary_$tag', size, dir: _uiDir);
        // A validation line: under the market's minimum.
        await typeAmount(tester, '0.20');
        await tester.ensureVisible(find.byKey(const ValueKey('advanced-hero-amount')));
        await settle(tester);
        await _shoot(tester, 'buy_limit_validation_$tag', size, dir: _uiDir);
        expect(tester.takeException(), isNull);
        await release(tester);
      });

      testWidgets('render: ui sell limit $tag', skip: _uiDir == null,
          (tester) async {
        seedYesBook();
        await pumpMarket(tester, size, _aliens,
            positions: const [_alienPosition], dark: dark);
        final nav = AppRouter.rootNavigatorKey.currentState!;
        if (size.width >= 900) KuteSideFlow.arm();
        SellSheet.show(nav.context,
            position: _alienPosition, startWithLimit: true);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await typeAmount(tester, '3');
        await _shoot(tester, 'sell_limit_$tag', size, dir: _uiDir);
        await scrollTo(tester, const ValueKey('sell-advanced-summary'));
        await _shoot(tester, 'sell_limit_summary_$tag', size, dir: _uiDir);
        expect(tester.takeException(), isNull);
        await release(tester);
      });
    }
  }
}
