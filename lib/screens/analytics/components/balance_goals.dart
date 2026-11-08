// lib/screens/analytics/components/balance_goals.dart
//
// THE BITCOIN HOME'S MILESTONES (founder, 6 November 2026: "Gamify the
// graph for the Bitcoin balance ... to reach certain thresholds"). The
// GOALS tab of the spending wallet (the pill read "Balance" until 8
// November 2026: the hero above already shows the balance; the tab's key,
// its analytics value and its links are unchanged), on the Bitcoin home
// only, carries a ladder of round goals for the person's money
// (balance_milestones.dart has the arithmetic and the once-only record):
//
//   * ON THE CHART, ALWAYS (founder, 8 November 2026: "the chart is the
//     goal's chart"): the next goal as the plot's dashed goal line, "Next
//     $500", whatever the distance; the chart's own scale keeps the line
//     at least half the plot and tints the gap up to the goal
//     (kute_trend_chart.dart, KuteTrendScale). The chart is in sats, so
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
//     Activity's position squares: the NEXT GOAL first (Sal squinting up
//     at a flag; "Next goal"; "$250 to go"; "$500" large; it carries the
//     move, so it leads: founder, 8 November 2026) and the LEVEL (Sal's
//     still for the level; a slim bar under him filling towards the goal,
//     the chance gauge's track and fill; the level's name; "50% to $500";
//     "Level 3" large). The bar fills from empty when first drawn and
//     eases to each new value on the settle curve. The total is never
//     written: with no Dollars it would repeat the headline's worth;
//   * THE LADDER SHEET (founder, 8 November 2026): the Level square taps
//     through to a sheet listing all twelve levels ([BalanceLadderSheet]),
//     in the Referral program's language (affiliate_screen.dart: its rows
//     on the one soft card, the app's sheet header, "Share my level" as the
//     bar, Done with balances hidden, its X either way): one
//     row per level, Sal's still, the level's name, "Level 3 · From $250"
//     (the first "Under $100"); the levels passed carry a quiet check, the
//     current one is written in full with its progress ("50% to $500")
//     and the settings lists' filled disc. With balances hidden the sheet
//     opens and names every level, but marks none;
//   * SAL PER LEVEL (founder, 7 November 2026: "use Sal for the next goal
//     and naming the levels, and use Sal Blender"): one 3D still per level
//     name, his attitude and props growing with it, always deadpan
//     (level_1 .. level_12 in lib/assets/sal, render_level_stills.py in
//     Kute Assets): Kute Nap, lying, lids nearly shut; Kute Coin, one
//     coin, looked down at; Kute Stack, a paw on a short stack; Kute
//     Podium, on a low podium of coins; Kute Briefcase, reading glasses and
//     the briefcase; Kute Vault, lying on a vault, paws crossed; Kute Tower,
//     chin up on a tall stack; Kute Bars, on gold bars; Kute Heap, lying on
//     a heap of them; Kute Crown, a small crown on a gold plinth; Kute
//     Legend, the crown, eyes shut on a wide stack; Off the Kute charts, the
//     crown on a tower that
//     leaves the frame. The squares are taller than the position squares
//     by Sal's room over their 40 logo;
//   * THE LOOPS (founder, 7 November 2026, of the squares: "animate
//     this"): each level's Sal is a calm 4 s idle loop from its still (a
//     breath, a dry blink, an ear or tail flick, a side-eye; the crown
//     catching the light; Kute Nap dozing), and the Next goal's flag
//     waves while Sal looks from it to the viewer and back. They play only
//     while the square is on screen ([BalanceGoalSalMotion]); under Reduce
//     Motion, and in the Next goal square while balances are hidden, the
//     first frame holds (the hidden Level square's flat card is a still);
//   * THE NEXT GOAL IS THE MOVE (founder, 7 November 2026, of the separate
//     "Move $50 to Dollars" card under the squares: "the next goal should
//     have the move to dollars not this"): where the move is allowed (the
//     route classifier's gates) and Investing or Predictions is live in
//     the person's country, the Next goal square itself taps through: its
//     line reads "Move $25 to Dollars" with a chevron in place of "$250 to
//     go", and it opens Move money straight on the amount, Bitcoin to
//     Dollars, pinned (showOwnMoneyMove), with that amount filled in (a
//     round tenth of the goal, never more than the bitcoin is worth).
//     Elsewhere it is a plain goal, not tappable. No card under the
//     squares; it names no venue and never says the money grows;
//   * SHARE MY LEVEL (founder, 8 November 2026: "just change Sal on this
//     tab to share my level"): while the Goals pill is on screen the Sal bar
//     IS "Share my level" (KuteBarContext.primary, its long press still
//     opens the search and Sal), opening the level's card
//     (share/goal_share.dart: the level and its name, Sal's still, no money
//     at all). The scope lives in [BalanceGoals], so the Activity pill, the
//     Dollars tab (its tickers are off) and any page over the tab read their
//     own bar. No level to share (nothing ever held, not ready, not the
//     spending wallet) or balances hidden: the default bar. The Levels sheet
//     has the same bar in place of Done, one way to share per screen; so
//     does a rung passed, the bar reading the same for its 6 s (the card
//     has no room for a button of its own, and needs none);
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
//     the bar is its track alone, the Level's Sal is a still that names no
//     level (the share cards' flat side-eye), the goal line is not drawn,
//     the Next goal's move drops its amount, the ladder sheet marks no
//     level;
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
// currency} on the Next goal's move (milestone: the goal, display
// currency; amount: the dollars filled in); `balance_goals_ladder_opened`
// {level} when the Level square opens the ladder sheet (the level number
// alone); `balance_goal_card_shared` {level, result, source} once a level's
// card went to the OS share sheet (goal_share.dart). Exact values; nothing
// else.

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
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/share/goal_share.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard, kKuteActionCardPadding;
import 'package:kute/screens/shared/kute_bar_context.dart';
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

/// The level's Sal still ([BalanceMilestoneProgress.nameIndex]): `level_1`
/// (Warming up) to `level_12` (Off the charts).
String balanceLevelClip(int nameIndex) =>
    'level_${nameIndex.clamp(0, kBalanceLevelNames - 1) + 1}';

/// The level's Sal at the share card's size (`level_card_1` ..
/// `level_card_12`, 384 px, from the same renders as [balanceLevelClip], whose
/// 192 px cell was soft blown up to the card's 1080 px image).
String balanceLevelCardClip(int nameIndex) =>
    'level_card_${nameIndex.clamp(0, kBalanceLevelNames - 1) + 1}';

/// Opens the card of the level [progress] stands on (share/goal_share.dart).
Future<void> shareBalanceLevel(
  BuildContext context,
  BalanceMilestoneProgress progress, {
  required String source,
}) =>
    openGoalCardShare(
      context,
      level: progress.level,
      name: balanceLevelName(context.l10n, progress.nameIndex),
      still: balanceLevelCardClip(progress.nameIndex),
      source: source,
    );

/// The Next goal square's Sal: squinting up at a flag.
const String kBalanceGoalNextClip = 'goal_next';

/// The Level square's Sal while balances are hidden: a still that names
/// no level (the share cards' flat side-eye).
const String kBalanceGoalHiddenClip = 'card_flat';

/// Every Sal still the goals draw.
List<String> get balanceGoalClips => [
      for (var i = 0; i < kBalanceLevelNames; i++) balanceLevelClip(i),
      kBalanceGoalNextClip,
      kBalanceGoalHiddenClip,
    ];

/// Sal's still in a goal square, design units, and the Level's slim bar
/// under him (its gap and its thickness).
const double kBalanceGoalSal = 64;
const double _kBarGap = 6;
const double _kBarHeight = 3;

/// The goal squares' height: the position squares' ([portfolioSquareHeight])
/// grown by Sal and the bar's room over their 40 logo. The celebration
/// takes the same, so nothing under it moves.
double balanceGoalSquareHeight(BuildContext context) =>
    portfolioSquareHeight(context) +
    (kBalanceGoalSal + _kBarGap + _kBarHeight - kPortfolioSquareIcon).w;

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
    // The bar's "Share my level": null while there is no level to share or
    // it is hidden (see the file header).
    VoidCallback? shareLevel;
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
      if (visible) {
        shareLevel = () => shareBalanceLevel(context, progress,
            source: celebrating != null
                ? kGoalShareCelebration
                : kGoalShareTab);
      }
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
        onLevelTap: () => showBalanceLadderSheet(context,
            progress: progress, currency: input.currency, visible: visible),
      );
    }
    // One shape whatever is ready, so the card is never remounted (a
    // scrub, the range's morph) when the goals arrive under it.
    return KuteBarContextScope(
      // Held only while this tab is on screen (the shell parks the other
      // tab's branch with its tickers off), as the Dollars home's.
      active: shareLevel != null && TickerMode.valuesOf(context).enabled,
      barContext: KuteBarContext.primary(
        label: context.l10n.balanceGoalShareMyLevel,
        onPrimary: shareLevel,
        // Never off: it is the default bar when there is nothing to share.
        disabledLabel: null,
        source: 'balance_goals_tab',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [widget.card(goal), if (goals != null) goals],
      ),
    );
  }
}

/// The Next goal square's move: its line ("Move $25 to Dollars") and its
/// tap.
@immutable
class BalanceGoalNudge {
  const BalanceGoalNudge({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

/// The goals under the Balance card, in the Bitcoin home Activity's
/// language (its "Latest" heading and squares, its "Earlier" soft card):
/// "Goals", then two squares side by side, the Next goal first (Sal and
/// the flag, "Next goal", "$250 to go", "$500" large; where the move is
/// allowed, "Move $25 to Dollars" with a chevron in place of the gap, and
/// the square taps through) and the Level (the level's Sal over the
/// progress bar, the level's name, "50% to $500", "Level 3" large; it taps
/// through to the ladder sheet, [onLevelTap]), or for a moment the
/// celebration in their place at their height.
class BalanceGoalsSection extends StatelessWidget {
  const BalanceGoalsSection({
    super.key,
    required this.progress,
    required this.currency,
    required this.visible,
    this.celebrating,
    this.confettiCue = 0,
    this.nudge,
    this.onLevelTap,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  /// The rung being celebrated; null shows the squares.
  final double? celebrating;

  /// Bumped to throw the confetti ([KuteConfettiBurst.cue]).
  final int confettiCue;
  final BalanceGoalNudge? nudge;

  /// The Level square's tap (the ladder sheet); null leaves it plain.
  final VoidCallback? onLevelTap;

  /// Sal's square in the celebration, design units.
  static const double salSize = 96;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = KuteMotion.reduce(context);
    // Figures hidden mid-celebration: the squares' dots at once.
    final rung = visible ? celebrating : null;
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
                      // The Next goal leads: it carries the move.
                      children: [
                        _NextGoalSquare(
                            progress: progress,
                            currency: currency,
                            visible: visible,
                            nudge: nudge),
                        _LevelSquare(
                            progress: progress,
                            currency: currency,
                            visible: visible,
                            onTap: onLevelTap),
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
/// (position_rows.dart): the grouped card's ground, 14 padding; Sal
/// top-left (with the Level's bar under him), then the name and the line
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
    this.action = false,
  });

  /// The line is the square's tap ("Move $25 to Dollars"): a touch
  /// stronger than the quiet line, with a chevron after it.
  final bool action;

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
        height: balanceGoalSquareHeight(context),
        padding: EdgeInsets.all(14.w),
        decoration: PremiumGroupContainer.decorationOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: kBalanceGoalSal.w,
                height: (kBalanceGoalSal + _kBarGap + _kBarHeight).w,
                child: Align(alignment: Alignment.topLeft, child: leading),
              ),
            ),
            const Spacer(),
            Text(label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet),
            SizedBox(height: 2.h),
            Row(
              children: [
                Flexible(
                  child: Text(line,
                      key: lineKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quiet.copyWith(
                        color: action ? c.textSecondary : c.textTertiary,
                        fontSize: 12.sp,
                        fontWeight: action ? FontWeight.w600 : null,
                        height: 1.3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                if (action)
                  Icon(Icons.chevron_right_rounded,
                      key: const ValueKey('balance-goal-move-chevron'),
                      size: 14.sp,
                      color: c.textSecondary),
              ],
            ),
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

/// The Level square: the level's Sal over the bar filling towards the
/// goal, the level's name, "50% to $500", and "Level 3" large; the whole
/// square taps through to the ladder sheet ([onTap], on the press spring,
/// as the position squares open their detail). Hidden: dots, a Sal that
/// names no level, and the bar's track alone.
class _LevelSquare extends StatelessWidget {
  const _LevelSquare({
    required this.progress,
    required this.currency,
    required this.visible,
    this.onTap,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = KuteMotion.reduce(context);
    final square = _GoalSquare(
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GoalSal(
            key: const ValueKey('balance-goal-level-sal'),
            clip: visible
                ? balanceLevelClip(progress.nameIndex)
                : kBalanceGoalHiddenClip,
            fallback: Icons.star_rounded,
          ),
          SizedBox(height: _kBarGap.w),
          // Fills from empty the first time it is drawn, then eases to
          // each new value on the settle curve; at once under Reduce
          // Motion.
          SizedBox(
            width: kBalanceGoalSal.w,
            height: _kBarHeight.w,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: visible ? progress.fraction : 0),
              duration:
                  reduce ? Duration.zero : const Duration(milliseconds: 700),
              curve: KuteMotion.settle,
              builder: (context, f, _) => BalanceGoalBar(
                  key: const ValueKey('balance-goal-bar'), fraction: f),
            ),
          ),
        ],
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
    final tap = onTap;
    if (tap == null) return square;
    return Semantics(
      button: true,
      child: KutePressable(
        child: GestureDetector(
          key: const ValueKey('balance-goal-ladder'),
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: square,
        ),
      ),
    );
  }
}

/// Opens the ladder sheet ([BalanceLadderSheet]) over the Level square's
/// tap and records `balance_goals_ladder_opened` {level}.
void showBalanceLadderSheet(
  BuildContext context, {
  required BalanceMilestoneProgress progress,
  required String currency,
  required bool visible,
}) {
  HapticFeedback.selectionClick();
  TrackingService.track('balance_goals_ladder_opened',
      params: {'level': progress.level});
  showAppBottomSheet(
    context: context,
    builder: (_) => BalanceLadderSheet(
        progress: progress, currency: currency, visible: visible),
  );
}

/// The ladder sheet (see the file header): "Levels", then every level as
/// a row on the one soft card, in the Referral program's rows' language
/// (affiliate_screen.dart, How it works): Sal's still for the level, the
/// level's name, and "Level 3 · From $250" under it ("Under $100" for the
/// first). The levels passed carry a quiet check; the current one is
/// written in full with its progress ("50% to $500") and the settings
/// lists' filled disc; the ones ahead are quiet. The bar is "Share my
/// level" (share/goal_share.dart), the header's X closing the sheet. With
/// balances hidden every level is named and none is marked, and the bar is
/// Done: the level is hidden, so nothing is shared.
class BalanceLadderSheet extends StatelessWidget {
  const BalanceLadderSheet({
    super.key,
    required this.progress,
    required this.currency,
    required this.visible,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;

  /// Sal's still in a row, design units.
  static const double salSize = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ladder = BalanceMilestoneLadder.forCurrency(currency);
    final surface = KuteActionCard.surfaceOf(context);
    return AppBottomSheetContainer(
      child: Column(
        key: const ValueKey('balance-ladder-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.balanceLadderTitle,
            trailing: const AppBottomSheetCloseButton(),
            titleIsHeader: true,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const ValueKey('balance-ladder'),
                    padding:
                        KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
                    decoration: surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < kBalanceLevelNames; i++) ...[
                          // Tight enough that on a common phone the last
                          // row rests above the bar, before any scroll (it
                          // sat under it at 14, founder, 8 November 2026);
                          // on a smaller one it scrolls clear.
                          if (i > 0) SizedBox(height: 10.h),
                          _LadderRow(
                            index: i,
                            // Level 1 is under the first rung; level i + 1
                            // starts at rung i - 1.
                            threshold: i == 0
                                ? l10n.balanceLadderUnder(
                                    formatBalanceGoal(ladder.rung(0), currency))
                                : l10n.balanceLadderFrom(formatBalanceGoal(
                                    ladder.rung(i - 1), currency)),
                            // Marks only over shown figures. Every level
                            // past the last name wears it: the last row is
                            // current for all of them.
                            state: !visible
                                ? _LadderState.unmarked
                                : i < progress.nameIndex
                                    ? _LadderState.passed
                                    : i == progress.nameIndex
                                        ? _LadderState.current
                                        : _LadderState.ahead,
                            progressLine: l10n.balanceGoalProgress(
                                progress.percent,
                                formatBalanceGoal(progress.next, currency)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // THE BAR IS THE BUTTON (kute_bar_context.dart): Share my
                  // level, Done with the level hidden. The last row scrolls
                  // clear of it (the room is the end of the scroll).
                  KuteBarContextScope(
                    barContext: visible
                        ? KuteBarContext.primary(
                            label: l10n.balanceGoalShareMyLevel,
                            onPrimary: () => shareBalanceLevel(
                                context, progress,
                                source: kGoalShareLadder),
                            disabledLabel: null,
                            source: 'balance_goals_ladder',
                          )
                        : KuteBarContext.primary(
                            label: l10n.done,
                            onPrimary: () => Navigator.of(context).pop(),
                            disabledLabel: null,
                            source: 'balance_goals_ladder',
                          ),
                    child: SizedBox(height: kuteBarScrollClearance.h),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LadderState { passed, current, ahead, unmarked }

/// One level of the ladder sheet (see [BalanceLadderSheet]).
class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.index,
    required this.threshold,
    required this.state,
    required this.progressLine,
  });

  /// The level name's index (0 to [kBalanceLevelNames] - 1).
  final int index;
  final String threshold;
  final _LadderState state;

  /// The current level's line ("50% to $500").
  final String progressLine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final current = state == _LadderState.current;
    final ahead = state == _LadderState.ahead;
    final sal = BalanceLadderSheet.salSize.w;
    final line = current
        ? progressLine
        : '${l10n.balanceGoalLevel(index + 1)} · $threshold';
    return MergeSemantics(
      key: ValueKey('balance-ladder-level-${index + 1}'),
      child: Semantics(
        selected: current ? true : null,
        checked: state == _LadderState.passed ? true : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Sal's still for the level, held (it names the level; the
            // loops are the squares').
            ExcludeSemantics(
              child: BalanceGoalSalMotion(
                hold: true,
                child: SizedBox.square(
                  dimension: sal,
                  child: SalSprite(
                    clip: balanceLevelClip(index),
                    size: sal,
                    fallback: Center(
                      child: Icon(Icons.star_rounded,
                          size: 20.w, color: c.textPrimary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balanceLevelName(l10n, index),
                    key: ValueKey('balance-ladder-name-${index + 1}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KuteActionCard.optionTitleStyle(c).copyWith(
                      color: ahead ? c.textTertiary : c.textPrimary,
                      fontWeight: current ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line,
                    key: ValueKey('balance-ladder-line-${index + 1}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KuteActionCard.subtitleStyle(c).copyWith(
                      color: current ? c.textSecondary : c.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (state == _LadderState.passed) ...[
              SizedBox(width: 12.w),
              // A rung passed: the quiet check.
              Icon(Icons.check_rounded,
                  key: ValueKey('balance-ladder-passed-${index + 1}'),
                  size: 18.sp,
                  color: c.textTertiary),
            ],
            if (current) ...[
              SizedBox(width: 12.w),
              // The current level: the settings lists' selection mark, the
              // filled disc with the check on it.
              Container(
                key: ValueKey('balance-ladder-current-${index + 1}'),
                width: 22.sp,
                height: 22.sp,
                decoration: BoxDecoration(
                    color: context.ctaFill, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded,
                    color: context.ctaOnColor, size: 15.sp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Next goal square: Sal and the waving flag, "Next goal", "$250 to
/// go", and the goal large. With [nudge] (the move allowed) the line is
/// "Move $25 to Dollars" with a chevron and the whole square taps through
/// on the press spring; without, a plain goal. Hidden: the figures are
/// dots, the move drops its amount, Sal holds his first frame.
class _NextGoalSquare extends StatelessWidget {
  const _NextGoalSquare({
    required this.progress,
    required this.currency,
    required this.visible,
    this.nudge,
  });

  final BalanceMilestoneProgress progress;
  final String currency;
  final bool visible;
  final BalanceGoalNudge? nudge;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final n = nudge;
    final square = _GoalSquare(
      leading: _GoalSal(
        key: const ValueKey('balance-goal-next-sal'),
        clip: kBalanceGoalNextClip,
        fallback: Icons.flag_rounded,
        still: !visible,
      ),
      label: l10n.balanceGoalNext,
      line: n != null
          ? n.label
          : visible
              ? l10n.balanceGoalToGo(formatBalanceGoal(progress.gap, currency))
              : _shortDots,
      action: n != null,
      figure: visible ? formatBalanceGoal(progress.next, currency) : _dots,
      labelKey: const ValueKey('balance-goal-next-label'),
      lineKey: ValueKey(
          n != null ? 'balance-goal-nudge-label' : 'balance-goal-to-go'),
      figureKey: const ValueKey('balance-goal-next'),
    );
    if (n == null) return square;
    return Semantics(
      button: true,
      child: KutePressable(
        child: GestureDetector(
          key: const ValueKey('balance-goal-nudge'),
          behavior: HitTestBehavior.opaque,
          onTap: n.onTap,
          child: square,
        ),
      ),
    );
  }
}

/// Sal in a goal square ([kBalanceGoalSal]): his loop for the level (or
/// the next goal), played only while the square is on screen
/// ([BalanceGoalSalMotion]); [still] holds its first frame. A level
/// changing switches the loop in place (a short dissolve). Without a sheet
/// (not bundled, a test) the icon the square wore before.
class _GoalSal extends StatelessWidget {
  const _GoalSal({
    super.key,
    required this.clip,
    required this.fallback,
    this.still = false,
  });

  final String clip;
  final IconData fallback;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final size = kBalanceGoalSal.w;
    return BalanceGoalSalMotion(
      hold: still,
      child: SizedBox.square(
        dimension: size,
        child: SalSprite(
          clip: clip,
          size: size,
          fallback: Center(
            child:
                Icon(fallback, size: 24.w, color: context.colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Lets the Sal under it move only while it is on screen and [hold] is
/// off: otherwise its first frame holds (it reads as Reduce Motion to
/// him: [SalSprite] then shows frame 0 and stops its ticker). On screen
/// means inside every scrolling viewport around it, checked as they
/// scroll; a tab off screen is already muted by its TickerMode.
class BalanceGoalSalMotion extends StatefulWidget {
  const BalanceGoalSalMotion(
      {super.key, required this.child, this.hold = false});

  final Widget child;
  final bool hold;

  @override
  State<BalanceGoalSalMotion> createState() => _BalanceGoalSalMotionState();
}

class _BalanceGoalSalMotionState extends State<BalanceGoalSalMotion> {
  final List<ScrollPosition> _positions = [];
  bool _onScreen = true;
  bool _checkQueued = false;

  /// Tests: whether the Sal under it may move now.
  @visibleForTesting
  bool get debugPlaying => _onScreen && !widget.hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
    _queueCheck();
  }

  void _listen() {
    for (final p in _positions) {
      p.removeListener(_queueCheck);
    }
    _positions.clear();
    // Every scrolling viewport around the square (the home's page, a
    // pager around it), nearest first.
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null && _positions.length < 4) {
      final position = scrollable.position;
      position.addListener(_queueCheck);
      _positions.add(position);
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  void _queueCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _check();
    });
  }

  void _check() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    var visible = true;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null && visible) {
      final port = scrollable.context.findRenderObject();
      if (port is RenderBox && port.hasSize && port.attached) {
        final view = port.localToGlobal(Offset.zero) & port.size;
        visible = view.overlaps(rect);
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    if (visible != _onScreen) setState(() => _onScreen = visible);
  }

  @override
  void dispose() {
    for (final p in _positions) {
      p.removeListener(_queueCheck);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_onScreen && !widget.hold) return widget.child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: widget.child,
    );
  }
}

/// The Level's slim bar under Sal: the whole track, and the fill from the
/// left for [fraction] of it (the Predictions chance gauge's look: the
/// border colour's track, a textPrimary fill, round ends).
class BalanceGoalBar extends StatelessWidget {
  const BalanceGoalBar({super.key, required this.fraction});

  /// 0 to 1.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      size: Size.infinite,
      painter: _BarPainter(
        fraction: fraction.clamp(0.0, 1.0),
        track: c.border,
        fill: c.textPrimary,
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    if (fraction > 0) {
      // Never thinner than its own height, so a sliver still reads round.
      final w = math.max(size.height, size.width * fraction);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
          Paint()..color = fill);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
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
        height: balanceGoalSquareHeight(context),
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
