// Localized names Gamma does not match: "brasil" finds the Copa do Brasil
// and the CR Brasil games but not "Brazil Presidential Election", because
// `public-search` matches the English title (accents it does fold:
// "méxico" finds Mexico). The venue search runs both the query as typed
// and its English rewrite, merged and de-duplicated. The table is small on
// purpose: the country and competition names a Portuguese- or
// Spanish-speaking person types; Gamma handles the rest.

/// Accent-folded, lower-cased [s] with single spaces, for matching.
String polySearchFold(String s) {
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
  const to = 'aaaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Localized name (accent-folded, lower case) → the English name Gamma
/// indexes. Longer phrases are matched first ("estados unidos" whole).
const Map<String, String> kPolySearchAliases = {
  // Portuguese
  'brasil': 'brazil',
  'alemanha': 'germany',
  'espanha': 'spain',
  'inglaterra': 'england',
  'franca': 'france',
  'italia': 'italy',
  'estados unidos': 'united states',
  'eua': 'usa',
  'holanda': 'netherlands',
  'paises baixos': 'netherlands',
  'belgica': 'belgium',
  'suica': 'switzerland',
  'suecia': 'sweden',
  'noruega': 'norway',
  'dinamarca': 'denmark',
  'polonia': 'poland',
  'turquia': 'turkey',
  'grecia': 'greece',
  'irlanda': 'ireland',
  'escocia': 'scotland',
  'ucrania': 'ukraine',
  'irao': 'iran',
  'ira': 'iran',
  'japao': 'japan',
  'coreia': 'korea',
  'africa do sul': 'south africa',
  'uruguai': 'uruguay',
  'paraguai': 'paraguay',
  'equador': 'ecuador',
  'eleicao': 'election',
  'eleicoes': 'elections',
  'presidente': 'president',
  'copa do mundo': 'world cup',
  'futebol': 'soccer',
  // Spanish
  'alemania': 'germany',
  'espana': 'spain',
  'francia': 'france',
  'paises bajos': 'netherlands',
  'suiza': 'switzerland',
  'eleccion': 'election',
  'elecciones': 'elections',
  'mundial': 'world cup',
  'futbol': 'soccer',
};

/// The English rewrite of [query] when a word or phrase in it is a known
/// localized name, else null (the search then runs once, as typed).
/// Matching is accent-insensitive and on whole words; the other words stay
/// as typed ("eleição brasil" → "election brazil").
String? polySearchAlias(String query) {
  final folded = polySearchFold(query);
  if (folded.isEmpty) return null;
  final keys = kPolySearchAliases.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = folded;
  for (final key in keys) {
    final re = RegExp('(?<![a-z0-9])${RegExp.escape(key)}(?![a-z0-9])');
    if (re.hasMatch(out)) out = out.replaceAll(re, kPolySearchAliases[key]!);
  }
  return out == folded ? null : out;
}
