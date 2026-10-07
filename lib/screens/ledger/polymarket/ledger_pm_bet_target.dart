import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart'
    show LedgerSubmissionUnknownException;
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show polymarketCentsLabel;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

enum LedgerPmBetOutcome {
  submitted,
  pending,
  prepared,
  resolved,
  cancelled,
  failed
}

// Covers preparation as well as submission, across every ticket for a wallet.
// Durable records provide the separate process-restart submission guard.
final _activeWallets = <String>{};

String _units(BigInt value) {
  final raw = value.toString().padLeft(7, '0');
  final fraction =
      raw.substring(raw.length - 6).replaceFirst(RegExp(r'0+$'), '');
  return '${raw.substring(0, raw.length - 6)}${fraction.isEmpty ? '' : '.$fraction'}';
}

void _refresh(WidgetRef ref, String walletId) {
  ref.invalidate(ledgerPmBuyingPowerProvider(walletId));
  ref.invalidate(ledgerPmPendingBetProvider(walletId));
  ref.invalidate(ledgerPmAccountProvider(walletId));
  ref.invalidate(ledgerPendingActionsProvider(walletId));
}

void _showFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  final l10n = context.l10n;
  final message = error is LedgerPmTradeRefused
      ? switch (error.reason) {
          LedgerPmTradeRefusal.accountUnavailable => l10n.ledgerBetUnavailable,
          LedgerPmTradeRefusal.marketChanged => l10n.ledgerBetDetailsChanged,
          LedgerPmTradeRefusal.insufficientCash =>
            l10n.ledgerBetInsufficientCash,
          LedgerPmTradeRefusal.liquidityUnavailable =>
            l10n.betBuyLiquidityUnavailable,
          LedgerPmTradeRefusal.priceMoved
              when error.price != null && error.limit != null =>
            l10n.betBuyPriceMoved(polymarketCentsLabel(error.price!),
                polymarketCentsLabel(error.limit!)),
          _ => l10n.ledgerBetCashUnavailable,
        }
      : error is LedgerSubmissionUnknownException
          ? l10n.ledgerBetPending
          : ledgerFundingErrorMessage(context, error);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Uses only the explicitly named Ledger. The ticket remains owned by its
/// caller: this opens the device/review sheet, never pops the ticket or claims
/// a fill. Allowance preparation is a separate approval and never buys.
Future<LedgerPmBetOutcome> showLedgerPredictionApproval(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required String tokenId,
  required String conditionId,
  required double amountUsd,
  required double reviewedPrice,
  required bool isLimit,
  required double slippagePct,
  required String marketQuestion,
  required String outcomeLabel,
  DateTime? marketEndAt,
  void Function(LedgerActionIntent intent)? onOrderIntent,
  void Function(double retryPrice)? onPriceMoved,
}) async {
  if (!_activeWallets.add(walletId)) return LedgerPmBetOutcome.cancelled;
  final source = LedgerPmMarketSource();
  final l10n = context.l10n;
  try {
    final identity = ref.read(ledgerIdentityProvider(walletId));
    if (!kLedgerInvestingEnabled ||
        identity?.hasVerifiedEvm != true ||
        !isLedgerActionAllowed(LedgerActionKind.pmOrder)) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.accountUnavailable);
    }
    final expires = DateTime.now().add(const Duration(minutes: 2));
    void ensureCurrent() {
      if (!context.mounted) {
        throw const LedgerFailure(LedgerFailureCode.rejected);
      }
      if (ref.read(ledgerIdentityProvider(walletId)) != identity) {
        throw const LedgerFailure(LedgerFailureCode.wrongSigner);
      }
      if (!DateTime.now().isBefore(expires) ||
          (marketEndAt != null && !DateTime.now().isBefore(marketEndAt))) {
        throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
      }
    }

    // The same gates the spending wallet checks in placeOrder: opening
    // predictions plus the category gate of a sports or politics market.
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(polymarketBetCapabilitiesFor([tokenId, conditionId]));
    ensureCurrent();
    final store = ref.read(ledgerSubmittedActionStoreProvider);
    if (await store.blockingPolymarketOrder(walletId) != null ||
        await store.blockingPolymarketBatch(walletId) != null) {
      return LedgerPmBetOutcome.pending;
    }
    final reads = ref.read(ledgerPolymarketReadsProvider);
    final account =
        await PolymarketAccountResolver(reads).resolve(identity!.evmAddress!);
    ensureCurrent();
    if (!account.canAct) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.accountUnavailable);
    }
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final address = identity.evmAddress!;
    LedgerPolymarketExecutor readExecutor() => factory(
        walletId: walletId,
        pairedAddress: address,
        signer: ledgerReadOnlySigner(address),
        account: account);
    var power = await readExecutor().readBuyingPower();
    ensureCurrent();
    if (power == null) {
      final authIntent = LedgerPolymarketIntents.authenticate(
          walletId: walletId,
          depositWallet: account.address!,
          summary: {
            l10n.ledgerSummaryAction: l10n.ledgerBetVerifyCash,
          });
      if (!context.mounted) return LedgerPmBetOutcome.cancelled;
      final result = await _approve<LedgerPmBuyingPower>(
        context,
        ref,
        identity: identity,
        account: account,
        intent: authIntent,
        ensureCurrent: ensureCurrent,
        execute: (executor, guard) =>
            executor.authenticateForTrading(authIntent),
      );
      ensureCurrent();
      if (result.outcome != LedgerPmBetOutcome.submitted ||
          result.result == null) {
        return result.outcome;
      }
      power = result.result!;
    }
    final rules = await source.read(tokenId, conditionId);
    // The backend's code, or the zero builder (no attribution, no builder
    // fee) when it has none to give; never a reason to refuse the bet.
    final builder = await PolymarketBackendService.getBuilderCode();
    ensureCurrent();
    final amounts = rules.amounts(
        budgetUsd: amountUsd,
        reviewedPrice: reviewedPrice,
        isLimit: isLimit,
        slippagePct: slippagePct);
    // The venue takes its platform and builder fees from the same pUSD as
    // the stake, outside the signed amounts. Reserve them at the reviewed
    // price (the cheapest this order fills at, where the per-share fee is
    // largest) so the device never signs an order the account cannot pay.
    final feeTerms = await PolymarketFeeTerms.fetchOrWorstCase(tokenId);
    ensureCurrent();
    final feeReserve = BigInt.from(
        (feeTerms.feeCeilingForNotional(amountUsd, reviewedPrice) * 1000000)
            .ceil());
    if (power.spendable < amounts.maker + feeReserve) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.insufficientCash);
    }
    // The exchange pulls fees from the same allowance as the stake. A
    // neg-risk order needs it at the Neg Risk Exchange and the v1 adapter
    // the CLOB still checks; allowance() is the smaller of the two, and the
    // approval sets both in one batch, each named on the review.
    if (power.allowance(rules.negRisk) < amounts.maker + feeReserve) {
      final approval = LedgerPolymarketIntents.approveTrading(
          walletId: walletId,
          depositWallet: account.address!,
          amount: amounts.maker + feeReserve,
          negRisk: rules.negRisk,
          summary: {
            l10n.ledgerSummaryAction: l10n.ledgerBetEnableSpending,
            l10n.ledgerBetMaxSpend: '\$${_units(amounts.maker + feeReserve)}',
            l10n.ledgerSummaryContracts:
                ledgerPmContractsLabel(ledgerPmTradeSpenders(rules.negRisk)),
          });
      String? reconciled;
      if (!context.mounted) return LedgerPmBetOutcome.cancelled;
      final result = await _approve<String>(
        context,
        ref,
        identity: identity,
        account: account,
        intent: approval,
        ensureCurrent: ensureCurrent,
        execute: (executor, guard) =>
            executor.approveTrading(approval, beforeSubmit: guard),
        reconcile: (recordId) async {
          final status = await readExecutor()
              .reconcileBatchResult(recordId, expectedIntent: approval);
          if (status.stage == LedgerSubmissionStage.confirmed &&
              status.hash != null) {
            reconciled = status.hash;
            return true;
          }
          return status.stage == LedgerSubmissionStage.rejected ? false : null;
        },
        recoveredResult: () => reconciled,
      );
      return result.outcome == LedgerPmBetOutcome.submitted
          ? LedgerPmBetOutcome.prepared
          : result.outcome;
    }
    final price =
        (amounts.maker * BigInt.from(1000000) + amounts.taker - BigInt.one) ~/
            amounts.taker;
    if (!isLimit) {
      // The same depth check the hot wallet prepares its quote from: the
      // whole stake must be fillable at or under the reviewed cap, or the
      // FOK would die at the venue after the device had already signed.
      final depth = rules.depthPriceFor(amountUsd);
      if (depth == null || BigInt.from((depth * 1000000).round()) > price) {
        throw const LedgerPmTradeRefused(
            LedgerPmTradeRefusal.liquidityUnavailable);
      }
    }
    final random = Random.secure();
    final salt = (BigInt.from(random.nextInt(1 << 26)) << 26) +
        BigInt.from(random.nextInt(1 << 26));
    final intent = LedgerPolymarketIntents.buy(
      walletId: walletId,
      depositWallet: account.address!,
      tokenId: tokenId,
      maxSpend: amounts.maker,
      minShares: amounts.taker,
      maxPriceMicros: price,
      negRisk: rules.negRisk,
      salt: salt,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      orderType: isLimit ? OrderType.gtc : OrderType.fok,
      builderCode: builder,
      feeReserve: feeReserve,
      summary: {
        l10n.ledgerSummaryAction: l10n.ledgerBetReviewTitle,
        l10n.ledgerSummaryMarket: marketQuestion,
        l10n.ledgerSummaryOutcome: outcomeLabel,
        l10n.ledgerBetMaxSpend: '\$${_units(amounts.maker)}',
        l10n.ledgerBetMinShares: _units(amounts.taker),
        l10n.ledgerBetWorstPrice: '${_units(price * BigInt.from(100))}¢',
      },
    );
    Future<void> revalidate() async {
      ensureCurrent();
      final fresh = await source.read(tokenId, conditionId);
      final freshAccount =
          await PolymarketAccountResolver(reads).resolve(address);
      // Held in memory for this policy revision, so an outage while the
      // device is open does not change it. A code that did change (policy
      // moved on, or the backend came back after a zero-builder review)
      // changes the builder fee reserved above, so the bet is re-reviewed.
      final freshBuilder = await PolymarketBackendService.getBuilderCode();
      ensureCurrent();
      // The book as it is now: the whole stake must still fill at or
      // under the maximum the device signed, or nothing is sent.
      if (!isLimit) {
        fresh.ensureFillsWithin(
            budgetUsd: amountUsd,
            maxPriceMicros: price,
            slippagePct: slippagePct);
      }
      if (!rules.sameRules(fresh) ||
          !freshAccount.canAct ||
          freshAccount.address?.toLowerCase() !=
              account.address!.toLowerCase() ||
          freshAccount.variant != account.variant ||
          freshBuilder != builder) {
        throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.marketChanged);
      }
    }

    onOrderIntent?.call(intent);
    LedgerPmOrderResult? reconciled;
    if (!context.mounted) return LedgerPmBetOutcome.cancelled;
    final result = await _approve<LedgerPmOrderResult>(
      context,
      ref,
      identity: identity,
      account: account,
      intent: intent,
      ensureCurrent: ensureCurrent,
      execute: (executor, guard) =>
          executor.buy(intent, revalidate: revalidate, ensureCurrent: guard),
      reconcile: (recordId) async {
        reconciled = await readExecutor()
            .reconcileOrder(recordId, expectedIntent: intent);
        if (reconciled == null) return null;
        final record = await store.get(walletId, recordId);
        return record?.stage != LedgerSubmissionStage.rejected;
      },
      recoveredResult: () => reconciled,
    );
    return result.outcome;
  } catch (error) {
    if (error is LedgerPmTradeRefused &&
        error.reason == LedgerPmTradeRefusal.priceMoved &&
        error.retryPrice != null) {
      onPriceMoved?.call(error.retryPrice!);
    }
    if (context.mounted) _showFailure(context, error);
    return error is LedgerSubmissionUnknownException
        ? LedgerPmBetOutcome.pending
        : LedgerPmBetOutcome.failed;
  } finally {
    source.close();
    _activeWallets.remove(walletId);
    if (context.mounted) _refresh(ref, walletId);
  }
}

typedef _Execution<R> = Future<R> Function(
    LedgerPolymarketExecutor executor, void Function() guard);

/// One approval owns one execution future. Closing while a device or network
/// request awaits cannot start another submission when that request resumes.
Future<({LedgerPmBetOutcome outcome, R? result})> _approve<R>(
  BuildContext context,
  WidgetRef ref, {
  required LedgerIdentity identity,
  required PolymarketLedgerAccount account,
  required LedgerActionIntent intent,
  required void Function() ensureCurrent,
  required _Execution<R> execute,
  LedgerReconcile? reconcile,
  R? Function()? recoveredResult,
}) async {
  final factory = ref.read(ledgerPmExecutorFactoryProvider);
  var closed = false;
  Future<R>? execution;
  var rejected = false;
  void guard() {
    if (closed) throw const LedgerFailure(LedgerFailureCode.rejected);
    ensureCurrent();
  }

  guard();
  final result = await showLedgerApprovalSheet<R>(
    context,
    walletId: identity.walletId,
    request: LedgerActionRequest<R>(
      intent: intent,
      reconcile: reconcile == null
          ? null
          : (id) async {
              final result = await reconcile(id);
              if (result == false) rejected = true;
              return result;
            },
      execute: (signing) {
        if (execution != null) return execution!;
        return execution = () async {
          guard();
          if (signing.walletId != identity.walletId ||
              signing.pairedAddress.toLowerCase() !=
                  identity.evmAddress!.toLowerCase()) {
            throw const LedgerFailure(LedgerFailureCode.wrongSigner);
          }
          return execute(
              factory(
                  walletId: identity.walletId,
                  pairedAddress: signing.pairedAddress,
                  signer: signing.signer,
                  account: account),
              guard);
        }();
      },
    ),
  );
  closed = true;
  if (rejected) return (outcome: LedgerPmBetOutcome.resolved, result: null);
  final recovered = recoveredResult?.call();
  if (result.isSuccess && (result.result != null || recovered != null)) {
    return (
      outcome: LedgerPmBetOutcome.submitted,
      result: result.result ?? recovered
    );
  }
  if (execution != null) {
    try {
      final completed = await execution;
      return (outcome: LedgerPmBetOutcome.submitted, result: completed);
    } on LedgerSubmissionUnknownException {
      return (outcome: LedgerPmBetOutcome.pending, result: null);
    } on LedgerPmTradeRefused catch (e) {
      // The price moved past the signed maximum: nothing was sent, and the
      // ticket says where it went and offers the new maximum.
      if (e.reason == LedgerPmTradeRefusal.priceMoved) rethrow;
    } catch (_) {
      // A non-submission error was already shown in the approval sheet.
    }
  }
  return (
    outcome: result.isPending
        ? LedgerPmBetOutcome.pending
        : LedgerPmBetOutcome.cancelled,
    result: null
  );
}

/// A status read never signs or replaces an order. Missing/ambiguous results
/// retain the durable lock. A confirmed old action is not a new draft's fill.
Future<LedgerPmBetOutcome> checkLedgerPredictionStatus(
    BuildContext context, WidgetRef ref,
    {required String walletId, LedgerActionIntent? expectedIntent}) async {
  if (!_activeWallets.add(walletId)) return LedgerPmBetOutcome.pending;
  try {
    final identity = ref.read(ledgerIdentityProvider(walletId));
    if (identity?.hasVerifiedEvm != true) return LedgerPmBetOutcome.pending;
    final store = ref.read(ledgerSubmittedActionStoreProvider);
    if (expectedIntent != null) {
      expectedIntent.verify();
      if (expectedIntent.walletId != walletId ||
          expectedIntent.kind != LedgerActionKind.pmOrder) {
        return LedgerPmBetOutcome.pending;
      }
    }
    final matches = expectedIntent == null
        ? const <LedgerSubmittedAction>[]
        : (await store.forWallet(walletId))
            .where((record) =>
                record.kind == LedgerActionKind.pmOrder.name &&
                record.paramsHash == expectedIntent.paramsHash)
            .toList();
    if (expectedIntent != null && matches.isEmpty) {
      // Records are written before any POST, so an intent with no record was
      // never sent. Nothing about it needs reconciliation.
      return LedgerPmBetOutcome.resolved;
    }
    if (expectedIntent != null && matches.length > 1) {
      return LedgerPmBetOutcome.pending;
    }
    final order = expectedIntent == null
        ? await store.blockingPolymarketOrder(walletId)
        : matches.single;
    final batch = expectedIntent == null
        ? await store.blockingPolymarketBatch(walletId)
        : null;
    if (order == null && batch == null) return LedgerPmBetOutcome.resolved;
    final account =
        await PolymarketAccountResolver(ref.read(ledgerPolymarketReadsProvider))
            .resolve(identity!.evmAddress!);
    if (!context.mounted ||
        ref.read(ledgerIdentityProvider(walletId)) != identity ||
        !account.canAct) {
      return LedgerPmBetOutcome.pending;
    }
    final executor = ref.read(ledgerPmExecutorFactoryProvider)(
        walletId: walletId,
        pairedAddress: identity.evmAddress!,
        signer: ledgerReadOnlySigner(identity.evmAddress!),
        account: account);
    if (order != null) {
      final result = await executor.reconcileOrder(order.id,
          expectedIntent: expectedIntent);
      if (result == null ||
          !context.mounted ||
          ref.read(ledgerIdentityProvider(walletId)) != identity) {
        return LedgerPmBetOutcome.pending;
      }
      final record = await store.get(walletId, order.id);
      if (!context.mounted ||
          ref.read(ledgerIdentityProvider(walletId)) != identity) {
        return LedgerPmBetOutcome.pending;
      }
      if (record?.stage == LedgerSubmissionStage.rejected) {
        return LedgerPmBetOutcome.resolved;
      }
      return record?.stage == LedgerSubmissionStage.accepted ||
              record?.stage == LedgerSubmissionStage.confirmed
          ? LedgerPmBetOutcome.submitted
          : LedgerPmBetOutcome.pending;
    }
    final stage = await executor.reconcileBatch(batch!.id);
    if (!context.mounted ||
        ref.read(ledgerIdentityProvider(walletId)) != identity) {
      return LedgerPmBetOutcome.pending;
    }
    return stage == LedgerSubmissionStage.confirmed ||
            stage == LedgerSubmissionStage.rejected
        ? LedgerPmBetOutcome.resolved
        : LedgerPmBetOutcome.pending;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.ledgerBetPending)));
    }
    return LedgerPmBetOutcome.pending;
  } finally {
    _activeWallets.remove(walletId);
    if (context.mounted) _refresh(ref, walletId);
  }
}
