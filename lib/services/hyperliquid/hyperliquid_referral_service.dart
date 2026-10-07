// lib/services/hyperliquid/hyperliquid_referral_service.dart
//
// Names Kute as the Hyperliquid referrer of the user's hot Investing
// account (`setReferrer`, an L1 action signed by the account's own key),
// once, silently and best-effort.
//
// When: the account exists on the venue (funded), Kute's policy allows
// `hyperliquid.trade` and `hyperliquid.referrer` (the per-country gate on
// the referral itself; denied while the policy is unreachable, like any
// capability outside kOfflineAllowedCapabilities), the backend publishes
// a referral code (see
// HyperliquidFundingService.getReferralCode) and the venue's `referral`
// info shows no referrer yet. Hyperliquid keeps the first referrer it
// records, so this runs before the first trade whenever it can: right
// after a deposit and whenever a funded account's snapshot arrives.
//
// Never blocks anything and never loops: one attempt per account is
// recorded on this device whatever the venue answers. Only a network
// failure, or an account the venue does not know yet (deposit still
// landing), leaves it unrecorded so the next session tries again. Off
// while the backend publishes no code (the default): nothing is sent.
//
// Ledger accounts never get here: their venues are off, and a Ledger
// signer is refused below in any case.
//
// No UI: nothing here is shown or promoted to the user.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';

enum HlReferrerOutcome {
  /// The venue accepted Kute's code.
  ok,

  /// The account already had a referrer (or the venue said so).
  alreadySet,

  /// The venue refused, or signing failed. Not retried.
  failed,

  /// Nothing to do: no code, trade or referrer not allowed, Ledger, or
  /// already tried.
  skipped,

  /// A network failure or an account not on the venue yet. Not recorded,
  /// so the next session tries again.
  retryLater,
}

class HyperliquidReferralService {
  HyperliquidReferralService._();

  static String _attemptedKey(String address) =>
      'hl_referrer_attempted_${address.toLowerCase()}';

  /// Accounts with an attempt running or already settled this app session.
  static final Set<String> _sessionDone = {};

  @visibleForTesting
  static void resetForTest() => _sessionDone.clear();

  /// Sets Kute's referral code on [exchange]'s account when it has none.
  /// Never throws. At most one venue call per account per app session.
  /// [allows] answers a capability id; tests inject it, the app reads the
  /// runtime policy.
  static Future<HlReferrerOutcome> ensureReferrerSet({
    required HyperliquidExchangeService exchange,
    bool Function(String capability)? allows,
  }) async {
    final address = exchange.walletAddress.toLowerCase();
    try {
      if (exchange.externalSigner != null) return HlReferrerOutcome.skipped;
      final allowed = allows ?? RuntimeCapabilitiesService.instance.allows;
      if (!allowed('hyperliquid.trade') || !allowed('hyperliquid.referrer')) {
        return HlReferrerOutcome.skipped;
      }
      if (!_sessionDone.add(address)) return HlReferrerOutcome.skipped;
      if (await _attempted(address)) return HlReferrerOutcome.skipped;

      final code = await HyperliquidFundingService.getReferralCode();
      if (code == null) {
        // A code published later in this session is still picked up.
        _sessionDone.remove(address);
        return HlReferrerOutcome.skipped;
      }

      final referred = await _hasReferrer(address);
      if (referred == null) return HlReferrerOutcome.retryLater;
      if (referred) return await _settle(address, HlReferrerOutcome.alreadySet);

      try {
        await exchange.setReferrer(code: code);
        return await _settle(address, HlReferrerOutcome.ok);
      } on HyperliquidSignatureRejectedException {
        // "User or API Wallet … does not exist": the venue has no account
        // for this address yet (a deposit still landing). The next funded
        // snapshot may ask again; each caller asks at most once.
        _sessionDone.remove(address);
        return HlReferrerOutcome.retryLater;
      } on HyperliquidRejectedException catch (e) {
        final reason = e.reason.toLowerCase();
        return await _settle(
            address,
            reason.contains('already')
                ? HlReferrerOutcome.alreadySet
                : HlReferrerOutcome.failed);
      } on HyperliquidApiException catch (e) {
        if (e.statusCode == 429 || e.statusCode >= 500) {
          return HlReferrerOutcome.retryLater;
        }
        return await _settle(address, HlReferrerOutcome.failed);
      } catch (e) {
        if (HyperliquidExchangeService.isOfflineError(e)) {
          return HlReferrerOutcome.retryLater;
        }
        return await _settle(address, HlReferrerOutcome.failed);
      }
    } catch (_) {
      return HlReferrerOutcome.retryLater;
    }
  }

  static Future<HlReferrerOutcome> _settle(
      String address, HlReferrerOutcome outcome) async {
    try {
      await secureStorage.write(key: _attemptedKey(address), value: 'true');
    } catch (_) {
      // The session guard still stops a repeat until the next launch.
    }
    TrackingService.track('hl_referrer_set', params: {
      'result': switch (outcome) {
        HlReferrerOutcome.ok => 'ok',
        HlReferrerOutcome.alreadySet => 'already_set',
        _ => 'failed',
      },
    });
    return outcome;
  }

  static Future<bool> _attempted(String address) async {
    try {
      return await secureStorage.read(key: _attemptedKey(address)) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// True when the venue names a referrer for [address], false when it
  /// names none, null when the venue could not be asked.
  static Future<bool?> _hasReferrer(String address) async {
    try {
      final resp = await http
          .post(
            HyperliquidConstants.infoUri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'type': 'referral', 'user': address}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map || !decoded.containsKey('referredBy')) return null;
      return decoded['referredBy'] != null;
    } catch (_) {
      return null;
    }
  }
}
