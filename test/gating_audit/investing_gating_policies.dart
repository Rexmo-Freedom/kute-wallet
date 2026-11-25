// Runtime policies for the gating audit of Investing, Predictions and the
// Portfolio (v2.2): a backend answer that denies chosen capabilities the
// four ways the backend can (a named region block, a platform rule, the
// switch off, coming soon), and the founder's swap cascade, where a
// region block on swaps reaches the venues' deposits and trading,
// receives into Dollars and one-time addresses with `blockedBy` and the
// regions named (test/services/capability_region_block_test.dart). The
// app obeys what it is told; nothing here is a rule of the app's own.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// The regions a region block names, as the backend sends them.
const kAuditRegions = {
  'label': 'the European Union, the UK and Switzerland',
  'groups': ['eu', 'uk', 'ch'],
  'countries': ['DE', 'FR', 'GB', 'CH'],
};

const kAuditRegionTitle =
    'Not available in the European Union, the UK and Switzerland';
const kAuditVpnLine = "If this isn't where you are, check your VPN settings.";

/// The ways the backend denies a capability.
enum AuditDenial {
  /// `country_blocked`, the regions named.
  country,

  /// `platform_not_allowed`.
  platform,

  /// `disabled`: the master switch off.
  masterOff,

  /// `coming_soon`.
  comingSoon,
}

/// Every capability the audited surfaces read; an id a loaded policy does
/// not name reads `unknown_capability`, a denial.
const kAuditCapabilities = [
  'orchestra.swap',
  'orchestra.swap.stablecoins',
  'orchestra.swap.altcoins',
  'crypto.deposit',
  'orchestra.onetime_addresses',
  'hyperliquid.browse',
  'hyperliquid.trade',
  'hyperliquid.stocks',
  'hyperliquid.referrer',
  'hyperliquid.deposit',
  'hyperliquid.withdraw',
  'hyperliquid.close',
  'hyperliquid.cancel',
  'polymarket.browse',
  'polymarket.trade',
  'polymarket.sports',
  'polymarket.politics',
  'polymarket.deposit',
  'polymarket.withdraw',
  'polymarket.close',
  'polymarket.cancel',
  'polymarket.protocol_v2',
  'trading.advanced',
  'ledger.hyperliquid',
  'ledger.polymarket',
];

/// The capabilities the swap master's region block cascades to.
const kAuditSwapCascade = [
  'orchestra.swap.stablecoins',
  'orchestra.swap.altcoins',
  'crypto.deposit',
  'orchestra.onetime_addresses',
  'hyperliquid.trade',
  'hyperliquid.deposit',
  'polymarket.trade',
  'polymarket.deposit',
];

/// The exits: never part of any cascade, always open.
const kAuditExits = [
  'hyperliquid.close',
  'hyperliquid.cancel',
  'hyperliquid.withdraw',
  'polymarket.close',
  'polymarket.cancel',
  'polymarket.withdraw',
];

/// One decision as the backend writes it for [denial].
Map<String, Object?> auditDenial(AuditDenial denial, {String? blockedBy}) =>
    switch (denial) {
      AuditDenial.country => {
          'allowed': false,
          'reason': 'country_blocked',
          'comingSoon': false,
          'regions': kAuditRegions,
          if (blockedBy != null) 'blockedBy': blockedBy,
        },
      AuditDenial.platform => {
          'allowed': false,
          'reason': 'platform_not_allowed',
          'comingSoon': false,
        },
      AuditDenial.masterOff => {
          'allowed': false,
          'reason': 'disabled',
          'comingSoon': false,
        },
      AuditDenial.comingSoon => {
          'allowed': false,
          'reason': 'coming_soon',
          'comingSoon': true,
        },
    };

/// A policy that allows every [kAuditCapabilities] id except those in
/// [denied], answered as given.
RuntimeCapabilitiesService auditPolicy(
        [Map<String, Map<String, Object?>> denied = const {}]) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                for (final id in kAuditCapabilities)
                  id: denied[id] ??
                      {'allowed': true, 'reason': '', 'comingSoon': false},
              },
              'fees': {
                'fiat_deposit': {'mode': 'fixed', 'bps': 100},
                'cross_chain_send': {'mode': 'fixed', 'bps': 50},
                'venue_withdrawal': {'mode': 'fixed', 'bps': 0}
              },
              'ai': {'dailyLimit': 5},
              'investing': {'maxLeverage': null},
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.2.0',
    );

/// [ids] denied the way [denial] says.
RuntimeCapabilitiesService auditDenying(
        Iterable<String> ids, AuditDenial denial) =>
    auditPolicy({for (final id in ids) id: auditDenial(denial)});

/// The founder's swap cascade: `orchestra.swap` blocked for the named
/// regions and [kAuditSwapCascade] inheriting it.
RuntimeCapabilitiesService auditSwapCountryBlock() => auditPolicy({
      'orchestra.swap': auditDenial(AuditDenial.country),
      for (final id in kAuditSwapCascade)
        id: auditDenial(AuditDenial.country, blockedBy: 'orchestra.swap'),
    });
