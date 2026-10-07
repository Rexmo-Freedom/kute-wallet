import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  group('TrackingService.generateUuidV4', () {
    test('produces valid UUID v4 format', () {
      final uuid = TrackingService.generateUuidV4();
      // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      // where y is one of [8, 9, a, b]
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(pattern.hasMatch(uuid), isTrue, reason: 'UUID "$uuid" does not match v4 format');
    });

    test('has correct length (36 chars with hyphens)', () {
      final uuid = TrackingService.generateUuidV4();
      expect(uuid.length, 36);
    });

    test('version nibble is always 4', () {
      for (var i = 0; i < 100; i++) {
        final uuid = TrackingService.generateUuidV4();
        // The 13th character (index 14 with hyphens) is the version nibble
        expect(uuid[14], '4', reason: 'Version nibble should be 4 in "$uuid"');
      }
    });

    test('variant bits are correct (10xx = 8, 9, a, or b)', () {
      for (var i = 0; i < 100; i++) {
        final uuid = TrackingService.generateUuidV4();
        // The 17th character (index 19 with hyphens) is the variant nibble
        final variant = uuid[19];
        expect(
          ['8', '9', 'a', 'b'].contains(variant),
          isTrue,
          reason: 'Variant nibble "$variant" should be 8, 9, a, or b in "$uuid"',
        );
      }
    });

    test('generates unique UUIDs', () {
      final uuids = <String>{};
      for (var i = 0; i < 1000; i++) {
        uuids.add(TrackingService.generateUuidV4());
      }
      expect(uuids.length, 1000, reason: 'All 1000 UUIDs should be unique');
    });

    test('uses only lowercase hex characters and hyphens', () {
      for (var i = 0; i < 50; i++) {
        final uuid = TrackingService.generateUuidV4();
        final validChars = RegExp(r'^[0-9a-f\-]+$');
        expect(validChars.hasMatch(uuid), isTrue,
            reason: 'UUID should only contain lowercase hex and hyphens');
      }
    });

    test('hyphens are at correct positions', () {
      final uuid = TrackingService.generateUuidV4();
      expect(uuid[8], '-');
      expect(uuid[13], '-');
      expect(uuid[18], '-');
      expect(uuid[23], '-');
    });
  });

  group('wallet guard event params', () {
    const forbidden = {
      'amount',
      'amount_bucket',
      'address',
      'deposit_address',
      'recipient',
      'quoteId',
      'quote_id',
      'order_id',
    };

    final builders = <String, (Map<String, Object>, Set<String>)>{
      'orchestra_quote_rejected': (
        TrackingService.orchestraQuoteRejectedParams(
            flow: 'pm_deposit',
            route: 'spark_btc>polygon_usdc.e',
            reason: 'expired'),
        {'flow', 'route', 'reason'},
      ),
      'orchestra_quote_requoted': (
        TrackingService.orchestraQuoteRequotedParams(flow: 'pm_deposit'),
        {'flow'},
      ),
      'orchestra_decimals_mismatch': (
        TrackingService.orchestraDecimalsMismatchParams(
            chain: 'bsc', asset: 'USDC'),
        {'chain', 'asset'},
      ),
      'hl_builder_config_rejected': (
        TrackingService.hlBuilderConfigRejectedParams(reason: 'address'),
        {'reason'},
      ),
      'hl_withdraw_destination_rejected': (
        TrackingService.hlWithdrawDestinationRejectedParams(
            kind: 'accumulation'),
        {'kind'},
      ),
      'accumulation_address_reverify_failed': (
        TrackingService.accumulationAddressReverifyFailedParams(
            reason: 'deposit_format'),
        {'reason'},
      ),
      'wallet_auth_challenge': (
        TrackingService.walletAuthChallengeParams(mode: 'v2'),
        {'mode'},
      ),
      'wallet_session_auth': (
        TrackingService.walletSessionAuthParams(
            route: 'orchestra', outcome: 'reauth'),
        {'route', 'outcome'},
      ),
    };

    builders.forEach((event, spec) {
      test('$event emits only its allowlisted keys', () {
        final (params, allowed) = spec;
        expect(params.keys.toSet(), allowed);
        expect(params.keys.toSet().intersection(forbidden), isEmpty);
        for (final value in params.values) {
          expect(value, isA<String>());
          expect(value as String, isNot(matches(RegExp(r'0x[0-9a-fA-F]{6,}'))));
        }
      });
    });

    test('the emitted events carry the builder params unchanged', () {
      final seen = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => seen.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);

      TrackingService.orchestraQuoteRequoted(flow: 'pm_withdraw');
      TrackingService.accumulationAddressReverifyFailed(reason: 'recipient');
      TrackingService.walletAuthChallenge(mode: 'v2');
      TrackingService.walletSessionAuth(route: 'pm_relay', outcome: 'unavailable');

      expect(seen.map((e) => e.$1), [
        'orchestra_quote_requoted',
        'accumulation_address_reverify_failed',
        'wallet_auth_challenge',
        'wallet_session_auth',
      ]);
      expect(seen.map((e) => e.$2), [
        <String, Object>{'flow': 'pm_withdraw'},
        <String, Object>{'reason': 'recipient'},
        <String, Object>{'mode': 'v2'},
        <String, Object>{'route': 'pm_relay', 'outcome': 'unavailable'},
      ]);
    });
  });
}
