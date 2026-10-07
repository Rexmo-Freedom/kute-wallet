// lib/services/venue_owner_link_service.dart
//
// Proves to the backend, once per venue account, that the signed-in
// wallet owns it, so builder-fee trades on that account can be credited to
// this user. Works for any venue account and any key: today the hot
// Hyperliquid account and the hot Polymarket signer; an imported
// Hyperliquid account can call [VenueOwnerLinkService.ensureLinked] with
// its own key.
//
// Flow (both routes behind the wallet session, see
// AffiliateService.sendWithSession):
//   1. POST /api/v1/venue-owner/challenge {venue, address[, trading_address]}
//      → {challenge, expires_at} or {already_linked: true}.
//   2. EIP-191 personal_sign of the challenge, exactly as returned, by the
//      account's key, then POST /api/v1/venue-owner with the signature.
//
// The challenge is signed only when it reads
// `kute-<venue>-owner-v1|<this address>|…`, so the backend can never get
// this key to sign anything else.
//
// Records (secure storage, `kute_venue_owner_v1:<venue>:<address>`):
// `linked` (also already linked) or `conflict` (the account is linked to
// another user). Either one ends the work for that account for good.
// Every other failure is tried again next app session: at most one
// attempt per account per app session, one at a time. Requests the backend
// rejects as malformed (400) stop after [_maxRejections] sessions; network,
// 401, 429 and 5xx failures have no cap. An expired challenge is retried
// once right away with a fresh one.
//
// Analytics: exactly one `venue_account_link_result` per attempt, with the
// venue and the result only. Never the address, signature, challenge,
// nonce or user id.
//
// No UI and never blocks: callers fire it with `unawaited`, it never
// throws, and nothing here runs inside a Ledger operation.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/hardware/evm_signing_request.dart'
    show personalMessageDigest;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

enum VenueOwnerLinkResult {
  /// The backend linked the account to this user now.
  linked,

  /// The backend already had the account linked to this user.
  alreadyLinked,

  /// The account is linked to another user. Never retried.
  conflict,

  /// Anything else. Tried again next app session.
  failed,

  /// Nothing sent: already recorded, already tried this session, a Ledger
  /// operation, no backend, or invalid input. No analytics event.
  skipped,
}

class VenueOwnerLinkService {
  VenueOwnerLinkService._();

  static const hyperliquid = 'hyperliquid';
  static const polymarket = 'polymarket';
  static const _venues = {hyperliquid, polymarket};

  static const _linked = 'linked';
  static const _conflict = 'conflict';

  /// Sessions in which the backend rejected the request itself (400)
  /// before an account stops trying.
  static const _maxRejections = 3;

  static final _address = RegExp(r'^0x[0-9a-f]{40}$');

  /// Settled or running in this app session, keyed `venue:address`.
  static final Set<String> _sessionTried = {};
  static final Map<String, Future<VenueOwnerLinkResult>> _inFlight = {};

  @visibleForTesting
  static void resetForTest() {
    _sessionTried.clear();
    _inFlight.clear();
  }

  @visibleForTesting
  static String storageKey(String venue, String address) =>
      'kute_venue_owner_v1:$venue:${address.toLowerCase()}';

  /// The Polymarket trading wallet of a linked signer, so a caller holding
  /// only the address its CLOB key is bound to still finds the link.
  static String _tradingKey(String tradingAddress) =>
      'kute_venue_owner_v1:polymarket_trading:${tradingAddress.toLowerCase()}';

  static String _rejectionsKey(String venue, String address) =>
      '${storageKey(venue, address)}:rejections';

  /// Links the account [key] controls on [venue] to the signed-in user, if
  /// it is not already. [tradingAddress] is the Polymarket wallet orders
  /// are made from (ignored for Hyperliquid; defaults to the signer).
  /// Never throws.
  static Future<void> ensureLinked({
    required String venue,
    required EthPrivateKey key,
    String? tradingAddress,
  }) async {
    try {
      await link(venue: venue, key: key, tradingAddress: tradingAddress);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// [ensureLinked] with its outcome, for tests.
  @visibleForTesting
  static Future<VenueOwnerLinkResult> link({
    required String venue,
    required EthPrivateKey key,
    String? tradingAddress,
  }) {
    try {
      if (LedgerOperationScope.isActive || !_venues.contains(venue)) {
        return Future.value(VenueOwnerLinkResult.skipped);
      }
      final address = key.address.hexWith0x.toLowerCase();
      final id = '$venue:$address';
      final running = _inFlight[id];
      if (running != null) return running;
      if (!_sessionTried.add(id)) {
        return Future.value(VenueOwnerLinkResult.skipped);
      }
      final trading = venue == polymarket
          ? (tradingAddress == null || tradingAddress.isEmpty
                  ? address
                  : tradingAddress)
              .toLowerCase()
          : null;
      final run = _run(venue, address, key, trading)
          .catchError((Object _) => VenueOwnerLinkResult.failed)
          // A block body: returning the removed future would make the run
          // wait on itself.
          .whenComplete(() {
        _inFlight.remove(id);
      });
      _inFlight[id] = run;
      return run;
    } catch (_) {
      return Future.value(VenueOwnerLinkResult.skipped);
    }
  }

  /// True once the Polymarket account of [address] (the signer, or its
  /// trading wallet) is recorded as linked on this device. False on any
  /// storage failure.
  static Future<bool> isPolymarketLinked(String address) async {
    try {
      final a = address.toLowerCase();
      if (await secureStorage.read(key: storageKey(polymarket, a)) == _linked) {
        return true;
      }
      return await secureStorage.read(key: _tradingKey(a)) == _linked;
    } catch (_) {
      return false;
    }
  }

  static Future<VenueOwnerLinkResult> _run(
    String venue,
    String address,
    EthPrivateKey key,
    String? trading,
  ) async {
    if (trading != null && !_address.hasMatch(trading)) {
      return VenueOwnerLinkResult.skipped;
    }
    final stored = await _read(storageKey(venue, address));
    if (stored == _linked || stored == _conflict) {
      return VenueOwnerLinkResult.skipped;
    }
    final rejections =
        int.tryParse(await _read(_rejectionsKey(venue, address)) ?? '') ?? 0;
    if (rejections >= _maxRejections) return VenueOwnerLinkResult.skipped;
    final backend = dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : '';
    if (backend.isEmpty) return VenueOwnerLinkResult.skipped;

    final body = <String, Object>{
      'venue': venue,
      'address': address,
      if (trading != null) 'trading_address': trading,
    };

    VenueOwnerLinkResult outcome;
    try {
      outcome = await _attempt(backend, venue, address, key, trading, body);
    } catch (_) {
      // Network, timeout or no wallet session: next session.
      outcome = VenueOwnerLinkResult.failed;
    }
    _track(venue, outcome);
    return outcome;
  }

  static Future<VenueOwnerLinkResult> _attempt(
    String backend,
    String venue,
    String address,
    EthPrivateKey key,
    String? trading,
    Map<String, Object> body,
  ) async {
    for (var round = 0; round < 2; round++) {
      final challengeRes = await _post('venue_owner_challenge',
          '$backend/api/v1/venue-owner/challenge', body);
      if (challengeRes.statusCode == 409) {
        return _settle(venue, address, trading, VenueOwnerLinkResult.conflict);
      }
      if (challengeRes.statusCode == 400) {
        return _rejected(venue, address);
      }
      if (challengeRes.statusCode != 200) return VenueOwnerLinkResult.failed;
      final challengeBody = _json(challengeRes.body);
      if (challengeBody['already_linked'] == true) {
        return _settle(
            venue, address, trading, VenueOwnerLinkResult.alreadyLinked);
      }
      final challenge = challengeBody['challenge'];
      if (challenge is! String ||
          !challenge.startsWith('kute-$venue-owner-v1|$address|')) {
        return VenueOwnerLinkResult.failed;
      }

      final linkRes =
          await _post('venue_owner_link', '$backend/api/v1/venue-owner', {
        ...body,
        'challenge': challenge,
        'signature': await personalSign(challenge, key),
      });
      if (linkRes.statusCode == 200) {
        final linkBody = _json(linkRes.body);
        if (linkBody['linked'] != true) return VenueOwnerLinkResult.failed;
        return _settle(
            venue,
            address,
            trading,
            linkBody['already_linked'] == true
                ? VenueOwnerLinkResult.alreadyLinked
                : VenueOwnerLinkResult.linked);
      }
      if (linkRes.statusCode == 409) {
        return _settle(venue, address, trading, VenueOwnerLinkResult.conflict);
      }
      if (linkRes.statusCode == 400) {
        if (round == 0 && _json(linkRes.body)['error'] == 'challenge_expired') {
          continue; // once more, with a fresh challenge
        }
        return _rejected(venue, address);
      }
      return VenueOwnerLinkResult.failed;
    }
    return _rejected(venue, address);
  }

  /// EIP-191 personal_sign of the UTF-8 [message]: `0x` + r||s||v hex,
  /// 65 bytes, v in {27, 28}.
  @visibleForTesting
  static Future<String> personalSign(String message, EthPrivateKey key) async {
    final digest =
        personalMessageDigest(Uint8List.fromList(utf8.encode(message)));
    final sig = await key.signToSignature(digest);
    final bytes = Uint8List(65)
      ..setRange(0, 32, _bytes32(sig.r))
      ..setRange(32, 64, _bytes32(sig.s));
    bytes[64] = sig.v < 27 ? sig.v + 27 : sig.v;
    return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  static Uint8List _bytes32(BigInt value) {
    final out = Uint8List(32);
    var v = value;
    for (var i = 31; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static Future<http.Response> _post(
      String route, String url, Map<String, Object> body) {
    return AffiliateService.sendWithSession(
      route,
      (auth) => http
          .post(
            Uri.parse(url),
            headers: {...auth, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15)),
    );
  }

  static Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Records a terminal outcome for the account.
  static Future<VenueOwnerLinkResult> _settle(String venue, String address,
      String? trading, VenueOwnerLinkResult outcome) async {
    final value =
        outcome == VenueOwnerLinkResult.conflict ? _conflict : _linked;
    await _write(storageKey(venue, address), value);
    if (trading != null && value == _linked) {
      await _write(_tradingKey(trading), _linked);
    }
    return outcome;
  }

  /// A 400: counted, so a request the backend will never accept stops
  /// after a few sessions.
  static Future<VenueOwnerLinkResult> _rejected(
      String venue, String address) async {
    final key = _rejectionsKey(venue, address);
    final count = int.tryParse(await _read(key) ?? '') ?? 0;
    await _write(key, '${count + 1}');
    return VenueOwnerLinkResult.failed;
  }

  static void _track(String venue, VenueOwnerLinkResult outcome) {
    final result = switch (outcome) {
      VenueOwnerLinkResult.linked => 'linked',
      VenueOwnerLinkResult.alreadyLinked => 'already_linked',
      VenueOwnerLinkResult.conflict => 'conflict',
      VenueOwnerLinkResult.failed => 'failed',
      VenueOwnerLinkResult.skipped => null,
    };
    if (result == null) return;
    TrackingService.track('venue_account_link_result',
        params: {'venue': venue, 'result': result});
  }

  static Future<String?> _read(String key) async {
    try {
      return await secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, String value) async {
    try {
      await secureStorage.write(key: key, value: value);
    } catch (_) {
      // The session guard still stops a repeat until the next launch.
    }
  }
}
