// The Crypto pages' round card on a laptop opens the round's own page
// (founder, 24 November 2026: "clicking here should make it full screen
// also"): a click on the card (its header, figures or chart) opens the
// round's page, the market desk with the slip as the side panel; Up / Down
// open it with the slip on that side. A phone and MEDIUM keep the card as
// it was (no page from the card; Up / Down open the slip as before).
// Pictures only when asked (the behaviour checks always run):
//   ROUND_FULL_RENDER=<dir> flutter test test/render/round_full_render_test.dart

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
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/crypto_round_strip.dart'
    show CryptoRoundStrip;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show PredictionsVenueFunder;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';
import '../screens/polymarket/crypto_next_round_card_test.dart'
    show CardWorld, roundStart;

final _dir = Platform.environment['ROUND_FULL_RENDER'];

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
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

/// The Crypto › 5 Min page's card as the Dollars page lays it out: on
/// EXPANDED no wider than a wide block, on the pane's left; on a phone the
/// width less the page's gutters.
class _CardPage extends StatelessWidget {
  const _CardPage();

  @override
  Widget build(BuildContext context) {
    final card = CryptoPredictBanner(
      config: kCryptoPredictAssets.first,
      roundMinutes: 5,
      chartHeight: CryptoPredictBanner.kPageChartHeight,
      opensRoundPageWide: true,
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: KuteLayout.isExpanded(context)
                      ? kPolyWideBlockMax
                      : double.infinity),
              child: card,
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

Future<void> _pump(WidgetTester tester, CardWorld world,
    {required Size size, required bool dark}) async {
  await _fonts(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polyWatchlistProvider.overrideWith(_NoStars.new),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      polymarketActivePositionsProvider.overrideWithValue(const []),
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
        home: const _CardPage(),
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  RuntimeCapabilitiesService? policy;
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    kuteShellMounted.value = true;
    OpenOnce.reset();
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
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

  Future<CardWorld> allow(WidgetTester tester) async {
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
    return world;
  }

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 31));
    policy?.dispose();
    policy = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  }

  final title = find.byKey(const ValueKey('crypto-round-window'));

  /// The slip on screen, wherever it is.
  BetSlipSheet? slip(WidgetTester tester) {
    final f = find.byType(BetSlipSheet);
    return f.evaluate().isEmpty ? null : tester.widget<BetSlipSheet>(f.last);
  }

  const shots = [
    ('1440x900', Size(1440, 900)),
    ('1180x820', Size(1180, 820)),
    ('1920x1080', Size(1920, 1080)),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: card 430x932 $mode', skip: _dir == null,
        (tester) async {
      final world = await allow(tester);
      await _pump(tester, world, size: const Size(430, 932), dark: dark);
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'card_430x932_$mode', const Size(430, 932));
      await release(tester);
    });
    for (final (name, size) in shots) {
      testWidgets('render: card and its page $name $mode', skip: _dir == null,
          (tester) async {
        final world = await allow(tester);
        await _pump(tester, world, size: size, dark: dark);
        await _shoot(tester, 'card_${name}_$mode', size);
        await tester.tap(title);
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_${name}_$mode', size);
        await release(tester);
      });
      testWidgets('render: Down opens the page on Down $name $mode',
          skip: _dir == null, (tester) async {
        final world = await allow(tester);
        await _pump(tester, world, size: size, dark: dark);
        await tester.tap(find.byKey(const ValueKey('crypto-round-down')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'page_down_${name}_$mode', size);
        await release(tester);
      });
    }
  }

  // ── Behaviour (always run) ──────────────────────────────────────────

  testWidgets(
      'EXPANDED: a click on the card opens the round\'s page, the slip as '
      'the side panel on Up', (tester) async {
    final world = await allow(tester);
    await _pump(tester, world, size: const Size(1440, 900), dark: false);
    expect(find.byType(FiveMinMarketDetailSheet), findsNothing);
    await tester.tap(title);
    await _settle(tester);
    expect(find.byType(FiveMinMarketDetailSheet), findsOneWidget);
    final panel =
        tester.getRect(find.byKey(const ValueKey('bet-slip-in-place')));
    expect(panel.right, 1440);
    expect(panel.top, 0);
    expect(panel.bottom, 900);
    expect(slip(tester)!.initialOutcomeIndex, 0);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'EXPANDED: Down opens the round\'s page with the slip on Down, no '
      'centred slip', (tester) async {
    final world = await allow(tester);
    await _pump(tester, world, size: const Size(1440, 900), dark: false);
    await tester.tap(find.byKey(const ValueKey('crypto-round-down')));
    await _settle(tester);
    expect(find.byType(FiveMinMarketDetailSheet), findsOneWidget);
    expect(find.byType(BetSlipSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('bet-slip-in-place')), findsOneWidget);
    expect(slip(tester)!.initialOutcomeIndex, 1);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'EXPANDED: a round pill picks the round, no page', (tester) async {
    final world = await allow(tester);
    await _pump(tester, world, size: const Size(1440, 900), dark: false);
    await tester.tap(find.byKey(CryptoRoundStrip.pillKey(
        roundStart.millisecondsSinceEpoch ~/ 1000 + 300)));
    await _settle(tester);
    expect(find.byType(FiveMinMarketDetailSheet), findsNothing);
    await release(tester);
  });

  for (final size in const [Size(430, 932), Size(820, 1180)]) {
    testWidgets(
        '${size.width.toInt()} wide: the card opens no page; Up opens the '
        'slip as before', (tester) async {
      final world = await allow(tester);
      await _pump(tester, world, size: size, dark: false);
      expect(find.byKey(const ValueKey('crypto-round-open-page')),
          findsNothing);
      await tester.tap(title);
      await _settle(tester);
      expect(find.byType(FiveMinMarketDetailSheet), findsNothing);
      await tester.tap(find.byKey(const ValueKey('crypto-round-up')));
      await _settle(tester);
      expect(find.byType(FiveMinMarketDetailSheet), findsNothing);
      expect(slip(tester)!.initialOutcomeIndex, 0);
      expect(find.byKey(const ValueKey('bet-slip-in-place')), findsNothing);
      await release(tester);
    });
  }
}
