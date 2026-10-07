// lib/services/hardware/ledger/ledger_submitted_action_store.dart
//
// Submitted-action records for Ledger venue actions (Wallet hardening
// Phase 3, plan B9).
//
// A record is written AFTER the device signed and BEFORE the request is
// POSTed, so a crash, timeout or dropped connection can never leave a
// signed action with no trace. A timeout moves the record to
// `submittedUnknown`; reconciliation reads venue state (Hyperliquid
// `orderStatus` or non-funding ledger updates, the Polymarket order ID, or
// the relayer transaction) and never re-signs or resubmits.
//
// Local only, public data only: kinds, nonces, client order IDs, order
// hashes and relayer IDs. No signatures, no API credentials, no amounts.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

enum LedgerSubmissionStage {
  /// Signed; the POST is about to start or in flight.
  submitting,

  /// The venue accepted the request.
  accepted,

  /// The venue rejected the request. Nothing further happens.
  rejected,

  /// The POST started but no answer arrived (timeout or network). The
  /// action may or may not have landed; only reconciliation decides.
  submittedUnknown,

  /// Reconciliation found the action on the venue.
  confirmed,

  /// The venue answered with an order ID that differs from the one
  /// computed before the POST.
  orderIdMismatch,
}

class LedgerSubmittedAction {
  const LedgerSubmittedAction({
    required this.id,
    required this.walletId,
    required this.kind,
    required this.paramsHash,
    required this.stage,
    required this.submittedAtMs,
    this.updatedAtMs,
    this.nonce,
    this.cloid,
    this.orderId,
    this.relayerNonce,
    this.relayerTxId,
    this.oid,
    this.notAccepted = false,
  });

  final String id;
  final String walletId;

  /// `LedgerActionKind.name`.
  final String kind;
  final String paramsHash;
  final LedgerSubmissionStage stage;
  final int submittedAtMs;
  final int? updatedAtMs;

  /// Hyperliquid nonce (ms) of the signed action.
  final int? nonce;

  /// Hyperliquid client order ID, for `orderStatus` reconciliation.
  final String? cloid;

  /// Polymarket Exchange-domain order hash.
  final String? orderId;

  /// Polymarket relayer WALLET nonce the batch signature commits to.
  final String? relayerNonce;
  final String? relayerTxId;

  /// Hyperliquid order ID once known.
  final int? oid;

  /// Explicit refusal or cancellation before POST, never inferred from timeout.
  /// Older records omit this proof and must still reconcile with the venue.
  final bool notAccepted;

  LedgerSubmittedAction copyWith({
    LedgerSubmissionStage? stage,
    int? updatedAtMs,
    String? relayerTxId,
    int? oid,
    bool? notAccepted,
  }) =>
      LedgerSubmittedAction(
        id: id,
        walletId: walletId,
        kind: kind,
        paramsHash: paramsHash,
        stage: stage ?? this.stage,
        submittedAtMs: submittedAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        nonce: nonce,
        cloid: cloid,
        orderId: orderId,
        relayerNonce: relayerNonce,
        relayerTxId: relayerTxId ?? this.relayerTxId,
        oid: oid ?? this.oid,
        notAccepted: notAccepted ?? this.notAccepted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'walletId': walletId,
        'kind': kind,
        'paramsHash': paramsHash,
        'stage': stage.name,
        'submittedAtMs': submittedAtMs,
        if (updatedAtMs != null) 'updatedAtMs': updatedAtMs,
        if (nonce != null) 'nonce': nonce,
        if (cloid != null) 'cloid': cloid,
        if (orderId != null) 'orderId': orderId,
        if (relayerNonce != null) 'relayerNonce': relayerNonce,
        if (relayerTxId != null) 'relayerTxId': relayerTxId,
        if (oid != null) 'oid': oid,
        if (notAccepted) 'notAccepted': true,
      };

  static LedgerSubmittedAction? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final stageName = raw['stage'];
    final stage = LedgerSubmissionStage.values
        .where((s) => s.name == stageName)
        .firstOrNull;
    final id = raw['id'], walletId = raw['walletId'], kind = raw['kind'];
    final hash = raw['paramsHash'], at = raw['submittedAtMs'];
    if (stage == null ||
        id is! String ||
        walletId is! String ||
        kind is! String ||
        hash is! String ||
        at is! int || (raw['notAccepted'] != null && raw['notAccepted'] is! bool)) {
      return null;
    }
    return LedgerSubmittedAction(
      id: id,
      walletId: walletId,
      kind: kind,
      paramsHash: hash,
      stage: stage,
      submittedAtMs: at,
      updatedAtMs: raw['updatedAtMs'] as int?,
      nonce: raw['nonce'] as int?,
      cloid: raw['cloid'] as String?,
      orderId: raw['orderId'] as String?,
      relayerNonce: raw['relayerNonce'] as String?,
      relayerTxId: raw['relayerTxId'] as String?,
      oid: raw['oid'] as int?,
      notAccepted: raw['notAccepted'] == true,
    );
  }
}

class LedgerSubmittedActionStore {
  LedgerSubmittedActionStore({
    Future<Box<String>> Function()? openBox,
    DateTime Function()? clock,
  })  : _openBox = openBox ?? (() => Hive.openBox<String>(boxName)),
        _clock = clock ?? DateTime.now;

  static const String boxName = 'ledger_submitted_actions';
  static final Set<String> _failedPolymarketWrites = {};
  static final Map<String, String> _acknowledgedPolymarketActions = {};

  final Future<Box<String>> Function() _openBox;
  final DateTime Function() _clock;

  static String _key(String walletId, String id) => '$walletId|$id';

  /// Writes and flushes [action] before the caller starts the POST.
  Future<void> recordBeforeSubmit(LedgerSubmittedAction action) async {
    final box = await _openBox();
    await _write(box, action);
  }

  Future<void> _write(Box<String> box, LedgerSubmittedAction action) async {
    final key = _key(action.walletId, action.id);
    final polymarketAction =
        action.id.startsWith('pm-batch-') || action.id.startsWith('pm-order-');
    if (polymarketAction) _acknowledgedPolymarketActions.remove(key);
    final encoded = jsonEncode(action.toJson());
    try {
      await box.put(key, encoded);
      await box.flush();
      _failedPolymarketWrites.remove(key);
      if (polymarketAction &&
          (action.stage == LedgerSubmissionStage.confirmed ||
              action.stage == LedgerSubmissionStage.rejected ||
              (action.id.startsWith('pm-order-') &&
                  action.stage == LedgerSubmissionStage.accepted))) {
        _acknowledgedPolymarketActions[key] = encoded;
      }
    } catch (_) {
      // Hive's cache can contain a terminal stage even when flush failed.
      // Do not let another executor mistake that cached write for resolution.
      if (polymarketAction) _failedPolymarketWrites.add(key);
      rethrow;
    }
  }

  /// Fail closed for direct Ledger batches, including records from an older
  /// app. Unlike a history listing, malformed records cannot be skipped here.
  Future<LedgerSubmittedAction?> blockingPolymarketBatch(
      String walletId) async {
    final box = await _openBox();
    LedgerSubmittedAction? latestTerminal;
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('$walletId|pm-batch-')) continue;
      final action =
          LedgerSubmittedAction.tryFromJson(jsonDecode(box.get(key)!));
      if (action == null ||
          action.walletId != walletId ||
          key != _key(walletId, action.id)) {
        throw const FormatException('Unreadable pending Polymarket batch.');
      }
      if (_failedPolymarketWrites.contains(key) ||
          (action.stage != LedgerSubmissionStage.confirmed &&
              action.stage != LedgerSubmissionStage.rejected)) {
        return action;
      }
      final previous = latestTerminal;
      final nonce = BigInt.tryParse(action.relayerNonce ?? '');
      final previousNonce = BigInt.tryParse(previous?.relayerNonce ?? '');
      if (previous == null ||
          (nonce != null && previousNonce != null
              ? nonce > previousNonce
              : action.submittedAtMs > previous.submittedAtMs)) {
        latestTerminal = action;
      }
    }
    // After restart, surface the latest recorded outcome once before allowing
    // another transfer. A terminal write may have reached disk even if flush
    // threw or the process died before the caller could show the result.
    if (latestTerminal != null &&
        _acknowledgedPolymarketActions[_key(walletId, latestTerminal.id)] !=
            jsonEncode(latestTerminal.toJson())) {
      return latestTerminal;
    }
    return null;
  }

  Future<LedgerSubmittedAction?> get(String walletId, String id) async {
    final box = await _openBox();
    final raw = box.get(_key(walletId, id));
    if (raw == null) return null;
    try {
      return LedgerSubmittedAction.tryFromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Unknown orders block a new purchase even after the ticket or app closes.
  /// A terminal result from a previous process is surfaced once: its caller
  /// may have died before learning that the order was accepted.
  Future<LedgerSubmittedAction?> blockingPolymarketOrder(
      String walletId) async {
    final box = await _openBox();
    LedgerSubmittedAction? latestTerminal;
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('$walletId|pm-order-')) continue;
      final action =
          LedgerSubmittedAction.tryFromJson(jsonDecode(box.get(key)!));
      if (action == null ||
          action.walletId != walletId ||
          key != _key(walletId, action.id) ||
          action.orderId == null) {
        throw const FormatException('Unreadable pending prediction.');
      }
      if (_failedPolymarketWrites.contains(key) ||
          !const {
            LedgerSubmissionStage.accepted,
            LedgerSubmissionStage.confirmed,
            LedgerSubmissionStage.rejected
          }.contains(action.stage)) {
        return action;
      }
      if (latestTerminal == null ||
          action.submittedAtMs > latestTerminal.submittedAtMs) {
        latestTerminal = action;
      }
    }
    if (latestTerminal != null &&
        _acknowledgedPolymarketActions[_key(walletId, latestTerminal.id)] !=
            jsonEncode(latestTerminal.toJson())) {
      return latestTerminal;
    }
    return null;
  }

  Future<LedgerSubmittedAction?> updateStage(
    String walletId,
    String id,
    LedgerSubmissionStage stage, {
    String? relayerTxId,
    int? oid,
    bool? notAccepted,
  }) async {
    final current = await get(walletId, id);
    if (current == null) return null;
    final next = current.copyWith(
      stage: stage,
      updatedAtMs: _clock().millisecondsSinceEpoch,
      relayerTxId: relayerTxId,
      oid: oid,
      notAccepted: notAccepted,
    );
    final box = await _openBox();
    await _write(box, next);
    return next;
  }

  Future<List<LedgerSubmittedAction>> forWallet(String walletId) async {
    final box = await _openBox();
    final out = <LedgerSubmittedAction>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('$walletId|')) continue;
      try {
        final a = LedgerSubmittedAction.tryFromJson(jsonDecode(box.get(key)!));
        if (a != null) out.add(a);
      } catch (_) {}
    }
    out.sort((a, b) => a.submittedAtMs.compareTo(b.submittedAtMs));
    return out;
  }

  Future<void> clearWallet(String walletId) async {
    final box = await _openBox();
    final keys = box.keys
        .where((k) => k is String && k.startsWith('$walletId|'))
        .toList();
    if (keys.isNotEmpty) await box.deleteAll(keys);
  }
}
