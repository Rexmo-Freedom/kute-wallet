// lib/screens/usd/usd_account_screen.dart
//
// The Dollars tab of the spending account — the dollar twin of the Bitcoin
// tab. It is the Bitcoin surface, part for part (user decision: "the
// design should be exactly the same as the bitcoin one, same buttons
// same everything"):
//
//   * the same hero as [WalletBitcoinBody] — the currency glyph, then
//     the amount, then a quiet second line,
//   * the same primary action row — the Dollar deposit door filling
//     the width,
//   * the same dock — Receive on the left, Send on the right, search in
//     the square,
//   * the same pull-to-refresh, with the accent spinner,
//   * the same pill strip under the actions, holding the two tabs the
//     Bitcoin screen leads with — Activity, then Balance — behind an
//     Earn tab of its own.
//
// EARN IS A TAB, NOT A DOOR. Holding dollars pays a daily bitcoin
// reward on the whole balance: nothing is staked, nothing is locked and
// there is nowhere to deposit into. So Earn is a VIEW of this same
// money, drawn by the same chart engine as Balance with the payout
// ledger as its series (usd_earn_chart.dart), and not a screen to push
// with Deposit and Withdraw buttons of its own — Purchase, Send and
// Receive already move dollars in and out, right here.
//
// EARN IS GATED BY THE BACKEND. The `usd.earn` capability
// (usdEarnEnabledProvider) decides whether the tab exists at all. Off,
// or with no policy to read, the strip is Activity and Balance only,
// the rewards API is never called and no rate appears anywhere; the
// rewards still accrue, they are just not shown.
//
// The other intentional difference: the activity is the dollar ledger
// only, and the strip stops after Balance. A cash account has no price
// chart and no coins map.
//
// ONE DOLLAR DEPOSIT DOOR. Every way of funding this balance is the
// same door wearing the same name and the same mark: "Dollar deposit"
// beside `kUsdMarkAsset`, opening [MoveLockedSide.depositToUsd] with
// the destination pinned here and the source left pickable. Paying with
// bitcoin is a source inside that door, not a second door: there is no
// separate "bitcoin to dollars" anywhere.
//
// Receive opens the coin picker off the Orchestra route list, pointed
// at this balance: whatever coin the money arrives in, dollars land.
// Send is its own screen (usd_send_screen.dart), pointed the other way:
// the user picks what the recipient gets and the dollars convert on the
// way out. The app's other dollar pool (the Predictions Safe) is a
// DIFFERENT account with a different balance, and neither verb here may
// ever act on it.
//
// The tab only ever renders for the spending account (see
// `shellShowsUsdTab` in shell_venue_tabs.dart) — a Bitcoin-only,
// watch-only, tracked, signer or Ledger account has no dollars.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart'
    show usdEarnEnabledProvider;
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/analytics/components/money_flow_breakdown.dart';
import 'package:kute/services/portfolio/money_flow_categories.dart'
    show MoneyFlowLedger;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart'
    show kShellTopBarSpacing;
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Source key for every event this surface emits.
const String kUsdSurfaceSource = 'usd';

/// Shell branch: the spending account's dollars. Same chrome as the other
/// tab pages — screen gradient, the floating nav bar's room at the top,
/// the shared money dock at the bottom.
///
/// The backup banner [ShellWalletScreen] carries above its body is
/// deliberately not repeated here: this IS the spending account, and Home
/// already shows that account its card.
class UsdAccountScreen extends StatelessWidget {
  const UsdAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: KuteDockHost(
        dockBuilder: (onHeightChanged) =>
            UsdAccountActionBar(onHeightChanged: onHeightChanged),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kShellTopBarSpacing.h),
              const Expanded(child: UsdAccountBody()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Balance, the primary action row, and the Earn / Activity / Balance
/// strip — the Bitcoin body with the charts a cash account cannot draw
/// taken out.
class UsdAccountBody extends ConsumerWidget {
  const UsdAccountBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dollars = ref.watch(usdBalanceProvider);
    final earnAllowed = ref.watch(usdEarnEnabledProvider);
    // The account these controls act on. The tab only renders for the
    // spending account, so this resolves in every real case; the
    // disabled row below is the belt-and-braces path.

    return RefreshIndicator(
      // Accent spinner, same as the Bitcoin body's pull-to-refresh.
      color: c.accent,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        TrackingService.pullToRefreshExecuted(screen: 'usd');
        // The dollar rows arrive with the Spark payment sync, so the
        // refresh this surface needs is the wallet sync, not a BDK scan.
        await BackgroundSyncService().forceRefreshAll();
      },
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
              child: _UsdBalanceCard(dollars: dollars),
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
              child: const _UsdPrimaryActions(),
            ),
            // The Bitcoin screen's pill strip, rendered edge-to-edge so
            // its own insets apply: Earn, when the backend allows it,
            // leads with what the balance has paid, Activity holds the
            // dollar ledger (the shared list, its rows and its empty
            // state), Balance holds the DOLLAR balance over time,
            // Breakdown the dollars in and out by kind. The
            // tabs are passed in: left to itself the strip falls through
            // to the shared bitcoin balance chart, which is the wrong
            // money on this screen. No Price and no Coins — a cash
            // account has neither.
            RepaintBoundary(
              child: HomeAnalyticsWidget(
                activityAndBalanceOnly: true,
                // The dollar ledger on its own screen, scoped the same
                // way the strip's preview is.
                onSeeAllActivity: () =>
                    showActivityHistory(context, onlyUsdb: true),
                // Null hides the tab: the chart is never mounted, so it
                // never reads the rewards API or fires usd_earn_*.
                earnChild: earnAllowed ? const UsdEarnChart() : null,
                // The same preview Home shows: the most recent rows, with
                // "See all" above opening the full dollar ledger (user
                // decision). The whole history used to sit inline here.
                activityChild: const TransactionList(
                  onlyUsdb: true,
                  emptyState: NoActivityState(),
                ),
                valuationChild: const UsdBalanceChart(),
                // Where the dollars went and where they came from.
                breakdownChild:
                    const MoneyFlowBreakdown(ledger: MoneyFlowLedger.dollars),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dollar hero. Same shape as the Bitcoin balance card — the asset
/// mark and the amount beside it, and nothing underneath — so the two
/// tabs read as one account. The mark carries the currency, so the
/// amount is the bare figure exactly as the sats figure is, and the
/// screen's own name already says which money this is.
class _UsdBalanceCard extends StatelessWidget {
  const _UsdBalanceCard({required this.dollars});

  final double dollars;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = NumberFormat('#,##0.00').format(dollars);
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 4.h, 4.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The outer Center forces horizontal centering regardless of
          // the parent scroll-view's stretch behavior, same as Bitcoin.
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Where the Bitcoin hero puts its typographic ₿, the
                  // dollar hero puts a typographic $ — the same glyph the
                  // Investing and Predictions amounts carry, at the same
                  // weight as the figure beside it (user decision).
                  Text(
                    r'$',
                    style: TextStyle(
                      fontSize: 44.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      height: 1.0,
                      color: c.textPrimary,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  AnimatedBalance(
                    text: amount,
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
        ],
      ),
    );
  }
}

/// The Dollar deposit door, full width, with nothing beside it: the
/// Earn shortcut that used to share the row is a tab in the strip below
/// now, because the programme pays on the balance this screen already
/// shows.
///
/// It carries the shared dollar mark and the shared label, the same two
/// the Move sheet shows once it opens, so the door reads as one thing
/// end to end. The destination is pinned to THIS balance and the source
/// stays pickable, so bitcoin and Cash App (while the policy offers it)
/// are ways to pay for a dollar deposit rather than doors of their own.
class _UsdPrimaryActions extends StatelessWidget {
  const _UsdPrimaryActions();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: AppButton(
          text: context.l10n.dollarDeposit,
          svgAsset: kUsdMarkAsset,
          onPressed: () {
            TrackingService.quickAction('dollar_deposit',
                source: kUsdSurfaceSource);
            TrackingService.markEntrySource('move', kUsdSurfaceSource);
            showDepositSheet(context, lockedSide: MoveLockedSide.depositToUsd);
          },
        ),
      );
}

/// The Dollars dock — the Bitcoin dock's verbs in the Bitcoin dock's order:
/// Receive on the left, Send on the right, search in the square.
///
/// RECEIVE is live. The dollar token is a first-class Orchestra asset,
/// so the same reusable deposit address the Bitcoin screen mints for a
/// cross-asset receive can be minted pointed at the dollar balance
/// instead: the user picks which coin the money is coming in as —
/// bitcoin included, it is an ordinary source here — and Orchestra
/// converts it on the way in. The picked coin's own deposit address is
/// what the QR shows; the dollars land on the wallet's Spark address.
///
/// SEND IS LIVE, through [UsdSendScreen] — its OWN screen, not the
/// Bitcoin send stepper. The three things that kept this button null
/// were all properties of `confirm_send.dart`, so the fix was to stop
/// going through it:
///
///  1. THE AMOUNT IS ONE INT OF SATOSHIS. `SendTx.amount` is the single
///     amount that stepper, its PSBT builder and every fee provider
///     read. The dollar send never writes `SendTx` at all: it parses the
///     typed string straight into six-decimal base units and keeps a
///     `BigInt` all the way to the SDK, so no price is consulted and no
///     `usd → sats → usd` round trip exists.
///  2. THE STEPPER SPENDS BITCOIN. Its cross-asset path pays out of the
///     bitcoin balance. The dollar screen imports no bitcoin dispatcher,
///     so there is nothing to fall back to: every failure ends in an
///     error on screen with the dollar balance untouched.
///  3. THERE WAS NO DOLLARS-ANCHORED SEND TABLE. `sendChainsFor` walks
///     the catalog out of the `sparkBtc` anchor row only.
///     `usdSendDestinations` (orchestra_usd_send_routes.dart) walks it
///     out of the DOLLAR row instead, live catalogue only, clipped to
///     the chains whose addresses the app can check.
///
/// The rail underneath is the one the venue deposits already proved:
/// `HotSettlement.prepareSpark` takes the token identifier from the
/// verified quote's own source asset and holds the SDK's echo to it by
/// equality, so a dollar send is a dollar payment or it is no payment.
///
/// Neither verb may ever point at the Predictions dollar pool: that is
/// a different account with a different balance, and it is on screen
/// nowhere here.
class UsdAccountActionBar extends ConsumerWidget {
  const UsdAccountActionBar({super.key, this.onHeightChanged});

  final ValueChanged<double>? onHeightChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => KuteBottomActionBar(
        source: kUsdSurfaceSource,
        onHeightChanged: onHeightChanged,
        actions: [
          KuteDockAction(
            icon: Icons.south_west_rounded,
            label: context.l10n.receive,
            trackingId: 'receive',
            // `usd_receive_opened` fires once from the screen's initState.
            onTap: () => context.pushNamed('receiveDollars'),
          ),
          KuteDockAction(
            icon: Icons.north_east_rounded,
            label: context.l10n.send,
            trackingId: 'send',
            // `usd_send_opened` fires once from the screen's initState.
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const UsdSendScreen(),
                ),
              );
            },
          ),
        ],
        // Search is this account's activity, the dollar rows included:
        // the spending wallet's own transaction scope.
        onSearch: () => showKuteSearch(
          context,
          source: kUsdSurfaceSource,
          walletId: pickSpendingWallet(ref.read(settingsProvider))?.id,
        ),
      );
}

/// Opens the Dollars tab's activity for a deep link or a shortcut. Kept next
/// to the screen so callers don't re-derive the route name.
void trackUsdTabOpened(String source) {
  TrackingService.track('usd_tab_opened', params: {'source': source});
}
