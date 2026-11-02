// A market page's "Send to a friend" (founder, 2 November 2026: "on
// markets, not the individual predictions, send a market should just be
// send the market. Only on individual predictions we can send the
// prediction"). An event page (several outcomes, each its own Yes/No
// market) opens the Sal sheet on one full-width "Send the market" card;
// a single Yes/No market (an outcome drilled into from an event is one)
// keeps both cards, "Send the market" and "Send this prediction".

import 'dart:async';

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

PolymarketEvent _event(String title, List<PolymarketOutcome> outcomes) =>
    PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
      title: title,
      volume: 1200000,
      liquidity: 50000,
      category: 'politics',
      tags: const [],
      endDate: DateTime(2027, 11, 3),
      conditionId: 'c-$title',
      outcomes: outcomes,
    );

/// The founder's screenshot: each candidate its own Yes/No market.
final _michigan = _event('Michigan Senate Election Winner', const [
  PolymarketOutcome(
      name: 'Abdul El-Sayed (D)',
      price: 0.64,
      tokenId: 'a-yes',
      noTokenId: 'a-no',
      conditionId: 'c-a'),
  PolymarketOutcome(
      name: 'Mike Rogers (R)',
      price: 0.195,
      tokenId: 'b-yes',
      noTokenId: 'b-no',
      conditionId: 'c-b'),
  PolymarketOutcome(
      name: 'Haley Stevens (D)',
      price: 0.12,
      tokenId: 'c-yes',
      noTokenId: 'c-no',
      conditionId: 'c-c'),
]);

/// One Yes/No market: the page a candidate row drills into.
final _yesNo = _event('Will Abdul El-Sayed win the Michigan Senate race?',
    const [
      PolymarketOutcome(name: 'Yes', price: 0.64, tokenId: 'y'),
      PolymarketOutcome(name: 'No', price: 0.36, tokenId: 'n'),
    ]);

/// Two outcomes, each its own Yes/No market: still an event.
final _twoCandidates = _event('Fed decision in December?', const [
  PolymarketOutcome(
      name: 'No change', price: 0.71, tokenId: 'nc', noTokenId: 'nc-no'),
  PolymarketOutcome(
      name: '25 bps decrease', price: 0.24, tokenId: 'cut', noTokenId: 'c-no'),
]);

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

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
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

KuteMarketBarContext _bar(WidgetTester tester) => kuteBarTop(ProviderScope
            .containerOf(tester.element(find.byType(MarketDetailSheet)))
        .read(kuteBarContextProvider))! as KuteMarketBarContext;

/// Taps the page's "Send to a friend" pill: the Sal sheet opens.
Future<void> _openSheet(WidgetTester tester) async {
  final pill = find.byKey(const ValueKey('kute-sal-header-button'));
  expect(pill, findsOneWidget);
  await tester.tap(pill);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  for (final event in [_michigan, _twoCandidates]) {
    testWidgets(
        'an event page ("${event.title}"): the pill opens the Sal sheet on '
        'one full-width "Send the market" card, no "Send this prediction"',
        (tester) async {
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, event);
        final l10n = lookupAppLocalizations(const Locale('en'));
        final bar = _bar(tester);
        expect(bar.actions.map((a) => a.label), [l10n.shareTheMarket]);
        expect(bar.sublabel, l10n.shareTheMarketSub);
        await _openSheet(tester);
        final grid = find.byKey(const ValueKey('context-actions-card'));
        expect(grid, findsOneWidget);
        expect(
            find.descendant(
                of: grid, matching: find.text(l10n.shareTheMarket)),
            findsOneWidget);
        expect(find.text(l10n.sendThisPrediction), findsNothing);
        final card = find.byKey(
            ValueKey('context-action-card-${l10n.shareTheMarket}'));
        expect(tester.getRect(card).width,
            moreOrLessEquals(tester.getRect(grid).width));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  testWidgets(
      'a single Yes/No market (the page an outcome drills into): both '
      'cards, "Send the market" and "Send this prediction"', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _yesNo);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final bar = _bar(tester);
      expect(bar.actions.map((a) => a.label),
          [l10n.shareTheMarket, l10n.sendThisPrediction]);
      expect(bar.sublabel, l10n.barShareMarketSub);
      await _openSheet(tester);
      final grid = find.byKey(const ValueKey('context-actions-card'));
      expect(
          find.descendant(of: grid, matching: find.text(l10n.shareTheMarket)),
          findsOneWidget);
      expect(
          find.descendant(
              of: grid, matching: find.text(l10n.sendThisPrediction)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
