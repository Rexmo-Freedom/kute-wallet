import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart' show AppLocalizations, appL10n, l10nForLanguage;

enum InvestmentProvider { hyperliquid, polymarket }

enum ProviderAvailabilityStatus { allowed, restricted, unavailable }

class ProviderAvailability {
  const ProviderAvailability(this.provider, this.status);

  final InvestmentProvider provider;
  final ProviderAvailabilityStatus status;

  String get providerName =>
      provider == InvestmentProvider.hyperliquid ? 'Hyperliquid' : 'Polymarket';

  /// The sentence for this answer in the app language. See [messageIn].
  String get message => messageIn(appL10n());

  String messageIn(AppLocalizations l10n) =>
      status == ProviderAvailabilityStatus.restricted
          ? l10n.providerRegionRestricted(providerName)
          : l10n.providerAvailabilityUnknown(providerName);

  void ensureAllowed() {
    if (status == ProviderAvailabilityStatus.restricted) {
      throw ProviderAvailabilityException(this);
    }
  }
}

class ProviderAvailabilityException implements Exception {
  const ProviderAvailabilityException(this.availability);
  final ProviderAvailability availability;

  /// English on purpose: exception text feeds error categories and logs.
  /// Screens show the availability's [ProviderAvailability.messageIn].
  @override
  String toString() => availability.messageIn(l10nForLanguage('en'));
}

/// These requests must originate on the user's device. A backend proxy would
/// check the server's country instead. Results authorize only new exposure;
/// providers still enforce account, terms and transaction-level restrictions.
class InvestmentProviderAvailability {
  InvestmentProviderAvailability({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
    Duration cacheFor = defaultCacheFor,
  })  : _client = client ?? http.Client(),
        _timeout = timeout,
        _cacheFor = cacheFor;

  static final instance = InvestmentProviderAvailability();
  final http.Client _client;
  final Duration _timeout;

  /// A venue's own location answer changes with the network, not by the
  /// second. A definite answer is reused for [_cacheFor]; an unavailable
  /// check is never cached, so the next call asks again. Zero disables it.
  static const defaultCacheFor = Duration(minutes: 5);
  final Duration _cacheFor;
  final Map<InvestmentProvider, (ProviderAvailability, DateTime)> _cache = {};

  ProviderAvailability? _cached(InvestmentProvider provider) {
    if (_cacheFor <= Duration.zero) return null;
    final entry = _cache[provider];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$2) > _cacheFor) return null;
    return entry.$1;
  }

  ProviderAvailability _remember(ProviderAvailability value) {
    if (value.status != ProviderAvailabilityStatus.unavailable) {
      _cache[value.provider] = (value, DateTime.now());
    }
    return value;
  }

  // The official Hyperliquid app uses this address for a disconnected legal
  // check. Country eligibility depends on restrictions, not wallet ownership.
  static const hyperliquidLegalCheckAddress =
      '0x4FaEC93ff98ab58bacb93dDA550bcB8294e590eE';

  Future<ProviderAvailability> hyperliquid() async {
    const provider = InvestmentProvider.hyperliquid;
    // The same five-minute reuse as Polymarket's answer below. Every
    // Investing deposit quote asked this again, in series before the
    // policy fetch and the quote itself.
    final cached = _cached(provider);
    if (cached != null) return cached;
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.hyperliquid.xyz/info'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': 'legalCheck',
              'user': hyperliquidLegalCheckAddress,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return const ProviderAvailability(
            provider, ProviderAvailabilityStatus.unavailable);
      }
      final data = jsonDecode(response.body);
      if (data is! Map ||
          data['acceptedTerms'] is! bool ||
          data['userAllowed'] is! bool) {
        return const ProviderAvailability(
            provider, ProviderAvailabilityStatus.unavailable);
      }
      // Official app ipAllowed mapping: n = unrestricted, a = block actions,
      // o = hide outcomes, u = UK. The latter two do not ban perpetual trading.
      // userAllowed / acceptedTerms are separate account setup checks. Never
      // infer a country ban from them or automatically accept terms.
      return _remember(ProviderAvailability(
          provider,
          switch (data['restrictions']) {
            'n' || 'o' || 'u' => ProviderAvailabilityStatus.allowed,
            'a' => ProviderAvailabilityStatus.restricted,
            _ => ProviderAvailabilityStatus.unavailable,
          }));
    } catch (_) {
      return const ProviderAvailability(
          provider, ProviderAvailabilityStatus.unavailable);
    }
  }

  Future<ProviderAvailability> polymarket() async {
    const provider = InvestmentProvider.polymarket;
    final cached = _cached(provider);
    if (cached != null) return cached;
    try {
      final response = await _client
          .get(Uri.parse('https://polymarket.com/api/geoblock'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['blocked'] is bool) {
          return _remember(ProviderAvailability(
              provider,
              data['blocked'] == true
                  ? ProviderAvailabilityStatus.restricted
                  : ProviderAvailabilityStatus.allowed));
        }
      }
    } catch (_) {
      // An unavailable location check is advisory. Only an explicit provider
      // restriction blocks here; transaction and account checks still apply.
    }
    return const ProviderAvailability(
        provider, ProviderAvailabilityStatus.unavailable);
  }

  Future<void> ensureNewExposure(Iterable<String> capabilities) async {
    final requested = capabilities.toSet();
    if (requested.any(const {
      'hyperliquid.trade',
      'hyperliquid.deposit',
    }.contains)) {
      (await hyperliquid()).ensureAllowed();
    }
    if (requested.any(const {
      'polymarket.trade',
      'polymarket.deposit',
    }.contains)) {
      (await polymarket()).ensureAllowed();
    }
  }
}
