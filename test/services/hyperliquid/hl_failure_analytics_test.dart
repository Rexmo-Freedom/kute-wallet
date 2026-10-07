// Every Investing order failure carries the step it ended at, and an
// exchange rejection carries its class and the exchange's own words,
// cleaned of addresses and figures.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  test('exchange rejections fall into closed classes', () {
    expect(hlRefusalClass('Insufficient margin to place order. asset=5'),
        'insufficient_margin');
    expect(hlRefusalClass(r'Order must have minimum value of $10.'),
        'below_min_notional');
    expect(
        hlRefusalClass('Order could not immediately match against any '
            'resting orders. asset=0'),
        'ioc_no_match');
    expect(hlRefusalClass('Price must be divisible by tick size. asset=3'),
        'invalid_tick');
    expect(hlRefusalClass('Reduce only order would increase position.'),
        'reduce_only');
    expect(
        hlRefusalClass('User or API Wallet '
            '0x1111111111111111111111111111111111111111 does not exist.'),
        'unknown_signer');
    expect(hlRefusalClass('Something new'), 'other');
  });

  test('each failure names its stage', () {
    expect(hlFailureStage(const HyperliquidMinNotionalException('x')),
        'submit');
    expect(hlFailureStage(const HyperliquidSignatureRejectedException('x')),
        'sign');
    expect(hlFailureStage(TimeoutException('x')), 'timeout');
    expect(hlFailureStage(const SocketException('offline')), 'network');
    expect(hlFailureStage(const GrantExpired()), 'grant_expired');
    expect(hlFailureStage(const GrantRevoked()), 'user_declined');
    expect(hlFailureStage(ReauthRequired(const {})), 'reauth');
    expect(
        hlFailureStage(
            const HyperliquidApiException(statusCode: 500, body: 'oops')),
        'submit');
  });

  test('the failure event carries them, never the signer address', () {
    final events = <Map<String, Object>?>[];
    TrackingService.debugTrackObserver = (e, p) {
      if (e == 'hyperliquid_order_failed') events.add(p);
    };
    addTearDown(() => TrackingService.debugTrackObserver = null);
    const error = HyperliquidSignatureRejectedException('User or API Wallet '
        '0x1111111111111111111111111111111111111111 does not exist.');
    TrackingService.hyperliquidOrderFailed(
        coin: 'BTC',
        reason: 'signature_invalid',
        action: 'open',
        extra: hlFailureParams(error));
    final params = events.single!;
    expect(params['stage'], 'sign');
    expect(params['refusal_class'], 'unknown_signer');
    expect(params['venue_refusal'], 'user or api wallet does not exist');
    expect(params.values.join(' '), isNot(contains('0x')));
  });
}
