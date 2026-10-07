// lib/screens/ledger/ledger_polymarket_tab.dart
//
// Predictions tab (Polymarket) of the Ledger account screen (Wallet
// hardening Phase 4, P4.4, B10): balance header and public discovery.
//
// Read only through `ledgerPmAccountProvider`: no CLOB credentials, no
// deploy, no approvals. Positions, sell and claim live behind Portfolio,
// exactly like Home; their Ledger hooks come from
// `ledgerAccountActionsProvider` and never act for a legacy Safe account
// (O4, read only). A failed read shows "Some balances could not load",
// never zero.
//
// Public discovery stays visible independently of account reads. Activity
// lives in Portfolio; its shared rows below use this Ledger's records only.

import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, PolymarketEvent;
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_feed_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        Tag,
        activityCrestIcon,
        polymarketEventsByTagIdProvider,
        polymarketParentTagsProvider;
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets;
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show openLedgerInvestingSetup;
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/ledger/ledger_tab_states.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_market_browser.dart';
import 'package:kute/screens/polymarket/components/poly_feed_utils.dart'
    show collapseByGameId;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart'
    show CryptoPredictBanner;
import 'package:kute/screens/ledger/ledger_investment_balance_header.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventsProvider;
import 'package:kute/services/polymarket/polymarket_account_resolver.dart'
    show PolymarketAccountKind;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/screens/shared/activity_row_copy.dart'
    show predictionRowCopy, predictionRowFigures;
import 'package:kute/screens/shared/transactions_builder.dart'
    show
        activityDaySections,
        activityRowTitle,
        buildWalletActivityRow,
        predictionActivityIcon,
        predictionResultColor,
        showPredictionResultDetails;
import 'package:kute/services/runtime_capabilities_service.dart';

/// Totals from one Ledger Polymarket read; null when a read failed.
class LedgerPmTotals {
  const LedgerPmTotals({this.total, this.positionsValue, this.cash});

  factory LedgerPmTotals.of(LedgerPmAccount data) {
    final kind = data.account?.kind;
    if (kind == null || kind == PolymarketAccountKind.uncertain) {
      return const LedgerPmTotals();
    }
    if (kind == PolymarketAccountKind.none) {
      return const LedgerPmTotals(total: 0, positionsValue: 0, cash: 0);
    }
    final positions = data.positions;
    final pusd = data.pusdBalance;
    final usdce = data.usdceBalance;
    final double? positionsValue =
        positions?.fold<double>(0, (s, p) => s + p.currentValue);
    final double? cash =
        pusd == null || usdce == null ? null : (pusd + usdce).toDouble() / 1e6;
    return LedgerPmTotals(
      total:
          positionsValue != null && cash != null ? positionsValue + cash : null,
      positionsValue: positionsValue,
      cash: cash,
    );
  }

  final double? total;
  final double? positionsValue;
  final double? cash;
}

class LedgerPolymarketTab extends ConsumerWidget {
  final String walletId;

  const LedgerPolymarketTab({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    final paired = identity != null &&
        identity.walletId == walletId &&
        identity.hasVerifiedEvm;
    final async = paired ? ref.watch(ledgerPmAccountProvider(walletId)) : null;
    void retry() {
      ref.invalidate(ledgerPmAccountProvider(walletId));
      ref.invalidate(ledgerPmActivityFeedProvider(walletId));
      ref.invalidate(polymarketParentTagsProvider);
      ref.invalidate(polymarketEventsByTagIdProvider);
    }

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        retry();
        // The position cards' events: a batch that failed is asked again.
        ref.read(polyPositionEventsProvider.notifier).retry();
        try {
          if (paired) await ref.read(ledgerPmAccountProvider(walletId).future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
            top: 4.h, bottom: 40.h + MediaQuery.paddingOf(context).bottom),
        children: [
          if (!paired)
            LedgerEnableInvestingCard(
              onEnable: () => openLedgerInvestingSetup(context, walletId),
            )
          else
            ...async!.when<List<Widget>>(
              loading: () => const [LedgerTabLoading()],
              error: (_, __) => [LedgerTabLoadFailed(onRetry: retry)],
              data: (data) => data.walletId != walletId ||
                      data.eoa?.toLowerCase() !=
                          identity.evmAddress!.toLowerCase()
                  ? [LedgerTabLoadFailed(onRetry: retry)]
                  : [
                      _LedgerPmContent(
                          walletId: walletId, data: data, onRetry: retry),
                    ],
            ),
          // Public markets do not depend on private account setup, cash or
          // history reads. A balance outage must not hide discovery.
          _LedgerPredictionsDiscovery(walletId: walletId),
        ],
      ),
    );
  }
}

class _LedgerPmContent extends ConsumerWidget {
  final String walletId;
  final LedgerPmAccount data;
  final VoidCallback onRetry;

  const _LedgerPmContent({
    required this.walletId,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final actions = ref.watch(ledgerAccountActionsProvider);
    final kind = data.account?.kind;
    final readOnly = data.isReadOnly;
    final canAct = !readOnly && kind == PolymarketAccountKind.depositWallet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.hasPartialFailure) LedgerPartialLoadNote(onRetry: onRetry),
        LedgerInvestmentBalanceHeader(
          walletId: walletId,
          product: InvestmentsProduct.predictions,
          showDepositButton: true,
        ),
        // Arrived Ledger bitcoin sits as USDC.e until the user makes it
        // available (one Ledger approval).
        if (canAct &&
            actions.onPredictionsMakeFundsAvailable != null &&
            (data.usdceBalance ?? BigInt.zero) > BigInt.zero) ...[
          LedgerTabNote(text: l10n.ledgerPmMakeAvailableTabNote),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: AppButton(
              text: l10n.ledgerPmMakeAvailableCta,
              onPressed: () =>
                  actions.onPredictionsMakeFundsAvailable!(context, walletId),
            ),
          ),
        ],
      ],
    );
  }
}

/// Public discovery mirrors Home: the 5 Minute Markets block, then one
/// section per Gamma parent tag in Home's order, with Home's market cards.
/// Every market and Up/Down tap pins the selected Ledger through market
/// detail, amount entry and device approval.
class _LedgerPredictionsDiscovery extends ConsumerWidget {
  const _LedgerPredictionsDiscovery({required this.walletId});

  final String walletId;

  /// Home lazy-mounts tag sections on scroll; this column fetches every
  /// section at once, so the tag count is capped.
  static const int _kTagSectionCount = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision =
        ref.watch(runtimeCapabilitiesProvider).decision('polymarket.browse');
    if (!decision.allowed) return LedgerTabNote(text: decision.message);
    void retry() {
      ref.invalidate(polymarketParentTagsProvider);
      ref.invalidate(polymarketEventsByTagIdProvider);
    }

    final fiveMinute = _LedgerFiveMinuteMarkets(walletId: walletId);
    Widget withFiveMinute(Widget below) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [fiveMinute, below],
        );
    return ref.watch(polymarketParentTagsProvider).when(
          loading: () => withFiveMinute(const LedgerTabLoading()),
          error: (_, __) => withFiveMinute(LedgerTabLoadFailed(onRetry: retry)),
          data: (tags) {
            final sections = <InvestmentBrowseSection<PolymarketEvent>>[];
            var pending = false;
            for (final Tag tag in tags.take(_kTagSectionCount)) {
              final events = ref.watch(polymarketEventsByTagIdProvider(tag.id));
              if (events.isLoading) pending = true;
              final raw = events.valueOrNull;
              if (raw == null) continue;
              final open = collapseByGameId(
                  raw.where((event) => !event.ended).toList(growable: false));
              if (open.isEmpty) continue;
              sections.add(InvestmentBrowseSection(
                  label: tag.label ?? tag.slug ?? 'Topic', markets: open));
            }
            if (sections.isEmpty) {
              return withFiveMinute(pending
                  ? const LedgerTabLoading()
                  : LedgerTabNote(text: context.l10n.betNoOpenMarketsInTopic));
            }
            return InvestmentMarketBrowser<PolymarketEvent>(
              product: 'predictions',
              leading: fiveMinute,
              sections: sections,
              cardBuilder: (event, onTap) =>
                  PredictionBrowseCard(event: event, onTap: onTap),
              onOpenMarket: (event) {
                if (!context.mounted) return;
                MarketDetailSheet.show(context,
                    event: event, ledgerWalletId: walletId, source: 'ledger');
              },
            );
          },
        );
  }
}

/// Home's 5 Minute Markets block: header and the live Up-or-Down hero card.
/// The card's Up and Down taps carry the Ledger wallet into the bet ticket.
class _LedgerFiveMinuteMarkets extends StatelessWidget {
  const _LedgerFiveMinuteMarkets({required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InvestmentSectionHeader(label: context.l10n.ledgerFiveMinuteMarkets),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: RepaintBoundary(
            child: CryptoPredictBanner(
              config: kCryptoPredictAssets.first,
              showLiveIndicator: true,
              ledgerWalletId: walletId,
            ),
          ),
        ),
      ],
    );
  }
}

/// One past Predictions event on the shared activity row: the market
/// crest, "Sold · G2" style title, the short market under it, the dollar
/// amount signed by direction. Built from this record alone; nothing
/// reads the spending wallet. A venue record is not tappable (the
/// account's records carry no detail sheet); a result opens its own.
class LedgerPmActivityRow extends ConsumerWidget {
  final Activity activity;

  /// This account's own Predictions records, for the realised profit or
  /// loss of a sale or a payout and the stake of a loss. Never the
  /// spending wallet's.
  final List<Activity> history;

  /// Set when the row is a result read from the account's resolved
  /// market ([predictionResults]) rather than a venue record.
  final PredictionResult? result;

  /// The Ledger wallet, for the market a result's sheet opens.
  final String? walletId;

  const LedgerPmActivityRow(
      {super.key,
      required this.activity,
      this.history = const [],
      this.result,
      this.walletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final copy = predictionRowCopy(l10n, activity,
        time: DateFormat('HH:mm').format(activity.timestampDate));
    final figures = predictionRowFigures(activity, history,
        flow: copy.flow, result: result);
    final pnl = figures.pnl;
    // A win still to claim says so; the claim is on the position.
    final claimable = result?.claimable ?? false;
    final r = result;
    return buildWalletActivityRow(
      onTap: r == null
          ? null
          : () => showPredictionResultDetails(context, r,
              ledgerWalletId: walletId),
      leading: predictionActivityIcon(activityCrestIcon(ref, activity)),
      title: activityRowTitle(copy.title),
      subtitle: copy.subtitle,
      status: claimable ? l10n.claim : null,
      statusColor: claimable ? AppColors.marketUp : null,
      amount: formatPolyAmount(ref, figures.amount),
      flow: figures.flow,
      amountColor: predictionResultColor(figures),
      secondaryAmount: pnl == null
          ? ''
          : pnl >= 0
              ? l10n.activityAmountProfit(formatPolyAmount(ref, pnl.abs()))
              : l10n.activityAmountLoss(formatPolyAmount(ref, pnl.abs())),
      secondaryColor: pnl == null
          ? null
          : pnl >= 0
              ? AppColors.marketUp
              : AppColors.marketDown,
    );
  }
}

/// The Ledger account's Predictions activity, grouped by day on the same
/// cards as Home and the spending account's Predictions activity, with
/// the results of its predictions held to a resolved market that the
/// history does not record ([predictionResults], from [positions]): a
/// lost prediction not cleared yet, a win not claimed yet.
class LedgerPmActivityList extends StatelessWidget {
  final List<Activity> rows;

  /// The account's open positions (the Ledger read lists no closed ones).
  final List<Position> positions;

  /// The Ledger wallet, for the market a result's sheet opens.
  final String? walletId;

  const LedgerPmActivityList(
      {super.key,
      required this.rows,
      this.positions = const [],
      this.walletId});

  @override
  Widget build(BuildContext context) {
    final results = Map<Activity, PredictionResult>.identity()
      ..addEntries([
        for (final r in predictionResults(
            open: positions, closed: const [], history: rows))
          MapEntry(r.activity, r),
      ]);
    final all = results.isEmpty
        ? rows
        : ([...rows, ...results.keys]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
    // Hosted under the Ledger Portfolio's dock: the last row clears it.
    return ListView(
      padding: EdgeInsets.fromLTRB(
          0, 4.h, 0, 40.h + kuteDockScrollClearance(context)),
      children: activityDaySections<Activity>(
        all,
        timeOf: (a) => a.timestampDate,
        rowOf: (a) => LedgerPmActivityRow(
            activity: a,
            history: rows,
            result: results[a],
            walletId: walletId),
      ),
    );
  }
}

/// One Polymarket position. Sell is solid marketDown; claim is the primary
/// fill. Both only when their Ledger hook is passed.
class LedgerPmPositionRow extends ConsumerWidget {
  final Position position;
  final VoidCallback? onSell;
  final VoidCallback? onClaim;

  const LedgerPmPositionRow({
    super.key,
    required this.position,
    this.onSell,
    this.onClaim,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pnl = position.cashPnl;
    Widget? action;
    if (onClaim != null) {
      action = AppButton(
        text: l10n.ledgerClaimCta,
        compact: true,
        onPressed: onClaim,
      );
    } else if (onSell != null) {
      action = AppButton(
        text: l10n.ledgerSellCta,
        compact: true,
        color: AppColors.marketDown,
        textColor: Colors.white,
        onPressed: onSell,
      );
    }
    // The Portfolio's own position card, on the list cards' inset.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: PolyPositionCard(
        question: position.title,
        imageUrl: position.icon,
        outcome: position.outcome,
        shares: position.size,
        avgPrice: position.avgPrice,
        value: position.currentValue,
        pnl: pnl,
        pnlPercent: position.percentPnl,
        eventSlug: position.eventSlug,
        end: DateTime.tryParse(position.endDate ?? ''),
        conditionId: position.conditionId,
        resolved: position.redeemable,
        claimable: position.redeemable && position.curPrice >= 0.99,
        action: action,
      ),
    );
  }
}
