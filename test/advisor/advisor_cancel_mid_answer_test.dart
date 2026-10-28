// Closing Sal while an answer is still streaming tears the HTTP connection
// down under the event stream. IOClient surfaces that as a ClientException
// ("Connection closed while receiving data"); on 2.1.x it escaped
// AdvisorCancellation.cancel and the cancelled subscription and was
// reported as uncaught, a fatal on iOS. Nobody is listening after a
// cancel, so the error ends inside the service and the provider.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/services/advisor/advisor_service.dart';
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

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a close that throws ends in AdvisorCancellation.cancel', () {
    final cancellation = AdvisorCancellation();
    cancellation.attach(() {
      throw http.ClientException('Connection closed while receiving data');
    });
    expect(cancellation.cancel, returnsNormally);
    expect(cancellation.isCancelled, isTrue);
    // Attaching after the cancel closes at once; a throw there ends too.
    expect(
        () => cancellation.attach(() => throw StateError('closed twice')),
        returnsNormally);
  });

  test('cancelling mid-answer swallows the closed connection error',
      () async {
    final body = StreamController<List<int>>();
    // Like IOClient: closing the client fails the response stream with
    // the connection error, synchronously from close().
    final client = _StreamingClient(
        (_) async => http.StreamedResponse(body.stream, 200,
            headers: {'content-type': 'text/event-stream'}), onClose: () {
      if (!body.isClosed) {
        body.addError(
            http.ClientException('Connection closed while receiving data'));
        body.close();
      }
    });
    final cancellation = AdvisorCancellation();
    final transport = AdvisorTransport(
        baseUrl: 'https://kute.test',
        sessionToken: 'backend-only-auth',
        clientFactory: () => client);
    final events = <AdvisorStreamEvent>[];
    final errors = <Object>[];
    final subscription = transport
        .stream(
            request: const AdvisorRequest(query: 'Explain funding'),
            cancellation: cancellation)
        .listen(events.add, onError: errors.add);
    await _until(() => body.hasListener);
    body.add(utf8.encode('event: delta\ndata: {"text":"Funding is"}\n\n'));
    await _until(() => events.isNotEmpty);

    // The sheet closes: the request is cancelled, then the subscription.
    cancellation.cancel();
    await expectLater(subscription.cancel(), completes);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(errors, isEmpty);
    expect(client.closed, isTrue);
    expect(events.single.text, 'Funding is');
  });

  test('the session notifier ignores what the cancelled stream throws',
      () async {
    TrackingService.setDisabled(true);
    final container = ProviderContainer(overrides: [
      advisorStreamRequestProvider.overrideWithValue(({
        required String query,
        AdvisorContext? context,
        List<Map<String, String>> history = const [],
        required AdvisorCancellation cancellation,
        String? locale,
        AdvisorPrompt? prompt,
      }) async* {
        yield const AdvisorStreamEvent.delta('Funding is');
        // The transport's await-for: a cancel closes the connection and
        // the stream resumes with the connection error after the
        // listener has already gone.
        final torn = Completer<void>();
        cancellation.attach(() => torn.completeError(
            http.ClientException('Connection closed while receiving data')));
        await torn.future;
      })
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(advisorSessionProvider.notifier);
    final pending = notifier.ask('Why is funding positive?');
    await _until(() => container
        .read(advisorSessionProvider)
        .turns
        .any((turn) => turn.partialText.isNotEmpty));

    notifier.cancel();
    await pending;
    // Whatever the torn-down stream threw during the cancel stays inside
    // the notifier; the test's zone sees no uncaught error.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(advisorSessionProvider).turns.single.loading,
        isFalse);
  });
}
