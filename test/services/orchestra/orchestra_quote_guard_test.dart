// One case per Phase 2 D6 rule. Fixtures are hand-written from
// docs.flashnet.xyz/orchestra/quotes and get replaced by redacted live
// captures once [N]1 runs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _ownSparkLegacy =
    'sp1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9hvvq4l';
const _flashnetSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherEvm = '0x0000000000000000000000000000000000000001';
const _flashnetEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _btcOnchain = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';

final _now = DateTime.utc(2026, 9, 15, 12);

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/services/fixtures/orchestra_quote_$name.json')
        .readAsStringSync()) as Map<String, dynamic>;

OrchestraQuote _quote(String name, [Map<String, dynamic> changes = const {}]) {
  final json = _fixture(name)..addAll(changes);
  json.removeWhere((_, v) => v == _absent);
  return OrchestraQuote.fromJson(json);
}

const _absent = '__absent__';

/// Spark BTC to Polymarket USDC.e: 100,000 sats at a local price worth
/// 60,000,000 USDC.e base units.
OrchestraQuoteRequest _sparkRequest({
  String recipient = _pmWallet,
  String refund = _ownSpark,
  RecipientKind kind = RecipientKind.ownPmWallet,
  String? own = _pmWallet,
}) =>
    OrchestraQuoteRequest(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'polygon',
      destinationAsset: 'USDC.e',
      amountBaseUnits: BigInt.from(100000),
      recipientAddress: recipient,
      refundAddress: refund,
      recipientKind: kind,
      ownAddress: own,
    );

/// Polymarket USDC.e to Spark BTC: 50 USDC.e worth 83,333 sats.
OrchestraQuoteRequest _polygonRequest({
  String recipient = _ownSpark,
  String own = _ownSpark,
}) =>
    OrchestraQuoteRequest(
      sourceChain: 'polygon',
      sourceAsset: 'USDC.e',
      destinationChain: 'spark',
      destinationAsset: 'BTC',
      amountBaseUnits: BigInt.from(50000000),
      recipientAddress: recipient,
      refundAddress: _pmWallet,
      recipientKind: RecipientKind.ownSpark,
      ownAddress: own,
    );

OrchestraQuoteBounds _sparkBounds({double? reference = 60000000}) =>
    OrchestraQuoteBounds.forSource('spark', inputValueInOutputUnits: reference);

OrchestraQuoteBounds _polygonBounds({double? reference = 83333}) =>
    OrchestraQuoteBounds.forSource('polygon',
        inputValueInOutputUnits: reference);

VerifiedOrchestraQuote _verifySpark(
  OrchestraQuote quote, {
  OrchestraQuoteRequest? request,
  OrchestraQuoteBounds? bounds,
  DateTime? now,
}) =>
    verifyOrchestraQuote(request ?? _sparkRequest(), quote,
        now: now ?? _now, bounds: bounds ?? _sparkBounds(), mainnet: true);

VerifiedOrchestraQuote _verifyPolygon(
  OrchestraQuote quote, {
  OrchestraQuoteRequest? request,
  OrchestraQuoteBounds? bounds,
  DateTime? now,
}) =>
    verifyOrchestraQuote(request ?? _polygonRequest(), quote,
        now: now ?? _now, bounds: bounds ?? _polygonBounds(), mainnet: true);

Matcher _rejects(WalletGuardReason reason) => throwsA(
    isA<WalletGuardException>().having((e) => e.reason, 'reason', reason));

String _at(Duration offset) => _now.add(offset).toIso8601String();

void main() {
  test('quoted app fees participate in the safety cap', () {
    expect(
        () => _verifySpark(_quote('spark_to_polygon', {
              'feeBps': 100,
              'appFees': [
                {'feeBps': 301}
              ],
            })),
        _rejects(WalletGuardReason.feeAboveCap));
    expect(
        () => _verifySpark(_quote('spark_to_polygon', {
              'feeBps': 100,
              'appFees': [
                {'feeBps': 'unknown'}
              ],
            })),
        _rejects(WalletGuardReason.feeAboveCap));
    final valid = _verifySpark(_quote('spark_to_polygon', {
      'feeBps': 100,
      'appFees': [
        {'feeBps': 50}
      ],
    }));
    expect(valid.quote.combinedFeeBps, 150);
  });
  test('XRP receive requires explicit memo support and a valid destination tag',
      () {
    const xrp = 'rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh';
    OrchestraQuoteRequest request(bool enabled) => OrchestraQuoteRequest(
          sourceChain: 'xrp',
          sourceAsset: 'XRP',
          destinationChain: 'spark',
          destinationAsset: 'BTC',
          amountBaseUnits: BigInt.from(50000000),
          recipientAddress: _ownSpark,
          refundAddress: xrp,
          recipientKind: RecipientKind.ownSpark,
          ownAddress: _ownSpark,
          externalDepositMemo: enabled,
        );
    OrchestraQuote quote(String memo) => _quote('polygon_to_spark', {
          'route': ['xrp:XRP', 'spark:BTC'],
          'depositAddress': xrp,
          'depositMemo': memo,
        });
    expect(() => _verifyPolygon(quote('123'), request: request(false)),
        _rejects(WalletGuardReason.depositMemoPresent));
    expect(
        _verifyPolygon(quote('123'), request: request(true)).quote.depositMemo,
        '123');
    expect(() => _verifyPolygon(quote('4294967296'), request: request(true)),
        _rejects(WalletGuardReason.depositMemoPresent));
  });

  group('happy path', () {
    test('Spark source fixture verifies', () {
      final v = _verifySpark(_quote('spark_to_polygon'));
      expect(v.amountIn, BigInt.from(100000));
      expect(v.expiresAt, DateTime.utc(2026, 9, 15, 12, 2));
      expect(v.expiryMargin, const Duration(seconds: 15));
      expect(v.depositAddress, _flashnetSpark);
      expect(v.quoteId, 'q_fixture_spark_polygon');
    });

    test('Polygon source fixture verifies', () {
      final v = _verifyPolygon(_quote('polygon_to_spark'));
      expect(v.amountIn, BigInt.from(50000000));
      expect(v.expiryMargin, const Duration(seconds: 60));
    });

    test('route labels are not validated', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon', {
                'route': ['anything', 'goes']
              })),
          returnsNormally);
    });
  });

  test('rule 1: empty quoteId', () {
    expect(() => _verifySpark(_quote('spark_to_polygon', {'quoteId': ''})),
        _rejects(WalletGuardReason.quoteMissingId));
    expect(() => _verifySpark(_quote('spark_to_polygon', {'quoteId': _absent})),
        _rejects(WalletGuardReason.quoteMissingId));
  });

  group('rule 2: deposit address format for the source chain', () {
    test('EVM deposit on a Spark source', () {
      expect(
          () => _verifySpark(
              _quote('spark_to_polygon', {'depositAddress': _flashnetEvm})),
          _rejects(WalletGuardReason.depositAddressFormat));
    });

    test('Lightning invoice or empty deposit', () {
      expect(
          () => _verifySpark(
              _quote('spark_to_polygon', {'depositAddress': 'lnbc1invoice'})),
          _rejects(WalletGuardReason.depositAddressFormat));
      expect(
          () =>
              _verifySpark(_quote('spark_to_polygon', {'depositAddress': ''})),
          _rejects(WalletGuardReason.depositAddressFormat));
    });

    test('Spark deposit on a Polygon source', () {
      expect(
          () => _verifyPolygon(
              _quote('polygon_to_spark', {'depositAddress': _flashnetSpark})),
          _rejects(WalletGuardReason.depositAddressFormat));
    });

    test('a chain without a rule is refused', () {
      final request = OrchestraQuoteRequest(
        sourceChain: 'ton',
        sourceAsset: 'USDT',
        destinationChain: 'spark',
        destinationAsset: 'BTC',
        amountBaseUnits: BigInt.from(50000000),
        recipientAddress: _ownSpark,
        refundAddress: 'UQ_fixture',
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      );
      expect(
          () => _verifyPolygon(
              _quote('polygon_to_spark', {'depositAddress': 'UQ_fixture'}),
              request: request),
          _rejects(WalletGuardReason.depositAddressFormat));
    });
  });

  test('rule 3: a deposit memo is refused, an empty one is not', () {
    expect(
        () =>
            _verifySpark(_quote('spark_to_polygon', {'depositMemo': '12345'})),
        _rejects(WalletGuardReason.depositMemoPresent));
    expect(() => _verifySpark(_quote('spark_to_polygon', {'depositMemo': ''})),
        returnsNormally);
  });

  group('rule 4: amountIn equals the request', () {
    test('different amount', () {
      expect(
          () =>
              _verifySpark(_quote('spark_to_polygon', {'amountIn': '100001'})),
          _rejects(WalletGuardReason.amountMismatch));
    });

    test('leading zeros compare as the same integer', () {
      expect(
          _verifySpark(_quote('spark_to_polygon', {'amountIn': '000100000'}))
              .amountIn,
          BigInt.from(100000));
    });

    test('missing, decimal, signed and hex values', () {
      for (final bad in [
        _absent,
        '100000.0',
        '-100000',
        '+100000',
        '0x186a0'
      ]) {
        expect(
            () => _verifySpark(_quote('spark_to_polygon', {'amountIn': bad})),
            _rejects(WalletGuardReason.amountMismatch),
            reason: bad);
      }
    });

    test('numeric JSON amount is read as its integer string', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon', {'amountIn': 100000})),
          returnsNormally);
    });
  });

  group('rule 5: expiry with margin', () {
    test('Spark margin boundary is 15 s', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon',
              {'expiresAt': _at(const Duration(seconds: 15))})),
          _rejects(WalletGuardReason.quoteExpired));
      expect(
          () => _verifySpark(_quote('spark_to_polygon', {
                'expiresAt': _at(const Duration(seconds: 15, milliseconds: 1))
              })),
          returnsNormally);
    });

    test('Polygon relayer margin boundary is 60 s', () {
      expect(
          () => _verifyPolygon(_quote('polygon_to_spark',
              {'expiresAt': _at(const Duration(seconds: 60))})),
          _rejects(WalletGuardReason.quoteExpired));
      expect(
          () => _verifyPolygon(_quote('polygon_to_spark',
              {'expiresAt': _at(const Duration(seconds: 61))})),
          returnsNormally);
    });

    test('missing, empty, past or unparseable expiry', () {
      for (final bad in [
        _absent,
        '',
        'soon',
        _at(const Duration(minutes: -1))
      ]) {
        expect(
            () => _verifySpark(_quote('spark_to_polygon', {'expiresAt': bad})),
            _rejects(WalletGuardReason.quoteExpired),
            reason: bad);
      }
    });

    test('an ISO expiry without a zone is read as UTC', () {
      expect(
          () => _verifySpark(
              _quote('spark_to_polygon', {'expiresAt': '2026-09-15T12:02:00'})),
          returnsNormally);
      expect(
          () => _verifySpark(
              _quote('spark_to_polygon', {'expiresAt': '2026-09-15T11:58:00'})),
          _rejects(WalletGuardReason.quoteExpired));
      expect(
          _verifySpark(_quote(
                  'spark_to_polygon', {'expiresAt': '2026-09-15T12:02:00'}))
              .expiresAt,
          DateTime.utc(2026, 9, 15, 12, 2));
    });

    test('an out-of-range numeric expiry is a guard rejection', () {
      for (final bad in ['99999999999999999', '9223372036854775807']) {
        expect(
            () => _verifySpark(_quote('spark_to_polygon', {'expiresAt': bad})),
            _rejects(WalletGuardReason.quoteExpired),
            reason: bad);
      }
    });

    test('a far-future expiry is capped at the quote lifetime', () {
      final v = _verifySpark(_quote('spark_to_polygon',
          {'expiresAt': _now.add(const Duration(days: 1)).toIso8601String()}));
      expect(v.expiresAt, _now.add(OrchestraQuoteBounds.maxQuoteLifetime));
    });

    test('unix seconds and milliseconds are accepted', () {
      final at = _now.add(const Duration(minutes: 2));
      expect(
          () => _verifySpark(_quote('spark_to_polygon',
              {'expiresAt': at.millisecondsSinceEpoch ~/ 1000})),
          returnsNormally);
      expect(
          () => _verifySpark(_quote(
              'spark_to_polygon', {'expiresAt': at.millisecondsSinceEpoch})),
          returnsNormally);
    });
  });

  group('rule 6: request-side refund and recipient', () {
    test('an on-chain Bitcoin refund on a Spark source', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(refund: _btcOnchain)),
          _rejects(WalletGuardReason.refundAddressChain));
    });

    test('an EVM refund on a Spark source', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(refund: _pmWallet)),
          _rejects(WalletGuardReason.refundAddressChain));
    });

    test('a recipient in the wrong format for the destination chain', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(recipient: _ownSpark, own: _ownSpark)),
          _rejects(WalletGuardReason.recipientAddressChain));
    });

    test('an own-kind recipient that is not the resolved own address', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(recipient: _otherEvm)),
          _rejects(WalletGuardReason.recipientNotOwn));
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(own: null)),
          _rejects(WalletGuardReason.recipientNotOwn));
    });

    test('an external recipient skips the own-address check', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon'),
              request: _sparkRequest(
                  recipient: _otherEvm,
                  kind: RecipientKind.external,
                  own: null)),
          returnsNormally);
    });

    test('sp1 and spark1 spellings of the own Spark address match', () {
      expect(
          () => _verifyPolygon(_quote('polygon_to_spark'),
              request:
                  _polygonRequest(recipient: _ownSparkLegacy, own: _ownSpark)),
          returnsNormally);
    });
  });

  group('rule 7: fee cap', () {
    test('400 bps passes, 401 is refused', () {
      expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': 400})),
          returnsNormally);
      expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': 401})),
          _rejects(WalletGuardReason.feeAboveCap));
    });

    test('malformed or fractional fee is refused, integer strings accepted',
        () {
      for (final bad in <Object>[
        'abc',
        '9000 ',
        '400.9',
        400.9,
        <String, dynamic>{},
        ''
      ]) {
        expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': bad})),
            _rejects(WalletGuardReason.feeAboveCap),
            reason: '$bad');
      }
      expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': '200'})),
          returnsNormally);
      expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': 200.0})),
          returnsNormally);
    });

    test('missing or negative fee is refused', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon', {'feeBps': _absent})),
          _rejects(WalletGuardReason.feeAboveCap));
      expect(() => _verifySpark(_quote('spark_to_polygon', {'feeBps': -1})),
          _rejects(WalletGuardReason.feeAboveCap));
    });
  });

  // The local-price output floor and the locked-vs-estimate check were
  // removed on purpose in 6bf6be95 ("NO OUTPUT FLOOR" in the guard): a
  // ratio against this app's own price cannot tell a small deposit
  // paying a fixed bridge cost from a hostile route, and it refused
  // honest transfers. The declared fee cap (rule 7) still applies. These
  // tests pin that decision so a floor cannot silently come back, or
  // silently be relied on.
  group('rule 8: no output floor from the local price', () {
    test('a low estimatedOut is not refused by the guard', () {
      for (final out in ['56399999', '1']) {
        expect(
            () =>
                _verifySpark(_quote('spark_to_polygon', {'estimatedOut': out})),
            returnsNormally,
            reason: out);
      }
    });

    test('a low lockedMinAmountOut is not refused by the guard', () {
      expect(
          () => _verifyPolygon(
              _quote('polygon_to_spark', {'lockedMinAmountOut': '78333'})),
          returnsNormally);
    });

    test('a missing reference price is not a refusal', () {
      for (final reference in [null, 0.0, -1.0, double.nan]) {
        expect(
            () => _verifySpark(_quote('spark_to_polygon'),
                bounds: _sparkBounds(reference: reference)),
            returnsNormally,
            reason: '$reference');
      }
    });

    test('the declared fee cap still refuses a costly quote', () {
      expect(
          () => _verifySpark(
              _quote('spark_to_polygon', {'estimatedOut': '1', 'feeBps': 401})),
          _rejects(WalletGuardReason.feeAboveCap));
    });
  });

  group('strict output parsing', () {
    Matcher malformed(String field) => throwsA(isA<WalletGuardException>()
        .having((e) => e.reason, 'reason', WalletGuardReason.outputMalformed)
        .having((e) => e.field, 'field', field));

    const bad = <Object>[
      'lots',
      '',
      ' ',
      'NaN',
      'Infinity',
      '-1',
      '0',
      '00',
      '1.5',
      '1e6',
      0,
      -1,
      1.5,
      double.nan,
      double.infinity,
      _absent,
    ];

    test('a missing, non-numeric, non-finite, zero or signed estimatedOut '
        'is refused', () {
      for (final value in bad) {
        expect(
            () => _verifySpark(
                _quote('spark_to_polygon', {'estimatedOut': value})),
            malformed('estimated_out'),
            reason: '$value');
      }
    });

    test('a present but malformed lockedMinAmountOut is refused', () {
      for (final value in bad.where((v) => v != _absent)) {
        expect(
            () => _verifyPolygon(
                _quote('polygon_to_spark', {'lockedMinAmountOut': value})),
            malformed('locked_min_amount_out'),
            reason: '$value');
      }
    });

    test('valid positive integer amounts pass; the locked minimum is optional',
        () {
      for (final value in <Object>['58800000', 58800000, '1']) {
        expect(
            () => _verifySpark(
                _quote('spark_to_polygon', {'estimatedOut': value})),
            returnsNormally,
            reason: '$value');
      }
      expect(() => _verifyPolygon(_quote('polygon_to_spark')), returnsNormally);
      expect(
          () => _verifyPolygon(
              _quote('polygon_to_spark', {'lockedMinAmountOut': _absent})),
          returnsNormally);
    });
  });

  group('rule 9: undocumented echo fields', () {
    test('absent echoes are accepted', () {
      final quote = _quote('spark_to_polygon');
      expect(quote.present.contains('sourceChain'), isFalse);
      expect(() => _verifySpark(quote), returnsNormally);
    });

    test('matching echoes are accepted, case-insensitively for labels', () {
      expect(
          () => _verifySpark(_quote('spark_to_polygon', {
                'sourceChain': 'SPARK',
                'sourceAsset': 'btc',
                'destinationChain': 'polygon',
                'destinationAsset': 'USDC.E',
                'recipientAddress': _pmWallet.toLowerCase(),
                'refundAddress': _ownSparkLegacy,
              })),
          returnsNormally);
    });

    test('each present but different echo is refused', () {
      final cases = <String, Object>{
        'sourceChain': 'bitcoin',
        'sourceAsset': 'USDB',
        'destinationChain': 'arbitrum',
        'destinationAsset': 'USDC',
        'recipientAddress': _otherEvm,
        'refundAddress': _flashnetSpark,
      };
      cases.forEach((field, value) {
        expect(() => _verifySpark(_quote('spark_to_polygon', {field: value})),
            _rejects(WalletGuardReason.echoMismatch),
            reason: field);
      });
    });
  });

  test('rules apply in order: memo is reported before amount', () {
    expect(
        () => _verifySpark(_quote('spark_to_polygon',
            {'depositMemo': 'x', 'amountIn': '1', 'feeBps': 9999})),
        _rejects(WalletGuardReason.depositMemoPresent));
  });

  test('routeLabel carries chains and assets only', () {
    expect(_sparkRequest().routeLabel, 'spark_btc>polygon_usdc.e');
  });
}
