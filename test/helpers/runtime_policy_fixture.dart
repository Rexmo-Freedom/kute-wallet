import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

RuntimeCapabilitiesService runtimePolicyFixture(
        {Set<String> blocked = const {}, int revision = 1, int? maxLeverage}) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': revision,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                for (final id in [
                  'orchestra.swap',
                  'orchestra.swap.stablecoins',
                  'orchestra.swap.altcoins',
                  'crypto.deposit',
                  'orchestra.onetime_addresses',
                  'onramp.cashapp',
                  'hyperliquid.trade',
                  'hyperliquid.stocks',
                  'hyperliquid.referrer',
                  'hyperliquid.deposit',
                  'hyperliquid.withdraw',
                  'hyperliquid.close',
                  'polymarket.deposit',
                  'polymarket.close',
                  'polymarket.trade',
                  'polymarket.sports',
                  'polymarket.politics',
                  'polymarket.withdraw',
                  'trading.advanced',
                ])
                  id: {
                    'allowed': !blocked.contains(id),
                    'reason': blocked.contains(id) ? 'disabled' : '',
                    'comingSoon': false
                  },
              },
              'fees': {
                'fiat_deposit': {'mode': 'fixed', 'bps': 100},
                'cross_chain_send': {'mode': 'fixed', 'bps': 50},
                'venue_withdrawal': {'mode': 'fixed', 'bps': 0}
              },
              'ai': {'dailyLimit': 5},
              'investing': {'maxLeverage': maxLeverage},
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.0.4',
    );
