// A person in Sweden could not bet for eight minutes on 2026-11-08: every
// Polygon RPC read on their phone timed out all evening, and each buy was
// declined in the account's setup re-check (setup_failed, four times)
// before a single request reached the order book, although the same
// deposit wallet had been verified deployed and approved days before. A
// buy now leans on that verification when the chain cannot be read at
// all, and on nothing else: no memory, a stale one, a refusal or a changed
// account still end the setup as before.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/remembered_setup.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException, RelayerSubmitRejected;

void main() {
  final now = DateTime(2026, 11, 8, 21, 30);
  const wallet = '0x14791697260E4c9A71f18484C9f997B308e59325';
  final fresh = PolySetupMemory(
      depositWallet: wallet, verifiedAt: now.subtract(const Duration(days: 3)));
  const readFailedClosed =
      PolymarketReadException('eth_getCode: no Polygon RPC answered');

  bool ready(Object error,
          {bool offline = false,
          PolySetupMemory? memory,
          String? known = wallet,
          DateTime? at}) =>
      polySetupRemembered(error,
          offline: offline,
          memory: memory ?? fresh,
          knownDepositWallet: known,
          now: at ?? now);

  group('the fresh verification could not reach the chain', () {
    test('every RPC failing one read, verified within 14 days: ready', () {
      expect(ready(readFailedClosed), isTrue);
    });

    test('the phone offline (the caller read the error so): ready', () {
      expect(
          ready(Exception('SocketException: Failed host lookup'),
              offline: true),
          isTrue);
    });

    test('verified exactly 14 days ago still counts; a day more does not',
        () {
      expect(
          ready(readFailedClosed,
              memory: PolySetupMemory(
                  depositWallet: wallet,
                  verifiedAt: now.subtract(kPolySetupMemoryTtl))),
          isTrue);
      expect(
          ready(readFailedClosed,
              memory: PolySetupMemory(
                  depositWallet: wallet,
                  verifiedAt: now.subtract(const Duration(days: 15)))),
          isFalse);
    });

    test('a clock set back before the verification is not current', () {
      expect(
          ready(readFailedClosed,
              at: fresh.verifiedAt.subtract(const Duration(hours: 1))),
          isFalse);
    });
  });

  group('never skipped', () {
    test('without a memory the setup fails as before', () {
      expect(
          polySetupRemembered(readFailedClosed,
              offline: false,
              memory: null,
              knownDepositWallet: wallet,
              now: now),
          isFalse);
    });

    test('a relayer refusal, offline or not', () {
      const refused = RelayerSubmitRejected(400, 'wallet busy');
      expect(ready(refused), isFalse);
      expect(ready(refused, offline: true), isFalse);
    });

    test('an account that changed under the setup', () {
      expect(ready(StateError('Predictions account changed')), isFalse);
    });

    test('a refusal that is neither a chain read nor the network', () {
      expect(ready(Exception('Could not decrypt wallet')), isFalse);
      expect(ready(Exception('Wallet locked. Please unlock first.')), isFalse);
    });

    test('a memory for another deposit wallet than the account knows', () {
      expect(
          ready(readFailedClosed,
              known: '0x000000000000000000000000000000000000dEaD'),
          isFalse);
      // Case does not matter; an account whose address is not known yet
      // takes the remembered wallet.
      expect(ready(readFailedClosed, known: wallet.toLowerCase()), isTrue);
      expect(ready(readFailedClosed, known: null), isTrue);
      expect(ready(readFailedClosed, known: ''), isTrue);
    });
  });

  group('the memory on disk', () {
    test('round-trips through its stored form', () {
      final back = PolySetupMemory.decode(fresh.encode());
      expect(back?.depositWallet, wallet.toLowerCase());
      expect(back?.verifiedAt, fresh.verifiedAt);
    });

    test('anything that is not a memory decodes to nothing', () {
      expect(PolySetupMemory.decode(null), isNull);
      expect(PolySetupMemory.decode(''), isNull);
      expect(PolySetupMemory.decode('0xabc:12'), isNull);
      expect(PolySetupMemory.decode('$wallet:soon'), isNull);
      expect(PolySetupMemory.decode(wallet), isNull);
    });
  });
}
