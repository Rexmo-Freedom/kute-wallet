// A sport's list as polymarket.com/sports shows it: the matches apart from
// the Props markets, the matches by day in kickoff order under Live,
// Today, Tomorrow and the weekday and date.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_game_days.dart';

PolymarketEvent _event(
  String id, {
  List<PolymarketTeam> teams = const [],
  int? gameId,
  DateTime? startTime,
  DateTime? gameStart,
  String? score,
  String? period,
}) =>
    PolymarketEvent(
      id: id,
      slug: id,
      title: id,
      volume: 1,
      liquidity: 1,
      category: 'sports',
      conditionId: id,
      outcomes: const [
        PolymarketOutcome(name: 'A', price: 0.5),
        PolymarketOutcome(name: 'B', price: 0.5),
      ],
      teams: teams,
      gameId: gameId,
      startTime: startTime,
      gameStart: gameStart,
      score: score,
      period: period,
    );

const _teams = [PolymarketTeam(name: 'Home'), PolymarketTeam(name: 'Away')];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // In the app the Material localizations load intl's date symbols.
  setUpAll(() => initializeDateFormatting('en'));

  test('Games are matches (teams or a game id); Props is the rest', () {
    final match = _event('match', teams: _teams);
    final byId = _event('by-id', gameId: 7);
    final award = _event('mvp');
    final total = _event('passing-yards');
    expect(polyIsGame(match), isTrue);
    expect(polyIsGame(byId), isTrue);
    expect(polyIsGame(award), isFalse);
    final split = polySplitGamesProps([award, match, total, byId]);
    expect(split.games.map((e) => e.id), ['match', 'by-id']);
    expect(split.props.map((e) => e.id), ['mvp', 'passing-yards']);
  });

  test('by day in kickoff order: Live, Today, Tomorrow, then the date', () {
    // A fixed clock: Sunday 8 November 2026, 15:00 local time.
    final now = DateTime(2026, 11, 8, 15);
    final games = [
      _event('sat', teams: _teams, startTime: DateTime(2026, 11, 14, 20)),
      _event('tomorrow-late',
          teams: _teams, startTime: DateTime(2026, 11, 9, 21)),
      _event('today-later', teams: _teams, startTime: DateTime(2026, 11, 8, 20)),
      _event('in-play',
          teams: _teams,
          startTime: DateTime(2026, 11, 8, 14),
          score: '1-0',
          period: '2H'),
      _event('today-earlier',
          teams: _teams, startTime: DateTime(2026, 11, 8, 17, 30)),
      _event('tomorrow-early',
          teams: _teams, startTime: DateTime(2026, 11, 9, 12)),
      // Kicked off this morning, no score yet: still today's.
      _event('today-started', teams: _teams, startTime: DateTime(2026, 11, 8, 11)),
      // A kickoff known only from the market (`gameStartTime`).
      _event('fri', teams: _teams, gameStart: DateTime(2026, 11, 13, 19)),
      _event('no-kickoff', teams: _teams),
    ];
    final days = polyGameDays(games, now: now);
    expect([for (final d in days) d.kind], [
      PolyGameDayKind.live,
      PolyGameDayKind.today,
      PolyGameDayKind.tomorrow,
      PolyGameDayKind.day,
      PolyGameDayKind.day,
      PolyGameDayKind.unscheduled,
    ]);
    expect([
      for (final d in days) [for (final g in d.games) g.id]
    ], [
      ['in-play'],
      ['today-started', 'today-earlier', 'today-later'],
      ['tomorrow-early', 'tomorrow-late'],
      ['fri'],
      ['sat'],
      ['no-kickoff'],
    ]);
    expect(days[1].day, DateTime(2026, 11, 8));
    expect(days[3].day, DateTime(2026, 11, 13));
    expect(days[4].day, DateTime(2026, 11, 14));
  });

  test('a day with no game has no heading; nothing in play, no Live', () {
    final now = DateTime(2026, 11, 8, 15);
    final days = polyGameDays([
      _event('sat', teams: _teams, startTime: DateTime(2026, 11, 14, 20)),
      _event('tomorrow', teams: _teams, startTime: DateTime(2026, 11, 9, 12)),
    ], now: now);
    expect([for (final d in days) d.kind],
        [PolyGameDayKind.tomorrow, PolyGameDayKind.day]);
    expect(polyGameDays(const [], now: now), isEmpty);
  });

  test('the headings read Live, Today, Tomorrow, then the weekday and date',
      () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final now = DateTime(2026, 11, 8, 15);
    final days = polyGameDays([
      _event('in-play', teams: _teams, score: '0-0', period: '1H'),
      _event('today', teams: _teams, startTime: DateTime(2026, 11, 8, 20)),
      _event('tomorrow', teams: _teams, startTime: DateTime(2026, 11, 9, 12)),
      _event('sat', teams: _teams, startTime: DateTime(2026, 11, 14, 20)),
      _event('no-kickoff', teams: _teams),
    ], now: now);
    expect([for (final d in days) d.label(l10n, 'en')],
        ['Live', 'Today', 'Tomorrow', 'Sat, Nov 14', null]);
  });
}
