// The title a Polymarket market is shown under: one rule for the market
// page, the slip and its PIN sheet, the feed and search rows, the share
// cards, the Send flow, positions and activity.
//
// Gamma groups markets that ask one thing for different deadlines, names
// or ranges under one event, and writes the event's title with a blank
// for the part each market fills: "Will Russia invade a NATO country
// by...?" over its markets "... in 2025?", "... by June 30, 2026?" and
// "... by December 31, 2026?". Neither half reads alone (founder, 7
// November 2026: "is the yes or no correct?" under "by...?", and a page
// titled only "December 31, 2026"):
//
//   * a page, slip, card or row about ONE market is titled by that
//     market's own question ("Will Russia invade a NATO country by
//     December 31, 2026?"), and so is an event with one open market
//     left (PolymarketEvent.marketQuestion);
//   * without the question, the event's blank is filled from the
//     market's `groupItemTitle` ("... by December 31, 2026?"); a bare
//     `groupItemTitle` ("December 31, 2026", "Lula da Silva",
//     "100-119") is never a title on its own;
//   * an event that lists several open markets keeps its own title, the
//     blank taken out with the word before it ("Will Russia invade a
//     NATO country?"): its rows name the deadlines.

/// Polymarket's blank in an event title: "...", "…" or "___".
final RegExp _kBlank = RegExp(r'\.{2,}|…|_{2,}');

/// The blank with the little word that leads into it ("by...", "in ...",
/// "above ___"), for taking it out of a title whole.
final RegExp _kLedBlank = RegExp(
  r'(?:\b(?:by|in|on|before|after|at|until|till|through|during|for|of|'
  r'from|to|than|above|below|over|under|between|reach|hit)\s*)?'
  r'(?:\.{2,}|…|_{2,})',
  caseSensitive: false,
);

/// True when [title] carries Polymarket's blank for the part each market
/// of its event fills ("by...?", "in ...?", "...?", "___").
bool polyTitleHasPlaceholder(String title) => _kBlank.hasMatch(title);

/// [s] with its spaces collapsed and none before closing punctuation.
String _tidy(String s) => s
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s+([?!.,:;)])'), (m) => m[1]!)
    .trim();

/// Whether [s] has a letter or a digit: a title, not punctuation left over.
bool _reads(String s) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s);

/// [title]'s first blank filled with [item], any other taken out.
String _filled(String title, String item) {
  final m = _kBlank.firstMatch(title)!;
  final out =
      '${title.substring(0, m.start)} $item ${title.substring(m.end)}';
  return _tidy(out.replaceAll(_kLedBlank, ' '));
}

/// [title] with its blanks and the words that lead into them taken out.
String _stripped(String title) => _tidy(title.replaceAll(_kLedBlank, ' '));

/// The title to show for a Polymarket market (see the file header).
///
/// [eventTitle] is the event's Gamma `title`. [question] is the market's
/// own question, given when the view is about that one market (its page,
/// its slip, its row); [itemTitle] is its `groupItemTitle` (an outcome's
/// name in a grouped event), used to fill the event's blank when there is
/// no question. With neither, the event's own title, its blank taken out.
String polyMarketDisplayTitle(String eventTitle,
    {String? question, String? itemTitle}) {
  final event = _tidy(eventTitle);
  final item = _tidy(itemTitle ?? '');
  final q = _tidy(question ?? '');
  if (q.isNotEmpty) {
    if (!polyTitleHasPlaceholder(q)) return q;
    if (item.isNotEmpty) return _filled(q, item);
  }
  if (polyTitleHasPlaceholder(event)) {
    if (item.isNotEmpty) return _filled(event, item);
    final stripped = _stripped(event);
    if (_reads(stripped)) return stripped;
    if (q.isNotEmpty && _reads(_stripped(q))) return _stripped(q);
    return event;
  }
  if (item.isEmpty || item.toLowerCase() == event.toLowerCase()) {
    return event.isNotEmpty ? event : item;
  }
  if (event.isEmpty) return item;
  // No question to say it whole: the event, then the market's name
  // ("Lions vs Tigers: Tigers").
  return '$event: $item';
}
