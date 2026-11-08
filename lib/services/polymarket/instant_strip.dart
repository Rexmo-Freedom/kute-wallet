// lib/services/polymarket/instant_strip.dart
//
// The window strip of the Instant screen's card (founder, 8 November 2026:
// "can't we select a 'next one' directly? instead of voting on the current
// one?"): the last few rounds of the asset as result dots, the round in
// play ("Now · 1:49"), the next ("Next · 7:20") and one after, and WHICH
// of them the one pair of Up and Down buttons bets on. Pure: the card
// passes the clock, Gamma's reads and the books in.
//
// Rules:
//   * Rounds start on every multiple of their length on the clock
//     ([polyRoundStartAt]); the strip is arithmetic, no list read.
//   * The buttons follow the roll by default (crypto_next_round.dart: this
//     round while early, the next once it has real prices and this one is
//     two minutes old; five-minute rounds only). A tap on a round overrides
//     that until the round starts (a later one) or ends (the one in play).
//   * Only a round with REAL live prices can be picked: the one in play
//     (its card is live), or a round ahead that Gamma lists as taking
//     orders with a two-sided book no wider than 10¢ on both tokens
//     ([polyNextRoundOpen], [polyRoundBookIsReal]). The others show "No
//     prices yet" and take no tap. Past rounds are results, not choices.

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

  /// Whether the buttons can bet on it (see the file header).
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

  PolyStripRound copyWith({bool? selectable, bool? held, Btc5MinEvent? event}) =>
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
/// play, then [kPolyStripAhead] ahead. [ahead] are Gamma's reads of those
/// rounds by start (null where nothing answered yet) and [books] the feed's
/// current books by token. [heldSlugs] are the slugs of the rounds the
/// person holds or is buying.
List<PolyStripRound> polyInstantStrip({
  required String asset,
  required int minutes,
  required DateTime now,
  required List<CryptoWindowResult> past,
  required Map<int, Btc5MinEvent?> ahead,
  required PolymarketLiveBook? Function(String token) books,
  Set<String> heldSlugs = const {},
}) {
  final liveStart = polyRoundStartAt(now, minutes);
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
      selectable: true,
      held: held(liveStart),
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
/// stands at [now]: the round in play until it ends, a round ahead until
/// it starts; a past round never.
bool polyInstantPickStands(int picked,
    {required int liveStart, required int minutes, required DateTime now}) {
  final at = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  if (picked == liveStart) return at < liveStart + minutes * 60;
  if (picked > liveStart) return at < picked;
  return false;
}

/// The start of the round the buttons bet on: the person's [picked] while
/// it stands and that round can still be picked ([rounds]), else the roll's
/// [rolledStart] (crypto_next_round.dart) when the strip can pick it, else
/// the round in play.
int polyInstantSelectedStart({
  required List<PolyStripRound> rounds,
  required DateTime now,
  int? picked,
  int? rolledStart,
}) {
  final live = rounds.firstWhere((r) => r.slot == PolyRoundSlot.live);
  bool pickable(int start) =>
      rounds.any((r) => r.start == start && r.selectable);
  if (picked != null &&
      pickable(picked) &&
      polyInstantPickStands(picked,
          liveStart: live.start, minutes: live.minutes, now: now)) {
    return picked;
  }
  if (rolledStart != null && pickable(rolledStart)) return rolledStart;
  return live.start;
}

/// The `which` value of `predictions_instant_round_picked`: `current`,
/// `next` or `later`.
String polyInstantWhich(PolyStripRound round) => switch (round.slot) {
      PolyRoundSlot.live => 'current',
      PolyRoundSlot.next => 'next',
      _ => 'later',
    };
