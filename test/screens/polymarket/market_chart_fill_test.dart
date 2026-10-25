// The market sheet's chart takes the room a short list leaves: a Yes / No
// market or an event of two outcomes has no empty screen under it, while
// a long list keeps the chart at its own height. Worked out once, so the
// chart does not move afterwards.

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
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
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

PolymarketEvent _event(List<PolymarketOutcome> outcomes) => PolymarketEvent(
      id: '9',
      slug: 'brazil-presidential-election',
      title: 'Brazil Presidential Election',
      volume: 1000000,
      liquidity: 50000,
      category: 'politics',
      conditionId: '0x9',
      endDate: DateTime.now().add(const Duration(days: 30)),
      outcomes: outcomes,
    );

final _two = _event(const [
  PolymarketOutcome(
      gammaMarketId: 'a',
      name: 'Flávio Bolsonaro',
      price: 0.79,
      tokenId: 'ya',
      noTokenId: 'na'),
  PolymarketOutcome(
      gammaMarketId: 'b',
      name: 'Luiz Inácio Lula da Silva',
      price: 0.21,
      tokenId: 'yb',
      noTokenId: 'nb'),
]);

final _many = _event([
  for (var i = 0; i < 25; i++)
    PolymarketOutcome(
        gammaMarketId: 'm$i',
        name: 'Candidate $i',
        price: 0.18 - i * 0.006,
        tokenId: 't$i',
        noTokenId: 'n$i'),
]);

final _yesNo = _event(const [
  PolymarketOutcome(gammaMarketId: 'y', name: 'Yes', price: 0.6, tokenId: 'y'),
  PolymarketOutcome(gammaMarketId: 'y', name: 'No', price: 0.4, tokenId: 'n'),
]);

Future<void> _pump(WidgetTester tester, PolymarketEvent event,
    {Size size = const Size(430, 932)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
      polyWatchlistProvider.overrideWith(_NoStars.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MarketDetailSheet(event: event),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

double _chartHeight(WidgetTester tester) =>
    tester.widget<MarketChart>(find.byType(MarketChart)).height;

/// The room under the scroll area's last content: the space between the
/// Rules row's bottom and the sticky buttons, when it is on screen.
double _emptyUnderContent(WidgetTester tester) {
  final scrollable = tester.getRect(find.byType(Scrollable).first);
  final rules = find.text('Rules and resolution');
  if (rules.evaluate().isEmpty) return 0;
  return scrollable.bottom - tester.getRect(rules).bottom;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('polyChartFillExtra', () {
    test('takes the room left, up to its share of the screen', () {
      expect(polyChartFillExtra(leftover: 120, base: 220, viewport: 700), 120);
      // 70% of 700 is 490: 270 over a 220 chart at most.
      expect(polyChartFillExtra(leftover: 400, base: 220, viewport: 700),
          closeTo(270, 1e-9));
      // No room left (a long list): the chart's own height.
      expect(polyChartFillExtra(leftover: -300, base: 220, viewport: 700), 0);
      // A chart already past its share never grows (and never shrinks).
      expect(polyChartFillExtra(leftover: 200, base: 380, viewport: 520), 0);
    });
  });

  testWidgets('two outcomes on a tall phone: the chart grows into the room '
      'under the list, and stays put', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _two);
      final base = polyChartHeightFor(2);
      final height = _chartHeight(tester);
      expect(height, greaterThan(base + 40));
      // The rest of the screen is not left empty, nor overflowed past the
      // sticky buttons by more than a row's slack.
      expect(_emptyUnderContent(tester), lessThan(60));
      expect(_emptyUnderContent(tester), greaterThanOrEqualTo(-1));
      // Settled: later frames do not move it.
      await tester.pump(const Duration(seconds: 1));
      expect(_chartHeight(tester), height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('a Yes / No market grows its chart too', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _yesNo);
      expect(_chartHeight(tester), greaterThan(380));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('a long list keeps the chart at its own height',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _many);
      expect(_chartHeight(tester), polyChartHeightFor(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('a small phone: never smaller than its own height, never past '
      'its share of the screen', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _two, size: const Size(320, 568));
      final h = _chartHeight(tester);
      expect(h, greaterThanOrEqualTo(polyChartHeightFor(2)));
      final viewport = tester.getRect(find.byType(Scrollable).first).height;
      expect(h, lessThanOrEqualTo(
          viewport * kPolyChartMaxShare + 1 > polyChartHeightFor(2)
              ? viewport * kPolyChartMaxShare + 1
              : polyChartHeightFor(2)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
