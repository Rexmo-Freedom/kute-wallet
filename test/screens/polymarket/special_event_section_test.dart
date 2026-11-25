// The market page of a US election event draws it (special_event_section
// .dart): Build your map shows the most likely map coloured by side and
// chance, a state's sides as pills, and opens the one real market your
// map is; one market per state opens a state's market from the map;
// balance of power splits each race by party. Real Gamma events
// (special_event_fixtures.dart) on the whole sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/special_event_section.dart';
import 'package:kute/screens/polymarket/components/us_map_geometry.dart';
import 'package:kute/screens/polymarket/components/us_state_map.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/special_event_map.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/polymarket/special_event_fixtures.dart';

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
  void tick(String token, double p) => state = state.copyWithPrice(token, p);
}

PolymarketEvent _event(Map<String, dynamic> raw) =>
    PolymarketModel().parseEventsRaw([raw]).single;

double? _shown(PolymarketOutcome o) => o.unpriced ? null : o.price;

const _lightNeutral = Color(0xFFE3E6EB);
const _darkNeutral = Color(0xFF3B4148);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<_Prices> pumpSheet(WidgetTester tester, PolymarketEvent event,
      {bool dark = false}) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prices = _Prices();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        livePriceProvider.overrideWith(() => prices),
        sportsLiveProvider.overrideWith(_NoGames.new),
        polyGameTimelineProvider.overrideWith(_NoTimeline.new),
        polyGameLinesProvider
            .overrideWith((ref, slug) async => PolyGameLines.empty),
        polymarketActivePositionsProvider.overrideWithValue(const []),
        polymarketClaimablePositionsProvider.overrideWithValue(const []),
        aiEnabledProvider.overrideWith((ref) async => false),
        polyWatchlistProvider.overrideWith(_NoStars.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: dark
              ? ThemeData(
                  brightness: Brightness.dark,
                  extensions: [AppColorsExtension.dark()])
              : ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarketDetailSheet(event: event),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return prices;
  }

  UsStateMap theMap(WidgetTester tester) =>
      tester.widget<UsStateMap>(find.byType(UsStateMap));

  /// Taps [code] in the middle of its outline on the map.
  Future<void> tapState(WidgetTester tester, String code) async {
    final finder = find.byType(UsStateMap);
    await tester.ensureVisible(finder);
    await tester.pump();
    final box = tester.renderObject<RenderBox>(finder);
    final scale = box.size.width / kUsMapWidth;
    await tester
        .tapAt(box.localToGlobal(kUsStateLabelPoints[code]!.at * scale));
    await tester.pump();
  }

  PolymarketEvent openedMarket(WidgetTester tester) => tester
      .widgetList<MarketDetailSheet>(find.byType(MarketDetailSheet))
      .map((w) => w.event)
      .where((e) => e.isSyntheticBinary)
      .single;

  /// The section's own figure for [token] (the outcome list below has
  /// one too).
  Finder figure(String? token, String text) => find.descendant(
      of: find.byType(PolySpecialEventSection),
      matching: find.byWidgetPredicate(
          (w) => w is RollingFigure && w.identity == token && w.text == text));

  testWidgets(
      'Build your map: the most likely map by side and chance, a state\'s '
      'sides, and the one market your map is', (tester) async {
    await http.runWithClient(() async {
      final event = _event(buildYourMapSenateRaw());
      final map = polySpecialEventOf(event) as PolyStateCombos;
      final odds = polyComboStateOdds(map, _shown);
      PolymarketOutcome named(String name) =>
          event.outcomes.firstWhere((o) => o.name == name);
      await pumpSheet(tester, event);

      expect(find.byType(PolyBuildYourMap), findsOneWidget);
      expect(
          find.text('Republicans favoured in 0 of 7 states'), findsOneWidget);
      // The most likely map: "None", every state blue (Republicans lose),
      // as deep as each state's chance of it.
      expect(find.text('Most likely map'), findsOneWidget);
      expect(figure(named('None').tokenId, '96.7%'), findsOneWidget);
      var fills = theMap(tester).fills;
      expect(fills.keys.toSet(), map.states.toSet());
      expect(
          fills['TX'],
          polyMapFill(kPolyDemocratBlue, odds['TX']![PolyMapSide.notRep]!,
              _lightNeutral));
      expect(fills['CA'], isNull); // not in this market: grey
      expect(find.text('Tap the states to build your map'), findsOneWidget);

      // Texas: its two sides with their chances, Not Republican picked.
      await tapState(tester, 'TX');
      expect(theMap(tester).selected, 'TX');
      expect(find.text('Texas'), findsOneWidget);
      final pills = tester
          .widgetList<KutePill>(find.byType(KutePill))
          .where((p) => p.key.toString().contains('poly-map-side-TX'));
      expect({for (final p in pills) p.label: p.selected},
          {'Republican': false, 'Not Republican': true});

      // Republican Texas: your map is the market "TX".
      await tester.tap(find.byKey(const ValueKey('poly-map-side-TX-rep')));
      await tester.pump();
      expect(find.text('Your map'), findsOneWidget);
      expect(figure(named('TX').tokenId, '<1%'), findsOneWidget);
      fills = theMap(tester).fills;
      expect(
          fills['TX'],
          polyMapFill(kPolyRepublicanRed, odds['TX']![PolyMapSide.rep]!,
              _lightNeutral));
      expect(find.text('Back to the most likely map'), findsOneWidget);

      // It opens that market's own Yes / No page.
      await tester
          .ensureVisible(find.byKey(const ValueKey('poly-map-open-market')));
      await tester.tap(find.byKey(const ValueKey('poly-map-open-market')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final opened = openedMarket(tester);
      expect(opened.title, 'TX');
      expect(opened.outcomes.first.tokenId, named('TX').tokenId);
      expect(opened.outcomes.last.tokenId, named('TX').noTokenId);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('Build your map follows the feed until the user picks',
      (tester) async {
    await http.runWithClient(() async {
      final event = _event(buildYourMapSenateRaw());
      final ak = event.outcomes.firstWhere((o) => o.name == 'AK');
      final none = event.outcomes.firstWhere((o) => o.name == 'None');
      final prices = await pumpSheet(tester, event);
      prices.tick(ak.tokenId!, 0.9);
      prices.tick(none.tokenId!, 0.05);
      await tester.pump(const Duration(seconds: 1));
      // Alaska now leans Republican, and "AK" is the most likely map.
      expect(
          find.text('Republicans favoured in 1 of 7 states'), findsOneWidget);
      expect(figure(ak.tokenId, '90%'), findsOneWidget);
      final fills = theMap(tester).fills;
      expect(HSLColor.fromColor(fills['AK']!).hue,
          closeTo(HSLColor.fromColor(kPolyRepublicanRed).hue, 1));
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets(
      'one market per state: green by Yes chance, a tap opens the state\'s '
      'market (dark)', (tester) async {
    await http.runWithClient(() async {
      final event = _event(trumpStateVisitsRaw());
      final markets = polySpecialEventOf(event) as PolyStateMarkets;
      await pumpSheet(tester, event, dark: true);
      // West Virginia's book is wide: its last trade, 77%, is its chance.
      final yes =
          markets.byState.values.where((o) => (_shown(o) ?? 0) > 0.5).length;
      expect(yes, 1);
      expect(find.text('Yes leads in 1 of ${markets.byState.length} states'),
          findsOneWidget);
      final fills = theMap(tester).fills;
      // Visited states have closed: no open market, grey.
      expect(fills['TX'], isNull);
      expect(
          fills['CO'],
          polyMapFill(AppColors.marketUp, markets.byState['CO']!.price,
              _darkNeutral));
      // A 26/38 book is wide: Louisiana reads its last trade.
      expect(theMap(tester).semanticLabels['LA'], 'Louisiana: 38%');

      await tapState(tester, 'CO');
      await tester.pump(const Duration(milliseconds: 400));
      final opened = openedMarket(tester);
      expect(opened.title, 'Colorado');
      expect(opened.outcomes.first.tokenId, markets.byState['CO']!.tokenId);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('balance of power: each race split by party', (tester) async {
    await http.runWithClient(() async {
      await pumpSheet(tester, _event(balanceOfPowerRaw()));
      expect(find.text('Senate'), findsOneWidget);
      expect(find.text('House'), findsOneWidget);
      expect(find.text('Democratic >99%'), findsNWidgets(2));
      expect(find.text('Republican <1%'), findsNWidgets(2));
      expect(find.byType(UsStateMap), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('any other event draws nothing', (tester) async {
    await http.runWithClient(() async {
      await pumpSheet(tester, _event(ebolaCountriesRaw()));
      expect(find.byType(PolySpecialEventSection), findsNothing);
      expect(find.byType(UsStateMap), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
