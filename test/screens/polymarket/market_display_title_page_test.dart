// The market page's title (market_display_title.dart). Founder, 7
// November 2026: "Look here does not make sense, is the yes or no
// correct?" under "Will Russia invade a NATO country by...?" (the event's
// title over its one open market), then a page titled only "December 31,
// 2026" (one deadline opened as its own page). The page, and the card its
// Send to a friend shares, read the market's whole question.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

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

const _russia = 'Will Russia invade a NATO country by...?';
const _qJun = 'Will Russia invade a NATO country by June 30, 2026?';
const _qDec = 'Will Russia invade a NATO country by December 31, 2026?';

Map<String, dynamic> _market(String id, String question, String item,
        {required bool closed, required List<String> prices}) =>
    {
      'id': id,
      'question': question,
      'groupItemTitle': item,
      'conditionId': '0x$id',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': jsonEncode(prices),
      'clobTokenIds': '["$id-yes", "$id-no"]',
      'bestBid': closed ? 0 : double.parse(prices.first) - 0.001,
      'bestAsk': closed ? 0 : double.parse(prices.first) + 0.001,
      'lastTradePrice': closed ? 0 : double.parse(prices.first),
      'active': true,
      'closed': closed,
      'acceptingOrders': !closed,
    };

PolymarketEvent _event(List<Map<String, dynamic>> markets) =>
    PolymarketModel().parseEventsRaw([
      {
        'id': '23784',
        'slug': 'will-russia-invade-a-nato-country-in-2025',
        'title': _russia,
        'endDate': '2027-01-01T00:00:00Z',
        'active': true,
        'closed': false,
        'tags': [
          {'slug': 'politics'}
        ],
        'markets': markets,
      }
    ]).single;

/// Gamma today: three deadlines settled, December 31, 2026 open.
final _oneOpenLeft = _event([
  _market('m2025', 'Will Russia invade a NATO country in 2025?',
      'December 31, 2025',
      closed: true, prices: ['0', '1']),
  _market('mjun', _qJun, 'June 30, 2026', closed: true, prices: ['0', '1']),
  _market('msep', 'Will Russia invade a NATO country by September 30, 2026?',
      'September 30, 2026',
      closed: true, prices: ['0', '1']),
  _market('mdec', _qDec, 'December 31, 2026',
      closed: false, prices: ['0.0205', '0.9795']),
]);

/// Two deadlines still open: an event with a list.
final _twoOpen = _event([
  _market('mjun', _qJun, 'June 30, 2026',
      closed: false, prices: ['0.12', '0.88']),
  _market('mdec', _qDec, 'December 31, 2026',
      closed: false, prices: ['0.0205', '0.9795']),
]);

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, PolymarketEvent event) async {
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
      aiEnabledProvider.overrideWith((ref) async => true),
      polyWatchlistProvider.overrideWith(_NoStars.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme:
            buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: AppRouter.rootNavigatorKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) =>
            Stack(children: [child!, const KuteShellBar()]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pump();
  AppRouter.rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'market'),
      builder: (_) => MarketDetailSheet(event: event)));
  await _settle(tester);
}

/// The header's title on the page on top.
String _title(WidgetTester tester) => tester
    .widget<Text>(find
        .descendant(
            of: find.byKey(const ValueKey('poly-detail-title')),
            matching: find.byType(Text))
        .last)
    .data!;

/// The title Send to a friend shares: the bar's own context, or the one
/// its trade row's round Sal button carries.
String _sharedTitle(WidgetTester tester) {
  final top = kuteBarTop(ProviderScope.containerOf(
          tester.element(find.byType(MarketDetailSheet).last))
      .read(kuteBarContextProvider))!;
  final bar =
      (top.isTrade ? top.share!.barContext! : top) as KuteMarketBarContext;
  return bar.preview.title;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  testWidgets(
      'one open deadline left: the page reads its whole question, never '
      '"by...?"', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _oneOpenLeft);
      expect(_title(tester), _qDec);
      expect(_sharedTitle(tester), _qDec);
      expect(find.textContaining('by...'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets(
      'several open: the event without its blank; a deadline opened as its '
      'own page reads its question, never the bare date', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _twoOpen);
      expect(_title(tester), 'Will Russia invade a NATO country?');
      expect(find.textContaining('by...'), findsNothing);

      await tester.tap(find.text('December 31, 2026').first);
      await _settle(tester);
      expect(find.byType(MarketDetailSheet), findsNWidgets(2));
      expect(_title(tester), _qDec);
      expect(_sharedTitle(tester), _qDec);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
