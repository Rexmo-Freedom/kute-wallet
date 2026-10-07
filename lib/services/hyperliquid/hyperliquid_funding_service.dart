import 'package:kute/services/runtime_capabilities_service.dart';
// lib/services/hyperliquid/hyperliquid_funding_service.dart
//
// Builder-fee configuration for the Hyperliquid integration, via OUR
// backend (dotenv BACKEND, /api/v1/hl/*).
//
// Backend endpoint:
//   GET  /api/v1/hl/builder → 200 {builderAddress, defaultFeeTenthsBp,
//        listedFeeTenthsBp, refereeDiscountTenthsBp, maxFeeRate,
//        referralCode, revision}
//        | 404 {referralCode} (no builder configured). The ONLY source of
//        the builder: anything but a valid 200 means orders carry no
//        builder. `referralCode` (both answers) is Kute's Hyperliquid
//        referral code; empty, absent or malformed means none.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/affiliate_model.dart'
    show AffiliateService;
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/tracking_service.dart';
import 'dart:async';

/// Builder-fee attribution config served by the backend.
class HlBuilderInfo {
  final String builderAddress;

  /// Default per-order fee in tenths of a basis point (the order wire's
  /// `f` unit).
  final int defaultFeeTenthsBp;

  /// Max rate the user approves once, e.g. '0.01%'.
  final String maxFeeRate;

  /// The published (undiscounted) fee and the referee discount the backend
  /// already subtracted from [defaultFeeTenthsBp] for this session. Both in
  /// tenths of a basis point; display only.
  final int listedFeeTenthsBp;
  final int refereeDiscountTenthsBp;

  const HlBuilderInfo({
    required this.builderAddress,
    required this.defaultFeeTenthsBp,
    required this.maxFeeRate,
    int? listedFeeTenthsBp,
    this.refereeDiscountTenthsBp = 0,
  }) : listedFeeTenthsBp = listedFeeTenthsBp ?? defaultFeeTenthsBp;

  /// True when this session pays less than the listed fee.
  bool get discounted =>
      refereeDiscountTenthsBp > 0 && defaultFeeTenthsBp < listedFeeTenthsBp;

  HlBuilderFee get asOrderFee =>
      HlBuilderFee(address: builderAddress, feeTenthsBp: defaultFeeTenthsBp);
}

class HyperliquidFundingService {
  HyperliquidFundingService._();

  // ────────────────────────────── builder ─────────────────────────────
  //
  // The builder (Kute's fee recipient), the per-order fee and the approval
  // cap come ONLY from the backend. The app ships no builder address and
  // keeps no on-disk copy of one: when the backend's answer is missing,
  // invalid or a 404, there is no builder, so orders carry no `b`/`f` and
  // no approval is asked for. Trading is never blocked on this.
  //
  // Every consumer (the `maxBuilderFee` check, `approveBuilderFee` on hot
  // and Ledger wallets, the order's builder field, the Ledger executor's
  // pre-sign check) reads [getBuilder], so they all see the same address.
  // A rotated address arrives with a new policy revision, which drops the
  // in-memory copy; the approval record and the venue's `maxBuilderFee`
  // are per address, so the next order finds the new builder unapproved
  // and runs the approval flow again, exactly as the first time.

  static HlBuilderInfo? _cachedBuilder;
  static String? _cachedReferralCode;
  static bool _builderResolved = false;
  static int? _builderPolicyRevision;
  static String? _builderSession;
  static bool _builderRejectionReported = false;
  static DateTime? _builderUnavailableUntil;

  /// How long invalid settings stay unused without repeating the lookup.
  /// A new policy revision or session clears this immediately.
  static const Duration _builderRejectionTtl = Duration(minutes: 10);

  /// How long an unreachable backend is not asked again, so one order does
  /// not wait out the timeouts at every step and every step sees the same
  /// (absent) builder.
  static const Duration _builderUnreachableTtl = Duration(seconds: 30);

  /// `hl_builder_address_source` values already reported this app session.
  static final Set<String> _reportedBuilderSources = {};

  @visibleForTesting
  static void resetBuilderCacheForTest() {
    _cachedBuilder = null;
    _cachedReferralCode = null;
    _builderPolicyRevision = null;
    _builderResolved = false;
    _builderRejectionReported = false;
    _builderUnavailableUntil = null;
    // Tests swap the HTTP client per zone; drop the shared one with the
    // cache so the next read picks up the current zone's client.
    _builderClient?.close();
    _builderClient = null;
  }

  /// Per-app-session analytics dedupe; production never resets it.
  @visibleForTesting
  static void resetBuilderSourceTrackingForTest() =>
      _reportedBuilderSources.clear();

  /// One connection for the builder reads; a fresh client per call pays a
  /// TLS handshake each time, which over a VPN is most of the allowance.
  static http.Client? _builderClient;
  static http.Client get _client => _builderClient ??= http.Client();

  static HlBuilderInfo _builderFrom(Map<String, dynamic> data) {
    final listed = data['listedFeeTenthsBp'];
    final discount = data['refereeDiscountTenthsBp'];
    return HlBuilderInfo(
      builderAddress: data['builderAddress'] as String,
      defaultFeeTenthsBp: (data['defaultFeeTenthsBp'] as num).toInt(),
      maxFeeRate: data['maxFeeRate'] as String,
      listedFeeTenthsBp: listed is num && listed >= 0 ? listed.toInt() : null,
      refereeDiscountTenthsBp:
          discount is num && discount >= 0 ? discount.toInt() : 0,
    );
  }

  /// Reports where the builder came from, at most once per source per app
  /// session. Never carries the address.
  static void _reportBuilderSource(String source, {String? reason}) {
    if (!_reportedBuilderSources.add(source)) return;
    TrackingService.track('hl_builder_address_source', params: {
      'source': source,
      if (reason != null) 'reason': reason,
    });
  }

  static HlBuilderInfo? _noBuilder(String reason, {Duration? retryAfter}) {
    if (retryAfter != null) {
      _builderUnavailableUntil = DateTime.now().add(retryAfter);
    }
    _reportBuilderSource('none', reason: reason);
    return null;
  }

  /// Warms the in-memory settings so the order path reads them at once.
  static Future<void> prefetchBuilder() async {
    try {
      await getBuilder();
    } catch (_) {}
  }

  /// The builder the backend publishes for the active policy revision and
  /// session, or null when there is none to attach: a 404, an invalid
  /// answer or an unreachable backend. Null means "no builder": orders go
  /// out without one and nothing is approved. Never throws.
  static Future<HlBuilderInfo?> getBuilder() async {
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;
    // The fee is per session (a referred account may pay less), so a new
    // session invalidates the cache just like a new policy revision.
    final session = AffiliateService.sessionToken;
    if (_builderPolicyRevision != revision || _builderSession != session) {
      resetBuilderCacheForTest();
      _builderPolicyRevision = revision;
      _builderSession = session;
    }
    if (_builderResolved) return _cachedBuilder;
    final until = _builderUnavailableUntil;
    if (until != null && DateTime.now().isBefore(until)) return null;

    String backend;
    try {
      backend = dotenv.env['BACKEND'] ?? '';
    } catch (_) {
      backend = '';
    }
    if (backend.isEmpty) return _noBuilder('no_backend');

    final headers = {
      if (session != null && session.isNotEmpty)
        'Authorization': 'Bearer $session',
    };
    // Two attempts: the first is short so a healthy connection is not
    // held up, the second gives a slow VPN the time it needs.
    for (final timeout in const [Duration(seconds: 5), Duration(seconds: 10)]) {
      try {
        final res = await _client
            .get(Uri.parse('$backend/api/v1/hl/builder'), headers: headers)
            .timeout(timeout);
        if (res.statusCode == 404) {
          _cachedBuilder = null;
          _cachedReferralCode = _referralCodeIn(res.body);
          _builderResolved = true;
          return _noBuilder('not_configured');
        }
        if (res.statusCode != 200) break;
        final data = jsonDecode(res.body);
        if (revision != null && data is Map && data['revision'] != revision) {
          // Issued for another policy revision: not this session's
          // settings. Ask again once the snapshot catches up.
          return _noBuilder('revision_mismatch');
        }
        final rejection = data is Map<String, dynamic>
            ? builderConfigRejection(data)
            : 'malformed';
        if (rejection != null) {
          if (!_builderRejectionReported) {
            _builderRejectionReported = true;
            TrackingService.hlBuilderConfigRejected(reason: rejection);
          }
          return _noBuilder('invalid', retryAfter: _builderRejectionTtl);
        }
        _cachedBuilder = _builderFrom(data as Map<String, dynamic>);
        _cachedReferralCode = _referralCodeIn(data);
        _builderResolved = true;
        _reportBuilderSource('backend');
        return _cachedBuilder;
      } on TimeoutException {
        // Try once more with the longer allowance.
      } catch (_) {
        break;
      }
    }
    return _noBuilder('unreachable', retryAfter: _builderUnreachableTtl);
  }

  /// Kute's Hyperliquid referral code for the active policy revision and
  /// session, or null when none is published (or the backend has not
  /// answered). Read from the same answer as [getBuilder]. Never throws.
  static Future<String?> getReferralCode() async {
    await getBuilder();
    return _cachedReferralCode;
  }

  /// Hyperliquid referral codes: 1 to 20 uppercase letters or digits.
  static final RegExp _referralCodePattern = RegExp(r'^[A-Z0-9]{1,20}$');

  /// The well-formed `referralCode` in a builder answer, else null.
  static String? _referralCodeIn(Object? body) {
    try {
      final data = body is String ? jsonDecode(body) : body;
      final code = data is Map ? data['referralCode'] : null;
      return code is String && _referralCodePattern.hasMatch(code)
          ? code
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Validate the runtime recipient and exact integer fees within the exchange
  /// perps maximum (0.1%). Approval increases need a separate user review.
  @visibleForTesting
  static String? builderConfigRejection(Map<String, dynamic> data) {
    final address = data['builderAddress'];
    if (address is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address) ||
        BigInt.parse(address.substring(2), radix: 16) == BigInt.zero) {
      return 'invalid_address';
    }
    final fee = data['defaultFeeTenthsBp'];
    if (fee is! num || fee != fee.roundToDouble() || fee < 0 || fee > 100) {
      return 'fee_tenths_bp';
    }
    final rate = data['maxFeeRate'];
    final cap = rate is String ? builderFeeCapTenthsBp(rate) : null;
    if (cap == null || cap < fee || cap > 100) return 'max_fee_rate';
    return null;
  }

  /// Parses an exact percent into tenths of a basis point (1% = 1000).
  static int? builderFeeCapTenthsBp(String rate) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?%$').firstMatch(rate.trim());
    if (match == null) return null;
    final fraction = match.group(2) ?? '';
    final numerator = BigInt.parse('${match.group(1)}$fraction') * BigInt.from(1000);
    final denominator = BigInt.from(10).pow(fraction.length);
    if (numerator % denominator != BigInt.zero) return null;
    return (numerator ~/ denominator).toInt();
  }
}
