// lib/screens/ledger/polymarket/ledger_pm_support.dart
//
// Helpers shared by the Polymarket Ledger sheets (Wallet hardening
// Phase 4a, P4.6): the sell order amounts (same precision rules as the
// hot FOK sell, in exact integer arithmetic) and a batch reconciler that
// reads relayer state without ever signing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

class LedgerPmSellQuote {
  const LedgerPmSellQuote({
    required this.makerAmount,
    required this.takerAmount,
    required this.price,
  });

  /// Outcome shares sold, 6-decimal base units, two share decimals.
  final BigInt makerAmount;

  /// Minimum pUSD received, 6-decimal base units.
  final BigInt takerAmount;

  /// The limit price the order carries.
  final double price;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// (price decimals, amount decimals) for a CLOB tick size.
(int, int) ledgerPmRoundingForTick(String? tickSize) => switch (tickSize) {
      '0.1' => (1, 3),
      '0.01' => (2, 4),
      '0.001' => (3, 4),
      '0.0001' => (4, 4),
      _ => (2, 4),
    };

/// A fill-or-kill SELL of [shares] at most [slippage] below [bestBid]
/// (at least one tick below it while [slippage] is above zero).
/// Shares floor to two decimals; the minimum proceeds floor to the tick's
/// amount precision. Null when the order would be empty.
LedgerPmSellQuote? buildLedgerPmSellQuote({
  required double shares,
  required double bestBid,
  required String? tickSize,
  double slippage = 0.05,
}) {
  if (shares <= 0 || bestBid <= 0) return null;
  final (priceDecimals, amountDecimals) = ledgerPmRoundingForTick(tickSize);
  final sharesCents = (shares * 100 + 1e-9).floor();
  if (sharesCents <= 0) return null;
  final priceScale = _pow10(priceDecimals);
  // The hot sell sheet's floor: the slippage rounded up, with one tick of
  // room at least (polymarketSellFloor).
  var priceUnits = (polymarketSellFloor(
                  bid: bestBid,
                  slippagePct: slippage * 100,
                  tick: 1 / priceScale) *
              priceScale)
          .round();
  if (priceUnits < 1) priceUnits = 1;
  if (priceUnits >= priceScale) priceUnits = priceScale - 1;

  final maker = BigInt.from(sharesCents) * BigInt.from(10000);
  final numerator = BigInt.from(sharesCents) *
      BigInt.from(priceUnits) *
      BigInt.from(1000000);
  final denominator = BigInt.from(100) * BigInt.from(priceScale);
  final step = BigInt.from(_pow10(6 - amountDecimals));
  final taker = (numerator ~/ denominator) ~/ step * step;
  if (taker <= BigInt.zero) return null;
  return LedgerPmSellQuote(
    makerAmount: maker,
    takerAmount: taker,
    price: priceUnits / priceScale,
  );
}

/// Reads the relayer state of a pending Ledger batch. Builds the executor
/// with a signer that refuses every request.
LedgerReconcile ledgerPmBatchReconcile(
  WidgetRef ref, {
  required String walletId,
  required PolymarketLedgerAccount account,
}) {
  final factory = ref.read(ledgerPmExecutorFactoryProvider);
  return (recordId) async {
    final paired = ref.read(ledgerIdentityProvider(walletId))?.evmAddress;
    if (paired == null) return null;
    final stage = await factory(
      walletId: walletId,
      pairedAddress: paired,
      signer: ledgerReadOnlySigner(paired),
      account: account,
    ).reconcileBatch(recordId);
    return switch (stage) {
      LedgerSubmissionStage.confirmed || LedgerSubmissionStage.accepted => true,
      LedgerSubmissionStage.rejected => false,
      _ => null,
    };
  };
}
