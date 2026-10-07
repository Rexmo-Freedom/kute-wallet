// An onramp the runtime policy does not offer is not shown anywhere:
// denied, coming soon, unknown to the policy, or no policy at all all
// read as hidden. These pin `onrampVisible` against the real service.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = DateTime.utc(2026, 10, 1, 12);
  late DateTime now;
  var online = true;
  late RuntimeCapabilitiesService service;

  Map<String, dynamic> policy() => {
        'schemaVersion': 1,
        'revision': 1,
        'evaluatedAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
        'capabilities': {
          'onramp.cashapp': {'allowed': true},
          'onramp.bank': {'allowed': true, 'comingSoon': true},
          'onramp.depix': {'allowed': false, 'reason': 'disabled'},
          'onramp.future': {'allowed': false, 'reason': 'country_unknown'},
        },
      };

  setUp(() {
    now = origin;
    online = true;
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => online
          ? http.Response(jsonEncode(policy()), 200)
          : http.Response('', 503)),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => 'wallet-a',
      clock: () => now,
      appVersion: () async => '2.0.4',
    );
  });
  tearDown(() => service.dispose());

  test('no policy read yet: every onramp is hidden', () {
    expect(onrampVisible(service, kOnrampCashApp), isFalse);
    expect(onrampVisible(service, kOnrampBank), isFalse);
  });

  test('only an onramp the policy offers outright is visible', () async {
    expect(await service.refresh(), isTrue);
    expect(onrampVisible(service, kOnrampCashApp), isTrue);
    // Coming soon is not offered: no badge, no row.
    expect(onrampVisible(service, kOnrampBank), isFalse);
    expect(onrampVisible(service, 'onramp.depix'), isFalse);
    // Onramps are not location-advisory: an unknown country hides them.
    expect(onrampVisible(service, 'onramp.future'), isFalse);
    // An onramp the policy does not name is not offered.
    expect(onrampVisible(service, 'onramp.unlisted'), isFalse);
  });

  test('a policy outage hides an onramp that was offered', () async {
    expect(await service.refresh(), isTrue);
    expect(onrampVisible(service, kOnrampCashApp), isTrue);
    // The policy goes stale and the next fetch fails.
    online = false;
    now = now.add(const Duration(minutes: 6));
    expect(await service.refresh(), isFalse);
    expect(service.snapshot, isNull);
    expect(onrampVisible(service, kOnrampCashApp), isFalse);
  });
}
