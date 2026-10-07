import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure/secret_error_class.dart';

void main() {
  group('iOS OSStatus in details', () {
    const cases = {
      -128: SecretErrorClass.cancelled,
      -25293: SecretErrorClass.authFailed,
      -25308: SecretErrorClass.interactionNotAllowed,
      -34018: SecretErrorClass.unavailable,
      -26275: SecretErrorClass.decode,
      -25300: SecretErrorClass.unknown,
      -50: SecretErrorClass.unknown,
    };
    cases.forEach((status, expected) {
      test('$status is ${expected.name}', () {
        final error = PlatformException(
          code: 'Unexpected security result code',
          message: 'status',
          details: status,
        );
        expect(
            classifySecretError(error, platform: TargetPlatform.iOS), expected);
      });
    });

    test('a numeric string status is accepted', () {
      final error = PlatformException(code: 'x', details: '-26275');
      expect(classifySecretError(error, platform: TargetPlatform.iOS),
          SecretErrorClass.decode);
    });

    test('missing details is unknown', () {
      final error = PlatformException(code: 'x');
      expect(classifySecretError(error, platform: TargetPlatform.iOS),
          SecretErrorClass.unknown);
    });
  });

  group('Android fixture strings', () {
    final fixture = jsonDecode(
      File('test/fixtures/secure_storage_errors_android.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in fixture['cases'] as List) {
      final entry = raw as Map<String, dynamic>;
      test('${entry['class']}: ${entry['message']}', () {
        final error = PlatformException(
          code: entry['code'] as String,
          message: entry['message'] as String?,
          details: entry['details'],
        );
        expect(
          classifySecretError(error, platform: TargetPlatform.android).name,
          entry['class'],
        );
      });
    }
  });

  test('non-platform errors are unknown on every platform', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(classifySecretError(StateError('x'), platform: platform),
          SecretErrorClass.unknown);
    }
  });

  test('only keyInvalidated and decode are definitive', () {
    expect(
      SecretErrorClass.values.where((c) => c.isDefinitive).toSet(),
      {SecretErrorClass.keyInvalidated, SecretErrorClass.decode},
    );
  });
}
