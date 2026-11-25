// A look by eye at the option cards under a chart (kute_action_cards.dart),
// light and dark, written only when asked: OPTION_CARDS_RENDER=<dir>.
// The Yes/No market page holds the lone "Rules and resolution" card, one
// compact full-width row (founder, 7 November 2026, the big card with the
// rules' first lines: "way too much"); the gallery shows the grid with the
// cards each screen builds: a position's lone action, the Investing
// market's two, a cross position's three, an isolated position's four, a
// settled prediction's three (Closing conditions a full-width row under
// two squares) and five. One render per run, so:
//   for v in 'market light' 'market dark' 'gallery light' 'gallery dark'; do
//     OPTION_CARDS_RENDER=<dir> flutter test \
//       test/render/option_cards_render_test.dart --plain-name "$v"; done

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

final _dir = Platform.environment['OPTION_CARDS_RENDER'];

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

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: true);
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

const _rules = 'This market will resolve to "Yes" if the President of the '
    'United States, or an official US government agency, publicly confirms '
    'the existence of extraterrestrial life or technology by December 31, '
    '2026, 11:59 PM ET. Otherwise, this market will resolve to "No".\n\n'
    'The resolution source will be official statements from the US '
    'government.';

/// The founder's screenshot: one Yes/No market.
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
    PolymarketOutcome(name: 'Yes', price: 0.06, tokenId: 'y'),
    PolymarketOutcome(name: 'No', price: 0.94, tokenId: 'n'),
  ],
);

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
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

/// One labelled grid of the gallery.
Widget _section(
        BuildContext context, String label, List<KuteActionCard> cards) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          KuteActionCardGrid(cards: cards),
        ],
      ),
    );

KuteActionCard _o(IconData icon, String title, String sub) =>
    KuteActionCard.option(
        icon: icon, title: title, subtitle: sub, onTap: () {});

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('render: option cards, market $mode', skip: _dir == null,
        (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          livePriceProvider.overrideWith(_Prices.new),
          sportsLiveProvider.overrideWith(_NoGames.new),
          polyGameTimelineProvider.overrideWith(_NoTimeline.new),
          polyGameLinesProvider
              .overrideWith((ref, slug) => Completer<PolyGameLines>().future),
          polymarketActivePositionsProvider.overrideWithValue(const []),
          polymarketClaimablePositionsProvider.overrideWithValue(const []),
          aiEnabledProvider.overrideWith((ref) async => false),
          polyWatchlistProvider.overrideWith(_NoStars.new),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
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
      AppRouter.rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'market'),
          builder: (_) => MarketDetailSheet(event: _aliens)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -6000));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(kPolyRulesCardKey), findsOneWidget);
      await _shoot(tester, 'option_cards_market_$mode');
      expect(tester.takeException(), isNull);
    });

    testWidgets('render: option cards, gallery $mode', skip: _dir == null,
        (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              RepaintBoundary(key: const ValueKey('shot'), child: child),
          home: Scaffold(
            body: Builder(builder: (context) {
              final l10n = context.l10n;
              final chart = _o(Icons.candlestick_chart_rounded,
                  l10n.hlAdvancedChart, l10n.optionAdvancedChartSub);
              final details = _o(Icons.receipt_long_rounded, l10n.details,
                  l10n.optionPositionDetailsSub);
              final protect = _o(Icons.shield_outlined, l10n.positionProtectIt,
                  l10n.hlStopLoss);
              final margin = _o(
                  Icons.add_rounded, l10n.hlMarginAdd, l10n.optionAddMarginSub);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  _section(context, 'Position action: 1', [protect]),
                  _section(context, 'Investing market: 2', [
                    chart,
                    _o(
                        Icons.info_outline_rounded,
                        l10n.investingAboutMarket('Bitcoin'),
                        l10n.optionAboutMarketSub),
                  ]),
                  _section(
                      context, 'Cross position: 3', [protect, chart, details]),
                  _section(context, 'Isolated position: 4',
                      [margin, protect, chart, details]),
                  _section(context, 'Settled prediction: 3', [
                    _o(Icons.show_chart_rounded, l10n.salViewMarket,
                        l10n.optionViewMarketSub),
                    _o(Icons.receipt_long_rounded, l10n.details,
                        l10n.optionPredictionDetailsSub),
                    _o(Icons.gavel_rounded, l10n.betClosingConditions,
                        l10n.optionHowItResolves),
                  ]),
                  _section(context, 'Five', [
                    margin,
                    protect,
                    chart,
                    details,
                    _o(Icons.gavel_rounded, l10n.polyRulesAndResolution,
                        'Ends Jan 1, 2027'),
                  ]),
                ],
              );
            }),
          ),
        ),
      ));
      await tester.pump();
      await _shoot(tester, 'option_cards_gallery_$mode');
      expect(tester.takeException(), isNull);
    });
  }
}
