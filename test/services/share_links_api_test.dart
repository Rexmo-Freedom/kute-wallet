// The share-links client against a fake backend (http MockClient): the
// routes, bodies and session headers it sends, what it makes of the
// answers, and how the pay-on-open pass and the deep-link parsing behave
// on top of it.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/app_router.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_link_claims.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';

import '../mocks/fake_share_links_api.dart';

/// A session sender that stamps a fixed bearer, like the real one after
/// the session is minted.
Future<http.Response> _withSession(
    String route, Future<http.Response> Function(Map<String, String>) send) {
  expect(route, 'share_links');
  return send({'Authorization': 'Bearer test-session'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TrackingService.setDisabled(true);
    ShareLinksStore.debugMemory = <String, String>{};
    ShareLinkClaims.debugReset();
  });

  tearDown(() {
    ShareLinksStore.debugMemory = null;
    ShareLinkClaims.debugPrompt = null;
  });

  group('BackendShareLinksApi', () {
    late List<http.Request> requests;
    late Map<String, http.Response Function(http.Request)> routes;
    late BackendShareLinksApi api;

    setUp(() {
      requests = [];
      routes = {};
      api = BackendShareLinksApi(
        baseUrl: 'https://backend.test',
        sessionSender: _withSession,
        client: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path}'
              '${request.url.hasQuery ? '?${request.url.query}' : ''}';
          final handler = routes[key];
          if (handler == null) return http.Response('{"error":"nope"}', 404);
          return handler(request);
        }),
      );
    });

    test('create posts kind, asset, amount, market and label with the session',
        () async {
      routes['POST /api/v1/share/links'] = (_) => http.Response(
          jsonEncode({
            'id': 'lnk_1',
            'url': 'https://web.test/c/lnk_1',
            'expiresAt': '2026-11-07T10:00:00Z',
          }),
          201);
      final created = await api.create(
        kind: ShareLinkKind.dollars,
        amountMinor: 1250,
        marketSlug: 'will-it-rain',
        senderLabel: ' João ',
      );
      expect(created.id, 'lnk_1');
      expect(created.url, 'https://web.test/c/lnk_1');
      expect(created.expiresAt, isNotNull);
      final req = requests.single;
      expect(req.headers['Authorization'], 'Bearer test-session');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(req.body), {
        'kind': 'dollars',
        'asset': 'USDB',
        'amountMinor': 1250,
        'marketSlug': 'will-it-rain',
        'senderLabel': 'João',
      });
    });

    test('create with a pick posts venue, outcome, outcomeIndex and side',
        () async {
      routes['POST /api/v1/share/links'] = (_) => http.Response(
          jsonEncode({'id': 'lnk_2', 'url': 'https://web.test/c/lnk_2'}),
          201);
      await api.create(
        kind: ShareLinkKind.dollars,
        amountMinor: 2000,
        marketSlug: 'gemini-carbon',
        venue: 'polymarket',
        outcome: ' Yes ',
        outcomeIndex: 0,
        side: 'buy',
      );
      expect(jsonDecode(requests.single.body), {
        'kind': 'dollars',
        'asset': 'USDB',
        'amountMinor': 2000,
        'marketSlug': 'gemini-carbon',
        'venue': 'polymarket',
        'outcome': 'Yes',
        'outcomeIndex': 0,
        'side': 'buy',
      });
    });

    test('read keeps the pick when the backend sends it, none otherwise',
        () async {
      routes['GET /api/v1/share/links/lnk_9'] = (_) => http.Response(
          jsonEncode({
            'id': 'lnk_9',
            'kind': 'dollars',
            'amountMinor': 2000,
            'marketSlug': 'gemini-carbon',
            'venue': 'polymarket',
            'outcome': 'Yes',
            'outcomeIndex': 0,
            'side': 'buy',
            'status': 'open',
          }),
          200);
      final link = await api.read('lnk_9');
      expect(link.hasPick, isTrue);
      expect(link.venue, 'polymarket');
      expect(link.outcome, 'Yes');
      expect(link.outcomeIndex, 0);
      expect(link.side, 'buy');
      final plain = ShareLink.fromJson({
        'id': 'lnk_8',
        'kind': 'dollars',
        'amountMinor': 100,
        'status': 'open',
      })!;
      expect(plain.hasPick, isFalse);
      expect(plain.outcomeIndex, isNull);
    });

    test('create for bitcoin sends BTC and leaves optional fields out',
        () async {
      routes['POST /api/v1/share/links'] = (_) => http.Response(
          jsonEncode({'id': 'lnk_2', 'url': 'https://web.test/c/lnk_2'}), 200);
      await api.create(kind: ShareLinkKind.bitcoin, amountMinor: 21000);
      expect(jsonDecode(requests.single.body),
          {'kind': 'bitcoin', 'asset': 'BTC', 'amountMinor': 21000});
    });

    test('read parses a link; unknown status and expiry are kept', () async {
      routes['GET /api/v1/share/links/lnk_1'] = (_) => http.Response(
          jsonEncode({
            'id': 'lnk_1',
            'kind': 'bitcoin',
            'asset': 'BTC',
            'amountMinor': 5000,
            'marketSlug': null,
            'senderLabel': 'Ana',
            'referralCode': 'KUTE42',
            'status': 'open',
            'expiresAt': '2099-01-01T00:00:00Z',
          }),
          200);
      final link = await api.read('lnk_1');
      expect(link.kind, ShareLinkKind.bitcoin);
      expect(link.amountMinor, 5000);
      expect(link.senderLabel, 'Ana');
      expect(link.referralCode, 'KUTE42');
      expect(link.status, ShareLinkStatus.open);
      expect(link.claimable, isTrue);
    });

    test('read: an expired link is not claimable', () async {
      routes['GET /api/v1/share/links/lnk_9'] = (_) => http.Response(
          jsonEncode({
            'id': 'lnk_9',
            'kind': 'dollars',
            'amountMinor': 100,
            'status': 'open',
            'expiresAt': '2020-01-01T00:00:00Z',
          }),
          200);
      final link = await api.read('lnk_9');
      expect(link.claimable, isFalse);
    });

    test('read: 404 is a ShareLinkApiException with the backend code',
        () async {
      routes['GET /api/v1/share/links/missing'] =
          (_) => http.Response(jsonEncode({'error': 'link_not_found'}), 404);
      expect(
        () => api.read('missing'),
        throwsA(isA<ShareLinkApiException>()
            .having((e) => e.notFound, 'notFound', isTrue)
            .having((e) => e.code, 'code', 'link_not_found')),
      );
    });

    test('claim posts the destination and returns the status', () async {
      routes['POST /api/v1/share/links/lnk_1/claim'] =
          (_) => http.Response(jsonEncode({'status': 'claimed'}), 200);
      final status = await api.claim('lnk_1', destination: 'spark1abc');
      expect(status, ShareLinkStatus.claimed);
      expect(jsonDecode(requests.single.body), {'destination': 'spark1abc'});
    });

    test('claimed reads mine?status=claimed and parses the rows', () async {
      routes['GET /api/v1/share/links/mine?status=claimed'] =
          (_) => http.Response(
              jsonEncode([
                {
                  'id': 'lnk_1',
                  'kind': 'dollars',
                  'asset': 'USDB',
                  'amountMinor': 1250,
                  'marketSlug': 'will-it-rain',
                  'claimDestination': 'spark1dest',
                  'claimedAt': '2026-10-31T09:00:00Z',
                },
                {'id': 'broken'},
              ]),
              200);
      final rows = await api.claimed();
      expect(rows, hasLength(1));
      expect(rows.single.claimDestination, 'spark1dest');
      expect(rows.single.marketSlug, 'will-it-rain');
      expect(rows.single.kind, ShareLinkKind.dollars);
    });

    test('paid and cancel post to their routes', () async {
      routes['POST /api/v1/share/links/lnk_1/paid'] =
          (_) => http.Response('{}', 200);
      routes['POST /api/v1/share/links/lnk_1/cancel'] =
          (_) => http.Response('{"status":"cancelled"}', 200);
      await api.markPaid('lnk_1', paymentId: 'pay_1');
      await api.cancel('lnk_1');
      expect(jsonDecode(requests.first.body), {'paymentId': 'pay_1'});
      expect(requests.last.url.path, '/api/v1/share/links/lnk_1/cancel');
    });

    test('a 409 on cancel is a conflict', () async {
      routes['POST /api/v1/share/links/lnk_1/cancel'] =
          (_) => http.Response(jsonEncode({'error': 'link_not_open'}), 409);
      expect(
        () => api.cancel('lnk_1'),
        throwsA(isA<ShareLinkApiException>()
            .having((e) => e.conflict, 'conflict', isTrue)),
      );
    });
  });

  group('ShareLinkClaims.claimIdFromLink', () {
    test('reads /c/{id} on the public web host', () {
      expect(
          ShareLinkClaims.claimIdFromLink(
              Uri.parse('https://backend.kutewallet.com/c/lnk_01HZX')),
          'lnk_01HZX');
    });

    test('reads the OneLink form', () {
      expect(
          ShareLinkClaims.claimIdFromLink(Uri.parse(
              'https://kute.onelink.me/abc?deep_link_value=claim&deep_link_sub1=lnk_7')),
          'lnk_7');
      expect(
          ShareLinkClaims.claimIdFromLink(Uri.parse(
              'kute://open?deep_link_value=claim&deep_link_sub1=lnk_8')),
          'lnk_8');
    });

    test('is null for referral links and odd ids', () {
      expect(
          ShareLinkClaims.claimIdFromLink(
              Uri.parse('kute://open?deep_link_value=KUTE42')),
          isNull);
      expect(
          ShareLinkClaims.claimIdFromLink(
              Uri.parse('https://backend.kutewallet.com/c/../etc')),
          isNull);
      expect(
          ShareLinkClaims.claimIdFromLink(
              Uri.parse('https://backend.kutewallet.com/c/')),
          isNull);
    });
  });

  group('AppRouter.claimLinkRedirect', () {
    test('unlocked: the Claim screen; locked: parked, no redirect', () {
      final uri = Uri.parse('https://backend.kutewallet.com/c/lnk_1');
      expect(AppRouter.claimLinkRedirect(uri, locked: false), '/claim/lnk_1');
      expect(ShareLinksStore.parkedClaimId, isNull);
      expect(AppRouter.claimLinkRedirect(uri, locked: true), isNull);
      expect(ShareLinksStore.parkedClaimId, 'lnk_1');
      expect(ShareLinksStore.takeParkedClaim(), 'lnk_1');
      expect(ShareLinksStore.parkedClaimId, isNull);
    });

    test('other links are untouched', () {
      expect(
          AppRouter.claimLinkRedirect(
              Uri.parse('kute://open?deep_link_value=KUTE42'),
              locked: false),
          isNull);
    });
  });

  group('ShareLinkClaims.check', () {
    testWidgets(
        'prompts for each claimed link, skips ones paid here, '
        'retries unreported payments', (tester) async {
      final fake = FakeShareLinksApi();
      fake.claimedForMe.addAll([
        const ClaimedShareLink(
            id: 'lnk_a',
            kind: ShareLinkKind.dollars,
            amountMinor: 1250,
            claimDestination: 'spark1a'),
        const ClaimedShareLink(
            id: 'lnk_b',
            kind: ShareLinkKind.bitcoin,
            amountMinor: 5000,
            claimDestination: 'lnbc1b'),
      ]);
      // lnk_b was paid on this device; the backend never heard.
      ShareLinksStore.put(PendingShareLink(
        id: 'lnk_b',
        kind: ShareLinkKind.bitcoin,
        amountMinor: 5000,
        url: 'https://web.test/c/lnk_b',
        createdAt: DateTime(2026, 10, 30),
        status: ShareLinkStatus.paid,
        paymentId: 'pay_b',
      ));
      final prompted = <String>[];
      ShareLinkClaims.debugPrompt = (context, claim) async {
        prompted.add(claim.id);
      };
      final container = ProviderContainer(
          overrides: [shareLinksApiProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      await ShareLinkClaims.check(
          read: container.read, contextOf: () => context, trigger: 'test');

      expect(fake.callNames, ['markPaid', 'claimed']);
      expect(fake.calls.first.$2, {'id': 'lnk_b', 'paymentId': 'pay_b'});
      expect(ShareLinksStore.byId('lnk_b')!.paidReported, isTrue);
      expect(prompted, ['lnk_a']);
      expect(ShareLinksStore.byId('lnk_a')!.status, ShareLinkStatus.claimed);

      // A second trigger inside the gap is ignored.
      await ShareLinkClaims.check(
          read: container.read, contextOf: () => context, trigger: 'test');
      expect(fake.callNames, ['markPaid', 'claimed']);
    });

    testWidgets('a backend failure is silent and the row stays claimed',
        (tester) async {
      final fake = FakeShareLinksApi();
      fake.failNext['claimed'] = const ShareLinkApiException(503);
      final container = ProviderContainer(
          overrides: [shareLinksApiProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);
      await ShareLinkClaims.check(
          read: container.read, contextOf: () => null, trigger: 'test');
      expect(fake.callNames, ['claimed']);
    });
  });
}
