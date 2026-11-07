// What a market page's Send to a friend shares, and what its bar says in
// send mode (founder, 7 November 2026).
//
//   * "sharing here should be just the yes or no. only here is the full
//     market": an event of several markets ("What price will Bitcoin hit
//     November 2-8?", ↑ 76,000 / ↓ 74,000 / ↑ 78,000) shares the whole
//     event, its card the event's leader and chart; one of its markets
//     opened as its own Yes / No page (the ↑ 76,000 row) shares THAT market:
//     its card the market's question and its Yes chance, its link naming
//     the candidate. A plain Yes / No market is unchanged.
//   * In SEND MODE (opened from Send) nothing offers the look-only link:
//     the event's bar reads "Pick an outcome · You're buying it for Ana"
//     ("... for your friend" without a contact) and brings the outcomes
//     into view; a Yes / No page's trade row reads "Send Yes" / "Send No"
//     in its green and red, with no round share button. The chip says who
//     the pick is for, in the primary ink.

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
import 'package:kute/screens/search/unified_search_screen.dart'
    show UnifiedSearchSurface;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/tracking_service.dart';
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

const _slug = 'what-price-will-bitcoin-hit-november-2-8';
const _title = 'What price will Bitcoin hit November 2-8?';
const _q76 = r'Will Bitcoin reach $76,000 November 2-8?';
const _q74 = r'Will Bitcoin dip to $74,000 November 2-8?';
const _q78 = r'Will Bitcoin reach $78,000 November 2-8?';

Map<String, dynamic> _market(
        String id, String question, String item, double yes) =>
    {
      'id': id,
      'question': question,
      'groupItemTitle': item,
      'conditionId': '0x$id',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': jsonEncode(['$yes', (1 - yes).toStringAsFixed(3)]),
      'clobTokenIds': '["$id-yes", "$id-no"]',
      'bestBid': yes - 0.001,
      'bestAsk': yes + 0.001,
      'lastTradePrice': yes,
      'active': true,
      'closed': false,
      'acceptingOrders': true,
    };

/// The founder's screenshot: an event of several open price markets.
final _btc = PolymarketModel().parseEventsRaw([
  {
    'id': '55001',
    'slug': _slug,
    'title': _title,
    'endDate': '2027-11-09T00:00:00Z',
    'active': true,
    'closed': false,
    'tags': [
      {'slug': 'crypto'}
    ],
    'markets': [
      _market('m76', _q76, '↑ 76,000', 0.94),
      _market('m74', _q74, '↓ 74,000', 0.153),
      _market('m78', _q78, '↑ 78,000', 0.42),
    ],
  }
]).single;

/// A plain Yes / No market.
const _plain = PolymarketEvent(
  id: 'p1',
  slug: 'will-lula-win',
  title: 'Will Lula win the 2026 election?',
  volume: 1000,
  liquidity: 500,
  category: 'politics',
  conditionId: 'c-p1',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.41, tokenId: 'p-yes'),
    PolymarketOutcome(name: 'No', price: 0.59, tokenId: 'p-no'),
  ],
);

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

Future<void> _pump(WidgetTester tester, PolymarketEvent event,
    {SendPickSession? sendPick, double height = 844}) async {
  tester.view.physicalSize = Size(390, height);
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
      // The share card reads the event by its slug: the whole event, as
      // Gamma serves it, whichever page shares.
      polymarketEventDetailsProvider
          .overrideWith((ref, slug) async => slug == _slug ? _btc : _plain),
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
      builder: (_) => MarketDetailSheet(event: event, sendPick: sendPick)));
  await _settle(tester);
}

final _l10n = lookupAppLocalizations(const Locale('en'));
final Finder _share = find.byKey(const ValueKey('kute-bar-share'));
final Finder _pill = find.byKey(const ValueKey('kute-bar-pill'));

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MarketDetailSheet).last));

/// What the bar reads on the page on top.
KuteBarContext _top(WidgetTester tester) =>
    kuteBarTop(_container(tester).read(kuteBarContextProvider))!;

/// The header's title on the page on top.
String _pageTitle(WidgetTester tester) => tester
    .widget<Text>(find
        .descendant(
            of: find.byKey(const ValueKey('poly-detail-title')),
            matching: find.byType(Text))
        .last)
    .data!;

/// Taps the page's Send to a friend (the round button, else the pill) and
/// hands back the market send sheet it opened.
Future<ShareMarketSheet> _send(WidgetTester tester) async {
  await tester.tap(_share.evaluate().isNotEmpty ? _share : _pill);
  await _settle(tester);
  expect(find.byType(ShareMarketSheet), findsOneWidget);
  return tester.widget<ShareMarketSheet>(find.byType(ShareMarketSheet));
}

/// The card [sheet] draws, read from the page's providers.
PredictionCardData _card(WidgetTester tester, ShareMarketSheet sheet) {
  final c = _container(tester);
  return sheet.card(<T>(p) => c.read(p)) as PredictionCardData;
}

Future<void> _done(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

http.Client _offline() => MockClient((_) async => http.Response('{}', 404));

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  group('what Send to a friend shares', () {
    testWidgets(
        'the event page shares the whole event: its title, its leader, its '
        'link to the event alone', (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _btc);
        final sheet = await _send(tester);
        expect(sheet.candidate, isNull);
        expect(sheet.title, _title);
        expect(sheet.marketSlug, _slug);
        expect(sheet.deepLink,
            marketShareLink(venue: kMarketLinkPredictions, slug: _slug));
        expect(Uri.parse(sheet.deepLink).queryParameters, isEmpty);
        final card = _card(tester, sheet);
        expect(card.question, _title);
        expect(card.binary, isFalse);
        expect(card.outcome, '↑ 76,000');
        await _done(tester);
      }, _offline);
    });

    testWidgets(
        'the ↑ 76,000 row opened as its own page shares just that Yes / No '
        'market: its question, its Yes 94%, its link naming the candidate',
        (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _btc);
        await tester.tap(find.text('↑ 76,000').last);
        await _settle(tester);
        expect(find.byType(MarketDetailSheet), findsNWidgets(2));
        expect(_pageTitle(tester), _q76);
        // The round button looks and sits as before.
        expect(_top(tester).isTrade, isTrue);
        expect(_share, findsOneWidget);

        final sheet = await _send(tester);
        expect(sheet.candidate, '↑ 76,000');
        expect(sheet.title, _q76);
        expect(sheet.chance, closeTo(94, 0.01));
        expect(sheet.marketSlug, _slug);
        final link = Uri.parse(sheet.deepLink);
        expect(link.path, '/m/predictions/$_slug');
        expect(link.queryParameters, {'outcome': '↑ 76,000'});

        final card = _card(tester, sheet);
        expect(card.question, _q76);
        expect(card.binary, isTrue);
        expect(card.outcome, 'Yes');
        expect(card.chance, closeTo(94, 0.01));
        expect(card.picked, isFalse);
        expect(card.amount, isNull);
        expect(card.lines, isNull);
        expect(card.charted, isFalse);
        expect(card.opponent, isNull);

        // The share's events never carry the candidate, its question or a
        // title.
        for (final e in events.where((e) => e.$1.startsWith('share_'))) {
          final values = e.$2?.values.map((v) => '$v').join(' ') ?? '';
          expect(values, isNot(contains('76')), reason: e.$1);
          expect(values, isNot(contains('Will Bitcoin')), reason: e.$1);
        }
        await _done(tester);
      }, _offline);
    });

    testWidgets('a plain Yes / No market is unchanged', (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _plain);
        final sheet = await _send(tester);
        expect(sheet.candidate, isNull);
        expect(sheet.deepLink,
            marketShareLink(venue: kMarketLinkPredictions, slug: _plain.slug));
        final card = _card(tester, sheet);
        expect(card.question, _plain.title);
        expect(card.binary, isTrue);
        expect(card.outcome, 'No');
        expect(card.chance, closeTo(59, 0.01));
        await _done(tester);
      }, _offline);
    });
  });

  group('the card from the providers', () {
    final t0 = DateTime.utc(2026, 11, 1);
    List<PolymarketPricePoint> history(List<double> ps) => [
          for (var i = 0; i < ps.length; i++)
            PolymarketPricePoint(
                timestamp: t0.add(Duration(hours: i)), price: ps[i]),
        ];

    Future<ShareCardWatch> watcher() async {
      final histories = {
        'm76-yes': history([0.80, 0.88, 0.93, 0.94]),
        'm78-yes': history([0.30, 0.35, 0.40, 0.42]),
        'm74-yes': history([0.30, 0.20, 0.16, 0.153]),
      };
      final container = ProviderContainer(overrides: [
        polymarketEventDetailsProvider.overrideWith((ref, slug) async => _btc),
        polymarketMarketHistoryProvider.overrideWith(
            (ref, key) async => histories[key.tokenId] ?? const []),
      ]);
      addTearDown(container.dispose);
      container.listen(polymarketEventDetailsProvider(_slug), (_, __) {});
      await container.read(polymarketEventDetailsProvider(_slug).future);
      for (final o in _btc.outcomes) {
        for (final range in const ['1d', '1w', '1m', 'max']) {
          final key = (tokenId: o.tokenId!, interval: range);
          container.listen(polymarketMarketHistoryProvider(key), (_, __) {});
          await container.read(polymarketMarketHistoryProvider(key).future);
        }
      }
      return <T>(ProviderListenable<T> p) => container.read(p);
    }

    test(
        'one market of the event: its question, Yes and its chance, its own '
        'week; never the other outcomes or their chart', () async {
      final watch = await watcher();
      final card = predictionCardFor(watch,
          slug: _slug, title: _q76, chance: 94, candidate: '↑ 76,000');
      expect(card.question, _q76);
      expect(card.outcome, 'Yes');
      expect(card.binary, isTrue);
      expect(card.chance, closeTo(94, 1e-9));
      expect(card.leading, isTrue);
      expect(card.series, [0.80, 0.88, 0.93, 0.94]);
      expect(card.lines, isNull);
      expect(card.opponent, isNull);
      // The Yes side even when it is the less likely one: the page's own
      // figure ("Yes chance 15.3%").
      final down = predictionCardFor(watch,
          slug: _slug, title: _q74, candidate: '↓ 74,000');
      expect(down.question, _q74);
      expect(down.outcome, 'Yes');
      expect(down.chance, closeTo(15.3, 1e-9));
      expect(down.leading, isFalse);
    });

    test('the event: its leader and the market chart of its top lines',
        () async {
      final watch = await watcher();
      final card = predictionCardFor(watch, slug: _slug, title: _title);
      expect(card.question, _title);
      expect(card.binary, isFalse);
      expect(card.outcome, '↑ 76,000');
      expect(card.charted, isTrue);
      expect([for (final l in card.lines!) l.name],
          containsAllInOrder(['↑ 76,000', '↑ 78,000']));
    });

    test('a candidate the event no longer lists: what the page handed over',
        () async {
      final watch = await watcher();
      final card = predictionCardFor(watch,
          slug: _slug,
          title: 'Will Bitcoin reach \$80,000?',
          chance: 3,
          candidate: '↑ 80,000');
      expect(card.question, 'Will Bitcoin reach \$80,000?');
      expect(card.outcome, 'Yes');
      expect(card.chance, 3);
      expect(card.lines, isNull);
    });

    test('a pick keeps its own card: the candidate is the market shared only',
        () async {
      final watch = await watcher();
      final card = predictionCardFor(watch,
          slug: _slug,
          title: _title,
          outcome: '↑ 78,000',
          picked: true,
          amount: r'$10',
          candidate: '↑ 76,000');
      expect(card.outcome, '↑ 78,000');
      expect(card.picked, isTrue);
    });
  });

  test('the market link names one market only when asked', () {
    expect(marketShareLink(venue: kMarketLinkPredictions, slug: _slug),
        'https://backend.kutewallet.com/m/predictions/$_slug');
    final one = Uri.parse(marketShareLink(
        venue: kMarketLinkPredictions, slug: _slug, outcome: ' ↑ 76,000 '));
    expect(one.path, '/m/predictions/$_slug');
    expect(one.queryParameters, {'outcome': '↑ 76,000'});
    expect(
        marketShareLink(
            venue: kMarketLinkPredictions, slug: _slug, outcome: ''),
        'https://backend.kutewallet.com/m/predictions/$_slug');
    // The referral code rides along, the outcome kept.
    final shared =
        Uri.parse(shareLinkWithReferral(one.toString(), code: 'ANA1'));
    expect(shared.queryParameters, {'outcome': '↑ 76,000', 'ref': 'ANA1'});
  });

  group('send mode: no look-only link, the bar says what is happening', () {
    for (final name in ['Ana', null]) {
      testWidgets(
          'the event page${name == null ? '' : ' (for $name)'}: "Pick an '
          'outcome · You\'re buying it for ${name ?? 'your friend'}"; a tap '
          'brings the outcomes up and sends nothing', (tester) async {
        await _loadInter(tester);
        await http.runWithClient(() async {
          // A short phone: the outcomes start below the fold.
          await _pump(tester, _btc,
              height: 600,
              sendPick: SendPickSession(
                  entrySource: 'dollar_send', recipientName: name));
          final top = _top(tester);
          expect(top.isTrade, isFalse);
          expect(top.isPrimary, isFalse);
          expect(top.label, _l10n.sendPickBarPickOutcome);
          expect(
              top.sublabel,
              name == null
                  ? _l10n.sendPickBarBuyingForFriend
                  : _l10n.sendPickBarBuyingFor(name));
          expect(top.sublabel, isNot(_l10n.shareTheMarketSub));
          // No market send behind it, no Sal sheet card for it.
          expect(top, isNot(isA<KuteMarketBarContext>()));
          expect(top.actions, isEmpty);
          expect(top.directAction, isNotNull);
          expect(
              find.descendant(
                  of: _pill, matching: find.text(_l10n.sendPickBarPickOutcome)),
              findsOneWidget);
          expect(find.text(_l10n.shareTheMarketSub), findsNothing);
          // The chip names the friend, in the primary ink, the gift glyph.
          final chip = find.byKey(const ValueKey('send-pick-chip'));
          expect(
              find.descendant(
                  of: chip,
                  matching: find.text(name == null
                      ? _l10n.sendPickChipFriend
                      : _l10n.sendPickChipForNamed(name))),
              findsOneWidget);
          expect(find.byKey(const ValueKey('send-pick-chip-gift')),
              findsOneWidget);
          final box =
              tester.widget<Container>(chip).decoration as BoxDecoration;
          expect(box.color, AppColorsExtension.light().textPrimary);

          final scroll = tester
              .state<ScrollableState>(find.descendant(
                  of: find.byType(CustomScrollView).first,
                  matching: find.byType(Scrollable)))
              .position;
          expect(scroll.pixels, 0);
          await tester.tap(_pill);
          await _settle(tester);
          expect(find.byType(ShareMarketSheet), findsNothing);
          expect(find.byType(UnifiedSearchSurface), findsNothing);
          expect(scroll.pixels, greaterThan(0));
          expect(events.where((e) => e.$1.startsWith('share_market')), isEmpty);
          await _done(tester);
        }, _offline);
      });
    }

    testWidgets(
        'the ↑ 76,000 Yes / No page: "Send Yes 94%" | "Send No 6%" in green '
        'and red, no round share button', (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _btc,
            sendPick: SendPickSession(
                entrySource: 'dollar_send', recipientName: 'Ana'));
        await tester.tap(find.text('↑ 76,000').last);
        await _settle(tester);
        expect(_pageTitle(tester), _q76);
        final top = _top(tester);
        expect(top.isTrade, isTrue);
        expect(top.share, isNull);
        expect(top.trades.map((t) => (t.label, t.value, t.fill)), [
          (_l10n.sendPickTradeSide(_l10n.yes), '94%', AppColors.marketUp),
          (_l10n.sendPickTradeSide(_l10n.betNo), '6%', AppColors.marketDown),
        ]);
        expect(find.text('Send Yes'), findsOneWidget);
        expect(_share, findsNothing);
        expect(
            find.descendant(
                of: find.byType(MarketDetailSheet).last,
                matching: find.text(_l10n.sendPickChipForNamed('Ana'))),
            findsOneWidget);
        await _done(tester);
      }, _offline);
    });

    testWidgets('outside send mode the event page keeps "Send to a friend"',
        (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _btc);
        final top = _top(tester);
        expect(top.label, _l10n.barShareWithFriends);
        expect(top.sublabel, _l10n.shareTheMarketSub);
        expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
        await _done(tester);
      }, _offline);
    });
  });
}
