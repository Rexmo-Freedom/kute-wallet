// lib/services/one_balance/venue_readiness.dart
//
// The venue's readiness for a queued funded order, as the autofire walks
// it, in the words the step graph's readiness sub-steps follow
// (`kReadinessPhases`): Predictions `waiting` → `converting` (USDC.e to
// pUSD) → `approving` (the spend allowance, only when needed) →
// `confirming` (the venue's own balance view covers the order) → `ready`;
// Investing `waiting` → `crediting` (the money is where the order draws
// from) → `ready`. The order going to `placing` is `ready` too. Reads
// only.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show
        HlReadiness,
        PendingHlOrderIntent,
        PendingHlOrderStatus,
        pendingHyperliquidOrderProvider;
import 'package:kute/providers/pending_polymarket_bet_provider.dart'
    show
        PendingBetIntent,
        PendingBetStatus,
        PredictionsReadiness,
        pendingPolymarketBetProvider;
import 'package:kute/services/one_balance/one_balance_state.dart';

/// The phase of a queued Predictions bet, or null when it says nothing.
String? predictionsPhaseOf(PendingBetIntent? intent) {
  if (intent == null) return null;
  switch (intent.status) {
    case PendingBetStatus.placing:
    case PendingBetStatus.done:
    case PendingBetStatus.awaitingConfirmation:
      // A wait after a "not enough balance" keeps the bet placing while
      // its readiness drops back: the readiness says where it is.
      final r = intent.readiness;
      if (r != null && r != PredictionsReadiness.ready) return _pm(r);
      return 'ready';
    case PendingBetStatus.awaitingBalance:
      final r = intent.readiness;
      return r == null ? 'waiting' : _pm(r);
    case PendingBetStatus.awaitingDeposit:
    case PendingBetStatus.converting:
    case PendingBetStatus.failed:
      return null;
  }
}

String _pm(PredictionsReadiness r) => switch (r) {
      PredictionsReadiness.waitingFunds => 'waiting',
      PredictionsReadiness.converting => 'converting',
      PredictionsReadiness.approving => 'approving',
      PredictionsReadiness.confirming => 'confirming',
      PredictionsReadiness.ready => 'ready',
    };

/// The phase of a queued Investing order, or null when it says nothing.
String? investingPhaseOf(PendingHlOrderIntent? intent) {
  if (intent == null) return null;
  switch (intent.status) {
    case PendingHlOrderStatus.placing:
    case PendingHlOrderStatus.done:
      final r = intent.readiness;
      if (r == HlReadiness.crediting) return 'crediting';
      return 'ready';
    case PendingHlOrderStatus.awaitingBalance:
      return switch (intent.readiness) {
        HlReadiness.crediting => 'crediting',
        HlReadiness.ready => 'ready',
        _ => 'waiting',
      };
    case PendingHlOrderStatus.awaitingDeposit:
    case PendingHlOrderStatus.failed:
      return null;
  }
}

/// Every new phase of the queued order on [venue], the current one first.
Stream<String> readinessPhasesOf(Ref ref, OneBalanceVenue venue) {
  late final StreamController<String> controller;
  ProviderSubscription<Object?>? sub;
  String? last;
  void emit(String? phase) {
    if (phase == null || phase == last || controller.isClosed) return;
    last = phase;
    controller.add(phase);
  }

  controller = StreamController<String>(
    onListen: () {
      switch (venue) {
        case OneBalanceVenue.predictions:
          sub = ref.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
              (_, next) => emit(predictionsPhaseOf(next)),
              fireImmediately: true);
        case OneBalanceVenue.investing:
          sub = ref.listen<PendingHlOrderIntent?>(
              pendingHyperliquidOrderProvider,
              (_, next) => emit(investingPhaseOf(next)),
              fireImmediately: true);
      }
    },
    onCancel: () => sub?.close(),
  );
  return controller.stream;
}
