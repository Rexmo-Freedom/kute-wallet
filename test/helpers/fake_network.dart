// test/helpers/fake_network.dart
//
// One fake network for a test body. The remaining top-level `http.get` /
// `http.post` call sites reach it through `http.runWithClient`; the call
// sites on the shared keep-alive client ([SharedHttpClient]) never build a
// client of their own, so `runWithClient` cannot reach them, and they get
// the same fake through [SharedHttpClient.debugOverride] for the length of
// the body.

import 'package:http/http.dart' as http;
import 'package:kute/services/http/shared_http_client.dart';

/// Runs [body] with every HTTP request, pooled or one-off, answered by a
/// client from [client]. The shared-client override is restored afterwards.
Future<T> withFakeNetwork<T>(
    Future<T> Function() body, http.Client Function() client) async {
  final previous = SharedHttpClient.debugOverride;
  SharedHttpClient.debugOverride = client();
  try {
    return await http.runWithClient(body, client);
  } finally {
    SharedHttpClient.debugOverride = previous;
  }
}
