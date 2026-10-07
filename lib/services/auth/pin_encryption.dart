import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;

class PinEncryptionHelper {
  static const int _pbkdf2Iterations = 100000;
  static const int _saltLength = 32;
  static const int _gcmIvLength = 12;

  static Uint8List _deriveKeyV2(String pin, Uint8List salt) {
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static String encryptData(String plainText, String pin) {
    final salt = randomBytes(_saltLength);
    final iv = randomBytes(_gcmIvLength);
    final keyBytes = _deriveKeyV2(pin, salt);

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(keyBytes),
          128, // 128-bit auth tag
          iv,
          Uint8List(0),
        ),
      );

    final plainBytes = Uint8List.fromList(utf8.encode(plainText));
    final cipherBytes = cipher.process(plainBytes);

    return "v2:${base64Encode(salt)}:${base64Encode(iv)}:${base64Encode(cipherBytes)}";
  }

  /// Encrypt data off the main thread to avoid blocking the UI.
  static Future<String> encryptDataAsync(String plainText, String pin) {
    return compute(_encryptDataIsolate, (plainText, pin));
  }

  static String _encryptDataIsolate((String, String) args) {
    return encryptData(args.$1, args.$2);
  }

  static String decryptData(String encryptedCombined, String pin) {
    if (encryptedCombined.startsWith('v2:')) {
      return _decryptV2(encryptedCombined, pin);
    }
    return _decryptV1(encryptedCombined, pin);
  }

  /// Decrypt data off the main thread to avoid blocking the UI.
  static Future<String> decryptDataAsync(String encryptedCombined, String pin) {
    return compute(_decryptDataIsolate, (encryptedCombined, pin));
  }

  static String _decryptDataIsolate((String, String) args) {
    return decryptData(args.$1, args.$2);
  }

  static bool isLegacyFormat(String encryptedCombined) {
    return !encryptedCombined.startsWith('v2:');
  }

  static Uint8List _deriveKeyV1(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  static String _decryptV1(String encryptedCombined, String pin) {
    final parts = encryptedCombined.split(':');
    if (parts.length != 2) throw Exception("Invalid encrypted data format");

    final ivBytes = Uint8List.fromList(base64Decode(parts[0]));
    final cipherBytes = Uint8List.fromList(base64Decode(parts[1]));

    final keyBytes = _deriveKeyV1(pin);

    final cipher = pc.PaddedBlockCipherImpl(
      pc.PKCS7Padding(),
      pc.CBCBlockCipher(pc.AESEngine()),
    )..init(
        false,
        pc.PaddedBlockCipherParameters<pc.CipherParameters, pc.CipherParameters>(
          pc.ParametersWithIV(pc.KeyParameter(keyBytes), ivBytes),
          null,
        ),
      );

    final plainBytes = cipher.process(cipherBytes);
    return utf8.decode(plainBytes);
  }

  static String _decryptV2(String encryptedCombined, String pin) {
    final parts = encryptedCombined.split(':');
    if (parts.length != 4 || parts[0] != 'v2') {
      throw Exception("Invalid v2 encrypted data format");
    }

    final salt = base64Decode(parts[1]);
    final iv = Uint8List.fromList(base64Decode(parts[2]));
    final cipherBytes = Uint8List.fromList(base64Decode(parts[3]));

    final keyBytes = _deriveKeyV2(pin, Uint8List.fromList(salt));

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(keyBytes),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final plainBytes = cipher.process(cipherBytes);
    return utf8.decode(plainBytes);
  }

  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}
