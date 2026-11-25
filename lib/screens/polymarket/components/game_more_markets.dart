// lib/screens/polymarket/components/game_more_markets.dart
//
// A game's "More markets" (founder, 5 November 2026, on the Dota 2 and
// LoL sheets: "Look at all these games, any better way to display this?",
// then "do it for all items"). Every game with markets beyond its board,
// in every sport:
//
//   * PERIOD CHIPS at the top: All · Match · Game 1 · Game 2 … (Map N,
//     Set N, 1st half, Q3, Period 2 by sport; "Full game" for a sport
//     played in quarters or innings), read from each market's question
//     (game_line_rows.dart). Under them, KIND CHIPS (Winner, Handicap,
//     Total kills …) only when the period has more than eight lines of
//     more than one kind.
//   * The period's lines BY KIND under small headings; a kind with one
//     line has no heading, its name in the line's label instead.
//   * Each LINE is one short label and its two sides as buttons
//     ([PolyGameSideButton], the board's tile a step down, so the board
//     and the list read as one): "24.5" · [Over 57.5%] [Under 42.5%],
//     "GL -1.5" · [GL -1.5 63%] [YS +1.5 37%]. A side opens the slip on
//     that side; the label opens the market's own page.
//   * Lines nobody trades yet and lines already decided (over 99%, under
//     1%, closed) fold away at the foot of the period: "Not trading yet ·
//     5", "Settled · 2".
//   * With every period and kind listed, a kind shows its first four lines
//     and "Show N more".
//
// No league logo per line (the page's header has it), no event or team
// in front of a label, no "Over/Under" or "?" in it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/game_side_button.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyAutoScrollRow;
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/kute_motion.dart' show SliverSelectionFade;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/live_game/game_line_rows.dart';
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The name of a game's [period] on its chip ("Game 2", "1st half",
/// "Q3"); [fullGame] names the whole game "Full game" rather than "Match".
String gamePeriodName(AppLocalizations l10n, GamePeriod period,
        {bool fullGame = false}) =>
    switch (period.unit) {
      GamePeriodUnit.match =>
        fullGame ? l10n.polyPeriodFullGame : l10n.polyPeriodMatch,
      GamePeriodUnit.game => l10n.polyPeriodGame(period.index),
      GamePeriodUnit.map => l10n.polyPeriodMap(period.index),
      GamePeriodUnit.set => l10n.polyPeriodSet(period.index),
      GamePeriodUnit.half => period.index == 2
          ? l10n.polyPeriodSecondHalf
          : l10n.polyPeriodFirstHalf,
      GamePeriodUnit.quarter => l10n.polyPeriodQuarter(period.index),
      GamePeriodUnit.period => l10n.polyPeriodPeriod(period.index),
      GamePeriodUnit.firstFive => l10n.polyPeriodFirstFive,
      GamePeriodUnit.inning => l10n.polyPeriodFirstInning,
    };

/// The name of a kind of game line, on its chip and its heading.
String gameLineTypeName(AppLocalizations l10n, GameLineType type) =>
    switch (type) {
      GameLineType.winner => l10n.betGroupMoneyline,
      GameLineType.handicap => l10n.betGroupSpread,
      GameLineType.setHandicap => l10n.polyLineSetHandicap,
      GameLineType.total => l10n.betGroupTotals,
      GameLineType.totalGames => l10n.polyLineTotalGames,
      GameLineType.totalSets => l10n.polyLineTotalSets,
      GameLineType.kills => l10n.polyLineTotalKills,
      GameLineType.rounds => l10n.polyLineTotalRounds,
      GameLineType.duration => l10n.polyLineDuration,
      GameLineType.teamTotals => l10n.polyLineTeamTotals,
      GameLineType.players => l10n.polyLinePlayers,
      GameLineType.other => l10n.betGroupProps,
    };

/// Where a line stands at the live prices.
enum GameLineStatus { open, notTrading, settled }

/// [o]'s status at the live [prices]: settled when its market has closed
/// or its chance is past 99% or under 1%; not trading yet when it has no
/// chance to show (a wide book that never traded, [polyShownChanceOf]) or
/// still sits at Gamma's untouched 50/50 with no live price.
GameLineStatus gameLineStatus(
    Map<String, double> prices, Set<String> unpriced, PolymarketOutcome o) {
  if (o.marketLine?.closed == true) return GameLineStatus.settled;
  final shown = polyShownChanceOf(prices, unpriced, o);
  if (shown == null) return GameLineStatus.notTrading;
  final live = o.tokenId == null ? null : prices[o.tokenId];
  if (live == null && (o.price - 0.5).abs() < 0.0005) {
    return GameLineStatus.notTrading;
  }
  if (shown > 0.99 || shown < 0.01) return GameLineStatus.settled;
  return GameLineStatus.open;
}

/// What a side tap hands the page: the line's market, the side (0 its
/// first token, 1 its second) and the two sides' names for the slip.
typedef GameLineSideTap = void Function(
  PolymarketOutcome market,
  int side, {
  required String pos,
  required String neg,
});

/// A game's "More markets" as slivers: the title, the chips and the lines.
/// [outcomes] are the markets the board does not show, in the event's
/// order.
class PolyGameMoreMarkets extends ConsumerStatefulWidget {
  final PolymarketEvent event;
  final List<PolymarketTeam> teams;
  final List<PolymarketOutcome> outcomes;
  final GameLineSideTap onSide;

  /// Opens the market's own page (its chart, its rules), as a tap on a
  /// line's label.
  final void Function(PolymarketOutcome market) onOpen;

  const PolyGameMoreMarkets({
    super.key,
    required this.event,
    required this.teams,
    required this.outcomes,
    required this.onSide,
    required this.onOpen,
  });

  @override
  ConsumerState<PolyGameMoreMarkets> createState() =>
      _PolyGameMoreMarketsState();
}

/// A list of statuses, compared by value: what the price selector hands
/// back, so a tick rebuilds the list only when a line changes group.
class _StatusKey {
  final List<GameLineStatus> statuses;
  const _StatusKey(this.statuses);

  @override
  bool operator ==(Object other) {
    if (other is! _StatusKey || other.statuses.length != statuses.length) {
      return false;
    }
    for (var i = 0; i < statuses.length; i++) {
      if (other.statuses[i] != statuses[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(statuses);
}

class _PolyGameMoreMarketsState extends ConsumerState<PolyGameMoreMarkets> {
  static const String _all = 'all';

  /// The lines a kind shows, with every period and kind listed, before
  /// its "Show N more".
  static const int _collapseAfter = 4;

  /// A period with more lines than this, of more than one kind, gets the
  /// kind chips.
  static const int _typeChipsAfter = 8;

  String _period = _all;
  String _type = _all;

  /// Groups opened past their first lines, and the folded "Not trading
  /// yet" / "Settled" groups opened, by period and group.
  final Set<String> _opened = {};

  GameLineReader? _reader;
  PolymarketEvent? _readerEvent;
  List<PolymarketTeam>? _readerTeams;

  GameLineReader get _lines {
    final e = widget.event;
    if (_reader == null ||
        !identical(_readerEvent, e) ||
        !identical(_readerTeams, widget.teams)) {
      _readerEvent = e;
      _readerTeams = widget.teams;
      _reader = GameLineReader(
        eventTitle: e.title,
        teams: widget.teams,
        esports: e.tags.contains('esports'),
        outcomes: e.outcomes,
      );
    }
    return _reader!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final outcomes = widget.outcomes;
    if (outcomes.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final reader = _lines;
    final rows = [for (final o in outcomes) reader.read(o)];
    final statuses = ref
        .watch(livePriceProvider.select((s) => _StatusKey([
              for (final o in outcomes) gameLineStatus(s.prices, s.unpriced, o),
            ])))
        .statuses;

    // The periods, whole match first.
    final periods = {for (final r in rows) r.period}.toList()..sort();
    final fullGame = periods.any((p) => const {
          GamePeriodUnit.quarter,
          GamePeriodUnit.period,
          GamePeriodUnit.firstFive,
          GamePeriodUnit.inning,
        }.contains(p.unit));
    final showPeriods = periods.length > 1;
    final periodKeys = [_all, for (final p in periods) p.key];
    final period = showPeriods && periodKeys.contains(_period) ? _period : _all;
    final inPeriod = [
      for (var i = 0; i < rows.length; i++)
        if (period == _all || rows[i].period.key == period) i
    ];

    // The kinds of the period's open lines.
    final open = [
      for (final i in inPeriod)
        if (statuses[i] == GameLineStatus.open) i
    ];
    final types = {for (final i in open) rows[i].type}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final showTypes = types.length > 1 && open.length > _typeChipsAfter;
    final typeKeys = [_all, for (final t in types) t.key];
    final type = showTypes && typeKeys.contains(_type) ? _type : _all;
    bool ofType(int i) => type == _all || rows[i].type.key == type;

    // Most useful first: by kind, by period, by team or player (in the
    // order the event first names them), by line; another question by
    // its chance, most likely first.
    final firstSeen = <String, int>{};
    for (var i = 0; i < rows.length; i++) {
      firstSeen.putIfAbsent(rows[i].subject.toLowerCase(), () => i);
    }
    int order(int a, int b) {
      final ra = rows[a], rb = rows[b];
      var c = ra.type.index.compareTo(rb.type.index);
      if (c != 0) return c;
      c = ra.period.compareTo(rb.period);
      if (c != 0) return c;
      c = firstSeen[ra.subject.toLowerCase()]!
          .compareTo(firstSeen[rb.subject.toLowerCase()]!);
      if (c != 0) return c;
      final la = ra.line, lb = rb.line;
      if (la != null && lb != null) {
        c = la.abs().compareTo(lb.abs());
        if (c != 0) return c;
        c = la.compareTo(lb);
        if (c != 0) return c;
      }
      if (ra.type == GameLineType.other) {
        c = outcomes[b].price.compareTo(outcomes[a].price);
        if (c != 0) return c;
      }
      return a.compareTo(b);
    }

    final shown = [
      for (final i in open)
        if (ofType(i)) i
    ]..sort(order);
    final waiting = [
      for (final i in inPeriod)
        if (statuses[i] == GameLineStatus.notTrading && ofType(i)) i
    ]..sort(order);
    final settled = [
      for (final i in inPeriod)
        if (statuses[i] == GameLineStatus.settled && ofType(i)) i
    ]..sort(order);

    final groups = <GameLineType, List<int>>{};
    for (final i in shown) {
      (groups[rows[i].type] ??= []).add(i);
    }
    // Headings name a kind's lines, unless a kind chip already does.
    final headed = groups.length > 1 || type == _all;
    final withPeriod = period == _all && showPeriods;

    String periodName(GamePeriod p) =>
        gamePeriodName(l10n, p, fullGame: fullGame);

    /// A line's title: its period (with every period listed), its kind
    /// (unless a heading says it, or its words do) and its label.
    String title(GameLineRow r, {required bool kindShown}) {
      final parts = <String>[
        if (withPeriod && !r.period.isWhole) periodName(r.period),
        if (!kindShown &&
            (r.label.isEmpty ||
                (r.type != GameLineType.other &&
                    r.type != GameLineType.players)))
          gameLineTypeName(l10n, r.type),
        if (r.label.isNotEmpty) r.label,
      ];
      return parts.isEmpty ? gameLineTypeName(l10n, r.type) : parts.join(' · ');
    }

    final entries = <Widget Function(BuildContext)>[];
    Widget tile(int i, String text, {bool muted = false}) {
      final r = rows[i];
      final o = outcomes[i];
      final names = _sideNames(l10n, r);
      final slip = _slipNames(l10n, r, o);
      return _GameLineTile(
        key: ValueKey('game-line-${o.tokenId ?? o.gammaMarketId ?? i}'),
        outcome: o,
        title: text,
        sideA: names.$1,
        sideB: names.$2,
        muted: muted,
        onOpen: () => widget.onOpen(o),
        onSide: (side) => widget.onSide(o, side, pos: slip.$1, neg: slip.$2),
      );
    }

    Widget heading(String text, {required bool first}) => Padding(
          padding:
              EdgeInsets.only(top: first ? 4.h : 18.h, bottom: 2.h, left: 4.w),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        );

    Widget toggle(String text, {required bool open, required String key}) =>
        InkWell(
          key: ValueKey('game-lines-toggle-$key'),
          borderRadius: BorderRadius.circular(12.r),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (!_opened.remove(key)) _opened.add(key);
            });
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(width: 2.w),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18.sp,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
        );

    var first = true;
    for (final MapEntry(key: kind, value: lines) in groups.entries) {
      final withHeading = headed && lines.length > 1;
      if (withHeading) {
        final isFirst = first;
        entries
            .add((_) => heading(gameLineTypeName(l10n, kind), first: isFirst));
      } else if (!first) {
        // A lone line of another kind: the room a heading would take.
        entries.add((_) => SizedBox(height: 10.h));
      }
      first = false;
      final openKey = '$period/${kind.key}';
      final folded = type == _all &&
          groups.length > 1 &&
          lines.length > _collapseAfter + 1 &&
          !_opened.contains(openKey);
      for (final i in folded ? lines.take(_collapseAfter) : lines) {
        final text = title(rows[i], kindShown: withHeading || !headed);
        entries.add((_) => tile(i, text));
      }
      if (folded) {
        final more = lines.length - _collapseAfter;
        entries.add((context) => InkWell(
              key: ValueKey('game-lines-more-${kind.key}'),
              borderRadius: BorderRadius.circular(12.r),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _opened.add(openKey));
              },
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
                child: Text(
                  context.l10n.salShowMore(more),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ));
      }
    }

    // The folded groups at the foot: their lines carry their kind.
    var lastWasFold = false;
    void foldedGroup(List<int> lines, String key, String label) {
      if (lines.isEmpty) return;
      final openKey = '$period/$key';
      final isOpen = _opened.contains(openKey);
      // Room above the first fold only: a second fold sits right under it.
      final pad = entries.isNotEmpty && !lastWasFold;
      lastWasFold = !isOpen;
      entries.add((_) => Padding(
            padding: EdgeInsets.only(top: pad ? 8.h : 0),
            child: toggle(label, open: isOpen, key: openKey),
          ));
      if (!isOpen) return;
      for (final i in lines) {
        final text = title(rows[i], kindShown: false);
        entries.add((_) => tile(i, text, muted: true));
      }
    }

    foldedGroup(
        waiting, 'not_trading', l10n.polyLinesNotTrading(waiting.length));
    foldedGroup(settled, 'settled', l10n.polyLinesSettled(settled.length));

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24.h),
        Text(
          l10n.polyMoreMarkets,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (showPeriods) ...[
          SizedBox(height: 10.h),
          PolyAutoScrollRow(
            key: const ValueKey('game-period-chips'),
            height: 34.h,
            padding: 0,
            itemCount: periodKeys.length,
            selectedIndex: periodKeys.indexOf(period),
            itemBuilder: (context, i) {
              final key = periodKeys[i];
              return KutePill(
                label:
                    key == _all ? l10n.polySubAll : periodName(periods[i - 1]),
                selected: key == period,
                onTap: () {
                  if (key == period) return;
                  HapticFeedback.selectionClick();
                  TrackingService.track('category_pill_tapped', params: {
                    'section': 'game_periods',
                    'subcategory': key,
                  });
                  setState(() => _period = key);
                },
              );
            },
          ),
        ],
        if (showTypes) ...[
          SizedBox(height: showPeriods ? 6.h : 10.h),
          PolyAutoScrollRow(
            key: const ValueKey('game-type-chips'),
            height: KutePillSize.compact.height.h,
            padding: 0,
            itemCount: typeKeys.length,
            selectedIndex: typeKeys.indexOf(type),
            itemBuilder: (context, i) {
              final key = typeKeys[i];
              return KutePill(
                size: KutePillSize.compact,
                label: key == _all
                    ? l10n.polySubAll
                    : gameLineTypeName(l10n, types[i - 1]),
                selected: key == type,
                onTap: () {
                  if (key == type) return;
                  HapticFeedback.selectionClick();
                  TrackingService.track('category_pill_tapped', params: {
                    'section': 'game_markets',
                    'subcategory': key,
                  });
                  setState(() => _type = key);
                },
              );
            },
          ),
        ],
        SizedBox(height: 8.h),
      ],
    );

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: head),
        // A chip fades the list in; a price tick never does. The lines are
        // built as they scroll into view.
        SliverSelectionFade(
          selection: '$period/$type',
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => entries[i](context),
                childCount: entries.length,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The two buttons' names: Yes / No and Over / Under in the app's
  /// language, else the line's own (teams, a team and its line).
  static (String, String) _sideNames(AppLocalizations l10n, GameLineRow r) =>
      switch (r.words) {
        GameSideWords.yesNo => (l10n.yes, l10n.betNo),
        GameSideWords.overUnder => (l10n.polySideOver, l10n.polySideUnder),
        GameSideWords.named => (r.sideA, r.sideB),
      };

  /// The sides as the slip names them: a total's with its line ("Over
  /// 24.5"), a winner's teams whole, any other as its buttons do.
  static (String, String) _slipNames(
      AppLocalizations l10n, GameLineRow r, PolymarketOutcome o) {
    final names = _sideNames(l10n, r);
    if (r.words == GameSideWords.overUnder) {
      final line = r.type == GameLineType.duration
          ? r.label
          : (r.line == null ? '' : _number(r.line!));
      if (line.isEmpty) return names;
      return ('${names.$1} $line', '${names.$2} $line');
    }
    final sides = o.marketLine?.sides ?? const [];
    if (r.type == GameLineType.winner && sides.length == 2) {
      return (sides[0], sides[1]);
    }
    return names;
  }

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

/// One line: its label, then its two sides with their chances. The two
/// figures follow the line's own token on the live feed: a tick repaints
/// this line's buttons alone.
class _GameLineTile extends StatelessWidget {
  final PolymarketOutcome outcome;
  final String title;
  final String sideA;
  final String sideB;
  final bool muted;
  final VoidCallback onOpen;
  final void Function(int side) onSide;

  const _GameLineTile({
    super.key,
    required this.outcome,
    required this.title,
    required this.sideA,
    required this.sideB,
    required this.muted,
    required this.onOpen,
    required this.onSide,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final token = outcome.tokenId ?? '';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8.r),
              onTap: () {
                HapticFeedback.lightImpact();
                onOpen();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 4.w),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted ? c.textSecondary : c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Consumer(builder: (context, ref, _) {
            final live = ref.watch(livePriceProvider
                .select((s) => (s.prices[token], s.unpriced.contains(token))));
            final chance = polyShownChanceOf(
                {if (live.$1 != null) token: live.$1!},
                {if (live.$2) token},
                outcome);
            final pair = chance == null ? null : formatPolyChancePair(chance);
            Widget side(int i) => SizedBox(
                  width: 98.w,
                  child: PolyGameSideButton(
                    key: ValueKey('game-line-side-$token-$i'),
                    dense: true,
                    label: i == 0 ? sideA : sideB,
                    pctText: pair == null
                        ? '—'
                        : (i == 0 ? pair.first : pair.second),
                    muted: muted || pair == null,
                    onTap: () => onSide(i),
                  ),
                );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [side(0), SizedBox(width: 8.w), side(1)],
            );
          }),
        ],
      ),
    );
  }
}
