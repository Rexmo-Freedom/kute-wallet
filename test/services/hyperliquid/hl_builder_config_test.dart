// The Hyperliquid builder (Kute's fee recipient) comes only from the
// backend. These tests pin that contract: a valid backend answer is used
// for the approval check, the approval and the order fee; anything else
// (unreachable, 404, invalid) means no builder, no approval prompt and no
// builder on orders; a rotated address is a fresh, unapproved builder.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/tracking_service.dart';

const _user = '0x42187A0F42088287EbFE8c20BB7adF111e93c381';
const _builderA = '0x1111111111111111111111111111111111111111';
const _builderB = '0x2222222222222222222222222222222222222222';

class _FakeExchange implements HyperliquidExchangeService {
  final approvals = <({String builder, String maxFeeRate})>[];

  @override
  String get walletAddress => _user;

  @override
  Future<void> approveBuilderFee({
    required String builder,
    required String maxFeeRate,
  }) async {
    approvals.add((builder: builder, maxFeeRate: maxFeeRate));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _config({
  String address = _builderA,
  Object fee = 10,
  Object rate = '0.01%',
}) =>
    {'builderAddress': address, 'defaultFeeTenthsBp': fee, 'maxFeeRate': rate};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var builderHits = 0;
  final infoQueries = <Map<String, dynamic>>[];
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    HyperliquidFundingService.resetBuilderCacheForTest();
    HyperliquidFundingService.resetBuilderSourceTrackingForTest();
    FlutterSecureStorage.setMockInitialValues({});
    builderHits = 0;
    infoQueries.clear();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    HyperliquidFundingService.resetBuilderCacheForTest();
    HyperliquidFundingService.resetBuilderSourceTrackingForTest();
  });

  /// [config] null → 404; [down] → the backend cannot be reached.
  /// [approvedFor] is the venue's `maxBuilderFee` answer per builder.
  MockClient backend(Map<String, dynamic>? config,
          {bool down = false, Map<String, int> approvedFor = const {}}) =>
      MockClient((req) async {
        if (req.url.path == '/api/v1/hl/builder') {
          builderHits++;
          if (down) throw http.ClientException('connection refused');
          return config == null
              ? http.Response('', 404)
              : http.Response(jsonEncode(config), 200);
        }
        if (req.url.toString() == HyperliquidConstants.infoUri.toString()) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          infoQueries.add(body);
          return http.Response('${approvedFor[body['builder']] ?? 0}', 200);
        }
        return http.Response('not found', 404);
      });

  Future<T> withBackend<T>(Future<T> Function() body, MockClient client) =>
      http.runWithClient(body, () => client);

  List<Map<String, Object>?> sourceEvents() => [
        for (final e in events)
          if (e.$1 == 'hl_builder_address_source') e.$2
      ];

  Future<bool> ensure(_FakeExchange exchange, MockClient client,
          {HlBuilderInfo? reviewed}) =>
      withBackend(
        () => HyperliquidOnboardingService.ensureBuilderFeeApproved(
          exchange: exchange,
          walletAddress: _user,
          walletId: 'wallet-1',
          reviewed: reviewed,
        ),
        client,
      );

  group('getBuilder resolution', () {
    test('the backend value is used exactly and cached', () async {
      final client = backend(_config(fee: 5, rate: '0.005%'));
      final first =
          await withBackend(HyperliquidFundingService.getBuilder, client);
      final second =
          await withBackend(HyperliquidFundingService.getBuilder, client);
      expect(first, isNotNull);
      expect(first!.builderAddress, _builderA);
      expect(first.defaultFeeTenthsBp, 5);
      expect(first.maxFeeRate, '0.005%');
      expect(first.asOrderFee.address, _builderA);
      expect(first.asOrderFee.feeTenthsBp, 5);
      expect(identical(first, second), isTrue);
      expect(builderHits, 1);
      expect(sourceEvents(), [
        {'source': 'backend'}
      ]);
    });

    test('an unreachable backend means no builder, with a short backoff',
        () async {
      final client = backend(null, down: true);
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      // Both attempts of the first read, none during the backoff.
      expect(builderHits, 1);
      expect(sourceEvents(), [
        {'source': 'none', 'reason': 'unreachable'}
      ]);
    });

    test('a 404 is a definitive no-builder answer', () async {
      final client = backend(null);
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      expect(builderHits, 1);
      expect(sourceEvents(), [
        {'source': 'none', 'reason': 'not_configured'}
      ]);
    });

    test('invalid addresses are rejected, never used', () async {
      for (final address in [
        '0x00',
        '0x0000000000000000000000000000000000000000',
        '1111111111111111111111111111111111111111',
        '0x11111111111111111111111111111111111111zz',
      ]) {
        HyperliquidFundingService.resetBuilderCacheForTest();
        events.clear();
        expect(
            await withBackend(HyperliquidFundingService.getBuilder,
                backend(_config(address: address))),
            isNull,
            reason: address);
        expect(events.first.$2, {'reason': 'invalid_address'},
            reason: address);
      }
    });

    test('invalid fees and caps are rejected', () async {
      for (final config in [
        for (final rate in ['0.11%', 'abc', '1%', '0.01', '', '0.001%'])
          _config(rate: rate),
        for (final fee in [101, 10.5, -1, '10']) _config(fee: fee),
      ]) {
        HyperliquidFundingService.resetBuilderCacheForTest();
        expect(
            await withBackend(
                HyperliquidFundingService.getBuilder, backend(config)),
            isNull,
            reason: '$config');
      }
    });

    test('a rejection is reported once and not re-fetched at once',
        () async {
      final client = backend(_config(address: '0x00'));
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      expect(await withBackend(HyperliquidFundingService.getBuilder, client),
          isNull);
      expect(builderHits, 1);
      expect(
          events
              .where((e) => e.$1 != 'hl_builder_address_source')
              .single
              .$2,
          {'reason': 'invalid_address'});
      expect(sourceEvents(), [
        {'source': 'none', 'reason': 'invalid'}
      ]);
    });

    test('source analytics fire once per source per session, no address',
        () async {
      await withBackend(HyperliquidFundingService.getBuilder,
          backend(null, down: true));
      HyperliquidFundingService.resetBuilderCacheForTest(); // new revision
      await withBackend(
          HyperliquidFundingService.getBuilder, backend(_config()));
      HyperliquidFundingService.resetBuilderCacheForTest();
      await withBackend(HyperliquidFundingService.getBuilder,
          backend(_config(address: _builderB)));
      final sources = sourceEvents();
      expect(sources.map((p) => p!['source']), ['none', 'backend']);
      for (final params in sources) {
        for (final value in params!.values) {
          expect('$value'.toLowerCase(), isNot(contains('0x')));
        }
      }
    });
  });

  group('approval', () {
    test('the backend builder is checked and approved', () async {
      final exchange = _FakeExchange();
      final client = backend(_config());
      final builder =
          await withBackend(HyperliquidFundingService.getBuilder, client);
      expect(await ensure(exchange, client, reviewed: builder), isTrue);
      expect(infoQueries.single['builder'], _builderA);
      expect(exchange.approvals.single, (builder: _builderA, maxFeeRate: '0.01%'));
      expect(
          await withBackend(
              () => HyperliquidOnboardingService.hasApprovedBuilderFee(
                  'wallet-1'),
              client),
          isTrue);
    });

    test('an existing approval on the venue signs nothing', () async {
      final exchange = _FakeExchange();
      final ok = await ensure(
          exchange, backend(_config(), approvedFor: {_builderA: 10}));
      expect(ok, isTrue);
      expect(exchange.approvals, isEmpty);
    });

    test('a new approval needs the exact settings the order will carry',
        () async {
      final exchange = _FakeExchange();
      final client = backend(_config(fee: 20, rate: '0.02%'));
      expect(await ensure(exchange, client), isFalse);
      expect(HyperliquidOnboardingService.lastFailure, 'out_of_scope');
      expect(
          await ensure(exchange, client,
              reviewed: const HlBuilderInfo(
                  builderAddress: _builderB,
                  defaultFeeTenthsBp: 20,
                  maxFeeRate: '0.02%')),
          isFalse);
      expect(exchange.approvals, isEmpty);
    });

    for (final (name, client) in [
      ('unreachable', () => MockClient((req) async {
            if (req.url.path == '/api/v1/hl/builder') {
              throw http.ClientException('down');
            }
            return http.Response('0', 200);
          })),
      ('404', () => MockClient((req) async => http.Response('', 404))),
      ('invalid', () => MockClient((req) async => http.Response(
          jsonEncode(_config(address: '0x0000000000000000000000000000000000000000')),
          200))),
    ]) {
      test('backend $name: no builder, nothing to approve, never blocks',
          () async {
        final exchange = _FakeExchange();
        final c = client();
        expect(await ensure(exchange, c), isTrue);
        expect(
            await withBackend(
                () => HyperliquidOnboardingService.hasApprovedBuilderFee(
                    'wallet-1'),
                c),
            isTrue);
        expect(await withBackend(() => ledgerHlBuilderFeeApproved(_user), c),
            isTrue);
        expect(exchange.approvals, isEmpty);
        expect(infoQueries, isEmpty);
      });
    }

    test('a rotated builder is unapproved and is approved again', () async {
      final exchange = _FakeExchange();
      // First builder approved and recorded.
      final clientA = backend(_config());
      final a = await withBackend(HyperliquidFundingService.getBuilder, clientA);
      expect(await ensure(exchange, clientA, reviewed: a), isTrue);

      // The backend rotates (a new policy revision drops the cached one).
      HyperliquidFundingService.resetBuilderCacheForTest();
      infoQueries.clear();
      final clientB =
          backend(_config(address: _builderB), approvedFor: {_builderA: 10});
      final b = await withBackend(HyperliquidFundingService.getBuilder, clientB);
      expect(b!.builderAddress, _builderB);
      expect(
          await withBackend(
              () => HyperliquidOnboardingService.hasApprovedBuilderFee(
                  'wallet-1'),
              clientB),
          isFalse);
      // The Ledger check asks the venue about the new address only.
      expect(
          await withBackend(
              () => ledgerHlBuilderFeeApproved(_user, builder: b), clientB),
          isFalse);
      expect(infoQueries.single['builder'], _builderB);

      // Approval runs again for the new builder, like the first time.
      expect(await ensure(exchange, clientB, reviewed: b), isTrue);
      expect(exchange.approvals.map((a) => a.builder), [_builderA, _builderB]);
      expect(
          await withBackend(
              () => HyperliquidOnboardingService.hasApprovedBuilderFee(
                  'wallet-1'),
              clientB),
          isTrue);
      // Orders now carry the rotated address.
      expect(b.asOrderFee.address, _builderB);
    });

    test('a legacy bare approval flag proves nothing about the builder',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          {'hl_builder_approved_wallet-1': 'true'});
      expect(
          await withBackend(
              () => HyperliquidOnboardingService.hasApprovedBuilderFee(
                  'wallet-1'),
              backend(_config())),
          isFalse);
    });

    test('changed fee settings cannot reuse an earlier review', () async {
      final exchange = _FakeExchange();
      final approved = await ensure(
          exchange, backend(_config(fee: 30, rate: '0.03%')),
          reviewed: const HlBuilderInfo(
              builderAddress: _builderA,
              defaultFeeTenthsBp: 20,
              maxFeeRate: '0.02%'));
      expect(approved, isFalse);
      expect(exchange.approvals, isEmpty);
    });
  });
}
