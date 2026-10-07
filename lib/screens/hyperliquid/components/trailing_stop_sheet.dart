import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'hl_coin_icon.dart';
import 'hl_error_copy.dart';
import 'hl_order_controls.dart';

/// One native trailing ticket for both signers. Size/side/account are captured
/// from the parent ticket; editing the trail cannot change its funding wallet.
class HlTrailingStopSheet extends ConsumerStatefulWidget {
  const HlTrailingStopSheet(
      {super.key,
      required this.market,
      required this.size,
      required this.isBuy,
      required this.reduceOnly,
      required this.leverage,
      required this.isCross,
      required this.walletId,
      required this.ledger,
      this.embedded = false,
      this.onResult});
  final HlMarket market;
  final double size;
  final bool isBuy, reduceOnly, isCross, ledger;
  final int leverage;
  final String walletId;

  /// Rendered inline (inside the ticket's More options card) rather than
  /// as its own page: no chrome, and a placed order is reported through
  /// [onResult] instead of popping a route.
  final bool embedded;
  final ValueChanged<HlOrderResult>? onResult;

  static Future<HlOrderResult?> show(BuildContext context,
      {required HlMarket market,
      required double size,
      required bool isBuy,
      required bool reduceOnly,
      required int leverage,
      required bool isCross,
      required String walletId,
      required bool ledger}) {
    if (market.isSpot || size <= 0 || !size.isFinite) return Future.value(null);
    final normalizedSize = flooredSize(size, market.szDecimals);
    if (normalizedSize <= 0) return Future.value(null);
    // A full page with the Advanced ticket's chrome, not a bottom sheet:
    // it is one of the Advanced order doors and reads like the rest.
    return Navigator.of(context, rootNavigator: true).push<HlOrderResult>(
        MaterialPageRoute<HlOrderResult>(
            fullscreenDialog: true,
            settings: const RouteSettings(name: 'hyperliquid-trailing-stop'),
            builder: (_) => HlTrailingStopSheet(
                market: market,
                size: normalizedSize,
                isBuy: isBuy,
                reduceOnly: reduceOnly,
                leverage: leverage,
                isCross: isCross,
                walletId: walletId,
                ledger: ledger)));
  }

  @override
  ConsumerState<HlTrailingStopSheet> createState() => _TrailingStopState();
}

class _TrailingStopState extends ConsumerState<HlTrailingStopSheet> {
  final _distance = TextEditingController(text: '1');
  final _activation = TextEditingController();
  bool _percent = true, _activate = false, _busy = false, _pending = false;
  String? _error;
  @override
  void dispose() {
    _distance.dispose();
    _activation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _pending) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final distance = double.tryParse(_distance.text.replaceAll(',', '.'));
      final activation = double.tryParse(_activation.text.replaceAll(',', '.'));
      if (distance == null || (_activate && activation == null)) {
        throw ArgumentError('Enter a trailing distance and activation price.');
      }
      final trail = HlTrailingStop(
          retracement: distance,
          percent: _percent,
          activationPrice: _activate ? activation : null);
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('trading.advanced');
      await RuntimeCapabilitiesService.instance.ensureAllowed(
          widget.reduceOnly ? 'hyperliquid.close' : 'hyperliquid.trade');
      final price = await ledgerHlReferencePx(widget.market);
      trail.validate(
          market: widget.market, isBuy: widget.isBuy, referencePrice: price);
      if (!mounted) return;
      HlOrderResult? result;
      if (widget.ledger) {
        result = await runLedgerHlTrailingStop(context, ref,
            walletId: widget.walletId,
            market: widget.market,
            isBuy: widget.isBuy,
            size: widget.size,
            trail: trail,
            reduceOnly: widget.reduceOnly,
            leverage: widget.leverage,
            isCross: widget.isCross, onPending: () {
          if (mounted) {
            setState(() {
              _pending = true;
              _error = const PendingTrailingStopException().toString();
            });
          }
        });
      } else {
        if (pickSpendingWallet(ref.read(settingsProvider))?.id !=
            widget.walletId) {
          throw StateError('Wallet changed. Review this order again.');
        }
        final intent = HlIntents.trailingStop(
            walletId: widget.walletId,
            market: widget.market,
            isLong: widget.isBuy,
            size: widget.size,
            trail: trail,
            leverage: widget.leverage,
            isCross: widget.isCross,
            reduceOnly: widget.reduceOnly);
        final grant = await requireFreshAuthGrant(context, ref,
            intent: intent,
            reason: context.l10n.stepUpReasonOrder(widget.market.coin),
            amountUsd: widget.size * price / widget.leverage);
        if (grant == null || !mounted) return;
        result = await ref
            .read(hyperliquidTradingProvider.notifier)
            .placeTrailingStop(
                market: widget.market,
                isLong: widget.isBuy,
                size: widget.size,
                trail: trail,
                leverage: widget.leverage,
                isCross: widget.isCross,
                reduceOnly: widget.reduceOnly,
                grant: grant);
      }
      if (widget.ledger && result != null) {
        // The hot path reports from the trading notifier; a Ledger order
        // never touches it, so its placement is reported here.
        final lev = widget.market.isSpot
            ? 1
            : widget.leverage.clamp(1, widget.market.maxLeverage).toInt();
        final notional = widget.size * price;
        TrackingService.hyperliquidOrderPlaced(
          coin: widget.market.coin,
          kind: widget.market.isSpot ? 'spot' : 'perp',
          isBuy: widget.isBuy,
          leverage: lev,
          marginUsd: notional / lev,
          notionalUsd: notional,
          orderType: 'trailing',
          reduceOnly: widget.reduceOnly,
          filled: result.isFilled,
          walletKind: 'ledger',
          marketType: widget.market.isSpot
              ? 'spot'
              : (widget.market.dex.isEmpty ? 'perp' : widget.market.dex),
          builderFeeApplied: false,
        );
      }
      if (mounted && result != null) {
        setState(() => _busy = false);
        if (widget.embedded) {
          widget.onResult?.call(result);
        } else {
          Navigator.of(context).pop(result);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pending = e is PendingTrailingStopException;
          _error = e is ArgumentError
              ? e.message.toString()
              : e is PendingTrailingStopException
                  ? e.toString()
                  : hlTradeErrorMessage(context.l10n, e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label) {
    final c = context.colors;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.borderSubtle, width: .5));
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
            controller: controller,
            enabled: !_busy && !_pending,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
                labelText: label,
                filled: true,
                fillColor: c.surfaceLight,
                border: border,
                enabledBorder: border,
                focusedBorder: border,
                contentPadding: const EdgeInsets.all(16))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final form = <Widget>[
      Row(children: [
        HlCoinIcon(
            coin: HlMarket.baseCoin(widget.market.coin),
            wireCoin: widget.market.wireCoin,
            iconUrl: widget.market.iconUrl,
            category: widget.market.category),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                '${widget.reduceOnly ? context.l10n.trailingClose : widget.isBuy ? context.l10n.longLabel : context.l10n.shortLabel} '
                '${roundSize(widget.size, widget.market.szDecimals)} ${HlMarket.baseCoin(widget.market.coin)}',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)))
      ]),
      const SizedBox(height: 8),
      Text(
          widget.reduceOnly
              ? context.l10n.slipReduceOnly
              : '${widget.leverage}x · ${widget.isCross && !widget.market.onlyIsolated ? context.l10n.slipCross : context.l10n.slipIsolated}',
          style: TextStyle(color: c.textSecondary)),
      const SizedBox(height: 20),
      Text(
          widget.isBuy
              ? context.l10n.trailingFollowsLowBuys
              : context.l10n.trailingFollowsHighSells,
          style: TextStyle(color: c.textSecondary)),
      const SizedBox(height: 16),
      HlAdvancedSection(title: context.l10n.trailingDistance, children: [
        AbsorbPointer(
            absorbing: _busy || _pending,
            child: HlSegmentTrack(segments: [
              HlTrackSegment(
                  label: context.l10n.slipPercent,
                  selected: _percent,
                  onTap: () => setState(() => _percent = true)),
              HlTrackSegment(
                  label: context.l10n.price2,
                  selected: !_percent,
                  onTap: () => setState(() => _percent = false))
            ])),
        _field(
            _distance,
            _percent
                ? context.l10n.slipDistancePercent
                : context.l10n.trailingDistanceUsd),
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.slipActivationPrice),
            value: _activate,
            onChanged: _busy || _pending
                ? null
                : (v) => setState(() => _activate = v)),
        if (_activate)
          _field(_activation, context.l10n.trailingActivationPriceUsd),
      ]),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_error!, style: TextStyle(color: c.textPrimary))),
    ];
    final cta = PolySlipCta(
        color: widget.reduceOnly || !widget.isBuy
            ? AppColors.marketDown
            : AppColors.marketUp,
        isBusy: _busy,
        enabled: !_busy && !_pending,
        onTap: _submit,
        label: context.l10n.trailingPlace,
        busyLabel: context.l10n.loading);
    if (widget.embedded) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [...form, const SizedBox(height: 12), cta]);
    }
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              backgroundColor: c.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              leading: KuteBackButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                '${HlMarket.baseCoin(widget.market.coin)} · ${context.l10n.investingTrailingStop}',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600),
              ),
            ),
            body: KeyboardDismissOnTap(
                child: SafeArea(
                    top: false,
                    child: Column(children: [
                      Expanded(
                          child: SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 16, 20, 20),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: form))),
                      Padding(padding: const EdgeInsets.all(20), child: cta),
                    ])))));
  }
}
