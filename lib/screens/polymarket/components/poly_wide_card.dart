// The wide web Predictions page (founder, 26 and 27 November 2026: "on
// desktop this looks too much"; then a prediction-market site's desktop
// arrangement, built from Kute's own widgets, colours and strings):
//   * [PolyWideFeatured]: one large card for the featured markets: the
//     picture and title, the outcome rows and the volume on the left, the
//     market's own chart on the right, previous / next through the set;
//   * [PolyWideCard]: the grid's card, every one the same height. A small
//     picture (only one a backend image route draws) and the title; then
//     by kind: a Yes / No market its chance and one wide Yes and one wide
//     No; a match its two sides, each with a button named for it; more
//     outcomes the two leaders, each with a small Yes and No; "+N more";
//     the volume. No bars, sparklines or move arrows.
// Every button opens the bet slip with that pick, as the market page's own
// buttons do ([polyCardOpenSlip]): nothing is placed before the slip's
// Confirm. The phone's cards (market_card.dart) are untouched.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlCompactUsd;
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardPick, polyCardTitleStyle, polyThumbShown;
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/poly_chart_history.dart'
    show polyChartOpenedAt;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

/// The narrowest card of the wide grid (logical px).
const double kPolyWideCardMin = 280;

/// The gap between two cards of the wide grid, both ways.
const double kPolyWideCardGap = 16;

/// Every card's height in the wide grid: rows line up.
const double kPolyWideCardHeight = 196;

/// The featured card's height.
const double kPolyWideFeaturedHeight = 300;

/// How many columns of [kPolyWideCardMin] cards fit a content [width].
int polyWideColumns(double width) {
  final n = ((width + kPolyWideCardGap) / (kPolyWideCardMin + kPolyWideCardGap))
      .floor();
  return n < 1 ? 1 : n;
}

/// The two sides' colours, as the bet slip draws them.
const Color _kYes = AppColors.marketUp;
const Color _kNo = AppColors.marketDown;

/// What a grid card's button asks the slip for: a Yes / No side or a
/// match's side ([pick]), or one outcome of many ([outcomeIndex], into the
/// event's outcomes) on its Yes or its No ([no]).
typedef PolyWidePick = ({PolyCardPick? pick, int? outcomeIndex, bool no});

double _price(PolymarketOutcome o, Map<String, double> live) {
  final t = o.tokenId;
  return (t == null ? null : live[t]) ?? o.price;
}

PolymarketOutcome _yesOf(List<PolymarketOutcome> outcomes) =>
    outcomes.firstWhere((o) => o.name.trim().toLowerCase() == 'yes',
        orElse: () => outcomes.first);

/// A side's button in the slip's colours: a soft fill and the colour's
/// own label.
class _SideButton extends StatelessWidget {
  const _SideButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.height = 32,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class PolyWideCard extends StatelessWidget {
  const PolyWideCard({
    super.key,
    required this.title,
    required this.outcomes,
    this.imageUrl,
    this.volume = 0,
    this.livePrices = const {},
    required this.onTap,
    this.onTapDown,
    required this.onPick,
  });

  final String title;
  final List<PolymarketOutcome> outcomes;
  final String? imageUrl;
  final double volume;
  final Map<String, double> livePrices;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final ValueChanged<PolyWidePick> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final game = polyCardGame(title, outcomes, live: livePrices);
    final shape = outcomes.isEmpty
        ? PolyCardShape.outcomes
        : polyCardShape(game, outcomes);
    final nameStyle = TextStyle(
        color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w500);
    final figureStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final List<Widget> body;
    var more = 0;
    switch (shape) {
      case PolyCardShape.yesNo:
        body = [
          Text(
            polyCardChance(_price(_yesOf(outcomes), livePrices)),
            key: const ValueKey('poly-wide-chance'),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _SideButton(
                key: const ValueKey('poly-wide-yes'),
                label: l10n.yes,
                color: _kYes,
                height: 36,
                onTap: () => onPick((
                  pick: const PolyCardPick.side('yes'),
                  outcomeIndex: null,
                  no: false
                )),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SideButton(
                key: const ValueKey('poly-wide-no'),
                label: l10n.betNo,
                color: _kNo,
                height: 36,
                onTap: () => onPick((
                  pick: const PolyCardPick.side('no'),
                  outcomeIndex: null,
                  no: true
                )),
              ),
            ),
          ]),
        ];
      case PolyCardShape.game:
        final g = game!;
        Widget side(String name, double chance, int way, Color color) => Row(
              key: ValueKey('poly-wide-outcome-$way'),
              children: [
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle),
                ),
                const SizedBox(width: 8),
                Text(polyCardChance(chance), style: figureStyle),
                const SizedBox(width: 10),
                SizedBox(
                  width: 104,
                  child: _SideButton(
                    key: ValueKey('poly-wide-side-$way'),
                    label: name,
                    color: color,
                    onTap: () => onPick((
                      pick: PolyCardPick.game(way),
                      outcomeIndex: null,
                      no: false
                    )),
                  ),
                ),
              ],
            );
        body = [
          side(g.nameA, g.chanceA, 0, _kYes),
          const SizedBox(height: 8),
          side(g.nameB, g.chanceB, 1, _kNo),
        ];
      case PolyCardShape.outcomes:
        final top = polyCardTopOutcomes(outcomes, live: livePrices, count: 2);
        more = polyRealOutcomes(outcomes, live: livePrices).length - top.length;
        Widget row(PolymarketOutcome o, int i) {
          final at = outcomes.indexOf(o);
          return Row(
            key: ValueKey('poly-wide-outcome-$i'),
            children: [
              Expanded(
                child: Text(o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle),
              ),
              const SizedBox(width: 8),
              Text(polyCardChance(_price(o, livePrices)), style: figureStyle),
              const SizedBox(width: 10),
              SizedBox(
                width: 46,
                child: _SideButton(
                  key: ValueKey('poly-wide-yes-$i'),
                  label: l10n.yes,
                  color: _kYes,
                  onTap: () =>
                      onPick((pick: null, outcomeIndex: at, no: false)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 46,
                child: _SideButton(
                  key: ValueKey('poly-wide-no-$i'),
                  label: l10n.betNo,
                  color: _kNo,
                  onTap: () => onPick((pick: null, outcomeIndex: at, no: true)),
                ),
              ),
            ],
          );
        }
        body = [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            row(top[i], i),
          ],
        ];
    }

    final footer = <String>[
      if (more > 0) l10n.polyCardMoreOutcomes(more),
      if (volume > 0) '${l10n.betTotalVolume} ${formatHlCompactUsd(volume)}',
    ];
    final picture = imageUrl;

    return Container(
      key: const ValueKey('poly-wide-card'),
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Only a picture the web can draw; else the title alone.
                    if (picture != null && polyThumbShown(picture)) ...[
                      PolyCrestImage(
                        key: const ValueKey('poly-wide-picture'),
                        url: picture,
                        size: 36,
                        radius: AppRadius.md,
                        fallback: const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: polyCardTitleStyle(c)),
                    ),
                  ],
                ),
                const Spacer(),
                ...body,
                if (footer.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(footer.join(' · '),
                      key: const ValueKey('poly-wide-footer'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The featured markets as one large card at the head of the wide web
/// page: [markets] (the featured strip's own set), one at a time, previous
/// / next stepping through them. Left: the picture (when the web can draw
/// it) and the title, up to three outcome rows (big figures) and the
/// volume; right: the market's chart (its Yes line, as the market page
/// draws it). [onOpen] opens the market, as a strip card did.
class PolyWideFeatured extends ConsumerStatefulWidget {
  const PolyWideFeatured({
    super.key,
    required this.markets,
    required this.onOpen,
    this.onOpenDown,
    this.chart = true,
  });

  final List<PolymarketEvent> markets;
  final ValueChanged<PolymarketEvent> onOpen;
  final ValueChanged<PolymarketEvent>? onOpenDown;

  /// Tests: off leaves the chart's history fetch out.
  final bool chart;

  @override
  ConsumerState<PolyWideFeatured> createState() => _PolyWideFeaturedState();
}

class _PolyWideFeaturedState extends ConsumerState<PolyWideFeatured> {
  int _at = 0;

  @override
  Widget build(BuildContext context) {
    final markets = widget.markets;
    if (markets.isEmpty) return const SizedBox.shrink();
    final at = _at.clamp(0, markets.length - 1);
    final e = markets[at];
    final c = context.colors;
    final l10n = context.l10n;
    final rows = (e.outcomes.length == 2
            ? e.outcomes
            : polyCardTopOutcomes(e.outcomes, count: 3))
        .take(3)
        .toList();
    final live = <String, double>{};
    for (final o in e.outcomes) {
      final t = o.tokenId;
      if (t == null || t.isEmpty) continue;
      final p = ref.watch(livePriceProvider.select((s) => s.prices[t]));
      if (p != null) live[t] = p;
    }
    final yes = e.outcomes.isEmpty ? null : _yesOf(e.outcomes);
    final yesToken = yes?.tokenId;
    final picture = e.imageUrl;
    Widget arrow(IconData icon, int step, String key) => IconButton(
          key: ValueKey(key),
          onPressed: markets.length < 2
              ? null
              : () => setState(
                  () => _at = (at + step + markets.length) % markets.length),
          icon: Icon(icon, color: c.textSecondary),
        );
    return Container(
      key: const ValueKey('poly-wide-featured'),
      height: kPolyWideFeaturedHeight,
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(e),
          onTapDown:
              widget.onOpenDown == null ? null : (_) => widget.onOpenDown!(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            // A narrow page (one grid column) keeps the left side only.
            child: LayoutBuilder(builder: (context, box) {
              final chartShown = widget.chart &&
                  box.maxWidth >= 600 &&
                  yesToken != null &&
                  yesToken.isNotEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (picture != null && polyThumbShown(picture)) ...[
                              PolyCrestImage(
                                key: const ValueKey(
                                    'poly-wide-featured-picture'),
                                url: picture,
                                size: 48,
                                radius: AppRadius.md,
                                fallback: const SizedBox.shrink(),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(e.displayTitle,
                                  key: const ValueKey(
                                      'poly-wide-featured-title'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: polyCardTitleStyle(c)
                                      .copyWith(fontSize: 20, height: 1.25)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        for (final (i, o) in rows.indexed) ...[
                          if (i > 0) const SizedBox(height: 8),
                          Row(
                            key: ValueKey('poly-wide-featured-row-$i'),
                            children: [
                              Expanded(
                                child: Text(o.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                e.outcomes.length == 2 && i == 1
                                    ? polyCardOtherSideChance(
                                        _price(rows.first, live))
                                    : polyCardChance(_price(o, live)),
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: e.volume > 0
                                  ? Text(
                                      '${l10n.betTotalVolume} '
                                      '${formatHlCompactUsd(e.volume)}',
                                      key: const ValueKey(
                                          'poly-wide-featured-volume'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.textTertiary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500))
                                  : const SizedBox.shrink(),
                            ),
                            arrow(Icons.chevron_left_rounded, -1,
                                'poly-wide-featured-prev'),
                            arrow(Icons.chevron_right_rounded, 1,
                                'poly-wide-featured-next'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (chartShown) ...[
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: IgnorePointer(
                        child: MarketChart(
                          key: ValueKey('poly-wide-featured-chart-${e.id}'),
                          lines: [
                            MarketChartLine(
                              tokenId: yesToken,
                              color: _kYes,
                              label: l10n.yes,
                              livePrice: live[yesToken] ?? yes!.price,
                            ),
                          ],
                          height: kPolyWideFeaturedHeight - 48,
                          accentColor: _kYes,
                          openedAt: polyChartOpenedAt(e),
                          kindIds: [e.id],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
