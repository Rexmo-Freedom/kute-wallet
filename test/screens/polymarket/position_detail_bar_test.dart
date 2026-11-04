// The Predictions position screen's action is the floating bar's primary
// button (founder, 2 November 2026: "Close position should be a floating
// pill like the others", for Predictions and Investing alike;
// position_detail_sheet.dart, kute_bar_context.dart): Sell in the red its
// pinned button had, Clear (a lost side) in the app's primary look and
// thinking while the redeem runs; a won position has none. No pinned panel
// is left at the foot, and the body scrolls clear of the bar. Sell and
// Clear carry the round Sal button at their right (founder, 4 November
// 2026: Send to a friend floats). A won position in profit is "Brag about
// it" (its won card; founder, 4 November 2026: past wins brag too) with
// the round Sal button; a win with no profit is the Sal pill, "Send to a
// friend".
//
// Light and dark PNGs of the open position with its bar:
// flutter test --dart-define=POLY_POSITION_SHOT_OUT=<dir>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarPrimaryStyle, kuteBarScrollClearance;
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/shell_bar_harness.dart';

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

/// The redeem, held by the test.
class _Trading extends PolymarketTradingNotifier {
  final redeemed = <String>[];
  Completer<double?>? hold;

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();

  @override
  Future<void> refresh() async {}

  @override
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    redeemed.add(conditionId);
    final pending = hold;
    if (pending != null) return pending.future;
    return 0;
  }
}

/// No socket in a test: the page's addTokens subscribes nothing.
class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void removeTokens(List<String> tokenIds) {}
}

/// 20 No shares bought at 19¢, No now at 66%.
const _open = PolymarketPosition(
  marketId: 'c-cf',
  marketQuestion: 'Ukraine x Russia ceasefire in 2026?',
  outcome: 'No',
  size: 20,
  avgPrice: 0.19,
  currentPrice: 0.66,
  pnl: 9.4,
  pnlPercent: 247,
  isResolved: false,
  tokenId: 'cf-no',
  eventSlug: 'ceasefire-2026',
);

/// The same bet, settled the other way.
const _lost = PolymarketPosition(
  marketId: 'c-cf',
  marketQuestion: 'Ukraine x Russia ceasefire in 2026?',
  outcome: 'No',
  size: 20,
  avgPrice: 0.19,
  currentPrice: 0,
  pnl: -3.8,
  pnlPercent: -100,
  isResolved: true,
  won: false,
  tokenId: 'cf-no',
  eventSlug: 'ceasefire-2026',
);

const _won = PolymarketPosition(
  marketId: 'c-cf',
  marketQuestion: 'Ukraine x Russia ceasefire in 2026?',
  outcome: 'No',
  size: 20,
  avgPrice: 0.19,
  currentPrice: 1,
  pnl: 16.2,
  pnlPercent: 426,
  isResolved: true,
  won: true,
  tokenId: 'cf-no',
  eventSlug: 'ceasefire-2026',
);

/// A win bought at a dollar a share: paid out what it cost, no profit.
const _wonEven = PolymarketPosition(
  marketId: 'c-cf',
  marketQuestion: 'Ukraine x Russia ceasefire in 2026?',
  outcome: 'No',
  size: 20,
  avgPrice: 1,
  currentPrice: 1,
  pnl: 0,
  pnlPercent: 0,
  isResolved: true,
  won: true,
  tokenId: 'cf-no',
  eventSlug: 'ceasefire-2026',
);

Future<void> _loadAssets(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      SalSpriteCache.debugSetManifest(jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>);
      for (final clip in ['idle', 'curious', 'think', 'search']) {
        await SalSpriteCache.clip(clip, 3);
      }
    });

/// The position screen pushed over a home page, under the shell bar, as
/// in the app (Sell pops the screen through go_router).
Future<_Trading> _pump(WidgetTester tester, PolymarketPosition position,
    {bool dark = false, double height = 1200, double ratio = 1}) async {
  installShellBar();
  tester.view.physicalSize = Size(390 * ratio, height * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final trading = _Trading();
  final router = GoRouter(observers: shellBarObservers(), routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PositionDetailSheet(position: position))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(() => trading),
      polymarketEventDetailsProvider('ceasefire-2026')
          .overrideWith((ref) async => null),
      polyPositionJourneyProvider.overrideWith((ref, key) async => null),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('shot'),
            child: shellBarBuilder(context, child)),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await pumpBar(tester);
  await tester.pump(const Duration(milliseconds: 600));
  return trading;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteConfirmation.debugFeedbackOverride = () async {};
  });
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  testWidgets('an open position: Sell is the bar\'s red pill, no pinned '
      'panel; a tap opens the same sell slip', (tester) async {
    await _pump(tester, _open);
    // No button of the page's own.
    expect(find.byType(AppButton), findsNothing);
    expect(barIsPrimary(tester), isTrue);
    expect(barIsUp(tester), isTrue);
    final ctx = barPrimaryContext(tester);
    expect(ctx.label, 'Sell');
    expect(ctx.enabled, isTrue);
    expect(ctx.busy, isFalse);
    expect(ctx.style, same(KuteBarPrimaryStyle.destructive));
    expect(ctx.style!.fill, AppColors.marketDown);
    expect(barPrimaryInk(tester), const Color(0xFFFFFFFF));
    // The round Sal button at Sell's right, both taking their taps.
    final share = find.byKey(const ValueKey('kute-bar-share'));
    expect(share, findsOneWidget);
    expect(tester.getRect(share).left,
        greaterThan(tester.getRect(findBarPrimary()).right));
    expect(ctx.share!.barContext.market, isTrue);
    for (final f in [findBarPrimary(), share]) {
      final hit = tester.hitTestOnBinding(tester.getCenter(f));
      expect(hit.path.any((e) => e.target == tester.renderObject(f)), isTrue);
    }
    expect(find.byKey(const ValueKey('position-share-card')), findsNothing);
    // The body scrolls clear of the floating bar.
    final scroll = tester.widget<SingleChildScrollView>(find
        .ancestor(
            of: find.byKey(const ValueKey('poly-position-details')),
            matching: find.byType(SingleChildScrollView))
        .first);
    expect((scroll.padding! as EdgeInsets).bottom,
        closeTo(kuteBarScrollClearance.h, 0.01));

    await tapBarPrimary(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 600));
    // The screen gives way to the sell slip, as the pinned Sell did.
    expect(find.byType(PositionDetailSheet), findsNothing);
    final sell = tester.widget<SellSheet>(find.byType(SellSheet));
    expect(sell.source, 'position_detail');
    expect(sell.startWithLimit, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost side: Clear is the bar in the app\'s primary look, '
      'thinking while the redeem runs', (tester) async {
    final trading = await _pump(tester, _lost);
    expect(find.byType(AppButton), findsNothing);
    final ctx = barPrimaryContext(tester);
    expect(ctx.label, 'Clear position');
    expect(ctx.style, isNull);
    expect(barPrimaryEnabled(tester), isTrue);
    // Settled: the round Sal button sends the market, never the brag.
    expect(find.byKey(const ValueKey('kute-bar-share')), findsOneWidget);
    expect(ctx.share!.brag, isNull);

    trading.hold = Completer<double?>();
    await tapBarPrimary(tester, settle: false);
    await pumpBar(tester);
    expect(trading.redeemed, ['c-cf']);
    expect(barPrimaryBusy(tester), isTrue);
    expect(barPrimaryText('Clear position'), findsOneWidget);
    // Busy takes no second tap.
    await tapBarPrimary(tester, settle: false);
    await pumpBar(tester);
    expect(trading.redeemed, ['c-cf']);

    // It lands on the same cleared confirmation as before (position_claim
    // .dart, unchanged); one redeem in all.
    trading.hold!.complete(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(trading.redeemed, ['c-cf']);
    expect(tester.takeException(), isNull);
    // The cleared confirmation's own timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'a won position in profit has no Sell: the bar is "Brag about it", '
      'the round Sal button beside it', (tester) async {
    await _pump(tester, _won);
    expect(find.byType(AppButton), findsNothing);
    expect(barIsUp(tester), isTrue);
    final ctx = barPrimaryContext(tester);
    expect(ctx.label, 'Brag about it');
    expect(ctx.style, isNull);
    expect(barPrimaryEnabled(tester), isTrue);
    // The button is the brag; the round Sal button is the page's Sal
    // sheet, never a second brag.
    expect(find.byKey(const ValueKey('kute-bar-share')), findsOneWidget);
    expect(ctx.share!.brag, isNull);
    expect(find.byKey(const ValueKey('kute-bar-pill')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a won position with no profit has no action: the bar is not a '
      'button there but the Sal pill, "Send to a friend"', (tester) async {
    await _pump(tester, _wonEven);
    expect(barIsPrimary(tester), isFalse);
    expect(barIsUp(tester), isTrue);
    expect(find.byType(AppButton), findsNothing);
    final pill = find.byKey(const ValueKey('kute-bar-pill'));
    expect(pill, findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('Send to a friend')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  const shotOut = String.fromEnvironment('POLY_POSITION_SHOT_OUT');
  for (final dark in [false, true]) {
    final name = 'poly_position_open_${dark ? 'dark' : 'light'}';
    testWidgets('render: $name', (tester) async {
      await _loadAssets(tester);
      await _pump(tester, _open, dark: dark, height: 844, ratio: 3);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      if (shotOut.isEmpty) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(shotOut).createSync(recursive: true);
        File('$shotOut/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
      // The screen's and the bar's own timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
