// A market page's "Send to a friend" (founder, 2 November 2026: "on
// markets, not the individual predictions, send a market should just be
// send the market. Only on individual predictions we can send the
// prediction"). An event page (several outcomes, each its own Yes/No
// market) opens the Sal sheet on one full-width "Send the market" card;
// a single Yes/No market (an outcome drilled into from an event is one)
// keeps both cards, "Send the market" and "Send a prediction".
//
// A CARD TAP CLOSES THE SAL SHEET AND OPENS ITS SHEET (founder, 4 November
// 2026: "Card on search share not working. I click and nothing happens"):
// the market card opens the market send sheet, the prediction card Send
// to anyone on its side step, Yes and No equal and nothing chosen, with
// the Sal sheet gone from under them.
//
// Where it sits (founder, 4 November 2026: "It must be a floating
// button"): never in the header or beside the headline figure. One Yes/No
// market's bar is its trade row (Yes | No with the live chances, the round
// Sal button at the end; taps land on each and open the slip's path); an
// event's bar is the floating Sal pill, "Send to a friend". The page's
// last rows scroll clear of either.

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
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show kPolyRulesCardKey;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/search/unified_search_screen.dart'
    show UnifiedSearchSurface;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
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

/// What the bar reads on the page now.
KuteBarContext _top(WidgetTester tester) => kuteBarTop(ProviderScope
        .containerOf(tester.element(find.byType(MarketDetailSheet)))
    .read(kuteBarContextProvider))!;

/// The page's market context: the bar's own, or the one its trade row's
/// round Sal button opens.
KuteMarketBarContext _bar(WidgetTester tester) {
  final top = _top(tester);
  return (top.isTrade ? top.share!.barContext : top) as KuteMarketBarContext;
}

final Finder _share = find.byKey(const ValueKey('kute-bar-share'));
final Finder _pill = find.byKey(const ValueKey('kute-bar-pill'));
Finder _trade(String id) => find.byKey(ValueKey('kute-bar-trade-$id'));

/// Whether a tap at [finder]'s centre reaches its render box.
bool _tapLands(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == box);
}

/// Taps the page's Send to a friend (the trade row's round Sal button, or
/// the Sal pill): the Sal sheet opens.
Future<void> _openSheet(WidgetTester tester) async {
  final control = _share.evaluate().isNotEmpty ? _share : _pill;
  expect(control, findsOneWidget);
  await tester.tap(control);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the page to its very end.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(
      find.byType(CustomScrollView).first, const Offset(0, -6000));
  for (var i = 0; i < 10; i++) {
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
        'one full-width "Send the market" card, no "Send a prediction"',
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
        expect(find.text(l10n.sendAPrediction), findsNothing);
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
      'cards, "Send the market" and "Send a prediction"', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _yesNo);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final bar = _bar(tester);
      expect(bar.actions.map((a) => a.label),
          [l10n.shareTheMarket, l10n.sendAPrediction]);
      expect(bar.sublabel, l10n.barShareMarketSub);
      await _openSheet(tester);
      final grid = find.byKey(const ValueKey('context-actions-card'));
      expect(
          find.descendant(of: grid, matching: find.text(l10n.shareTheMarket)),
          findsOneWidget);
      expect(
          find.descendant(
              of: grid, matching: find.text(l10n.sendAPrediction)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  /// A market where No leads: the old default picked "No" here.
  final noLeads = _event('Will it snow in Lisbon this year?', const [
    PolymarketOutcome(name: 'Yes', price: 0.12, tokenId: 'y'),
    PolymarketOutcome(name: 'No', price: 0.88, tokenId: 'n'),
  ]);

  testWidgets(
      'tapping "Send the market" closes the Sal sheet and opens the market '
      'send sheet on top, Share the bar', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, noLeads);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _openSheet(tester);
      expect(find.byType(UnifiedSearchSurface), findsOneWidget);
      await tester.tap(
          find.byKey(ValueKey('context-action-card-${l10n.shareTheMarket}')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The Sal sheet is gone, not left under the new sheet.
      expect(find.byType(UnifiedSearchSurface), findsNothing);
      expect(find.byType(ShareMarketSheet).hitTestable(), findsOneWidget);
      final top = kuteBarTop(ProviderScope.containerOf(
              tester.element(find.byType(MarketDetailSheet)))
          .read(kuteBarContextProvider))!;
      expect(top.isPrimary, isTrue);
      expect(top.label, l10n.share);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets(
      'a single Yes/No market: the bar is Yes | No with the live chances '
      'and the round Sal button; no share pill in the page; Rules scrolls '
      'clear of the row', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _yesNo);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final top = _top(tester);
      expect(top.isTrade, isTrue);
      expect(top.trades.map((t) => (t.label, t.value, t.fill)), [
        (l10n.yes, '64%', AppColors.marketUp),
        (l10n.betNo, '36%', AppColors.marketDown),
      ]);
      expect(_trade('yes'), findsOneWidget);
      expect(_trade('no'), findsOneWidget);
      expect(_share, findsOneWidget);
      expect(_pill, findsNothing);
      expect(find.bySemanticsLabel('${l10n.yes}, 64%'), findsOneWidget);
      expect(find.bySemanticsLabel('${l10n.betNo}, 36%'), findsOneWidget);
      final yes = tester.getRect(_trade('yes'));
      final no = tester.getRect(_trade('no'));
      final share = tester.getRect(_share);
      expect(yes.right, lessThan(no.left));
      expect(no.right, lessThan(share.left));
      expect(yes.width, moreOrLessEquals(no.width, epsilon: 1));
      // Nothing to share in the header or beside the chance.
      expect(find.byKey(const ValueKey('kute-sal-header-button')),
          findsNothing);
      expect(find.text(l10n.shareHeaderLabel), findsNothing);
      // The last row scrolls clear of the floating row.
      await _scrollToEnd(tester);
      final rules = tester.getRect(find.byKey(kPolyRulesCardKey));
      expect(rules.bottom, lessThan(tester.getRect(_trade('yes')).top));
      // Rules and resolution is the page's only option card: the full
      // width, never half of it (founder, 5 November 2026).
      expect(rules.center.dx, moreOrLessEquals(390 / 2, epsilon: 1));
      expect(rules.width, greaterThan(390 * 0.85));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets(
      'tapping "Send a prediction" (No leads) closes the Sal sheet and opens '
      'Send to anyone on the side step: Yes and No, equal, nothing chosen, '
      'no amount yet', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, noLeads);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final bar = _bar(tester);
      // The card's foot reads both sides, never the leading one alone.
      expect(bar.preview.line, 'Yes 12% · No 88%');
      await _openSheet(tester);
      await tester.tap(find
          .byKey(ValueKey('context-action-card-${l10n.sendAPrediction}')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(UnifiedSearchSurface), findsNothing);
      expect(find.byType(SendToAnyoneSheet).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('send-pick-side-step')), findsOneWidget);
      final pair = find.byKey(const ValueKey('send-pick-side-pair'));
      final buttons = tester
          .widgetList<MarketPairButton>(
              find.descendant(of: pair, matching: find.byType(MarketPairButton)))
          .toList();
      expect(buttons.map((b) => b.label), [l10n.yes, l10n.betNo]);
      expect(buttons.map((b) => b.value), ['12%', '88%']);
      // Equal: the same size, side by side.
      final a = tester.getSize(find.byKey(const ValueKey('send-pick-side-0')));
      final b = tester.getSize(find.byKey(const ValueKey('send-pick-side-1')));
      expect(a, b);
      // Nothing picked, so no amount and no pick line yet.
      expect(find.byKey(const ValueKey('share-pick-line')), findsNothing);
      expect(find.text(l10n.sendPickSideSub), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  for (final side in ['yes', 'no']) {
    testWidgets(
        'a single Yes/No market: a tap lands on $side and opens the slip on '
        'it (prediction_outcome_tapped, $side)', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _loadInter(tester);
      await http.runWithClient(() async {
        await _pump(tester, _yesNo);
        expect(_tapLands(tester, _trade(side)), isTrue);
        expect(_tapLands(tester, _share), isTrue);
        await tester.tap(_trade(side));
        final taps = events
            .where((e) => e.$1 == 'prediction_outcome_tapped')
            .toList();
        expect(taps, hasLength(1));
        expect(taps.single.$2!['outcome_type'], side);
        // The slip itself is its own tests' (bet_slip_*_test.dart): the
        // page goes before the slip is built.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  testWidgets(
      'an event page: no trade pair, the bar is the floating Sal pill '
      '"Send to a friend"; nothing beside the leader\'s chance; the last '
      'rows scroll clear of it', (tester) async {
    await _loadInter(tester);
    await http.runWithClient(() async {
      await _pump(tester, _michigan);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final top = _top(tester);
      expect(top.isTrade, isFalse);
      expect(top.isPrimary, isFalse);
      expect(top.inHeader, isFalse);
      expect(_pill, findsOneWidget);
      expect(_share, findsNothing);
      expect(
          find.descendant(
              of: _pill, matching: find.text(l10n.barShareWithFriends)),
          findsOneWidget);
      expect(find.byKey(const ValueKey('kute-sal-header-button')),
          findsNothing);
      expect(_tapLands(tester, _pill), isTrue);
      await _scrollToEnd(tester);
      // Scrolled down, the pill may be folded into the round button; the
      // last row stays clear of it either way.
      final pill = tester.getRect(_pill);
      expect(tester.getRect(find.byKey(kPolyRulesCardKey)).bottom,
          lessThan(pill.top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
