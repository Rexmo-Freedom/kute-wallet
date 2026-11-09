// A search that names a Predictions category ("soccer", "nfl", "art",
// "futebol") puts that category first in the results: a row that opens
// the Predictions browse on it. The match is kept apart from the sheet so
// it can be tested without a widget tree.
//
// What is matched, whole and accent-insensitive (never a prefix: "art"
// must not open on "Arts" markets a title holds, and "ten" is not Tennis):
// a topic's name in the app's language and its slug (Culture,
// `pop-culture`), a sport's name and key (Soccer, `soccer`; Combat, `mma`),
// an esports game's name and slug (CS2), a league's name and its Gamma
// `/sports` code (LaLiga, `lal`, when the league list has been read), and
// the English rewrite of a localized name the venue search also runs
// ("futebol" is Soccer; search_aliases.dart). The first match in that
// order wins.

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel, polySubLabel;
import 'package:kute/services/polymarket/search_aliases.dart';

/// The category a query names: the pill, its subcategory key (null for
/// the pill's own list) and the row's name.
class PolyCategoryHit {
  final PolyPill pill;
  final String? sub;
  final String label;

  const PolyCategoryHit(this.pill, {this.sub, required this.label});

  PolyBrowseSelection get selection {
    final s = PolyBrowseSelection(pill: pill);
    return sub == null ? s : s.copyWith(sub: sub);
  }

  /// The route segment the pick is reported as (`sports/soccer`).
  String get key => sub == null ? pill.key : '${pill.key}/$sub';
}

String _norm(String s) =>
    polySearchFold(s).replaceAll(RegExp(r'[^a-z0-9\p{L}]', unicode: true), '');

/// The category [query] names among [pills] (the ones on offer) and
/// [leagues] (every league Gamma lists, [polySportsLeaguesProvider]); null
/// when it names none.
PolyCategoryHit? polySearchCategoryHit(
  String query,
  AppLocalizations l10n, {
  Iterable<PolyPill> pills = PolyPill.values,
  List<PolySub> leagues = const [],
}) {
  final typed = _norm(query);
  if (typed.isEmpty) return null;
  final alias = polySearchAlias(query);
  final wanted = {typed, if (alias != null) _norm(alias)}..remove('');
  bool hit(Iterable<String> names) =>
      names.any((n) => n.isNotEmpty && wanted.contains(_norm(n)));

  for (final p in pills) {
    if (!p.isTopic) continue;
    if (hit([polyPillLabel(l10n, p), p.key, ...p.tagSlugs])) {
      return PolyCategoryHit(p, label: polyPillLabel(l10n, p));
    }
  }
  if (pills.contains(PolyPill.sports)) {
    for (final sport in kPolySportGroups) {
      final sub = PolySub(sport);
      final name = polySubLabel(l10n, sub);
      if (hit([name, sport])) {
        return PolyCategoryHit(PolyPill.sports, sub: sport, label: name);
      }
    }
  }
  if (pills.contains(PolyPill.esports)) {
    for (final g in kPolyEsportsGames) {
      if (hit([g.label, g.slug, g.sport])) {
        return PolyCategoryHit(PolyPill.esports, sub: g.slug, label: g.label);
      }
    }
  }
  if (pills.contains(PolyPill.sports)) {
    for (final league in leagues) {
      final name = league.label ?? '';
      if (hit([name, league.route])) {
        return PolyCategoryHit(PolyPill.sports,
            sub: league.key, label: name.isEmpty ? league.route : name);
      }
    }
  }
  return null;
}
