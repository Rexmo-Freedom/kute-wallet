// A sport's games by day, as polymarket.com/sports lists them: the games
// in play first, then each day's games in kickoff order under the day's
// heading ("Today", "Tomorrow", then the weekday and date, "Sat, Nov 15",
// in the app's locale), games with no kickoff at the end. The split that
// decides what a game is (a match with teams or a game id; everything else,
// listed after the games, is not) lives here too, so the screen and the
// tests share it.

import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';

/// Whether [e] is a game (a match with teams or a Gamma game id) rather
/// than another market of the sport (a season award, a player total, an
/// outright), which the list shows after the games.
bool polyIsGame(PolymarketEvent e) => e.teams.isNotEmpty || e.gameId != null;

/// [events] split into the games and the other markets, each in the
/// list's own order.
({List<PolymarketEvent> games, List<PolymarketEvent> props}) polySplitGamesProps(
    List<PolymarketEvent> events) {
  final games = <PolymarketEvent>[];
  final props = <PolymarketEvent>[];
  for (final e in events) {
    (polyIsGame(e) ? games : props).add(e);
  }
  return (games: games, props: props);
}

/// Which heading a group of games sits under.
enum PolyGameDayKind { live, today, tomorrow, day, unscheduled }

/// One group of a sport's games: its heading ([kind], and the calendar
/// [day] for [PolyGameDayKind.day]) and its games in kickoff order.
class PolyGameDay {
  final PolyGameDayKind kind;
  final DateTime? day;
  final List<PolymarketEvent> games;

  const PolyGameDay(this.kind, this.games, {this.day});

  /// The heading's words: Live, Today, Tomorrow, the weekday and date in
  /// [locale] (intl's `MMMEd`), or null for games with no kickoff.
  String? label(AppLocalizations l10n, String locale) => switch (kind) {
        PolyGameDayKind.live => l10n.polyPillLive,
        PolyGameDayKind.today => l10n.activityToday,
        PolyGameDayKind.tomorrow => l10n.polyDayTomorrow,
        PolyGameDayKind.day => DateFormat.MMMEd(locale).format(day!),
        PolyGameDayKind.unscheduled => null,
      };
}

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// [games] grouped for the list: the ones in play first (under Live), then
/// each local calendar day from [now]'s on, its games soonest first, and
/// last the games whose kickoff is not known. Days are the device's local
/// days ([now] is local time); kickoffs are read in local time too. A day
/// with no game has no heading.
List<PolyGameDay> polyGameDays(List<PolymarketEvent> games,
    {required DateTime now}) {
  final live = <PolymarketEvent>[];
  final unscheduled = <PolymarketEvent>[];
  final byDay = <DateTime, List<PolymarketEvent>>{};
  for (final g in games) {
    if (g.isInPlay) {
      live.add(g);
      continue;
    }
    final kickoff = g.kickoff?.toLocal();
    if (kickoff == null) {
      unscheduled.add(g);
      continue;
    }
    (byDay[_dateOnly(kickoff)] ??= []).add(g);
  }
  final today = _dateOnly(now);
  final tomorrow = today.add(const Duration(days: 1));
  int byKickoff(PolymarketEvent a, PolymarketEvent b) =>
      a.kickoff!.compareTo(b.kickoff!);
  // A game whose kickoff has passed but is not in play yet (the feed has
  // no score for it) still reads as today's.
  final todays = <PolymarketEvent>[];
  final later = <DateTime>[];
  for (final day in byDay.keys.toList()..sort()) {
    if (day.isAfter(today)) {
      later.add(day);
    } else {
      todays.addAll(byDay[day]!);
    }
  }
  return [
    if (live.isNotEmpty) PolyGameDay(PolyGameDayKind.live, live),
    if (todays.isNotEmpty)
      PolyGameDay(PolyGameDayKind.today, todays..sort(byKickoff), day: today),
    for (final day in later)
      PolyGameDay(
        day == tomorrow ? PolyGameDayKind.tomorrow : PolyGameDayKind.day,
        byDay[day]!..sort(byKickoff),
        day: day,
      ),
    if (unscheduled.isNotEmpty)
      PolyGameDay(PolyGameDayKind.unscheduled, unscheduled),
  ];
}
