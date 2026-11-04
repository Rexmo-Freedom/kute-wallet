// A game sheet's Send to a friend (founder, 4 November 2026: "I do not
// like the Send to a friend on the top right in Hyperliquid and
// Predictions. It must be a floating button"). No pill in the title row,
// whatever the title's length: the title has the row up to the star, and
// the bar at the foot is the floating Sal pill, "Send to a friend", which
// opens the market's Sal sheet (a game is an event: Send the market
// alone) and which the page's last rows scroll clear of. A game has no
// Yes / No pair, so no trade row.
//
// On demand, light renders:
//   flutter test test/screens/polymarket/game_sheet_share_bar_test.dart \
//     --dart-define=GAME_HEADER_OUT=<dir>

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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/poly_watch_star.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show kPolyRulesCardKey;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCloseButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('GAME_HEADER_OUT');

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

Map<String, dynamic> _market(String id, String type, double? line, String q,
        List<String> sides, List<String> prices) =>
    {
      'id': id,
      'question': q,
      'sportsMarketType': type,
      'line': line,
      'outcomes': '["${sides[0]}", "${sides[1]}"]',
      'outcomePrices': '["${prices[0]}", "${prices[1]}"]',
      'clobTokenIds': '["${id}a", "${id}b"]',
      'conditionId': '0x$id',
    };

/// A game between [a] and [b] titled [title].
PolymarketEvent _game(String title, String a, String b) =>
    PolymarketModel().parseEventsRaw([
      {
        'id': '1',
        'slug': 'game-1',
        'title': title,
        'gameId': 19502,
        'tags': [
          {'slug': 'sports'}
        ],
        'teams': [
          {'name': a, 'abbreviation': 'aaa', 'ordering': 'away'},
          {'name': b, 'abbreviation': 'bbb', 'ordering': 'home'},
        ],
        'markets': [
          _market('ml', 'moneyline', null, title, [a, b], ['0.62', '0.38']),
          _market('to', 'totals', 2.5, '$a vs. $b: O/U 2.5',
              ['Over', 'Under'], ['0.55', '0.45']),
          for (var i = 0; i < 12; i++)
            _market('p$i', 'player_props', null, 'Player $i: first kill?',
                ['Yes', 'No'], ['0.5', '0.5']),
        ],
      }
    ]).single;

const _short = ('PSG vs OM', 'PSG', 'OM');
const _medium = ('Colts vs. Commanders', 'Colts', 'Commanders');
const _long = (
  'Counter-Strike: Natus Vincere vs Team Falcons (BO3) - ESL Pro League '
      'Season 22 Playoffs',
  'Natus Vincere',
  'Team Falcons',
);

final _pill = find.byKey(const ValueKey('kute-bar-pill'));

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

/// The app's shape: the shell bar over the root navigator, the game sheet
/// pushed over a blank tab.
Future<void> _pump(WidgetTester tester, (String, String, String) game,
    {double width = 390}) async {
  // A tablet keeps a phone's proportions (the sheet's .h and .sp scale
  // with the width there).
  tester.view.physicalSize = Size(width, width > 430 ? width * 932 / 430 : 844);
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
      aiEnabledProvider.overrideWith((ref) async => true),
      polyWatchlistProvider.overrideWith(_NoStars.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme().copyWith(
            splashFactory: NoSplash.splashFactory),
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
      builder: (_) => MarketDetailSheet(event: _game(game.$1, game.$2, game.$3))));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

KuteBarContext? _top(WidgetTester tester) => kuteBarTop(ProviderScope
        .containerOf(tester.element(find.byType(MarketDetailSheet)))
    .read(kuteBarContextProvider));

Finder get _header => find
    .ancestor(of: find.byType(KuteCloseButton), matching: find.byType(Row))
    .first;

Future<void> _shoot(WidgetTester tester, String name) async {
  if (_out.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  for (final (game, width) in [
    (_short, 430.0),
    (_medium, 744.0),
    (_medium, 390.0),
    (_long, 390.0),
    (_long, 430.0),
  ]) {
    testWidgets(
        'at ${width.toInt()} wide "${game.$1}": nothing to share in the '
        'title row, the title whole up to the star; the bar is the floating '
        'Sal pill "Send to a friend", opening the market\'s Sal sheet, and '
        'the last rows scroll clear of it', (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, game, width: width);
        final l10n = AppLocalizations.of(tester.element(_header));
        expect(find.byKey(const ValueKey('kute-sal-header-button')),
            findsNothing);
        for (final words in [l10n.shareHeaderLabel, l10n.share]) {
          expect(find.descendant(of: _header, matching: find.text(words)),
              findsNothing);
        }
        final title = find.byKey(const ValueKey('poly-detail-title'));
        final titleText =
            find.descendant(of: title, matching: find.byType(Text));
        expect(tester.renderObject<RenderParagraph>(titleText)
            .didExceedMaxLines, isFalse);
        expect(tester.widget<Text>(titleText).data, game.$1);
        // The title runs to the star: nothing between them.
        final star = find.descendant(
            of: _header, matching: find.byType(PolyWatchStar));
        expect(tester.getRect(star).left - tester.getRect(title).right,
            lessThanOrEqualTo(8 * width / 430 + 0.5));
        // The bar: the page's market context as the floating Sal pill.
        final top = _top(tester)!;
        expect(top.inHeader, isFalse);
        expect(top.isPrimary, isFalse);
        expect(top.isTrade, isFalse);
        expect(top.label, l10n.barShareWithFriends);
        expect(_pill, findsOneWidget);
        expect(
            find.descendant(
                of: _pill, matching: find.text(l10n.barShareWithFriends)),
            findsOneWidget);
        expect(find.byKey(const ValueKey('kute-bar-primary-button')),
            findsNothing);
        final slide = find.byKey(const ValueKey('kute-shell-bar-slide'));
        expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
        await _shoot(tester,
            'game_share_bar_${width.toInt()}_${game.$2.split(' ').first}');
        expect(tester.takeException(), isNull);
        // Scrolled to the very end, Rules sits above the floating pill.
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -6000));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.widget<KuteSalPill>(find.byType(KuteSalPill)).collapsed,
            isFalse,
            reason: 'the scroll has been still: the full pill again');
        final rules = find.byKey(kPolyRulesCardKey);
        expect(tester.getRect(rules).bottom,
            lessThan(tester.getRect(_pill).top));
        expect(tester.takeException(), isNull);
        // A tap opens the Sal sheet with the market's send card: a game is
        // an event, so the market alone (founder, 2 November 2026).
        await tester.tap(_pill);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text(l10n.shareTheMarket), findsWidgets);
        expect(find.text(l10n.sendThisPrediction), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }
}
