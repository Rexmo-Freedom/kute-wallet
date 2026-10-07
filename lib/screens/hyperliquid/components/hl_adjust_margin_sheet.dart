// lib/screens/hyperliquid/components/hl_adjust_margin_sheet.dart
//
// Add or remove margin on an ISOLATED Hyperliquid position
// (updateIsolatedMargin). Leverage setting, size and side stay as they
// are; only the money behind the position moves, and with it the
// liquidation price and the Investing balance.
//
// Built like the close-position ticket, piece for piece: the sheet wears
// the move's direction (money into the position green, out of it red),
// the header carries the market's logo, the title and the side and
// leverage chips, an Add / Remove pill pair under it switches the mode
// (Add by default; no Remove on a market that locks isolated margin),
// the one big figure is typed on the pinned keypad,
// $10 / $25 / $50 / Max fill it (Max: the Investing balance when adding,
// what the venue lets come out when removing), a summary says in plain
// words what the tap does with the numbers that change, and the pinned
// button carries the wait. Success is the app's confirmation screen with
// a receipt; a refusal stays on the ticket in plain words.
//
// Money safety: the amount is approved with the same step-up grant as
// every other money action (HlIntents.isolatedMargin binds market, side,
// direction and the exact amount) and the notifier re-checks the
// position, and that the market is the position's own, before signing.
// Spending wallet only: the Ledger signer has no reviewed path for this
// action, so the position screen hides the button for a Ledger position.
//
// Analytics (hyperliquid_margin_adjust_*): started on open, submitted
// once approved, then exactly one completed (venue accepted) or failed,
// or abandoned when closed without submitting. Each carries `source`
// (where the sheet was opened from: [HlMarginSource]) and `action` (the
// mode at that moment). Exact amount_usd; no ids, addresses or balances.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit/deposit_quick_amounts.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// Where the margin sheet was opened from (the `source` analytics
/// property).
abstract final class HlMarginSource {
  /// "Add margin" beside the Liquidation row of the position screen.
  static const liquidationRow = 'liquidation_row';

  /// The liquidation-risk alert banner.
  static const alertBanner = 'alert_banner';
}

class HlAdjustMarginSheet extends ConsumerStatefulWidget {
  const HlAdjustMarginSheet({
    super.key,
    required this.position,
    required this.market,
    required this.add,
    required this.source,
  });

  final HlPerpPosition position;
  final HlMarket market;

  /// The mode the sheet opens in: true adds margin, false removes it. The
  /// pill pair at the top switches it.
  final bool add;

  /// Where it was opened from ([HlMarginSource]).
  final String source;

  static const routeName = 'hyperliquid-adjust-margin-sheet';

  /// Same route options as the close-position ticket.
  static Future<void> show(
    BuildContext context, {
    required HlPerpPosition position,
    required HlMarket market,
    required bool add,
    required String source,
  }) {
    // One margin ticket at a time.
    return OpenOnce.run(routeName, () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      // Drag-to-dismiss bypasses PopScope, so it is off (tap outside still
      // dismisses, and is held while the change is in flight).
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      routeSettings: const RouteSettings(name: routeName),
      builder: (_) =>
          HlAdjustMarginSheet(
              position: position, market: market, add: add, source: source),
    ));
  }

  /// What can be taken out (see [hlRemovableMargin]).
  static double removableMargin(HlPerpPosition p) => hlRemovableMargin(p);

  /// The liquidation price after moving [delta] USD of margin (see
  /// [hlLiquidationAfter]).
  static double? liquidationAfter(HlPerpPosition p, double delta) =>
      hlLiquidationAfter(p, delta);

  @override
  ConsumerState<HlAdjustMarginSheet> createState() =>
      _HlAdjustMarginSheetState();
}

class _HlAdjustMarginSheetState extends ConsumerState<HlAdjustMarginSheet> {
  /// The typed amount in dollars, as the keypad writes it.
  String _amountText = '';
  bool _busy = false;

  /// Synchronous re-entrancy guard: [_busy] only flips inside setState.
  bool _inFlight = false;
  bool _submitted = false;
  String? _errorText;
  Object? _errorCause;

  HlMarket get _market => widget.market;

  /// The mode: true adds margin, false removes it. A market that locks
  /// isolated margin (strictIsolated) only takes margin in.
  late bool _add = widget.add || widget.market.isolatedMarginLocked;
  Color get _side => sideTintForMoneyIn(_add);

  /// The position as the account reads it now (the snapshot it was
  /// opened on until the first refresh lands).
  HlPerpPosition _live(WidgetRef ref) =>
      ref
          .watch(hyperliquidPerpPositionsProvider)
          .where((p) => p.coin == widget.position.coin)
          .firstOrNull ??
      widget.position;

  Map<String, Object> _params([double? amount]) => {
        'venue': 'hyperliquid',
        'action': _add ? 'add' : 'remove',
        'source': widget.source,
        'coin': _market.coin,
        ...VenueAnalytics.hlAssetParams(_market.coin, kind: 'perp'),
        'leverage': widget.position.leverageValue,
        'wallet_kind': 'hot',
        if (amount != null) ...TrackingService.moneyParams(amountUsd: amount),
      };

  @override
  void initState() {
    super.initState();
    TrackingService.track('hyperliquid_margin_adjust_started',
        params: _params());
  }

  @override
  void dispose() {
    if (!_submitted) {
      try {
        TrackingService.track('hyperliquid_margin_adjust_abandoned',
            params: _params(_amount));
      } catch (_) {}
    }
    super.dispose();
  }

  double? get _amount {
    final v = double.tryParse(_amountText);
    return v == null || !v.isFinite || v <= 0 ? null : v;
  }

  /// The Investing balance (perp cash on every dex plus spot USDC).
  double _cash(HyperliquidTradingState? state) => state?.availableUsdc ?? 0;

  /// The most this change can move: the Investing balance when adding,
  /// what the venue lets come out when removing. Floored to a cent.
  double _limit(HyperliquidTradingState? state, HlPerpPosition pos) => _add
      ? (_cash(state) * 100).floorToDouble() / 100
      : hlRemovableMargin(pos);

  void _setAmount(String v) {
    if (v == _amountText) return;
    setState(() {
      _amountText = v;
      // A new figure is a new attempt.
      _errorText = null;
      _errorCause = null;
    });
  }

  /// Switches between adding and removing. The figure typed for one is
  /// not a figure for the other (Max differs), so it starts afresh.
  void _setMode(bool add) {
    if (_busy || _inFlight || add == _add) return;
    HapticFeedback.selectionClick();
    setState(() {
      _add = add;
      _amountText = '';
      _errorText = null;
      _errorCause = null;
    });
  }

  void _fillMax(double limit) {
    if (limit <= 0) return;
    HapticFeedback.selectionClick();
    _setAmount(limit.toStringAsFixed(2));
  }

  Future<void> _confirm(double limit, HlPerpPosition pos) async {
    final amount = _amount;
    if (_inFlight || _busy || amount == null || amount > limit + 1e-9) return;
    final l10n = context.l10n;
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) {
      setState(() {
        _errorCause = null;
        _errorText = l10n.depositActionWalletUnavailable;
      });
      return;
    }
    _inFlight = true;
    try {
      HapticFeedback.mediumImpact();
      final usd = _add ? amount : -amount;
      // The confirmation lives on the root navigator, past this sheet.
      final rootNav = Navigator.of(context, rootNavigator: true);
      final preview = _Figures.of(
        pos,
        cash: _cash(ref.read(hyperliquidTradingProvider).valueOrNull),
        liveMid: ref.read(hyperliquidLiveMidProvider(pos.coin)),
        delta: usd,
      );
      final grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: HlIntents.isolatedMargin(
          walletId: walletId,
          market: _market,
          positionIsLong: pos.isLong,
          usd: usd,
        ),
        reason: l10n.hlMarginStepUp(_market.coin),
        amountUsd: amount,
      );
      if (grant == null || !mounted) return;
      _submitted = true;
      TrackingService.track('hyperliquid_margin_adjust_submitted',
          params: _params(amount));
      setState(() {
        _busy = true;
        _errorText = null;
        _errorCause = null;
      });
      try {
        await ref
            .read(hyperliquidTradingProvider.notifier)
            .adjustIsolatedMargin(
              market: _market,
              position: pos,
              usd: usd,
              grant: grant,
            );
      } catch (e) {
        TrackingService.track('hyperliquid_margin_adjust_failed', params: {
          ..._params(amount),
          'error_category': e is AuthGrantException
              ? 'approval_expired'
              : TrackingService.errorCategory(e),
        });
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errorCause = e;
          // A StateError stopped before anything was signed (the position
          // changed, or the market allows no removal).
          _errorText = e is StateError
              ? l10n.ledgerErrorDetailsChanged
              : hlTradeErrorMessage(l10n, e);
        });
        return;
      }
      TrackingService.track('hyperliquid_margin_adjust_completed',
          params: _params(amount));
      if (!mounted) return;
      // Released first: the ticket holds itself while busy, and a held
      // ticket would refuse its own hand-off to the confirmation.
      setState(() => _busy = false);
      Navigator.of(context).pop();
      pushKuteSuccessOverlay(
        navigator: rootNav,
        overlay: KuteConfirmation(
          message: _add ? l10n.hlMarginAdded : l10n.hlMarginRemoved,
          showCloseButton: true,
          onDone: () => rootNav.pop(),
          detail: l10n.investingBalanceUpdating,
          receipt: TradeReceipt(
            leading: _artwork(),
            title: _market.coin,
            subtitle: pos.isLong ? l10n.longLabel : l10n.shortLabel,
            rows: {
              _add ? l10n.hlMarginAdd : l10n.hlMarginRemove:
                  formatHlUsd(amount),
              if (preview.moneyAfter != null)
                l10n.hlPositionMoney: '≈ ${formatHlUsd(preview.moneyAfter!)}',
              if (preview.liqAfter != null)
                l10n.chartLiquidationPrice:
                    '≈ ${formatHlPrice(preview.liqAfter!, decimalCap: _market.pxDecimalCap)}',
              l10n.moveInvestingBalance:
                  '≈ ${formatHlUsd(math.max(0, preview.cashAfter))}',
            },
          ),
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  Widget _artwork() => HlCoinIcon(
      coin: _market.coin,
      wireCoin: _market.wireCoin,
      iconUrl: _market.iconUrl,
      category: _market.category,
      size: 36);

  @override
  Widget build(BuildContext context) {
    final c = sideTintPalette(context.colors, _side);
    final l10n = context.l10n;
    final state = ref.watch(hyperliquidTradingProvider).valueOrNull;
    final pos = _live(ref);
    final liveMid = ref.watch(hyperliquidLiveMidProvider(pos.coin));
    final limit = _limit(state, pos);
    final amount = _amount;
    final over = amount != null && amount > limit + 1e-9;
    final canConfirm = !_busy && amount != null && !over && limit > 0;
    final failed = _errorText != null;
    final figures = _Figures.of(
      pos,
      cash: _cash(state),
      liveMid: liveMid,
      delta: (amount ?? 0) * (_add ? 1 : -1),
    );
    final price = _market.pxDecimalCap;

    String move(double from, double to, String Function(double) fmt) =>
        '${fmt(from)} → ${fmt(to)}';

    final sheet = Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: _side,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                  child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 14.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────────
                    Row(
                      children: [
                        _artwork(),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _add
                                    ? l10n.hlMarginAddTitle(_market.coin)
                                    : l10n.hlMarginRemoveTitle(_market.coin),
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3.h),
                              Row(
                                children: [
                                  HlSideChip(
                                    text: pos.isLong ? 'LONG' : 'SHORT',
                                    color: c.textPrimary,
                                  ),
                                  SizedBox(width: 6.w),
                                  HlMetaChip(text: '${pos.leverageValue}x'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.close_rounded,
                              color: c.textPrimary, size: 22.sp),
                        ),
                      ],
                    ),
                    // ── Mode ─────────────────────────────────────────
                    // Add / Remove, the app's pill pair. No Remove on a
                    // market that locks isolated margin.
                    if (!_market.isolatedMarginLocked) ...[
                      SizedBox(height: 14.h),
                      KutePillTabs(
                        key: const ValueKey('hl-margin-mode'),
                        horizontalPadding: 0,
                        items: [
                          KutePillItem(label: l10n.hlMarginModeAdd),
                          KutePillItem(label: l10n.hlMarginModeRemove),
                        ],
                        selectedIndex: _add ? 0 : 1,
                        onTap: (i) => _setMode(i == 0),
                      ),
                    ],
                    SizedBox(height: 18.h),

                    // ── Amount ───────────────────────────────────────
                    // Typed on the pinned keypad; the line under it is
                    // the most this change can move (tap fills it).
                    BigAmountDisplay(
                      prefix: r'$',
                      amountText: _amountText,
                      availableLabel: _add
                          ? l10n.hlMarginCanAdd(formatHlUsd(limit))
                          : l10n.hlMarginCanRemove(formatHlUsd(limit)),
                      availableExceeded: over,
                      onAvailableTap: _busy ? null : () => _fillMax(limit),
                    ),
                    SizedBox(height: 14.h),
                    AmountQuickChips(
                      enabled: !_busy && limit > 0,
                      chips: moveQuickAmountChips(
                        amountIsUsd: true,
                        maxLabel: l10n.max,
                        exceedsAvailable: (usd) => usd > limit + 1e-9,
                        onDollars: (usd) {
                          HapticFeedback.selectionClick();
                          _setAmount(moveQuickAmountTyped(usd));
                        },
                        onPercent: (_, {chip}) => _fillMax(limit),
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // ── What it does ─────────────────────────────────
                    PolySlipSection(children: [
                      Text(
                        amount == null
                            ? (_add
                                ? l10n.hlMarginAddExplain
                                : l10n.hlMarginRemoveExplain)
                            : [
                                _add
                                    ? l10n.hlMarginAddSummary(
                                        formatHlUsd(amount))
                                    : l10n.hlMarginRemoveSummary(
                                        formatHlUsd(amount)),
                                if (figures.liqBefore != null &&
                                    figures.liqAfter != null)
                                  l10n.hlMarginLiqMoves(
                                      formatHlPrice(figures.liqBefore!,
                                          decimalCap: price),
                                      formatHlPrice(figures.liqAfter!,
                                          decimalCap: price)),
                                l10n.hlMarginCashMoves(
                                    formatHlUsd(figures.cashBefore),
                                    formatHlUsd(
                                        math.max(0, figures.cashAfter))),
                              ].join(' '),
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            height: 1.4),
                      ),
                      if (amount != null) ...[
                        if (figures.moneyBefore != null &&
                            figures.moneyAfter != null) ...[
                          SizedBox(height: 12.h),
                          PolySlipDetailRow(
                              label: l10n.hlPositionMoney,
                              value: move(figures.moneyBefore!,
                                  figures.moneyAfter!, formatHlUsd)),
                        ],
                        if (figures.liqBefore != null &&
                            figures.liqAfter != null) ...[
                          SizedBox(height: 8.h),
                          PolySlipDetailRow(
                              label: l10n.chartLiquidationPrice,
                              value: move(
                                  figures.liqBefore!,
                                  figures.liqAfter!,
                                  (v) => formatHlPrice(v,
                                      decimalCap: price))),
                        ],
                        SizedBox(height: 8.h),
                        PolySlipDetailRow(
                            label: l10n.moveInvestingBalance,
                            value: move(figures.cashBefore,
                                math.max(0, figures.cashAfter), formatHlUsd)),
                        if (figures.leverageAfter != null) ...[
                          SizedBox(height: 8.h),
                          PolySlipDetailRow(
                              label: l10n.hlMarginLeverageAfter,
                              value:
                                  '${figures.leverageAfter!.toStringAsFixed(1)}x'),
                        ],
                      ],
                    ]),
                    if (over) ...[
                      SizedBox(height: 10.h),
                      Text(l10n.hlMarginTooMuch,
                          style: TextStyle(color: c.error, fontSize: 13.sp)),
                    ],
                    if (_errorText != null) ...[
                      SizedBox(height: 10.h),
                      HlTradeErrorNotice(
                          message: _errorText!, error: _errorCause),
                    ],
                  ],
                ),
              )),

              // ── Keypad, pinned ─────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: AmountKeypad(
                  value: _amountText,
                  maxDecimals: 2,
                  enabled: !_busy,
                  onChanged: _setAmount,
                ),
              ),

              // ── CTA, pinned ────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w,
                    math.max(16.h, MediaQuery.of(context).padding.bottom)),
                child: PolySlipCta(
                  label: failed
                      ? l10n.retry
                      : (_add ? l10n.hlMarginAdd : l10n.hlMarginRemove),
                  onTap: () => _confirm(limit, pos),
                  enabled: canConfirm,
                  isBusy: _busy,
                  busyLabel: l10n.loading,
                  color: _side,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // An in-flight change cannot be dismissed out from under itself.
    return PopScope(
        canPop: !_busy,
        child: SideTintedSubtree(side: _side, child: sheet));
  }
}

/// The figures a margin change moves, before and after moving [delta]
/// dollars (positive = added). Estimates of what the venue will report:
/// the receipt and the summary mark them as such.
class _Figures {
  const _Figures({
    required this.moneyBefore,
    required this.moneyAfter,
    required this.liqBefore,
    required this.liqAfter,
    required this.cashBefore,
    required this.cashAfter,
    required this.leverageAfter,
  });

  final double? moneyBefore, moneyAfter, liqBefore, liqAfter, leverageAfter;
  final double cashBefore, cashAfter;

  factory _Figures.of(HlPerpPosition p,
      {required double cash, required double? liveMid, required double delta}) {
    final money = hlPositionMoney(p, liveMid: liveMid);
    final liq = p.liquidationPx;
    final marginAfter = p.marginUsed + delta;
    return _Figures(
      moneyBefore: money,
      moneyAfter: money == null ? null : money + delta,
      liqBefore: liq != null && liq.isFinite && liq > 0 ? liq : null,
      liqAfter: hlLiquidationAfter(p, delta),
      cashBefore: cash,
      cashAfter: cash - delta,
      leverageAfter:
          marginAfter > 0 ? p.positionValue.abs() / marginAfter : null,
    );
  }
}
