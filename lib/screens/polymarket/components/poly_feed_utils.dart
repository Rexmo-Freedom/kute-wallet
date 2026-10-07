import 'package:kute/models/polymarket_model.dart';

/// The base game event ("Netherlands vs. Japan") rather than a sub-market
/// fragment ("... - More Markets" / "... - Exact Score").
bool isPrimaryGameEvent(PolymarketEvent e) => !e.title.contains(' - ');

/// Collapse sibling sports events of the SAME game (shared `gameId`) into a
/// single feed entry — the base "Team vs Team" moneyline event, not the
/// "- More Markets" / "- Exact Score" / "- Halftime Result" fragments.
/// Outright/tournament markets have a null `gameId` and pass through
/// untouched (so "World Cup Winner" etc. are never swallowed).
///
/// Shared by the main Predictions feed and the group/series landing pages
/// so per-gameId de-dupe behaves identically everywhere.
List<PolymarketEvent> collapseByGameId(List<PolymarketEvent> events) {
  final primaryByGame = <int, int>{}; // gameId -> index in result
  final result = <PolymarketEvent>[];
  for (final e in events) {
    final gid = e.gameId;
    if (gid == null) {
      result.add(e);
      continue;
    }
    final existingIdx = primaryByGame[gid];
    if (existingIdx == null) {
      primaryByGame[gid] = result.length;
      result.add(e);
    } else if (isPrimaryGameEvent(e) &&
        !isPrimaryGameEvent(result[existingIdx])) {
      // Upgrade the kept entry to the base moneyline event, in place.
      result[existingIdx] = e;
    }
    // else: drop the sibling fragment.
  }
  return result;
}


/// Groups every event by its `gameId`, returning ONLY the games that have more
/// than one sibling market (moneyline + "More Markets" + "Both Teams to Score"
/// + O/U + corners …). Each value is the FULL ordered sibling set with the
/// primary moneyline event first, so a collapsed match card can offer a
/// "+N more markets" affordance that opens the whole set — the siblings
/// `collapseByGameId` otherwise discards from view (FIX: sub-event
/// organization). Games with a single market (and all null-`gameId` outrights)
/// are omitted, so callers only surface the affordance when there's genuinely
/// more to show.
Map<int, List<PolymarketEvent>> siblingsByGameId(
    List<PolymarketEvent> events) {
  final byGame = <int, List<PolymarketEvent>>{};
  for (final e in events) {
    final gid = e.gameId;
    if (gid == null) continue;
    (byGame[gid] ??= <PolymarketEvent>[]).add(e);
  }
  final grouped = <int, List<PolymarketEvent>>{};
  byGame.forEach((gid, list) {
    if (list.length < 2) return;
    // Primary moneyline event leads; sibling fragments follow in arrival order.
    final ordered = [
      ...list.where(isPrimaryGameEvent),
      ...list.where((e) => !isPrimaryGameEvent(e)),
    ];
    grouped[gid] = ordered;
  });
  return grouped;
}
