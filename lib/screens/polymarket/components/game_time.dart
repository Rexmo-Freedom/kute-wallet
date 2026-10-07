// When a game is played, in the one wording the game's header and its list
// card both use:
//
//   * before kickoff: "Starts in 23 min" within the hour, else "Today 20:30",
//     "Tomorrow 18:00", "Sat 21:00" within the next six days, else
//     "12 Oct 20:30" (never a year);
//   * once over: "Final", or "Final · 4 Oct" when it ended on an earlier day.
//
// Times are the reader's own (their zone, their locale's day and month
// names). Within the hour the countdown moves by the minute
// ([polyMinuteTickProvider]); nothing here ticks by the second.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';

/// How long before kickoff the caption counts down in minutes.
const polyKickoffCountdown = Duration(minutes: 60);

/// A tick every minute, for a caption that counts down to kickoff. Shared,
/// so every card and header on screen refreshes off one timer, and only
/// while something watches it.
final polyMinuteTickProvider = Provider.autoDispose<DateTime>((ref) {
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return DateTime.now();
});

/// Whether the kickoff caption of a game starting at [kickoff] counts down
/// at [now] (and so has to refresh each minute).
bool polyKickoffCountsDown(DateTime? kickoff, DateTime now) {
  if (kickoff == null) return false;
  final left = kickoff.difference(now);
  return left > Duration.zero && left <= polyKickoffCountdown;
}

/// [t] on the reader's wall clock: their own zone, or [utcOffset] from UTC
/// when one is given (tests).
DateTime _wall(DateTime t, Duration? utcOffset) =>
    utcOffset == null ? t.toLocal() : t.toUtc().add(utcOffset);

/// The calendar day of a wall-clock time, as a day count (DST-proof).
int _day(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _capitalised(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "12 Oct" in the reader's locale (no year).
String _dayMonth(AppLocalizations l10n, DateTime wall) =>
    DateFormat('d MMM', l10n.localeName).format(wall);

/// When a game that has not started yet kicks off, as its caption says it:
/// "Starts in 23 min", "Today 20:30", "Tomorrow 18:00", "Sat 21:00",
/// "12 Oct 20:30". A kickoff that has passed with no sign of the game
/// reads by its day and time ("Today 20:30").
String polyKickoffText(
  AppLocalizations l10n,
  DateTime kickoff, {
  required DateTime now,
  Duration? utcOffset,
}) {
  if (polyKickoffCountsDown(kickoff, now)) {
    final seconds = kickoff.difference(now).inSeconds;
    return l10n.polyKickoffStartsInMinutes((seconds / 60).ceil());
  }
  final at = _wall(kickoff, utcOffset);
  final days = _day(at) - _day(_wall(now, utcOffset));
  final time = DateFormat.Hm(l10n.localeName).format(at);
  if (days == 0) return l10n.polyKickoffToday(time);
  if (days == 1) return l10n.polyKickoffTomorrow(time);
  if (days > 1 && days <= 6) {
    return '${_capitalised(DateFormat.E(l10n.localeName).format(at))} $time';
  }
  return '${_dayMonth(l10n, at)} $time';
}

/// A finished game's caption: "Final", or "Final · 4 Oct" when it is known
/// to have ended on a day before today.
String polyFinalText(
  AppLocalizations l10n,
  DateTime? finishedAt, {
  required DateTime now,
  Duration? utcOffset,
}) {
  if (finishedAt == null) return l10n.polyMarkerFinal;
  final at = _wall(finishedAt, utcOffset);
  if (_day(at) >= _day(_wall(now, utcOffset))) return l10n.polyMarkerFinal;
  return l10n.polyMarkerFinalOn(_dayMonth(l10n, at));
}
