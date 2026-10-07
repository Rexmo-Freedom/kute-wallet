// lib/screens/polymarket/components/exact_score_list.dart
//
// A football match's Exact Score market as a score list: each row is the
// score alone ("2 – 1", home first, the sheet's header names the teams),
// its chance and the chevron. Most likely first within each section: the
// home team's wins, the draws, the away team's wins, then "Any other
// score" pinned last. Up to the eight most likely show (never a "—" while
// a priced score is left out); "Show N more" opens the rest. Polymarket names each of these markets with the whole fixture
// ("Tottenham Hotspur FC 4 - 5 Coventry City FC"), which made a 37-row
// list of the same two names.
//
// Also the rule that keeps a game's other sub-markets from repeating the
// event's title in every row ([polyStripEventPrefix]).
//
// Layout logic is pure ([polyExactScoreSections]) and unit tested in
// test/screens/polymarket/exact_score_list_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';

/// Gamma's `sportsMarketType` of an exact-score market.
const String kPolyExactScoreKind = 'soccer_exact_score';

/// Rows shown before "Show N more".
const int kPolyExactScoreRows = 8;

/// Section headings appear from this many score rows.
const int kPolyExactScoreSectionsFrom = 6;

final RegExp _kScore =
    RegExp(r'(?:^|\s)(\d{1,2})\s*[-–—]\s*(\d{1,2})(?=\s|\?|$)');
final RegExp _kAnyOther = RegExp(
    r'^\s*(exact score:\s*)?any\s+other\s+score\s*\??\s*$',
    caseSensitive: false);

/// A score, home goals first.
typedef PolyExactScore = ({int home, int away});

/// The score an exact-score market names ("Tottenham Hotspur FC 4 - 5
/// Coventry City FC" → 4–5); null for "Any Other Score" and anything
/// else.
PolyExactScore? polyParseExactScore(String name) {
  final m = _kScore.firstMatch(name);
  if (m == null) return null;
  return (home: int.parse(m.group(1)!), away: int.parse(m.group(2)!));
}

/// Whether [name] is the catch-all "Any Other Score" market.
bool polyIsAnyOtherScore(String name) => _kAnyOther.hasMatch(name);

/// Whether an event's [outcomes] are one exact-score market each: Gamma
/// types them `soccer_exact_score`, or (read without the type) the
/// event's [title] says "Exact Score" and every outcome is a score or the
/// catch-all.
bool polyIsExactScoreList(List<PolymarketOutcome> outcomes, {String? title}) {
  if (outcomes.length < 3) return false;
  final typed =
      outcomes.where((o) => o.marketLine?.kind == kPolyExactScoreKind).length;
  if (typed == outcomes.length) return true;
  if (typed > 0) return false;
  if (!(title ?? '').toLowerCase().contains('exact score')) return false;
  return outcomes.every((o) =>
      polyParseExactScore(o.name) != null || polyIsAnyOtherScore(o.name));
}

/// The section a score row sits in.
enum PolyScoreGroup { home, draw, away, other }

PolyScoreGroup polyScoreGroupOf(PolymarketOutcome o) {
  final s = polyParseExactScore(o.name);
  if (s == null) return PolyScoreGroup.other;
  if (s.home > s.away) return PolyScoreGroup.home;
  if (s.home == s.away) return PolyScoreGroup.draw;
  return PolyScoreGroup.away;
}

/// What the list shows: [sections] in order (home wins, draws, away
/// wins, other), each most likely first, with how many score rows
/// [hidden] behind "Show N more" and whether [headed] (enough rows for
/// section headings).
typedef PolyExactScoreLayout = ({
  List<({PolyScoreGroup group, List<PolymarketOutcome> rows})> sections,
  int hidden,
  bool headed,
});

/// Lays out [outcomes] by [chanceOf] (null, no chance to show: last).
/// Folded to the [collapseTo] most likely scores unless [expanded], and
/// to the priced ones alone when there are fewer of those; the catch-all
/// always shows, last. A fold that would hide a single row shows it
/// instead.
PolyExactScoreLayout polyExactScoreSections(
  List<PolymarketOutcome> outcomes,
  double? Function(PolymarketOutcome o) chanceOf, {
  int collapseTo = kPolyExactScoreRows,
  bool expanded = false,
}) {
  int byChance(PolymarketOutcome a, PolymarketOutcome b) {
    final pa = chanceOf(a), pb = chanceOf(b);
    if (pa == null && pb == null) return 0;
    if (pa == null) return 1;
    if (pb == null) return -1;
    return pb.compareTo(pa);
  }

  final scores = <PolymarketOutcome>[];
  final other = <PolymarketOutcome>[];
  for (final o in outcomes) {
    (polyScoreGroupOf(o) == PolyScoreGroup.other ? other : scores).add(o);
  }
  // Equal chances read lowest score first (1–1 before 2–2), then in the
  // event's order.
  int goals(PolymarketOutcome o) {
    final s = polyParseExactScore(o.name)!;
    return s.home + s.away;
  }

  final ranked = [
    for (final (i, o) in scores.indexed) (i, o),
  ]..sort((a, b) {
      final c = byChance(a.$2, b.$2);
      if (c != 0) return c;
      final g = goals(a.$2).compareTo(goals(b.$2));
      return g != 0 ? g : a.$1.compareTo(b.$1);
    });
  // Folded: the most likely scores, never a "—" while a priced score
  // fills the room (an exact-score book is mostly empty: on a real
  // Premier League match 31 of 36 scores had no price to show).
  var keep = ranked.length;
  if (!expanded) {
    final priced = ranked.where((r) => chanceOf(r.$2) != null).length;
    keep = priced > 0 && priced < collapseTo ? priced : collapseTo;
    if (ranked.length <= keep + 1) keep = ranked.length;
  }
  final fold = keep < ranked.length;
  final shown = fold ? ranked.take(keep).toList() : ranked;
  final headed = scores.length >= kPolyExactScoreSectionsFrom;
  final sections = <({PolyScoreGroup group, List<PolymarketOutcome> rows})>[];
  if (headed) {
    for (final g in [
      PolyScoreGroup.home,
      PolyScoreGroup.draw,
      PolyScoreGroup.away,
    ]) {
      final rows = [
        for (final r in shown)
          if (polyScoreGroupOf(r.$2) == g) r.$2
      ];
      if (rows.isNotEmpty) sections.add((group: g, rows: rows));
    }
  } else if (shown.isNotEmpty) {
    sections
        .add((group: PolyScoreGroup.home, rows: [for (final r in shown) r.$2]));
  }
  if (other.isNotEmpty) {
    sections.add((group: PolyScoreGroup.other, rows: other));
  }
  return (
    sections: sections,
    hidden: ranked.length - shown.length,
    headed: headed,
  );
}

/// [name] without the event's own fixture in front of it: a game's
/// sub-market reads "Spurs vs. Coventry: O/U 2.5" under a header that
/// already names the two teams, so the row says "O/U 2.5". [eventTitle]'s
/// fixture is what comes before a " - " suffix ("… - More Markets").
/// Unchanged when the name does not start with it, or is nothing else.
String polyStripEventPrefix(String name, String eventTitle) {
  var fixture = eventTitle.trim();
  final dash = fixture.lastIndexOf(' - ');
  if (dash > 0) fixture = fixture.substring(0, dash).trim();
  if (fixture.isEmpty) return name;
  final n = name.trim();
  if (n.length <= fixture.length ||
      n.substring(0, fixture.length).toLowerCase() != fixture.toLowerCase()) {
    return name;
  }
  var rest = n.substring(fixture.length).trimLeft();
  if (!rest.startsWith(':')) return name;
  rest = rest.substring(1).trim();
  return rest.isEmpty ? name : rest;
}

/// The Exact Score list as a sliver. [chanceFor] is a row's chance, read
/// against the row's own ref (null: "—"); [onPick] opens a row, exactly
/// as the plain outcome list does. [outcomes] come most likely first.
class PolyExactScoreList extends StatefulWidget {
  final List<PolymarketOutcome> outcomes;
  final double? Function(WidgetRef ref, PolymarketOutcome o) chanceFor;

  /// The chance a row sorts by, without a watch (the caller's order is
  /// already watched).
  final double? Function(PolymarketOutcome o) sortChance;
  final void Function(PolymarketOutcome o) onPick;
  final String homeName;
  final String awayName;
  final String? homeCrest;
  final String? awayCrest;
  final String? homeAbbr;
  final String? awayAbbr;

  const PolyExactScoreList({
    super.key,
    required this.outcomes,
    required this.chanceFor,
    required this.sortChance,
    required this.onPick,
    required this.homeName,
    required this.awayName,
    this.homeCrest,
    this.awayCrest,
    this.homeAbbr,
    this.awayAbbr,
  });

  @override
  State<PolyExactScoreList> createState() => _PolyExactScoreListState();
}

class _PolyExactScoreListState extends State<PolyExactScoreList> {
  bool _expanded = false;

  /// Width of each side of a score, so every row's dash lines up under
  /// the column hint.
  double get _sideWidth => 40.w;

  TextStyle _headingStyle(AppColorsExtension c) => TextStyle(
        color: c.textTertiary,
        fontSize: 12.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      );

  String _short(String name, String? abbr) {
    final a = abbr?.trim() ?? '';
    if (a.isNotEmpty) return a.toUpperCase();
    final letters = name.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    return (letters.length > 3 ? letters.substring(0, 3) : letters)
        .toUpperCase();
  }

  String _heading(BuildContext context, PolyScoreGroup g) => switch (g) {
        PolyScoreGroup.home => widget.homeName,
        PolyScoreGroup.draw => context.l10n.betDraw,
        PolyScoreGroup.away => widget.awayName,
        PolyScoreGroup.other => context.l10n.betGroupOther,
      }
          .toUpperCase();

  Widget _crest(String? url, String label) => url == null || url.isEmpty
      ? const SizedBox.shrink()
      : PolyCrestImage(url: url, size: 14.r, radius: 3.r, label: label);

  /// The two teams over the score columns: home on the left, away on the
  /// right, so "2 – 1" reads without the names on every row.
  Widget _columnHint(AppColorsExtension c) {
    final style = _headingStyle(c);
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 2.h),
      child: Row(
        children: [
          // Scaled down rather than clipped when a large text size makes
          // a side wider than its column.
          SizedBox(
            width: _sideWidth,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _crest(widget.homeCrest, widget.homeName),
                    SizedBox(width: 4.w),
                    Text(_short(widget.homeName, widget.homeAbbr),
                        style: style),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 24.w),
          SizedBox(
            width: _sideWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_short(widget.awayName, widget.awayAbbr),
                        style: style),
                    SizedBox(width: 4.w),
                    _crest(widget.awayCrest, widget.awayName),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppColorsExtension c, PolymarketOutcome o) {
    final score = polyParseExactScore(o.name);
    final nameStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = score == null
        ? Expanded(child: Text(o.name, style: nameStyle))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _sideWidth,
                child: Text('${score.home}',
                    textAlign: TextAlign.end, style: nameStyle),
              ),
              SizedBox(
                width: 24.w,
                child: Text('–',
                    textAlign: TextAlign.center,
                    style: nameStyle.copyWith(color: c.textTertiary)),
              ),
              SizedBox(
                width: _sideWidth,
                child: Text('${score.away}', style: nameStyle),
              ),
            ],
          );
    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPick(o);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
        child: Row(
          children: [
            label,
            if (score != null) const Spacer(),
            SizedBox(width: 12.w),
            // Its own Consumer: a tick on this row's token repaints the
            // figure alone.
            Consumer(builder: (context, priceRef, _) {
              final chance = widget.chanceFor(priceRef, o);
              return RollingFigure(
                identity: o.tokenId ?? o.gammaMarketId ?? o.name,
                text: chance == null ? '—' : formatPolyChance(chance),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            }),
            SizedBox(width: 8.w),
            Icon(Icons.chevron_right_rounded,
                color: c.textTertiary, size: 18.sp),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layout = polyExactScoreSections(widget.outcomes, widget.sortChance,
        expanded: _expanded);
    final entries = <Widget Function(BuildContext)>[];
    if (layout.sections.any((s) => s.group != PolyScoreGroup.other)) {
      entries.add((context) => _columnHint(c));
    }
    for (final (i, section) in layout.sections.indexed) {
      final isOther = section.group == PolyScoreGroup.other;
      if (layout.headed || (isOther && i > 0)) {
        // Before "Any other score", the fold of the scores above it.
        if (isOther && layout.hidden > 0) entries.add(_showMore(c, layout));
        if (layout.headed) {
          final first = i == 0;
          entries.add((context) => Padding(
                padding: EdgeInsets.only(
                    top: first ? 8.h : 16.h, bottom: 4.h, left: 4.w),
                child: Text(_heading(context, section.group),
                    style: _headingStyle(c)),
              ));
        }
      }
      for (final o in section.rows) {
        entries.add((context) => _row(context, c, o));
      }
    }
    if (layout.hidden > 0 &&
        !layout.sections.any((s) => s.group == PolyScoreGroup.other)) {
      entries.add(_showMore(c, layout));
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: entries[i](context),
        ),
        childCount: entries.length,
      ),
    );
  }

  /// "Show N more": the plain outcome list's fold row, to the letter.
  Widget Function(BuildContext) _showMore(
          AppColorsExtension c, PolyExactScoreLayout layout) =>
      (context) => InkWell(
            borderRadius: BorderRadius.circular(12.r),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = true);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
              child: Text(
                context.l10n.salShowMore(layout.hidden),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          );
}
