// lib/screens/polymarket/components/crypto_round_card.dart
//
// The compact live crypto round card and its parts, the Predictions
// list's card ([CryptoPredictBanner.compact], polymarket_screen.dart,
// under Crypto › 5 Min and pinned under Crypto › All): the card itself
// ([CompactCryptoCard]: logo, title, the past rounds as dots, the
// countdown pill; the live price, its move and the target; the sparkline
// against the dashed target; the line naming the round the buttons bet
// on; the one pair of Up and Down pills with their odds), the pills
// ([CompactSidePill]), the dots ([PastRoundDots]), the line over the
// buttons ([CryptoNextWindowLine]) and the on-screen counter the shared
// Chainlink feed streams for ([CryptoCardOnScreen]). Moved here from
// polymarket_screen.dart on 8 November 2026 unchanged. The round on show
// is the one in play; the buttons bet it until its cutoff, then roll to the
// NEXT round by themselves (founder, 12 November 2026;
// crypto_next_round.dart), so the strip of rounds that once picked one is
// gone. The other slots a taller card once
// used (its own plot height, a card with no odds) stay for the next card
// that needs them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/screens/home/components/btc_predict_chart.dart';
import 'package:kute/screens/polymarket/components/crypto_asset_logo.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:intl/intl.dart';

/// A round card's price: whole dollars from $1,000, cents above $1, four
/// decimals below; a dash for none.
String formatCryptoRoundPrice(double? price) {
  if (price == null) return '—';
  if (price >= 1000) {
    return '\$${NumberFormat('#,##0', 'en_US').format(price.round())}';
  } else if (price >= 1) {
    return '\$${NumberFormat('#,##0.00', 'en_US').format(price)}';
  } else {
    return '\$${price.toStringAsFixed(4)}';
  }
}

/// A price difference in dollars: cents above $1 (polymarket.com prints
/// "$309.98"), four decimals below.
String formatCryptoRoundDiff(double diff) {
  if (diff >= 1) {
    return '\$${NumberFormat('#,##0.00', 'en_US').format(diff)}';
  }
  return '\$${diff.toStringAsFixed(4)}';
}

/// A round's time as its card and rows write it: "02:16" for the rounds
/// shorter than an hour, "0:37:55" for the hourly and four-hour ones (never
/// "239:59").
String cryptoRoundClockText(int seconds, int minutes) {
  final s = seconds < 0 ? 0 : seconds;
  String two(int n) => n.toString().padLeft(2, '0');
  if (minutes < 60) return '${two(s ~/ 60)}:${two(s % 60)}';
  return '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}

/// Registers its subtree in [cryptoCardsOnScreenProvider] while
/// tickers are enabled there. A hidden shell branch turns tickers off
/// (`Offstage` + `TickerMode`), so a banner counts only while it can be
/// seen; the count is changed after the frame, never during build.
class CryptoCardOnScreen extends ConsumerStatefulWidget {
  const CryptoCardOnScreen({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CryptoCardOnScreen> createState() =>
      CryptoCardOnScreenState();
}

class CryptoCardOnScreenState extends ConsumerState<CryptoCardOnScreen> {
  // Read at once: a lazy list can build and drop a card within one frame
  // (a fling past it), before the microtask below first runs.
  late final StateController<int> _cards;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _cards = ref.read(cryptoCardsOnScreenProvider.notifier);
  }

  void _count(bool on) {
    if (on == _counted) return;
    _counted = on;
    // The whole scope may be gone by then (the app torn down).
    Future.microtask(() {
      if (_cards.mounted) _cards.state += on ? 1 : -1;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _count(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _count(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The line over the buttons of a live round card, naming the round they
/// bet on ("Now · Ends in 02:16", then "Next · Starts in 01:12", and "· No
/// prices yet" while it has none): one line in the card's own target style, nothing around it,
/// scaled down whole rather than cut.
class CryptoNextWindowLine extends StatelessWidget {
  const CryptoNextWindowLine({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('crypto-round-next'),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
}

/// The compact crypto round card ([CryptoPredictBanner.compact]): about
/// 200 px for the same data and actions as the full card, the live
/// sparkline against the target included, and Up / Down as solid buttons
/// in the market page's Yes / No colours (founder, 2 November 2026).
class CompactCryptoCard extends StatelessWidget {
  const CompactCryptoCard({
    super.key,
    required this.config,
    required this.title,
    required this.countdown,
    required this.pastResults,
    required this.loading,
    required this.priceText,
    required this.diffText,
    required this.diffUp,
    required this.targetText,
    required this.history,
    required this.priceToBeat,
    required this.roundStart,
    required this.upFrac,
    this.nextLabel,
    this.window,
    this.buttonsEnabled = true,
    required this.onUp,
    required this.onDown,
    this.sparkHeight = CompactCryptoCard.kSparkHeight,
    this.chartWindow = kBtcPredictChartWindow,
  });

  final CryptoAssetConfig config;
  final String title;

  /// The time left as the card writes it; null when it is not known (a
  /// card without Gamma's event): the countdown pill then shows a
  /// skeleton bar, never "0:00:00".
  final String? countdown;
  final List<CryptoWindowResult> pastResults;
  final bool loading;
  final String priceText;
  final String? diffText;
  final bool diffUp;
  final String targetText;
  final List<BtcPriceSnapshot>? history;
  final double? priceToBeat;
  final DateTime? roundStart;

  /// Up's chance on the buttons; null when there are no odds to show (a
  /// card with no round to bet on): the pills then read "Up" and "Down"
  /// alone, never 50% and 50%.
  final double? upFrac;

  /// The line over the buttons: the round they bet on, the one in play
  /// ("Now · Ends in 02:16") until its cutoff, then the next one ("Next ·
  /// Starts in 01:12"; crypto_next_round.dart), with "No prices yet"
  /// while it has none. Null for no line.
  final String? nextLabel;

  /// The name of the round the buttons bet on ("BTC up or down ·
  /// 7:20–7:25"), read out with each pill; null when it is not known.
  final String? window;

  /// Whether the buttons can bet: false while the round they stand on has
  /// no price (dimmed, inert, no odds).
  final bool buttonsEnabled;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// The plot's height; the compact card's 54, a taller card more.
  final double sparkHeight;

  /// The most of the series the plot shows ([BtcPredictChart.maxWindow]).
  final Duration chartWindow;

  /// The sparkline's plot height on the list's card; the chart's own
  /// bottom margin (18 px, time labels off) is clipped away beneath it.
  static const double kSparkHeight = 54;

  /// The "Next · 7:20" line's height. It takes its room from the sparkline,
  /// so the buttons rolling never changes the card's height (the list
  /// under it would jump twice a window).
  static const double _nextLine = 16;

  /// The header's logo.
  static const double _logo = 32;

  /// The Up / Down pills' height.
  static const double pillHeight = 44;

  /// The price row's height: the live price as [RollingNumberText] draws
  /// it (every digit a cell of the font's full ascent and descent, its
  /// line height ignored), measured in the face and at the text size it
  /// paints in, so the figures fill the line exactly and are never scaled
  /// to fit it.
  static double _priceLine(BuildContext context, TextStyle style) =>
      (TextPainter(
        text: TextSpan(
            text: '0', style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      )..layout())
          .height;

  /// The width [text] takes on one line in [style], at the person's text
  /// size, every digit counted as wide as the widest (the row's shape then
  /// holds from tick to tick); [perChar] as [RollingNumberText] lays a
  /// figure out, one cell per character.
  static double textWidth(BuildContext context, String text, TextStyle style,
      {bool perChar = false}) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final steady = text.replaceAll(RegExp(r'\d'), '0');
    double measure(String part) {
      final painter = TextPainter(
        text: TextSpan(text: part, style: merged),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    if (!perChar) return measure(steady);
    var width = 0.0;
    for (final ch in steady.characters) {
      width += measure(ch);
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = CryptoAssetLogo(config: config, size: _logo.sp);
    // No odds (the Instant card with no round to bet on): "Up" and "Down"
    // alone, never 50% and 50%.
    final pair = upFrac == null ? null : formatPolyChancePair(upFrac!);
    final seeded = (history?.length ?? 0) >= 2;
    // The line over the buttons: the round they bet on.
    final lineLabel = nextLabel;
    final rolled = lineLabel != null;
    // 10 over the buttons either way; rolled, 6 and the line and 6.
    final sparkHeight = rolled
        ? this.sparkHeight + 10.h - 12.h - _nextLine
        : this.sparkHeight;
    final priceStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 24.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.7,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      key: const ValueKey('crypto-round-compact'),
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo, title, past rounds as dots, the countdown pill. The dots
          // stand only where the title still fits one line beside them (a
          // narrow phone, large text: the dots go first, calmly).
          LayoutBuilder(builder: (context, box) {
            final titleStyle = TextStyle(
              color: c.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.2,
            );
            final pillStyle = TextStyle(
              color: c.textPrimary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            final dotsFit = pastResults.isNotEmpty &&
                _logo.sp +
                        10.w +
                        textWidth(context, title, titleStyle) +
                        8.w +
                        PastRoundDots.widthOf(pastResults.length) +
                        8.w +
                        16.w +
                        11.w +
                        textWidth(context, countdown ?? '00:00', pillStyle) +
                        1 <=
                    box.maxWidth;
            return Row(
            children: [
              SizedBox(width: _logo.sp, height: _logo.sp, child: logo),
              SizedBox(width: 10.w),
              // The title is never cut: on a narrow phone at a large text
              // size it takes a second line beside the countdown.
              Expanded(
                child: Text(title, style: titleStyle),
              ),
              SizedBox(width: 8.w),
              if (dotsFit) ...[
                PastRoundDots(results: pastResults),
                SizedBox(width: 8.w),
              ],
              Container(
                key: const ValueKey('crypto-round-countdown'),
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6.w,
                      height: 6.w,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 5.w),
                    // The time left, or a skeleton bar while it is not
                    // known (no event): never a made-up "0:00:00".
                    if (countdown case final countdown?)
                      Text(countdown, style: pillStyle)
                    else
                      KuteSkeleton(
                        key: const ValueKey('crypto-round-countdown-skeleton'),
                        child: SkeletonBar(34.w, 12.sp, radius: 4.r),
                      ),
                  ],
                ),
              ),
            ],
          );
          }),
          SizedBox(height: 10.h),
          // The live price, its move against the target, the target at
          // the right. One fixed line, skeleton or figures: a price scaled
          // down to fit beside a wider move, or the skeleton giving way to
          // the digits, never changes the card's height (the list under it
          // would move with every tick). Where the three do not fit one
          // line (a narrow phone, large text) the target goes under the
          // price, whole, never cut (founder, 12 November 2026); the widths
          // are measured with every digit as wide as the widest, so a tick
          // never flips the row between its two shapes.
          LayoutBuilder(builder: (context, box) {
            final line = _priceLine(context, priceStyle);
            if (loading) {
              return SizedBox(
                height: line,
                child: KuteSkeleton(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBar(150.w, 24.h, radius: 6.r),
                  ),
                ),
              );
            }
            final diffStyle = TextStyle(
              color: diffUp ? AppColors.marketUp : AppColors.marketDown,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            final targetStyle = TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            final oneLine =
                textWidth(context, priceText, priceStyle, perChar: true) +
                    (diffText == null
                        ? 0
                            : 6.w + textWidth(context, diffText!, diffStyle)) +
                    8.w +
                        textWidth(context, targetText, targetStyle) +
                    1 <=
                box.maxWidth;
            final figures = <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RollingNumberText(text: priceText, style: priceStyle),
                ),
              ),
              if (diffText != null) ...[
                SizedBox(width: 6.w),
                Text(diffText!, maxLines: 1, style: diffStyle),
              ],
            ];
            final target = Text(
              targetText,
              key: const ValueKey('crypto-round-target'),
              style: targetStyle,
            );
            if (oneLine) {
              return SizedBox(
                height: line,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    ...figures,
                    SizedBox(width: 8.w),
                    const Spacer(),
                    target,
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: line,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: figures,
                  ),
                ),
                SizedBox(height: 4.h),
                target,
              ],
            );
          }),
          SizedBox(height: 8.h),
          // The sparkline with the dashed target line, no in-chart
          // "Target" badge: the target is printed just above.
          SizedBox(
            height: sparkHeight,
            child: !seeded
                ? SkeletonLineChart(
                    height: sparkHeight, padding: EdgeInsets.zero)
                : ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: sparkHeight + 18,
                      child: BtcPredictChart(
                        height: sparkHeight + 18,
                        externalHistory: history,
                        externalPriceToBeat: priceToBeat,
                        roundStart: roundStart,
                        maxWindow: chartWindow,
                        showLiveIndicator: false,
                        showHeader: false,
                        showTargetBadge: false,
                      ),
                    ),
                  ),
          ),
          if (rolled) ...[
            SizedBox(height: 6.h),
            SizedBox(
                height: _nextLine,
                child: CryptoNextWindowLine(label: lineLabel)),
            SizedBox(height: 6.h),
          ] else
            SizedBox(height: 10.h),
          // Up and Down with their odds, one row of two pills.
          Row(
            children: [
              Expanded(
                child: CompactSidePill(
                  key: const ValueKey('crypto-round-up'),
                  label: context.l10n.upLabel,
                  odds: buttonsEnabled ? pair?.first ?? '' : '',
                  window: window,
                  up: true,
                  enabled: buttonsEnabled,
                  onTap: onUp,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: CompactSidePill(
                  key: const ValueKey('crypto-round-down'),
                  label: context.l10n.downLabel,
                  odds: buttonsEnabled ? pair?.second ?? '' : '',
                  window: window,
                  up: false,
                  enabled: buttonsEnabled,
                  onTap: onDown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One side of the compact card: a 44 px button
/// ([CompactCryptoCard.pillHeight]) with squared 14 px corners
/// ([radius]), the side then its chance on one line, in the market page's
/// solid Yes / No fill: the market colour with its faint top highlight,
/// the label in the colour that reads on it (white) and, in light mode,
/// the same quiet glow ([marketPairDecoration]; founder, 2 November 2026:
/// "put them back at the darker colours").
class CompactSidePill extends StatelessWidget {
  const CompactSidePill({
    super.key,
    required this.label,
    required this.odds,
    this.window,
    required this.up,
    this.enabled = true,
    required this.onTap,
  });

  final String label;
  final String odds;

  /// The name of the round the pill bets on: read out with it.
  final String? window;
  final bool up;

  /// False: dimmed and inert, the [MarketPairButton] disabled grammar
  /// (0.35), while the round it would bet on has no real prices.
  final bool enabled;
  final VoidCallback onTap;

  /// The corner radius: a rounded rectangle, the market page's outcome
  /// tiles' squared shape, not a full pill (founder, 2 November 2026:
  /// "the more squared ones").
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    final color = up ? AppColors.marketUp : AppColors.marketDown;
    final style = TextStyle(
      color: contrastingOnColor(color),
      fontSize: 15.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${window == null ? '' : '$window, '}$label $odds'.trim(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
          height: CompactCryptoCard.pillHeight,
          decoration: marketPairDecoration(color,
              borderRadius: BorderRadius.circular(radius.r),
              glow: !context.isDark && enabled),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: style),
                if (odds.isNotEmpty) ...[
                  SizedBox(width: 6.w),
                  RollingNumberText(text: odds, style: style),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// The last few windows as tiny dots, oldest first: up and down in the
/// market colours, a hairline ring while one is still settling.
class PastRoundDots extends StatelessWidget {
  const PastRoundDots({super.key, required this.results});

  final List<CryptoWindowResult> results;

  /// The row's width for [count] dots, as it lays them out.
  static double widthOf(int count) =>
      count <= 0 ? 0 : count * 7.sp + (count - 1) * 3.w;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = 7.sp;
    return Semantics(
      label: context.l10n.predictPastRounds,
      child: Row(
        key: const ValueKey('crypto-round-past-dots'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < results.length; i++) ...[
            if (i > 0) SizedBox(width: 3.w),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: results[i].up == null
                    ? null
                    : results[i].up!
                        ? AppColors.marketUp
                        : AppColors.marketDown,
                shape: BoxShape.circle,
                border: results[i].up == null
                    ? Border.all(color: c.borderSubtle, width: 1)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One quick amount under the round card's buttons: what it says ("$5 ·
/// win $12") and what a tap does (opens the slip with that amount; null
/// while the buttons take no bet).
typedef CryptoQuickAmount = ({
  double amount,
  String label,
  VoidCallback? onTap
});

/// The live crypto round card, full size ([CryptoPredictBanner] without
/// `compact`: Predictions › Crypto › 5 Min, 15 Min, 1 Hour and 4 Hours, the
/// round's own sheet, Ledger Predictions), polymarket.com's own round page
/// made for a phone (founder, 12 November 2026: "look at how it is on the
/// polymarket website, make it better please"):
///
///   * the coin, "BTC up or down · 5m" and the window on show ("7:15–7:20");
///   * the figures: "Price to beat" and its figure, "Current price" with its
///     move against the target ("▼ $22.00", in the market colours) and its
///     figure, the time left large in the live red at the right; on two
///     rows where one does not hold them whole;
///   * the chart of the round on show against the dashed target;
///   * the round row ([strip]: the past results as dots, the round in play,
///     the next and the one after);
///   * the line naming the round the buttons bet on ([line]);
///   * Up and Down, full width, at that round's odds;
///   * the quick amounts ([quick]) for the side last tapped: a tap opens the
///     slip with that amount filled in, nothing more (money moves only after
///     Confirm, in the slip).
///
/// Nothing on it is cut: a text too long for its room wraps.
class CryptoRoundHeroCard extends StatelessWidget {
  const CryptoRoundHeroCard({
    super.key,
    required this.config,
    required this.title,
    required this.window,
    required this.loading,
    required this.beatText,
    required this.currentText,
    required this.diffText,
    required this.diffUp,
    required this.countdown,
    required this.feedName,
    required this.history,
    required this.priceToBeat,
    required this.roundStart,
    required this.chartHeight,
    required this.chartWindow,
    required this.strip,
    required this.line,
    required this.upFrac,
    required this.roundName,
    required this.buttonsEnabled,
    required this.onUp,
    required this.onDown,
    required this.quick,
    required this.quickUp,
  });

  final CryptoAssetConfig config;
  final String title;

  /// The window on show, "7:15–7:20"; null while it is not known.
  final String? window;
  final bool loading;
  final String beatText;
  final String currentText;
  final String? diffText;
  final bool diffUp;

  /// The round on show's time left; null while it is not known.
  final String? countdown;
  final String? feedName;
  final List<BtcPriceSnapshot>? history;
  final double? priceToBeat;
  final DateTime? roundStart;
  final double chartHeight;
  final Duration chartWindow;

  /// The round row; null for a card of one given window.
  final Widget? strip;

  /// The line over the buttons, naming the round they bet on.
  final String line;
  final double? upFrac;
  final String roundName;
  final bool buttonsEnabled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final List<CryptoQuickAmount> quick;

  /// The side the quick amounts are for: Up when true.
  final bool quickUp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pair = upFrac == null ? null : formatPolyChancePair(upFrac!);
    final seeded = (history?.length ?? 0) >= 2;
    return Container(
      key: const ValueKey('crypto-round-full'),
      // The rows' 14 inset, so the coins' logos stand in one column.
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The coin, the title, the window on show.
          Row(
            children: [
              CryptoAssetLogo(config: config, size: 36.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                    if (window case final w?) ...[
                      SizedBox(height: 2.h),
                      Text(
                        w,
                        key: const ValueKey('crypto-round-window'),
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _figures(context),
          SizedBox(height: 10.h),
          // The chart of the round on show, the dashed target with its tag.
          // The chart's own bottom margin (18 px, time labels off) is
          // clipped away beneath the plot, as on the list's card.
          SizedBox(
            height: chartHeight,
            child: !seeded
                ? SkeletonLineChart(
                    height: chartHeight, padding: EdgeInsets.zero)
                : ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: chartHeight + 18,
                      child: BtcPredictChart(
                        height: chartHeight + 18,
                        externalHistory: history,
                        externalPriceToBeat: priceToBeat,
                        roundStart: roundStart,
                        maxWindow: chartWindow,
                        showLiveIndicator: false,
                        showHeader: false,
                      ),
                    ),
                  ),
          ),
          if (strip case final s?) ...[
            SizedBox(height: 8.h),
            s,
          ],
          SizedBox(height: 8.h),
          CryptoNextWindowLine(label: line),
          SizedBox(height: 8.h),
          // Up and Down, full width, "Up 50.5%" on one line, the round
          // they bet on read out with each.
          Row(
            children: [
              Expanded(
                child: CompactSidePill(
                  key: const ValueKey('crypto-round-up'),
                  label: context.l10n.upLabel,
                  odds: buttonsEnabled ? pair?.first ?? '' : '',
                  window: roundName,
                  up: true,
                  enabled: buttonsEnabled,
                  onTap: onUp,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: CompactSidePill(
                  key: const ValueKey('crypto-round-down'),
                  label: context.l10n.downLabel,
                  odds: buttonsEnabled ? pair?.second ?? '' : '',
                  window: roundName,
                  up: false,
                  enabled: buttonsEnabled,
                  onTap: onDown,
                ),
              ),
            ],
          ),
          if (quick.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _quickRow(context),
          ],
        ],
      ),
    );
  }

  /// Price to beat, the current price and its move, the time left: one
  /// row where all three fit whole, else the two prices on one row and the
  /// time left under them, else each on its own.
  Widget _figures(BuildContext context) {
    final c = context.colors;
    final labelStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
    );
    final figureStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 22.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final moveColor = diffUp ? AppColors.marketUp : AppColors.marketDown;
    final diffStyle = TextStyle(
      color: moveColor,
      fontSize: 12.sp,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final clockStyle = figureStyle.copyWith(color: const Color(0xFFFF4444));
    return LayoutBuilder(builder: (context, box) {
      double w(String text, TextStyle style, {bool perChar = false}) =>
          CompactCryptoCard.textWidth(context, text, style, perChar: perChar);
      final beatLabel = context.l10n.btcPredictPriceToBeat;
      final currentLabel = context.l10n.investingCurrentPrice;
      final gap = 16.w;
      final beatW = [
        w(beatLabel, labelStyle),
        w(beatText, figureStyle, perChar: true),
      ].reduce((a, b) => a > b ? a : b);
      final currentW = [
        w(currentLabel, labelStyle) +
            (diffText == null ? 0 : 6.w + w(diffText!, diffStyle)),
        w(currentText, figureStyle, perChar: true) +
            (feedName == null ? 0 : 6.w + w(feedName!, labelStyle)),
      ].reduce((a, b) => a > b ? a : b);
      final clockW = countdown == null ? 0.0 : w(countdown!, clockStyle);

      Widget block(String label, Widget labelSide, Widget figure, {Key? key}) =>
          Column(
            key: key,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6.w,
                children: [Text(label, style: labelStyle), labelSide],
              ),
              SizedBox(height: 4.h),
              figure,
            ],
          );
      Widget figureText(String text, TextStyle style) => loading
          ? KuteSkeleton(child: SkeletonBar(84.w, 20.h, radius: 6.r))
          : RollingNumberText(text: text, style: style);
      final beat = block(
        beatLabel,
        const SizedBox.shrink(),
        figureText(beatText, figureStyle.copyWith(color: c.textSecondary)),
        key: const ValueKey('crypto-round-target'),
      );
      final current = block(
        currentLabel,
        diffText == null
            ? const SizedBox.shrink()
            : Text(diffText!,
                key: const ValueKey('crypto-round-move'), style: diffStyle),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6.w,
          children: [
            figureText(currentText, figureStyle),
            if (feedName case final f?) Text(f, style: labelStyle),
          ],
        ),
        key: const ValueKey('crypto-round-current'),
      );
      final clock = countdown == null
          ? KuteSkeleton(
              key: const ValueKey('crypto-round-countdown-skeleton'),
              child: SkeletonBar(56.w, 20.h, radius: 6.r))
          : Text(countdown!,
              key: const ValueKey('crypto-round-countdown'), style: clockStyle);
      final max = box.maxWidth;
      if (beatW + gap + currentW + gap + clockW + 1 <= max) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            beat,
            SizedBox(width: gap),
            current,
            const Spacer(),
            clock,
          ],
        );
      }
      return Column(
        key: const ValueKey('crypto-round-figures-wrapped'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (beatW + gap + currentW + 1 <= max)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [beat, SizedBox(width: gap), current],
            )
          else ...[
            beat,
            SizedBox(height: 8.h),
            current,
          ],
          SizedBox(height: 8.h),
          clock,
        ],
      );
    });
  }

  /// The quick amounts, three equal chips; a label too long for its chip
  /// takes a second line rather than be cut.
  Widget _quickRow(BuildContext context) {
    final c = context.colors;
    final color = quickUp ? AppColors.marketUp : AppColors.marketDown;
    return IntrinsicHeight(
      key: const ValueKey('crypto-round-quick'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < quick.length; i++) ...[
            if (i > 0) SizedBox(width: 8.w),
            Expanded(
              child: Semantics(
                button: true,
                enabled: quick[i].onTap != null,
                child: GestureDetector(
                  key:
                      ValueKey('crypto-round-quick-${quick[i].amount.round()}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: quick[i].onTap == null
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          quick[i].onTap!();
                        },
                  child: Opacity(
                    opacity: quick[i].onTap == null ? 0.35 : 1,
                    child: Container(
                      alignment: Alignment.center,
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: context.isDark ? c.background : c.surfaceLight,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: c.borderSubtle, width: 0.5),
                      ),
                      child: Text(
                        quick[i].label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
