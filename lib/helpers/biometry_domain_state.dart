// lib/helpers/biometry_domain_state.dart
//
// iOS biometry domain state (Wallet Hardening Phase 1b, D-14).
//
// `SecurityNativePlugin.biometryDomainStateHash()` on the
// `com.kutewallet.app/security` channel returns the SHA-256 hex of
// `LAContext.evaluatedPolicyDomainState`, which changes when a face or a
// finger is added or removed. The Swift method lands after Phase 1a. Until
// then the call throws MissingPluginException, which reads as unknown, so
// no change is ever detected.
//
// The hash of the last biometric approval is kept in `secureStorage` under
// `bio_domain_state_v1`. Android has no equivalent (risk R7). Phase 1c
// reuses this class.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';

abstract final class BiometryDomainState {
  static const MethodChannel _channel =
      MethodChannel('com.kutewallet.app/security');

  static const String storageKey = 'bio_domain_state_v1';

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  static String? _reportedHash;

  /// The current hash, or null when unknown: not iOS, no biometry, the
  /// native method missing, or any error.
  static Future<String?> currentHash() async {
    if (!Platform.isIOS) return null;
    try {
      final raw =
          await _channel.invokeMethod<String>('biometryDomainStateHash');
      final value = raw?.trim().toLowerCase();
      return value != null && _sha256Hex.hasMatch(value) ? value : null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The stored hash, or null when absent or unreadable.
  static Future<String?> storedHash() async {
    try {
      final value = await secureStorage.read(key: storageKey);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Stores [hash] after a biometric approval. Failures are ignored: the
  /// next step-up simply compares against the older value again.
  static Future<void> store(String hash) async {
    try {
      await secureStorage.write(key: storageKey, value: hash);
    } catch (_) {}
  }

  /// Emits `seed_bio_domain_changed` once per detected hash in this process.
  static void reportChangedOnce(String currentHash) {
    if (_reportedHash == currentHash) return;
    _reportedHash = currentHash;
    TrackingService.track('seed_bio_domain_changed');
  }
}
