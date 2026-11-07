// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD, restrained premium (founder, 1 November 2026: the
// Robinhood / Revolut / Apple Card share cards, then "bigger numbers and
// such" and an edgy line on the card; 2 November 2026: the earlier
// cards' colours back, Sal whole and in a mood, the predictions' own
// speedometer). A 4:5 share image at [kBragCardSize], captured at
// [kBragCardPixelRatio] (1080 × 1350), in the share cards' one layout
// (cards/share_card_frame.dart) on one solid colour by the result's tone
// ([bragPalette]: green for a win, red for a loss, navy when flat):
//
//   * PORTFOLIO: "MY PORTFOLIO", the all-time P&L huge, "All time", then
//     the all-time P&L line (BragPortfolio.series, the stock card's
//     chart) and the HOLDINGS under it (founder, 7 November 2026: "how
//     much i made on each?"): the open positions with the largest P&L
//     either way as rows ([_Holdings]: the REAL logo through the app's
//     widgets, HlCoinIcon or PolyCrestImage; the Portfolio's short name
//     with the side held quieter after it, "Anthropic · Short", "Lakers ·
//     Yes"; the P&L in money at the right in its colour, "+$12.40"), then
//     a quiet "+2 more" for the ones not listed. The line takes what the
//     rows leave ([bragHoldingsPlan]: the rows under it 18 / 15, at least
//     [kBragChartMin] of line; as many of the three as fit, the rest in
//     the "+N more"); without a line the rows spread over the middle at
//     28 / 17 when they fit; with nothing open the line fills it, as
//     before. Perps, holdings and predictions: never "stocks" or
//     "shares". No ring.
//   * INVESTING POSITION: the stock card with the P&L as the hero: "MY
//     POSITION", the market's logo, title and the side held ("Long"), the
//     P&L huge, "Since you bought · +42.1%", the line since the buy filling
//     the space when the page has read it, and the entry and the price now
//     as the plain fact line ("3,812.40 → 3,576.10").
//   * PREDICTION POSITION: the same top, then the open-position screen's
//     speedometer (cards/share_card_speedometer.dart): the needle at the
//     held side's chance now, the dot at the price paid, the P&L huge under
//     its hub and "Since you bought · +42.1%"; the price paid and now as
//     the plain fact line ("41¢ → 62¢").
//   * WON PREDICTION ([BragWin], founder, 4 November 2026: past wins
//     brag too): "CALLED IT", the market's logo, title and the side that
//     won with the day it resolved ("Yes · Nov 3, 2026"), then the same
//     speedometer with the needle at the end (resolved, won) and the dot
//     at the average price paid, the profit huge under its hub and "Won
//     from 41¢ · +143.9%"; what it cost and what it paid out as the plain
//     fact line ("Paid $12.30 · Paid out $30.00"). Green, Sal's win pose.
//   * Sal at the top right in the tone's pose ([bragPose]: lounging on a
//     win, eyes shut on a big one, a flop on a loss), the EDGY LINE
//     (brag_lines.dart) over the footer: the wordmark and the sharer's
//     code.
//
// AMOUNTS (founder, 1 November 2026: "don't even give the option"): the
// card always shows the real amounts, with the percents where they exist.
//
// The card never reads a provider or the screen's scale: the same pixels
// at every size, so the preview is exactly the image.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardOutcome;
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_speedometer.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The card's logical size: 4:5.
const Size kBragCardSize = kShareCardSize;

/// The capture's pixel ratio: [kBragCardSize] × 3 = 1080 × 1350.
const double kBragCardPixelRatio = kShareCardPixelRatio;

/// The card's colour by the result's tone: green for a win, red for a
/// loss, navy when flat.
ShareCardPalette bragPalette(BragData data) => switch (data.tone) {
      BragTone.bigWin ||
      BragTone.win ||
      BragTone.smallWin =>
        ShareCardPalette.win,
      BragTone.loss => ShareCardPalette.loss,
      BragTone.flat => ShareCardPalette.flat,
    };

/// Sal's pose by the tone: retired on a big win, lounging on any other
/// win (a small one too), a flop on a loss, a side-eye when flat.
ShareCardPose bragPose(BragData data) => switch (data.tone) {
      BragTone.bigWin => ShareCardPose.bigWin,
      BragTone.win || BragTone.smallWin => ShareCardPose.win,
      BragTone.loss => ShareCardPose.loss,
      BragTone.flat => ShareCardPose.flat,
    };

/// A result's colour on [p]: up, down, or muted when flat.
Color _signed(ShareCardPalette p, BragResult r) => r.up
    ? p.up
    : r.down
        ? p.down
        : p.muted;

/// The day a won prediction resolved, as the locale writes it ("Nov 3,
/// 2026", "3. Nov. 2026").
String bragWonDate(AppLocalizations l10n, DateTime at) {
  final local = at.toLocal();
  try {
    return DateFormat.yMMMd(l10n.localeName).format(local);
  } catch (_) {
    // Date symbols not loaded for the locale (a test, an early start).
    return DateFormat.yMMMd('en').format(local);
  }
}

/// A holdings row's sizes on the portfolio card: the logo, the text (the
/// name, the side and the P&L), the least the name steps down to before
/// it is cut, the row's height and the gap after the logo.
typedef BragRowStyle = ({
  double logo,
  double text,
  double minText,
  double height,
  double gap,
});

/// The rows alone in the middle (no line over them): the logo 28, the
/// text 17, as the rows were before the line joined them.
const BragRowStyle kBragRowRoomy =
    (logo: 28, text: 17, minText: 15, height: 32, gap: 12);

/// The rows under the line: the logo 18, the text 15.
const BragRowStyle kBragRowDense =
    (logo: 18, text: 15, minText: 13, height: 20, gap: 10);

/// The quiet "+N more" row under the rows: 13 w600 muted (the caps line's
/// size, no smaller text on a card), and its height.
const double kBragMoreSize = 13;
const double kBragMoreHeight = 15;

/// The line over the rows: its least height, and the space under it.
const double kBragChartMin = 20;
const double kBragChartGap = 6;

/// The space between a row's name and its P&L.
const double kBragRowFigureGap = 12;

/// How the holdings sit in the card's middle ([BragPortfolio.top]).
typedef BragHoldingsPlan = ({int rows, int more, BragRowStyle style});

/// The holdings in a middle [height] tall: [listed] rows to pick from
/// ([BragPortfolio.top]), [open] positions open in all, under the line
/// when [chart]. As many rows as fit, the line keeping at least
/// [kBragChartMin]; the roomy rows when there is no line and they fit,
/// else the dense ones; [BragHoldingsPlan.more] the open positions not
/// listed ("+N more"). No row at all when not even one fits.
BragHoldingsPlan bragHoldingsPlan({
  required double height,
  required int listed,
  required int open,
  required bool chart,
}) {
  final total = math.max(open, listed);
  final room = height.isFinite ? height : double.infinity;
  for (var n = math.min(listed, kBragTopHoldings); n >= 1; n--) {
    final more = total - n;
    for (final style in [if (!chart) kBragRowRoomy, kBragRowDense]) {
      final need = n * style.height +
          (more > 0 ? kBragMoreHeight : 0) +
          (chart ? kBragChartGap + kBragChartMin : 0);
      // Half a pixel of slack for the layout's rounding.
      if (need <= room + 0.5) return (rows: n, more: more, style: style);
    }
  }
  return (rows: 0, more: 0, style: kBragRowDense);
}

/// The side a holdings row writes after its name: "Long" or "Short" on a
/// perp, a prediction's outcome ("Yes" / "No" in the app's language, a
/// named one as it is); null on a holding (spot), or when the name
/// already is the side.
String? bragHoldingSide(AppLocalizations l10n, BragTopPosition row) {
  final long = row.long;
  if (long != null) return long ? l10n.longLabel : l10n.shortLabel;
  final side = row.side?.trim() ?? '';
  if (side.isEmpty || row.titleIsSide) return null;
  if (side.toLowerCase() == row.title.trim().toLowerCase()) return null;
  return shareCardOutcome(l10n, side);
}

/// What separates a row's name from its side: "Anthropic · Short".
const String kBragSideJoin = ' · ';

/// [text]'s width in one line at [style].
double _textWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// A row's name size for [label] (the name and its side) in [width]:
/// [BragRowStyle.text] when it fits, else shrunk to fit, never under
/// [BragRowStyle.minText] (the name is cut after that, its side kept).
double bragRowNameSize(String label, double width, BragRowStyle style) {
  if (!width.isFinite || width <= 0) return style.text;
  final w = _textWidth(label,
      shareCardText(style.text, FontWeight.w500, Colors.white, spacing: -0.2));
  if (w <= width) return style.text;
  return math.max(style.minText, style.text * width / w);
}

/// The edgy line [BragCard] draws for [data] at [seed] ([bragEdge]); on
/// a portfolio card that lists its holdings, the first line from the
/// seed's on that sets on ONE line at the card's width, so the rows keep
/// their room (three and the "+N more" under the line); the seed's own
/// when none does.
String bragCardEdge(AppLocalizations l10n, BragData data, int seed) {
  final pick = bragEdge(l10n, data, seed);
  if (data is! BragPortfolio || data.top.isEmpty) return pick;
  final pool = bragEdges(l10n, data);
  final start = pool.indexOf(pick);
  final style = shareCardText(kShareCardLineSize, FontWeight.w700, Colors.white,
      spacing: -0.5, height: 1.12);
  final width = kShareCardSize.width - 2 * kShareCardPadding;
  for (var i = 0; i < pool.length; i++) {
    final line = pool[(start + i) % pool.length];
    final tp = TextPainter(
      text: TextSpan(text: line, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final one = !tp.didExceedMaxLines;
    tp.dispose();
    if (one) return line;
  }
  return pick;
}

class BragCard extends StatelessWidget {
  const BragCard({super.key, required this.data, this.mark, this.lineSeed = 0});

  final BragData data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  /// Picks the edgy line (bragEdge): the preview's random seed.
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final line = bragCardEdge(l10n, data, lineSeed);
    final p = bragPalette(data);
    final pose = bragPose(data);
    switch (data) {
      case final BragPortfolio d:
        final r = d.allTime;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        final chart = hasChart
            ? ShareCardSparkline(
                key: const ValueKey('brag-card-chart'),
                points: series,
                color: r != null && (r.up || r.down) ? _signed(p, r) : p.ink,
              )
            : null;
        return ShareCardFrame(
          palette: p,
          keyPrefix: 'brag-card',
          caps: d.title,
          number: r?.text ?? '—',
          fact: l10n.portfolioAllTime,
          // Nothing open: the line alone fills the middle, as before.
          graphic: d.top.isEmpty
              ? chart
              : _Holdings(data: d, palette: p, chart: chart),
          graphicFills: hasChart || d.top.isNotEmpty,
          line: line,
          code: d.referralCode,
          mark: mark,
          pose: pose,
        );
      case final BragWin d:
        final r = d.result;
        final pct = r.percent;
        final entry = d.entryText?.trim();
        final caption = [
          if (entry != null && entry.isNotEmpty) l10n.bragWonFrom(entry),
          if (pct != null) bragPercent(pct),
        ].join(' · ');
        final at = d.resolvedAt;
        // The side that won and the day it resolved, either when unknown.
        final meta = [
          if (d.side.trim().isNotEmpty) shareCardOutcome(l10n, d.side),
          if (at != null) bragWonDate(l10n, at),
        ].join(' · ');
        return ShareCardFrame(
          palette: p,
          keyPrefix: 'brag-card',
          caps: l10n.bragWonCaps,
          identity: ShareCardIdentity(
            palette: p,
            keyPrefix: 'brag-card',
            logo: ShareCardLogo(
              key: const ValueKey('brag-card-logo'),
              size: 36,
              title: d.title,
              investing: false,
              palette: p,
              imageUrl: d.imageUrl,
            ),
            name: d.title,
            meta: meta.isEmpty ? null : meta,
          ),
          // Resolved: the needle at the end, the dot where it was bought.
          graphic: ShareCardSpeedometer(
            palette: p,
            keyPrefix: 'brag-card',
            fraction: 1,
            entry: d.entryValue,
            figure: r.text,
            figureMax: 72,
            caption: caption.isEmpty ? null : caption,
            captionColor: _signed(p, r),
          ),
          graphicFills: true,
          plain: l10n.bragWonPaidPayout(d.paidText, d.payoutText),
          line: line,
          code: d.referralCode,
          mark: mark,
          pose: pose,
        );
      case final BragPosition d:
        final r = d.result;
        final pct = r.percent;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        final entry = d.entryText?.trim();
        final now = d.nowText?.trim();
        final fact = pct == null
            ? l10n.bragSinceYouBought
            : '${l10n.bragSinceYouBought} · ${bragPercent(pct)}';
        final factColor = r.up || r.down ? _signed(p, r) : null;
        // A prediction: the open-position screen's speedometer, the P&L
        // under its hub.
        final chance = d.investing ? null : d.chance;
        return ShareCardFrame(
          palette: p,
          keyPrefix: 'brag-card',
          caps: l10n.bragMyPosition,
          identity: ShareCardIdentity(
            palette: p,
            keyPrefix: 'brag-card',
            logo: ShareCardLogo(
              key: const ValueKey('brag-card-logo'),
              size: 36,
              title: d.title,
              investing: d.investing,
              palette: p,
              coin: d.coin,
              wireCoin: d.wireCoin,
              iconUrl: d.iconUrl,
              category: d.category,
              imageUrl: d.imageUrl,
            ),
            name: d.title,
            meta: d.side,
          ),
          number: chance == null ? r.text : null,
          fact: chance == null ? fact : null,
          factColor: factColor,
          graphic: chance != null
              ? ShareCardSpeedometer(
                  palette: p,
                  keyPrefix: 'brag-card',
                  fraction: chance,
                  entry: d.entryValue,
                  figure: r.text,
                  figureMax: 72,
                  caption: fact,
                  captionColor: factColor,
                )
              : hasChart
                  ? ShareCardSparkline(
                      key: const ValueKey('brag-card-chart'),
                      points: series,
                      color: r.up || r.down ? _signed(p, r) : p.ink,
                    )
                  : null,
          graphicFills: chance != null || hasChart,
          // What it cost and what it is now: "3,812.40 → 3,576.10".
          plain: entry != null && now != null ? '$entry → $now' : null,
          line: line,
          code: d.referralCode,
          mark: mark,
          pose: pose,
        );
    }
  }
}

/// The portfolio card's holdings ([bragHoldingsPlan]): the line over the
/// rows when there is one, taking what they leave; the rows alone spread
/// over the middle otherwise; then the quiet "+N more".
class _Holdings extends StatelessWidget {
  const _Holdings({required this.data, required this.palette, this.chart});

  final BragPortfolio data;
  final ShareCardPalette palette;

  /// The all-time line over the rows; null: the rows alone.
  final Widget? chart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(builder: (context, box) {
      final plan = bragHoldingsPlan(
        height: box.maxHeight,
        listed: data.top.length,
        open: data.openCount,
        chart: chart != null,
      );
      final style = plan.style;
      final more = data.moreThan(plan.rows);
      final rows = <Widget>[
        for (var i = 0; i < plan.rows; i++)
          SizedBox(
            height: style.height,
            child: _HoldingRow(
                key: ValueKey('brag-card-top-$i'),
                row: data.top[i],
                palette: palette,
                style: style),
          ),
        if (plan.rows > 0 && more > 0)
          SizedBox(
            height: kBragMoreHeight,
            child: Padding(
              // Under the names, where the list's text starts.
              padding:
                  EdgeInsetsDirectional.only(start: style.logo + style.gap),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.bragHoldingsMore(more),
                  key: const ValueKey('brag-card-more'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shareCardText(
                      kBragMoreSize, FontWeight.w600, palette.muted,
                      spacing: -0.1, height: 1.15),
                ),
              ),
            ),
          ),
      ];
      final line = chart;
      if (line == null) {
        return Column(
          key: const ValueKey('brag-card-rows'),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: rows,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: line),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: kBragChartGap),
            Column(
              key: const ValueKey('brag-card-rows'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ],
        ],
      );
    });
  }
}

/// One open position as a row: its real logo, its short name in the ink
/// with the side held quieter after it ("Anthropic · Short"), and its P&L
/// in money at the right in the result's colour ("+$12.40"). A long name
/// steps down a size, then is cut; the side and the P&L stay whole.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    super.key,
    required this.row,
    required this.palette,
    required this.style,
  });

  final BragTopPosition row;
  final ShareCardPalette palette;
  final BragRowStyle style;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final r = row.result;
    final side = bragHoldingSide(context.l10n, row);
    final figureStyle = shareCardText(
        style.text, FontWeight.w600, _signed(p, r),
        spacing: -0.2, tabular: true);
    return LayoutBuilder(builder: (context, box) {
      final room = box.maxWidth -
          style.logo -
          style.gap -
          kBragRowFigureGap -
          _textWidth(r.text, figureStyle);
      final size = bragRowNameSize(
          side == null ? row.title : '${row.title}$kBragSideJoin$side',
          room,
          style);
      final nameStyle =
          shareCardText(size, FontWeight.w500, p.ink, spacing: -0.2);
      return Row(
        children: [
          ShareCardLogo(
            size: style.logo,
            title: row.title,
            investing: row.investing,
            palette: p,
            coin: row.coin,
            wireCoin: row.wireCoin,
            iconUrl: row.iconUrl,
            category: row.category,
            imageUrl: row.imageUrl,
          ),
          SizedBox(width: style.gap),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.title,
                    key: ValueKey('$_key-name'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                ),
                if (side != null)
                  ConstrainedBox(
                    // A long named side never pushes the name out.
                    constraints:
                        BoxConstraints(maxWidth: math.max(0, room * 0.5)),
                    child: Text(
                      '$kBragSideJoin$side',
                      key: ValueKey('$_key-side'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle.copyWith(color: p.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: kBragRowFigureGap),
          Text(
            r.text,
            key: ValueKey('$_key-pnl'),
            maxLines: 1,
            softWrap: false,
            style: figureStyle,
          ),
        ],
      );
    });
  }

  /// The row's own key ("brag-card-top-0"), its parts keyed after it.
  String get _key {
    final k = key;
    return k is ValueKey<String> ? k.value : 'brag-card-top';
  }
}
