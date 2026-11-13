// Backend runtime policies for the market, slip and share gating audit
// (fw36): the four ways the backend withholds a capability, as the policy
// endpoint answers them. Blocks live only in the backend policy (founder
// decision, 27 October 2026); the app obeys the decision it is sent.
//
//   * [MarketDenial.swapCountryBlock]: `orchestra.swap` refused for named
//     regions and the cascade the backend sends with it (`blockedBy:
//     orchestra.swap` and the same `regions` on every capability that
//     requires it: the Investing and Predictions deposits and trading,
//     crypto deposits, one-time addresses). Exits never follow it;
//   * [MarketDenial.platform]: `platform_not_allowed` on the targets;
//   * [MarketDenial.masterOff]: the operator switch off (`disabled`);
//   * [MarketDenial.comingSoon]: `comingSoon: true` on the targets.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';

final marketGatingEn = lookupAppLocalizations(const Locale('en'));

const kGatingRegions = {
  'label': 'the European Union, the UK and Switzerland',
  'labels': {
    'de': 'der Europäischen Union, im Vereinigten Königreich und der Schweiz',
  },
  'groups': ['eu', 'uk', 'ch'],
  'countries': ['DE', 'FR', 'GB', 'CH'],
};

const kGatingNamedTitle =
    'Not available in the European Union, the UK and Switzerland';
const kGatingVpnSentence =
    "If this isn't where you are, check your VPN settings.";

/// The swap master and what the backend cascades from it.
const kSwapMaster = 'orchestra.swap';
const kSwapCascade = [
  '$kSwapMaster.stablecoins',
  '$kSwapMaster.altcoins',
  'crypto.deposit',
  'orchestra.onetime_addresses',
  'hyperliquid.trade',
  'hyperliquid.deposit',
  'polymarket.trade',
  'polymarket.deposit',
];

/// What a slip or a market page answers to that must stay open whatever
/// blocks new business: cancel, close (sell, claim) and withdraw.
const kVenueExits = [
  'hyperliquid.cancel',
  'hyperliquid.close',
  'hyperliquid.withdraw',
  'polymarket.cancel',
  'polymarket.close',
  'polymarket.withdraw',
];

/// Every id a loaded policy names here (an id it does not name reads
/// `unknown_capability`, a denial).
const _allIds = [
  kSwapMaster,
  ...kSwapCascade,
  'onramp.cashapp',
  'hyperliquid.browse',
  'hyperliquid.stocks',
  'hyperliquid.referrer',
  'polymarket.browse',
  'polymarket.sports',
  'polymarket.politics',
  'polymarket.protocol_v2',
  'trading.advanced',
  'ledger.hyperliquid',
  'ledger.polymarket',
  ...kVenueExits,
];

enum MarketDenial { swapCountryBlock, platform, masterOff, comingSoon }

extension MarketDenialLabel on MarketDenial {
  String get label => switch (this) {
        MarketDenial.swapCountryBlock => 'swap country block (cascade)',
        MarketDenial.platform => 'platform block',
        MarketDenial.masterOff => 'master switch off',
        MarketDenial.comingSoon => 'coming soon',
      };

  /// Kute's whole sentence for a denial of this kind (messageIn).
  String get message => switch (this) {
        MarketDenial.swapCountryBlock =>
          '$kGatingNamedTitle\n$kGatingVpnSentence',
        MarketDenial.platform => marketGatingEn.capabilityDeviceRestricted,
        MarketDenial.masterOff => marketGatingEn.capabilityUnavailable,
        MarketDenial.comingSoon => marketGatingEn.capabilityComingSoon,
      };
}

Map<String, Object?> _decision(String id,
    {required MarketDenial? how, required Set<String> targets}) {
  if (how == MarketDenial.swapCountryBlock) {
    if (id == kSwapMaster) {
      return {
        'allowed': false,
        'reason': 'country_blocked',
        'regions': kGatingRegions,
      };
    }
    if (kSwapCascade.contains(id) || targets.contains(id)) {
      return {
        'allowed': false,
        'reason': 'country_blocked',
        'blockedBy': kSwapMaster,
        'regions': kGatingRegions,
      };
    }
    return {'allowed': true};
  }
  if (how == null || !targets.contains(id)) return {'allowed': true};
  return switch (how) {
    MarketDenial.platform => {
        'allowed': false,
        'reason': 'platform_not_allowed'
      },
    MarketDenial.masterOff => {'allowed': false, 'reason': 'disabled'},
    MarketDenial.comingSoon => {
        'allowed': false,
        'reason': 'coming_soon',
        'comingSoon': true,
      },
    MarketDenial.swapCountryBlock => throw StateError('handled above'),
  };
}

/// A loaded backend policy denying [targets] the way [how] says (the swap
/// country block also denies its whole cascade; [targets] adds to it).
/// [overrides] replaces single decisions (e.g. `country_unknown`). Null
/// [how] allows everything. Set `AffiliateService.debugSessionToken`
/// before refreshing it.
RuntimeCapabilitiesService marketGatingPolicy(
  MarketDenial? how, {
  Set<String> targets = const {},
  Map<String, Map<String, Object?>> overrides = const {},
}) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                for (final id in _allIds)
                  id: overrides[id] ??
                      _decision(id, how: how, targets: targets),
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
      store: MemoryRuntimePolicySnapshotStore(),
    );

/// [marketGatingPolicy], installed as the app's policy and refreshed.
Future<RuntimeCapabilitiesService> installMarketGatingPolicy(
  MarketDenial? how, {
  Set<String> targets = const {},
  Map<String, Map<String, Object?>> overrides = const {},
}) async {
  if (AffiliateService.sessionToken == null) {
    AffiliateService.debugSessionToken = 'gating-audit-session';
  }
  final policy =
      marketGatingPolicy(how, targets: targets, overrides: overrides);
  RuntimeCapabilitiesService.debugInstance = policy;
  final ok = await policy.refresh();
  if (!ok) throw StateError('the fixture policy did not load');
  return policy;
}

void uninstallMarketGatingPolicy() {
  RuntimeCapabilitiesService.debugInstance?.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  AffiliateService.debugSessionToken = null;
}
