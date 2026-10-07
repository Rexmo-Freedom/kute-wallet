// The small-action step-up allowance (D-11) is a backend runtime-policy
// setting. It reads `security.smallActionAllowanceCents` from the current
// fresh capabilities snapshot and nothing else: no snapshot, a stale one or
// a backend outage leaves it off.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/small_action_allowance.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

class _Session implements StepUpSessionState {
  const _Session(this.isSessionUnlocked);
  @override
  final bool isSessionUnlocked;
}

RuntimeCapabilities _snapshot({Object? security}) {
  final now = DateTime.utc(2026, 9, 30, 12);
  // Round-trip through JSON so the map types match a real response.
  return RuntimeCapabilities.fromJson(jsonDecode(jsonEncode({
    'schemaVersion': 1,
    'revision': 7,
    'evaluatedAt': now.toIso8601String(),
    'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
    'capabilities': {
      'polymarket.trade': {'allowed': true, 'reason': ''},
    },
    'fees': {},
    'ai': {},
    'referral': {'refereeDiscountBps': 20},
    if (security != null) 'security': security,
  })) as Map<String, dynamic>);
}

SensitiveIntent _bet(int usdCents, {String venue = 'polymarket'}) =>
    SensitiveIntent(
      action: SensitiveAction.pmBet,
      walletId: 'wallet-a',
      venue: venue,
      asset: 'USDC.e',
      amountMax: BigInt.from(usdCents) * BigInt.from(10000),
    );

SensitiveIntent _hlOrder({required String kind, required String side}) =>
    SensitiveIntent(
      action: SensitiveAction.hlOrder,
      walletId: 'wallet-a',
      venue: 'hyperliquid',
      asset: 'USDC',
      amountMax: BigInt.from(100) * BigInt.from(10000),
      limits: {IntentLimit.orderKind: kind, IntentLimit.side: side},
    );

AuthGrant? _issue(SmallActionAllowance allowance, SensitiveIntent intent,
        {int? cents, bool unlocked = true, bool fundingLeg = false}) =>
    allowance.tryIssue(intent,
        amountUsdCents: cents ?? 100,
        paidFromVenueBalance: true,
        hasFundingLeg: fundingLeg,
        session: _Session(unlocked));

void main() {
  test('the snapshot model parses security.smallActionAllowanceCents', () {
    expect(_snapshot().smallActionAllowanceCents, 0);
    expect(_snapshot(security: {}).smallActionAllowanceCents, 0);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': 250})
            .smallActionAllowanceCents,
        250);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': 0})
            .smallActionAllowanceCents,
        0);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': -5})
            .smallActionAllowanceCents,
        0);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': '250'})
            .smallActionAllowanceCents,
        0);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': 2.5})
            .smallActionAllowanceCents,
        2);
    // Other sections are untouched.
    expect(
        _snapshot(security: {'smallActionAllowanceCents': 250})
            .refereeDiscountBps,
        20);
  });

  test('off without a fresh snapshot, when unset, and when the read throws',
      () {
    expect(SmallActionAllowance(readSnapshot: () => null).enabled, isFalse);
    expect(
        SmallActionAllowance(readSnapshot: () => _snapshot()).enabled, isFalse);
    expect(
        SmallActionAllowance(
            readSnapshot: () =>
                _snapshot(security: {'smallActionAllowanceCents': 0})).enabled,
        isFalse);
    final throwing =
        SmallActionAllowance(readSnapshot: () => throw StateError('down'));
    expect(throwing.enabled, isFalse);
    expect(throwing.perActionCapCents, 0);
    expect(_issue(SmallActionAllowance(readSnapshot: () => null), _bet(100)),
        isNull);
  });

  test('follows the current snapshot on every read, with the client clamp', () {
    RuntimeCapabilities? current;
    final allowance = SmallActionAllowance(readSnapshot: () => current);
    expect(allowance.enabled, isFalse);
    current = _snapshot(security: {'smallActionAllowanceCents': 250});
    expect(allowance.perActionCapCents, 250);
    current = _snapshot(security: {'smallActionAllowanceCents': 9000});
    expect(allowance.perActionCapCents, SmallActionAllowance.maxPerActionCents);
    // The policy went away (expired, session changed, backend down): off
    // at the next use, without any refresh call.
    current = null;
    expect(allowance.enabled, isFalse);
    expect(_issue(allowance, _bet(100)), isNull);
    expect(SmallActionAllowance.clampCents(null), 0);
    expect(SmallActionAllowance.clampCents(-1), 0);
    expect(SmallActionAllowance.clampCents(500), 500);
    expect(SmallActionAllowance.clampCents(501), 500);
  });

  test('issues allowance grants inside scope and within both caps', () {
    final allowance = SmallActionAllowance(
        readSnapshot: () =>
            _snapshot(security: {'smallActionAllowanceCents': 300}));
    final grant = _issue(allowance, _bet(300), cents: 300);
    expect(grant, isNotNull);
    expect(grant!.method, AuthGrantMethod.allowance);
    expect(allowance.sessionSpentCents, 300);
    expect(_issue(allowance, _bet(301), cents: 301), isNull);
    expect(_issue(allowance, _bet(100), unlocked: false), isNull);
    expect(_issue(allowance, _bet(100), fundingLeg: true), isNull);
    expect(_issue(allowance, _bet(100, venue: 'other')), isNull);
    // Base units larger than the quoted cents cannot slip through.
    expect(_issue(allowance, _bet(400), cents: 100), isNull);
    expect(_issue(allowance, _hlOrder(kind: 'spot', side: 'buy')), isNotNull);
    expect(_issue(allowance, _hlOrder(kind: 'perp', side: 'buy')), isNull);
    expect(_issue(allowance, _hlOrder(kind: 'spot', side: 'sell')), isNull);
    // Session cap: 300 + 100 spent so far; 2,500 in total per session.
    for (var i = 0; i < 7; i++) {
      expect(_issue(allowance, _bet(300), cents: 300), isNotNull);
    }
    expect(allowance.sessionSpentCents, 2500);
    expect(_issue(allowance, _bet(1), cents: 1), isNull);
    allowance.reset();
    expect(allowance.sessionSpentCents, 0);
    expect(_issue(allowance, _bet(1), cents: 1), isNotNull);
  });
}
