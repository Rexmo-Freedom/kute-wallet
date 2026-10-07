// Semantic labels for a Polymarket binary / sub-market's two sides,
// derived from its name. "Yes/No" is meaningless on sports legs, so we
// translate to what the two sides actually are:
//
//   Over/Under (totals, props)      → OVER / UNDER
//   Up/Down (hourly crypto)         → UP / DOWN
//   Odd/Even                        → ODD / EVEN
//   Handicap "A (±n) vs B (±n)"     → "A ±n" / "B ±n"
//   Spread "Spread: Team (±n)"      → "Team ±n" / "Team ∓n"
//   Moneyline "Team A vs Team B"    → "Team A" / "Team B"
//   anything else                   → YES / NO
//
// Returns ('YES','NO') for the default so callers can cheaply detect
// "no semantic shape matched" and fall back to raw outcome names.

/// Coarse market-type classification for analytics — never carries
/// amounts/ids, just a structural label of a public market name. Buckets:
/// over_under / up_down / odd_even / spread / moneyline / yes_no / other.
String polymarketMarketType(String name, {String? outcome}) {
  final raw = name.trim();
  if (RegExp(r'(?:O\s*/\s*U|Over\s*/\s*Under|\bOver\b)', caseSensitive: false)
          .hasMatch(raw) &&
      RegExp(r'\d').hasMatch(raw)) {
    return 'over_under';
  }
  if (RegExp(r'\bup\b.*\bdown\b|\bdown\b.*\bup\b|up\s*or\s*down',
          caseSensitive: false)
      .hasMatch(raw)) {
    return 'up_down';
  }
  if (RegExp(r'\bodd\b.*\beven\b|\beven\b.*\bodd\b|odd\s*/\s*even',
          caseSensitive: false)
      .hasMatch(raw)) {
    return 'odd_even';
  }
  if (RegExp(r'spread:?', caseSensitive: false).hasMatch(raw) ||
      RegExp(r'\([+-]\s*\d').hasMatch(raw)) {
    return 'spread';
  }
  if (RegExp(r'\svs\.?\s', caseSensitive: false).hasMatch(raw)) {
    return 'moneyline';
  }
  final o = (outcome ?? '').trim().toLowerCase();
  if (o == 'yes' || o == 'no') return 'yes_no';
  return 'other';
}

({String pos, String neg}) polymarketSideLabels(String name) {
  final raw = name.trim();
  if (raw.isEmpty) return (pos: 'YES', neg: 'NO');
  // The draw of a three-way match, which Gamma names after the match
  // ("Draw (Leeds United FC vs. Manchester United FC)"), is a plain
  // Yes / No question: the teams in its brackets are not its two sides.
  if (RegExp(r'^(draw|tie)\b', caseSensitive: false).hasMatch(raw)) {
    return (pos: 'YES', neg: 'NO');
  }

  // Over/Under — needs the word/marker AND a number (line).
  if (RegExp(r'(?:O\s*/\s*U|Over\s*/\s*Under|\bOver\b)', caseSensitive: false)
          .hasMatch(raw) &&
      RegExp(r'\d').hasMatch(raw)) {
    return (pos: 'OVER', neg: 'UNDER');
  }
  // Up/Down.
  if (RegExp(r'\bup\b.*\bdown\b|\bdown\b.*\bup\b|up\s*or\s*down',
          caseSensitive: false)
      .hasMatch(raw)) {
    return (pos: 'UP', neg: 'DOWN');
  }
  // Odd/Even.
  if (RegExp(r'\bodd\b.*\beven\b|\beven\b.*\bodd\b|odd\s*/\s*even',
          caseSensitive: false)
      .hasMatch(raw)) {
    return (pos: 'ODD', neg: 'EVEN');
  }
  // Handicap: "TeamA (±n) vs TeamB (±n)".
  final handicap = RegExp(
    r'^(.+?)\s*\(([+-]?\d+(?:\.\d+)?)\)\s*vs\.?\s*(.+?)\s*\(([+-]?\d+(?:\.\d+)?)\)\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (handicap != null) {
    final a = _shortTeam(handicap.group(1) ?? '');
    final b = _shortTeam(handicap.group(3) ?? '');
    if (a.isNotEmpty && b.isNotEmpty) {
      return (
        pos: '$a ${_line(handicap.group(2) ?? '')}'.trim(),
        neg: '$b ${_line(handicap.group(4) ?? '')}'.trim(),
      );
    }
  }
  // Spread: "Spread: Team (±n)" → the favourite's line vs the opposite
  // line (the standard two-way spread display).
  final spread = RegExp(
    r'spread:?\s*(.+?)\s*\(([+-]?\d+(?:\.\d+)?)\)\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (spread != null) {
    final team = _shortTeam(spread.group(1) ?? '');
    final n = double.tryParse(spread.group(2) ?? '') ?? 0;
    if (team.isNotEmpty) {
      return (pos: '$team ${_fmt(n)}'.trim(), neg: '$team ${_fmt(-n)}'.trim());
    }
  }
  // Moneyline: "Team A vs Team B" (optionally with a trailing descriptor
  // like "… Winner", "… (BO5)", "… - Playoffs").
  final vs =
      RegExp(r'^(.+?)\s+vs\.?\s+(.+?)$', caseSensitive: false).firstMatch(raw);
  if (vs != null) {
    final a = _shortTeam(_stripDescriptor(vs.group(1) ?? ''));
    final b = _shortTeam(_stripDescriptor(vs.group(2) ?? ''));
    if (a.isNotEmpty && b.isNotEmpty) return (pos: a, neg: b);
  }

  return (pos: 'YES', neg: 'NO');
}

/// Index of the "positive" side of a two-outcome market: the side drawn
/// green, with the check or up arrow. Yes, Up and Over are positive
/// wherever they sit; otherwise the first outcome is. Colour and glyph
/// only: what is bought is always the outcome at the selected index.
int polymarketPositiveIndex(List<String> outcomeNames) {
  if (outcomeNames.length != 2) return 0;
  final a = outcomeNames[0].trim().toLowerCase();
  final b = outcomeNames[1].trim().toLowerCase();
  const negatives = {'no', 'down', 'under'};
  const positives = {'yes', 'up', 'over'};
  if (negatives.contains(a) && positives.contains(b)) return 1;
  return 0;
}

/// The label for each outcome of a two-outcome market, in outcome order,
/// or null when the outcomes' own names should be shown.
///
/// [semantic] is the pair the market's title reads as (UP / DOWN, the two
/// teams, OVER / UNDER …), positive side first. A literal Yes/No market
/// takes it by meaning: Yes reads as [semantic].pos, No as [semantic].neg.
/// Any other market's outcomes ARE the sides, so each label is matched to
/// the outcome it names ("UP" to "Up", "Lakers" to "Los Angeles Lakers",
/// "LGC -1.5" to "LGC"), never by position or by "is it called No": a
/// label that cannot be matched to exactly one outcome is not used, and
/// the outcomes' names are shown instead. The label on a side therefore
/// always names the outcome that side buys.
List<String>? polymarketBinarySideLabels(
    List<String> outcomeNames, ({String pos, String neg}) semantic) {
  if (outcomeNames.length != 2) return null;
  if (semantic.pos == 'YES' && semantic.neg == 'NO') return null;
  final names = [for (final n in outcomeNames) n.trim().toLowerCase()];
  if (names.toSet().containsAll(const {'yes', 'no'})) {
    return [
      for (final n in names) n == 'yes' ? semantic.pos : semantic.neg,
    ];
  }
  final posAt = _matchingOutcomes(semantic.pos, names);
  final negAt = _matchingOutcomes(semantic.neg, names);
  if (posAt.length != 1 || negAt.length != 1 || posAt.first == negAt.first) {
    return null;
  }
  final labels = ['', ''];
  labels[posAt.first] = semantic.pos;
  labels[negAt.first] = semantic.neg;
  return labels;
}

/// Indexes of the outcomes [label] names: the same words, or one inside
/// the other on word boundaries, a trailing line ("+1.5") ignored.
List<int> _matchingOutcomes(String label, List<String> names) {
  final core = label
      .toLowerCase()
      .replaceFirst(RegExp(r'\s*[+\-−]?\d+(?:\.\d+)?\s*$'), '')
      .trim();
  if (core.isEmpty) return const [];
  bool within(String needle, String hay) =>
      RegExp('(^|\\W)${RegExp.escape(needle)}(\\W|\$)').hasMatch(hay);
  return [
    for (var i = 0; i < names.length; i++)
      if (names[i].isNotEmpty &&
          (names[i] == core ||
              within(core, names[i]) ||
              within(names[i], core)))
        i,
  ];
}

/// What a side's disc shows. A check and a cross say yes and no, so only a
/// literal Yes/No side gets them; up and down sides (Up/Down, Over/Under)
/// get arrows, and every other side (a team, a candidate) a neutral glyph.
enum PolymarketSideGlyph { yes, no, up, down, neutral }

PolymarketSideGlyph polymarketSideGlyph(String label) {
  final l = label.trim().toLowerCase();
  if (l == 'yes') return PolymarketSideGlyph.yes;
  if (l == 'no') return PolymarketSideGlyph.no;
  final word = l.split(RegExp(r'\s+')).first;
  if (const {'up', 'over', 'higher', 'above'}.contains(word)) {
    return PolymarketSideGlyph.up;
  }
  if (const {'down', 'under', 'lower', 'below'}.contains(word)) {
    return PolymarketSideGlyph.down;
  }
  return PolymarketSideGlyph.neutral;
}

/// Strip a trailing market descriptor a sub-market name often carries after
/// the team(s): "Aurora Winner" → "Aurora", "Legacy (BO5) - Playoffs" →
/// "Legacy", "Team A: Map 1" → "Team A".
String _stripDescriptor(String s) {
  var r = s.trim();
  // Cut at the first separator that introduces a descriptor clause.
  r = r.split(RegExp(r'\s*[-:(]\s*')).first.trim();
  // Drop trailing market-type words.
  r = r
      .replaceFirst(
          RegExp(r'\s+(winner|to\s+win|match|series|moneyline|map\s*\d*)$',
              caseSensitive: false),
          '')
      .trim();
  return r;
}

/// Signed-line formatter for a raw numeric string ("1.5" → "+1.5").
String _line(String raw) {
  final n = double.tryParse(raw.trim());
  if (n == null) return raw.trim();
  return _fmt(n);
}

String _fmt(double n) {
  final s = n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  return n >= 0 ? '+$s' : s; // negatives already carry '-'
}

/// Team nickname for button labels — "Cleveland Guardians" → "Guardians",
/// "BetBoom Team" → "BetBoom", "Team Spirit" → "Spirit", keeping two-word
/// nicknames (Red Sox, Blue Jays) intact.
String _shortTeam(String name) {
  var s = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return s;
  // Strip an org/franchise tag at either end so it doesn't become the
  // nickname ("BetBoom Team" → "BetBoom", "Team Falcons" → "Falcons").
  s = s.replaceFirst(RegExp(r'^team\s+', caseSensitive: false), '');
  s = s
      .replaceFirst(
          RegExp(r'\s+(team|esports|gaming|fc|cf|sc|club)$',
              caseSensitive: false),
          '')
      .trim();
  if (s.isEmpty) return name.trim();
  final words = s.split(' ');
  if (words.length >= 2) {
    final last = words.last.toLowerCase();
    if (const {'sox', 'jays'}.contains(last)) {
      return words.sublist(words.length - 2).join(' ');
    }
    return words.last;
  }
  return s;
}
