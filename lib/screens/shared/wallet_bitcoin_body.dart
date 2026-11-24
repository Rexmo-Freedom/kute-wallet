import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
// lib/screens/shared/wallet_bitcoin_body.dart
//
// The on-chain Bitcoin body of the wallet detail screen: balance, Purchase,
// Receive / Send, analytics and activity, with pull-to-refresh. Moved
// unchanged out of `wallet_detail_screen.dart` (Wallet hardening Phase 4,
// P4.4) so the Ledger account screen reuses it as its Bitcoin tab.
//
// It relies on the detail screen having pinned the BDK scope and the
// viewed wallet to [wallet] (see `WalletDetailScreen.initState`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/screens/home/bitcoin_home_panes.dart'
    show
        BitcoinListWidthSliver,
        BitcoinPanesFrame,
        bitcoinPaneEnd,
        bitcoinPaneScrollWatch,
        kBitcoinActionPaneKey;
import 'package:kute/screens/search/unified_search_screen.dart'
    show showKuteSearch;
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/theme/app_theme.dart';

class WalletBitcoinBody extends ConsumerWidget {
  final WalletConfig wallet;

  /// The EXPANDED wallet tab (shell_wallet_screen.dart), separated like
  /// the Bitcoin and Dollars homes (bitcoin_home_panes.dart): the hero,
  /// its actions and its Receive / Send dock in the right pane, still;
  /// the charts and the activity behind the phone's own strip in the left
  /// pane, the one scroll. False: the body exactly as it is.
  final bool wide;

  /// [wide] only: the backup banner over the hero, when the tab shows one.
  final Widget? banner;

  const WalletBitcoinBody(
      {super.key, required this.wallet, this.wide = false, this.banner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final balance = ref.watch(walletBalanceCacheProvider)[wallet.id];
    // Hardware / watch-only / tracked / signer wallets don't hold a
    // Spark balance — only on-chain BTC. If `sparkBitcoinbalance` has
    // a non-zero value for one of these (cache contamination from an
    // earlier active-wallet swap), ignore it so the screen never
    // mixes the spending wallet's Spark sats into a cold card.
    final isColdWallet = wallet.isBitcoinSoftware ||
        wallet.isHardware ||
        wallet.isWatchOnly ||
        wallet.isExternalAddress ||
        wallet.isSigner;
    final sats = isColdWallet
        ? (balance?.onChainBtcBalance ?? 0)
        : ((balance?.onChainBtcBalance ?? 0) +
            (balance?.sparkBitcoinbalance ?? 0));
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    // Settings-driven fiat currency — matches the home hero so the
    // user sees their preferred local currency (€, £, …) on the
    // detail screen too instead of being pinned to USD.
    final selectedCurrency =
        ref.watch(settingsProvider.select((s) => s.currency));
    final fiatPerBtc =
        ref.watch(selectedCurrencyProvider(selectedCurrency)).toDouble();
    final fiatValue = (sats / 1e8) * fiatPerBtc;
    // Switching the shell tab to this wallet kicks its BDK scan straight
    // away, so a wallet the cache has never held can be on screen while
    // that scan runs. Say so with the app's standard shimmer instead of
    // rendering a confident zero the person would read as "empty wallet".
    // A wallet that DOES have a cached number keeps showing it; the
    // pull-to-refresh spinner already covers that case.
    final isAwaitingFirstBalance = balance == null &&
        ref.watch(bdkScanningWalletsProvider).contains(wallet.id);

    Future<void> refresh() async {
      HapticFeedback.lightImpact();
      ref
          .read(walletBalanceCacheProvider.notifier)
          .invalidateStreamFreshness(wallet.id);
      // Single-shot BDK scan targeting the scoped
      // wallet only. The continuous loop is
      // deliberately NOT used here — BDK Electrum
      // scans crash under repeated polling, so the
      // detail screen only scans on key user actions
      // (open, pull-to-refresh, Send/Move). An explicit
      // refresh scans every address up to the stop gap,
      // not only the ones this app revealed.
      await BackgroundSyncService()
          .scanBdkScope(source: 'pull_refresh', fullScan: true);
    }

    final balanceCard = isAwaitingFirstBalance
        ? const _BalanceSkeleton()
        : _BalanceCard(
            sats: sats,
            fiatValue: fiatValue,
            fiatCurrency: selectedCurrency,
            btcFormat: btcFormat,
          );

    if (wide) {
      return BitcoinPanesFrame(
        left: _WideWalletLeft(wallet: wallet, onRefresh: refresh),
        // The hero as on a phone, its dock (Receive · Send · search)
        // right under it rather than floating at the window's foot.
        right: CustomScrollView(
          key: kBitcoinActionPaneKey,
          physics: const ClampingScrollPhysics(),
          slivers: [
            if (banner != null) SliverToBoxAdapter(child: banner),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                child: balanceCard,
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 16.h)),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                child: BitcoinWalletPrimaryActions(
                    wallet: wallet, source: 'wallet_detail'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: WalletBitcoinActionBar(
                  wallet: wallet,
                  onSearch: () => showKuteSearch(context,
                      walletId: wallet.id, source: 'wallet_detail'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                  height: MediaQuery.viewPaddingOf(context).bottom + 16.h),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      // Accent spinner so the pull-to-refresh matches the
      // app palette (same treatment as the affiliate
      // screen) while still signalling the BDK scan is
      // mid-flight.
      color: c.accent,
      onRefresh: refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: 8.h,
          bottom: 40.h + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: balanceCard,
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
              child: BitcoinWalletPrimaryActions(
                  wallet: wallet, source: 'wallet_detail'),
            ),
            // Per-wallet analytics rendered edge-to-edge
            // so its self-applied 16.w / 24.h padding
            // matches the rest of the screen instead of
            // stacking on top of the parent's 16.w. The
            // widget reads `viewedWalletId` (set on init)
            // so it surfaces the cold wallet's UTXOs /
            // price / valuation tabs automatically.
            RepaintBoundary(
              child: HomeAnalyticsWidget(
                // Same merged pill strip as Home:
                // Activity leads, then the per-wallet
                // charts (Balance/Price/UTXOs). The
                // Balance chart carries no headline
                // here: the hero card above is the
                // balance now (owner decision).
                onSeeAllActivity: () => showActivityHistory(
                  context,
                  walletIdOverride: wallet.id,
                  title: wallet.name,
                ),
                activityChild: TransactionList(
                  walletIdOverride: wallet.id,
                  showAll: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wide tab's left pane ([WalletBitcoinBody.wide]): the phone's own
/// strip (Activity, then this wallet's Balance / Price / UTXOs) at the
/// pane's top left, where the Dollars pills stand, and the pill's content
/// under it in a readable column, the one scroll. The Activity pill is the
/// wallet's full history here, so it never turns into "See all". A wallet
/// with no history: one empty state, centred under the strip.
class _WideWalletLeft extends ConsumerWidget {
  const _WideWalletLeft({required this.wallet, required this.onRefresh});

  final WalletConfig wallet;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final empty = ref.watch(walletTransactionCacheProvider.select(
        (cache) => cache[wallet.id]?.allTransactionsSorted.isEmpty ?? true));
    final analytics = SliverToBoxAdapter(
      child: RepaintBoundary(
        child: HomeAnalyticsWidget(
          // The strip where the Dollars pills stand (bitcoin_home_panes
          // .dart, BitcoinPaneTop), at a phone's width.
          padding: EdgeInsets.only(top: 8.h, bottom: 24.h),
          stripMaxWidth: KuteLayout.paneWidth - 32,
          activityChild: empty
              ? const NoActivityState(
                  padding: EdgeInsets.fromLTRB(24, 34, 24, 8))
              : TransactionList(walletIdOverride: wallet.id, showAll: true),
        ),
      ),
    );
    return bitcoinPaneScrollWatch(
      ref,
      RefreshIndicator(
        color: c.accent,
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // A readable column of rows; with nothing to list, the pane's
            // width, so the one empty state centres in it (the strip is
            // held to a phone's width either way).
            if (empty) analytics else BitcoinListWidthSliver(sliver: analytics),
            bitcoinPaneEnd(context),
          ],
        ),
      ),
    );
  }
}

/// Shimmer stand-in for [_BalanceCard] while this wallet's first scan
/// runs. Same shape and same palette as Home's hero skeleton, so
/// "loading" reads identically on both surfaces.
class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 4.h, 4.w, 12.h),
      child: KuteSkeleton(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonCircle(40.w),
                SizedBox(width: 10.w),
                SkeletonBar(180.w, 44.h, radius: 12.r),
              ],
            ),
            SizedBox(height: 8.h),
            SkeletonBar(90.w, 16.h, radius: 8.r),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int sats;
  final double fiatValue;
  final String fiatCurrency;
  final String btcFormat;

  const _BalanceCard({
    required this.sats,
    required this.fiatValue,
    required this.fiatCurrency,
    required this.btcFormat,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Canonical BTC wallet hero — sats/BTC headline with fiat as the
    // secondary line. Mirrors the Home hero (typographic ₿ prefix +
    // 56.sp amount, fiat 16.sp under) so spending / hardware /
    // watch-only / tracked / signer detail screens all share the same
    // shape. The user's fiat-hero spending wallet lives on home only;
    // portfolio detail uniformly leads with sats.
    final btcStr = sats.toFormattedString(btcFormat);
    final fiatStr =
        NumberFormat.simpleCurrency(name: fiatCurrency, decimalDigits: 2)
            .format(fiatValue);
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 4.h, 4.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The outer Center widgets force horizontal centering
          // regardless of the parent scroll-view's stretch behavior
          // (Bug 22/29).
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // BIP-177: the same typographic ₿ prefix as the Home
                  // hero, not a separate orange circle.
                  Text(
                    '₿',
                    style: TextStyle(
                      fontSize: 44.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      height: 1.0,
                      color: c.textPrimary,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  BtcAmountText(
                    text: btcStr,
                    style: TextStyle(
                      fontSize: 56.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 6.h),
          Center(
            child: AnimatedBalance(
              text: fiatStr,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search remains bound to the displayed wallet by the host callback.
class WalletBitcoinActionBar extends ConsumerWidget {
  final WalletConfig wallet;
  final VoidCallback onSearch;
  final ValueChanged<double>? onHeightChanged;
  const WalletBitcoinActionBar({
    super.key,
    required this.wallet,
    required this.onSearch,
    this.onHeightChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => KuteBottomActionBar(
        source: 'wallet_detail',
        onHeightChanged: onHeightChanged,
        // Send and Receive are the dock's verbs on a bitcoin surface.
        actions: bitcoinWalletDockActions(context, ref, wallet),
        onSearch: onSearch,
      );
}
