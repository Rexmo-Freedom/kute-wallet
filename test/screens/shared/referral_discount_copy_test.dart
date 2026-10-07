// The referee discount is display-only in the app: the backend applies it
// to every positive Kute fee and reports what it applied. These tests pin
// the copy helpers and the parsing of the figures the backend sends.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

void main() {
  test('discount copy is a share of the fee', () {
    expect(discountShareText(40), '40%');
    expect(discountShareText(100), '100%');
    expect(discountShareText(0), '0%');
    // 20 bps off a 50 bps fee: paid 30, discount 20 → 40% of the listed fee.
    expect(discountShareOf(paid: 30, discount: 20), 40);
    // The discount took the whole fee.
    expect(discountShareOf(paid: 0, discount: 20), 100);
    expect(discountShareOf(paid: 50, discount: 0), 0);
    // Hyperliquid, in tenths of a bp: listed 10, paid 8.
    expect(discountShareOf(paid: 8, discount: 2), 20);
  });

  test('orchestra estimate reads the referral discount header', () {
    final quote = OrchestraEstimate.fromJson(
      {'estimatedOut': '1', 'feeAmount': '0', 'feeBps': 100, 'route': []},
      headers: {
        'X-Kute-App-Fee-Bps': '80',
        'X-Kute-Referral-Discount-Bps': '20',
      },
    );
    expect(quote.kuteAppFeeBps, 80);
    expect(quote.kuteReferralDiscountBps, 20);
    final none = OrchestraEstimate.fromJson(
      {'estimatedOut': '1', 'feeAmount': '0', 'feeBps': 100, 'route': []},
    );
    expect(none.kuteReferralDiscountBps, 0);
  });

  test('builder info knows when the session pays less than listed', () {
    const listed = HlBuilderInfo(
        builderAddress: '0xabc', defaultFeeTenthsBp: 10, maxFeeRate: '0.01%');
    expect(listed.discounted, isFalse);
    expect(listed.listedFeeTenthsBp, 10);
    const referred = HlBuilderInfo(
        builderAddress: '0xabc',
        defaultFeeTenthsBp: 8,
        maxFeeRate: '0.01%',
        listedFeeTenthsBp: 10,
        refereeDiscountTenthsBp: 2);
    expect(referred.discounted, isTrue);
    // A discount that did not lower the fee (fee was already zero) shows
    // no note.
    const zero = HlBuilderInfo(
        builderAddress: '0xabc',
        defaultFeeTenthsBp: 0,
        maxFeeRate: '0.01%',
        listedFeeTenthsBp: 0,
        refereeDiscountTenthsBp: 2);
    expect(zero.discounted, isFalse);
  });

  test('capability policy exposes the public referral terms', () {
    final now = DateTime.now().toUtc();
    final policy = RuntimeCapabilities.fromJson(<String, dynamic>{
      'schemaVersion': 1,
      'revision': 3,
      'evaluatedAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
      'capabilities': <String, dynamic>{},
      'referral': <String, dynamic>{
        'refereeDiscountBps': 20,
        'refereeDiscountPct': 40,
        'isReferred': true
      },
    });
    expect(policy.refereeDiscountBps, 20);
    expect(policy.refereeDiscountPct, 40);
    expect(policy.isReferred, isTrue);
    final bare = RuntimeCapabilities.fromJson(<String, dynamic>{
      'schemaVersion': 1,
      'revision': 3,
      'evaluatedAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
      'capabilities': <String, dynamic>{},
    });
    expect(bare.refereeDiscountBps, 0);
    expect(bare.refereeDiscountPct, 0);
    expect(bare.isReferred, isFalse);
  });
}
