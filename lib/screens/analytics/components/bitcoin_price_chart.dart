import 'package:kute/services/tracking_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:kute/helpers/extension.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:coingecko_api/data/ohlc_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/screens/shared/charts/kute_chart_autoscale.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class BitcoinPriceChart extends ConsumerStatefulWidget {
  final String selectedAsset;

  /// A new value puts a zoomed chart back on the whole range (the range
  /// pill tapped again).
  final Object? viewResetKey;
  const BitcoinPriceChart({super.key, required this.selectedAsset, this.viewResetKey});

  @override
  ConsumerState<BitcoinPriceChart> createState() => _BitcoinPriceChartState();
}

class _BitcoinPriceChartState extends ConsumerState<BitcoinPriceChart> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showCandles = false;
  bool _entranceStarted = false;

  // Candle-view scrub, zoom and pan (the line view does both inside
  // KuteLineChart).
  int? _candleTouchIndex;
  DateTime _lastCandleHaptic = DateTime(0);
  final KuteIndexViewport _candleViewport = KuteIndexViewport();
  int _candleCount = -1;

  @override
  void initState() {
    super.initState();
    // The line view now fades/morphs itself through the shared engine
    // (KuteLineChart); this controller only covers the candle view's
    // fade-in on mount and on line→candle toggles.
    _fadeController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the decorative fade-in entrance once. Honour reduce-motion
    // by jumping straight to the finished state instead of playing the
    // transition — the chart is still fully shown.
    if (_entranceStarted) return;
    _entranceStarted = true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _fadeController.value = 1.0;
    } else {
      _fadeController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant BitcoinPriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewResetKey != widget.viewResetKey) _candleViewport.reset();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  DateTime _normalizeDate(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  void _onCandleScrub(
      double dx, double width, List<OHLCInfo> candles, KuteIndexWindow window) {
    if (candles.isEmpty || width <= 0) return;
    final x = dx.clamp(0.0, width);
    final idx =
        window.indexAt(x, width).floor().clamp(0, candles.length - 1).toInt();
    if (idx == _candleTouchIndex) return;
    // One event per scrub gesture: the first index only, never the moves.
    if (_candleTouchIndex == null) {
      TrackingService.analyticsChartScrubbed(chart: 'price', view: 'candles');
    }
    // Throttled to ~10/s: an un-throttled selectionClick per index
    // change buzzes continuously on a fast scrub across dense candles.
    final now = DateTime.now();
    if (now.difference(_lastCandleHaptic).inMilliseconds > 100) {
      HapticFeedback.selectionClick();
      _lastCandleHaptic = now;
    }
    setState(() => _candleTouchIndex = idx);
  }

  void _endCandleScrub() {
    if (_candleTouchIndex != null) {
      setState(() => _candleTouchIndex = null);
    }
  }

  /// The candles in [window], one either side included.
  static (int, int) _candleRange(int n, KuteIndexWindow window) {
    final first = window.start.floor().clamp(0, n - 1).toInt();
    final last = (window.end.ceil() - 1).clamp(first, n - 1).toInt();
    return (first, last);
  }

  /// The price scale of the candles on screen: the venue charts'
  /// autoscale over their wicks.
  static KuteYDomain _candleDomain(
      List<OHLCInfo> candles, KuteIndexWindow window) {
    final (first, last) = _candleRange(candles.length, window);
    var lo = candles[first].low.toDouble();
    var hi = candles[first].high.toDouble();
    for (var i = first; i <= last; i++) {
      lo = min(lo, candles[i].low.toDouble());
      hi = max(hi, candles[i].high.toDouble());
    }
    return kuteAutoScaleDomain(lo, hi);
  }

  KuteCrosshairData? _candleCrosshairData(
    Size size,
    List<OHLCInfo> candles,
    int ti,
    KuteIndexWindow window,
    KuteYDomain domain,
    KuteScrubCardData? card,
  ) {
    if (ti < 0 || ti >= candles.length) return null;
    final k = candles[ti];
    final up = k.close >= k.open;
    return KuteCrosshairData(
      x: window.xOf(ti + 0.5, size.width),
      dots: [
        KuteCrosshairDot(
          y: kuteLineY(k.close.toDouble(), size.height, domain),
          color: up ? AppColors.marketUp : AppColors.marketDown,
        ),
      ],
      card: card,
    );
  }

  /// What the wallet received and sent on [day], for the scrub card.
  List<String> _activityLines(
    DateTime day,
    Map<DateTime, double> inAmountByDay,
    Map<DateTime, double> outAmountByDay,
    String btcFormat,
  ) {
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
    final received = inAmountByDay[day];
    final sent = outAmountByDay[day];
    return [
      if (received != null && received > 0)
        '${context.l10n.received}: +${received.toInt().toFormattedString(btcFormat)} $unit',
      if (sent != null && sent > 0)
        '${context.l10n.sent}: −${sent.toInt().toFormattedString(btcFormat)} $unit',
    ];
  }

  /// The scrub card for candle [ti]: its close, the change since the
  /// first candle on screen, its open, high and low, that day's wallet
  /// activity and the date.
  KuteScrubCardData _candleCard(
    List<OHLCInfo> candles,
    int ti,
    KuteIndexWindow window,
    NumberFormat fmt,
    Map<DateTime, double> inAmountByDay,
    Map<DateTime, double> outAmountByDay,
    String btcFormat,
  ) {
    final d = candles[ti];
    final (first, _) = _candleRange(candles.length, window);
    final base = candles[first].close.toDouble();
    final delta = d.close.toDouble() - base;
    final l10n = context.l10n;
    return KuteScrubCardData(
      value: fmt.format(d.close),
      change: ti == first
          ? null
          : kuteChangeText(
              delta: delta,
              base: base,
              magnitude: fmt.format,
            ),
      changeSign: ti == first ? 0 : (delta > 0 ? 1 : (delta < 0 ? -1 : 0)),
      details: [
        '${l10n.ohlcOpen}${fmt.format(d.open)}',
        '${l10n.ohlcHigh}${fmt.format(d.high)}',
        '${l10n.ohlcLow}${fmt.format(d.low)}',
        ..._activityLines(_normalizeDate(d.timestamp), inAmountByDay,
            outAmountByDay, btcFormat),
      ],
      time: kuteChartDay(d.timestamp.toLocal(), kuteChartLocale(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 4.w, bottom: 4.h),
            child: _buildChartModeToggle(c, isLight),
          ),
        ),
        Expanded(
          child: _showCandles
              ? _buildCandlestickView(c, isLight)
              : _buildLineView(c, isLight),
        ),
      ],
    );
  }

  /// One event per real line/candle switch (the taps above are guarded
  /// on the current mode, so re-tapping the active one never fires).
  void _trackChartType(String chartType) =>
      TrackingService.track('analytics_chart_type_changed', params: {
        'chart_type': chartType,
        'tab': 'price',
        'live': false,
      });

  Widget _buildChartModeToggle(AppColorsExtension c, bool isLight) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Line / Candle mode — LIVE moved off this toggle into the bottom
    // period strip (alongside 24H / 1W / 1M / ALL). When the user
    // picks the LIVE period there, the parent swaps the entire chart
    // for a streaming view; this toggle keeps governing line-vs-candle
    // and that selection carries into the live view too (live line
    // chart vs live per-minute candle chart).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChartModeButton(
          icon: Icons.show_chart_rounded,
          isSelected: !_showCandles,
          c: c,
          isLight: isLight,
          onTap: () {
            if (_showCandles) {
              HapticFeedback.selectionClick();
              _trackChartType('line');
              // The freshly mounted KuteLineChart plays its own
              // entrance fade — no controller restart needed here.
              setState(() {
                _showCandles = false;
                _candleTouchIndex = null;
              });
            }
          },
        ),
        SizedBox(width: 4.w),
        _ChartModeButton(
          icon: Icons.candlestick_chart,
          isSelected: _showCandles,
          c: c,
          isLight: isLight,
          onTap: () {
            if (!_showCandles) {
              HapticFeedback.selectionClick();
              _trackChartType('candles');
              setState(() => _showCandles = true);
              if (reduceMotion) {
                _fadeController.value = 1.0;
              } else {
                _fadeController.forward(from: 0);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildCandlestickView(AppColorsExtension c, bool isLight) {
    final ohlcAsync = ref.watch(filteredBitcoinOHLCProvider);
    // Tx markers on the candlestick chart should track the carousel
    // page, not the operational active wallet — otherwise a swipe to
    // a different wallet leaves the prior wallet's markers up for
    // 250 ms while the activeWalletId debounce settles.
    final allTxs = ref.watch(viewedWalletTransactionsProvider
        .select((t) => t.allTransactions));
    final settings = ref.read(settingsProvider);
    final btcFormat = settings.btcFormat;

    return ohlcAsync.when(
      data: (ohlcData) {
        if (ohlcData.isEmpty) {
          return Center(child: Text(context.l10n.noPriceDataForThisRange, style: TextStyle(color: c.textSecondary, fontSize: 16.sp)));
        }

        final ohlcDateSet = <DateTime>{};
        for (final d in ohlcData) {
          ohlcDateSet.add(_normalizeDate(d.timestamp));
        }

        final Map<DateTime, double> inAmountByDay = {};
        final Map<DateTime, double> outAmountByDay = {};
        final isBitcoinChart = widget.selectedAsset.toLowerCase() == 'btc';

        for (var tx in allTxs) {
          bool shouldInclude = false;
          double amountInSats = 0.0;
          bool isReceived = false;

          if (tx is SparkTransaction) {
            final completed = tx.details != null
                ? tx.details!.status == breez.PaymentStatus.completed
                : !tx.isPending;
            if (isBitcoinChart && completed) {
              shouldInclude = true;
              amountInSats = tx.amountSats.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          } else if (tx is BitcoinTransaction) {
            if (isBitcoinChart) {
              shouldInclude = true;
              amountInSats = tx.amount.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          } else {
            if (tx.asset == widget.selectedAsset) {
              shouldInclude = true;
              amountInSats = tx.amount.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          }

          if (shouldInclude && amountInSats > 0) {
            final txDay = _normalizeDate(tx.timestamp);
            if (ohlcDateSet.contains(txDay)) {
              if (isReceived) {
                inAmountByDay.update(txDay, (val) => val + amountInSats, ifAbsent: () => amountInSats);
              } else {
                outAmountByDay.update(txDay, (val) => val + amountInSats, ifAbsent: () => amountInSats);
              }
            }
          }
        }

        final txDays = inAmountByDay.keys.toSet().union(outAmountByDay.keys.toSet());

        // The window on screen (the whole range until a pinch) and its
        // price scale; a range of another length starts unzoomed.
        if (ohlcData.length != _candleCount) {
          _candleCount = ohlcData.length;
          _candleViewport.reset();
        }
        final window =
            _candleViewport.windowFor(ohlcData.length.toDouble());
        final domain = _candleDomain(ohlcData, window);

        final isDark = !isLight;
        final ti = _candleTouchIndex;
        final scrubbing = ti != null && ti >= 0 && ti < ohlcData.length;
        final priceFmt = NumberFormat.simpleCurrency(
            name: settings.currency, decimalDigits: 2);

        // The scrub card is written here, never inside a paint pass.
        final card = scrubbing
            ? _candleCard(ohlcData, ti, window, priceFmt, inAmountByDay,
                outAmountByDay, btcFormat)
            : null;

        return AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) => Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
          child: KuteChartGestures(
            viewport: _candleViewport,
            extent: ohlcData.length.toDouble(),
            onViewChanged: () => setState(() {}),
            onScrub: (dx, w) => _onCandleScrub(dx, w, ohlcData, window),
            onScrubEnd: _endCandleScrub,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PriceCandlePainter(
                        candles: ohlcData,
                        window: window,
                        minY: domain.minY,
                        maxY: domain.maxY,
                        upColor: AppColors.marketUp,
                        downColor: AppColors.marketDown,
                        accentColor: c.accent,
                        txDays: txDays,
                      ),
                    ),
                  ),
                ),
                // Scrub crosshair and card, the shared layer every chart
                // uses.
                Positioned.fill(
                  child: KuteChartCrosshair(
                    resolve: !scrubbing
                        ? null
                        : (size) => _candleCrosshairData(
                            size, ohlcData, ti, window, domain, card),
                    repaintKey: (ti, ohlcData.length, window, isDark),
                    isDark: isDark,
                    hairlineColor: c.border,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SkeletonChart(),
      error: (e, s) => Center(child: Text(context.l10n.errorLoadingPriceData, style: TextStyle(color: c.textSecondary))),
    );
  }

  Widget _buildLineView(AppColorsExtension c, bool isLight) {
    final marketDataAsync = ref.watch(filteredBitcoinMarketDataProvider);
    // Same viewed-wallet treatment as the candlestick view above.
    final allTxs = ref.watch(viewedWalletTransactionsProvider
        .select((t) => t.allTransactions));

    return marketDataAsync.when(
      data: (marketData) {
        if (marketData.isEmpty) {
          return Center(child: Text(context.l10n.noPriceDataForThisRange, style: TextStyle(color: c.textSecondary, fontSize: 16.sp)));
        }

        final priceByDay = {
          for (var dp in marketData) _normalizeDate(dp.date): dp.price ?? 0
        };

        final sortedDays = priceByDay.keys.toList()..sort((a, b) => a.compareTo(b));

        final Map<DateTime, double> inAmountByDay = {};
        final Map<DateTime, double> outAmountByDay = {};
        final Map<DateTime, double> netAmountByDay = {};
        final isBitcoinChart = widget.selectedAsset.toLowerCase() == 'btc';

        for (var tx in allTxs) {
          bool shouldInclude = false;
          double amountInSats = 0.0;
          bool isReceived = false;

          if (tx is SparkTransaction) {
            final completed = tx.details != null
                ? tx.details!.status == breez.PaymentStatus.completed
                : !tx.isPending;
            if (isBitcoinChart && completed) {
              shouldInclude = true;
              amountInSats = tx.amountSats.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          } else if (tx is BitcoinTransaction) {
            if (isBitcoinChart) {
              shouldInclude = true;
              amountInSats = tx.amount.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          } else {
            if (tx.asset == widget.selectedAsset) {
              shouldInclude = true;
              amountInSats = tx.amount.toDouble();
              isReceived = tx.type == TransactionType.received;
            }
          }

          if (shouldInclude && amountInSats > 0) {
            final txDay = _normalizeDate(tx.timestamp);
            if (priceByDay.containsKey(txDay)) {
              if (isReceived) {
                inAmountByDay.update(txDay, (val) => val + amountInSats, ifAbsent: () => amountInSats);
                netAmountByDay.update(txDay, (val) => val + amountInSats, ifAbsent: () => amountInSats);
              } else {
                outAmountByDay.update(txDay, (val) => val + amountInSats, ifAbsent: () => amountInSats);
                netAmountByDay.update(txDay, (val) => val - amountInSats, ifAbsent: () => -amountInSats);
              }
            }
          }
        }

        // Transaction dot markers on the price line — a marker per day
        // with activity, colored by the day's NET flow (received minus
        // sent). Preserved from the old second fl_chart series; the
        // engine draws them as small halo'd dots (HL fill-marker style).
        final markers = <KuteLineMarker>[];
        for (int i = 0; i < sortedDays.length; i++) {
          final day = sortedDays[i];
          if (!inAmountByDay.containsKey(day) &&
              !outAmountByDay.containsKey(day)) {
            continue;
          }
          final net = netAmountByDay[day] ?? 0;
          markers.add(KuteLineMarker(
              i, net >= 0 ? AppColors.marketUp : AppColors.marketDown));
        }

        final values = <double>[
          for (final day in sortedDays)
            max(0, (priceByDay[day] ?? 0).toDouble()).toDouble(),
        ];

        // Direction pair: up weeks in marketUp, down weeks in marketDown
        // (matching the trading charts); flat falls back to the accent.
        final Color lineColor;
        if (values.length >= 2 && values.last > values.first) {
          lineColor = AppColors.marketUp;
        } else if (values.length >= 2 && values.last < values.first) {
          lineColor = AppColors.marketDown;
        } else {
          lineColor = c.accent;
        }

        final currency = ref.read(settingsProvider).currency;
        final priceFmt =
            NumberFormat.simpleCurrency(name: currency, decimalDigits: 2);

        // Engine chart: monotone cubic (no rubber-band overshoot),
        // standard 0.14 gradient fill, endpoint dot, ~280ms morph on
        // range switches, the venue charts' zoom and pan, and the scrub
        // card (price, change since the first day on screen, that day's
        // wallet activity, the date).
        final locale = kuteChartLocale(context);
        final btcFormat = ref.read(settingsProvider).btcFormat;
        return Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: KuteLineChart(
            values: values,
            lineColor: lineColor,
            markers: markers,
            viewResetKey: widget.viewResetKey,
            onScrubStart: () => TrackingService.analyticsChartScrubbed(
                chart: 'price', view: 'line'),
            valueTextBuilder: (index) =>
                index >= 0 && index < values.length
                    ? priceFmt.format(values[index])
                    : null,
            changeFormatter: priceFmt.format,
            detailTextBuilder: (index) => index >= 0 &&
                    index < sortedDays.length
                ? _activityLines(sortedDays[index], inAmountByDay,
                    outAmountByDay, btcFormat)
                : const [],
            timeTextBuilder: (index) =>
                index >= 0 && index < sortedDays.length
                    ? kuteChartDay(sortedDays[index], locale)
                    : null,
          ),
        );
      },
      loading: () => const SkeletonLineChart(),
      error: (e, s) => Center(child: Text(context.l10n.errorLoadingPriceData, style: TextStyle(color: c.textSecondary))),
    );
  }

}

class _ChartModeButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final AppColorsExtension c;
  final bool isLight;
  final VoidCallback onTap;

  const _ChartModeButton({
    required this.icon,
    required this.isSelected,
    required this.c,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        padding: EdgeInsets.all(5.w),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.white : c.surfaceElevated)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: isSelected
              ? (isLight ? Border.all(color: c.border) : null)
              : Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Icon(
          icon,
          size: 14.sp,
          color: isSelected ? c.textPrimary : c.textTertiary,
        ),
      ),
    );
  }
}

/// Live mode button — blinking red dot + "LIVE" label. Sits alongside
/// the line / candle buttons on the analytics chart toggle row.
class _LiveModeButton extends StatefulWidget {
  final bool isSelected;
  final AppColorsExtension c;
  final bool isLight;
  final VoidCallback onTap;

  const _LiveModeButton({
    required this.isSelected,
    required this.c,
    required this.isLight,
    required this.onTap,
  });

  @override
  State<_LiveModeButton> createState() => _LiveModeButtonState();
}

class _LiveModeButtonState extends State<_LiveModeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The blinking red dot is decorative; the "LIVE" label already
    // conveys the state. Don't loop the pulse under reduce-motion —
    // pin it to a steady, fully-visible value instead.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_blink.isAnimating) _blink.stop();
      _blink.value = 1.0;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.w),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? (widget.isLight ? Colors.white : widget.c.surfaceElevated)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: widget.isSelected
              ? (widget.isLight
                  ? Border.all(color: widget.c.border)
                  : null)
              : Border.all(color: widget.c.borderSubtle, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _blink,
              builder: (_, __) => Container(
                width: 7.sp,
                height: 7.sp,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30)
                      .withValues(alpha: 0.4 + 0.6 * _blink.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3B30)
                          .withValues(alpha: 0.5 * _blink.value),
                      blurRadius: 4 + 4 * _blink.value,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 5.w),
            Text(
              'LIVE',
              style: TextStyle(
                color: widget.isSelected
                    ? widget.c.textPrimary
                    : widget.c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-second BTC/USD price stream from Binance — `wss://stream.binance.com:9443/ws/btcusdt@trade`
/// drips a fresh trade message every few hundred ms. We buffer the
/// last ~120 ticks (~2 minutes of activity) and repaint a sparkline
/// + hero current-price label every time a new tick arrives. No
/// historical bootstrap — the chart fills up as the stream runs.
class _LiveBinanceView extends StatefulWidget {
  const _LiveBinanceView();

  @override
  State<_LiveBinanceView> createState() => _LiveBinanceViewState();
}

class _LiveBinanceViewState extends State<_LiveBinanceView> {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final List<double> _prices = [];
  static const int _maxPoints = 120;
  double? _lastPrice;
  double? _openPrice;
  DateTime _connectedAt = DateTime.now();
  Timer? _reconnect;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://stream.binance.com:9443/ws/btcusdt@trade'),
      );
      // web_socket_channel 3.x rejects `.ready` on a failed connect;
      // with no listener that rejection escapes the zone as a recorded
      // FATAL (one per reconnect attempt when offline). The stream
      // onError below owns recovery; `.ready` just needs a listener.
      _channel!.ready.ignore();
      _connectedAt = DateTime.now();
      _sub = _channel!.stream.listen(
        (raw) {
          try {
            final map = jsonDecode(raw as String);
            if (map is! Map<String, dynamic>) return;
            final priceStr = map['p'] as String?;
            if (priceStr == null) return;
            final price = double.tryParse(priceStr);
            if (price == null || price <= 0) return;
            _push(price);
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), () {
      if (mounted) _connect();
    });
  }

  void _push(double price) {
    if (!mounted) return;
    setState(() {
      _openPrice ??= price;
      _prices.add(price);
      if (_prices.length > _maxPoints) {
        _prices.removeRange(0, _prices.length - _maxPoints);
      }
      _lastPrice = price;
    });
  }

  @override
  void dispose() {
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  String _formatPrice(double v) {
    return NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2)
        .format(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hasData = _prices.length >= 2;
    final delta = (_lastPrice != null && _openPrice != null)
        ? (_lastPrice! - _openPrice!)
        : 0.0;
    final deltaPct = (_openPrice != null && _openPrice! > 0)
        ? (delta / _openPrice!) * 100
        : 0.0;
    final isUp = delta >= 0;
    final accent = isUp ? AppColors.marketUp : AppColors.marketDown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _lastPrice != null ? _formatPrice(_lastPrice!) : '—',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(width: 10.w),
              if (hasData)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '${isUp ? '+' : ''}${deltaPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: accent,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                context.l10n
                    .liveSince(DateFormat('HH:mm:ss').format(_connectedAt)),
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        Expanded(
          child: hasData
              ? CustomPaint(
                  size: Size.infinite,
                  painter: _LiveSparkPainter(
                    prices: _prices,
                    accent: accent,
                    isDark: !isLight,
                  ),
                )
              : Center(
                  child: KuteSkeleton(
                    child: SkeletonBar(double.infinity, 3.h, radius: 2.r),
                  ),
                ),
        ),
      ],
    );
  }
}

/// LIVE Binance sparkline — rendered through the shared chart engine
/// (monotone cubic path, standard 0.14 fill, 2.0 stroke, endpoint dot)
/// so the streaming view matches every other line chart in the app.
class _LiveSparkPainter extends CustomPainter {
  final List<double> prices;
  final Color accent;
  final bool isDark;

  _LiveSparkPainter({
    required this.prices,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    kutePaintLineSpark(
      canvas,
      values: prices,
      width: size.width,
      height: size.height,
      color: accent,
      isDark: isDark,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveSparkPainter old) =>
      !kuteSameSeries(old.prices, prices) ||
      old.accent != accent ||
      old.isDark != isDark;
}

/// Bespoke Price-tab candlestick painter — replaced the fl_chart
/// CandlestickChart. Same body grammar as the Hyperliquid candle
/// painter: rounded RRect bodies at 62% of the slot width (clamped),
/// round-cap wicks, up/down via AppColors.marketUp/marketDown. Days
/// with wallet activity keep their accent-colored highlight (accent
/// wick + accent body stroke), preserved from the fl_chart style
/// provider. Grid-free per the app's unified chart language; the scrub
/// crosshair lives in the shared KuteChartCrosshair layer, so this
/// canvas never repaints during a scrub.
class _PriceCandlePainter extends CustomPainter {
  final List<OHLCInfo> candles;
  final KuteIndexWindow window;
  final double minY;
  final double maxY;
  final Color upColor;
  final Color downColor;
  final Color accentColor;
  final Set<DateTime> txDays;

  _PriceCandlePainter({
    required this.candles,
    required this.window,
    required this.minY,
    required this.maxY,
    required this.upColor,
    required this.downColor,
    required this.accentColor,
    required this.txDays,
  });

  DateTime _normalizeDate(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = candles.length;
    if (n == 0) return;
    final range = maxY - minY;
    if (range <= 0) return;

    final h = size.height;
    final w = size.width;
    final span = window.span > 0 ? window.span : n.toDouble();
    final slot = w / span;
    final bodyW = (slot * 0.62).clamp(1.0, 22.0);
    double toY(double v) => h * (1 - (v - minY) / range);

    final wickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, bodyW * 0.14)
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    for (var i = 0; i < n; i++) {
      final cx = window.xOf(i + 0.5, w);
      // Only the candles on screen (a zoomed window).
      if (cx < -slot || cx > w + slot) continue;
      final k = candles[i];
      final up = k.close >= k.open;
      final col = up ? upColor : downColor;
      final hasTx = txDays.isNotEmpty &&
          txDays.contains(_normalizeDate(k.timestamp));

      // Wick (high → low) — accent on days with wallet activity.
      canvas.drawLine(
        Offset(cx, toY(k.high)),
        Offset(cx, toY(k.low)),
        wickPaint..color = (hasTx ? accentColor : col).withValues(alpha: 0.9),
      );

      // Body (open → close). Floor to 2px so zero-range days read as
      // candles, not stray dashes.
      final openY = toY(k.open);
      final closeY = toY(k.close);
      final top = min(openY, closeY);
      final bottom = max(openY, closeY);
      final bodyH = max(bottom - top, 2.0);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Radius.circular(min(2.0, bodyW / 3)),
      );
      canvas.drawRRect(rrect, Paint()..color = col);
      if (hasTx) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = accentColor,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PriceCandlePainter old) =>
      old.candles != candles ||
      old.window != window ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.upColor != upColor ||
      old.downColor != downColor ||
      old.accentColor != accentColor ||
      old.txDays != txDays;
}
