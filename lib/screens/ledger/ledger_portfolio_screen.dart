import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show kPolyDustShares;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show LedgerAccountTab, openLedgerInvestingSetup;
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/ledger/ledger_account_action_bar.dart';
import 'package:kute/screens/ledger/ledger_investment_balance_header.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/ledger/ledger_tab_states.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/hyperliquid_activity_list.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_activity_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/models/portfolio_performance.dart';

/// A standalone portfolio for the exact Ledger account and venue. Account
/// providers, search, and every money action remain wallet-scoped.
class LedgerPortfolioScreen extends StatelessWidget {
  final String walletId;
  final InvestmentsProduct product;
  final int initialTab;
  final bool embedded;
  const LedgerPortfolioScreen(
      {super.key,
      required this.walletId,
      required this.product,
      this.initialTab = 0,
      this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trading = product == InvestmentsProduct.trading;
    final tabLabels = <(String, IconData)>[
      (context.l10n.portfolioTabOpen, Icons.account_balance_wallet_outlined),
      (context.l10n.portfolioTabOrders, Icons.receipt_long_outlined),
      (context.l10n.activity, Icons.history_rounded),
      (context.l10n.portfolioTabStatistics, Icons.insights_outlined),
    ];
    final tabs = Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      child: PortfolioTabs(tabs: tabLabels),
    );
    final content = TabBarView(children: [
      _LedgerPortfolioBody(
          walletId: walletId, product: product, view: _View.positions),
      trading
          ? _LedgerPortfolioBody(
              walletId: walletId, product: product, view: _View.orders)
          : OpenOrdersSheet(embedded: true, ledgerWalletId: walletId),
      _LedgerActivityBody(walletId: walletId, product: product),
      PortfolioStatistics(
          venue: trading
              ? PortfolioPerformanceVenue.trading
              : PortfolioPerformanceVenue.predictions,
          walletId: walletId),
    ]);
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: embedded
          ? Material(
              color: Colors.transparent,
              child: Column(children: [
                tabs,
                Expanded(child: content),
              ]))
          : Scaffold(
              backgroundColor: c.background,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: true,
                leading: const KuteBackButton(),
                title: Text(context.l10n.walletPortfolioAction,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ),
              body: Container(
                decoration: AppDecorations.screenGradient(context),
                // Same dock mount as Home and the spending wallet's
                // portfolio; the dock stays bound to this Ledger wallet.
                child: KuteDockHost(
                  dockBuilder: (onHeightChanged) => LedgerAccountActionBar(
                    walletId: walletId,
                    tab: trading
                        ? LedgerAccountTab.investing
                        : LedgerAccountTab.predictions,
                    onHeightChanged: onHeightChanged,
                    onPortfolio: true,
                  ),
                  body: SafeArea(
                      top: false,
                      bottom: false,
                      child: NestedScrollView(
                        headerSliverBuilder: (context, innerBoxIsScrolled) => [
                          SliverToBoxAdapter(
                              child: LedgerInvestmentBalanceHeader(
                                  walletId: walletId, product: product)),
                          // Pinned, exactly as on the spending account's
                          // portfolio: Ledger mirrors Home.
                          PortfolioTabsSliver(tabs: tabLabels),
                        ],
                        // The tabs run to the bottom of the screen, under
                        // the frost band and the dock, as on Home; each
                        // list keeps its last row clear of the dock
                        // (kuteDockScrollClearance).
                        body: content,
                      )),
                ),
              ),
            ),
    );
  }

  static Future<void> show(
    BuildContext context, {
    required String walletId,
    required InvestmentsProduct product,
  }) =>
      Navigator.of(context, rootNavigator: true).push<void>(MaterialPageRoute(
          builder: (_) =>
              LedgerPortfolioScreen(walletId: walletId, product: product)));
}

enum _View { positions, orders }

class _LedgerPortfolioBody extends ConsumerWidget {
  final String walletId;
  final InvestmentsProduct product;
  final _View view;
  const _LedgerPortfolioBody(
      {required this.walletId, required this.product, required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null || !identity.hasVerifiedEvm) {
      return _EnableLedger(walletId: walletId);
    }
    if (identity.walletId != walletId) {
      return LedgerTabLoadFailed(
          onRetry: () => ref.invalidate(ledgerIdentityProvider(walletId)));
    }
    return product == InvestmentsProduct.trading
        ? _trading(context, ref, identity)
        : _predictions(context, ref, identity);
  }

  Widget _trading(
      BuildContext context, WidgetRef ref, LedgerIdentity identity) {
    final data = ref.watch(ledgerHlAccountProvider(walletId));
    void retry() => ref.invalidate(ledgerHlAccountProvider(walletId));
    return data.when(
      loading: () => const LedgerTabLoading(),
      error: (_, __) => LedgerTabLoadFailed(onRetry: retry),
      data: (account) {
        if (account.walletId != walletId ||
            account.address?.toLowerCase() !=
                identity.evmAddress!.toLowerCase()) {
          return LedgerTabLoadFailed(onRetry: retry);
        }
        final actions = ref.watch(ledgerAccountActionsProvider);
        final rows = <Widget>[];
        if (account.hasPartialFailure) {
          rows.add(LedgerPartialLoadNote(onRetry: retry));
        }
        switch (view) {
          case _View.positions:
            final positions = [
              ...?account.account?.positions,
              for (final dex in account.dexAccounts.values) ...dex.positions,
            ];
            rows.addAll(positions.map(
                (p) => LedgerHlPositionRow(position: p, walletId: walletId)));
            rows.addAll((account.account?.spotBalances ??
                    const <HlSpotBalance>[])
                .where((balance) => balance.coin != 'USDC' && balance.total > 0)
                .map((balance) => _LedgerSpotRow(balance: balance)));
          case _View.orders:
            final orders = account.openOrders ?? const <HlOpenOrder>[];
            rows.addAll(orders.map((order) => LedgerHlOrderRow(
                order: order,
                onCancel: actions.onCancelOrder == null
                    ? null
                    : () => actions.onCancelOrder!(context, walletId, order))));
        }
        if (rows.isEmpty) {
          return _EmptyPortfolio(
              message: view == _View.orders
                  ? context.l10n.hlOrdersEmpty
                  : context.l10n.ledgerInvestingEmpty);
        }
        return ListView(
            padding: EdgeInsets.only(
                bottom: 16.h + kuteDockScrollClearance(context)),
            children: rows);
      },
    );
  }

  Widget _predictions(
      BuildContext context, WidgetRef ref, LedgerIdentity identity) {
    final data = ref.watch(ledgerPmAccountProvider(walletId));
    void retry() => ref.invalidate(ledgerPmAccountProvider(walletId));
    return data.when(
      loading: () => const LedgerTabLoading(),
      error: (_, __) => LedgerTabLoadFailed(onRetry: retry),
      data: (account) {
        if (account.walletId != walletId ||
            account.eoa?.toLowerCase() != identity.evmAddress!.toLowerCase()) {
          return LedgerTabLoadFailed(onRetry: retry);
        }
        final actions = ref.watch(ledgerAccountActionsProvider);
        final canAct = account.account?.canAct == true && !account.isReadOnly;
        // A position sold down to dust (under 0.01 share) is gone, as on
        // the spending wallet's Portfolio.
        final positions = (account.positions ?? const [])
            .where((p) => p.size >= kPolyDustShares)
            .toList();
        if (positions.isEmpty && !account.hasPartialFailure) {
          return _EmptyPortfolio(message: context.l10n.ledgerNoPositionsYet);
        }
        return ListView(
            padding: EdgeInsets.only(
                bottom: 16.h + kuteDockScrollClearance(context)),
            children: [
          if (account.hasPartialFailure) LedgerPartialLoadNote(onRetry: retry),
          if (account.isReadOnly)
            LedgerTabNote(text: context.l10n.ledgerPmLegacyReadOnly),
          for (final position in positions)
            LedgerPmPositionRow(
              position: position,
              onSell: !canAct ||
                      position.redeemable ||
                      actions.onSellPosition == null
                  ? null
                  : () => actions.onSellPosition!(context, walletId, position),
              onClaim: !canAct ||
                      !position.redeemable ||
                      actions.onClaimPosition == null
                  ? null
                  : () => actions.onClaimPosition!(context, walletId, position),
            ),
        ]);
      },
    );
  }
}

/// Public market metadata augments only the holding returned for this Ledger.
/// This row never routes into a hot account's order ticket.
class _LedgerSpotRow extends ConsumerWidget {
  const _LedgerSpotRow({required this.balance});
  final HlSpotBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull;
    final market = markets?.where((m) => m.coin == balance.coin).firstOrNull;
    final price = ref
        .watch(hyperliquidSpotTickersProvider)
        .valueOrNull
        ?.tickers[balance.coin]
        ?.markPrice;
    final value = price == null || !price.isFinite || price <= 0
        ? null
        : price * balance.total;
    // The Portfolio's own card, on the list cards' inset.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: HlPortfolioCard(
        coin: balance.coin,
        wireCoin: market?.wireCoin,
        iconUrl: market?.iconUrl,
        category: market?.category,
        name: hlFriendlyName(balance.coin) ??
            market?.unitAssetName ??
            balance.coin,
        caption: '${balance.coin} · ${context.l10n.investingSpot}',
        trailing: PortfolioCardValue(
          value: value == null || !value.isFinite
              ? '—'
              : formatPolyAmount(ref, value),
        ),
        footer: [
          context.l10n
              .openInvestHeld(formatHlSize(balance.total, maxDecimals: 8)),
        ],
      ),
    );
  }
}

class _LedgerActivityBody extends ConsumerWidget {
  final String walletId;
  final InvestmentsProduct product;
  const _LedgerActivityBody({required this.walletId, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null || !identity.hasVerifiedEvm) {
      return _EnableLedger(walletId: walletId);
    }
    if (identity.walletId != walletId) {
      return LedgerTabLoadFailed(
          onRetry: () => ref.invalidate(ledgerIdentityProvider(walletId)));
    }
    if (product == InvestmentsProduct.trading) {
      void retry() => ref.invalidate(ledgerHlAccountProvider(walletId));
      return ref.watch(ledgerHlAccountProvider(walletId)).when(
            loading: () => const LedgerTabLoading(),
            error: (_, __) => LedgerTabLoadFailed(onRetry: retry),
            data: (account) {
              if (account.walletId != walletId ||
                  account.address?.toLowerCase() !=
                      identity.evmAddress!.toLowerCase()) {
                return LedgerTabLoadFailed(onRetry: retry);
              }
              if (account.fills == null) {
                return LedgerTabLoadFailed(onRetry: retry);
              }
              final live = ref.watch(ledgerHlFillsProvider(walletId));
              return HyperliquidActivityList(
                  fills: live.valueOrNull ?? account.fills!,
                  walletId: walletId,
                  loading: live.isLoading,
                  loadFailed: live.hasError,
                  onRetry: () {
                    retry();
                    ref.invalidate(ledgerHlFillsProvider(walletId));
                  });
            },
          );
    }
    void retry() {
      ref.invalidate(ledgerPmAccountProvider(walletId));
      ref.invalidate(ledgerPmActivityProvider(walletId));
    }

    final account = ref.watch(ledgerPmAccountProvider(walletId));
    final data = account.valueOrNull;
    if (data != null &&
        (data.walletId != walletId ||
            data.eoa?.toLowerCase() != identity.evmAddress!.toLowerCase())) {
      return LedgerTabLoadFailed(onRetry: retry);
    }
    return ref.watch(ledgerPmActivityProvider(walletId)).when(
          loading: () => const LedgerTabLoading(),
          error: (_, __) => LedgerTabLoadFailed(onRetry: retry),
          data: (activity) {
            final rows = activity;
            if (rows.isEmpty) {
              return _EmptyPortfolio(message: context.l10n.ledgerActivityEmpty);
            }
            // The shared activity rows ("Prediction · Yes", "Won · Up",
            // "Merged shares") instead of the raw TRADE, REDEEM, MERGE
            // and SPLIT types, on the same day cards as every surface.
            return LedgerPmActivityList(
                rows: rows,
                positions: data?.positions ?? const [],
                walletId: walletId);
          },
        );
  }
}

class _EnableLedger extends StatelessWidget {
  final String walletId;
  const _EnableLedger({required this.walletId});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: EdgeInsets.only(bottom: kuteDockScrollClearance(context)),
      child: LedgerEnableInvestingCard(
          onEnable: () => openLedgerInvestingSetup(context, walletId)));
}

/// One centred sentence, nothing else.
class _EmptyPortfolio extends StatelessWidget {
  final String message;
  const _EmptyPortfolio({required this.message});
  @override
  Widget build(BuildContext context) => KuteDockClearance(
          child: Center(
              child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Text(message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500)),
      )));
}
