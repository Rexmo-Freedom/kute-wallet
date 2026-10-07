// lib/services/hardware/ledger/ledger_action_intent.dart
//
// A reviewed Ledger venue action (Wallet hardening Phase 3, plan B9).
//
// * The intent carries normalized parameters (base units, wire strings,
//   lowercase hex) and a display summary built at review time, plus a
//   SHA-256 `paramsHash` over their canonical JSON.
// * Executors rebuild the payload from the intent, never from live UI
//   state, and check the hash before any device prompt. Any change needs
//   a new intent and a new device signature.
// * It produces a Phase 1b `SensitiveIntent`-shaped draft with the same
//   canonical-JSON digest scheme (sorted keys, BigInt as a decimal string,
//   lowercase hex), so one review drives both app step-up and the device
//   prompt. Phase 1b types are not on this branch; the draft maps field
//   for field when they land.
//
// Digests are local only; never tracked or logged.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kute/services/hardware/signing_clarity.dart';

/// Thrown before any prompt when an intent's parameters do not hash to its
/// `paramsHash`, or the payload rebuilt from it differs from what would be
/// signed.
class LedgerIntentMismatchException implements Exception {
  const LedgerIntentMismatchException(this.reason);
  final String reason;

  @override
  String toString() => 'LedgerIntentMismatchException($reason)';
}

/// Canonical JSON: sorted map keys, no whitespace, BigInt as a decimal
/// string, 0x hex strings lowercased. Floating point is refused so a value
/// can never drift between review and signing.
String ledgerCanonicalJson(Object? value) {
  final out = StringBuffer();
  void write(Object? v) {
    if (v == null) {
      out.write('null');
    } else if (v is bool) {
      out.write(v ? 'true' : 'false');
    } else if (v is int) {
      out.write(v.toString());
    } else if (v is BigInt) {
      out.write(jsonEncode(v.toString()));
    } else if (v is String) {
      out.write(jsonEncode(_normalizeHex(v)));
    } else if (v is Map) {
      final keys = v.keys.map((k) {
        if (k is! String) throw ArgumentError('Map keys must be strings');
        return k;
      }).toList()
        ..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(jsonEncode(keys[i]));
        out.write(':');
        write(v[keys[i]]);
      }
      out.write('}');
    } else if (v is Iterable) {
      out.write('[');
      var first = true;
      for (final e in v) {
        if (!first) out.write(',');
        first = false;
        write(e);
      }
      out.write(']');
    } else if (v is double) {
      throw ArgumentError('Use base units or wire strings, not doubles');
    } else {
      throw ArgumentError('Unsupported canonical JSON value: ${v.runtimeType}');
    }
  }

  write(value);
  return out.toString();
}

String ledgerCanonicalDigest(Object? value) =>
    sha256.convert(utf8.encode(ledgerCanonicalJson(value))).toString();

String _normalizeHex(String s) =>
    RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(s) ? s.toLowerCase() : s;

Object? _freeze(Object? v) {
  if (v is Map) {
    return Map<String, Object?>.unmodifiable(
        {for (final e in v.entries) e.key as String: _freeze(e.value)});
  }
  if (v is Iterable) return List<Object?>.unmodifiable(v.map(_freeze));
  if (v is String) return _normalizeHex(v);
  if (v is double) {
    throw ArgumentError('Use base units or wire strings, not doubles');
  }
  return v;
}

/// The Phase 1b `SensitiveIntent` fields (draft :469-479), produced from a
/// Ledger intent. [action] is a Phase 1b `SensitiveAction` name.
/// [requiresStepUp] follows Phase 1 policy D-9: fresh authentication for
/// orders, sells and withdrawals; session only for
/// cancels, internal transfers, fixed-spender approvals, builder-fee
/// approval and wraps.
class LedgerSensitiveIntentDraft {
  const LedgerSensitiveIntentDraft({
    required this.action,
    required this.walletId,
    required this.venue,
    this.account,
    this.destination,
    required this.asset,
    required this.amountMax,
    this.limits = const {},
    this.ttl = const Duration(seconds: 60),
    required this.requiresStepUp,
  });

  final String action;
  final String walletId;
  final String venue;
  final String? account;
  final String? destination;
  final String asset;
  final BigInt amountMax;
  final Map<String, Object?> limits;
  final Duration ttl;
  final bool requiresStepUp;

  Map<String, Object?> toCanonicalMap() => {
        'action': action,
        'walletId': walletId,
        'venue': venue,
        'account': account,
        'destination': destination,
        'asset': asset,
        'amountMax': amountMax,
        'limits': limits,
        'ttlSeconds': ttl.inSeconds,
      };

  /// SHA-256 over canonical JSON, lowercase hex.
  String get digest => ledgerCanonicalDigest(toCanonicalMap());
}

class LedgerActionIntent {
  LedgerActionIntent._({
    required this.walletId,
    required this.kind,
    required this.params,
    required this.summary,
    required this.paramsHash,
    required this.createdAtMs,
    required this.sensitive,
  });

  /// Builds an intent at review time and computes its hash.
  factory LedgerActionIntent.create({
    required String walletId,
    required LedgerActionKind kind,
    required Map<String, Object?> params,
    required Map<String, String> summary,
    required LedgerSensitiveIntentDraft sensitive,
    DateTime? now,
  }) {
    final frozen = _freeze(params) as Map<String, Object?>;
    final frozenSummary = Map<String, String>.unmodifiable(summary);
    return LedgerActionIntent._(
      walletId: walletId,
      kind: kind,
      params: frozen,
      summary: frozenSummary,
      paramsHash: computeHash(
          walletId: walletId, kind: kind, params: frozen, summary: frozenSummary),
      createdAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
      sensitive: sensitive,
    );
  }

  /// Rebuilds a persisted intent with its stored hash. The executor
  /// re-verifies the hash, so a tampered or stale intent is refused.
  factory LedgerActionIntent.restore({
    required String walletId,
    required LedgerActionKind kind,
    required Map<String, Object?> params,
    required Map<String, String> summary,
    required String paramsHash,
    required int createdAtMs,
    required LedgerSensitiveIntentDraft sensitive,
  }) =>
      LedgerActionIntent._(
        walletId: walletId,
        kind: kind,
        params: _freeze(params) as Map<String, Object?>,
        summary: Map<String, String>.unmodifiable(summary),
        paramsHash: paramsHash,
        createdAtMs: createdAtMs,
        sensitive: sensitive,
      );

  final String walletId;
  final LedgerActionKind kind;
  final Map<String, Object?> params;
  final Map<String, String> summary;
  final String paramsHash;
  final int createdAtMs;
  final LedgerSensitiveIntentDraft sensitive;

  static String computeHash({
    required String walletId,
    required LedgerActionKind kind,
    required Map<String, Object?> params,
    required Map<String, String> summary,
  }) =>
      ledgerCanonicalDigest({
        'walletId': walletId,
        'kind': kind.name,
        'params': params,
        'summary': summary,
      });

  /// Throws [LedgerIntentMismatchException] unless the parameters still
  /// hash to [paramsHash] and the Phase 1b draft is bound to this wallet.
  void verify() {
    final recomputed = computeHash(
        walletId: walletId, kind: kind, params: params, summary: summary);
    if (recomputed != paramsHash) {
      throw const LedgerIntentMismatchException('params hash');
    }
    if (sensitive.walletId != walletId) {
      throw const LedgerIntentMismatchException('wallet');
    }
  }

  /// The Phase 1b `SensitiveIntent` for app step-up.
  LedgerSensitiveIntentDraft toSensitiveIntent() => sensitive;

  T param<T>(String name) {
    final v = params[name];
    if (v is! T) {
      throw LedgerIntentMismatchException('missing or invalid $name');
    }
    return v;
  }
}

/// Exact decimal string to base units. Refuses more fractional digits
/// than [decimals] instead of rounding.
BigInt decimalToBaseUnits(String value, int decimals) {
  final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(value.trim());
  if (m == null) throw ArgumentError('Not a positive decimal: $value');
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  if (frac.length > decimals) {
    throw ArgumentError('Too many decimals for $decimals: $value');
  }
  return BigInt.parse(whole + frac.padRight(decimals, '0'));
}
