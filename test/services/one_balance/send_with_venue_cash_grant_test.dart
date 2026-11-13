// The Dollars send's one approval when venue cash comes home for it
// (OrchestraGrants.sendWithVenueCash): asked before anything moves, then
// the send's settlement runs under it with no second prompt, and only
// within what was approved (OrchestraGrants.takeSend).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart' show OrchestraGrants;
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;

const _to = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';
const _route = 'spark_usdb>arbitrum_usdc';

AuthGrant _grant({BigInt? amountMax}) => AuthGrants.issue(
    OrchestraGrants.sendWithVenueCash(
      walletId: 'spending',
      recipient: _to,
      routeLabel: _route,
      asset: 'USDB',
      amountMax: amountMax ?? BigInt.from(150000000),
    ),
    method: AuthGrantMethod.biometric);

SettlementAuthorizationIntent _auth({
  String walletId = 'spending',
  String recipient = _to,
  String version = '',
  String route = _route,
  int amountIn = 150000000,
}) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.sendExternal,
      walletId: walletId,
      destination: '$recipient|$version',
      routeLabel: route,
      amountIn: BigInt.from(amountIn),
      minReceive: BigInt.one,
      maxFeeBps: 100,
    );

void main() {
  test('covers the send it was asked for, once', () {
    final grant = _grant();
    expect(OrchestraGrants.takeSend(grant, _auth(), asset: 'USDB'), isTrue);
    expect(grant.consumed, isTrue);
    expect(OrchestraGrants.takeSend(grant, _auth(), asset: 'USDB'), isFalse,
        reason: 'single use');
  });

  test('a recipient in another case is the same address', () {
    expect(
        OrchestraGrants.takeSend(
            _grant(), _auth(recipient: _to.toLowerCase()),
            asset: 'USDB'),
        isTrue);
  });

  test('less than approved is covered', () {
    expect(
        OrchestraGrants.takeSend(_grant(), _auth(amountIn: 149000000),
            asset: 'USDB'),
        isTrue);
  });

  test('refuses anything else, and the grant stays unused', () {
    for (final auth in [
      _auth(amountIn: 150000001),
      _auth(recipient: '0x0000000000000000000000000000000000000001'),
      _auth(route: 'spark_usdb>polygon_usdc'),
      _auth(version: 'v2'),
      _auth(walletId: 'other'),
      _auth(amountIn: 0),
    ]) {
      final grant = _grant();
      expect(OrchestraGrants.takeSend(grant, auth, asset: 'USDB'), isFalse);
      expect(grant.consumed, isFalse);
    }
    expect(
        OrchestraGrants.takeSend(_grant(), _auth(), asset: 'BTC'), isFalse);
  });

  test('a revoked approval covers nothing', () {
    final grant = _grant()..revoke();
    expect(OrchestraGrants.takeSend(grant, _auth(), asset: 'USDB'), isFalse);
  });
}
