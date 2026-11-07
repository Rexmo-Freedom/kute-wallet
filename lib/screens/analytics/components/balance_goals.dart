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
//   * THE CARD STAYS CLEAN (founder, 6 November 2026: "The design is too
//     dense; must be better, like the things in the Dollars screens"): the
//     figure, the change, the chart with its goal line and the range row,
//     nothing else inside. The goals stand UNDER the card, on its gutters,
//     in the Bitcoin home Activity's language (its "Latest" heading and
//     two-by-two squares, its "Earlier" soft card):
//   * "GOALS", then two squares side by side, drawn as the Dollars
//     Activity's position squares: the LEVEL (a ring filling towards the
//     goal, the chance gauge's track and fill; the level's name; "50% to
//     $500"; "Level 3" large) and the NEXT GOAL (a flag; "Next goal";
//     "$250 to go"; "$500" large). The ring fills from empty when first
//     drawn and eases to each new value on the settle curve. The total is
//     never written: with no Dollars it would repeat the headline's worth;
//   * THE NUDGE, one full-width soft card under the squares: the Dollars
//     mark, "Move $25 to Dollars" over "Your money, more places to go in
//     Dollars.", a chevron. It opens Move money straight on the amount,
//     Bitcoin to Dollars, pinned (showOwnMoneyMove), with that amount
//     filled in (a round tenth of the goal, never more than
//     the bitcoin is worth). Shown only where the move is allowed
//     (the route classifier's gates) and Investing or Predictions is live in the
//     person's country; it names neither. It never says the money grows:
//     places to go, not returns;
//   * A RUNG PASSED: once, after the figure has held for 1.5 s, one card
//     takes the squares' place at their height (nothing moves): Sal
//     cheering (`body_cheer`, once) beside "You passed $250" large and
//     "Bitcoin and Dollars together. Sal is acting like it's nothing.",
//     with a confetti burst thrown up from it over the card
//     (kute_confetti.dart; none under Reduce Motion) and a medium haptic;
//     after 6 s the squares come back, now towards the next goal. Not
//     while balances are hidden: the celebration waits until the figures
//     are shown;
//   * BALANCES HIDDEN: the squares' figures and the level's name are dots,
//     the ring is its track alone, the goal line is not drawn, the nudge
//     drops its amount;
//   * NOTHING EVER HELD (the card's empty state): no goals, nothing
//     recorded or celebrated.
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

import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraCapabilityRequirements;
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide;
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show MoneyMovementAccount, showOwnMoneyMove;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show kPortfolioSquareIcon, portfolioSquareHeight;
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
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

  /// Bitcoin into Dollars is allowed here (the route classifier's gates).
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
    // Bitcoin into Dollars through the one route classifier, as the Move
    // sheet asks (orchestra_capability_requirements.dart).
    canMoveToDollars: orchestraCapabilityRequirements(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'spark',
      destinationAsset: 'USDB',
      policy: policy,
    ).every(policy.allows),
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

/// The Bitcoin home's Balance card with its milestones under it. [card]
/// builds the plain Balance card with the goal line this hands it; the
/// goals ([BalanceGoalsSection]) stand under the card on the same gutters,
/// never inside it. [hasHistory] false (nothing ever held: the card's
/// empty state): the card alone, nothing recorded or celebrated.
class BalanceGoals extends ConsumerStatefulWidget {
  const BalanceGoals({super.key, required this.card, this.hasHistory = true});

  final Widget Function(KuteTrendGoal? goal) card;

  /// The balance has a history (the card draws its chart); the goals are
  /// shown, recorded and celebrated only then.
  final bool hasHistory;

  /// Test seam: what the nudge opens. Null opens the Move sheet
  /// ([showOwnMoneyMove], Bitcoin to Dollars).
  @visibleForTesting
  static void Function(BuildContext context, MoveLockedSide side, double usd)?
      debugMoveOpener;

  @override
  ConsumerState<BalanceGoals> createState() => _BalanceGoalsState();
}

class _BalanceGoalsState extends ConsumerState<BalanceGoals> {
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
      if (!mounted || !widget.hasHistory) return;
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
    HapticFeedback.selectionClick();
    TrackingService.track('balance_goal_cta_tapped', params: {
      'milestone': _exact(goal),
      'amount': _exact(usd),
      'currency': currency,
    });
    TrackingService.markEntrySource('move', kBalanceGoalSource);
    final open = BalanceGoals.debugMoveOpener;
    if (open != null) return open(context, MoveLockedSide.depositToUsd, usd);
    // An own-account move: the one Move money screen, nothing to pick.
    unawaited(showOwnMoneyMove(context,
        from: MoneyMovementAccount.bitcoin,
        entrySource: kBalanceGoalSource,
        initialTargetUsd: usd));
  }

  @override
  Widget build(BuildContext context) {
    final input = ref.watch(balanceGoalInputProvider);
    KuteTrendGoal? goal;
    Widget? goals;
    if (input != null && input.ready && widget.hasHistory) {
      final l10n = context.l10n;
      final visible =
          ref.watch(settingsProvider.select((s) => s.balanceVisible));
      final ladder = BalanceMilestoneLadder.forCurrency(input.currency,
          usdToDisplay: input.usdToDisplay);
      final progress = ladder.progress(input.total);
      // Recording and celebrating only over shown figures.
      if (visible) _consider(ladder, progress.reached);

      final celebrating = _celebrating;
      final goalSats = _goalLine(input, progress);
      if (celebrating == null && goalSats != null) {
        goal = KuteTrendGoal(
            value: goalSats,
            label: l10n.balanceGoalChartLabel(
                formatBalanceGoal(progress.next, input.currency)));
      }

      final suggestion = balanceGoalSuggestedUsd(
          goal: progress.next,
          usdToDisplay: input.usdToDisplay,
          bitcoinUsd: input.bitcoinUsd);
      // "More places to go" is true only where a venue is live.
      final nudge = input.canMoveToDollars &&
              (input.investing || input.predictions) &&
              suggestion != null
          ? BalanceGoalNudge(
              label: visible
                  ? l10n.balanceGoalMove(NumberFormat.simpleCurrency(
                          name: 'USD',
                          decimalDigits: suggestion % 1 == 0 ? 0 : 2)
                      .format(suggestion))
                  : l10n.balanceGoalMovePlain,
              line: l10n.balanceGoalMoveWhy,
              onTap: () => _move(suggestion, progress.next, input.currency),
            )
          : null;

      goals = BalanceGoalsSection(
        progress: progress,
        currency: input.currency,
        visible: visible,
        celebrating: celebrating,
        confettiCue: _confettiCue,
        nudge: nudge,
      );
    }
    // One shape whatever is ready, so the card is never remounted (a
    // scrub, the range's morph) when the goals arrive under it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [widget.card(goal), if (goals != null) goals],
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

/// The goals under the Balance card, in the Bitcoin home Activity's
/// language (its "Latest" heading and squares, its "Earlier" soft card):
/// "Goals", then two squares side by side, the Level (the progress ring,
/// the level's name, "50% to $500", "Level 3" large) and the Next goal
/// (the flag, "Next goal", "$250 to go", "$500" large), or for a moment
/// the celebration in their place at their height; then the nudge as one
/// full-width soft card.
class BalanceGoalsSection extends StatelessWidget {
  const BalanceGoalsSection({
    super.key,
    required this.progress,
    required this.currency,
    required this.visible,
    this.celebrating,
    this.confettiCue = 0,
    this.nudge,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  /// The rung being celebrated; null shows the squares.
  final double? celebrating;

  /// Bumped to throw the confetti ([KuteConfettiBurst.cue]).
  final int confettiCue;
  final BalanceGoalNudge? nudge;

  /// Sal's square in the celebration, design units.
  static const double salSize = 96;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = KuteMotion.reduce(context);
    // Figures hidden mid-celebration: the squares' dots at once.
    final rung = visible ? celebrating : null;
    final n = nudge;
    return Column(
      key: const ValueKey('balance-goals'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading(l10n.balanceGoalsHeading),
        // The squares, or for a moment the celebration in their place
        // at their height (nothing under it moves); the confetti thrown
        // up from it over the card.
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedSwitcher(
              duration: reduce ? Duration.zero : KuteMotion.settleDuration,
              switchInCurve: KuteMotion.settle,
              switchOutCurve: KuteMotion.settle,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: rung != null
                  ? _Celebration(
                      key: ValueKey('balance-goal-celebration-$rung'),
                      amount: formatBalanceGoal(rung, currency),
                    )
                  : ActivitySquareGrid(
                      key: const ValueKey('balance-goal-squares'),
                      children: [
                        _LevelSquare(
                            progress: progress,
                            currency: currency,
                            visible: visible),
                        _NextGoalSquare(
                            progress: progress,
                            currency: currency,
                            visible: visible),
                      ],
                    ),
            ),
            Positioned.fill(
              child: KuteConfettiBurst(
                key: const ValueKey('balance-goal-confetti'),
                cue: confettiCue,
                origin: const Alignment(0, 0.4),
              ),
            ),
          ],
        ),
        if (n != null) ...[
          SizedBox(height: 10.w),
          _NudgeCard(nudge: n),
        ],
      ],
    );
  }
}

/// "Goals" over the squares, in the home Activity's heading style
/// ("Latest", all_activity.dart), 12 inside the blocks' edge.
class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12.w, 14.h, 12.w, 8.h),
        child: Text(
          label,
          key: const ValueKey('balance-goals-heading'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      );
}

const String _dots = '••••••';
const String _shortDots = '••••';

/// One goal square, drawn as the Dollars Activity's position squares
/// (position_rows.dart): the grouped card's ground, 14 padding, the
/// squares' height; the picture top-left, then the name and the line
/// under it quiet over the figure at 22 sp.
class _GoalSquare extends StatelessWidget {
  const _GoalSquare({
    required this.leading,
    required this.label,
    required this.line,
    required this.figure,
    required this.labelKey,
    required this.lineKey,
    required this.figureKey,
  });

  final Widget leading;
  final String label;
  final String line;
  final String figure;
  final Key labelKey;
  final Key lineKey;
  final Key figureKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    return MergeSemantics(
      child: Container(
        height: portfolioSquareHeight(context),
        padding: EdgeInsets.all(14.w),
        decoration: PremiumGroupContainer.decorationOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                  dimension: kPortfolioSquareIcon.w, child: leading),
            ),
            const Spacer(),
            Text(label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet),
            SizedBox(height: 2.h),
            Text(line,
                key: lineKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet.copyWith(
                  color: c.textTertiary,
                  fontSize: 12.sp,
                  height: 1.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            SizedBox(height: 4.h),
            // A figure too wide for the square shrinks rather than
            // overflow it.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: RollingFigure(
                key: figureKey,
                text: figure,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Level square: the ring filling towards the goal, the level's
/// name, "50% to $500", and "Level 3" large. Hidden: dots and the ring's
/// track alone.
class _LevelSquare extends StatelessWidget {
  const _LevelSquare({
    required this.progress,
    required this.currency,
    required this.visible,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = KuteMotion.reduce(context);
    return _GoalSquare(
      // Fills from empty the first time it is drawn, then eases to each
      // new value on the settle curve; at once under Reduce Motion.
      leading: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: visible ? progress.fraction : 0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: KuteMotion.settle,
        builder: (context, f, _) => BalanceGoalRing(
            key: const ValueKey('balance-goal-ring'), fraction: f),
      ),
      label: visible ? balanceLevelName(l10n, progress.nameIndex) : _shortDots,
      line: visible
          ? l10n.balanceGoalProgress(
              progress.percent, formatBalanceGoal(progress.next, currency))
          : _shortDots,
      figure: visible ? l10n.balanceGoalLevel(progress.level) : _dots,
      labelKey: const ValueKey('balance-goal-level-name'),
      lineKey: const ValueKey('balance-goal-progress'),
      figureKey: const ValueKey('balance-goal-level'),
    );
  }
}

/// The Next goal square: the flag, "Next goal", "$250 to go", and the
/// goal large. Hidden: the figures are dots.
class _NextGoalSquare extends StatelessWidget {
  const _NextGoalSquare({
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
    return _GoalSquare(
      // The icon on the ring's soft ground (the Portfolio ring's track).
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: context.isDark ? c.surfaceLight : c.surfaceElevated,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.flag_rounded,
            size: 20.w, color: c.textPrimary),
      ),
      label: l10n.balanceGoalNext,
      line: visible
          ? l10n.balanceGoalToGo(formatBalanceGoal(progress.gap, currency))
          : _shortDots,
      figure: visible ? formatBalanceGoal(progress.next, currency) : _dots,
      labelKey: const ValueKey('balance-goal-next-label'),
      lineKey: const ValueKey('balance-goal-to-go'),
      figureKey: const ValueKey('balance-goal-next'),
    );
  }
}

/// The Level square's ring: the whole track, and the fill from the top,
/// clockwise, for [fraction] of it (the Predictions chance gauge's look:
/// the border colour's track, a textPrimary fill, 4 px, round ends).
class BalanceGoalRing extends StatelessWidget {
  const BalanceGoalRing({super.key, required this.fraction});

  /// 0 to 1.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A star in the hole: a level, never a spinner.
    return CustomPaint(
      size: Size.infinite,
      painter: _RingPainter(
        fraction: fraction.clamp(0.0, 1.0),
        track: c.border,
        fill: c.textPrimary,
        stroke: 4,
      ),
      child: Center(
        child: Icon(Icons.star_rounded, size: 18.w, color: c.textPrimary),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(rect.center, r, paint(track));
    final sweep = 2 * math.pi * fraction;
    if (sweep > 0) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, paint(fill));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

/// A rung passed: one card the squares' width and height in their place,
/// Sal cheering (`body_cheer`, once) beside "You passed $250" large and
/// the deadpan line under it.
class _Celebration extends StatelessWidget {
  const _Celebration({super.key, required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final sal = BalanceGoalsSection.salSize.w;
    return Semantics(
      liveRegion: true,
      child: Container(
        height: portfolioSquareHeight(context),
        padding: EdgeInsets.fromLTRB(8.w, 8.w, 16.w, 8.w),
        decoration: PremiumGroupContainer.decorationOf(context),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: sal,
                child: SalSprite(
                  clip: 'body_cheer',
                  size: sal,
                  loop: false,
                  fallback: KuteDogCheer(size: sal, cycles: 2),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.balanceMilestonePassed(amount),
                      key: const ValueKey('balance-goal-celebration-title'),
                      maxLines: 1,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    l10n.balanceMilestonePassedLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The nudge as one full-width soft card (the home Activity's "Earlier"
/// card, one row): the Dollars mark, "Move $25 to Dollars" over its line,
/// and a chevron. The whole card taps through on the press spring.
class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.nudge});

  final BalanceGoalNudge nudge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: KutePressable(
        child: GestureDetector(
          key: const ValueKey('balance-goal-nudge'),
          behavior: HitTestBehavior.opaque,
          onTap: nudge.onTap,
          child: DecoratedBox(
            decoration: PremiumGroupContainer.decorationOf(context),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 12.h, 12.w, 12.h),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: AssetIcon(assetCode: 'USD', size: 36.sp),
                  ),
                  SizedBox(width: 12.w),
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
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            height: 1.25,
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
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
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
        ),
      ),
    );
  }
}
