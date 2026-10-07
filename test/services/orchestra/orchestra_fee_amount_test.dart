import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';

Map<String, dynamic> _live() => jsonDecode(
    File('test/services/fixtures/orchestra_estimate_spark_to_hypercore.json')
        .readAsStringSync()) as Map<String, dynamic>;
void main() {
  outNetOfKuteFeeTests();
  quoteFeeAmountsTests();
  test(
      'live estimate includes rounding and interprets fee asset independently from destination',
      () {
    final quote = OrchestraEstimate.fromJson(_live());
    expect(quote.feeAssetDetails!.decimals, 6);
    expect(quote.destination!.decimals, 8);
    expect(orchestraFeeAmount(quote).usd, closeTo(1.041619, 1e-9));
    expect(orchestraFeeAmount(quote).usd, greaterThan(10 * 81.419 / 10000));
    final receive = orchestraReceiveAmount(quote,
        destinationChain: 'hypercore', destinationAsset: 'USDC');
    expect(receive.usd, closeTo(80.09, 1e-9));
  });
  test('raw fee fallback uses Solana6 units even for HyperCore8 destination',
      () {
    final json = _live()..remove('totalFeeAmountUsd');
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).usd,
        closeTo(1.041619, 1e-9));
  });
  test(
      'platform-only amount or rate is never presented as total conversion fee',
      () {
    final json = _live()
      ..remove('totalFeeAmount')
      ..remove('totalFeeAmountUsd');
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).isAvailable,
        isFalse);
  });
  test('feeBps is not required when total fee is reported', () {
    final json = _live()..remove('feeBps');
    final quote = OrchestraEstimate.fromJson(json);
    expect(quote.hasFeeRate, isFalse);
    expect(orchestraFeeAmount(quote).usd, closeTo(1.041619, 1e-9));
  });
  test('affiliate platform cut is not added to returned total twice', () {
    final json = _live()
      ..['appFeeAmount'] = '2000000'
      ..['appFeePlatformCutAmount'] = '400000'
      ..['totalFeeAmount'] = '3041619'
      ..['totalFeeAmountUsd'] = '3.041619';
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).usd,
        closeTo(3.041619, 1e-9));
  });
  test('Bitcoin fee and net output remain sats, with no second deduction', () {
    final quote = OrchestraEstimate.fromJson({
      'feeBps': 10,
      'feeAmount': '100',
      'totalFeeAmount': '1666',
      'feeAsset': 'BTC',
      'feeAssetDetails': {'chain': 'spark', 'asset': 'BTC', 'decimals': 8},
      'estimatedOut': '163334',
      'destination': {'chain': 'spark', 'asset': 'BTC', 'decimals': 8},
    });
    expect(orchestraFeeAmount(quote).sats, closeTo(1666, 1e-8));
    expect(
        orchestraReceiveAmount(quote,
                destinationChain: 'spark', destinationAsset: 'BTC')
            .sats,
        closeTo(163334, 1e-8));
  });
  test(
      'missing or mismatched fee denomination never borrows destination decimals',
      () {
    for (final details in [
      null,
      {'chain': 'solana', 'asset': 'SOL', 'decimals': 9},
      {'chain': 'solana', 'asset': 'USDC', 'decimals': -1}
    ]) {
      final json = _live()
        ..remove('totalFeeAmountUsd')
        ..['feeAssetDetails'] = details;
      expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).isAvailable,
          isFalse);
    }
  });
  test('invalid total values do not become zero', () {
    for (final value in ['NaN', 'Infinity', '-1', '1.5', 'unknown']) {
      final json = _live()
        ..remove('totalFeeAmountUsd')
        ..['totalFeeAmount'] = value;
      expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).isAvailable,
          isFalse);
    }
  });
  test('a valid zero quote is distinct from missing fees', () {
    final json = _live()
      ..['totalFeeAmount'] = '0'
      ..['totalFeeAmountUsd'] = '0';
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).usd, 0);
    json['totalFeeAmount'] = '1041619';
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).isAvailable,
        isFalse);
  });
  test('foreign-asset fees can use provider USD valuation without inventing FX',
      () {
    final json = _live()
      ..['feeAsset'] = 'SOL'
      ..['feeAssetDetails'] = {
        'chain': 'solana',
        'asset': 'SOL',
        'decimals': 9
      };
    expect(orchestraFeeAmount(OrchestraEstimate.fromJson(json)).usd,
        closeTo(1.041619, 1e-9));
  });
  test('receive only describes the requested destination', () {
    final quote = OrchestraEstimate.fromJson(_live());
    expect(
        orchestraReceiveAmount(quote,
                destinationChain: 'polygon', destinationAsset: 'USDC')
            .isAvailable,
        isFalse);
  });
}

// "You receive" on the cross-chain Send and the Dollars send reads the
// estimate, which the backend serves without the Kute fee, while the quote
// that is paid takes the pinned rate out of that same output. These pin the
// displayed figure to what the paid quote delivers.
OrchestraEstimate _estimateWithHeaders(String estimatedOut,
        {String? appFeeBps, String included = 'false', String? discount}) =>
    OrchestraEstimate.fromJson({
      'estimatedOut': estimatedOut,
      'feeBps': 20,
      'feeAmount': '0',
    }, headers: {
      'X-Kute-Estimate-Includes-App-Fee': included,
      if (appFeeBps != null) 'X-Kute-App-Fee-Bps': appFeeBps,
      if (discount != null) 'X-Kute-Referral-Discount-Bps': discount,
    });

/// What the paid quote delivers for the same route: the Kute rate taken out
/// of the output in base units, as the provider settles it.
BigInt _paidOut(BigInt gross, int bps) =>
    gross - (gross * BigInt.from(bps) ~/ BigInt.from(10000));

void outNetOfKuteFeeTests() {
  group('orchestraOutNetOfKuteFee', () {
    // (chain, asset, decimals, gross base units)
    const cases = [
      ('solana', 'USDC', 6, '2480000'), // $2.48, six decimals
      ('ethereum', 'USDC', 6, '250000000000'), // $250,000
      ('hypercore', 'USDC', 8, '998765432'), // $9.98765432, eight decimals
      ('spark', 'BTC', 8, '163334'), // sats
      ('tron', 'USDT', 6, '1000'), // a tenth of a cent
    ];
    for (final (chain, asset, decimals, raw) in cases) {
      for (final (bps, discount) in [(50, null), (30, '20'), (0, null)]) {
        test('$asset on $chain at $bps bps (discount ${discount ?? 0})', () {
          final quote =
              _estimateWithHeaders(raw, appFeeBps: '$bps', discount: discount);
          final scale = BigInt.from(10).pow(decimals).toDouble();
          final shown = orchestraOutNetOfKuteFee(
              quote, BigInt.parse(raw).toDouble() / scale)!;
          final paid = _paidOut(BigInt.parse(raw), bps).toDouble() / scale;
          // Equal to the paid output within one base unit of rounding.
          expect(shown, closeTo(paid, 1 / scale));
          if (bps > 0) {
            expect(shown, lessThan(BigInt.parse(raw).toDouble() / scale));
          }
        });
      }
    }
    test('discount on vs off differs by exactly the discount', () {
      const gross = 100.0;
      final full = orchestraOutNetOfKuteFee(
          _estimateWithHeaders('100000000', appFeeBps: '50'), gross)!;
      final referred = orchestraOutNetOfKuteFee(
          _estimateWithHeaders('100000000', appFeeBps: '30', discount: '20'),
          gross)!;
      expect(full, closeTo(99.50, 1e-9));
      expect(referred, closeTo(99.70, 1e-9));
    });
    test('an estimate that already holds the fee is not reduced again', () {
      final quote =
          _estimateWithHeaders('99500000', appFeeBps: '50', included: 'true');
      expect(orchestraOutNetOfKuteFee(quote, 99.5), 99.5);
    });
    test('an unknown rate on an estimate without the fee has no net figure',
        () {
      expect(orchestraOutNetOfKuteFee(_estimateWithHeaders('1000000'), 1.0),
          isNull);
      expect(
          orchestraOutNetOfKuteFee(
              _estimateWithHeaders('1000000', appFeeBps: '10000'), 1.0),
          isNull);
    });
  });
}

// The Ledger funding review's "Fees" headline used to be the provider's
// rate alone (amountSats x feeBps); the Kute fee sat behind the chevron as a
// percentage. The headline is now both parts, as the quote charges them.
void quoteFeeAmountsTests() {
  OrchestraQuote quote({int feeBps = 20, List<int>? appFees}) =>
      OrchestraQuote.fromJson({
        'quoteId': 'q',
        'depositAddress': 'd',
        'amountIn': '0',
        'estimatedOut': '0',
        'feeAmount': '0',
        'feeBps': feeBps,
        if (appFees != null)
          'appFees': [
            for (final bps in appFees) {'affiliateId': 'kute', 'feeBps': bps}
          ],
        'route': const [],
        'expiresAt': '',
      });

  group('orchestraQuoteFeeAmounts', () {
    test('headline is the provider fee plus the Kute fee on what remains', () {
      // 50,000 sats, provider 20 bps: 100 sats; Kute 50 bps of 49,900: 249.5.
      final full = orchestraQuoteFeeAmounts(quote(appFees: [50]), 50000);
      expect(full.provider, closeTo(100, 1e-9));
      expect(full.kute, closeTo(249.5, 1e-9));
      expect(full.total, closeTo(349.5, 1e-9));
      // The friend discount (20 bps) lowers only the Kute part.
      final referred = orchestraQuoteFeeAmounts(quote(appFees: [30]), 50000);
      expect(referred.kute, closeTo(149.7, 1e-9));
      expect(full.total - referred.total, closeTo(99.8, 1e-9));
    });
    test('small and large amounts scale exactly', () {
      for (final sats in [1000, 50000, 250000000]) {
        final fees = orchestraQuoteFeeAmounts(quote(appFees: [50]), sats);
        expect(fees.total, closeTo(sats * (0.002 + 0.998 * 0.005), 1e-6));
      }
    });
    test('a quote without an app fee list states the provider fee alone', () {
      final none = orchestraQuoteFeeAmounts(quote(), 50000);
      expect(none.kute, isNull);
      expect(none.total, closeTo(100, 1e-9));
      final zero = orchestraQuoteFeeAmounts(quote(appFees: const []), 50000);
      expect(zero.kute, 0);
      expect(zero.total, closeTo(100, 1e-9));
    });
  });
}
