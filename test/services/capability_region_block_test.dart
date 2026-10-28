// Region blocks named by the backend (founder decision, 27 October 2026):
// the regions live only in the backend policy, the app obeys the decision
// and names what it was told. A block on swaps cascades (`blockedBy`) to
// the Investing and Predictions deposits and trading, Dollars deposits and
// cross-chain sends and receives; exits stay open; plain bitcoin is never
// gated. The copy names the regions and its only VPN sentence is "If this
// isn't where you are, check your VPN settings." — never advice to use one.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _regions = {
  'label': 'the European Union, the UK and Switzerland',
  'labels': {
    'de': 'der Europäischen Union, im Vereinigten Königreich und der Schweiz',
    'pt': 'na União Europeia, no Reino Unido e na Suíça',
  },
  'groups': ['eu', 'uk', 'ch'],
  'countries': ['DE', 'FR', 'GB', 'CH'],
};

const _named = 'Not available in the European Union, the UK and Switzerland';
const _vpn = "If this isn't where you are, check your VPN settings.";

/// The backend blocking swaps in a region, and the cascade it sends: the
/// Investing and Predictions deposits and trading, crypto deposits and
/// one-time addresses inherit the block. Exits are untouched.
const _cascaded = [
  'orchestra.swap.stablecoins',
  'orchestra.swap.altcoins',
  'crypto.deposit',
  'orchestra.onetime_addresses',
  'hyperliquid.trade',
  'hyperliquid.deposit',
  'polymarket.trade',
  'polymarket.deposit',
];

RuntimeCapabilitiesService _regionPolicy({bool named = true}) =>
    runtimePolicyFixture(
      blocked: {'orchestra.swap', ..._cascaded},
      reasons: {
        'orchestra.swap': 'country_blocked',
        for (final id in _cascaded) id: 'country_blocked',
      },
      decorations: {
        'orchestra.swap': {if (named) 'regions': _regions},
        for (final id in _cascaded)
          id: {
            'blockedBy': 'orchestra.swap',
            if (named) 'regions': _regions,
          },
      },
    );

OrchestraReceiveOption _row(String chain, String asset,
        {bool reusable = false}) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
      reusableAddress: reusable,
    );

void main() {
  setUp(() {
    AffiliateService.debugSessionToken = 'session';
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('parsing', () {
    test('an older backend without blockedBy or regions reads as before',
        () async {
      final policy = runtimePolicyFixture(
          blocked: {'orchestra.swap'},
          reasons: {'orchestra.swap': 'country_blocked'});
      expect(await policy.refresh(), isTrue);
      final d = policy.decision('orchestra.swap');
      expect(d.allowed, isFalse);
      expect(d.blockedBy, isEmpty);
      expect(d.regions, isNull);
      expect(d.regionRestricted, isTrue);
      expect(d.regionNamed, isFalse);
      expect(d.regionTitleIn(_en), isNull);
      expect(d.bodyIn(_en), _en.capabilityRegionRestricted);
      expect(d.messageIn(_en), _en.capabilityRegionRestricted);
      policy.dispose();
    });

    test('a newer backend: regions and the cascade are read', () async {
      final policy = _regionPolicy();
      expect(await policy.refresh(), isTrue);
      final root = policy.decision('orchestra.swap');
      expect(root.blockedBy, isEmpty);
      expect(root.regions!.label, _regions['label']);
      expect(root.regions!.groups, ['eu', 'uk', 'ch']);
      expect(root.regions!.countries, ['DE', 'FR', 'GB', 'CH']);
      final inherited = policy.decision('hyperliquid.deposit');
      expect(inherited.allowed, isFalse);
      expect(inherited.blockedBy, 'orchestra.swap');
      expect(inherited.regionRestricted, isTrue);
      expect(inherited.regionTitleIn(_en), _named);
      // Exits are never part of the cascade.
      for (final exit in [
        'hyperliquid.withdraw',
        'hyperliquid.close',
        'polymarket.withdraw',
        'polymarket.close',
      ]) {
        expect(policy.allows(exit), isTrue, reason: exit);
      }
      policy.dispose();
    });

    test(
        'a 403 feature_unavailable keeps blockedBy and regions; an older '
        'body without them still parses', () {
      final denial = capabilityDenialFromResponse(
          403,
          jsonEncode({
            'error': 'feature_unavailable',
            'capability': 'hyperliquid.deposit',
            'reason': 'country_blocked',
            'blockedBy': 'orchestra.swap',
            'regions': _regions,
          }))!;
      expect(denial.capability, 'hyperliquid.deposit');
      expect(denial.decision.blockedBy, 'orchestra.swap');
      expect(denial.decision.regionTitleIn(_en), _named);

      final old = capabilityDenialFromResponse(
          403,
          jsonEncode({
            'error': 'feature_unavailable',
            'capability': 'orchestra.swap',
            'reason': 'country_blocked',
            'message': 'Operator words.',
          }))!;
      expect(old.decision.blockedBy, isEmpty);
      expect(old.decision.regions, isNull);
      expect(old.decision.messageIn(_en), 'Operator words.');
    });

    test(
        'a cascaded block whose own reason is not a region code still '
        'reads as the named region block', () {
      final d = CapabilityDecision.fromJson({
        'allowed': false,
        'reason': 'requires_capability',
        'blockedBy': 'orchestra.swap',
        'regions': _regions,
      });
      expect(d.regionRestricted, isTrue);
      expect(d.regionTitleIn(_en), _named);
      expect(d.bodyIn(_en), _vpn);
      // Without regions it is no region block: its own words stand.
      final plain = CapabilityDecision.fromJson({
        'allowed': false,
        'reason': 'disabled',
        'blockedBy': 'orchestra.swap',
      });
      expect(plain.regionRestricted, isFalse);
      expect(plain.messageIn(_en), _en.capabilityUnavailable);
    });
  });

  group('copy', () {
    test(
        'named: the title names the regions, the body is the one VPN '
        'sentence; inline copy carries both', () {
      final d = CapabilityDecision.fromJson({
        'allowed': false,
        'reason': 'country_blocked',
        'message': 'Ignored for a named region block.',
        'regions': _regions,
      });
      expect(d.regionTitleIn(_en), _named);
      expect(d.bodyIn(_en), _vpn);
      expect(d.messageIn(_en), '$_named\n$_vpn');
    });

    test(
        'the region phrase follows the app language, then its language, '
        'then the English label', () {
      final d = CapabilityDecision.fromJson(
          {'allowed': false, 'reason': 'country_blocked', 'regions': _regions});
      expect(d.regionTitleIn(lookupAppLocalizations(const Locale('de'))),
          contains('der Europäischen Union'));
      expect(d.regionTitleIn(lookupAppLocalizations(const Locale('pt'))),
          contains('na União Europeia'));
      expect(d.regionTitleIn(lookupAppLocalizations(const Locale('fr'))),
          contains('the European Union, the UK and Switzerland'));
      expect(CapabilityRegions.fromJson(_regions)!.labelFor('pt_BR'),
          'na União Europeia, no Reino Unido e na Suíça');
      // The backend stores regional keys lowercased with "-".
      final regional = CapabilityRegions.fromJson({
        ..._regions,
        'labels': {'es-es': 'la Unión Europea', 'es': 'la UE'},
      })!;
      expect(regional.labelFor('es_ES'), 'la Unión Europea');
      expect(regional.labelFor('es_MX'), 'la UE');
    });

    test('unnamed falls back to the operator message, then the default', () {
      expect(
          const CapabilityDecision(
                  allowed: false,
                  reason: 'country_blocked',
                  serverMessage: 'Operator words.')
              .messageIn(_en),
          'Operator words.');
      expect(
          const CapabilityDecision(allowed: false, reason: 'country_blocked')
              .bodyIn(_en),
          _en.capabilityRegionRestricted);
    });

    test(
        'every locale: the VPN sentence is the only VPN mention in the '
        'region copy and never tells anyone to use a VPN', () {
      final banned = RegExp(
          r'\b(use|turn on|switch on|enable|connect to|try) (a |an |your )?VPN',
          caseSensitive: false);
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        final vpn = l10n.capabilityRegionCheckVpn;
        expect('VPN'.allMatches(vpn).length, 1, reason: locale.toString());
        for (final copy in [
          vpn,
          l10n.capabilityRegionRestricted,
          l10n.tradingUnavailableRegion,
          l10n.ledgerErrorGeoBlocked,
          l10n.providerRegionRestricted('Hyperliquid'),
          l10n.capabilityRegionTitleNamed('X'),
        ]) {
          expect('VPN'.allMatches(copy).length, lessThanOrEqualTo(1),
              reason: '$locale: $copy');
          if (copy.contains('VPN')) {
            expect(copy, endsWith(vpn), reason: '$locale: $copy');
          }
          expect(banned.hasMatch(copy), isFalse, reason: '$locale: $copy');
        }
        expect(l10n.capabilityRegionTitleNamed('REGIONS'), contains('REGIONS'));
      }
      expect(_en.capabilityRegionCheckVpn, _vpn);
      expect(
          _en.capabilityRegionTitleNamed('the EU'), 'Not available in the EU');
    });
  });

  group('entry points under the swap cascade', () {
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      policy = _regionPolicy();
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
    });

    test(
        'Investing: trade and deposit refuse with the named copy; close, '
        'cancel-free exits and withdraw pass', () async {
      await expectLater(
          policy.ensureAllAllowed(['hyperliquid.trade']),
          throwsA(isA<CapabilityUnavailableException>()
              .having((e) => e.decision.regionTitleIn(_en), 'title', _named)));
      await expectLater(policy.ensureAllAllowed(['hyperliquid.deposit']),
          throwsA(isA<CapabilityUnavailableException>()));
      await policy.ensureAllowed('hyperliquid.close');
      await policy.ensureAllowed('hyperliquid.withdraw');
      await policy.ensureAllowed('polymarket.close');
      await policy.ensureAllowed('polymarket.withdraw');
      await expectLater(policy.ensureAllAllowed(['polymarket.trade']),
          throwsA(isA<CapabilityUnavailableException>()));
    });

    test(
        'Move money: exits out of a venue (Buy bitcoin from Investing '
        'included) stay open; into a venue or Dollars is refused with the '
        'named copy and its cascade', () {
      MoneyMovementRestriction? restriction(
              MoneyMovementAccount from, MoneyMovementAccount to) =>
          moneyMovementRestrictionFor(
              moneyMovementPlanFor(MoneyMovementRoute(from, to)).capabilities,
              policy.decision);
      const investing = MoneyMovementAccount.investing,
          predictions = MoneyMovementAccount.predictions,
          bitcoin = MoneyMovementAccount.bitcoin,
          dollars = MoneyMovementAccount.dollars;
      expect(restriction(investing, bitcoin), isNull);
      expect(restriction(investing, dollars), isNull);
      expect(restriction(predictions, bitcoin), isNull);
      expect(restriction(predictions, dollars), isNull);

      final intoInvesting = restriction(bitcoin, investing)!;
      expect(intoInvesting.capability, 'hyperliquid.deposit');
      expect(intoInvesting.region, isTrue);
      expect(intoInvesting.policyRegion, isTrue);
      expect(intoInvesting.blockedBy, 'orchestra.swap');
      expect(intoInvesting.message, contains('European Union'));

      final intoDollars = restriction(bitcoin, dollars)!;
      expect(intoDollars.capability, 'orchestra.swap');
      expect(intoDollars.blockedBy, isEmpty);
    });

    test(
        'a later leg refused with the 403 stops as a restriction (no '
        'Retry), with the named copy', () {
      final denial = capabilityDenialFromResponse(
          403,
          jsonEncode({
            'error': 'feature_unavailable',
            'capability': 'orchestra.swap',
            'reason': 'country_blocked',
            'regions': _regions,
          }))!;
      final restriction = moneyMovementRestrictionOf(denial,
          capabilities: const ['hyperliquid.withdraw'],
          decide: policy.decision)!;
      expect(restriction.region, isTrue);
      expect(restriction.message, '$_named\n$_vpn');
    });

    test(
        'pickers keep the rows a region refuses; their tap reads the '
        'block. Rows refused for any other reason still go', () {
      final rows = [_row('ethereum', 'USDT'), _row('solana', 'SOL')];
      final kept = orchestraOptionsOfferedUnderPolicy(rows, policy);
      expect(kept.offered, rows);
      expect(kept.hiddenReason, isNull);
      final strict = orchestraOptionsOfferedUnderPolicy(rows, policy,
          keepRegionBlocked: false);
      expect(strict.offered, isEmpty);
      final block = orchestraOptionRegionBlock(rows.first, policy)!;
      expect(block.capability, 'orchestra.swap');
      expect(block.decision.regionTitleIn(_en), _named);
      final receive =
          orchestraOptionRegionBlock(rows.first, policy, depositAddress: true)!;
      expect(receive.capability, 'orchestra.onetime_addresses');

      final off = runtimePolicyFixture(blocked: {'orchestra.swap'});
      addTearDown(off.dispose);
      return off.refresh().then((_) {
        final hidden = orchestraOptionsOfferedUnderPolicy(rows, off);
        expect(hidden.offered, isEmpty);
        expect(hidden.hiddenReason, isNotNull);
        expect(orchestraOptionRegionBlock(rows.first, off), isNull);
      });
    });
  });
}
