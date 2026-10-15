import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
import 'package:kute/services/investment_provider_availability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = DateTime.utc(2026, 9, 22, 12);
  late DateTime now;
  late String? session;
  late RuntimeCapabilitiesService service;

  Map<String, dynamic> policy(
          {int revision = 1,
          bool trade = true,
          bool comingSoon = false,
          Duration validFor = const Duration(minutes: 5)}) =>
      {
        'schemaVersion': 1,
        'revision': revision,
        'evaluatedAt': now.toIso8601String(),
        'expiresAt': now.add(validFor).toIso8601String(),
        'capabilities': {
          'hyperliquid.trade': {
            'allowed': trade,
            'reason': trade ? '' : 'country_blocked'
          },
          'hyperliquid.close': {'allowed': true},
          'hyperliquid.withdraw': {'allowed': true},
          'onramp.bank': {'allowed': true, 'comingSoon': comingSoon},
        },
        'fees': {
          'fiat_deposit': {'bps': 100, 'mode': 'fixed'}
        },
        'ai': {'dailyLimit': 5, 'remaining': 3},
        'security': {'smallActionAllowanceCents': 250},
      };

  /// What `/config/policy` (no session) publishes: the same shape minus
  /// `ai` and `referral.isReferred`, with account rules unknown.
  Map<String, dynamic> publicPolicy({int revision = 1, bool trade = true}) => {
        ...policy(revision: revision, trade: trade),
        'capabilities': {
          ...policy(trade: trade)['capabilities'] as Map<String, dynamic>,
          'polymarket.trade': {'allowed': true},
          'trading.advanced': {'allowed': false, 'reason': 'affiliate_unknown'},
          'wallet.savings': {'allowed': false, 'reason': 'wallet_unknown'},
          'hyperliquid.stocks': {'allowed': false, 'reason': 'country_blocked'},
        },
        'polymarket': {'builderCode': 'kute-builder'},
      }..remove('ai');

  const publicPath = '/api/v1/config/policy';

  /// A backend: [respond] answers `/config/capabilities`; [public] answers
  /// `/config/policy`, which a backend without the route (production until
  /// it is deployed) answers 404.
  http.Client client(FutureOr<http.Response> Function(http.Request) respond,
      {FutureOr<http.Response> Function(http.Request)? public}) {
    return MockClient((request) async {
      if (request.url.path == publicPath) {
        return public == null ? http.Response('', 404) : await public(request);
      }
      return respond(request);
    });
  }

  void setup(FutureOr<http.Response> Function(http.Request) respond,
      {FutureOr<http.Response> Function(http.Request)? public,
      RuntimePolicySnapshotStore? store}) {
    service = RuntimeCapabilitiesService.forTesting(
      client: client(respond, public: public),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      appVersion: () async => '2.0.4',
      store: store,
    );
  }

  setUp(() {
    now = origin;
    session = 'wallet-a';
  });
  tearDown(() => service.dispose());

  test('authenticated device context and bounded public fee metadata',
      () async {
    setup((request) {
      expect(request.url.path, '/api/v1/config/capabilities');
      expect(request.url.queryParameters,
          {'platform': 'ios', 'appVersion': '2.0.4'});
      expect(request.headers['Authorization'], 'Bearer wallet-a');
      return http.Response(jsonEncode(policy()), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.snapshot!.ai['dailyLimit'], 5);
    expect(service.snapshot!.fees['fiat_deposit']['bps'], 100);
    expect(service.snapshot!.smallActionAllowanceCents, 250);
    now = now.add(const Duration(minutes: 6));
    expect(service.snapshot, isNull);
    // A stale policy is not shown as fresh, but what it allowed stays
    // allowed for the offline grace period, marked as such.
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'offline_grace');
    expect(service.decision('hyperliquid.trade').offline, isTrue);
    expect(service.allows('hyperliquid.close'), isTrue);
  });

  test('sends the device id and surfaces the reason beside the control',
      () async {
    late http.Request seen;
    setup((request) {
      seen = request;
      final body = policy();
      body['capabilities'] = <String, dynamic>{
        ...body['capabilities'] as Map,
        'trading.advanced': {
          'allowed': false,
          'reason': 'affiliate_not_allowed',
          'message': 'Advanced trading is in closed beta.',
        },
        'onramp.cashapp': {'allowed': false, 'reason': 'app_update_required'},
        'hardware.wallet': {'allowed': false, 'reason': 'device_blocked'},
        'polymarket.close': {'allowed': false, 'reason': 'wallet_blocked'},
      };
      return http.Response(jsonEncode(body), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(seen.headers['X-Kute-App-Version'], '2.0.4');
    expect(seen.url.queryParameters['appVersion'], '2.0.4');
    // The operator's sentence wins; reason codes get Kute's wording.
    expect(service.blockReason('trading.advanced'),
        'Advanced trading is in closed beta.');
    expect(service.blockReason('onramp.cashapp'), contains('Update Kute'));
    expect(service.blockReason('hardware.wallet'), contains('this device'));
    expect(service.blockReason('polymarket.close'), contains('your account'));
    expect(service.blockReason('hyperliquid.close'), isNull);
    expect(service.allows('trading.advanced'), isFalse);
  });

  test('the capabilities request never carries the install id', () async {
    late http.Request seen;
    setup((request) {
      seen = request;
      return http.Response(jsonEncode(policy()), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(seen.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-kute-device-id')));
    expect(
        seen.headers.keys.where((k) => k.toLowerCase().contains('device')),
        isEmpty);
    expect(
        seen.url.queryParameters.keys
            .where((k) => k.toLowerCase().contains('device')),
        isEmpty);
    expect((await service.requestContextHeaders()).keys,
        unorderedEquals(['X-Kute-Platform', 'X-Kute-App-Version']));
  });

  test('a policy outage keeps what the last policy allowed, for 24 hours',
      () async {
    var online = true;
    setup((_) =>
        http.Response(online ? jsonEncode(policy()) : '', online ? 200 : 503));
    await service.refresh();
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, '');
    online = false;
    // The held policy is still fresh, so its answer stands for display...
    expect(service.allows('hyperliquid.trade'), isTrue);
    // ...and execution refetches, fails, and falls back to the held policy:
    // trading was allowed, so it stays allowed, marked offline.
    await service.ensureAllowed('hyperliquid.trade');
    await service.ensureAllowed('onramp.bank');
    await service.ensureAllowed('hyperliquid.withdraw');
    await service.ensureAllAllowed(['hyperliquid.trade', 'onramp.bank']);
    // Expired by the server's clock and by the display age: still allowed.
    for (final at in [
      const Duration(minutes: 6),
      const Duration(hours: 12),
      const Duration(hours: 24),
    ]) {
      now = origin.add(at);
      expect(service.snapshot, isNull, reason: '$at');
      expect(service.allows('hyperliquid.trade'), isTrue, reason: '$at');
      expect(service.decision('hyperliquid.trade').reason, 'offline_grace',
          reason: '$at');
      expect(service.blockReason('hyperliquid.trade'), isNull, reason: '$at');
      expect(service.decision('hyperliquid.trade').message,
          contains("can't be reached"),
          reason: '$at');
      await service.ensureAllowed('hyperliquid.trade');
      expect(service.allows('hyperliquid.browse'), isTrue);
    }
    // A capability the policy never named is still unknown, not granted.
    expect(service.allows('polymarket.trade'), isFalse);
    expect(service.decision('polymarket.trade').reason, 'policy_unavailable');
    // Past the grace period the offline table decides again.
    now = origin.add(const Duration(hours: 24, seconds: 1));
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'policy_unavailable');
    expect(service.blockReason('hyperliquid.trade'), contains('Unable to check'));
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'policy_unavailable')));
    await expectLater(
        service.ensureAllowed('onramp.bank'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'policy_unavailable')));
    await service.ensureAllowed('hyperliquid.withdraw');
    expect(service.allows('hyperliquid.browse'), isTrue);
    // The backend comes back: a fresh policy replaces the grace at once.
    online = true;
    expect(await service.refresh(), isTrue);
    expect(service.decision('hyperliquid.trade').reason, '');
  });

  test('the grace never turns an explicit deny or coming-soon into permission',
      () async {
    var online = true;
    setup((_) {
      final value = policy(trade: false, comingSoon: true);
      (value['capabilities'] as Map)['polymarket.trade'] = {
        'allowed': false,
        'reason': 'disabled',
        'message': 'Bets are paused.',
      };
      return http.Response(online ? jsonEncode(value) : '', online ? 200 : 503);
    });
    expect(await service.refresh(), isTrue);
    online = false;
    for (final at in [Duration.zero, const Duration(hours: 23)]) {
      now = origin.add(at);
      expect(service.allows('hyperliquid.trade'), isFalse, reason: '$at');
      expect(service.decision('hyperliquid.trade').reason, 'country_blocked');
      expect(service.allows('polymarket.trade'), isFalse, reason: '$at');
      expect(service.blockReason('polymarket.trade'), 'Bets are paused.');
      expect(service.allows('onramp.bank'), isFalse, reason: '$at');
      expect(service.decision('onramp.bank').comingSoon, isTrue);
      await expectLater(
          service.ensureAllowed('polymarket.trade'),
          throwsA(isA<CapabilityUnavailableException>()
              .having((e) => e.decision.reason, 'reason', 'disabled')));
      // Exits the policy allowed are in grace like anything else.
      await service.ensureAllowed('hyperliquid.close');
      expect(service.decision('hyperliquid.close').reason,
          at == Duration.zero ? '' : 'offline_grace');
    }
  });

  test('the last policy is saved on disk and restored at the next start',
      () async {
    const slot = RuntimePolicySlot.session;
    final disk = MemoryRuntimePolicySnapshotStore();
    setup((_) => http.Response(jsonEncode(policy()), 200), store: disk);
    expect(disk.read(slot), isNull);
    expect(await service.refresh(), isTrue);
    final saved = disk.read(slot)!;
    expect(saved.owner, 'wallet-a');
    expect(saved.fetchedAt, origin);
    expect(saved.policy['revision'], 1);
    // Public metadata only: the token never goes to disk.
    expect(jsonEncode(saved.toJson()), isNot(contains('Bearer')));
    expect(saved.toJson()['owner'], 'wallet-a');
    expect(disk.read(RuntimePolicySlot.public), isNull,
        reason: 'the public route answered 404');
    service.dispose();

    // Next launch, 3 hours later, backend unreachable: the saved policy is
    // the held policy, and what it allowed stays allowed.
    now = origin.add(const Duration(hours: 3));
    setup((_) => http.Response('', 503), store: disk);
    expect(service.allows('hyperliquid.trade'), isFalse,
        reason: 'nothing restored yet');
    service.restore();
    expect(service.snapshot, isNull, reason: 'restored, but not fresh');
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'offline_grace');
    expect(service.maxLeverage, 1);
    expect(await service.refresh(), isFalse);
    await service.ensureAllowed('hyperliquid.trade');
    expect(service.allows('polymarket.trade'), isFalse);
    // The saved copy is untouched by failed fetches.
    expect(disk.read(slot)!.fetchedAt, origin);
    service.dispose();

    // Another wallet's session never reads a policy saved for this one.
    session = 'wallet-b';
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'policy_unavailable');
    service.dispose();

    // A saved policy older than the grace period is dropped at start.
    session = 'wallet-a';
    now = origin.add(const Duration(hours: 25));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(disk.read(slot), isNull);
  });

  test('a restored deny blocks and a corrupt saved policy is forgotten',
      () async {
    const slot = RuntimePolicySlot.session;
    final disk = MemoryRuntimePolicySnapshotStore();
    final denied = policy(trade: false);
    (denied['capabilities'] as Map)['hyperliquid.trade']['reason'] = 'disabled';
    disk.write(
        slot,
        StoredRuntimePolicy(
            owner: 'wallet-a', fetchedAt: origin, policy: denied));
    now = origin.add(const Duration(hours: 1));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'disabled');
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'disabled')));
    service.dispose();

    // A restored region denial was asked before this launch, maybe from
    // another country: it waits for the launch fetch. Unanswered, it is an
    // unknown location, which never blocks...
    disk.write(
        slot,
        StoredRuntimePolicy(
            owner: 'wallet-a', fetchedAt: origin, policy: policy(trade: false)));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'country_unknown');
    await service.ensureAllowed('hyperliquid.trade');
    service.dispose();

    // ...and once the launch fetch confirms it, it blocks again.
    setup((_) => http.Response(jsonEncode(policy(trade: false)), 200),
        store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'country_blocked');
    service.dispose();

    disk.write(
        slot,
        StoredRuntimePolicy(
            owner: 'wallet-a',
            fetchedAt: origin,
            policy: {...policy(), 'schemaVersion': 7}));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'policy_unavailable');
    expect(disk.read(slot), isNull);
  });

  test('the session owner, not the raw token, binds the held policy',
      () async {
    // Tokens renew; the wallet behind them does not. A renewed token keeps
    // the policy (and its grace), a different wallet does not.
    var online = true;
    service = RuntimeCapabilitiesService.forTesting(
      client: client((_) =>
          http.Response(online ? jsonEncode(policy()) : '', online ? 200 : 503)),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      sessionOwner: (token) => token?.split('/').first,
    );
    session = 'wallet-a/token-1';
    expect(await service.refresh(), isTrue);
    online = false;
    now = now.add(const Duration(hours: 2));
    session = 'wallet-a/token-2';
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'offline_grace');
    session = 'wallet-b/token-3';
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'policy_unavailable');
  });

  test('a wallet without a session reads the public policy first', () async {
    final publicRequests = <http.Request>[];
    var sessionRequests = 0;
    setup((_) {
      sessionRequests++;
      final body = policy();
      (body['capabilities'] as Map)['trading.advanced'] = {'allowed': true};
      body['polymarket'] = {'builderCode': 'kute-session'};
      return http.Response(jsonEncode(body), 200);
    }, public: (request) {
      publicRequests.add(request);
      return http.Response(jsonEncode(publicPolicy()), 200);
    });
    session = null;
    expect(service.polymarketBuilderCode, isNull);
    expect(await service.refresh(), isTrue);
    expect(sessionRequests, 0);
    expect(publicRequests, hasLength(1));
    expect(publicRequests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
    expect(service.snapshot, isNull);
    expect(service.publicSnapshot, isNotNull);
    // Country, platform and version rules apply as the backend states them.
    expect(service.allows('polymarket.trade'), isTrue);
    expect(service.decision('polymarket.trade').reason, '');
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.allows('hyperliquid.stocks'), isFalse);
    expect(service.decision('hyperliquid.stocks').reason, 'country_blocked');
    // Account rules the public route cannot evaluate are unknown, not
    // denied: the offline table decides until a session policy arrives.
    expect(service.allows('trading.advanced'), isFalse);
    expect(service.decision('trading.advanced').reason, 'policy_unavailable');
    expect(service.allows('wallet.savings'), isFalse);
    expect(service.decision('wallet.savings').reason, 'policy_unavailable');
    expect(service.allows('hyperliquid.close'), isTrue);
    // Execution reads the fresh public policy too.
    await service.ensureAllowed('polymarket.trade');
    await expectLater(
        service.ensureAllowed('trading.advanced'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'policy_unavailable')));
    expect(service.polymarketBuilderCode, 'kute-builder');
    expect(service.publicSnapshot!.ai, isEmpty);
    expect(service.publicSnapshot!.isReferred, isFalse);

    // Every refresh without a fresh session policy asks for the public one
    // again (the two execution checks above did).
    expect(publicRequests, hasLength(3));

    // The wallet signs in: the session policy is layered on top and decides
    // the account rules. That first session fetch still goes out with a
    // public fetch (no fresh session policy yet); once the session policy is
    // fresh, a refresh asks for the session policy only.
    session = 'wallet-a';
    expect(await service.refresh(), isTrue);
    expect(sessionRequests, 1);
    expect(publicRequests, hasLength(4));
    expect(service.snapshot, isNotNull);
    expect(service.allows('trading.advanced'), isTrue);
    expect(service.polymarketBuilderCode, 'kute-session');
    expect(await service.refresh(), isTrue);
    expect(sessionRequests, 2);
    expect(publicRequests, hasLength(4));
    // A later refresh with the session policy expired asks for both.
    now = now.add(const Duration(minutes: 6));
    expect(await service.refresh(), isTrue);
    expect(sessionRequests, 3);
    expect(publicRequests, hasLength(5));
  });

  test('a fresh public deny blocks even while a stale session policy allowed',
      () async {
    var online = true;
    setup((_) => online ? http.Response(jsonEncode(policy()), 200) : http.Response('', 503),
        public: (_) => http.Response(jsonEncode(publicPolicy(trade: false)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.trade'), isTrue,
        reason: 'the fresh session policy decides');
    online = false;
    now = now.add(const Duration(minutes: 6));
    // Session fetch fails, the public one lands: the public deny stands over
    // the stale session allow, and the public allow needs no grace.
    expect(await service.refresh(), isTrue);
    expect(service.snapshot, isNull);
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.decision('hyperliquid.trade').reason, 'country_blocked');
    expect(service.allows('polymarket.trade'), isTrue);
    expect(service.decision('polymarket.trade').reason, '');
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'country_blocked')));
  });

  test('the public policy is saved, restored and kept for the grace period',
      () async {
    final disk = MemoryRuntimePolicySnapshotStore();
    session = null;
    setup((_) => http.Response('', 503),
        public: (_) => http.Response(jsonEncode(publicPolicy()), 200),
        store: disk);
    expect(await service.refresh(), isTrue);
    final saved = disk.read(RuntimePolicySlot.public)!;
    expect(saved.owner, kPublicPolicyOwner);
    expect(disk.read(RuntimePolicySlot.session), isNull);
    service.dispose();

    // Next launch, 5 hours later, backend unreachable, still no session:
    // the saved public policy decides, in grace.
    now = origin.add(const Duration(hours: 5));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.publicSnapshot, isNull);
    expect(service.allows('polymarket.trade'), isTrue);
    expect(service.decision('polymarket.trade').reason, 'offline_grace');
    // The saved region denial came from an earlier network: unknown now.
    expect(service.allows('hyperliquid.stocks'), isTrue);
    expect(service.decision('hyperliquid.stocks').reason, 'offline_grace');
    expect(service.allows('trading.advanced'), isFalse);
    expect(service.decision('trading.advanced').reason, 'policy_unavailable');
    expect(service.polymarketBuilderCode, 'kute-builder');
    expect(await service.refresh(), isFalse);
    await service.ensureAllowed('polymarket.trade');
    // The public policy is not bound to a wallet: a session that appears
    // later reads it too, until its own policy arrives.
    session = 'wallet-a';
    expect(service.allows('polymarket.trade'), isTrue);
    service.dispose();

    now = origin.add(const Duration(hours: 25));
    setup((_) => http.Response('', 503), store: disk);
    service.restore();
    expect(service.allows('polymarket.trade'), isFalse);
    expect(disk.read(RuntimePolicySlot.public), isNull);
  });

  test('the server expiry is honoured as published', () async {
    setup((_) => http.Response(
        jsonEncode(policy(validFor: const Duration(minutes: 15))), 200));
    expect(await service.refresh(), isTrue);
    now = origin.add(const Duration(minutes: 14));
    expect(service.snapshot, isNotNull);
    expect(service.decision('hyperliquid.trade').reason, '');
    now = origin.add(const Duration(minutes: 15));
    expect(service.snapshot, isNull);
    expect(service.decision('hyperliquid.trade').reason, 'offline_grace');
  });

  test('a refresh after the current one picks up a session that appeared',
      () async {
    final gate = Completer<void>();
    var sessionRequests = 0;
    setup((_) {
      sessionRequests++;
      return http.Response(jsonEncode(policy()), 200);
    }, public: (_) async {
      await gate.future;
      return http.Response(jsonEncode(publicPolicy()), 200);
    });
    session = null;
    final first = service.refresh();
    // The first fetch has found no session and is waiting on the public
    // policy when the session shows up.
    await pumpEventQueue();
    session = 'wallet-a';
    final second = service.refreshAfterCurrent();
    gate.complete();
    expect(await first, isTrue);
    expect(sessionRequests, 0);
    expect(await second, isTrue);
    expect(sessionRequests, 1);
    expect(service.snapshot, isNotNull);
  });

  test('the stored policy record round-trips and rejects other shapes', () {
    setup((_) => http.Response('', 503));
    final record = StoredRuntimePolicy(
        owner: '42', fetchedAt: origin, policy: policy());
    final json = jsonDecode(jsonEncode(record.toJson()));
    final back = StoredRuntimePolicy.fromJson(json)!;
    expect(back.owner, '42');
    expect(back.fetchedAt, origin);
    expect(back.policy['revision'], 1);
    expect(StoredRuntimePolicy.fromJson(null), isNull);
    expect(StoredRuntimePolicy.fromJson({'v': 2}), isNull);
    expect(StoredRuntimePolicy.fromJson({...json as Map, 'owner': ''}),
        isNull);
    expect(StoredRuntimePolicy.fromJson({...json, 'fetchedAt': 'soon'}),
        isNull);
  });

  const exits = [
    'hyperliquid.cancel',
    'hyperliquid.close',
    'hyperliquid.withdraw',
    'polymarket.cancel',
    'polymarket.close',
    'polymarket.withdraw',
  ];

  test('policy outage never blocks cancelling, closing or withdrawing',
      () async {
    setup((_) => http.Response('', 503));
    expect(await service.refresh(), isFalse);
    for (final id in exits) {
      expect(service.allows(id), isTrue, reason: id);
      expect(service.blockReason(id), isNull, reason: id);
      await service.ensureAllowed(id);
    }
    await service.ensureAllAllowed(exits);
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    await service.ensureAnyAllowed(['onramp.bank', 'polymarket.withdraw']);
  });

  test('the offline table is exactly what an outage allows', () async {
    setup((_) => http.Response('', 503));
    expect(await service.refresh(), isFalse);
    expect(kOfflineAllowedCapabilities, {
      'hyperliquid.browse',
      'polymarket.browse',
      'settings.advanced',
      'export.transactions',
      // The Protocol V2 order path, so a V2 position stays sellable.
      'polymarket.protocol_v2',
      ...exits,
    });
    for (final id in kOfflineAllowedCapabilities) {
      expect(service.allows(id), isTrue, reason: id);
      expect(service.decision(id).reason, 'policy_unavailable', reason: id);
      await service.ensureAllowed(id);
    }
    for (final id in [
      // New Investing and Predictions exposure and funding.
      'hyperliquid.trade',
      'hyperliquid.deposit',
      'polymarket.trade',
      'polymarket.deposit',
      'trading.advanced',
      'hyperliquid.stocks',
      'polymarket.sports',
      'polymarket.politics',
      // Naming Kute as the Hyperliquid referrer.
      'hyperliquid.referrer',
      // Orchestra swaps and deposit addresses.
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
      'crypto.deposit',
      // One-time quoted receive addresses: an outage leaves only the
      // reusable receive options.
      'orchestra.onetime_addresses',
      // Investing and Predictions on a hardware wallet.
      'ledger.hyperliquid',
      'ledger.polymarket',
      // Adding any wallet beyond the spending account.
      'hardware.wallet',
      'wallet.savings',
      'wallet.tracked',
      // Onramps, Earn, referral, Sal.
      'onramp.bank',
      'onramp.cashapp',
      'usd.earn',
      'affiliate.program',
      'ai.ask',
      // Anything the table does not name.
      'hyperliquid.unknown',
      'polymarket.unknown',
    ]) {
      expect(service.allows(id), isFalse, reason: id);
      expect(service.blockReason(id), contains('Unable to check'), reason: id);
      await expectLater(
          service.ensureAllowed(id),
          throwsA(isA<CapabilityUnavailableException>().having(
              (e) => e.decision.reason, 'reason', 'policy_unavailable')),
          reason: id);
    }
    await expectLater(
        service.ensureAllAllowed(['hyperliquid.close', 'trading.advanced']),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.capability, 'capability', 'trading.advanced')));
    await expectLater(
        service.ensureAnyAllowed(['hyperliquid.trade', 'polymarket.deposit']),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('a hardware-wallet denial seen this session survives an outage',
      () async {
    var online = true;
    setup((_) {
      final value = policy();
      (value['capabilities'] as Map)['hardware.wallet'] = {
        'allowed': false,
        'reason': 'device_blocked'
      };
      return http.Response(online ? jsonEncode(value) : '', online ? 200 : 503);
    });
    expect(await service.refresh(), isTrue);
    online = false;
    now = now.add(const Duration(minutes: 6));
    await expectLater(
        service.ensureAllowed('hardware.wallet'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'device_blocked')));
  });

  test('an explicit exit denial from a loaded policy survives an outage',
      () async {
    var online = true;
    setup((_) {
      final value = policy();
      final capabilities = value['capabilities'] as Map;
      for (final id in exits) {
        capabilities[id] = {'allowed': false, 'reason': 'disabled'};
      }
      return http.Response(online ? jsonEncode(value) : '', online ? 200 : 503);
    });
    expect(await service.refresh(), isTrue);
    for (final id in exits) {
      expect(service.allows(id), isFalse, reason: id);
    }
    online = false;
    for (final at in [Duration.zero, const Duration(minutes: 6)]) {
      now = origin.add(at);
      for (final id in exits) {
        expect(service.allows(id), isFalse, reason: '$id +$at');
        await expectLater(
            service.ensureAllowed(id),
            throwsA(isA<CapabilityUnavailableException>()
                .having((e) => e.decision.reason, 'reason', 'disabled')),
            reason: '$id +$at');
      }
    }
  });

  test('on the same network a region denial stands through an outage, and a '
      'fresh allow lifts it at once', () async {
    var online = true;
    var blocked = true;
    setup((_) => http.Response(
        online ? jsonEncode(policy(trade: !blocked)) : '', online ? 200 : 503));
    await service.refresh();
    online = false;
    // Hours later, still on the same network, backend unreachable.
    now = now.add(const Duration(hours: 5));
    expect(service.allows('hyperliquid.trade'), isFalse);
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'country_blocked')));
    online = true;
    blocked = false;
    await service.ensureAllowed('hyperliquid.trade');
    expect(service.allows('hyperliquid.trade'), isTrue);
  });

  test('a network change stops trusting a region denial and asks again',
      () async {
    var blocked = true;
    var requests = 0;
    setup((_) {
      requests++;
      return http.Response(jsonEncode(policy(trade: !blocked)), 200);
    });
    var notified = 0;
    service.addListener(() => notified++);
    expect(await service.refresh(), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'country_blocked');
    // The VPN switches country: the next fetch answers allowed.
    blocked = false;
    final landed = service.networkChanged();
    // The old answer stays on screen while the new network answers, so a
    // re-check never flickers...
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(await landed, isTrue);
    // ...and the new answer replaces it, heard by every listener.
    expect(requests, 2);
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(notified, greaterThanOrEqualTo(2));
  });

  test('a network change with the backend unreachable never shows the old '
      'region block', () async {
    var online = true;
    setup((_) => http.Response(
        online ? jsonEncode(policy(trade: false)) : '', online ? 200 : 503));
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.trade'), isFalse);
    online = false;
    expect(await service.networkChanged(), isFalse);
    // The fresh policy was asked on another network: unknown location.
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.decision('hyperliquid.trade').reason, 'country_unknown');
    await service.ensureAllowed('hyperliquid.trade');
  });

  test('a tap asks again before showing a refusal', () async {
    var blocked = true;
    var requests = 0;
    setup((_) {
      requests++;
      return http.Response(jsonEncode(policy(trade: !blocked)), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(await service.confirmDecision('hyperliquid.close'),
        isA<CapabilityDecision>().having((d) => d.allowed, 'allowed', isTrue));
    expect(requests, 1, reason: 'an allowed door answers at once');
    blocked = false;
    final decision = await confirmCapability(service, 'hyperliquid.trade');
    expect(requests, 2);
    expect(decision.allowed, isTrue);
    // A refusal is never read from a reused policy either.
    blocked = true;
    await service.refresh();
    blocked = false;
    await service.ensureAllAllowed(['hyperliquid.trade'],
        maxAge: const Duration(minutes: 1));
    expect(requests, 4);
  });

  for (final reason in ['country_blocked', 'disabled', 'app_update_required']) {
    test('policy outage preserves previously observed $reason', () async {
      var online = true;
      setup((_) {
        final value = policy(trade: false);
        (value['capabilities'] as Map)['hyperliquid.trade']['reason'] = reason;
        return http.Response(
            online ? jsonEncode(value) : '', online ? 200 : 503);
      });
      await service.refresh();
      online = false;
      now = now.add(const Duration(minutes: 6));
      await expectLater(
          service.ensureAllowed('hyperliquid.trade'),
          throwsA(isA<CapabilityUnavailableException>()
              .having((error) => error.decision.reason, 'reason', reason)));
    });
  }

  test('unknown location passes while a missing capability stays disabled',
      () async {
    setup((_) {
      final value = policy(trade: false);
      (value['capabilities'] as Map)['hyperliquid.trade']['reason'] =
          'country_unknown';
      return http.Response(jsonEncode(value), 200);
    });
    await service.ensureAllowed('hyperliquid.trade');
    await expectLater(
        service.ensureAllowed('polymarket.trade'),
        throwsA(isA<CapabilityUnavailableException>().having(
            (error) => error.decision.reason, 'reason', 'unknown_capability')));
  });

  test('navigation scopes observe updates without disposing the app service',
      () async {
    var revision = 1;
    setup((_) => http.Response(jsonEncode(policy(revision: revision)), 200));
    RuntimeCapabilitiesService.debugInstance = service;
    addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
    final first = ProviderContainer();
    final revisions = <int?>[];
    first.listen(
        runtimeCapabilitiesProvider.select((p) => p.snapshot?.revision),
        (_, value) => revisions.add(value));
    await service.refresh();
    expect(revisions, [1]);
    first.dispose();
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.listen(
        runtimeCapabilitiesProvider.select((p) => p.snapshot?.revision),
        (_, value) => revisions.add(value));
    revision = 2;
    await service.refresh();
    expect(revisions, [1, 2]);
    expect(second.read(runtimeCapabilitiesProvider).allows('hyperliquid.trade'),
        isTrue);
  });

  test('country block preserves separately permitted close and withdrawal',
      () async {
    setup((_) => http.Response(jsonEncode(policy(trade: false)), 200));
    await expectLater(service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()));
    await service.ensureAllowed('hyperliquid.close');
    await service.ensureAllowed('hyperliquid.withdraw');
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
  });

  test(
      'provider check precedes fresh Kute policy; either may independently deny',
      () async {
    final calls = <String>[];
    var providerAllowed = true;
    var kuteAllowed = false;
    final provider = InvestmentProviderAvailability(
        cacheFor: Duration.zero,
        client: MockClient((request) async {
          calls.add('provider');
          return http.Response(
              jsonEncode({
                'acceptedTerms': true,
                'userAllowed': false,
                'restrictions': providerAllowed ? 'u' : 'a',
              }),
              200);
        }));
    service = RuntimeCapabilitiesService.forTesting(
      client: client((_) {
        calls.add('kute');
        return http.Response(jsonEncode(policy(trade: kuteAllowed)), 200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      ensureProviderAvailability: provider.ensureNewExposure,
    );
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(
          // Kute's own policy denial, not the provider's (which names the
          // provider): the generic feature wording, with no provider name.
          isA<CapabilityUnavailableException>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('This feature is restricted'),
                  isNot(contains('Hyperliquid')))),
        ));
    expect(calls, ['provider', 'kute']);
    calls.clear();
    providerAllowed = false;
    kuteAllowed = true;
    await expectLater(service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<ProviderAvailabilityException>()));
    expect(calls, ['provider']);
    calls.clear();
    await service.ensureAllowed('hyperliquid.close');
    await service.ensureAllowed('hyperliquid.withdraw');
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    expect(calls, ['kute', 'kute', 'kute']);
    calls.clear();
    providerAllowed = true;
    await service.ensureAllowed('hyperliquid.trade');
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, ['provider', 'kute', 'provider', 'kute']);
  });

  test('unknown capabilities and coming-soon rails cannot start operations',
      () async {
    setup((_) => http.Response(jsonEncode(policy(comingSoon: true)), 200));
    await expectLater(service.ensureAllowed('missing'),
        throwsA(isA<CapabilityUnavailableException>()));
    await expectLater(service.ensureAllowed('onramp.bank'),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('wallet changes invalidate cached policy and discard in-flight response',
      () async {
    final response = Completer<http.Response>();
    setup((_) => response.future);
    final request = service.refresh();
    await Future<void>.delayed(Duration.zero);
    session = 'wallet-b';
    response.complete(http.Response(jsonEncode(policy()), 200));
    expect(await request, isFalse);
    expect(service.snapshot, isNull);
  });

  test('no session asks for the public policy only, with no bearer',
      () async {
    final publicRequests = <http.Request>[];
    setup((_) => throw StateError('must not fetch the session policy'),
        public: (request) {
      publicRequests.add(request);
      return http.Response('', 404);
    });
    session = null;
    expect(await service.refresh(), isFalse);
    expect(publicRequests, hasLength(1));
    expect(publicRequests.single.url.path, publicPath);
    expect(publicRequests.single.url.queryParameters,
        {'platform': 'ios', 'appVersion': '2.0.4'});
    expect(publicRequests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
    // Without a session and without the public route the policy is
    // unavailable, so the offline table decides (see 'the offline table is
    // exactly what an outage allows'). Execution never asks for the session
    // policy without a session either.
    for (final id in ['onramp.bank', 'hyperliquid.trade']) {
      await expectLater(
          service.ensureAllowed(id),
          throwsA(isA<CapabilityUnavailableException>().having(
              (e) => e.decision.reason, 'reason', 'policy_unavailable')),
          reason: id);
    }
    await service.ensureAllowed('hyperliquid.withdraw');
  });

  test('revision rollback is rejected without dropping the latest display',
      () async {
    var revision = 4;
    setup((_) => http.Response(jsonEncode(policy(revision: revision)), 200));
    await service.refresh();
    revision = 3;
    expect(await service.refresh(), isFalse);
    expect(service.snapshot!.revision, 4);
  });

  test('one fresh request checks multiple requirements', () async {
    var calls = 0;
    setup((_) {
      calls++;
      return http.Response(jsonEncode(policy()), 200);
    });
    await service.ensureAllAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    expect(calls, 1);
  });

  test('a re-check within maxAge reads the policy it just fetched', () async {
    var calls = 0;
    setup((_) {
      calls++;
      return http.Response(jsonEncode(policy()), 200);
    });
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, 1);
    // Moments later, the same gate may read the held policy.
    await service.ensureAllowed('hyperliquid.trade',
        maxAge: const Duration(seconds: 60));
    expect(calls, 1);
    // Without a reuse window it asks again, as before.
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, 2);
    // A window shorter than the policy's age asks again too.
    await service.ensureAllowed('hyperliquid.trade', maxAge: Duration.zero);
    expect(calls, 3);
  });

  test('malformed or expired policy cannot allow an operation', () async {
    setup((_) =>
        http.Response(jsonEncode({...policy(), 'schemaVersion': 2}), 200));
    expect(await service.refresh(), isFalse);
    expect(service.snapshot, isNull);
  });

  test('the leverage cap is read from the snapshot for this region', () async {
    Map<String, dynamic> withInvesting(Object? cap, {bool present = true}) => {
          ...policy(),
          if (present) 'investing': {'maxLeverage': cap},
        };
    setup((_) => http.Response(jsonEncode(withInvesting(null)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, isNull, reason: 'null means the venue max');
    expect(service.offeredLeverage(40), 40);
    service.ensureLeverageAllowed(40);
    service.dispose();

    setup((_) => http.Response(jsonEncode(withInvesting(2)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 2);
    expect(service.offeredLeverage(40), 2);
    expect(service.offeredLeverage(1), 1);
    service.ensureLeverageAllowed(2);
    expect(
        () => service.ensureLeverageAllowed(3),
        throwsA(isA<LeverageCapExceededException>()
            .having((e) => e.maxLeverage, 'cap', 2)));
    expect(const LeverageCapExceededException(2).toString(), contains('2x'));
    service.dispose();

    // A snapshot that says nothing about leverage is read as the most
    // conservative cap, never as no cap.
    setup((_) =>
        http.Response(jsonEncode(withInvesting(null, present: false)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 1);
    service.dispose();

    setup((_) => http.Response(jsonEncode(withInvesting('x')), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 1, reason: 'malformed reads as 1x');
  });

  test('an outage can only tighten the leverage cap', () async {
    var fail = false;
    setup((_) => fail
        ? http.Response('down', 503)
        : http.Response(
            jsonEncode({
              ...policy(),
              'investing': {'maxLeverage': 5},
            }),
            200));
    // Never fetched: 1x.
    expect(service.maxLeverage, 1);
    expect(service.offeredLeverage(40), 1);
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 5);
    // Expired and unreachable: the last cap seen for this session holds.
    now = now.add(const Duration(minutes: 6));
    fail = true;
    expect(await service.refresh(), isFalse);
    expect(service.snapshot, isNull);
    expect(service.maxLeverage, 5);
    // Another session inherits nothing: back to 1x.
    session = 'wallet-b';
    expect(service.maxLeverage, 1);
  });

  test('the jurisdiction gates fail closed while exits stay open', () async {
    setup((_) => http.Response('down', 503));
    expect(await service.refresh(), isFalse);
    for (final gate in [
      'hyperliquid.stocks',
      'hyperliquid.referrer',
      'polymarket.sports',
      'polymarket.politics',
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
    ]) {
      expect(service.allows(gate), isFalse, reason: gate);
      expect(service.decision(gate).reason, 'policy_unavailable');
      expect(service.blockReason(gate), contains('Unable to check'));
    }
    for (final exit in [
      'hyperliquid.close',
      'hyperliquid.cancel',
      'hyperliquid.withdraw',
      'polymarket.close',
      'polymarket.cancel',
      'polymarket.withdraw',
    ]) {
      expect(service.allows(exit), isTrue, reason: exit);
    }
    // And with a policy loaded that names a gate, its answer is used as is.
    service.dispose();
    setup((_) => http.Response(
        jsonEncode({
          ...policy(),
          'capabilities': {
            ...policy()['capabilities'] as Map<String, dynamic>,
            'hyperliquid.stocks': {
              'allowed': false,
              'reason': 'country_blocked'
            },
            'hyperliquid.referrer': {
              'allowed': false,
              'reason': 'country_blocked'
            },
            'polymarket.sports': {'allowed': true, 'reason': 'allowed'},
            'polymarket.politics': {
              'allowed': false,
              'reason': 'country_unknown'
            },
          },
        }),
        200));
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.stocks'), isFalse);
    expect(service.decision('hyperliquid.stocks').regionRestricted, isTrue);
    expect(service.allows('hyperliquid.referrer'), isFalse);
    expect(service.allows('polymarket.sports'), isTrue);
    expect(service.allows('polymarket.politics'), isFalse,
        reason: 'an unknown country is not advisory for a narrow gate');
  });
}
