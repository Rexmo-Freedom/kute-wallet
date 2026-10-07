// The Polymarket short-round fast-bet window: one prompt opens 10 minutes
// of one-tap orders on 5 and 15 minute Up/Down rounds, up to $50 of buys,
// and every way out of it ends it.

import 'dart:ui' show AppLifecycleState;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';

const _short5 = 'btc-updown-5m-1791152100';
const _short15 = 'eth-updown-15m-1791152100';
const _hourly = 'btc-updown-4h-1791144000';
const _normal = 'will-it-rain-in-lisbon-tomorrow';

const _shortReq = FastBetRequest(eventSlug: _short5, hot: true);
final _session = Object();

SensitiveIntent _buy(int cents, {String wallet = 'w1', int? baseCents}) =>
    PmIntents.order(
      walletId: wallet,
      tokenId: '0xabc',
      isBuy: true,
      amountMax: BigInt.from(baseCents ?? cents) * BigInt.from(10000),
      limitPrice: 0.55,
      orderType: 'fok',
      maxSlippageBps: 200,
    );

SensitiveIntent _sell({String wallet = 'w1'}) => PmIntents.order(
      walletId: wallet,
      tokenId: '0xabc',
      isBuy: false,
      amountMax: IntentUnits.size(10),
      limitPrice: 0.40,
      orderType: 'fok',
    );

void main() {
  late DateTime now;
  late FastBetWindow window;

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    window = FastBetWindow(
      clock: () => now,
      registry: AuthGrantRegistry(clock: () => now),
    );
    AuthGrants.clock = () => now;
  });

  tearDown(() => AuthGrants.clock = DateTime.now);

  void openWith({
    AuthGrantMethod method = AuthGrantMethod.biometric,
    FastBetRequest request = _shortReq,
    SensitiveIntent? intent,
    Object? session,
  }) {
    window.open(
      intent ?? _buy(500),
      request: request,
      method: method,
      session: session ?? _session,
      sessionUnlocked: true,
    );
  }

  AuthGrant? tap(SensitiveIntent intent,
          {int? cents,
          FastBetRequest request = _shortReq,
          Object? session,
          bool unlocked = true}) =>
      window.tryIssue(
        intent,
        request: request,
        amountUsdCents: cents ??
            (intent.action == SensitiveAction.pmBet
                ? PmGrants.usdCentsCeil(intent.amountMax)
                : 0),
        session: session ?? _session,
        sessionUnlocked: unlocked,
      );

  group('eligibility', () {
    test('5 and 15 minute Up/Down rounds only', () {
      expect(polyIsFastBetRound(_short5), isTrue);
      expect(polyIsFastBetRound(_short15), isTrue);
      expect(polyIsFastBetRound(_hourly), isFalse);
      expect(polyIsFastBetRound('bitcoin-up-or-down-october-4-2026-6pm-et'),
          isFalse);
      expect(polyIsFastBetRound(_normal), isFalse);
      expect(polyIsFastBetRound(null), isFalse);
      expect(const FastBetRequest(eventSlug: _short5, hot: false).eligible,
          isFalse,
          reason: 'a Ledger order is never eligible');
    });
  });

  group('opening', () {
    test('the first approval opens the window', () {
      window.enterScope();
      expect(window.isOpen, isFalse);
      openWith();
      expect(window.isOpen, isTrue);
      expect(window.spentCents, 0);
    });

    test('a PIN fallback approval opens it too', () {
      window.enterScope();
      openWith(method: AuthGrantMethod.pin);
      expect(window.isOpen, isTrue);
    });

    test('an allowance or fast-window grant never opens one', () {
      window.enterScope();
      openWith(method: AuthGrantMethod.allowance);
      expect(window.isOpen, isFalse);
      openWith(method: AuthGrantMethod.fastWindow);
      expect(window.isOpen, isFalse);
    });

    test('nothing opens without a short-round screen up', () {
      openWith();
      expect(window.isOpen, isFalse);
    });

    test('nothing opens while locked or without a session', () {
      window.enterScope();
      window.open(_buy(500),
          request: _shortReq,
          method: AuthGrantMethod.biometric,
          session: _session,
          sessionUnlocked: false);
      expect(window.isOpen, isFalse);
      window.open(_buy(500),
          request: _shortReq,
          method: AuthGrantMethod.biometric,
          session: null,
          sessionUnlocked: true);
      expect(window.isOpen, isFalse);
    });

    test('a sell approval opens it', () {
      window.enterScope();
      openWith(intent: _sell());
      expect(window.isOpen, isTrue);
    });
  });

  group('one tap', () {
    setUp(() {
      window.enterScope();
      openWith();
    });

    test('the second bet gets a grant without a prompt', () {
      final intent = _buy(1000);
      final grant = tap(intent);
      expect(grant, isNotNull);
      expect(grant!.method, AuthGrantMethod.fastWindow);
      expect(FastBetWindow.approvalParam(grant.method), 'fast_window');
      // The same single-use grant a prompt gives, bound to this order.
      AuthGrants.consume(grant, intent);
      expect(() => AuthGrants.consume(grant, intent),
          throwsA(isA<GrantConsumed>()));
      expect(window.spentCents, 1000);
    });

    test('each order keeps its own max: a higher price re-auths', () {
      final intent = _buy(1000);
      final grant = tap(intent)!;
      final worse = intent.copyWith(limits: {
        ...intent.limits,
        IntentLimit.limitPrice: 0.60,
      });
      expect(() => AuthGrants.check(grant, worse),
          throwsA(isA<ReauthRequired>()));
    });

    test('sells are one tap and never count toward the cap', () {
      for (var i = 0; i < 5; i++) {
        expect(tap(_sell()), isNotNull);
      }
      expect(window.spentCents, 0);
      expect(tap(_buy(5000)), isNotNull);
      expect(window.spentCents, 5000);
      expect(tap(_sell()), isNotNull,
          reason: 'sells stay allowed with the buy budget spent');
    });

    test('a non-short market always prompts', () {
      expect(
          tap(_buy(100),
              request: const FastBetRequest(eventSlug: _normal, hot: true)),
          isNull);
      expect(
          tap(_buy(100),
              request: const FastBetRequest(eventSlug: _hourly, hot: true)),
          isNull);
      expect(window.spentCents, 0);
    });

    test('a Ledger order always prompts', () {
      expect(
          tap(_buy(100),
              request: const FastBetRequest(eventSlug: _short5, hot: false)),
          isNull);
    });

    test('a combo or a Builder run never rides the window', () {
      final combo = PmGrants.comboBet(
        walletId: 'w1',
        legPositionIds: const ['a', 'b'],
        maxStakeE6: BigInt.from(1000000),
        minPayoutE6: BigInt.from(2000000),
      );
      expect(tap(combo, cents: 100), isNull);
    });

    test('a 15 minute round rides the same window', () {
      expect(
          tap(_buy(100),
              request: const FastBetRequest(eventSlug: _short15, hot: true)),
          isNotNull);
    });

    test('cents below the bound base units never pass', () {
      expect(tap(_buy(100, baseCents: 4000), cents: 100), isNull);
      expect(window.spentCents, 0);
    });
  });

  group('cap', () {
    setUp(() {
      window.enterScope();
      openWith();
    });

    test('reaching the cap prompts, and that approval opens a fresh window',
        () {
      expect(tap(_buy(3000)), isNotNull);
      expect(tap(_buy(2000)), isNotNull);
      expect(window.spentCents, 5000);
      expect(tap(_buy(1)), isNull, reason: 'past \$50 the next buy prompts');
      expect(window.isOpen, isFalse);
      expect(window.lastEnd, FastBetWindowEnd.capReached);
      openWith(intent: _buy(1));
      expect(window.isOpen, isTrue);
      expect(window.spentCents, 0);
      expect(tap(_buy(4000)), isNotNull);
    });

    test('one buy over the cap prompts on its own', () {
      expect(tap(_buy(5001)), isNull);
    });

    test('concurrent taps cannot both pass the cap', () async {
      final results = await Future.wait([
        for (var i = 0; i < 4; i++) Future(() => tap(_buy(2000))),
      ]);
      // \$40 booked, the third \$20 would pass \$50: it prompts and the
      // window ends, so the fourth prompts too.
      expect(results.whereType<AuthGrant>().length, 2);
      expect(results.take(2).every((g) => g != null), isTrue);
      expect(window.lastEnd, FastBetWindowEnd.capReached);
    });
  });

  group('ending', () {
    test('ten minutes end it (fake clock and timer)', () {
      fakeAsync((async) {
        final w = FastBetWindow(clock: () => now);
        w.enterScope();
        w.open(_buy(500),
            request: _shortReq,
            method: AuthGrantMethod.biometric,
            session: _session,
            sessionUnlocked: true);
        async.elapse(const Duration(minutes: 9, seconds: 59));
        now = now.add(const Duration(minutes: 9, seconds: 59));
        expect(w.isOpen, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(w.debugHoldsState, isFalse,
            reason: 'the timer drops the window without any tap');
        expect(w.lastEnd, FastBetWindowEnd.expired);
      });
    });

    test('an order after ten minutes prompts even if the timer is late', () {
      window.enterScope();
      openWith();
      now = now.add(FastBetWindow.duration);
      expect(tap(_buy(100)), isNull);
      expect(window.lastEnd, FastBetWindowEnd.expired);
    });

    test('backgrounding ends it at once', () {
      for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
        window.enterScope();
        openWith();
        window.onLifecycle(state);
        expect(window.isOpen, isFalse, reason: '$state');
        expect(window.lastEnd, FastBetWindowEnd.background);
        window.exitScope();
      }
    });

    test('inactive past the grace ends it; a short one or our own prompt '
        'does not', () {
      fakeAsync((async) {
        final w = FastBetWindow(clock: () => now);
        w.enterScope();
        w.open(_buy(500),
            request: _shortReq,
            method: AuthGrantMethod.biometric,
            session: _session,
            sessionUnlocked: true);
        w.onLifecycle(AppLifecycleState.inactive, selfPrompt: true);
        async.elapse(const Duration(seconds: 10));
        expect(w.isOpen, isTrue, reason: 'our own biometric sheet');
        w.onLifecycle(AppLifecycleState.inactive);
        async.elapse(const Duration(seconds: 2));
        w.onLifecycle(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 5));
        expect(w.isOpen, isTrue, reason: 'Control Center for 2 s');
        w.onLifecycle(AppLifecycleState.inactive);
        async.elapse(FastBetWindow.inactiveGrace);
        expect(w.isOpen, isFalse);
        expect(w.lastEnd, FastBetWindowEnd.background);
      });
    });

    test('leaving the short-round screens ends it', () {
      window.enterScope(); // round sheet
      window.enterScope(); // slip over it
      openWith();
      window.exitScope(); // the slip closes after the bet
      expect(window.isOpen, isTrue);
      expect(tap(_buy(100)), isNotNull,
          reason: 'the round sheet is still up');
      window.exitScope(); // the round sheet closes
      expect(window.isOpen, isFalse);
      expect(window.lastEnd, FastBetWindowEnd.leftScreens);
    });

    test('a wallet switch ends it', () {
      window.enterScope();
      openWith();
      expect(tap(_buy(100, wallet: 'w2')), isNull);
      expect(window.isOpen, isFalse);
      expect(window.lastEnd, FastBetWindowEnd.walletChanged);
      expect(tap(_buy(100)), isNull, reason: 'gone, not paused');
    });

    test('the session lock ends it', () {
      window.enterScope();
      openWith();
      expect(tap(_buy(100), unlocked: false), isNull);
      expect(window.lastEnd, FastBetWindowEnd.sessionLock);
    });

    test('a new session (logout, wipe, cold start) ends it', () {
      window.enterScope();
      openWith();
      expect(tap(_buy(100), session: Object()), isNull);
      expect(window.lastEnd, FastBetWindowEnd.sessionChanged);
    });

    test('ending drops every field and timer', () {
      window.enterScope();
      openWith();
      expect(tap(_buy(1000)), isNotNull);
      window.onLifecycle(AppLifecycleState.inactive);
      expect(window.debugHoldsState, isTrue);
      window.end(FastBetWindowEnd.sessionLock);
      expect(window.debugHoldsState, isFalse);
      expect(window.spentCents, 0);
      expect(window.isOpen, isFalse);
      // Ending twice is harmless and keeps the first reason.
      window.end(FastBetWindowEnd.background);
      expect(window.lastEnd, FastBetWindowEnd.sessionLock);
    });
  });

  test('approval values', () {
    expect(FastBetWindow.approvalParam(AuthGrantMethod.biometric), 'biometric');
    expect(FastBetWindow.approvalParam(AuthGrantMethod.pin), 'biometric');
    expect(FastBetWindow.approvalParam(AuthGrantMethod.pinThenBiometric),
        'biometric');
    expect(FastBetWindow.approvalParam(AuthGrantMethod.fastWindow),
        'fast_window');
    expect(FastBetWindow.approvalParam(AuthGrantMethod.allowance), 'allowance');
  });
}
