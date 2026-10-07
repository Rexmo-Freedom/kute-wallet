import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// How often the open count market refreshes its tally (polymarket.com
/// polls its tracker every 30 s; there is no push).
const Duration kPolyTweetCountRefresh = Duration(seconds: 30);

/// The running tally of a count market ("Elon Musk # of tweets"), read
/// from Gamma's undocumented `GET /events/{id}/tweet-count` every
/// [kPolyTweetCountRefresh] while a sheet shows it. Nothing is emitted when
/// a read fails — the sheet keeps the count the event arrived with — so the
/// endpoint going away fails silently.
final polyTweetCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, eventId) async* {
  if (int.tryParse(eventId) == null) return;
  final client = http.Client();
  var alive = true;
  ref.onDispose(() {
    alive = false;
    client.close();
  });
  final uri = Uri.parse(
      'https://gamma-api.polymarket.com/events/$eventId/tweet-count');
  while (alive) {
    final count = await readPolyTweetCount(client, uri);
    if (!alive) return;
    if (count != null) yield count;
    await Future<void>.delayed(kPolyTweetCountRefresh);
  }
});

/// One read of [uri]; null on any failure or an unexpected body.
Future<int?> readPolyTweetCount(http.Client client, Uri uri) async {
  try {
    final resp = await client.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body);
    final v = body is Map ? body['tweetCount'] : null;
    return v is num && v >= 0 ? v.toInt() : null;
  } catch (_) {
    return null;
  }
}

/// The bracket a count falls in, for count markets whose outcomes are
/// ranges ("<20", "20-39", "200+"). Null when [label] is not a range.
({int min, int? max})? polyCountBracket(String label) {
  final s = label.replaceAll(',', '').replaceAll('–', '-').trim();
  final lt = RegExp(r'^<\s*(\d+)$').firstMatch(s);
  if (lt != null) return (min: 0, max: int.parse(lt.group(1)!) - 1);
  final plus = RegExp(r'^(\d+)\s*\+$').firstMatch(s);
  if (plus != null) return (min: int.parse(plus.group(1)!), max: null);
  final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(s);
  if (range != null) {
    return (min: int.parse(range.group(1)!), max: int.parse(range.group(2)!));
  }
  return null;
}
