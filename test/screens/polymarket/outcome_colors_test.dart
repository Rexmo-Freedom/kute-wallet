// An outcome with a line on its market's chart wears that line's colour:
// its button under the chart is a solid slab of it (white text, 4.5:1),
// and the bet slip opened on it is tinted in it, switching when the slip
// flips to the other side. Yes / No and Up / Down keep green and red, and
// the sell sheet stays red.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

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

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<void> refresh() async {}
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

SettingsModel _settings() => SettingsModel(Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
    ));

List<Override> _overrides() => [
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polyGameLinesProvider
          .overrideWith((ref, slug) => Completer<PolyGameLines>().future),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polyWatchlistProvider.overrideWith(_NoStars.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      settingsProvider.overrideWith((ref) => _settings()),
      polymarketTradingProvider.overrideWith(_Trading.new),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const [])),
    ];

Future<void> _pump(WidgetTester tester, Widget home,
    {bool dark = false}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

/// A two-sided game: moneyline (charted), spread, total.
PolymarketEvent _game() => PolymarketModel().parseEventsRaw([
      {
        'id': '1',
        'slug': 'nfl-ind-was-2026-10-04',
        'title': 'Colts vs. Commanders',
        'gameId': 19502,
        'tags': [
          {'slug': 'sports'}
        ],
        'teams': [
          {'name': 'Colts', 'abbreviation': 'ind', 'ordering': 'away'},
          {'name': 'Commanders', 'abbreviation': 'was', 'ordering': 'home'},
        ],
        'markets': [
          _market('ml', 'moneyline', null, 'Colts vs. Commanders',
              ['Colts', 'Commanders'], ['0.655', '0.345']),
          _market('sp', 'spreads', -4.5, 'Spread: Colts (-4.5)',
              ['Colts', 'Commanders'], ['0.495', '0.505']),
          _market('to', 'totals', 46.5, 'Colts vs. Commanders: O/U 46.5',
              ['Over', 'Under'], ['0.495', '0.505']),
        ],
      }
    ]).single;

/// A football three-way: team, draw, team. With [gameId] it is a game
/// sheet (the board); without, the Win/Draw/Lose row.
PolymarketEvent _threeWay({int? gameId}) => PolymarketEvent(
      id: '7',
      slug: 'epl-ars-che',
      title: 'Arsenal vs. Chelsea',
      volume: 1000,
      liquidity: 1000,
      category: 'sports',
      conditionId: '0x7',
      gameId: gameId,
      outcomes: const [
        PolymarketOutcome(
            name: 'Arsenal',
            price: 0.5,
            tokenId: 'a',
            noTokenId: 'an',
            gammaMarketId: 'ma'),
        PolymarketOutcome(
            name: 'Draw',
            price: 0.25,
            tokenId: 'd',
            noTokenId: 'dn',
            gammaMarketId: 'md'),
        PolymarketOutcome(
            name: 'Chelsea',
            price: 0.25,
            tokenId: 'c',
            noTokenId: 'cn',
            gammaMarketId: 'mc'),
      ],
    );

/// The outcome button holding [label]: the Container with a rounded
/// decoration nearest above it.
BoxDecoration _buttonOf(WidgetTester tester, String label) {
  final box = find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null),
      )
      .first;
  return tester.widget<Container>(box).decoration as BoxDecoration;
}

Color? _slipTint(WidgetTester tester) {
  final tint = find.byType(SheetTint);
  if (tint.evaluate().isEmpty) return null;
  return tester.widget<SheetTint>(tint.first).side;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('polyOutcomeFill', () {
    final palette = {...kPolyOutcomeColors, ...kGameSideColors};
    test('white text on every palette fill reads at 4.5:1 or better', () {
      for (final line in palette) {
        final fill = polyOutcomeFill(line);
        expect(polyWhiteContrast(fill), greaterThanOrEqualTo(4.5),
            reason: '$line → $fill');
      }
    });

    test('keeps the line\'s hue, only ever darker', () {
      for (final line in palette) {
        final a = HSLColor.fromColor(line);
        final b = HSLColor.fromColor(polyOutcomeFill(line));
        final dh = (a.hue - b.hue).abs();
        expect(dh < 3 || dh > 357, isTrue, reason: '$line hue moved $dh');
        expect(b.lightness, lessThanOrEqualTo(a.lightness + 0.005));
      }
    });

    test('a line already dark enough is its own fill', () {
      const deep = Color(0xFF1E3A8A);
      expect(polyOutcomeFill(deep), deep);
    });
  });

  group('game board buttons take their chart line colours', () {
    for (final dark in [false, true]) {
      testWidgets('two sides (${dark ? 'dark' : 'light'})', (tester) async {
        final event = _game();
        await http.runWithClient(() async {
          await _pump(tester, MarketDetailSheet(event: event), dark: dark);
          expect(find.text('WINNER'), findsOneWidget);
          // The chart's two lines, in its order (title's first team first).
          final colts = kGameSideColors[0], commanders = kGameSideColors[1];
          expect(_buttonOf(tester, 'Colts').color, polyOutcomeFill(colts));
          expect(_buttonOf(tester, 'Commanders').color,
              polyOutcomeFill(commanders));
          // A spread's sides are the teams: their lines' colours.
          expect(_buttonOf(tester, 'IND -4.5').color, polyOutcomeFill(colts));
          expect(
              _buttonOf(tester, 'WAS +4.5').color, polyOutcomeFill(commanders));
          // The chart draws no Over/Under: neutral cards, as before.
          final surface =
              (dark ? AppColorsExtension.dark() : AppColorsExtension.light())
                  .surface;
          expect(_buttonOf(tester, 'Over 46.5').color, surface);
          expect(_buttonOf(tester, 'Under 46.5').color, surface);
          // White label and figure on the filled ones.
          final label = tester.widget<Text>(find.text('Colts').last);
          expect(label.style?.color, Colors.white);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }, () => MockClient((_) async => http.Response('{}', 404)));
      });
    }

    testWidgets('a three-way game: team, draw (third line), team',
        (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, MarketDetailSheet(event: _threeWay(gameId: 42)));
        expect(find.text('WINNER'), findsOneWidget);
        expect(_buttonOf(tester, 'Arsenal').color,
            polyOutcomeFill(kGameSideColors[0]));
        expect(_buttonOf(tester, 'Draw').color,
            polyOutcomeFill(kGameSideColors[2]));
        expect(_buttonOf(tester, 'Chelsea').color,
            polyOutcomeFill(kGameSideColors[1]));
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets('the Win/Draw/Lose row of a match with no game',
        (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, MarketDetailSheet(event: _threeWay()));
        expect(_buttonOf(tester, 'Arsenal').color,
            polyOutcomeFill(kGameSideColors[0]));
        expect(_buttonOf(tester, 'Draw').color,
            polyOutcomeFill(kPolyOutcomeColors[2]));
        expect(_buttonOf(tester, 'Chelsea').color,
            polyOutcomeFill(kGameSideColors[1]));
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets('a binary market keeps its green and red pair', (tester) async {
      final binary = PolymarketEvent(
        id: '3',
        slug: 'rain',
        title: 'Will it rain?',
        volume: 1,
        liquidity: 1,
        category: 'weather',
        conditionId: '0x3',
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.6, tokenId: 'y'),
          PolymarketOutcome(name: 'No', price: 0.4, tokenId: 'n'),
        ],
      );
      await http.runWithClient(() async {
        await _pump(tester, MarketDetailSheet(event: binary));
        final pair = tester
            .widgetList<MarketPairButton>(find.byType(MarketPairButton))
            .map((b) => b.color)
            .toList();
        expect(pair, [AppColors.marketUp, AppColors.marketDown]);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  });

  group('the bet slip wears the outcome colour', () {
    Widget slip(List<PolymarketOutcome> outcomes,
            {List<Color?>? colors, int initial = 0}) =>
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
              marketQuestion: outcomes.first.name == 'Yes'
                  ? 'Will it rain?'
                  : 'Colts vs. Commanders',
              outcomes: outcomes,
              initialOutcomeIndex: initial,
              outcomeColors: colors,
              initialAmountUsd: 10,
            ),
          ),
        );
    const teams = [
      PolymarketOutcome(name: 'Colts', price: 0.6, tokenId: 'a'),
      PolymarketOutcome(name: 'Commanders', price: 0.4, tokenId: 'b'),
    ];
    const yesNo = [
      PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'y'),
      PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'n'),
    ];

    testWidgets('follows the picked outcome and switches on the toggle',
        (tester) async {
      final a = kGameSideColors[0], b = kGameSideColors[1];
      await _pump(tester, slip(teams, colors: [a, b]));
      expect(_slipTint(tester), polyOutcomeFill(a));
      // White ink on the outcome's fill.
      expect(tester.widget<SheetTint>(find.byType(SheetTint).first).on,
          Colors.white);
      await tester.tap(find.text('Commanders').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_slipTint(tester), polyOutcomeFill(b));
      await tester.tap(find.text('Colts').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_slipTint(tester), polyOutcomeFill(a));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an outcome with no line falls back to red', (tester) async {
      final draw = kGameSideColors[2];
      await _pump(tester, slip(yesNo, colors: [draw, null]));
      expect(_slipTint(tester), polyOutcomeFill(draw));
      await tester.tap(find.text('NO'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_slipTint(tester), AppColors.marketDown);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Yes / No without colours stays green and red', (tester) async {
      await _pump(tester, slip(yesNo));
      expect(_slipTint(tester), AppColors.marketUp);
      await tester.tap(find.text('NO'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_slipTint(tester), AppColors.marketDown);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a WINNER tap opens the slip in that side\'s colour',
        (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, MarketDetailSheet(event: _game()));
        await tester.tap(find.text('Commanders').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(BetSlipSheet), findsOneWidget);
        expect(_slipTint(tester), polyOutcomeFill(kGameSideColors[1]));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets('the sell sheet stays red', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: SellSheet(
            position: PolymarketPosition(
              marketId: 'condition',
              marketQuestion: 'Colts vs. Commanders',
              outcome: 'Colts',
              size: 10,
              avgPrice: 0.5,
              currentPrice: 0.6,
              pnl: 1,
              pnlPercent: 20,
              isResolved: false,
              tokenId: 'a',
            ),
          ),
        ),
      );
      expect(
          tester
              .widget<SideTintedSubtree>(find.byType(SideTintedSubtree).first)
              .side,
          AppColors.marketDown);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
