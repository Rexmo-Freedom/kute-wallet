// lib/screens/shared/portfolio_builder/builder_market_card.dart
//
// The portfolio Builder's pick card: a Predictions list card
// (polymarket/components/market_card.dart) whose answers can be picked.
// Same frame, thumbnail, title and quiet footer, in the same three shapes
// (market_card_shape.dart):
//
//   * a Yes/No market: the title and the Yes chance; the card is the tap;
//   * a game: a row per team (crest, name, win chance), and the draw on a
//     three-way market, each a tap of its own;
//   * an event with many outcomes: its most likely ones, each a tap of
//     its own, and "+N more" to list them all.
//
// Presentation only. What a tap becomes (the leg, its tokens and prices)
// is decided by the Builder screen; the card reports the event or the
// outcome tapped.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventTeamsProvider;
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

/// An outcome can be a leg only with a token of its own: a leg without
/// one is placed on the event's first market, which is another answer.
bool builderOutcomeSelectable(PolymarketOutcome o) =>
    o.tokenId?.isNotEmpty ?? false;

/// True when [leg] is the leg [outcome] makes.
bool builderLegIsOutcome(PredictionBuilderLeg leg, PolymarketOutcome outcome) =>
    builderOutcomeSelectable(outcome) && leg.yesTokenId == outcome.tokenId;

/// The game on [event] when each side is an outcome of its own (so each
/// can be a leg); null for anything else, a game priced by one Yes/No
/// moneyline included.
PolyCardGame? builderCardGame(PolymarketEvent event) {
  if (event.isBinary) return null;
  final game = polyCardGame(event.title, event.outcomes);
  if (game == null || identical(game.outcomeA, game.outcomeB)) return null;
  return game;
}

/// The thumbnail of a card or a leg: the list card's 40 pt image on its
/// neutral ground, the category's glyph when there is no image.
class BuilderThumb extends StatelessWidget {
  final String? imageUrl;
  final String? category;
  final double? size;
  final double? radius;

  const BuilderThumb({
    super.key,
    this.imageUrl,
    this.category,
    this.size,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = this.size ?? 40.w;
    final radius = this.radius ?? 10.r;
    final glyph = Center(
      child: Icon(polyCategoryGlyph(category),
          color: c.textSecondary, size: size * 0.46),
    );
    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: url != null && url.isNotEmpty
          ? PolyCrestImage(
              url: url, size: size, radius: radius, fallback: glyph)
          : glyph,
    );
  }
}

/// The pick control: "+" while free, a check once picked.
class BuilderSelectMark extends StatelessWidget {
  final bool selected;
  final bool enabled;

  const BuilderSelectMark(
      {super.key, required this.selected, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedSwitcher(
      duration: kuteMotion(context, const Duration(milliseconds: 150)),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.add_circle_outline_rounded,
        key: ValueKey<bool>(selected),
        size: 22.sp,
        color: selected
            ? context.ctaFill
            : enabled
                ? c.textTertiary
                : c.borderSubtle,
      ),
    );
  }
}

/// The frame every Builder card shares: the app card, with the primary
/// outline while [selected] (drawn over the card, so nothing moves).
class BuilderCardFrame extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const BuilderCardFrame({
    super.key,
    this.selected = false,
    this.onTap,
    this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    final body = Padding(
      padding: padding ?? EdgeInsets.all(16.w),
      child: child,
    );
    // The outline eases in and out with the pick (150 ms); at once under
    // Reduce Motion.
    return AnimatedContainer(
      duration: kuteMotion(context, const Duration(milliseconds: 150)),
      curve: Curves.easeOut,
      decoration: AppDecorations.card(context),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: selected ? context.ctaFill : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: onTap == null
            ? body
            : InkWell(onTap: onTap, borderRadius: radius, child: body),
      ),
    );
  }
}

class BuilderMarketCard extends ConsumerStatefulWidget {
  final PolymarketEvent event;

  /// The draft's leg on this event, when it has one.
  final PredictionBuilderLeg? leg;

  /// A tap: the outcome tapped, or null for a Yes/No market (the market
  /// itself is the pick).
  final void Function(PolymarketOutcome? outcome) onToggle;

  const BuilderMarketCard({
    super.key,
    required this.event,
    required this.leg,
    required this.onToggle,
  });

  @override
  ConsumerState<BuilderMarketCard> createState() => _BuilderMarketCardState();
}

class _BuilderMarketCardState extends ConsumerState<BuilderMarketCard> {
  /// "+N more" was tapped: every outcome is listed.
  bool _expanded = false;

  static TextStyle _figure(Color color) => TextStyle(
        color: color,
        fontSize: 20.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle _caption(AppColorsExtension c) => TextStyle(
        color: c.textTertiary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  PolymarketEvent get _event => widget.event;

  bool _picked(PolymarketOutcome o) {
    final leg = widget.leg;
    return leg != null && builderLegIsOutcome(leg, o);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = _event;
    final game = builderCardGame(e);
    final yesNo = game == null && (e.isBinary || e.outcomes.isEmpty);

    // Crests, as the list card finds them: the event's own teams, or the
    // lazy read by slug for a match the search path sent without them.
    var teams = e.teams;
    final looksLikeMatch = e.gameId != null ||
        RegExp(r'\svs\.?\s', caseSensitive: false).hasMatch(e.title);
    if (teams.isEmpty && looksLikeMatch && e.slug.isNotEmpty) {
      teams = ref.watch(polymarketEventTeamsProvider(e.slug)).valueOrNull ??
          const [];
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (game != null)
          _gameRows(c, game, teams)
        else if (yesNo)
          _heading(
            c,
            teams,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(polyCardChance(e.yesPrice), style: _figure(c.textPrimary)),
                SizedBox(width: 10.w),
                BuilderSelectMark(selected: widget.leg != null),
              ],
            ),
          )
        else
          _outcomeRows(c, teams),
        SizedBox(height: 12.h),
        _footer(c, game: game, yesNo: yesNo),
      ],
    );

    return Semantics(
      container: true,
      button: yesNo,
      selected: widget.leg != null,
      child: BuilderCardFrame(
        selected: widget.leg != null,
        onTap: yesNo ? () => widget.onToggle(null) : null,
        child: content,
      ),
    );
  }

  Widget _heading(AppColorsExtension c, List<PolymarketTeam> teams,
      {Widget? trailing}) {
    final e = _event;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuilderThumb(
            imageUrl: e.displayIconUrlWithTeams(teams), category: e.category),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            // Written whole: the card grows with its title.
            e.title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.25,
            ),
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 10.w),
          trailing,
        ],
      ],
    );
  }

  /// One answer of the card: what it is on the left, its chance and the
  /// pick control on the right. The row is the tap.
  Widget _answerRow(
    AppColorsExtension c, {
    required PolymarketOutcome outcome,
    required Widget label,
    required double chance,
    required TextStyle chanceStyle,
    Widget? leading,
  }) {
    final enabled = builderOutcomeSelectable(outcome);
    final picked = _picked(outcome);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: picked,
      child: InkWell(
        onTap: enabled ? () => widget.onToggle(outcome) : null,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Row(
            children: [
              if (leading != null) ...[leading, SizedBox(width: 12.w)],
              Expanded(child: label),
              SizedBox(width: 12.w),
              Text(polyCardChance(chance), style: chanceStyle),
              SizedBox(width: 10.w),
              BuilderSelectMark(selected: picked, enabled: enabled),
            ],
          ),
        ),
      ),
    );
  }

  /// A game: a row per team in the title's order, then the draw where
  /// the market has one.
  Widget _gameRows(
      AppColorsExtension c, PolyCardGame game, List<PolymarketTeam> teams) {
    final leader = polyCardLeader(chanceA: game.chanceA, chanceB: game.chanceB);
    final crestSize = 28.w;

    Widget team(String name, double chance, PolymarketOutcome o, bool leads) {
      final tone = leads ? c.textPrimary : c.textSecondary;
      return _answerRow(
        c,
        outcome: o,
        chance: chance,
        chanceStyle: _figure(tone),
        leading: BuilderThumb(
          imageUrl: PolymarketEvent.logoFromTeams(teams, name) ?? o.imageUrl,
          category: _event.category,
          size: crestSize,
          radius: 8.r,
        ),
        label: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tone,
            fontSize: 16.sp,
            fontWeight: leads ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      );
    }

    PolymarketOutcome? draw;
    if (game.draw != null) {
      for (final o in _event.outcomes) {
        if (!identical(o, game.outcomeA) && !identical(o, game.outcomeB)) {
          draw = o;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        team(game.nameA, game.chanceA, game.outcomeA, leader >= 0),
        team(game.nameB, game.chanceB, game.outcomeB, leader <= 0),
        if (draw != null)
          _answerRow(
            c,
            outcome: draw,
            chance: game.draw!,
            chanceStyle: _figure(c.textSecondary),
            leading: SizedBox(width: crestSize),
            label: Text(
              context.l10n.betDraw,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
      ],
    );
  }

  /// Every outcome, most likely first; equal chances keep the feed's
  /// order. Fillers with no market behind them ("Candidate A" at Gamma's
  /// default 50%) are left out: there is nothing to predict on them.
  List<PolymarketOutcome> _ranked() {
    final outcomes = polyRealOutcomes(_event.outcomes);
    final indexed = [for (var i = 0; i < outcomes.length; i++) i];
    indexed.sort((x, y) {
      final byPrice = outcomes[y].price.compareTo(outcomes[x].price);
      return byPrice != 0 ? byPrice : x.compareTo(y);
    });
    return [for (final i in indexed) outcomes[i]];
  }

  /// The outcomes on show: the two most likely (and the picked one), or
  /// all of them once "+N more" was tapped.
  List<PolymarketOutcome> _shown() {
    final ranked = _ranked();
    if (_expanded || ranked.length <= 2) return ranked;
    return [
      for (var i = 0; i < ranked.length; i++)
        if (i < 2 || _picked(ranked[i])) ranked[i],
    ];
  }

  Widget _outcomeRows(AppColorsExtension c, List<PolymarketTeam> teams) {
    final shown = _shown();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading(c, teams),
        SizedBox(height: 6.h),
        for (var i = 0; i < shown.length; i++)
          _answerRow(
            c,
            outcome: shown[i],
            chance: shown[i].price,
            chanceStyle: TextStyle(
              color: i == 0 ? c.textPrimary : c.textSecondary,
              fontSize: 15.sp,
              fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            label: Text(
              shown[i].name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: i == 0 ? c.textPrimary : c.textSecondary,
                fontSize: 15.sp,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
      ],
    );
  }

  String _volume(double v) {
    if (v >= 1000000) {
      return '${formatPolyAmount(ref, v / 1000000, decimalDigits: 1)}M';
    } else if (v >= 1000) {
      return '${formatPolyAmount(ref, v / 1000, decimalDigits: 1)}K';
    }
    return formatPolyAmount(ref, v, decimalDigits: 0);
  }

  /// When the market ends, or when the game starts.
  String? _date(PolyCardGame? game) {
    final e = _event;
    final now = DateTime.now();
    if (game != null) {
      final kickoff = e.gameStart ??
          (e.startDate != null && e.startDate!.isAfter(now)
              ? e.startDate
              : null);
      if (kickoff != null) {
        return DateFormat('MMM d, HH:mm').format(kickoff.toLocal());
      }
    }
    final end = e.endDate;
    return end == null ? null : DateFormat('MMM d, yyyy').format(end);
  }

  /// One caption line: the date (or "+N more") on the left, the volume
  /// on the right.
  Widget _footer(AppColorsExtension c,
      {required PolyCardGame? game, required bool yesNo}) {
    final l10n = context.l10n;
    final style = _caption(c);
    final hidden = game != null || yesNo || _expanded
        ? 0
        : polyRealOutcomes(_event.outcomes).length - _shown().length;
    final date = _date(game);
    final volume = _event.volume;
    return Row(
      children: [
        Expanded(
          child: hidden > 0
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = true),
                    borderRadius: BorderRadius.circular(6.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.polyCardMoreOutcomes(hidden),
                              style: style.copyWith(color: c.textSecondary)),
                          Icon(Icons.expand_more_rounded,
                              size: 16.sp, color: c.textTertiary),
                        ],
                      ),
                    ),
                  ),
                )
              : Text(date ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
        if (volume > 0) ...[
          SizedBox(width: 12.w),
          Text(l10n.polyCardVolume(_volume(volume)),
              maxLines: 1, style: style),
        ],
      ],
    );
  }
}
