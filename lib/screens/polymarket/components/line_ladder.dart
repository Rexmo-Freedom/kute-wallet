// lib/screens/polymarket/components/line_ladder.dart
//
// LINE LADDERS (founder, 12 November 2026, on "Sabah FK vs. FC Barcelona -
// Total Corners", then on the real "FK Shakhtar Donetsk vs. Fenerbahçe SK
// - Total Corners": "some Polymarket events still look like complete
// slop"). A football prop event is not a list of candidates: it is a few
// QUESTIONS, each asked at several lines:
//
//   Total Corners            O/U 7.5 … 13.5
//   1st Half Total Corners   O/U 3.5 … 5.5
//   FK Shakhtar Donetsk Corners   O/U 2.5 … 5.5
//   Fenerbahçe SK Corners    O/U 2.5 … 5.5
//   (and one-off markets: "Total Corners Odd or Even?", "Team to Take
//   First Corner"; a "More Markets" event adds spreads, goals O/U, team
//   totals, both teams to score)
//
// The page read it as a list of rows, each "OVER —" in another colour,
// under a chart of five lines. [polyLadderBoard] sorts the event's
// markets into LADDER GROUPS by question (the market's name with the
// fixture and its line taken out); a market with no line is not in a
// group and stays a row of its own. The page then shows, as
// polymarket.com shows a ladder:
//
//   * a GROUP PICKER when there is more than one group, in the app's pill
//     row: "Total · 1st half · Shakhtar · Fenerbahçe"
//     ([polyLadderGroupLabels]);
//   * for the group picked, ONE question: the selected line's question as
//     the headline ("O/U 8.5 Total Corners", never the fixture in front
//     of it) and its first side's chance; its own chart, Over and Under,
//     each tag naming its side and line; a LINE STEPPER "‹ 7.5 8.5 9.5 ›"
//     (hidden for a group of one line); the line's two sides as the game
//     page's side buttons, each in its chart line's colour.
//
// It opens on the group with the most volume (the first, "Total", on a
// tie) and on the line nearest 50%. ONLY a line with a real price is
// offered ([polyLadderLineTrades]): a book wider than 10¢ that never
// traded, a stub at Gamma's 50/50 and a line already decided (99% or 1%)
// are left out, never written "—". A group with no such line says it
// awaits liquidity; an event with none says so once.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/exact_score_list.dart'
    show polyStripEventPrefix;
import 'package:kute/screens/polymarket/components/game_more_markets.dart'
    show GameLineStatus, gameLineStatus;
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/theme/app_theme.dart';

/// One line of a ladder: its market, its line and the question as the
/// page writes it (the fixture taken off the front).
class PolyLadderLine {
  final PolymarketOutcome outcome;
  final double line;

  /// "O/U 8.5 Total Corners".
  final String question;

  const PolyLadderLine({
    required this.outcome,
    required this.line,
    required this.question,
  });

  /// The line as the stepper writes it: "8.5", a spread with its sign
  /// ("-1.5", "+2.5").
  String get lineText => polyLadderLineText(line, signed: _signed);

  bool get _signed => RegExp(r'[+-]\s*\d').hasMatch(question);
}

/// One ladder: a question's lines, lowest first, and the two sides every
/// line's market has, in the market's order ("Over" / "Under", two teams
/// on a spread, "Yes" / "No").
class PolyLineLadder {
  /// What makes two markets the same question: the name with its line
  /// taken out, the kind of market and its sides.
  final String key;

  /// The question without its line and the words every ladder shares
  /// ("O/U", "Spread:"): "Total Corners", "1st Half Total Corners",
  /// "FK Shakhtar Donetsk Corners"; empty for a bare "O/U 2.5".
  final String stem;

  /// Gamma's kind of market (`sportsMarketType`), '' when it sends none.
  final String kind;
  final List<PolyLadderLine> lines;
  final String sideA;
  final String sideB;

  const PolyLineLadder({
    required this.key,
    required this.stem,
    required this.kind,
    required this.lines,
    required this.sideA,
    required this.sideB,
  });

  /// The sides are Over and Under.
  bool get overUnder =>
      sideA.trim().toLowerCase() == 'over' &&
      sideB.trim().toLowerCase() == 'under';

  /// A handicap: its sides are the two teams.
  bool get spread =>
      kind.toLowerCase().contains('spread') ||
      kind.toLowerCase().contains('handicap') ||
      lines.any((l) => l.question.toLowerCase().startsWith('spread'));

  /// What its markets have traded, added up.
  double get volume =>
      lines.fold(0.0, (sum, l) => sum + (l.outcome.volume ?? 0));
}

/// An event read as ladders: its groups, in the event's order, and the
/// markets that are no line of any ([others]: "Odd or Even?", "Both Teams
/// to Score").
class PolyLadderBoard {
  final List<PolyLineLadder> groups;
  final List<PolymarketOutcome> others;

  const PolyLadderBoard({required this.groups, required this.others});
}

/// [line] written as a ladder writes it: no trailing ".0", a sign when
/// [signed] and the line is positive.
String polyLadderLineText(double line, {bool signed = false}) {
  final t =
      line == line.roundToDouble() ? line.toStringAsFixed(0) : line.toString();
  return signed && line > 0 ? '+$t' : t;
}

/// A half line ("8.5", "-1.5") in a market's name, not part of a longer
/// number.
final RegExp _kHalfLine = RegExp(r'(?<![\d.])[+-]?\d+\.5(?![\d.])');

/// Gamma's kinds of market that are a game's own board (its winner): an
/// event with one is the game itself, never a page of ladders.
const Set<String> _kWinnerKinds = {'moneyline', 'child_moneyline'};

/// What is left of a ladder's question without its line and the words
/// every ladder shares: "O/U # Total Corners" -> "Total Corners",
/// "Spread: FK Dynamo Kyiv (#)" -> "FK Dynamo Kyiv".
String _ladderStem(String shape) => shape
    .replaceAll('#', ' ')
    .replaceAll(RegExp(r'\bo\s*/\s*u\b', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'\bover\s*/\s*under\b', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'^\s*spread\s*:', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'[()\[\]:?]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// [event] read as ladders, or null when it is not a page of them.
///
/// Only a sports event (a sports tag, teams or a matchup title) that is
/// not a game's own event (no winner market) and not one Yes / No market.
/// Each two-sided market whose name, with the fixture taken off, carries
/// exactly one half line is a line of the group that asks its question:
/// same name once the line is out, same kind, same sides. Every other
/// market is one of [PolyLadderBoard.others]. Null unless at least one
/// group has two lines: a match result with a draw, an exact score, a
/// first-to-score event and a price ladder outside sports keep their
/// pages.
PolyLadderBoard? polyLadderBoard(PolymarketEvent event) {
  if (event.isBinary || event.isSyntheticBinary) return null;
  final sports = event.isSportsCategory ||
      event.teams.isNotEmpty ||
      event.looksLikeMatchup;
  if (!sports) return null;
  final outcomes = event.outcomes;
  if (outcomes.length < 2) return null;
  final byKey = <String, List<PolyLadderLine>>{};
  final meta = <String, ({String stem, String kind, String a, String b})>{};
  final others = <PolymarketOutcome>[];
  for (final o in outcomes) {
    final kind = (o.marketLine?.kind ?? '').trim();
    if (_kWinnerKinds.contains(kind.toLowerCase())) return null;
    final question =
        polyStripEventPrefix((o.question ?? o.name).trim(), event.title);
    final matches = _kHalfLine.allMatches(question).toList();
    final named =
        matches.length == 1 ? double.tryParse(matches.single.group(0)!) : null;
    final gamma = o.marketLine?.line;
    // A line of a ladder: two tokens, one half line in the name, and
    // Gamma's own line (when it sends one) the same but for its sign.
    if (!o.hasYesNo ||
        o.tokenId == null ||
        o.tokenId!.isEmpty ||
        named == null ||
        (gamma != null && gamma.abs() != named.abs())) {
      others.add(o);
      continue;
    }
    final shape = question
        .replaceRange(matches.single.start, matches.single.end, '#')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final own = o.marketLine?.sides ?? const [];
    final a = own.length == 2 ? own[0].trim() : 'Yes';
    final b = own.length == 2 ? own[1].trim() : 'No';
    final key = '${shape.toLowerCase()}|${kind.toLowerCase()}|'
        '${a.toLowerCase()}|${b.toLowerCase()}';
    final lines = byKey.putIfAbsent(key, () => []);
    if (lines.any((l) => l.line == named)) {
      others.add(o);
      continue;
    }
    meta[key] ??= (stem: _ladderStem(shape), kind: kind, a: a, b: b);
    lines.add(PolyLadderLine(outcome: o, line: named, question: question));
  }
  if (!byKey.values.any((l) => l.length >= 2)) return null;
  return PolyLadderBoard(
    groups: [
      for (final e in byKey.entries)
        PolyLineLadder(
          key: e.key,
          stem: meta[e.key]!.stem,
          kind: meta[e.key]!.kind,
          lines: [...e.value]..sort((x, y) => x.line.compareTo(y.line)),
          sideA: meta[e.key]!.a,
          sideB: meta[e.key]!.b,
        ),
    ],
    others: others,
  );
}

final RegExp _kFirstHalf =
    RegExp(r'\b(1st|first)\s+half\b', caseSensitive: false);
final RegExp _kSecondHalf =
    RegExp(r'\b(2nd|second)\s+half\b', caseSensitive: false);

/// The picker's name for each of [groups], short and never the same
/// twice: the whole game's question is [total] ("Total"), a half's is its
/// half ([firstHalf], [secondHalf]), a team's is the team's short name
/// ([shortA] for [teamA], the fixture's first side), a team's half both
/// ("Shakhtar 1st half") and a handicap [spread] and its team ("Spread
/// Dynamo"). What the question counts ("Corners") is the page's title
/// already; it is written only to tell two groups apart ("Total Corners"
/// beside "Total Cards"), and two that still read alike write their
/// whole stems.
List<String> polyLadderGroupLabels(
  List<PolyLineLadder> groups, {
  String? teamA,
  String? teamB,
  String? shortA,
  String? shortB,
  required String total,
  required String firstHalf,
  required String secondHalf,
  required String spread,
}) {
  ({String label, String rest}) read(PolyLineLadder g) {
    var rest = g.stem;
    String? period;
    if (_kFirstHalf.hasMatch(rest)) {
      period = firstHalf;
      rest = rest.replaceAll(_kFirstHalf, ' ');
    } else if (_kSecondHalf.hasMatch(rest)) {
      period = secondHalf;
      rest = rest.replaceAll(_kSecondHalf, ' ');
    }
    String? team;
    // The longer name first: "Manchester United" before "Manchester".
    final sides = [
      if (teamA != null && teamA.trim().isNotEmpty)
        (teamA.trim(), shortA ?? teamA),
      if (teamB != null && teamB.trim().isNotEmpty)
        (teamB.trim(), shortB ?? teamB),
    ]..sort((x, y) => y.$1.length.compareTo(x.$1.length));
    for (final (name, short) in sides) {
      final at = rest.toLowerCase().indexOf(name.toLowerCase());
      if (at < 0) continue;
      team = short.trim();
      rest = rest.replaceRange(at, at + name.length, ' ');
      break;
    }
    rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = [
      if (g.spread) spread,
      if (team != null) team,
      if (period != null) period,
    ];
    return (label: parts.isEmpty ? total : parts.join(' '), rest: rest);
  }

  final reads = [for (final g in groups) read(g)];
  bool clash(List<String> labels, int i) {
    for (var j = 0; j < labels.length; j++) {
      if (j != i && labels[j].toLowerCase() == labels[i].toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  final first = [for (final r in reads) r.label];
  final second = [
    for (var i = 0; i < reads.length; i++)
      clash(first, i) && reads[i].rest.isNotEmpty
          ? (first[i] == total &&
                  reads[i].rest.toLowerCase().contains(total.toLowerCase())
              ? reads[i].rest
              : '${first[i]} ${reads[i].rest}')
          : first[i],
  ];
  return [
    for (var i = 0; i < reads.length; i++)
      clash(second, i) && groups[i].stem.isNotEmpty
          ? groups[i].stem
          : second[i],
  ];
}

/// Whether [o] has a real price at the live [prices]: its book trades
/// ([gameLineStatus] open: not a wide book that never traded, not a stub
/// at Gamma's 50/50, not closed) and it is not decided already (99% or
/// more, 1% or less). Only such a line is offered.
bool polyLadderLineTrades(
    Map<String, double> prices, Set<String> unpriced, PolymarketOutcome o) {
  if (gameLineStatus(prices, unpriced, o) != GameLineStatus.open) return false;
  final p = polyShownChanceOf(prices, unpriced, o);
  return p != null && p > 0.01 + 1e-9 && p < 0.99 - 1e-9;
}

/// The lines of [ladder] the stepper offers at the live [prices]: those
/// that trade ([polyLadderLineTrades]), lowest first. Empty when none
/// does: the group then awaits liquidity.
List<PolyLadderLine> polyLadderShownLines(PolyLineLadder ladder,
        Map<String, double> prices, Set<String> unpriced) =>
    [
      for (final l in ladder.lines)
        if (polyLadderLineTrades(prices, unpriced, l.outcome)) l
    ];

/// The group a page of ladders opens on: among those with a line that
/// trades, the one with the most volume; the earlier one on a tie (the
/// whole game's question comes first). Null when no group trades.
int? polyLadderDefaultGroup(List<PolyLineLadder> groups,
    Map<String, double> prices, Set<String> unpriced) {
  int? best;
  for (var i = 0; i < groups.length; i++) {
    if (polyLadderShownLines(groups[i], prices, unpriced).isEmpty) continue;
    if (best == null || groups[i].volume > groups[best].volume + 1e-9) {
      best = i;
    }
  }
  return best;
}

/// The line a ladder opens on: the one whose first side's chance is
/// nearest 50% ([polyShownChanceOf]); the lower line on a tie, the middle
/// line when none has a chance.
int polyLadderDefaultIndex(List<PolyLadderLine> lines,
    Map<String, double> prices, Set<String> unpriced) {
  if (lines.isEmpty) return 0;
  int? best;
  double bestGap = double.infinity;
  for (var i = 0; i < lines.length; i++) {
    final p = polyShownChanceOf(prices, unpriced, lines[i].outcome);
    if (p == null) continue;
    final gap = (p - 0.5).abs();
    if (gap < bestGap - 1e-9) {
      bestGap = gap;
      best = i;
    }
  }
  return best ?? (lines.length - 1) ~/ 2;
}

/// The stepper over a ladder's lines: "‹ 7.5 8.5 9.5 ›". The chevrons
/// step one line (dim at either end), the selected line in the primary
/// text colour, its neighbours in the tertiary one and a tap away. Light
/// and dark read the theme's own text colours; nothing is drawn behind it.
class PolyLineStepper extends StatelessWidget {
  final List<String> lines;
  final int selected;
  final ValueChanged<int> onSelect;

  /// What screen readers hear before the line ("Line").
  final String? semanticPrefix;

  const PolyLineStepper({
    super.key,
    required this.lines,
    required this.selected,
    required this.onSelect,
    this.semanticPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = selected.clamp(0, lines.length - 1);
    void go(int to) {
      if (to < 0 || to >= lines.length || to == i) return;
      HapticFeedback.selectionClick();
      onSelect(to);
    }

    Widget chevron(IconData icon, int to, String key) {
      final enabled = to >= 0 && to < lines.length;
      return Semantics(
        button: true,
        enabled: enabled,
        child: GestureDetector(
          key: ValueKey('line-stepper-$key'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => go(to) : null,
          child: SizedBox(
            width: 40.w,
            height: 40.h,
            child: Icon(icon,
                size: 22.sp, color: enabled ? c.textSecondary : c.textDisabled),
          ),
        ),
      );
    }

    Widget value(int at) {
      final on = at == i;
      final text = Text(
        lines[at],
        maxLines: 1,
        style: TextStyle(
          color: on ? c.textPrimary : c.textTertiary,
          fontSize: (on ? 17 : 14).sp,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      return GestureDetector(
        key: ValueKey('line-stepper-value-${lines[at]}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => go(at),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
          child: text,
        ),
      );
    }

    return Semantics(
      label: '${semanticPrefix ?? ''} ${lines[i]}'.trim(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          chevron(Icons.chevron_left_rounded, i - 1, 'prev'),
          // The neighbours keep their seat at either end, so the selected
          // line never moves sideways as it steps.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: i > 0
                        ? FittedBox(fit: BoxFit.scaleDown, child: value(i - 1))
                        : const SizedBox.shrink(),
                  ),
                ),
                FittedBox(fit: BoxFit.scaleDown, child: value(i)),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: i < lines.length - 1
                        ? FittedBox(fit: BoxFit.scaleDown, child: value(i + 1))
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          chevron(Icons.chevron_right_rounded, i + 1, 'next'),
        ],
      ),
    );
  }
}
