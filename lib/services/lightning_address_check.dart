// lib/services/lightning_address_check.dart
//
// Whether a user@domain really is a Lightning address (founder, 9 November
// 2026: "show it as a Lightning address if it exists, otherwise it's an
// email"). The two look the same, so the shape cannot tell them apart: only
// the domain's LNURL-pay endpoint can (LUD-16,
// https://<domain>/.well-known/lnurlp/<user>).
//
// PRIVACY. The domain sees that this name was looked up, so only an address
// the person typed, pasted or picked is ever asked about, after a pause in
// typing, and a phone's contact list never is. The request deliberately does
// not go through SharedHttpClient: that client reports each request's host
// to analytics, and this host is something the person typed.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

enum LightningAddressStatus {
  /// The answer has not arrived yet.
  checking,

  /// The domain answers with a pay request for this name.
  exists,

  /// The domain answered and has no such name: an email.
  missing,

  /// No usable answer (offline, a timeout, the host's own trouble). Says
  /// nothing about the address, so nothing is refused on it: the payment's
  /// own parse decides, as it always did.
  unknown,
}

class LightningAddressCheck {
  LightningAddressCheck._();

  static const Duration timeout = Duration(seconds: 5);
  static const Duration _existsFor = Duration(minutes: 10);
  static const Duration _missingFor = Duration(minutes: 1);

  /// How long typing must pause before a name is sent to its domain.
  @visibleForTesting
  static Duration debounce = const Duration(milliseconds: 400);

  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static final Map<String, ({LightningAddressStatus status, DateTime at})>
      _answers = {};

  @visibleForTesting
  static void resetForTest() {
    _answers.clear();
    debounce = const Duration(milliseconds: 400);
    clientFactory = http.Client.new;
  }

  static final RegExp _shape = RegExp(
      r'^([a-z0-9._+\-]+)@([a-z0-9\-]+(?:\.[a-z0-9\-]+)+)$',
      caseSensitive: false);

  /// The address in the one form it is asked about and cached under, null
  /// when [raw] is not a user@domain.
  static String? keyOf(String raw) {
    var a = raw.trim().toLowerCase();
    if (a.startsWith('lightning:')) a = a.substring('lightning:'.length);
    return _shape.hasMatch(a) ? a : null;
  }

  /// A remembered answer that is still good.
  static LightningAddressStatus? cached(String key) {
    final hit = _answers[key];
    if (hit == null) return null;
    final life = hit.status == LightningAddressStatus.exists
        ? _existsFor
        : _missingFor;
    return DateTime.now().difference(hit.at) < life ? hit.status : null;
  }

  /// Asks the domain. Never throws.
  static Future<LightningAddressStatus> check(String key) async {
    final match = _shape.firstMatch(key);
    if (match == null) return LightningAddressStatus.missing;
    final known = cached(key);
    if (known != null) return known;
    final client = clientFactory();
    try {
      final response = await client.get(
        Uri.https(match.group(2)!,
            '/.well-known/lnurlp/${Uri.encodeComponent(match.group(1)!)}'),
        headers: const {'accept': 'application/json'},
      ).timeout(timeout);
      final status = statusOf(response.statusCode, response.body);
      if (status != LightningAddressStatus.unknown) {
        _answers[key] = (status: status, at: DateTime.now());
      }
      return status;
    } catch (_) {
      return LightningAddressStatus.unknown;
    } finally {
      client.close();
    }
  }

  /// What an answer means. A 200 counts only as a real pay request: many
  /// sites answer any path with their HTML page. A 5xx, a rate limit or a
  /// refusal is the host's trouble and says nothing about the name.
  @visibleForTesting
  static LightningAddressStatus statusOf(int code, String body) {
    if (code == 404 || code == 410) return LightningAddressStatus.missing;
    if (code != 200) return LightningAddressStatus.unknown;
    try {
      final json = jsonDecode(body);
      if (json is Map &&
          json['tag'] == 'payRequest' &&
          json['callback'] is String) {
        return LightningAddressStatus.exists;
      }
    } catch (_) {}
    return LightningAddressStatus.missing;
  }
}

/// The status of a typed address, by [LightningAddressCheck.keyOf]. A name
/// the person is still typing is dropped before it is ever sent.
final lightningAddressStatusProvider = FutureProvider.autoDispose
    .family<LightningAddressStatus, String>((ref, key) async {
  final known = LightningAddressCheck.cached(key);
  if (known != null) return known;
  var left = false;
  ref.onDispose(() => left = true);
  if (LightningAddressCheck.debounce > Duration.zero) {
    await Future<void>.delayed(LightningAddressCheck.debounce);
  }
  if (left) return LightningAddressStatus.unknown;
  return LightningAddressCheck.check(key);
});

/// [raw]'s status for a screen that is building, null when it is not a
/// user@domain.
LightningAddressStatus? watchLightningAddress(WidgetRef ref, String raw) {
  final key = LightningAddressCheck.keyOf(raw);
  if (key == null) return null;
  return ref.watch(lightningAddressStatusProvider(key)).valueOrNull ??
      LightningAddressStatus.checking;
}
