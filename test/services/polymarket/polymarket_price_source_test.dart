import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart';

void main() {
  group('PmPriceSourcePolicy.select', () {
    test('no CLOB credentials → RTDS (users without a Polymarket account)', () {
      final policy = PmPriceSourcePolicy();
      expect(policy.select(hasClobCredentials: false), PmPriceSource.rtds);
    });

    test('credentials present → PolyBolt', () {
      final policy = PmPriceSourcePolicy();
      expect(policy.select(hasClobCredentials: true), PmPriceSource.polyBolt);
    });

    test('credentials present but PolyBolt failed → RTDS, sticky', () {
      final policy = PmPriceSourcePolicy();
      policy.markActive(PmPriceSource.polyBolt);
      expect(policy.markPolyBoltFailed(), PmPriceSource.rtds);
      expect(policy.polyBoltFailed, isTrue);
      expect(policy.select(hasClobCredentials: true), PmPriceSource.rtds);
      expect(policy.select(hasClobCredentials: true), PmPriceSource.rtds,
          reason: 'no flapping back within the session');
    });

    test('a fresh policy forgets the failure (new build / tab session)', () {
      final failed = PmPriceSourcePolicy()..markPolyBoltFailed();
      expect(failed.select(hasClobCredentials: true), PmPriceSource.rtds);
      expect(PmPriceSourcePolicy().select(hasClobCredentials: true),
          PmPriceSource.polyBolt);
    });
  });

  group('PmPriceSourcePolicy.shouldUpgrade', () {
    test('RTDS active and credentials arrive → upgrade', () {
      final policy = PmPriceSourcePolicy()..markActive(PmPriceSource.rtds);
      expect(policy.shouldUpgrade(hasClobCredentials: true), isTrue);
    });

    test('RTDS active, still no credentials → stay', () {
      final policy = PmPriceSourcePolicy()..markActive(PmPriceSource.rtds);
      expect(policy.shouldUpgrade(hasClobCredentials: false), isFalse);
    });

    test('PolyBolt already active → no reconnect churn', () {
      final policy = PmPriceSourcePolicy()..markActive(PmPriceSource.polyBolt);
      expect(policy.shouldUpgrade(hasClobCredentials: true), isFalse);
    });

    test('RTDS active because PolyBolt failed → never upgrade this session', () {
      final policy = PmPriceSourcePolicy()
        ..markActive(PmPriceSource.polyBolt)
        ..markPolyBoltFailed()
        ..markActive(PmPriceSource.rtds);
      expect(policy.shouldUpgrade(hasClobCredentials: true), isFalse);
    });

    test('nothing connected yet → not an upgrade', () {
      expect(PmPriceSourcePolicy().shouldUpgrade(hasClobCredentials: true),
          isFalse);
    });
  });
}
