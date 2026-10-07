// lib/services/funding/ledger_settlement.dart
//
// Phase 5 connection for the Ledger funding routes (Phase 4b, F22). The
// Ledger services do not keep their own route record or availability
// table; they use the Phase 5 pieces through this file:
//
//  - [FundingRouteAvailability]: the Phase 5 route availability query
//    (`OrchestraRoutesCatalog.availability`) with the live requirement for
//    Ledger wallets, a `bitcoin` or `hypercore` leg, or a versioned route.
//    A catalog older than `kMoneyCatalogMaxAge` forces one refresh; a
//    failed refresh leaves it `stale`.
//  - [LedgerSettlementRecords]: the Ledger flows' writes to
//    `SettlementStore`. The operation is created at `quoted`, moves through
//    `reviewed`, `authorizing` and `signed` (txid, vout and inputs), is at
//    `broadcasting` on disk before the broadcast or relayer call, and holds
//    its funding proof and submit key at `funded`. The Phase 5 reconciler
//    then picks it up like any hot operation (submit retries with the
//    persisted key, status polling, late deposits).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart'
    show orchestraSupportedRoutesProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_http.dart';
import 'package:kute/services/funding/settlement_reconciler.dart'
    show SubmitAttemptOutcome;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show VerifiedOrchestraQuote;
import 'package:kute/services/tracking_service.dart';

// ─────────────────────────────── scope ──────────────────────────────────

/// Runs a Ledger funding step inside [LedgerOperationScope] for [walletId]
/// (Phase 5 plan B12), so hot signing and seed entry points refuse to run
/// during it. The backend wallet session (Orchestra, the Polymarket relay)
/// is prepared BEFORE the scope starts, because minting one signs with the
/// hot wallet identity, which the scope refuses. A nested call, already
/// inside a scope, skips the preparation.
Future<T> runLedgerFundingScope<T>(
  String walletId,
  Future<T> Function() body, {
  Future<void> Function() prepareSession =
      AffiliateService.prepareSessionForLedgerOperation,
}) async {
  if (!LedgerOperationScope.isActive) {
    try {
      await prepareSession();
    } catch (_) {
      // Without a session the backend call inside fails closed with
      // WalletSessionUnavailable. Nothing signs with the hot identity.
    }
  }
  return LedgerOperationScope.run(walletId, body);
}

// ───────────────────────────── availability ─────────────────────────────

/// Whether money may move on a route now (Phase 5 plan B2).
abstract interface class FundingRouteAvailability {
  Future<RouteAvailability> availability(RouteKey route);
}

/// [FundingRouteAvailability] over the app's Orchestra route catalog.
class CatalogFundingRouteAvailability implements FundingRouteAvailability {
  CatalogFundingRouteAvailability(
    this._read, {
    required this.ledgerWallet,
    this.routeVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ProviderReader _read;
  final bool ledgerWallet;
  final String? routeVersion;
  final DateTime Function() _clock;

  @override
  Future<RouteAvailability> availability(RouteKey route) async {
    final req = routeRequirementFor(route,
        ledgerWallet: ledgerWallet, routeVersion: routeVersion);
    var catalog = _read(orchestraSupportedRoutesProvider);
    if (req == RouteRequirement.live) {
      try {
        catalog = await _read(orchestraSupportedRoutesProvider.notifier)
            .refreshIfOlderThan(kMoneyCatalogMaxAge);
      } catch (_) {
        // The stale copy answers `stale` below.
        catalog = _read(orchestraSupportedRoutesProvider);
      }
    }
    final result = catalog.availability(route, req: req, now: _clock());
    if (!result.isAvailable) {
      TrackingService.settlementRouteUnavailable(
          route: route.label, reason: result.reason!.code);
    }
    return result;
  }
}

/// Route availability for Ledger funding routes (always the live
/// requirement).
final ledgerFundingRouteAvailabilityProvider =
    Provider<FundingRouteAvailability>(
        (ref) => CatalogFundingRouteAvailability(ref.read, ledgerWallet: true));

// ─────────────────────────────── records ────────────────────────────────

/// Thrown when a Ledger operation record could not be written before a
/// step that needs it. Nothing moved at that point.
class LedgerSettlementWriteFailed implements Exception {
  const LedgerSettlementWriteFailed(this.code);

  final String code;

  @override
  String toString() => 'LedgerSettlementWriteFailed($code)';
}

/// The Ledger flows' writes to the Phase 5 settlement store.
class LedgerSettlementRecords {
  LedgerSettlementRecords({
    Future<SettlementStore> Function()? store,
    DateTime Function()? clock,
    String Function()? newId,
    SettlementSubmitCall submit = sendSettlementSubmit,
  })  : _store = store ?? SettlementStore.shared,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? OrchestraService.generateIdempotencyKey,
        _submit = submit;

  final Future<SettlementStore> Function() _store;
  final DateTime Function() _clock;
  final String Function() _newId;
  final SettlementSubmitCall _submit;

  final Map<String, Object> _leases = {};

  /// F4: the inputs of earlier Bitcoin fundings on [walletId] and [route]
  /// whose outcome is not known (`fundingUnknown`, `broadcasting`, or
  /// `signed` with no live flow). One group per operation. A new funding
  /// must spend at least one outpoint (`txid:vout`) of every group, so the
  /// two transactions conflict and at most one of them can confirm.
  Future<List<List<String>>> mustSpendOutpointsFor(
      String walletId, RouteKey route) async {
    final store = await _store();
    final groups = <List<String>>[];
    for (final op in await store.activeFor(walletId, route)) {
      final funding = op.funding;
      if (funding == null ||
          funding.kind != SettlementFundingKind.bitcoin ||
          funding.btcInputs.isEmpty) {
        continue;
      }
      final unresolved = op.stage == SettlementStage.fundingUnknown ||
          op.stage == SettlementStage.broadcasting ||
          (op.stage == SettlementStage.signed &&
              !store.isLeased(op.operationId));
      if (unresolved) groups.add(List.unmodifiable(funding.btcInputs));
    }
    return groups;
  }

  /// Persists the relayer transaction id as soon as the relayer accepted a
  /// batch, before any polling, so a kill while polling still leaves the
  /// id the reconciler probes. Best effort: the batch was already sent.
  Future<void> recordRelayerSubmitted(
      String operationId, String relayerTxId) async {
    try {
      final store = await _store();
      final op = await store.get(operationId);
      if (op == null) return;
      await store.update(
        operationId,
        stage: op.stage,
        expectedVersion: op.version,
        patch: (c) => c.copyWith(
          funding: (c.funding ??
                  const SettlementFunding(kind: SettlementFundingKind.relayer))
              .copyWith(
            kind: SettlementFundingKind.relayer,
            relayerTxId: relayerTxId,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Creates the operation at `quoted` for a verified [quote]. Refuses with
  /// [SettlementStopped] (`blockedPending`) while an earlier operation on
  /// the same wallet and route may have moved funds and is unresolved
  /// (F11). [quoteHistory] holds quotes this operation replaced before any
  /// funds moved.
  Future<SettlementOperation> start({
    required String walletId,
    required SettlementAccountKind accountKind,
    required SettlementFlow flow,
    required String routeVersion,
    required RouteKey route,
    required VerifiedOrchestraQuote quote,
    required SettlementAddressRef recipient,
    required SettlementAddressRef refund,
    Duration? skew,
    List<SettlementQuoteHistoryEntry> quoteHistory = const [],
  }) async {
    final store = await _store();
    final now = _clock();
    final created = await store.create(SettlementOperation(
      operationId: _newId(),
      walletId: walletId,
      accountKind: accountKind,
      flow: flow,
      routeVersion: routeVersion,
      route: route,
      amountInBaseUnits: quote.amountIn.toString(),
      quote: settlementQuoteTermsFor(quote, skew: skew ?? Duration.zero),
      quoteHistory: quoteHistory,
      recipient: recipient,
      refund: refund,
      stage: SettlementStage.quoted,
      createdAt: now,
      updatedAt: now,
    ));
    TrackingService.settlementOperationStarted(
      flow: flow.code,
      routeVersion: routeVersion,
      amountUsd: null,
    );
    return created;
  }

  Future<SettlementOperation?> get(String operationId) async =>
      (await _store()).get(operationId);

  /// Marks [operationId] as owned by a live flow in this process, so the
  /// reconciler does not act on it at `signed` or below. Idempotent.
  Future<void> hold(String operationId) async {
    if (_leases.containsKey(operationId)) return;
    final token = (await _store()).acquireLease(operationId);
    if (token != null) _leases[operationId] = token;
  }

  Future<void> release(String operationId) async {
    final token = _leases.remove(operationId);
    if (token == null) return;
    (await _store()).releaseLease(operationId, token);
  }

  /// Moves [operationId] from its current stage to [to]. Throws
  /// [LedgerSettlementWriteFailed] when the record is missing, changed
  /// meanwhile, or the move is not in the stage graph.
  Future<SettlementOperation> advance(
    String operationId,
    SettlementStage to, {
    SettlementOperation Function(SettlementOperation current)? patch,
  }) async {
    final store = await _store();
    final current = await store.get(operationId);
    if (current == null) {
      throw const LedgerSettlementWriteFailed('record_missing');
    }
    final write = await store.transition(
      operationId,
      to,
      from: current.stage,
      expectedVersion: current.version,
      patch: patch,
    );
    final written = write.operation;
    if (!write.applied || written == null) {
      throw LedgerSettlementWriteFailed(write.status.name);
    }
    return written;
  }

  /// [advance] after funds may have moved: a failed write never stops the
  /// flow, and the reconciler still sees the last written stage.
  Future<SettlementOperation?> advanceBestEffort(
    String operationId,
    SettlementStage to, {
    SettlementOperation Function(SettlementOperation current)? patch,
  }) async {
    try {
      return await advance(operationId, to, patch: patch);
    } catch (_) {
      return null;
    }
  }

  /// `signed`: the device signature is held in memory; the txid, deposit
  /// output and inputs are on disk before any broadcast.
  Future<SettlementOperation> recordSigned(
    String operationId, {
    required String txid,
    required int vout,
    required List<String> inputs,
  }) =>
      advance(
        operationId,
        SettlementStage.signed,
        patch: (c) => c.copyWith(
          funding: SettlementFunding(
            kind: SettlementFundingKind.bitcoin,
            btcTxid: txid.trim().toLowerCase(),
            btcVout: vout,
            btcInputs: inputs,
          ),
        ),
      );

  /// `funded` with the proof, a new submit key and the late flag. Best
  /// effort: funds already moved.
  Future<SettlementOperation?> recordFunded(
    String operationId,
    SettlementFunding proof,
  ) {
    final fundedAt = _clock();
    return advanceBestEffort(
      operationId,
      SettlementStage.funded,
      patch: (c) {
        final quote = c.quote;
        final previous = c.funding;
        return c.copyWith(
          funding: previous == null
              ? proof
              : previous.copyWith(
                  kind: proof.kind,
                  btcTxid: proof.btcTxid,
                  btcVout: proof.btcVout,
                  btcInputs:
                      proof.btcInputs.isEmpty ? null : proof.btcInputs,
                  evmTxHash: proof.evmTxHash,
                  relayerTxId: proof.relayerTxId,
                  hlNonce: proof.hlNonce,
                  hlActionHash: proof.hlActionHash,
                ),
          keys: c.submitKeys == null
              ? c.keysWithSubmit(SubmitIdempotencyKeys.create())
              : c.keys,
          late: quote == null
              ? c.late
              : SettlementLate(
                  quoteExpiredBeforeFunding:
                      fundedAt.add(quote.skew).isAfter(quote.expiresAt),
                ),
        );
      },
    );
  }

  /// One `submitDeposit` with the persisted key and the recorded proof.
  /// Never throws; a failed submit stays `funded` for the reconciler.
  Future<({bool accepted, String? orderId})> submit(String operationId) async {
    try {
      final store = await _store();
      final op = await store.get(operationId);
      if (op == null) return (accepted: false, orderId: null);
      if (op.stage == SettlementStage.submitted) {
        return (accepted: true, orderId: op.orderId);
      }
      if (op.stage != SettlementStage.funded) {
        return (accepted: false, orderId: null);
      }
      final result = await submitSettlementDeposit(store, op,
          submit: _submit, clock: _clock);
      final accepted = result.outcome == SubmitAttemptOutcome.accepted;
      TrackingService.settlementFundingRecorded(
          flow: op.flow.code, fundingKind: op.funding?.kind?.name ?? 'unknown');
      return (accepted: accepted, orderId: result.orderId);
    } catch (_) {
      return (accepted: false, orderId: null);
    }
  }

  /// Ends an operation that never reached `broadcasting`: the signature (if
  /// any) was discarded and nothing was sent. A record that did reach it is
  /// left for the reconciler.
  Future<void> abandon(String operationId) async {
    try {
      final store = await _store();
      final op = await store.get(operationId);
      if (op == null || op.everBroadcast || !op.stage.isBeforeBroadcasting) {
        return;
      }
      await store.transition(operationId, SettlementStage.abandoned,
          from: op.stage, expectedVersion: op.version);
    } catch (_) {
      // A record left below broadcasting is abandoned by the reconciler
      // after its quote expires.
    } finally {
      await release(operationId);
    }
  }
}

final ledgerSettlementRecordsProvider =
    Provider<LedgerSettlementRecords>((ref) => LedgerSettlementRecords());
