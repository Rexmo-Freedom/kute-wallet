// lib/services/branta/branta_payee_service.dart
//
// WHO AM I PAYING? (founder, 12 November 2026: "on the send side when you
// have the address: get the logo of the thing we are sending to, on the
// confirmation screen; show it on the cards with the name of the vendor;
// make it work with USDC and such ones that are available").
//
// Branta (https://branta.pro, the `branta` package, MIT) is a registry
// merchants and payment processors publish their payment codes to. A
// wallet hands it what the person scanned or pasted and gets back the
// payee's name and logo when the code is registered, or a flag when the
// address in it was swapped.
//
// PRIVACY. Branta never sees the address:
//
//   * a `bitcoin:` code or a stablecoin chain code (`pol:`, `eth:`,
//     `bsc:`, `tron:`, `sol:`) from a Branta merchant carries
//     `branta_id` (the address already encrypted with `branta_secret`) and
//     `branta_secret`; the lookup sends the id alone, the secret never
//     leaves the phone, and the answer is decrypted here;
//   * a Lightning invoice is looked up by itself encrypted with a key
//     derived from itself, so Branta can only match it if the payee
//     already registered that very invoice;
//   * a bare address (no Branta params) is never sent at all: the package
//     answers `unknown` without a request.
//
// Branta still sees that this phone looked a code up (IP and time). So a
// lookup only runs for a recipient the person entered (the recipient card
// or the Review on screen), never for contacts or history, and only when
// the input carries something Branta can verify ([brantaCanVerify]).
//
// WHAT IT COVERS (what Branta supports, mapped to what Kute pays):
//
//   * Bitcoin on-chain: a `bitcoin:` code with `branta_id`/`branta_secret`;
//   * Lightning: a BOLT11 invoice (also from a unified `bitcoin:` code);
//   * stablecoins (branta 4.3.0, founder 13 November 2026: "it accepts
//     other stables"), each a chain code with the Branta params, the
//     scheme naming the network and Branta's answer the token:
//       - USDC and USDT on Polygon (`pol:`),
//       - USDC and USDT on Ethereum (`eth:`),
//       - USDC and USDT on BNB Smart Chain (`bsc:`),
//       - USDT on Tron (`tron:`),
//       - USDC and USDT on Solana (`sol:`).
//
// Branta also has USDT on TON (`ton:`), but Kute never pays TON (it is
// not a sendable chain), so it has no rail here. Nothing else is in
// Branta (no USDC on Base or Arbitrum, no USDC on Tron, no Spark or
// Lightning addresses): those never show a badge.
//
// A NAME ONLY FOR WHAT IS PAID. A payee is shown only when Branta bound
// the very address Send pays, on the rail it pays ([BrantaRail]): a
// Polygon USDC code paid as USDC on Base, or a code whose address was
// edited, shows nothing. A swapped address (`tampered`) is the one
// warning ([BrantaPayeeStatus.tampered]).
//
// NEVER IN THE WAY. Every lookup is capped at [kBrantaLookupTimeout] and
// never blocks the send; an answer is kept in memory for the session
// (a failed one for a minute, so nothing retries in a loop); the same
// lookup in flight is shared. Errors, timeouts and Branta being down all
// read as "no badge". Lookups are never persisted and nothing goes to
// analytics but a yes/no (`verified_payee`). A send the person confirms
// with a verified payee on screen keeps that payee's name and logo with
// the payment (branta_payee_records.dart), so the activity lists show it
// without asking Branta again.

import 'dart:async';

import 'package:branta/branta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The longest a lookup may take before Send carries on without it.
const Duration kBrantaLookupTimeout = Duration(seconds: 2);

/// How Send pays the destination: the one rail a Branta answer must name
/// for the payee to show.
enum BrantaRail {
  bitcoinOnchain(DestinationType.bitcoinAddress),
  lightning(DestinationType.bolt11),
  usdcPolygon(DestinationType.usdcPolygon),
  usdtPolygon(DestinationType.usdtPolygon),
  usdcEthereum(DestinationType.usdcEthereum),
  usdtEthereum(DestinationType.usdtEthereum),
  usdcBsc(DestinationType.usdcBsc),
  usdtBsc(DestinationType.usdtBsc),
  usdtTron(DestinationType.usdtTron),
  usdcSolana(DestinationType.usdcSolana),
  usdtSolana(DestinationType.usdtSolana);

  const BrantaRail(this.type);

  /// Branta's own name for the rail.
  final DestinationType type;
}

/// The rail of a send of [assetCode] on [chain] (an Orchestra slug or a
/// network name), or null when Branta has nothing for it. Only the
/// exact tokens Branta names count: USDC.e (bridged), USDT0 and the like
/// are different tokens and get none.
BrantaRail? brantaRailFor({required String assetCode, required String chain}) {
  final asset = assetCode.trim().toUpperCase();
  final network = chain.trim().toLowerCase();
  final (usdc, usdt) = switch (network) {
    'polygon' || 'matic' || 'pol' => (
        BrantaRail.usdcPolygon,
        BrantaRail.usdtPolygon
      ),
    'ethereum' || 'eth' => (BrantaRail.usdcEthereum, BrantaRail.usdtEthereum),
    'bsc' || 'bnb' => (BrantaRail.usdcBsc, BrantaRail.usdtBsc),
    // Branta has no USDC on Tron.
    'tron' || 'trx' => (null, BrantaRail.usdtTron),
    'solana' || 'sol' => (BrantaRail.usdcSolana, BrantaRail.usdtSolana),
    _ => (null, null),
  };
  if (asset == 'USDC') return usdc;
  if (asset == 'USDT') return usdt;
  if (asset == 'BTC' && network == 'bitcoin') return BrantaRail.bitcoinOnchain;
  if (asset == 'BTC' && network == 'lightning') return BrantaRail.lightning;
  return null;
}

/// The URI schemes Branta's stablecoin codes use (one per network; the
/// token is in Branta's answer, never in the scheme). `ton:` is among
/// them though Kute pays no TON, so such a code still reduces to its
/// address like the others.
const Set<String> kBrantaChainSchemes = {
  'pol',
  'eth',
  'bsc',
  'tron',
  'ton',
  'sol'
};

/// The rail a bitcoin destination is paid on by its shape: a BOLT11
/// invoice on Lightning, a bitcoin address (or `bitcoin:` code) on chain;
/// null for anything else (Lightning and Spark addresses, LNURL, 0x …).
BrantaRail? brantaRailForBitcoin(String destination) {
  var d = destination.trim().toLowerCase();
  if (d.startsWith('lightning:')) d = d.substring('lightning:'.length);
  if (_isBolt11(d)) return BrantaRail.lightning;
  if (d.startsWith('bitcoin:')) return BrantaRail.bitcoinOnchain;
  if (RegExp(r'^(bc1|tb1|bcrt1)[a-z0-9]{8,}$').hasMatch(d) ||
      RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$')
          .hasMatch(destination.trim())) {
    return BrantaRail.bitcoinOnchain;
  }
  return null;
}

bool _isBolt11(String lower) =>
    lower.startsWith('lnbc') || lower.startsWith('lntb');

/// Whether [input] carries anything Branta can verify: a code with
/// `branta_id` and `branta_secret`, or a BOLT11 invoice. Anything else
/// would only ever be `unknown`, so it is never looked up.
bool brantaCanVerify(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return false;
  if (s.contains('branta_id=') && s.contains('branta_secret=')) return true;
  if (s.startsWith('lightning:')) s = s.substring('lightning:'.length);
  return _isBolt11(s);
}

/// What Branta said about a destination, when it said something worth
/// showing.
enum BrantaPayeeStatus {
  /// Registered, and bound to the very address Send pays.
  verified,

  /// The address in the code was swapped: Branta's one warning.
  tampered,
}

/// A payee Branta vouches for ([status] verified: [name] and maybe a
/// [logoUrl]), or its warning ([status] tampered: no name).
@immutable
class BrantaPayee {
  const BrantaPayee.verified({required String this.name, this.logoUrl})
      : status = BrantaPayeeStatus.verified;

  const BrantaPayee.tampered()
      : status = BrantaPayeeStatus.tampered,
        name = null,
        logoUrl = null;

  final BrantaPayeeStatus status;

  /// The payee's name ("Bitfinex", "Strike"); null when [tampered].
  final String? name;

  /// The payee's logo, always on Branta's own host (the package refuses
  /// any other), https only; null when there is none.
  final String? logoUrl;

  bool get verified => status == BrantaPayeeStatus.verified;
  bool get tampered => status == BrantaPayeeStatus.tampered;

  @override
  bool operator ==(Object other) =>
      other is BrantaPayee &&
      other.status == status &&
      other.name == name &&
      other.logoUrl == logoUrl;

  @override
  int get hashCode => Object.hash(status, name, logoUrl);

  @override
  String toString() => 'BrantaPayee(${status.name}, $name)';
}

/// The lookup itself: the package's `verify` in production, a fake in
/// tests.
typedef BrantaVerifier = Future<VerifyResult> Function(String input);

/// Looks payees up (see the file header). One per app ([shared]).
class BrantaPayeeService {
  BrantaPayeeService({
    BrantaVerifier? verifier,
    this.timeout = kBrantaLookupTimeout,
    this.failureTtl = const Duration(minutes: 1),
    this.maxEntries = 64,
    DateTime Function()? now,
  })  : _verifier = verifier,
        _now = now ?? DateTime.now;

  /// The app's service. Tests swap it (test/flutter_test_config.dart keeps
  /// every widget test offline).
  static BrantaPayeeService shared = BrantaPayeeService();

  final BrantaVerifier? _verifier;
  final Duration timeout;

  /// How long a failed lookup (timeout, error, Branta unreachable) is
  /// remembered before it may be tried again.
  final Duration failureTtl;

  /// The most answers (and remembered inputs) kept in memory.
  final int maxEntries;
  final DateTime Function() _now;

  BrantaService? _sdk;

  final Map<String, ({BrantaPayee? payee, DateTime? until})> _cache = {};
  final Map<String, Future<BrantaPayee?>> _inFlight = {};

  /// What the person scanned or pasted, by the bare destination Send kept
  /// of it (lower case): Send strips a `bitcoin:` or chain code (`pol:`,
  /// `eth:` …) down to its address, and the Branta params go with it.
  final Map<String, String> _inputs = {};

  /// Production uses Branta's production registry; `BRANTA_STAGING=true`
  /// in .env points a test build at staging (its sample codes).
  static BrantaEnvironment get environment {
    try {
      return (dotenv.env['BRANTA_STAGING'] ?? '').trim() == 'true'
          ? BrantaEnvironment.staging
          : BrantaEnvironment.production;
    } catch (_) {
      return BrantaEnvironment.production;
    }
  }

  Future<VerifyResult> _verify(String input) {
    final fake = _verifier;
    if (fake != null) return fake(input);
    return (_sdk ??= BrantaService(environment: environment)).verify(input);
  }

  /// Remember [raw], as the person scanned or pasted it, for the bare
  /// destinations Send will keep of it. Only a code Branta can verify by
  /// its params is kept (a bare invoice is looked up as itself); nothing
  /// is persisted.
  void noteInput(String raw) {
    final input = raw.trim();
    if (input.isEmpty || !input.toLowerCase().contains('branta_id=')) return;
    for (final key in _bareDestinationsOf(input)) {
      _inputs.remove(key);
      _inputs[key] = input;
    }
    while (_inputs.length > maxEntries) {
      _inputs.remove(_inputs.keys.first);
    }
  }

  /// What to look [destination] up by: the code it was noted from
  /// ([noteInput]), else itself.
  String inputFor(String destination) =>
      _inputs[destination.trim().toLowerCase()] ?? destination.trim();

  /// The answer already in memory for [destination] on [rail], without a
  /// lookup (analytics reads this: it never starts one).
  BrantaPayee? cached(String destination, BrantaRail rail) {
    final input = inputFor(destination);
    final key = '${rail.name}|${_bareDestination(destination)}|$input';
    final hit = _cache[key];
    if (hit == null) return null;
    final until = hit.until;
    if (until != null && !_now().isBefore(until)) return null;
    return hit.payee;
  }

  /// The payee Branta names for [destination] paid on [rail], its warning,
  /// or null (nothing to show). Never throws; never takes longer than
  /// [timeout].
  Future<BrantaPayee?> lookup(String destination, BrantaRail rail) {
    final input = inputFor(destination);
    if (!brantaCanVerify(input)) return Future.value(null);
    final payTo = _bareDestination(destination);
    if (payTo.isEmpty) return Future.value(null);
    final key = '${rail.name}|$payTo|$input';
    final cached = _cache[key];
    if (cached != null) {
      final until = cached.until;
      if (until == null || _now().isBefore(until)) {
        return Future.value(cached.payee);
      }
      _cache.remove(key);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _run(input, payTo, rail).then((r) {
      _remember(key, r.payee, failed: r.failed);
      return r.payee;
    }).whenComplete(() {
      // A block, not an arrow: remove() hands back this very future, and
      // whenComplete would wait on it (itself) for ever.
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<({BrantaPayee? payee, bool failed})> _run(
      String input, String payTo, BrantaRail rail) async {
    try {
      final result = await _verify(input).timeout(timeout);
      return switch (result.status) {
        VerifyStatus.match => (
            payee: payeeFromMatch(result, payTo: payTo, rail: rail),
            failed: false
          ),
        VerifyStatus.tampered => (
            payee: const BrantaPayee.tampered(),
            failed: false
          ),
        VerifyStatus.unknown => (payee: null, failed: false),
        VerifyStatus.incomplete => (payee: null, failed: true),
      };
    } catch (_) {
      // A timeout, no network, a logo on a foreign host (the package
      // refuses it): no badge.
      return (payee: null, failed: true);
    }
  }

  void _remember(String key, BrantaPayee? payee, {required bool failed}) {
    _cache.remove(key);
    _cache[key] = (payee: payee, until: failed ? _now().add(failureTtl) : null);
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Forget every answer and noted input (a wallet wipe; tests).
  void clear() {
    _cache.clear();
    _inFlight.clear();
    _inputs.clear();
  }

  @visibleForTesting
  int get debugCacheSize => _cache.length;
}

/// The payee a `match` names for [payTo] on [rail]: the payment that bound
/// that very address on that rail, by its name and logo. Null when the
/// match bound something else (another address, another rail) or names
/// nobody.
@visibleForTesting
BrantaPayee? payeeFromMatch(VerifyResult result,
    {required String payTo, required BrantaRail rail}) {
  bool same(Destination d) =>
      d.type == rail.type && _sameDestination(d.value, payTo, rail);
  if (!result.matchedDestinations.any(same)) return null;
  final payment = result.payments
          .where((p) => p.destinations.any((d) => !d.isEncrypted && same(d)))
          .firstOrNull ??
      result.payments.firstOrNull;
  final name = payment?.platform?.trim() ?? '';
  if (payment == null || name.isEmpty) return null;
  return BrantaPayee.verified(
    name: name,
    logoUrl: _httpsOrNull(payment.platformLogoUrl) ??
        _httpsOrNull(payment.platformLogoLightUrl),
  );
}

String? _httpsOrNull(String? url) {
  final u = url?.trim() ?? '';
  final uri = Uri.tryParse(u);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return u;
}

/// Addresses and invoices compare without case (bech32, BOLT11 and EVM
/// checksums are all case-insensitive); base58 compares exactly, and the
/// Tron and Solana rails are base58 only (a Solana address may well start
/// with "ln" or "bc1").
bool _sameDestination(String a, String b, BrantaRail rail) {
  final x = a.trim();
  final y = b.trim();
  if (rail == BrantaRail.usdtTron ||
      rail == BrantaRail.usdcSolana ||
      rail == BrantaRail.usdtSolana) {
    return x == y;
  }
  final lower = x.toLowerCase();
  final caseless = lower.startsWith('bc1') ||
      lower.startsWith('tb1') ||
      lower.startsWith('bcrt1') ||
      lower.startsWith('ln') ||
      lower.startsWith('0x');
  return caseless ? lower == y.toLowerCase() : x == y;
}

/// [destination] as Send pays it: a `bitcoin:`, `lightning:` or Branta
/// chain code ([kBrantaChainSchemes]) reduced to its address or invoice.
String _bareDestination(String destination) {
  var d = destination.trim();
  final colon = d.indexOf(':');
  if (colon > 0) {
    final scheme = d.substring(0, colon).toLowerCase();
    if (scheme == 'bitcoin' ||
        scheme == 'lightning' ||
        kBrantaChainSchemes.contains(scheme)) {
      d = d.substring(colon + 1);
      final q = d.indexOf('?');
      if (q != -1) d = d.substring(0, q);
    }
  }
  return d.trim();
}

/// Every bare destination Send may keep of [input]: the code's address
/// and, for a unified `bitcoin:` code, its `lightning=` invoice. Lower
/// case.
List<String> _bareDestinationsOf(String input) {
  final out = <String>[];
  final bare = _bareDestination(input);
  if (bare.isNotEmpty) out.add(bare.toLowerCase());
  final q = input.indexOf('?');
  if (q != -1) {
    for (final part in input.substring(q + 1).split('&')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      if (part.substring(0, eq).toLowerCase() != 'lightning') continue;
      try {
        final v = Uri.decodeComponent(part.substring(eq + 1)).trim();
        if (v.isNotEmpty) out.add(v.toLowerCase());
      } catch (_) {}
    }
  }
  return out;
}

/// Remember what the person scanned or pasted (see
/// [BrantaPayeeService.noteInput]). Every Send entry point calls it.
void brantaNoteInput(String raw) => BrantaPayeeService.shared.noteInput(raw);

/// Whether Branta verified the payee of [destination] on [rail], from
/// what is already in memory: the analytics `verified_payee` yes/no (never
/// the payee, never the address; never a lookup of its own).
bool brantaVerifiedPayee(String destination, BrantaRail? rail) =>
    brantaVerifiedPayeeShown(destination, rail) != null;

/// The payee Branta verified for [destination] on [rail], from what is
/// already in memory: the answer Send showed on its recipient card and
/// Review (never a lookup of its own). Null when it was not verified
/// (unknown, tampered, still loading, failed). The send stores it with
/// the payment once the person confirms (branta_payee_records.dart).
BrantaPayee? brantaVerifiedPayeeShown(String destination, BrantaRail? rail) {
  if (rail == null || destination.trim().isEmpty) return null;
  final payee = BrantaPayeeService.shared.cached(destination.trim(), rail);
  return payee != null && payee.verified ? payee : null;
}

/// The app's [BrantaPayeeService].
final brantaPayeeServiceProvider =
    Provider<BrantaPayeeService>((_) => BrantaPayeeService.shared);

/// The payee for one destination on one rail (null: nothing to show,
/// including while it loads).
final brantaPayeeProvider = FutureProvider.autoDispose
    .family<BrantaPayee?, ({String destination, BrantaRail rail})>(
  (ref, q) =>
      ref.watch(brantaPayeeServiceProvider).lookup(q.destination, q.rail),
);
