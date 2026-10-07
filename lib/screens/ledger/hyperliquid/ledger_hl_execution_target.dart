import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
// lib/screens/ledger/hyperliquid/ledger_hl_execution_target.dart
//
// The Ledger execution target for Hyperliquid (Wallet hardening Phase 4a,
// P4.7, O11) and the flows behind it.
//
// * Every action is a reviewed intent executed by LedgerHyperliquidExecutor
//   with the Ledger signer from the approval sheet. No onboarding, no agent
//   key, no phone signer, no automatic retry.
// * Orders, cancels and leverage are opaque on the device (a code) and
//   stay behind `kLedgerHyperliquidOpaqueActionsEnabled` (O1); the executor
//   refuses them before any prompt while the flag is off.
// * Before the first Ledger order the builder fee is approved once, as its
//   own readable prompt (O17).
// * A perps order whose leverage differs from the account setting needs a
//   separate leverage approval first; the order summary says so.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_execution_target.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_builder_fee_sheet.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart';

class LedgerHlExecutionTarget implements HlExecutionTarget {
  const LedgerHlExecutionTarget({required this.walletId, required this.ref});

  final String walletId;
  final WidgetRef ref;

  @override
  bool get isLedger => true;

  @override
  Future<HlOrderResult?> placeMarketOrder(
    BuildContext context, {
    required HlMarket market,
    required bool isBuy,
    required double marginUsd,
    int leverage = 1,
    double slippagePct = 1.0,
    String? source,
  }) =>
      runLedgerHlMarketOrder(
        context,
        ref,
        walletId: walletId,
        market: market,
        isBuy: isBuy,
        marginUsd: marginUsd,
        leverage: leverage,
        slippagePct: slippagePct,
      );

  @override
  Future<bool> cancelOrder(
    BuildContext context, {
    required HlOpenOrder order,
    int? assetId,
  }) =>
      runLedgerHlCancel(context, ref,
          walletId: walletId, order: order, assetId: assetId);
}

// ─────────────────────────────── helpers ───────────────────────────────

String ledgerNewCloid([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

Future<Object?> _hlInfo(Map<String, Object?> body) async {
  final resp = await http
      .post(
        HyperliquidConstants.infoUri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 10));
  if (resp.statusCode != 200) {
    throw http.ClientException('info ${body['type']} failed');
  }
  return jsonDecode(resp.body);
}

/// Whether [user] has approved the builder an order is about to carry.
///
/// Pass the [builder] the order will be tagged with, so the check, the
/// approval and the order all name one address; when omitted, the
/// backend's current builder is read. True when there is no builder (none
/// published or the backend unreachable: the order goes out without one).
/// Null when the approved fee could not be read. A rotated builder has no
/// approval yet, so it reads false and the device is asked again.
Future<bool?> ledgerHlBuilderFeeApproved(String user,
    {HlBuilderInfo? builder}) async {
  try {
    final config = builder ?? await HyperliquidFundingService.getBuilder();
    if (config == null) return true;
    final value = await _hlInfo({
      'type': 'maxBuilderFee',
      'user': user,
      'builder': config.builderAddress.toLowerCase(),
    });
    final fee = value is num ? value.toInt() : int.tryParse('$value');
    if (fee == null) return null;
    return fee >= config.defaultFeeTenthsBp;
  } catch (_) {
    return null;
  }
}

/// Live mid for [market], falling back to the market snapshot.
Future<double> ledgerHlReferencePx(HlMarket market) async {
  try {
    final mids = await _hlInfo({'type': 'allMids'});
    if (mids is Map) {
      final raw = mids[market.wireCoin] ?? mids[market.coin];
      final px = double.tryParse('$raw');
      if (px != null && px > 0) return px;
    }
  } catch (_) {}
  final px = market.midPx > 0 ? market.midPx : market.markPx;
  if (px <= 0) throw StateError('No reference price for ${market.coin}');
  return px;
}

HlPerpPosition? _positionFor(LedgerHlAccount? account, String coin) {
  if (account == null) return null;
  final snapshots = [
    if (account.account != null) account.account!,
    ...account.dexAccounts.values,
  ];
  for (final snapshot in snapshots) {
    for (final p in snapshot.positions) {
      if (p.coin == coin) return p;
    }
  }
  return null;
}

String? _paired(WidgetRef ref, String walletId) {
  final identity = ref.read(ledgerIdentityProvider(walletId));
  return identity != null && identity.hasVerifiedEvm
      ? identity.evmAddress
      : null;
}

LedgerReconcile ledgerHlReconcile(WidgetRef ref, String walletId) {
  final factory = ref.read(ledgerHlExecutorFactoryProvider);
  return (recordId) async {
    final paired = _paired(ref, walletId);
    if (paired == null) return null;
    final outcome = await factory(
      walletId: walletId,
      pairedAddress: paired,
      signer: ledgerReadOnlySigner(paired),
    ).reconcile(recordId);
    return outcome == LedgerReconcileOutcome.confirmed ? true : null;
  };
}

// ──────────────────────────────── flows ────────────────────────────────

/// Builder fee (once), leverage (when it differs), then the order. Each is
/// its own reviewed approval. Returns the order result, or null when any
/// step was cancelled, failed or is still pending.
Future<HlOrderResult?> runLedgerHlMarketOrder(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required HlMarket market,
  required bool isBuy,
  required double marginUsd,
  int leverage = 1,
  double slippagePct = 1.0,
  VoidCallback? onPending,
}) async {
  if (!await ensureRouteNotPaused(
          context, PausableRoute.ledgerInvestingActions) ||
      !context.mounted) {
    return null;
  }
  final l10n = context.l10n;
  // The same gates the spending wallet checks in openPosition: opening
  // investments plus, on a stock-linked perp, the stock-perp gate. A buy
  // is new exposure; a spot sell is an exit and answers to closing.
  await RuntimeCapabilitiesService.instance.ensureAllAllowed(
      market.isSpot && !isBuy
          ? const ['hyperliquid.close']
          : hlOpenCapabilities(market));
  final paired = _paired(ref, walletId);
  if (paired == null) return null;
  final factory = ref.read(ledgerHlExecutorFactoryProvider);

  // 1) Builder fee, one readable prompt on the device itself (O17). The
  // builder is read once and the same one is approved and put on the
  // order; none published means no approval and no builder field.
  final builder = await HyperliquidFundingService.getBuilder();
  if (!context.mounted) return null;
  if (builder != null) {
    final approved = await ledgerHlBuilderFeeApproved(paired, builder: builder);
    if (!context.mounted) return null;
    if (approved != true) {
      final ok = await approveLedgerHlBuilderFee(context, ref,
          walletId: walletId, builder: builder);
      if (!ok || !context.mounted) return null;
    }
  }

  // 2) Leverage for perps, only when the account setting differs.
  final lev = market.isSpot ? 1 : leverage.clamp(1, market.maxLeverage).toInt();
  if (!market.isSpot) {
    // The region's leverage cap, at the same point the spending wallet
    // checks it (before the venue is asked to set the leverage).
    RuntimeCapabilitiesService.instance.ensureLeverageAllowed(lev);
    final account = ref.read(ledgerHlAccountProvider(walletId)).valueOrNull;
    // Positions carry the wire coin ('xyz:TSLA').
    final position = _positionFor(account, market.wireCoin);
    // An open position keeps its margin mode: adding to it never flips
    // isolated to cross (or back). The ticket prefills its leverage, so
    // only a leverage the user moved on purpose differs here.
    final isCross = position != null
        ? position.isCross && !market.onlyIsolated
        : !market.onlyIsolated;
    final matches = position != null &&
        position.leverageValue == lev &&
        (position.leverageType == 'cross') == isCross;
    if (!matches) {
      final intent = LedgerHyperliquidIntents.updateLeverage(
        walletId: walletId,
        account: paired,
        assetId: market.assetId,
        coin: market.coin,
        isCross: isCross,
        leverage: lev,
        summary: {
          l10n.ledgerSummaryMarket: market.coin,
          l10n.ledgerSummaryLeverage: '${lev}x',
        },
      );
      final outcome = await showLedgerApprovalSheet<void>(
        context,
        walletId: walletId,
        request: LedgerActionRequest<void>(
          intent: intent,
          execute: (signing) => factory(
            walletId: walletId,
            pairedAddress: signing.pairedAddress,
            signer: signing.signer,
          ).updateLeverage(intent),
        ),
      );
      if (!outcome.isSuccess || !context.mounted) return null;
    }
  }

  // 3) The order: an IOC limit through the book, as the hot market order.
  final double refPx;
  try {
    refPx = await ledgerHlReferencePx(market);
  } catch (_) {
    if (context.mounted) {
      showMessageSnackBar(
          context: context, message: l10n.ledgerPriceUnavailable, error: true);
    }
    return null;
  }
  if (!context.mounted) return null;
  final size = sizeFromUsd(
      usd: marginUsd * lev, px: refPx, szDecimals: market.szDecimals);
  // Valued where the venue values it: a sell at its slippage price.
  final checkPx = hlMinCheckPx(
    referencePx: refPx,
    isBuy: isBuy,
    slippage: slippagePct / 100,
    szDecimals: market.szDecimals,
    isSpot: market.isSpot,
  );
  if (size <= 0 || !meetsMinNotional(px: checkPx, sz: size)) {
    showMessageSnackBar(
        context: context, message: l10n.ledgerOrderTooSmall, error: true);
    return null;
  }
  final String px;
  final String sz;
  try {
    px = slippagePrice(
      referencePx: refPx,
      isBuy: isBuy,
      slippage: slippagePct / 100,
      szDecimals: market.szDecimals,
      isSpot: market.isSpot,
    );
    sz = roundSize(size, market.szDecimals);
  } on ArgumentError {
    showMessageSnackBar(
        context: context, message: l10n.ledgerOrderTooSmall, error: true);
    return null;
  }

  final intent = LedgerHyperliquidIntents.order(
    walletId: walletId,
    account: paired,
    assetId: market.assetId,
    coin: market.coin,
    isBuy: isBuy,
    px: px,
    sz: sz,
    tif: 'Ioc',
    reduceOnly: false,
    cloid: ledgerNewCloid(),
    builderAddress: builder?.builderAddress,
    builderFeeTenthsBp: builder?.defaultFeeTenthsBp,
    // Market, side and the dollars committed stay on the review card; the
    // coin size, leverage and worst price sit behind its Advanced row.
    summary: {
      l10n.ledgerSummaryMarket: market.coin,
      l10n.ledgerSummarySide: isBuy ? l10n.buy : l10n.sell,
      l10n.ledgerSummaryAmount: ledgerFormatUsd(marginUsd),
      l10n.ledgerSummarySize: '$sz ${market.coin}',
      if (!market.isSpot) l10n.ledgerSummaryLeverage: '${lev}x',
      l10n.ledgerSummaryPriceType: l10n.ledgerOrderMarketPrice,
      l10n.ledgerSummaryLimitPrice: px,
    },
  );
  final outcome = await showLedgerApprovalSheet<HlOrderResult>(
    context,
    walletId: walletId,
    request: LedgerActionRequest<HlOrderResult>(
      intent: intent,
      amountUsd: marginUsd * lev,
      execute: (signing) => factory(
        walletId: walletId,
        pairedAddress: signing.pairedAddress,
        signer: signing.signer,
      ).placeOrder(intent),
      reconcile: ledgerHlReconcile(ref, walletId),
    ),
  );
  if (outcome.isSuccess || outcome.isPending) {
    ref.invalidate(ledgerHlAccountProvider(walletId));
    ref.invalidate(ledgerPendingActionsProvider(walletId));
  }
  if (outcome.isPending) onPending?.call();
  return outcome.isSuccess ? outcome.result : null;
}

/// A close is always reduce-only and bound to the selected Ledger account.
/// It never changes leverage or delegates signing to the spending wallet.
Future<LedgerApprovalOutcome<HlOrderResult>?> runLedgerHlClose(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required HlPerpPosition position,
  required HlMarket market,
  required double size,
  required double slippagePct,
  double? limitPrice,
}) async {
  if (!await ensureRouteNotPaused(
          context, PausableRoute.ledgerInvestingActions) ||
      !context.mounted) {
    return null;
  }
  final paired = _paired(ref, walletId);
  if (paired == null || market.isSpot || market.wireCoin != position.coin) {
    throw StateError('Position account or market unavailable. Review again.');
  }
  final sz = roundSize(size, market.szDecimals);
  final quantity = double.tryParse(sz) ?? 0;
  if (!quantity.isFinite ||
      quantity <= 0 ||
      quantity > position.szi.abs() ||
      !slippagePct.isFinite ||
      slippagePct <= 0 ||
      slippagePct > 5 ||
      (limitPrice != null && (!limitPrice.isFinite || limitPrice <= 0))) {
    throw StateError('Invalid close amount or price. Review again.');
  }
  Future<void> verifyPosition() async {
    final current = await ref.refresh(ledgerHlAccountProvider(walletId).future);
    validateLedgerHlClosePosition(
      current: current,
      walletId: walletId,
      pairedAddress: paired,
      currentPairedAddress: _paired(ref, walletId),
      position: position,
      quantity: quantity,
    );
  }

  await verifyPosition();
  if (!context.mounted) return null;
  // One builder for the approval check, the approval and the order.
  final builder = await HyperliquidFundingService.getBuilder();
  if (!context.mounted) return null;
  if (builder != null &&
      await ledgerHlBuilderFeeApproved(paired, builder: builder) != true) {
    if (!context.mounted ||
        !await approveLedgerHlBuilderFee(context, ref,
            walletId: walletId, builder: builder)) {
      return null;
    }
  }
  if (!context.mounted) return null;
  final reference = await ledgerHlReferencePx(market);
  final isBuy = !position.isLong;
  final px = limitPrice == null
      ? slippagePrice(
          referencePx: reference,
          isBuy: isBuy,
          slippage: slippagePct / 100,
          szDecimals: market.szDecimals,
          isSpot: false)
      : roundPrice(limitPrice, szDecimals: market.szDecimals, isSpot: false);
  if (!context.mounted) return null;
  final l10n = context.l10n;
  final intent = LedgerHyperliquidIntents.order(
    walletId: walletId,
    account: paired,
    assetId: market.assetId,
    coin: position.coin,
    isBuy: isBuy,
    px: px,
    sz: sz,
    tif: limitPrice == null ? 'Ioc' : 'Gtc',
    reduceOnly: true,
    cloid: ledgerNewCloid(),
    builderAddress: builder?.builderAddress,
    builderFeeTenthsBp: builder?.defaultFeeTenthsBp,
    summary: {
      l10n.ledgerSummaryMarket: position.coin,
      l10n.ledgerSummarySide: l10n.hlClosePosition,
      l10n.ledgerSummarySize: '$sz ${position.coin}',
      l10n.ledgerSummaryPriceType: limitPrice == null
          ? l10n.ledgerOrderMarketPrice
          : l10n.betOrderTypeLimit,
      l10n.ledgerSummaryLimitPrice: px,
      l10n.ledgerSummaryReduceOnly: l10n.yes,
    },
  );
  final factory = ref.read(ledgerHlExecutorFactoryProvider);
  final outcome = await showLedgerApprovalSheet<HlOrderResult>(
    context,
    walletId: walletId,
    request: LedgerActionRequest<HlOrderResult>(
      intent: intent,
      amountUsd: quantity * double.parse(px),
      execute: (signing) async {
        await verifyPosition();
        return factory(
                walletId: walletId,
                pairedAddress: signing.pairedAddress,
                signer: signing.signer)
            .placeOrder(intent);
      },
      reconcile: ledgerHlReconcile(ref, walletId),
    ),
  );
  if (context.mounted) {
    ref.invalidate(ledgerHlAccountProvider(walletId));
    ref.invalidate(ledgerPendingActionsProvider(walletId));
  }
  return outcome;
}

/// Rechecked immediately before a Ledger close is signed. An unrelated
/// history/vault read failure must not prevent reducing a live position.
void validateLedgerHlClosePosition({
  required LedgerHlAccount current,
  required String walletId,
  required String pairedAddress,
  required String? currentPairedAddress,
  required HlPerpPosition position,
  required double quantity,
}) {
  final live = _positionFor(current, position.coin);
  final category = position.coin.contains(':')
      ? LedgerHlReadCategory.hip3Dexes
      : LedgerHlReadCategory.account;
  if (current.walletId != walletId ||
      current.partialFailures.contains(category) ||
      current.address?.toLowerCase() != pairedAddress.toLowerCase() ||
      currentPairedAddress?.toLowerCase() != pairedAddress.toLowerCase() ||
      !quantity.isFinite ||
      quantity <= 0 ||
      !position.szi.isFinite ||
      quantity > position.szi.abs() ||
      live == null ||
      !live.szi.isFinite ||
      live.isLong != position.isLong ||
      quantity > live.szi.abs()) {
    throw StateError('Position changed. Review the close again.');
  }
}

/// The market a resting order names. Orders carry WIRE coins ('BTC',
/// 'xyz:TSLA', '@107', 'PURR/USDC'), so the match is exact on the wire
/// coin and covers the builder (HIP-3) dexes too: a by-name match could
/// sign the cancel against another instrument sharing the symbol.
Future<HlMarket?> _resolveOrderMarket(WidgetRef ref, String wire) async {
  final model = ref.read(ledgerHyperliquidModelProvider);
  try {
    final perps = wire.contains(':')
        ? await model.getAllPerpMarkets()
        : await model.getPerpMarkets();
    for (final m in perps) {
      if (m.wireCoin == wire) return m;
    }
    for (final m in await model.getSpotMarkets()) {
      if (m.wireCoin == wire) return m;
    }
  } catch (_) {}
  return null;
}

/// Cancels one resting order with a Ledger approval (a Hyperliquid cancel
/// needs the account signature by protocol).
Future<bool> runLedgerHlCancel(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required HlOpenOrder order,
  int? assetId,
}) async {
  if (!await ensureRouteNotPaused(
          context, PausableRoute.ledgerInvestingActions) ||
      !context.mounted) {
    return false;
  }
  final l10n = context.l10n;
  final paired = _paired(ref, walletId);
  if (paired == null) return false;
  final market = await _resolveOrderMarket(ref, order.coin);
  final resolved = assetId ?? market?.assetId;
  if (!context.mounted) return false;
  if (resolved == null) {
    showMessageSnackBar(
        context: context, message: l10n.ledgerErrorUnknown, error: true);
    return false;
  }
  final factory = ref.read(ledgerHlExecutorFactoryProvider);
  // What the review card shows: the display name, never '@107'.
  final shown = market?.coin ?? HlMarket.baseCoin(order.coin);
  final intent = LedgerHyperliquidIntents.cancel(
    walletId: walletId,
    account: paired,
    assetId: resolved,
    coin: order.coin,
    oid: order.oid,
    summary: {
      l10n.ledgerSummaryAction: l10n.ledgerCancelOrderSummary,
      l10n.ledgerSummaryMarket: shown,
      l10n.ledgerSummarySide: order.isBuy ? l10n.buy : l10n.sell,
      l10n.ledgerSummaryAmount: order.isTrailingStop
          ? '${order.sz} $shown'
          : ledgerFormatUsd(order.sz * order.limitPx),
      l10n.ledgerSummarySize: '${order.sz} $shown',
      if (!order.isTrailingStop)
        l10n.ledgerSummaryLimitPrice: '${order.limitPx}',
    },
  );
  final outcome = await showLedgerApprovalSheet<void>(
    context,
    walletId: walletId,
    request: LedgerActionRequest<void>(
      intent: intent,
      execute: (signing) => factory(
        walletId: walletId,
        pairedAddress: signing.pairedAddress,
        signer: signing.signer,
      ).cancelOrder(intent),
    ),
  );
  if (outcome.isSuccess || outcome.isPending) {
    ref.invalidate(ledgerHlAccountProvider(walletId));
  }
  if (outcome.isSuccess && context.mounted) {
    showLedgerConfirmation(Navigator.of(context, rootNavigator: true),
        message: l10n.ledgerOrderCancelled);
  }
  return outcome.isSuccess;
}

/// Native trailing stops keep the paired Ledger as the sole signer.
Future<HlOrderResult?> runLedgerHlTrailingStop(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required HlMarket market,
  required bool isBuy,
  required double size,
  required HlTrailingStop trail,
  required bool reduceOnly,
  required int leverage,
  required bool isCross,
  VoidCallback? onPending,
}) async {
  if (!await ensureRouteNotPaused(
        context,
        PausableRoute.ledgerInvestingActions,
      ) ||
      !context.mounted) {
    return null;
  }
  await RuntimeCapabilitiesService.instance.ensureAllowed('trading.advanced');
  await RuntimeCapabilitiesService.instance.ensureAllAllowed(
    reduceOnly ? const ['hyperliquid.close'] : hlOpenCapabilities(market),
  );
  final paired = _paired(ref, walletId);
  if (paired == null) throw StateError('Ledger account unavailable.');
  void verifyAccount() {
    if (!context.mounted ||
        _paired(ref, walletId)?.toLowerCase() != paired.toLowerCase()) {
      throw StateError('Ledger account changed. Review again.');
    }
  }

  await TrailingStopGuard().ensureAvailable(
    address: paired,
    assetId: market.assetId,
  );
  final reference = await ledgerHlReferencePx(market);
  trail.validate(market: market, isBuy: isBuy, referencePrice: reference);
  if (!context.mounted) return null;
  final factory = ref.read(ledgerHlExecutorFactoryProvider);
  final lev = leverage.clamp(1, market.maxLeverage).toInt();
  if (!reduceOnly) {
    final intent = LedgerHyperliquidIntents.updateLeverage(
      walletId: walletId,
      account: paired,
      assetId: market.assetId,
      coin: market.coin,
      leverage: lev,
      isCross: isCross && !market.onlyIsolated,
      summary: {
        'Market': HlMarket.baseCoin(market.coin),
        'Leverage': '${lev}x',
        'Margin': isCross && !market.onlyIsolated ? 'Cross' : 'Isolated',
      },
    );
    final outcome = await showLedgerApprovalSheet<void>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<void>(
        intent: intent,
        execute: (signing) {
          verifyAccount();
          return factory(
            walletId: walletId,
            pairedAddress: signing.pairedAddress,
            signer: signing.signer,
          ).updateLeverage(intent);
        },
      ),
    );
    if (!outcome.isSuccess || !context.mounted) return null;
  }
  verifyAccount();
  final l10n = context.l10n;
  final intent = LedgerHyperliquidIntents.trailingStop(
    walletId: walletId,
    account: paired,
    market: market,
    isBuy: isBuy,
    size: size,
    trail: trail,
    reduceOnly: reduceOnly,
    summary: {
      l10n.ledgerSummaryMarket: HlMarket.baseCoin(market.coin),
      l10n.ledgerSummaryOrder: l10n.hlOrdersTrailingStopMarket,
      l10n.ledgerSummarySide: isBuy ? l10n.buy : l10n.sell,
      l10n.ledgerSummarySize:
          '${roundSize(size, market.szDecimals)} ${HlMarket.baseCoin(market.coin)}',
      l10n.ledgerSummaryTrailingDistance:
          '${trail.retracement}${trail.percent ? '%' : ' USD'}',
      l10n.ledgerSummaryActivation:
          trail.activationPrice?.toString() ?? l10n.ledgerSummaryImmediately,
      l10n.ledgerSummaryReduceOnly: reduceOnly ? l10n.yes : l10n.betNo,
    },
  );
  if (!context.mounted) return null;
  final outcome = await showLedgerApprovalSheet<HlOrderResult>(
    context,
    walletId: walletId,
    request: LedgerActionRequest<HlOrderResult>(
      intent: intent,
      amountUsd: size * reference,
      execute: (signing) {
        verifyAccount();
        return factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
        ).placeTrailingStop(
          intent,
          market: market,
          trail: trail,
          size: size,
          referencePrice: reference,
          beforeSend: verifyAccount,
        );
      },
      reconcile: ledgerHlReconcile(ref, walletId),
    ),
  );
  if (context.mounted && (outcome.isSuccess || outcome.isPending)) {
    ref.invalidate(ledgerHlAccountProvider(walletId));
    ref.invalidate(ledgerPendingActionsProvider(walletId));
  }
  if (outcome.isPending) onPending?.call();
  return outcome.isSuccess ? outcome.result : null;
}
