import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:kute/services/auth/pin_encryption.dart';

String _hashPinIsolate(String pin) {
  return PinHashHelper.hashPin(pin);
}

bool _verifyPinIsolate((String, String) args) {
  return PinHashHelper.verifyPin(args.$1, args.$2);
}

class PinHashHelper {
  static const int _iterations = 100000;
  static const int _saltLength = 32;
  static const int _hashLength = 32;

  static Future<String> hashPinAsync(String pin) {
    return compute(_hashPinIsolate, pin);
  }

  static String hashPin(String pin) {
    final salt = PinEncryptionHelper.randomBytes(_saltLength);
    final hash = _pbkdf2(pin, salt);
    return "${base64Encode(salt)}:${base64Encode(hash)}";
  }

  /// Off-main-isolate PIN verification. PBKDF2-SHA256 at 100k iterations
  /// takes a few hundred ms on mid-range hardware; running it on the UI
  /// isolate is what made the app feel like it "lagged" after the 6th
  /// digit before the home screen appeared. `compute` hands it to a
  /// background isolate so the keypad stays responsive and navigation
  /// fires the instant verification returns.
  static Future<bool> verifyPinAsync(String pin, String storedHash) {
    return compute(_verifyPinIsolate, (pin, storedHash));
  }

  static bool verifyPin(String pin, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) return false;

    final salt = Uint8List.fromList(base64Decode(parts[0]));
    final expectedHash = base64Decode(parts[1]);
    final computedHash = _pbkdf2(pin, salt);

    return _constantTimeEquals(computedHash, Uint8List.fromList(expectedHash));
  }

  static Uint8List _pbkdf2(String pin, Uint8List salt) {
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, _iterations, _hashLength));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
