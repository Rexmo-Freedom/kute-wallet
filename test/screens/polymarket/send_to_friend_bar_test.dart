// "Send to a friend" on every Polymarket market, event and game sheet is
// the bar at the foot (founder, 2 November 2026: "share with a friend,
// always make it on the bottom like we did for predictions"): the dark
// primary button every pinned action is, "Send to a friend" on one line,
// the same Sal sheet on a tap, never a pill in the title row or beside the
// big number, whatever the title's length or the screen's width. The page's
// last rows scroll clear of it; on a Yes/No market it rides above the Yes /
// No pair.
//
// On demand, light renders:
//   flutter test test/screens/polymarket/send_to_friend_bar_test.dart \
//     --dart-define=SEND_BAR_OUT=<dir>

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
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show PolyRulesRow;
import 'package:kute/screens/polymarket/components/poly_watch_star.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCloseButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('SEND_BAR_OUT');

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

/// A Yes/No market titled [title].
PolymarketEvent _yesNo(String title) => PolymarketModel().parseEventsRaw([
      {
        'id': '2',
        'slug': 'yes-no-1',
        'title': title,
        'markets': [
          _market('yn', 'binary', null, title, ['Yes', 'No'], ['0.64', '0.36']),
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

final _shareButton = find.byKey(const ValueKey('kute-sal-header-button'));

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

/// The app's shape: the shell bar over the root navigator, the game sheet
/// pushed over a blank tab.
Future<void> _pump(WidgetTester tester, PolymarketEvent event,
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
      builder: (_) => MarketDetailSheet(event: event)));
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

/// The bar is the dark "Send to a friend" button, opening the market's Sal
/// sheet; no pill anywhere on the page; the title has the whole row.
Future<Finder> _expectSendBar(WidgetTester tester) async {
  final l10n = AppLocalizations.of(tester.element(_header));
  expect(_shareButton, findsNothing);
  final top = _top(tester)!;
  expect(top.inHeader, isFalse);
  // The primary button, as every pinned action: one line, the same words
  // if it were ever off.
  expect(top.isPrimary, isTrue);
  expect(top.actionable, isTrue);
  expect(top.primaryLabel, l10n.shareHeaderLabel);
  expect(top.disabledLabel, l10n.shareHeaderLabel);
  expect(top.sublabel, isNull);
  expect(top.source, 'predictions');
  final slide = find.byKey(const ValueKey('kute-shell-bar-slide'));
  expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
  // Dark: the app's primary fill with white words, not the white two-line
  // Sal pill.
  final button = find.byKey(const ValueKey('kute-bar-primary-button'));
  expect(button, findsOneWidget);
  expect(find.byKey(const ValueKey('kute-bar-pill')), findsNothing);
  final fill =
      tester.widget<AnimatedContainer>(button).decoration! as BoxDecoration;
  expect(fill.color, AppColorsExtension.light().textPrimary);
  final words =
      find.descendant(of: button, matching: find.text(l10n.shareHeaderLabel));
  expect(words, findsOneWidget);
  expect(tester.widget<Text>(words).style?.color, Colors.white);
  expect(find.text(l10n.barShareMarketSub), findsNothing);
  // The title runs to the star: nothing between them.
  final title = find.byKey(const ValueKey('poly-detail-title'));
  final star = find.descendant(of: _header, matching: find.byType(PolyWatchStar));
  expect(tester.getRect(star).left - tester.getRect(title).right,
      lessThan(9 * tester.view.physicalSize.width / 430 + 1));
  return button;
}

/// A tap on [button] opens the Sal sheet with the market's send cards, as
/// the header pill did.
Future<void> _expectOpensSalSheet(WidgetTester tester, Finder button) async {
  final l10n = AppLocalizations.of(tester.element(_header));
  await tester.tap(button);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text(l10n.shareTheMarket), findsWidgets);
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
    (_long, 390.0),
    (_long, 430.0),
    (_medium, 390.0),
  ]) {
    testWidgets(
        'a game at ${width.toInt()} wide, "${game.$1}": no pill in the '
        'header, the title whole, the bar is the dark "Send to a friend" '
        'button opening the market\'s Sal sheet, and the last rows scroll '
        'clear of it', (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _game(game.$1, game.$2, game.$3), width: width);
        final button = await _expectSendBar(tester);
        // A game sheet has nothing pinned at its foot.
        expect(_top(tester)!.actionRowHeight, 0);
        if (game == _short) {
          // A short title keeps its own size: nothing took its room.
          final titleText = find.descendant(
              of: find.byKey(const ValueKey('poly-detail-title')),
              matching: find.byType(Text));
          expect(tester.widget<Text>(titleText).style!.fontSize,
              closeTo(18 * width / 430, 0.01));
          expect(tester.renderObject<RenderParagraph>(titleText)
              .didExceedMaxLines, isFalse);
        }
        await _shoot(tester,
            'game_bar_${width.toInt()}_${game.$2.split(' ').first}');
        // Scrolled to the very end, Rules sits above the floating bar.
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -6000));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final rules = find.byType(PolyRulesRow);
        expect(tester.getRect(rules).bottom,
            lessThan(tester.getRect(button).top));
        await _expectOpensSalSheet(tester, button);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  testWidgets(
      'a Yes/No market: no pill beside the chance, the bar is the dark "Send '
      'to a friend" button riding above the Yes / No pair', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _yesNo('Will Bitcoin close above \$120k on Friday?'),
          width: 390);
      final button = await _expectSendBar(tester);
      expect(_top(tester)!.actionRowHeight, greaterThan(0));
      // Lifted clear of the pinned pair (the blurred band with its
      // hairline at the top).
      final yes = find.textContaining(RegExp('^Yes'));
      expect(yes, findsWidgets);
      expect(tester.getRect(button).bottom,
          lessThan(tester.getRect(yes.last).top));
      // The band under the lifted bar lets taps through to the pair.
      final hit = tester.hitTestOnBinding(tester.getCenter(yes.last));
      final yesBox = tester.renderObject(yes.last);
      expect(hit.path.any((e) => e.target == yesBox), isTrue);
      await _shoot(tester, 'yes_no_bar_390');
      await _expectOpensSalSheet(tester, button);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
