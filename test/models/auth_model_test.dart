import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';

void main() {
  group('PinEncryptionHelper', () {
    test('v2 encrypt/decrypt round-trip', () {
      final plain = 'my secret seed phrase';
      final pin = '123456';
      final encrypted = PinEncryptionHelper.encryptData(plain, pin);
      final decrypted = PinEncryptionHelper.decryptData(encrypted, pin);
      expect(decrypted, plain);
    });

    test('v2 output starts with v2: prefix', () {
      final encrypted = PinEncryptionHelper.encryptData('data', '0000');
      expect(encrypted.startsWith('v2:'), isTrue);
    });

    test('v2 different PINs produce different ciphertexts', () {
      const plain = 'same data';
      final enc1 = PinEncryptionHelper.encryptData(plain, '1111');
      final enc2 = PinEncryptionHelper.encryptData(plain, '2222');
      expect(enc1, isNot(equals(enc2)));
    });

    test('v2 same PIN produces different ciphertexts (random salt/iv)', () {
      const plain = 'same data';
      final enc1 = PinEncryptionHelper.encryptData(plain, '1111');
      final enc2 = PinEncryptionHelper.encryptData(plain, '1111');
      expect(enc1, isNot(equals(enc2)));
    });

    test('v2 wrong PIN fails decrypt', () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      expect(
        () => PinEncryptionHelper.decryptData(encrypted, '9999'),
        throwsA(isA<Exception>()),
      );
    });

    test('v1 legacy format detection', () {
      expect(PinEncryptionHelper.isLegacyFormat('v2:abc:def:ghi'), isFalse);
      expect(PinEncryptionHelper.isLegacyFormat('abc:def'), isTrue);
      expect(PinEncryptionHelper.isLegacyFormat('singlestring'), isTrue);
    });

    test('decryptData with malformed v2 data throws', () {
      expect(
        () => PinEncryptionHelper.decryptData('v2:bad', '1234'),
        throwsA(isA<Exception>()),
      );
    });

    test('empty plaintext encrypt/decrypt round-trip', () {
      final encrypted = PinEncryptionHelper.encryptData('', '1234');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '1234');
      expect(decrypted, '');
    });

    test('long plaintext encrypt/decrypt round-trip', () {
      final plain = 'word ' * 500;
      final encrypted = PinEncryptionHelper.encryptData(plain, '5678');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '5678');
      expect(decrypted, plain);
    });

    test('randomBytes returns correct length', () {
      expect(PinEncryptionHelper.randomBytes(16).length, 16);
      expect(PinEncryptionHelper.randomBytes(32).length, 32);
      expect(PinEncryptionHelper.randomBytes(0).length, 0);
    });
  });

  group('PinHashHelper', () {
    test('hashPin returns salt:hash format', () {
      final hashed = PinHashHelper.hashPin('1234');
      final parts = hashed.split(':');
      expect(parts.length, 2);
      expect(parts[0].isNotEmpty, isTrue);
      expect(parts[1].isNotEmpty, isTrue);
    });

    test('verifyPin correct PIN', () {
      final hashed = PinHashHelper.hashPin('5678');
      expect(PinHashHelper.verifyPin('5678', hashed), isTrue);
    });

    test('verifyPin wrong PIN', () {
      final hashed = PinHashHelper.hashPin('5678');
      expect(PinHashHelper.verifyPin('0000', hashed), isFalse);
    });

    test('same PIN produces different hashes (random salt)', () {
      final h1 = PinHashHelper.hashPin('1234');
      final h2 = PinHashHelper.hashPin('1234');
      expect(h1, isNot(equals(h2)));
      // But both verify
      expect(PinHashHelper.verifyPin('1234', h1), isTrue);
      expect(PinHashHelper.verifyPin('1234', h2), isTrue);
    });

    test('verifyPin with malformed stored hash returns false', () {
      expect(PinHashHelper.verifyPin('1234', 'notvalid'), isFalse);
      expect(PinHashHelper.verifyPin('1234', ''), isFalse);
      expect(PinHashHelper.verifyPin('1234', 'a:b:c'), isFalse);
    });

    test('empty PIN hash and verify', () {
      final hashed = PinHashHelper.hashPin('');
      expect(PinHashHelper.verifyPin('', hashed), isTrue);
      expect(PinHashHelper.verifyPin('x', hashed), isFalse);
    });

    test('numeric PIN hash and verify', () {
      final hashed = PinHashHelper.hashPin('000000');
      expect(PinHashHelper.verifyPin('000000', hashed), isTrue);
      expect(PinHashHelper.verifyPin('000001', hashed), isFalse);
    });

    test('long PIN hash and verify', () {
      final longPin = '1' * 1000;
      final hashed = PinHashHelper.hashPin(longPin);
      expect(PinHashHelper.verifyPin(longPin, hashed), isTrue);
      expect(PinHashHelper.verifyPin('1' * 999, hashed), isFalse);
    });

    test('special characters in PIN hash and verify', () {
      final pin = '!@#\$%^&*()_+-=';
      final hashed = PinHashHelper.hashPin(pin);
      expect(PinHashHelper.verifyPin(pin, hashed), isTrue);
      expect(PinHashHelper.verifyPin('!@#\$%^&*()_+-', hashed), isFalse);
    });

    test('unicode PIN hash and verify', () {
      final pin = '\u{1F600}\u{1F4A9}';
      final hashed = PinHashHelper.hashPin(pin);
      expect(PinHashHelper.verifyPin(pin, hashed), isTrue);
      expect(PinHashHelper.verifyPin('abc', hashed), isFalse);
    });

    test('hash output contains valid base64 segments', () {
      final hashed = PinHashHelper.hashPin('1234');
      final parts = hashed.split(':');
      // Both parts should be valid base64
      expect(() => base64Decode(parts[0]), returnsNormally);
      expect(() => base64Decode(parts[1]), returnsNormally);
      // Salt should be 32 bytes
      expect(base64Decode(parts[0]).length, 32);
      // Hash should be 32 bytes
      expect(base64Decode(parts[1]).length, 32);
    });

    test('verifyPin is case-sensitive', () {
      final hashed = PinHashHelper.hashPin('abcd');
      expect(PinHashHelper.verifyPin('abcd', hashed), isTrue);
      expect(PinHashHelper.verifyPin('ABCD', hashed), isFalse);
      expect(PinHashHelper.verifyPin('Abcd', hashed), isFalse);
    });

    test('verifyPin rejects similar PINs', () {
      final hashed = PinHashHelper.hashPin('1234');
      expect(PinHashHelper.verifyPin('1234 ', hashed), isFalse);
      expect(PinHashHelper.verifyPin(' 1234', hashed), isFalse);
      expect(PinHashHelper.verifyPin('12345', hashed), isFalse);
      expect(PinHashHelper.verifyPin('123', hashed), isFalse);
    });
  });

  group('PinEncryptionHelper - additional edge cases', () {
    test('v2 decrypt with wrong PIN near-match fails', () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      expect(
        () => PinEncryptionHelper.decryptData(encrypted, '1235'),
        throwsA(isA<Exception>()),
      );
    });

    test('v2 decrypt with empty PIN when encrypted with non-empty PIN fails',
        () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      expect(
        () => PinEncryptionHelper.decryptData(encrypted, ''),
        throwsA(isA<Exception>()),
      );
    });

    test('encrypt with empty PIN and decrypt with empty PIN succeeds', () {
      final encrypted = PinEncryptionHelper.encryptData('data', '');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '');
      expect(decrypted, 'data');
    });

    test('v2 output has exactly 4 colon-separated parts', () {
      final encrypted = PinEncryptionHelper.encryptData('data', '1234');
      final parts = encrypted.split(':');
      expect(parts.length, 4);
      expect(parts[0], 'v2');
      // salt, iv, ciphertext should all be valid base64
      expect(() => base64Decode(parts[1]), returnsNormally);
      expect(() => base64Decode(parts[2]), returnsNormally);
      expect(() => base64Decode(parts[3]), returnsNormally);
    });

    test('v2 salt is 32 bytes and iv is 12 bytes', () {
      final encrypted = PinEncryptionHelper.encryptData('data', '1234');
      final parts = encrypted.split(':');
      expect(base64Decode(parts[1]).length, 32); // salt
      expect(base64Decode(parts[2]).length, 12); // GCM IV
    });

    test('special characters in plaintext round-trip', () {
      final plain = 'hello\nworld\t\r\n!@#\$%^&*(){}[]|\\:;"\'<>,.?/~`';
      final encrypted = PinEncryptionHelper.encryptData(plain, '9999');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '9999');
      expect(decrypted, plain);
    });

    test('unicode plaintext round-trip', () {
      final plain = '\u{1F600} \u{1F4A9} \u{1F680} \u{00E9}\u{00F1}\u{00FC}';
      final encrypted = PinEncryptionHelper.encryptData(plain, '1234');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '1234');
      expect(decrypted, plain);
    });

    test('mnemonic-like plaintext round-trip', () {
      final plain =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final encrypted = PinEncryptionHelper.encryptData(plain, '123456');
      final decrypted = PinEncryptionHelper.decryptData(encrypted, '123456');
      expect(decrypted, plain);
    });

    test('decryptData with completely invalid base64 in v2 throws', () {
      expect(
        () => PinEncryptionHelper.decryptData('v2:!!!:!!!:!!!', '1234'),
        throwsA(anything),
      );
    });

    test('decryptData with empty string throws', () {
      // Empty string is v1 legacy format with no colon -> single part -> throws
      expect(
        () => PinEncryptionHelper.decryptData('', '1234'),
        throwsA(anything),
      );
    });

    test('decryptData with tampered ciphertext throws', () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      final parts = encrypted.split(':');
      // Tamper with the ciphertext (last part)
      final cipherBytes = base64Decode(parts[3]);
      cipherBytes[0] ^= 0xFF; // flip bits
      final tampered =
          '${parts[0]}:${parts[1]}:${parts[2]}:${base64Encode(cipherBytes)}';
      expect(
        () => PinEncryptionHelper.decryptData(tampered, '1234'),
        throwsA(anything),
      );
    });

    test('decryptData with tampered IV throws', () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      final parts = encrypted.split(':');
      final ivBytes = base64Decode(parts[2]);
      ivBytes[0] ^= 0xFF;
      final tampered =
          '${parts[0]}:${parts[1]}:${base64Encode(ivBytes)}:${parts[3]}';
      expect(
        () => PinEncryptionHelper.decryptData(tampered, '1234'),
        throwsA(anything),
      );
    });

    test('decryptData with tampered salt throws', () {
      final encrypted = PinEncryptionHelper.encryptData('secret', '1234');
      final parts = encrypted.split(':');
      final saltBytes = base64Decode(parts[1]);
      saltBytes[0] ^= 0xFF;
      final tampered =
          '${parts[0]}:${base64Encode(saltBytes)}:${parts[2]}:${parts[3]}';
      expect(
        () => PinEncryptionHelper.decryptData(tampered, '1234'),
        throwsA(anything),
      );
    });

    test('randomBytes produces unique outputs', () {
      final a = PinEncryptionHelper.randomBytes(32);
      final b = PinEncryptionHelper.randomBytes(32);
      // Extremely unlikely to be equal
      expect(a, isNot(equals(b)));
    });

    test('isLegacyFormat edge cases', () {
      expect(PinEncryptionHelper.isLegacyFormat('v2:'), isFalse);
      expect(PinEncryptionHelper.isLegacyFormat('v2'), isTrue);
      expect(PinEncryptionHelper.isLegacyFormat('V2:abc:def:ghi'), isTrue);
      expect(PinEncryptionHelper.isLegacyFormat('v1:abc:def'), isTrue);
    });
  });

  group('AuthModel.getLockoutDuration', () {
    test('0 failed attempts returns 0 (no lockout)', () {
      expect(AuthModel.getLockoutDuration(0), 0);
    });

    test('1 failed attempt returns 0 (no lockout)', () {
      expect(AuthModel.getLockoutDuration(1), 0);
    });

    test('2 failed attempts returns 0 (no lockout)', () {
      expect(AuthModel.getLockoutDuration(2), 0);
    });

    test('3 failed attempts returns 30 seconds', () {
      expect(AuthModel.getLockoutDuration(3), 30);
    });

    test('4 failed attempts returns 60 seconds', () {
      expect(AuthModel.getLockoutDuration(4), 60);
    });

    test('5 failed attempts returns 300 seconds', () {
      expect(AuthModel.getLockoutDuration(5), 300);
    });

    test('6 failed attempts returns -1 (wipe)', () {
      expect(AuthModel.getLockoutDuration(6), -1);
    });

    test('7 or more failed attempts returns -1 (wipe)', () {
      expect(AuthModel.getLockoutDuration(7), -1);
      expect(AuthModel.getLockoutDuration(10), -1);
      expect(AuthModel.getLockoutDuration(100), -1);
    });

    test('lockout durations increase progressively', () {
      final d3 = AuthModel.getLockoutDuration(3);
      final d4 = AuthModel.getLockoutDuration(4);
      final d5 = AuthModel.getLockoutDuration(5);
      expect(d3, lessThan(d4));
      expect(d4, lessThan(d5));
    });

    test('brute force: first two attempts have no lockout', () {
      for (int i = 0; i <= 2; i++) {
        expect(AuthModel.getLockoutDuration(i), 0,
            reason: '$i attempts should have no lockout');
      }
    });

    test('brute force: lockout kicks in at 3rd attempt', () {
      expect(AuthModel.getLockoutDuration(2), 0);
      expect(AuthModel.getLockoutDuration(3), greaterThan(0));
    });

    test('brute force: wipe triggers at 6 attempts, not before', () {
      expect(AuthModel.getLockoutDuration(5), isNot(equals(-1)));
      expect(AuthModel.getLockoutDuration(6), -1);
    });
  });

  group('PinHashHelper + PinEncryptionHelper integration', () {
    test('hash does not collide with encryption output', () {
      final hash = PinHashHelper.hashPin('1234');
      final encrypted = PinEncryptionHelper.encryptData('1234', '1234');
      // Hash is salt:hash, encrypted is v2:salt:iv:cipher
      expect(hash, isNot(equals(encrypted)));
      expect(hash.startsWith('v2:'), isFalse);
    });

    test('encrypt then hash PIN independently both work', () {
      const pin = '5678';
      const data = 'my mnemonic phrase';

      // Encrypt data with PIN
      final encrypted = PinEncryptionHelper.encryptData(data, pin);
      // Hash PIN
      final hashedPin = PinHashHelper.hashPin(pin);

      // Both operations should succeed independently
      expect(PinEncryptionHelper.decryptData(encrypted, pin), data);
      expect(PinHashHelper.verifyPin(pin, hashedPin), isTrue);

      // Wrong PIN should fail both
      expect(
        () => PinEncryptionHelper.decryptData(encrypted, '0000'),
        throwsA(isA<Exception>()),
      );
      expect(PinHashHelper.verifyPin('0000', hashedPin), isFalse);
    });

    test('simulated PIN change: re-encrypt with new PIN', () {
      const oldPin = '1234';
      const newPin = '5678';
      const mnemonic = 'abandon ability able about above absent';

      // Encrypt with old PIN
      final encryptedOld =
          PinEncryptionHelper.encryptData(mnemonic, oldPin);

      // Decrypt with old PIN and re-encrypt with new PIN
      final decrypted =
          PinEncryptionHelper.decryptData(encryptedOld, oldPin);
      expect(decrypted, mnemonic);

      final encryptedNew =
          PinEncryptionHelper.encryptData(decrypted, newPin);

      // Old PIN should no longer decrypt new ciphertext
      expect(
        () => PinEncryptionHelper.decryptData(encryptedNew, oldPin),
        throwsA(isA<Exception>()),
      );

      // New PIN should decrypt
      expect(
          PinEncryptionHelper.decryptData(encryptedNew, newPin), mnemonic);
    });

    test(
        'simulated brute force: wrong PINs fail, correct PIN succeeds after lockout clears',
        () {
      const correctPin = '1234';
      final hashedPin = PinHashHelper.hashPin(correctPin);
      final encrypted =
          PinEncryptionHelper.encryptData('seed phrase', correctPin);

      // Simulate 5 wrong attempts
      final wrongPins = ['0000', '1111', '2222', '3333', '4444'];
      int failedAttempts = 0;

      for (final wrongPin in wrongPins) {
        final matches = PinHashHelper.verifyPin(wrongPin, hashedPin);
        expect(matches, isFalse);
        failedAttempts++;

        final lockoutDuration = AuthModel.getLockoutDuration(failedAttempts);
        if (failedAttempts >= 3) {
          expect(lockoutDuration, greaterThan(0));
        }
      }

      // At 5 failures, lockout is 300s but not wipe yet
      expect(AuthModel.getLockoutDuration(failedAttempts), 300);
      expect(failedAttempts, 5);

      // 6th failure would trigger wipe
      expect(AuthModel.getLockoutDuration(failedAttempts + 1), -1);

      // Correct PIN still verifies (before wipe)
      expect(PinHashHelper.verifyPin(correctPin, hashedPin), isTrue);
      expect(
          PinEncryptionHelper.decryptData(encrypted, correctPin),
          'seed phrase');
    });
  });
}
