import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_bet_target.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_placement.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';

/// Only an exact reviewed intent may reconcile a pending draft leg. These
/// session drafts do not survive restart; the durable executor journal does.
final ledgerBuilderPendingIntentsProvider =
    StateProvider.family<Map<String, LedgerBuilderPendingLeg>, String>(
        (ref, walletId) => const {});

class LedgerBuilderPendingLeg {
  const LedgerBuilderPendingLeg(this.leg, this.intent);
  final PredictionBuilderLeg leg;
  final LedgerActionIntent intent;

  bool matches(PredictionBuilderLeg current) =>
      current.key == leg.key &&
      current.tokenId == leg.tokenId &&
      current.conditionId == leg.conditionId &&
      current.price == leg.price &&
      current.amountUsd == leg.amountUsd &&
      current.marketEndAt == leg.marketEndAt;
}

Future<BuilderLegResult> placeLedgerBuilderLeg(
  BuildContext context,
  WidgetRef ref,
  PredictionBuilderLeg leg, {
  required String walletId,
}) async {
  final l10n = context.l10n;
  final pending = ref.read(ledgerBuilderPendingIntentsProvider(walletId));
  if (pending.containsKey(leg.key)) {
    return BuilderLegResult.paused(l10n.builderOrderStatusPending);
  }
  if (leg.tokenId?.isNotEmpty != true ||
      leg.conditionId?.isNotEmpty != true ||
      !leg.price.isFinite ||
      leg.price <= 0 ||
      leg.price >= 1 ||
      !leg.amountUsd.isFinite ||
      leg.amountUsd <= 0 ||
      (leg.marketEndAt != null && !DateTime.now().isBefore(leg.marketEndAt!))) {
    return BuilderLegResult.paused(l10n.ledgerBetDetailsChanged);
  }
  LedgerBuilderPendingLeg? owned;
  final outcome = await showLedgerPredictionApproval(
    context,
    ref,
    walletId: walletId,
    tokenId: leg.tokenId!,
    conditionId: leg.conditionId!,
    amountUsd: leg.amountUsd,
    reviewedPrice: leg.price,
    isLimit: false,
    slippagePct: 1,
    marketQuestion: leg.title,
    outcomeLabel: leg.outcomeName,
    marketEndAt: leg.marketEndAt,
    onOrderIntent: (intent) {
      final state = ref.read(ledgerBuilderPendingIntentsProvider(walletId));
      owned = LedgerBuilderPendingLeg(leg, intent);
      ref.read(ledgerBuilderPendingIntentsProvider(walletId).notifier).state = {
        ...state,
        leg.key: owned!
      };
    },
  );
  if (!context.mounted) return BuilderLegResult.paused(l10n.builderRunPaused);
  final expected = owned;
  if (outcome == LedgerPmBetOutcome.submitted && expected != null) {
    clearLedgerBuilderPending(ref, walletId, leg.key, expected: expected);
    return const BuilderLegResult.ok();
  }
  if (expected != null) {
    // A record is written before any POST and this wallet's approvals run one
    // at a time, so a hash with no record was never sent. A failed journal
    // read remains uncertain. Never discard its exact binding on an error.
    try {
      final store = ref.read(ledgerSubmittedActionStoreProvider);
      final records = await store.forWallet(walletId);
      final hasOwnRecord = records.any((record) =>
          record.walletId == walletId &&
          record.paramsHash == expected.intent.paramsHash);
      if (context.mounted && !hasOwnRecord) {
        clearLedgerBuilderPending(ref, walletId, leg.key, expected: expected);
      }
    } catch (_) {}
  }
  return BuilderLegResult.paused(outcome == LedgerPmBetOutcome.prepared
      ? l10n.ledgerBetPrepared
      : outcome == LedgerPmBetOutcome.pending
          ? l10n.builderOrderStatusPending
          : l10n.builderRunPaused);
}

bool clearLedgerBuilderPending(WidgetRef ref, String walletId, String key,
    {required LedgerBuilderPendingLeg expected}) {
  final current = ref.read(ledgerBuilderPendingIntentsProvider(walletId));
  if (!identical(current[key], expected)) return false;
  final next = {...current}..remove(key);
  ref.read(ledgerBuilderPendingIntentsProvider(walletId).notifier).state = next;
  return true;
}
