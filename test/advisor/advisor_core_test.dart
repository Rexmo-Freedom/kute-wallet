import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/auth_provider.dart' show appLockedProvider;
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/advisor_local_stub.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';
import 'package:kute/services/tracking_service.dart';

class _StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final void Function()? onClose;
  bool closed = false;
  _StreamingClient(this.handler, {this.onClose});
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closed = true;
    onClose?.call();
  }
}

const _context = AdvisorContext(
    surface: 'hl_order_slip',
    marketVenue: 'hyperliquid',
    marketId: 'xyz:NVDA',
    orderType: 'limit');
const _response = AdvisorResponse(blocks: [
  AdvisorBlock(
      id: 'a', kind: AdvisorBlockKind.answer, markdown: 'A public explanation.')
]);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily quota carries reset time and a per-question idempotency key',
      () async {
    final ids = <String>[];
    final reset = DateTime.utc(2026, 9, 23);
    final transport = AdvisorTransport(
        baseUrl: 'https://backend.test',
        sessionToken: 'session',
        clientFactory: () => _StreamingClient((request) async {
              ids.add(request.headers['X-Idempotency-Key']!);
              return http.StreamedResponse(
                  Stream.value(utf8.encode(jsonEncode({
                    'error': 'ai_daily_limit',
                    'remaining': 0,
                    'resetAt': reset.toIso8601String(),
                  }))),
                  429,
                  headers: {'retry-after': '3600'});
            }));
    for (var i = 0; i < 2; i++) {
      await expectLater(
          transport
              .stream(
                  request:
                      const AdvisorRequest(query: 'What is a limit order?'),
                  cancellation: AdvisorCancellation())
              .toList(),
          throwsA(isA<AdvisorRateLimitedException>()
              .having((e) => e.daily, 'daily quota', isTrue)
              .having((e) => e.resetAt, 'reset', reset)
              .having((e) => e.retryAfter, 'retry', const Duration(hours: 1))));
    }
    expect(
        ids[0],
        matches(RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$')));
    expect(ids[0], isNot(ids[1]));
  });

  test('offline wallet questions give actual Kute steps, never a perp card',
      () {
    final receive =
        AdvisorLocalStub.respond('How do I receive bitcoin in lightning?');
    expect(
        receive.blocks.single.markdown, contains('Request a specific amount'));
    expect(receive.blocks.single.markdown, contains('Create request'));
    expect(receive.blocks.single.markdown, contains('spending wallet'));
    final send =
        AdvisorLocalStub.respond('How do people actually buy or send Bitcoin?');
    expect(send.blocks.single.markdown, contains('Send to'));
    expect(send.blocks.single.markdown, contains('Purchase on Home'));
    expect(send.blocks.single.card, isNull);
  });

  test('v3 wire body contains only submitted text, safe history and public id',
      () async {
    final body = await const AdvisorRequest(
        query: 'What is a limit order?',
        context: _context,
        prompt: AdvisorPrompt.typed(),
        history: [
          {'role': 'system', 'content': 'should never reach the server'},
          {
            'role': 'user',
            'content': 'What is funding?',
            'walletId': 'private'
          },
          {'role': 'assistant', 'content': 'Funding is a periodic payment.'},
          {'role': 'user', 'content': 'My balance is 1234 USD'},
        ]).toJson();
    expect(body.keys.toSet(),
        {'schemaVersion', 'query', 'market', 'education', 'history', 'prompt'});
    expect(body['schemaVersion'], '3');
    expect(body['prompt'], {'source': 'typed'});
    expect(body['market'], {'venue': 'hyperliquid', 'id': 'xyz:NVDA'});
    expect(body['education'], {'orderType': 'limit'});
    expect(body['history'], [
      {'role': 'user', 'content': 'What is funding?'},
      {'role': 'assistant', 'content': 'Funding is a periodic payment.'},
    ]);
    expect(jsonEncode(body), isNot(contains('hl_order_slip')));
  });

  test('private inputs and bare recovery phrases are rejected before transport',
      () async {
    for (final query in [
      'My balance is 3000 USD',
      'I own 2 BTC',
      'Email me at somebody@example.com',
      'What is at 0x1234567890123456789012345678901234567890',
      'my seed phrase is test test test',
      'xai-abcdefghijklmnopqrstuv',
      'xprvabcdefghijklmnopqrstuvwxyz1234567890',
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    ]) {
      await expectLater(AdvisorRequest(query: query).toJson(),
          throwsA(isA<AdvisorPrivateInputException>()));
    }
    expect(
        await AdvisorInputGuard.isSafe('What is a recovery phrase?'), isTrue);
    expect(await AdvisorInputGuard.isSafe('What is Nancy Pelosi betting on?'),
        isTrue);
    expect(
        await AdvisorInputGuard.isSafe('What does 10x leverage mean?'), isTrue);
  });

  test('unrecognised and private market identifiers are not sent', () {
    expect(
        const AdvisorContext(
                surface: 'test', marketVenue: 'wallet', marketId: 'abc')
            .toRequestMarket,
        isNull);
    expect(
        const AdvisorContext(
                surface: 'test',
                marketVenue: 'hyperliquid',
                marketId: '0x1234567890123456789012345678901234567890')
            .toRequestMarket,
        isNull);
    expect(
        const AdvisorContext(
                surface: 'test',
                marketVenue: 'polymarket',
                marketId: 'will-it-rain')
            .toRequestMarket,
        {'venue': 'polymarket', 'id': 'will-it-rain'});
  });

  test('history is bounded and never accepts extra message properties',
      () async {
    final body = await AdvisorRequest(query: 'Explain funding', history: [
      for (var i = 0; i < 30; i++)
        {'role': 'user', 'content': 'Explain concept $i', 'account': 'secret'},
    ]).toJson();
    expect((body['history'] as List).length, 12);
    expect(jsonEncode(body), isNot(contains('account')));
  });

  test('local questions cover market and wallet surfaces', () {
    final en = l10nForLanguage('en');
    List<String> texts(AdvisorContext c) =>
        [for (final chip in SalChipCatalogue.select(c, en)) chip.text];
    const spot = AdvisorContext(
        surface: 'hl_market_detail',
        marketVenue: 'hyperliquid',
        marketId: 'PURR/USDC');
    expect(texts(spot), contains('What drives the price of PURR/USDC?'));
    expect(spot.toRequestMarket, {'venue': 'hyperliquid', 'id': 'PURR/USDC'});
    expect(texts(const AdvisorContext(surface: 'btc_tx_detail')).first,
        contains('confirmation'));
    expect(texts(const AdvisorContext(surface: 'backup')).join(' '),
        contains('recovery'));
  });

  test('SSE emits actual deltas before completion across split UTF-8 packets',
      () async {
    final network = StreamController<List<int>>();
    final events = <AdvisorStreamEvent>[];
    final done = AdvisorTransport.decodeEvents(network.stream)
        .listen(events.add)
        .asFuture<void>();
    final payload = utf8.encode('event: delta\ndata: {"text":"Hello £"}\n\n');
    final split = payload.indexOf(0xc2) + 1;
    network.add(payload.sublist(0, split));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    network.add(payload.sublist(split));
    await _until(() => events.length == 1);
    expect(events.single.text, 'Hello £');
    network.add(utf8.encode(
        'event: done\ndata: {"schemaVersion":"3","blocks":[{"id":"a","markdown":"Finished"}]}\n\n'));
    await done;
    expect(events.last.response!.blocks.single.markdown, 'Finished');
    await network.close();
  });

  test('SSE exposes only recognized progress phases and preserves the answer',
      () async {
    final events = await AdvisorTransport.decodeEvents(Stream.value(utf8.encode(
      'event: status\ndata: {"phase":"reading"}\n\n'
      'event: status\ndata: {"phase":"private","text":"not user copy"}\n\n'
      'event: status\ndata: {"phase":"connecting"}\n\n'
      'event: delta\ndata: {"text":"Hello"}\n\n'
      'event: status\ndata: {"phase":"checking"}\n\n'
      'event: done\ndata: {"schemaVersion":"3","blocks":[{"markdown":"Complete"}]}\n\n',
    ))).toList();
    expect(events.where((e) => e.progress != null).map((e) => e.progress), [
      AdvisorProgress.reading,
      AdvisorProgress.connecting,
      AdvisorProgress.checking,
    ]);
    expect(events.where((e) => e.text != null).single.text, 'Hello');
    expect(events.last.response!.blocks.single.markdown, 'Complete');
  });

  test('SSE requires v3 and reads only the error category, never its text',
      () async {
    final old = Stream.value(utf8.encode(
        'event: done\ndata: {"schemaVersion":"2","blocks":[{"id":"a","markdown":"Old"}]}\n\n'));
    await expectLater(AdvisorTransport.decodeEvents(old).toList(),
        throwsA(isA<AdvisorUnavailableException>()));
    for (final (data, category) in [
      ('{"category":"timeout"}', 'timeout'),
      ('{"category":"quota_unavailable"}', 'quota_unavailable'),
      ('{"category":"upstream_unavailable"}', 'upstream_unavailable'),
      ('{"error":"secret server content"}', 'upstream_unavailable'),
      ('{"category":"secret server content"}', 'upstream_unavailable'),
    ]) {
      final error = Stream.value(utf8.encode('event: error\ndata: $data\n\n'));
      await expectLater(
          AdvisorTransport.decodeEvents(error).toList(),
          throwsA(isA<AdvisorServerErrorException>()
              .having((e) => e.category, 'category', category)));
    }
  });

  test('SSE delivers the early market card before the streamed text', () async {
    final events = await AdvisorTransport.decodeEvents(Stream.value(utf8.encode(
      'event: status\ndata: {"phase":"reading"}\n\n'
      'event: card\ndata: {"block":{"id":"hl-BTC","kind":"market","title":"Bitcoin (BTC)","card":{"venue":"hyperliquid","id":"BTC","instrument":"crypto_perp","asOf":"2026-10-07T10:00:00Z","perp":{"markPx":65000}},"actions":[]}}\n\n'
      'event: card\ndata: {"block":{"id":"block-0","kind":"answer","markdown":"No card here"}}\n\n'
      'event: status\ndata: {"phase":"connecting"}\n\n'
      'event: delta\ndata: {"text":"BTC is up"}\n\n'
      'event: status\ndata: {"phase":"checking"}\n\n'
      'event: done\ndata: {"schemaVersion":"3","blocks":[{"id":"block-0","kind":"answer","markdown":"BTC is up 1.6%."}]}\n\n',
    ))).toList();
    expect([
      for (final e in events)
        e.progress != null
            ? 'status'
            : e.card != null
                ? 'card'
                : e.text != null
                    ? 'delta'
                    : 'done'
    ], [
      'status',
      'card',
      'status',
      'delta',
      'status',
      'done'
    ]);
    final card = events[1].card!;
    expect(card.id, 'hl-BTC');
    expect(card.kind, AdvisorBlockKind.market);
    expect(card.card!.perp!.markPx, 65000);
  });

  test('a non-streaming error body maps to its category', () async {
    for (final (status, category) in [
      (504, 'timeout'),
      (503, 'quota_unavailable'),
      (502, 'upstream_unavailable'),
    ]) {
      final transport = AdvisorTransport(
          baseUrl: 'https://kute.test',
          sessionToken: 'backend-only-auth',
          clientFactory: () => _StreamingClient((_) async =>
              http.StreamedResponse(
                  Stream.value(utf8.encode(jsonEncode({'error': category}))),
                  status,
                  headers: {'content-type': 'application/json'})));
      await expectLater(
          transport
              .stream(
                  request: const AdvisorRequest(query: 'Explain funding'),
                  cancellation: AdvisorCancellation())
              .toList(),
          throwsA(isA<AdvisorServerErrorException>()
              .having((e) => e.category, 'category', category)));
    }
  });

  test('HTTP stream asks for SSE and closes client after final response',
      () async {
    late _StreamingClient client;
    client = _StreamingClient((request) async {
      expect(request.headers['Accept'], 'text/event-stream');
      final json = jsonDecode((request as http.Request).body) as Map;
      expect(
          json.keys.toSet(), {'schemaVersion', 'query', 'market', 'education'});
      expect(json['education'], {'orderType': 'limit'});
      return http.StreamedResponse(
          Stream.value(utf8.encode(
              'event: done\ndata: {"schemaVersion":"3","blocks":[{"markdown":"Complete"}]}\n\n')),
          200,
          headers: {'content-type': 'text/event-stream'});
    });
    final transport = AdvisorTransport(
        baseUrl: 'https://kute.test',
        sessionToken: 'backend-only-auth',
        clientFactory: () => client);
    final result = await transport
        .stream(
            request: const AdvisorRequest(
                query: 'Explain funding', context: _context),
            cancellation: AdvisorCancellation())
        .toList();
    expect(result.single.response!.blocks.single.markdown, 'Complete');
    expect(client.closed, isTrue);
  });

  test('cancellation closes HTTP while waiting for headers', () async {
    final pending = Completer<http.StreamedResponse>();
    final client = _StreamingClient((_) => pending.future, onClose: () {
      if (!pending.isCompleted) {
        pending.completeError(const AdvisorUnavailableException());
      }
    });
    final cancellation = AdvisorCancellation();
    final transport = AdvisorTransport(
        baseUrl: 'https://kute.test',
        sessionToken: 'backend-only-auth',
        clientFactory: () => client);
    final stream = transport
        .stream(
            request: const AdvisorRequest(query: 'Explain funding'),
            cancellation: cancellation)
        .toList();
    final expectation =
        expectLater(stream, throwsA(isA<AdvisorUnavailableException>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cancellation.cancel();
    await expectation;
    expect(client.closed, isTrue);
  });

  test('model parses the typed card and ignores v2-only fields', () {
    final response = AdvisorResponse.fromJson({
      'schemaVersion': '3',
      'htmlTemplateVersion': '1',
      'followups': ['What next?'],
      'blocks': [
        {
          'id': 'block-0',
          'kind': 'answer',
          'markdown': 'A disclosed purchase.',
          'section': 'activity',
          'html': '<div>legacy</div>',
          'facts': ['Instrument: Perpetual'],
          'sources': [
            {'title': 'Disclosure', 'url': 'https://example.com/disclosure'},
            {'title': 'Invalid', 'url': 'javascript:alert(1)'}
          ],
          'transactionDate': '2026-08-01',
          'disclosureDate': '2026-09-01',
        },
        {
          'id': 'pm-ars-che',
          'kind': 'market',
          'title': 'Arsenal vs Chelsea',
          'section': 'predictions',
          'card': {
            'venue': 'polymarket',
            'id': 'ars-che',
            'slug': 'ars-che',
            'submarketId': '123',
            'instrument': 'prediction',
            'imageUrl': 'https://polymarket.com/x.png',
            'asOf': '2026-10-07T10:00:00Z',
            'closesAt': '2026-10-07T21:00:00Z',
            'outcomes': [
              {'id': '123', 'label': 'Arsenal', 'price': 0.61, 'delta24h': 0.04}
            ],
            'live': {
              'state': 'live',
              'home': 'Arsenal',
              'away': 'Chelsea',
              'score': '1-0'
            },
            'related': [
              {
                'venue': 'polymarket',
                'id': 'ars-che-btts',
                'title': 'Both teams score'
              }
            ],
            'resolutionRules': 'Full rules.',
          },
          'actions': [
            {
              'label': 'View market',
              'actionId': 'open_market_by_slug',
              'params': {'slug': 'ars-che'}
            }
          ],
        },
        {
          // A card without a known venue is no card, and nothing else here.
          'id': 'bad', 'kind': 'market', 'card': {'venue': 'kalshi', 'id': 'x'}
        },
      ],
    });
    expect(response.blocks, hasLength(2));
    final prose = response.blocks.first;
    expect(prose.kind, AdvisorBlockKind.answer);
    expect(prose.section, 'activity');
    expect(prose.sources.single.title, 'Disclosure');
    expect(prose.transactionDate, '2026-08-01');
    expect(prose.card, isNull);
    final market = response.blocks.last;
    expect(market.kind, AdvisorBlockKind.market);
    final card = market.card!;
    expect(card.key, 'polymarket:ars-che:123');
    expect(card.outcomes.single.label, 'Arsenal');
    expect(card.outcomes.single.delta24h, 0.04);
    expect(card.live!.score, '1-0');
    expect(card.related.single.title, 'Both teams score');
    expect(card.resolutionRules, 'Full rules.');
    expect(market.actions.single.params, {'slug': 'ars-che'});
  });

  test(
      'offline responder gives education without current facts or trading actions',
      () {
    final explanation =
        AdvisorLocalStub.respond('What is a limit order?', _context);
    expect(explanation.blocks.single.markdown, contains('may fill partly'));
    expect(explanation.blocks.single.actions, isEmpty);
    final research =
        AdvisorLocalStub.respond('What is Nancy Pelosi betting on?');
    expect(
        research.blocks.single.markdown, contains('cannot retrieve current'));
    expect(research.blocks.single.card, isNull);
  });

  group('conversation lifecycle', () {
    late ProviderContainer container;
    late List<StreamController<AdvisorStreamEvent>> streams;
    late List<AdvisorCancellation> cancellations;
    late List<AdvisorContext?> contexts;
    late List<List<Map<String, String>>> histories;
    late List<AdvisorPrompt?> prompts;
    late List<String?> locales;
    setUp(() {
      streams = [];
      cancellations = [];
      contexts = [];
      histories = [];
      prompts = [];
      locales = [];
      container = ProviderContainer(overrides: [
        advisorStreamRequestProvider.overrideWithValue(({
          required String query,
          AdvisorContext? context,
          List<Map<String, String>> history = const [],
          required AdvisorCancellation cancellation,
          String? locale,
          AdvisorPrompt? prompt,
        }) {
          final controller = StreamController<AdvisorStreamEvent>();
          streams.add(controller);
          cancellations.add(cancellation);
          contexts.add(context);
          histories.add(history);
          prompts.add(prompt);
          locales.add(locale);
          return controller.stream;
        })
      ]);
    });

    test('each question carries its prompt source, template and locale',
        () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final notifier = container.read(advisorSessionProvider.notifier);
      Future<void> answer(Future<void> pending) async {
        await _until(
            () => streams.length == prompts.length && streams.isNotEmpty);
        streams.last.add(const AdvisorStreamEvent.done(_response));
        await streams.last.close();
        await pending;
      }

      await answer(notifier.ask('Why is BTC moving today?',
          context: _context,
          input: 'suggested',
          template: 'hl.moving_today',
          chipIndex: 2,
          locale: 'de'));
      await answer(notifier.ask('Explain funding', locale: 'pt'));
      await answer(notifier.ask('What next?', input: 'followup', locale: 'ja'));
      // There is no follow-up source: anything not a chip is typed.
      expect(prompts, const [
        AdvisorPrompt.chip('hl.moving_today'),
        AdvisorPrompt.typed(),
        AdvisorPrompt.typed(),
      ]);
      expect(locales, ['de', 'pt', 'ja']);
      final asked = [
        for (final (name, params) in events)
          if (name == 'sal_question_asked') params!
      ];
      expect(asked, hasLength(3));
      expect(asked[0]['input'], 'suggested');
      expect(asked[0]['template'], 'hl.moving_today');
      expect(asked[0]['chip_index'], 2);
      for (final typed in asked.skip(1)) {
        expect(typed.keys, isNot(contains('template')));
        expect(typed.keys, isNot(contains('chip_index')));
      }
    });

    test('a template outside the allowlist never reaches analytics', () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final notifier = container.read(advisorSessionProvider.notifier);
      final pending = notifier.ask('Why?',
          input: 'suggested', template: 'my.private.thing', chipIndex: 0);
      await _until(() => streams.isNotEmpty);
      final params = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
      expect(params.keys, isNot(contains('template')));
      expect(params['chip_index'], 0);
      expect(prompts.single!.toJson(), {'source': 'chip'});
      notifier.cancel();
      await pending;
    });
    tearDown(() async {
      container.dispose();
      for (final stream in streams) {
        await stream.close();
      }
    });

    test('changing selected market or order type starts without stale history',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final first = notifier.ask('Explain limit orders', context: _context);
      await _until(() => streams.isNotEmpty);
      streams[0].add(const AdvisorStreamEvent.done(_response));
      await streams[0].close();
      await first;
      const selected = AdvisorContext(
          surface: 'hl_order_slip',
          marketVenue: 'hyperliquid',
          marketId: 'xyz:XYZ100',
          orderType: 'stop_market');
      final second =
          notifier.ask('How does this stop order work?', context: selected);
      await _until(() => streams.length == 2);
      expect(contexts.last, selected);
      expect(histories.last, isEmpty);
      expect(container.read(advisorSessionProvider).turns.length, 1);
      notifier.cancel();
      await second;
    });

    test('locking clears local messages and cancels the pending request',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final pending = notifier.ask('Explain funding');
      await _until(() => streams.isNotEmpty);
      container.read(appLockedProvider.notifier).state = true;
      await pending;
      expect(cancellations.single.isCancelled, isTrue);
      expect(container.read(advisorSessionProvider).turns, isEmpty);
      await notifier.ask('Explain leverage');
      expect(streams.length, 1);
      container.read(appLockedProvider.notifier).state = false;
      final next = notifier.ask('Explain leverage');
      await _until(() => streams.length == 2);
      expect(histories.last, isEmpty);
      notifier.cancel();
      await next;
    });

    test('separate app sessions never inherit each other’s chat history',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final first = notifier.ask('Explain funding');
      await _until(() => streams.isNotEmpty);
      streams.single.add(const AdvisorStreamEvent.done(_response));
      await streams.single.close();
      await first;
      final other = ProviderContainer(overrides: [
        advisorStreamRequestProvider.overrideWithValue(({
          required String query,
          AdvisorContext? context,
          List<Map<String, String>> history = const [],
          required AdvisorCancellation cancellation,
          String? locale,
          AdvisorPrompt? prompt,
        }) {
          expect(history, isEmpty);
          return Stream.value(const AdvisorStreamEvent.done(_response));
        }),
      ]);
      addTearDown(other.dispose);
      expect(other.read(advisorSessionProvider).turns, isEmpty);
      await other
          .read(advisorSessionProvider.notifier)
          .ask('Explain limit orders');
      expect(container.read(advisorSessionProvider).turns.single.query,
          'Explain funding');
      expect(other.read(advisorSessionProvider).turns.single.query,
          'Explain limit orders');
    });

    test(
        'renders partial response, swaps final blocks and preserves context in chat',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final first = notifier.ask('Explain funding', context: _context);
      await _until(() => streams.isNotEmpty);
      streams[0].add(const AdvisorStreamEvent.delta('Funding is'));
      await _until(() => container
          .read(advisorSessionProvider)
          .turns
          .last
          .partialText
          .isNotEmpty);
      expect(container.read(advisorSessionProvider).turns.last.loading, isTrue);
      streams[0].add(const AdvisorStreamEvent.done(_response));
      await streams[0].close();
      await first;
      expect(container.read(advisorSessionProvider).turns.last.partialText,
          isEmpty);
      expect(
          container
              .read(advisorSessionProvider)
              .turns
              .last
              .blocks
              .single
              .markdown,
          'A public explanation.');
      final second = notifier.ask('What is a limit order?');
      await _until(() => streams.length == 2);
      expect(contexts.last, same(_context));
      expect(histories.last.first['content'], 'Explain funding');
      streams[1].add(const AdvisorStreamEvent.done(_response));
      await streams[1].close();
      await second;
    });

    test(
        'clear aborts old request and its completion cannot overwrite new turn',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final first = notifier.ask('Explain funding', context: _context);
      await _until(() => streams.length == 1);
      notifier.clear();
      expect(cancellations[0].isCancelled, isTrue);
      await first;
      final second = notifier.ask('Explain limit orders');
      await _until(() => streams.length == 2);
      streams[0].add(const AdvisorStreamEvent.done(_response));
      await Future<void>.delayed(Duration.zero);
      expect(
          container.read(advisorSessionProvider).turns.single.loading, isTrue);
      expect(contexts.last, isNull);
      expect(histories.last, isEmpty);
      streams[1].add(const AdvisorStreamEvent.done(_response));
      await streams[1].close();
      await second;
      expect(container.read(advisorSessionProvider).turns.single.query,
          'Explain limit orders');
    });

    test(
        'private prompt never reaches transport and is excluded from conversation history',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      await notifier.ask('My balance is 100 USD');
      expect(streams, isEmpty);
      expect(container.read(advisorSessionProvider).turns.single.query,
          'Private details removed');
      final safe = notifier.ask('What is leverage?');
      await _until(() => streams.isNotEmpty);
      expect(histories.single, isEmpty);
      streams.single.add(const AdvisorStreamEvent.done(_response));
      await streams.single.close();
      await safe;
    });

    test(
        'the early card leads the turn, text streams under it, done keeps it once',
        () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      const card = AdvisorBlock(
          id: 'hl-BTC',
          kind: AdvisorBlockKind.market,
          markdown: '',
          card: AdvisorCard(
              venue: 'hyperliquid', id: 'BTC', instrument: 'crypto_perp'));
      final notifier = container.read(advisorSessionProvider.notifier);
      final pending = notifier.ask('Why is BTC moving?', context: _context);
      await _until(() => streams.isNotEmpty);
      AdvisorTurn turn() => container.read(advisorSessionProvider).turns.single;
      streams[0].add(const AdvisorStreamEvent.card(card));
      await _until(() => turn().card != null);
      expect(turn().loading, isTrue);
      streams[0]
          .add(const AdvisorStreamEvent.status(AdvisorProgress.connecting));
      streams[0].add(const AdvisorStreamEvent.delta('BTC is up'));
      await _until(() => turn().partialText.isNotEmpty);
      expect(turn().card, same(card));
      streams[0].add(const AdvisorStreamEvent.done(AdvisorResponse(blocks: [
        AdvisorBlock(
            id: 'block-0',
            kind: AdvisorBlockKind.answer,
            markdown: 'BTC is up 1.6%.'),
        card,
      ])));
      await streams[0].close();
      await pending;
      expect(turn().loading, isFalse);
      expect(turn().card, same(card));
      expect(turn().blocks.length, 2);
      expect(turn().blocksAfterCard.map((b) => b.id), ['block-0']);
      final received =
          events.firstWhere((e) => e.$1 == 'sal_answer_received').$2!;
      expect(received['market_cards'], 1);
      expect(received.keys, isNot(contains('has_followups')));
    });

    test('a backend error category reads as Sal unavailable', () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final notifier = container.read(advisorSessionProvider.notifier);
      final pending = notifier.ask('Who is Nancy Pelosi betting on?');
      await _until(() => streams.isNotEmpty);
      streams[0].addError(AdvisorServerErrorException('timeout'));
      await pending;
      final turn = container.read(advisorSessionProvider).turns.single;
      expect(turn.loading, isFalse);
      expect(turn.includeInHistory, isFalse);
      expect(turn.blocks.single.markdown, l10nForLanguage('en').salStubOffline);
      expect(
          events
              .firstWhere((e) => e.$1 == 'sal_answer_failed')
              .$2!['error_category'],
          'unavailable');
    });

    test('cancel retains readable partial response without resending it',
        () async {
      final notifier = container.read(advisorSessionProvider.notifier);
      final first = notifier.ask('Explain funding');
      await _until(() => streams.isNotEmpty);
      streams[0].add(const AdvisorStreamEvent.delta('Partial explanation'));
      await _until(() => container
          .read(advisorSessionProvider)
          .turns
          .single
          .partialText
          .isNotEmpty);
      notifier.cancel();
      await first;
      expect(
          container.read(advisorSessionProvider).turns.single.loading, isFalse);
      expect(
          container
              .read(advisorSessionProvider)
              .turns
              .single
              .blocks
              .single
              .markdown,
          contains('stopped before completion'));
      final second = notifier.ask('What is leverage?');
      await _until(() => streams.length == 2);
      expect(histories.last, isEmpty);
      streams[1].add(const AdvisorStreamEvent.done(_response));
      await streams[1].close();
      await second;
    });
  });
}
