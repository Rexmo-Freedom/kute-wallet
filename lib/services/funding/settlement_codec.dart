// lib/services/funding/settlement_codec.dart
//
// Hand-written map codec for SettlementOperation (Phase 5 plan B6). No
// Hive type id and no generated adapter: records are JSON maps, known
// fields are written over the map the record was read from, so fields a
// newer build added survive a downgrade. Timestamps are milliseconds
// since epoch under `...Ms` keys; amounts stay decimal strings.

import 'dart:convert';

import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_stage.dart';

/// A record that cannot be decoded. [field] names the first bad path.
class SettlementCodecException implements Exception {
  const SettlementCodecException(this.field);

  final String field;

  @override
  String toString() => 'SettlementCodecException($field)';
}

/// Marks a known field whose on-disk value must stay as it is (an enum
/// value written by a newer build).
const Object _keep = Object();

const int _maxEpochMs = 8640000000000000;
final RegExp _digits = RegExp(r'^\d+$');

class _Reader {
  _Reader(this.map, [this.path = '']);

  final Map<String, Object?> map;
  final String path;

  Never fail(String key) => throw SettlementCodecException('$path$key');

  String str(String key) {
    final v = map[key];
    if (v is String) return v;
    fail(key);
  }

  String? optStr(String key) {
    final v = map[key];
    if (v == null || v is String) return v as String?;
    fail(key);
  }

  int integer(String key) {
    final v = map[key];
    if (v is int) return v;
    fail(key);
  }

  int? optInt(String key) {
    final v = map[key];
    if (v == null || v is int) return v as int?;
    fail(key);
  }

  bool? optBool(String key) {
    final v = map[key];
    if (v == null || v is bool) return v as bool?;
    fail(key);
  }

  DateTime ms(String key) {
    final v = integer(key);
    if (v.abs() > _maxEpochMs) fail(key);
    return DateTime.fromMillisecondsSinceEpoch(v);
  }

  DateTime? optMs(String key) => map[key] == null ? null : ms(key);

  _Reader? optObj(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is Map) return _Reader(Map<String, Object?>.from(v), '$path$key.');
    fail(key);
  }

  _Reader obj(String key) => optObj(key) ?? fail(key);

  List<Object?> list(String key) {
    final v = map[key];
    if (v == null) return const [];
    if (v is List) return v;
    fail(key);
  }

  List<String> strings(String key) {
    final out = <String>[];
    for (final item in list(key)) {
      if (item is! String) fail(key);
      out.add(item);
    }
    return List.unmodifiable(out);
  }
}

class SettlementCodec {
  SettlementCodec._();

  static String encodeJson(SettlementOperation op) => jsonEncode(encode(op));

  static SettlementOperation decodeJson(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      throw const SettlementCodecException('json');
    }
    if (parsed is! Map) throw const SettlementCodecException('root');
    return decode(Map<String, Object?>.from(parsed));
  }

  /// The `schema` of a stored record, or null when unreadable.
  static int? peekSchema(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['schema'] is int) {
        return parsed['schema'] as int;
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────── encode ───────────────────────────────

  static Map<String, Object?> encode(SettlementOperation op) {
    final known = <String, Object?>{
      'schema': op.schema < kSettlementSchemaVersion
          ? kSettlementSchemaVersion
          : op.schema,
      'operationId': op.operationId,
      'walletId': op.walletId,
      'accountKind': op.accountKind == SettlementAccountKind.unknown
          ? _keep
          : op.accountKind.name,
      'flow': op.flow == SettlementFlow.unknown ? _keep : op.flow.name,
      'routeVersion': op.routeVersion,
      'from': <String, Object?>{
        'chain': op.route.fromChain,
        'asset': op.route.fromAsset,
      },
      'to': <String, Object?>{
        'chain': op.route.toChain,
        'asset': op.route.toAsset,
      },
      'amountInBaseUnits': op.amountInBaseUnits,
      'quote': op.quote == null ? null : _quote(op.quote!),
      'quoteHistory': [
        for (final e in op.quoteHistory)
          {
            'quoteId': e.quoteId,
            'reason': e.reason,
            'supersededAtMs': e.supersededAt.millisecondsSinceEpoch,
          },
      ],
      'recipient': op.recipient == null ? null : _address(op.recipient!),
      'refund': op.refund == null ? null : _address(op.refund!),
      'keys': <String, Object?>{
        'quote': op.keys.quote,
        'submit': op.keys.submit,
        'submitHistory': op.keys.submitHistory,
        'submitFingerprint': op.keys.submitFingerprint,
      },
      'stage': op.stage.name,
      'stageHistory': [
        for (final e in op.stageHistory)
          {'stage': e.stage.name, 'atMs': e.at.millisecondsSinceEpoch},
      ],
      'funding': op.funding == null ? null : _funding(op.funding!),
      'orderId': op.orderId,
      'submit': <String, Object?>{
        'attempts': op.submit.attempts,
        'lastAttemptAtMs': op.submit.lastAttemptAt?.millisecondsSinceEpoch,
        'lastErrorCode': op.submit.lastErrorCode,
        'acceptedAtMs': op.submit.acceptedAt?.millisecondsSinceEpoch,
        'providerDetected': op.submit.providerDetected,
      },
      'poll': <String, Object?>{
        'providerStatus': op.poll.providerStatus,
        'mappedStatus': op.poll.mappedStatus,
        'lastCheckedAtMs': op.poll.lastCheckedAt?.millisecondsSinceEpoch,
        'consecutiveFailures': op.poll.consecutiveFailures,
        'nextCheckAtMs': op.poll.nextCheckAt?.millisecondsSinceEpoch,
        'sdkSyncsSinceBroadcasting': op.poll.sdkSyncsSinceBroadcasting,
        'lastSdkSyncGeneration': op.poll.lastSdkSyncGeneration,
      },
      'late': op.late == null
          ? null
          : <String, Object?>{
              'quoteExpiredBeforeFunding': op.late!.quoteExpiredBeforeFunding,
              'detectedAtMs': op.late!.detectedAt?.millisecondsSinceEpoch,
            },
      'refundObserved': op.refundObserved == null
          ? null
          : <String, Object?>{
              'atMs': op.refundObserved!.at?.millisecondsSinceEpoch,
              'txRef': op.refundObserved!.txRef,
            },
      'recoveredFrom': op.recoveredFrom,
      'createdAtMs': op.createdAt.millisecondsSinceEpoch,
      'updatedAtMs': op.updatedAt.millisecondsSinceEpoch,
      'terminalAtMs': op.terminalAt?.millisecondsSinceEpoch,
      'version': op.version,
    };
    return _merge(op.raw, known);
  }

  static Map<String, Object?> _quote(SettlementQuoteTerms q) => {
        'quoteId': q.quoteId,
        'depositAddress': q.depositAddress,
        'amountIn': q.amountIn,
        'estimatedOut': q.estimatedOut,
        'lockedMinAmountOut': q.lockedMinAmountOut,
        'feeBps': q.feeBps,
        'totalFeeAmount': q.totalFeeAmount,
        'feeAsset': q.feeAsset,
        'priceLockMode': q.priceLockMode,
        'expiresAtMs': q.expiresAt.millisecondsSinceEpoch,
        'skewMs': q.skew.inMilliseconds,
        'readToken': q.readToken,
      };

  static Map<String, Object?> _address(SettlementAddressRef a) => {
        'address': a.address,
        'kind': a.kind == OwnedAddressKind.unknown ? _keep : a.kind.name,
        'index': a.index,
        'deviceVerifiedAtMs': a.deviceVerifiedAt?.millisecondsSinceEpoch,
      };

  static Map<String, Object?> _funding(SettlementFunding f) => {
        'kind': f.kind?.name ?? _keep,
        'sparkPaymentId': f.sparkPaymentId,
        'btcTxid': f.btcTxid,
        'btcVout': f.btcVout,
        'btcInputs': f.btcInputs.isEmpty ? null : f.btcInputs,
        'evmTxHash': f.evmTxHash,
        'relayerTxId': f.relayerTxId,
        'hlNonce': f.hlNonce,
        'hlActionHash': f.hlActionHash,
      };

  /// Writes [known] over [raw]. A null known value removes the key, a
  /// [_keep] value leaves the raw value, and nested maps merge.
  static Map<String, Object?> _merge(
      Map<String, Object?> raw, Map<String, Object?> known) {
    final out = <String, Object?>{};
    raw.forEach((k, v) => out[k] = v);
    known.forEach((key, value) {
      if (identical(value, _keep)) return;
      if (value == null) {
        out.remove(key);
        return;
      }
      final existing = out[key];
      if (value is Map<String, Object?> && existing is Map) {
        out[key] = _merge(Map<String, Object?>.from(existing), value);
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  // ─────────────────────────────── decode ───────────────────────────────

  static SettlementOperation decode(Map<String, Object?> map) {
    final r = _Reader(map);
    final schema = r.integer('schema');
    if (schema < 1) r.fail('schema');

    final operationId = r.str('operationId');
    if (operationId.trim().isEmpty) r.fail('operationId');

    final from = r.obj('from');
    final to = r.obj('to');
    final route = RouteKey(
      fromChain: from.str('chain'),
      fromAsset: from.str('asset'),
      toChain: to.str('chain'),
      toAsset: to.str('asset'),
    );

    final amount = r.str('amountInBaseUnits');
    if (!_digits.hasMatch(amount)) r.fail('amountInBaseUnits');

    final stage = SettlementStage.fromName(r.str('stage')) ?? r.fail('stage');

    final quoteReader = r.optObj('quote');
    final SettlementQuoteTerms? quote;
    if (quoteReader == null) {
      quote = null;
    } else {
      final amountIn = quoteReader.str('amountIn');
      if (!_digits.hasMatch(amountIn)) quoteReader.fail('amountIn');
      quote = SettlementQuoteTerms(
        quoteId: quoteReader.str('quoteId'),
        depositAddress: quoteReader.str('depositAddress'),
        amountIn: amountIn,
        estimatedOut: quoteReader.str('estimatedOut'),
        lockedMinAmountOut: quoteReader.optStr('lockedMinAmountOut'),
        feeBps: quoteReader.integer('feeBps'),
        totalFeeAmount: quoteReader.optStr('totalFeeAmount'),
        feeAsset: quoteReader.optStr('feeAsset'),
        priceLockMode: quoteReader.optStr('priceLockMode'),
        expiresAt: quoteReader.ms('expiresAtMs'),
        skew: Duration(milliseconds: quoteReader.optInt('skewMs') ?? 0),
        readToken: quoteReader.optStr('readToken'),
      );
    }

    final quoteHistory = <SettlementQuoteHistoryEntry>[];
    for (final item in r.list('quoteHistory')) {
      if (item is! Map) r.fail('quoteHistory');
      final e = _Reader(Map<String, Object?>.from(item), 'quoteHistory.');
      quoteHistory.add(SettlementQuoteHistoryEntry(
        quoteId: e.str('quoteId'),
        reason: e.str('reason'),
        supersededAt: e.ms('supersededAtMs'),
      ));
    }

    final stageHistory = <SettlementStageEntry>[];
    for (final item in r.list('stageHistory')) {
      if (item is! Map) r.fail('stageHistory');
      final e = _Reader(Map<String, Object?>.from(item), 'stageHistory.');
      final s = SettlementStage.fromName(e.str('stage')) ?? e.fail('stage');
      stageHistory.add(SettlementStageEntry(s, e.ms('atMs')));
    }

    final keys = r.optObj('keys');
    final fundingReader = r.optObj('funding');
    final SettlementFunding? funding;
    if (fundingReader == null) {
      funding = null;
    } else {
      final kindName = fundingReader.optStr('kind');
      SettlementFundingKind? kind;
      for (final k in SettlementFundingKind.values) {
        if (k.name == kindName) kind = k;
      }
      funding = SettlementFunding(
        kind: kind,
        sparkPaymentId: fundingReader.optStr('sparkPaymentId'),
        btcTxid: fundingReader.optStr('btcTxid'),
        btcVout: fundingReader.optInt('btcVout'),
        btcInputs: fundingReader.strings('btcInputs'),
        evmTxHash: fundingReader.optStr('evmTxHash'),
        relayerTxId: fundingReader.optStr('relayerTxId'),
        hlNonce: fundingReader.optInt('hlNonce'),
        hlActionHash: fundingReader.optStr('hlActionHash'),
      );
    }

    final submit = r.optObj('submit');
    final poll = r.optObj('poll');
    final late = r.optObj('late');
    final refundObserved = r.optObj('refundObserved');

    return SettlementOperation(
      schema: schema,
      operationId: operationId,
      walletId: r.str('walletId'),
      accountKind: SettlementAccountKind.fromName(r.optStr('accountKind')),
      flow: SettlementFlow.fromName(r.optStr('flow')),
      routeVersion: r.optStr('routeVersion'),
      route: route,
      amountInBaseUnits: amount,
      quote: quote,
      quoteHistory: List.unmodifiable(quoteHistory),
      recipient: _decodeAddress(r.optObj('recipient')),
      refund: _decodeAddress(r.optObj('refund')),
      keys: keys == null
          ? const SettlementKeys()
          : SettlementKeys(
              quote: keys.optStr('quote'),
              submit: keys.optStr('submit'),
              submitHistory: keys.strings('submitHistory'),
              submitFingerprint: keys.optStr('submitFingerprint'),
            ),
      stage: stage,
      stageHistory: List.unmodifiable(stageHistory),
      funding: funding,
      orderId: r.optStr('orderId'),
      submit: submit == null
          ? const SettlementSubmitState()
          : SettlementSubmitState(
              attempts: submit.optInt('attempts') ?? 0,
              lastAttemptAt: submit.optMs('lastAttemptAtMs'),
              lastErrorCode: submit.optStr('lastErrorCode'),
              acceptedAt: submit.optMs('acceptedAtMs'),
              providerDetected: submit.optBool('providerDetected') ?? false,
            ),
      poll: poll == null
          ? const SettlementPollState()
          : SettlementPollState(
              providerStatus: poll.optStr('providerStatus'),
              mappedStatus: poll.optStr('mappedStatus'),
              lastCheckedAt: poll.optMs('lastCheckedAtMs'),
              consecutiveFailures: poll.optInt('consecutiveFailures') ?? 0,
              nextCheckAt: poll.optMs('nextCheckAtMs'),
              sdkSyncsSinceBroadcasting:
                  poll.optInt('sdkSyncsSinceBroadcasting') ?? 0,
              lastSdkSyncGeneration: poll.optInt('lastSdkSyncGeneration'),
            ),
      late: late == null
          ? null
          : SettlementLate(
              quoteExpiredBeforeFunding:
                  late.optBool('quoteExpiredBeforeFunding') ?? false,
              detectedAt: late.optMs('detectedAtMs'),
            ),
      refundObserved: refundObserved == null
          ? null
          : SettlementRefundObserved(
              at: refundObserved.optMs('atMs'),
              txRef: refundObserved.optStr('txRef'),
            ),
      recoveredFrom: r.optStr('recoveredFrom'),
      createdAt: r.ms('createdAtMs'),
      updatedAt: r.optMs('updatedAtMs') ?? r.ms('createdAtMs'),
      terminalAt: r.optMs('terminalAtMs'),
      version: r.optInt('version') ?? 0,
      raw: Map.unmodifiable(map),
    );
  }

  static SettlementAddressRef? _decodeAddress(_Reader? r) {
    if (r == null) return null;
    return SettlementAddressRef(
      address: r.str('address'),
      kind: OwnedAddressKind.fromName(r.optStr('kind')),
      index: r.optInt('index'),
      deviceVerifiedAt: r.optMs('deviceVerifiedAtMs'),
    );
  }
}
