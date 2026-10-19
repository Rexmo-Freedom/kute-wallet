// A Predictions position on the Portfolio, in the list card's language:
// a game's two team rows (with the score once it is on) or the market's
// image and its whole title (never cut, running under the figure once past
// it), the position in one line with when the market ends, the value top
// right with the profit or loss under it, one quiet caption.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/combo_position_card.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

/// A live figure on the card (the value, the P&L): it rolls its digits
/// ([RollingNumberText]), so it is found by what it shows.
Finder _rolled(String containing) => find.byWidgetPredicate(
    (w) => w is RollingNumberText && w.text.contains(containing),
    description: 'rolling figure containing "$containing"');

/// The title as the card writes it: one text, or its first lines beside
/// the figure and the rest under it. Never cut.
List<Text> _titleParts(WidgetTester tester, String title) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(PolyPositionCard), matching: find.byType(Text)))
    .where((t) => (t.data ?? '').length > 3 && title.contains(t.data!))
    .toList();

void _expectWholeTitle(WidgetTester tester, String title) {
  final parts = _titleParts(tester, title);
  expect(parts, isNotEmpty);
  expect(parts.map((t) => t.data).join(' '), title);
  for (final t in parts) {
    expect(t.maxLines, isNull);
    expect(t.overflow, isNot(TextOverflow.ellipsis));
  }
}

/// How tall the written title is, all its parts.
double _titleHeight(WidgetTester tester, String title) =>
    _titleParts(tester, title).fold(
        0.0,
        (h, t) =>
            h + tester.getSize(find.byWidget(t)).height);

class _Games extends SportsLiveNotifier {
  _Games(this.games);
  final Map<String, SportsMatchUpdate> games;
  int connects = 0;

  @override
  Map<String, SportsMatchUpdate> build() => games;

  // No socket in a test.
  @override
  void connect() => connects++;
}

final _game = PolymarketEvent(
  id: 'e1',
  slug: 'nfl-sf-den',
  title: '49ers vs. Broncos',
  volume: 1000,
  liquidity: 1000,
  category: 'sports',
  conditionId: 'c1',
  outcomes: const [
    PolymarketOutcome(name: '49ers', price: 0.64, tokenId: 'sf'),
    PolymarketOutcome(name: 'Broncos', price: 0.36, tokenId: 'den'),
  ],
  gameId: 77,
  gameStart: DateTime(2030, 10, 5, 20, 30),
  teams: const [
    PolymarketTeam(name: 'Broncos', abbreviation: 'den', ordering: 'home'),
    PolymarketTeam(name: '49ers', abbreviation: 'sf', ordering: 'away'),
  ],
);

Future<_Games> _pump(
  WidgetTester tester,
  Widget card, {
  PolymarketEvent? event,
  Map<String, SportsMatchUpdate> games = const {},
  String slug = 'nfl-sf-den',
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notifier = _Games(games);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sportsLiveProvider.overrideWith(() => notifier),
      polyPositionEventProvider(slug).overrideWith((ref) => event),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: card,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return notifier;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a market: the whole title, the position with its end in one '
      'line, value over P&L',
      (tester) async {
    const title = 'Will the Fed cut interest rates by more than 25 basis '
        'points at its December meeting this year?';
    var taps = 0;
    await _pump(
      tester,
      PolyPositionCard(
        question: title,
        outcome: 'Yes',
        shares: 120,
        avgPrice: 0.42,
        value: 54.2,
        pnl: 3.8,
        pnlPercent: 7.5,
        end: DateTime(2030, 12, 18),
        onTap: () => taps++,
      ),
    );
    // Written whole, never cut.
    _expectWholeTitle(tester, title);
    // The position in one line under the title, with when it ends (the
    // year written, it is not this one's).
    final line = find.text('Yes · 120 shares at 42¢ · Ends Dec 18, 2030');
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).maxLines, isNull);
    final titleBottom = _titleParts(tester, title)
        .map((t) => tester.getBottomLeft(find.byWidget(t)).dy)
        .reduce((a, b) => a > b ? a : b);
    expect(tester.getTopLeft(line).dy, greaterThan(titleBottom - 1));

    final c = AppColorsExtension.light();
    final pnl = tester.widget<RollingNumberText>(_rolled('(+7.5%)'));
    expect(pnl.text, startsWith('+'));
    expect(pnl.style.color, AppColors.marketUp);
    // The value is the big number, on the right, in the primary colour.
    final value = tester
        .widgetList<RollingNumberText>(find.descendant(
            of: find.byType(PortfolioCardValue),
            matching: find.byType(RollingNumberText)))
        .first;
    expect(value.text, r'$54.20');
    expect(value.style.color, c.textPrimary);
    expect(value.style.fontSize, greaterThan(pnl.style.fontSize!));
    // Top right, level with the title's first line.
    final first = find.byWidget(_titleParts(tester, title).first);
    expect(tester.getTopRight(find.byType(PortfolioCardValue)).dx,
        greaterThan(tester.getTopRight(first).dx));
    expect(
        (tester.getTopLeft(find.byType(PortfolioCardValue)).dy -
                tester.getTopLeft(first).dy)
            .abs(),
        lessThan(4));

    await tester.tap(find.byType(PolyPositionCard));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a loss reads in the down colour with the true minus',
      (tester) async {
    await _pump(
      tester,
      const PolyPositionCard(
        question: 'Will it rain?',
        outcome: 'No',
        shares: 10,
        avgPrice: 0.5,
        value: 4,
        pnl: -1,
        pnlPercent: -20,
      ),
    );
    final pnl = tester.widget<RollingNumberText>(_rolled('(−20.0%)'));
    expect(pnl.text, startsWith('−'));
    expect(pnl.style.color, AppColors.marketDown);
  });

  testWidgets('a game before kickoff: a row per team, kickoff as caption',
      (tester) async {
    final games = await _pump(
      tester,
      const PolyPositionCard(
        question: '49ers vs. Broncos',
        outcome: '49ers',
        shares: 120,
        avgPrice: 0.42,
        value: 60,
        pnl: 9.6,
        pnlPercent: 19,
        eventSlug: 'nfl-sf-den',
      ),
      event: _game,
    );
    expect(find.text('49ers'), findsOneWidget);
    expect(find.text('Broncos'), findsOneWidget);
    // The teams are the rows: the title is not written again.
    expect(find.text('49ers vs. Broncos'), findsNothing);
    expect(find.text('49ers · 120 shares at 42¢'), findsOneWidget);
    // The kickoff, in the shared game-time wording (day word or date).
    expect(find.textContaining('20:30'), findsOneWidget);
    // Kickoff is years away: the live score feed is not joined.
    expect(games.connects, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a game in play: each team\'s score, the clock as caption',
      (tester) async {
    final live = SportsMatchUpdate(
      slug: 'nfl-sf-den',
      gameId: 77,
      live: true,
      ended: false,
      homeTeam: 'den',
      awayTeam: 'sf',
      score: '7-3',
      period: 'Q2',
      elapsed: '10:28',
      updatedAt: DateTime(2030),
    );
    await _pump(
      tester,
      const PolyPositionCard(
        question: 'Spread: 49ers (-4.5)',
        outcome: 'Yes',
        shares: 10,
        avgPrice: 0.5,
        value: 5,
        pnl: 0,
        pnlPercent: 0,
        eventSlug: 'nfl-sf-den',
      ),
      event: _game,
      games: {'nfl-sf-den': live},
    );
    // The feed writes home (Broncos) first; the 49ers are the first row.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(tester.getTopLeft(find.text('3')).dy,
        lessThan(tester.getTopLeft(find.text('7')).dy));
    expect(find.text('Q2 10:28'), findsOneWidget);
    // A market inside the game leads the position line with its question.
    expect(find.text('Spread: 49ers (-4.5) · Yes · 10 shares at 50¢'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a claimable win: its Claim button says so, written once',
      (tester) async {
    var claims = 0;
    await _pump(
      tester,
      PolyPositionCard(
        question: 'Will it rain?',
        outcome: 'Yes',
        shares: 10,
        avgPrice: 0.5,
        value: 10,
        pnl: 5,
        pnlPercent: 100,
        resolved: true,
        claimable: true,
        end: DateTime(2020),
        action: AppButton(
            text: 'Claim', compact: true, onPressed: () => claims++),
      ),
    );
    // The button is the state: no "Ready to claim" caption over it.
    expect(find.text('Ready to claim'), findsNothing);
    await tester.tap(find.byType(AppButton));
    expect(claims, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a claimable win with no button of its own says so',
      (tester) async {
    await _pump(
      tester,
      PolyPositionCard(
        question: 'Will it rain?',
        outcome: 'Yes',
        shares: 10,
        avgPrice: 0.5,
        value: 10,
        pnl: 5,
        pnlPercent: 100,
        resolved: true,
        claimable: true,
        end: DateTime(2020),
      ),
    );
    expect(find.text('Ready to claim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares in hundredths: "2.07 shares at 96¢"', (tester) async {
    await _pump(
      tester,
      PolyPositionCard(
        question: 'Counter-Strike: G2 vs Aurora',
        outcome: 'G2',
        shares: 2.072917,
        avgPrice: 0.96,
        value: 2.07,
        pnl: 0.08,
        pnlPercent: 4,
        end: DateTime(2030, 12, 18),
      ),
    );
    expect(find.text('G2 · 2.07 shares at 96¢ · Ends Dec 18, 2030'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the end date is written in the app\'s language',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: const Locale('pt'),
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PolyPositionCard(
              question: 'Vai chover?',
              outcome: 'Sim',
              shares: 10,
              avgPrice: 0.5,
              value: 5,
              pnl: 0,
              end: DateTime(2030, 12, 18),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Dec 18, 2030'), findsNothing);
    expect(find.textContaining('dez'), findsOneWidget);
    expect(find.textContaining('Sim · 10 unidades a 50¢ · Termina a '),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('ended, result not claimable yet', () {
    // A 5 minute round that ended ten minutes ago (its slug carries its
    // start): past the measured settle window, so the caption falls back to
    // "in a few minutes" (the estimate itself is covered by
    // position_awaiting_estimate_test.dart).
    final start = DateTime.now().toUtc().subtract(const Duration(minutes: 15));
    final slug = 'btc-updown-5m-${start.millisecondsSinceEpoch ~/ 1000}';
    final end = start.add(const Duration(minutes: 5));

    PolyPositionCard round({required double value, DateTime? at}) =>
        PolyPositionCard(
          question: 'Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET',
          outcome: 'Up',
          shares: 4.53,
          avgPrice: 0.66,
          value: value,
          pnl: value - 2.99,
          pnlPercent: (value / 2.99 - 1) * 100,
          eventSlug: slug,
          end: at ?? end,
        );

    testWidgets('a won round: ready to claim in a few minutes, value kept',
        (tester) async {
      await _pump(tester, round(value: 4.53), slug: slug);
      expect(find.text('You won · Ready to claim in a few minutes'),
          findsOneWidget);
      expect(find.text('Ready to claim'), findsNothing);
      expect(_rolled(r'$4.53'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lost round: ended, lost', (tester) async {
      await _pump(tester, round(value: 0), slug: slug);
      expect(find.text('Ended · Lost'), findsOneWidget);
      expect(find.textContaining('Ends'), findsNothing);
      expect(find.text('Up · 4.53 shares at 66¢'), findsOneWidget);
    });

    testWidgets('a round whose price has not settled: result in a few '
        'minutes', (tester) async {
      await _pump(tester, round(value: 2.2), slug: slug);
      expect(find.text('Ended · Result in a few minutes'), findsOneWidget);
    });

    testWidgets('a round still running keeps its end time', (tester) async {
      await _pump(tester,
          round(value: 3, at: DateTime.now().add(const Duration(minutes: 3))),
          slug: slug);
      expect(find.textContaining('Ended'), findsNothing);
      expect(find.textContaining('You won'), findsNothing);
    });

    testWidgets('a finished game: ready to claim soon', (tester) async {
      final over = SportsMatchUpdate(
        slug: 'nfl-sf-den',
        gameId: 77,
        live: false,
        ended: true,
        homeTeam: 'den',
        awayTeam: 'sf',
        score: '17-24',
        period: 'FT',
        updatedAt: DateTime(2030),
      );
      await _pump(
        tester,
        const PolyPositionCard(
          question: '49ers vs. Broncos',
          outcome: '49ers',
          shares: 10,
          avgPrice: 0.5,
          value: 10,
          pnl: 5,
          pnlPercent: 100,
          eventSlug: 'nfl-sf-den',
        ),
        event: _game,
        games: {'nfl-sf-den': over},
      );
      expect(find.text('You won · Ready to claim soon'), findsOneWidget);
      expect(find.text('Final'), findsNothing);
    });

    PolymarketEvent election({bool marketsClosed = false, DateTime? endDate}) =>
        PolymarketEvent(
          id: 'e2',
          slug: 'brazil-presidential-election',
          title: 'Brazil Presidential Election',
          volume: 1000,
          liquidity: 1000,
          category: 'politics',
          conditionId: 'c2',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.87, tokenId: 'y'),
            PolymarketOutcome(name: 'No', price: 0.13, tokenId: 'n'),
          ],
          marketsClosed: marketsClosed,
          endDate: endDate,
        );
    final firstRound = DateTime.now().subtract(const Duration(days: 14));
    PolyPositionCard electionCard() => PolyPositionCard(
          question: 'Will Flávio Bolsonaro win the 2026 Brazilian '
              'presidential election?',
          outcome: 'Yes',
          shares: 5.75,
          avgPrice: 0.87,
          value: 4.99,
          pnl: 0,
          pnlPercent: 0,
          eventSlug: 'brazil-presidential-election',
          // The first-round date Polymarket left on the market, two weeks
          // gone.
          end: firstRound,
        );

    testWidgets('a market past its end date that still trades is not ended',
        (tester) async {
      await _pump(tester, electionCard(),
          event: election(), slug: 'brazil-presidential-election');
      expect(find.textContaining('Ended'), findsNothing);
      expect(find.textContaining('Waiting for the result'), findsNothing);
      // Never the past date, and no event end to show instead.
      expect(find.textContaining('Ends'), findsNothing);
      expect(
          find.textContaining(DateFormat.MMMd('en').format(firstRound)),
          findsNothing);
    });

    testWidgets('a market past its end date that still trades shows the '
        'event\'s later end', (tester) async {
      // The runoff, a week ahead (the event ends 26 Oct 2026, the market
      // kept 5 Oct).
      final runoff = DateTime.now().add(const Duration(days: 7));
      await _pump(tester, electionCard(),
          event: election(endDate: runoff),
          slug: 'brazil-presidential-election');
      final day = DateFormat.MMMd('en').format(runoff);
      expect(find.textContaining('Yes · 5.75 shares at 87¢ · Ends $day'),
          findsOneWidget);
      expect(
          find.textContaining(DateFormat.MMMd('en').format(firstRound)),
          findsNothing);
      expect(find.textContaining('Ended'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a market whose trading stopped waits for the result',
        (tester) async {
      await _pump(tester, electionCard(),
          event: election(marketsClosed: true),
          slug: 'brazil-presidential-election');
      expect(find.text('Ended · Waiting for the result'), findsOneWidget);
      // The state, not a date.
      expect(find.textContaining('Ends'), findsNothing);
    });

    testWidgets('a game past its scheduled end but in play is not ended',
        (tester) async {
      final live = SportsMatchUpdate(
        slug: 'nfl-sf-den',
        gameId: 77,
        live: true,
        ended: false,
        homeTeam: 'den',
        awayTeam: 'sf',
        score: '7-3',
        period: 'Q4',
        elapsed: '01:10',
        updatedAt: DateTime(2030),
      );
      await _pump(
        tester,
        PolyPositionCard(
          question: '49ers vs. Broncos',
          outcome: '49ers',
          shares: 10,
          avgPrice: 0.5,
          value: 9.9,
          pnl: 4.9,
          pnlPercent: 98,
          eventSlug: 'nfl-sf-den',
          end: DateTime(2020),
        ),
        event: _game,
        games: {'nfl-sf-den': live},
      );
      expect(find.textContaining('Ended'), findsNothing);
      expect(find.textContaining('You won'), findsNothing);
    });
  });

  group('a long title is written whole', () {
    const fed = 'Will there be no change in Fed interest rates after the '
        'December 2026 meeting of the Federal Open Market Committee?';
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('375 wide, text at ×$scale: several lines, never cut, '
          'value and P&L kept clear of it', (tester) async {
        await _pump(
          tester,
          PolyPositionCard(
            question: fed,
            outcome: 'Yes',
            shares: 6.49,
            avgPrice: 0.77,
            value: 4.92,
            pnl: -0.07,
            pnlPercent: -1.5,
            end: DateTime(2030, 12, 18),
          ),
          width: 375,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        _expectWholeTitle(tester, fed);
        // Several lines: well over one line's height (16sp, 1.25).
        final line = 16 * (375 / 430) * 1.25 * scale;
        expect(_titleHeight(tester, fed), greaterThan(2.5 * line));

        final value = find.byType(PortfolioCardValue);
        expect(_rolled(r'$4.92'), findsOneWidget);
        expect(_rolled('(−1.5%)'), findsOneWidget);
        final card = tester.getRect(find.byType(PolyPositionCard));
        final figure = tester.getRect(value);
        expect(card.contains(figure.topLeft), isTrue);
        expect(card.contains(figure.bottomRight - const Offset(1, 1)),
            isTrue);
        for (final part in _titleParts(tester, fed)) {
          expect(
              tester.getRect(find.byWidget(part)).deflate(0.5).overlaps(
                  figure.deflate(0.5)),
              isFalse);
        }
        // The position line wraps rather than cut.
        final meta = find.text('Yes · 6.49 shares at 77¢ · Ends Dec 18, 2030');
        expect(meta, findsOneWidget);
        expect(tester.widget<Text>(meta).maxLines, isNull);
      });
    }

    testWidgets('its first lines beside the figure, the rest under it to '
        'the card\'s edge', (tester) async {
      // Short words (the test font writes every letter a full em wide).
      const title = 'Will the Fed hold its rates at the next two meetings '
          'and then cut them at the one after that, or not at all?';
      await _pump(
        tester,
        PolyPositionCard(
          question: title,
          outcome: 'Yes',
          shares: 6.49,
          avgPrice: 0.77,
          value: 4.92,
          pnl: -0.07,
          pnlPercent: -1.5,
          end: DateTime(2030, 12, 18),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      _expectWholeTitle(tester, title);
      final parts = _titleParts(tester, title);
      expect(parts, hasLength(2));
      final beside = tester.getRect(find.byWidget(parts[0]));
      final under = tester.getRect(find.byWidget(parts[1]));
      final figure = tester.getRect(find.byType(PortfolioCardValue));
      // Level: the figure's top with the title's first line.
      expect((figure.top - beside.top).abs(), lessThan(4));
      expect(beside.right, lessThanOrEqualTo(figure.left));
      // The rest starts where the title starts, under the figure, and runs
      // past the figure's left edge.
      expect(under.left, beside.left);
      expect(under.top, greaterThanOrEqualTo(figure.bottom - 1));
      expect(under.right, greaterThan(figure.left));
    });

    testWidgets('a short title stays beside the figure on one text',
        (tester) async {
      await _pump(
        tester,
        const PolyPositionCard(
          question: 'Will it rain?',
          outcome: 'Yes',
          shares: 10,
          avgPrice: 0.5,
          value: 5,
          pnl: 0,
        ),
        width: 375,
      );
      expect(find.text('Will it rain?'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(PortfolioCardValue)).dy,
          lessThan(tester.getBottomLeft(find.text('Will it rain?')).dy));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a narrow phone at large text: nothing overflows',
      (tester) async {
    await _pump(
      tester,
      const PolyPositionCard(
        question: 'Will the Golden State Warriors win the 2030 NBA Finals '
            'after trailing in the conference semifinals?',
        outcome: 'Golden State Warriors',
        shares: 12345.6,
        avgPrice: 0.42,
        value: 123456.78,
        pnl: -23456.78,
        pnlPercent: -123.4,
      ),
      width: 320,
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
    _expectWholeTitle(
        tester,
        'Will the Golden State Warriors win the 2030 NBA Finals '
        'after trailing in the conference semifinals?');
  });

  testWidgets('a combo: the same frame, an estimate labelled as one, each '
      'leg written once', (tester) async {
    ComboLeg leg(int i, String title, String status) => ComboLeg(
          index: i,
          positionId: 'p\$i',
          outcomeIndex: 0,
          outcomeLabel: 'Yes',
          status: status,
          currentPrice: status == 'RESOLVED_WIN' ? 1 : 0.5,
          title: title,
          question: title,
        );
    await _pump(
      tester,
      ComboPositionCard(
        position: ComboPosition(
          conditionId: 'c',
          positionId: '1',
          outcomeIndex: 0,
          shares: 40,
          entryAvgPrice: 0.25,
          stakeUsd: 10,
          entryFeesUsd: 0,
          realizedPayoutUsd: 0,
          status: 'OPEN',
          redeemable: false,
          legsTotal: 2,
          legsResolved: 1,
          legsPending: 1,
          legs: [
            leg(0, 'Porto win the league', 'RESOLVED_WIN'),
            leg(1, 'Benfica reach the cup final', 'OPEN'),
          ],
        ),
      ),
      width: 320,
    );
    expect(find.byType(PortfolioCardFrame), findsOneWidget);
    expect(find.byType(PortfolioCardValue), findsOneWidget);
    expect(find.text('Combo · 2 legs'), findsOneWidget);
    expect(find.text('Est. value'), findsOneWidget);
    expect(find.text('Porto win the league'), findsOneWidget);
    expect(find.text('Benfica reach the cup final'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
