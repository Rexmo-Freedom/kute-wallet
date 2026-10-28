import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/http/fresh_connection.dart';

class _Client extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value([111, 107]), 200);
  @override
  void close() => closed = true;
}

void main() {
  test('fresh requests to the same server open distinct TCP connections',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ports = <int>[];
    server.listen((request) async {
      ports.add(request.connectionInfo!.remotePort);
      request.response.write('ok');
      await request.response.close();
    });
    try {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/policy');
      for (var i = 0; i < 2; i++) {
        expect((await FreshConnection.send((client) => client.get(uri))).body,
            'ok');
      }
      expect(ports.toSet(), hasLength(2));
    } finally {
      await server.close(force: true);
    }
  });

  test('a connection closes on success, failure and caller timeout', () async {
    final success = _Client();
    await FreshConnection.send(
        (client) => client.get(Uri.parse('http://example.test')),
        connect: () => success);
    expect(success.closed, isTrue);
    final failed = _Client();
    await expectLater(
        FreshConnection.send<void>((_) async => throw StateError('failed'),
            connect: () => failed),
        throwsStateError);
    expect(failed.closed, isTrue);
    final slow = _Client();
    await expectLater(
        FreshConnection.send<void>(
            (_) => Completer<void>()
                .future
                .timeout(const Duration(milliseconds: 10)),
            connect: () => slow),
        throwsA(isA<TimeoutException>()));
    expect(slow.closed, isTrue);
  });
}
