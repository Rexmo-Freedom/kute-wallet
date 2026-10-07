// lib/screens/polymarket/components/market_chart.dart
//
// The one Polymarket chart, shared by the market detail sheet and the open
// position sheet so both look and behave the same. Line style only: the
// prices-history feed is price points, not OHLC.
//
// Feel copied from the Hyperliquid chart (HlCandlestickChart):
//   * a drag pans through time, two fingers pinch to zoom (anchored to the
//     right edge, sliding both fingers pans), and a long press (then slide)
//     shows the crosshair with the value and time;
//   * the probability scale autoscales to the window on screen with the
//     shared TradingView rules (kute_chart_autoscale.dart) and glides
//     between targets; a vertical drag on the left label strip sets it by
//     hand, and the same Auto pill or a double tap fits it again;
//   * the newest point is pinned to the live book price and eases to each
//     tick, with the live pulse at the right edge;
//   * nothing sits above the plot: the screen's hero carries the figure,
//     and the values under the finger go on the scrub card;
//   * panning or pinching past the oldest point loads older history page
//     by page where the API allows it (PolyChartHistory), otherwise the
//     view stops at the oldest point.
//
// Under the plot, the time axis says when the window on screen starts and
// ends ("Sep 12" … "Now"), following every pan and pinch; its row comes
// out of the plot's height, so the chart keeps its own
// (kute_chart_time_axis.dart). The first chart a person ever sees with
// enough points zooms in a little and back out once, to show it can be
// pinched (kute_chart_zoom_hint.dart).
//
// There is no range row: the chart picks one of Polymarket's history
// windows itself (polyChartAutoRange: a game from its kickoff, a young
// market, a short round or a resolved one its whole life, anything else
// its last month) and keeps it. The range is fetched at its own
// resolution and extended by the live feed; zoom and pan work inside it. Reads go through PolyPriceHistoryCache (one
// session cache per token and range, prefetched when a sheet opens), every
// line is requested at once, and a cold chart draws each line as it lands.
//
// A live or finished game's chart also draws its event markers (a goal, a
// set or a map won, a period change) at the time each happened, so the
// move in the odds can be read against it. Markers that would overlap are
// drawn as one with a count; a tap on one, or the crosshair passing it,
// names it on the scrub card. The chart opens on the range that
// holds the game, zoomed to the game itself (a little before kickoff to
// now, or to a little after the last whistle).
//
// The probability scale fits the lines in the window on screen
// (polyChartDomain: a tenth of their span free above and below, never
// under five points tall, never outside 0-100%) and fits again on every
// range change, pan, pinch and change of lines.
//
// Motion, as on the Investing chart: a range change eases the window and
// the scale from the old range's to the new one's over 250ms (easeInOut;
// the window's span in log space, so a year-to-an-hour zoom reads as one
// steady zoom), starting once the new range's lines have landed. Both
// ranges' lines are real prices on the same time axis, so instead of
// resampling one onto the other the old lines fade out and the new fade
// in through that one moving window and scale; markers, value tags and
// the pulse follow it. Any other refit of the scale glides
// over 150ms, except while a finger is on the plot, where it follows at
// once. At rest the chart is drawn exactly as with no motion. Under
// Reduce Motion everything lands at once and the live pulse stops.
//
// Multi-outcome markets keep one line per outcome in the host's colours.
// Each line ends in a right-edge value pill in its colour reading its
// short name and chance ("Sakatsume 72.5%", "Yes 18%"), drawn over the
// lines and the pulse; where lines end close together the pills stack
// clear of each other and of the end dots, and a crowded stack writes
// its chances alone (poly_chart_tags.dart). The user's average
// price on a shown outcome is drawn as a dashed "Bought · 32¢" line, the
// Polymarket twin of the Hyperliquid "Entry" line, through the shared
// trade-lines layer.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlAutoScalePill, hlNiceLevels;
import 'package:kute/screens/polymarket/components/poly_chart_history.dart';
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_autoscale.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart'
    show KuteDrawingGeometry;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/polymarket/thin_history.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

// The scrub readout writes a chance as the tags on the plot do.
String _formatPct(double price) => polyChartTagPct(price);

/// Per-share buy price in cents for the "Bought" tag (0.32 → "32¢",
/// 0.003 → "0.3¢"), so a deep longshot never collapses to "0¢".
String _formatCents(double price) {
  final cents = price * 100;
  return cents >= 10
      ? '${cents.toStringAsFixed(0)}¢'
      : '${cents.toStringAsFixed(1)}¢';
}

/// A per-share price as the chart's "Bought" tag writes it ("32¢"), for
/// the screens that name the same price beside the chart.
String formatPolyBoughtCents(double price) => _formatCents(price);

const double _kRightMargin = 12;
const double _kBottomMargin = 6;

/// A range change eases the window and the scale from the old range's to
/// the new one's, the old lines fading out as the new ones fade in.
const Duration _kRangeMotion = Duration(milliseconds: 250);

/// The scale's glide to a new fit (a pan or a pinch ended, a line added
/// or removed, a line walking out of the scale).
const Duration _kRefitMotion = Duration(milliseconds: 150);

/// Left price-label strip: a vertical drag that starts here scales the
/// axis by hand (the Hyperliquid chart's strip width).
const double _kAxisStripWidth = 48.0;

/// Laid-out TextPainters for the endpoint pills and the
/// scale labels, keyed by (text, color, fontSize). The text is highly
/// repetitive between frames — re-laying it out on every paint was
/// flagged as paint-time allocation. Bounded defensively.
final Map<(String, int, double), TextPainter> _endpointTpCache = {};

TextPainter _endpointTp(
    String text, Color color, double fontSize, FontWeight weight) {
  if (_endpointTpCache.length > 96) _endpointTpCache.clear();
  return _endpointTpCache.putIfAbsent(
    (text, color.toARGB32(), fontSize),
    () => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kuteChartFontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

/// Where the right-edge value tags sit so that none covers another: the
/// shared tag rule ([kuteLayoutTags]) for tags of one [height]; the
/// higher line keeps the higher tag. Returns the tops in the order given.
List<double> spreadChartTags(
  List<double> tops, {
  required double height,
  required double maxBottom,
  double gap = 2,
}) =>
    kuteLayoutTags([for (final t in tops) (top: t, height: height)],
        maxBottom: maxBottom, gap: gap);

/// The right-edge value tags of [series] for one frame (poly_chart_tags.dart):
/// each line's tag at the end of its line, written as its short name and
/// chance ("Sakatsume 72.5%"), moved apart from the others where lines end
/// close together, with its colour. Only while the newest points are on
/// screen ([atLiveEdge]). Shared by the tags layer, which draws them, and
/// the "Bought" layer, which keeps its tags off them: these are the
/// latest prices' own tags.
List<
        ({
          double y,
          double top,
          double height,
          double width,
          String text,
          Color color
        })>
    _valueTags({
  required List<_Series> series,
  required List<double> leads,
  required int start,
  required int end,
  required KuteYDomain domain,
  required double drawH,
  required double plotWidth,
  required bool atLiveEdge,
}) {
  if (!atLiveEdge || drawH <= 0) return const [];
  final raw = <({double y, double price, Color color, String name})>[];
  for (var li = 0; li < series.length; li++) {
    final s = series[li];
    final pts = s.points;
    if (pts.length < 2) continue;
    final lastT = pts.last.timestamp.millisecondsSinceEpoch;
    if (lastT < start) continue;
    final lead = leads.isNotEmpty ? leads[li] : pts.last.price;
    final tag = s.tagPrice;
    raw.add((
      y: _yFor(tag ?? lead, domain, drawH),
      price: tag ?? pts.last.price,
      color: s.color,
      name: polyChartShortName(s.label),
    ));
  }
  if (raw.isEmpty) return const [];
  final pillH = _endpointTp('0%', Colors.white, _kTagFontSize, FontWeight.w800)
          .height +
      _kTagPadV * 2;
  final placed = polyLayoutValueTags(
    lines: [
      for (final t in raw)
        (y: t.y, price: t.price, pct: polyChartTagPct(t.price), name: t.name),
    ],
    plotWidth: plotWidth,
    drawH: drawH,
    tagHeight: pillH,
    padH: _kTagPadH,
    measure: (text) =>
        _endpointTp(text, Colors.white, _kTagFontSize, FontWeight.w800).width,
  );
  return [
    for (final p in placed)
      (
        y: raw[p.index].y,
        top: p.top,
        height: pillH,
        width: p.width,
        text: p.text,
        color: raw[p.index].color,
      ),
  ];
}

const double _kTagFontSize = 10.5;
const double _kTagPadH = 5.0;
const double _kTagPadV = 2.5;

/// The window a game's chart shows by default inside a range whose data
/// runs [dataStartMs]..[dataEndMs]: the game itself, with a short run-up
/// before kickoff (five minutes, or a twelfth of the time played when
/// that is longer), up to now while it is played, or to the same margin
/// after its last whistle once [gameEndMs] is known. A range that does not
/// reach back to kickoff (1H three hours into a game) keeps all of
/// itself. Null when the game has not started inside the data.
({int start, int end})? polyGameWindow({
  required int dataStartMs,
  required int dataEndMs,
  required int gameStartMs,
  int? gameEndMs,
}) {
  final until =
      gameEndMs == null ? dataEndMs : math.min(gameEndMs, dataEndMs);
  final played = until - gameStartMs;
  if (played <= 0) return null;
  final total = dataEndMs - dataStartMs;
  final pad = math.max(5 * 60000, played ~/ 12);
  if (gameEndMs == null) {
    final span = math.min(total, played + pad);
    return (start: dataEndMs - span, end: dataEndMs);
  }
  final span = math.min(total, played + 2 * pad);
  final end = math.max(dataStartMs + span, math.min(dataEndMs, until + pad));
  return (start: end - span, end: end);
}

/// The least a probability scale spans: a line that barely moves is drawn
/// as the flat line it is, not as noise filling the plot.
const double kPolyChartMinSpan = 0.05;

/// The probability scale for lines that run from [lo] to [hi] (0..1) in
/// the window on screen: the data with a tenth of its span left free
/// above and below, at least [kPolyChartMinSpan] tall, and never further
/// outside 0%..100% than the sliver that keeps a line at either bound
/// off the plot's edge.
KuteYDomain polyChartDomain(double lo, double hi) {
  if (!lo.isFinite || !hi.isFinite) return (minY: 0, maxY: 1);
  if (hi < lo) {
    final t = lo;
    lo = hi;
    hi = t;
  }
  lo = lo.clamp(0.0, 1.0).toDouble();
  hi = hi.clamp(0.0, 1.0).toDouble();
  final pad = (hi - lo) * 0.1;
  var minY = lo - pad, maxY = hi + pad;
  if (maxY - minY < kPolyChartMinSpan) {
    final mid = (lo + hi) / 2;
    minY = mid - kPolyChartMinSpan / 2;
    maxY = mid + kPolyChartMinSpan / 2;
  }
  // Inside 0..1, keeping the span where it can be kept.
  final edge = (maxY - minY) * 0.03;
  if (minY < -edge) {
    maxY = math.min(1.0 + edge, maxY + (-edge - minY));
    minY = -edge;
  }
  if (maxY > 1 + edge) {
    minY = math.max(-edge, minY - (maxY - (1 + edge)));
    maxY = 1 + edge;
  }
  return (minY: minY, maxY: maxY);
}

/// [domain] raised so that a line at [hi] ends at least [lane] (a share of
/// the plot's height) under the plot's top: the lane a game's event
/// markers are drawn in, which a line near 100% and its tag would
/// otherwise run through. The lane is the plot's furniture, not part of
/// the scale, so this may reach past 100%.
KuteYDomain polyChartHeadroom(KuteYDomain domain, double hi, double lane) {
  if (!(lane > 0) || lane >= 0.5) return domain;
  final needed = (hi - lane * domain.minY) / (1 - lane);
  return needed > domain.maxY ? (minY: domain.minY, maxY: needed) : domain;
}

/// What a line's end keeps clear of the plot's top and bottom edges
/// (pixels): its end dot (4) and the bright part of the live pulse
/// around it, so neither is cut by the plot's edge when a line sits at
/// the top or bottom of the scale (a leader near 100%, a long shot near
/// 0%).
const double kPolyChartEndRoom = 10;

/// [domain] widened, as little as it takes, so that a line at [hi] sits
/// at least [top] (a share of the plot's height) under the plot's top
/// and a line at [lo] at least [bottom] over its bottom. This is the
/// room of the end dots and the pulse, and of a game's marker lane, not
/// part of the scale: it may reach past 0% and 100%, where no level is
/// labelled.
KuteYDomain polyChartEdgeRoom(
  KuteYDomain domain,
  double lo,
  double hi, {
  double top = 0,
  double bottom = 0,
}) {
  if (!lo.isFinite || !hi.isFinite) return domain;
  if (hi < lo) {
    final t = lo;
    lo = hi;
    hi = t;
  }
  lo = lo.clamp(0.0, 1.0).toDouble();
  hi = hi.clamp(0.0, 1.0).toDouble();
  top = top.clamp(0.0, 0.45).toDouble();
  bottom = bottom.clamp(0.0, 0.45).toDouble();
  var minY = domain.minY, maxY = domain.maxY;
  bool topOk(double minY, double maxY) =>
      maxY - hi >= top * (maxY - minY) - 1e-12;
  bool bottomOk(double minY, double maxY) =>
      lo - minY >= bottom * (maxY - minY) - 1e-12;
  if (topOk(minY, maxY) && bottomOk(minY, maxY)) return domain;
  if (!topOk(minY, maxY)) {
    final up = (hi - top * minY) / (1 - top);
    if (bottomOk(minY, up)) return (minY: minY, maxY: up);
  }
  if (!bottomOk(minY, maxY)) {
    final down = (lo - bottom * maxY) / (1 - bottom);
    if (topOk(down, maxY)) return (minY: down, maxY: maxY);
  }
  // Both edges bind: the data fills what the two rooms leave.
  final span = math.max(hi - lo, 1e-9) / (1 - top - bottom);
  return (
    minY: math.min(minY, lo - bottom * span),
    maxY: math.max(maxY, hi + top * span),
  );
}

/// The height of an event's chart of its most likely outcomes: [base] for
/// one or two lines, a fifth more for three or more, whose lines and
/// stacked end tags were cramped (and cut) in the binary chart's height.
double polyChartHeightFor(int lines, {double base = 220}) =>
    lines >= 3 ? (base * 1.18).roundToDouble() : base;

/// A chance as the chart's own tags write it (the value at the end of a
/// line, the crosshair's bubbles): one decimal at most, "93.5%", "62%".
/// Under 1% and over 99% a second decimal is kept, so a long shot at
/// 0.45% does not read "0.5%".
String polyChartTagPct(double price) =>
    formatPolyChance(price, fineEnds: true);

/// First index in [points] whose time is at or after [ms].
int _lowerBound(List<PolymarketPricePoint> points, int ms) {
  var lo = 0, hi = points.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (points[mid].timestamp.millisecondsSinceEpoch < ms) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The last point at or before [ms], or null before the series starts.
PolymarketPricePoint? _pointAt(List<PolymarketPricePoint> points, int ms) {
  if (points.isEmpty) return null;
  final i = _lowerBound(points, ms + 1) - 1;
  return i >= 0 ? points[i] : null;
}

class MarketChartLine {
  final String tokenId;
  final Color color;
  final String label;
  /// Optional: the live outcome price (0..1) for this line. When set,
  /// the chart's last point is pinned to this value so the rightmost
  /// data point always matches whatever the YES/NO buy buttons show.
  /// Without this, the chart and the buttons can diverge — historical
  /// price feed lags the live orderbook by tens of seconds.
  final double? livePrice;

  /// The line's market has hardly traded ([polyMarketIsThin]): its
  /// history is drawn from the cleaned copy (thin_history.dart).
  final bool thin;
  const MarketChartLine({
    required this.tokenId,
    required this.color,
    required this.label,
    this.livePrice,
    this.thin = false,
  });
}

/// The user's average price (0..1) on one outcome token. Drawn as a
/// dashed "Bought · 32¢" line in that outcome's colour when the token is
/// one of the chart's lines; ignored otherwise.
class MarketChartBought {
  final String tokenId;
  final double price;
  const MarketChartBought({required this.tokenId, required this.price});
}

/// One event of a game on the chart's time axis (a goal, a set won, a
/// period change). The host builds the [label] in the user's language.
class MarketChartMarker {
  /// When it happened (epoch ms).
  final int tMs;

  /// "Goal 38' 1–0", "Set 2", "Map 3 won".
  final String label;
  final Color color;

  /// A period change rather than a score: drawn smaller.
  final bool minor;

  /// What it is, for analytics ("goal", "period").
  final String kind;

  const MarketChartMarker({
    required this.tMs,
    required this.label,
    required this.color,
    this.minor = false,
    this.kind = '',
  });
}

/// Markers close enough on screen to be drawn as one.
class _MarkerCluster {
  final double x;
  final List<MarketChartMarker> markers;
  const _MarkerCluster(this.x, this.markers);

  /// The first scoring marker's colour, else the first marker's.
  Color get color => markers
      .firstWhere((m) => !m.minor, orElse: () => markers.first)
      .color;
  bool get minor => markers.every((m) => m.minor);
}

/// The height at the top of the plot kept for a game's event markers
/// (their dots and counts), which lines and value tags stay under.
const double _kMarkerLane = 30;

/// A range draws a game's own window only when it has at least this many
/// points inside it.
const int _kGameWindowMinPoints = 8;

/// Markers closer than this on screen are drawn as one, with a count.
const double _kMarkerClusterGap = 18;

/// How near a tap must land to pick a marker.
const double _kMarkerTapSlop = 20;

/// One plotted outcome for a frame: its points (ascending, older history
/// pages in front, the newest point pinned to the live price) and look.
class _Series {
  final String tokenId;
  final List<PolymarketPricePoint> points;
  final Color color;
  final String label;

  /// The live price the value tag writes when the line is NOT pinned to
  /// it: a thin market whose live book sits far from its stale history
  /// (thin_history.dart, [kPolyThinCliff]). The line ends at the history,
  /// the tag sits at this price. Null when the line is pinned as usual.
  final double? tagPrice;
  const _Series(this.tokenId, this.points, this.color, this.label,
      {this.tagPrice});
}

/// The time window on screen for one frame, epoch ms.
typedef _Frame = ({
  int dataStart,
  int dataEnd,
  int start,
  int end,
  int minSpan,
});

class MarketChart extends ConsumerStatefulWidget {
  final String? tokenId;
  final List<MarketChartLine>? lines;
  final double height;
  final Color? accentColor;

  /// Average prices the user holds on the shown outcomes.
  final List<MarketChartBought> bought;

  /// A 5 / 15 minute round: the chart shows its whole life (ALL).
  final bool shortMarket;

  /// The market has resolved: no live pulse, and the chart opens on ALL
  /// (its last month may be long gone).
  final bool resolved;

  /// When the market opened (Gamma `startDate`; null for a game, whose
  /// start date may be its kickoff): one under a month old opens on ALL,
  /// an older one on its last month ([polyChartAutoRange]).
  final DateTime? openedAt;

  /// A game being played: with no [gameStart] known, the chart opens on
  /// its last day.
  final bool inPlay;

  /// Where the chart sits, for analytics: `market` or `position`.
  final String surface;

  /// Market identifiers for the analytics kind-of-bet properties (never
  /// sent themselves; see VenueAnalytics.pmKindParams).
  final List<String?> kindIds;

  /// A game's events, oldest first, drawn on the time axis. The list's
  /// identity is the memo key: pass the same list while nothing changed.
  final List<MarketChartMarker> markers;

  /// A marker (or a cluster of [count]) was named to the user, by a tap or
  /// by the crosshair passing it ([via] `tap` / `scrub`).
  final void Function(MarketChartMarker first, int count, String via)?
      onMarkerShown;

  /// A game's kickoff: the chart opens on the range that holds the game,
  /// zoomed to the game.
  final DateTime? gameStart;

  /// When a finished game ended: the chart then opens on the game itself
  /// (kickoff to the end), not on everything since. Null while in play.
  final DateTime? gameEnd;

  /// The bare [tokenId]'s market has hardly traded (a chart with [lines]
  /// says so per line, [MarketChartLine.thin]).
  final bool thin;

  const MarketChart({
    super.key,
    this.tokenId,
    this.lines,
    this.height = 200,
    this.accentColor,
    this.bought = const [],
    this.shortMarket = false,
    this.resolved = false,
    this.openedAt,
    this.inPlay = false,
    this.surface = 'market',
    this.kindIds = const [],
    this.markers = const [],
    this.onMarkerShown,
    this.gameStart,
    this.gameEnd,
    this.thin = false,
  });

  /// This chart with a game's event [markers] on it, opening on the game.
  MarketChart withGame({
    required List<MarketChartMarker> markers,
    required DateTime gameStart,
    DateTime? gameEnd,
    void Function(MarketChartMarker first, int count, String via)?
        onMarkerShown,
  }) =>
      MarketChart(
        key: key,
        tokenId: tokenId,
        lines: lines,
        height: height,
        accentColor: accentColor,
        bought: bought,
        shortMarket: shortMarket,
        resolved: resolved,
        openedAt: openedAt,
        inPlay: inPlay,
        surface: surface,
        kindIds: kindIds,
        markers: markers,
        onMarkerShown: onMarkerShown,
        gameStart: gameStart,
        gameEnd: gameEnd,
        thin: thin,
      );

  /// Starts the history read for the range a chart on [tokenIds] opens on
  /// ([polyChartAutoRange]), so it runs during the sheet's slide-in
  /// instead of after the chart mounts. The read lands in the session
  /// cache the chart reads from.
  static void prefetch(
    Iterable<String?> tokenIds, {
    bool shortMarket = false,
    bool resolved = false,
    DateTime? gameStart,
    bool inPlay = false,
    DateTime? openedAt,
  }) {
    final interval = polyChartAutoRange(
      now: DateTime.now(),
      gameStart: gameStart,
      inPlay: inPlay,
      openedAt: openedAt,
      shortMarket: shortMarket,
      resolved: resolved,
    );
    for (final t in tokenIds.take(6)) {
      if (t != null && t.isNotEmpty) {
        PolyPriceHistoryCache.prefetch(t, interval);
      }
    }
  }

  @override
  ConsumerState<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends ConsumerState<MarketChart>
    with TickerProviderStateMixin {
  /// The range on screen, the chart's own pick ([polyChartAutoRange]).
  late String _interval = _openingInterval();

  String _openingInterval() => polyChartAutoRange(
        now: DateTime.now(),
        gameStart: widget.gameStart,
        inPlay: widget.inPlay,
        openedAt: widget.openedAt,
        shortMarket: widget.shortMarket,
        resolved: widget.resolved,
      );

  // ── event markers ────────────────────────────────────────────────
  /// Clusters for the window painted last, memoized on the marker list's
  /// identity, the window and the plot width.
  (Object, int, int, double, List<_MarkerCluster>)? _clusterMemo;

  /// The cluster a tap named, held on the scrub card for a few seconds.
  _MarkerCluster? _tappedCluster;
  Timer? _tappedTimer;

  /// The last cluster the crosshair named, so one pass reports it once.
  int? _scrubbedMarkerMs;


  // ── viewport ─────────────────────────────────────────────────────
  /// Time span on screen (null = the range's default: the whole range,
  /// or a game's own window) and the end of the window (null = the
  /// newest point, the live edge). Set by a drag or a pinch; a new range
  /// or market starts from the default.
  int? _viewSpanMs;
  int? _anchorEndMs;

  /// The window painted last frame, for the gesture handlers.
  _Frame? _frame;
  double _plotWidth = 0;

  /// Raw pointers on the plot, for the pinch. Two of them zoom; every
  /// one-finger handler stays quiet until all fingers lift.
  final Map<int, Offset> _pointers = {};
  bool _pinching = false;
  double? _pinchStartDistance;
  double? _pinchStartFocalX;
  int? _pinchStartSpan;
  int? _pinchStartEnd;

  /// One-finger pan of the window in time.
  bool _panningView = false;
  double _panStartX = 0;
  int _panStartEnd = 0;
  int _panSpan = 0;

  /// A drag that starts on the left label strip scales the axis when it
  /// goes vertical and pans when it goes sideways.
  bool _axisCandidate = false;
  Offset _gestureStart = Offset.zero;
  bool _axisDragging = false;
  double _axisStartY = 0;
  KuteYDomain? _axisStartDomain;

  DateTime _lastHistoryRequest = DateTime(0);

  // ── price scale (TradingView-style autoscale) ─────────────────────
  /// Autoscale on: the scale fits the points on screen. Off after the
  /// user drags the price axis; the Auto pill or a double tap restores it.
  bool _autoScale = true;
  KuteYDomain? _manualDomain;

  /// The domain painted last frame (mid-glide included), so gestures map
  /// touches exactly as the user sees them.
  KuteYDomain? _shownDomain;

  /// The scale's glide to each new target: from [_domFrom] to [_domTo]
  /// over [_kRefitMotion]. A null [_domTo] makes the next target land at
  /// once (another market).
  KuteYDomain? _domFrom;
  KuteYDomain? _domTo;
  late final AnimationController _refit = AnimationController(
    vsync: this,
    duration: _kRefitMotion,
    value: 1,
  );
  late final Animation<double> _refitCurve =
      CurvedAnimation(parent: _refit, curve: Curves.easeInOut);

  // ── range motion ─────────────────────────────────────────────────
  /// What was on screen when the range changed: its window, scale and
  /// lines. The window and the scale ease from it to the new range's over
  /// [_kRangeMotion] while the old lines fade out and the new ones in.
  /// Null when no range change is in motion.
  ({
    _Frame frame,
    KuteYDomain domain,
    List<_Series> series,
    bool edge,
    String interval,
  })? _rangeFrom;

  /// The range changed and its lines are still loading: the view holds
  /// [_rangeFrom] until they land, then the motion starts.
  bool _rangeArmed = false;
  late final AnimationController _range =
      AnimationController(vsync: this, duration: _kRangeMotion);
  late final Animation<double> _rangeCurve =
      CurvedAnimation(parent: _range, curve: Curves.easeInOut);

  /// The window, lines and live-edge state painted last (mid-motion
  /// included), what a range change moves away from.
  _Frame? _shownFrame;
  List<_Series>? _shownSeries;
  bool _shownEdge = false;

  final KuteAutoScaleTracker _scaleTracker = KuteAutoScaleTracker();
  final List<KuteRangeExtremes<PolymarketPricePoint>> _extremes = [];

  /// Second tap of a double tap (restores autoscale).
  DateTime _lastTapAt = DateTime(0);
  Offset _lastTapPos = Offset.zero;

  // ── scrub ────────────────────────────────────────────────────────
  /// Time (epoch ms) of the primary line's point under the finger while
  /// the long-press crosshair is up.
  int? _touchMs;
  DateTime _lastHaptic = DateTime(0);

  /// Last series actually shown. While a newly picked range is still
  /// loading the chart keeps painting these instead of flashing a
  /// skeleton; only a cold start shows the skeleton.
  List<_Series>? _held;

  /// Merged (older pages + live) series per token, memoized on the
  /// identities of both inputs and the live pin.
  final Map<String, (Object, Object, double?, List<PolymarketPricePoint>)>
      _merged = {};

  /// Memoized "Bought" trade lines, keyed on their content.
  final Map<String, List<ChartTradeLine>> _boughtLines = {};
  final List<ChartTradeLineHit> _tradeHits = [];

  /// Analytics dedupe scope for this chart instance: the range resets on
  /// every open, so a repeat pick on a new open is a real change.
  late final String _analyticsScope =
      'poly_chart:${widget.surface}:${identityHashCode(this)}';

  /// Drives the pulsing "live" ring at the chart's right edge. The mid is
  /// pinned to the live WS price, but on quiet (illiquid / long-dated)
  /// markets the line barely moves — the pulse makes it read as live.
  /// Purely decorative — the line + endpoint dot already convey the live
  /// value, so the repeating pulse is gated off under Reduce Motion.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Live-tick endpoint smoothing: when the leading point updates from a
  /// live tick, the endpoint eases to its new position over 250ms instead
  /// of jumping (the BtcPredictChart value-approach feel).
  late final AnimationController _lead = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _leadCurve =
      CurvedAnimation(parent: _lead, curve: Curves.easeOutCubic);

  // Endpoint tween state: displayed lead = lerp(_leadFrom, _leadTo, t).
  List<double>? _leadFrom;
  List<double>? _leadTo;

  /// Whether the platform requests reduced/disabled animations. Read in
  /// `build` so it stays current; under it every change lands at once
  /// and the live pulse stops.
  bool _reduceMotion = false;

  // ── zoom nudge ───────────────────────────────────────────────────
  /// The one-time zoom nudge (kute_chart_zoom_hint.dart) and the wait
  /// before it, once this chart's lines have landed.
  late final KuteZoomNudge _nudge = KuteZoomNudge(this);
  Timer? _nudgeTimer;
  bool _nudgeScheduled = false;

  /// The plot's height: the chart's, less the time axis row under it.
  double get _plotH =>
      math.max(0.0, widget.height - kKuteTimeAxisHeight);

  /// Schedules the nudge once the lines on screen have enough points.
  void _maybeScheduleNudge(List<_Series> series) {
    if (_nudgeScheduled) return;
    var most = 0;
    for (final s in series) {
      if (s.points.length > most) most = s.points.length;
    }
    if (most < kKuteZoomNudgeMinPoints) return;
    _nudgeScheduled = true;
    if (KuteZoomHint.seen) return;
    _nudgeTimer = Timer(kKuteZoomNudgeDelay, () {
      if (!mounted ||
          _pointers.isNotEmpty ||
          _touchMs != null ||
          _rangeFrom != null ||
          _viewSpanMs != null ||
          _anchorEndMs != null) {
        return;
      }
      _nudge.tryStart(reduceMotion: _reduceMotion);
    });
  }

  /// [f] with the nudge's zoom in it, anchored on its end.
  _Frame _nudged(_Frame f) {
    final amount = _nudge.amount;
    if (amount <= 0) return f;
    final span = f.end - f.start;
    return (
      dataStart: f.dataStart,
      dataEnd: f.dataEnd,
      start: f.end - (span * (1 - amount)).round(),
      end: f.end,
      minSpan: f.minSpan,
    );
  }

  @override
  void initState() {
    super.initState();
    _range.addStatusListener((status) {
      if (status != AnimationStatus.completed || _rangeFrom == null) return;
      // The new range is in place: the old lines leave the tree.
      _rangeFrom = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant MarketChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = _tokenKey(oldWidget), newKey = _tokenKey(widget);
    if (oldKey != newKey) {
      // Another market: nothing of the old view carries over. A line
      // added to or taken off the same market keeps the scale's glide.
      final oldTokens = oldKey.split('|').toSet();
      final sameMarket = newKey.split('|').any(oldTokens.contains);
      _held = null;
      _merged.clear();
      _fineMerged.clear();
      _cleanedTapes.clear();
      _touchMs = null;
      _tappedCluster = null;
      _stopRangeMotion();
      _resetViewport();
      _resetScale(jump: !sameMarket);
    }
    if (oldWidget.gameStart != widget.gameStart ||
        oldWidget.inPlay != widget.inPlay ||
        oldWidget.openedAt != widget.openedAt ||
        oldWidget.shortMarket != widget.shortMarket ||
        oldWidget.resolved != widget.resolved) {
      // What the range is picked from changed after the chart opened (the
      // game's kickoff or the market's age became known): move to the
      // range it picks now. A live tick alone never moves it.
      final want = _openingInterval();
      if (want != _interval) {
        _armRangeMotion();
        _interval = want;
        _resetViewport();
        _resetScale();
      } else if (oldWidget.gameStart != widget.gameStart) {
        // Same range, the game's window inside it moved.
        _resetViewport();
      }
    }
  }

  @override
  void dispose() {
    VenueAnalytics.resetSettings(_analyticsScope);
    _tappedTimer?.cancel();
    _nudgeTimer?.cancel();
    _nudge.dispose();
    _pulse.dispose();
    _lead.dispose();
    _refit.dispose();
    _range.dispose();
    super.dispose();
  }

  // ─────────────────────────── motion ───────────────────────────

  /// A range change starts from what is on screen now. Nothing moves
  /// under Reduce Motion or before the chart has drawn.
  void _armRangeMotion() {
    final frame = _shownFrame, domain = _shownDomain, series = _shownSeries;
    if (_reduceMotion || frame == null || domain == null || series == null) {
      _stopRangeMotion();
      return;
    }
    _rangeFrom = (
      frame: frame,
      domain: domain,
      series: series,
      edge: _shownEdge,
      interval: _interval,
    );
    _rangeArmed = true;
    _range.stop();
  }

  /// Lands any range motion at its end, at once.
  void _stopRangeMotion() {
    _rangeFrom = null;
    _rangeArmed = false;
    if (_range.isAnimating) _range.stop();
  }

  /// Where the range motion stands (0..1, eased), or null when none is
  /// under way. Held at 0 while the new range is loading.
  double? get _rangeT {
    if (_rangeFrom == null) return null;
    return _rangeArmed ? 0.0 : _rangeCurve.value;
  }

  /// A finger on the plot, panning, pinching or scaling the axis: the
  /// scale follows it at once so a gesture never lags.
  bool get _gestureActive =>
      _pinching || _panningView || _axisDragging || _pointers.isNotEmpty;

  /// Moves the scale's glide to [target]: at once under Reduce Motion,
  /// during a gesture, for another market, or while a range motion carries
  /// the scale itself; otherwise eased over [_kRefitMotion].
  void _syncScale(KuteYDomain target) {
    if (target == _domTo) return;
    final shown = _shownDomain;
    if (_domTo == null ||
        shown == null ||
        _reduceMotion ||
        _gestureActive ||
        _rangeFrom != null) {
      _domFrom = target;
      _domTo = target;
      if (_refit.value != 1) _refit.value = 1;
      return;
    }
    _domFrom = shown;
    _domTo = target;
    _refit.forward(from: 0);
  }

  /// The scale to paint this frame.
  KuteYDomain _domainNow(KuteYDomain target, double? rangeT) {
    final to = _domTo ?? target;
    final from = _rangeFrom;
    if (rangeT != null && from != null) {
      return _lerpDomain(from.domain, to, rangeT);
    }
    return _lerpDomain(_domFrom ?? to, to, _refitCurve.value);
  }

  static String _tokenKey(MarketChart w) {
    final lines = w.lines;
    if (lines != null && lines.isNotEmpty) {
      return lines.map((l) => l.tokenId).join('|');
    }
    return w.tokenId ?? '';
  }

  /// The lines to plot: [MarketChart.lines], or the bare [tokenId] in the
  /// accent colour.
  List<MarketChartLine> _lineSpecs(Color accent) {
    final lines = widget.lines;
    if (lines != null && lines.isNotEmpty) return lines;
    final token = widget.tokenId;
    if (token == null || token.isEmpty) return const [];
    return [
      MarketChartLine(
          tokenId: token, color: accent, label: '', thin: widget.thin),
    ];
  }

  /// True when every line has converged to one of at most 2 distinct
  /// extreme endpoints (rounded to 2dp) on a 4+ line chart. Used to swap
  /// the spaghetti-tangle of converged outcomes with a single "Market
  /// resolved" pill on resolved sports / many-candidate events.
  bool _allLinesConverged(List<_Series> series) {
    if (series.length <= 3) return false;
    final endpoints = <double>{};
    for (final s in series) {
      if (s.points.isEmpty) return false;
      final last = s.points.last.price;
      if (last > 0.02 && last < 0.98) return false;
      endpoints.add(double.parse(last.toStringAsFixed(2)));
      if (endpoints.length > 2) return false;
    }
    return endpoints.length <= 2;
  }

  /// [older] history pages in front of the [live] tape, cut where the
  /// live tape starts, with the newest point pinned to [pin]. Memoized
  /// per token so a rebuild with the same inputs keeps the list identity.
  List<PolymarketPricePoint> _mergedFor(
    String tokenId,
    List<PolymarketPricePoint> older,
    List<PolymarketPricePoint> live,
    double? pin,
  ) {
    final hit = _merged[tokenId];
    if (hit != null &&
        identical(hit.$1, older) &&
        identical(hit.$2, live) &&
        hit.$3 == pin) {
      return hit.$4;
    }
    List<PolymarketPricePoint> out = live;
    if (older.isNotEmpty && live.isNotEmpty) {
      final cut = _lowerBound(older, live.first.timestamp.millisecondsSinceEpoch);
      if (cut > 0) out = [...older.take(cut), ...live];
    } else if (live.isEmpty) {
      out = older;
    }
    // Pin the last sample to the live price so the chart's right edge —
    // and the crosshair when scrubbed to "now" — agrees with the YES/NO
    // buy buttons. The historical feed lags the live orderbook by tens of
    // seconds, which is what surfaced the buttons-vs-chart discrepancy.
    if (pin != null && out.isNotEmpty && out.last.price != pin) {
      out = [
        ...out.take(out.length - 1),
        PolymarketPricePoint(timestamp: out.last.timestamp, price: pin),
      ];
    }
    _merged[tokenId] = (older, live, pin, out);
    return out;
  }

  // ─────────────────────── a thin market's history ───────────────────────

  /// Memo of [_cleaned] per token: the tape and its cleaned copy.
  final Map<String, (Object, List<PolymarketPricePoint>)> _cleanedTapes = {};

  /// [tape] as the chart draws it: a thin market's needles and combs out
  /// ([smoothThinHistory]). Never a game's chart, where a jump is a goal,
  /// and never a market that trades. Only what is drawn: the live price
  /// and its tag are the caller's own.
  List<PolymarketPricePoint> _cleaned(
      MarketChartLine line, List<PolymarketPricePoint> tape) {
    if (!line.thin || widget.gameStart != null) return tape;
    final hit = _cleanedTapes[line.tokenId];
    if (hit != null && identical(hit.$1, tape)) return hit.$2;
    final out = smoothThinHistory(tape);
    _cleanedTapes[line.tokenId] = (tape, out);
    return out;
  }

  // ─────────────────────── a game, minute by minute ───────────────────────

  /// Memo of [_withGameMinutes] per token: the range's tape, the game's
  /// minutes, and the two merged.
  final Map<String, (Object, Object, List<PolymarketPricePoint>)> _fineMerged =
      {};

  /// The stretch of a game read at one-minute grain: from ten minutes
  /// before kickoff to ten after the end (now, while it is played). Null
  /// for a chart that is not a game's, or a game too long or too old to
  /// read that way.
  ({int start, int? end})? get _gameMinutesWindow {
    final gameStart = widget.gameStart;
    if (gameStart == null) return null;
    final start = gameStart.millisecondsSinceEpoch - 10 * 60000;
    final gameEnd = widget.gameEnd?.millisecondsSinceEpoch;
    final end = gameEnd == null ? null : gameEnd + 10 * 60000;
    return PolyGameWindowHistory.canRead(start, end)
        ? (start: start, end: end)
        : null;
  }

  /// [tape] (one line's points for the range on screen) with the game's
  /// own stretch at one-minute grain where the range's grain is coarser
  /// (1D and longer): ten-minute and twelve-hour points drew a game as a
  /// few smooth bumps. The minutes are read once per game and line
  /// ([PolyGameWindowHistory]); the range's own points are drawn until
  /// they land.
  List<PolymarketPricePoint> _withGameMinutes(
      String tokenId, String interval, List<PolymarketPricePoint> tape) {
    if (interval == '1h' || interval == '6h') return tape;
    final window = _gameMinutesWindow;
    if (window == null) return tape;
    final fine =
        PolyGameWindowHistory.points(tokenId, window.start, window.end);
    if (fine == null) {
      unawaited(PolyGameWindowHistory.load(tokenId, window.start, window.end)
          .then((arrived) {
        if (arrived && mounted) setState(() {});
      }));
      return tape;
    }
    final hit = _fineMerged[tokenId];
    if (hit != null && identical(hit.$1, tape) && identical(hit.$2, fine)) {
      return hit.$3;
    }
    final merged = mergeFineWindow(tape, fine);
    _fineMerged[tokenId] = (tape, fine, merged);
    return merged;
  }

  // ─────────────────────────── viewport ───────────────────────────

  void _resetViewport() {
    _viewSpanMs = null;
    _anchorEndMs = null;
    _pointers.clear();
    _pinching = false;
    _panningView = false;
  }

  /// The window for [series]: the user's span and end, clamped into the
  /// loaded data.
  _Frame _frameFor(List<_Series> series) {
    var dataStart = 0, dataEnd = 0;
    var any = false;
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final a = s.points.first.timestamp.millisecondsSinceEpoch;
      final b = s.points.last.timestamp.millisecondsSinceEpoch;
      if (!any) {
        dataStart = a;
        dataEnd = b;
        any = true;
      } else {
        if (a < dataStart) dataStart = a;
        if (b > dataEnd) dataEnd = b;
      }
    }
    // A single instant still gets a minute of width.
    if (dataEnd - dataStart < 60000) dataStart = dataEnd - 60000;
    final total = dataEnd - dataStart;
    final minSpan = math.min(total, math.max(60000, total ~/ 400));
    var fallback = total;
    var fallbackEnd = dataEnd;
    final game = _gameWindowFor(series, dataStart, dataEnd);
    if (game != null) {
      fallback = game.end - game.start;
      fallbackEnd = game.end;
    }
    final span = (_viewSpanMs ?? fallback).clamp(minSpan, total);
    final end =
        (_anchorEndMs ?? fallbackEnd).clamp(dataStart + span, dataEnd);
    return (
      dataStart: dataStart,
      dataEnd: dataEnd,
      start: end - span,
      end: end,
      minSpan: minSpan,
    );
  }

  /// A game's own window inside the range on screen ([polyGameWindow]),
  /// which the chart opens on: 6H or 1D of a game two hours old would
  /// otherwise be mostly the flat price before kickoff. Not where the
  /// range's grain leaves the game too few points to draw (a three-hour
  /// game is three points of 1W).
  ({int start, int end})? _gameWindowFor(
      List<_Series> series, int dataStart, int dataEnd) {
    final gameStart = widget.gameStart;
    if (gameStart == null) return null;
    final window = polyGameWindow(
      dataStartMs: dataStart,
      dataEndMs: dataEnd,
      gameStartMs: gameStart.millisecondsSinceEpoch,
      gameEndMs: widget.gameEnd?.millisecondsSinceEpoch,
    );
    if (window == null) return null;
    var most = 0;
    for (final s in series) {
      final n = _lowerBound(s.points, window.end + 1) -
          _lowerBound(s.points, window.start);
      if (n > most) most = n;
    }
    return most >= _kGameWindowMinPoints ? window : null;
  }

  /// Applies a new span and end, keeping the live edge when the window
  /// reaches the newest point.
  void _setView(int span, int end, _Frame f) {
    final total = f.dataEnd - f.dataStart;
    final s = span.clamp(f.minSpan, total);
    final e = end.clamp(f.dataStart + s, f.dataEnd);
    final anchor = e >= f.dataEnd ? null : e;
    if (s == (f.end - f.start) && anchor == _anchorEndMs) return;
    setState(() {
      _viewSpanMs = s;
      _anchorEndMs = anchor;
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    // A finger on the plot stops the zoom nudge where the view rests.
    _nudgeTimer?.cancel();
    _nudge.cancel();
    // A finger on the plot lands a range motion where it was going, so
    // the gesture works on the window it sees settle.
    if (_rangeFrom != null) setState(_stopRangeMotion);
    final f = _frame;
    if (_pointers.length == 2 && f != null) {
      final points = _pointers.values.toList();
      _axisCandidate = false;
      _axisDragging = false;
      _panningView = false;
      _pinching = true;
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartFocalX = (points[0].dx + points[1].dx) / 2;
      _pinchStartSpan = f.end - f.start;
      _pinchStartEnd = f.end;
      setState(() => _touchMs = null);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final f = _frame;
    if (!_pinching || _pointers.length < 2 || f == null) return;
    final points = _pointers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    final focalX = (points[0].dx + points[1].dx) / 2;
    final startDistance = _pinchStartDistance ?? distance;
    final startSpan = _pinchStartSpan ?? (f.end - f.start);
    if (startDistance <= 0 || startSpan <= 0 || _plotWidth <= 0) return;
    final total = f.dataEnd - f.dataStart;
    // Fingers apart → a shorter span (zoom in); together → longer.
    final scale = (distance / startDistance).clamp(0.05, 20.0);
    final span = (startSpan / scale).round().clamp(f.minSpan, total);
    // Sliding both fingers pans the window.
    final panMs =
        ((focalX - (_pinchStartFocalX ?? focalX)) / _plotWidth * span).round();
    final wantEnd = (_pinchStartEnd ?? f.end) - panMs;
    // Zooming out with the whole range already on screen, or sliding past
    // its oldest point, is a request for more history.
    if (span >= total && scale < 0.98) _requestMoreHistory();
    if (wantEnd < f.dataStart + span) _requestMoreHistory();
    _setView(span, wantEnd, f);
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty && _pinching) {
      _pinching = false;
      _pinchStartDistance = null;
      _pinchStartFocalX = null;
      _pinchStartSpan = null;
      _pinchStartEnd = null;
    }
  }

  void _onPanStart(DragStartDetails d, Size size) {
    final f = _frame;
    if (f == null) return;
    final pos = d.localPosition;
    _gestureStart = pos;
    _axisCandidate = pos.dx <= _kAxisStripWidth &&
        pos.dy <= size.height - _kBottomMargin &&
        _shownDomain != null;
    _panningView = !_axisCandidate;
    _panStartX = pos.dx;
    _panStartEnd = f.end;
    _panSpan = f.end - f.start;
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    if (_axisCandidate) {
      final delta = d.localPosition - _gestureStart;
      _axisCandidate = false;
      if (delta.dy.abs() > delta.dx.abs()) {
        setState(() {
          _axisDragging = true;
          _axisStartY = _gestureStart.dy;
          _axisStartDomain = _shownDomain;
        });
      } else {
        _panningView = true;
      }
    }
    if (_axisDragging) {
      _onAxisDrag(d.localPosition.dy, size);
      return;
    }
    final f = _frame;
    if (!_panningView || f == null || _plotWidth <= 0) return;
    // Dragging right walks back in time.
    final wantEnd = _panStartEnd -
        ((d.localPosition.dx - _panStartX) / _plotWidth * _panSpan).round();
    if (wantEnd < f.dataStart + _panSpan) _requestMoreHistory();
    _setView(_panSpan, wantEnd, f);
  }

  void _onPanEnd() {
    _panningView = false;
    _axisCandidate = false;
    if (_axisDragging) {
      setState(() {
        _axisDragging = false;
        _axisStartDomain = null;
      });
    }
  }

  // ─────────────────────────── history ────────────────────────────

  /// Asks for older points, at most once every 700ms.
  void _requestMoreHistory() {
    if (!PolyChartHistory.canPage(_interval)) return;
    final now = DateTime.now();
    if (now.difference(_lastHistoryRequest).inMilliseconds <= 700) return;
    _lastHistoryRequest = now;
    unawaited(_loadMoreHistory());
  }

  /// The window was panned or pinched past its oldest point: load one
  /// page of older points in front of every line (PolyChartHistory
  /// throttles and caches).
  Future<void> _loadMoreHistory() async {
    final shown = _held;
    final interval = _interval;
    if (shown == null || shown.isEmpty) return;
    final pages = await Future.wait([
      for (final s in shown)
        if (s.points.isNotEmpty)
          PolyChartHistory.loadOlder(
            tokenId: s.tokenId,
            interval: interval,
            beforeMs: s.points.first.timestamp.millisecondsSinceEpoch,
          ),
    ]);
    final added = pages.fold<int>(0, (a, b) => a + b);
    if (!mounted || added <= 0 || interval != _interval) return;
    setState(() {});
    TrackingService.track('chart_history_extended', params: {
      'venue': 'polymarket',
      'surface': widget.surface,
      'interval': interval,
      'points': added,
      ...VenueAnalytics.pmKindParams(widget.kindIds),
    });
  }

  // ─────────────────────────── price scale ───────────────────────────

  /// Where the scale should sit for [series] in window [f]: the manual
  /// domain, or the autoscale fit of the points on screen (the live leads
  /// included). The "Bought" lines never take part in the fit.
  KuteYDomain _scaleTarget(List<_Series> series, _Frame f, List<double>? leads) {
    final manual = _manualDomain;
    if (!_autoScale && manual != null) return manual;
    while (_extremes.length < series.length) {
      _extremes.add(KuteRangeExtremes<PolymarketPricePoint>(
          lowOf: (p) => p.price, highOf: (p) => p.price));
    }
    var lo = double.infinity, hi = double.negativeInfinity;
    var firstVisible = -1;
    for (var i = 0; i < series.length; i++) {
      final pts = series[i].points;
      if (pts.isEmpty) continue;
      final ext = _extremes[i]..sync(pts);
      final i0 = _lowerBound(pts, f.start);
      final i1 = _lowerBound(pts, f.end + 1);
      if (i == 0) firstVisible = i0;
      final r = ext.query(i0, i1);
      if (r != null) {
        lo = math.min(lo, r.lo);
        hi = math.max(hi, r.hi);
      }
      // The line enters the window at the value of the last point before
      // it (all there is of it when nothing falls inside).
      if (r == null || i0 > 0) {
        final p = _pointAt(pts, f.start);
        if (p != null) {
          lo = math.min(lo, p.price);
          hi = math.max(hi, p.price);
        }
      }
      if (leads != null && i < leads.length && i1 >= pts.length) {
        lo = math.min(lo, leads[i]);
        hi = math.max(hi, leads[i]);
      }
      // A tag at the live price, off the end of its line, is on the scale.
      final tag = series[i].tagPrice;
      if (tag != null && i1 >= pts.length) {
        lo = math.min(lo, tag);
        hi = math.max(hi, tag);
      }
    }
    if (!lo.isFinite || !hi.isFinite) {
      lo = 0;
      hi = 1;
    }
    // A game's markers have the top of the plot to themselves, and every
    // line's end dot and pulse stay clear of both edges.
    final drawH = math.max(1.0, _plotH - _kBottomMargin);
    final lane = widget.markers.isEmpty ? 0.0 : _kMarkerLane / drawH;
    final room = kPolyChartEndRoom / drawH;
    // The window's identity: a pan, a pinch, another range, another set
    // of lines or another series under the same range each fit afresh.
    return _scaleTracker.fit(
      (
        firstVisible,
        f.end - f.start,
        _anchorEndMs == null,
        _interval,
        f.dataStart,
        Object.hashAll([for (final s in series) s.tokenId]),
      ),
      lo,
      hi,
      domain: (lo, hi) => polyChartEdgeRoom(polyChartDomain(lo, hi), lo, hi,
          top: math.max(room, lane), bottom: room),
    );
  }

  /// Back to autoscale (the Auto pill or a double tap).
  void _restoreAutoScale() {
    if (_autoScale) return;
    HapticFeedback.selectionClick();
    setState(() {
      _autoScale = true;
      _manualDomain = null;
      _scaleTracker.reset();
    });
    _trackAutoScale(true);
  }

  /// Forget any manual scale without telling analytics (a new market or
  /// range, not a user choice). [jump] skips the glide.
  void _resetScale({bool jump = false}) {
    _autoScale = true;
    _manualDomain = null;
    _axisDragging = false;
    _axisStartDomain = null;
    _scaleTracker.reset();
    if (jump) {
      _domTo = null;
      _shownDomain = null;
    }
  }

  /// True on the second tap of a double tap. Detected by hand so the
  /// single-tap path stays immediate.
  bool _isDoubleTap(Offset pos) {
    final now = DateTime.now();
    final hit = now.difference(_lastTapAt) < kDoubleTapTimeout &&
        (pos - _lastTapPos).distance < kDoubleTapSlop;
    _lastTapAt = hit ? DateTime(0) : now;
    _lastTapPos = pos;
    return hit;
  }

  /// Vertical drag on the price axis: down squeezes the scale, up
  /// stretches it, about the middle of the shown domain.
  void _onAxisDrag(double y, Size size) {
    final d0 = _axisStartDomain;
    final priceH = size.height - _kBottomMargin;
    if (d0 == null || priceH <= 0) return;
    final f = math.exp((y - _axisStartY) / priceH * 1.6);
    final mid = (d0.minY + d0.maxY) / 2;
    final half = (d0.maxY - d0.minY) / 2 * f;
    if (!half.isFinite || half <= 0) return;
    final wasAuto = _autoScale;
    setState(() {
      _autoScale = false;
      _manualDomain = (minY: mid - half, maxY: mid + half);
    });
    if (wasAuto) _trackAutoScale(false);
  }

  void _trackAutoScale(bool auto) {
    VenueAnalytics.settingChanged(
      'chart_autoscale_toggled',
      setting: 'auto_scale',
      value: auto,
      scope: _analyticsScope,
      extra: {
        'venue': 'polymarket',
        'surface': widget.surface,
        ...VenueAnalytics.pmKindParams(widget.kindIds),
      },
    );
  }

  // ─────────────────────────── scrub ───────────────────────────

  /// Crosshair at [dx]: snaps to the primary line's nearest point.
  void _scrubAt(double dx, List<_Series> series) {
    final f = _frame;
    if (f == null || series.isEmpty || _plotWidth <= 0) return;
    final pts = series.first.points;
    if (pts.isEmpty) return;
    final chartW = math.max(1.0, _plotWidth - _kRightMargin);
    final x = dx.clamp(0.0, chartW);
    final t = f.start + (x / chartW * (f.end - f.start)).round();
    var i = _lowerBound(pts, t).clamp(0, pts.length - 1);
    if (i > 0 &&
        (t - pts[i - 1].timestamp.millisecondsSinceEpoch).abs() <
            (pts[i].timestamp.millisecondsSinceEpoch - t).abs()) {
      i--;
    }
    final ms = pts[i].timestamp.millisecondsSinceEpoch;
    if (ms == _touchMs) return;
    // Throttled to ~10/s so a fast scrub over dense points doesn't buzz
    // continuously.
    final now = DateTime.now();
    if (now.difference(_lastHaptic).inMilliseconds > 100) {
      HapticFeedback.selectionClick();
      _lastHaptic = now;
    }
    setState(() => _touchMs = ms);
    final near = _clusterNear(_xFor(ms, f, chartW), 10);
    if (near == null) {
      _scrubbedMarkerMs = null;
    } else if (near.markers.first.tMs != _scrubbedMarkerMs) {
      _scrubbedMarkerMs = near.markers.first.tMs;
      widget.onMarkerShown
          ?.call(near.markers.first, near.markers.length, 'scrub');
    }
  }

  void _endScrub() {
    _scrubbedMarkerMs = null;
    if (_touchMs != null) setState(() => _touchMs = null);
  }

  // ─────────────────────────── event markers ───────────────────────────

  /// The markers inside window [f], grouped so that no two drawn markers
  /// are closer than [_kMarkerClusterGap]. Linear in the marker count and
  /// memoized, so a rebuild with the same window costs nothing.
  List<_MarkerCluster> _clustersFor(_Frame f, double chartW) {
    final markers = widget.markers;
    if (markers.isEmpty || chartW <= 0) return const [];
    final memo = _clusterMemo;
    if (memo != null &&
        identical(memo.$1, markers) &&
        memo.$2 == f.start &&
        memo.$3 == f.end &&
        memo.$4 == chartW) {
      return memo.$5;
    }
    final out = <_MarkerCluster>[];
    var group = <MarketChartMarker>[];
    var firstX = 0.0, lastX = 0.0;
    void flush() {
      if (group.isEmpty) return;
      out.add(_MarkerCluster((firstX + lastX) / 2, group));
      group = [];
    }

    for (final m in markers) {
      if (m.tMs < f.start || m.tMs > f.end) continue;
      final x = _xFor(m.tMs, f, chartW);
      if (group.isNotEmpty && x - firstX > _kMarkerClusterGap) flush();
      if (group.isEmpty) firstX = x;
      lastX = x;
      group.add(m);
    }
    flush();
    _clusterMemo = (markers, f.start, f.end, chartW, out);
    return out;
  }

  /// The cluster nearest to plot x [dx], within [slop] pixels.
  _MarkerCluster? _clusterNear(double dx, double slop) {
    final f = _frame;
    if (f == null || widget.markers.isEmpty || _plotWidth <= 0) return null;
    final chartW = math.max(1.0, _plotWidth - _kRightMargin);
    _MarkerCluster? best;
    var bestDist = slop;
    for (final c in _clustersFor(f, chartW)) {
      final d = (c.x - dx).abs();
      if (d <= bestDist) {
        best = c;
        bestDist = d;
      }
    }
    return best;
  }

  /// A tap on a marker puts the crosshair on it for a few seconds: the
  /// scrub card names it, with the chances at that moment.
  bool _tapMarker(Offset pos, List<_Series> series) {
    final hit = _clusterNear(pos.dx, _kMarkerTapSlop);
    if (hit == null) return false;
    // The tap reports it once; the crosshair landing on it does not again.
    _scrubbedMarkerMs = hit.markers.first.tMs;
    _scrubAt(hit.x, series);
    final held = _touchMs;
    _tappedTimer?.cancel();
    _tappedTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _tappedCluster = null;
        // A scrub started since keeps its crosshair.
        if (_touchMs == held && _pointers.isEmpty) {
          _touchMs = null;
          _scrubbedMarkerMs = null;
        }
      });
    });
    setState(() => _tappedCluster = hit);
    widget.onMarkerShown?.call(hit.markers.first, hit.markers.length, 'tap');
    return true;
  }

  /// "Goal 38' 1–0", or the first two of a cluster and how many more.
  static String _clusterLabel(List<MarketChartMarker> markers) {
    if (markers.length == 1) return markers.first.label;
    final shown = markers.take(2).map((m) => m.label).join(' · ');
    return markers.length > 2 ? '$shown +${markers.length - 2}' : shown;
  }

  // ─────────────────────────── live endpoint ───────────────────────────

  /// Track the leading values so a live tick eases the endpoint to its
  /// new position instead of snapping it.
  void _updateLead(List<double> lasts) {
    final to = _leadTo;
    if (to == null || to.length != lasts.length) {
      _leadFrom = lasts;
      _leadTo = lasts;
      return;
    }
    var same = true;
    for (int i = 0; i < lasts.length; i++) {
      if (to[i] != lasts[i]) {
        same = false;
        break;
      }
    }
    if (same) return;
    // Restart the tween from wherever the endpoint currently sits.
    _leadFrom = _currentLeads();
    _leadTo = lasts;
    if (_reduceMotion) {
      _lead.value = 1.0;
    } else {
      _lead.forward(from: 0);
    }
  }

  List<double> _currentLeads() {
    final from = _leadFrom, to = _leadTo;
    if (from == null || to == null) return const [];
    final t = _leadCurve.value;
    return [for (int i = 0; i < to.length; i++) from[i] + (to[i] - from[i]) * t];
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _rangeFrom != null) _stopRangeMotion();
    final accent = widget.accentColor ??
        (widget.lines != null && widget.lines!.isNotEmpty
            ? widget.lines!.first.color
            : const Color(0xFF3B82F6));
    final specs = _lineSpecs(accent);
    if (specs.isEmpty) {
      _stopRangeMotion();
      return const SizedBox.shrink();
    }

    final interval = _interval;
    // Every line's history is requested at once (one provider per line,
    // all watched in this build); a line counts as pending until its
    // history lands, even when a live tick already arrived, so a lone
    // tick never reads as "no history yet".
    var pending = 0;
    final fresh = <_Series>[];
    for (final line in specs) {
      final key = (tokenId: line.tokenId, interval: interval);
      final live = ref.watch(polymarketLiveChartProvider(key));
      final history = ref.watch(polymarketMarketHistoryProvider(key));
      if (!history.hasValue && !history.hasError) {
        pending++;
        continue;
      }
      final tape =
          _cleaned(line, _withGameMinutes(line.tokenId, interval, live));
      // A wide book that has not traded has no price to show
      // (shown_price.dart): its line ends where its history does.
      final unpriced = ref.watch(livePriceProvider
          .select((s) => s.unpriced.contains(line.tokenId)));
      final pin = widget.resolved || unpriced ? null : line.livePrice;
      // A thin market's live book can sit far from its stale history: the
      // newest point is not pinned to it (that drew a cliff); the tag
      // still says the live price.
      final cliff = polyThinCliff(
          thin: line.thin, live: pin, last: tape.lastOrNull?.price);
      final points = _mergedFor(
        line.tokenId,
        PolyChartHistory.older(line.tokenId, interval),
        tape,
        cliff ? null : pin,
      );
      fresh.add(_Series(line.tokenId, points, line.color, line.label,
          tagPrice: cliff ? pin : null));
    }
    final feedLive = ref.watch(livePriceProvider.select((s) => s.live));
    final isLive = feedLive && !widget.resolved;

    List<_Series> series;
    var partial = false;
    var loading = false;
    final held = _held;
    if (pending > 0 && held != null && held.length == specs.length) {
      // New range still loading: keep the old lines up until every new
      // line is in.
      series = held;
      loading = true;
    } else if (pending == specs.length) {
      // Cold start with nothing back yet.
      _stopRangeMotion();
      return _plotSlot(SkeletonLineChart(
        height: widget.height,
        padding: EdgeInsets.zero,
      ));
    } else {
      // Cold start draws each line as it arrives.
      series = fresh;
      partial = pending > 0;
      if (pending == 0 && series.any((s) => s.points.length >= 2)) {
        _held = series;
      }
    }
    if (partial && !series.any((s) => s.points.length >= 2)) {
      // The lines back so far have no points; wait for the rest.
      _stopRangeMotion();
      return _plotSlot(SkeletonLineChart(
        height: widget.height,
        padding: EdgeInsets.zero,
      ));
    }

    if (!series.any((s) => s.points.length >= 2)) {
      _stopRangeMotion();
      return _plotSlot(Center(
        child: Text(
          context.l10n.betNoHistoryYet,
          style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
        ),
      ));
    }

    // Resolved many-outcome event: every line is pinned at 0% or 100%,
    // and at most 2 distinct endpoints across 4+ candidates. The line
    // chart at this point is just noise (overlapping strokes at the
    // top/bottom edge) — swap it for a single centered "Market resolved"
    // tile.
    if (!partial && _allLinesConverged(series)) {
      _stopRangeMotion();
      return _plotSlot(_resolvedTile(c));
    }

    final f = _frameFor(series);
    _frame = f;
    final atLiveEdge = f.end >= f.dataEnd;
    _updateLead([
      for (final s in series) s.points.isEmpty ? 0.5 : s.points.last.price
    ]);
    // The new range's lines are in: the motion from the old view starts.
    if (_rangeArmed && !loading) {
      _rangeArmed = false;
      _range.forward(from: 0);
    }
    // The scale's target for the window the motion ends on; the glide (or
    // the range motion) carries the painted scale to it.
    final leadsNow = _currentLeads();
    final target = _scaleTarget(
        series, f, leadsNow.length == series.length ? leadsNow : null);
    _syncScale(target);

    final wantPulse = isLive && atLiveEdge && !_reduceMotion;
    if (wantPulse && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!wantPulse && _pulse.isAnimating) {
      _pulse.stop();
    }

    // One build per frame of a range motion: the window and every layer
    // of the plot move together.
    if (!loading && !partial) _maybeScheduleNudge(series);
    return AnimatedBuilder(
      animation: Listenable.merge([_range, _nudge.listenable]),
      builder: (context, _) {
        final rangeT = _rangeT;
        final from = _rangeFrom;
        final shown = _nudged(rangeT == null || from == null
            ? f
            : _lerpFrame(from.frame, f, rangeT));
        _shownFrame = shown;
        _shownSeries = series;
        _shownEdge = atLiveEdge;
        return _chartBody(
            c, series, shown, rangeT, target, atLiveEdge, isLive);
      },
    );
  }

  /// The plot for one frame: [shown]
  /// is the window painted, the one the view rests on ([_frame]) at rest
  /// and on its way there during a range motion at [rangeT].
  Widget _chartBody(
    AppColorsExtension c,
    List<_Series> series,
    _Frame shown,
    double? rangeT,
    KuteYDomain target,
    bool atLiveEdge,
    bool isLive,
  ) {
    final plot = LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      _plotWidth = w;
      final size = Size(w, _plotH);
      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (e) => _onPointerUp(e.pointer),
        onPointerCancel: (e) => _onPointerUp(e.pointer),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (d) {
            if (_pinching) return;
            if (_tapMarker(d.localPosition, series)) return;
            if (_isDoubleTap(d.localPosition) && !_autoScale) {
              _restoreAutoScale();
            }
          },
          onPanStart: (d) {
            if (_pinching) return;
            _onPanStart(d, size);
          },
          onPanUpdate: (d) {
            if (_pinching) return;
            _onPanUpdate(d, size);
          },
          onPanEnd: (_) {
            if (_pinching) return;
            _onPanEnd();
          },
          onPanCancel: () {
            if (_pinching) return;
            _onPanEnd();
          },
          // The crosshair is a long press (then slide), so a plain drag
          // pans and two fingers zoom without fighting the scrub.
          onLongPressStart: (d) {
            if (_pinching) return;
            HapticFeedback.selectionClick();
            _scrubAt(d.localPosition.dx, series);
          },
          onLongPressMoveUpdate: (d) {
            if (_pinching) return;
            _scrubAt(d.localPosition.dx, series);
          },
          onLongPressEnd: (_) => _endScrub(),
          onLongPressCancel: _endScrub,
          child: SizedBox(
            width: double.infinity,
            height: _plotH,
            child: _layers(context, c, series, shown, rangeT, target,
                atLiveEdge, isLive),
          ),
        ),
      );
    });

    // The time axis: when the window painted starts and ends.
    final locale = kuteChartLocale(context);
    final axis = kuteTimeAxisTexts(
      start: DateTime.fromMillisecondsSinceEpoch(shown.start),
      end: DateTime.fromMillisecondsSinceEpoch(shown.end),
      live: !widget.resolved && shown.end >= shown.dataEnd,
      nowLabel: context.l10n.betNow,
      locale: locale,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        plot,
        KuteTimeAxis(start: axis.start, end: axis.end),
      ],
    );
  }

  /// The plot's layers for one frame: the data painter, the price scale,
  /// the "Bought" lines, the live pulse, the crosshair and the Auto pill,
  /// all through window [f] (the painted one) and one domain. The domain
  /// glides to each new autoscale [target] ([_kRefitMotion]), or eases
  /// with a range change ([_kRangeMotion], [rangeT]); the endpoints ease
  /// to each live tick (250ms). During a range change the old lines fade
  /// out as the new ones fade in, both through the same moving window and
  /// scale.
  Widget _layers(
    BuildContext context,
    AppColorsExtension c,
    List<_Series> series,
    _Frame f,
    double? rangeT,
    KuteYDomain target,
    bool atLiveEdge,
    bool isLive,
  ) {
    final isDark = context.isDark;
    final touch = _touchMs;
    final scrubbing = touch != null;
    // The old range's lines, fading out, while a range motion runs over
    // another feed (the same feed: only the window moves).
    final from = _rangeFrom;
    final fade = rangeT != null && from != null && from.interval != _interval
        ? rangeT
        : null;
    final colors = [for (final s in series) s.color];
    final bought = _boughtFor(series);
    final clusters =
        _clustersFor(f, math.max(1.0, _plotWidth - _kRightMargin));

    // The scrub card is written here, never inside a paint pass.
    final card = touch == null ? null : _scrubCard(series, f, touch);

    return AnimatedBuilder(
      animation: Listenable.merge([_lead, _refit]),
      builder: (context, _) {
        final domain = _domainNow(target, rangeT);
        _shownDomain = domain;
        var leads = _currentLeads();
        if (leads.length != series.length) leads = const [];
        return Stack(
          children: [
            if (fade != null && from != null)
              Positioned.fill(
                key: const ValueKey('lines-from'),
                child: Opacity(
                  opacity: 1 - fade,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _LinesPainter(
                        series: from.series,
                        leads: const [],
                        start: f.start,
                        end: f.end,
                        domain: domain,
                        atLiveEdge: from.edge,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              key: const ValueKey('lines'),
              child: Opacity(
                opacity: fade ?? 1,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _LinesPainter(
                      series: series,
                      leads: leads,
                      start: f.start,
                      end: f.end,
                      domain: domain,
                      atLiveEdge: atLiveEdge,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
            ),
            // ── Price scale (left-edge labels + faint hairlines), the
            // Hyperliquid treatment: shown while scrubbing or while the
            // scale is set by hand.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity:
                      (scrubbing || !_autoScale || _axisDragging) ? 1 : 0,
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ScalePainter(
                        domain: domain,
                        labelColor: c.textTertiary,
                        hairlineColor: c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── "Bought" lines: the dashed average-price reference per
            // held outcome, tagged at the right edge like the
            // Hyperliquid entry line.
            for (final b in bought)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: KuteChartTradeLinesPainter(
                        lines: b.lines,
                        dragging: null,
                        hits: _tradeHits,
                        palette: ChartTradeLinePalette(
                          up: b.color,
                          down: b.color,
                          warning: AppColors.warning,
                          neutral: c.textSecondary,
                          tagBackground:
                              isDark ? Colors.black : Colors.white,
                          tagText: isDark ? Colors.black : Colors.white,
                        ),
                        formatPrice: _formatCents,
                        resolveGeometry: (size) =>
                            _priceGeometry(size, domain),
                        // The lines' value tags are the latest prices'
                        // own: a Bought tag keeps off them, and one at
                        // the price now reads "Bought ≈" beside it.
                        latestTags: (size, geom) => [
                          for (final t in _valueTags(
                            series: series,
                            leads: leads,
                            start: f.start,
                            end: f.end,
                            domain: domain,
                            drawH: geom.priceH,
                            plotWidth: size.width - _kRightMargin,
                            atLiveEdge: atLiveEdge,
                          ))
                            (y: t.y, top: t.top, height: t.height),
                        ],
                        repaintKey: (domain, isDark, leads, f.start, f.end,
                            atLiveEdge),
                      ),
                    ),
                  ),
                ),
              ),
            // ── Event markers: their own canvas, repainted only when
            // the markers, the window or the picked one change.
            if (clusters.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _MarkersPainter(
                        clusters: clusters,
                        activeMs: scrubbing
                            ? _scrubbedMarkerMs
                            : _tappedCluster?.markers.first.tMs,
                        lineColor: c.textTertiary,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ),
              ),
            if (isLive && atLiveEdge)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    willChange: true,
                    painter: KutePulseDecorPainter(
                      pulse: _pulse,
                      dataSets: [
                        for (var i = 0; i < series.length; i++)
                          [
                            series[i].points.isEmpty
                                ? 0.0
                                : series[i].points.first.price,
                            leads.isEmpty
                                ? (series[i].points.isEmpty
                                    ? 0.0
                                    : series[i].points.last.price)
                                : leads[i],
                          ],
                      ],
                      colors: colors,
                      visible: !scrubbing,
                      resolve: (size) =>
                          _pulsePoints(size, series, f, domain, leads),
                    ),
                  ),
                ),
              ),
            // ── Value tags: over the lines and the pulse, each layer
            // fading with its lines through a range motion.
            if (fade != null && from != null)
              Positioned.fill(
                key: const ValueKey('tags-from'),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1 - fade,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TagsPainter(
                          series: from.series,
                          leads: const [],
                          start: f.start,
                          end: f.end,
                          domain: domain,
                          atLiveEdge: from.edge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              key: const ValueKey('tags'),
              child: IgnorePointer(
                child: Opacity(
                  opacity: fade ?? 1,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _TagsPainter(
                        series: series,
                        leads: leads,
                        start: f.start,
                        end: f.end,
                        domain: domain,
                        atLiveEdge: atLiveEdge,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: KuteChartCrosshair(
                resolve: touch == null
                    ? null
                    : (size) => _crosshairData(
                          size,
                          series,
                          f,
                          domain,
                          touch,
                          card,
                        ),
                repaintKey: (
                  touch,
                  f.start,
                  f.end,
                  series.length,
                  domain,
                  isDark,
                ),
                isDark: isDark,
                hairlineColor: c.textTertiary,
                cardRightInset: kuteScrubCardTagGutter,
              ),
            ),
            // ── Auto: the scale was set by hand; one tap (or a double
            // tap on the plot) fits the visible points again.
            if (!_autoScale)
              Positioned(
                left: 4,
                top: math.max(0.0, _plotH - _kBottomMargin - 30),
                child: HlAutoScalePill(
                  onTap: _restoreAutoScale,
                  background: isDark
                      ? Colors.black.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.9),
                  border: c.border,
                  text: c.textPrimary,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The "Bought" trade lines per held outcome on the chart, in that
  /// outcome's colour. Memoized on content so a rebuild keeps identities.
  List<({Color color, List<ChartTradeLine> lines})> _boughtFor(
      List<_Series> series) {
    if (widget.bought.isEmpty) return const [];
    final label = context.l10n.polyChartBought;
    final out = <({Color color, List<ChartTradeLine> lines})>[];
    for (final s in series) {
      for (final b in widget.bought) {
        if (b.tokenId != s.tokenId || !(b.price > 0) || b.price > 1) continue;
        final key = '${b.tokenId}|${b.price}|$label';
        final lines = _boughtLines[key] ??= [
          ChartTradeLine(
            id: 'bought:${b.tokenId}',
            kind: ChartTradeLineKind.entry,
            price: b.price,
            label: label,
            detail: _formatCents(b.price),
          ),
        ];
        out.add((color: s.color, lines: lines));
      }
    }
    if (_boughtLines.length > 16) _boughtLines.clear();
    return out;
  }

  /// The price geometry the trade-lines layer maps through: the same
  /// linear mapping the data painter uses over the plot height.
  KuteDrawingGeometry _priceGeometry(Size size, KuteYDomain domain) {
    final span = domain.maxY - domain.minY;
    return KuteDrawingGeometry(
      timesMs: const [0],
      width: size.width,
      priceH: math.max(1.0, size.height - _kBottomMargin),
      loP: domain.minY,
      rangeP: span > 0 ? span : 1.0,
      bucketMs: 1,
    );
  }

  List<KutePulsePoint> _pulsePoints(Size size, List<_Series> series, _Frame f,
      KuteYDomain domain, List<double> leads) {
    final chartW = size.width - _kRightMargin;
    final drawH = size.height - _kBottomMargin;
    if (chartW <= 0 || drawH <= 0) return const [];
    final out = <KutePulsePoint>[];
    for (var i = 0; i < series.length; i++) {
      final pts = series[i].points;
      if (pts.length < 2) continue;
      final t = pts.last.timestamp.millisecondsSinceEpoch;
      if (t < f.start) continue;
      final v = leads.isEmpty ? pts.last.price : leads[i];
      // On the plot's right edge while a range motion's window has not
      // reached the newest point yet (at rest it always has).
      out.add(KutePulsePoint(
        Offset(math.min(_xFor(t, f, chartW), chartW), _yFor(v, domain, drawH)),
        series[i].color,
      ));
    }
    return out;
  }

  KuteCrosshairData? _crosshairData(
    Size size,
    List<_Series> series,
    _Frame f,
    KuteYDomain domain,
    int touch,
    KuteScrubCardData? card,
  ) {
    final chartW = size.width - _kRightMargin;
    final drawH = size.height - _kBottomMargin;
    if (chartW <= 0 || drawH <= 0 || series.isEmpty) return null;
    final dots = <KuteCrosshairDot>[];
    for (var i = 0; i < series.length; i++) {
      final p = _pointAt(series[i].points, touch);
      if (p == null) continue;
      dots.add(KuteCrosshairDot(
        y: _yFor(p.price, domain, drawH).clamp(0.0, drawH),
        color: series[i].color,
      ));
    }
    return KuteCrosshairData(
      x: _xFor(touch, f, chartW).clamp(0.0, chartW),
      dots: dots,
      plotBottom: drawH,
      card: card,
    );
  }

  /// The scrub card at [touch]: one line's chance and its move since the
  /// start of the window, or a many-line chart's chances (leaders
  /// first), then the time and the game event the crosshair is on.
  KuteScrubCardData? _scrubCard(List<_Series> series, _Frame f, int touch) {
    final time = kuteChartDayTime(
        DateTime.fromMillisecondsSinceEpoch(touch), kuteChartLocale(context));
    final details = <String>[];
    if (widget.markers.isNotEmpty) {
      final chartW = math.max(1.0, _plotWidth - _kRightMargin);
      final near = _clusterNear(_xFor(touch, f, chartW), 10);
      if (near != null) details.add(_clusterLabel(near.markers));
    }
    if (series.length == 1) {
      final s = series.first;
      final p = _pointAt(s.points, touch);
      if (p == null) return null;
      final first = _pointAt(s.points, f.start) ??
          (s.points.isEmpty ? null : s.points.first);
      final delta = first == null ? 0.0 : p.price - first.price;
      final move = formatPolyChanceMove(delta);
      return KuteScrubCardData(
        value: _formatPct(p.price),
        change: move == null ? null : '$move%',
        changeSign: move == null ? 0 : (delta > 0 ? 1 : -1),
        time: time,
        details: details,
      );
    }
    final entries = <({String label, double price, Color color})>[
      for (final s in series)
        if (_pointAt(s.points, touch) case final p?)
          (label: s.label, price: p.price, color: s.color),
    ]..sort((a, b) => b.price.compareTo(a.price));
    if (entries.isEmpty) return null;
    return KuteScrubCardData(
      entries: [
        for (final e in entries.take(5))
          KuteScrubCardEntry(
              color: e.color,
              label: _shortName(e.label),
              value: _formatPct(e.price)),
      ],
      time: time,
      details: details,
    );
  }

  Widget _plotSlot(Widget child) =>
      SizedBox(width: double.infinity, height: widget.height, child: child);

  Widget _resolvedTile(AppColorsExtension c) {
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          context.l10n.marketResolved,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Window [a] eased toward [b] by [t] (0..1): the end moves straight
/// across, the span in proportion (log space), so a zoom from a year to
/// an hour reads as one steady zoom instead of a sliver at the end. [b]
/// itself at 1, so the motion lands exactly where the view rests.
_Frame _lerpFrame(_Frame a, _Frame b, double t) {
  if (t >= 1) return b;
  final spanA = math.max(1, a.end - a.start).toDouble();
  final spanB = math.max(1, b.end - b.start).toDouble();
  final span =
      math.exp(math.log(spanA) + (math.log(spanB) - math.log(spanA)) * t);
  final end = a.end + (b.end - a.end) * t;
  return (
    dataStart: b.dataStart,
    dataEnd: b.dataEnd,
    start: (end - span).round(),
    end: end.round(),
    minSpan: b.minSpan,
  );
}

/// Scale [a] eased toward [b] by [t]: [b] itself at 1, [a] at 0.
KuteYDomain _lerpDomain(KuteYDomain a, KuteYDomain b, double t) {
  if (t >= 1) return b;
  if (t <= 0) return a;
  return (
    minY: a.minY + (b.minY - a.minY) * t,
    maxY: a.maxY + (b.maxY - a.maxY) * t,
  );
}

/// Time → x inside the plot width [chartW] for window [f].
double _xFor(int ms, _Frame f, double chartW) {
  final span = f.end - f.start;
  return span > 0 ? (ms - f.start) / span * chartW : chartW;
}

/// Price → y inside the plot height [drawH]: the linear mapping the
/// Hyperliquid chart and the shared trade-lines layer use.
double _yFor(double v, KuteYDomain d, double drawH) {
  final span = d.maxY - d.minY;
  return drawH * (1 - (v - d.minY) / (span > 0 ? span : 1.0));
}

/// Data layer for one or many probability lines, through the shared
/// engine (monotone cubic smoothing, cached gradient fill, round-cap
/// stroke, endpoint dot). Points are placed by time, so a line that starts
/// later or ticks faster still lines up with the others. The single-line
/// chart gets the gradient fill under its line (a multi-line fill stack
/// would be mud). At the live edge each line ends in its dot; its value
/// pill is the tags layer's ([_TagsPainter]).
///
/// Crosshair, scale, value tags, "Bought" lines and live pulse live in their own
/// layers, so this canvas repaints only when the series, the window, the
/// domain or an endpoint tween changes.
class _LinesPainter extends CustomPainter {
  final List<_Series> series;
  final List<double> leads;
  final int start;
  final int end;
  final KuteYDomain domain;
  final bool atLiveEdge;
  final bool isDark;


  _LinesPainter({
    required this.series,
    required this.leads,
    required this.start,
    required this.end,
    required this.domain,
    required this.atLiveEdge,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _kRightMargin;
    final drawH = size.height - _kBottomMargin;
    if (chartW <= 0 || drawH <= 0 || series.isEmpty) return;
    final f = (dataStart: start, dataEnd: end, start: start, end: end, minSpan: 0);
    final single = series.length == 1;

    for (var li = series.length - 1; li >= 0; li--) {
      final s = series[li];
      final pts = s.points;
      if (pts.length < 2) continue;
      final n = pts.length;
      // The points on screen plus one either side, so the line runs
      // off the edges instead of stopping short of them.
      final i0 = math.max(0, _lowerBound(pts, start) - 1);
      final i1 = math.min(n, _lowerBound(pts, end + 1) + 1);
      if (i1 - i0 < 2) continue;
      final lead = leads.isNotEmpty ? leads[li] : pts.last.price;
      final offsets = <Offset>[
        for (var i = i0; i < i1; i++)
          Offset(
            _xFor(pts[i].timestamp.millisecondsSinceEpoch, f, chartW),
            _yFor(i == n - 1 ? lead : pts[i].price, domain, drawH),
          ),
      ];
      final path = kuteMonotonePath(offsets);

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, -4, chartW + 6, drawH + 8));
      if (single) {
        final fillPath = Path.from(path)
          ..lineTo(offsets.last.dx, drawH)
          ..lineTo(offsets.first.dx, drawH)
          ..close();
        canvas.drawPath(
            fillPath, Paint()..shader = kuteFillShader(chartW, drawH, s.color));
      }
      canvas.drawPath(path, kuteStrokePaint(s.color, width: single ? 2.0 : 2.5));
      canvas.restore();

      // Endpoint dot, only while the newest point
      // is on screen (the live pulse rides the decor layer).
      final lastT = pts.last.timestamp.millisecondsSinceEpoch;
      if (!atLiveEdge || lastT < start) continue;
      // On the plot's right edge while a range motion's window has not
      // reached the newest point yet (at rest it always has).
      final endPt = Offset(math.min(_xFor(lastT, f, chartW), chartW),
          _yFor(lead, domain, drawH));
      kuteDrawEndpointDot(canvas, endPt, s.color, isDark: isDark);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) =>
      !identical(old.series, series) ||
      !_sameLeads(old.leads, leads) ||
      old.start != start ||
      old.end != end ||
      old.domain != domain ||
      old.atLiveEdge != atLiveEdge ||
      old.isDark != isDark;

  static bool _sameLeads(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The right-edge value tags ([_valueTags]): a small rounded pill per
/// line filled with the line's colour, contrast text by luminance (the
/// Hyperliquid price tag treatment), reading the outcome's short name and
/// its chance. Their own layer, over the live pulse, so no ring of a dot
/// shows through a pill.
class _TagsPainter extends CustomPainter {
  final List<_Series> series;
  final List<double> leads;
  final int start;
  final int end;
  final KuteYDomain domain;
  final bool atLiveEdge;

  _TagsPainter({
    required this.series,
    required this.leads,
    required this.start,
    required this.end,
    required this.domain,
    required this.atLiveEdge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _kRightMargin;
    final drawH = size.height - _kBottomMargin;
    if (chartW <= 0 || drawH <= 0 || series.isEmpty) return;
    final tags = _valueTags(
      series: series,
      leads: leads,
      start: start,
      end: end,
      domain: domain,
      drawH: drawH,
      plotWidth: chartW,
      atLiveEdge: atLiveEdge,
    );
    for (final t in tags) {
      final text = _endpointTp(
        t.text,
        t.color.computeLuminance() > 0.55 ? Colors.black : Colors.white,
        _kTagFontSize,
        FontWeight.w800,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - t.width, t.top, t.width, t.height),
          const Radius.circular(5),
        ),
        Paint()..color = t.color,
      );
      text.paint(canvas,
          Offset(size.width - t.width + _kTagPadH, t.top + _kTagPadV));
    }
  }

  @override
  bool shouldRepaint(covariant _TagsPainter old) =>
      !identical(old.series, series) ||
      !_LinesPainter._sameLeads(old.leads, leads) ||
      old.start != start ||
      old.end != end ||
      old.domain != domain ||
      old.atLiveEdge != atLiveEdge;
}

/// The probability scale: 4-6 nice levels (the Hyperliquid ladder) as
/// left-edge labels with faint full-width hairlines, inside the plot so
/// nothing else shifts. Levels outside 0-100% are skipped.
/// The game's event markers: a faint dashed line down the plot per marker
/// (or cluster), topped by a dot in the scoring side's colour. A cluster
/// shows how many events it holds; a period change is a small hollow ring.
class _MarkersPainter extends CustomPainter {
  final List<_MarkerCluster> clusters;

  /// The picked cluster (its first marker's time), drawn stronger.
  final int? activeMs;
  final Color lineColor;
  final bool isDark;

  _MarkersPainter({
    required this.clusters,
    required this.activeMs,
    required this.lineColor,
    required this.isDark,
  });

  static const double _badgeY = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final drawH = size.height - _kBottomMargin;
    for (final cluster in clusters) {
      final active = cluster.markers.first.tMs == activeMs;
      final minor = cluster.minor;
      final x = cluster.x;
      final line = Paint()
        ..color = (minor ? lineColor : cluster.color)
            .withValues(alpha: active ? 0.9 : (minor ? 0.28 : 0.45))
        ..strokeWidth = active ? 1.2 : 0.8;
      for (var y = _badgeY + 9; y < drawH; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, drawH)), line);
      }
      final center = Offset(x, _badgeY);
      final count = cluster.markers.length;
      if (count > 1) {
        canvas.drawCircle(center, 8, Paint()..color = cluster.color);
        final tp = _endpointTp(count > 9 ? '9+' : '$count',
            isDark ? Colors.black : Colors.white, 9, FontWeight.w800);
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      } else if (minor) {
        canvas.drawCircle(
          center,
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = lineColor.withValues(alpha: active ? 1 : 0.7),
        );
      } else {
        canvas.drawCircle(center, 5, Paint()..color = cluster.color);
      }
      if (active) {
        canvas.drawCircle(
          center,
          count > 1 ? 10.5 : 7.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = cluster.color.withValues(alpha: 0.6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarkersPainter old) =>
      !identical(old.clusters, clusters) ||
      old.activeMs != activeMs ||
      old.lineColor != lineColor ||
      old.isDark != isDark;
}

/// A level of the probability scale as its label writes it: "20%",
/// "0.5%". The ladder's bottom rung can come back as negative zero, which
/// would be written "-0%".
String polyScaleLabel(double level, int decimals) =>
    '${(level == 0 ? 0.0 : level).toStringAsFixed(decimals)}%';

class _ScalePainter extends CustomPainter {
  final KuteYDomain domain;
  final Color labelColor;
  final Color hairlineColor;

  _ScalePainter({
    required this.domain,
    required this.labelColor,
    required this.hairlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final drawH = size.height - _kBottomMargin;
    if (drawH <= 0) return;
    final levels = hlNiceLevels(domain.minY * 100, domain.maxY * 100);
    if (levels.isEmpty) return;
    final step = levels.length > 1 ? levels[1] - levels[0] : 1.0;
    final decimals = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    final linePaint = Paint()
      ..color = hairlineColor.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    for (final level in levels) {
      if (level < 0 || level > 100) continue;
      final y = _yFor(level / 100, domain, drawH);
      if (y < 0 || y > drawH) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      final tp = _endpointTp(
          polyScaleLabel(level, decimals), labelColor, 10.5, FontWeight.w600);
      final ty =
          (y - tp.height - 2).clamp(0.0, math.max(0.0, drawH - tp.height));
      tp.paint(canvas, Offset(2, ty.toDouble()));
    }
  }

  @override
  bool shouldRepaint(covariant _ScalePainter old) =>
      old.domain != domain ||
      old.labelColor != labelColor ||
      old.hairlineColor != hairlineColor;
}

/// A name short enough to sit beside its figure: the whole label when it
/// is short, otherwise everything after the first word ("Marine Le Pen" →
/// "Le Pen", "Jean-Luc Mélenchon" → "Mélenchon"), cut with an ellipsis
/// past twelve characters. Yes/No style labels are left as they are.
String _shortName(String label) {
  final rest = polyChartShortName(label);
  return rest.length <= 12 ? rest : '${rest.substring(0, 11)}…';
}
