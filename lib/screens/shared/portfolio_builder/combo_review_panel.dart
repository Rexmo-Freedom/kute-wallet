// lib/screens/shared/portfolio_builder/combo_review_panel.dart
//
// The "Combine into one bet" review of the portfolio Builder: one stake
// over 2+ prediction legs, priced by a Polymarket combo RFQ. Shows the
// payout, multiplier and fees, counts down the quote's acceptance window
// (a few seconds, the gateway's `expires_at`), re-quotes on its own when
// it lapses, and places the combo after ONE step-up approval.
//
// Hot wallet only. The Builder hides this for Ledger: a hardware review
// cannot fit in the quote window, so Ledger places the legs separately.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/home/home_feature_carousel.dart'
    show checkPolymarketGeoblock;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/polymarket/components/combo_copy.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/services/polymarket/combos/combo_analytics.dart';
import 'package:kute/services/polymarket/combos/combo_ids.dart';
import 'package:kute/services/polymarket/combos/combo_math.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_service.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/theme/app_theme.dart';

/// How many lapsed quotes are replaced on their own before the panel waits
/// for a tap (the gateway allows 15 quote requests a minute).
const int kComboAutoRequotes = 5;

/// True when [legs] can be one combo: 2 to 50 legs, every one enabled on
/// Gamma with its side's position id, and a valid leg set.
bool comboEligible(List<PredictionBuilderLeg> legs) {
  if (legs.length < ComboIds.minLegs || legs.length > ComboIds.maxLegs) {
    return false;
  }
  if (!legs.every((l) => l.comboEnabled)) return false;
  try {
    ComboIds.canonicalLegs([for (final l in legs) l.comboPositionId!]);
    return true;
  } on ComboLegsException {
    return false;
  }
}

enum _Phase { quoting, quoted, noQuote, error, placing, placed, pending }

class ComboReviewPanel extends ConsumerStatefulWidget {
  const ComboReviewPanel({
    super.key,
    required this.legs,
    required this.stakeUsd,
    required this.availableUsd,
    required this.onEditStake,
    required this.onDeposit,
    required this.onPlaced,
    this.onBusy,
  });

  final List<PredictionBuilderLeg> legs;
  final double stakeUsd;
  final double? availableUsd;
  final VoidCallback onEditStake;
  final VoidCallback? onDeposit;

  /// The combo filled (or is settling): the Builder clears its draft.
  final VoidCallback onPlaced;

  /// The panel is signing/placing: the Builder blocks back navigation.
  final ValueChanged<bool>? onBusy;

  @override
  ConsumerState<ComboReviewPanel> createState() => _ComboReviewPanelState();
}

class _ComboReviewPanelState extends ConsumerState<ComboReviewPanel> {
  _Phase _phase = _Phase.quoting;
  ComboQuote? _quote;
  String? _message;
  Timer? _ticker;
  int _autoRequotes = 0;
  int _requestSeq = 0;
  ComboQuote? _placedQuote;

  List<String> get _legIds =>
      ComboIds.canonicalLegs([for (final l in widget.legs) l.comboPositionId!]);

  bool get _insufficient =>
      widget.availableUsd != null &&
      widget.stakeUsd > widget.availableUsd! + 1e-6;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestQuote());
  }

  @override
  void didUpdateWidget(covariant ComboReviewPanel old) {
    super.didUpdateWidget(old);
    final legsChanged = old.legs.length != widget.legs.length ||
        [for (var i = 0; i < old.legs.length; i++) i].any((i) =>
            old.legs[i].comboPositionId != widget.legs[i].comboPositionId);
    if ((legsChanged || old.stakeUsd != widget.stakeUsd) &&
        _phase != _Phase.placing &&
        _phase != _Phase.placed &&
        _phase != _Phase.pending) {
      _autoRequotes = 0;
      _requestQuote();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final q = _quote;
    if (_phase != _Phase.quoted || q == null) return;
    if (q.remaining(DateTime.now()) > Duration.zero) {
      setState(() {});
      return;
    }
    final willRequote = _autoRequotes < kComboAutoRequotes && !_insufficient;
    ComboAnalytics.quoteExpired(
        direction: 'buy', legs: widget.legs.length, willRequote: willRequote);
    if (willRequote) {
      _autoRequotes++;
      _requestQuote(auto: true);
    } else {
      setState(() {
        _quote = null;
        _phase = _Phase.error;
        _message = null;
      });
    }
  }

  Future<void> _requestQuote({bool auto = false}) async {
    if (!mounted || widget.stakeUsd <= 0) return;
    final seq = ++_requestSeq;
    setState(() {
      _phase = _Phase.quoting;
      _message = null;
    });
    final legs = widget.legs.length;
    ComboAnalytics.quoteRequested(
      direction: 'buy',
      legs: legs,
      sizeUsd: widget.stakeUsd,
      auto: auto,
      entrySource: 'portfolio_builder',
    );
    final clock = Stopwatch()..start();
    try {
      final quote = await ref.read(polymarketCombosProvider.notifier).quoteBuy(
            legPositionIds: _legIds,
            budgetE6: usdToE6Floor(widget.stakeUsd),
          );
      if (!mounted || seq != _requestSeq) return;
      ComboAnalytics.quoted(
        direction: 'buy',
        legs: legs,
        result: 'quoted',
        stakeUsd: quote.stakeUsd,
        payoutUsd: quote.payoutUsd,
        multiplier: quote.multiplier,
        feeUsd: quote.feesUsd,
        windowMs: quote.remaining(DateTime.now()).inMilliseconds,
        latencyMs: clock.elapsedMilliseconds,
        entrySource: 'portfolio_builder',
      );
      setState(() {
        _quote = quote;
        _phase = _Phase.quoted;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      ComboAnalytics.quoted(
        direction: 'buy',
        legs: legs,
        result: switch (e) {
          ComboNoQuoteException() => 'no_quote',
          ComboRfqException(:final isRateLimited) when isRateLimited =>
            'rate_limited',
          _ => 'error',
        },
        latencyMs: clock.elapsedMilliseconds,
        reasonCode: switch (e) {
          ComboNoQuoteException(:final code) => code,
          ComboRfqException(:final code) => code,
          _ => null,
        },
        entrySource: 'portfolio_builder',
      );
      setState(() {
        _quote = null;
        _phase = e is ComboNoQuoteException ? _Phase.noQuote : _Phase.error;
        _message = comboErrorCopy(context, e);
      });
    }
  }

  List<String> _capabilities() => {
        for (final l in widget.legs)
          ...polymarketBetCapabilitiesFor([l.tokenId, l.conditionId, l.slug]),
      }.toList();

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null || _phase != _Phase.quoted) return;
    HapticFeedback.mediumImpact();
    final caps = _capabilities();
    if (await checkPolymarketGeoblock(context,
        capabilities: caps, maxAge: const Duration(seconds: 60))) {
      return;
    }
    if (!mounted) return;
    final walletId =
        ref.read(polymarketTradingProvider.notifier).signingWalletId;
    if (walletId == null || walletId.isEmpty) return;
    // The review binds the budget the user set and the payout shown, with
    // 1% room for the re-quote a few seconds later may need.
    final intent = PmGrants.comboBet(
      walletId: walletId,
      legPositionIds: quote.legPositionIds,
      maxStakeE6: quote.requestedE6,
      minPayoutE6: quote.payoutE6 * BigInt.from(99) ~/ BigInt.from(100),
    );
    widget.onBusy?.call(true);
    setState(() => _phase = _Phase.placing);
    try {
      final grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: intent,
        reason: context.l10n.stepUpReasonCombo(widget.legs.length),
        amountUsd: e6ToDouble(quote.requestedE6),
      );
      if (!mounted) return;
      if (grant == null) {
        _autoRequotes = 0;
        await _requestQuote();
        return;
      }
      final result = await ref.read(polymarketCombosProvider.notifier).place(
            shown: quote,
            grant: grant,
            capabilities: caps,
            entrySource: 'portfolio_builder',
          );
      if (!mounted) return;
      switch (result.state) {
        case ComboFillState.filled:
          HapticFeedback.heavyImpact();
          setState(() {
            _placedQuote = result.quote;
            _phase = _Phase.placed;
          });
          widget.onPlaced();
        case ComboFillState.pending:
          setState(() {
            _placedQuote = result.quote;
            _phase = _Phase.pending;
          });
          widget.onPlaced();
        case ComboFillState.failed:
          _autoRequotes = 0;
          setState(() {
            _quote = null;
            _phase = _Phase.error;
            _message = context.l10n.comboDeclined;
          });
      }
    } catch (e) {
      if (!mounted) return;
      if (await handleGrantFailure(context, e,
          action: SensitiveAction.pmBet)) {
        if (mounted) await _requestQuote();
        return;
      }
      if (!mounted) return;
      if (e is ComboQuoteChanged) {
        setState(() {
          _quote = e.quote;
          _phase = _Phase.quoted;
          _message = context.l10n.comboPriceChanged;
        });
        return;
      }
      setState(() {
        _quote = null;
        _phase = e is ComboNoQuoteException ? _Phase.noQuote : _Phase.error;
        _message = comboErrorCopy(context, e);
      });
    } finally {
      widget.onBusy?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final q = _quote;
    final done = _phase == _Phase.placed || _phase == _Phase.pending;
    final placed = _placedQuote;

    Widget row(String label, String value,
        {Color? color, bool strong = false, VoidCallback? onTap}) {
      final child = Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600)),
            Row(children: [
              Text(value,
                  style: TextStyle(
                    color: color ?? c.textPrimary,
                    fontSize: strong ? 17.sp : 15.sp,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              if (onTap != null) ...[
                SizedBox(width: 6.w),
                Icon(Icons.edit_outlined, size: 16.sp, color: c.textSecondary),
              ],
            ]),
          ],
        ),
      );
      return onTap == null
          ? child
          : InkWell(onTap: onTap, borderRadius: AppRadius.buttonBorder, child: child);
    }

    final busy = _phase == _Phase.placing;
    final seconds = q == null
        ? 0
        : (q.remaining(DateTime.now()).inMilliseconds / 1000).ceil();

    if (done && placed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
                _phase == _Phase.placed
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_top_rounded,
                color: _phase == _Phase.placed
                    ? AppColors.success
                    : c.textSecondary,
                size: 22.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                _phase == _Phase.placed ? l10n.comboPlaced : l10n.comboSettling,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          SizedBox(height: 6.h),
          Text(l10n.comboPlacedBody(formatHlUsd(placed.payoutUsd)),
              style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
          SizedBox(height: 16.h),
          AppButton(
            text: l10n.done,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(l10n.comboStake, formatHlUsd(widget.stakeUsd),
            strong: true, onTap: busy ? null : widget.onEditStake),
        row(
          l10n.comboPaysIfAllWin,
          q == null ? '-' : formatHlUsd(q.payoutUsd),
          color: q == null ? c.textTertiary : AppColors.success,
          strong: true,
        ),
        row(l10n.comboMultiplier,
            q == null ? '-' : comboMultiplierText(q.multiplier)),
        // The quote's fees: one caption line, as fees read elsewhere.
        if (q != null) ...[
          SizedBox(height: 2.h),
          Text(
            '${l10n.fees} · ${formatHlUsd(q.feesUsd)}',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              height: 1.35,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        SizedBox(height: 6.h),
        Text(
          switch (_phase) {
            _Phase.quoting => _quote == null && _autoRequotes > 0
                ? l10n.comboRefreshingPrice
                : l10n.comboGettingPrice,
            _Phase.quoted => _message ?? l10n.comboPriceValidFor(seconds),
            _Phase.noQuote || _Phase.error =>
              _message ?? l10n.comboPriceFailed,
            _ => '',
          },
          style: TextStyle(
            color: (_phase == _Phase.noQuote || _phase == _Phase.error)
                ? AppColors.error
                : c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_insufficient) ...[
          SizedBox(height: 6.h),
          Text(
            l10n.builderAddToContinue(
                formatHlUsd(widget.stakeUsd - (widget.availableUsd ?? 0))),
            style: TextStyle(color: AppColors.error, fontSize: 13.sp),
          ),
        ],
        SizedBox(height: 14.h),
        if (_insufficient)
          AppButton(
            text: l10n.deposit,
            onPressed: widget.onDeposit,
          )
        else if (_phase == _Phase.noQuote || _phase == _Phase.error)
          AppButton(
            text: l10n.comboGetNewPrice,
            onPressed: () {
              _autoRequotes = 0;
              _requestQuote();
            },
          )
        else
          AppButton(
            text: l10n.comboPlace,
            variant: AppButtonVariant.moneyIn,
            isLoading: busy || _phase == _Phase.quoting,
            onPressed: _phase == _Phase.quoted && q != null ? _confirm : null,
          ),
      ],
    );
  }
}
