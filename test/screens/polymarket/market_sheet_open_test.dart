// Opening a game's market sheet: the board is drawn from the event the
// card already has (never waiting on a second read of the game), the rows
// of "More markets" are built as they scroll into view, and a price tick
// repaints the one row it moved.

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
import 'package:kute/providers/advisor_provider.dart'
    show advisorStreamRequestProvider, aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/poly_watch_star.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:kute/models/advisor_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlLiveDot;
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/advisor_service.dart'
    show AdvisorPrompt, AdvisorStreamEvent;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/theme/app_theme.dart';

/// No stars: the watchlist box is never opened in a test.
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
          // 150 player props, most likely first by price.
          for (var i = 0; i < 150; i++)
            _market('p$i', 'player_props', null,
                'Player $i: Anytime touchdown?', ['Yes', 'No'], [
              (0.9 - i * 0.005).toStringAsFixed(3),
              (0.1 + i * 0.005).toStringAsFixed(3),
            ]),
        ],
      }
    ]).single;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a game opens on its board at once, builds only the rows in '
      'view, and a tick repaints its one row', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = _game();
    final prices = _Prices();
    // The Gamma read of the game never answers.
    final never = Completer<PolyGameLines>();
    await http.runWithClient(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          livePriceProvider.overrideWith(() => prices),
          sportsLiveProvider.overrideWith(_NoGames.new),
          polyGameTimelineProvider.overrideWith(_NoTimeline.new),
          polyGameLinesProvider.overrideWith((ref, slug) => never.future),
          polymarketActivePositionsProvider.overrideWithValue(const []),
          polymarketClaimablePositionsProvider.overrideWithValue(const []),
          aiEnabledProvider.overrideWith((ref) async => false),
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

      // The header carries no category tag: the browse cards keep their
      // category pills, the sheet gives the room to the title and Sal.
      expect(event.category.toLowerCase(), 'sports');
      expect(find.text('Sports'), findsNothing);

      // The board, from the event itself.
      expect(find.text('WINNER'), findsOneWidget);
      expect(find.text('SPREAD'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('IND -4.5'), findsOneWidget);

      // "More markets": 150 props, a few rows built.
      await tester.scrollUntilVisible(find.text('More markets'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      final built = find.textContaining('Anytime touchdown').evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));

      // A tick on the first prop's token repaints that row's figure.
      final row = find.text('Player 0: Anytime touchdown?');
      expect(row, findsOneWidget);
      Finder figure(String text) => find.byWidgetPredicate(
          (w) => w is RollingFigure && w.identity == 'p0a' && w.text == text);
      expect(figure('90%'), findsOneWidget);
      prices.tick('p0a', 0.95);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(figure('95%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  // A 25-outcome race: the leader's chance is the hero, Sal's question
  // capsule is right under it, and the title is up in the header.
  PolymarketEvent race({String? title}) => PolymarketEvent(
        id: '9',
        slug: 'next-leader',
        title: title ??
            'Who will be the next leader of the Example Party after the '
                'upcoming leadership election?',
        volume: 1000000,
        liquidity: 50000,
        category: 'politics',
        conditionId: '0x9',
        endDate: DateTime.now().add(const Duration(days: 730)),
        outcomes: [
          for (var i = 0; i < 25; i++)
            PolymarketOutcome(
                gammaMarketId: 'm$i',
                name: 'Candidate $i',
                price: 0.18 - i * 0.006,
                tokenId: 't$i'),
        ],
      );

  Future<void> loadInter(WidgetTester tester) => tester.runAsync(() async {
        final inter = FontLoader('Inter');
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      });

  Future<void> pumpRace(WidgetTester tester,
      {double width = 430,
      Locale locale = const Locale('en'),
      String? title,
      double textScale = 1,
      List<Override> extra = const []}) async {
    tester.view.physicalSize = Size(width, 932);
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
        aiEnabledProvider.overrideWith((ref) async => true),
        polyWatchlistProvider.overrideWith(_NoStars.new),
        ...extra,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: locale,
          theme: ThemeData(
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: MarketDetailSheet(event: race(title: title)),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final capsule = find.byKey(const ValueKey('sal-question-capsule'));
  final capsuleText = find.byKey(const ValueKey('sal-question-capsule-text'));

  int lines(WidgetTester tester, String text) => tester
      .renderObject<RenderParagraph>(capsuleText)
      .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length))
      .map((b) => b.top.round())
      .toSet()
      .length;

  // The owner's screenshot: a long game title was cut at "ESL Pro…".
  const longTitle = 'Counter-Strike: PARIVISION vs Natus Vincere (BO3) - '
      'ESL Pro League Season 22';
  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
          'at ${width.toInt()} wide and text x$scale a long title shrinks to '
          'fit its two lines, whole', (tester) async {
        await loadInter(tester);
        await http.runWithClient(() async {
          await pumpRace(tester,
              width: width, title: longTitle, textScale: scale);
          final text = find.descendant(
              of: find.byKey(const ValueKey('poly-detail-title')),
              matching: find.byType(Text));
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final size = tester.widget<Text>(text).style!.fontSize!;
          // The header's 18.sp at this width.
          final base = 18 * width / 430;
          expect(size, lessThan(base), reason: 'it had to shrink');
          // Never drawn under 70% of the standard size.
          expect(size * scale, greaterThanOrEqualTo(base * 0.7 - 0.01));
          expect(tester.widget<Text>(text).data, longTitle);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => MockClient((_) async => http.Response('{}', 404)));
      });
    }
  }

  for (final width in [320.0, 430.0]) {
    testWidgets('at ${width.toInt()} wide: close, image, title and star in '
        'the header (no Sal button); the leader\'s chance with Sal\'s '
        'question under it; no market count, change row or end date',
        (tester) async {
      await loadInter(tester);
      await http.runWithClient(() async {
        await pumpRace(tester, width: width);
        final close = find.byType(KuteCloseButton);
        final header = find.ancestor(of: close, matching: find.byType(Row)).first;
        final title = find.byKey(const ValueKey('poly-detail-title'));
        expect(find.descendant(of: header, matching: title), findsOneWidget);
        final titleText =
            find.descendant(of: title, matching: find.byType(Text));
        expect(tester.widget<Text>(titleText).maxLines, 2);
        final star = find.descendant(
            of: header, matching: find.byType(PolyWatchStar));
        expect(star, findsOneWidget);
        expect(tester.getRect(star).left,
            greaterThanOrEqualTo(tester.getRect(title).right));
        expect(find.byType(AskSalChip), findsNothing);
        expect(find.byKey(const ValueKey('ask-sal-pill')), findsNothing);
        // Gone: the market count line, the change / LIVE row, the end date.
        expect(find.textContaining('Tap a market'), findsNothing);
        expect(find.textContaining('markets ·'), findsNothing);
        expect(find.text('Ends in'), findsNothing);
        expect(find.byType(HlLiveDot), findsNothing);
        expect(find.textContaining(RegExp(r'% past \d')), findsNothing);
        // The hero: the leader's chance, the capsule right under it.
        final figure = find.text('18%');
        expect(figure, findsWidgets);
        expect(capsule, findsOneWidget);
        expect(tester.getRect(capsule).top,
            greaterThan(tester.getRect(figure.first).bottom));
        expect(tester.getRect(capsule).width,
            moreOrLessEquals(width - 40.w, epsilon: 1));
        final top = AskSalChip.topQuestion(tester.element(capsule),
            const AdvisorContext(
                surface: 'polymarket_market_detail',
                marketVenue: 'polymarket',
                marketId: 'next-leader'),
            salSignalsForPolyEvent(race()))!;
        expect(tester.widget<Text>(capsuleText).data, top.text);
        expect(find.descendant(of: capsule, matching: find.byType(KuteDogGlance)),
            findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(capsuleText)
            .didExceedMaxLines, isFalse);
        expect(lines(tester, top.text), lessThanOrEqualTo(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  for (final locale in ['de', 'fi', 'pt', 'hu', 'el']) {
    testWidgets('in $locale at 320 wide the question shows whole, in at most '
        'two lines', (tester) async {
      await loadInter(tester);
      await http.runWithClient(() async {
        await pumpRace(tester, width: 320, locale: Locale(locale));
        expect(capsule, findsOneWidget);
        final text = tester.widget<Text>(capsuleText).data!;
        expect(tester.renderObject<RenderParagraph>(capsuleText)
            .didExceedMaxLines, isFalse);
        expect(lines(tester, text), lessThanOrEqualTo(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  testWidgets('a tap on the capsule opens Sal asking its question, from '
      'market_capsule', (tester) async {
    OpenOnce.reset();
    addTearDown(OpenOnce.reset);
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final prompts = <AdvisorPrompt?>[];
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    await http.runWithClient(() async {
      await pumpRace(tester, extra: [
        advisorStreamRequestProvider.overrideWithValue((
            {required query,
            context,
            history = const [],
            required cancellation,
            locale,
            prompt}) {
          prompts.add(prompt);
          return Stream.value(const AdvisorStreamEvent.done(
              AdvisorResponse(blocks: [
            AdvisorBlock(
                id: 'answer',
                kind: AdvisorBlockKind.answer,
                markdown: 'The race is wide open.')
          ])));
        }),
      ]);
      final question = tester.widget<Text>(capsuleText).data!;
      await tester.tap(capsule);
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(prompts, hasLength(1));
      expect(find.textContaining('The race is wide open.'), findsOneWidget);
      expect(find.text(question), findsWidgets);
      final opened = events.firstWhere((e) => e.$1 == 'sal_opened').$2!;
      expect(opened['entry'], 'market_capsule');
      expect(opened['surface'], 'polymarket_market_detail');
      final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
      expect(asked['input'], 'suggested');
      expect(asked['template'], prompts.single?.template);
      expect(asked['chip_index'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('Sal switched off: no capsule, the hero stays', (tester) async {
    await http.runWithClient(() async {
      await pumpRace(tester, extra: [
        aiEnabledProvider.overrideWith((ref) async => false),
      ]);
      expect(capsule, findsNothing);
      expect(find.text('18%'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
