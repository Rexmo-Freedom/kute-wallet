// lib/screens/polymarket/components/crypto_round_card.dart
//
// The compact live crypto round card and its parts, the Predictions
// list's card ([CryptoPredictBanner.compact], polymarket_screen.dart,
// under Crypto › 5 Min and pinned under Crypto › All): the card itself
// ([CompactCryptoCard]: logo, title, the past rounds as dots, the
// countdown pill; the live price, its move and the target; the sparkline
// against the dashed target; the one pair of Up and Down pills with their
// odds), the pills ([CompactSidePill]), the dots ([PastRoundDots]), the
// "Next · 7:20" line ([CryptoNextWindowLine]) and the on-screen counter
// the shared Chainlink feed streams for ([CryptoCardOnScreen]). Moved here
// from polymarket_screen.dart on 8 November 2026 unchanged. The slots a
// taller card once used (a strip under the plot, its own plot height,
// a card with no round or no odds) stay for the next card that needs
// them; the Instant page that used them went on 9 November 2026 (the
// rounds are Crypto's rows).

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

/// "Next · 7:20" over the buttons of a card that have rolled to the next
/// window: one line in the card's own target style, nothing around it.
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
    required this.onUp,
    required this.onDown,
    this.strip,
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

  /// "Next · 7:20" once the buttons have rolled to the next window
  /// (crypto_next_round.dart); null while they bet on this one. On a card
  /// of one length: the name of the round the buttons bet on when it is
  /// not the one on show.
  final String? nextLabel;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// A strip laid between the sparkline and the buttons (a taller card's
  /// window strip); null on the list's card.
  final Widget? strip;

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = CryptoAssetLogo(config: config, size: _logo.sp);
    // No odds (the Instant card with no round to bet on): "Up" and "Down"
    // alone, never 50% and 50%.
    final pair = upFrac == null ? null : formatPolyChancePair(upFrac!);
    final seeded = (history?.length ?? 0) >= 2;
    final rolled = nextLabel != null;
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
          // Logo, title, past rounds as dots, the countdown pill.
          Row(
            children: [
              SizedBox(width: _logo.sp, height: _logo.sp, child: logo),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (pastResults.isNotEmpty) ...[
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
                      Text(
                        countdown,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    else
                      KuteSkeleton(
                        key: const ValueKey('crypto-round-countdown-skeleton'),
                        child: SkeletonBar(34.w, 12.sp, radius: 4.r),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // The live price, its move against the target, the target.
          // One fixed line, skeleton or figures: a price scaled down to
          // fit beside a wider move, or the skeleton giving way to the
          // digits, never changes the card's height (the list under it
          // would move with every tick).
          SizedBox(
            height: _priceLine(context, priceStyle),
            child: loading
                ? KuteSkeleton(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SkeletonBar(150.w, 24.h, radius: 6.r),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: RollingNumberText(
                              text: priceText, style: priceStyle),
                        ),
                      ),
                      if (diffText != null) ...[
                        SizedBox(width: 6.w),
                        Text(
                          diffText!,
                          maxLines: 1,
                          style: TextStyle(
                            color: diffUp
                                ? AppColors.marketUp
                                : AppColors.marketDown,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      SizedBox(width: 8.w),
                      const Spacer(),
                      Text(
                        targetText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
          ),
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
          // A taller card's strip of rounds, 10 under the plot.
          if (strip != null) ...[
            SizedBox(height: 10.h),
            strip!,
          ],
          if (rolled) ...[
            SizedBox(height: 6.h),
            SizedBox(
                height: _nextLine,
                child: CryptoNextWindowLine(label: nextLabel!)),
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
                  odds: pair?.first ?? '',
                  window: nextLabel,
                  up: true,
                  onTap: onUp,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: CompactSidePill(
                  key: const ValueKey('crypto-round-down'),
                  label: context.l10n.downLabel,
                  odds: pair?.second ?? '',
                  window: nextLabel,
                  up: false,
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
    required this.onTap,
  });

  final String label;
  final String odds;

  /// "Next · 7:20" when the pill bets on the next window: read out with it.
  final String? window;
  final bool up;
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
      label: '${window == null ? '' : '$window, '}$label $odds'.trim(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: CompactCryptoCard.pillHeight,
          decoration: marketPairDecoration(color,
              borderRadius: BorderRadius.circular(radius.r),
              glow: !context.isDark),
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
    );
  }
}

/// The last few windows as tiny dots, oldest first: up and down in the
/// market colours, a hairline ring while one is still settling.
class PastRoundDots extends StatelessWidget {
  const PastRoundDots({super.key, required this.results});

  final List<CryptoWindowResult> results;

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

