// lib/services/polymarket/builder_code_resolver.dart
//
// The Polymarket V2 builder code signed into every order's `builder`
// field. The backend is its only source (GET /api/v1/pm/builder-code,
// `{builderCode, revision}`); the app ships no fallback code of its own.
//
// Attribution never gates trading. When the backend cannot be reached,
// answers for a different policy revision, or returns anything that is not
// a 0x-prefixed bytes32, the order is signed with the zero builder: no
// attribution and, because the venue charges builder fees only against a
// registered code, no builder fee either. The person can always trade.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/polymarket_constants.dart';

/// Where a resolved builder code came from.
enum BuilderCodeSource { backend, noAttribution }

class ResolvedBuilderCode {
  const ResolvedBuilderCode(this.code, this.source);

  static const none = ResolvedBuilderCode(
      PolymarketConstants.bytes32Zero, BuilderCodeSource.noAttribution);

  /// 0x-prefixed bytes32, the zero value when there is no attribution.
  final String code;
  final BuilderCodeSource source;

  bool get attributed => source == BuilderCodeSource.backend;
}

final RegExp _bytes32 = RegExp(r'^0x[0-9a-fA-F]{64}$');

/// True when [code] is the zero builder, i.e. the order carries no
/// attribution and no builder fee applies.
bool isZeroBuilderCode(String code) =>
    code.toLowerCase() == PolymarketConstants.bytes32Zero;

class PolymarketBuilderCodeResolver {
  PolymarketBuilderCodeResolver({
    required this.client,
    required this.baseUrl,
    required this.revision,
    required this.session,
    DateTime Function()? clock,
    this.timeouts = const [Duration(seconds: 5), Duration(seconds: 10)],
    this.failureBackoff = const Duration(minutes: 1),
    void Function(Object error, Duration elapsed)? onFailure,
    void Function(int? revision)? onRevisionMismatch,
  })  : _clock = clock ?? DateTime.now,
        _onFailure = onFailure,
        _onRevisionMismatch = onRevisionMismatch;

  final http.Client Function() client;
  final String Function() baseUrl;

  /// The capability policy revision the app currently holds, if any. A
  /// code is only used for the revision it was issued under.
  final int? Function() revision;
  final String? Function() session;

  /// Attempts per resolution. The first is short so a healthy connection
  /// is not held up; the second gives a slow VPN the time it needs.
  final List<Duration> timeouts;

  /// After a failed resolution, orders sign with the zero builder for this
  /// long without asking again, so an outage costs one wait, not one per
  /// order.
  final Duration failureBackoff;

  final DateTime Function() _clock;
  final void Function(Object error, Duration elapsed)? _onFailure;
  final void Function(int? revision)? _onRevisionMismatch;

  String? _code;
  int? _codeRevision;
  String? _codeSession;
  DateTime? _failedAt;
  Future<ResolvedBuilderCode>? _inFlight;

  /// Forgets the held code and any failure backoff.
  void reset() {
    _code = null;
    _codeRevision = null;
    _codeSession = null;
    _failedAt = null;
    _inFlight = null;
  }

  /// The code for the order being signed now. Never throws.
  Future<ResolvedBuilderCode> resolve() {
    final currentRevision = revision();
    final currentSession = session();
    if (currentRevision != _codeRevision || currentSession != _codeSession) {
      _code = null;
      _failedAt = null;
      _codeRevision = currentRevision;
      _codeSession = currentSession;
    }
    final held = _code;
    if (held != null) {
      return Future.value(ResolvedBuilderCode(held, BuilderCodeSource.backend));
    }
    final failedAt = _failedAt;
    if (failedAt != null && _clock().difference(failedAt) < failureBackoff) {
      return Future.value(ResolvedBuilderCode.none);
    }
    return _inFlight ??= _fetch(currentRevision, currentSession)
        .whenComplete(() => _inFlight = null);
  }

  Future<ResolvedBuilderCode> _fetch(
      int? expectedRevision, String? bearer) async {
    final backend = baseUrl().replaceFirst(RegExp(r'/$'), '');
    if (backend.isEmpty) return ResolvedBuilderCode.none;
    final clock = Stopwatch()..start();
    for (final timeout in timeouts) {
      try {
        final response = await client()
            .get(Uri.parse('$backend/api/v1/pm/builder-code'), headers: {
          if (bearer != null && bearer.isNotEmpty)
            'Authorization': 'Bearer $bearer',
        }).timeout(timeout);
        final parsed = response.statusCode == 200
            ? parseBuilderCodeResponse(response.body,
                expectedRevision: expectedRevision)
            : null;
        if (parsed == null) {
          if (response.statusCode == 200 &&
              expectedRevision != null &&
              _revisionOf(response.body) != expectedRevision) {
            _onRevisionMismatch?.call(_revisionOf(response.body));
          }
          throw StateError('No valid builder code (${response.statusCode})');
        }
        // Only keep it if nothing changed while the request was out.
        if (revision() == expectedRevision && session() == bearer) {
          _code = parsed;
          _failedAt = null;
        }
        return ResolvedBuilderCode(parsed, BuilderCodeSource.backend);
      } on TimeoutException catch (e) {
        _onFailure?.call(e, clock.elapsed);
      } catch (e) {
        _onFailure?.call(e, clock.elapsed);
        break;
      }
    }
    if (revision() == expectedRevision && session() == bearer) {
      _failedAt = _clock();
    }
    return ResolvedBuilderCode.none;
  }

  static int? _revisionOf(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map && data['revision'] is int
          ? data['revision'] as int
          : null;
    } catch (_) {
      return null;
    }
  }
}

/// The builder code in a `/api/v1/pm/builder-code` body, or null when the
/// body is malformed, carries no 0x-prefixed bytes32 code, or was issued
/// for another policy revision than [expectedRevision] (when one is held).
/// The zero code is returned as null too: it means "not configured".
String? parseBuilderCodeResponse(String body, {int? expectedRevision}) {
  try {
    final data = jsonDecode(body);
    if (data is! Map) return null;
    if (expectedRevision != null && data['revision'] != expectedRevision) {
      return null;
    }
    final code = data['builderCode'];
    if (code is! String ||
        !_bytes32.hasMatch(code) ||
        isZeroBuilderCode(code)) {
      return null;
    }
    return code;
  } catch (_) {
    return null;
  }
}
