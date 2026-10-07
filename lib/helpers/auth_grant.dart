// lib/helpers/auth_grant.dart
//
// Step-up v2 core (Wallet Hardening Phase 1b, spec section 4.1).
//
// A step-up prompt produces an [AuthGrant] bound to exactly what the
// user reviewed, expressed as a [SensitiveIntent]. Executors re-derive
// the intent they are about to submit and pass it to
// [AuthGrants.check] (laddered retries) or [AuthGrants.consume] (the
// final submit). Any drift outside the D-12 rules throws
// [ReauthRequired]; a stale grant throws [GrantExpired]; a reused
// single-use grant throws [GrantConsumed].
//
// Pure Dart, no Flutter or plugin imports: the prompt policy lives in
// `require_fresh_auth.dart` and the in-memory lifetimes in
// `auth_grant_registry.dart`.
//
// Privacy: the digest and the bound intent are local only. They are
// never tracked or logged, and `toString` is redacted on purpose.

import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Actions that need a fresh step-up (D-9). Session-only housekeeping
/// (cancels, claims, wraps, internal transfers, fixed approvals) is
/// deliberately absent.
enum SensitiveAction {
  seedReveal,
  send,
  sparkRefund,
  moveTransfer,
  venueDeposit,
  venueWithdraw,
  hlOrder,
  pmBet,
  pmSell,
  walletRemove,
  walletSwitch,
  biometricsToggle,
  changePin,
}

/// How a grant was obtained. `name` is the `method` event value.
enum AuthGrantMethod {
  biometric,
  pin,

  /// D-14: counted Kute PIN followed by a successful biometric.
  pinThenBiometric,

  /// D-11 small-action allowance. Still goes through `consume`.
  allowance,

  /// The Polymarket short-round fast-bet window (`FastBetWindow`): a
  /// fresh prompt in the last 10 minutes approved a short-round order.
  /// Still single use and bound to this order's own intent.
  fastWindow,
}

/// Well-known keys for [SensitiveIntent.limits]. Keys not listed here
/// are still bound, and bound exactly (any change re-auths).
abstract final class IntentLimit {
  /// Max slippage in basis points. Actual may be at or under the cap.
  static const maxSlippageBps = 'maxSlippageBps';

  /// Worst acceptable price. Buys may only go lower, sells only
  /// higher (see [side]). Without a known direction it is exact.
  static const limitPrice = 'limitPrice';

  /// Exact.
  static const leverage = 'leverage';

  /// Exact.
  static const reduceOnly = 'reduceOnly';

  /// Exact. Send-max / Move-max mode.
  static const maxMode = 'maxMode';

  /// Exact. orchestra, breez, ... A fallback re-auths.
  static const provider = 'provider';

  /// Exact. For Orchestra-funded moves this is the route version
  /// (owner decision, Phase 5). See [SensitiveIntent.orchestraFunded].
  static const route = 'route';

  /// Minimum receive in base units. Actual may be at or above.
  static const minReceive = 'minReceive';

  /// Maximum fee in base units. Actual may be at or under.
  static const maxFee = 'maxFee';

  /// Exact canonical list (builder placement binds the leg list).
  static const legs = 'legs';

  /// Exact. buy|sell|long|short. Also sets the [limitPrice] direction.
  static const side = 'side';

  /// Exact. Order kind, for example `spot` for a Hyperliquid spot order
  /// (the D-11 allowance scope reads it).
  static const orderKind = 'orderKind';
}

/// Field classes reported by [ReauthRequired] and used as the
/// `field_class` event value (`name`).
enum DriftField {
  action,
  wallet,
  venue,
  account,
  destination,
  asset,
  amount,
  provider,
  route,
  leverage,
  maxMode,
  slippage,
  price,
  fee,
  minReceive,
  side,
  legs,
  other,
}

/// What the user is asked to approve. Build it from the same snapshot
/// the confirmation UI shows, after routes, quotes and provider deposit
/// addresses exist (spec 4.1, confirm_send).
class SensitiveIntent {
  SensitiveIntent({
    required this.action,
    required this.walletId,
    required this.venue,
    this.account,
    this.destination,
    required this.asset,
    required this.amountMax,
    Map<String, Object?> limits = const {},
    this.ttl = AuthGrants.defaultTtl,
  }) : limits = Map.unmodifiable(limits);

  /// Orchestra-funded move (owner decision, Phase 5): the grant binds
  /// the FINAL recipient plus the route version, never the per-quote
  /// deposit address. The Phase 2 quote gate validates the deposit
  /// address separately, so a requote to a new deposit address does
  /// not re-prompt, while a different recipient or route version does.
  factory SensitiveIntent.orchestraFunded({
    required SensitiveAction action,
    required String walletId,
    String? account,
    required String finalRecipient,
    required String routeVersion,
    required String asset,
    required BigInt amountMax,
    Map<String, Object?> limits = const {},
    Duration ttl = AuthGrants.defaultTtl,
  }) {
    return SensitiveIntent(
      action: action,
      walletId: walletId,
      venue: 'orchestra',
      account: account,
      destination: finalRecipient,
      asset: asset,
      amountMax: amountMax,
      limits: {
        ...limits,
        IntentLimit.provider: 'orchestra',
        IntentLimit.route: routeVersion,
      },
      ttl: ttl,
    );
  }

  final SensitiveAction action;
  final String walletId;

  /// spark|bitcoin|lightning|hyperliquid|polymarket|orchestra|local
  final String venue;

  /// HL address, PM safe.
  final String? account;

  /// Address, invoice hash, market/token id, vault address, provider
  /// deposit address (never the Orchestra per-quote deposit address).
  final String? destination;

  /// BTC, USDC, PUSD, coin, pool.
  final String asset;

  /// Base units. The actual amount may only be at or under this.
  final BigInt amountMax;

  /// See [IntentLimit].
  final Map<String, Object?> limits;

  /// Grant lifetime from issue. Not part of the digest.
  final Duration ttl;

  SensitiveIntent copyWith({
    String? destination,
    String? account,
    String? asset,
    BigInt? amountMax,
    Map<String, Object?>? limits,
    Duration? ttl,
  }) {
    return SensitiveIntent(
      action: action,
      walletId: walletId,
      venue: venue,
      account: account ?? this.account,
      destination: destination ?? this.destination,
      asset: asset ?? this.asset,
      amountMax: amountMax ?? this.amountMax,
      limits: limits ?? this.limits,
      ttl: ttl ?? this.ttl,
    );
  }

  /// SHA-256 hex of [canonicalJson]. Local only.
  String get digest => AuthGrants.digestOf(this);

  /// Canonical JSON: sorted keys, BigInt as decimal string, lowercase
  /// hex. Local only.
  String get canonicalJson => AuthGrants.canonicalJsonOf(this);

  @override
  String toString() => 'SensitiveIntent(${action.name}, <redacted>)';
}

/// A fresh step-up approval bound to one [SensitiveIntent].
class AuthGrant {
  AuthGrant._({
    required this.digest,
    required this.action,
    required this.walletId,
    required this.method,
    required this.issuedAt,
    required this.expiresAt,
    required this.singleUse,
    required SensitiveIntent bound,
  }) : _bound = bound;

  final String digest;
  final SensitiveAction action;
  final String walletId;
  final AuthGrantMethod method;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// False only for screen-scoped seed reveal grants, which are revoked
  /// when the screen is disposed instead of consumed.
  final bool singleUse;

  final SensitiveIntent _bound;
  bool _consumed = false;
  bool _revoked = false;

  bool get consumed => _consumed;
  bool get revoked => _revoked;

  /// Venue of the bound intent (for `pending_intent_expired{venue}`).
  String get venue => _bound.venue;

  /// Normalized, immutable copy of what was approved. Local only.
  SensitiveIntent get boundIntent => _bound;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Invalidates the grant; later checks throw [GrantRevoked].
  void revoke() => _revoked = true;

  @override
  String toString() =>
      'AuthGrant(${action.name}, ${method.name}, consumed: $_consumed, '
      'revoked: $_revoked)';
}

/// Base class for grant failures.
sealed class AuthGrantException implements Exception {
  const AuthGrantException();
}

/// The intent drifted outside the D-12 rules. UI shows C8 and
/// "Review again"; emit `step_up_reauth_required{action_type,
/// field_class}` with [primaryFieldClass].
class ReauthRequired extends AuthGrantException {
  ReauthRequired(Set<DriftField> fieldClasses)
      : fieldClasses = UnmodifiableSetView(
            SplayTreeSet<DriftField>((a, b) => a.index.compareTo(b.index))
              ..addAll(fieldClasses));

  /// Every changed field class, in [DriftField] order.
  final Set<DriftField> fieldClasses;

  DriftField get primaryFieldClass => fieldClasses.first;

  @override
  String toString() =>
      'ReauthRequired(${fieldClasses.map((f) => f.name).join(',')})';
}

class GrantExpired extends AuthGrantException {
  const GrantExpired();
  @override
  String toString() => 'GrantExpired';
}

/// Revoked explicitly (screen disposed, registry cleared). Treated as
/// expired by callers that only catch [GrantExpired].
class GrantRevoked extends GrantExpired {
  const GrantRevoked();
  @override
  String toString() => 'GrantRevoked';
}

class GrantConsumed extends AuthGrantException {
  const GrantConsumed();
  @override
  String toString() => 'GrantConsumed';
}

/// Grant issue, check and consume. Stateless apart from the test clock.
abstract final class AuthGrants {
  static const Duration defaultTtl = Duration(seconds: 60);
  static const Duration autofireTtl = Duration(minutes: 30);

  /// Far-future expiry for screen-scoped grants (revoked on dispose).
  static const Duration screenScopedTtl = Duration(days: 1);

  static const String _digestDomain = 'kute.sensitive_intent.v1';

  /// Replaceable clock for tests.
  static DateTime Function() clock = DateTime.now;

  /// Issues a grant for [intent]. [singleUse] false is reserved for
  /// screen-scoped seed reveal grants.
  static AuthGrant issue(
    SensitiveIntent intent, {
    required AuthGrantMethod method,
    bool singleUse = true,
    DateTime? now,
  }) {
    if (intent.amountMax.isNegative) {
      throw ArgumentError.value(intent.amountMax, 'amountMax', 'negative');
    }
    if (intent.walletId.isEmpty) {
      throw ArgumentError.value(intent.walletId, 'walletId', 'empty');
    }
    if (intent.ttl <= Duration.zero) {
      throw ArgumentError.value(intent.ttl, 'ttl', 'not positive');
    }
    if (!singleUse && intent.action != SensitiveAction.seedReveal) {
      throw ArgumentError('Only seed reveal grants may be reusable');
    }
    final issuedAt = now ?? clock();
    final bound = _normalizedIntent(intent);
    return AuthGrant._(
      digest: digestOf(bound),
      action: intent.action,
      walletId: intent.walletId,
      method: method,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(intent.ttl),
      singleUse: singleUse,
      bound: bound,
    );
  }

  /// Validates [grant] against the [actual] intent without using it.
  /// For retries inside one executor call.
  static void check(AuthGrant grant, SensitiveIntent actual,
      {DateTime? now}) {
    if (grant._consumed) throw const GrantConsumed();
    if (grant._revoked) throw const GrantRevoked();
    if (grant.isExpiredAt(now ?? clock())) throw const GrantExpired();
    final drift = driftBetween(grant._bound, actual);
    if (drift.isNotEmpty) throw ReauthRequired(drift);
  }

  /// [check], then marks a single-use grant consumed. For the final
  /// submit. A failed check leaves the grant unconsumed.
  static void consume(AuthGrant grant, SensitiveIntent actual,
      {DateTime? now}) {
    check(grant, actual, now: now);
    if (grant.singleUse) grant._consumed = true;
  }

  // ── Digest ─────────────────────────────────────────────────────────

  static String digestOf(SensitiveIntent intent) =>
      sha256.convert(utf8.encode(canonicalJsonOf(intent))).toString();

  static String canonicalJsonOf(SensitiveIntent intent) =>
      jsonEncode(_jsonable(_intentTree(intent)));

  static Map<String, Object?> _intentTree(SensitiveIntent i) {
    return _canonical(<String, Object?>{
      'v': _digestDomain,
      'action': i.action.name,
      'walletId': i.walletId,
      'venue': i.venue,
      'account': i.account,
      'destination': i.destination,
      'asset': i.asset,
      'amountMax': i.amountMax,
      'limits': i.limits,
    }) as Map<String, Object?>;
  }

  /// Recursively sorts map keys, lowercases 0x hex strings, turns enums
  /// into names and ints into BigInt. Rejects unsupported values.
  static Object? _canonical(Object? v) {
    if (v == null || v is bool) return v;
    if (v is String) return _hex.hasMatch(v) ? v.toLowerCase() : v;
    if (v is BigInt) return v;
    if (v is int) return BigInt.from(v);
    if (v is double) {
      if (!v.isFinite) throw ArgumentError.value(v, 'limits', 'not finite');
      if (v == v.truncateToDouble() && v.abs() < 9007199254740992) {
        return BigInt.from(v);
      }
      return v;
    }
    if (v is Enum) return v.name;
    if (v is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      v.forEach((k, val) {
        if (k is! String) {
          throw ArgumentError.value(k, 'limits', 'map keys must be strings');
        }
        sorted[k] = _canonical(val);
      });
      return Map<String, Object?>.unmodifiable(sorted);
    }
    if (v is Iterable) {
      return List<Object?>.unmodifiable(v.map(_canonical));
    }
    throw ArgumentError.value(v, 'limits', 'unsupported ${v.runtimeType}');
  }

  static Object? _jsonable(Object? v) {
    if (v is BigInt) return v.toString();
    if (v is Map) return v.map((k, val) => MapEntry(k, _jsonable(val)));
    if (v is List) return v.map(_jsonable).toList();
    return v;
  }

  static final RegExp _hex = RegExp(r'^0[xX][0-9a-fA-F]+$');

  static SensitiveIntent _normalizedIntent(SensitiveIntent i) {
    final tree = _intentTree(i);
    return SensitiveIntent(
      action: i.action,
      walletId: i.walletId,
      venue: tree['venue'] as String,
      account: tree['account'] as String?,
      destination: tree['destination'] as String?,
      asset: tree['asset'] as String,
      amountMax: i.amountMax,
      limits: tree['limits'] as Map<String, Object?>,
      ttl: i.ttl,
    );
  }

  // ── Drift (D-12) ───────────────────────────────────────────────────

  /// Field classes that changed from [approved] to [actual] in a way
  /// D-12 does not allow. Empty means the grant still covers [actual].
  static Set<DriftField> driftBetween(
      SensitiveIntent approved, SensitiveIntent actual) {
    final a = _intentTree(approved);
    final b = _intentTree(actual);
    final out = <DriftField>{};

    if (a['action'] != b['action']) out.add(DriftField.action);
    if (a['walletId'] != b['walletId']) out.add(DriftField.wallet);
    if (a['venue'] != b['venue']) out.add(DriftField.venue);
    if (a['account'] != b['account']) out.add(DriftField.account);
    if (a['destination'] != b['destination']) out.add(DriftField.destination);
    if (a['asset'] != b['asset']) out.add(DriftField.asset);

    final amountA = a['amountMax'] as BigInt;
    final amountB = b['amountMax'] as BigInt;
    if (amountB.isNegative || amountB > amountA) out.add(DriftField.amount);

    final la = a['limits'] as Map<String, Object?>;
    final lb = b['limits'] as Map<String, Object?>;
    final direction = _priceDirection(approved.action, la[IntentLimit.side]);
    for (final key in {...la.keys, ...lb.keys}) {
      final va = la[key];
      final vb = lb[key];
      final field = _fieldFor(key);
      final ok = switch (key) {
        IntentLimit.maxSlippageBps => _atMost(vb, va),
        IntentLimit.maxFee => _atMost(vb, va),
        IntentLimit.minReceive => _atMost(va, vb),
        IntentLimit.limitPrice => switch (direction) {
            _Direction.buy => _atMost(vb, va),
            _Direction.sell => _atMost(va, vb),
            _Direction.unknown => _sameValue(va, vb),
          },
        _ => _sameValue(va, vb),
      };
      if (!ok) out.add(field);
    }
    return out;
  }

  static DriftField _fieldFor(String key) => switch (key) {
        IntentLimit.maxSlippageBps => DriftField.slippage,
        IntentLimit.limitPrice => DriftField.price,
        IntentLimit.leverage => DriftField.leverage,
        IntentLimit.maxMode => DriftField.maxMode,
        IntentLimit.provider => DriftField.provider,
        IntentLimit.route => DriftField.route,
        IntentLimit.minReceive => DriftField.minReceive,
        IntentLimit.maxFee => DriftField.fee,
        IntentLimit.legs => DriftField.legs,
        IntentLimit.side => DriftField.side,
        _ => DriftField.other,
      };

  static _Direction _priceDirection(SensitiveAction action, Object? side) {
    final s = side is String ? side.toLowerCase() : null;
    if (s == 'buy' || s == 'long') return _Direction.buy;
    if (s == 'sell' || s == 'short') return _Direction.sell;
    if (action == SensitiveAction.pmBet) return _Direction.buy;
    if (action == SensitiveAction.pmSell) return _Direction.sell;
    return _Direction.unknown;
  }

  static bool _sameValue(Object? a, Object? b) =>
      jsonEncode(_jsonable(a)) == jsonEncode(_jsonable(b));

  /// True when [lower] <= [upper]. A missing or non-numeric side on
  /// either end is a change (an unbounded value was never reviewed).
  static bool _atMost(Object? lower, Object? upper) {
    final l = _Dec.tryParse(lower);
    final u = _Dec.tryParse(upper);
    if (l == null || u == null) return lower == null && upper == null;
    return l.compareTo(u) <= 0;
  }
}

enum _Direction { buy, sell, unknown }

/// Exact decimal: value = mantissa * 10^-scale.
class _Dec implements Comparable<_Dec> {
  const _Dec(this.mantissa, this.scale);
  final BigInt mantissa;
  final int scale;

  static final RegExp _num = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

  static _Dec? tryParse(Object? v) {
    if (v is BigInt) return _Dec(v, 0);
    if (v is int) return _Dec(BigInt.from(v), 0);
    if (v is double) {
      if (!v.isFinite) return null;
      return tryParse(v.toString());
    }
    if (v is! String) return null;
    final m = _num.firstMatch(v.trim());
    if (m == null) return null;
    final intPart = m.group(2) ?? '';
    final frac = m.group(3) ?? '';
    if (intPart.isEmpty && frac.isEmpty) return null;
    final exp = int.tryParse(m.group(4) ?? '0');
    if (exp == null || exp.abs() > 1000) return null;
    var mantissa = BigInt.parse('${intPart.isEmpty ? '0' : intPart}$frac');
    if (m.group(1) == '-') mantissa = -mantissa;
    var scale = frac.length - exp;
    if (scale < 0) {
      mantissa *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    return _Dec(mantissa, scale);
  }

  @override
  int compareTo(_Dec other) {
    final s = scale > other.scale ? scale : other.scale;
    final a = mantissa * BigInt.from(10).pow(s - scale);
    final b = other.mantissa * BigInt.from(10).pow(s - other.scale);
    return a.compareTo(b);
  }
}

/// Minimal stand-in for the Phase 1a session state (`isSessionUnlocked`).
/// Wire the 1a session provider to this once 1a lands.
abstract interface class StepUpSessionState {
  bool get isSessionUnlocked;
}
