// Event-by-slug reads go to Gamma `GET /events/slug/{slug}`, which returns
// the event object itself. The offset `GET /events?slug=` list answered
// `deprecation: true` with a 2026-05-01 sunset. The fixture is a live
// `/events/slug/cs2-ts7-m80-2026-10-07` response read on 2026-10-07,
// trimmed to three markets; the 404 body is Gamma's own.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';

String _fixture(String name) =>
    File('test/fixtures/polymarket_gamma/$name').readAsStringSync();

const _slug = 'cs2-ts7-m80-2026-10-07';

Future<T> _with<T>(MockClient client, Future<T> Function() body) =>
    http.runWithClient(body, () => client);

void main() {
  test('reads the event from /events/slug/{slug}', () async {
    final seen = <Uri>[];
    final event = await _with(MockClient((request) async {
      seen.add(request.url);
      return http.Response(_fixture('events_slug_cs2_ts7_m80.json'), 200);
    }), () => PolymarketModel().getEventDetailsBySlug(_slug));

    expect(seen, hasLength(1));
    expect(seen.single.host, 'gamma-api.polymarket.com');
    expect(seen.single.path, '/events/slug/$_slug');
    expect(seen.single.queryParameters, isEmpty);

    expect(event, isNotNull);
    expect(event!.id, '1145394');
    expect(event.slug, _slug);
    expect(event.title,
        'Counter-Strike: Spirit vs M80 (BO3) - ESL Pro League Group Stage');
    expect(event.teams.map((t) => t.name), ['Spirit', 'M80']);
    expect(event.outcomes, isNotEmpty);
  });

  test('team crests come from the same route', () async {
    final teams = await _with(
        MockClient((_) async =>
            http.Response(_fixture('events_slug_cs2_ts7_m80.json'), 200)),
        () => PolymarketModel().fetchEventTeams(_slug));
    expect(teams.map((t) => t.abbreviation), ['ts7', 'm80']);
    expect(teams.map((t) => t.ordering), ['home', 'away']);
  });

  test('a 404 reads as no event', () async {
    final client = MockClient((_) async =>
        http.Response(_fixture('events_slug_not_found.json'), 404));
    expect(
        await _with(client, () => PolymarketModel().getEventDetailsBySlug('x')),
        isNull);
    expect(await _with(client, () => PolymarketModel().fetchEventTeams('x')),
        isEmpty);
  });

  test('a server error or a list body reads as no event', () async {
    expect(
        await _with(MockClient((_) async => http.Response('down', 503)),
            () => PolymarketModel().getEventDetailsBySlug(_slug)),
        isNull);
    // The old list shape is not the slug route's answer.
    expect(
        await _with(MockClient((_) async => http.Response('[]', 200)),
            () => PolymarketModel().getEventDetailsBySlug(_slug)),
        isNull);
  });

  test('the slug is path-encoded', () async {
    Uri? seen;
    await _with(MockClient((request) async {
      seen = request.url;
      return http.Response('{}', 404);
    }), () => PolymarketModel().getEventDetailsBySlug('a b/c'));
    expect(seen!.path, '/events/slug/a%20b%2Fc');
  });
}
