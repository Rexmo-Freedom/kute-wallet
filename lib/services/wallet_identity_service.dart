import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// WalletIdentityService — the wallet's stable cryptographic identity for
/// authenticating to the backend's wallet-native affiliate program.
///
/// Identity is **deterministic from the wallet's 12-word seed** via Breez:
///   pubkey = `sdk.getInfo().identityPubkey` (secp256k1 33-byte compressed,
///            hex-encoded). Same seed → same pubkey on any device after
///            recovery. Wallet switch (multi-wallet) → different SDK
///            instance → different pubkey → different affiliate row.
///
/// Signing uses `sdk.signMessage(SignMessageRequest(compact: true))` —
/// Breez applies SHA-256 internally and returns a 65-byte ECDSA compact
/// recoverable signature in hex. The backend recovers the pubkey from
/// that signature and the SHA-256 of the challenge, then compares it
/// to the pubkey on the request.
class WalletIdentityService {
  WalletIdentityService._();

  static String? _cachedPubkey;
  static spark.BreezSdk? _sdk;

  /// Bind a Breez SDK instance and prime the pubkey cache by calling
  /// getInfo(). Retries on transient failures — first Earn-tab open used
  /// to fail because getInfo throws if Breez is still warming up, the
  /// pubkey stayed null, and the Earn screen errored. Second open
  /// always worked because the SDK had finished init by then.
  static Future<void> initFromBreez(spark.BreezSdk sdk) async {
    _sdk = sdk;
    // Try up to 5 times with backoff: 0ms, 250ms, 500ms, 1s, 2s.
    // Covers most cold-start races without blocking forever on a real
    // failure.
    final delaysMs = <int>[0, 250, 500, 1000, 2000];
    for (var attempt = 0; attempt < delaysMs.length; attempt++) {
      if (delaysMs[attempt] > 0) {
        await Future<void>.delayed(Duration(milliseconds: delaysMs[attempt]));
      }
      try {
        final info = await sdk.getInfo(request: const spark.GetInfoRequest());
        if (info.identityPubkey.isNotEmpty) {
          _cachedPubkey = info.identityPubkey;
          if (kDebugMode && attempt > 0) {
            debugPrint('WalletIdentity: getInfo succeeded on attempt ${attempt + 1}');
          }
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('WalletIdentity: initFromBreez getInfo attempt ${attempt + 1} failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint('WalletIdentity: initFromBreez exhausted retries; pubkey unresolved');
    }
  }

  /// True once initFromBreez has resolved a pubkey at least once.
  static bool get isReady =>
      _cachedPubkey != null && (_sdk != null || _debugSigner != null);

  static Future<String> Function(String message)? _debugSigner;

  /// Test-only identity: a pubkey plus a signer standing in for the SDK.
  @visibleForTesting
  static void debugBind({
    required String? pubkey,
    Future<String> Function(String message)? signer,
  }) {
    _cachedPubkey = pubkey;
    _debugSigner = signer;
  }

  /// The wallet's stable public identifier (33-byte compressed secp256k1
  /// pubkey, hex). Available after [initFromBreez]. Returns null if the
  /// SDK hasn't been bound yet.
  static String? get pubkey => _cachedPubkey;

  /// Re-fetch the pubkey from the active SDK. Useful after a wallet
  /// switch — if the pubkey has changed, callers should wipe any cached
  /// affiliate session and re-auth.
  static Future<String?> refreshPubkey() async {
    final sdk = _sdk;
    if (sdk == null) return _cachedPubkey;
    try {
      final info = await sdk.getInfo(request: const spark.GetInfoRequest());
      _cachedPubkey = info.identityPubkey;
    } catch (_) {
      // Keep previous cached value
    }
    return _cachedPubkey;
  }

  /// Sign a challenge string with the active wallet's node key. Returns
  /// the hex-encoded compact ECDSA signature (130 hex chars, 65 bytes).
  /// Empty string if the SDK isn't bound.
  static Future<String> sign(String challenge) async {
    final debugSigner = _debugSigner;
    if (debugSigner != null) return debugSigner(challenge);
    final sdk = _sdk;
    if (sdk == null) return '';
    final resp = await sdk.signMessage(
      request: spark.SignMessageRequest(message: challenge, compact: true),
    );
    return resp.signature;
  }

  static final RegExp _lowerHex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Hex SHA-256 of the auth body fields a v2 signature binds, newline
  /// separated, absent fields as empty strings. Must be built from the
  /// exact values posted.
  static String canonicalAuthBodyDigest({
    required String paykuteAddress,
    String? referredByCode,
    String? appsflyerId,
    String? afPlatform,
  }) =>
      sha256Hex([
        paykuteAddress,
        referredByCode ?? '',
        appsflyerId ?? '',
        afPlatform ?? '',
      ].join('\n'));

  /// How far the device clock may run ahead of the server's before a
  /// fresh challenge looks expired. The server enforces expiry itself.
  static const int _challengeClockSkewSeconds = 300;

  /// Longest challenge validity window accepted from the server.
  static const int _maxChallengeLifetimeSeconds = 600;

  /// Signs a server-issued `kute-auth-v2|pubkey|nonce|issued|expires`
  /// challenge with [bodyDigest] appended. Refuses (empty map, nothing
  /// signed) unless the challenge names this wallet's pubkey, is well
  /// formed, spans at most 10 minutes and has not expired at [now],
  /// allowing 5 minutes of device clock skew.
  static Future<Map<String, String>> buildAuthChallengeV2(
    String challenge, {
    required String bodyDigest,
    DateTime? now,
  }) async {
    // Phase 5 B12: never sign with the hot identity inside a Ledger
    // operation. A session re-auth there fails closed instead; Ledger flows
    // prepare the session before their scope starts.
    LedgerOperationScope.assertHotAllowed(HotSigningAction.walletIdentitySign);
    final pubkey = _cachedPubkey;
    if (!isReady || pubkey == null) return const {};
    final fields = challenge.split('|');
    if (fields.length != 5 ||
        fields[0] != 'kute-auth-v2' ||
        fields[1] != pubkey ||
        !_lowerHex64.hasMatch(fields[2]) ||
        !_lowerHex64.hasMatch(bodyDigest)) {
      return const {};
    }
    final issued = int.tryParse(fields[3]);
    final expires = int.tryParse(fields[4]);
    final nowUnix = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (issued == null ||
        expires == null ||
        expires <= issued ||
        expires - issued > _maxChallengeLifetimeSeconds ||
        expires <= nowUnix - _challengeClockSkewSeconds) {
      return const {};
    }
    final message = '$challenge|$bodyDigest';
    final sig = await sign(message);
    if (sig.isEmpty) return const {};
    return {
      'pubkey': pubkey,
      'challenge': message,
      'signature': sig,
    };
  }

  /// Compute the SHA-256 of an arbitrary string. Exposed so callers (or
  /// tests) can verify that backend's hash matches the wallet's.
  @visibleForTesting
  static String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

  /// Wipe in-memory identity. Called on wallet switch / creation / sign-out
  /// so the next [initFromBreez] re-derives the active wallet's pubkey
  /// instead of reusing the previous wallet's cached one. Re-binding the
  /// same seed restores the same pubkey, so this is safe to call freely.
  static Future<void> wipe() async {
    _cachedPubkey = null;
    _sdk = null;
  }
}
