// lib/screens/polymarket/components/special_event_section.dart
//
// The market page's drawing of a special US election event
// (special_event_map.dart), between the chart and the outcome list, which
// stays as it is:
//
//   * State markets: a map of each state's Yes chance (green, deeper the
//     likelier), "Yes leads in 9 of 22 states" above it; a tap on a state
//     opens its own market, as its row below does.
//   * Build your map: the map of the most likely combination, each state
//     in the colour of the side it goes and deeper the likelier that side
//     is, "Republicans favoured in 0 of 7 states" above it. A tap on a
//     state outlines it and shows its sides as pills with their chances;
//     a pill puts that side on your map. The row under the map names the
//     market your map is ("AK, TX") and its chance, and opens it: one real
//     market of the event, never a combination the app makes up.
//   * Balance of power: one bar per race (Senate, House) split between the
//     parties by their chance of winning it.
//
// Live: the section follows the price feed for its own markets only.
// Nothing here is logged; opening a market goes through the page's own
// path ([PolySpecialEventSection.onPickOutcome]).

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/us_states.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/polymarket/components/us_state_map.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/services/polymarket/special_event_map.dart';
import 'package:kute/theme/app_theme.dart';

/// The Republican party's red on the map and the race bars.
const Color kPolyRepublicanRed = Color(0xFFE5484D);

/// The Democratic party's blue.
const Color kPolyDemocratBlue = Color(0xFF2F6FED);

/// An independent's purple.
const Color kPolyIndependentPurple = Color(0xFF9B6BDA);

/// The colour of [side] on the map, its legend and its pills: a party's
/// own; the side a named party loses, the other party's; Yes and No the
/// app's up green and down red.
Color polyMapSideColor(PolyMapSide side) => switch (side) {
      PolyMapSide.rep || PolyMapSide.notDem => kPolyRepublicanRed,
      PolyMapSide.dem || PolyMapSide.notRep => kPolyDemocratBlue,
      PolyMapSide.ind => kPolyIndependentPurple,
      PolyMapSide.yes => AppColors.marketUp,
      PolyMapSide.no => AppColors.marketDown,
    };

/// A state's fill: [hue] over the [neutral] grey, deeper the likelier
/// ([chance], 0 to 1); never lighter than a fifth of the hue, so a long
/// shot still shows its colour.
Color polyMapFill(Color hue, double chance, Color neutral) =>
    Color.lerp(neutral, hue, 0.22 + 0.78 * chance.clamp(0.0, 1.0))!;

/// What [side] is called on the legend and the pills.
String polyMapSideLabel(AppLocalizations l10n, PolyMapSide side) =>
    switch (side) {
      PolyMapSide.rep => l10n.polyMapRepublican,
      PolyMapSide.dem => l10n.polyMapDemocratic,
      PolyMapSide.ind => l10n.polyMapIndependent,
      PolyMapSide.notRep => l10n.polyMapNotRepublican,
      PolyMapSide.notDem => l10n.polyMapNotDemocratic,
      PolyMapSide.yes => l10n.yes,
      PolyMapSide.no => l10n.betNo,
    };

/// The live prices of the section's own tokens: equal while none of them
/// moved, so a tick elsewhere rebuilds nothing.
@immutable
class _Quotes {
  final Map<String, double> prices;
  final Set<String> unpriced;

  const _Quotes(this.prices, this.unpriced);

  factory _Quotes.of(LivePriceState s, List<String> tokens) => _Quotes(
        {
          for (final t in tokens)
            if (s.prices[t] != null) t: s.prices[t]!,
        },
        {
          for (final t in tokens)
            if (s.unpriced.contains(t)) t,
        },
      );

  double? chanceOf(PolymarketOutcome o) =>
      polyShownChanceOf(prices, unpriced, o);

  @override
  bool operator ==(Object other) =>
      other is _Quotes &&
      mapEquals(other.prices, prices) &&
      setEquals(other.unpriced, unpriced);

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(
          prices.entries.map((e) => Object.hash(e.key, e.value))),
      Object.hashAllUnordered(unpriced));
}

class PolySpecialEventSection extends ConsumerWidget {
  final PolymarketEvent event;

  /// Opens one of the event's markets, as its row in the list does.
  final void Function(PolymarketOutcome outcome) onPickOutcome;

  const PolySpecialEventSection({
    super.key,
    required this.event,
    required this.onPickOutcome,
  });

  /// The section as a sliver of the market page: empty for an event that
  /// is not special.
  static Widget sliver(
    PolymarketEvent event, {
    required void Function(PolymarketOutcome outcome) onPickOutcome,
  }) {
    if (polySpecialEventOf(event) == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: 8.h, bottom: 20.h),
        child: PolySpecialEventSection(
            event: event, onPickOutcome: onPickOutcome),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final special = polySpecialEventOf(event);
    if (special == null) return const SizedBox.shrink();
    final tokens = [
      for (final o in special.outcomes)
        if (o.tokenId != null && o.tokenId!.isNotEmpty) o.tokenId!,
    ];
    final quotes =
        ref.watch(livePriceProvider.select((s) => _Quotes.of(s, tokens)));
    return switch (special) {
      PolyStateMarkets m => _StateMarketsMap(
          markets: m, chanceOf: quotes.chanceOf, onPick: onPickOutcome),
      PolyStateCombos m => PolyBuildYourMap(
          map: m, chanceOf: quotes.chanceOf, onPick: onPickOutcome),
      PolyBalanceOfPower b =>
        _RaceBars(balance: b, chanceOf: quotes.chanceOf),
    };
  }
}

TextStyle _summaryStyle(AppColorsExtension c) => TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );

TextStyle _legendStyle(AppColorsExtension c) => TextStyle(
      color: c.textSecondary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
    );

Widget _dot(Color color, {double? size}) => Container(
      width: size ?? 8.r,
      height: size ?? 8.r,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

Widget _legendItem(AppColorsExtension c, Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(color),
        SizedBox(width: 6.w),
        Text(label, style: _legendStyle(c)),
      ],
    );

/// One Yes / No market per state: each state's Yes chance.
class _StateMarketsMap extends StatelessWidget {
  final PolyStateMarkets markets;
  final PolyChanceOf chanceOf;
  final void Function(PolymarketOutcome outcome) onPick;

  const _StateMarketsMap({
    required this.markets,
    required this.chanceOf,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final neutral = UsStateMap.neutralOf(context);
    final chances = {
      for (final e in markets.byState.entries) e.key: chanceOf(e.value),
    };
    final yes = chances.values.where((p) => p != null && p > 0.5).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.polyMapYesLeads(yes, markets.byState.length),
            style: _summaryStyle(c)),
        SizedBox(height: 10.h),
        UsStateMap(
          fills: {
            for (final e in chances.entries)
              if (e.value != null)
                e.key: polyMapFill(AppColors.marketUp, e.value!, neutral),
          },
          tappable: markets.byState.keys.toSet(),
          labelled: markets.byState.keys.toSet(),
          onTapState: (code) => onPick(markets.byState[code]!),
          semanticLabels: {
            for (final e in chances.entries)
              e.key: e.value == null
                  ? kUsStateNames[e.key]!
                  : '${kUsStateNames[e.key]!}: ${formatPolyChance(e.value!)}',
          },
        ),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 14.w,
          runSpacing: 6.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.polyMapChanceOfYes, style: _legendStyle(c)),
                SizedBox(width: 8.w),
                Text('0%', style: _legendStyle(c)),
                SizedBox(width: 4.w),
                Container(
                  width: 56.w,
                  height: 8.r,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4.r),
                    gradient: LinearGradient(colors: [
                      polyMapFill(AppColors.marketUp, 0, neutral),
                      polyMapFill(AppColors.marketUp, 1, neutral),
                    ]),
                  ),
                ),
                SizedBox(width: 4.w),
                Text('100%', style: _legendStyle(c)),
              ],
            ),
            _legendItem(c, neutral, l10n.polyMapNoMarket),
          ],
        ),
      ],
    );
  }
}

/// Build your map: the most likely combination of states, or the one the
/// user picks, and the market it is.
class PolyBuildYourMap extends StatefulWidget {
  final PolyStateCombos map;
  final PolyChanceOf chanceOf;
  final void Function(PolymarketOutcome outcome) onPick;

  const PolyBuildYourMap({
    super.key,
    required this.map,
    required this.chanceOf,
    required this.onPick,
  });

  @override
  State<PolyBuildYourMap> createState() => _PolyBuildYourMapState();
}

class _PolyBuildYourMapState extends State<PolyBuildYourMap> {
  /// The user's map; null follows the most likely one as prices move.
  Map<String, PolyMapSide>? _picks;

  /// The state whose sides show under the map.
  String? _selected;

  PolyStateCombos get map => widget.map;

  String _summary(AppLocalizations l10n, int count) {
    final total = map.states.length;
    return switch (map.lead) {
      PolyMapSide.rep => l10n.polyMapRepublicansFavoured(count, total),
      PolyMapSide.dem => l10n.polyMapDemocratsFavoured(count, total),
      _ => l10n.polyMapYesLeads(count, total),
    };
  }

  void _pick(String state, PolyMapSide side, Map<String, PolyMapSide> now) {
    if (now[state] == side) return;
    HapticFeedback.selectionClick();
    setState(() => _picks = {...now, state: side});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final neutral = UsStateMap.neutralOf(context);
    final odds = polyComboStateOdds(map, widget.chanceOf);
    final likely = polyMostLikelyCombo(map, widget.chanceOf);
    final picks = _picks ??
        likely?.picks ??
        {for (final s in map.states) s: map.sidesOf(s).first};
    final combo = map.comboFor(picks);
    final isLikely = likely != null && identical(combo, likely);
    final selected = _selected;
    String sideOdds(String state, PolyMapSide side) {
      final p = odds[state]?[side];
      return p == null ? '—' : formatPolyChance(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (odds.isNotEmpty) ...[
          Text(_summary(l10n, polyStatesFavouring(odds, map.lead)),
              style: _summaryStyle(c)),
          SizedBox(height: 10.h),
        ],
        UsStateMap(
          fills: {
            for (final s in map.states)
              s: polyMapFill(polyMapSideColor(picks[s]!),
                  odds[s]?[picks[s]] ?? 0, neutral),
          },
          tappable: map.states.toSet(),
          labelled: map.states.toSet(),
          selected: selected,
          onTapState: (code) => setState(() => _selected = code),
          semanticLabels: {
            for (final s in map.states)
              s: [
                l10n.polyMapStatePick(kUsStateNames[s]!,
                    polyMapSideLabel(l10n, picks[s]!)),
                for (final side in map.sidesOf(s))
                  '${polyMapSideLabel(l10n, side)} ${sideOdds(s, side)}',
              ].join('. '),
          },
        ),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 14.w,
          runSpacing: 6.h,
          children: [
            for (final side in map.sides)
              _legendItem(c, polyMapSideColor(side), polyMapSideLabel(l10n, side)),
            _legendItem(c, neutral, l10n.polyMapNoMarket),
          ],
        ),
        SizedBox(height: 14.h),
        if (selected == null)
          Text(l10n.polyMapTapToBuild, style: _summaryStyle(c))
        else ...[
          Text(
            kUsStateNames[selected]!,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final side in map.sidesOf(selected))
                KutePill(
                  key: ValueKey('poly-map-side-$selected-${side.name}'),
                  label: polyMapSideLabel(l10n, side),
                  detail: sideOdds(selected, side),
                  leading: _dot(polyMapSideColor(side)),
                  selected: picks[selected] == side,
                  onTap: () => _pick(selected, side, picks),
                ),
            ],
          ),
        ],
        SizedBox(height: 6.h),
        _mapRow(c, l10n, combo, isLikely),
        if (_picks != null && !isLikely && likely != null)
          InkWell(
            borderRadius: BorderRadius.circular(12.r),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _picks = null);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
              child: Text(l10n.polyMapBackToMostLikely,
                  style: _summaryStyle(c)),
            ),
          ),
      ],
    );
  }

  /// "Most likely map" or "Your map": the market it is, its chance, and a
  /// tap opens it; when the event lists no market for it, says so.
  Widget _mapRow(AppColorsExtension c, AppLocalizations l10n,
      PolyMapCombo? combo, bool isLikely) {
    final title = Text(
      isLikely ? l10n.polyMapMostLikely : l10n.polyMapYourMap,
      style: TextStyle(
        color: c.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        height: 1.3,
      ),
    );
    final sub = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    if (combo == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, Text(l10n.polyMapNoSuchMap, style: sub)],
        ),
      );
    }
    final chance = widget.chanceOf(combo.outcome);
    return InkWell(
      key: const ValueKey('poly-map-open-market'),
      borderRadius: BorderRadius.circular(12.r),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPick(combo.outcome);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  Text(combo.outcome.name,
                      style: sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            RollingFigure(
              identity: combo.outcome.tokenId ?? combo.outcome.name,
              text: chance == null ? '—' : formatPolyChance(chance),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(Icons.chevron_right_rounded,
                color: c.textTertiary, size: 18.sp),
          ],
        ),
      ),
    );
  }
}

/// Balance of power: each race split between the parties.
class _RaceBars extends StatelessWidget {
  final PolyBalanceOfPower balance;
  final PolyChanceOf chanceOf;

  const _RaceBars({required this.balance, required this.chanceOf});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final odds = polyRaceOdds(balance, chanceOf);
    if (odds.isEmpty) return const SizedBox.shrink();
    // Democrats from the left, Republicans from the right.
    const order = [PolyMapSide.dem, PolyMapSide.ind, PolyMapSide.rep];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, race) in balance.races.indexed) ...[
          if (i > 0) SizedBox(height: 16.h),
          Text(
            race,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(height: 8.h),
          Semantics(
            label: [
              race,
              for (final side in order)
                if (odds[race]?[side] != null)
                  '${polyMapSideLabel(l10n, side)} '
                      '${formatPolyChance(odds[race]![side]!)}',
            ].join(', '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5.r),
                  child: SizedBox(
                    height: 10.h,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final side in order)
                          if ((odds[race]?[side] ?? 0) > 0)
                            Expanded(
                              flex: (odds[race]![side]! * 1000)
                                  .round()
                                  .clamp(1, 1000),
                              child: ColoredBox(
                                  color: polyMapSideColor(side)),
                            ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    for (final (j, side) in [
                      for (final s in order)
                        if (odds[race]?[s] != null) s,
                    ].indexed) ...[
                      if (j > 0) const Spacer(),
                      _legendItem(
                        c,
                        polyMapSideColor(side),
                        '${polyMapSideLabel(l10n, side)} '
                        '${formatPolyChance(odds[race]![side]!)}',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
