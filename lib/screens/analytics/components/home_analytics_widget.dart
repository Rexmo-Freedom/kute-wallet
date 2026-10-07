import 'package:kute/providers/polymarket_combos_provider.dart'
    show polymarketCombosValueProvider;
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/providers/bitcoin_coins_display_provider.dart';
import 'package:kute/screens/shared/bitcoin_labels.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kute/helpers/extension.dart';
import 'package:kute/models/datetime_range_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/analytics/components/bitcoin_price_chart.dart';
import 'package:kute/screens/analytics/components/analytics_card.dart';
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/analytics/components/chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/analytics/components/fee_chart.dart';
import 'package:kute/screens/analytics/components/utxo_map.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shimmer/shimmer.dart'; // REQUIRED: Add shimmer to pubspec.yaml

enum AnalyticsTab {
  /// What a balance has PAID over time. Only the Dollars tab offers it,
  /// via [HomeAnalyticsWidget.earnChild]: the dollar rewards programme
  /// pays on the whole balance, so Earn is a view of this same money and
  /// not a destination of its own.
  earn,
  activity,
  balance,
  valuation,

  /// Where the money went and where it came from, all time, as a donut.
  /// Only Home (the spending wallet) and Dollars offer it, via
  /// [HomeAnalyticsWidget.breakdownChild].
  breakdown,
  price,
  utxo,
  allocation,
  fees
}

class HomeAnalyticsWidget extends ConsumerStatefulWidget {
  /// When true, the Split (allocation) tab is shown. Home keeps it
  /// hidden — the always-BTC architecture means a Home user only
  /// ever has BTC + dust, so a pie chart is misleading. The
  /// Portfolio screen sets this true since it shows the full
  /// cross-wallet breakdown (BTC per wallet + dust line), which IS
  /// a real split worth visualising.
  final bool showSplit;

  /// When true, ONLY the Split tab renders — no Price / UTXOs /
  /// Fees / Valuation tabs and no tab selector at all. Portfolio
  /// passes this so its analytics surface is a pure portfolio
  /// breakdown widget without the carousel-style tab strip that
  /// Home uses. Implies [showSplit].
  final bool onlySplit;

  /// When true, the Fees tab is included in the tab strip. Home and
  /// the spending wallet detail leave this off because fees are a
  /// global cross-flow stat — Polymarket taker, Orchestra spread,
  /// BTC chain fees etc. all roll up into one
  /// place. Portfolio sets this true so users see the breakdown
  /// alongside the allocation pie.
  final bool includeFees;

  /// When non-null, an "Activity" tab leads the strip and renders this
  /// widget (the caller's transaction list, pre-resolved for its own
  /// skeleton/empty states). Home and the wallet detail pass it so the
  /// Activity list and the charts live behind ONE pill strip (user
  /// decision) instead of stacking as separate sections. Portfolio
  /// modes never see it (their tab lists are hardcoded).
  final Widget? activityChild;

  /// When non-null, the Balance tab renders this instead of the shared
  /// bitcoin balance chart. Same shape as [activityChild]: the caller
  /// owns the content, the strip owns the pills. The Dollars tab passes
  /// its own balance-over-time chart — the tab strip there is a dollar
  /// account's, so falling through to the bitcoin series showed the
  /// wrong money entirely.
  final Widget? valuationChild;

  /// When non-null, an "Earn" tab LEADS the strip and renders this.
  /// Only the Dollars tab passes it, and only alongside
  /// [activityAndBalanceOnly]: the earnings series is a sibling of the
  /// balance series, drawn in the same card by the same chart engine.
  final Widget? earnChild;

  /// When non-null, a "Breakdown" tab follows Balance and renders this:
  /// the money in and out of the account by kind, all time. Home passes
  /// it for the spending wallet and Dollars for the dollar account; no
  /// hardware, Ledger, watch-only or on-chain wallet ever does.
  final Widget? breakdownChild;

  /// When false the Price tab is left out. Home passes false (owner
  /// decision: no price chart on the main screen); the other wallets'
  /// screens keep it.
  final bool showPrice;

  /// When true the strip is the caller's own short strip — Activity and
  /// Balance, led by Earn when [earnChild] is passed — whatever the
  /// scope filters would otherwise allow. The Dollars tab passes it: a
  /// cash account has no price chart and no coins map, so Price / Coins
  /// Tapping Activity while Activity is already showing. The pill
  /// relabels itself to "See all" in that state, because the preview is
  /// capped at four rows and tapping the pill again is the obvious way
  /// to ask for the rest. Null leaves the pill inert once selected,
  /// which is what every surface did before.
  final VoidCallback? onSeeAllActivity;

  /// / Split would be dead pills. Requires [activityChild]; ignored by
  /// the Portfolio modes, which hardcode their own tab lists.
  final bool activityAndBalanceOnly;

  /// Categorical analytics surface ('home' | 'wallet_detail' | 'usd' |
  /// 'portfolio'). Null infers it from the mode flags; Home passes it
  /// explicitly because Home and a wallet tab share the same flags.
  final String? surface;

  /// When false (the default) the Balance tab draws no headline figure
  /// above its plot (owner decision): the balance is the hero figure at
  /// the top of home and of the wallet screen, and a touched moment is
  /// written on the chart's own scrub card. The Price tab keeps its
  /// headline either way.
  final bool showBalanceHeadline;

  const HomeAnalyticsWidget({
    super.key,
    this.surface,
    this.showBalanceHeadline = false,
    this.showSplit = false,
    this.onlySplit = false,
    this.includeFees = false,
    this.activityChild,
    this.valuationChild,
    this.earnChild,
    this.breakdownChild,
    this.showPrice = true,
    this.activityAndBalanceOnly = false,
    this.onSeeAllActivity,
  });

  @override
  ConsumerState<HomeAnalyticsWidget> createState() =>
      _HomeAnalyticsWidgetState();
}

class _HomeAnalyticsWidgetState extends ConsumerState<HomeAnalyticsWidget> {
  AnalyticsTab _selectedTab = AnalyticsTab.valuation;

  @override
  void initState() {
    super.initState();
    // Earn leads where it is offered (owner decision): on the dollar
    // balance the programme is what the screen is for, so the strip
    // opens on it rather than on the ledger.
    if (widget.earnChild != null) {
      _selectedTab = AnalyticsTab.earn;
    } else if (widget.activityChild != null) {
      // Activity is the landing tab everywhere else — the list is the
      // primary content, the charts are the drill-down.
      _selectedTab = AnalyticsTab.activity;
    }
  }

  String get _surface =>
      widget.surface ??
      (widget.onlySplit || (widget.showSplit && widget.includeFees)
          ? 'portfolio'
          : widget.activityAndBalanceOnly
              ? 'usd'
              : 'wallet_detail');

  void _onTabSelected(AnalyticsTab tab) {
    if (tab == _selectedTab) return;
    HapticFeedback.selectionClick();
    // User taps only — the scope fallback below re-selects silently.
    TrackingService.track('analytics_tab_selected', params: {
      'tab': tab.name,
      'from_tab': _selectedTab.name,
      'surface': _surface,
    });
    setState(() => _selectedTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    // Analytics tabs follow the *viewed* wallet — the carousel page
    // determines which analytics make sense to show, so a swipe to
    // a savings page should immediately reveal/hide the right tabs
    // without waiting for the 250 ms `activeWalletId` debounce.
    // Falls back to the active wallet when viewed isn't yet set.
    final viewedWallet = ref.watch(viewedWalletProvider);
    final activeWallet =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    final wallet = viewedWallet ?? activeWallet;
    // A true Spark wallet is a hot wallet (not hardware, not watch-only)
    final isHardwareOrWatchOnly = (wallet?.usesBdk ?? false);
    final isSpark = wallet?.isSparkWallet ?? false;

    // Carousel scope drives which tabs make sense.
    //   - 'all'           → Balance + Split + Fees     (no Price)
    //   - 'spending-btc'  → Balance + Price + Split + Fees
    //   - 'spending-usdc' → Balance + Split + Fees     (no Price)
    //   - per-wallet      → Balance + Price + Split + UTXOs + Fees
    //   - null (default)  → original wallet-type-based filter
    //
    // Split (allocation) is visible on every scope — for single-
    // asset scopes it just renders one slice, but the user
    // explicitly asked it not to disappear.
    final isAllScope = ref.watch(isAllAccountsScopeProvider);
    final isBtcScope = ref.watch(isBtcOnlyScopeProvider);
    final isUsdcScope = ref.watch(isUsdcOnlyScopeProvider);
    // Portfolio override — `onlySplit` collapses the tab list to
    // just the allocation Split. No tab strip rendered (see the
    // build below). Skipping the per-scope filter logic since
    // there's only one tab anyway.
    //
    // Portfolio's other mode (`showSplit && includeFees`) is a
    // fixed two-tab list: Split + Fees. Portfolio is a cross-wallet
    // surface, so per-wallet scope filters (e.g. "drop Split when
    // active wallet is hardware") must NOT apply here — otherwise
    // a user parked on a hardware wallet sees only Fees on the
    // Portfolio, which is the bug.
    final List<AnalyticsTab> tabs;
    if (widget.onlySplit) {
      tabs = const [AnalyticsTab.allocation];
    } else if (widget.activityAndBalanceOnly && widget.activityChild != null) {
      // The short strip: what the balance has earned, then the list the
      // caller passed, then the balance over time. Same pills, same
      // switching, no scope filtering. Earn leads when it is offered.
      tabs = [
        if (widget.earnChild != null) AnalyticsTab.earn,
        AnalyticsTab.activity,
        AnalyticsTab.valuation,
        if (widget.breakdownChild != null) AnalyticsTab.breakdown,
      ];
    } else if (widget.showSplit && widget.includeFees) {
      tabs = const [AnalyticsTab.allocation, AnalyticsTab.fees];
    } else {
      tabs = AnalyticsTab.values.where((t) {
        if (t == AnalyticsTab.activity) return widget.activityChild != null;
        // Earn only ever rides the short strip above.
        if (t == AnalyticsTab.earn) return false;
        if (t == AnalyticsTab.balance) return false; // legacy
        // Breakdown is the caller's own child; Price is opt-out.
        if (t == AnalyticsTab.breakdown) return widget.breakdownChild != null;
        if (t == AnalyticsTab.price && !widget.showPrice) return false;
        // Split is opt-in via the `showSplit` constructor flag. Home
        // (the default) hides it because the always-BTC model means
        // there's only one asset to "split". Portfolio passes
        // showSplit: true since it visualises the cross-wallet
        // breakdown (BTC per wallet + dust) which IS a real split.
        if (t == AnalyticsTab.allocation && !widget.showSplit) return false;
        // Fees is a global cross-flow stat (Polymarket taker, Orchestra
        // spread, BTC chain). Surfaced ONLY when
        // the caller opts in via `includeFees` — Portfolio passes
        // true, Home/wallet-detail leave it off so the spending
        // wallet's tab strip doesn't carry it.
        if (t == AnalyticsTab.fees && !widget.includeFees) return false;
        // Portfolio mode (showSplit + includeFees) is Split + Fees
        // only. Balance/Price/UTXOs are per-wallet surfaces and
        // don't belong on the cross-wallet portfolio.
        if (widget.showSplit && widget.includeFees) {
          if (t == AnalyticsTab.valuation) return false;
          if (t == AnalyticsTab.price) return false;
          if (t == AnalyticsTab.utxo) return false;
        }
        if (isAllScope) {
          return t != AnalyticsTab.price && t != AnalyticsTab.utxo;
        }
        if (isBtcScope) {
          return t != AnalyticsTab.utxo;
        }
        if (isUsdcScope) {
          return t != AnalyticsTab.price && t != AnalyticsTab.utxo;
        }
        // Default per-wallet scope (active wallet, no carousel filter).
        if ((isSpark || wallet == null || wallet.isSigner) &&
            t == AnalyticsTab.utxo) {
          return false;
        }
        // Hardware / watch-only wallets only hold a single asset
        // (on-chain BTC), so the allocation pie has nothing to split
        // — drop the Split tab on those pages.
        if (isHardwareOrWatchOnly && t == AnalyticsTab.allocation) {
          return false;
        }
        return true;
      }).toList();
    }
    // If the previously-selected tab was filtered out (e.g. user
    // was on Price then swiped to All), drop back to a valid one.
    // Portfolio mode (showSplit + includeFees, no Balance/Price)
    // defaults to the allocation pie; everything else defaults to
    // valuation (Balance).
    if (!tabs.contains(_selectedTab)) {
      // Portfolio mode (Split + Fees only) defaults to allocation;
      // everything else defaults to valuation.
      final fallback =
          (widget.onlySplit || (widget.showSplit && widget.includeFees))
              ? AnalyticsTab.allocation
              : widget.activityChild != null
                  ? AnalyticsTab.activity
                  : AnalyticsTab.valuation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedTab = fallback);
      });
    }

    final showingActivity =
        _selectedTab == AnalyticsTab.activity && widget.activityChild != null;
    final showingValuationChild =
        _selectedTab == AnalyticsTab.valuation && widget.valuationChild != null;
    final showingEarnChild =
        _selectedTab == AnalyticsTab.earn && widget.earnChild != null;
    final showingBreakdownChild =
        _selectedTab == AnalyticsTab.breakdown && widget.breakdownChild != null;
    return Padding(
      // Horizontal padding moves onto the strip/charts individually:
      // the Activity list carries its own row insets (it used to sit
      // directly in the Home column) and double-padding squeezed it.
      padding: EdgeInsets.symmetric(vertical: 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab strip suppressed for `onlySplit` (Portfolio) and for any
          // other single-tab list — one tab doesn't need a selector and
          // a one-pill segment reads like dead UI. Other surfaces (Home
          // / wallet detail) keep the strip because they have multiple
          // tabs.
          if (!widget.onlySplit && tabs.length > 1)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: _buildTypeSelector(tabs),
            ),
          if (showingActivity)
            widget.activityChild!
          else
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: showingEarnChild
                  ? widget.earnChild!
                  : showingBreakdownChild
                      ? widget.breakdownChild!
                      : showingValuationChild
                          ? widget.valuationChild!
                          : _InternalAnalyticsView(
                              currentTab: _selectedTab,
                              surface: _surface,
                              showBalanceHeadline: widget.showBalanceHeadline,
                            ),
            ),
        ],
      ),
    );
  }

  /// The tab strip is the shared [KutePillTabs] row (same chrome as
  /// the category pills on the Predictions and Investing screens, user
  /// decision). Three tabs (Home: Activity/Balance/Breakdown) share the
  /// width; hardware wallets add Coins and the strip side-scrolls.
  Widget _buildTypeSelector(List<AnalyticsTab> tabs) {
    return KutePillTabs(
      items: [for (final t in tabs) _pillItem(t)],
      selectedIndex: tabs.indexOf(_selectedTab),
      onTap: (i) {
        final tapped = tabs[i];
        final seeAll = widget.onSeeAllActivity;
        if (tapped == AnalyticsTab.activity &&
            _selectedTab == AnalyticsTab.activity &&
            seeAll != null) {
          seeAll();
          return;
        }
        _onTabSelected(tapped);
      },
    );
  }

  KutePillItem _pillItem(AnalyticsTab tab) {
    switch (tab) {
      case AnalyticsTab.earn:
        return KutePillItem(
          label: context.l10n.usdEarnTitle,
          icon: Icons.auto_graph_rounded,
        );
      case AnalyticsTab.activity:
        // Already showing it: the pill stops naming the tab and starts
        // naming what a second tap does.
        final seeAll = _selectedTab == AnalyticsTab.activity &&
            widget.onSeeAllActivity != null;
        return KutePillItem(
          label: seeAll ? context.l10n.seeAll : context.l10n.activity,
          icon:
              seeAll ? Icons.arrow_forward_rounded : Icons.receipt_long_rounded,
        );
      case AnalyticsTab.balance:
      case AnalyticsTab.valuation:
        // Spending balance over time → piggy bank reads as "savings/
        // balance" without the asset-specific connotation a BTC mark
        // would carry. Both legacy enum cases map here so existing
        // settings/tracking keep working.
        return KutePillItem(
          label: context.l10n.balance,
          icon: Icons.savings_rounded,
        );
      case AnalyticsTab.breakdown:
        return KutePillItem(
          label: context.l10n.analyticsBreakdownTab,
          icon: Icons.donut_large_rounded,
        );
      case AnalyticsTab.price:
        return KutePillItem(
          label: context.l10n.price2,
          icon: Icons.show_chart_rounded,
        );
      case AnalyticsTab.utxo:
        return KutePillItem(
          label: context.l10n.activityUtxos,
          icon: Icons.scatter_plot_rounded,
        );
      case AnalyticsTab.allocation:
        return KutePillItem(
          label: context.l10n.split,
          icon: Icons.pie_chart_rounded,
        );
      case AnalyticsTab.fees:
        return KutePillItem(
          label: context.l10n.fees,
          icon: Icons.percent_rounded,
        );
    }
  }
}

/// Translates a date-range label ('7D', 'ALL', …) into the shared
/// [dateTimeSelectProvider] window every analytics chart reads. Shared
/// so a second chart surface (the Dollars tab's balance chart) drives
/// the same window with the same rules instead of a copy of them.
void applyAnalyticsDateRange(WidgetRef ref, String range) {
  final now = DateTime.now();
  final today = _dateOnly(now);
  // Use end-of-day so today's transactions are included in all analytics
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
  DateTime start;
  switch (range) {
    // 24H is rendered by the hourly-mode chart (selectedDays length
    // <= 2 triggers the swap). Setting start = today - 1 day gives
    // the chart a two-day window so the hourly path activates.
    case '24H':
      start = today.subtract(const Duration(days: 1));
      break;
    case '7D':
      start = today.subtract(const Duration(days: 6));
      break;
    case '1M':
      start = today.subtract(const Duration(days: 29));
      break;
    case '3M':
      start = today.subtract(const Duration(days: 89));
      break;
    case '1Y':
      start = today.subtract(const Duration(days: 364));
      break;
    case 'ALL':
      // Span from the user's first transaction. Previously fell
      // back to "5 years ago" when no transactions were known yet,
      // which painted a wide flat-zero history that read as
      // broken. Anchor on the earliest activity instead, and clamp
      // to a 1-day minimum so the chart has at least two points to
      // draw a line between (a single same-day point renders as a
      // dot and reads as broken too).
      final ts = ref.read(transactionNotifierProvider).earliestTimestamp;
      if (ts != null) {
        final earliestDay = _dateOnly(ts);
        start = today.difference(earliestDay).inDays < 1
            ? today.subtract(const Duration(days: 1))
            : earliestDay;
      } else {
        start = today.subtract(const Duration(days: 1));
      }
      break;
    default:
      start = today.subtract(const Duration(days: 29));
  }
  ref
      .read(dateTimeSelectProvider.notifier)
      .update(DateTimeSelect(start: start, end: endOfDay));
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Reconstructs the user's Spark BTC balance (in sats) at timestamp
/// [t] by walking the Spark transaction history backwards from
/// [currentSats]. For every tx that happened AFTER [t], we reverse
/// its effect: a received tx after t means we had less back then; a
/// sent tx after t means we had more back then.
///
/// Used by the analytics 24H chart and the home Spending card
/// sparkline so the line reads as "real wallet value over time"
/// instead of "current holdings projected backwards against
/// historical price". Fees are folded into Breez's `amount` so we
/// don't need to add them separately.
int _sparkSatsAt(DateTime t, int currentSats, List<SparkTransaction> txs) {
  int delta = 0;
  for (final tx in txs) {
    if (!tx.timestamp.isAfter(t)) continue;
    final amt = tx.amount.toInt();
    if (tx.type == TransactionType.received) {
      delta += amt;
    } else {
      delta -= amt;
    }
  }
  final reconstructed = currentSats - delta;
  return reconstructed < 0 ? 0 : reconstructed;
}

/// Same reconstruction as `_sparkSatsAt` but for the on-chain BTC tx
/// list — used by hardware / watch-only wallets where Spark txs are
/// empty and the wallet's history lives on the public chain. Without
/// this the analytics chart for those wallets just plotted
/// `currentBalance × historical price`, missing the user's actual
/// receives + sends over the window.
int _onChainBtcSatsAtAnalytics(
    DateTime t, int currentSats, List<BitcoinTransaction> txs) {
  int delta = 0;
  for (final tx in txs) {
    if (!tx.timestamp.isAfter(t)) continue;
    final amt = tx.amount.toInt();
    if (tx.type == TransactionType.received) {
      delta += amt;
    } else {
      delta -= amt;
    }
  }
  final reconstructed = currentSats - delta;
  return reconstructed < 0 ? 0 : reconstructed;
}

// FRONT: INTERNAL ANALYTICS (Standard Size)
class _InternalAnalyticsView extends ConsumerStatefulWidget {
  final AnalyticsTab currentTab;
  final String surface;
  final bool showBalanceHeadline;
  const _InternalAnalyticsView({
    required this.currentTab,
    required this.surface,
    this.showBalanceHeadline = false,
  });

  @override
  ConsumerState<_InternalAnalyticsView> createState() =>
      _InternalAnalyticsViewState();
}

class _InternalAnalyticsViewState
    extends ConsumerState<_InternalAnalyticsView> {
  String _selectedRange = '7D';

  /// The live views' latest figure for the headline (LIVE streams its
  /// value up; a scrub never does: the scrub card carries that point).
  double? _scrubValue;
  DateTime? _scrubDate;

  /// Bumped when the range already shown is tapped again: a zoomed chart
  /// goes back to the whole range.
  int _viewReset = 0;

  /// Error states already reported this mount, keyed by chart surface, so
  /// a rebuild or a provider re-emit of the same error never re-fires.
  final Set<String> _reportedErrors = {};

  /// `home_error_state_shown`, once per mount per [surface]. Deferred to
  /// after the frame: it is reached from an AsyncValue error builder.
  void _reportErrorState(String surface, Object error) {
    if (!_reportedErrors.add(surface)) return;
    final category = TrackingService.errorCategory(error);
    final screen = widget.surface;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.track('home_error_state_shown', params: {
        'surface': surface,
        'screen': screen,
        'error_category': category,
      });
    });
  }

  @override
  void didUpdateWidget(covariant _InternalAnalyticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A scrub must not survive a tab switch — the headline would show
    // a stale point from the previous chart.
    if (oldWidget.currentTab != widget.currentTab &&
        (_scrubValue != null || _scrubDate != null)) {
      _scrubValue = null;
      _scrubDate = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateDateRangeProvider(_selectedRange);
    });
  }

  void _updateDateRangeProvider(String range) =>
      applyAnalyticsDateRange(ref, range);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (btcFormat, currency) =
        ref.watch(settingsProvider.select((s) => (s.btcFormat, s.currency)));
    final marketDataAsync = ref.watch(filteredBitcoinMarketDataProvider);
    final selectedDays = ref.watch(selectedDaysDateArrayProvider);
    final tab = widget.currentTab;
    // Read inventory only while Coins is visible. Tracked addresses use
    // their explorer feed; descriptor wallets use the native BDK snapshot.
    // Spark and signer accounts never open either inventory from this tab.
    final utxosAsync = tab == AnalyticsTab.utxo
        ? ref.watch(bitcoinCoinsDisplayProvider)
        : const AsyncValue<List<LocalOutput>>.data([]);

    // Total-balance overlay for the valuation tab: pull the current
    // Stables sub-balance (USDB + USDC.e in the Polymarket Safe)
    // ONLY when the active wallet is the hot Spark wallet, since
    // those balances physically live there. Hardware / watch-only /
    // external-address / signer wallets see only their on-chain BTC.
    // Active Predictions are excluded from the total regardless of
    // wallet type — claimable positions, not spendable balance.
    // Display-side balance — viewed wallet so the analytics tab
    // reacts to a swipe immediately. Same `isSpending` derivation as
    // before, just resolved against the viewed wallet (with active-
    // wallet fallback for cold start).
    final balanceState = ref.watch(viewedWalletBalanceProvider);
    ref.watch(polymarketBalanceProvider);
    final viewedWalletForActive = ref.watch(viewedWalletProvider);
    final activeWalletFallback =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    final activeWallet = viewedWalletForActive ?? activeWalletFallback;
    final isSpending = activeWallet != null && activeWallet.isSparkWallet;
    final fiatPerBtc = ref.watch(selectedCurrencyProvider(currency)).toDouble();
    ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble();
    // Carousel-driven scope (Phase 16/17): when the user is on
    // page 0 ('all'), sum BTC across every wallet and include USDC.
    // 'spending-btc' / 'spending-usdc' constrain to a single asset.
    // null = follow the active wallet, original behaviour.
    final isAllScope = ref.watch(isAllAccountsScopeProvider);
    final isBtcScope = ref.watch(isBtcOnlyScopeProvider);
    final isUsdcScope = ref.watch(isUsdcOnlyScopeProvider);
    int btcSatsTotal;
    if (isAllScope) {
      // Sum BTC across every wallet using the per-wallet balance
      // cache. Active wallet uses the live state; the rest fall
      // back to the cached snapshot.
      final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
      final activeId =
          ref.watch(settingsProvider.select((s) => s.activeWalletId));
      final cache = ref.watch(walletBalanceCacheProvider);
      var sum = 0;
      for (final w in wallets) {
        if (w.isSigner) continue;
        if (w.id == activeId) {
          sum +=
              balanceState.sparkBitcoinbalance + balanceState.onChainBtcBalance;
        } else {
          final b = cache[w.id];
          if (b != null) sum += b.sparkBitcoinbalance + b.onChainBtcBalance;
        }
      }
      btcSatsTotal = sum;
    } else if (isUsdcScope) {
      btcSatsTotal = 0;
    } else if (isBtcScope) {
      btcSatsTotal = balanceState.sparkBitcoinbalance;
    } else {
      // Active wallet, no scope filter
      btcSatsTotal = isSpending
          ? balanceState.sparkBitcoinbalance
          : balanceState.onChainBtcBalance;
    }
    final btcFiat = (btcSatsTotal / 1e8) * fiatPerBtc;
    // Always-BTC architecture: analytics value surfaces (valuation
    // header + 24h fiat sparkline + daily chart) plot Bitcoin only.
    // Residual USDC ("dust") is shown on the Portfolio Split tab,
    // never blended into the headline number here. Both scope and
    // wallet-type checks are moot — always zero on the home surface.
    const double stablesFiat = 0.0;
    const double nonBtcFiatOffset = 0.0;

    return AnalyticsCard(
      // Fees tab gets more vertical room than other charts because
      // every fee category is rendered as its own row — Bitcoin
      // network, Lightning routing, Polymarket, Uniswap, Orchestra,
      // Kute, plus retired providers' history. With L1 fees from savings
      // wallets now flowing into the same ledger the list reliably
      // exceeds the 400 dp default and the inner Expanded list
      // ends up cramped. Every other tab, Coins included, shares the
      // 400 dp card so the strip reads the same height across tabs.
      height: tab == AnalyticsTab.fees ? 540.h : 400.h,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              child: Column(
                children: [
                  if (_shouldShowValueHeader(tab) &&
                      marketDataAsync is AsyncData)
                    _ValueHeader(
                      scrubValue: _scrubValue,
                      scrubDate: _scrubDate,
                      scrubCounterpart: _computeScrubCounterpart(
                        tab: tab,
                        btcFormat: btcFormat,
                        currency: currency,
                        fiatPerBtc: fiatPerBtc,
                      ),
                      scrubPrimaryOverride: _computeScrubPrimaryValuation(
                        tab: tab,
                        btcFormat: btcFormat,
                      ),
                      tab: tab,
                      btcFormat: btcFormat,
                      currency: currency,
                      c: c,
                      latestValue: _getLatestValue(
                          tab, selectedDays, btcFormat, nonBtcFiatOffset,
                          liveBtcFiat: btcFiat,
                          liveStablesFiat: stablesFiat,
                          liveBtcSatsTotal: btcSatsTotal),
                      // The Balance tab's headline is the balance now, with
                      // no date under it: the chart has no range to date.
                      latestDate: tab == AnalyticsTab.valuation ||
                              selectedDays.isEmpty
                          ? null
                          : selectedDays.last,
                      btcFiat: btcFiat,
                      btcSats: btcSatsTotal,
                      stablesFiat: stablesFiat,
                      // Always-BTC architecture: Home analytics hides
                      // both the Bitcoin and Stables pills. The
                      // headline number is the Bitcoin balance — no
                      // pill labels needed since the entire surface
                      // is BTC-only on Home. The Split tab on the
                      // Portfolio still shows the full breakdown.
                      showBitcoin: false,
                      showStables: false,
                    ),
                  Expanded(
                    child: _buildTabContent(
                      tab: tab,
                      marketDataAsync: marketDataAsync,
                      utxosAsync: utxosAsync,
                      selectedDays: selectedDays,
                      btcFormat: btcFormat,
                      currency: currency,
                      c: c,
                      nonBtcFiatOffset: nonBtcFiatOffset,
                    ),
                  ),
                  // The range row is the Price tab's (and the legacy
                  // views'). The Balance tab shows the whole history, so
                  // it has no row and its chart takes the room.
                  if (tab != AnalyticsTab.utxo &&
                      tab != AnalyticsTab.allocation &&
                      tab != AnalyticsTab.valuation) ...[
                    SizedBox(height: 12.h),
                    HomeDateRangeSelector(
                      selectedRange: _selectedRange,
                      onSelected: (range) {
                        if (range != _selectedRange) {
                          TrackingService.track('analytics_range_selected',
                              params: {
                                'range': range,
                                'from_range': _selectedRange,
                                'tab': tab.name,
                                'surface': widget.surface,
                              });
                        }
                        setState(() {
                          if (range == _selectedRange) _viewReset++;
                          _selectedRange = range;
                        });
                        _updateDateRangeProvider(range);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowValueHeader(AnalyticsTab tab) {
    if (tab == AnalyticsTab.valuation) return widget.showBalanceHeadline;
    return tab == AnalyticsTab.balance || tab == AnalyticsTab.price;
  }

  double? _getLatestValue(
    AnalyticsTab tab,
    List<DateTime> selectedDays,
    String btcFormat,
    double nonBtcFiatOffset, {
    double? liveBtcFiat,
    double? liveStablesFiat,
    int? liveBtcSatsTotal,
  }) {
    // The Balance tab's headline is the live balance, whatever range the
    // Price tab last set.
    if (tab == AnalyticsTab.valuation && liveBtcSatsTotal != null) {
      return btcFormat == 'sats'
          ? liveBtcSatsTotal.toDouble()
          : liveBtcSatsTotal / 1e8;
    }
    if (selectedDays.isEmpty) return null;
    // Use the already-watched marketDataAsync from build() to avoid redundant reads
    final marketDataAsync = ref.read(filteredBitcoinMarketDataProvider);
    if (tab == AnalyticsTab.balance) {
      // Balance tab uses BTC native units. Prefer the live scope-
      // aware sat total computed in build() so the header tracks the
      // home card exactly; fall back to the historical daily snapshot.
      if (liveBtcSatsTotal != null) {
        return btcFormat == 'sats'
            ? liveBtcSatsTotal.toDouble()
            : liveBtcSatsTotal / 1e8;
      }
      final balanceByDay = ref.read(bitcoinBalanceInFormatByDayProvider);
      final lastDay = _dateOnly(selectedDays.last);
      return balanceByDay[lastDay]?.toDouble();
    } else if (tab == AnalyticsTab.valuation) {
      // Bitcoin-hero hierarchy: the Balance / Valuation header
      // leads with sats/BTC (matching the user's btcFormat setting)
      // and shows the fiat counterpart as the small secondary line
      // via `_secondaryValue`. Mirrors the balance branch above so
      // the scope-aware sat total drives the headline directly.
      if (liveBtcSatsTotal != null) {
        return btcFormat == 'sats'
            ? liveBtcSatsTotal.toDouble()
            : liveBtcSatsTotal / 1e8;
      }
      final balanceByDay = ref.read(bitcoinBalanceInFormatByDayProvider);
      final lastDay = _dateOnly(selectedDays.last);
      return balanceByDay[lastDay]?.toDouble();
    } else if (tab == AnalyticsTab.price) {
      return marketDataAsync.whenOrNull(data: (marketData) {
        if (marketData.isEmpty) return null;
        return (marketData.last.price ?? 0).toDouble();
      });
    }
    return null;
  }

  void _onScrubValueChanged(double value, DateTime date) {
    setState(() {
      _scrubValue = value;
      _scrubDate = date;
    });
  }

  /// Bitcoin-quantity primary string for the scrubbed Valuation
  /// headline. The Valuation chart still plots fiat over time (we
  /// preserved that chart chrome) so the chart's scrubValue is a
  /// fiat number, but the headline is Bitcoin-hero — we need to
  /// recover the BTC holding at scrubDay from `balanceByDay`
  /// (forward-filled, same as the chart series construction) and
  /// hand the ready-to-display sats/BTC string back so the header
  /// doesn't try to reinterpret the fiat scrubValue as sats.
  /// Returns null for non-valuation tabs (they self-format) and
  /// when not scrubbing.
  String? _computeScrubPrimaryValuation({
    required AnalyticsTab tab,
    required String btcFormat,
  }) {
    if (tab != AnalyticsTab.valuation) return null;
    if (_scrubValue == null || _scrubDate == null) return null;
    final balanceByDay = ref.read(bitcoinBalanceInFormatByDayProvider);
    final scrubDay = _dateOnly(_scrubDate!);
    num balAtDay = 0;
    final sortedBalDays = balanceByDay.keys.toList()..sort();
    for (final d in sortedBalDays) {
      if (d.isAfter(scrubDay)) break;
      balAtDay = balanceByDay[d] ?? balAtDay;
    }
    final int sats =
        btcFormat == 'sats' ? balAtDay.round() : (balAtDay * 1e8).round();
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
    return '${sats.toFormattedString(btcFormat)} $unit';
  }

  /// Computes the cross-currency counterpart to show under the
  /// scrubbed headline. Resolves the BTC balance on the scrub date
  /// (via the per-day historical balance map) and the BTC price on
  /// that date (via the cached market data), then renders the
  /// OTHER currency from those two:
  ///
  ///   - Balance / Valuation tab → primary is BTC; secondary is fiat
  ///       fiat = historicalBtc × historicalPrice
  ///   - Price tab → primary is fiat; secondary is BTC
  ///       use the user's historical BTC balance directly
  ///
  /// Returns null when not scrubbing or when we don't have the
  /// historical data to compute the counterpart.
  String? _computeScrubCounterpart({
    required AnalyticsTab tab,
    required String btcFormat,
    required String currency,
    required double fiatPerBtc,
  }) {
    if (_scrubValue == null || _scrubDate == null) return null;
    final scrubValue = _scrubValue!;
    final balanceByDay = ref.read(bitcoinBalanceInFormatByDayProvider);
    final marketAsync = ref.read(filteredBitcoinMarketDataProvider);
    final marketData = marketAsync.valueOrNull ?? const [];
    final dailyPrices = <DateTime, num>{
      for (var dp in marketData)
        _dateOnly(dp.date.toLocal()): (dp.price as num?) ?? 0,
    };

    // Forward-fill: pick the most recent price <= scrubDate.
    num priceAtDay = 0;
    final scrubDay = _dateOnly(_scrubDate!);
    final sortedPriceDays = dailyPrices.keys.toList()..sort();
    for (final d in sortedPriceDays) {
      if (d.isAfter(scrubDay)) break;
      priceAtDay = dailyPrices[d] ?? priceAtDay;
    }
    // Forward-fill the balance the same way — balanceByDay stores
    // snapshots on tx days only; non-tx days inherit the prior value.
    num balAtDay = 0;
    final sortedBalDays = balanceByDay.keys.toList()..sort();
    for (final d in sortedBalDays) {
      if (d.isAfter(scrubDay)) break;
      balAtDay = balanceByDay[d] ?? balAtDay;
    }
    final double effectivePrice =
        priceAtDay > 0 ? priceAtDay.toDouble() : fiatPerBtc;

    if (tab == AnalyticsTab.balance) {
      // Primary = sats/BTC at scrubDay (already passed via scrubValue
      // since the Balance chart plots BTC quantity natively);
      // secondary = fiat at scrubDay.
      // Derive fiat from the scrubbed BTC quantity × historical price.
      final btcUnits = btcFormat == 'sats' ? scrubValue / 1e8 : scrubValue;
      final fiatAtDay = btcUnits * effectivePrice;
      if (fiatAtDay <= 0) return null;
      return NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
          .format(fiatAtDay);
    }

    if (tab == AnalyticsTab.valuation) {
      // Valuation chart plots fiat over time but the headline is
      // Bitcoin-hero — so the scrubValue here IS the historical fiat
      // value (= historicalBtc × historicalPrice). Return it directly
      // as the small secondary line; the BTC-quantity primary is
      // resolved separately via `_computeScrubPrimaryValuation` from
      // `balanceByDay`.
      if (scrubValue <= 0) return null;
      return NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
          .format(scrubValue);
    }

    if (tab == AnalyticsTab.price) {
      // Primary = fiat (BTC price) at scrubDay; secondary = BTC quantity
      // at scrubDay. Show the stored balance ONLY when it's non-zero.
      // The earlier fallback that back-derived `scrubValue / effectivePrice`
      // made empty wallets show "1 sats" everywhere the tooltip landed —
      // the tiny non-zero fiat rounded up to 1 sat. If the user
      // genuinely held no BTC that day, hide the secondary line.
      final num btcUnits = balAtDay;
      if (btcUnits <= 0) return null;
      final int sats =
          btcFormat == 'sats' ? btcUnits.round() : (btcUnits * 1e8).round();
      if (sats <= 0) return null;
      final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
      return '${sats.toFormattedString(btcFormat)} $unit';
    }

    return null;
  }

  /// Routes tab content: UTXO, allocation, fees render independently;
  /// balance, valuation, price, trading depend on market data.
  Widget _buildTabContent({
    required AnalyticsTab tab,
    required AsyncValue<List<dynamic>> marketDataAsync,
    required AsyncValue<List<LocalOutput>> utxosAsync,
    required List<DateTime> selectedDays,
    required String btcFormat,
    required String currency,
    required AppColorsExtension c,
    required double nonBtcFiatOffset,
  }) {
    // Tabs that do NOT need market data
    switch (tab) {
      case AnalyticsTab.utxo:
        return utxosAsync.when(
          // A dependency-driven refetch (this wallet's scan just landed)
          // keeps the current list on screen instead of dropping back to
          // the shimmer for every tick.
          skipLoadingOnReload: true,
          data: (utxos) =>
              UtxoListVisualizer(utxos: utxos, btcFormat: btcFormat),
          loading: () => _buildChartShimmer(c),
          error: (e, s) {
            _reportErrorState('analytics_coins', e);
            return _UtxoStateMessage(
                icon: Icons.cloud_off_rounded,
                message: context.l10n.errorLoadingUtxos,
                actionLabel: context.l10n.retry,
                onAction: () {
                  TrackingService.track('home_retry_tapped', params: {
                    'surface': 'analytics_coins',
                    'screen': widget.surface,
                  });
                  // A retry that fails again is a new error to report.
                  _reportedErrors.remove('analytics_coins');
                  ref.invalidate(bitcoinCoinsDisplayProvider);
                });
          },
        );
      case AnalyticsTab.allocation:
        return const _AllocationPieChart();
      case AnalyticsTab.fees:
        return const FeeChart();
      case AnalyticsTab.valuation:
        // The Balance tab: the wallet's whole history, no range (the
        // range row and LIVE are the Price tab's).
        return _BitcoinBalanceHistory(
          currency: currency,
          btcFormat: btcFormat,
          onError: (e) => _reportErrorState('analytics_chart', e),
        );
      default:
        break;
    }

    // LIVE period: stream Binance's BTC/USD trade feed every few
    // hundred ms and recompute the user's fiat balance live to the
    // second. Routed for Balance / Valuation tabs (where the dollar
    // value chart makes sense). The Price tab can layer its own
    // candle / line live view via the upper-right toggle — its
    // standard chart already has the line/candle mode locked, so we
    // just let it fall through to the live painter below.
    if (_selectedRange == 'LIVE' &&
        (tab == AnalyticsTab.balance || tab == AnalyticsTab.valuation)) {
      // Resolve the user's current BTC holdings in sats. We pull the
      // viewed-wallet balance so the live stream tracks whichever
      // wallet the carousel is parked on, and fall back to the
      // active wallet for cold-start.
      final balState = ref.watch(viewedWalletBalanceProvider);
      final btcSatsLive =
          balState.sparkBitcoinbalance + balState.onChainBtcBalance;
      return _LiveBalanceStream(
        btcSats: btcSatsLive,
        currency: currency,
        fiatPerUsd:
            ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble(),
        onValueChanged: _onScrubValueChanged,
      );
    }

    // Hourly mode: when the selected window spans 1-2 calendar days
    // (typically "ALL" on a wallet whose first transaction is today),
    // the daily-keyed chart only has 1-2 points to draw and reads as
    // broken. Fall back to a 24h hourly value chart powered by the
    // same minute-level CoinGecko feed the home sparkline uses.
    if (selectedDays.length <= 2 &&
        (tab == AnalyticsTab.balance || tab == AnalyticsTab.valuation)) {
      return _HourlyValueChart(
        tab: tab,
        currency: currency,
        btcFormat: btcFormat,
        viewResetKey: (_selectedRange, _viewReset),
      );
    }

    // Tabs that need market data (balance, valuation, price, trading)
    return marketDataAsync.when(
      // The venue charts' placeholder: a shimmering line where the line
      // will be.
      loading: () => const SkeletonLineChart(padding: EdgeInsets.zero),
      error: (e, s) {
        _reportErrorState('analytics_chart', e);
        return Center(
            child: Text(context.l10n.errorLoadingData,
                style: TextStyle(color: c.textTertiary)));
      },
      data: (marketData) {
        final dailyPrices = <DateTime, num>{
          for (var dp in marketData)
            _dateOnly(dp.date.toLocal()): (dp.price as num?) ?? 0
        };
        final balanceByDay = ref.watch(bitcoinBalanceInFormatByDayProvider);
        // Always-BTC architecture: the home "Balance" tab (UI label;
        // backed by legacy enum `AnalyticsTab.valuation` since the
        // original `balance` enum is disabled at line 151) plots
        // Bitcoin fiat value ONLY. Stables (Spark USDB + Polymarket
        // Safe USDC.e) used to be folded in here — `bal * price +
        // usdc + usdb` — which made a wallet that swapped BTC→USDC
        // render a misleading "spike-then-drop" line with a +100%
        // chip on top. Portfolio Split is the dedicated surface for
        // the BTC + Stables + Predictions blend; this chart is the
        // BTC-only counterpart. The CoinGecko feed already returns
        // prices in the user's selected currency, so no USD→fiat
        // multiplier is required for `bal * lastKnownPrice`.
        final dailyDollarBalance = <DateTime, num>{};

        num lastKnownPrice = 0;
        if (dailyPrices.isNotEmpty) {
          lastKnownPrice = dailyPrices.values.first;
        }

        for (var day in selectedDays) {
          final normalizedDay = _dateOnly(day);
          num bal = balanceByDay[normalizedDay] ?? 0;
          if (btcFormat == 'sats') bal = bal / 1e8;
          if (dailyPrices.containsKey(normalizedDay)) {
            lastKnownPrice = dailyPrices[normalizedDay]!;
          }
          dailyDollarBalance[normalizedDay] = bal * lastKnownPrice;
        }

        // LIVE on the Price tab: stream Binance trade ticks bucketed
        // into 1-minute candles. The in-progress candle updates every
        // tick (high/low/close grow); when the minute closes a new
        // candle starts. Matches the user's "1-minute dynamic
        // candlestick" spec.
        if (_selectedRange == 'LIVE' && tab == AnalyticsTab.price) {
          return _LivePriceStream(onValueChanged: _onScrubValueChanged);
        }
        return switch (tab) {
          AnalyticsTab.price => BitcoinPriceChart(
              selectedAsset: 'btc',
              viewResetKey: (_selectedRange, _viewReset),
            ),
          _ => Chart(
              selectedDays: selectedDays,
              mainData: tab == AnalyticsTab.balance
                  ? balanceByDay
                  : dailyDollarBalance,
              bitcoinBalanceByDayformatted: balanceByDay,
              dollarBalanceByDay: dailyDollarBalance,
              priceByDay: dailyPrices,
              selectedCurrency: currency,
              isShowingMainData: true,
              isCurrency: tab == AnalyticsTab.valuation,
              btcFormat: btcFormat,
              isBitcoinAsset: true,
              selectedAsset: 'Bitcoin',
              viewResetKey: (_selectedRange, _viewReset),
            ),
        };
      },
    );
  }

  Widget _buildChartShimmer(AppColorsExtension c) {
    return Shimmer.fromColors(
      baseColor: c.surfaceLight,
      highlightColor: c.surfaceLight.withValues(alpha: 0.5),
      child: Container(
          decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(16.r))),
    );
  }
}

/// The Balance tab of a Bitcoin wallet (spending, hardware, watch-only,
/// Ledger): the viewed wallet's sats as the moments they changed, over
/// the whole history, in the unit the headline leads with. The scrub
/// card adds what the touched balance was worth that day.
class _BitcoinBalanceHistory extends ConsumerWidget {
  final String currency;
  final String btcFormat;
  final void Function(Object error) onError;

  const _BitcoinBalanceHistory({
    required this.currency,
    required this.btcFormat,
    required this.onError,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final history = ref.watch(bitcoinBalanceStepsProvider);
    final fiatPerBtc = ref.watch(selectedCurrencyProvider(currency)).toDouble();
    return ref.watch(bitcoinMarketDataProvider).when(
          loading: () => const SkeletonLineChart(padding: EdgeInsets.zero),
          error: (e, s) {
            onError(e);
            return Center(
                child: Text(context.l10n.errorLoadingData,
                    style: TextStyle(color: c.textTertiary)));
          },
          data: (market) {
            // Daily prices, oldest first, already in the display
            // currency. A day before the feed starts takes its first
            // price, as the day-keyed chart did; with no feed at all the
            // live price stands in.
            final days = <DateTime>[];
            final prices = <double>[];
            final sorted = market.where((d) => d.price != null).toList()
              ..sort((a, b) => a.date.compareTo(b.date));
            for (final d in sorted) {
              final day = _dateOnly(d.date.toLocal());
              if (days.isNotEmpty && days.last == day) {
                prices[prices.length - 1] = d.price!.toDouble();
              } else {
                days.add(day);
                prices.add(d.price!.toDouble());
              }
            }
            double priceOn(DateTime t) {
              if (days.isEmpty) return fiatPerBtc;
              final day = _dateOnly(t);
              var lo = 0, hi = days.length - 1, found = 0;
              while (lo <= hi) {
                final mid = (lo + hi) >> 1;
                if (!days[mid].isAfter(day)) {
                  found = mid;
                  lo = mid + 1;
                } else {
                  hi = mid - 1;
                }
              }
              return prices[found];
            }

            final fiat = NumberFormat.simpleCurrency(name: currency);
            final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
            return BalanceHistoryChart(
              history: history,
              format: (sats) =>
                  '${sats.round().toFormattedString(btcFormat)} $unit',
              scaleLabel: (level, step) =>
                  bitcoinScaleLabel(level, step, btcFormat),
              // What the balance was worth that day, as the header's
              // fiat line says it for now.
              detailText: (t, sats) =>
                  sats <= 0 ? null : fiat.format(sats / 1e8 * priceOn(t)),
              trackingChart: 'valuation',
            );
          },
        );
  }
}

/// A level of a bitcoin Balance chart's scale ([level] and [step] in
/// sats), in the app's unit: "10K sats", "0.0001 BTC", "0 sats".
String bitcoinScaleLabel(double level, double step, String btcFormat) {
  if (btcFormat == 'sats') {
    return '${NumberFormat.compact(locale: 'en_US').format(level)} sats';
  }
  if (level == 0) return '0 BTC';
  final btcStep = step / 1e8;
  final decimals = btcStep >= 1
      ? 0
      : (-(math.log(btcStep) / math.ln10).floor()).clamp(0, 8).toInt();
  return '${(level / 1e8).toStringAsFixed(decimals)} BTC';
}

class _ValueHeader extends StatelessWidget {
  final double? scrubValue;
  final DateTime? scrubDate;

  /// Pre-computed counterpart value for the current scrub position
  /// (BTC ↔ fiat conversion at the scrubbed date). Computed in the
  /// parent because it needs access to the historical balance and
  /// price maps that the widget itself shouldn't pull in.
  final String? scrubCounterpart;

  /// Optional pre-formatted primary headline for the scrub position.
  /// Set by the parent on the Valuation tab where the chart trajectory
  /// is in fiat but the headline must render in BTC — the parent
  /// resolves the BTC quantity at scrubDay from `balanceByDay` and
  /// hands a ready-to-display string here, sidestepping the
  /// fiat→sats interpretation that `_formatValue` would otherwise
  /// apply to the chart's raw scrubValue.
  final String? scrubPrimaryOverride;
  final AnalyticsTab tab;
  final String btcFormat;
  final String currency;
  final AppColorsExtension c;
  final double? latestValue;
  final DateTime? latestDate;
  final double btcFiat;

  /// Live total satoshis. Needed so the header can render BTC AND
  /// fiat side by side regardless of which tab's primary metric is
  /// (Balance → sats primary, Valuation/Price → fiat primary).
  final int btcSats;
  final double stablesFiat;
  final bool showStables;

  /// Hide the Bitcoin pill — used in USDC scope where charting BTC
  /// alongside the stablecoin headline is misleading.
  final bool showBitcoin;

  const _ValueHeader({
    required this.scrubValue,
    required this.scrubDate,
    required this.scrubCounterpart,
    required this.tab,
    required this.btcFormat,
    required this.currency,
    required this.c,
    required this.latestValue,
    required this.latestDate,
    required this.btcFiat,
    required this.btcSats,
    required this.stablesFiat,
    required this.showStables,
    this.showBitcoin = true,
    this.scrubPrimaryOverride,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = scrubValue ?? latestValue;
    final displayDate = scrubDate ?? latestDate;
    if (displayValue == null) return const SizedBox.shrink();

    final isScrubbing = scrubValue != null;
    final formattedValue = (isScrubbing && scrubPrimaryOverride != null)
        ? scrubPrimaryOverride!
        : _formatValue(displayValue);
    // The date in the app's language, as the scrub card writes it.
    final formattedDate = displayDate != null
        ? kuteChartDay(displayDate, kuteChartLocale(context))
        : '';

    // Breakdown row stays visible while the user scrubs the chart. The
    // pills represent the live BTC + Stables split; only the headline
    // value + date react to the scrub position.
    final showBreakdown = tab == AnalyticsTab.valuation;

    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline + date are the only thing that swaps on scrub —
          // wrapping just them in the AnimatedSwitcher keeps the
          // breakdown row stable underneath instead of cross-fading
          // every time the user moves their finger across the chart.
          // Cash-register roll per digit while the user scrubs the
          // chart, matching the Polymarket web tooltip. While not
          // scrubbing (background tick updates) the same widget
          // still rolls but with a slower 350 ms duration so it
          // looks like a settle, not a frantic re-roll.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RollingNumberText(
                text: formattedValue,
                duration: Duration(milliseconds: isScrubbing ? 120 : 350),
                dimColor: (tab == AnalyticsTab.balance ||
                        tab == AnalyticsTab.valuation)
                    ? c.textTertiary
                    : null,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              // Cross-currency reference line. Animates with the
              // same RollingNumberText cadence as the primary so a
              // scrub feels coherent — both numbers (sats AND fiat)
              // roll together rather than the primary scrubbing and
              // the secondary jumping or staying static.
              if (_secondaryValue() != null) ...[
                SizedBox(height: 2.h),
                RollingNumberText(
                  text: _secondaryValue()!,
                  duration: Duration(milliseconds: isScrubbing ? 120 : 350),
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (formattedDate.isNotEmpty) ...[
                SizedBox(height: 2.h),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  // accent-contrast: the scrubbed date was painted in the
                  // brand accent (Bitcoin orange) which fails ~4.5:1 on the
                  // card surface. Use textPrimary while scrubbing — still
                  // a clear emphasis vs the resting tertiary, but legible.
                  // Merged into the inherited style so the date keeps the
                  // app's face (a bare style fell back to the system one).
                  style: DefaultTextStyle.of(context).style.merge(TextStyle(
                    color: isScrubbing ? c.textPrimary : c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  )),
                  child: Text(formattedDate),
                ),
              ],
            ],
          ),
          if (showBreakdown && (showBitcoin || showStables)) ...[
            SizedBox(height: 8.h),
            Row(
              children: [
                if (showBitcoin)
                  _BalancePill(
                    label: context.l10n.bitcoin,
                    value: btcFiat,
                    color: const Color(0xFFF7931A),
                    currency: currency,
                    c: c,
                  ),
                if (showBitcoin && showStables) SizedBox(width: 6.w),
                if (showStables)
                  _BalancePill(
                    label: context.l10n.activityStables,
                    value: stablesFiat,
                    color: const Color(0xFF3B82F6),
                    currency: currency,
                    c: c,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatValue(double value) {
    if (tab == AnalyticsTab.price) {
      return NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
          .format(value);
    }
    // Balance / Valuation — analytics surfaces lead with Bitcoin
    // (sats/BTC per the user's btcFormat setting). Fiat shows as
    // the small secondary line via `_secondaryValue` below.
    // Convert back to satoshis for precision-safe formatting.
    final int sats =
        btcFormat == 'sats' ? value.round() : (value * 100000000).round();
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
    return '${sats.toFormattedString(btcFormat)} $unit';
  }

  /// Counterpart-currency string shown below the primary headline.
  ///   - While scrubbing: shows the HISTORICAL counterpart at the
  ///     scrubbed date (parent computes via balance/price maps).
  ///   - Otherwise: shows the LIVE counterpart from current balance.
  String? _secondaryValue() {
    if (scrubValue != null) {
      return scrubCounterpart;
    }
    if (tab == AnalyticsTab.price) {
      if (btcSats <= 0) return null;
      final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
      return '${btcSats.toFormattedString(btcFormat)} $unit';
    }
    // Balance / Valuation — fiat is the secondary line under the
    // sats/BTC headline. Bitcoin-hero hierarchy for analytics
    // surfaces (the headline IS the holding; fiat is reference).
    if (btcFiat <= 0) return null;
    return NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
        .format(btcFiat);
  }
}

/// Compact pill that shows one component of the wallet's total value
/// (Bitcoin / Stables / Predictions) on the valuation tab. Color dot +
/// label + amount, all inline so three of them fit in one row on a
/// narrow phone.
class _BalancePill extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String currency;
  final AppColorsExtension c;

  const _BalancePill({
    required this.label,
    required this.value,
    required this.color,
    required this.currency,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
            .format(value);
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6.w,
                  height: 6.w,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 5.w),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 2.h),
            AnimatedBalance(
              text: formatted,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocationPieChart extends ConsumerWidget {
  const _AllocationPieChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final polyBalance = ref.watch(polymarketBalanceProvider);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));

    // Split chart always shows the *whole portfolio* — sum BTC
    // across every wallet on device regardless of which carousel
    // page is active. The user explicitly asked for hardware-wallet
    // balances to be reflected in Split everywhere, not just on the
    // All page. Stables + Predictions live on the spending wallet
    // (single Polymarket Safe per user) so we read those from the
    // active balanceState — when the carousel is on a hardware
    // page the active wallet is hardware and stables/predictions
    // legitimately drop to 0; when on a spending page they're the
    // hot wallet's. Either way the BTC slice is always all-wallets.
    //
    // Per-wallet breakdown: spending BTC is rolled into a single
    // "Bitcoin (Spending)" slice (there can be only one spending
    // wallet) and every cold/hardware/watch-only/external/tracked
    // wallet becomes its OWN slice labelled by the wallet's name.
    // Signer wallets are excluded — they don't hold funds, they
    // just sign PSBTs.
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
    final activeId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    final cache = ref.watch(walletBalanceCacheProvider);
    // For the ACTIVE wallet, read the live Spark notifier — its cache
    // entry is written-through on every update but `balanceNotifier`
    // is the source of truth and avoids any cache-write race. For
    // every OTHER wallet, read the per-wallet cache entry.
    //
    // Pre-fix bug: this used `viewedWalletBalanceProvider` for the
    // active wallet, which returns the HARDWARE wallet's balance
    // when the user has been inside a wallet-detail screen (the
    // viewed-id stays set after navigating away). That attributed
    // the hardware balance to the spending slice AND counted it
    // again under the hardware slice — Ledger appeared twice and
    // the spending slice was wrong.
    final liveActiveBalance = ref.watch(balanceNotifierProvider);
    int satsFor(WalletConfig w) {
      if (w.id == activeId) {
        return liveActiveBalance.sparkBitcoinbalance +
            liveActiveBalance.onChainBtcBalance;
      }
      final b = cache[w.id];
      if (b == null) return 0;
      return b.sparkBitcoinbalance + b.onChainBtcBalance;
    }

    int spendingSats = 0;
    final perColdWalletSats = <({String name, int sats})>[];
    // Map the wallet-type string to a short brand label so legend
    // rows read as "Ledger" / "Jade" / "Keystone" instead of the
    // verbose user-given wallet name ("My Ledger Nano X Backup #2").
    // Falls back to a Title-cased walletType for unknown brands
    // (including legacy stored types like 'coldcard') and finally to
    // the wallet's name as a last resort.
    String shortLabel(WalletConfig w) {
      final t = w.walletType.toLowerCase();
      switch (t) {
        case 'ledger':
          return 'Ledger';
        case 'jade':
          return 'Jade';
        case 'keystone':
          return 'Keystone';
        case 'krux':
          return 'Krux';
        case 'specter':
          return 'Specter';
        case 'bitcoin_keeper':
        case 'bitcoinkeeper':
          return 'Keeper';
        case 'watch_only':
        case 'watchonly':
          return context.l10n.accountWatchOnly;
        case 'external_address':
        case 'externaladdress':
          return context.l10n.activityTracked;
      }
      if (t.isNotEmpty) {
        return t[0].toUpperCase() + t.substring(1);
      }
      return w.name.isNotEmpty ? w.name : context.l10n.activityBitcoinWallet;
    }

    for (final w in wallets) {
      if (w.isSigner) continue;
      final isSpending = w.isSparkWallet;
      if (isSpending) {
        spendingSats += satsFor(w);
      } else {
        final s = satsFor(w);
        if (s > 0) {
          perColdWalletSats.add((
            name: shortLabel(w),
            sats: s,
          ));
        }
      }
    }
    final btcSats =
        spendingSats + perColdWalletSats.fold<int>(0, (a, b) => a + b.sats);
    final selectedCurrency =
        ref.watch(settingsProvider.select((s) => s.currency));
    final oneBtcInFiat = ref.watch(selectedCurrencyProvider(selectedCurrency));
    final fiatPerBtc = oneBtcInFiat.toDouble();
    final btcFiat = (btcSats / 100000000.0) * fiatPerBtc;

    // Stables (USDC.e in the Polymarket Safe; USDB left with the Earn
    // product). Dollar-pegged — convert to the selected fiat currency
    // via the USD→fiat rate so BTC and stables compare apples to apples.
    final stablesDollars = polyBalance;
    final fiatPerUsd =
        ref.watch(selectedCurrencyProviderFromUSD(selectedCurrency)).toDouble();
    final stablesFiat = stablesDollars * fiatPerUsd;

    // Active predictions value (USD, 1:1 with USDC).
    final positions = ref.watch(polymarketActivePositionsProvider);
    double predictionsDollars = 0;
    for (final p in positions) {
      predictionsDollars += p.size * p.currentPrice;
    }
    // Combos (parlays) are not CLOB positions: their estimate is added once.
    predictionsDollars += ref.watch(polymarketCombosValueProvider);
    final predictionsFiat = predictionsDollars * fiatPerUsd;

    final total = btcFiat + stablesFiat + predictionsFiat;

    if (total <= 0) {
      return Center(
        child: Text(context.l10n.activityNoBalancesYet,
            style: TextStyle(color: c.textTertiary, fontSize: 16.sp)),
      );
    }

    final stablesPct = (stablesFiat / total * 100);
    final predPct = (predictionsFiat / total * 100);

    // Saturated, modern palette inspired by the Polymarket chart
    // accents (vivid green / red / purple) so the pie reads as a
    // proper data viz rather than a muddy brown wash. Each slice has
    // a clearly distinct hue so adjacent wedges separate cleanly on
    // small thumbnails. The previous palette stayed inside the
    // BTC-orange family which produced unreadable cold-wallet wedges
    // (saddle brown / dark amber / burnt orange all blending).
    const btcColor = Color(0xFFF7931A); // canonical Bitcoin orange
    const coldPalette = <Color>[
      Color(0xFFFFB020), // warm gold (Ledger Nano-ish)
      Color(0xFFE76F51), // coral
      Color(0xFFD946EF), // fuchsia (Jade)
      Color(0xFF14B8A6), // teal (BitBox / generic cold)
      Color(0xFFEAB308), // amber-500
    ];
    const stablesColor = Color(0xFF1FA663); // Polymarket green
    const predColor = Color(0xFF8247E5); // Polygon purple

    final sections = <_AllocationEntry>[];
    if (spendingSats > 0) {
      final spendingFiat = (spendingSats / 1e8) * fiatPerBtc;
      final pct = total > 0 ? (spendingFiat / total * 100) : 0.0;
      // Spending wallet always reads as plain "Bitcoin" — the
      // Bitcoin icon next to the row already conveys the asset; an
      // extra "(Spending)" qualifier reads as cheap parenthetical
      // chrome. Cold wallets surface their wallet name directly
      // (e.g. "Ledger Nano", "Jade") so the rows differentiate
      // without the redundant "Bitcoin" prefix.
      sections.add(_AllocationEntry(
        context.l10n.bitcoin,
        pct,
        btcColor,
        spendingSats.toFormattedString(btcFormat),
        btcFormat,
      ));
    }
    for (var i = 0; i < perColdWalletSats.length; i++) {
      final entry = perColdWalletSats[i];
      final coldFiat = (entry.sats / 1e8) * fiatPerBtc;
      final pct = total > 0 ? (coldFiat / total * 100) : 0.0;
      sections.add(_AllocationEntry(
        entry.name,
        pct,
        coldPalette[i % coldPalette.length],
        entry.sats.toFormattedString(btcFormat),
        btcFormat,
      ));
    }
    // Predictions denomination — when bitcoin mode is on, USD-pegged
    // slices (Spendable balance, Open positions) render in sats/BTC
    // instead of dollars. Matches every other Polymarket surface.

    String stableValueStr(double usd) {
      {}
      // Dollar-pegged value → show it in the user's SELECTED display
      // currency (was hardcoded to `$`/USD). `fiatPerUsd` + `selectedCurrency`
      // are already resolved above for the stables conversion.
      return NumberFormat.simpleCurrency(
              name: selectedCurrency, decimalDigits: 2)
          .format(usd * fiatPerUsd);
    }

    final stableUnit = '';
    if (stablesPct > 0) {
      sections.add(_AllocationEntry(
          context.l10n.accountSpendableBalance,
          stablesPct,
          stablesColor,
          stableValueStr(stablesDollars),
          stableUnit));
    }
    if (predPct > 0) {
      sections.add(_AllocationEntry(context.l10n.accountOpenPositions, predPct,
          predColor, stableValueStr(predictionsDollars), stableUnit));
    }

    // Row-based layout: each slice is a horizontal row with the
    // wallet/asset name on the left, the percentage on the right,
    // a smaller value/unit sub-line beneath the label, and a
    // colored linear progress bar spanning the full width below
    // — reads as data viz rather than a stock-chart pie wedge.
    // The colour palette is preserved verbatim from the previous
    // pie wedges so vivid slice hues (BTC orange, gold, coral,
    // fuchsia, teal, amber, Polymarket green, Polygon purple)
    // still carry the legend meaning.
    // Treemap of colored squares — verbatim shape of the UTXO tab's
    // treemap view: each slice becomes a tinted square (0.2 alpha
    // fill + 0.4 alpha border, 6.r corner radius, 1.5 px margin)
    // sized proportionally to its percentage, with the percentage
    // text top-center and the label/value beneath when the square is
    // tall enough. Slice-and-dice layout splits horizontally /
    // vertically based on the current aspect ratio so large slices
    // get wide rects and small slices nest in the leftover space.
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;
        final rects = <_AllocRect>[];
        _layoutAllocTreemap(
          sections: sections,
          x: 0,
          y: 0,
          width: totalW,
          height: totalH,
          rects: rects,
        );
        return Stack(
          children: rects.map((r) {
            final s = r.entry;
            // Smart label visibility:
            //   - very small square → percentage only.
            //   - narrow square → percentage + label, both scaled
            //     via FittedBox so long words ("Spendable balance",
            //     "Open positions") shrink instead of truncating to
            //     "Open posi…".
            //   - large square → also show the value/unit sub-line.
            //
            // FittedBox is the key — it preserves the text intact at
            // a smaller font instead of clipping it. A hard 9.sp
            // floor (via a wrapping `SizedBox(height: 10.h)` per
            // line) keeps the layout sane on tiny rects.
            final showLabel = r.width > 36 && r.height > 28;
            final showValue =
                r.width > 70 && r.height > 60 && s.value.isNotEmpty;
            final unit = s.unit.isNotEmpty ? ' ${s.unit}' : '';
            return Positioned(
              left: r.x,
              top: r.y,
              width: r.width,
              height: r.height,
              child: Container(
                margin: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(
                      color: s.color.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${s.percent.toStringAsFixed(s.percent >= 10 ? 0 : 1)}%',
                            style: TextStyle(
                              color: s.color,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (showLabel) ...[
                          SizedBox(height: 2.h),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              s.label,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ],
                        if (showValue) ...[
                          SizedBox(height: 1.h),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${s.value}$unit',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Treemap rect for a single allocation slice.
class _AllocRect {
  final _AllocationEntry entry;
  final double x, y, width, height;
  const _AllocRect({
    required this.entry,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Slice-and-dice treemap layout — mirrors the UTXO treemap's
/// algorithm. Splits the running rectangle horizontally or
/// vertically based on aspect ratio, then recursively places the
/// two halves.
void _layoutAllocTreemap({
  required List<_AllocationEntry> sections,
  required double x,
  required double y,
  required double width,
  required double height,
  required List<_AllocRect> rects,
}) {
  if (sections.isEmpty || width <= 0 || height <= 0) return;
  if (sections.length == 1) {
    rects.add(_AllocRect(
        entry: sections.first, x: x, y: y, width: width, height: height));
    return;
  }
  final localTotal = sections.fold<double>(0, (sum, s) => sum + s.percent);
  if (localTotal == 0) return;
  final horizontal = width >= height;
  double runningSum = 0;
  int splitIndex = 0;
  final half = localTotal / 2;
  for (int i = 0; i < sections.length - 1; i++) {
    runningSum += sections[i].percent;
    if (runningSum >= half) {
      splitIndex = i + 1;
      break;
    }
  }
  if (splitIndex == 0) splitIndex = 1;
  final firstHalf = sections.sublist(0, splitIndex);
  final secondHalf = sections.sublist(splitIndex);
  final firstTotal = firstHalf.fold<double>(0, (sum, s) => sum + s.percent);
  final ratio = firstTotal / localTotal;
  if (horizontal) {
    final splitW = width * ratio;
    _layoutAllocTreemap(
        sections: firstHalf,
        x: x,
        y: y,
        width: splitW,
        height: height,
        rects: rects);
    _layoutAllocTreemap(
        sections: secondHalf,
        x: x + splitW,
        y: y,
        width: width - splitW,
        height: height,
        rects: rects);
  } else {
    final splitH = height * ratio;
    _layoutAllocTreemap(
        sections: firstHalf,
        x: x,
        y: y,
        width: width,
        height: splitH,
        rects: rects);
    _layoutAllocTreemap(
        sections: secondHalf,
        x: x,
        y: y + splitH,
        width: width,
        height: height - splitH,
        rects: rects);
  }
}

class _AllocationEntry {
  final String label;
  final double percent;
  final Color color;
  final String value;
  final String unit;
  const _AllocationEntry(
      this.label, this.percent, this.color, this.value, this.unit);
}

// ... (Rest of sub-components: HomeDateRangeSelector, UtxoListVisualizer remain same)
/// LIVE sits at the front — leftmost label so it's the first thing the
/// eye lands on. The pre-selected default is still a dated range (set in
/// each parent's `_selectedRange` field), so users only get the
/// streaming view when they pick it explicitly.
const List<String> kHomeDateRanges = [
  'LIVE',
  '24H',
  '7D',
  '1M',
  '3M',
  '1Y',
  'ALL'
];

/// The date-range row under the analytics charts: the range pills every
/// chart shares ([KuteRangePills], the Predictions chart's row), with the
/// LIVE range marked by its dot.
class HomeDateRangeSelector extends StatelessWidget {
  final String selectedRange;

  /// Called with the range tapped, the selected one included (the chart
  /// then goes back to the whole range).
  final Function(String) onSelected;

  /// The labels to offer. Defaults to [kHomeDateRanges]; the Dollars
  /// tab passes a list without LIVE, whose streaming view is a bitcoin
  /// price feed a cash balance has no use for.
  final List<String> ranges;

  const HomeDateRangeSelector({
    super.key,
    required this.selectedRange,
    required this.onSelected,
    this.ranges = kHomeDateRanges,
  });

  @override
  Widget build(BuildContext context) {
    return KuteRangePills(
      labels: ranges,
      selectedIndex: ranges.indexOf(selectedRange),
      onSelected: (i) => onSelected(ranges[i]),
      leadingFor: (i, selected) =>
          ranges[i] == 'LIVE' ? _LiveDot(active: selected) : null,
    );
  }
}

/// The LIVE indicator pulses only while the live range is selected.
class _LiveDot extends StatefulWidget {
  final bool active;
  const _LiveDot({required this.active});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Decorative attention-pulse. Honour Reduce Motion: don't loop the
    // pulse (and stop it if it's already running) when the OS asks for
    // reduced animation. The dot still renders at full opacity.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion || !widget.active) {
      if (_ctrl.isAnimating) _ctrl.stop();
      _ctrl.value = 1.0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = _ctrl.value;
        return Container(
          width: 7.sp,
          height: 7.sp,
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.4 + 0.6 * v),
            shape: BoxShape.circle,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.5 * v),
                      blurRadius: 4 + 4 * v,
                      spreadRadius: 0.4,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class UtxoListVisualizer extends ConsumerStatefulWidget {
  final List<LocalOutput> utxos;
  final String btcFormat;
  const UtxoListVisualizer(
      {super.key, required this.utxos, required this.btcFormat});

  @override
  ConsumerState<UtxoListVisualizer> createState() => _UtxoListVisualizerState();
}

class _UtxoListVisualizerState extends ConsumerState<UtxoListVisualizer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(bitcoinLabelsWalletIdProvider);
    final labels = owner == null
        ? <String, String>{}
        : ref.watch(bitcoinLabelsProvider(owner));
    final utxos = widget.utxos;
    final btcFormat = widget.btcFormat;

    if (utxos.isEmpty) {
      return _UtxoStateMessage(
          icon: Icons.toll_outlined,
          message: context.l10n.noUtxosAvailable,
          hint: context.l10n.coinsEmptyHint);
    }

    final sortedUtxos = List<LocalOutput>.from(utxos)
      ..sort((a, b) => b.txout.value.toSat().compareTo(a.txout.value.toSat()));

    final totalSats =
        sortedUtxos.fold<int>(0, (sum, u) => sum + u.txout.value.toSat());

    // No Map/List switch: the map IS the coins view (user decision).
    return Column(
      children: [
        Expanded(
          child: UtxoMap(
            coins: sortedUtxos,
            totalSats: totalSats,
            btcFormat: btcFormat,
            labels: labels,
            onOpenCoin: (coin) => showBitcoinCoinDetails(context, ref, coin),
            onEditLabel: (coin) {
              if (owner == null) return;
              editBitcoinLabel(context, ref,
                  walletId: owner,
                  labelKey: bitcoinCoinLabelKey(coin.outpoint),
                  title: context.l10n.coinLabel,
                  inheritedLabel: labels[bitcoinTransactionLabelKey(
                      coin.outpoint.txid.toString())]);
            },
          ),
        ),
      ],
    );
  }
}

/// Empty and error states for the Coins tab in the app's quiet pattern:
/// tertiary glyph, one line of copy, optional hint and a plain retry.
class _UtxoStateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _UtxoStateMessage({
    required this.icon,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.textTertiary, size: 24.sp),
            SizedBox(height: 12.h),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2)),
            if (hint != null) ...[
              SizedBox(height: 4.h),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.35)),
            ],
            if (actionLabel != null) ...[
              SizedBox(height: 8.h),
              AppTextButton(
                  text: actionLabel!,
                  onPressed: onAction,
                  textColor: c.textPrimary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 24-hour value chart used by the analytics screen when the active
/// window spans 1-2 calendar days (typically a freshly funded wallet
/// on the ALL tab). Plots `current sat balance × hourly BTC price`
/// for the last 24 hours, with the same trend-coloured styling as the
/// daily Chart so users get a continuous visual language across
/// timescales. Reuses [bitcoinMarketDataLast24hProvider] — same feed
/// the home BTC card sparkline reads from.
class _HourlyValueChart extends ConsumerStatefulWidget {
  final AnalyticsTab tab;
  final String currency;
  final String btcFormat;
  final Object? viewResetKey;

  const _HourlyValueChart({
    required this.tab,
    required this.currency,
    required this.btcFormat,
    this.viewResetKey,
  });

  @override
  ConsumerState<_HourlyValueChart> createState() => _HourlyValueChartState();
}

class _HourlyValueChartState extends ConsumerState<_HourlyValueChart> {
  // Entrance/timeframe motion now lives inside the shared KuteLineChart
  // (one-shot fade + ~280ms series morph, Duration.zero under reduce
  // motion) — no local draw-in controller needed.

  /// `home_error_state_shown` once per mount, never per rebuild.
  bool _errorReported = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Viewed wallet so the second analytics surface (Balance tab on
    // the all-accounts portfolio card) follows the carousel page
    // without the activeWalletId debounce delay.
    final balanceState = ref.watch(viewedWalletBalanceProvider);
    final viewedWallet = ref.watch(viewedWalletProvider);
    final activeWalletFallback =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    final activeWallet = viewedWallet ?? activeWalletFallback;
    final isSpending = activeWallet != null && activeWallet.isSparkWallet;
    // BTC source. In all-accounts scope sum every wallet's BTC for
    // the chart's "current" anchor point so the line tops out at
    // the portfolio total. In btc / usdc sub-scopes constrain to
    // that asset; everywhere else fall back to the active wallet
    // (Spark for hot, on-chain for hardware/watch-only).
    final isAllScopeChart = ref.watch(isAllAccountsScopeProvider);
    final isUsdcScopeChart = ref.watch(isUsdcOnlyScopeProvider);
    ref.watch(isBtcOnlyScopeProvider);
    int currentBtcSats;
    if (isAllScopeChart) {
      final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
      final activeId =
          ref.watch(settingsProvider.select((s) => s.activeWalletId));
      final cache = ref.watch(walletBalanceCacheProvider);
      var sum = 0;
      for (final w in wallets) {
        if (w.isSigner) continue;
        if (w.id == activeId) {
          sum +=
              balanceState.sparkBitcoinbalance + balanceState.onChainBtcBalance;
        } else {
          final b = cache[w.id];
          if (b != null) sum += b.sparkBitcoinbalance + b.onChainBtcBalance;
        }
      }
      currentBtcSats = sum;
    } else if (isUsdcScopeChart) {
      currentBtcSats = 0;
    } else {
      currentBtcSats = isSpending
          ? balanceState.sparkBitcoinbalance
          : balanceState.onChainBtcBalance;
    }
    final marketAsync = ref.watch(bitcoinMarketDataLast24hProvider);
    // Always-BTC architecture: the home line chart on the Balance
    // tab plots Bitcoin only. Stables (USDB + Polymarket USDC.e) are
    // dust post-claim and surfaced on the Portfolio Split tab, never
    // blended into the live home balance trajectory. Previously this
    // mixed in `usdcBalanceProvider + usdbBalance` for the spending
    // wallet's chart, which painted a line representing BTC+stables
    // even though the headline balance and breakdown were BTC-only.
    // Same viewed-wallet treatment for the historical-balance walk
    // — pairs with `balanceState` above so both come from the same
    // wallet on every swipe.
    final txState = ref.watch(viewedWalletTransactionsProvider);
    final sparkTxs =
        isSpending ? txState.sparkTransactions : <SparkTransaction>[];
    // Hardware / watch-only wallets — walk on-chain BTC txs so the
    // chart reflects the user's real balance trajectory, not just
    // currentBalance × historical price drift.
    final btcTxs =
        isSpending ? const <BitcoinTransaction>[] : txState.bitcoinTransactions;
    final fiatPerUsd =
        ref.watch(selectedCurrencyProviderFromUSD(widget.currency)).toDouble();
    final usdToFiat = fiatPerUsd > 0 ? fiatPerUsd : 1.0;

    return marketAsync.when(
      loading: () => const SkeletonLineChart(padding: EdgeInsets.zero),
      error: (e, s) {
        if (!_errorReported) {
          _errorReported = true;
          final category = TrackingService.errorCategory(e);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            TrackingService.track('home_error_state_shown', params: {
              'surface': 'analytics_hourly_chart',
              'error_category': category,
            });
          });
        }
        return Center(
          child: Text(context.l10n.errorLoadingData,
              style: TextStyle(color: c.textTertiary, fontSize: 14.sp)),
        );
      },
      data: (market) {
        if (market.length < 2) {
          return Center(
            child: Text(context.l10n.accountNotEnoughDataYet,
                style: TextStyle(color: c.textTertiary, fontSize: 14.sp)),
          );
        }

        final sorted = market.toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        // Downsample CoinGecko's 5-min ticks (~288 points) to ~48 so
        // fl_chart isn't churning through hundreds of segments.
        final step = sorted.length > 48 ? (sorted.length / 48).ceil() : 1;
        final samples = <MapEntry<DateTime, double>>[];
        // Compute the wallet's actual fiat value at timestamp `t` —
        // walks Spark / on-chain BTC history backwards
        // from current balance so the line reflects real moves, not
        // price drift.
        double fiatAt(double priceUsd, DateTime t) {
          final btcAtT = isSpending
              ? _sparkSatsAt(t, currentBtcSats, sparkTxs)
              : _onChainBtcSatsAtAnalytics(t, currentBtcSats, btcTxs);
          return (btcAtT / 1e8) * priceUsd * usdToFiat;
        }

        for (int i = 0; i < sorted.length; i += step) {
          final p = sorted[i].price;
          if (p == null) continue;
          final t = sorted[i].date.toLocal();
          samples.add(MapEntry(t, fiatAt(p.toDouble(), t)));
        }
        if (samples.isEmpty || samples.last.key != sorted.last.date.toLocal()) {
          final lastP = sorted.last.price;
          if (lastP != null) {
            final t = sorted.last.date.toLocal();
            samples.add(MapEntry(t, fiatAt(lastP.toDouble(), t)));
          }
        }
        if (samples.length < 2) {
          return Center(
            child: Text(context.l10n.accountNotEnoughDataYet,
                style: TextStyle(color: c.textTertiary, fontSize: 14.sp)),
          );
        }

        final values = <double>[
          for (final s in samples) s.value,
        ];
        final firstY = values.first;
        final lastY = values.last;
        // Direction pair via the market palette so every line chart in
        // the app speaks the same up/down colour language.
        Color lineColor;
        if (lastY > firstY) {
          lineColor = AppColors.marketUp;
        } else if (lastY < firstY) {
          lineColor = AppColors.marketDown;
        } else {
          lineColor = c.accent;
        }
        final fiatFmt = NumberFormat.simpleCurrency(name: widget.currency);
        final locale = kuteChartLocale(context);

        return Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: KuteLineChart(
            values: values,
            lineColor: lineColor,
            viewResetKey: widget.viewResetKey,
            // The change over the window on screen, as the venue charts
            // write theirs above the plot.
            summaryBuilder: (first, last) {
              final from = values[first];
              if (from == 0 || last <= first) return null;
              return Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 4.w, bottom: 4.h),
                  child: ChartChangeText(
                      percent: (values[last] - from) / from * 100),
                ),
              );
            },
            onScrubStart: () => TrackingService.analyticsChartScrubbed(
                chart: widget.tab.name, view: 'hourly'),
            valueTextBuilder: (idx) => idx >= 0 && idx < samples.length
                ? fiatFmt.format(samples[idx].value)
                : null,
            changeFormatter: fiatFmt.format,
            timeTextBuilder: (idx) => idx >= 0 && idx < samples.length
                ? kuteChartDayTime(samples[idx].key, locale)
                : null,
          ),
        );
      },
    );
  }
}

/// Singleton broadcast feed for Binance's BTCUSDT trade WebSocket.
/// Public hook for screens upstream of the analytics widget to cold-
/// start the Binance BTC/USD WebSocket the moment they mount, so that
/// by the time the user lands on the LIVE Price tab the first tick is
/// already in flight (or already delivered). The underlying singleton
/// honours its own 30s idle-close grace, so calling this even when
/// the user never reaches LIVE doesn't leak the connection.
void prewarmLiveBtcFeed() => _BinanceBtcLiveFeed.instance.prewarm();

/// Shared between the LIVE Balance and LIVE Price views so switching
/// tabs doesn't have to re-connect — the new widget subscribes to the
/// already-open stream and starts receiving ticks immediately. The
/// WS stays open as long as at least one listener is subscribed; the
/// last `cancel()` triggers a 30s grace timer (so a quick tab flip
/// stays warm) before closing.
class _BinanceBtcLiveFeed {
  static final _BinanceBtcLiveFeed instance = _BinanceBtcLiveFeed._();
  _BinanceBtcLiveFeed._();

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  StreamController<double>? _controller;
  Timer? _idleClose;
  Timer? _reconnect;
  int _listeners = 0;
  double? _lastPrice;
  // Tracks whether the WS handshake has completed AND we've received
  // at least one valid tick. Subscribers use this to skip the
  // "Connecting…" placeholder once a tick has actually landed (even
  // before their own listener was attached).
  bool _hasReceivedTick = false;

  /// Last seen price — `null` until the first tick lands. Lets a new
  /// subscriber paint something instantly while waiting for the next
  /// real tick.
  double? get lastPrice => _lastPrice;

  /// True once we've seen at least one tick on the shared feed. Used
  /// by subscribers to decide whether to hide the "Connecting…"
  /// placeholder even on their very first frame (a previous tab may
  /// already have warmed the feed).
  bool get hasReceivedTick => _hasReceivedTick;

  /// Eagerly opens the WS without registering a long-lived listener.
  /// Wallet-detail / home call this on mount so that by the time the
  /// user navigates to the LIVE Price tab ticks are already flowing.
  /// Honours the same idle-close grace period as `subscribe()` — the
  /// connection stays warm for 30s without any subscribers before
  /// shutting down on its own.
  void prewarm() {
    _idleClose?.cancel();
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<double>.broadcast();
      _connect();
    }
    // No listener registered — schedule the idle close so we don't
    // leak the WS if the user never reaches the LIVE tab.
    if (_listeners == 0) {
      _idleClose?.cancel();
      _idleClose = Timer(const Duration(seconds: 30), _shutdown);
    }
  }

  Stream<double> subscribe() {
    _idleClose?.cancel();
    _listeners++;
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<double>.broadcast();
      _connect();
    }
    return _controller!.stream;
  }

  void release() {
    _listeners = (_listeners - 1).clamp(0, 999);
    if (_listeners == 0) {
      // Don't close immediately — a tab flip transiently has 0
      // listeners as the old widget unmounts before the new one
      // subscribes. 30 seconds keeps the WS warm across navigation.
      _idleClose?.cancel();
      _idleClose = Timer(const Duration(seconds: 30), _shutdown);
    }
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
      _wsSub = _channel!.stream.listen(
        (raw) {
          try {
            final map = jsonDecode(raw as String);
            if (map is! Map<String, dynamic>) return;
            final priceStr = map['p'] as String?;
            if (priceStr == null) return;
            final price = double.tryParse(priceStr);
            if (price == null || price <= 0) return;
            _lastPrice = price;
            _hasReceivedTick = true;
            _controller?.add(price);
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
    _wsSub?.cancel();
    _channel?.sink.close();
    _reconnect?.cancel();
    if (_listeners > 0) {
      _reconnect = Timer(const Duration(seconds: 2), _connect);
    }
  }

  void _shutdown() {
    _wsSub?.cancel();
    _channel?.sink.close();
    _reconnect?.cancel();
    _controller?.close();
    _controller = null;
    _channel = null;
    _wsSub = null;
    _hasReceivedTick = false;
  }
}

/// Live fiat-balance stream for the Balance / Valuation tab when the
/// user picks the LIVE period. Subscribes to the shared
/// `_BinanceBtcLiveFeed` so switching to/from the Price tab doesn't
/// re-open the WS; multiplies each price tick by the user's BTC
/// holdings and renders a streaming sparkline.
class _LiveBalanceStream extends ConsumerStatefulWidget {
  final int btcSats;
  final String currency;
  final double fiatPerUsd;
  final void Function(double value, DateTime date)? onValueChanged;

  const _LiveBalanceStream({
    required this.btcSats,
    required this.currency,
    required this.fiatPerUsd,
    this.onValueChanged,
  });

  @override
  ConsumerState<_LiveBalanceStream> createState() => _LiveBalanceStreamState();
}

class _LiveBalanceStreamState extends ConsumerState<_LiveBalanceStream> {
  StreamSubscription<double>? _feedSub;
  final List<double> _values = [];
  // ~10 minutes of trade ticks at typical Binance rates. A longer
  // buffer lets the user actually see the line wobble up and down
  // instead of staring at the last ~3 minutes (which on a small
  // balance looks near-flat).
  static const int _maxPoints = 600;
  double? _lastPrice;
  double? _openValue;
  // Locked y-scale — mirrors the LIVE Price chart. Without this the
  // painter auto-fits to whatever values are currently buffered, so
  // every new tick visibly shifts the entire line up or down and the
  // chart reads as "resetting constantly". With it the scale only
  // expands outward when a tick exceeds the window by >2%; it never
  // tightens, so the line stays in the same vertical position frame
  // to frame.
  double? _lockedMinY;
  double? _lockedMaxY;

  @override
  void initState() {
    super.initState();
    // Seed the first tick from the shared feed's cached lastPrice
    // (if any) so the chart isn't blank waiting for the next trade.
    // Deferred to a post-frame callback because `_push` fans out via
    // `widget.onValueChanged` to the parent's `_onScrubValueChanged`
    // which calls `setState` — running that during initState (while
    // the parent is mid-build) triggers
    // "setState or markNeedsBuild called during build". The post-
    // frame schedule guarantees the parent has finished building
    // before we mutate its scrub state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cached = _BinanceBtcLiveFeed.instance.lastPrice;
      if (cached != null) _push(cached);
      // Cold-start bootstrap: fetch the last 10 one-minute kline
      // closes from Binance so the chart isn't blank for ~3 minutes
      // waiting for live ticks to fill the buffer. Best-effort —
      // failures fall through to the live tick stream.
      _bootstrapFromBinance();
    });
    _feedSub = _BinanceBtcLiveFeed.instance.subscribe().listen(_push);
  }

  Future<void> _bootstrapFromBinance() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              'https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=10',
            ),
          )
          .timeout(const Duration(seconds: 4));
      if (!mounted || resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      if (body is! List) return;
      final btc = widget.btcSats / 1e8;
      final seeded = <double>[];
      for (final k in body) {
        if (k is! List || k.length < 5) continue;
        final closeStr = k[4];
        final close = closeStr is String
            ? double.tryParse(closeStr)
            : (closeStr is num ? closeStr.toDouble() : null);
        if (close == null || close <= 0) continue;
        seeded.add(btc * close * widget.fiatPerUsd);
      }
      if (seeded.isEmpty || !mounted) return;
      setState(() {
        // Prepend bootstrap closes ahead of any live ticks that may
        // have already landed so chronological order is preserved.
        _values.insertAll(0, seeded);
        if (_values.length > _maxPoints) {
          _values.removeRange(0, _values.length - _maxPoints);
        }
        _openValue ??= _values.first;
      });
    } catch (_) {
      // Best-effort: let live ticks fill the buffer.
    }
  }

  void _push(double price) {
    if (!mounted) return;
    final btc = widget.btcSats / 1e8;
    final fiat = btc * price * widget.fiatPerUsd;
    setState(() {
      _openValue ??= fiat;
      _values.add(fiat);
      if (_values.length > _maxPoints) {
        _values.removeRange(0, _values.length - _maxPoints);
      }
      _lastPrice = price;
      _updateLockedScale(fiat);
    });
    widget.onValueChanged?.call(fiat, DateTime.now());
  }

  /// Seed / expand the locked y-axis window. On the very first tick
  /// we centre a ±0.5% window around the value so the line lands mid-
  /// chart and any wobble is visible. Subsequent ticks only widen the
  /// window — never tighten it — and only when a value escapes the
  /// current bounds by more than 2% (which is large for a balance
  /// chart and prevents the lock from flailing on minor wiggle).
  void _updateLockedScale(double value) {
    if (_lockedMinY == null || _lockedMaxY == null) {
      final half = value > 0 ? value * 0.005 : 0.01;
      _lockedMinY = value - half;
      _lockedMaxY = value + half;
      return;
    }
    final span = _lockedMaxY! - _lockedMinY!;
    final guard = span * 0.02;
    if (value < _lockedMinY! - guard) {
      _lockedMinY = value - guard;
    } else if (value > _lockedMaxY! + guard) {
      _lockedMaxY = value + guard;
    }
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    _BinanceBtcLiveFeed.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Reduce Motion: the footer fiat figure's count-up tween is purely
    // decorative (begin 0 → end value); snap to the value when the OS
    // asks for reduced animation. The live chart line itself conveys
    // data and is left streaming.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Render as soon as the first tick (or bootstrap value) lands —
    // the painter now handles single-point input by drawing the
    // endpoint dot, so there's no reason to gate on >=2.
    final hasData = _values.isNotEmpty;
    final lastValue = _values.isNotEmpty ? _values.last : null;
    final delta = (lastValue != null && _openValue != null)
        ? (lastValue - _openValue!)
        : 0.0;
    final deltaPct = (_openValue != null && _openValue! > 0)
        ? (delta / _openValue!) * 100
        : 0.0;
    final isUp = delta >= 0;
    final accent = isUp ? AppColors.marketUp : AppColors.marketDown;

    // Live-priced BTC pair display uses the user's selected currency
    // (not hardcoded USD) so EUR / GBP / etc users see their own
    // unit. The Binance feed is USD-denominated, so we multiply by
    // the same fiatPerUsd passed in for the balance math.
    final btcInUserFiat =
        _lastPrice != null ? _lastPrice! * widget.fiatPerUsd : null;

    // Sparkline streaming chart. The top-of-card label (driven by
    // the parent's `_onScrubValueChanged` via `widget.onValueChanged`)
    // is the live-updating fiat balance — we don't paint our own
    // hero number, that would duplicate the card chrome.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: hasData
              ? CustomPaint(
                  size: Size.infinite,
                  painter: _LiveBalancePainter(
                    // Snapshot copy: `_values` is mutated in place per
                    // tick, so passing it by identity would defeat the
                    // painter's series-equality repaint check.
                    values: List<double>.from(_values),
                    accent: accent,
                    isDark: !isLight,
                    lockedMin: _lockedMinY,
                    lockedMax: _lockedMaxY,
                  ),
                )
              : Center(
                  child: _ConnectingPulse(c: c, isDark: !isLight),
                ),
        ),
        SizedBox(height: 8.h),
        // Footer strip: delta-since-connect pill + live BTC/fiat pair
        // (animated). Sits below the chart so the chart's vertical
        // budget isn't eaten by chrome.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Row(
            children: [
              if (hasData)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
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
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const Spacer(),
              if (btcInUserFiat != null)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: btcInUserFiat),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    'BTC ${NumberFormat.simpleCurrency(name: widget.currency, decimalDigits: 2).format(value)}',
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveBalancePainter extends CustomPainter {
  final List<double> values;
  final Color accent;
  final bool isDark;
  // When true, paint right-edge y-axis price labels (top / mid /
  // bottom of the visible range) + a floating current-price pill at
  // the endpoint. Used by the LIVE Price tab's line mode; the LIVE
  // Balance tab leaves it off to keep its hero card clean.
  final bool showPriceLabels;
  // Optional locked y-scale — when present, the painter SKIPS its
  // own min/max computation and uses these bounds. Keeps the LIVE
  // chart's line from appearing to slide as new ticks shift the
  // auto-computed range. The locking is owned by the parent state
  // so it can decide when to expand vs hold the lock.
  final double? lockedMin;
  final double? lockedMax;

  _LiveBalancePainter({
    required this.values,
    required this.accent,
    required this.isDark,
    this.showPriceLabels = false,
    this.lockedMin,
    this.lockedMax,
  });

  static const double _rightLabelGutter = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final w = showPriceLabels
        ? (size.width - _rightLabelGutter).clamp(40.0, size.width)
        : size.width;
    final h = size.height;
    // Single-point fast path: paint just the endpoint dot so the
    // very first tick is visible and gives the user something to look
    // at while the buffer fills.
    if (values.length == 1) {
      kuteDrawEndpointDot(canvas, Offset(w, h / 2), accent, isDark: isDark);
      return;
    }

    double minV;
    double maxV;
    if (lockedMin != null && lockedMax != null) {
      // Parent state has locked the scale — use it verbatim. Lock
      // expansion happens upstream as ticks arrive.
      minV = lockedMin!;
      maxV = lockedMax!;
    } else {
      minV = values.first;
      maxV = values.first;
      for (final v in values) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      // Adaptive y-scale. Tiny balances (cents) need a tighter visual
      // window so per-tick wobble is visible — for €1.33 a "0.5% of
      // mid" window is ±0.66¢ which renders as a flat line because the
      // underlying BTC tick variance lands sub-cent. Scale the
      // expansion factor inversely with balance magnitude:
      //   * mid >= 100  → ±0.5%  (large balance, real variance shows)
      //   * mid >= 10   → ±2%    (mid balance, modest variance shows)
      //   * mid <  10   → ±10%   (small balance / cents — exaggerate
      //                          movement so the user sees the tick
      //                          they expect)
      final mid = (maxV + minV) / 2.0;
      final fracVar = mid > 0 ? (maxV - minV) / mid : 0.0;
      if (mid > 0 && fracVar < 0.0002) {
        final double halfFrac = mid >= 100
            ? 0.005
            : mid >= 10
                ? 0.02
                : 0.10;
        final halfSpan = mid * halfFrac;
        minV = mid - halfSpan;
        maxV = mid + halfSpan;
      }
    }
    // Shared-engine spark: monotone cubic path, the standard 0.14
    // gradient fill, 2.0 round-cap stroke and endpoint dot — same
    // rendering as every other line chart, with the resolved locked /
    // adaptive window pinned as the y-domain.
    kutePaintLineSpark(
      canvas,
      values: values,
      width: w.toDouble(),
      height: h,
      color: accent,
      isDark: isDark,
      lockedMin: minV,
      lockedMax: maxV,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveBalancePainter old) =>
      !kuteSameSeries(old.values, values) ||
      old.accent != accent ||
      old.isDark != isDark ||
      old.lockedMin != lockedMin ||
      old.lockedMax != lockedMax;
}

/// Per-minute BTC/USD candle stream for the Price tab when LIVE is
/// active. Binance trade ticks are bucketed into 1-minute OHLC
/// candles; the current (in-progress) candle updates with every new
/// trade. When the minute rolls over a new candle starts. Renders a
/// hero current-price label + delta pill + a dynamic candle chart.
class _LivePriceStream extends ConsumerStatefulWidget {
  /// Forwarded to the parent's `_onScrubValueChanged` so the top-of-
  /// card scrub label displays the live BTC price (in the user's
  /// settings currency) instead of whatever value was last cached by
  /// a previous tab (e.g. fiat balance carried over from LIVE Balance).
  final void Function(double value, DateTime date)? onValueChanged;

  const _LivePriceStream({this.onValueChanged});

  @override
  ConsumerState<_LivePriceStream> createState() => _LivePriceStreamState();
}

class _Candle {
  final DateTime minute;
  double open;
  double high;
  double low;
  double close;
  _Candle(this.minute, double price)
      : open = price,
        high = price,
        low = price,
        close = price;

  void update(double price) {
    if (price > high) high = price;
    if (price < low) low = price;
    close = price;
  }
}

class _LivePriceStreamState extends ConsumerState<_LivePriceStream> {
  StreamSubscription<double>? _feedSub;
  final List<_Candle> _candles = [];
  // Sub-minute live tick buffer fed by every WS message (already
  // converted to the user's settings currency). The line painter
  // consumes this directly so the line grows tick-by-tick instead of
  // once per minute (which is the resolution `_candles` is keyed to).
  final List<double> _liveTicks = [];
  // ~10 minutes of trade ticks at Binance's typical 3-10 Hz; enough
  // movement to fill the chart without dragging older quotes that no
  // longer reflect the current price level.
  static const int _maxTicks = 600;
  // Keep the last hour of 1-min candles on screen. As minute N closes
  // its candle freezes and a fresh one starts forming for N+1, so the
  // user sees a rolling tape of completed candles plus the in-progress
  // one. 60 fits comfortably in the chart width without each candle
  // collapsing to a 1px sliver.
  static const int _maxCandles = 60;
  // Most-recent USD→fiat rate snapshot. Refreshed every build from
  // `selectedCurrencyProviderFromUSD` so a settings-currency switch
  // applies to the next WS tick. Cached here (rather than re-read in
  // `_push`) because the WS subscription's listener runs outside of
  // `build` and can't watch providers directly. `1.0` until the FX
  // provider resolves — falls back to raw USD ticks so we don't drop
  // them, as the spec calls for.
  double _fiatPerUsd = 1.0;
  double? _lastPrice;
  // Locked y-scale for the LIVE line view. Set when the first tick
  // arrives and held stable across subsequent ticks so the chart line
  // doesn't appear to shift as new values come in. Only relaxes
  // outward when a tick exceeds the current locked window by >2% —
  // never tightens. Cleared whenever the user leaves LIVE (timeframe
  // change) so re-entering LIVE re-locks against the fresh data.
  double? _lockedMinY;
  double? _lockedMaxY;
  // Previous tick — used as the tween's starting value so the in-
  // progress candle's close interpolates smoothly between ticks
  // instead of snapping to each new value.
  double? _prevPrice;
  double? _openPrice;
  // Line / candle mode toggle — defaults to candle (the headline
  // feature of the LIVE Price tab). The user can flip to line for the
  // simpler trend view via the top-right toggle.
  bool _showCandles = true;

  @override
  void initState() {
    super.initState();
    // Same post-frame guard as `_LiveBalanceStreamState` so the
    // seed-from-cache path can't fire setState during the parent's
    // build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cached = _BinanceBtcLiveFeed.instance.lastPrice;
      if (cached != null) _push(cached);
      // Cold-start bootstrap: pull the prior one-minute candle
      // from Binance so the chart isn't blank for the first minute
      // waiting for live ticks to bucket into the first OHLC.
      _bootstrapCandles();
    });
    _feedSub = _BinanceBtcLiveFeed.instance.subscribe().listen(_push);
  }

  Future<void> _bootstrapCandles() async {
    try {
      // Pull a full hour of 1-min klines so the chart renders a real
      // candle tape on first paint instead of a single in-progress
      // candle waiting for the next minute to roll over. Matches
      // `_maxCandles` so the seeded set fills the visible window.
      final resp = await http
          .get(
            Uri.parse(
              'https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=60',
            ),
          )
          .timeout(const Duration(seconds: 4));
      if (!mounted || resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      if (body is! List) return;
      final seeded = <_Candle>[];
      for (final k in body) {
        if (k is! List || k.length < 5) continue;
        final openTimeRaw = k[0];
        final openTime = openTimeRaw is int
            ? openTimeRaw
            : (openTimeRaw is num ? openTimeRaw.toInt() : null);
        if (openTime == null) continue;
        final minute = DateTime.fromMillisecondsSinceEpoch(openTime);
        // Normalise to a minute-floored timestamp so live ticks
        // landing in the same minute correctly merge into the
        // matching seeded candle.
        final minuteFloor = DateTime(
          minute.year,
          minute.month,
          minute.day,
          minute.hour,
          minute.minute,
        );
        double? parseNum(dynamic v) {
          if (v is String) return double.tryParse(v);
          if (v is num) return v.toDouble();
          return null;
        }

        final openUsd = parseNum(k[1]);
        final highUsd = parseNum(k[2]);
        final lowUsd = parseNum(k[3]);
        final closeUsd = parseNum(k[4]);
        if (openUsd == null ||
            highUsd == null ||
            lowUsd == null ||
            closeUsd == null) {
          continue;
        }
        // Binance klines are USD-denominated — multiply through by the
        // current FX rate so the seeded candles share scale with the
        // live ticks coming in via `_push` (which apply the same rate).
        final fx = _fiatPerUsd > 0 ? _fiatPerUsd : 1.0;
        final candle = _Candle(minuteFloor, openUsd * fx)
          ..high = highUsd * fx
          ..low = lowUsd * fx
          ..close = closeUsd * fx;
        seeded.add(candle);
      }
      if (seeded.isEmpty || !mounted) return;
      setState(() {
        // If a live tick already started a candle for the latest
        // minute, prefer the seeded candle's OHLC but merge in the
        // live close so we don't lose any in-progress movement.
        final livePartial = _candles.isNotEmpty ? _candles.last : null;
        _candles
          ..clear()
          ..addAll(seeded);
        if (livePartial != null &&
            _candles.isNotEmpty &&
            _candles.last.minute == livePartial.minute) {
          _candles.last.update(livePartial.close);
        } else if (livePartial != null &&
            (_candles.isEmpty ||
                _candles.last.minute.isBefore(livePartial.minute))) {
          _candles.add(livePartial);
        }
        if (_candles.length > _maxCandles) {
          _candles.removeRange(0, _candles.length - _maxCandles);
        }
        _openPrice ??= _candles.first.open;
      });
    } catch (_) {
      // Best-effort: let live ticks build candles minute by minute.
    }
  }

  void _push(double priceUsd) {
    if (!mounted) return;
    // Convert the raw USD trade tick into the user's settings
    // currency before it lands in any buffer. The FX rate is the
    // most-recent value snapshotted in `build`; if the FX provider
    // hasn't resolved yet (`_fiatPerUsd == 1.0` and currency stayed
    // USD) we fall through to the raw USD price so we never drop a
    // tick — the header label has the same fallback.
    final fx = _fiatPerUsd > 0 ? _fiatPerUsd : 1.0;
    final price = priceUsd * fx;
    setState(() {
      _openPrice ??= price;
      // Remember the previous tick so `TweenAnimationBuilder` can
      // interpolate from there to the new `_lastPrice`.
      _prevPrice = _lastPrice ?? price;
      _lastPrice = price;
      // Append to the sub-minute tick buffer that the line painter
      // consumes. This keeps growing every WS tick so the line
      // visibly extends in real time instead of waiting for minute
      // boundaries (which is what `_candles` is keyed to).
      _liveTicks.add(price);
      if (_liveTicks.length > _maxTicks) {
        _liveTicks.removeRange(0, _liveTicks.length - _maxTicks);
      }
      // Tiered y-scale. Default window is the user's spending currency
      // equivalent of $1 so sub-dollar movements are visible. When a
      // tick lands outside the current window, jump to the next tier
      // ($10 → $100 → $1k …) so larger movements stay within view.
      // Lock only RELAXES outward — never tightens — so the line
      // doesn't appear to slide when ticks settle back inside.
      double observedMin = _liveTicks.first;
      double observedMax = _liveTicks.first;
      for (final v in _liveTicks) {
        if (v < observedMin) observedMin = v;
        if (v > observedMax) observedMax = v;
      }
      final mid = (observedMin + observedMax) / 2.0;
      final actualSpan = observedMax - observedMin;
      // Walk through the tier ladder until we find a window that
      // contains the observed variance. ×_fiatPerUsd so a user on EUR
      // sees ~€1, on JPY sees ~¥150, etc. — the tier is always "1
      // unit of the user's display currency" at minimum.
      final tiers = <double>[1, 10, 100, 1000, 10000];
      double pickedTier = tiers.last * _fiatPerUsd;
      for (final t in tiers) {
        final fiatTier = t * _fiatPerUsd;
        if (actualSpan <= fiatTier) {
          pickedTier = fiatTier;
          break;
        }
      }
      final halfWindow = pickedTier / 2.0;
      final targetMin = mid - halfWindow;
      final targetMax = mid + halfWindow;
      if (_lockedMinY == null || _lockedMaxY == null) {
        _lockedMinY = targetMin;
        _lockedMaxY = targetMax;
      } else {
        // Relax outward only — when ticks exceed the current locked
        // bounds we grow to the next tier. Never tighten.
        final lockedSpan = _lockedMaxY! - _lockedMinY!;
        if (pickedTier > lockedSpan) {
          _lockedMinY = targetMin;
          _lockedMaxY = targetMax;
        } else {
          if (targetMin < _lockedMinY!) _lockedMinY = targetMin;
          if (targetMax > _lockedMaxY!) _lockedMaxY = targetMax;
        }
      }
      final now = DateTime.now();
      final minute =
          DateTime(now.year, now.month, now.day, now.hour, now.minute);
      if (_candles.isEmpty || _candles.last.minute != minute) {
        // New minute → freeze the prior candle (its O/H/L/C are now
        // final) and start a fresh one for this minute. Older candles
        // stay visible up to `_maxCandles`, so the user sees a
        // rolling tape rather than just the in-progress bar.
        _candles.add(_Candle(minute, price));
        if (_candles.length > _maxCandles) {
          _candles.removeRange(0, _candles.length - _maxCandles);
        }
      } else {
        _candles.last.update(price);
      }
    });
    // Feed the parent's scrub-value label so the top-of-card shows
    // the live BTC price (in settings currency) while on the Price
    // tab. Without this the label is stuck on whatever value was
    // last cached (e.g. a tiny fiat balance left over from the LIVE
    // Balance tab).
    widget.onValueChanged?.call(price, DateTime.now());
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    _BinanceBtcLiveFeed.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Snapshot the user's settings currency + USD→fiat rate every
    // build so the next WS tick converts into the current settings
    // currency. We don't retroactively rewrite historical ticks on a
    // currency change — only future ticks pick up the new rate, per
    // the spec.
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final fiatPerUsd = currency == 'USD'
        ? 1.0
        : ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble();
    _fiatPerUsd = fiatPerUsd > 0 ? fiatPerUsd : 1.0;
    // The candle view needs at least 1 candle; the line view paints
    // from the sub-minute tick buffer and needs at least 1 tick.
    // Either is enough to flip out of the "Connecting…" placeholder
    // — the first WS tick should render immediately, no buffer wait.
    final hasData = _showCandles ? _candles.isNotEmpty : _liveTicks.isNotEmpty;
    final delta = (_lastPrice != null && _openPrice != null)
        ? (_lastPrice! - _openPrice!)
        : 0.0;
    final deltaPct = (_openPrice != null && _openPrice! > 0)
        ? (delta / _openPrice!) * 100
        : 0.0;
    final isUp = delta >= 0;
    final accent = isUp ? AppColors.marketUp : AppColors.marketDown;

    // No duplicate price hero — the parent's top-of-card scrub label
    // already shows the live BTC price via the `onValueChanged`
    // callback. This widget just renders the chart + a footer strip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top-right: line / candle toggle.
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 4.w, bottom: 6.h),
            child: _LiveModeToggle(
              showCandles: _showCandles,
              onChanged: (next) {
                if (next == _showCandles) return;
                HapticFeedback.selectionClick();
                TrackingService.track('analytics_chart_type_changed', params: {
                  'chart_type': next ? 'candles' : 'line',
                  'tab': 'price',
                  'live': true,
                });
                setState(() => _showCandles = next);
              },
            ),
          ),
        ),
        Expanded(
          child: hasData
              ? (_showCandles
                  // Tween the in-progress candle's close between
                  // successive ticks so the chart feels alive instead
                  // of snapping. Keyed by `_lastPrice` so each new
                  // tick restarts the tween from the previous price.
                  ? TweenAnimationBuilder<double>(
                      key: ValueKey<double?>(_lastPrice),
                      tween: Tween<double>(
                        begin: _prevPrice ?? _lastPrice ?? 0,
                        end: _lastPrice ?? 0,
                      ),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      builder: (context, tweened, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _LiveCandlePainter(
                          candles: _candles,
                          upColor: AppColors.marketUp,
                          downColor: AppColors.marketDown,
                          isDark: !isLight,
                          tweenedLastClose: tweened > 0 ? tweened : null,
                        ),
                      ),
                    )
                  : CustomPaint(
                      size: Size.infinite,
                      painter: _LiveBalancePainter(
                        // Line mode reads the sub-minute tick buffer
                        // so the line extends with every WS tick. The
                        // candle close list (capped at 1) only updates
                        // once a minute, which is too coarse for a
                        // streaming line view.
                        values: List<double>.from(_liveTicks),
                        accent: accent,
                        isDark: !isLight,
                        showPriceLabels: true,
                        // Locked y-scale prevents the line from
                        // appearing to slide as fresh ticks arrive.
                        lockedMin: _lockedMinY,
                        lockedMax: _lockedMaxY,
                      ),
                    ))
              : Center(
                  // No "Connecting…" text — the first tick should land
                  // within a few hundred ms (often sooner if the home
                  // screen pre-warmed the WS), so a subtle pulsing dot
                  // reads as "live feed warming up" without the alarming
                  // copy that suggests something's broken. If the WS is
                  // genuinely stuck, the pulse stays visible — same
                  // signal, less noise.
                  child: _ConnectingPulse(c: c, isDark: !isLight),
                ),
        ),
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Row(
            children: [
              if (hasData)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
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
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                _showCandles && _candles.isNotEmpty
                    ? context.l10n.chartLastMinutes(
                        _candles.last.minute
                                .difference(_candles.first.minute)
                                .inMinutes +
                            1,
                      )
                    : context.l10n.activityLiveLine,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact line / candle toggle pill shown at the top-right of the
/// LIVE price chart. Matches the toggle style used on
/// `BitcoinPriceChart` so users get the same affordance in both views.
class _LiveModeToggle extends StatelessWidget {
  final bool showCandles;
  final ValueChanged<bool> onChanged;
  const _LiveModeToggle({required this.showCandles, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(
          context,
          icon: Icons.show_chart_rounded,
          selected: !showCandles,
          isLight: isLight,
          c: c,
          onTap: () => onChanged(false),
        ),
        SizedBox(width: 4.w),
        _btn(
          context,
          icon: Icons.candlestick_chart,
          selected: showCandles,
          isLight: isLight,
          c: c,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }

  Widget _btn(
    BuildContext context, {
    required IconData icon,
    required bool selected,
    required bool isLight,
    required AppColorsExtension c,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(5.w),
        decoration: BoxDecoration(
          color: selected
              ? (isLight ? c.accent : c.surfaceElevated)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border:
              selected ? null : Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Icon(
          icon,
          size: 14.sp,
          color: selected
              ? (isLight ? Colors.white : c.textPrimary)
              : c.textTertiary,
        ),
      ),
    );
  }
}

/// Subtle pulsing dot shown while the LIVE feed's first tick is in
/// flight. Replaces the old "Connecting…" copy — the WS handshake +
/// first trade usually lands within a few hundred ms (faster if the
/// wallet-detail screen pre-warmed the connection), so the pulse
/// reads as "any second now" rather than "broken / waiting".
class _ConnectingPulse extends StatefulWidget {
  final AppColorsExtension c;
  final bool isDark;
  const _ConnectingPulse({required this.c, required this.isDark});

  @override
  State<_ConnectingPulse> createState() => _ConnectingPulseState();
}

class _ConnectingPulseState extends State<_ConnectingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final a = 0.35 + (0.4 * _ctrl.value);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.c.textTertiary.withValues(alpha: a),
          ),
        );
      },
    );
  }
}

class _LiveCandlePainter extends CustomPainter {
  final List<_Candle> candles;
  final Color upColor;
  final Color downColor;
  final bool isDark;
  // Optional tweened close override for the in-progress (last)
  // candle. When non-null, the painter renders the last candle's
  // close using this value instead of the raw close so the chart
  // smoothly interpolates between ticks instead of snapping.
  final double? tweenedLastClose;

  _LiveCandlePainter({
    required this.candles,
    required this.upColor,
    required this.downColor,
    required this.isDark,
    this.tweenedLastClose,
  });

  static const double _rightLabelGutter = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    // Reserve a right-edge gutter for the live price-level labels.
    final w = (size.width - _rightLabelGutter).clamp(40.0, size.width);
    final h = size.height;

    double minP = candles.first.low;
    double maxP = candles.first.high;
    for (final c in candles) {
      if (c.low < minP) minP = c.low;
      if (c.high > maxP) maxP = c.high;
    }
    // Same near-flat guard as `_LiveBalancePainter`: if the whole
    // window is essentially one price (range < 0.05% of mid), widen
    // the y-range so small intra-tick wobble is still visible.
    final mid = (maxP + minP) / 2.0;
    if (mid > 0 && (maxP - minP) / mid < 0.0005) {
      final halfSpan = mid * 0.005; // ±0.5% of mid
      minP = mid - halfSpan;
      maxP = mid + halfSpan;
    }
    final span = (maxP - minP).abs() < 0.001 ? 1.0 : (maxP - minP);
    const padFrac = 0.12;
    double y(double v) {
      final n = ((v - minP) / span).clamp(0.0, 1.0);
      return h * (1 - padFrac) - n * h * (1 - 2 * padFrac);
    }

    final slot = w / candles.length;
    final candleW = (slot * 0.6).clamp(2.0, 16.0);
    double? lastClose;
    bool lastIsUp = true;
    for (int i = 0; i < candles.length; i++) {
      final cd = candles[i];
      final isLast = i == candles.length - 1;
      // Use the tweened close on the in-progress candle so the body
      // top/bottom interpolates between live ticks.
      final effectiveClose =
          (isLast && tweenedLastClose != null) ? tweenedLastClose! : cd.close;
      final isUp = effectiveClose >= cd.open;
      final color = isUp ? upColor : downColor;
      final cx = slot * (i + 0.5);
      // High/low should still bound the tweened close so the wick
      // grows correctly when the tween overshoots the stored extreme.
      final effectiveHigh = effectiveClose > cd.high ? effectiveClose : cd.high;
      final effectiveLow = effectiveClose < cd.low ? effectiveClose : cd.low;
      final yHigh = y(effectiveHigh);
      final yLow = y(effectiveLow);
      final yOpen = y(cd.open);
      final yClose = y(effectiveClose);
      final bodyTop = isUp ? yClose : yOpen;
      final bodyBottom = isUp ? yOpen : yClose;
      // Wick
      canvas.drawLine(
        Offset(cx, yHigh),
        Offset(cx, yLow),
        Paint()
          ..color = color
          ..strokeWidth = 1.2,
      );
      // Body
      final rect = Rect.fromLTRB(
        cx - candleW / 2,
        bodyTop,
        cx + candleW / 2,
        bodyBottom < bodyTop + 1 ? bodyTop + 1 : bodyBottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = color,
      );
      if (isLast) {
        lastClose = effectiveClose;
        lastIsUp = isUp;
      }
    }

    // ── Right-edge y-axis labels ─────────────────────────────────
    // Three ticks (top / mid / bottom of the visible price range)
    // give the user immediate spatial context for the candles. The
    // labels re-compute every paint, so as the auto-scaled range
    // expands or contracts they tick along with it.
    final labelColor =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45);
    void drawAxisLabel(double price, double yPos) {
      final tp = TextPainter(
        text: TextSpan(
          text: _formatPrice(price),
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _rightLabelGutter - 6);
      tp.paint(canvas, Offset(w + 6, yPos - tp.height / 2));
    }

    drawAxisLabel(maxP, y(maxP));
    drawAxisLabel(mid, y(mid));
    drawAxisLabel(minP, y(minP));

    // Floating "current price" pill anchored to the right edge at
    // the latest candle's close — follows the in-progress candle as
    // it grows. Uses the same up/down color as the candle body so
    // the pill reads as the leading edge.
    if (lastClose != null) {
      final pillColor = lastIsUp ? upColor : downColor;
      // Contrast text picked by the pill fill's luminance instead of
      // hardcoded white, so a light up/down palette stays legible.
      final pillFg =
          pillColor.computeLuminance() > 0.55 ? Colors.black : Colors.white;
      final yC = y(lastClose);
      final priceTp = TextPainter(
        text: TextSpan(
          text: _formatPrice(lastClose),
          style: TextStyle(
            color: pillFg,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: -0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _rightLabelGutter - 4);
      final pillW = priceTp.width + 10;
      final pillH = priceTp.height + 6;
      final pillRect = Rect.fromLTWH(
        w + 2,
        (yC - pillH / 2).clamp(0.0, h - pillH),
        pillW,
        pillH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(4)),
        Paint()..color = pillColor,
      );
      priceTp.paint(canvas, Offset(pillRect.left + 5, pillRect.top + 3));
    }
  }

  static String _formatPrice(double v) {
    if (v >= 1000) {
      return NumberFormat('#,##0', 'en_US').format(v.round());
    }
    return v.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _LiveCandlePainter old) =>
      old.candles != candles ||
      old.tweenedLastClose != tweenedLastClose ||
      old.candles.isNotEmpty && (old.candles.last.close != candles.last.close);
}
