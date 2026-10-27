// lib/services/polymarket/builder_code_resolver.dart
//
// The Polymarket V2 builder code signed into every order's `builder`
// field. The backend is its only source (GET /api/v1/pm/builder-code,
// `{builderCode, revision}`); the app ships no fallback code of its own.
//
// The code is off the order's critical path. An order signs with
// ([cachedCode]), in this order: the code the runtime policy the app
// already holds carries ([policyCode], `polymarket.builderCode` on
// `/config/capabilities` and `/config/policy`), else the last code the
// backend gave, kept on the device ([persist] / [loadPersisted]), while
// `/pm/builder-code` is asked again only in the background ([refresh]). A
// phone that once read the code never waits on the network for it again; a
// phone that never did signs with the zero builder rather than wait.
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
import 'package:kute/services/runtime_capabilities_service.dart';

/// Where a resolved builder code came from: the runtime policy snapshot,
/// the backend this run, the copy kept on the device from an earlier run,
/// or nowhere.
enum BuilderCodeSource { policy, backend, persisted, noAttribution }

class ResolvedBuilderCode {
  const ResolvedBuilderCode(this.code, this.source);

  static const none = ResolvedBuilderCode(
      PolymarketConstants.bytes32Zero, BuilderCodeSource.noAttribution);

  /// 0x-prefixed bytes32, the zero value when there is no attribution.
  final String code;
  final BuilderCodeSource source;

  bool get attributed => source != BuilderCodeSource.noAttribution;
}

final RegExp _bytes32 = RegExp(r'^0x[0-9a-fA-F]{64}$');

/// The device copy of the code and the policy revision it was issued under
/// (null when the app held no policy when it was read).
class PersistedBuilderCode {
  const PersistedBuilderCode(this.code, this.revision);
  final String code;
  final int? revision;
}

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
    Future<PersistedBuilderCode?> Function()? loadPersisted,
    Future<void> Function(PersistedBuilderCode copy)? persist,
    String? Function()? policyCode,
  })  : _clock = clock ?? DateTime.now,
        _onFailure = onFailure,
        _onRevisionMismatch = onRevisionMismatch,
        _loadPersisted = loadPersisted,
        _persist = persist,
        _policyCode = policyCode;

  final http.Client Function() client;
  final String Function() baseUrl;

  /// The capability policy revision the app currently holds, if any. A
  /// code read this run is only held for the revision it was issued under;
  /// the persisted copy is signed with until the refresh for a new
  /// revision lands.
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
  final Future<PersistedBuilderCode?> Function()? _loadPersisted;
  final Future<void> Function(PersistedBuilderCode copy)? _persist;

  /// The builder code the runtime policy snapshot the app holds carries,
  /// when it has one. It is the freshest source and costs no request, so
  /// it wins; it is copied to the device so the next start has it too.
  final String? Function()? _policyCode;

  String? _code;
  int? _codeRevision;
  String? _codeSession;
  DateTime? _failedAt;
  Future<ResolvedBuilderCode>? _inFlight;

  /// The last code the backend gave, from this run or an earlier one.
  PersistedBuilderCode? _persisted;
  Future<void>? _hydrating;
  bool _hydrated = false;

  /// Forgets the held code, the persisted copy in memory and any failure
  /// backoff. The device copy itself is left alone.
  void reset() {
    _code = null;
    _codeRevision = null;
    _codeSession = null;
    _failedAt = null;
    _inFlight = null;
    _persisted = null;
    _hydrated = false;
    _hydrating = null;
  }

  /// Reads the device copy once. Never throws; safe to call repeatedly.
  Future<void> hydrate() {
    if (_hydrated) return Future.value();
    return _hydrating ??= () async {
      try {
        final stored = await _loadPersisted?.call();
        if (stored != null &&
            _bytes32.hasMatch(stored.code) &&
            !isZeroBuilderCode(stored.code)) {
          _persisted ??= stored;
        }
      } catch (_) {
        // No device copy: the first backend answer becomes it.
      } finally {
        _hydrated = true;
        _hydrating = null;
      }
    }();
  }

  /// The code an order signs with right now, without waiting on anything:
  /// the policy snapshot's code, else the backend's code for the current
  /// revision and session, else the last code kept on the device, else
  /// null (sign with the zero builder).
  String? get cachedCode {
    _dropStaleHeld();
    return _fromPolicy() ?? _code ?? _persisted?.code;
  }

  /// A valid code from the policy snapshot, remembered on the device as
  /// it changes. Null when the policy carries none.
  String? _fromPolicy() {
    String? code;
    try {
      code = _policyCode?.call();
    } catch (_) {
      return null;
    }
    if (code == null || !_bytes32.hasMatch(code) || isZeroBuilderCode(code)) {
      return null;
    }
    final currentRevision = revision();
    if (_persisted?.code != code || _persisted?.revision != currentRevision) {
      final copy = PersistedBuilderCode(code, currentRevision);
      _persisted = copy;
      unawaited(Future<void>.sync(() => _persist?.call(copy)).catchError((_) {}));
    }
    return code;
  }

  /// Asks the backend again in the background. Never throws, never waits
  /// on a backoff: a refresh inside the failure backoff does nothing, one
  /// with a current code held does nothing unless [force]. Call it when
  /// the Predictions surface opens, when a slip opens and after the policy
  /// changes revision.
  Future<void> refresh({bool force = false}) async {
    await hydrate();
    _dropStaleHeld();
    if (_code != null && !force) return;
    final failedAt = _failedAt;
    if (!force &&
        failedAt != null &&
        _clock().difference(failedAt) < failureBackoff) {
      return;
    }
    await (_inFlight ??= _fetch(revision(), session())
        .whenComplete(() => _inFlight = null));
  }

  /// The code for a read that may wait a little (fee terms, Ledger
  /// orders). Never throws. A code held for this run, or a device copy
  /// issued under the policy revision the app holds now, answers at once
  /// (the device copy also starts a background refresh). A copy from an
  /// older revision waits for the backend, bounded by [timeouts], and is
  /// signed with when the backend does not answer. Order signing itself
  /// never waits: it reads [cachedCode].
  Future<ResolvedBuilderCode> resolve() async {
    await hydrate();
    _dropStaleHeld();
    final fromPolicy = _fromPolicy();
    if (fromPolicy != null) {
      return ResolvedBuilderCode(fromPolicy, BuilderCodeSource.policy);
    }
    final held = _code;
    if (held != null) {
      return ResolvedBuilderCode(held, BuilderCodeSource.backend);
    }
    final persisted = _persisted;
    final currentRevision = revision();
    if (persisted != null &&
        (currentRevision == null || persisted.revision == currentRevision)) {
      unawaited(refresh());
      return ResolvedBuilderCode(persisted.code, BuilderCodeSource.persisted);
    }
    final failedAt = _failedAt;
    if (failedAt != null && _clock().difference(failedAt) < failureBackoff) {
      return persisted != null
          ? ResolvedBuilderCode(persisted.code, BuilderCodeSource.persisted)
          : ResolvedBuilderCode.none;
    }
    return _inFlight ??= _fetch(currentRevision, session())
        .whenComplete(() => _inFlight = null);
  }

  void _dropStaleHeld() {
    final currentRevision = revision();
    final currentSession = session();
    if (currentRevision != _codeRevision || currentSession != _codeSession) {
      _code = null;
      _failedAt = null;
      _codeRevision = currentRevision;
      _codeSession = currentSession;
    }
  }

  Future<ResolvedBuilderCode> _fetch(
      int? expectedRevision, String? bearer) async {
    final backend = baseUrl().replaceFirst(RegExp(r'/$'), '');
    if (backend.isEmpty) return ResolvedBuilderCode.none;
    final clock = Stopwatch()..start();
    // Platform and app version, as every call to Kute's backend sends.
    var context = const <String, String>{};
    try {
      context =
          await RuntimeCapabilitiesService.instance.requestContextHeaders();
    } catch (_) {}
    for (final timeout in timeouts) {
      try {
        final response = await client()
            .get(Uri.parse('$backend/api/v1/pm/builder-code'), headers: {
          ...context,
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
        final copy = PersistedBuilderCode(parsed, _revisionOf(response.body));
        if (_persisted?.code != copy.code ||
            _persisted?.revision != copy.revision) {
          _persisted = copy;
          try {
            await _persist?.call(copy);
          } catch (_) {
            // The in-memory copy still serves this run.
          }
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
    final persisted = _persisted;
    return persisted != null
        ? ResolvedBuilderCode(persisted.code, BuilderCodeSource.persisted)
        : ResolvedBuilderCode.none;
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
