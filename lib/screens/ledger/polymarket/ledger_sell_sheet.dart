// lib/screens/ledger/polymarket/ledger_sell_sheet.dart
//
// Sell a Polymarket position held by a Ledger account.
//
// Presentation is the spending account's sell ticket
// (`screens/polymarket/components/sell_sheet.dart`): the whole sheet
// wears the red side tint, the shared `slip_chrome` header / figure /
// Advanced row / CTA, one big typed dollar figure over the shared
// keypad, and the bet slip's fee block. There are no percent chips —
// tapping the position's value under the figure sells the whole thing,
// exactly as it does on the spending sheet.
//
// The signing path is unchanged:
// * Reads the position and account through the wallet-scoped Ledger
//   provider only; no hot provider.
// * The first sale (or claim) asks for the one-time CTF share approvals
//   first, as their own Ledger approval (ensureLedgerPmShareApprovals).
// * The intent (shares, minimum proceeds, salt, timestamp) is built when
//   the user taps the CTA and is executed exactly as reviewed.
// * Success says "Sold" only when the CLOB answered `matched`; otherwise
//   "Submitted. Waiting for confirmation." A pending submission locks the
//   CTA so the same position cannot be sold twice from this sheet.
// * Cancel, rejection or disconnect keep the typed amount.
// * A legacy Safe account is read-only (O4).

import 'dart:math';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show PolymarketSellPriceMoved, polymarketCentsLabel, polymarketSellFloor;
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class LedgerSellSheet extends ConsumerStatefulWidget {
  const LedgerSellSheet({
    super.key,
    required this.walletId,
    required this.position,
  });

  final String walletId;
  final Position position;

  static Future<void> show(
    BuildContext context, {
    required String walletId,
    required Position position,
  }) {
    TrackingService.ledgerActionSheetOpened(action: 'pm_sell');
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) => LedgerSellSheet(walletId: walletId, position: position),
    );
  }

  @override
  ConsumerState<LedgerSellSheet> createState() => _LedgerSellSheetState();
}

class _LedgerSellSheetState extends ConsumerState<LedgerSellSheet> {
  static const double _slippage = 0.05;

  /// The typed dollar figure, the amount it parses to and the shares it
  /// buys back at the best bid. The spending sheet's model exactly: the
  /// user types money, the shares are derived, and the share count is
  /// what the intent carries.
  String _amountText = '';
  double _amountUsd = 0;
  double _sharesToSell = 0;

  double? _bestBid;
  String? _tickSize;
  bool _loadingBook = true;
  bool _preparing = false;
  bool _submittedPending = false;

  /// True while the Advanced route is being pushed, so a double tap on
  /// the row cannot stack two copies of the screen. Mirrors the spending
  /// sheet.
  bool _openingAdvanced = false;

  Position get _position => widget.position;

  /// The sheet only takes input while nothing is in flight and nothing is
  /// waiting on the chain.
  bool get _canEdit => !_preparing && !_submittedPending;

  @override
  void initState() {
    super.initState();
    unawaited(VenueAnalytics.ensurePolymarket(
        slug: widget.position.eventSlug,
        ids: [widget.position.asset, widget.position.conditionId]));
    TrackingService.polymarketSellInitiated(
        marketId: widget.position.asset,
        walletKind: 'ledger',
        extra: const {'entry_source': 'ledger_portfolio'});
    _loadBook();
  }

  Future<void> _loadBook() async {
    final model = PolymarketModel();
    try {
      final book = await model.getOrderBook(_position.asset);
      if (!mounted) return;
      setState(() {
        _bestBid = book.bestBid;
        _tickSize = book.minTickSize;
        _loadingBook = false;
        _recomputeShares();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBook = false);
    } finally {
      model.dispose();
    }
  }

  /// Shares the typed dollars buy back at the best bid, clamped to the
  /// position so the user cannot oversell. With no bid the sheet has
  /// nothing to convert with and says so rather than computing from zero.
  void _recomputeShares() {
    final bid = _bestBid;
    if (bid == null || bid <= 0) {
      _sharesToSell = 0;
      return;
    }
    _sharesToSell = (_amountUsd / bid).clamp(0.0, _position.size);
  }

  void _onAmountChanged(String value) {
    setState(() {
      _amountText = value;
      _amountUsd = double.tryParse(value) ?? 0.0;
      _recomputeShares();
    });
  }

  /// The position's value IS the quick-amount control: there is no
  /// percent row on this ticket, so tapping the figure underneath fills
  /// the whole position. `_position.size` is used exactly, so the
  /// fill-or-kill quote gets the same share count the old Max chip
  /// produced rather than a number rounded through the typed string.
  void _sellWholePosition() {
    final bid = _bestBid;
    if (bid == null || bid <= 0 || !_canEdit) return;
    final usd = _position.size * bid;
    final seed = usd <= 0
        ? ''
        : (usd == usd.roundToDouble()
            ? usd.toStringAsFixed(0)
            : usd.toStringAsFixed(2));
    setState(() {
      _amountText = seed;
      _amountUsd = usd;
      _sharesToSell = _position.size;
    });
    HapticFeedback.selectionClick();
    TrackingService.track('ledger_sell_sheet_available_tapped');
  }

  /// Push the Advanced page the way the spending sheet does: a
  /// full-screen dialog route on the ROOT navigator, which sits ABOVE
  /// this sheet's `SideTintedSubtree` and so keeps the app palette with
  /// no stripping code. Nothing on it is editable — a Ledger sell is
  /// always an immediate fill-or-kill at the fixed slippage — so it
  /// returns nothing and the sheet's state is untouched.
  Future<void> _openAdvanced() async {
    if (_openingAdvanced) return;
    // Withheld Advanced opens nothing, as on the spending sheet.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    _openingAdvanced = true;
    HapticFeedback.selectionClick();
    TrackingService.track('ledger_sell_sheet_advanced_opened');
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _LedgerSellAdvancedScreen(
            marketQuestion: _position.title,
            outcome: _position.outcome,
            slippage: _slippage,
          ),
        ),
      );
    } finally {
      _openingAdvanced = false;
    }
  }

  /// The best bid and tick now, or null when the book cannot be read.
  Future<({double bid, String? tick})?> _readBid() async {
    final model = PolymarketModel();
    try {
      final book = await model
          .getOrderBook(_position.asset)
          .timeout(const Duration(seconds: 3));
      final bid = book.bestBid;
      return bid == null || bid <= 0
          ? null
          : (bid: bid, tick: book.minTickSize);
    } catch (_) {
      return null;
    } finally {
      model.dispose();
    }
  }

  /// Set when a sale stopped because the bid fell under the signed floor:
  /// the floor a new approval would name, for "Retry at 41¢".
  double? _retryPrice;

  Future<void> _sell(PolymarketLedgerAccount account) async {
    final depositWallet = account.address;
    if (_preparing ||
        _submittedPending ||
        _bestBid == null ||
        depositWallet == null) {
      return;
    }
    final l10n = context.l10n;
    setState(() {
      _preparing = true;
      _retryPrice = null;
    });
    // The exchanges must be allowed to move the shares: the first sale
    // asks for the one-time share approvals as their own Ledger approval,
    // before the bid is read and the order is built.
    final ready = await ensureLedgerPmShareApprovals(context, ref,
        walletId: widget.walletId, account: account);
    if (!mounted) return;
    if (!ready) {
      setState(() => _preparing = false);
      return;
    }
    // The bid as it is now, not when the sheet opened: the floor the
    // device signs is computed from it (polymarketSellFloor).
    final latest = await _readBid();
    if (!mounted) return;
    if (latest != null) {
      _bestBid = latest.bid;
      _tickSize = latest.tick ?? _tickSize;
    }
    setState(() => _preparing = false);
    final bid = _bestBid!;
    final quote = buildLedgerPmSellQuote(
      shares: _sharesToSell,
      bestBid: bid,
      tickSize: _tickSize,
      slippage: _slippage,
    );
    if (quote == null) {
      showMessageSnackBar(
          context: context, message: l10n.ledgerSellTooSmall, error: true);
      return;
    }

    setState(() => _preparing = true);
    // The backend's code, or the zero builder when it has none to give:
    // attribution never stands between the person and a sale.
    final builderCode = await PolymarketBackendService.getBuilderCode();
    if (!mounted) return;

    final now = DateTime.now();
    final salt = BigInt.from(
        (now.millisecondsSinceEpoch / 1000 * Random.secure().nextDouble())
            .round());
    final walletId = widget.walletId;
    final intent = LedgerPolymarketIntents.sell(
      walletId: walletId,
      depositWallet: depositWallet,
      tokenId: _position.asset,
      shares: quote.makerAmount,
      minProceeds: quote.takerAmount,
      negRisk: _position.negativeRisk,
      salt: salt,
      timestampMs: now.millisecondsSinceEpoch,
      orderType: OrderType.fok,
      builderCode: builderCode,
      summary: {
        l10n.ledgerSummaryMarket: _position.title,
        l10n.ledgerSummaryOutcome: _position.outcome,
        l10n.ledgerSummaryShares: ledgerFormatShares(quote.makerAmount),
        l10n.ledgerSummaryMinProceeds: ledgerFormatMicros(quote.takerAmount),
      },
      now: now,
    );
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    PolymarketSellPriceMoved? moved;
    final outcome = await showLedgerApprovalSheet<LedgerPmSellResult>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<LedgerPmSellResult>(
        intent: intent,
        amountUsd: quote.takerAmount.toDouble() / 1e6,
        execute: (signing) => factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
          account: account,
        ).sell(intent, revalidate: () async {
          // Signed; before it is sent the bid must still be at or above
          // the signed floor, or nothing goes out.
          final fresh = await _readBid();
          if (fresh != null && fresh.bid < quote.price - 1e-9) {
            final tick = 1 /
                pow(10, ledgerPmRoundingForTick(fresh.tick ?? _tickSize).$1);
            throw moved = PolymarketSellPriceMoved(
                price: fresh.bid,
                limit: quote.price,
                retryPrice: polymarketSellFloor(
                    bid: fresh.bid,
                    slippagePct: _slippage * 100,
                    tick: tick.toDouble()));
          }
        }),
      ),
    );
    // Canonical sale event for the Ledger account (wallet_kind 'ledger'),
    // only on a match, like the spending sheet. providerOrderId is the same
    // order hash the executor logged as 'pending' before submitting, so the
    // backend upserts that row instead of adding a second one. Proceeds are
    // the signed minimum (the fill can only be better).
    final sold = outcome.result;
    if (outcome.kind == LedgerApprovalOutcomeKind.success &&
        sold?.status?.toLowerCase() == 'matched' &&
        quote.makerAmount > BigInt.zero) {
      final shares = quote.makerAmount.toDouble() / 1e6;
      final proceeds = quote.takerAmount.toDouble() / 1e6;
      TrackingService.polymarketPositionSold(
        marketId: _position.asset,
        shares: shares,
        price: proceeds / shares,
        pnl: proceeds - _position.avgPrice * shares,
        providerOrderId: sold?.orderId,
        orderType: 'market',
        walletKind: 'ledger',
        extra: {
          'entry_source': 'ledger_portfolio',
          'sell_scope':
              shares >= _position.size - 0.000001 ? 'all' : 'partial',
          'pct_of_position': _position.size > 0
              ? ((shares / _position.size) * 100).round().clamp(0, 100)
              : 0,
        },
      );
    }
    if (!mounted) return;
    setState(() => _preparing = false);

    switch (outcome.kind) {
      case LedgerApprovalOutcomeKind.success:
        ref.invalidate(ledgerPmAccountProvider(walletId));
        final matched = outcome.result?.status?.toLowerCase() == 'matched';
        Navigator.of(context).pop();
        showLedgerConfirmation(
          navigator,
          message: matched ? l10n.ledgerSold : l10n.ledgerPendingStatus,
        );
      case LedgerApprovalOutcomeKind.pending:
      case LedgerApprovalOutcomeKind.backgrounded:
        ref.invalidate(ledgerPendingActionsProvider(walletId));
        setState(() => _submittedPending = true);
      case LedgerApprovalOutcomeKind.cancelled:
      case LedgerApprovalOutcomeKind.failed:
        // The typed amount stays as it was. A bid that fell under the
        // signed floor says so, and the button offers the new floor.
        final m = moved;
        if (m != null) {
          setState(() => _retryPrice = m.retryPrice);
          showMessageSnackBar(
              context: context,
              message: l10n.betSellPriceMoved(polymarketCentsLabel(m.price),
                  polymarketCentsLabel(m.limit)),
              error: true);
        }
    }
  }

  /// Compact ¢/$ share-price formatter, the spending sheet's. Sub-dollar
  /// prices read as cents with one decimal (`9.0¢`), $1+ flips to dollar
  /// formatting.
  String _formatPriceCompact(double v) {
    if (v >= 1.0) return '\$${v.toStringAsFixed(2)}';
    final cents = v * 100;
    if (cents >= 10) return '${cents.toStringAsFixed(0)}¢';
    return '${cents.toStringAsFixed(1)}¢';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final pm = ref.watch(ledgerPmAccountProvider(widget.walletId)).valueOrNull;
    final account = pm?.account;
    final canAct = account != null && account.canAct && account.address != null;
    final bid = _bestBid;
    // Everything the ticket states about value is quoted at the bid the
    // sale would actually fill at; with no bid there is no value line and
    // the figure says the price is unavailable.
    final price = bid ?? _position.curPrice;
    final positionValue = bid == null ? null : _position.size * bid;
    final pnl = (price - _position.avgPrice) * _position.size;
    final pnlPct = _position.avgPrice > 0
        ? ((price - _position.avgPrice) / _position.avgPrice) * 100
        : 0.0;
    final canSell = canAct &&
        bid != null &&
        _sharesToSell > 0 &&
        _sharesToSell <= _position.size;

    // Selling is money coming out, so the ticket wears the red side the
    // same way the spending sheet does: the whole subtree is handed the
    // tinted palette and every child that reads `context.colors` follows
    // without knowing about it.
    //
    // Nothing inside the tinted subtree opens a sheet of its own. The
    // approval sheet and the error snackbars are raised from
    // `State.context`, which sits ABOVE this wrapper, so the theme they
    // capture is the app's real palette rather than ink meant for red.
    const sideColor = AppColors.marketDown;
    final tc = sideTintPalette(c, sideColor);

    final viewInsetBottom = MediaQuery.of(context).viewInsets.bottom;
    // The OS bottom inset, applied by hand so the sheet clears the home
    // indicator on BOTH platforms.
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final form = Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PositionCard(
            outcome: _position.outcome,
            size: _position.size,
            value: positionValue,
            pnl: pnl,
            pnlPct: pnlPct,
            colors: tc,
          ),
          SizedBox(height: 8.h),
          Text(
            l10n.betAvgNowPrice(_formatPriceCompact(_position.avgPrice),
                _formatPriceCompact(price)),
            style: TextStyle(
              color: tc.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 22.h),
          // One big typed figure, the share equivalent and the position's
          // value underneath. There is no TextField on this step, so the
          // OS keyboard never opens over the ticket; the pinned keypad
          // below the form is the only way in.
          BigAmountDisplay(
            prefix: r'$',
            amountText: _amountText,
            conversionLoading: _loadingBook,
            conversionLabel: bid == null
                ? l10n.ledgerPriceUnavailable
                : (_sharesToSell > 0
                    ? '≈ ${l10n.betSharesCount(_sharesToSell.toStringAsFixed(2))}'
                    : null),
            conversionIsError: !_loadingBook && bid == null,
            availableLabel: positionValue == null
                ? null
                : '${l10n.available} ${ledgerFormatUsd(positionValue)}',
            availableExceeded:
                positionValue != null && _amountUsd > positionValue,
            // One small Max beside the figure, as on the spending sheet:
            // the whole position. Nothing to sell, no chip; dimmed while
            // the price is unknown or a sale is under way.
            trailing: _position.size > 0 && (positionValue ?? 1) > 0
                ? AmountMaxChip(
                    label: l10n.max,
                    semanticLabel: l10n.amountUseMaximum,
                    onTap: positionValue == null || !_canEdit
                        ? null
                        : _sellWholePosition,
                  )
                : null,
          ),
          SizedBox(height: 24.h),
          // The estimated fee, and nothing else (owner decision): no
          // proceeds line before it and none after it.
          PolymarketFeeSummary(
              tokenId: _position.asset,
              shares: _sharesToSell,
              price: bid ?? 0,
              bitcoinFirst: false),
          SizedBox(height: 8.h),
          PolySlipAdvancedRow(onTap: _openAdvanced),
          SizedBox(height: 4.h),
          // What only a Ledger seller needs to know, on the ticket's
          // secondary line rather than hidden behind Advanced.
          if (pm?.isReadOnly == true)
            LedgerNote(text: l10n.ledgerPmLegacyReadOnly)
          else if (pm != null && !canAct)
            LedgerNote(text: l10n.ledgerErrorAccountUnsupported),
          if (_submittedPending)
            LedgerNote(
                text: l10n.ledgerPendingStatus, icon: Icons.schedule_rounded),
          LedgerNote(text: l10n.ledgerSellSlippageNote),
          SizedBox(height: 12.h),
        ],
      ),
    );

    return SideTintedSubtree(
      side: sideColor,
      child: Container(
        // Bottom-modal chrome — the spending ticket's, to the pixel: the
        // side colour as the fill, rounded-top corners, max 92% screen
        // height, sized to content.
        padding: EdgeInsets.only(bottom: viewInsetBottom),
        decoration: BoxDecoration(
          color: sideColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          border: Border(top: BorderSide(color: tc.border)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.of(context).size.height * 0.92 - viewInsetBottom)
                    .clamp(0.0, double.infinity),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PolySlipHeader(
                marketQuestion: _position.title,
                marketImage: _position.icon,
              ),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  primary: false,
                  child: form,
                ),
              ),
              // The sheet's only amount input, pinned under the scrolling
              // form so the figure above it never hides behind anything.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: AmountKeypad(
                  value: _amountText,
                  maxDecimals: 2,
                  enabled: _canEdit,
                  onChanged: _onAmountChanged,
                ),
              ),
              Padding(
                padding:
                    EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h + safeBottom),
                child: _submittedPending
                    ? PolySlipCta(
                        color: sideColor,
                        isBusy: false,
                        enabled: true,
                        onTap: () => Navigator.of(context).pop(),
                        label: l10n.ledgerApprovalClose,
                      )
                    : PolySlipCta(
                        color: sideColor,
                        isBusy: _preparing,
                        enabled: canSell && !_preparing,
                        onTap: () => _sell(account!),
                        busyLabel: l10n.betSellingEllipsis,
                        label: canSell && _retryPrice != null
                            ? l10n.betRetryAtPrice(
                                polymarketCentsLabel(_retryPrice!))
                            : canSell
                                ? '${l10n.sell} · ${ledgerFormatUsd(_amountUsd)}'
                                : l10n.sell,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sell ticket's side block: what is being sold and what it is worth
/// right now. Inert, so it stays on the quietest step of the tinted
/// palette.
///
/// The outcome is neutral ink on purpose. The sheet's own red already
/// means "selling", so a second directional fill beside it would both
/// vanish and lie. The gain and loss line keeps its sign and reads
/// through `success` / `error`, which the tinted palette collapses onto
/// the contrast ink.
class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.outcome,
    required this.size,
    required this.value,
    required this.pnl,
    required this.pnlPct,
    required this.colors,
  });

  final String outcome;
  final double size;

  /// Null until the book answers; the card shows a dash rather than a
  /// value computed from a price it does not have.
  final double? value;
  final double pnl;
  final double pnlPct;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final v = value;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  outcome.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  context.l10n.betSharesCount(size.toStringAsFixed(1)),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v == null ? '--' : ledgerFormatUsd(v),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (v != null) ...[
                SizedBox(height: 3.h),
                Text(
                  '${pnl >= 0 ? '+' : '-'}${ledgerFormatUsd(pnl.abs())} '
                  '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: pnl >= 0 ? c.success : c.error,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The Ledger sell ticket's Advanced page: the order the device will be
/// asked to sign.
///
/// It is pushed as a full-screen dialog on the root navigator, so it sits
/// ABOVE the sheet's `SideTintedSubtree` and keeps the app palette. Only
/// sheets wear the side colour.
///
/// Every value here is fixed. A Ledger sell is always an immediate
/// fill-or-kill at the sheet's slippage, so the page states the terms
/// instead of offering controls that would change what was reviewed on
/// the device.
class _LedgerSellAdvancedScreen extends StatelessWidget {
  const _LedgerSellAdvancedScreen({
    required this.marketQuestion,
    required this.outcome,
    required this.slippage,
  });

  final String marketQuestion;
  final String outcome;
  final double slippage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const KuteBackButton(),
        centerTitle: true,
        title: Text(
          l10n.betAdvancedSale,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                primary: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 12.h),
                      Text(marketQuestion,
                          style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                      SizedBox(height: 20.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(16.r),
                          border:
                              Border.all(color: c.borderSubtle, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.portfolioTabOrders,
                                style: TextStyle(
                                    fontSize: 17.sp,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                            SizedBox(height: 8.h),
                            SheetDetailRow(
                                label: l10n.ledgerSellOrderType,
                                value: l10n.betOrderTypeSpot),
                            SheetDetailRow(
                                label: l10n.ledgerSummaryOutcome,
                                value: outcome),
                            SheetDetailRow(
                              label: l10n.maxSlippage,
                              value: '${(slippage * 100).toStringAsFixed(0)}%',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8.h),
                      LedgerNote(text: l10n.ledgerSellAdvancedFixedNote),
                      SizedBox(height: 16.h),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
              child: AppButton(
                text: l10n.done,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
