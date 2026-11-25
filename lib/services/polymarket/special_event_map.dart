// lib/services/polymarket/special_event_map.dart
//
// Polymarket's US election shapes that read better drawn than listed. An
// event is one of these by its outcomes' names alone (Gamma
// `groupItemTitle`), never by a tag or a slug, so a new event of the same
// shape is drawn the day it lists:
//
//   * State markets: one Yes / No market per state ("Which states will
//     Donald Trump visit in 2026?": Alabama, Alaska, …). A map of each
//     state's Yes chance; a state opens its own market.
//   * Build your map: one market per combination of states, each naming
//     the states a party wins ("Which Senate Swing States will Republicans
//     win? (Build Your Map)": "AK, IA, KS", "All 7", "None", 128 of them),
//     or a party per state ("Senate Combo: Texas, Michigan, Maine": "Reps
//     sweep", "Reps TX & MI, Dems ME", "Reps MS & SC, Ind MT"). Each
//     state's chance of going each way is every combination's chance
//     added up; picking a way for every state lands on one real market.
//   * Balance of power: one market per way two (or three) races split
//     between the parties ("Balance of Power: 2026 Midterms": "Democrats
//     Sweep", "D Senate, R House", …; "Kansas Senate and Governor Combo":
//     "Dems win Gov, Reps win Senate"; "Who wins Presidency + Popular
//     Vote?"). Each race's chance per party, added up the same way.
//
// Anything else (a sports event, a list that is not states, an "Other"
// catch-all) is null, and the market page lists it as before. Pure:
// tested in test/services/polymarket/special_event_map_test.dart on real
// Gamma events (special_event_fixtures.dart).

import 'package:kute/helpers/us_states.dart';
import 'package:kute/models/polymarket_model.dart';

/// Which way a state or a race goes in one outcome.
enum PolyMapSide {
  rep,
  dem,
  ind,

  /// A "Build your map" state the named party loses (whoever wins it).
  notRep,
  notDem,

  /// A "Build your map" with no party named: the state is in or out.
  yes,
  no,
}

/// A chance as the page shows it (null: none to show).
typedef PolyChanceOf = double? Function(PolymarketOutcome o);

/// A special event, as [polySpecialEventOf] reads it.
sealed class PolySpecialEvent {
  const PolySpecialEvent();

  /// Every outcome the drawing reads a chance of.
  List<PolymarketOutcome> get outcomes;
}

/// One Yes / No market per state.
class PolyStateMarkets extends PolySpecialEvent {
  /// Each state's market by USPS code, in the event's order.
  final Map<String, PolymarketOutcome> byState;

  const PolyStateMarkets(this.byState);

  @override
  List<PolymarketOutcome> get outcomes => byState.values.toList();
}

/// One market of a [PolyStateCombos]: the way it has every state go.
class PolyMapCombo {
  final PolymarketOutcome outcome;
  final Map<String, PolyMapSide> picks;

  const PolyMapCombo(this.outcome, this.picks);
}

/// One market per combination of states ("Build your map").
class PolyStateCombos extends PolySpecialEvent {
  /// The states, USPS codes, in the order the map lists them.
  final List<String> states;

  /// The ways a state can go, in the legend's order.
  final List<PolyMapSide> sides;

  /// The side the summary counts ("Republicans favoured in 5 of 7").
  final PolyMapSide lead;

  final List<PolyMapCombo> combos;

  const PolyStateCombos({
    required this.states,
    required this.sides,
    required this.lead,
    required this.combos,
  });

  @override
  List<PolymarketOutcome> get outcomes => [for (final c in combos) c.outcome];

  /// The ways [state] goes in at least one market, in [sides] order.
  List<PolyMapSide> sidesOf(String state) {
    final seen = {for (final c in combos) c.picks[state]};
    return [for (final s in sides) if (seen.contains(s)) s];
  }

  /// The market that has every state go as [picks]; null when the event
  /// lists none.
  PolyMapCombo? comboFor(Map<String, PolyMapSide> picks) {
    for (final c in combos) {
      if (states.every((s) => c.picks[s] == picks[s])) return c;
    }
    return null;
  }
}

/// One market of a [PolyBalanceOfPower]: the party it gives each race.
class PolyRaceControl {
  final PolymarketOutcome outcome;
  final Map<String, PolyMapSide> control;

  const PolyRaceControl(this.outcome, this.control);
}

/// One market per way the races split between the parties.
class PolyBalanceOfPower extends PolySpecialEvent {
  /// The races ("Senate", "House"), in the event's order.
  final List<String> races;
  final List<PolyRaceControl> cells;

  const PolyBalanceOfPower({required this.races, required this.cells});

  @override
  List<PolymarketOutcome> get outcomes => [for (final c in cells) c.outcome];
}

final Expando<({PolySpecialEvent? special})> _memo = Expando();

/// What special shape [event] is; null for a plain event. Read once per
/// event object.
PolySpecialEvent? polySpecialEventOf(PolymarketEvent event) {
  final known = _memo[event];
  if (known != null) return known.special;
  final special = _read(event);
  _memo[event] = (special: special);
  return special;
}

PolySpecialEvent? _read(PolymarketEvent event) {
  if (event.isBinary || event.isSyntheticBinary) return null;
  // A game's markets are lines and props, never a map ("Texas" is a team).
  if (event.isSportsCategory ||
      event.teams.isNotEmpty ||
      event.gameId != null ||
      event.metadataGameId != null) {
    return null;
  }
  final outcomes = [
    for (final o in event.outcomes)
      if (!_kCatchAll.hasMatch(o.name.trim())) o,
  ];
  if (outcomes.length < 2) return null;
  return _stateSetCombos(event.title, outcomes) ??
      _partyCombos(event.title, outcomes) ??
      _balanceOfPower(outcomes) ??
      _stateMarkets(event.title, outcomes);
}

/// The catch-all a combination event lists beside its combinations.
final RegExp _kCatchAll = RegExp(
    r'^(?:other|another outcome|any other outcome|none of the above)$',
    caseSensitive: false);

PolyMapSide? _partyOf(String word) =>
    switch (word.toLowerCase().replaceAll('.', '')) {
      'r' || 'rep' || 'reps' || 'republican' || 'republicans' || 'gop' =>
        PolyMapSide.rep,
      'd' ||
      'dem' ||
      'dems' ||
      'democrat' ||
      'democrats' ||
      'democratic' =>
        PolyMapSide.dem,
      'i' || 'ind' || 'inds' || 'independent' || 'independents' =>
        PolyMapSide.ind,
      _ => null,
    };

/// The party an event's [title] names ("… will Republicans win?").
PolyMapSide? _titleParty(String title) {
  for (final w in title.split(RegExp(r'[^A-Za-z]+'))) {
    if (w.length < 3) continue; // "R", "D": too short to read in a title
    final p = _partyOf(w);
    if (p != null && p != PolyMapSide.ind) return p;
  }
  return null;
}

final RegExp _kListSplit = RegExp(r'\s*(?:,|&|\band\b)\s*');
final RegExp _kAllStates =
    RegExp(r'^all(?:\s+(\d+))?(?:\s+states)?$', caseSensitive: false);
final RegExp _kNoState = RegExp(r'^(?:none|no states)$', caseSensitive: false);

/// The states a "Build your map" outcome names: a list ("AK, IA, KS"),
/// none ("None") or all of them ("All 7", [count] 7). Null when [name] is
/// anything else.
({Set<String> states, bool all, int? count})? _stateSet(String name) {
  final t = name.trim();
  final all = _kAllStates.firstMatch(t);
  if (all != null) {
    return (
      states: const <String>{},
      all: true,
      count: int.tryParse(all.group(1) ?? ''),
    );
  }
  if (_kNoState.hasMatch(t)) {
    return (states: const <String>{}, all: false, count: null);
  }
  final states = <String>{};
  for (final item in t.split(_kListSplit)) {
    final code = usStateCodeOf(item);
    if (code == null || !states.add(code)) return null;
  }
  return (states: states, all: false, count: null);
}

/// "Build your map" by state lists: every outcome a list of states (or
/// "None" / "All N"), and at least one of them more than a single state,
/// or it is one market per state.
PolyStateCombos? _stateSetCombos(
    String title, List<PolymarketOutcome> outcomes) {
  if (outcomes.length < 4) return null;
  final parsed = <(PolymarketOutcome, ({Set<String> states, bool all, int? count}))>[];
  for (final o in outcomes) {
    final set = _stateSet(o.name);
    if (set == null) return null;
    parsed.add((o, set));
  }
  final universe = {for (final p in parsed) ...p.$2.states};
  if (universe.length < 2) return null;
  final combined =
      parsed.any((p) => p.$2.all || p.$2.states.length != 1);
  if (!combined) return null;
  for (final p in parsed) {
    final n = p.$2.count;
    if (n != null && n != universe.length) return null;
  }
  final lead = _titleParty(title) ?? PolyMapSide.yes;
  final against = switch (lead) {
    PolyMapSide.rep => PolyMapSide.notRep,
    PolyMapSide.dem => PolyMapSide.notDem,
    _ => PolyMapSide.no,
  };
  final states = universe.toList()..sort();
  return PolyStateCombos(
    states: states,
    sides: [lead, against],
    lead: lead,
    combos: [
      for (final (o, set) in parsed)
        PolyMapCombo(o, {
          for (final s in states)
            s: set.all || set.states.contains(s) ? lead : against,
        }),
    ],
  );
}

final RegExp _kSweep = RegExp(
    r'^(\S+)\s+(?:sweep|win\s+both|win\s+all|win\s+everything)$',
    caseSensitive: false);
final RegExp _kClause =
    RegExp(r'^(\S+)\s+(?:wins?\s+)?(.+)$', caseSensitive: false);

/// The party a "sweep" outcome gives every state or race ("Reps sweep",
/// "Democrats win both"); null for anything else.
PolyMapSide? _sweepParty(String name) {
  final m = _kSweep.firstMatch(name.trim());
  return m == null ? null : _partyOf(m.group(1)!);
}

/// "Reps TX & OR, Dems VT" → (rep, TX), (rep, OR), (dem, VT); "D Senate,
/// R House"; "Dems win Gov, Reps win Senate". A clause with no party of
/// its own takes the one before it. Null when a clause names no party
/// and none came before.
List<(PolyMapSide, String)>? _clauses(String name) {
  final out = <(PolyMapSide, String)>[];
  PolyMapSide? party;
  for (final raw in name.split(',')) {
    final clause = raw.trim();
    if (clause.isEmpty) return null;
    final m = _kClause.firstMatch(clause);
    final own = m == null ? null : _partyOf(m.group(1)!);
    final String rest;
    if (own != null) {
      party = own;
      rest = m!.group(2)!;
    } else {
      if (party == null) return null;
      rest = clause;
    }
    for (final item in rest.split(RegExp(r'\s*(?:&|\band\b)\s*'))) {
      if (item.trim().isEmpty) return null;
      out.add((party, item.trim()));
    }
  }
  return out;
}

/// The states a combo's title lists, in its order ("Senate Combo:
/// Mississippi, South Carolina, Montana"); empty when it lists none.
List<String> _titleStates(String title) {
  final colon = title.indexOf(':');
  if (colon < 0) return const [];
  final codes = <String>[];
  for (final item in title.substring(colon + 1).split(_kListSplit)) {
    final code = usStateCodeOf(item.replaceAll(RegExp(r'[?()]'), ''));
    if (code == null) return const [];
    codes.add(code);
  }
  return codes;
}

/// "Build your map" by party per state ("Senate Combo: …").
PolyStateCombos? _partyCombos(String title, List<PolymarketOutcome> outcomes) {
  if (outcomes.length < 3) return null;
  final parsed = <(PolymarketOutcome, Object)>[];
  for (final o in outcomes) {
    final sweep = _sweepParty(o.name);
    if (sweep != null) {
      parsed.add((o, sweep));
      continue;
    }
    final clauses = _clauses(o.name);
    if (clauses == null) return null;
    final picks = <String, PolyMapSide>{};
    for (final (party, item) in clauses) {
      final code = usStateCodeOf(item);
      if (code == null || picks.containsKey(code)) return null;
      picks[code] = party;
    }
    parsed.add((o, picks));
  }
  final mixed = [
    for (final p in parsed)
      if (p.$2 is Map<String, PolyMapSide>) p.$2 as Map<String, PolyMapSide>,
  ];
  if (mixed.isEmpty) return null;
  final seen = <String>[];
  for (final m in mixed) {
    for (final s in m.keys) {
      if (!seen.contains(s)) seen.add(s);
    }
  }
  if (seen.length < 2 || mixed.any((m) => m.length != seen.length)) {
    return null;
  }
  final fromTitle = _titleStates(title);
  final states = fromTitle.length == seen.length &&
          fromTitle.toSet().containsAll(seen)
      ? fromTitle
      : seen;
  final combos = [
    for (final (o, v) in parsed)
      PolyMapCombo(
          o,
          v is PolyMapSide
              ? {for (final s in states) s: v}
              : v as Map<String, PolyMapSide>),
  ];
  final used = {for (final c in combos) ...c.picks.values};
  final sides = [
    for (final s in const [PolyMapSide.rep, PolyMapSide.dem, PolyMapSide.ind])
      if (used.contains(s)) s,
  ];
  if (sides.length < 2) return null;
  return PolyStateCombos(
    states: states,
    sides: sides,
    lead: sides.contains(PolyMapSide.rep) ? PolyMapSide.rep : sides.first,
    combos: combos,
  );
}

/// A race's name as a balance-of-power outcome writes it: words only, and
/// never a state (that is a party combo).
final RegExp _kRaceName = RegExp(r"^[A-Za-z][A-Za-z .'-]{0,24}$");

/// Balance of power: every outcome a sweep or a party per race, two or
/// three races, at least one split.
PolyBalanceOfPower? _balanceOfPower(List<PolymarketOutcome> outcomes) {
  if (outcomes.length < 3) return null;
  final races = <String>[];
  final keys = <String>[];
  final parsed = <(PolymarketOutcome, Object)>[];
  for (final o in outcomes) {
    final sweep = _sweepParty(o.name);
    if (sweep != null) {
      parsed.add((o, sweep));
      continue;
    }
    final clauses = _clauses(o.name);
    if (clauses == null) return null;
    final control = <String, PolyMapSide>{};
    for (final (party, item) in clauses) {
      if (party == PolyMapSide.ind) return null;
      if (!_kRaceName.hasMatch(item) || usStateCodeOf(item) != null) {
        return null;
      }
      final key = item.toLowerCase();
      if (control.containsKey(key)) return null;
      control[key] = party;
      if (!keys.contains(key)) {
        keys.add(key);
        races.add(item);
      }
    }
    parsed.add((o, control));
  }
  final mixed = [
    for (final p in parsed)
      if (p.$2 is Map<String, PolyMapSide>) p.$2 as Map<String, PolyMapSide>,
  ];
  if (mixed.isEmpty || keys.length < 2 || keys.length > 3) return null;
  if (mixed.any((m) => m.length != keys.length)) return null;
  return PolyBalanceOfPower(
    races: races,
    cells: [
      for (final (o, v) in parsed)
        PolyRaceControl(o, {
          for (final (i, k) in keys.indexed)
            races[i]: v is PolyMapSide
                ? v
                : (v as Map<String, PolyMapSide>)[k]!,
        }),
    ],
  );
}

final RegExp _kStatesWord = RegExp(r'\bstates?\b', caseSensitive: false);

/// One market per state: at least three states, four in five outcomes a
/// state, and the title saying "state" unless there are eight or more.
PolyStateMarkets? _stateMarkets(
    String title, List<PolymarketOutcome> outcomes) {
  final byState = <String, PolymarketOutcome>{};
  for (final o in outcomes) {
    final code = usStateCodeOf(o.name);
    if (code != null) byState.putIfAbsent(code, () => o);
  }
  if (byState.length < 3 || byState.length < outcomes.length * 0.8) {
    return null;
  }
  if (byState.length < 8 && !_kStatesWord.hasMatch(title)) return null;
  return PolyStateMarkets(byState);
}

/// Every combination's chance by [chanceOf], none counting nothing.
List<double> _chances(List<PolymarketOutcome> outcomes, PolyChanceOf chanceOf) =>
    [for (final o in outcomes) (chanceOf(o) ?? 0).clamp(0.0, 1.0)];

/// Each state's chance of going each way: the chances of the markets
/// that have it go that way, over the chances of them all (their sum is
/// not exactly 1: the book's spread). Empty while no market has a chance.
Map<String, Map<PolyMapSide, double>> polyComboStateOdds(
    PolyStateCombos map, PolyChanceOf chanceOf) {
  final chances = _chances(map.outcomes, chanceOf);
  final total = chances.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const {};
  final odds = {
    for (final s in map.states) s: {for (final side in map.sidesOf(s)) side: 0.0},
  };
  for (final (i, c) in map.combos.indexed) {
    for (final s in map.states) {
      final side = c.picks[s]!;
      odds[s]![side] = odds[s]![side]! + chances[i] / total;
    }
  }
  return odds;
}

/// Each race's chance per party, as [polyComboStateOdds].
Map<String, Map<PolyMapSide, double>> polyRaceOdds(
    PolyBalanceOfPower balance, PolyChanceOf chanceOf) {
  final chances = _chances(balance.outcomes, chanceOf);
  final total = chances.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const {};
  final odds = <String, Map<PolyMapSide, double>>{
    for (final r in balance.races) r: {},
  };
  for (final (i, c) in balance.cells.indexed) {
    for (final r in balance.races) {
      final party = c.control[r]!;
      odds[r]![party] = (odds[r]![party] ?? 0) + chances[i] / total;
    }
  }
  return odds;
}

/// The market most likely now; null while none has a chance.
PolyMapCombo? polyMostLikelyCombo(PolyStateCombos map, PolyChanceOf chanceOf) {
  PolyMapCombo? best;
  var bestChance = 0.0;
  for (final c in map.combos) {
    final chance = chanceOf(c.outcome);
    if (chance != null && chance > bestChance) {
      best = c;
      bestChance = chance;
    }
  }
  return best;
}

/// The way most likely in [odds] and its chance; null when empty.
({PolyMapSide side, double chance})? polyLeadingSide(
    Map<PolyMapSide, double>? odds) {
  if (odds == null || odds.isEmpty) return null;
  final best = odds.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (side: best.key, chance: best.value);
}

/// How many states of [odds] are more likely than not to go [side].
int polyStatesFavouring(
        Map<String, Map<PolyMapSide, double>> odds, PolyMapSide side) =>
    odds.values.where((o) => (o[side] ?? 0) > 0.5).length;
