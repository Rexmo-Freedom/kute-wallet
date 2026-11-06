// lib/screens/analytics/components/balance_goals.dart
//
// THE BITCOIN HOME'S MILESTONES (founder, 6 November 2026: "Gamify the
// graph for the Bitcoin balance ... to reach certain thresholds"). The
// Balance tab of the spending wallet, on the Bitcoin home only, carries a
// ladder of round goals for the person's money (balance_milestones.dart
// has the arithmetic and the once-only record):
//
//   * ON THE CHART: the next goal as the plot's dashed goal line, "Next
//     $500", while it is in reach of the line on screen (the line keeps at
//     least half the plot; balanceGoalInReach). The chart is in sats, so
//     the line sits at the bitcoin it would take with the Dollars as they
//     are: the bitcoin now plus the gap at today's price. A rate refresh
//     that moves it under 2% leaves it where it is (no jitter on ticks);
//   * UNDER THE RANGE ROW, after a hairline (the soft-card row grammar):
//     "Level 3 · Stacker" on the left, "62% to $500" on the right, and a
//     4 px bar under them (the Predictions chance bar's track and fill),
//     easing to a new value on the settle curve. The total is never
//     written here: with no Dollars it would repeat the headline's worth;
//   * THE NUDGE, one quiet row with a chevron (the home's waiting-deposit
//     line): "Move $25 to Dollars" over "Your money, more places to go:
//     Investing and Predictions in Dollars." It opens the Move sheet locked
//     to Dollars with that amount filled in (a round tenth of the goal,
//     never more than the bitcoin is worth). Shown only where the move is
//     allowed (`orchestra.swap`) and at least one of the two venues is
//     live in the person's country, and the line names only the live ones.
//     It never says the money grows: places to go, not returns;
//   * A RUNG PASSED: once, after the figure has held for 1.5 s, the footer
//     shows Sal cheering (`body_cheer`, once) beside "You passed $250" and
//     "Bitcoin and Dollars together. Sal is acting like it's nothing.",
//     with a confetti burst over the card (kute_confetti.dart; none under
//     Reduce Motion) and a medium haptic; after 6 s the footer goes back
//     to the progress, now towards the next goal. Not while balances are
//     hidden: the celebration waits until the figures are shown;
//   * BALANCES HIDDEN: the level and the progress are dots, the bar is its
//     track alone, the goal line is not drawn, the nudge drops its amount.
//
// The total is the spending wallet's bitcoin at today's price plus the
// Dollars cash; open Investing and Predictions positions never count, so
// no trade is ever scored or celebrated, and moving bitcoin to Dollars
// never lowers the progress.
//
// Analytics: `balance_milestone_reached` {milestone, currency} when a
// rung is celebrated; `balance_goal_cta_tapped` {milestone, amount,
// currency} on the nudge (milestone: the goal, display currency; amount:
// the dollars filled in). Exact values; nothing else.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_confetti.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/balance_milestones.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// How long a newly passed rung must hold before it is celebrated.
const Duration kBalanceMilestoneSettle = Duration(milliseconds: 1500);

/// How long the celebration stays in the footer.
const Duration kBalanceMilestoneCelebration = Duration(seconds: 6);

/// The Move sheet's entry source for the nudge.
const String kBalanceGoalSource = 'bitcoin_balance_goal';

/// Everything the milestones read, as plain values.
@immutable
class BalanceGoalInput {
  const BalanceGoalInput({
    required this.ready,
    required this.currency,
    required this.bitcoinSats,
    required this.fiatPerBtc,
    required this.usdToDisplay,
    required this.cashUsd,
    this.canMoveToDollars = false,
    this.investing = false,
    this.predictions = false,
  });

  /// The figures are real: the wallet's balance is known (cached or
  /// live, or a wallet made empty here), the rates are in, the Dollars
  /// have answered. Nothing is recorded or celebrated before.
  final bool ready;

  /// The display currency.
  final String currency;

  /// The spending wallet's bitcoin, in sats.
  final int bitcoinSats;

  /// One bitcoin in the display currency.
  final double fiatPerBtc;

  /// One US dollar in the display currency.
  final double usdToDisplay;

  /// The Dollars cash in US dollars: the spending account, venue cash,
  /// money moving, owed back; never a position.
  final double cashUsd;

  /// Bitcoin into Dollars is allowed here (`orchestra.swap`).
  final bool canMoveToDollars;

  /// Investing / Predictions are live in the person's country.
  final bool investing;
  final bool predictions;

  double get bitcoinDisplay =>
      fiatPerBtc.isFinite ? bitcoinSats / 1e8 * fiatPerBtc : 0;

  /// The bitcoin's worth in US dollars.
  double get bitcoinUsd => usdToDisplay > 0 ? bitcoinDisplay / usdToDisplay : 0;

  /// The milestones' total, in the display currency.
  double get total {
    final cash = cashUsd.isFinite && cashUsd > 0 ? cashUsd : 0;
    final t =
        bitcoinDisplay + cash * (usdToDisplay.isFinite ? usdToDisplay : 0);
    return t.isFinite ? t : 0;
  }
}

/// The Bitcoin home's milestones input, or null when the wallet on screen
/// is not the spending wallet (a Ledger, a watch-only wallet).
final balanceGoalInputProvider = Provider<BalanceGoalInput?>((ref) {
  final wallet = ref.watch(viewedWalletProvider) ??
      ref.watch(settingsProvider.select((s) => s.activeWallet));
  if (wallet == null || !wallet.isSparkWallet) return null;
  final currency = ref.watch(settingsProvider.select((s) => s.currency));
  final sats = ref
      .watch(viewedWalletBalanceProvider.select((b) => b.sparkBitcoinbalance));
  final known = wallet.createdEmpty ||
      ref.watch(walletBalanceCacheProvider
          .select((cache) => cache.containsKey(wallet.id)));
  final fiatPerBtc = ref.watch(selectedCurrencyProvider(currency)).toDouble();
  final usdToDisplay =
      ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble();
  final one = ref.watch(oneBalanceProvider);
  final policy = ref.watch(runtimeCapabilitiesProvider);
  return BalanceGoalInput(
    ready: known &&
        one.dollarsKnown &&
        fiatPerBtc.isFinite &&
        fiatPerBtc > 0 &&
        usdToDisplay.isFinite &&
        usdToDisplay > 0,
    currency: currency,
    bitcoinSats: sats,
    fiatPerBtc: fiatPerBtc,
    usdToDisplay: usdToDisplay,
    cashUsd: one.totalUsd - one.investedUsd,
    canMoveToDollars: policy.allows('orchestra.swap'),
    investing: policy.allows('hyperliquid.browse'),
    predictions: policy.allows('polymarket.browse'),
  );
});

/// Where the once-only record keeps its flags (a map in tests).
final balanceMilestoneFlagsProvider =
    Provider<BalanceMilestoneFlags>((ref) => const OnceBalanceMilestoneFlags());

/// The level's name ("Stacker"); [index] from
/// [BalanceMilestoneProgress.nameIndex].
String balanceLevelName(AppLocalizations l10n, int index) => switch (index) {
      0 => l10n.balanceLevelName0,
      1 => l10n.balanceLevelName1,
      2 => l10n.balanceLevelName2,
      3 => l10n.balanceLevelName3,
      4 => l10n.balanceLevelName4,
      5 => l10n.balanceLevelName5,
      6 => l10n.balanceLevelName6,
      7 => l10n.balanceLevelName7,
      8 => l10n.balanceLevelName8,
      9 => l10n.balanceLevelName9,
      10 => l10n.balanceLevelName10,
      _ => l10n.balanceLevelName11,
    };

/// A goal as the app writes a round figure: "$500", "€2,500".
String formatBalanceGoal(double value, String currency) {
  final whole = (value - value.roundToDouble()).abs() < 1e-9;
  return NumberFormat.simpleCurrency(
          name: currency, decimalDigits: whole ? 0 : 2)
      .format(value);
}

/// The analytics figure for a goal: an int when it is whole.
num _exact(double v) => (v - v.roundToDouble()).abs() < 1e-9 ? v.round() : v;

/// The Bitcoin home's Balance chart with its milestones. [chart] builds
/// the plain chart with the goal line and the footer this hands it.
class BalanceGoalsChart extends ConsumerStatefulWidget {
  const BalanceGoalsChart({super.key, required this.chart});

  final Widget Function(KuteTrendGoal? goal, Widget? footer) chart;

  /// Test seam: what the nudge opens. Null opens the Move sheet
  /// ([showDepositSheet]).
  @visibleForTesting
  static void Function(BuildContext context, MoveLockedSide side, double usd)?
      debugMoveOpener;

  @override
  ConsumerState<BalanceGoalsChart> createState() => _BalanceGoalsChartState();
}

class _BalanceGoalsChartState extends ConsumerState<BalanceGoalsChart> {
  Timer? _settle;
  Timer? _celebrationEnd;

  /// The rung on show, while the celebration lasts.
  double? _celebrating;
  int _confettiCue = 0;

  /// The goal line as drawn, and what it was drawn for (hysteresis).
  double? _goalSats;
  double? _goalFor;
  int? _goalBase;

  @override
  void dispose() {
    _settle?.cancel();
    _celebrationEnd?.cancel();
    super.dispose();
  }

  BalanceMilestoneRecord get _record =>
      BalanceMilestoneRecord(ref.read(balanceMilestoneFlagsProvider));

  /// A rung not recorded yet: wait for the figure to hold, then record
  /// it (and celebrate it unless this is the first reading).
  void _consider(BalanceMilestoneLadder ladder, int reached) {
    if (_settle?.isActive ?? false) return;
    if (!_record.hasNews(ladder, reached)) return;
    _settle = Timer(kBalanceMilestoneSettle, () {
      if (!mounted) return;
      // The figure now, not the one last built: a blip that went back
      // within the settle is not news.
      final input = ref.read(balanceGoalInputProvider);
      if (input == null || !input.ready) return;
      if (!ref.read(settingsProvider).balanceVisible) return;
      final l = BalanceMilestoneLadder.forCurrency(input.currency,
          usdToDisplay: input.usdToDisplay);
      final rung = _record.claim(l, l.reached(input.total));
      if (rung != null) _celebrate(rung, l.currency);
    });
  }

  void _celebrate(double rung, String currency) {
    TrackingService.track('balance_milestone_reached', params: {
      'milestone': _exact(rung),
      'currency': currency,
    });
    HapticFeedback.mediumImpact();
    setState(() {
      _celebrating = rung;
      _confettiCue++;
    });
    _celebrationEnd?.cancel();
    _celebrationEnd = Timer(kBalanceMilestoneCelebration, () {
      if (mounted) setState(() => _celebrating = null);
    });
  }

  /// The goal line in sats: the bitcoin now plus the gap at today's
  /// price, held while a rate refresh moves it under 2%.
  double? _goalLine(BalanceGoalInput input, BalanceMilestoneProgress p) {
    if (!(input.fiatPerBtc > 0)) return null;
    final raw = input.bitcoinSats + p.gap / input.fiatPerBtc * 1e8;
    if (!raw.isFinite) return null;
    final held = _goalSats;
    if (held != null &&
        _goalFor == p.next &&
        _goalBase == input.bitcoinSats &&
        (raw - held).abs() <= held.abs() * 0.02) {
      return held;
    }
    _goalSats = raw;
    _goalFor = p.next;
    _goalBase = input.bitcoinSats;
    return raw;
  }

  void _move(double usd, double goal, String currency) {
    TrackingService.track('balance_goal_cta_tapped', params: {
      'milestone': _exact(goal),
      'amount': _exact(usd),
      'currency': currency,
    });
    TrackingService.markEntrySource('move', kBalanceGoalSource);
    final open = BalanceGoalsChart.debugMoveOpener;
    if (open != null) return open(context, MoveLockedSide.depositToUsd, usd);
    unawaited(showDepositSheet(context,
        lockedSide: MoveLockedSide.depositToUsd, initialTargetUsd: usd));
  }

  @override
  Widget build(BuildContext context) {
    final input = ref.watch(balanceGoalInputProvider);
    if (input == null || !input.ready) return widget.chart(null, null);
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final ladder = BalanceMilestoneLadder.forCurrency(input.currency,
        usdToDisplay: input.usdToDisplay);
    final progress = ladder.progress(input.total);
    // Recording and celebrating only over shown figures.
    if (visible) _consider(ladder, progress.reached);

    final celebrating = _celebrating;
    final goalSats = _goalLine(input, progress);
    final goal = celebrating == null && goalSats != null
        ? KuteTrendGoal(
            value: goalSats,
            label: l10n.balanceGoalChartLabel(
                formatBalanceGoal(progress.next, input.currency)))
        : null;

    final suggestion = balanceGoalSuggestedUsd(
        goal: progress.next,
        usdToDisplay: input.usdToDisplay,
        bitcoinUsd: input.bitcoinUsd);
    final why = input.investing && input.predictions
        ? l10n.balanceGoalMoveWhyBoth
        : input.investing
            ? l10n.balanceGoalMoveWhyInvesting
            : input.predictions
                ? l10n.balanceGoalMoveWhyPredictions
                : null;
    final nudge = input.canMoveToDollars && why != null && suggestion != null
        ? BalanceGoalNudge(
            label: visible
                ? l10n.balanceGoalMove(NumberFormat.simpleCurrency(
                        name: 'USD', decimalDigits: suggestion % 1 == 0 ? 0 : 2)
                    .format(suggestion))
                : l10n.balanceGoalMovePlain,
            line: why,
            onTap: () => _move(suggestion, progress.next, input.currency),
          )
        : null;

    final footer = BalanceGoalFooter(
      progress: progress,
      currency: input.currency,
      visible: visible,
      celebrating: celebrating,
      nudge: nudge,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.chart(goal, footer),
        Positioned.fill(
          child: KuteConfettiBurst(
            key: const ValueKey('balance-goal-confetti'),
            cue: _confettiCue,
          ),
        ),
      ],
    );
  }
}

/// The nudge's words and its tap.
@immutable
class BalanceGoalNudge {
  const BalanceGoalNudge(
      {required this.label, required this.line, required this.onTap});

  final String label;
  final String line;
  final VoidCallback onTap;
}

/// The footer under the range row: the level and the progress (or the
/// celebration), then the nudge.
class BalanceGoalFooter extends StatelessWidget {
  const BalanceGoalFooter({
    super.key,
    required this.progress,
    required this.currency,
    required this.visible,
    this.celebrating,
    this.nudge,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  /// The rung being celebrated; null shows the progress.
  final double? celebrating;
  final BalanceGoalNudge? nudge;

  /// Sal's square in the celebration.
  static const double salSize = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = KuteMotion.reduce(context);
    // Figures hidden mid-celebration: the dots at once.
    final rung = visible ? celebrating : null;
    final n = nudge;
    return Column(
      key: const ValueKey('balance-goal-footer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),
        Divider(color: c.borderSubtle, height: 1, thickness: 0.5),
        SizedBox(height: 12.h),
        // The progress, or for a moment the celebration in its place; the
        // card follows the height on the settle curve (AnalyticsCard).
        AnimatedSwitcher(
          duration: reduce ? Duration.zero : KuteMotion.settleDuration,
          switchInCurve: KuteMotion.settle,
          switchOutCurve: KuteMotion.settle,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, if (current != null) current],
          ),
          child: rung != null
              ? _Celebration(
                  key: ValueKey('balance-goal-celebration-$rung'),
                  amount: formatBalanceGoal(rung, currency),
                )
              : _Progress(
                  key: const ValueKey('balance-goal-progress-slot'),
                  progress: progress,
                  currency: currency,
                  visible: visible,
                ),
        ),
        if (n != null) ...[
          SizedBox(height: 4.h),
          _NudgeRow(nudge: n),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    super.key,
    required this.progress,
    required this.currency,
    required this.visible,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final reduce = KuteMotion.reduce(context);
    const dots = '••••••';
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                visible
                    ? TextSpan(children: [
                        TextSpan(
                          text: l10n.balanceGoalLevel(progress.level),
                          style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                            text:
                                ' · ${balanceLevelName(l10n, progress.nameIndex)}'),
                      ])
                    : const TextSpan(text: dots),
                key: const ValueKey('balance-goal-level'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: 12.w),
            Text(
              visible
                  ? l10n.balanceGoalProgress(progress.percent,
                      formatBalanceGoal(progress.next, currency))
                  : dots,
              key: const ValueKey('balance-goal-progress'),
              maxLines: 1,
              style: quiet,
            ),
          ],
        ),
        SizedBox(height: 8.h),
        // The Predictions chance bar's look: 4 px, the border colour's
        // track, a textPrimary fill; easing to a new value, at once
        // under Reduce Motion. Hidden: the track alone.
        TweenAnimationBuilder<double>(
          tween: Tween(end: visible ? progress.fraction : 0),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
          curve: KuteMotion.settle,
          builder: (context, f, _) => ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              key: const ValueKey('balance-goal-bar'),
              height: 4,
              child: ColoredBox(
                color: c.border,
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: f.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: ColoredBox(
                      key: const ValueKey('balance-goal-bar-fill'),
                      color: c.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Celebration extends StatelessWidget {
  const _Celebration({super.key, required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final size = BalanceGoalFooter.salSize.h;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: size,
              child: SalSprite(
                clip: 'body_cheer',
                size: size,
                loop: false,
                fallback: KuteDogCheer(size: size, cycles: 2),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.balanceMilestonePassed(amount),
                  key: const ValueKey('balance-goal-celebration-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  l10n.balanceMilestonePassedLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The nudge: one quiet row with a chevron, as the home's waiting-deposit
/// line.
class _NudgeRow extends StatelessWidget {
  const _NudgeRow({required this.nudge});

  final BalanceGoalNudge nudge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: KutePressScale(
        onTap: nudge.onTap,
        child: Padding(
          key: const ValueKey('balance-goal-nudge'),
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nudge.label,
                      key: const ValueKey('balance-goal-nudge-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      nudge.line,
                      key: const ValueKey('balance-goal-nudge-line'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(Icons.chevron_right_rounded,
                  color: c.textTertiary, size: 18.sp),
            ],
          ),
        ),
      ),
    );
  }
}
