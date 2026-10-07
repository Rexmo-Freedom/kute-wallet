import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Coins under this many sats are dust: at everyday fee rates one input
/// costs about this much to spend, so they collapse into a single cell
/// instead of cluttering the map. The legend states the threshold.
const int kUtxoDustThresholdSats = 1000;

/// Chain tip so cells can be coloured by confirmation depth. Cached for
/// ten minutes on success and one minute on failure. Null means the
/// explorer was unreachable; the map then falls back to each coin's own
/// confirmation time, and to confirmed versus unconfirmed when that is
/// missing too.
final utxoMapTipHeightProvider = FutureProvider.autoDispose<int?>((ref) async {
  final link = ref.keepAlive();
  int? tip;
  try {
    tip = await MempoolAddressService.fetchBlockTipHeight()
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    tip = null;
  }
  final timer = Timer(
      tip == null ? const Duration(minutes: 1) : const Duration(minutes: 10),
      link.close);
  ref.onDispose(timer.cancel);
  return tip;
});

/// Age classes the map colours by. [confirmed] is the fallback when a coin
/// is confirmed but neither the tip nor its block time is known.
enum UtxoAgeBucket { unconfirmed, day, month, year, older, confirmed }

const int _secondsPerBlock = 600;
const int _daySeconds = 86400;

/// Seconds since the coin confirmed: exact from block depth when the tip
/// is known, else from the block time, else null.
int? utxoAgeSeconds(LocalOutput coin,
    {required int? tipHeight, required int nowSeconds}) {
  final position = coin.chainPosition;
  if (position is! ConfirmedChainPosition) return null;
  final blockTime = position.confirmationBlockTime;
  final height = blockTime.blockId.height;
  if (tipHeight != null && tipHeight >= height) {
    return (tipHeight - height + 1) * _secondsPerBlock;
  }
  if (blockTime.confirmationTime > 0) {
    return math.max(0, nowSeconds - blockTime.confirmationTime);
  }
  return null;
}

UtxoAgeBucket utxoAgeBucket(LocalOutput coin, int? ageSeconds) {
  if (coin.chainPosition is! ConfirmedChainPosition) {
    return UtxoAgeBucket.unconfirmed;
  }
  if (ageSeconds == null) return UtxoAgeBucket.confirmed;
  if (ageSeconds < _daySeconds) return UtxoAgeBucket.day;
  if (ageSeconds < 30 * _daySeconds) return UtxoAgeBucket.month;
  if (ageSeconds < 365 * _daySeconds) return UtxoAgeBucket.year;
  return UtxoAgeBucket.older;
}

/// Single-hue sequential ramp on the marketUp hue, young (light) to old
/// (deep), one set per theme so the deep end still reads on black. The
/// accent stays reserved for unconfirmed, as it is everywhere else.
class _UtxoMapPalette {
  _UtxoMapPalette._();

  static const _light = [
    Color(0xFF67E099),
    Color(0xFF2DAF6B),
    Color(0xFF0A7D48),
    Color(0xFF00512B),
  ];
  static const _dark = [
    Color(0xFF75EEA6),
    Color(0xFF3EBC77),
    Color(0xFF0B8B50),
    Color(0xFF026035),
  ];

  static Color fill(UtxoAgeBucket bucket, {required bool isLight}) {
    final ramp = isLight ? _light : _dark;
    return switch (bucket) {
      UtxoAgeBucket.unconfirmed => AppColors.accent,
      UtxoAgeBucket.day => ramp[0],
      UtxoAgeBucket.month => ramp[1],
      UtxoAgeBucket.year => ramp[2],
      UtxoAgeBucket.older => ramp[3],
      UtxoAgeBucket.confirmed => ramp[1],
    };
  }

  /// Text on a solid fill: near-black on the light steps and the accent,
  /// white on the deep steps.
  static Color ink(Color fill) =>
      fill.computeLuminance() > 0.3 ? const Color(0xFF0E2417) : Colors.white;
}

enum _ItemKind { coin, dust, small }

class _MapItem {
  final String id;
  final _ItemKind kind;
  final List<LocalOutput> coins;
  final int sats;
  final double weight;
  final UtxoAgeBucket? bucket;
  final int? ageSeconds;
  final String? label;

  const _MapItem({
    required this.id,
    required this.kind,
    required this.coins,
    required this.sats,
    required this.weight,
    this.bucket,
    this.ageSeconds,
    this.label,
  });

  LocalOutput get coin => coins.first;
}

String _coinId(LocalOutput coin) =>
    '${coin.outpoint.txid}:${coin.outpoint.vout}';

int _sats(LocalOutput coin) => coin.txout.value.toSat();

/// Squarified treemap (Bruls, Huizing, van Wijk). [weights] must be sorted
/// descending; rects come back in the same order.
List<Rect> _squarify(List<double> weights, Size size) {
  final n = weights.length;
  final rects = List<Rect>.filled(n, Rect.zero);
  if (n == 0 || size.isEmpty) return rects;
  final total = weights.fold<double>(0, (sum, w) => sum + w);
  if (total <= 0) return rects;
  final scale = size.width * size.height / total;
  final areas = weights.map((w) => math.max(w * scale, 1e-6)).toList();

  var x = 0.0, y = 0.0, w = size.width, h = size.height;
  final row = <int>[];
  var rowSum = 0.0, rowMin = double.infinity, rowMax = 0.0;

  double worst(double sum, double minArea, double maxArea, double side) {
    final side2 = side * side;
    final sum2 = sum * sum;
    return math.max(side2 * maxArea / sum2, sum2 / (side2 * minArea));
  }

  void flush() {
    if (row.isEmpty) return;
    if (w >= h) {
      final stripW = h > 0 ? rowSum / h : 0.0;
      var cy = y;
      for (final i in row) {
        final ch = stripW > 0 ? areas[i] / stripW : 0.0;
        rects[i] = Rect.fromLTWH(x, cy, stripW, ch);
        cy += ch;
      }
      x += stripW;
      w = math.max(0, w - stripW);
    } else {
      final stripH = w > 0 ? rowSum / w : 0.0;
      var cx = x;
      for (final i in row) {
        final cw = stripH > 0 ? areas[i] / stripH : 0.0;
        rects[i] = Rect.fromLTWH(cx, y, cw, stripH);
        cx += cw;
      }
      y += stripH;
      h = math.max(0, h - stripH);
    }
    row.clear();
    rowSum = 0;
    rowMin = double.infinity;
    rowMax = 0;
  }

  var i = 0;
  while (i < n) {
    final area = areas[i];
    final side = math.min(w, h);
    if (row.isEmpty || side <= 0) {
      row.add(i);
      rowSum += area;
      rowMin = math.min(rowMin, area);
      rowMax = math.max(rowMax, area);
      i++;
      continue;
    }
    final current = worst(rowSum, rowMin, rowMax, side);
    final withNext = worst(
        rowSum + area, math.min(rowMin, area), math.max(rowMax, area), side);
    if (withNext <= current) {
      row.add(i);
      rowSum += area;
      rowMin = math.min(rowMin, area);
      rowMax = math.max(rowMax, area);
      i++;
    } else {
      flush();
    }
  }
  flush();
  return rects;
}

/// The Coins map: a squarified treemap where area is the coin's share of
/// the wallet and colour is its age. Dust and coins too small to draw fold
/// into one neutral cell each, so the picture stays readable. Tap opens the
/// coin sheet, hold opens the label editor, and the legend below explains
/// the colours.
class UtxoMap extends ConsumerStatefulWidget {
  /// Coins sorted by value, largest first.
  final List<LocalOutput> coins;
  final int totalSats;
  final String btcFormat;
  final Map<String, String> labels;
  final void Function(LocalOutput coin) onOpenCoin;
  final void Function(LocalOutput coin) onEditLabel;

  const UtxoMap({
    super.key,
    required this.coins,
    required this.totalSats,
    required this.btcFormat,
    required this.labels,
    required this.onOpenCoin,
    required this.onEditLabel,
  });

  @override
  ConsumerState<UtxoMap> createState() => _UtxoMapState();
}

class _UtxoMapState extends ConsumerState<UtxoMap> {
  /// Drilled-into group: tapping a grouped cell zooms the map to just
  /// those coins instead of listing them in a sheet (user decision).
  List<LocalOutput>? _zoomCoins;
  String? _zoomTitle;

  List<LocalOutput> get coins => _zoomCoins ?? widget.coins;
  int get totalSats => _zoomCoins == null
      ? widget.totalSats
      : _zoomCoins!.fold(0, (sum, coin) => sum + _sats(coin));
  String get btcFormat => widget.btcFormat;
  Map<String, String> get labels => widget.labels;
  void Function(LocalOutput coin) get onOpenCoin => widget.onOpenCoin;
  void Function(LocalOutput coin) get onEditLabel => widget.onEditLabel;

  @override
  void didUpdateWidget(UtxoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The wallet's coin set changed underneath us; a stale zoom would
    // show coins that no longer exist.
    if (oldWidget.coins.length != widget.coins.length) {
      _zoomCoins = null;
      _zoomTitle = null;
    }
  }

  static const double _gap = 1.5;
  // Below this a coin cannot be tapped or read, so it folds into the
  // smaller-coins cell. The twelve largest always stand on their own.
  static const double _minCellArea = 18 * 18;
  static const int _alwaysShown = 12;
  // Grouped cells get at least this much room so their name and count fit.
  static const double _minGroupArea = 96 * 48;

  String _ageLabel(BuildContext context, UtxoAgeBucket bucket) {
    final l10n = context.l10n;
    return switch (bucket) {
      UtxoAgeBucket.unconfirmed => l10n.unconfirmed,
      UtxoAgeBucket.day => l10n.coinMapAgeDay,
      UtxoAgeBucket.month => l10n.coinMapAgeMonth,
      UtxoAgeBucket.year => l10n.coinMapAgeYear,
      UtxoAgeBucket.older => l10n.coinMapAgeOlder,
      UtxoAgeBucket.confirmed => l10n.confirmed,
    };
  }

  String? _shortAge(BuildContext context, int? seconds) {
    if (seconds == null) return null;
    final l10n = context.l10n;
    if (seconds < _daySeconds) {
      return l10n.coinMapAgeShortHours(math.max(1, seconds ~/ 3600));
    }
    final days = seconds ~/ _daySeconds;
    if (days < 30) return l10n.coinMapAgeShortDays(days);
    if (days < 365) return l10n.coinMapAgeShortMonths(days ~/ 30);
    return l10n.coinMapAgeShortYears(days ~/ 365);
  }

  String get _unit => btcFormat == 'sats' ? 'sats' : 'BTC';

  String _amountWithUnit(int sats) =>
      '${sats.toFormattedString(btcFormat)} $_unit';

  String _share(int sats) {
    final pct = totalSats > 0 ? sats / totalSats * 100 : 0.0;
    return '${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%';
  }

  List<_MapItem> _buildItems(Size size, Map<String, int?> ages) {
    final dust = <LocalOutput>[];
    final visible = <LocalOutput>[];
    for (final coin in coins) {
      (_sats(coin) < kUtxoDustThresholdSats ? dust : visible).add(coin);
    }
    final area = size.width * size.height;
    final kept = <LocalOutput>[];
    final small = <LocalOutput>[];
    for (var i = 0; i < visible.length; i++) {
      final coin = visible[i];
      final cellArea = totalSats > 0 ? _sats(coin) / totalSats * area : 0.0;
      (i < _alwaysShown || cellArea >= _minCellArea ? kept : small).add(coin);
    }
    // Groups are floored so they stay tappable; the map states they are
    // grouped, so the slight area distortion is honest.
    final floorWeight = area > 0 ? totalSats * (_minGroupArea / area) : 0.0;
    final items = <_MapItem>[
      for (final coin in kept)
        _MapItem(
          id: _coinId(coin),
          kind: _ItemKind.coin,
          coins: [coin],
          sats: _sats(coin),
          weight: _sats(coin).toDouble(),
          bucket: utxoAgeBucket(coin, ages[_coinId(coin)]),
          ageSeconds: ages[_coinId(coin)],
          label: bitcoinCoinLabel(labels, coin.outpoint),
        ),
      if (small.isNotEmpty)
        _MapItem(
          id: 'small',
          kind: _ItemKind.small,
          coins: small,
          sats: small.fold(0, (sum, c) => sum + _sats(c)),
          weight: math.max(
              small.fold<int>(0, (sum, c) => sum + _sats(c)).toDouble(),
              floorWeight),
        ),
      if (dust.isNotEmpty)
        _MapItem(
          id: 'dust',
          kind: _ItemKind.dust,
          coins: dust,
          sats: dust.fold(0, (sum, c) => sum + _sats(c)),
          weight: math.max(
              dust.fold<int>(0, (sum, c) => sum + _sats(c)).toDouble(),
              floorWeight),
        ),
    ];
    items.sort((a, b) => b.weight.compareTo(a.weight));
    return items;
  }

  /// Zoom the map into a grouped cell rather than listing it in a sheet:
  /// the same treemap, re-laid out over just those coins, with a way back.
  void _openGroup(BuildContext context, _MapItem item) {
    final l10n = context.l10n;
    final isDust = item.kind == _ItemKind.dust;
    TrackingService.track('coin_map_cell_opened',
        params: {'kind': isDust ? 'dust' : 'small'});
    HapticFeedback.selectionClick();
    setState(() {
      _zoomCoins = List<LocalOutput>.unmodifiable(item.coins);
      _zoomTitle = isDust ? l10n.coinMapDustCoins : l10n.coinMapSmallCoins;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 360);

    // Latest known height: the explorer tip, nudged up if a coin already
    // sits above it (a stale cache). Without a tip, ages come from block
    // times instead, never from the wallet's own newest block.
    var tip = ref.watch(utxoMapTipHeightProvider).asData?.value;
    if (tip != null) {
      for (final coin in coins) {
        if (coin.chainPosition
            case ConfirmedChainPosition(:final confirmationBlockTime)) {
          tip = math.max(tip!, confirmationBlockTime.blockId.height);
        }
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ages = <String, int?>{
      for (final coin in coins)
        _coinId(coin): utxoAgeSeconds(coin, tipHeight: tip, nowSeconds: now),
    };

    // Legend lists only what is on screen, in age order.
    final present = <UtxoAgeBucket>{
      for (final coin in coins)
        if (_sats(coin) >= kUtxoDustThresholdSats)
          utxoAgeBucket(coin, ages[_coinId(coin)]),
    };
    final hasDust = coins.any((c) => _sats(c) < kUtxoDustThresholdSats);
    final legend = <_LegendEntry>[
      for (final bucket in UtxoAgeBucket.values)
        if (present.contains(bucket))
          _LegendEntry(
              fill: _UtxoMapPalette.fill(bucket, isLight: isLight),
              label: _ageLabel(context, bucket)),
      if (hasDust)
        _LegendEntry(
            fill: null,
            label: l10n.coinMapDustLegend(
                kUtxoDustThresholdSats.toFormattedString('sats'))),
    ];

    return Column(
      children: [
        if (_zoomTitle != null) ...[
          _UtxoZoomBar(
            title: _zoomTitle!,
            count: coins.length,
            onBack: () {
              HapticFeedback.selectionClick();
              setState(() {
                _zoomCoins = null;
                _zoomTitle = null;
              });
            },
          ),
          SizedBox(height: 8.h),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final items = _buildItems(size, ages);
              final rects =
                  _squarify(items.map((i) => i.weight).toList(), size);
              return Stack(
                children: [
                  for (var i = 0; i < items.length; i++)
                    _positioned(context, items[i], rects[i],
                        isLight: isLight, duration: duration),
                ],
              );
            },
          ),
        ),
        SizedBox(height: 8.h),
        _UtxoMapLegend(entries: legend, neutralFill: c.surfaceLight),
      ],
    );
  }

  Widget _positioned(BuildContext context, _MapItem item, Rect rect,
      {required bool isLight, required Duration duration}) {
    final c = context.colors;
    final l10n = context.l10n;
    final width = math.max(0.0, rect.width - 2 * _gap);
    final height = math.max(0.0, rect.height - 2 * _gap);
    final radius = math.min(8.r, math.min(width, height) * 0.2);
    final amount = _amountWithUnit(item.sats);

    final _UtxoMapCell cell;
    switch (item.kind) {
      case _ItemKind.coin:
        final fill = _UtxoMapPalette.fill(item.bucket!, isLight: isLight);
        final ageText = _ageLabel(context, item.bucket!);
        cell = _UtxoMapCell(
          fill: fill,
          ink: _UtxoMapPalette.ink(fill),
          border: null,
          radius: radius,
          duration: duration,
          primary: item.sats.toFormattedString(btcFormat),
          primarySuffix: ' $_unit',
          dimLeadingZeros: true,
          secondary: _share(item.sats),
          secondaryExtra: _shortAge(context, item.ageSeconds),
          tertiary: item.label,
          unconfirmed: item.bucket == UtxoAgeBucket.unconfirmed,
          semanticsLabel: [
            amount,
            _share(item.sats),
            ageText,
            if (item.label case final label?) label,
          ].join(', '),
          onTap: () {
            TrackingService.track('coin_map_cell_opened',
                params: {'kind': 'coin'});
            onOpenCoin(item.coin);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            TrackingService.track('coin_map_label_edit_opened');
            onEditLabel(item.coin);
          },
        );
      case _ItemKind.dust:
      case _ItemKind.small:
        final name = item.kind == _ItemKind.dust
            ? l10n.utxoDust
            : l10n.coinMapSmallCoins;
        final count = l10n.activityUtxoCountLabel(item.coins.length);
        cell = _UtxoMapCell(
          fill: c.surfaceLight,
          ink: c.textPrimary,
          border: c.borderSubtle,
          radius: radius,
          duration: duration,
          primary: name,
          primarySuffix: null,
          dimLeadingZeros: false,
          secondary: count,
          secondaryExtra: null,
          tertiary: amount,
          unconfirmed: false,
          semanticsLabel: [name, count, amount].join(', '),
          onTap: () => _openGroup(context, item),
          onLongPress: null,
        );
    }

    return AnimatedPositioned(
      key: ValueKey(item.id),
      duration: duration,
      curve: Curves.easeOutCubic,
      left: rect.left + _gap,
      top: rect.top + _gap,
      width: width,
      height: height,
      child: cell,
    );
  }
}

/// Text line the cell may show, ranked so the most useful lines survive
/// when space is tight: amount, then share, then label.
class _CellLine {
  final String text;
  final TextStyle style;
  final Size size;
  final int priority;
  final int order;
  final bool amount;
  final String? suffix;
  final bool marker;
  const _CellLine({
    required this.text,
    required this.style,
    required this.size,
    required this.priority,
    required this.order,
    this.amount = false,
    this.suffix,
    this.marker = false,
  });
}

class _UtxoMapCell extends StatelessWidget {
  final Color fill;
  final Color ink;
  final Color? border;
  final double radius;
  final Duration duration;
  final String primary;
  final String? primarySuffix;
  final bool dimLeadingZeros;
  final String secondary;
  final String? secondaryExtra;
  final String? tertiary;
  final bool unconfirmed;
  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _UtxoMapCell({
    required this.fill,
    required this.ink,
    required this.border,
    required this.radius,
    required this.duration,
    required this.primary,
    required this.primarySuffix,
    required this.dimLeadingZeros,
    required this.secondary,
    required this.secondaryExtra,
    required this.tertiary,
    required this.unconfirmed,
    required this.semanticsLabel,
    required this.onTap,
    required this.onLongPress,
  });

  static const double _padX = 5;
  static const double _padY = 3;
  static const double _lineGap = 1;

  Size _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  /// Picks the lines that fit, by priority, then returns them in visual
  /// order. Nothing is ever clipped: a line that does not fit is dropped.
  List<_CellLine> _fit(BuildContext context, double availW, double availH,
      double primarySize, double secondarySize) {
    final scaler = MediaQuery.textScalerOf(context);
    final primaryStyle = TextStyle(
      color: ink,
      fontSize: primarySize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final secondaryStyle = TextStyle(
      color: ink.withValues(alpha: 0.82),
      fontSize: secondarySize,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tertiaryStyle = TextStyle(
      color: ink,
      fontSize: secondarySize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.1,
    );
    // Same glyph size and gap `_line` draws for the unconfirmed marker.
    final markerW = unconfirmed ? primarySize * 0.85 + 3 : 0.0;

    final candidates = <_CellLine>[];
    // Amount: with its unit when there is room, bare otherwise.
    for (final suffix in [primarySuffix, null]) {
      final text = suffix == null ? primary : '$primary$suffix';
      final size = _measure(text, primaryStyle, scaler);
      if (size.width + markerW <= availW) {
        candidates.add(_CellLine(
            text: primary,
            suffix: suffix,
            style: primaryStyle,
            size: Size(size.width + markerW, size.height),
            priority: 0,
            order: 1,
            amount: true,
            marker: unconfirmed));
        break;
      }
      if (suffix == null) break;
    }
    // Share, with the age caption when there is room.
    for (final extra in [secondaryExtra, null]) {
      final text = extra == null ? secondary : '$secondary · $extra';
      final size = _measure(text, secondaryStyle, scaler);
      if (size.width <= availW) {
        candidates.add(_CellLine(
            text: text,
            style: secondaryStyle,
            size: size,
            priority: 1,
            order: 2));
        break;
      }
      if (extra == null) break;
    }
    if (tertiary case final tertiary?) {
      final size = _measure(tertiary, tertiaryStyle, scaler);
      if (size.width <= availW) {
        candidates.add(_CellLine(
            text: tertiary,
            style: tertiaryStyle,
            size: size,
            priority: 2,
            order: 0));
      }
    }

    candidates.sort((a, b) => a.priority.compareTo(b.priority));
    final chosen = <_CellLine>[];
    var used = 0.0;
    for (final line in candidates) {
      final needed = line.size.height + (chosen.isEmpty ? 0 : _lineGap);
      if (used + needed > availH) break;
      chosen.add(line);
      used += needed;
    }
    chosen.sort((a, b) => a.order.compareTo(b.order));
    return chosen;
  }

  Widget _line(_CellLine line) {
    Widget text;
    if (line.amount) {
      text = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.marker) ...[
            Icon(Icons.schedule_rounded,
                size: line.style.fontSize! * 0.85, color: ink),
            const SizedBox(width: 3),
          ],
          if (dimLeadingZeros)
            BtcAmountText(
                text: line.text,
                style: line.style,
                brightColor: ink,
                dimColor: ink.withValues(alpha: 0.55),
                maxLines: 1)
          else
            Text(line.text, style: line.style, maxLines: 1, softWrap: false),
          if (line.suffix case final suffix?)
            Text(suffix, style: line.style, maxLines: 1, softWrap: false),
        ],
      );
    } else {
      text = Text(line.text, style: line.style, maxLines: 1, softWrap: false);
    }
    // Every line was measured to fit; the scale-down box only absorbs a
    // sub-pixel rounding difference so nothing can ever paint an overflow.
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: _FadeIn(
          duration: duration,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(radius),
              border: border == null
                  ? null
                  : Border.all(color: border!, width: 0.5),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final minSide = math.min(w, h);
                if (minSide < 14 || w < 26) return const SizedBox.shrink();
                final primarySize =
                    (minSide * 0.17).clamp(11.sp, 17.sp).toDouble();
                final secondarySize =
                    (primarySize * 0.78).clamp(10.sp, 13.sp).toDouble();
                final lines = _fit(context, w - 2 * _padX, h - 2 * _padY,
                    primarySize, secondarySize);
                if (lines.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _padX, vertical: _padY),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < lines.length; i++) ...[
                          if (i > 0) const SizedBox(height: _lineGap),
                          _line(lines[i]),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades a cell in when it first appears; instant under reduced motion.
class _FadeIn extends StatelessWidget {
  final Duration duration;
  final Widget child;
  const _FadeIn({required this.duration, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      child: child,
      builder: (_, value, child) => Opacity(opacity: value, child: child),
    );
  }
}

class _LegendEntry {
  /// Null draws the neutral grouped-cell swatch.
  final Color? fill;
  final String label;
  const _LegendEntry({required this.fill, required this.label});
}

/// Compact legend: an "Age" caption, one swatch per bucket on screen, and
/// the dust rule when dust is present.
class _UtxoMapLegend extends StatelessWidget {
  final List<_LegendEntry> entries;
  final Color neutralFill;
  const _UtxoMapLegend({required this.entries, required this.neutralFill});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 11.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
    );
    return Wrap(
      spacing: 10.w,
      runSpacing: 4.h,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(context.l10n.coinMapAgeTitle,
            style:
                labelStyle.copyWith(color: c.textTertiary, letterSpacing: 0.2)),
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9.sp,
                height: 9.sp,
                decoration: BoxDecoration(
                  color: entry.fill ?? neutralFill,
                  borderRadius: BorderRadius.circular(2.5.r),
                  border: entry.fill == null
                      ? Border.all(color: c.border, width: 0.5)
                      : null,
                ),
              ),
              SizedBox(width: 4.w),
              Text(entry.label, style: labelStyle),
            ],
          ),
      ],
    );
  }
}

/// Back out of a zoomed group: one quiet row above the map.
class _UtxoZoomBar extends StatelessWidget {
  const _UtxoZoomBar({
    required this.title,
    required this.count,
    required this.onBack,
  });

  final String title;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBack,
      child: Row(
        children: [
          Icon(Icons.arrow_back_rounded, size: 18.sp, color: c.textSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            context.l10n.activityUtxoCountLabel(count),
            style: TextStyle(color: c.textSecondary, fontSize: 13.sp),
          ),
        ],
      ),
    );
  }
}
