// A dedicated connection for checks whose answer depends on the caller IP.
// Dispose it after the response or timeout so later checks open a new socket.

import 'dart:io' show HttpClient;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Opens a client whose first request starts a new connection.
typedef ConnectionOpener = http.Client Function();

abstract final class FreshConnection {
  /// How long a fresh connection may take to open. The caller's own
  /// timeout still bounds the whole request.
  static const Duration connectTimeout = Duration(seconds: 5);

  /// A client with an empty pool: its request opens a new connection.
  /// The caller closes it ([send] does).
  static http.Client open() {
    final zoned = http.Client();
    // Under runWithClient the factory returns the zone's client (a fake):
    // keep it.
    if (zoned is! IOClient) return zoned;
    zoned.close();
    return IOClient(HttpClient()
      ..connectionTimeout = connectTimeout
      // Nothing is kept for a later request.
      ..idleTimeout = Duration.zero
      ..maxConnectionsPerHost = 1);
  }

  /// Runs [request] on a client from [connect] (a fresh one by default)
  /// and closes it afterwards, whether the request answered, failed or
  /// was abandoned by a timeout inside [request].
  static Future<T> send<T>(Future<T> Function(http.Client client) request,
      {ConnectionOpener? connect}) async {
    final client = (connect ?? open)();
    try {
      return await request(client);
    } finally {
      client.close();
    }
  }
}

/// Test seam: [inner] lent out as a "fresh" client that the borrower may
/// close without closing [inner], so a test's single fake answers every
/// fresh connection a service opens.
class BorrowedClient extends http.BaseClient {
  BorrowedClient(this.inner);
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() {}
}
