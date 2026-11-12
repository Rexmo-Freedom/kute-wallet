// lib/screens/polymarket/components/line_ladder.dart
//
// A LINE LADDER (founder, 12 November 2026, on "Sabah FK vs. FC
// Barcelona - Total Corners": "on some of these events for football it is
// not correctly divided, it looks bad, make it look good please"): an
// event whose markets are one question asked at different lines, "O/U 7.5
// Total Corners" … "O/U 12.5 Total Corners", a spread at -1.5 / -2.5, a
// card count. The page read it as a list of six rows, each "OVER —" in
// another colour, under a chart of six lines whose tags all read "Total
// Corners".
//
// It now reads as polymarket.com shows a ladder, ONE question:
//
//   * the selected line's question as the headline ("O/U 8.5 Total
//     Corners", never the fixture in front of it: the teams header names
//     it) and its Over chance;
//   * its own chart, Over and Under, each tag naming its side and line
//     ("Over 8.5", "Under 8.5");
//   * a LINE STEPPER, "‹ 7.5 8.5 9.5 ›": the chevrons step a line, a
//     neighbour is a tap away;
//   * the line's two sides as the game page's side buttons ("Over 53.5%",
//     "Under 46.5%"), each in its chart line's colour.
//
// It opens on the line nearest 50%. A line nobody trades (a book wider
// than 10¢ that never traded, a stub still at Gamma's 50/50) or one
// already settled is not offered while another line trades
// ([polyLadderShownLines]); with none trading every line stays, figures
// quiet.

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

/// A ladder: its lines, lowest first, and the two sides every line's
/// market has, in the market's order ("Over" / "Under", "Yes" / "No").
class PolyLineLadder {
  final List<PolyLadderLine> lines;
  final String sideA;
  final String sideB;

  const PolyLineLadder({
    required this.lines,
    required this.sideA,
    required this.sideB,
  });

  /// The sides are Over and Under.
  bool get overUnder =>
      sideA.trim().toLowerCase() == 'over' &&
      sideB.trim().toLowerCase() == 'under';
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

/// The ladder [event] is, or null when it is not one.
///
/// A ladder is a sports event (a sports tag, teams or a matchup title)
/// of two or more markets, each a two-sided market (its own two tokens),
/// that ask the SAME question at different half lines: every market's
/// name with the fixture and its line taken out reads the same, its sides
/// are the same pair, and no two share a line. The line is Gamma's own
/// (`line`) when the market carries it, else the one half line in its
/// name. Anything else (a match result with a draw, both teams to score,
/// a game of many kinds of market, a price ladder outside sports) is not
/// a ladder and keeps its page.
PolyLineLadder? polyLineLadder(PolymarketEvent event) {
  if (event.isBinary || event.isSyntheticBinary) return null;
  final sports = event.isSportsCategory ||
      event.teams.isNotEmpty ||
      event.looksLikeMatchup;
  if (!sports) return null;
  final outcomes = event.outcomes;
  if (outcomes.length < 2) return null;
  String? template;
  String? kind;
  (String, String)? sides;
  final seen = <double>{};
  final lines = <PolyLadderLine>[];
  for (final o in outcomes) {
    if (!o.hasYesNo || o.tokenId == null || o.tokenId!.isEmpty) return null;
    final question =
        polyStripEventPrefix((o.question ?? o.name).trim(), event.title);
    final matches = _kHalfLine.allMatches(question).toList();
    final named = matches.length == 1
        ? double.tryParse(matches.single.group(0)!.replaceAll(' ', ''))
        : null;
    final line = o.marketLine?.line ?? named;
    if (line == null || matches.length != 1) return null;
    // Gamma's line and the name's agree (a spread's line may be the other
    // side's sign).
    if (named == null || named.abs() != line.abs()) return null;
    if (!seen.add(named)) return null;
    final shape = question
        .replaceRange(matches.single.start, matches.single.end, '#')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    template ??= shape;
    if (shape != template) return null;
    final k = o.marketLine?.kind ?? '';
    kind ??= k;
    if (k != kind) return null;
    final own = o.marketLine?.sides ?? const [];
    final pair =
        own.length == 2 ? (own[0].trim(), own[1].trim()) : ('Yes', 'No');
    sides ??= pair;
    if (pair.$1.toLowerCase() != sides.$1.toLowerCase() ||
        pair.$2.toLowerCase() != sides.$2.toLowerCase()) {
      return null;
    }
    lines.add(PolyLadderLine(outcome: o, line: named, question: question));
  }
  lines.sort((a, b) => a.line.compareTo(b.line));
  return PolyLineLadder(lines: lines, sideA: sides!.$1, sideB: sides.$2);
}

/// The lines the stepper offers at the live [prices]: those trading
/// ([gameLineStatus] open); with none trading, those not settled; with
/// every line settled, all of them. Lowest first.
List<PolyLadderLine> polyLadderShownLines(
    PolyLineLadder ladder, Map<String, double> prices, Set<String> unpriced) {
  final open = [
    for (final l in ladder.lines)
      if (gameLineStatus(prices, unpriced, l.outcome) == GameLineStatus.open) l
  ];
  if (open.isNotEmpty) return open;
  final unsettled = [
    for (final l in ladder.lines)
      if (gameLineStatus(prices, unpriced, l.outcome) != GameLineStatus.settled)
        l
  ];
  return unsettled.isNotEmpty ? unsettled : ladder.lines;
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
