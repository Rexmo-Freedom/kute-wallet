// lib/services/debug/settlement_fault_registry.dart
//
// One-shot settlement faults for the debug fault panel (Wallet hardening
// Phase 5 plan P5.17, owner B-DEBUG cases).
//
// * Every hook is inert unless `kDebugMode`. In a release build each hook
//   returns its input unchanged, the fault code is dead, and the panel
//   route does not exist.
// * Each fault fires once and disarms itself.
// * No fault pays anything or bypasses a guard. The deposit address,
//   amount and memo faults (X1, X2, X5) exist to prove the quote guard
//   rejects the quote: run them only from a wallet holding no more than the
//   route minimum, because a guard defect would send real funds.

import 'dart:convert';

import 'package:flutter/foundation.dart';

enum SettlementFault {
  quoteExpiresSoon('Force quote expiry in N seconds', 'Next quote'),
  alterDepositAddress(
      'Alter the deposit address (wrong format)', 'Next quote'),
  dropExpiresAt('Drop expiresAt', 'Next quote'),
  changeAmountIn('Change amountIn by one base unit', 'Next quote'),
  addMemo('Return a deposit memo', 'Next quote'),
  duplicateNextStatus(
      'Duplicate the next status response', 'Replayed on the read after'),
  failNextStatus503('Fail the next status read with 503', 'Nothing is sent'),
  throwAfterBroadcasting('Throw after broadcasting',
      'The payment call still runs; its proof is dropped'),
  returnUnfulfilled('Return unfulfilled', 'Next status read');

  const SettlementFault(this.label, this.detail);

  final String label;
  final String detail;
}

abstract final class SettlementFaults {
  /// Armed faults. The panel listens to this.
  static final ValueNotifier<Set<SettlementFault>> armed =
      ValueNotifier<Set<SettlementFault>>(const {});

  /// Seconds from now for [SettlementFault.quoteExpiresSoon].
  static int quoteExpirySeconds = 30;

  static final Map<String, Map<String, dynamic>> _pendingReplays = {};

  static void setArmed(SettlementFault fault, bool on) {
    if (!kDebugMode) return;
    final next = {...armed.value};
    if (on) {
      next.add(fault);
    } else {
      next.remove(fault);
    }
    armed.value = Set.unmodifiable(next);
  }

  static void disarmAll() {
    if (!kDebugMode) return;
    armed.value = const {};
    _pendingReplays.clear();
  }

  static bool _take(SettlementFault fault) {
    if (!kDebugMode || !armed.value.contains(fault)) return false;
    setArmed(fault, false);
    debugPrint('[settlement-fault] fired ${fault.name}');
    return true;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  /// Hook: a decoded quote response, before it is parsed and verified.
  static Map<String, dynamic> quoteBody(Map<String, dynamic> json) {
    if (!kDebugMode || armed.value.isEmpty) return json;
    final out = Map<String, dynamic>.of(json);
    if (_take(SettlementFault.quoteExpiresSoon)) {
      out['expiresAt'] = DateTime.now()
          .toUtc()
          .add(Duration(seconds: quoteExpirySeconds))
          .toIso8601String();
    }
    if (_take(SettlementFault.dropExpiresAt)) out.remove('expiresAt');
    if (_take(SettlementFault.alterDepositAddress)) {
      // One extra character: a wrong length or checksum on every chain,
      // never a different valid address.
      out['depositAddress'] = '${out['depositAddress'] ?? ''}0';
    }
    if (_take(SettlementFault.changeAmountIn)) {
      final current = BigInt.tryParse('${out['amountIn'] ?? ''}');
      out['amountIn'] = ((current ?? BigInt.zero) + BigInt.one).toString();
    }
    if (_take(SettlementFault.addMemo)) out['depositMemo'] = 'kute-debug';
    return out;
  }

  /// Hook: before a status read. True means answer with a 503 without
  /// sending the request.
  static bool takeStatusFailure() =>
      _take(SettlementFault.failNextStatus503);

  /// Hook: a decoded status response for [id], before it is parsed.
  static Map<String, dynamic> statusBody(
      String id, Map<String, dynamic> json) {
    if (!kDebugMode) return json;
    final replay = _pendingReplays.remove(id);
    if (replay != null) {
      debugPrint('[settlement-fault] replayed a duplicate status response');
      return replay;
    }
    if (armed.value.isEmpty) return json;
    var out = json;
    if (_take(SettlementFault.returnUnfulfilled)) {
      out = _copy(json);
      final order = out['order'];
      if (order is Map<String, dynamic>) {
        order['status'] = 'unfulfilled';
      } else {
        out['status'] = 'unfulfilled';
      }
    }
    if (_take(SettlementFault.duplicateNextStatus)) {
      _pendingReplays[id] = _copy(out);
    }
    return out;
  }

  /// Hook: right after the settlement runner's payment call returned.
  /// Throws once when armed, so the operation records `fundingUnknown`
  /// even though the payment went out.
  static void afterFund() {
    if (_take(SettlementFault.throwAfterBroadcasting)) {
      throw StateError('Debug fault: throw after broadcasting');
    }
  }
}
