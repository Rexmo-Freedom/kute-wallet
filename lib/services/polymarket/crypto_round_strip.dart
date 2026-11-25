// lib/services/polymarket/crypto_round_strip.dart
//
// The window strip of the live crypto round card (Predictions › Crypto ›
// 5 Min and every card of one asset's rounds, CryptoPredictBanner in
// polymarket_screen.dart; founder, 8 November 2026: "can't we select a
// 'next one' directly? instead of voting on the current one?", and again
// on build 2.2.0 (101): "we also don't have the 'next' tab we can choose
// on the bottom"): the last few rounds of the asset as result dots, the
// round in play ("Now · 1:49"), the next ("Next · 7:20") and one after,
// and WHICH of them the one pair of Up and Down buttons bets on. Pure: the
// card passes the clock, Gamma's reads and the books in. Built for the
// Instant card on 8 November 2026 (b180992d), gone with it on 9 November
// and back, unchanged, on the card the rounds open in under Crypto. Gone
// on 12 November 2026 with the next-round-only rule, and back the same day
// for every length (5m, 15m, 1h, 4h) on the card of polymarket.com's own
// round page (founder: "look at how it is on the polymarket website, make
// it better please").
//
// Rules:
//   * Rounds start on every multiple of their length on the New York clock
//     ([polyRoundStartAt]); the strip is arithmetic, no list read.
//   * The buttons follow the roll by default (crypto_next_round.dart: the
//     round in play until its cutoff, two minutes into a five-minute round
//     and 3, 5 and 10 minutes before the end of a 15-minute, hourly and
//     four-hour one; the next round from then on). A tap on a round ahead
//     overrides that until the round starts; a tap on the round in play
//     until its cutoff.
//   * A round can be BET only with REAL live prices: the one in play once
//     Gamma has answered with its event (its card is live) and until its
//     cutoff, or a round ahead that Gamma lists as taking orders with a
//     two-sided book no wider than 10¢ on both tokens ([polyNextRoundOpen],
//     [polyRoundBookIsReal]). A round ahead without them is dimmed; picked
//     (or where the roll lands), the card says "No prices yet" over its
//     disabled buttons. The round in play past its cutoff is dimmed and
//     takes no tap: never back on it. Past rounds are results, not
//     choices.

import 'package:kute/models/polymarket_model.dart' show Btc5MinEvent;
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart'
    show CryptoWindowResult;
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketLiveBook;

/// Where a round of the strip stands against the clock.
enum PolyRoundSlot { past, live, next, later }

/// One round on the strip.
class PolyStripRound {
  const PolyStripRound({
    required this.start,
    required this.minutes,
    required this.slot,
    this.result,
    this.selectable = false,
    this.held = false,
    this.event,
  });

  /// Its start, UTC seconds.
  final int start;
  final int minutes;
  final PolyRoundSlot slot;

  /// A past round's result: Up, Down, or null while it settles.
  final bool? result;

  /// Whether the buttons can bet on it (see the file header): real prices,
  /// and the round in play before its cutoff.
  final bool selectable;

  /// Whether the person holds a side of it (a marker on the strip).
  final bool held;

  /// Gamma's event, when read: its tokens, title and times.
  final Btc5MinEvent? event;

  int get end => start + minutes * 60;
  DateTime get startTime =>
      DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true);
  DateTime get endTime =>
      DateTime.fromMillisecondsSinceEpoch(end * 1000, isUtc: true);

  PolyStripRound copyWith(
          {bool? selectable, bool? held, Btc5MinEvent? event}) =>
      PolyStripRound(
        start: start,
        minutes: minutes,
        slot: slot,
        result: result,
        selectable: selectable ?? this.selectable,
        held: held ?? this.held,
        event: event ?? this.event,
      );
}

/// How many rounds ahead of the one in play the strip shows.
const int kPolyStripAhead = 2;

/// The starts (UTC seconds) of the rounds ahead of [liveStart]: the next
/// and the one after.
List<int> polyStripAheadStarts(int liveStart, int minutes,
        {int ahead = kPolyStripAhead}) =>
    [for (var k = 1; k <= ahead; k++) liveStart + k * minutes * 60];

/// The strip for the [minutes]-long rounds of one asset at [now]: [past]
/// results (oldest first, as the results strip reads them), the round in
/// play, then [kPolyStripAhead] ahead. [live] is Gamma's event of the round
/// in play (null while nothing answered, or when Gamma lists none: then it
/// cannot be picked), [ahead] Gamma's reads of the rounds ahead by start
/// (null where nothing answered yet) and [books] the feed's current books
/// by token. [heldSlugs] are the slugs of the rounds the person holds or
/// is buying. [shownStart] is the start of the round the card shows when it
/// knows it (the card rolls forward a second or two after the clock), else
/// the clock's round.
List<PolyStripRound> polyRoundStrip({
  required String asset,
  required int minutes,
  required DateTime now,
  required List<CryptoWindowResult> past,
  required Btc5MinEvent? live,
  required Map<int, Btc5MinEvent?> ahead,
  required PolymarketLiveBook? Function(String token) books,
  Set<String> heldSlugs = const {},
  int? shownStart,
}) {
  final liveStart = shownStart ?? polyRoundStartAt(now, minutes);
  bool held(int start) =>
      heldSlugs.contains(polyCryptoRoundSlug(asset, minutes, start));
  final rounds = <PolyStripRound>[
    for (final r in past)
      PolyStripRound(
        start: r.startEpoch,
        minutes: minutes,
        slot: PolyRoundSlot.past,
        result: r.up,
        held: held(r.startEpoch),
      ),
    PolyStripRound(
      start: liveStart,
      minutes: minutes,
      slot: PolyRoundSlot.live,
      selectable: live != null &&
          !polyRoundButtonsRolled(
              liveStart: liveStart, minutes: minutes, now: now),
      held: held(liveStart),
      event: live,
    ),
  ];
  var k = 0;
  for (final start in polyStripAheadStarts(liveStart, minutes)) {
    k += 1;
    final event = ahead[start];
    final open =
        event != null && polyNextRoundOpen(event, start: start, now: now);
    final priced = open &&
        polyRoundBookIsReal(books(event.upTokenId!)) &&
        polyRoundBookIsReal(books(event.downTokenId!));
    rounds.add(PolyStripRound(
      start: start,
      minutes: minutes,
      slot: k == 1 ? PolyRoundSlot.next : PolyRoundSlot.later,
      selectable: priced,
      held: held(start),
      event: event,
    ));
  }
  return rounds;
}

/// Whether the person's pick of the round starting at [picked] still
/// stands at [now]: the round in play until its cutoff
/// ([polyRoundButtonsRolled]), a round ahead until it starts; a past round
/// never.
bool polyRoundPickStands(int picked,
    {required int liveStart, required int minutes, required DateTime now}) {
  final at = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  if (picked == liveStart) {
    return !polyRoundButtonsRolled(
        liveStart: liveStart, minutes: minutes, now: now);
  }
  if (picked > liveStart) return at < picked;
  return false;
}

/// The start of the round the buttons bet on: the person's [picked] while
/// it stands (a round ahead is picked with or without prices, the card
/// then says it has none; the round in play only while it takes bets),
/// else the roll's: the round in play until its cutoff, the next round
/// from then on ([polyRoundButtonsRolled]), priced or not.
int polyRoundSelectedStart({
  required List<PolyStripRound> rounds,
  required DateTime now,
  int? picked,
}) {
  final live = rounds.firstWhere((r) => r.slot == PolyRoundSlot.live);
  if (picked != null &&
      rounds.any((r) =>
          r.start == picked &&
          r.slot != PolyRoundSlot.past &&
          (r.slot != PolyRoundSlot.live || r.selectable)) &&
      polyRoundPickStands(picked,
          liveStart: live.start, minutes: live.minutes, now: now)) {
    return picked;
  }
  return polyRoundButtonsRolled(
          liveStart: live.start, minutes: live.minutes, now: now)
      ? live.start + live.minutes * 60
      : live.start;
}

/// The `which` value of `predictions_instant_round_picked` (the event's
/// name from the Instant card, kept so the series runs on): `current`,
/// `next` or `later`.
String polyRoundPickWhich(PolyStripRound round) => switch (round.slot) {
      PolyRoundSlot.live => 'current',
      PolyRoundSlot.next => 'next',
      _ => 'later',
    };
