// lib/screens/home/components/desktop_top_bar_money.dart
//
// THE MONEY IN THE DESKTOP TOP BAR (EXPANDED; founder, 26 November 2026,
// of the Dollars right pane: "on the desktop these buttons should move
// more towards the top, the balance always on the top … check main
// fintech apps, and do what they do, like Polymarket and such … but keep
// the same feel as Kute mobile, don't change that much"). As Polymarket,
// Kalshi, Robinhood and Coinbase do on a desktop, the account's money
// lives in the top bar, always in view: the ACTIVE TAB'S balance, its
// actions at the right, then the hub button (kute_top_nav_bar.dart). The
// balance itself stands in the bar's CENTRE, larger (founder, 24 November
// 2026, of the figure beside the actions: "make the balance bigger in the
// center"; of Bitcoin's: "same here"): [KuteDesktopMoney.balance] and
// [KuteDesktopMoney.actions] are the two halves the bar places.
//
//   * Dollars: the one-balance total ([InvestmentBalanceHeader.
//     oneBalanceFigure]: rolling, dimmed with the stale sweep while saved,
//     dots with balances hidden) and under it on one small line what the
//     phone's hero writes there ([OneBalancePnlAvailableLine]:
//     "▲ $3.00 (+1.5%) · Available $25.00"). The figure is not a button
//     (founder, 25 November 2026: "not in number clicking"). Its actions:
//     Portfolio · Buy dollars · Move · Receive · Send (the Portfolio's
//     door beside Buy dollars, then [UsdAccountActionBar.moneyActions]).
//   * Bitcoin: the ₿ balance with its fiat line under it, as the hero
//     draws them (the shimmer while the wallet wakes up, dots with balances
//     hidden); a tap cycles the balances' privacy, as the hero's does. Its
//     actions: Purchase · Scan · Receive · Send ([bitcoinHomeDockActions]).
//   * Another wallet on the first tab: that wallet's balance (its card's
//     figures) and the same four actions for it.
//
// The actions are the phone's own, same order, handlers and events, as
// compact pills ([KuteTopBarActions]). The in-flight Dollars lines the
// hero wrote under the total sit at the top of the Dollars page's left
// pane (usd_account_screen.dart). Switching tabs fades one group into
// the other; the hub button never moves.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatDollars;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/components/wallet_cards.dart'
    show cycleBalancePrivacyTracked;
import 'package:kute/screens/home/home.dart' show heroBalanceShowsSkeleton;
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart'
    show bitcoinHomeDockActions;
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show UsdAccountActionBar, kUsdSurfaceSource;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The balance figure's size in the bar: as large as the bar's height
/// carries with its line under it.
const double _kFigure = 34;

/// The line under it.
const double _kLine = 13.5;

/// The Dollars line's width: its two halves meet at a dot under the
/// figure, as on the phone ([OneBalancePnlAvailableLine]).
const double _kDollarsLineWidth = 264;

/// The active tab's balance, or its actions, for the desktop top bar (see
/// the file header): the bar puts the balance in its centre and the
/// actions at its right. [labels]: the actions with their words (a wide
/// window), else icons with tooltips.
class KuteDesktopMoney extends ConsumerWidget {
  /// The balance, for the bar's centre.
  const KuteDesktopMoney.balance({super.key, required this.activeTab})
      : _actions = false,
        labels = false;

  /// The actions, for the bar's right.
  const KuteDesktopMoney.actions(
      {super.key, required this.activeTab, required this.labels})
      : _actions = true;

  final ActiveNavTab activeTab;
  final bool labels;
  final bool _actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(shellWalletProvider);
    final active = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final (Object key, Widget? group) = switch (activeTab) {
      ActiveNavTab.usd => (
          'usd',
          _actions
              ? KuteTopBarActions(
                  // The Portfolio's door stands beside Buy dollars
                  // (founder, 25 November 2026: "on web put the portfolio
                  // button next to buy dollars"), then the phone's four.
                  actions: [
                    UsdAccountActionBar.portfolioAction(context),
                    ...UsdAccountActionBar.moneyActions(context),
                  ],
                  source: kUsdSurfaceSource,
                  labels: labels)
              : const _DollarsTopBalance(),
        ),
      ActiveNavTab.home when shell != null => (
          'wallet-${shell.id}',
          _actions
              ? KuteTopBarActions(
                  actions: bitcoinHomeDockActions(context, ref, shell,
                      source: 'wallet_detail'),
                  source: 'wallet_detail',
                  labels: labels)
              : _BitcoinTopBalance(wallet: shell),
        ),
      ActiveNavTab.home when active != null && !active.isSigner => (
          'home-${active.id}',
          _actions
              ? KuteTopBarActions(
                  actions: bitcoinHomeDockActions(context, ref, active,
                      source: 'home'),
                  source: 'home',
                  labels: labels)
              : const _BitcoinTopBalance(),
        ),
      _ => ('none', null),
    };
    return AnimatedSwitcher(
      duration: KuteMotion.reduce(context)
          ? Duration.zero
          : KuteMotion.settleDuration,
      switchInCurve: KuteMotion.settle,
      switchOutCurve: KuteMotion.settle,
      layoutBuilder: (current, previous) => Stack(
        alignment: _actions ? Alignment.centerRight : Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(
        key: ValueKey(key),
        child: group ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// The Dollars total in the bar (see the file header).
class _DollarsTopBalance extends ConsumerWidget {
  const _DollarsTopBalance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double value) => visible ? formatDollars(value) : '••••••';
    final figure = InvestmentBalanceHeader.oneBalanceFigure(ref);
    final split = InvestmentBalanceHeader.oneBalanceSplitFigures(ref);
    // The figure is read, not pressed: the Portfolio opens from its own
    // button beside Buy dollars (founder, 25 November 2026: "and not in
    // number clicking").
    return Column(
      key: const ValueKey('top-bar-dollars-balance'),
      mainAxisSize: MainAxisSize.min,
      children: [
        StaleShimmer(
          stale: figure.stale,
          child: RollingNumberText(
            text: figure.text,
            style: TextStyle(
              fontSize: _kFigure,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: figure.stale ? c.textSecondary : c.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: _kDollarsLineWidth,
          child: OneBalancePnlAvailableLine(
            available: amount(split.availableUsd),
            availableLabel: context.l10n.available,
            stale: split.stale,
            fontSize: _kLine,
          ),
        ),
      ],
    );
  }
}

/// A Bitcoin balance in the bar (see the file header): the Bitcoin home's
/// ([wallet] null: the active wallet, as the hero reads it) or another
/// wallet's (its card's figures).
class _BitcoinTopBalance extends ConsumerWidget {
  const _BitcoinTopBalance({this.wallet});

  final WalletConfig? wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final w = wallet;
    final int sats;
    final bool skeleton;
    if (w == null) {
      // The hero's own reading (home.dart, _BitcoinAccountFront).
      final balanceState = ref.watch(balanceNotifierProvider);
      sats = balanceState.sparkBitcoinbalance + balanceState.onChainBtcBalance;
      final activeId =
          ref.watch(settingsProvider.select((s) => s.activeWalletId));
      skeleton = heroBalanceShowsSkeleton(
        breezWaking: ref.watch(breezSDKProvider).isLoading,
        btcSats: sats,
        hasCachedBalance: ref.watch(walletBalanceCacheProvider.select(
            (cache) => activeId != null && cache.containsKey(activeId))),
        createdEmpty: ref.watch(settingsProvider
            .select((s) => s.activeWallet?.createdEmpty ?? false)),
      );
    } else {
      // The wallet card's (wallet_bitcoin_body.dart): a cold wallet's
      // on-chain bitcoin alone.
      final balance = ref.watch(walletBalanceCacheProvider)[w.id];
      final cold = w.isBitcoinSoftware ||
          w.isHardware ||
          w.isWatchOnly ||
          w.isExternalAddress ||
          w.isSigner;
      sats = cold
          ? (balance?.onChainBtcBalance ?? 0)
          : ((balance?.onChainBtcBalance ?? 0) +
              (balance?.sparkBitcoinbalance ?? 0));
      skeleton = balance == null &&
          ref.watch(bdkScanningWalletsProvider).contains(w.id);
    }
    if (skeleton) {
      return KuteSkeleton(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBar(130, _kFigure * 0.9, radius: 8),
            const SizedBox(height: 4),
            SkeletonBar(70, _kLine, radius: 6),
          ],
        ),
      );
    }
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final rate = ref.watch(selectedCurrencyProvider(currency)).toDouble();
    final raw = (sats / 1e8) * rate;
    final fiat = raw.isFinite ? raw : 0.0;
    final fiatStr = visible
        ? NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
            .format(fiat)
        : '••••••••';
    final btcStr = visible ? sats.toFormattedString(btcFormat) : '••••••••';
    final block = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₿',
              style: TextStyle(
                fontSize: _kFigure * 0.8,
                fontWeight: FontWeight.w800,
                height: 1.0,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: 1),
            AnimatedBtcAmountText(
              text: btcStr,
              dim: visible,
              style: TextStyle(
                fontSize: _kFigure,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: c.textPrimary,
              ),
              brightColor: c.textPrimary,
              dimColor: c.textTertiary,
            ),
          ],
        ),
        const SizedBox(height: 3),
        AnimatedBalance(
          text: fiatStr,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: _kLine + 0.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    // The home hero's tap: the balances' privacy, one step.
    if (w != null) return block;
    return GestureDetector(
      key: const ValueKey('top-bar-bitcoin-balance'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.mediumImpact();
        cycleBalancePrivacyTracked(ref, surface: 'home_hero');
      },
      child: block,
    );
  }
}
