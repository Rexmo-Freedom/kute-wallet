import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:kute/services/api/api_client.dart';

import '../mocks/mock_http_client.dart';

void main() {
  late MockHttpClient mockHttp;
  late ApiClient client;

  setUpAll(() {
    registerFallbackValue(FakeUri());
  });

  setUp(() {
    mockHttp = MockHttpClient();
    client = ApiClient('https://api.test', client: mockHttp);
  });

  group('ApiResponse', () {
    test('isSuccess true when data present and no error', () {
      final r = ApiResponse(data: 'ok', statusCode: 200);
      expect(r.isSuccess, isTrue);
    });

    test('isSuccess false when error present', () {
      final r = ApiResponse<String>(error: 'fail', statusCode: 400);
      expect(r.isSuccess, isFalse);
    });

    test('isSuccess false when data is null', () {
      final r = ApiResponse<String>(statusCode: 200);
      expect(r.isSuccess, isFalse);
    });
  });

  group('get', () {
    test('returns parsed data on 200', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({'key': 'value'}),
                200,
              ));

      final res = await client.get<Map<String, dynamic>>(
        '/test',
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, {'key': 'value'});
      expect(res.statusCode, 200);
    });

    test('returns error on 400', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('bad request', 400));

      final res = await client.get<String>('/test', (json) => json as String);

      expect(res.isSuccess, isFalse);
      expect(res.error, 'bad request');
      expect(res.statusCode, 400);
    });

    test('returns error on 500', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('server error', 500));

      final res = await client.get<String>('/test', (json) => json as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 500);
    });

    test('handles timeout', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 20));
        return http.Response('', 200);
      });

      final res = await client.get<String>('/test', (json) => json as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, isNotNull);
    });

    test('handles exception', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('network error'));

      final res = await client.get<String>('/test', (json) => json as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, contains('network error'));
    });

    test('passes custom headers', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>(
        '/test',
        (json) => json as String,
        headers: {'X-Custom': 'val'},
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['X-Custom'], 'val');
      expect(captured['Content-Type'], 'application/json');
    });
  });

  group('getRaw', () {
    test('returns raw body on 200', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('123456', 200));

      final res = await client.getRaw('/height');

      expect(res.isSuccess, isTrue);
      expect(res.data, '123456');
    });

    test('returns error on non-2xx', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('not found', 404));

      final res = await client.getRaw('/missing');

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 404);
    });
  });

  group('post', () {
    test('returns parsed data on 201', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({'id': 1}),
            201,
          ));

      final res = await client.post<Map<String, dynamic>>(
        '/create',
        {'name': 'test'},
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, {'id': 1});
    });

    test('sends JSON encoded body', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>('/create', {'key': 'val'}, (j) => j as String);

      final captured = verify(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured.single as String;

      expect(jsonDecode(captured), {'key': 'val'});
    });

    test('returns error on 400', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('invalid', 400));

      final res =
          await client.post<String>('/create', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 400);
    });
  });

  group('patch', () {
    test('returns parsed data on 200', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({'updated': true}),
            200,
          ));

      final res = await client.patch<Map<String, dynamic>>(
        '/update/1',
        {'name': 'new'},
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, {'updated': true});
    });

    test('returns error on 500', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('error', 500));

      final res =
          await client.patch<String>('/update/1', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 500);
    });

    test('handles exception', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('connection refused'));

      final res =
          await client.patch<String>('/update/1', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, contains('connection refused'));
    });
  });

  group('json parsing', () {
    test('parses list response', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode([1, 2, 3]),
                200,
              ));

      final res = await client.get<List<int>>(
        '/list',
        (json) => (json as List).cast<int>(),
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, [1, 2, 3]);
    });

    test('handles malformed JSON', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('not json{', 200));

      final res = await client.get<String>('/bad', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
    });

    test('parses nested object response', () async {
      final nested = {
        'user': {
          'name': 'Alice',
          'addresses': [
            {'city': 'Berlin'}
          ]
        }
      };
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode(nested), 200));

      final res = await client.get<Map<String, dynamic>>(
        '/nested',
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data!['user']['name'], 'Alice');
    });

    test('handles empty JSON object', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode({}), 200));

      final res = await client.get<Map<String, dynamic>>(
        '/empty',
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, isEmpty);
    });

    test('handles empty JSON array', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode([]), 200));

      final res = await client.get<List>(
        '/empty-list',
        (json) => json as List,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, isEmpty);
    });

    test('parser exception is caught and returned as error', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
              (_) async => http.Response(jsonEncode({'key': 'value'}), 200));

      final res = await client.get<int>(
        '/bad-parse',
        (json) => json as int, // will throw TypeError
      );

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, isNotNull);
    });

    test('handles malformed JSON in post response', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('{invalid json', 200));

      final res = await client.post<String>(
        '/bad-json',
        {'key': 'val'},
        (j) => j as String,
      );

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
    });

    test('handles malformed JSON in patch response', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('not-json', 200));

      final res = await client.patch<String>(
        '/bad-json',
        {'key': 'val'},
        (j) => j as String,
      );

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
    });
  });

  group('request building - URL construction', () {
    test('get builds correct full URL', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>('/users/42', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(captureAny(), headers: any(named: 'headers')),
      ).captured.single as Uri;

      expect(captured.toString(), 'https://api.test/users/42');
    });

    test('post builds correct full URL', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>('/items', {'a': 1}, (j) => j as String);

      final captured = verify(() => mockHttp.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Uri;

      expect(captured.toString(), 'https://api.test/items');
    });

    test('patch builds correct full URL', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.patch<String>('/items/5', {'a': 1}, (j) => j as String);

      final captured = verify(() => mockHttp.patch(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Uri;

      expect(captured.toString(), 'https://api.test/items/5');
    });

    test('getRaw builds correct full URL', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('raw', 200));

      await client.getRaw('/raw/path');

      final captured = verify(
        () => mockHttp.get(captureAny(), headers: any(named: 'headers')),
      ).captured.single as Uri;

      expect(captured.toString(), 'https://api.test/raw/path');
    });

    test('path with query parameters is preserved', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>(
          '/search?q=hello&page=2', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(captureAny(), headers: any(named: 'headers')),
      ).captured.single as Uri;

      expect(captured.toString(), 'https://api.test/search?q=hello&page=2');
    });
  });

  group('header management', () {
    test('default Content-Type header is always sent for get', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>('/test', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Content-Type'], 'application/json');
    });

    test('default Content-Type header is always sent for post', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>('/test', {}, (j) => j as String);

      final captured = verify(() => mockHttp.post(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['Content-Type'], 'application/json');
    });

    test('default Content-Type header is always sent for patch', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.patch<String>('/test', {}, (j) => j as String);

      final captured = verify(() => mockHttp.patch(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['Content-Type'], 'application/json');
    });

    test('custom headers override defaults', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>(
        '/test',
        (j) => j as String,
        headers: {'Content-Type': 'text/plain'},
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Content-Type'], 'text/plain');
    });

    test('constructor headers are included in all requests', () async {
      final clientWithHeaders = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {'X-Api-Key': 'secret123'},
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await clientWithHeaders.get<String>('/test', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['X-Api-Key'], 'secret123');
      expect(captured['Content-Type'], 'application/json');
    });

    test('per-request headers merge with constructor headers', () async {
      final clientWithHeaders = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {'X-Api-Key': 'secret123'},
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await clientWithHeaders.get<String>(
        '/test',
        (j) => j as String,
        headers: {'X-Request-Id': 'abc'},
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['X-Api-Key'], 'secret123');
      expect(captured['X-Request-Id'], 'abc');
      expect(captured['Content-Type'], 'application/json');
    });

    test('per-request headers override constructor headers', () async {
      final clientWithHeaders = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {'Authorization': 'Bearer old-token'},
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await clientWithHeaders.get<String>(
        '/test',
        (j) => j as String,
        headers: {'Authorization': 'Bearer new-token'},
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer new-token');
    });

    test('getRaw passes custom headers', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('raw', 200));

      await client.getRaw('/test', headers: {'Accept': 'text/plain'});

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Accept'], 'text/plain');
      expect(captured['Content-Type'], 'application/json');
    });

    test('post passes custom headers', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>(
        '/test',
        {},
        (j) => j as String,
        headers: {'X-Trace': 'trace-id'},
      );

      final captured = verify(() => mockHttp.post(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['X-Trace'], 'trace-id');
    });

    test('patch passes custom headers', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.patch<String>(
        '/test',
        {},
        (j) => j as String,
        headers: {'X-Trace': 'trace-id'},
      );

      final captured = verify(() => mockHttp.patch(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['X-Trace'], 'trace-id');
    });
  });

  group('auth token attachment', () {
    test('bearer token passed via constructor headers', () async {
      final authedClient = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {'Authorization': 'Bearer my-jwt-token'},
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await authedClient.get<String>('/secure', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer my-jwt-token');
    });

    test('bearer token passed via per-request headers on get', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>(
        '/secure',
        (j) => j as String,
        headers: {'Authorization': 'Bearer request-token'},
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer request-token');
    });

    test('bearer token passed via per-request headers on post', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>(
        '/secure',
        {'data': 1},
        (j) => j as String,
        headers: {'Authorization': 'Bearer post-token'},
      );

      final captured = verify(() => mockHttp.post(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer post-token');
    });

    test('bearer token passed via per-request headers on patch', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.patch<String>(
        '/secure',
        {'data': 1},
        (j) => j as String,
        headers: {'Authorization': 'Bearer patch-token'},
      );

      final captured = verify(() => mockHttp.patch(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured.single as Map<String, String>;

      expect(captured['Authorization'], 'Bearer patch-token');
    });

    test('no auth header when none provided', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.get<String>('/public', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured.containsKey('Authorization'), isFalse);
    });
  });

  group('error response handling', () {
    test('get returns error body for 401 unauthorized', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
              (_) async => http.Response('{"message":"unauthorized"}', 401));

      final res = await client.get<String>('/secure', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 401);
      expect(res.error, contains('unauthorized'));
      expect(res.data, isNull);
    });

    test('get returns error body for 403 forbidden', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('forbidden', 403));

      final res = await client.get<String>('/admin', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 403);
      expect(res.error, 'forbidden');
    });

    test('get returns error body for 404 not found', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('not found', 404));

      final res = await client.get<String>('/missing', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 404);
      expect(res.error, 'not found');
    });

    test('post returns error body for 409 conflict', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('duplicate entry', 409));

      final res =
          await client.post<String>('/create', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 409);
      expect(res.error, 'duplicate entry');
    });

    test('post returns error body for 422 unprocessable entity', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
              (_) async => http.Response('validation failed', 422));

      final res =
          await client.post<String>('/create', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 422);
      expect(res.error, 'validation failed');
    });

    test('patch returns error body for 404', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('resource not found', 404));

      final res =
          await client.patch<String>('/items/99', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 404);
      expect(res.error, 'resource not found');
    });

    test('getRaw returns error body for 503 service unavailable', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
              (_) async => http.Response('service unavailable', 503));

      final res = await client.getRaw('/health');

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 503);
      expect(res.error, 'service unavailable');
    });

    test('boundary: 299 is still success', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 299));

      final res = await client.get<String>('/test', (j) => j as String);

      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 299);
    });

    test('boundary: 300 is error', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('redirect', 300));

      final res = await client.get<String>('/test', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 300);
    });

    test('boundary: 199 is error', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('informational', 199));

      final res = await client.get<String>('/test', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 199);
    });

    test('error response body with empty string', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('', 500));

      final res = await client.get<String>('/test', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 500);
      expect(res.error, '');
    });
  });

  group('timeout handling', () {
    test('post handles timeout', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 20));
        return http.Response('', 200);
      });

      final res =
          await client.post<String>('/slow', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, isNotNull);
    });

    test('patch handles timeout', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 20));
        return http.Response('', 200);
      });

      final res =
          await client.patch<String>('/slow', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, isNotNull);
    });

    test('getRaw handles timeout', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 20));
        return http.Response('', 200);
      });

      final res = await client.getRaw('/slow');

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, isNotNull);
    });

    test('timeout error message contains timeout info', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 20));
        return http.Response('', 200);
      });

      final res = await client.get<String>('/slow', (j) => j as String);

      expect(res.error, isNotNull);
      expect(res.error!.toLowerCase(), contains('timeout'));
    });
  });

  group('exception handling across HTTP methods', () {
    test('get handles SocketException-like error', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('SocketException: Connection refused'));

      final res = await client.get<String>('/test', (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, contains('Connection refused'));
    });

    test('post handles exception', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('connection reset'));

      final res =
          await client.post<String>('/test', {}, (j) => j as String);

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, contains('connection reset'));
    });

    test('getRaw handles exception', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('DNS resolution failed'));

      final res = await client.getRaw('/test');

      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 0);
      expect(res.error, contains('DNS resolution failed'));
    });
  });

  group('request body serialization', () {
    test('post sends nested JSON body', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      final body = {
        'user': {
          'name': 'Alice',
          'tags': ['admin', 'user'],
        }
      };
      await client.post<String>('/users', body, (j) => j as String);

      final captured = verify(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured.single as String;

      final decoded = jsonDecode(captured);
      expect(decoded['user']['name'], 'Alice');
      expect(decoded['user']['tags'], ['admin', 'user']);
    });

    test('patch sends JSON encoded body', () async {
      when(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.patch<String>(
          '/update', {'status': 'active'}, (j) => j as String);

      final captured = verify(() => mockHttp.patch(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured.single as String;

      expect(jsonDecode(captured), {'status': 'active'});
    });

    test('post sends empty body', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>('/empty', {}, (j) => j as String);

      final captured = verify(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured.single as String;

      expect(jsonDecode(captured), {});
    });

    test('post sends list body', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await client.post<String>('/batch', [1, 2, 3], (j) => j as String);

      final captured = verify(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured.single as String;

      expect(jsonDecode(captured), [1, 2, 3]);
    });
  });

  group('2xx status code range', () {
    test('get succeeds with 200', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      final res = await client.get<String>('/test', (j) => j as String);
      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 200);
    });

    test('get succeeds with 201', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 201));

      final res = await client.get<String>('/test', (j) => j as String);
      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 201);
    });

    test('get succeeds with 204 and parseable body', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 204));

      final res = await client.get<String>('/test', (j) => j as String);
      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 204);
    });

    test('post succeeds with 201 created', () async {
      when(() => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
              (_) async => http.Response(jsonEncode({'id': 42}), 201));

      final res = await client.post<Map<String, dynamic>>(
        '/items',
        {'name': 'new'},
        (j) => j as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 201);
      expect(res.data!['id'], 42);
    });
  });

  group('ApiResponse properties', () {
    test('data is accessible when success', () {
      final r = ApiResponse(data: 42, statusCode: 200);
      expect(r.data, 42);
      expect(r.error, isNull);
    });

    test('error is accessible when failure', () {
      final r = ApiResponse<int>(error: 'boom', statusCode: 500);
      expect(r.error, 'boom');
      expect(r.data, isNull);
    });

    test('statusCode is always accessible', () {
      final success = ApiResponse(data: 'ok', statusCode: 200);
      final failure = ApiResponse<String>(error: 'fail', statusCode: 400);
      expect(success.statusCode, 200);
      expect(failure.statusCode, 400);
    });

    test('both data and error can be set simultaneously', () {
      final r = ApiResponse(data: 'ok', error: 'warn', statusCode: 200);
      expect(r.data, 'ok');
      expect(r.error, 'warn');
      // isSuccess is false because error is not null
      expect(r.isSuccess, isFalse);
    });
  });

  group('ApiClient construction', () {
    test('creates with default http client when none provided', () {
      // Should not throw
      final c = ApiClient('https://example.com');
      expect(c.baseUrl, 'https://example.com');
    });

    test('creates with custom headers via constructor', () async {
      final c = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {
          'X-App-Version': '1.0',
          'X-Platform': 'ios',
        },
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await c.get<String>('/test', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      expect(captured['X-App-Version'], '1.0');
      expect(captured['X-Platform'], 'ios');
      expect(captured['Content-Type'], 'application/json');
    });

    test('constructor custom headers do not overwrite Content-Type', () async {
      // Content-Type is set first, then ...?headers spreads, so custom wins
      final c = ApiClient(
        'https://api.test',
        client: mockHttp,
        headers: {'Content-Type': 'text/xml'},
      );

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode('ok'), 200));

      await c.get<String>('/test', (j) => j as String);

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, String>;

      // Spread operator: {'Content-Type': 'application/json', ...?headers}
      // means custom headers override the default
      expect(captured['Content-Type'], 'text/xml');
    });
  });
}
