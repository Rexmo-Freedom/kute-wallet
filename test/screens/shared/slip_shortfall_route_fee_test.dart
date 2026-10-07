import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';

OrchestraEstimate _estimate({String? includes, String? bps}) =>
    OrchestraEstimate.fromJson({
      'estimatedOut': '19880000',
      'feeAmount': '0',
      'feeBps': 0,
    }, headers: {
      if (includes != null) 'X-Kute-Estimate-Includes-App-Fee': includes,
      if (bps != null) 'X-Kute-App-Fee-Bps': bps,
    });

void main() {
  group('slipRouteFeeFrom', () {
    test('an estimate without the Kute fee counts the rate it reports', () {
      final fee = slipRouteFeeFrom(_estimate(includes: 'false', bps: '50'),
          sentUsd: 20, arrivingUsd: 19.88);
      expect(fee!.fee, closeTo(0.006, 1e-9));
      expect(fee.kuteBps, 50);
    });

    test('a missing header reads as excluded, like the backend reports', () {
      final fee = slipRouteFeeFrom(_estimate(bps: '35'),
          sentUsd: 20, arrivingUsd: 19.88);
      expect(fee!.kuteBps, 35);
    });

    test('a discounted or zero rate is used as reported', () {
      expect(
          slipRouteFeeFrom(_estimate(includes: 'false', bps: '0'),
                  sentUsd: 20, arrivingUsd: 19.88)!
              .kuteBps,
          0);
    });

    test('an estimate that already took the Kute fee does not count it twice',
        () {
      final fee = slipRouteFeeFrom(_estimate(includes: 'true', bps: '50'),
          sentUsd: 20, arrivingUsd: 19.78);
      expect(fee!.fee, closeTo(0.011, 1e-9));
      expect(fee.kuteBps, 0);
    });

    test('an excluded Kute fee at an unknown rate is not read as zero', () {
      expect(
          slipRouteFeeFrom(_estimate(includes: 'false'),
              sentUsd: 20, arrivingUsd: 19.88),
          isNull);
      expect(
          slipRouteFeeFrom(_estimate(includes: 'false', bps: '10000'),
              sentUsd: 20, arrivingUsd: 19.88),
          isNull);
    });
  });
}
