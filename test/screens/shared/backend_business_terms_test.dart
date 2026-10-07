// Business figures shown in copy (referral discount, commission ladder,
// rewards rate) come only from the backend or the venue. When they have
// not been received the app shows no figure rather than a built-in one.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/screens/shared/fee_copy.dart';

void main() {
  tearDown(() {
    AffiliateService.debugRefereeDiscountBps = null;
    AffiliateService.debugRefereeDiscountPct = null;
    AffiliateService.debugCommissionTopRatePct = null;
  });

  test('commission rates format from the percent the backend publishes', () {
    expect(commissionRateText(5), '5%');
    expect(commissionRateText(20.0), '20%');
    expect(commissionRateText(7.5), '7.5%');
    expect(commissionRateText(150), '100%');
  });

  test('the referral discount is unknown until the backend states it', () {
    expect(AffiliateService.refereeDiscountBps, isNull);
    expect(AffiliateService.refereeDiscountPct, isNull);
    expect(AffiliateService.commissionTopRatePct, isNull);

    AffiliateService.debugRefereeDiscountBps = 20;
    AffiliateService.debugRefereeDiscountPct = 40;
    AffiliateService.debugCommissionTopRatePct = 20;
    expect(AffiliateService.refereeDiscountBps, 20);
    expect(AffiliateService.refereeDiscountPct, 40);
    expect(AffiliateService.commissionTopRatePct, 20);
  });

  group('rewards rate', () {
    Map<String, dynamic> summary(Object? percent) => {
          'pubkey': 'pk',
          'usdbBalance': {'raw': 0, 'display': 12.0},
          'volumeUtcToday': {'swapSats': 0, 'swapCount': 0},
          'rewardsBracket': 1,
          'rewardsPercent': percent,
          'estimatedSatsToday': 0,
        };

    test('is the rate the service reported', () {
      expect(UserRewardsSummary.fromJson(summary(4.25)).rewardsPercent, 4.25);
      expect(UserRewardsSummary.fromJson(summary('3')).rewardsPercent, 3.0);
    });

    test('is absent when the service reports none', () {
      for (final value in [null, 'n/a', -1, double.nan]) {
        expect(UserRewardsSummary.fromJson(summary(value)).rewardsPercent,
            isNull,
            reason: '$value');
      }
    });

    test('a payout row without a rate carries none', () {
      final row = RewardPayout.fromJson({'day': '2026-09-28'});
      expect(row.annualRewardsBps, isNull);
      expect(row.annualRewardsPercent, isNull);
      final rated =
          RewardPayout.fromJson({'day': '2026-09-28', 'annualRewardsBps': 350});
      expect(rated.annualRewardsPercent, 3.5);
    });
  });
}
