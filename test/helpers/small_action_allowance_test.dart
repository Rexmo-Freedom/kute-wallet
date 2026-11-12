// The small-action step-up allowance (D-11, widened 2026-11-12: orders
// under $50 skip Face ID / PIN while unlocked) is a backend runtime-policy
// setting. It reads `security.smallActionAllowanceCents` from the current
// fresh capabilities snapshot and nothing else: no snapshot, a stale one or
// a backend outage leaves it off. Scope: Predictions buys and sells
// (combos too), Investing market and limit orders, closes and margin adds,
// with or without a funding leg from the person's own accounts. Never
// sends, withdrawals, gifts, Swap, leverage, Pro orders or the Builder.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/small_action_allowance.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart'
    show kFundUsdLimit, kFundVenueLimit, kFundVenueInvesting;
import 'package:kute/services/runtime_capabilities_service.dart';

class _Session implements StepUpSessionState {
  const _Session(this.isSessionUnlocked);
  @override
  final bool isSessionUnlocked;
}

RuntimeCapabilities _snapshot({Object? security}) {
  final now = DateTime.utc(2026, 11, 12, 12);
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

/// The policy the deploy of 2026-11-12 publishes: orders under $50.
RuntimeCapabilities _on() =>
    _snapshot(security: {'smallActionAllowanceCents': 5000});

const _perp = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

const _spot = HlMarket(
  coin: 'HYPE',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 40,
  midPx: 40,
  prevDayPx: 40,
  dayNtlVlm: 0,
);

const _w = 'wallet-a';

int _cents(double usd) => (usd * 100).round();

// ── Predictions ──────────────────────────────────────────────────────

SensitiveIntent _bet(double usd, {String orderType = 'fok'}) =>
    PmGrants.betReview(
        walletId: _w,
        tokenId: '0xyes',
        maxCostUsd: usd,
        worstPrice: 0.55,
        orderType: orderType);

SensitiveIntent _sell(double shares, double worst) => PmGrants.sellReview(
    walletId: _w,
    tokenId: '0xyes',
    shares: shares,
    worstPrice: worst,
    orderType: 'fok');

Map<String, Object?> _directLegs(String to) =>
    DirectLegGrants.limit(destination: to, capsUsd: {'investing': 3})!;

Map<String, Object?> _btcLeg({String? direct, String? directRoute}) => {
      ...BitcoinLegGrants.limit(maxSats: 20000, ownSpark: 'sp1ownspark'),
      if (direct != null)
        'direct': {
          'route': directRoute ?? BitcoinLegGrants.directRouteOf(direct),
          'to': '0xowndeposit',
          'maxSats': '10000',
        },
    };

SensitiveIntent _fundedBet(double usd,
        {String venue = IntentVenue.polymarket,
        Map<String, Object?>? directLegs,
        Map<String, Object?>? btcLeg}) =>
    PmGrants.fundedBetReview(_bet(usd),
        fundUsd: usd + 1,
        venue: venue,
        directLegs: directLegs,
        btcLeg: btcLeg);

// ── Investing ────────────────────────────────────────────────────────

SensitiveIntent _open(double usd, {int leverage = 1}) => HlIntents.openPosition(
    walletId: _w,
    market: _perp,
    isLong: true,
    marginUsd: usd,
    leverage: leverage,
    isCross: true);

SensitiveIntent _spotOrder(double usd, {bool buy = true}) =>
    HlIntents.spotOrder(walletId: _w, market: _spot, isBuy: buy, usd: usd);

SensitiveIntent _limit(double usd, {bool reduceOnly = false}) =>
    HlIntents.limit(
        walletId: _w,
        market: _perp,
        isLong: true,
        marginUsd: usd,
        px: 59000,
        reduceOnly: reduceOnly);

SensitiveIntent _close(double fraction) => HlIntents.close(
    walletId: _w, market: _perp, positionIsLong: true, fraction: fraction);

SensitiveIntent _fundedHl(SensitiveIntent order,
        {String fundVenue = kFundVenueInvesting,
        Map<String, Object?>? directLegs,
        Map<String, Object?>? btcLeg}) =>
    order.copyWith(limits: {
      ...order.limits,
      kFundUsdLimit: '5000000',
      kFundVenueLimit: fundVenue,
      if (directLegs != null) VenueLimit.directLegs: directLegs,
      if (btcLeg != null) VenueLimit.fundBtc: btcLeg,
    });

// ── Never in scope ───────────────────────────────────────────────────

SensitiveIntent _send(SensitiveAction action, {String asset = 'USDC'}) =>
    SensitiveIntent(
      action: action,
      walletId: _w,
      venue: IntentVenue.orchestra,
      destination: 'sp1someoneelse',
      asset: asset,
      amountMax: IntentUnits.usd(10),
      limits: const {IntentLimit.provider: 'orchestra'},
    );

AuthGrant? _issue(SmallActionAllowance allowance, SensitiveIntent intent,
        {double usd = 10, int? cents, bool unlocked = true}) =>
    allowance.tryIssue(intent,
        amountUsdCents: cents ?? _cents(usd), session: _Session(unlocked));

void main() {
  test('the snapshot model parses security.smallActionAllowanceCents', () {
    expect(_snapshot().smallActionAllowanceCents, 0);
    expect(_snapshot(security: {}).smallActionAllowanceCents, 0);
    expect(
        _snapshot(security: {'smallActionAllowanceCents': 5000})
            .smallActionAllowanceCents,
        5000);
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
    expect(_issue(throwing, _bet(10)), isNull);
    expect(_issue(SmallActionAllowance(readSnapshot: () => null), _bet(10)),
        isNull);
    expect(_issue(SmallActionAllowance(readSnapshot: _snapshot), _bet(10)),
        isNull);
  });

  test('follows the current snapshot on every read, clamped to \$50', () {
    RuntimeCapabilities? current;
    final allowance = SmallActionAllowance(readSnapshot: () => current);
    expect(allowance.enabled, isFalse);
    current = _snapshot(security: {'smallActionAllowanceCents': 250});
    expect(allowance.perActionCapCents, 250);
    current = _on();
    expect(allowance.perActionCapCents, 5000);
    current = _snapshot(security: {'smallActionAllowanceCents': 90000});
    expect(allowance.perActionCapCents, SmallActionAllowance.maxPerActionCents);
    expect(SmallActionAllowance.maxPerActionCents, 5000);
    expect(SmallActionAllowance.sessionCapCents, 25000);
    // The policy went away (expired, session changed, backend down): off
    // at the next use, without any refresh call.
    current = null;
    expect(allowance.enabled, isFalse);
    expect(_issue(allowance, _bet(10)), isNull);
    expect(SmallActionAllowance.clampCents(null), 0);
    expect(SmallActionAllowance.clampCents(-1), 0);
    expect(SmallActionAllowance.clampCents(5000), 5000);
    expect(SmallActionAllowance.clampCents(5001), 5000);
  });

  group('under \$50 skips the prompt', () {
    late SmallActionAllowance allowance;
    setUp(() => allowance = SmallActionAllowance(readSnapshot: _on));

    final cases = <String, (SensitiveIntent, double)>{
      'a prediction (market)': (_bet(49.99), 49.99),
      'a prediction (limit)': (_bet(20, orderType: 'gtc'), 20),
      'a prediction funded from Dollars': (_fundedBet(10), 10),
      'a prediction funded from Investing cash':
          (_fundedBet(10, directLegs: _directLegs('predictions')), 10),
      'a prediction funded from Bitcoin via Dollars':
          (_fundedBet(10, btcLeg: _btcLeg()), 10),
      'a prediction funded from Bitcoin straight to Predictions':
          (_fundedBet(10, btcLeg: _btcLeg(direct: 'predictions')), 10),
      'a prediction sell': (_sell(80, 0.5), 40),
      'a combo bet': (
        PmGrants.comboBet(
            walletId: _w,
            legPositionIds: const ['a', 'b'],
            maxStakeE6: BigInt.from(20000000),
            minPayoutE6: BigInt.from(60000000)),
        20
      ),
      'a combo close': (
        PmGrants.comboClose(
            walletId: _w,
            positionId: 'combo',
            sharesE6: BigInt.from(60000000),
            minProceedsE6: BigInt.from(30000000)),
        30.5
      ),
      'a perp open or add at 1x': (_open(49), 49),
      'a spot buy': (_spotOrder(25), 25),
      'a spot sell': (_spotOrder(25, buy: false), 25),
      'a limit order': (_limit(30), 30),
      'a reduce-only limit (close sheet)': (_limit(30, reduceOnly: true), 30),
      'a close or reduce': (_close(0.5), 45),
      'an Investing order funded from Dollars': (_fundedHl(_open(20)), 20),
      'an Investing order funded from Predictions cash': (
        _fundedHl(_open(20), directLegs: _directLegs('investing')),
        20
      ),
      'an Investing order funded from Bitcoin': (
        _fundedHl(_spotOrder(20), btcLeg: _btcLeg(direct: 'investing')),
        20
      ),
      'margin added to an own position': (
        HlIntents.isolatedMargin(
            walletId: _w, market: _perp, positionIsLong: true, usd: 15),
        15
      ),
      'margin added, funded from Dollars': (
        _fundedHl(HlIntents.isolatedMargin(
            walletId: _w, market: _perp, positionIsLong: true, usd: 15)),
        15
      ),
    };
    for (final MapEntry(key: name, value: (intent, usd)) in cases.entries) {
      test(name, () {
        expect(SmallActionAllowance.inScope(intent), isTrue);
        final grant = _issue(allowance, intent, usd: usd);
        expect(grant, isNotNull);
        expect(grant!.method, AuthGrantMethod.allowance);
        // Bound to the exact order: the executor consumes it as usual.
        AuthGrants.consume(grant, intent);
        expect(grant.consumed, isTrue);
        expect(allowance.sessionSpentCents, _cents(usd));
      });
    }
  });

  test('\$50.00 and above, or nothing, asks', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    expect(_issue(allowance, _bet(50), usd: 50), isNull);
    expect(_issue(allowance, _bet(50.01), usd: 50.01), isNull);
    expect(_issue(allowance, _open(50), usd: 50), isNull);
    expect(_issue(allowance, _sell(200, 0.5), usd: 100), isNull);
    expect(_issue(allowance, _close(1), usd: 80), isNull);
    expect(_issue(allowance, _bet(1), cents: 0), isNull);
    expect(_issue(allowance, _bet(49.99), usd: 49.99), isNotNull);
    // A lower published threshold is honoured exactly.
    final low = SmallActionAllowance(
        readSnapshot: () =>
            _snapshot(security: {'smallActionAllowanceCents': 500}));
    expect(_issue(low, _bet(5), usd: 5), isNull);
    expect(_issue(low, _bet(4.99), usd: 4.99), isNotNull);
  });

  test('the session cap asks once \$250 have gone through, until relock',
      () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    for (var i = 0; i < 5; i++) {
      expect(_issue(allowance, _bet(49.99), usd: 49.99), isNotNull);
    }
    expect(allowance.sessionSpentCents, 24995);
    expect(_issue(allowance, _bet(0.06), usd: 0.06), isNull);
    expect(_issue(allowance, _open(1), usd: 1), isNull);
    expect(_issue(allowance, _bet(0.05), usd: 0.05), isNotNull);
    expect(allowance.sessionSpentCents, SmallActionAllowance.sessionCapCents);
    expect(_issue(allowance, _bet(0.01), usd: 0.01), isNull);
    allowance.reset();
    expect(allowance.sessionSpentCents, 0);
    expect(_issue(allowance, _bet(10)), isNotNull);
  });

  test('a locked session asks', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    expect(_issue(allowance, _bet(10), unlocked: false), isNull);
    expect(allowance.sessionSpentCents, 0);
  });

  test('money leaving the wallet always asks, however small', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    for (final intent in [
      _send(SensitiveAction.send), // Send, gifts (share links), Swap out
      _send(SensitiveAction.moveTransfer), // Swap, Buy Bitcoin, Move
      _send(SensitiveAction.venueWithdraw),
      _send(SensitiveAction.venueDeposit),
      _send(SensitiveAction.sparkRefund),
      _send(SensitiveAction.depositClaim),
      HlIntents.withdraw(
          walletId: _w,
          usd: 10,
          destination: '0xown',
          destinationKind: 'own_eoa'),
      DirectLegGrants.buyBitcoin(
          walletId: _w,
          ownSpark: 'sp1own',
          route: 'spark_usdb>spark_btc',
          asset: 'USDB',
          totalUsd: 10,
          directLegs: null,
          ttl: AuthGrants.autofireTtl),
      walletSwitchIntentFor(_w),
      SensitiveIntent(
          action: SensitiveAction.biometricsToggle,
          walletId: 'app',
          venue: 'local',
          asset: 'BIOMETRICS',
          amountMax: BigInt.zero),
    ]) {
      expect(SmallActionAllowance.inScope(intent), isFalse,
          reason: intent.action.name);
      expect(_issue(allowance, intent), isNull, reason: intent.action.name);
    }
    expect(allowance.sessionSpentCents, 0);
  });

  test('leverage, Pro orders, edits and the Builder always ask', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    for (final intent in [
      _open(10, leverage: 3),
      HlIntents.marginMode(
          walletId: _w, market: _perp, isCross: true, leverage: 2),
      HlIntents.isolatedMargin(
          walletId: _w, market: _perp, positionIsLong: true, usd: -10),
      HlIntents.scale(
          walletId: _w,
          market: _perp,
          isLong: true,
          totalUsd: 10,
          startPx: 1,
          endPx: 2,
          count: 3),
      HlIntents.twap(
          walletId: _w,
          market: _perp,
          isLong: true,
          marginUsd: 10,
          durationMinutes: 30),
      HlIntents.trigger(
          walletId: _w,
          market: _perp,
          isLong: false,
          size: 0.0001,
          triggerPx: 50000,
          isMarket: true,
          tpsl: 'sl'),
      HlIntents.trailingStop(
          walletId: _w,
          market: _perp,
          isLong: false,
          size: 0.0001,
          trail: const HlTrailingStop(retracement: 1)),
      HlIntents.modify(
          walletId: _w,
          market: _perp,
          oid: 7,
          isLong: true,
          size: 0.0001,
          px: 59000,
          reduceOnly: false),
      PmGrants.builderRun(walletId: _w, legs: [_bet(2), _bet(3)]),
    ]) {
      expect(SmallActionAllowance.inScope(intent), isFalse,
          reason: intent.limits.toString());
      expect(_issue(allowance, intent), isNull);
    }
  });

  test('a funding leg that is not the order venue\'s own asks', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    for (final intent in [
      // A prediction whose Dollars leg names Investing.
      _fundedBet(10, venue: IntentVenue.hyperliquid),
      // Venue cash sent anywhere but Predictions.
      _fundedBet(10, directLegs: _directLegs('bitcoin')),
      _fundedBet(10, directLegs: _directLegs('investing')),
      // A Bitcoin leg on another route, or straight to the wrong venue.
      _fundedBet(10, btcLeg: {..._btcLeg(), 'route': 'spark_btc>base_usdc'}),
      _fundedBet(10, btcLeg: _btcLeg(direct: 'investing')),
      _fundedBet(10,
          btcLeg: _btcLeg(direct: 'predictions', directRoute: 'spark_btc>x')),
      // An Investing order whose legs go elsewhere.
      _fundedHl(_open(10), fundVenue: 'predictions'),
      _fundedHl(_open(10), directLegs: _directLegs('dollars')),
      _fundedHl(_open(10), btcLeg: _btcLeg(direct: 'predictions')),
      // Funding keys of the other venue, or half a leg.
      _bet(10).copyWith(limits: {..._bet(10).limits, kFundUsdLimit: '1'}),
      _open(10).copyWith(
          limits: {..._open(10).limits, VenueLimit.fundingUsd: '1'}),
      _open(10).copyWith(limits: {..._open(10).limits, kFundUsdLimit: '1'}),
      // Sells, closes and combos never carry a funding leg.
      _close(0.5).copyWith(limits: {
        ..._close(0.5).limits,
        kFundUsdLimit: '1',
        kFundVenueLimit: kFundVenueInvesting
      }),
    ]) {
      expect(SmallActionAllowance.inScope(intent), isFalse,
          reason: intent.limits.toString());
      expect(_issue(allowance, intent), isNull);
    }
  });

  test('an amount that does not match the order asks', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    // A $60 bet stated as $10.
    expect(_issue(allowance, _bet(60), usd: 10), isNull);
    // A $60 Investing order stated as $10.
    expect(_issue(allowance, _open(60), usd: 10), isNull);
    expect(_issue(allowance, _spotOrder(60), usd: 10), isNull);
    // 200 shares that pay at least $0.50 each, stated as $40.
    expect(_issue(allowance, _sell(200, 0.5), usd: 40), isNull);
    // A combo close that must pay at least $60, stated as $10.
    expect(
        _issue(
            allowance,
            PmGrants.comboClose(
                walletId: _w,
                positionId: 'combo',
                sharesE6: BigInt.from(90000000),
                minProceedsE6: BigInt.from(60000000)),
            usd: 10),
        isNull);
    expect(allowance.sessionSpentCents, 0);
  });

  test('the grant comes from the caller\'s store, as an allowance grant', () {
    final allowance = SmallActionAllowance(readSnapshot: _on);
    SensitiveIntent? asked;
    final grant = allowance.tryIssue(_bet(10),
        amountUsdCents: 1000,
        session: const _Session(true), issue: (i) {
      asked = i;
      return AuthGrants.issue(i, method: AuthGrantMethod.allowance);
    });
    expect(grant, isNotNull);
    expect(asked, isNotNull);
    // A store that refuses (a malformed intent) books nothing.
    expect(
        allowance.tryIssue(_bet(10),
            amountUsdCents: 1000,
            session: const _Session(true),
            issue: (_) => throw ArgumentError('bad')),
        isNull);
    expect(allowance.sessionSpentCents, 1000);
  });
}

SensitiveIntent walletSwitchIntentFor(String walletId) => SensitiveIntent(
      action: SensitiveAction.walletSwitch,
      walletId: walletId,
      venue: 'local',
      asset: 'WALLET',
      amountMax: BigInt.zero,
    );
