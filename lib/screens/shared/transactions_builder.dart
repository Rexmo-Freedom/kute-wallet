import 'package:kute/screens/shared/orchestra_swap_refund_action.dart';
import 'package:kute/screens/shared/activity_row_copy.dart';
export 'package:kute/screens/shared/activity_row_copy.dart' show ActivityFlow;
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/screens/shared/bitcoin_labels.dart';
import 'package:kute/screens/shared/bitcoin_performance_comparison.dart';
import 'package:kute/providers/cash_app_payment_window_provider.dart';
import 'package:kute/helpers/cash_app_purchase_session.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/helpers/cash_app_status.dart' show cashAppStatusLabel;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide, showDepositSheet;
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/mempool_address_service.dart'
    show MempoolAddressService;
import 'package:kute/services/tx_fiat_snapshot_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatPolyAmount;
import 'package:kute/helpers/common_operation_methods.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show showBuyUnavailableSheet;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, orchestraChainDisplayName;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/asset_icon_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/pending_ledger_settlement_provider.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, ActivityType;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show activityCrestIcon, polymarketClaimablePositionsProvider;
import 'package:kute/helpers/prediction_results.dart'
    show PredictionResult, predictionResults;
import 'package:kute/screens/polymarket/components/position_claim.dart'
    show PolyClaimButton;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/transaction_search_provider.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/components/tx_flow_graph.dart';
import 'package:kute/screens/shared/components/transaction_row_content.dart';
import 'package:kute/screens/shared/spark_transaction_details.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kute/screens/shared/animations/fade_in_slide.dart';
import 'package:kute/screens/shared/animations/bouncy_touch.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';

const Color _kPolyRedTx = Color(0xFFEF4444);


/// Rows an activity preview shows before "See all" (Home, Dollars, the
/// Bitcoin wallet, hardware and watch-only wallets): five, by user decision.
const int kActivityPreviewRows = 5;

class TransactionList extends ConsumerStatefulWidget {
  /// Optional override — when set, the list renders transactions
  /// from `walletTransactionCacheProvider[walletId]` directly,
  /// bypassing the active-wallet `transactionNotifierProvider`. Used
  /// by the portfolio wallet detail screen so it surfaces a hardware
  /// wallet's BDK history without flipping `activeWalletId` (which
  /// must stay on the spending wallet for Home).
  final String? walletIdOverride;

  /// When true, render the entire filtered list instead of capping at
  /// the 4 most recent rows. Home keeps the cap (compact Activity
  /// preview); the portfolio wallet detail screen overrides this so
  /// the cold-storage Activity rail surfaces the full history of the
  /// wallet without the user having to drill into a separate route.
  final bool showAll;

  /// Renders ONLY the dollar rows (the USDB token transfers on Spark).
  /// The USD tab's activity list is the dollar ledger of the spending
  /// account, not its whole history; every other surface leaves this
  /// false and sees the merged feed exactly as before. Internal name
  /// keeps the token's own identifier — the user only sees "USD".
  final bool onlyUsdb;

  /// Empty content supplied by the containing wallet surface.
  final Widget? emptyState;

  const TransactionList({
    super.key,
    this.walletIdOverride,
    this.showAll = false,
    this.onlyUsdb = false,
    this.emptyState,
  });
  @override
  _TransactionListState createState() => _TransactionListState();
}

class _TransactionListState extends ConsumerState<TransactionList> {
  bool _reviewCheckDone = false;

  /// The txid set the last prefetch ran for, so a rebuild of the same list
  /// never re-issues the requests.
  String? _prefetchedKey;

  /// Warm mempool.space for the on-chain rows on screen, so tapping one
  /// opens a detail sheet whose flow graph is already drawable. Only
  /// confirmed on-chain rows qualify: Lightning and Spark rows have no UTXO
  /// braid, and a pending transaction is still allowed to change.
  void _prefetchOnChainDetails(List<BaseTransaction> rows) {
    final txids = <String>[];
    for (final tx in rows) {
      if (txids.length >= 10) break;
      if (tx is BitcoinTransaction) {
        if (tx.isConfirmed) txids.add(tx.id);
      } else if (tx is MempoolAddressTransaction) {
        if (tx.details.confirmed) txids.add(tx.details.txid);
      }
    }
    if (txids.isEmpty) return;
    final key = txids.join(',');
    if (key == _prefetchedKey) return;
    _prefetchedKey = key;
    // Fire and forget: the service never throws and bounds its own
    // concurrency, so nothing here can delay a frame.
    unawaited(MempoolAddressService.prefetchTransactions(txids));
  }

  Future<void> _checkForReviewPrompt(dynamic transactionState) async {
    final settings = ref.read(settingsProvider);
    if (settings.reviewDone) {
      return;
    }

    final hasRelevantTransactions =
        (transactionState.bitcoinTransactions?.isNotEmpty ?? false) ||
            (transactionState.sparkTransactions?.isNotEmpty ?? false);
    if (!hasRelevantTransactions) {
      return;
    }

    // Mark in-flight immediately so the next build doesn't fire a
    // second prompt while we're awaiting the native review sheet.
    if (mounted) {
      setState(() => _reviewCheckDone = true);
    }

    // Give the user a beat to see the new tx land before the
    // native rating sheet pops over it.
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) {
      return;
    }

    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        TrackingService.track('review_prompted',
            params: const {'trigger': 'first_tx'});
      }
    } catch (_) {/* native sheet unavailable / rate-limited */}

    // Always mark done after attempting — even if the OS suppressed
    // the prompt (Apple's quota is 3 prompts/year). We don't want
    // to keep checking on every Activity rebuild.
    if (!mounted) {
      return;
    }
    ref.read(settingsProvider.notifier).setReviewDone(true);
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.walletIdOverride;

    // Resolve which wallet's transactions to display. When the
    // detail screen passes an explicit override, render that wallet's
    // per-wallet cache directly (no active-wallet swap needed). Else
    // fall back to the legacy active-wallet path used by Home.
    //
    // Home and History now read the SAME source — `allTransactionsSorted`
    // — so the two never disagree on what rows exist. Earlier Home
    // used `homeTransactionsSorted` which applied an extra heuristic
    // filter (Polymarket-tagged Spark txs hidden) that History
    // didn't; the symptom was Home showing 1 row while History
    // showed 9 for the same wallet. Surfaces now differ only in
    // projection: Home takes top 4, History shows everything. This
    // is the surgical first step of the ActivityEvent refactor (see
    // `project_activity_event_refactor` memory) — the full
    // canonical-event model lands later.
    List<BaseTransaction> homeTransactionsSorted;
    bool isHardwareOrWatchOnly;
    if (override != null) {
      final cache = ref.watch(walletTransactionCacheProvider);
      final overrideTx = cache[override];
      homeTransactionsSorted =
          overrideTx?.allTransactionsSorted ?? const <BaseTransaction>[];
      final settings = ref.watch(settingsProvider);
      final w = settings.wallets
          .cast<WalletConfig?>()
          .firstWhere((x) => x?.id == override, orElse: () => null);
      isHardwareOrWatchOnly = (w?.isHardware ?? false) ||
          (w?.isWatchOnly ?? false) ||
          (w?.isExternalAddress ?? false);
    } else {
      final activeWallet =
          ref.watch(settingsProvider.select((s) => s.activeWallet));
      // Read the active wallet's per-wallet cache slot DIRECTLY
      // instead of via the StateNotifier. The notifier's `_refresh`
      // only writes state when `next != state`, and `Transaction.==`
      // compares every sublist element-wise — but the
      // `_cachedAllTransactionsSorted` cached sorted-list lives on
      // the Transaction instance and only invalidates when a NEW
      // Transaction instance is published. Reading the cache slot
      // directly side-steps that staleness path and matches what
      // the merged provider walks per slot. Same data semantics as
      // History (active wallet only), no cross-wallet aggregation.
      final activeId =
          ref.watch(settingsProvider.select((s) => s.activeWalletId));
      final cache = ref.watch(walletTransactionCacheProvider);
      // Disambiguate from `bdk.Transaction` (also in scope via
      // `package:kute/models/onchain_types.dart`).
      final activeTx = (activeId != null ? cache[activeId] : null);
      homeTransactionsSorted =
          activeTx?.allTransactionsSorted ?? const <BaseTransaction>[];
      isHardwareOrWatchOnly = (activeWallet?.isHardware ?? false) ||
          (activeWallet?.isWatchOnly ?? false) ||
          (activeWallet?.isExternalAddress ?? false);
    }

    // What this surface shows, one row per user intent. The surface
    // filters run FIRST and the leg collapse second, so a leg is only ever
    // hidden behind a row that is still on screen (see [assembleActivityRows]).
    final allSorted = assembleActivityRows(
      homeTransactionsSorted,
      ownAddresses: activityOwnSettleAddresses(ref),
      isHardwareOrWatchOnly: isHardwareOrWatchOnly,
      onlyUsdb: widget.onlyUsdb,
    );

    final recentTransactions = widget.showAll
        ? allSorted
        : allSorted.take(kActivityPreviewRows).toList();

    // The on-chain rows the person can tap right now: warm their explorer
    // payloads while they are still reading the list.
    _prefetchOnChainDetails(recentTransactions);

    final Map<DateTime, List<BaseTransaction>> groupedTransactions = {};
    for (var tx in recentTransactions) {
      final dateKey =
          DateTime(tx.timestamp.year, tx.timestamp.month, tx.timestamp.day);
      groupedTransactions.putIfAbsent(dateKey, () => []).add(tx);
    }

    final sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    if (recentTransactions.isNotEmpty && !_reviewCheckDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForReviewPrompt(ref.read(transactionNotifierProvider));
      });
    }

    // Privacy level 2 keeps the activity rows visible but masks each
    // row's amounts (handled inside _TransactionRow). Levels 0/1 show
    // full values, so the list always renders here — no whole-list
    // "Balances hidden" placeholder.
    if (sortedDates.isEmpty) {
      return widget.emptyState ?? buildNoTransactionsFound(context);
    }

    return Column(
      children: sortedDates.asMap().entries.map((entry) {
        final date = entry.value;
        return FadeInSlide(
          index: entry.key,
          child: ActivityDaySection(
            day: date,
            rows: [
              for (final tx in groupedTransactions[date]!)
                _buildUnifiedTransactionItem(tx, context, ref),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// The day a group of activity rows belongs to, in the app's language:
/// "Today", "Yesterday", "October 2" ("Hoje", "Ontem", "2 de outubro"),
/// with the year added once the day is in another year.
String activityDayLabel(BuildContext context, DateTime day) {
  final l10n = context.l10n;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(day.year, day.month, day.day);
  if (date == today) return l10n.activityToday;
  if (date == today.subtract(const Duration(days: 1))) {
    return l10n.activityYesterday;
  }
  final locale = l10n.localeName;
  final sameYear = date.year == today.year;
  try {
    return (sameYear ? DateFormat.MMMMd(locale) : DateFormat.yMMMMd(locale))
        .format(date);
  } catch (_) {
    // Date symbols not loaded for this locale (tests, early start).
    return (sameYear ? DateFormat.MMMMd() : DateFormat.yMMMMd()).format(date);
  }
}

/// One day of activity, the same on every surface: the day's name, then
/// that day's rows on one card, split by hairlines that start where the
/// text does.
class ActivityDaySection extends StatelessWidget {
  final DateTime day;
  final List<Widget> rows;

  const ActivityDaySection({super.key, required this.day, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(28.w, 14.h, 28.w, 8.h),
          child: Text(
            activityDayLabel(context, day),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
        PremiumGroupContainer(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(
                    color: c.borderSubtle,
                    height: 1,
                    thickness: 0.5,
                    indent: 16.w + _kRowIcon + 12.w,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The rows of one activity surface grouped by day, newest first, as a
/// list for a tab body. [timeOf] reads each entry's time.
List<Widget> activityDaySections<T>(
  List<T> entries, {
  required DateTime Function(T entry) timeOf,
  required Widget Function(T entry) rowOf,
}) {
  final days = <DateTime, List<Widget>>{};
  for (final entry in entries) {
    final t = timeOf(entry);
    days.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(rowOf(entry));
  }
  final sorted = days.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sorted) ActivityDaySection(day: day, rows: days[day]!),
  ];
}

/// Side of the leading icon tile on every activity row.
double get _kRowIcon => 40.sp;

/// Internal helper that handles the row/header amount text in two
/// modes:
///   * `isBtc == false` — render `amount` as a single Text in
///     `brightColor` (legacy behavior for USDC / fiat).
///   * `isBtc == true` — split `amount` into an optional sign prefix,
///     a numeric body (rendered through BtcAmountText so leading
///     zeros dim), and an optional trailing unit (" BTC" / " sats")
///     painted in `brightColor`. Handles strings like "0.00 011 172",
///     "0.00 011 172 BTC", "+ 12,345 sats", and the masked "••••".
class _AmountText extends StatelessWidget {
  final String amount;
  final Color brightColor;
  final Color dimColor;
  final bool isBtc;
  final double fontSize;
  final double letterSpacing;

  const _AmountText({
    required this.amount,
    required this.brightColor,
    required this.dimColor,
    required this.isBtc,
    this.fontSize = 18,
    this.letterSpacing = -0.6,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: brightColor,
      fontSize: fontSize.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (!isBtc || amount.contains('•')) {
      return Text(amount, style: style);
    }
    // Strip leading sign / whitespace into a "prefix" we re-prepend
    // in the bright color so it stays a deliberate signal.
    var prefix = '';
    var rest = amount;
    while (rest.isNotEmpty &&
        (rest.codeUnitAt(0) == 0x2B /* + */ ||
            rest.codeUnitAt(0) == 0x2D /* - */ ||
            rest.codeUnitAt(0) == 0x2212 /* − */ ||
            rest.codeUnitAt(0) == 0x20 /* space */)) {
      prefix += rest[0];
      rest = rest.substring(1);
    }
    // Detect trailing unit (last space + alpha-only token).
    String body = rest;
    String unit = '';
    final spaceIdx = rest.lastIndexOf(' ');
    if (spaceIdx > 0 && spaceIdx < rest.length - 1) {
      final tail = rest.substring(spaceIdx + 1);
      if (RegExp(r'^[A-Za-z]+$').hasMatch(tail)) {
        body = rest.substring(0, spaceIdx);
        unit = rest.substring(spaceIdx);
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefix.isNotEmpty) Text(prefix, style: style),
        BtcAmountText(
          text: body,
          style: style,
          brightColor: brightColor,
          dimColor: dimColor,
        ),
        if (unit.isNotEmpty) Text(unit, style: style),
      ],
    );
  }
}

/// The shared activity row used by every activity surface: the wallets
/// (Home, See all, Bitcoin, Dollars, Ledger, watch-only), Predictions and
/// Investing. [title] is one line; [subtitle] one line of context;
/// [amount] the main figure, signed by [flow]; [secondaryAmount] at most
/// one figure under it, in [secondaryColor] when it is a profit or loss.
/// [status] leads the context line only while something is unfinished.
/// [amountColor] colours the amount of a settled result only (a
/// prediction won or lost); every other amount is the primary text
/// colour.
Widget buildWalletActivityRow({
  required Widget leading,
  required Widget title,
  required String subtitle,
  required String amount,
  required String secondaryAmount,
  Color? secondaryColor,
  ActivityFlow flow = ActivityFlow.neutral,
  String? status,
  Color? statusColor,
  Color? amountColor,
  // False for a public figure (a market's chance or price on a search
  // result), which the balance privacy setting does not hide.
  bool maskValues = true,
  VoidCallback? onTap,
}) =>
    _TransactionRow(
        leading: leading,
        title: title,
        subtitle: subtitle,
        amount: amount,
        fiatAmount: secondaryAmount,
        secondaryColor: secondaryColor,
        amountColor: amountColor,
        flow: flow,
        status: status == null
            ? null
            : _RowStatus(text: status, color: statusColor ?? Colors.grey),
        maskValues: maskValues,
        onTap: onTap);

/// One-line activity row title ("Deposit", "Sold · G2", "Long BTC").
Widget activityRowTitle(String text) => _RowTitle(text);

class _TransactionRow extends ConsumerWidget {
  final Widget leading;
  final Widget title;
  final String subtitle;
  final String amount;
  final String fiatAmount;

  /// Colour of the secondary figure when it is a profit or a loss; the
  /// tertiary text colour otherwise.
  final Color? secondaryColor;

  /// Which way the money moved, for the amount's sign.
  final ActivityFlow flow;

  /// Colour of the amount when it is a settled result (a prediction won
  /// or lost); the primary text colour otherwise.
  final Color? amountColor;

  /// Optional status word that leads the context line ("Pending ·
  /// 14:21"), only while the row is not complete. Rendered as plain
  /// coloured text in the same size as the subtitle so the line reads as
  /// one sentence.
  final _RowStatus? status;
  final VoidCallback? onTap;

  /// When true the [amount] string is a BTC value (possibly with a
  /// trailing " BTC" / " sats" unit and optional sign prefix); render
  /// it through BtcAmountText so leading zeros dim. Defaults to false
  /// for non-BTC rows (USDC, fiat).
  final bool amountIsBtc;

  /// Whether the balance privacy setting hides the figures.
  final bool maskValues;

  const _TransactionRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.fiatAmount,
    required this.onTap,
    this.secondaryColor,
    this.amountColor,
    this.flow = ActivityFlow.neutral,
    this.status,
    this.amountIsBtc = false,
    this.maskValues = true,
  });

  /// [raw] with any sign the formatter put on it replaced by the row's.
  String _signed(String raw) {
    var body = raw.trimLeft();
    while (body.isNotEmpty && '+-−'.contains(body[0])) {
      body = body.substring(1).trimLeft();
    }
    return switch (flow) {
      ActivityFlow.moneyIn => '+$body',
      ActivityFlow.moneyOut => '−$body',
      ActivityFlow.neutral => body,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // At the deepest balance-privacy level the activity feed stays
    // visible but every row's monetary value is masked. The dim
    // bullet string mirrors the headline balance's mask.
    final valuesVisible = !maskValues ||
        ref.watch(settingsProvider.select((s) => s.transactionValuesVisible));
    final shownAmount = valuesVisible ? _signed(amount) : '••••';
    final shownFiat = valuesVisible ? fiatAmount : '';
    final row = Container(
      color: Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: TransactionRowContent(
        leading: _RowIconTile(child: leading),
        title: title,
        subtitle: Text.rich(
          TextSpan(children: [
            if (status != null) ...[
              TextSpan(
                  text: status!.text,
                  style: TextStyle(
                      color: status!.color, fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty) const TextSpan(text: ' · '),
            ],
            TextSpan(text: subtitle),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              height: 1.3),
        ),
        amount: _AmountText(
            amount: shownAmount,
            brightColor:
                valuesVisible ? amountColor ?? c.textPrimary : c.textPrimary,
            isBtc: amountIsBtc && valuesVisible,
            dimColor: c.textTertiary,
            fontSize: 16,
            letterSpacing: -0.3),
        secondaryAmount: shownFiat.isEmpty
            ? null
            : Text(shownFiat,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    color: secondaryColor ?? c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.3,
                    fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
    if (onTap == null) return row;
    return BouncyTouch(onTap: onTap!, child: row);
  }
}

/// The leading slot of every row: one 40 pt tile. The asset, venue and
/// market marks are drawn at their sheet size (44 pt, 48 with the pending
/// ring) and scaled into the tile, so the row and the detail sheet share
/// one icon and the pending ring stays around the tile.
class _RowIconTile extends StatelessWidget {
  final Widget child;

  /// The tile's side: 40 on a row, larger on the detail sheet's header.
  final double? size;
  const _RowIconTile({required this.child, this.size});

  @override
  Widget build(BuildContext context) {
    final side = size == null ? _kRowIcon : size!.sp;
    final scale = side / 44.sp;
    return SizedBox.square(
      dimension: side,
      child: OverflowBox(
        // Laid out at the mark's own size, then scaled into the tile.
        minWidth: 0,
        minHeight: 0,
        maxWidth: 48.sp,
        maxHeight: 48.sp,
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

String _formatRate(String rate) {
  final v = double.tryParse(rate);
  if (v == null) {
    return rate;
  }
  if (v >= 1) {
    return v.toStringAsFixed(2);
  }
  // For small rates, show up to 8 significant digits
  return v.toStringAsPrecision(8);
}

String _assetDisplayName(String code) {
  switch (code.toUpperCase()) {
    case 'BTC':
      return 'Bitcoin';
    case 'BTC-LN':
      return 'Lightning';
    case 'LIGHTNING':
      return 'Lightning';
    case 'USDC':
      return 'USDC';
    case 'USDT':
      return 'USDT';
    case 'ETH':
      return 'ETH';
    case 'SOL':
      return 'SOL';
    case 'BNB':
      return 'BNB';
    case 'XRP':
      return 'XRP';
    case 'LTC':
      return 'LTC';
    case 'TRX':
      return 'TRX';
    default:
      return code;
  }
}

String _cashAppDestinationLabel(BuildContext context, SwapOrder order) =>
    switch (cashAppDestination(order)) {
      CashAppDestination.predictions => context.l10n.predictions,
      CashAppDestination.investing => context.l10n.trading,
      // The dollar balance reads as plain dollars; the token's own
      // name stays on the row's asset code, never on a label.
      CashAppDestination.dollars => context.l10n.assetDollars,
      _ => _assetDisplayName(order.coinTo),
    };

/// One-line row title, the same on every row: verb first, ellipsized,
/// never two lines.
class _RowTitle extends StatelessWidget {
  final String text;
  const _RowTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The name of one leg of a conversion on its row: "Bitcoin",
/// "Lightning", "Dollar". Per the canonical rule table the literals
/// `USDC` / `USDC.e` / `USDT` / `pUSD` never appear in user-visible text;
/// the chain a dollar sits on is detail-sheet material.
String _swapLegLabel(BuildContext context, String ticker) {
  final upper = ticker.toUpperCase();
  final dollar = upper == 'USDC' ||
      upper == 'USDC.E' ||
      upper == 'USDT' ||
      upper == 'PUSD' ||
      upper == kOrchestraUsdAssetCode;
  return dollar ? context.l10n.activityDollar : _assetDisplayName(ticker);
}

/// A row's context line ending in the time: "to Predictions · 12:09".
String _withTime(String context, DateTime at) {
  final time = DateFormat('HH:mm').format(at);
  return context.isEmpty ? time : '$context · $time';
}

/// The top of every activity detail sheet: the row the person tapped,
/// opened up. Same chrome as the app's other sheets (drag handle, the
/// close X on the right, the Ask Sal chip on the left where the sheet
/// offers one), then the row's own icon tile, its title, its signed
/// amount and its one secondary figure, so the sheet reads as the row it
/// came from. [row] is the activity row the list draws for this
/// transaction (`_build*Item`, `buildWalletActivityRow`). [note] adds one
/// quiet line of context the row leaves out (a conversion's two legs).
class TransactionDetailHeader extends StatelessWidget {
  final Widget row;
  final String? note;

  /// Names the kind of detail this sheet shows (for example
  /// `btc_tx_detail`). When set, an Ask Sal chip sits on the sheet's
  /// top row so Sal can explain what a pending or confirmed transaction
  /// means. Only the surface name ever leaves the device — never an
  /// address, id, label, counterparty or amount.
  final String? advisorSurface;

  const TransactionDetailHeader({
    super.key,
    required this.row,
    this.note,
    this.advisorSurface,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final face = row as _TransactionRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: AppDecorations.dragHandle(context),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            if (advisorSurface != null)
              AskSalChip(
                advisorContext: AdvisorContext(surface: advisorSurface!),
              ),
            const Spacer(),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        _RowIconTile(size: 56, child: face.leading),
        SizedBox(height: 14.h),
        DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: face.title,
        ),
        SizedBox(height: 6.h),
        _AmountText(
          amount: face._signed(face.amount),
          brightColor: c.textPrimary,
          isBtc: face.amountIsBtc,
          dimColor: c.textTertiary,
          fontSize: 34,
          letterSpacing: -0.8,
        ),
        if (face.fiatAmount.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Text(
            face.fiatAmount,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: face.secondaryColor ?? c.textTertiary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (note != null && note!.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Text(
            note!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ],
        SizedBox(height: 20.h),
      ],
    );
  }
}

/// A date and time on a detail sheet, in the app's language
/// ("5 out 2026, 12:09" in Portuguese, "5 Oct 2026, 12:09" in English).
String activitySheetDate(BuildContext context, DateTime at) {
  try {
    return DateFormat('d MMM yyyy, HH:mm', context.l10n.localeName).format(at);
  } catch (_) {
    // Date symbols not loaded for this locale (tests, early start).
    return activitySheetDate(context, at);
  }
}

/// Addresses that settle into the user's own wallet — used by the
/// Spark-receive collapse in [_collapsePolymarketFlows] so an exchange
/// only hides an inbound payment when it verifiably paid US. The
/// Bitcoin address comes from the cached `addressProvider`; the Spark
/// address needs an SDK round-trip (`sparkSelfAddressProvider`) and
/// may not be resolved on the first frames — until it is, only
/// bet-flow-tagged exchanges can hide receives, which fails safe (the
/// receive row stays visible).
Set<String> activityOwnSettleAddresses(WidgetRef ref) {
  final own = <String>{};
  final btcAddress = ref.watch(addressProvider).bitcoinAddress;
  if (btcAddress.isNotEmpty) {
    own.add(btcAddress.trim().toLowerCase());
  }
  final sparkAddress = ref.watch(sparkSelfAddressProvider).valueOrNull;
  if (sparkAddress != null && sparkAddress.isNotEmpty) {
    own.add(sparkAddress.trim().toLowerCase());
  }
  return own;
}

/// Destination string of an outbound Spark payment, lowercased for
/// address comparison. The Breez `PaymentDetails` variants carry
/// "where did it go" in different fields:
///   * Lightning → the BOLT11 `invoice` we paid,
///   * Spark → `invoiceDetails.invoice` (Spark addresses ARE encoded
///     invoices, so this is the address string the send targeted),
///   * Deposit / Withdraw / Token → only a tx id / hash, no reusable
///     destination string → null (caller falls back to heuristics).
/// Cache-hydrated shells (`details == null`) also return null.
String? _sparkSendDestination(SparkTransaction tx) {
  final d = tx.details?.details;
  if (d is breez.PaymentDetails_Lightning) {
    return d.invoice.trim().toLowerCase();
  }
  if (d is breez.PaymentDetails_Spark) {
    return d.invoiceDetails?.invoice.trim().toLowerCase();
  }
  return null;
}

/// Orchestra BTC amounts arrive either already in sats (integer ≥ 1,
/// from the Flashnet API) or as a BTC decimal (from our own polling
/// conversion). Same detection the old `_groupSwapPairs` heuristic
/// used, extracted so every matcher normalises identically.
int _exchangeBtcFieldToSats(String btcField) {
  final raw = double.tryParse(btcField) ?? 0;
  return (raw >= 1 && raw == raw.roundToDouble())
      ? raw.round()
      : (raw * 100000000).round();
}

/// The dollar twin of [_exchangeBtcFieldToSats]. Orchestra dollar amounts
/// arrive either as six-decimal base units (the Flashnet API) or as a
/// plain dollar figure (our own polling conversion). Base units for any
/// amount worth showing are a large whole number; a dollar figure that
/// large AND exactly round is vanishingly rare on this rail, so the same
/// shape of test the sats helper uses reads them apart.
double _exchangeUsdFieldToDollars(String field) {
  final raw = double.tryParse(field) ?? 0;
  if (!raw.isFinite || raw <= 0) return 0;
  return (raw >= 10000 && raw == raw.roundToDouble()) ? raw / 1e6 : raw;
}

/// Whether [order] moved the dollar balance. The asset alone decides it:
/// this token lives on one rail, so a leg carrying it means dollars left
/// or dollars arrived. Shared by the dollar ledger's filter and by the
/// row that renders it, so the tab can never hide a row it should hold.
bool orchestraTouchesDollars(SwapOrder order) =>
    order.isOrchestra &&
    (order.coinTo.toUpperCase() == kOrchestraUsdAssetCode ||
        order.coinFrom.toUpperCase() == kOrchestraUsdAssetCode);

/// Whether [order] moved bitcoin at either end. A conversion with no
/// bitcoin leg never belongs in a bitcoin ledger: funding Predictions
/// out of dollars spends dollars, and the row was appearing on the
/// Bitcoin tab where nothing had happened.
bool orchestraTouchesBitcoin(SwapOrder order) {
  // A Cash App purchase is paid over Lightning, but that leg is the
  // payment rail, not the person's bitcoin. Only a purchase that delivers
  // bitcoin belongs in the bitcoin ledger; a dollar purchase is dollars
  // arriving and lives on the Dollars screen alone.
  if (order.isCashAppPurchase) return order.coinTo.toUpperCase() == 'BTC';
  return order.coinTo.toUpperCase() == 'BTC' ||
      order.coinFrom.toUpperCase() == 'BTC';
}

/// Whether [order] is a send to someone else paid from the dollar
/// balance. The Dollars send screen pays every destination this way
/// (bitcoin on-chain, Lightning, Spark, other dollars): the dollar token
/// leaves to Orchestra, which pays the recipient, so nothing lands in the
/// person's bitcoin.
bool _isDollarFundedSend(SwapOrder order, SwapActivityKind kind) =>
    kind == SwapActivityKind.send &&
    order.coinFrom.toUpperCase() == kOrchestraUsdAssetCode;

/// Whether the dollar transfer [tx] is the leg that settled [ex]: the
/// token send that funded a swap out of dollars, or the token receive
/// that delivered one into them. Same side, the dollar amount within two
/// percent (a cent at least) and within 30 minutes of the order.
bool _isDollarLegOf(UsdbTokenTransaction tx, SwapOrderTransaction ex) {
  final dollars = tx.amount.toInt() / 1e6;
  if (dollars <= 0) return false;
  final d = ex.details;
  if (!d.isOrchestra) return false;
  final isSend = tx.details.paymentType == breez.PaymentType.send;
  // A send funds a swap OUT of dollars; a receive settles one INTO
  // them. Reading the matching side keeps an unrelated transfer in the
  // other direction from swallowing this row.
  final coin = isSend ? d.coinFrom : d.coinTo;
  if (coin.toUpperCase() != kOrchestraUsdAssetCode) return false;
  final amount = _exchangeUsdFieldToDollars(
      isSend ? d.depositAmount : d.withdrawalAmount);
  if (amount <= 0) return false;
  if ((dollars - amount).abs() > max(0.01, amount * 0.02)) return false;
  return (tx.timestamp.millisecondsSinceEpoch -
              ex.timestamp.millisecondsSinceEpoch)
          .abs() <=
      30 * 60 * 1000;
}

/// Whether a send paid from dollars knows what the recipient got: its
/// delivered amount is at least one sat for bitcoin, or a cent for
/// anything else. Before the first status check the row holds the
/// quote's estimate, which the send screen saves to two decimals, so a
/// bitcoin estimate reads as 0 until the real figure lands.
@visibleForTesting
bool dollarSendDeliveredKnown(SwapOrder order) {
  final human = orchestraRowAmount(order.withdrawalAmount, order.coinTo);
  if (!human.isFinite || human <= 0) return false;
  if (order.coinTo.toUpperCase() == 'BTC') {
    return (human * 100000000).round() > 0;
  }
  return human >= 0.005;
}

/// The rows one activity surface shows, newest first, from the wallet's
/// sorted transactions.
///
/// The surface filters run before the leg collapse. A leg (the Spark or
/// dollar transfer that settled a conversion) is hidden only behind a row
/// that is still on the list, so a move can never lose both its legs and
/// its own row: when the row is filtered out, or nothing matches, the raw
/// leg stays visible. Running the collapse first hid a Predictions cash-out
/// to dollars twice over on Home: its dollar receive went behind the
/// conversion row, and the bitcoin-ledger filter then dropped that row.
///
/// A send belongs to the balance that paid it. A send paid from dollars
/// (to a bitcoin, Lightning or dollar address) shows on the Dollars tab
/// alone; every other surface drops it together with the token transfer
/// that funded it, since both are the Dollars ledger's.
///
/// [keepVenueMoves] keeps every Predictions move's own conversion row even
/// when a Predictions deposit or withdrawal row beside it tells the story
/// (the Breakdown donut weighs the conversion, in the ledger's own unit;
/// the Predictions row is in dollars on the venue's side).
///
/// [classify] reads a conversion's intent; tests pass their own.
List<BaseTransaction> assembleActivityRows(
  List<BaseTransaction> sorted, {
  required Set<String> ownAddresses,
  required bool isHardwareOrWatchOnly,
  required bool onlyUsdb,
  bool keepVenueMoves = false,
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  // Home activity is bitcoin-anchored (user decision): pool deposits
  // and withdrawals stay (they move wallet funds), but pool-internal
  // events (placed / sold / won predictions) live on the Predictions
  // tab's own Activity section, not here.
  var rows = sorted.where((tx) {
    if (tx is PolymarketTransaction) {
      return tx.activityType == ActivityType.deposit ||
          tx.activityType == ActivityType.withdraw;
    }
    return true;
  }).toList();

  if (isHardwareOrWatchOnly) {
    // Spark-, Polymarket- and dollar-only flows don't apply to hardware or
    // watch-only wallets. Swap orders that involve the wallet are mirrored
    // into its cache slot by `mergeSwapOrder` and stay, and so do Outlogic
    // orders, which settle on-chain to the wallet that started them.
    rows = rows
        .where((tx) =>
            tx is! PolymarketTransaction &&
            tx is! PolymarketUsdcReceive &&
            tx is! UsdbTokenTransaction)
        .toList();
  }

  if (onlyUsdb) {
    // USD tab: the dollar ledger only. Every conversion with a dollar leg
    // spends or fills this balance too, so it belongs here, including a
    // venue funded from or paid out to dollars (owner decision).
    // A send belongs to the balance that paid it, so bitcoin sent to a
    // dollar address stays on the bitcoin side.
    rows = rows.where((tx) {
      if (tx is UsdbTokenTransaction) return true;
      if (tx is! SwapOrderTransaction) return false;
      final d = tx.details;
      if (!orchestraTouchesDollars(d)) return false;
      if (d.isCashAppPurchase) return true;
      final kind = classify(d);
      return kind != SwapActivityKind.send || _isDollarFundedSend(d, kind);
    }).toList();
  } else {
    // A conversion that only touches dollars is the dollar ledger's, not
    // this one's. A venue move is the exception: money entering or leaving
    // Predictions or Investing is always one row on every surface, in
    // whichever unit it moved.
    //
    // A send paid from dollars is the dollar ledger's too, whatever it
    // delivers (user decision: "All sends from Dollars should only show
    // up in Dollars"). Sending dollars to someone's bitcoin address used
    // to show here as a bitcoin "Sent", because the order delivers BTC.
    // The send leaves with the token transfer that funded it: both are
    // the Dollars ledger's, and the Dollars tab shows the send as one row.
    final dollarSends = <SwapOrderTransaction>[];
    rows = rows.where((tx) {
      if (tx is! SwapOrderTransaction) return true;
      final d = tx.details;
      if (!orchestraTouchesDollars(d)) return true;
      if (d.isCashAppPurchase) return orchestraTouchesBitcoin(d);
      final kind = classify(d);
      if (_isDollarFundedSend(d, kind)) {
        dollarSends.add(tx);
        return false;
      }
      if (orchestraTouchesBitcoin(d)) return true;
      return kind.isPredictions || kind.isInvesting;
    }).toList();
    if (dollarSends.isNotEmpty) {
      rows = rows
          .where((tx) =>
              tx is! UsdbTokenTransaction ||
              tx.details.paymentType != breez.PaymentType.send ||
              !dollarSends.any((ex) => _isDollarLegOf(tx, ex)))
          .toList();
    }
  }

  // One row per user intent, judged only against rows still on the list.
  return _collapsePolymarketFlows(
    rows,
    ownAddresses: ownAddresses,
    keepVenueMoves: keepVenueMoves,
    classify: classify,
  );
}

/// ─── Polymarket / Orchestra flow collapse ────────────────────────────
///
/// One activity row per user intent. A single bet used to paint up to
/// four rows (Spark funding send → "Predictions deposit" exchange →
/// "Placed prediction", plus the claim flow's mirror three) because
/// every plumbing leg of the BTC↔USDC.e conversion rendered
/// independently. This pass hides the moved-money legs and keeps the
/// user-meaningful row:
///
///   * "Placed prediction" / "Won prediction" (PolymarketTransaction)
///     — never hidden.
///   * Orchestra "Predictions deposit/withdraw" exchange rows — hidden
///     only when a Polymarket deposit/withdraw row on the same side sits
///     within ±30 min of it in [transactions]. A bet-flow tag alone no
///     longer hides one: the bet and claim rows it used to stand behind
///     are not on these surfaces, so the move must keep its own row.
///   * Spark SENDS — hidden deterministically when the payment's own
///     destination string equals ANY listed exchange's deposit address
///     (it IS the swap-funding leg, whatever the provider), or the tx id
///     was tagged at send time AND a bitcoin-funded exchange it can stand
///     behind is listed within ±30 min. Only when no destination is
///     extractable does a tightened amount/time heuristic run (±2% AND
///     ±10 min AND direction agreement — the old ±5%/±5 min version
///     ate unrelated sends).
///   * Spark RECEIVES — hidden only on a tight settle-side match: an
///     exchange delivering BTC whose withdrawal amount matches ±2%
///     within ±30 min AND (settles to one of the user's own addresses
///     OR is bet-flow tagged). Fallback: a Spark-protocol receive
///     within ±10 min of a Predictions deposit/withdraw exchange row.
///     Anything looser stays visible — money appearing in the wallet
///     must never vanish unless we're confident it's an internal leg.
///
/// [transactions] must already be the surface's rows (see
/// [assembleActivityRows]): every hide here is justified by a row in the
/// same list, so a row filtered out beforehand cannot hide anything.
///
/// Runs on every activity surface built from `TransactionList`. The
/// settle-side match above is the fix for the claim screenshot where
/// the Spark receive survived next to its withdraw row: the old rules'
/// ±2 min window was measured against the exchange row's CREATION
/// time — Orchestra routinely delivers 3–10 min later.
List<BaseTransaction> _collapsePolymarketFlows(
  List<BaseTransaction> transactions, {
  required Set<String> ownAddresses,
  bool keepVenueMoves = false,
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  // Snapshot the Hive tag boxes once per pass, not per row.
  final betFlowOrderIds = PolymarketSparkTxsService.orchestraOrderSnapshot();
  final betFlowSparkIds = PolymarketSparkTxsService.snapshot();

  final exchanges = <SwapOrderTransaction>[];
  final polymarketRows = <PolymarketTransaction>[];
  // Every exchange's (lowercased) deposit address — a Spark send whose
  // destination is one of these funded a swap, regardless of provider.
  final exchangeDepositAddresses = <String>{};
  for (final tx in transactions) {
    if (tx is SwapOrderTransaction) {
      exchanges.add(tx);
      final addr = tx.details.depositAddress.trim().toLowerCase();
      if (addr.isNotEmpty) {
        exchangeDepositAddresses.add(addr);
      }
    } else if (tx is PolymarketTransaction) {
      polymarketRows.add(tx);
    }
  }
  if (exchanges.isEmpty && betFlowSparkIds.isEmpty) {
    return transactions;
  }

  bool isPolymarketLeg(SwapOrder d) => classify(d).isPredictions;

  bool hideExchange(SwapOrderTransaction ex) {
    // This is new money paid from Cash App, never the funding leg of a bet.
    if (ex.details.isCashAppPurchase) return false;
    if (keepVenueMoves) return false;
    final d = ex.details;
    if (!isPolymarketLeg(d)) {
      return false;
    }
    // Same-side Polymarket row within ±30 min → that row tells the story
    // and this conversion leg is plumbing. Only rows still on this list
    // count: a bet-flow tag, or a placed/won prediction filtered out
    // upstream, used to hide the move with nothing left in its place.
    final isDepositSide = classify(d).isDeposit;
    final exMs = ex.timestamp.millisecondsSinceEpoch;
    for (final poly in polymarketRows) {
      if ((poly.timestamp.millisecondsSinceEpoch - exMs).abs() >
          30 * 60 * 1000) {
        continue;
      }
      final t = poly.activityType;
      final sameSide = isDepositSide
          ? (t == ActivityType.trade || t == ActivityType.deposit)
          : (t == ActivityType.redeem || t == ActivityType.withdraw);
      if (sameSide) {
        return true;
      }
    }
    // Manual move — no bet/claim nearby. Keep the single exchange row.
    return false;
  }

  // A tagged funding send stands behind the bitcoin-funded conversion it
  // paid for. With no such row listed near it, it is the only trace of
  // the money leaving and stays visible.
  bool hasFundedExchangeNear(SparkTransaction tx) {
    final txMs = tx.timestamp.millisecondsSinceEpoch;
    for (final ex in exchanges) {
      final d = ex.details;
      if (d.coinFrom.toUpperCase() != 'BTC' || d.isCashAppPurchase) continue;
      if ((txMs - ex.timestamp.millisecondsSinceEpoch).abs() <=
          30 * 60 * 1000) {
        return true;
      }
    }
    return false;
  }

  bool hideSparkSend(SparkTransaction tx) {
    // Deterministic first: the payment's own destination string. A
    // match against an exchange deposit address means this send IS the
    // swap-funding leg — hide unconditionally.
    final dest = _sparkSendDestination(tx);
    if (dest != null && dest.isNotEmpty) {
      if (exchangeDepositAddresses.contains(dest)) {
        return true;
      }
      // Destination known and NOT an exchange address → a real send
      // somewhere else. No heuristic fallback; only the explicit
      // funding tag may still hide it (the tag is stamped on this
      // exact tx id at send time), and only behind a listed exchange.
      return betFlowSparkIds.contains(tx.id) && hasFundedExchangeNear(tx);
    }
    if (betFlowSparkIds.contains(tx.id) && hasFundedExchangeNear(tx)) {
      return true;
    }
    // Fallback (no destination on the payload, e.g. cache-hydrated
    // shells): tightened amount/time heuristic against Orchestra
    // exchanges whose DEPOSIT side is BTC (direction agreement — an
    // outbound send can only ever be the deposit half).
    final amountSats = tx.amountSats.abs();
    final txMs = tx.timestamp.millisecondsSinceEpoch;
    for (final ex in exchanges) {
      final d = ex.details;
      if (!d.isOrchestra || d.coinFrom != 'BTC' || d.isCashAppPurchase) {
        continue;
      }
      final fieldSats = _exchangeBtcFieldToSats(d.depositAmount);
      if (fieldSats <= 0) {
        continue;
      }
      final tolSats = max(1, (fieldSats * 0.02).round());
      if ((amountSats - fieldSats).abs() > tolSats) {
        continue;
      }
      if ((txMs - ex.timestamp.millisecondsSinceEpoch).abs() > 10 * 60 * 1000) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool hideSparkReceive(SparkTransaction tx) {
    // NOTE: the bet-flow tag box is deliberately IGNORED for receives
    // — an earlier auto-match bug left stale tags on unrelated inbound
    // payments (see the claim-window matcher history), so a tag alone
    // must never hide incoming money.
    final amountSats = tx.amountSats.abs();
    final txMs = tx.timestamp.millisecondsSinceEpoch;
    // Tight settle-side match: an exchange delivering BTC back to us.
    for (final ex in exchanges) {
      final d = ex.details;
      if (d.coinTo.toUpperCase() != 'BTC') {
        continue;
      }
      final fieldSats = _exchangeBtcFieldToSats(d.withdrawalAmount);
      if (fieldSats <= 0) {
        continue;
      }
      // A dollar or Investing withdrawal is our own money coming back to
      // our own Spark address by construction (the flow resolves the
      // recipient to the wallet's address before anything moves), so
      // the row is the one that tells the story and the receipt is its
      // settle leg. Its stored amount is the quote's estimate until the
      // poll writes the delivered figure, so it gets a wider match than
      // the two percent an exact settled amount is held to.
      final kind = classify(d);
      final ownWithdrawal = d.isOrchestra &&
          (kind == SwapActivityKind.dollarWithdrawal ||
              kind == SwapActivityKind.investingWithdrawal);
      final tolSats =
          max(1, (fieldSats * (ownWithdrawal ? 0.10 : 0.02)).round());
      if ((amountSats - fieldSats).abs() > tolSats) {
        continue;
      }
      final windowMs = (ownWithdrawal ? 60 : 30) * 60 * 1000;
      if ((txMs - ex.timestamp.millisecondsSinceEpoch).abs() > windowMs) {
        continue;
      }
      // Amount + time alone can coincide; require ownership evidence:
      // the exchange settles to one of OUR addresses, it was created
      // by the bet/claim flow (tagged order id), or it is one of our
      // own withdrawals above.
      final settleAddr = d.withdrawalAddress.trim().toLowerCase();
      final settlesToSelf =
          settleAddr.isNotEmpty && ownAddresses.contains(settleAddr);
      if (settlesToSelf ||
          ownWithdrawal ||
          betFlowOrderIds.contains(ex.id)) {
        return true;
      }
    }
    // Fallback for exchanges with missing/foreign-format settle
    // addresses (ownership can't be proven): a Spark-protocol receive
    // may only be hidden when it matches a Predictions WITHDRAW leg on
    // amount (±2%), direction (exchange delivers BTC) AND time
    // (±10 min — Orchestra routinely lands 3–10 min after the exchange
    // row is created). Time alone is NOT enough: a timestamp-only rule
    // here hid genuine P2P receives that happened to land near a bet,
    // on every surface at once — money appearing with no row to
    // explain it. If the exchange's withdrawalAmount is unparseable,
    // the receive stays visible. Lightning / on-chain receives always
    // stay visible on this branch — those are plausibly real money
    // from outside even when the timing lines up.
    if (tx.sparkType == SparkTransactionType.spark) {
      for (final ex in exchanges) {
        final d = ex.details;
        if (!isPolymarketLeg(d)) {
          continue;
        }
        if (d.coinTo.toUpperCase() != 'BTC') {
          continue;
        }
        final fieldSats = _exchangeBtcFieldToSats(d.withdrawalAmount);
        if (fieldSats <= 0) {
          continue;
        }
        final tolSats = max(1, (fieldSats * 0.02).round());
        if ((amountSats - fieldSats).abs() > tolSats) {
          continue;
        }
        if ((txMs - ex.timestamp.millisecondsSinceEpoch).abs() >
            10 * 60 * 1000) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  /// The dollar leg of a conversion. Moving bitcoin into dollars painted
  /// two rows for one action — the swap AND the token transfer that
  /// settled it — the way a Predictions or Investing deposit used to.
  /// The swap row is the user-meaningful one (it names both ends), so
  /// the settle leg goes, and a dollar transfer with no conversion
  /// beside it still stands on its own.
  bool hideDollarLeg(UsdbTokenTransaction tx) =>
      exchanges.any((ex) => _isDollarLegOf(tx, ex));

  return transactions.where((tx) {
    if (tx is SwapOrderTransaction) {
      return !hideExchange(tx);
    }
    if (tx is UsdbTokenTransaction) {
      return !hideDollarLeg(tx);
    }
    if (tx is SparkTransaction) {
      return tx.type == TransactionType.sent
          ? !hideSparkSend(tx)
          : !hideSparkReceive(tx);
    }
    return true;
  }).toList();
}

Widget _buildUnifiedTransactionItem(
    BaseTransaction transaction, BuildContext context, WidgetRef ref) {
  if (transaction is BitcoinTransaction) {
    return _buildBitcoinItem(transaction, context, ref);
  }
  if (transaction is SparkTransaction) {
    return _buildSparkItem(transaction, context, ref);
  }
  if (transaction is SparkUnclaimedDeposit) {
    return _buildUnclaimedItem(transaction, context, ref);
  }
  if (transaction is SparkPendingDeposit) {
    return _buildSparkPendingDepositItem(transaction, context, ref);
  }
  if (transaction is MempoolAddressTransaction) {
    return _buildMempoolItem(transaction, context, ref);
  }
  if (transaction is UsdbTokenTransaction) {
    return _buildUsdbTokenItem(transaction, context, ref);
  }
  if (transaction is SwapOrderTransaction) {
    return _buildSwapOrderItem(transaction, context, ref);
  }
  if (transaction is PolymarketTransaction) {
    return _buildPolymarketItem(transaction, context, ref);
  }
  if (transaction is PolymarketUsdcReceive) {
    return _buildPolymarketUsdcReceiveItem(transaction, context, ref);
  }
  if (transaction is OutlogicTransaction) {
    return _buildOutlogicItem(transaction, context, ref);
  }
  return const SizedBox.shrink();
}

/// Public wrapper around [_buildUnifiedTransactionItem] so out-of-file
/// callers (the unified "Search kute" sheet) can render the SAME
/// per-type activity row — correct leading asset icon (Bitcoin / Spark /
/// swap / Outlogic / Polymarket / USDB) AND the canonical tap
/// wiring — instead of re-deriving the icon logic and drifting from the
/// activity feed. The private builder stays private; this is the single
/// exported entrypoint.
Widget buildUnifiedTransactionItem(
        BaseTransaction transaction, BuildContext context, WidgetRef ref) =>
    _buildUnifiedTransactionItem(transaction, context, ref);

/// Public dispatcher that opens the detail surface for any
/// [BaseTransaction], switching on the concrete type and calling the
/// matching private opener used by the activity-feed rows. Added so
/// out-of-file callers (e.g. the unified search screen) can open a
/// transaction's detail sheet without each opener having to be made
/// public individually. Mirrors the `onTap` wiring in the per-type
/// `_build*Item` builders above.
///
/// Returns a `Future` for call-site ergonomics; the underlying openers
/// fire `showModalBottomSheet` / route pushes and return synchronously.
///
/// Start the explorer lookup for an on-chain row the moment it is tapped, so
/// the request is already in flight while the sheet animates in and its flow
/// graph has something to draw on arrival. Lightning and Spark rows have no
/// on-chain braid and are skipped.
void _warmTxDetails(BaseTransaction transaction) {
  String? txid;
  if (transaction is BitcoinTransaction) {
    txid = transaction.id;
  } else if (transaction is MempoolAddressTransaction) {
    txid = transaction.details.txid;
  } else if (transaction is SparkPendingDeposit) {
    txid = transaction.mempoolTx.txid;
  }
  if (txid == null || txid.isEmpty) return;
  unawaited(MempoolAddressService.prefetchTransactions([txid]));
}

Future<void> openTransactionDetails(
    BuildContext context, WidgetRef ref, BaseTransaction transaction) async {
  _warmTxDetails(transaction);
  if (transaction is BitcoinTransaction) {
    _showBitcoinTxDetails(context, ref, transaction);
  } else if (transaction is SparkTransaction) {
    _showSparkTxDetails(context, ref, transaction);
  } else if (transaction is SparkUnclaimedDeposit) {
    _openUnclaimedDeposit(context, ref, transaction);
  } else if (transaction is SparkPendingDeposit) {
    _showSparkPendingDepositDetails(context, ref, transaction);
  } else if (transaction is MempoolAddressTransaction) {
    // Mirror the row tap: seed the on-chain tx lookup + open the modal.
    ref.read(transactionSearchProvider.notifier).state = TransactionSearchModel(
      isLiquid: false,
      txid: transaction.details.txid,
    );
    context.push('/search_modal');
  } else if (transaction is UsdbTokenTransaction) {
    _showUsdbTokenTxDetails(context, ref, transaction);
  } else if (transaction is SwapOrderTransaction) {
    _showSwapOrderDetails(context, ref, transaction);
  } else if (transaction is PolymarketTransaction) {
    _showPolymarketTxDetails(context, ref, transaction);
  } else if (transaction is PolymarketUsdcReceive) {
    _showPolymarketUsdcReceiveDetails(context, ref, transaction);
  } else if (transaction is OutlogicTransaction) {
    _showOutlogicTxDetails(context, ref, transaction);
  }
}

/// Inbound USDC / USDC.e transfer to the Polymarket Safe — indexed
/// via Etherscan and rendered to match the rest of the activity
/// feed (`Sent Bitcoin`-style row: 44sp asset icon with corner
/// arrow, asset chip in the title, address subtitle, signed amount
/// + fiat sub on the right).
Widget _buildPolymarketUsdcReceiveItem(
    PolymarketUsdcReceive tx, BuildContext context, WidgetRef ref) {
  // USDC is USD-pegged — render through `formatPolyAmount` so the
  // row honors the global Predictions denomination setting (sats/BTC
  // in bitcoin mode, user's fiat in fiat mode). Asset identity stays
  // on the leading USDC icon; the row never spells "USDC" out loud.
  // The sender address lives in the sheet's Nerd data, not on the row.
  final fiatStr = formatPolyAmount(ref, tx.amount.toDouble());
  return _TransactionRow(
    onTap: () => _showPolymarketUsdcReceiveDetails(context, ref, tx),
    leading: _AssetTxIcon(assetCode: 'USDC', isSend: false),
    title: _RowTitle(context.l10n.received),
    subtitle: DateFormat('HH:mm').format(tx.timestamp),
    amount: fiatStr,
    flow: ActivityFlow.moneyIn,
    fiatAmount: '',
  );
}

void _showPolymarketUsdcReceiveDetails(
    BuildContext context, WidgetRef ref, PolymarketUsdcReceive tx) {
  TrackingService.transactionDetailViewed('polymarket_usdc_receive');
  final c = context.colors;
  // Sheet headline follows the global Predictions denomination
  // setting — sats/BTC in bitcoin mode, user's fiat in fiat mode.
  // Asset identity stays on the leading USDC icon.
  final fiatStr = formatPolyAmount(ref, tx.amount.toDouble());
  final dateStr = activitySheetDate(context, tx.timestamp);
  final hash = tx.id.split(':').first;
  showAppBottomSheet(
    context: context,
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildPolymarketUsdcReceiveItem(tx, context, ref),
                  advisorSurface: 'polymarket_deposit_tx_detail',
                ),
              ),
              _sheetDetailRow(c, context.l10n.date, dateStr),
              _sheetDetailRow(c, context.l10n.status, context.l10n.completed,
                  valueColor: AppColors.success),
              // Network-free deposit flow: sender → Predictions balance.
              // Amount lives ON the graph (no duplicate text row).
              SizedBox(height: 6.h),
              SimpleFlowGraph(
                source: SimpleFlowNode(
                    label: context.l10n.activitySender, amount: fiatStr),
                destinations: [
                  SimpleFlowNode(
                    label: context.l10n.predictions,
                    amount: fiatStr,
                    highlight: true,
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              _NerdDataSection(children: [
                _sheetDetailRow(c, context.l10n.network,
                    orchestraChainDisplayName('POLYGON')),
                _sheetDetailRow(
                    c, context.l10n.activityBlock, tx.blockNumber.toString()),
                _sheetDetailRow(c, context.l10n.from, tx.fromAddress,
                    copiable: true, isAddress: true, ctx: ctx),
                _sheetDetailRow(c, context.l10n.activityTxHash, hash,
                    copiable: true, isAddress: true, ctx: ctx),
              ]),
              SizedBox(height: 16.h),
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      launchUrl(Uri.parse('https://polygonscan.com/tx/$hash')),
                  icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                  label: Text(
                    context.l10n.activityViewOnBlockchain,
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.buttonBorder),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Detail sheet for a same-asset USDC / USDC.e send on Polygon
/// (provider='Native' swap-order row). The standard swap-order sheet
/// renders these as a USDC → USDC swap pair, which is wrong — the
/// asset doesn't change, only the address. Mirror the
/// PolymarketUsdcReceive sheet style so send + receive look like
/// peers in the activity feed, and link to Polygonscan for the
/// destination address (we don't currently persist the on-chain
/// tx hash for native sends).
void _showNativeUsdcSendDetails(
    BuildContext context, WidgetRef ref, SwapOrderTransaction tx) {
  TrackingService.transactionDetailViewed('native_usdc_send');
  final c = context.colors;
  final details = tx.details;
  // Sheet headline follows the global Predictions denomination
  // setting — sats/BTC in bitcoin mode, user's fiat in fiat mode.
  // Asset identity stays on the leading USDC icon.
  final dateStr = activitySheetDate(context, tx.timestamp);
  showAppBottomSheet(
    context: context,
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildNativeUsdcSendRow(tx, context, ref),
                  advisorSurface: 'polymarket_withdrawal_tx_detail',
                ),
              ),
              _sheetDetailRow(c, context.l10n.date, dateStr),
              _sheetDetailRow(c, context.l10n.status,
                  tx.isComplete ? context.l10n.completed : context.l10n.pending,
                  valueColor: tx.isComplete
                      ? AppColors.success
                      : context.colors.accent),
              _NerdDataSection(children: [
                _sheetDetailRow(c, context.l10n.network,
                    orchestraChainDisplayName('POLYGON')),
                _sheetDetailRow(c, context.l10n.to, details.withdrawalAddress,
                    copiable: true, isAddress: true, ctx: ctx),
              ]),
              SizedBox(height: 16.h),
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(
                      'https://polygonscan.com/address/${details.withdrawalAddress}')),
                  icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                  label: Text(
                    context.l10n.activityViewOnBlockchain,
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.buttonBorder),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildBitcoinItem(
    BitcoinTransaction tx, BuildContext context, WidgetRef ref) {
  final details = tx.btcDetails;
  final labelWalletId = ref.watch(bitcoinLabelsWalletIdProvider);
  final label = labelWalletId == null
      ? null
      : ref.watch(bitcoinLabelsProvider(labelWalletId))[
          bitcoinTransactionLabelKey(tx.id)];
  // Live path uses the existing TxDetails-backed formatters; cache
  // path (details == null, sourced from the Hive snapshot) derives
  // the same row from the primitive received/sent fields exposed
  // via [BitcoinTransaction.receivedSats]/[sentSats] and
  // [BaseTransaction.isConfirmed]. Both paths produce identical
  // visual output for the home Activity row; the live path retains
  // tap-to-detail richness.
  final isReceive = details != null
      ? transactionIsReceived(details, ref)
      : tx.type == TransactionType.received;
  final isPending = details != null
      ? details.chainPosition is! ConfirmedChainPosition
      : !tx.isConfirmed;
  final amountStr = details != null
      ? transactionAmount(details, ref)
      : _formatBtcSats(tx.receivedSats - tx.sentSats, ref);
  final fiatStr = details != null
      ? transactionAmountInFiat(details, ref)
      : ref.watch(
          conversionToFiatProvider((tx.receivedSats - tx.sentSats).abs()));

  Widget iconWidget = _AssetTxIcon(assetCode: 'BTC', isSend: !isReceive);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  return _TransactionRow(
    onTap: () => _showBitcoinTxDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(isReceive ? context.l10n.received : context.l10n.sent),
    // The payment label when there is one, otherwise just the time. The
    // rail is Nerd data on the detail sheet.
    subtitle: label ?? DateFormat('HH:mm').format(tx.timestamp),
    status: isPending
        ? _RowStatus(text: context.l10n.pending, color: context.colors.warning)
        : null,
    amount: amountStr,
    flow: isReceive ? ActivityFlow.moneyIn : ActivityFlow.moneyOut,
    amountIsBtc: true,
    fiatAmount: fiatStr,
  );
}

/// Helper used when rendering cache-sourced [BitcoinTransaction]s
/// whose live `btcDetails` is null. Mirrors the formatting that
/// `transactionAmount(TxDetails)` produces for the live path so the
/// row text is visually identical regardless of source.
String _formatBtcSats(int signedSats, WidgetRef ref) {
  final settings = ref.read(settingsProvider);
  final unit = settings.btcFormat;
  // Direction is conveyed by the row's icon + amount color; the
  // `+`/`-` prefix is redundant and reads as noise. ₿ prefix (BIP-177)
  // replaces the trailing `sats`/`BTC` unit suffix; mirrors the
  // `conversionProvider` cache path so live and cache produce identical
  // strings.
  final magnitude = signedSats.abs();
  return '₿${magnitude.toFormattedString(unit)}';
}

Widget _buildSparkItem(
    SparkTransaction tx, BuildContext context, WidgetRef ref) {
  // Use the safe accessors so a Hive-hydrated row (no live
  // `details`) still renders the user-visible bits — direction,
  // amount, channel, pending dot — from the cached primitives.
  final isSend = tx.type == TransactionType.sent;
  final direction = isSend ? context.l10n.sent : context.l10n.received;
  final assetCode = tx.sparkType == SparkTransactionType.lightning
      ? 'Lightning'
      : tx.sparkType == SparkTransactionType.spark
          ? 'Spark'
          : 'BTC';
  final isPending = tx.isPending;

  Widget iconWidget = _AssetTxIcon(assetCode: assetCode, isSend: isSend);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  return _TransactionRow(
    onTap: () => _showSparkTxDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(direction),
    // The rail (Lightning / Spark / on-chain) is Nerd data on the sheet.
    subtitle: DateFormat('HH:mm').format(tx.timestamp),
    status: isPending
        ? _RowStatus(text: context.l10n.pending, color: context.colors.warning)
        : null,
    amount: sparkTransactionAmount(tx, ref),
    flow: isSend ? ActivityFlow.moneyOut : ActivityFlow.moneyIn,
    amountIsBtc: true,
    fiatAmount: sparkTransactionAmountInFiat(tx, ref),
  );
}

Widget _buildOutlogicItem(
    OutlogicTransaction tx, BuildContext context, WidgetRef ref) {
  final isBuy = tx.isBuy;
  final fiatAsset = tx.fiatAsset;
  final fiatAmt = tx.fiatAmount;
  final status = tx.details.status;
  final isPending = tx.isPending;

  // Status badge for non-completed orders
  _RowStatus? badge;
  if (status == 'COMPLETED') {
    badge = null;
  } else if (status == 'CANCELED' ||
      status == 'EXPIRED' ||
      status == 'REJECTED') {
    badge = _RowStatus(text: status.capitalize(), color: AppColors.marketDown);
  } else if (status == 'REFUNDED') {
    badge = _RowStatus(text: context.l10n.refunded, color: AppColors.info);
  } else if (status == 'DEPOSIT_CONFIRMED' || status == 'APPROVED') {
    // User's action is done; treat as effectively complete in the UI.
    badge = _RowStatus(
        text: _outlogicStatusLabel(context, status), color: AppColors.success);
  } else {
    badge = _RowStatus(
        text: _outlogicStatusLabel(context, status),
        color: context.colors.warning);
  }

  final direction = isBuy
      ? context.l10n.activityRowBought('Bitcoin')
      : context.l10n.activityRowSold('Bitcoin');

  Widget iconWidget = _OutlogicTxIcon(isBuy: isBuy, fiatAsset: fiatAsset);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  return _TransactionRow(
    onTap: () => _showOutlogicTxDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(direction),
    // The provider is Nerd data on the sheet.
    subtitle: DateFormat('HH:mm').format(tx.timestamp),
    status: badge,
    amount: '$fiatAmt $fiatAsset',
    fiatAmount: isBuy
        ? '${tx.details.fromAmount.toStringAsFixed(2)} $fiatAsset'
        : '',
  );
}

String _outlogicStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'WAITING_FOR_DEPOSIT':
      return context.l10n.activityAwaitingDeposit;
    case 'AWAITING_DEPOSIT':
      return context.l10n.activityAwaitingDeposit;
    case 'DEPOSIT_RECEIVED':
      return context.l10n.activityDepositReceived;
    case 'DEPOSIT_CONFIRMED':
      return context.l10n.confirmed;
    case 'APPROVED':
      return context.l10n.activityApproved;
    default:
      return status.replaceAll('_', ' ').capitalize();
  }
}

void _showOutlogicTxDetails(
    BuildContext context, WidgetRef ref, OutlogicTransaction tx) {
  TrackingService.transactionDetailViewed('outlogic');
  final c = context.colors;
  final order = tx.details;
  final isBuy = tx.isBuy;
  final dateStr = activitySheetDate(context, tx.timestamp);

  String statusText = _outlogicStatusLabel(context, order.status);
  Color statusColor;
  if (order.status == 'COMPLETED' ||
      order.status == 'DEPOSIT_CONFIRMED' ||
      order.status == 'APPROVED') {
    statusColor = AppColors.success;
  } else if (order.isTerminal) {
    statusColor = AppColors.error;
  } else {
    statusColor = context.colors.accent;
  }

  showAppBottomSheet(
    context: context,
    // `ctx` (the live modal-route context), not the captured outer
    // `context`: the tx row is often scrolled out and deactivated by
    // the time the sheet builds, so MediaQuery.of(context) walked a
    // dead element → "Null check operator used on a null value".
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer(
                  builder: (context, ref, _) => TransactionDetailHeader(
                    row: _buildOutlogicItem(tx, context, ref),
                    advisorSurface: 'outlogic_tx_detail',
                  ),
                ),
                _sheetDetailRow(c, context.l10n.date, dateStr),
                _sheetDetailRow(c, context.l10n.status, statusText,
                    valueColor: statusColor),
                ..._fiatSnapshotRows(context, ref, c, order.id),
                if (order.trade != null)
                  _sheetDetailRow(c, context.l10n.youReceive,
                      '${order.trade!.toAmount} ${order.trade!.toAsset}'),
                // SEPA bank details stay VISIBLE for buy orders — these
                // are what the user has to copy/paste into their bank
                // to complete the transfer. Hiding them defeats the
                // purpose of the sheet.
                if (isBuy && order.depositSepaAddress != null)
                  _sheetDetailRow(c, 'IBAN', order.depositSepaAddress!,
                      copiable: true, ctx: ctx),
                if (isBuy && order.depositSepaBic != null)
                  _sheetDetailRow(c, 'BIC', order.depositSepaBic!,
                      copiable: true, ctx: ctx),
                if (isBuy && order.depositSepaBeneficiary != null)
                  _sheetDetailRow(c, context.l10n.receiveBeneficiary,
                      order.depositSepaBeneficiary!,
                      copiable: true, ctx: ctx),
                if (isBuy && order.transferCode != null)
                  _sheetDetailRow(
                      c, context.l10n.activityReference, order.transferCode!,
                      copiable: true, ctx: ctx),
                _NerdDataSection(children: [
                  _sheetDetailRow(c, context.l10n.provider, 'Outlogic'),
                  // Trade mechanics, with the unit the value is quoted in.
                  if (order.trade != null) ...[
                    _sheetDetailRow(c, context.l10n.fee,
                        '${order.trade!.feeAmount} ${tx.fiatAsset}'),
                    _sheetDetailRow(c, context.l10n.price2,
                        '${order.trade!.price} ${tx.fiatAsset}'),
                  ],
                  if (order.destinationCryptoAddress.isNotEmpty)
                    _sheetDetailRow(c, context.l10n.depositAddress,
                        order.destinationCryptoAddress,
                        copiable: true, isAddress: true, ctx: ctx),
                  _sheetDetailRow(c, context.l10n.orderId, order.id,
                      copiable: true, ctx: ctx),
                ]),
              ],
            ),
          )),
    ),
  );
}

/// Refunding and mature deposits open the action sheet. Deposits still
/// waiting for confirmations open the read-only pending sheet.
void _openUnclaimedDeposit(
    BuildContext context, WidgetRef ref, SparkUnclaimedDeposit tx) {
  final refundTxId = tx.refundTxId;
  if ((refundTxId != null && refundTxId.isNotEmpty) || tx.isMature) {
    _showUnclaimedDepositDetails(context, ref, tx);
  } else {
    _showPendingUnclaimedSheet(context, ref, tx);
  }
}

Widget _buildUnclaimedItem(
    SparkUnclaimedDeposit tx, BuildContext context, WidgetRef ref) {
  final refundTxId = tx.refundTxId;
  final isRefunding = refundTxId != null && refundTxId.isNotEmpty;
  // The SDK can't auto-claim — only THEN do we surface the bespoke
  // "Action Required" prompt. While the deposit is just confirming
  // (or the SDK is mid auto-claim), we render the same way the old
  // mempool-watcher row did: Bitcoin icon with the pending halo,
  // "Received BTC / On-chain · HH:mm", and a Pending badge. Tap
  // opens a bottom sheet with deposit details + a "View on
  // mempool.space" link so the user can drill into chain detail
  // without leaving the app immediately.
  final needsAction = tx.isMature && tx.hasClaimError;

  if (isRefunding || needsAction) {
    // Calm words: the bitcoin is here and waits for one tap, so the row
    // wears the same pending halo as any arriving payment.
    return _TransactionRow(
      onTap: () => _openUnclaimedDeposit(context, ref, tx),
      leading: isRefunding
          ? buildCircularIcon(Icons.replay_rounded, AppColors.info)
          : _PendingIconWrapper(
              child: _AssetTxIcon(assetCode: 'BTC', isSend: false)),
      title: _RowTitle(isRefunding
          ? context.l10n.refunding
          : context.l10n.activityBitcoinWaiting),
      subtitle: isRefunding
          ? context.l10n.activityProcessingEllipsis
          : context.l10n.activityTapToAddToWallet,
      status: isRefunding
          ? _RowStatus(
              text: context.l10n.pending, color: context.colors.warning)
          : null,
      amount: ref.watch(conversionProvider(tx.amount.toInt())),
      flow: isRefunding ? ActivityFlow.neutral : ActivityFlow.moneyIn,
      amountIsBtc: true,
      fiatAmount: ref.watch(conversionToFiatProvider(tx.amount.toInt())),
    );
  }

  // Pending receive — Bitcoin icon + halo, opens the pending
  // deposit modal sheet (with a mempool link inside) on tap.
  Widget iconWidget = _AssetTxIcon(assetCode: 'BTC', isSend: false);
  iconWidget = _PendingIconWrapper(child: iconWidget);
  return _TransactionRow(
    onTap: () => _openUnclaimedDeposit(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(context.l10n.received),
    subtitle: DateFormat('HH:mm').format(tx.timestamp),
    status:
        _RowStatus(text: context.l10n.pending, color: context.colors.warning),
    amount: ref.watch(conversionProvider(tx.amount.toInt())),
    flow: ActivityFlow.moneyIn,
    amountIsBtc: true,
    fiatAmount: ref.watch(conversionToFiatProvider(tx.amount.toInt())),
  );
}

/// Modal sheet for an in-flight Bitcoin deposit: shows whatever
/// primitives the SDK has surfaced (txid, amount, maturity flag)
/// and a "View on mempool.space" CTA so the user can drill into the
/// confirmation tracker without leaving the activity feed
/// involuntarily. Distinct from the action-required modal (which is
/// reached only when the SDK reports `claimError`).
void _showPendingUnclaimedSheet(
    BuildContext context, WidgetRef ref, SparkUnclaimedDeposit tx) {
  TrackingService.transactionDetailViewed('spark_unclaimed_pending');
  final c = context.colors;
  final dateStr = activitySheetDate(context, tx.timestamp);
  final txid = tx.txid;

  showAppBottomSheet(
    context: context,
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.85,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildUnclaimedItem(tx, context, ref),
                  advisorSurface: 'deposit_tx_detail',
                ),
              ),
              _sheetDetailRow(c, context.l10n.date, dateStr),
              _sheetDetailRow(
                  c, context.l10n.status, context.l10n.activityArriving,
                  valueColor: c.accent),
              // Rail and tx ID are nerd data — collapsed.
              _NerdDataSection(children: [
                _sheetDetailRow(
                    c, context.l10n.network, context.l10n.activityOnChain),
                if (txid.isNotEmpty)
                  _sheetDetailRow(c, context.l10n.txId, txid,
                      copiable: true, isAddress: true, ctx: ctx),
              ]),
              SizedBox(height: 20.h),
              if (txid.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      ctx.pop();
                      final uri = Uri.parse('https://mempool.space/tx/$txid');
                      // Match the polygonscan/sparkscan affordance —
                      // SFSafariViewController on iOS, Chrome Custom
                      // Tabs on Android. Falls back to the external
                      // browser if the in-app surface isn't available.
                      if (!await launchUrl(uri,
                          mode: LaunchMode.inAppBrowserView)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                    label: Text(context.l10n.activityViewOnBlockchain,
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.buttonBorder),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildMempoolItem(
    MempoolAddressTransaction tx, BuildContext context, WidgetRef ref) {
  final owner = ref.watch(bitcoinLabelsWalletIdProvider);
  final label = owner == null
      ? null
      : ref.watch(bitcoinLabelsProvider(owner))[
          bitcoinTransactionLabelKey(tx.details.txid)];
  final isReceive = tx.type == TransactionType.received;
  final isPending = !tx.isConfirmed;
  final amountSats = tx.amount.toInt();

  Widget iconWidget = _AssetTxIcon(assetCode: 'BTC', isSend: !isReceive);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  return _TransactionRow(
    onTap: () => _showTrackedBitcoinTxDetails(context, ref, tx, owner),
    leading: iconWidget,
    title: _RowTitle(isReceive ? context.l10n.received : context.l10n.sent),
    subtitle: label ?? DateFormat('HH:mm').format(tx.timestamp),
    status: isPending
        ? _RowStatus(text: context.l10n.pending, color: context.colors.warning)
        : null,
    amount: ref.watch(conversionProvider(amountSats)),
    flow: isReceive ? ActivityFlow.moneyIn : ActivityFlow.moneyOut,
    amountIsBtc: true,
    fiatAmount: ref.watch(conversionToFiatProvider(amountSats)),
  );
}

/// The address a tracked-address wallet watches, or null when it cannot be
/// read. Storage errors are swallowed: the graph then falls back to its
/// received-amount heuristic instead of failing the sheet.
Future<String?> _trackedAddressFor(String? owner) async {
  if (owner == null) return null;
  try {
    return await AuthModel().getExternalAddress(owner);
  } catch (_) {
    return null;
  }
}

void _showTrackedBitcoinTxDetails(BuildContext context, WidgetRef ref,
    MempoolAddressTransaction tx, String? owner) {
  TrackingService.transactionDetailViewed('tracked_bitcoin');
  _warmTxDetails(tx);
  final c = context.colors;
  final isReceive = tx.type == TransactionType.received;
  // The tracked address is the wallet's only own address: the flow graph
  // highlights the inputs spent from it and the outputs paid to it. Read it
  // once, outside the builder, so a sheet rebuild never re-reads storage.
  final ownAddress = _trackedAddressFor(owner);
  showAppBottomSheet(
      context: context,
      // The sheet keeps its own context and ref if its source row disappears.
      builder: (ctx) => Consumer(
          builder: (context, ref, _) => AppBottomSheetContainer(
                maxHeight: 0.85,
                child: SheetScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Consumer(
                        builder: (context, ref, _) => TransactionDetailHeader(
                          row: _buildMempoolItem(tx, context, ref),
                          advisorSurface: 'btc_tx_detail',
                        ),
                      ),
                      if (owner != null)
                        BitcoinTransactionLabel(
                            txid: tx.details.txid, walletId: owner),
                      _sheetDetailRow(c, context.l10n.date,
                          activitySheetDate(context, tx.timestamp)),
                      _sheetDetailRow(
                          c,
                          context.l10n.status,
                          tx.isConfirmed
                              ? context.l10n.confirmed
                              : context.l10n.pending),
                      // Tx-flow graph (UTXO braid) built entirely from
                      // mempool.space inputs/outputs (values + addresses) with
                      // the fee node on top. Compact skeleton while loading,
                      // nothing on failure; it never blocks or errors.
                      SizedBox(height: 6.h),
                      FutureBuilder<String?>(
                          future: ownAddress,
                          builder: (_, snap) {
                            final addr = snap.data;
                            return TxFlowGraph(
                                txid: tx.details.txid,
                                isSend: !isReceive,
                                ownAddresses: addr == null || addr.isEmpty
                                    ? const {}
                                    : {addr},
                                // Fallback highlight while the address is
                                // unknown: a receive's balance change is the
                                // amount paid to the tracked address.
                                receivedSats: tx.details.balanceChange > 0
                                    ? tx.details.balanceChange
                                    : 0);
                          }),
                      SizedBox(height: 6.h),
                      // Rail and tx ID are nerd data — collapsed.
                      _NerdDataSection(children: [
                        _sheetDetailRow(c, context.l10n.network,
                            context.l10n.activityOnChain),
                        _sheetDetailRow(c, context.l10n.txId, tx.details.txid,
                            copiable: true, isAddress: true, ctx: ctx),
                      ]),
                      SizedBox(height: 8.h),
                      TextButton.icon(
                          onPressed: () {
                            ref.read(transactionSearchProvider.notifier).state =
                                TransactionSearchModel(
                                    isLiquid: false, txid: tx.details.txid);
                            final router = GoRouter.of(ctx);
                            Navigator.of(ctx).pop();
                            router.push('/search_modal');
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(context.l10n.activityViewOnBlockchain)),
                    ])),
              )));
}

Widget _buildSparkPendingDepositItem(
    SparkPendingDeposit tx, BuildContext context, WidgetRef ref) {
  final amountSats = tx.amount.toInt();

  Widget iconWidget = const _AssetTxIcon(assetCode: 'BTC', isSend: false);
  iconWidget = _PendingIconWrapper(child: iconWidget);

  return _TransactionRow(
    onTap: () => _showSparkPendingDepositDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(context.l10n.receiving),
    // "Arriving · 1 of 3 confirmations": the count is the whole story of
    // this transient row, so it replaces the time.
    subtitle: context.l10n.activityConfirmationsOfThree('${tx.confirmations}'),
    status: _RowStatus(
        text: context.l10n.activityArriving, color: context.colors.warning),
    amount: ref.watch(conversionProvider(amountSats)),
    flow: ActivityFlow.moneyIn,
    amountIsBtc: true,
    fiatAmount: ref.watch(conversionToFiatProvider(amountSats)),
  );
}

void _showSparkPendingDepositDetails(
    BuildContext context, WidgetRef ref, SparkPendingDeposit tx) {
  TrackingService.transactionDetailViewed('spark_pending_deposit');
  _warmTxDetails(tx);
  final c = context.colors;
  final amountSats = tx.amount.toInt();
  final dateStr = activitySheetDate(context, tx.timestamp);
  final txid = tx.mempoolTx.txid;

  showAppBottomSheet(
    context: context,
    // The graph can make a busy transaction taller than the screen: cap
    // the sheet like the bitcoin one and let the content scroll.
    builder: (context) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildSparkPendingDepositItem(tx, context, ref),
                  advisorSurface: 'deposit_tx_detail',
                ),
              ),
              _sheetDetailRow(c, context.l10n.date, dateStr),
              _sheetDetailRow(
                  c,
                  context.l10n.status,
                  context.l10n
                      .activityConfirmationsOfThree('${tx.confirmations}')),
              // The real incoming transaction from mempool.space, as on the
              // bitcoin sheet: the output worth exactly the incoming amount
              // is the wallet's own.
              SizedBox(height: 6.h),
              TxFlowGraph(txid: txid, receivedSats: amountSats),
              SizedBox(height: 6.h),
              _NerdDataSection(children: [
                _sheetDetailRow(
                    c, context.l10n.network, context.l10n.activityOnChain),
                _sheetDetailRow(c, context.l10n.txId, txid,
                    copiable: true, isAddress: true, ctx: context),
              ]),
              SizedBox(height: 16.h),
              // Quiet grey note, same as the info lines elsewhere in the app
              // (no tinted banner).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: c.textTertiary, size: 14.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      context.l10n.activityReadyAfterConfirmations(
                          '${tx.confirmations}'),
                      style: TextStyle(
                          color: c.textTertiary, fontSize: 13.sp, height: 1.35),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    context.pop();
                    final uri = Uri.parse('https://mempool.space/tx/$txid');
                    if (!await launchUrl(uri,
                        mode: LaunchMode.inAppBrowserView)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                  label: Text(context.l10n.activityViewOnBlockchain,
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.buttonBorder),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildUsdbTokenItem(
    UsdbTokenTransaction tx, BuildContext context, WidgetRef ref) {
  final details = tx.details;
  final isSend = details.paymentType == breez.PaymentType.send;
  final isPending = details.status == breez.PaymentStatus.pending;
  final usdbAmount = tx.amount.toInt() / 1e6;
  final usdbStr = usdbAmount.toStringAsFixed(2);

  // 'USD', not the token's own mark: the person holds dollars.
  Widget iconWidget = _AssetTxIcon(assetCode: 'USD', isSend: isSend);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  return _TransactionRow(
    onTap: () => _showUsdbTokenTxDetails(context, ref, tx),
    leading: iconWidget,
    // The user's dollars: a send out of the account is a withdrawal, an
    // incoming transfer a deposit, like every other balance's moves.
    title: _RowTitle(isSend
        ? context.l10n.activityRowWithdraw
        : context.l10n.activityRowDeposit),
    subtitle: _withTime(
        isSend
            ? context.l10n.activityRowFrom(context.l10n.assetDollars)
            : context.l10n.activityRowTo(context.l10n.assetDollars),
        tx.timestamp),
    status: isPending
        ? _RowStatus(text: context.l10n.pending, color: context.colors.warning)
        : null,
    amount: "\$$usdbStr",
    // The amount is already in dollars: no second figure to show.
    fiatAmount: '',
  );
}

void _showUsdbTokenTxDetails(
    BuildContext context, WidgetRef ref, UsdbTokenTransaction tx) {
  TrackingService.transactionDetailViewed('usd_token');
  final c = context.colors;
  final payment = tx.details;
  final isSend = payment.paymentType == breez.PaymentType.send;
  final dateStr = activitySheetDate(context, tx.timestamp);


  String statusText;
  Color statusColor;
  switch (payment.status) {
    case breez.PaymentStatus.completed:
      statusText = context.l10n.completed;
      statusColor = AppColors.success;
      break;
    case breez.PaymentStatus.failed:
      statusText = context.l10n.failed;
      statusColor = AppColors.error;
      break;
    case breez.PaymentStatus.pending:
      statusText = context.l10n.pending;
      statusColor = context.colors.accent;
      break;
  }

  // Fee
  final feeSat = payment.fees.toInt();
  final showFee = isSend && feeSat > 0;

  // Technical details from token payment
  final sparkPaymentId = payment.id;
  String? txHash;
  final details = payment.details;
  if (details is breez.PaymentDetails_Token) {
    txHash = details.txHash;
  }

  showAppBottomSheet(
    context: context,
    // `ctx` (the live modal-route context), not the captured outer
    // `context`: the tx row is often scrolled out and deactivated by
    // the time the sheet builds, so MediaQuery.of(context) walked a
    // dead element → "Null check operator used on a null value".
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildUsdbTokenItem(tx, context, ref),
                  advisorSurface: 'usdb_tx_detail',
                ),
              ),
              _sheetDetailRow(c, context.l10n.date, dateStr),
              _sheetDetailRow(c, context.l10n.status, statusText,
                  valueColor: statusColor),
              // Through the shared formatter so the fee follows the sats or
              // BTC setting like every other amount.
              if (showFee)
                _sheetDetailRow(
                    c, context.l10n.fee, ref.read(conversionProvider(feeSat))),
              _NerdDataSection(children: [
                // The rail this settles on is never named on screen for
                // the dollar account (user decision): the person holds
                // USD, not a token on a named network.
                if (txHash != null)
                  _sheetDetailRow(c, context.l10n.activityTxHash, txHash,
                      copiable: true, isAddress: true, ctx: ctx),
                _sheetDetailRow(
                    c,
                    context.l10n.paymentId,
                    sparkPaymentId.contains(':')
                        ? sparkPaymentId.split(':').first
                        : sparkPaymentId,
                    copiable: true,
                    isAddress: true,
                    ctx: ctx),
              ]),
              SizedBox(height: 16.h),
              // SparkScan stays visible — primary explorer affordance.
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final cleanId = sparkPaymentId.contains(':')
                        ? sparkPaymentId.split(':').first
                        : sparkPaymentId;
                    launchUrl(Uri.parse(
                        'https://sparkscan.io/tx/$cleanId?network=mainnet'));
                  },
                  icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                  label: Text(context.l10n.activityViewOnBlockchain,
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.buttonBorder),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Same-asset USDC transfer (USDC → USDC, USDC → USDC.e). Visually a
/// "Send", not a swap — single asset icon, plain "Send · HH:mm"
/// subtitle, signed amount. Tapping opens the native send detail
/// sheet so users can copy the destination / view the on-chain hash.
Widget _buildNativeUsdcSendRow(
    SwapOrderTransaction tx, BuildContext context, WidgetRef ref) {
  final details = tx.details;
  final isPending = details.isPending;
  final amount = double.tryParse(details.depositAmount) ?? 0;
  // Match the Spark / on-chain row layout: directional icon, "Sent"
  // title (no asset chip — identity is in the icon), "via Polygon ·
  // HH:mm" subtitle, no leading sign on the amount (the directional
  // icon already conveys direction). Amount renders via
  // `formatPolyAmount` so it follows the global Predictions
  // denomination setting (sats/BTC in bitcoin mode, user's fiat in
  // fiat mode).
  final fiatStr = formatPolyAmount(ref, amount);
  Widget iconWidget = _AssetTxIcon(assetCode: 'USDC', isSend: true);
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }
  return _TransactionRow(
    onTap: () => _showNativeUsdcSendDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(context.l10n.sent),
    subtitle: DateFormat('HH:mm').format(tx.timestamp),
    status: !tx.isComplete
        ? _RowStatus(text: context.l10n.pending, color: context.colors.warning)
        : null,
    amount: fiatStr,
    flow: ActivityFlow.moneyOut,
    fiatAmount: '',
  );
}

Widget _buildSwapOrderItem(
    SwapOrderTransaction tx, BuildContext context, WidgetRef ref) {
  final details = tx.details;
  final isPending = details.isPending;

  // Same-asset transfer (USDC → USDC, USDC → USDC.e on Polygon, etc.).
  // Older builds saved these in the swap-order list with
  // provider='Native', but they're
  // not swaps — same chain, same asset (or canonical equivalents).
  // Render as a plain Send row instead of a swap pair so users don't
  // think their USDC turned into different USDC.
  String _normalizeStable(String coin) {
    final c = coin.toUpperCase();
    return (c == 'USDC' || c == 'USDC.E') ? 'USDC' : c;
  }

  final isSameAssetTransfer = details.networkFrom.toUpperCase() ==
          details.networkTo.toUpperCase() &&
      _normalizeStable(details.coinFrom) == _normalizeStable(details.coinTo);
  if (isSameAssetTransfer) {
    return _buildNativeUsdcSendRow(tx, context, ref);
  }

  final activity = swapActivityFor(details);
  final isPolymarket = activity.isPredictions;
  final isTradingPool = activity.isInvesting;
  final isDollarPool = activity.isDollars;
  final isPoolDeposit = activity.isDeposit;
  final isExternal = activity.isExternal;
  final isExternalSend = activity == SwapActivityKind.send;
  // A send paid from dollars lives on the Dollars tab alone, so its row
  // reads in dollars: the dollar mark, the dollars that left as the
  // amount, and what the recipient got under it.
  final isDollarSend = _isDollarFundedSend(details, activity);
  final externalCoin = isDollarSend
      ? 'USD'
      : isExternalSend
          ? details.coinTo
          : details.coinFrom;

  // Cash App deposit (Orchestra / Flashnet onramp). The row is
  // recorded with a Lightning deposit leg, but that is plumbing: the
  // user paid Cash App, so the row names the account it credited,
  // with the Cash App mark as the source icon and
  // the fiat paid on the secondary line.
  final isCashAppPurchase = details.isCashAppPurchase;
  if (isCashAppPurchase) {
    ref.watch(cashAppDeadlinePassedProvider(details.cashAppExpiresAt));
  }
  final purchaseFiat = details.purchaseFiatUsd;

  Widget iconWidget;
  if (isCashAppPurchase) {
    iconWidget = const _CashAppTxIcon();
  } else if (isPolymarket) {
    iconWidget = _PolymarketTxIcon(
      isSend: isPoolDeposit,
      type: isPoolDeposit ? ActivityType.deposit : ActivityType.withdraw,
    );
  } else if (isTradingPool) {
    iconWidget = SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: AssetIcon(assetCode: 'Trading', size: 44.sp),
    );
  } else if (isDollarPool) {
    // Bare mark, no direction arrow, exactly like the Predictions and
    // Investing rows beside it. These are the same shape of row: money
    // moving between the person's own balances, with the direction
    // already spelled out in the title ("Dollar deposit" / "Dollar
    // withdrawal"). The arrow badge belongs to rows where the direction
    // is the only thing distinguishing them, which is not these.
    iconWidget = SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: AssetIcon(assetCode: 'USD', size: 44.sp),
    );
  } else if (isExternal) {
    iconWidget = _AssetTxIcon(assetCode: externalCoin, isSend: isExternalSend);
  } else {
    final fromIcon =
        details.coinFrom == 'BTC' && details.networkFrom == 'LIGHTNING'
            ? 'Lightning'
            : details.coinFrom;
    final toIcon = details.coinTo == 'BTC' && details.networkTo == 'LIGHTNING'
        ? 'Lightning'
        : details.coinTo;
    iconWidget = _SwapTxIcon(fromCode: fromIcon, toCode: toIcon);
  }
  if (isPending) {
    iconWidget = _PendingIconWrapper(child: iconWidget);
  }

  String statusLabel;
  Color statusColor = context.colors.warning;

  if (details.isCashAppPurchase) {
    statusLabel = cashAppStatusLabel(details, context.l10n);
    statusColor = details.cashAppPaymentWindowClosed
        ? context.colors.textSecondary
        : details.isComplete
            ? AppColors.success
            : details.isExpired
                ? AppColors.marketDown
                : context.colors.warning;
  } else if (details.isUntrackedLegacyOrder) {
    // A retired provider's order: nothing updates it any more, so it
    // claims neither progress nor an outcome.
    statusLabel = context.l10n.activityNoLongerTracked;
    statusColor = context.colors.textSecondary;
  } else if (details.isExpired) {
    statusLabel = context.l10n.expired;
    statusColor = AppColors.marketDown;
  } else {
    switch (details.status) {
      case 'success':
      case 'settled': // reconciler terminal spelling
        statusLabel = context.l10n.completed;
        statusColor = AppColors.success;
        break;
      case 'overdue':
      case 'expired':
        statusLabel = context.l10n.expired;
        statusColor = AppColors.marketDown;
        break;
      case 'unfulfilled':
      case 'failed':
      case 'emergency':
      case 'settle_data_error':
        statusLabel = context.l10n.activityNeedsAttention;
        statusColor = AppColors.marketDown;
        break;
      case 'refunded':
        statusLabel = context.l10n.refunded;
        statusColor = AppColors.marketDown;
        break;
      // A standing deposit that never became an order: held for return,
      // or already asked back (details offer the refund).
      case 'held':
        statusLabel = context.l10n.activityNeedsReturn;
        statusColor = AppColors.marketDown;
        break;
      case 'refund_requested':
        statusLabel = context.l10n.activityReturnRequested;
        break;
      default:
        statusLabel = context.l10n.pending;
    }
  }

  // Every USD-pegged leg of a swap renders via `formatPolyAmount`,
  // so Polymarket deposits + withdrawals follow the global
  // Predictions denomination setting (sats/BTC in bitcoin mode,
  // user's fiat in fiat mode). Other swap legs also
  // route through this helper — the rule reads consistently because
  // every USDC-flavoured leg is USD-pegged regardless of route.
  String fmtFiatStable(double usd) => formatPolyAmount(ref, usd);

  String formatSwapAmount(String rawAmount, String coin) {
    final isOrch = details.isOrchestra;

    if (isOrch) {
      // Orchestra amounts may be in smallest units (from Flashnet API)
      // or already converted to human-readable (from our polling conversion).
      // Detect: if the value looks like smallest units, convert it.
      final humanValue = orchestraRowAmount(rawAmount, coin);

      if (coin == 'BTC') {
        final sats = (humanValue * 100000000).round();
        // `conversionProvider` now embeds the unit suffix itself.
        return ref.watch(conversionProvider(sats));
      }
      final upperCoin = coin.toUpperCase();
      // The dollar token joins the stables: it IS a dollar, and its own
      // ticker must never reach a row.
      if (upperCoin == 'USDC' ||
          upperCoin == 'USDT' ||
          upperCoin == 'USDC.E' ||
          upperCoin == kOrchestraUsdAssetCode) {
        return fmtFiatStable(humanValue);
      }
      final displayCoin = _assetDisplayName(coin);
      return '${humanValue.toStringAsFixed(8)} $displayCoin';
    }

    // Non-Orchestra: amounts are always in human-readable format
    if (coin == 'BTC') {
      final sats = (double.tryParse(rawAmount) ?? 0) * 100000000;
      return ref.watch(conversionProvider(sats.round()));
    }
    final upperCoin = coin.toUpperCase();
    if (upperCoin == 'USDC' || upperCoin == 'USDT' || upperCoin == 'USDC.E') {
      final parsed = double.tryParse(rawAmount) ?? 0;
      return fmtFiatStable(parsed);
    }
    // Cap display precision for everything else. Some providers
    // hand us raw strings with 17–18 decimals (e.g. POL ~ wei),
    // which look broken in the activity row. Six decimals is plenty
    // for any non-stable crypto preview; the detail sheet still
    // shows the full amount via `rawAmount` if a user needs it.
    final displayCoin = _assetDisplayName(coin);
    final parsed = double.tryParse(rawAmount);
    if (parsed != null) {
      // Strip trailing zeros so 0.10000000 → 0.1.
      var formatted = parsed.toStringAsFixed(6);
      if (formatted.contains('.')) {
        formatted = formatted.replaceAll(RegExp(r'0+$'), '');
        formatted = formatted.replaceAll(RegExp(r'\.$'), '');
      }
      return '$formatted $displayCoin';
    }
    return '$rawAmount $displayCoin';
  }

  final bool showBadge = !tx.isComplete || details.canRefund;

  // Title: what happened, verb first, one line. Context line: where the
  // money went, then the time. The provider, the networks and the full
  // pair are Nerd data on the detail sheet.
  final String title;
  final String where;
  ActivityFlow flow = ActivityFlow.neutral;
  if (isCashAppPurchase) {
    // Money from outside arriving in one of the person's balances.
    title = context.l10n
        .activityRowBought(_cashAppDestinationLabel(context, details));
    where = '';
    flow = ActivityFlow.moneyIn;
  } else if (isPolymarket || isTradingPool || isDollarPool) {
    // A move between the person's own balances: no sign either way.
    final venue = isPolymarket
        ? context.l10n.predictions
        : isTradingPool
            ? context.l10n.trading
            : context.l10n.assetDollars;
    title = isPoolDeposit
        ? context.l10n.activityRowDeposit
        : context.l10n.activityRowWithdraw;
    where = isPoolDeposit
        ? context.l10n.activityRowTo(venue)
        : context.l10n.activityRowFrom(venue);
  } else if (isExternal) {
    title = isExternalSend ? context.l10n.sent : context.l10n.received;
    where = isDollarSend
        ? context.l10n.activityRowTo(
            details.coinTo == 'BTC' && details.networkTo == 'LIGHTNING'
                ? 'Lightning'
                : _swapLegLabel(context, details.coinTo))
        : '';
    flow = isExternalSend ? ActivityFlow.moneyOut : ActivityFlow.moneyIn;
  } else {
    final to = details.coinTo == 'BTC' && details.networkTo == 'LIGHTNING'
        ? 'Lightning'
        : _swapLegLabel(context, details.coinTo);
    title = context.l10n.swap;
    where = context.l10n.activityRowTo(to);
  }

  return _TransactionRow(
    onTap: () => _showSwapOrderDetails(context, ref, tx),
    leading: iconWidget,
    title: _RowTitle(title),
    subtitle: _withTime(where, tx.timestamp),
    status:
        showBadge ? _RowStatus(text: statusLabel, color: statusColor) : null,
    flow: flow,
    // Lead with what the user RECEIVED — that's the relevant
    // outcome of a swap. The previous "2.04 USDC → 0.00 002 510
    // BTC" read like the user lost USDC; flipping it so the
    // received amount is primary makes the row consistent with
    // the rest (amount column = balance change in your favour).
    // Outflow shifts to the secondary line as "from X coin".
    amount: (isExternal && !isExternalSend) || isDollarSend
        ? formatSwapAmount(details.depositAmount, details.coinFrom)
        : formatSwapAmount(details.withdrawalAmount, details.coinTo),
    amountIsBtc: ((isExternal && !isExternalSend) || isDollarSend
            ? details.coinFrom
            : details.coinTo) ==
        'BTC',
    // A purchase names the fiat paid ("from $55.00"); the Lightning
    // sats that moved behind it are not what the user handed over.
    // A stuck deposit converted into nothing, so no "→ $0.00" line.
    fiatAmount: details.isStuckStandingDeposit
        ? ''
        // A dollar send's delivered amount is the quote's estimate until
        // the first status check writes the real one, and that estimate
        // can round to nothing ("→ ₿0"): no figure until it is known.
        : isDollarSend && !dollarSendDeliveredKnown(details)
        ? ''
        : (isExternal && !isExternalSend) || isDollarSend
        ? '→ ${formatSwapAmount(details.withdrawalAmount, details.coinTo)}'
        : context.l10n.activityFromAmount(isCashAppPurchase &&
                purchaseFiat != null &&
                purchaseFiat.isNotEmpty
            ? '\$$purchaseFiat'
            : formatSwapAmount(details.depositAmount, details.coinFrom)),
  );
}

/// One leg of a conversion on its detail sheet: "Lightning", "Dollar",
/// "Bitcoin". The USDC literals never reach the person.
String _swapSheetLegLabel(BuildContext context, String code, String network) {
  if (code == 'BTC' && network == 'LIGHTNING') return 'Lightning';
  final upper = code.toUpperCase();
  if (upper == 'USDC' ||
      upper == 'USDC.E' ||
      upper == 'USDT' ||
      upper == 'PUSD') {
    return context.l10n.activityDollar;
  }
  return _assetDisplayName(code);
}

void _showSwapOrderDetails(
    BuildContext context, WidgetRef ref, SwapOrderTransaction tx) {
  TrackingService.transactionDetailViewed('swap_order');
  showAppBottomSheet(
    context: context,
    builder: (ctx) => _SwapOrderDetailSheet(tx: tx),
  );
}

class _SwapOrderDetailSheet extends ConsumerStatefulWidget {
  final SwapOrderTransaction tx;
  const _SwapOrderDetailSheet({required this.tx});

  @override
  ConsumerState<_SwapOrderDetailSheet> createState() =>
      _SwapOrderDetailSheetState();
}

class _SwapOrderDetailSheetState extends ConsumerState<_SwapOrderDetailSheet> {
  CashAppPurchaseSession? _cashAppSession;
  Timer? _cashAppPoll;

  bool get _isBitcoinVN => widget.tx.details.providerName == 'BitcoinVN';

  String _formatShiftAmount(String rawAmount, String coin) {
    if (coin == 'BTC') {
      final sats = (double.tryParse(rawAmount) ?? 0) * 100000000;
      return ref.read(conversionProvider(sats.round()));
    }
    final upperCoin = coin.toUpperCase();
    if (upperCoin == 'USDC' ||
        upperCoin == 'USDT' ||
        upperCoin == 'USDC.E' ||
        // The dollar balance's own token is a dollar too: a Cash App
        // purchase of dollars reads "$50.00", never eight decimals of
        // token.
        upperCoin == kOrchestraUsdAssetCode) {
      // USD-pegged legs render in the user's fiat. The literal coin
      // code never reaches the user — asset identity is in the swap
      // icon at the top of the sheet.
      final parsed = double.tryParse(rawAmount) ?? 0;
      final fiatCcy = ref.read(settingsProvider.select((s) => s.currency));
      final fiatPerUsd =
          ref.read(selectedCurrencyProviderFromUSD(fiatCcy)).toDouble();
      return NumberFormat.simpleCurrency(
        name: fiatCcy,
        decimalDigits: 2,
      ).format(parsed * fiatPerUsd);
    }
    return '$rawAmount $coin';
  }

  @override
  void initState() {
    super.initState();
    if (!widget.tx.details.isCashAppPurchase) {
      return;
    }
    _cashAppPoll = Timer.periodic(CashAppPurchaseSession.activePollInterval,
        (_) => _checkClosedCashAppPurchase());
    _checkClosedCashAppPurchase();
  }

  @override
  void dispose() {
    _cashAppPoll?.cancel();
    super.dispose();
  }

  bool _cancelling = false;

  /// Drops an unpaid Cash App purchase from Activity after the person
  /// confirms. The provider has no cancel for an unpaid invoice: it lapses
  /// on its own, and a payment that was already sent still settles to the
  /// same recipient, which the confirmation says. Re-checked against the
  /// live row so a payment that landed while the dialog was open wins.
  Future<void> _cancelCashAppPurchase(SwapOrder order) async {
    var confirmed = false;
    await showCustomAlertDialog(
      context: context,
      title: context.l10n.cashAppCancelPurchaseTitle,
      content: context.l10n.cashAppCancelPurchaseBody,
      buttons: [
        CustomAlertAction.destructive(
          text: context.l10n.cashAppCancelPurchase,
          // showDialog puts the dialog on the root navigator; popping the
          // nearest one from inside the sheet closed the wrong route and
          // left the dialog standing.
          onPressed: () {
            confirmed = true;
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        CustomAlertAction.secondary(
          text: context.l10n.cashAppKeepPurchase,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
    if (!confirmed || !mounted) return;
    final live = _liveCashAppOrder(ref.read(swapOrdersProvider));
    if (!kCashAppUnpaidStatuses.contains(live.status)) return;
    setState(() => _cancelling = true);
    try {
      _cashAppPoll?.cancel();
      await ref.read(swapOrdersProvider.notifier).deleteExchange(live.id);
      TrackingService.track('cashapp_purchase_cancelled', params: {
        'source': 'activity',
        'window_closed': live.cashAppPaymentWindowClosed,
      });
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
    if (!mounted) return;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    showMessageSnackBar(
      context: rootContext,
      message: rootContext.l10n.cashAppPurchaseCancelled,
      error: false,
      duration: const Duration(seconds: 2),
    );
  }

  /// Opens the Cash App amount screen for a fresh purchase. Nothing is
  /// created until the user continues there; this order keeps reconciling.
  void _startNewCashAppPurchase(SwapOrder order) {
    TrackingService.cashAppNewPurchaseTapped(source: 'activity');
    final destination = cashAppDestination(order);
    final wallet = ref
        .read(settingsProvider)
        .wallets
        .where((wallet) => wallet.id == order.walletId)
        .firstOrNull;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    TrackingService.markEntrySource('move', 'activity');
    TrackingService.markEntrySource('buy', 'activity');
    // Buying again repeats the purchase that was made, on the same locked
    // door the original buy used: a venue order reopens that venue's buy,
    // a dollar order the dollars door, and a bitcoin order the plain
    // Buy bitcoin door pointed at the wallet it credited. Never an
    // unlocked sheet: nothing here offers a move between wallets.
    final ledgerVenue =
        destination?.isVenue == true && wallet?.isLedger == true;
    showDepositSheet(
      rootContext,
      lockedSide: switch (destination) {
        CashAppDestination.predictions => MoveLockedSide.buyToPredictions,
        CashAppDestination.investing => MoveLockedSide.buyToHyperliquid,
        CashAppDestination.dollars => MoveLockedSide.depositToUsd,
        _ => MoveLockedSide.depositFromFiat,
      },
      // A savings wallet's own purchase credits that wallet, exactly as
      // its Purchase button does; the spending account is the default.
      fiatDepositWalletId:
          wallet != null && !wallet.isSparkWallet && !ledgerVenue
              ? wallet.id
              : null,
      venueWalletId: ledgerVenue ? wallet?.id : null,
      cashAppSource: true,
    );
  }

  /// The stored row for this Cash App purchase. Background sync swaps a
  /// quote id for the real order id, possibly while this sheet is open; the
  /// invoice still identifies it.
  SwapOrder _liveCashAppOrder(List<SwapOrder> orders) {
    final snapshot = widget.tx.details;
    return orders.where((order) => order.id == snapshot.id).firstOrNull ??
        (snapshot.depositAddress.isNotEmpty
            ? orders
                .where(
                    (order) => order.depositAddress == snapshot.depositAddress)
                .firstOrNull
            : null) ??
        snapshot;
  }

  /// While a closed unpaid purchase is shown, check its status the way the
  /// payment sheet does, so a payment that may still be landing is never
  /// met with a new purchase offer. Nothing is stored; background sync owns
  /// the order.
  Future<void> _checkClosedCashAppPurchase() async {
    final order = _liveCashAppOrder(ref.read(swapOrdersProvider));
    if (!order.cashAppPaymentWindowClosed) {
      return;
    }
    var session = _cashAppSession;
    final started = session == null;
    session ??= _cashAppSession =
        CashAppPurchaseSession(storedOrders: () => ref.read(swapOrdersProvider))
          ..beginStored(order);
    final offered = session.canOfferNewPurchase;
    await session.poll((id) async {
      final response = await OrchestraService.getStatus(id);
      return response.isSuccess ? response.data : null;
    });
    if (mounted && (started || session.canOfferNewPurchase != offered)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final snapshot = widget.tx.details;
    final details = snapshot.isCashAppPurchase
        ? _liveCashAppOrder(ref.watch(swapOrdersProvider))
        : snapshot;
    if (details.isCashAppPurchase) {
      ref.watch(cashAppDeadlinePassedProvider(details.cashAppExpiresAt));
    }
    final cashAppSession = _cashAppSession;
    if (cashAppSession != null) {
      ref.watch(
          cashAppDeadlinePassedProvider(cashAppSession.newPurchaseOfferAt));
    }
    // "Create new purchase" opens Cash App; watched so it follows the
    // policy live.
    final cashAppOffered = onrampVisible(
        ref.watch(runtimeCapabilitiesProvider), kOnrampCashApp);

    // Vendor states collapse into a few plain words; the raw status code
    // stays readable under Nerd data.
    Color statusColor;
    String statusText;
    switch (details.status) {
      case 'success':
      case 'settled':
        statusText = context.l10n.completed;
        statusColor = AppColors.success;
        break;
      case 'overdue':
      case 'expired':
        statusText = context.l10n.expired;
        statusColor = AppColors.error;
        break;
      case 'unfulfilled':
      case 'failed':
      case 'settle_data_error':
      case 'emergency':
        statusText = context.l10n.activityNeedsAttention;
        statusColor = AppColors.error;
        break;
      case 'refunded':
        statusText = context.l10n.refunded;
        statusColor = AppColors.error;
        break;
      case 'held':
        statusText = context.l10n.activityNeedsReturn;
        statusColor = AppColors.error;
        break;
      case 'refund_requested':
        statusText = context.l10n.activityReturnRequested;
        statusColor = context.colors.warning;
        break;
      case 'processing':
      case 'exchanging':
      case 'settling':
      case 'review':
        statusText = context.l10n.processing;
        statusColor = context.colors.accent;
        break;
      default:
        statusText = context.l10n.pending;
        statusColor = context.colors.accent;
    }

    if (details.isUntrackedLegacyOrder) {
      statusText = context.l10n.activityNoLongerTracked;
      statusColor = context.colors.textSecondary;
    }

    if (details.isCashAppPurchase) {
      statusText = cashAppStatusLabel(details, context.l10n);
      statusColor = details.cashAppPaymentWindowClosed
          ? context.colors.textSecondary
          : details.isComplete
              ? AppColors.success
              : details.isExpired
                  ? AppColors.error
                  : context.colors.warning;
    }

    final isOrchestra = details.isOrchestra;
    // Cash App deposit: the header says what was paid and what arrived.
    // The Lightning deposit network and the 0 rate are plumbing and stay
    // out of the sheet entirely.
    final isCashAppPurchase = details.isCashAppPurchase;

    final activity = swapActivityFor(details);
    final isPolymarketRow = activity.isPredictions || activity.isInvesting;

    return KeyboardDismissOnTap(
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: SheetScrollView(
            padding: EdgeInsets.only(bottom: 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer(
                  builder: (context, ref, _) => TransactionDetailHeader(
                    row: _buildSwapOrderItem(widget.tx, context, ref),
                    advisorSurface: 'swap_tx_detail',
                    // A conversion's row names only where it went; the
                    // sheet keeps both legs ("Dollar → Bitcoin").
                    note: activity == SwapActivityKind.swap &&
                            !isCashAppPurchase
                        ? context.l10n.activitySwapLegs(
                            _swapSheetLegLabel(
                                context, details.coinFrom, details.networkFrom),
                            _swapSheetLegLabel(
                                context, details.coinTo, details.networkTo))
                        : null,
                  ),
                ),
                _sheetDetailRow(
                  c,
                  context.l10n.date,
                  activitySheetDate(context, widget.tx.timestamp),
                ),
                _sheetDetailRow(
                    c,
                    context.l10n.status,
                    statusText,
                    valueColor: statusColor),
                // What moved is the header: the row's amount (what arrived)
                // and the figure under it (what was paid, "from ₿3,964").
                // Only a stuck deposit, which converted into nothing and so
                // has no figure under its amount, names what was sent here.
                // The provider, the chains and the rate are routing detail
                // under Nerd data.
                if (details.isStuckStandingDeposit)
                  _sheetDetailRow(
                      c,
                      context.l10n.deposit,
                      _formatShiftAmount(
                          details.depositAmount, details.coinFrom)),
                if (activity.isExternal)
                  _sheetDetailRow(c, context.l10n.network,
                      '${orchestraChainDisplayName(details.networkFrom)} → ${orchestraChainDisplayName(details.networkTo)}'),
                // Network-free deposit/swap flow: from-leg → to-leg. Derived
                // entirely from local fields (no network). For Polymarket-tagged
                // Orchestra rows the legs read "Your wallet → Predictions" (deposit)
                // or "Predictions → Your wallet" (withdraw); generic swaps show the
                // human leg names.
                () {
                  final isPolymarketRow = activity.isPredictions;
                  String legName(String code, String network) {
                    if (code == 'BTC' && network == 'LIGHTNING') {
                      return 'Lightning';
                    }
                    final upper = code.toUpperCase();
                    if (!activity.isExternal &&
                        (upper == 'USDC' ||
                            upper == 'USDC.E' ||
                            upper == 'USDT' ||
                            upper == 'PUSD')) {
                      return context.l10n.activityDollar;
                    }
                    return _assetDisplayName(code);
                  }

                  String fromLabel;
                  String toLabel;
                  if (isCashAppPurchase) {
                    fromLabel = 'Cash App';
                    toLabel = _cashAppDestinationLabel(context, details);
                  } else if (isPolymarketRow) {
                    final isDeposit = activity.isDeposit;
                    fromLabel = isDeposit
                        ? context.l10n.activityYourWallet
                        : context.l10n.predictions;
                    toLabel = isDeposit
                        ? context.l10n.predictions
                        : context.l10n.activityYourWallet;
                  } else {
                    fromLabel = legName(details.coinFrom, details.networkFrom);
                    toLabel = legName(details.coinTo, details.networkTo);
                  }
                  // Labels-only — both leg amounts already show in the
                  // Send / Receive rows above, so the graph just draws the path.
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: SimpleFlowGraph(
                      source: SimpleFlowNode(label: fromLabel, amount: ''),
                      destinations: [
                        SimpleFlowNode(
                          label: toLabel,
                          amount: '',
                          highlight: true,
                        ),
                      ],
                    ),
                  );
                }(),
                // Provider, chains, rate, raw status, addresses, exchange
                // ID and refund address are nerd data — collapsed.
                _NerdDataSection(children: [
                  _sheetDetailRow(
                      c, context.l10n.provider, details.providerName),
                  if (!isCashAppPurchase && details.networkFrom.isNotEmpty)
                    _sheetDetailRow(c, context.l10n.activityDepositNetwork,
                        orchestraChainDisplayName(details.networkFrom)),
                  if (isPolymarketRow)
                    _sheetDetailRow(
                        c,
                        context.l10n.receive,
                        _formatShiftAmount(
                            details.withdrawalAmount, details.coinTo)),
                  if (details.networkTo.isNotEmpty)
                    _sheetDetailRow(c, context.l10n.activityReceiveNetwork,
                        orchestraChainDisplayName(details.networkTo)),
                  if (!isCashAppPurchase)
                    _sheetDetailRow(
                        c, context.l10n.rate, _formatRate(details.rate)),
                  if (details.status.isNotEmpty)
                    _sheetDetailRow(
                        c, context.l10n.activityStatusCode, details.status),
                  // A Cash App purchase "deposit address" is the Lightning
                  // invoice Orchestra issued for Cash App to pay. The user's
                  // wallet never created it, so name it for what it is and
                  // call the settle address the delivery address. Only an
                  // invoice a payment followed reads as paid, and a closed,
                  // failed or cancelled one can no longer be copied to pay.
                  _sheetDetailRow(
                      c,
                      isCashAppPurchase
                          ? kCashAppPaidStatuses.contains(details.status)
                              ? context.l10n.activityInvoicePaidByCashApp
                              : context.l10n.cashAppInvoice
                          : context.l10n.depositAddress,
                      details.depositAddress,
                      copiable: !isCashAppPurchase ||
                          !(details.cashAppPaymentWindowClosed ||
                              details.isExpired),
                      isAddress: true,
                      ctx: context),
                  _sheetDetailRow(
                      c,
                      isCashAppPurchase
                          ? context.l10n.activityDeliveredTo
                          : context.l10n.activityWithdrawalAddress,
                      details.withdrawalAddress,
                      copiable: true,
                      isAddress: true,
                      ctx: context),
                  _sheetDetailRow(
                      c,
                      isCashAppPurchase
                          ? context.l10n.orderId
                          : context.l10n.activityExchangeId,
                      details.id,
                      copiable: true,
                      isAddress: true,
                      ctx: context),
                  if (_isBitcoinVN &&
                      details.providerToken != null &&
                      details.providerToken!.isNotEmpty)
                    _sheetDetailRow(
                        c, context.l10n.orderId, details.providerToken!,
                        copiable: true, ctx: context),
                  if (details.refundAddress.isNotEmpty)
                    _sheetDetailRow(c, context.l10n.activityRefundAddress,
                        details.refundAddress,
                        copiable: true, isAddress: true, ctx: context),
                ]),
                // An unpaid purchase can be dropped. Nothing is owed on an
                // invoice nobody paid; the row goes and the invoice simply
                // lapses. A paid or settling purchase has money in flight
                // and offers no such thing.
                if (isCashAppPurchase &&
                    kCashAppUnpaidStatuses.contains(details.status)) ...[
                  SizedBox(height: 16.h),
                  AppButton(
                    text: context.l10n.cashAppCancelPurchase,
                    variant: AppButtonVariant.secondary,
                    isLoading: _cancelling,
                    onPressed: _cancelling
                        ? null
                        : () => _cancelCashAppPurchase(details),
                    compact: true,
                  ),
                ],
                // Offered once the grace period passed and a fresh check
                // still reports the order unpaid, as in the payment sheet.
                // A Buy door is always drawn (founder decision, October
                // 2026): with Cash App withheld the tap opens the "no
                // purchase providers" sheet instead of a new purchase.
                if (isCashAppPurchase &&
                    details.cashAppPaymentWindowClosed &&
                    (cashAppSession?.canOfferNewPurchase ?? false)) ...[
                  SizedBox(height: 16.h),
                  AppButton(
                    text: context.l10n.cashAppCreateNewPurchase,
                    onPressed: () => cashAppOffered
                        ? _startNewCashAppPurchase(details)
                        : showBuyUnavailableSheet(context),
                    compact: true,
                  ),
                ],
                // A retired provider's order is history only: Kute can no
                // longer check or change it, and says so.
                if (details.isUntrackedLegacyOrder) ...[
                  SizedBox(height: 16.h),
                  Text(context.l10n.activityLegacyOrderNote,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 14.sp)),
                ],

                if (isOrchestra) OrchestraSwapRefundAction(order: details),

                // External-explorer button — same visual shape across
                // providers (matches the "View on Polygonscan" button
                // used for Polymarket transactions). Orchestra orders
                // do have a public explorer: orchestra.flashnet.xyz/
                // explorer/<id>. The id we hand to the explorer:
                //   - `ord_…` → pass straight through
                //   - bare uuid → prepend `ord_` (legacy records)
                //   - `q_…`    → pass straight through (NOT double-
                //     prefixed; `ord_q_…` is what the explorer was
                //     rejecting with "id must be an order id"). On
                //     in-flight rows whose quote hasn't been swapped
                //     for an order id yet, the explorer's quote view
                //     still loads given the bare quote prefix.
                // A stuck-deposit row has no order for the explorer to show.
                if (details.id.isNotEmpty &&
                    !details.isStuckStandingDeposit &&
                    details.isOrchestra) ...[
                  SizedBox(height: 20.h),
                  SizedBox(
                    width: double.infinity,
                    height: 48.h,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final orchId = details.id.startsWith('ord_') ||
                                details.id.startsWith('q_')
                            ? details.id
                            : 'ord_${details.id}';
                        final uri = Uri.parse(
                            'https://orchestra.flashnet.xyz/explorer/$orchId');
                        if (!await launchUrl(uri,
                            mode: LaunchMode.inAppBrowserView)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                      label: Text(
                        context.l10n.activityTrackExchange,
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.buttonBorder),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Computes realized P&L for a SELL trade row from the average cost of
/// the earlier BUYs of the same outcome. Returns null when no buy is
/// known.
double? _realizedPnlForPolymarketSell(
        PolymarketTransaction sellTx, WidgetRef ref) =>
    predictionSalePnl(_polymarketHistory(ref), sellTx.activity);

/// The spending account's Predictions records, for cost basis.
Iterable<Activity> _polymarketHistory(WidgetRef ref) => ref
    .read(transactionNotifierProvider)
    .polymarketTransactions
    .map((tx) => tx.activity);

/// True when a "Won prediction" redeem row has an Orchestra USDC→BTC
/// cash-out leg still in flight nearby (±30 min). The exchange row
/// itself is collapsed out of the feed by `_collapsePolymarketFlows`,
/// which would otherwise swallow its PENDING badge — the redeem row
/// carries a "Settling" subtitle suffix instead so the user keeps the
/// in-flight signal until the BTC lands.
bool _hasInFlightWithdrawLeg(PolymarketTransaction redeemTx, WidgetRef ref) {
  // watch (not read): the "Settling" suffix must clear on its own the
  // moment the pending exchange flips to success — with a read, the row
  // only updated on the next unrelated list rebuild.
  final exchanges =
      ref.watch(transactionNotifierProvider).swapOrderTransactions;
  final redeemMs = redeemTx.timestamp.millisecondsSinceEpoch;
  for (final ex in exchanges) {
    final d = ex.details;
    if (!d.isOrchestra) {
      continue;
    }
    // Withdraw side only: USDC leaving Polygon on its way to BTC.
    if (swapActivityFor(d) != SwapActivityKind.predictionsWithdrawal) {
      continue;
    }
    if (!d.isPending) {
      continue;
    }
    if ((redeemMs - ex.timestamp.millisecondsSinceEpoch).abs() >
        30 * 60 * 1000) {
      continue;
    }
    return true;
  }
  return false;
}

/// The results of the spending account's predictions held to a resolved
/// market that its history does not record ([predictionResults]): a lost
/// prediction, never claimed, and a win not claimed yet. Rows of [feed]'s
/// Predictions activity, dated at the resolution. None when [feed] is not
/// the spending account's (the trading state follows that account alone).
List<PolymarketTransaction> predictionResultTransactions(
    WidgetRef ref, Iterable<PolymarketTransaction> feed) {
  final state = ref.watch(polymarketTradingProvider).valueOrNull;
  final account = state?.proxyWalletAddress?.toLowerCase();
  if (state == null || !state.isAuthenticated || account == null) {
    return const [];
  }
  final history = [for (final t in feed) t.activity];
  if (!history.any((a) => a.proxyWallet.toLowerCase() == account)) {
    return const [];
  }
  return [
    for (final r in predictionResults(
      open: state.openPositions,
      closed: state.closedPositions,
      history: history,
      clearing: state.clearingConditionIds,
    ))
      PolymarketTransaction.result(r),
  ];
}

Widget _buildPolymarketItem(
    PolymarketTransaction tx, BuildContext context, WidgetRef ref) {
  final activity = tx.activity;
  final type = tx.activityType;
  final result = tx.result;

  // Polymarket rows are intrinsically dollar-priced: the amount follows
  // the person's fiat, never the BTC formatter, and no "USDC" word
  // appears (the crest or the venue mark says where it happened).
  String fmtFiat(double usd) => formatPolyAmount(ref, usd);
  final copy = predictionRowCopy(context.l10n, activity,
      time: DateFormat('HH:mm').format(tx.timestamp));

  // One secondary figure at most: the realised profit or loss of a sale
  // or a payout, coloured. A loss is the amount itself. Share counts and
  // the full market title are on the detail sheet.
  // A result carries its own stake and payout: the history is not read.
  final figures = predictionRowFigures(
      activity, result != null ? const <Activity>[] : _polymarketHistory(ref),
      flow: copy.flow, result: result);
  final pnl = figures.pnl;
  final secondary = pnl == null
      ? ''
      : pnl >= 0
          ? context.l10n.activityAmountProfit(fmtFiat(pnl.abs()))
          : context.l10n.activityAmountLoss(fmtFiat(pnl.abs()));
  final secondaryColor = pnl == null
      ? null
      : pnl >= 0
          ? AppColors.marketUp
          : AppColors.marketDown;
  // The Orchestra USDC→BTC cash-out leg is collapsed out of the feed
  // (`_collapsePolymarketFlows`), which would silently drop its pending
  // state: keep the in-flight signal on the row the user actually sees
  // until the BTC lands. A win not claimed yet says so, and the row runs
  // the claim.
  final claimable = result?.claimable ?? false;
  final status = claimable
      ? _RowStatus(text: context.l10n.claim, color: AppColors.marketUp)
      : result == null &&
              type == ActivityType.redeem &&
              tx.usdcAmount > 0.001 &&
              _hasInFlightWithdrawLeg(tx, ref)
          ? _RowStatus(
              text: context.l10n.activitySettling,
              color: context.colors.warning)
          : null;

  return _TransactionRow(
    // A result read from the market has no venue record: it opens its own
    // sheet (the figures, the market, the claim of a win not claimed yet).
    onTap: result == null
        ? () => _showPolymarketTxDetails(context, ref, tx)
        : () => showPredictionResultDetails(context, result),
    leading: _PolymarketTxIcon(
      isSend: copy.flow == ActivityFlow.moneyOut,
      type: type,
      // Crest-first: sports activities carry the generic league ball as
      // `icon` (Gamma ships it for every sub-market) — resolve the real
      // team crest from the event's teams by outcome/question text.
      iconUrl: activityCrestIcon(ref, activity),
    ),
    title: _RowTitle(copy.title),
    subtitle: copy.subtitle,
    status: status,
    amount: fmtFiat(figures.amount),
    flow: figures.flow,
    amountColor: predictionResultColor(figures),
    amountIsBtc: false,
    fiatAmount: secondary,
    secondaryColor: secondaryColor,
  );
}

/// The amount colour of a Predictions row: a settled result is coloured
/// (won green, lost red); everything else is the primary text colour
/// (null).
Color? predictionResultColor(
        ({double amount, ActivityFlow flow, double? pnl, bool settled})
            figures) =>
    !figures.settled
        ? null
        : switch (figures.flow) {
            ActivityFlow.moneyIn => AppColors.marketUp,
            ActivityFlow.moneyOut => AppColors.marketDown,
            ActivityFlow.neutral => null,
          };

/// The market or venue mark of a Predictions row, the same tile every
/// Predictions surface uses (the Ledger account's activity too).
Widget predictionActivityIcon(String? iconUrl) => _PolymarketTxIcon(
    isSend: false, type: ActivityType.trade, iconUrl: iconUrl);

void _showPolymarketTxDetails(
    BuildContext context, WidgetRef ref, PolymarketTransaction tx) {
  TrackingService.transactionDetailViewed('polymarket');
  final c = context.colors;
  final activity = tx.activity;
  final type = tx.activityType;
  // Honor the user's currency setting so the detail sheet shows
  // amounts in the same fiat as the rest of the app (€, £, BRL…)
  // instead of always USD. USDC is USD-pegged → multiply by the
  // user-currency-per-USD rate before formatting.
  // Honor the GLOBAL Settings → Predictions denomination setting via
  // `formatPolyAmount` — Polymarket transaction-detail sheet flips
  // sats/BTC ↔ fiat with the rest of the Predictions surfaces.
  String fmtFiat(double usd, {String prefix = ''}) =>
      '$prefix${formatPolyAmount(ref, usd)}';
  final usdcStr = fmtFiat(tx.usdcAmount);
  final dateStr = activitySheetDate(context, tx.timestamp);
  final isSell =
      type == ActivityType.trade && activity.side?.toUpperCase() == 'SELL';
  final isRedeem = type == ActivityType.redeem;

  // Best-effort cost basis for sells: first try the trading
  // provider's *closed* positions (SDK-computed cashPnl, most
  // accurate), then fall back to walking the user's own trade
  // history for an avg-cost basis. The fallback is what makes the
  // PnL card show even when closedPositions hasn't been hydrated
  // by the SDK yet, or when the position is still partly open.
  double? realizedPnl;
  if (isSell) {
    try {
      final closed =
          ref.read(polymarketTradingProvider).valueOrNull?.closedPositions ??
              const [];
      final match = closed
          .where((p) => p.conditionId == activity.conditionId)
          .firstOrNull;
      if (match != null) {
        realizedPnl = match.cashPnl;
      }
    } catch (_) {/* fall through — provider not ready */}
    realizedPnl ??= _realizedPnlForPolymarketSell(tx, ref);
  }



  showAppBottomSheet(
    context: context,
    // `ctx` (the live modal-route context), not the captured outer
    // `context`: the tx row is often scrolled out and deactivated by
    // the time the sheet builds, so MediaQuery.of(context) walked a
    // dead element → "Null check operator used on a null value".
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TransactionDetailHeader(
                  row: _buildPolymarketItem(tx, context, ref),
                  advisorSurface: isRedeem
                      ? 'polymarket_claim_tx_detail'
                      : 'polymarket_tx_detail',
                ),
              ),
              if (type == ActivityType.trade || isRedeem)
                PolymarketBitcoinComparison(transaction: tx),
              // No fee row: the activity feed does not report the trading
              // fee, and a permanent placeholder read as a missing number.
              _sheetDetailRow(c, context.l10n.date, dateStr),
              // Trade-flow row — explicit "what for what" so a buy reads
              // as "$X USDC → Y NO shares" rather than just an isolated
              // dollar amount. Helps a user who's not fluent in CLOB
              // mechanics see exactly what changed hands.
              if (type == ActivityType.trade &&
                  activity.outcome != null &&
                  activity.outcome!.isNotEmpty &&
                  activity.size > 0) ...[
                _sheetDetailRow(
                  c,
                  context.l10n.activityTrade,
                  isSell
                      ? '${activity.size.toStringAsFixed(2)} ${activity.outcome} → $usdcStr'
                      : '$usdcStr → ${activity.size.toStringAsFixed(2)} ${activity.outcome}',
                ),
              ] else if (isRedeem && tx.usdcAmount > 0) ...[
                // Won redemption — show the cash payout as the
                // primary outcome alongside the share count we held.
                if (activity.size > 0)
                  _sheetDetailRow(
                    c,
                    context.l10n.payout,
                    '${activity.size.toStringAsFixed(2)} ${activity.outcome ?? context.l10n.activitySharesLowercase} → ${fmtFiat(tx.usdcAmount, prefix: '+')}',
                    valueColor: const Color(0xFF15803D),
                  ),
              ] else ...[
                _sheetDetailRow(c, context.l10n.amount, usdcStr),
              ],
              // Network-free flow graph for deposits / withdrawals (money in or
              // out of the Predictions balance). Trades/redeems already express
              // "$X → Y shares" in their own rows, so the braid is skipped there.
              if (type == ActivityType.deposit ||
                  type == ActivityType.withdraw) ...[
                // Amount lives ON the graph (no duplicate text row).
                SizedBox(height: 6.h),
                SimpleFlowGraph(
                  source: SimpleFlowNode(
                    label: type == ActivityType.deposit
                        ? context.l10n.activityYourWallet
                        : context.l10n.predictions,
                    amount: usdcStr,
                  ),
                  destinations: [
                    SimpleFlowNode(
                      label: type == ActivityType.deposit
                          ? context.l10n.predictions
                          : context.l10n.activityYourWallet,
                      amount: usdcStr,
                      highlight: true,
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
              ],
              // Realized profit / loss line. Sells use the
              // SDK-derived `realizedPnl`; won redeems compute
              // `payout − stake` (netRedeem) from local trade
              // history. Skipped when stake is unknown — we'd have
              // nothing meaningful to subtract from.
              // The header already shows the row's realised profit or loss;
              // a separate line only when the venue's figure differs.
              if (!isRedeem &&
                  realizedPnl != null &&
                  (realizedPnl - (_realizedPnlForPolymarketSell(tx, ref) ?? 0))
                          .abs() >
                      0.005)
                _sheetDetailRow(
                  c,
                  realizedPnl >= 0
                      ? context.l10n.activityProfit
                      : context.l10n.activityLoss,
                  fmtFiat(realizedPnl.abs(),
                      prefix: realizedPnl >= 0 ? '+' : '−'),
                  valueColor:
                      realizedPnl >= 0 ? const Color(0xFF15803D) : _kPolyRedTx,
                ),
              if (activity.title != null && activity.title!.isNotEmpty)
                _sheetDetailRow(
                    c, context.l10n.betMarketCategory, activity.title!),
              if (activity.outcome != null && activity.outcome!.isNotEmpty)
                _sheetDetailRow(
                  c,
                  isRedeem
                      ? context.l10n.activityBacked
                      : context.l10n.activityOutcome,
                  activity.outcome!,
                ),
              // Price per share and the share count are order-book detail:
              // the Trade row above already says what changed hands.
              _NerdDataSection(children: [
                if (activity.price != null && type == ActivityType.trade)
                  _sheetDetailRow(c, context.l10n.price2,
                      '${(activity.price! * 100).toStringAsFixed(1)}¢'),
                if (activity.size > 0 && type == ActivityType.trade)
                  _sheetDetailRow(c, context.l10n.betShares,
                      activity.size.toStringAsFixed(2)),
                // The transaction hash is deliberately not shown on a
                // trade (owner decision); the explorer button below still
                // opens it.
              ]),
              SizedBox(height: 16.h),
              // Explorer button stays visible — block explorers are a
              // primary debugging affordance, not nerd data.
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse(
                        'https://polygonscan.com/tx/${activity.transactionHash}'));
                  },
                  icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                  label: Text(context.l10n.activityViewOnBlockchain,
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.buttonBorder),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The detail sheet of a Predictions result row ([PredictionResult]): a
/// prediction held to its resolved market, lost or won (claimed or not
/// yet). The venue records' sheet, with what the result is made of: the
/// shares held at the resolution, what they cost, what the market pays
/// for them and the realised profit or loss. No explorer link and no
/// hash: nothing happened on chain, so there is no transaction to open.
/// A win not claimed yet carries the Portfolio's Claim; the market opens
/// once its event is known. [ledgerWalletId] is set on a Ledger account's
/// row: its market opens for that wallet, and its claim stays on the
/// position.
void showPredictionResultDetails(BuildContext context, PredictionResult result,
    {String? ledgerWalletId}) {
  TrackingService.transactionDetailViewed('polymarket_result');
  final tx = PolymarketTransaction.result(result);
  final activity = result.activity;
  final slug = (activity.eventSlug ?? '').trim();
  final title = (activity.title ?? '').trim();
  final outcome = (activity.outcome ?? '').trim();
  showAppBottomSheet(
    context: context,
    builder: (ctx) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
          child: Consumer(builder: (context, ref, _) {
            final c = context.colors;
            final l = context.l10n;
            String money(double usd, {String prefix = ''}) =>
                '$prefix${formatPolyAmount(ref, usd)}';
            final pnl = result.pnlUsd;
            final event =
                slug.isEmpty ? null : ref.watch(polyPositionEventProvider(slug));
            final claim = ledgerWalletId == null && result.claimable
                ? ref
                    .watch(polymarketClaimablePositionsProvider)
                    .where((p) =>
                        p.marketId == result.conditionId && p.won == true)
                    .firstOrNull
                : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TransactionDetailHeader(
                  row: _buildPolymarketItem(tx, context, ref),
                  advisorSurface: 'polymarket_claim_tx_detail',
                ),
                _sheetDetailRow(
                    c, l.resolved, activitySheetDate(context, tx.timestamp)),
                if (title.isNotEmpty)
                  _sheetDetailRow(c, l.betMarketCategory, title),
                if (outcome.isNotEmpty)
                  _sheetDetailRow(c, l.activityBacked, outcome),
                _sheetDetailRow(
                    c, l.betShares, activity.size.toStringAsFixed(2)),
                _sheetDetailRow(c, l.betReceiptCost, money(result.stakeUsd)),
                _sheetDetailRow(c, l.payout, money(result.payoutUsd)),
                _sheetDetailRow(
                  c,
                  l.portfolioStatRealized,
                  money(pnl.abs(), prefix: pnl >= 0 ? '+' : '−'),
                  valueColor: pnl >= 0 ? const Color(0xFF15803D) : _kPolyRedTx,
                ),
                SizedBox(height: 16.h),
                if (claim != null) ...[
                  PolyClaimButton(
                      position: claim, surface: 'activity', popRoute: true),
                  SizedBox(height: 10.h),
                ],
                if (event != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48.h,
                    child: OutlinedButton.icon(
                      onPressed: () => MarketDetailSheet.show(context,
                          event: event,
                          ledgerWalletId: ledgerWalletId,
                          source: 'activity'),
                      icon: Icon(Icons.chevron_right_rounded, size: 18.sp),
                      label: Text(l.salViewMarket,
                          style: TextStyle(
                              fontSize: 16.sp, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.buttonBorder),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                ],
              ],
            );
          }),
        ),
      ),
    ),
  );
}

/// Collapsible disclosure for technical-only refs on tx detail
/// sheets — tx hash, block height, conditionId, addresses,
/// "view on Polygonscan" buttons, etc. Hidden by default; user
/// expands to "Nerd data" when they want the receipt.
///
/// Lives at the bottom of each detail sheet, below the
/// user-readable rows (Date, Type, Amount, Market, Outcome).
class _NerdDataSection extends StatefulWidget {
  final List<Widget> children;

  /// Disclosure title; defaults to "Nerd data". An "Advanced" block uses
  /// the same collapsed grammar for controls a person rarely needs.
  final String? title;
  const _NerdDataSection({required this.children, this.title});

  @override
  State<_NerdDataSection> createState() => _NerdDataSectionState();
}

class _NerdDataSectionState extends State<_NerdDataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 8.h),
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18.sp,
                  color: c.textTertiary,
                ),
                SizedBox(width: 4.w),
                Text(
                  widget.title ?? context.l10n.activityNerdData,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
        // The rows grow into place instead of snapping open; the hosting
        // sheet's SheetScrollView follows this one frame by frame.
        SheetAnimatedSize(
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 4.h),
                    ...widget.children,
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

Widget _sheetDetailRow(AppColorsExtension c, String label, String value,
    {Color? valueColor,
    bool copiable = false,
    bool isAddress = false,
    BuildContext? ctx}) {
  final display = isAddress && value.length > 16
      ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}'
      : value;
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 9.h),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            )),
        SizedBox(width: 12.w),
        Expanded(
          child: GestureDetector(
            onTap: copiable && ctx != null
                ? () {
                    TrackingService.transactionIdCopied();
                    Clipboard.setData(ClipboardData(text: value));
                    showMessageSnackBarInfo(
                        context: ctx, message: ctx.l10n.copiedToClipboard);
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(display,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: valueColor ?? c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                if (copiable) ...[
                  SizedBox(width: 6.w),
                  Icon(Icons.copy_rounded, color: c.accent, size: 12.sp)
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Detail rows showing what a tx was worth in USD when it first appeared and
/// how much that value is up/down vs now (from `TxFiatSnapshotService`).
/// Empty if no snapshot exists (e.g. pre-feature txs we chose not to backfill).
List<Widget> _fiatSnapshotRows(
    BuildContext context, WidgetRef ref, AppColorsExtension c, String txid) {
  final snap = TxFiatSnapshotService.snapshot(txid);
  if (snap == null || snap.usd <= 0) {
    return const [];
  }
  final valueThen = '\$${snap.usd.toStringAsFixed(2)}';
  final btcUsd = ref.read(currentBtcUsdProvider);
  if (btcUsd <= 0 || snap.sats <= 0) {
    return [_sheetDetailRow(c, context.l10n.activityValueThen, valueThen)];
  }
  final pct = snap.changePct(btcUsd);
  final up = pct >= 0;
  return [
    _sheetDetailRow(c, context.l10n.activityValueThen, valueThen),
    _sheetDetailRow(
      c,
      context.l10n.activityChangeSince,
      '${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}%',
      valueColor: up ? AppColors.success : AppColors.error,
    ),
  ];
}

void _showBitcoinTxDetails(
    BuildContext context, WidgetRef ref, BitcoinTransaction tx) {
  TrackingService.transactionDetailViewed('bitcoin');
  _warmTxDetails(tx);
  // Cached BitcoinTransactions hydrated from the per-wallet Hive
  // snapshot have no live `btcDetails` — chain position, fee, raw
  // tx bytes are all unavailable until the next sync replaces the
  // shell. We still open the sheet for them (txid + amount + date
  // are all in the cache) so the user can hop to mempool.space;
  // the fee / fee-rate rows just hide. Live entries take the
  // detail-rich path below.
  final c = context.colors;
  final details = tx.btcDetails;
  final labelWalletId = ref.read(bitcoinLabelsWalletIdProvider);

  final isReceive = details != null
      ? transactionIsReceived(details, ref)
      : tx.receivedSats > tx.sentSats;
  final isPending = details != null
      ? details.chainPosition is! ConfirmedChainPosition
      : !tx.isConfirmed;


  // Date
  String dateStr;
  if (details != null && details.chainPosition is ConfirmedChainPosition) {
    final ts = (details.chainPosition as ConfirmedChainPosition)
        .confirmationBlockTime
        .confirmationTime;
    dateStr = ts > 0
        ? activitySheetDate(
            context, DateTime.fromMillisecondsSinceEpoch(ts * 1000))
        : context.l10n.pending;
  } else if (details == null && tx.isConfirmed) {
    dateStr = activitySheetDate(context, tx.timestamp);
  } else {
    dateStr = context.l10n.pending;
  }

  final statusText = details != null
      ? confirmationStatus(context, details, ref)
      : (tx.isConfirmed ? context.l10n.confirmed : context.l10n.pending);
  final statusColor = isPending ? context.colors.accent : AppColors.success;

  // Fee — only available with live details. Shown ON the flow graph (Fee
  // node) when > 0; cached entries have no fee and just skip the node.
  final feeSats = details?.fee?.toSat() ?? 0;

  // Technical
  final txid = details?.txid.toString() ?? tx.id;
  String? feeRate;
  if (details != null) {
    final vSize = details.tx.vsize().toInt();
    final fee = (details.fee?.toSat() ?? 0).toDouble();
    if (vSize > 0 && fee > 0) {
      feeRate = '${(fee / vSize).toStringAsFixed(1)} sat/vB';
    }
  }

  // Tx-flow graph. With live BDK details each output carries its value
  // locally and the fee is known, so the rows render at once; the graph then
  // does ONE mempool.space `GET /tx/{txid}` to fill the input values and to
  // label rows with their counterparty addresses. Cached shells (no
  // `details`) pass no local rows and the graph builds them entirely from
  // that same fetch. The output matching `received` is the user's own and
  // gets highlighted.
  List<TxFlowInput> flowInputs = const [];
  List<TxFlowNode> flowOutputs = const [];
  if (details != null && details.tx.hasInputOutputDetails) {
    final ins = details.tx.input();
    final outs = details.tx.output();
    final receivedSats = details.received.toSat();

    flowInputs = [
      for (var i = 0; i < ins.length; i++)
        TxFlowInput(
          label: context.l10n.activityInputIndex('$i'),
          prevTxid: ins[i].previousOutput.txid.toString(),
          prevVout: ins[i].previousOutput.vout,
        ),
    ];

    final nodes = <TxFlowNode>[];
    // Fee sits at the top of the right column.
    if (feeSats > 0) {
      nodes
          .add(TxFlowNode(label: context.l10n.fee, sats: feeSats, isFee: true));
    }
    var highlighted = false;
    for (var i = 0; i < outs.length; i++) {
      final v = outs[i].value.toSat();
      // Highlight only the first output matching the received amount.
      final isReceived = !highlighted && receivedSats > 0 && v == receivedSats;
      if (isReceived) {
        highlighted = true;
      }
      nodes.add(TxFlowNode(
        label: context.l10n.activityOutputIndex('$i'),
        sats: v,
        highlight: isReceived,
      ));
    }
    flowOutputs = nodes;
  }

  showAppBottomSheet(
    context: context,
    // The sheet keeps its own context and ref if its source row disappears.
    builder: (ctx) => Consumer(
        builder: (context, ref, _) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer(
                        builder: (context, ref, _) => TransactionDetailHeader(
                          row: _buildBitcoinItem(tx, context, ref),
                          advisorSurface: 'btc_tx_detail',
                        ),
                      ),
                      if (labelWalletId != null)
                        BitcoinTransactionLabel(
                            txid: tx.id, walletId: labelWalletId),
                      _sheetDetailRow(c, context.l10n.date, dateStr),
                      _sheetDetailRow(c, context.l10n.status, statusText,
                          valueColor: statusColor),
                      ..._fiatSnapshotRows(context, ref, c, txid),
                      // Network fee lives ON the flow graph below (the "Fee" node), not
                      // in a duplicate text row.
                      // Tx-flow graph (UTXO braid) renders ALWAYS in the main body —
                      // not behind Nerd Data, live details or not. Input values and
                      // addresses resolve from mempool.space; if offline / the fetch
                      // fails the local rows still draw label-only (a cached shell
                      // draws nothing). It never blocks or errors.
                      SizedBox(height: 6.h),
                      TxFlowGraph(
                        txid: txid,
                        isSend: !isReceive,
                        inputs: flowInputs,
                        outputs: flowOutputs,
                        // A cached shell has no local outputs to flag, so the graph
                        // applies the received-amount heuristic to the mempool rows.
                        receivedSats: tx.receivedSats,
                      ),
                      SizedBox(height: 6.h),
                      // Rail, tx ID and fee rate are nerd data — collapsed.
                      _NerdDataSection(children: [
                        _sheetDetailRow(c, context.l10n.network,
                            context.l10n.activityOnChain),
                        if (feeRate != null)
                          _sheetDetailRow(c, context.l10n.feeRate2, feeRate),
                        _sheetDetailRow(c, context.l10n.txId, txid,
                            copiable: true, isAddress: true, ctx: ctx),
                      ]),
                      SizedBox(height: 16.h),
                      // A Ledger funding transaction whose settlement is pending keeps
                      // its Ledger account one tap away (Phase 5 plan B13).
                      _LedgerSettlementLink(txid: txid),
                      // Mempool explorer stays visible — primary affordance.
                      SizedBox(
                        width: double.infinity,
                        height: 48.h,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            ctx.pop();
                            final uri =
                                Uri.parse('https://mempool.space/tx/$txid');
                            if (!await launchUrl(uri,
                                mode: LaunchMode.inAppBrowserView)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                          label: Text(context.l10n.activityViewOnBlockchain,
                              style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.textPrimary,
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.buttonBorder),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
  );
}

void _showSparkTxDetails(
    BuildContext context, WidgetRef ref, SparkTransaction tx) {
  TrackingService.transactionDetailViewed('spark');
  final c = context.colors;
  // Spark txs come in two flavours:
  //   - Live: `tx.details` is the breez.Payment with full SDK
  //     metadata (fees, preimage, payment hash, raw tx id...).
  //   - Cached: hydrated from Hive shells (no SDK payload, just
  //     id + timestamp + amount + direction + sparkType +
  //     pending). We open the sheet either way; SDK-only rows
  //     (fee, technical IDs) just hide when missing.
  final payment = tx.details;
  final isSend = tx.type == TransactionType.sent;
  final settings = ref.read(settingsProvider);
  final denomination = settings.btcFormat;

  final amountSat = tx.amountSats;
  final amountStr = amountSat.toFormattedString(denomination);
  final channel = tx.sparkType == SparkTransactionType.bitcoin
      ? 'Bitcoin'
      : tx.sparkType == SparkTransactionType.lightning
          ? 'Lightning'
          : 'Spark';
  final dateStr = activitySheetDate(context, tx.timestamp);

  String statusText;
  Color statusColor;
  if (payment != null) {
    switch (payment.status) {
      case breez.PaymentStatus.completed:
        statusText = context.l10n.completed;
        statusColor = AppColors.success;
        break;
      case breez.PaymentStatus.failed:
        statusText = context.l10n.failed;
        statusColor = AppColors.error;
        break;
      case breez.PaymentStatus.pending:
        statusText = context.l10n.pending;
        statusColor = context.colors.accent;
        break;
    }
  } else {
    statusText = tx.isPending
        ? context.l10n.pending
        : (tx.isConfirmed ? context.l10n.completed : context.l10n.pending);
    statusColor = tx.isPending ? context.colors.accent : AppColors.success;
  }

  // Fee — live only; cached entries don't carry it.
  final feeSat = payment?.fees.toInt() ?? 0;
  final showFee = payment != null && isSend && feeSat > 0;
  final feeStr = feeSat.toFormattedString(denomination);

  // Technical details — only available with the live SDK payload.
  // Cached entries (hydrated from Hive at cold start) fall back to
  // the wallet-internal `tx.id` for the payment id and skip the
  // method-specific rows. Live rebuild on next sync fills these in.
  final sparkPaymentId = payment?.id ?? tx.id;
  // The chain txid survives the cache (see SparkTransaction.onChainTxId), so
  // a Hive-hydrated deposit or withdrawal still shows its id and graph.
  String? txId = tx.onChainTxId;
  String? invoice;
  String? preimage;
  String? description;
  String? paymentHash;
  String? comment;
  if (payment != null) {
    final details = payment.details;
    if (details is breez.PaymentDetails_Deposit) {
      txId = details.txId;
    } else if (details is breez.PaymentDetails_Withdraw) {
      txId = details.txId;
    } else if (details is breez.PaymentDetails_Lightning) {
      invoice = details.invoice;
      preimage = details.htlcDetails.preimage;
      description = details.description;
      paymentHash = details.htlcDetails.paymentHash;
      // LNURL comment: the sender's note on a received LNURL/Lightning-
      // address payment, or our own comment attached to an LNURL-pay
      // send. Human content — shown alongside Description, never nerd data.
      final senderComment = details.lnurlReceiveMetadata?.senderComment;
      comment = (senderComment != null && senderComment.isNotEmpty)
          ? senderComment
          : details.lnurlPayInfo?.comment;
    } else if (details is breez.PaymentDetails_Spark) {
      if (details.invoiceDetails != null) {
        invoice = details.invoiceDetails!.invoice;
        description = details.invoiceDetails!.description;
      }
      if (details.htlcDetails != null) {
        paymentHash = details.htlcDetails!.paymentHash;
        preimage = details.htlcDetails!.preimage;
      }
    }
  }

  // Spark withdrawals may share a provider transaction with unrelated outputs.
  // Only show our SDK payment amount and fee, never that batch's UTXO totals.
  final onChainTxId = !isSend &&
          tx.sparkType == SparkTransactionType.bitcoin &&
          txId != null &&
          txId.isNotEmpty
      ? txId
      : null;

  showAppBottomSheet(
    context: context,
    // The sheet keeps its own context and ref if its source row disappears.
    builder: (ctx) => Consumer(
        builder: (context, ref, _) => AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: SheetScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer(
                        builder: (context, ref, _) => TransactionDetailHeader(
                          row: _buildSparkItem(tx, context, ref),
                          advisorSurface:
                              tx.sparkType == SparkTransactionType.lightning
                                  ? 'lightning_tx_detail'
                                  : tx.sparkType == SparkTransactionType.bitcoin
                                      ? 'btc_tx_detail'
                                      : 'spark_tx_detail',
                        ),
                      ),
                      _sheetDetailRow(c, context.l10n.date, dateStr),
                      _sheetDetailRow(c, context.l10n.status, statusText,
                          valueColor: statusColor),
                      ..._fiatSnapshotRows(context, ref, c, tx.id),
                      // On chain the graph carries the miner fee of the transaction,
                      // not the fee the wallet paid, so that one keeps a plain row.
                      if (onChainTxId != null && showFee)
                        _sheetDetailRow(c, context.l10n.fee, '₿$feeStr'),
                      SizedBox(height: 6.h),
                      if (onChainTxId != null)
                        // The real chain transaction from mempool.space: skeleton
                        // while it loads, nothing on failure. The SDK payload carries
                        // no address, so the output worth exactly the amount that
                        // moved is the highlighted one: the wallet's own on a
                        // deposit, the recipient's on a withdrawal.
                        TxFlowGraph(
                            txid: onChainTxId,
                            isSend: isSend,
                            receivedSats: isSend ? 0 : amountSat,
                            sentSats: isSend ? amountSat : 0)
                      else
                        // Simple (network-free) flow graph derived from local fields:
                        // LN/Spark have no UTXOs, so this is a clean source →
                        // destination path. The amount + fee live ON the graph (no
                        // duplicate rows).
                        // The nodes are people, not rails: the rail is Nerd data.
                        SimpleFlowGraph(
                          source: SimpleFlowNode(
                            label: isSend
                                ? context.l10n.activityYourWallet
                                : context.l10n.activitySender,
                            amount: '₿$amountStr',
                            highlight: !isSend,
                          ),
                          destinations: [
                            if (isSend && showFee)
                              SimpleFlowNode(
                                  label: context.l10n.fee, amount: '₿$feeStr'),
                            SimpleFlowNode(
                              label: isSend
                                  ? context.l10n.recipient
                                  : context.l10n.activityYourWallet,
                              amount: '₿$amountStr',
                              highlight: !isSend,
                            ),
                          ],
                        ),
                      SizedBox(height: 6.h),
                      if (description != null && description.isNotEmpty)
                        _sheetDetailRow(
                            c, context.l10n.description, description),
                      if (comment != null && comment.isNotEmpty)
                        _sheetDetailRow(c, context.l10n.comment, comment),
                      // The rail and the technical refs (txid, payment hash, invoice
                      // blob, preimage, payment id) are nerd data. Collapsed by
                      // default so the default sheet stays human-readable.
                      _NerdDataSection(children: [
                        _sheetDetailRow(c, context.l10n.network, channel),
                        if (txId != null)
                          _sheetDetailRow(c, context.l10n.onChainTxid, txId,
                              copiable: true, isAddress: true, ctx: ctx),
                        if (paymentHash != null)
                          _sheetDetailRow(
                              c, context.l10n.paymentHash, paymentHash,
                              copiable: true, isAddress: true, ctx: ctx),
                        if (invoice != null)
                          _sheetDetailRow(c, context.l10n.invoice, invoice,
                              copiable: true, isAddress: true, ctx: ctx),
                        if (preimage != null)
                          _sheetDetailRow(c, context.l10n.preimage, preimage,
                              copiable: true, isAddress: true, ctx: ctx),
                        _sheetDetailRow(
                            c,
                            context.l10n.paymentId,
                            sparkPaymentId.contains(':')
                                ? sparkPaymentId.split(':').first
                                : sparkPaymentId,
                            copiable: true,
                            isAddress: true,
                            ctx: ctx),
                      ]),
                      SizedBox(height: 16.h),
                      // Explorer button is a primary affordance — kept visible.
                      SizedBox(
                        width: double.infinity,
                        height: 48.h,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final cleanId = sparkPaymentId.contains(':')
                                ? sparkPaymentId.split(':').first
                                : sparkPaymentId;
                            launchUrl(Uri.parse(
                                'https://sparkscan.io/tx/$cleanId?network=mainnet'));
                          },
                          icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
                          label: Text(context.l10n.activityViewOnBlockchain,
                              style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.textPrimary,
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.buttonBorder),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                    ],
                  ),
                ),
              ),
            )),
  );
}

void _showUnclaimedDepositDetails(
    BuildContext context, WidgetRef ref, SparkUnclaimedDeposit tx) {
  TrackingService.transactionDetailViewed('spark_unclaimed_deposit');
  final refundTxId = tx.refundTxId;
  final isRefunding = refundTxId != null && refundTxId.isNotEmpty;
  final settings = ref.read(settingsProvider);
  final denomination = settings.btcFormat;
  final unit = denomination == 'sats' ? 'sats' : 'BTC';
  final amountStr = tx.amount.toInt().toFormattedString(denomination);
  final fiatStr = ref.read(conversionToFiatProvider(tx.amount.toInt()));

  showAppBottomSheet(
    context: context,
    builder: (ctx) => _UnclaimedDepositSheet(
      tx: tx,
      isRefunding: isRefunding,
      amountStr: amountStr,
      unit: unit,
      fiatStr: fiatStr,
      denomination: denomination,
    ),
  );
}

enum _DepositAction { claim, refund }

class _UnclaimedDepositSheet extends ConsumerStatefulWidget {
  final SparkUnclaimedDeposit tx;
  final bool isRefunding;
  final String amountStr;
  final String unit;
  final String fiatStr;
  final String denomination;

  const _UnclaimedDepositSheet({
    required this.tx,
    required this.isRefunding,
    required this.amountStr,
    required this.unit,
    required this.fiatStr,
    required this.denomination,
  });

  @override
  ConsumerState<_UnclaimedDepositSheet> createState() =>
      _UnclaimedDepositSheetState();
}

class _UnclaimedDepositSheetState
    extends ConsumerState<_UnclaimedDepositSheet> {
  _DepositAction? _inFlight;
  late final String? _depositWalletId;

  /// A ceiling the person set under Advanced; null means the recommended
  /// one (the last network quote plus headroom) is used.
  int? _customMaxFeeSats;

  /// The last fee the SDK quoted for this claim, from the stored claim
  /// error, a fresh read or a rejected attempt.
  int? _quoteSats;

  @override
  void initState() {
    super.initState();
    _depositWalletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    _noteQuote(widget.tx.depositInfo?.claimError);
  }

  void _noteQuote(breez.DepositClaimError? error) {
    if (error is breez.DepositClaimError_MaxDepositClaimFeeExceeded) {
      _quoteSats = error.requiredFeeSats.toInt();
    }
  }

  /// The recommended ceiling: the last quote plus headroom, kept below the
  /// deposit. Null until the network has quoted this claim once.
  int? _recommendedFeeSats(int depositSats) {
    final quote = _quoteSats;
    return quote == null
        ? null
        : suggestedClaimFeeSats(
            lastQuoteSats: quote, depositAmountSats: depositSats);
  }

  int? _feeLimitSats(int depositSats) =>
      _customMaxFeeSats ?? _recommendedFeeSats(depositSats);

  int get _depositSats =>
      widget.tx.depositInfo?.amountSats.toInt() ?? widget.tx.amount.toInt();

  /// Advanced: a ceiling of the person's own, through the same picker the
  /// claim used to demand up front.
  Future<void> _pickFeeLimit() async {
    TrackingService.track('spark_deposit_fee_limit_opened');
    final picked = await showAppBottomSheet<int>(
      context: context,
      builder: (_) => ClaimFeePickerSheet(
        depositAmountSats: _depositSats,
        claimError: widget.tx.depositInfo?.claimError,
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() => _customMaxFeeSats = picked);
  }

  String _actionMessage(SparkDepositActionException e, {bool refund = false}) {
    final l10n = context.l10n;
    return switch (e.reason) {
      SparkDepositActionReason.walletChanged => l10n.depositActionWalletChanged,
      SparkDepositActionReason.busy => l10n.depositActionBusy,
      SparkDepositActionReason.walletUnavailable =>
        l10n.depositActionWalletUnavailable,
      SparkDepositActionReason.invalidDeposit =>
        l10n.depositActionInvalidDeposit,
      SparkDepositActionReason.immature => l10n.depositActionImmature,
      SparkDepositActionReason.refundInProgress =>
        l10n.depositActionRefundInProgress,
      SparkDepositActionReason.invalidFee =>
        refund ? l10n.invalidRate : l10n.depositActionInvalidFee,
      SparkDepositActionReason.invalidAddress => l10n.pleaseEnterAnAddress,
      SparkDepositActionReason.feeExceeded => l10n.depositAddFeeAboveLimit(
          ref.read(
              conversionProvider((e.requiredFeeSats ?? BigInt.zero).toInt()))),
    };
  }

  /// Claims with [maxFeeSats]. When the quote has moved above the
  /// recommended ceiling (nothing set under Advanced), retries once with
  /// the new recommendation instead of asking the person for a number.
  Future<SparkDepositClaimResult> _claimWithRetry(
    SparkDepositActions actions, {
    required String walletId,
    required int maxFeeSats,
    required int depositSats,
    required breez.DepositInfo? deposit,
  }) async {
    Future<SparkDepositClaimResult> attempt(int ceiling) => actions.claim(
          walletId: walletId,
          txid: widget.tx.txid,
          vout: widget.tx.vout,
          maxFeeSats: BigInt.from(ceiling),
          depositAmountSats:
              deposit?.amountSats ?? BigInt.from(widget.tx.amount),
        );
    try {
      return await attempt(maxFeeSats);
    } on SparkDepositActionException catch (e) {
      final required = e.requiredFeeSats?.toInt();
      if (e.reason != SparkDepositActionReason.feeExceeded ||
          required == null ||
          _customMaxFeeSats != null) {
        rethrow;
      }
      _quoteSats = required;
      final retry = suggestedClaimFeeSats(
          lastQuoteSats: required, depositAmountSats: depositSats);
      if (retry == null || retry <= maxFeeSats) {
        rethrow;
      }
      return attempt(retry);
    }
  }

  // Captured before any await so an attempted action still refreshes after
  // the sheet closes.
  void _refreshDeposits(ProviderContainer container) {
    container.invalidate(listSparkUnclaimedDepositsProvider);
    container.read(backgroundSyncNotifierProvider.notifier).performFullUpdate();
  }

  Future<void> _handleClaim() async {
    final walletId = _depositWalletId;
    if (_inFlight != null || walletId == null) {
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final actions = ref.read(sparkDepositActionsProvider);
    setState(() => _inFlight = _DepositAction.claim);
    var attempted = false;
    try {
      // A wallet that is not ready stops here. A failed list read falls back
      // to the row data; a deposit the SDK no longer lists skips the fee.
      breez.DepositInfo? live;
      var liveRead = false;
      try {
        live = await actions.liveDeposit(
            walletId: walletId, txid: widget.tx.txid, vout: widget.tx.vout);
        liveRead = true;
      } on SparkDepositActionException {
        rethrow;
      } catch (_) {}
      if (!mounted) {
        return;
      }
      final SparkDepositClaimResult result;
      if (liveRead && live == null) {
        attempted = true;
        result = await actions.missingDepositOutcome(
            walletId: walletId, txid: widget.tx.txid, vout: widget.tx.vout);
      } else {
        final deposit = live ?? widget.tx.depositInfo;
        final depositSats =
            deposit?.amountSats.toInt() ?? widget.tx.amount.toInt();
        // The freshest quote wins; the recommended ceiling follows it.
        _noteQuote(deposit?.claimError);
        var maxFeeSats = _feeLimitSats(depositSats);
        if (maxFeeSats == null) {
          // No quote yet and nothing set under Advanced: the picker is
          // the only way to a ceiling, as before.
          maxFeeSats = await showAppBottomSheet<int>(
            context: context,
            builder: (_) => ClaimFeePickerSheet(
              depositAmountSats: depositSats,
              claimError: deposit?.claimError,
            ),
          );
          if (!mounted || maxFeeSats == null) {
            return;
          }
        }
        attempted = true;
        result = await _claimWithRetry(
          actions,
          walletId: walletId,
          maxFeeSats: maxFeeSats,
          depositSats: depositSats,
          deposit: deposit,
        );
      }
      // An unknown status keeps the row listed in the SDK until its transfer
      // settles, so only the other outcomes drop it locally.
      if (result.outcome != SparkDepositClaimOutcome.statusUnknown) {
        container
            .read(walletTransactionCacheProvider.notifier)
            .removeSparkUnclaimedDeposit(walletId,
                txid: widget.tx.txid, vout: widget.tx.vout);
      }
      final claimedSats = widget.tx.amount.toInt();
      double? claimedUsd;
      try {
        final rate = ref.read(selectedCurrencyProvider('usd')).toDouble();
        if (rate > 0) claimedUsd = claimedSats / 1e8 * rate;
      } catch (_) {}
      TrackingService.sparkDepositClaimed(
        outcome: switch (result.outcome) {
          SparkDepositClaimOutcome.submitted => 'submitted',
          SparkDepositClaimOutcome.alreadyReceived => 'already_received',
          SparkDepositClaimOutcome.noLongerPending => 'no_longer_pending',
          SparkDepositClaimOutcome.statusUnknown => 'status_unknown',
        },
        status: result.paymentStatus?.name,
        amountSats: claimedSats > 0 ? claimedSats : null,
        amountUsd: claimedUsd,
        trigger: 'manual',
      );
      if (!mounted) {
        return;
      }
      switch (result.outcome) {
        case SparkDepositClaimOutcome.submitted:
          // The success moment: the sheet closes and the shared
          // confirmation takes over, honest about a transfer still landing.
          final message = context.l10n.activityBitcoinAdded;
          final detail = result.paymentStatus == breez.PaymentStatus.completed
              ? null
              : context.l10n.activityBitcoinAddedPending;
          context.pop();
          pushKuteSuccessOverlay(
            navigator: rootNav,
            overlay: KuteConfirmation(
              message: message,
              detail: detail,
              onDone: () => rootNav.pop(),
            ),
          );
          return;
        case SparkDepositClaimOutcome.alreadyReceived:
          showMessageSnackBarInfo(
              context: context, message: context.l10n.depositAlreadyReceived);
        case SparkDepositClaimOutcome.noLongerPending:
          showMessageSnackBarInfo(
              context: context, message: context.l10n.depositNoLongerPending);
        case SparkDepositClaimOutcome.statusUnknown:
          showMessageSnackBarInfo(
              context: context,
              message: context.l10n.depositClaimStatusUnknown);
      }
      context.pop();
    } on SparkDepositActionException catch (e) {
      TrackingService.sparkDepositClaimFailed(reason: e.reason.name);
      if (mounted) {
        showMessageSnackBar(
            context: context, message: _actionMessage(e), error: true);
      }
    } catch (e) {
      TrackingService.sparkDepositClaimFailed(reason: 'sdk_error');
      if (mounted) {
        // Unknown SDK errors never reach the user verbatim.
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, e,
                fallback: context.l10n.depositAddFailed),
            error: true);
      }
    } finally {
      if (attempted) {
        _refreshDeposits(container);
      }
      if (mounted) {
        setState(() => _inFlight = null);
      }
    }
  }

  Future<void> _handleRefund() async {
    final walletId = _depositWalletId;
    if (_inFlight != null || walletId == null) {
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final actions = ref.read(sparkDepositActionsProvider);
    setState(() => _inFlight = _DepositAction.refund);
    var attempted = false;
    try {
      final result = await showAppBottomSheet<({String address, int rate})>(
        context: context,
        builder: (_) => const RefundAddressModalSheet(),
      );
      if (!mounted || result == null) {
        return;
      }
      // Phase 1b: the refund step-up binds the reviewed destination, fee
      // rate and deposit. A cancelled or denied prompt attempts no refund.
      SensitiveIntent refundIntent() => SensitiveIntent(
            action: SensitiveAction.sparkRefund,
            walletId: walletId,
            venue: 'bitcoin',
            destination: result.address.trim(),
            asset: 'BTC',
            amountMax: BigInt.from(widget.tx.amount),
            limits: {
              'deposit': '${widget.tx.txid}:${widget.tx.vout}',
              'satPerVbyte': result.rate,
            },
          );
      double? amountUsd;
      try {
        amountUsd = widget.tx.amount /
            1e8 *
            ref.read(selectedCurrencyProvider('usd')).toDouble();
      } catch (_) {}
      final grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: refundIntent(),
        reason: context.l10n.stepUpReasonRefund,
        amountUsd: amountUsd,
      );
      if (grant == null || !mounted) {
        return;
      }
      try {
        AuthGrants.consume(grant, refundIntent());
      } on ReauthRequired catch (e) {
        await showStepUpReviewAgain(context,
            action: SensitiveAction.sparkRefund, field: e.primaryFieldClass);
        return;
      } on AuthGrantException {
        return;
      }
      attempted = true;
      await actions.refund(
        walletId: walletId,
        txid: widget.tx.txid,
        vout: widget.tx.vout,
        address: result.address,
        satPerVbyte: BigInt.from(result.rate),
      );
      TrackingService.track('spark_deposit_refunded', params: {
        'network': 'bitcoin',
        ...TrackingService.moneyParams(
          amountUsd: amountUsd,
          amount: widget.tx.amount / 1e8,
          asset: 'btc',
          amountSats: widget.tx.amount.toInt(),
        ),
      });
      if (!mounted) {
        return;
      }
      // Completed action: close the sheet and end on the confirmation.
      final message = context.l10n.activityRefundStarted;
      final detail = context.l10n.depositRefundSubmitted;
      context.pop();
      pushKuteSuccessOverlay(
        navigator: rootNav,
        overlay: KuteConfirmation(
          message: message,
          detail: detail,
          onDone: () => rootNav.pop(),
        ),
      );
    } on SparkDepositActionException catch (e) {
      TrackingService.sparkDepositRefundFailed(reason: e.reason.name);
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: _actionMessage(e, refund: true),
            error: true);
      }
    } catch (e) {
      // The SDK stores the signed refund before broadcasting it.
      breez.DepositInfo? live;
      try {
        live = await actions.liveDeposit(
            walletId: walletId, txid: widget.tx.txid, vout: widget.tx.vout);
      } catch (_) {}
      final signed = live?.refundTxId?.isNotEmpty == true ||
          live?.refundTx?.isNotEmpty == true;
      TrackingService.sparkDepositRefundFailed(
          reason: signed ? 'broadcast_unconfirmed' : 'sdk_error');
      if (mounted) {
        if (signed) {
          showMessageSnackBarInfo(
              context: context,
              message: context.l10n.depositRefundBroadcastUnconfirmed);
          context.pop();
        } else {
          showMessageSnackBar(
              context: context,
              message: userErrorCopy(context, e,
                  fallback: context.l10n.depositRefundStartFailed),
              error: true);
        }
      }
    } finally {
      if (attempted) {
        _refreshDeposits(container);
      }
      if (mounted) {
        setState(() => _inFlight = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final depositSats = _depositSats;
    final custom = _customMaxFeeSats;
    final limit = _feeLimitSats(depositSats);
    // "Up to ₿350" once the network has quoted the claim; until then the
    // fee is quoted when the person adds the bitcoin.
    final feeLabel = limit == null
        ? context.l10n.activityFeeQuotedWhenAdded
        : context.l10n.activityUpToAmount(ref.watch(conversionProvider(limit)));
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: SheetScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TransactionDetailHeader(
                row: _buildUnclaimedItem(widget.tx, context, ref),
                advisorSurface: 'deposit_tx_detail',
              ),
              if (!widget.isRefunding) ...[
                _sheetDetailRow(c, context.l10n.activityNetworkFee, feeLabel),
                // The ceiling is an Advanced control: the recommended one
                // applies unless the person sets their own here.
                _NerdDataSection(
                  title: context.l10n.advanced,
                  children: [
                    SheetDetailRow(
                      label: context.l10n.activityFeeLimit,
                      value: custom == null
                          ? feeLabel
                          : context.l10n.activityUpToAmount(
                              ref.watch(conversionProvider(custom))),
                      trailingIcon: Icons.edit_outlined,
                      onTap: _inFlight == null ? _pickFeeLimit : null,
                    ),
                  ],
                ),
              ],
              // Type, status and outpoint are nerd data — collapsed.
              _NerdDataSection(children: [
                _sheetDetailRow(
                    c, context.l10n.type, context.l10n.activityOnChainDeposit),
                _sheetDetailRow(
                    c,
                    context.l10n.status,
                    widget.isRefunding
                        ? context.l10n.refunding
                        : context.l10n.activityUnclaimed,
                    valueColor: widget.isRefunding
                        ? AppColors.info
                        : context.colors.accent),
                _sheetDetailRow(c, context.l10n.txId, widget.tx.txid,
                    copiable: true, isAddress: true, ctx: context),
                _sheetDetailRow(
                    c, context.l10n.vout, widget.tx.vout.toString()),
              ]),
              SizedBox(height: 16.h),
              // One primary action; the refund is a quiet text link.
              if (!widget.isRefunding) ...[
                if (widget.tx.isMature) ...[
                  AppButton(
                    text: context.l10n.activityAddToWallet,
                    onPressed: _inFlight != null ? null : _handleClaim,
                    isLoading: _inFlight == _DepositAction.claim,
                    textColor: Colors.white,
                    compact: true,
                  ),
                  SizedBox(height: 6.h),
                ],
                AppBottomSheetTextButton(
                  text: _inFlight == _DepositAction.refund
                      ? context.l10n.activityProcessingEllipsis
                      : context.l10n.refund,
                  onPressed: _inFlight != null ? null : _handleRefund,
                ),
                SizedBox(height: 4.h),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PolymarketTxIcon extends ConsumerWidget {
  final bool isSend;
  final ActivityType type;

  /// Market / event icon URL from the Polymarket Data API.
  /// When present, we render the actual market image (e.g. candidate
  /// portrait, sports team crest, weather emoji) so the row is
  /// recognisable at a glance. Falls back to the generic Predictions
  /// "P" mark when the URL is missing or fails to load.
  final String? iconUrl;
  const _PolymarketTxIcon({
    required this.isSend,
    required this.type,
    this.iconUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = 44.sp;
    final fallback = AssetIcon(assetCode: 'Predictions', size: size);
    if (iconUrl == null || iconUrl!.isEmpty) {
      return SizedBox(width: size, height: size, child: fallback);
    }
    // PolyCrestImage (not raster CachedNetworkImage): team crests resolved
    // by activityCrestIcon are frequently .svg, which the raster loader
    // can't decode — it would silently fall back to the generic "P" mark.
    // A round tile like every other row icon; a crest with a transparent
    // background sits on a faint disc instead of the bare card.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.textPrimary.withValues(alpha: 0.05),
      ),
      child: PolyCrestImage(
        url: iconUrl!,
        size: size,
        radius: size / 2,
        fallback: fallback,
      ),
    );
  }
}

class _AssetTxIcon extends ConsumerWidget {
  final String assetCode;
  final bool isSend;
  const _AssetTxIcon({required this.assetCode, required this.isSend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main asset icon
          AssetIcon(assetCode: assetCode, size: 44.sp),
          // Directional arrow overlay
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18.sp,
              height: 18.sp,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 1),
              ),
              child: Center(
                child: Icon(
                  isSend ? Icons.north_east_rounded : Icons.south_west_rounded,
                  size: 12.sp,
                  color: isSend ? fintechRed : fintechGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Cash App mark alone, with the inbound badge every purchase row
/// wears. The title already names what the money became ("Cash App →
/// Bitcoin"), so the icon says only where it came from, the same on
/// every destination and on the detail sheet.
class _CashAppTxIcon extends StatelessWidget {
  const _CashAppTxIcon();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22.sp),
            child: SvgPicture.asset(
              'lib/assets/cashapp-logo.svg',
              width: 44.sp,
              height: 44.sp,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16.sp,
              height: 16.sp,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 1),
              ),
              child: Center(
                child: Icon(
                  Icons.south_west_rounded,
                  size: 10.sp,
                  color: fintechGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapTxIcon extends ConsumerWidget {
  final String fromCode;
  final String toCode;
  const _SwapTxIcon({
    required this.fromCode,
    required this.toCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // First (from) icon
          Positioned(
            left: 0,
            top: 2,
            child: AssetIcon(assetCode: fromCode, size: 32.sp),
          ),
          // Second (to) icon, overlapping
          Positioned(
            right: 0,
            bottom: 2,
            child: AssetIcon(assetCode: toCode, size: 32.sp),
          ),
          // Swap badge
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16.sp,
              height: 16.sp,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 1),
              ),
              child: Center(
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 10.sp,
                  color: context.colors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlogicTxIcon extends ConsumerWidget {
  final bool isBuy;
  final String fiatAsset;
  const _OutlogicTxIcon({required this.isBuy, required this.fiatAsset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Fiat currency icon (back)
          Positioned(
            left: 0,
            top: 2,
            child: AssetIcon(assetCode: fiatAsset, size: 32.sp),
          ),
          // BTC icon (front, overlapping)
          Positioned(
            right: 0,
            bottom: 2,
            child: AssetIcon(assetCode: 'BTC', size: 32.sp),
          ),
          // Direction badge
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16.sp,
              height: 16.sp,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 1),
              ),
              child: Center(
                child: Icon(
                  isBuy ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 10.sp,
                  color: isBuy ? fintechGreen : fintechRed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingIconWrapper extends StatelessWidget {
  final Widget child;
  const _PendingIconWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48.sp,
      height: 48.sp,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          SizedBox(
            width: 48.sp,
            height: 48.sp,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: context.colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status word for a row's secondary line ("Pending", "Expired",
/// "Attention"). Sentence case, coloured text only: no pill, no
/// outline, no uppercase. `_TransactionRow` renders it inline ahead of
/// the subtitle so every row in the feed shares one vocabulary with
/// the Predictions and Investing activity rows. Pending states use the
/// theme's warning amber, failed states use marketDown.
class _RowStatus {
  final String text;
  final Color color;
  const _RowStatus({required this.text, required this.color});
}

// Empty state shown where a transaction list is expected but has
// nothing to render. Displays the kute_dog mascot + a quiet message
// rather than a loading spinner — callers only reach this code once
// they've decided the list is definitively empty (post-filter), so a
// spinner reads as misleading "still loading" UI when nothing is
// coming. Used by TransactionList (inside Activity).
Widget buildNoTransactionsFound([BuildContext? context]) {
  final textColor =
      context != null ? context.colors.textTertiary : Colors.grey[600]!;
  return Padding(
    padding: EdgeInsets.only(top: 40.h, bottom: 40.h),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            context != null ? kuteDogAsset(context) : kuteDogLightAsset,
            width: 48.sp,
            height: 48.sp,
          ),
          SizedBox(height: 12.h),
          Text(
            context != null
                ? context.l10n.activityNoTransactionsYet
                : 'No transactions yet',
            style: TextStyle(
              color: textColor,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Open Ledger account" for a Bitcoin transaction that funds a pending
/// Ledger settlement operation (Phase 5 plan B13). It stays available with
/// `kLedgerInvestingEnabled` off, so turning the flag off never strands a
/// pending operation's account. Renders nothing for any other transaction.
class _LedgerSettlementLink extends ConsumerWidget {
  const _LedgerSettlementLink({required this.txid});

  final String txid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op =
        ref.watch(pendingLedgerSettlementForTxidProvider(txid)).valueOrNull;
    if (op == null) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: SizedBox(
        width: double.infinity,
        height: 48.h,
        child: OutlinedButton.icon(
          onPressed: () {
            TrackingService.settlementOpenLedgerAccountTapped(
                stage: op.stage.name);
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.pushNamed(
              'walletDetail',
              pathParameters: {'walletId': op.walletId},
              queryParameters: const {'view': 'ledger'},
            );
          },
          icon: Icon(Icons.account_balance_wallet_outlined, size: 18.sp),
          label: Text(
            context.l10n.settlementOpenLedgerAccount,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.textPrimary,
            side: BorderSide(color: c.border),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonBorder),
          ),
        ),
      ),
    );
  }
}
