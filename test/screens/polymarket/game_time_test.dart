// When a game is played, as its header and its list card say it: the
// kickoff by day ("Today", "Tomorrow", a weekday, a date) in the reader's
// zone, the last hour as a countdown, and "Final" dated when the game
// ended on an earlier day.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/game_time.dart';
import 'package:kute/screens/shared/kute_motion.dart' show ScorePulseText;
import 'package:kute/theme/app_theme.dart';

/// The header's score ([ScorePulseText]: a goal pulses its number), found
/// by the score it shows.
Finder _score(String text) => find.byWidgetPredicate(
    (w) => w is ScorePulseText && w.text == text,
    description: 'score "$text"');

final _en = lookupAppLocalizations(const Locale('en'));
final _pt = lookupAppLocalizations(const Locale('pt'));

const _lisbon = Duration(hours: 1); // WEST, early October
const _newYork = Duration(hours: -4);
const _tokyo = Duration(hours: 9);

PolymarketEvent _event({DateTime? startTime, DateTime? gameStart}) =>
    PolymarketEvent(
      id: 'e1',
      slug: 'nfl-sf-den',
      title: '49ers vs. Broncos',
      volume: 0,
      liquidity: 0,
      category: 'sports',
      conditionId: 'c1',
      outcomes: const [],
      startTime: startTime,
      gameStart: gameStart,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt'));

  // Monday 5 Oct 2026, 13:00 in Lisbon.
  final now = DateTime.utc(2026, 10, 5, 12);
  String kickoff(DateTime at,
          {Duration zone = _lisbon, DateTime? from, AppLocalizations? l10n}) =>
      polyKickoffText(l10n ?? _en, at, now: from ?? now, utcOffset: zone);

  group('kickoff by day', () {
    test('today, tomorrow, a weekday within six days, else a date', () {
      expect(kickoff(DateTime.utc(2026, 10, 5, 19, 30)), 'Today 20:30');
      expect(kickoff(DateTime.utc(2026, 10, 6, 17)), 'Tomorrow 18:00');
      expect(kickoff(DateTime.utc(2026, 10, 10, 20)), 'Sat 21:00');
      // Six days on is still a weekday; seven would repeat today's.
      expect(kickoff(DateTime.utc(2026, 10, 11, 20)), 'Sun 21:00');
      expect(kickoff(DateTime.utc(2026, 10, 12, 19, 30)), '12 Oct 20:30');
      // Never a year, even far out.
      expect(kickoff(DateTime.utc(2027, 1, 3, 20)), '3 Jan 21:00');
    });

    test('the day turns at the reader\'s midnight, not UTC\'s', () {
      // 23:30 in Lisbon; kickoff at 02:00 Lisbon is tomorrow.
      final late = DateTime.utc(2026, 10, 5, 22, 30);
      final at = DateTime.utc(2026, 10, 6, 1);
      expect(kickoff(at, from: late), 'Tomorrow 02:00');
      // The same instants in New York: 18:30, kickoff 21:00 the same day.
      expect(kickoff(at, from: late, zone: _newYork), 'Today 21:00');
      // In Tokyo it is already the 6th: kickoff at 10:00 that day.
      expect(kickoff(at, from: late, zone: _tokyo), 'Today 10:00');
    });

    test('one minute either side of midnight', () {
      final beforeMidnight = DateTime.utc(2026, 10, 5, 22, 59); // 23:59
      expect(kickoff(DateTime.utc(2026, 10, 6, 21), from: beforeMidnight),
          'Tomorrow 22:00');
      final afterMidnight = DateTime.utc(2026, 10, 5, 23, 1); // 00:01 on 6th
      expect(kickoff(DateTime.utc(2026, 10, 6, 21), from: afterMidnight),
          'Today 22:00');
      expect(kickoff(DateTime.utc(2026, 10, 7, 21), from: afterMidnight),
          'Tomorrow 22:00');
    });

    test('a kickoff that has passed with no sign of the game', () {
      expect(kickoff(now.subtract(const Duration(minutes: 5))), 'Today 12:55');
      expect(kickoff(DateTime.utc(2026, 10, 4, 19, 30)), '4 Oct 20:30');
    });

    test('in pt-PT, with the locale\'s day and month names', () {
      expect(kickoff(DateTime.utc(2026, 10, 5, 19, 30), l10n: _pt),
          'Hoje 20:30');
      expect(kickoff(DateTime.utc(2026, 10, 6, 17), l10n: _pt),
          'Amanhã 18:00');
      final weekday = kickoff(DateTime.utc(2026, 10, 10, 20), l10n: _pt);
      expect(weekday, startsWith('Sáb'));
      expect(weekday, endsWith(' 21:00'));
      final date = kickoff(DateTime.utc(2026, 10, 12, 19, 30), l10n: _pt);
      expect(date, startsWith('12 out'));
      expect(date, endsWith(' 20:30'));
    });
  });

  group('the last hour counts down', () {
    test('in whole minutes, rounded up', () {
      expect(kickoff(now.add(const Duration(minutes: 23))), 'Starts in 23 min');
      expect(kickoff(now.add(const Duration(minutes: 22, seconds: 30))),
          'Starts in 23 min');
      expect(kickoff(now.add(const Duration(seconds: 20))), 'Starts in 1 min');
      expect(kickoff(now.add(const Duration(minutes: 60))), 'Starts in 60 min');
      expect(kickoff(now.add(const Duration(minutes: 61))), 'Today 14:01');
      expect(
          kickoff(now.add(const Duration(minutes: 23)), l10n: _pt),
          'Começa dentro de 23 min');
    });

    test('across midnight it still counts down', () {
      final late = DateTime.utc(2026, 10, 5, 22, 50); // 23:50 Lisbon
      expect(kickoff(DateTime.utc(2026, 10, 5, 23, 15), from: late),
          'Starts in 25 min');
    });

    test('only within the hour, and never without a kickoff', () {
      expect(polyKickoffCountsDown(null, now), isFalse);
      expect(polyKickoffCountsDown(now, now), isFalse);
      expect(polyKickoffCountsDown(now.add(const Duration(minutes: 1)), now),
          isTrue);
      expect(polyKickoffCountsDown(now.add(const Duration(minutes: 61)), now),
          isFalse);
    });
  });

  group('final', () {
    test('dated only when the game ended on an earlier day', () {
      String fin(DateTime? at, {Duration zone = _lisbon}) =>
          polyFinalText(_en, at, now: now, utcOffset: zone);
      expect(fin(null), 'Final');
      expect(fin(DateTime.utc(2026, 10, 5, 0, 30)), 'Final');
      expect(fin(DateTime.utc(2026, 10, 4, 21)), 'Final · 4 Oct');
      // 23:30 UTC on the 4th: today in Lisbon (00:30), yesterday in NY.
      final edge = DateTime.utc(2026, 10, 4, 23, 30);
      expect(fin(edge), 'Final');
      expect(fin(edge, zone: _newYork), 'Final · 4 Oct');
      expect(polyFinalText(_pt, DateTime.utc(2026, 10, 4, 21),
              now: now, utcOffset: _lisbon),
          startsWith('Final · 4 out'));
    });
  });

  group('the kickoff an event carries', () {
    final start = DateTime.utc(2026, 10, 5, 19, 30);
    final market = DateTime.utc(2026, 10, 5, 19);
    test('the event\'s own startTime first, then gameStart', () {
      expect(_event(startTime: start, gameStart: market).kickoff, start);
      expect(_event(gameStart: market).kickoff, market);
      expect(_event().kickoff, isNull);
    });
  });

  group('the header', () {
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: child),
          ),
        ),
      ));
      await tester.pump();
    }

    const teams = (
      teamA: '49ers',
      teamB: 'Broncos',
      imageA: null,
      imageB: null,
    );

    testWidgets('before kickoff: the time under the "vs"', (tester) async {
      final at = DateTime.now().add(const Duration(minutes: 23, seconds: 30));
      await pump(tester, PolyGameTeamsHeader(teams: teams, kickoff: at));
      expect(find.text('vs'), findsOneWidget);
      expect(find.text('Starts in 24 min'), findsOneWidget);
      // Off screen, the minute timer stops.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('no kickoff known: the plain "vs"', (tester) async {
      await pump(tester, const PolyGameTeamsHeader(teams: teams));
      expect(find.text('vs'), findsOneWidget);
      expect(find.textContaining('Starts'), findsNothing);
      expect(find.textContaining('Today'), findsNothing);
    });

    testWidgets('live without a clock or a score: "LIVE"', (tester) async {
      await pump(
          tester,
          PolyGameTeamsHeader(
              teams: teams, live: true, kickoff: DateTime.now()));
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.textContaining('Today'), findsNothing);
    });

    testWidgets('live: the score with its clock', (tester) async {
      await pump(
          tester,
          const PolyGameTeamsHeader(
              teams: teams, live: true, scoreText: '1 - 0', statusText: "Q2 4'"));
      expect(_score('1 - 0'), findsOneWidget);
      expect(find.text("Q2 4'"), findsOneWidget);
    });

    testWidgets('over on an earlier day: "Final · <date>"', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await pump(
          tester,
          PolyGameTeamsHeader(
              teams: teams,
              ended: true,
              scoreText: '2 - 1',
              finishedAt: yesterday));
      expect(find.textContaining('Final · '), findsOneWidget);
    });
  });
}
