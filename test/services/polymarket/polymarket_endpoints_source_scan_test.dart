// Source scan for Polymarket endpoints that are being shut down:
//   * the previous live-data socket (`ws-live-data.polymarket.com`) and
//     its price topics, whose price topics are removed around
//     2026-10-23 (https://docs.polymarket.com/migrate/rtds-to-polybolt);
//     reference prices come from PolyBolt only;
//   * Data API v1, retired 2026-10-24
//     (https://docs.polymarket.com/migrate/data-api-v1-to-v2); every
//     Data API read is a `/v2/` route (`/v1/accounting/snapshot` is the
//     one route that stays on v1);
//   * Gamma's offset `GET /events` and `GET /markets` lists, which answer
//     `deprecation: true` with `sunset: Fri, 01 May 2026` and point at
//     `/events/keyset` / `/markets/keyset`. Lists use the keyset routes;
//     a single event or market by slug uses `/events/slug/{slug}` or
//     `/markets/slug/{slug}`.
//
// Scans every Dart file the app or its tooling ships: lib/, tool/,
// integration_test/ and test/ (so a live audit test cannot keep a
// retired route either).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(List<String> roots) sync* {
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('.dart')) yield e;
    }
  }
}

const _roots = ['lib', 'tool', 'integration_test', 'test'];
const _self = 'polymarket_endpoints_source_scan_test.dart';

void main() {
  test('no code talks to the retired live-data socket or its price topics', () {
    final banned = <RegExp>[
      RegExp(r'ws-live-data\.polymarket\.com'),
      RegExp(r'(?<!ws-)live-data\.polymarket\.com'),
      RegExp(
          r'''['"]crypto_prices(_chainlink|_twap_sixty|_twap_thirty)?['"]'''),
      RegExp(r'''['"]equity_prices['"]'''),
    ];
    final hits = <String>[];
    for (final f in _dartFiles(_roots)) {
      if (f.path.endsWith(_self)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final re in banned) {
          if (re.hasMatch(lines[i]))
            hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'Reference prices come from PolyBolt '
            '(wss://ws-live-v2.polymarket.com/ws) only.');
  });

  test('the PolyBolt endpoint is the one reference-price socket', () {
    final src = File('lib/services/polymarket/polybolt_price_socket.dart')
        .readAsStringSync();
    expect(src, contains("'wss://ws-live-v2.polymarket.com/ws'"));
  });

  test('every Data API call is a v2 route', () {
    // Literal URLs: https://data-api.polymarket.com/<path>
    final literal = RegExp(r'data-api\.polymarket\.com(/[^\s' "'" r'"`)]*)?');
    // Uri.https('data-api.polymarket.com', '/path') or via a host constant.
    final uriHttps = RegExp(
        r'''Uri\.https\(\s*(?:'data-api\.polymarket\.com'|_dataApi)\s*,\s*'([^']*)'\s*''');
    // '$_dataApiBase/...' anywhere except the v2 base constant itself.
    final base = RegExp(r'\$_dataApiBase(/[^\s' "'" r']*)');
    bool allowed(String path) =>
        path.startsWith('/v2/') ||
        path == '/v2' ||
        path.startsWith('/v1/accounting/snapshot');
    final hits = <String>[];
    for (final f in _dartFiles(_roots)) {
      if (f.path.endsWith(_self)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final m in literal.allMatches(line)) {
          final path = m.group(1);
          if (path != null && !allowed(path)) {
            hits.add('${f.path}:${i + 1}: ${line.trim()}');
          }
        }
        for (final m in uriHttps.allMatches(line)) {
          if (!allowed(m.group(1)!))
            hits.add('${f.path}:${i + 1}: ${line.trim()}');
        }
        for (final m in base.allMatches(line)) {
          if (!allowed(m.group(1)!))
            hits.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: 'Data API v1 is retired on 2026-10-24.');
  });

  test('no code reads the sunset Gamma offset /events or /markets lists', () {
    // Literal URLs: https://gamma-api.polymarket.com/events (no sub-path).
    final literal =
        RegExp(r'gamma-api\.polymarket\.com/(events|markets)(?![/\w-])');
    // Uri.https('gamma-api.polymarket.com', '/markets', ...) or via a host
    // constant.
    final uriHttps = RegExp(
        r'''Uri\.https\(\s*(?:'gamma-api\.polymarket\.com'|_gamma)\s*,\s*'/(events|markets)/?' '''
        r'''?\s*[,)]''');
    // '$_gammaBase/events' or '$_gammaBase/$resource' without a sub-path.
    final base = RegExp(
        r'\$_gammaBase/(events|markets|\$resource|\$\{resource\})(?![/\w-])');
    final hits = <String>[];
    for (final f in _dartFiles(_roots)) {
      if (f.path.endsWith(_self)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (literal.hasMatch(line) ||
            uriHttps.hasMatch(line) ||
            base.hasMatch(line)) {
          hits.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'Gamma sunset GET /events and GET /markets on 2026-05-01: '
            'use /events/keyset, /markets/keyset or /{events,markets}/slug/.');
  });

  test('the Gamma scan catches each list shape it bans', () {
    // Guards the scan's own patterns against drifting into matching
    // nothing.
    final literal =
        RegExp(r'gamma-api\.polymarket\.com/(events|markets)(?![/\w-])');
    expect(
        literal.hasMatch("'https://gamma-api.polymarket.com/events')"), isTrue);
    expect(literal.hasMatch('gamma-api.polymarket.com/markets?id=1'), isTrue);
    expect(literal.hasMatch('gamma-api.polymarket.com/events?slug=x'), isTrue);
    expect(literal.hasMatch('gamma-api.polymarket.com/events/keyset'), isFalse);
    expect(literal.hasMatch('gamma-api.polymarket.com/events/slug/x'), isFalse);
    expect(literal.hasMatch('gamma-api.polymarket.com/events/1/tweet-count'),
        isFalse);
    final uriHttps = RegExp(
        r'''Uri\.https\(\s*(?:'gamma-api\.polymarket\.com'|_gamma)\s*,\s*'/(events|markets)/?' '''
        r'''?\s*[,)]''');
    expect(uriHttps.hasMatch("Uri.https(_gamma, '/markets', {"), isTrue);
    expect(
        uriHttps.hasMatch("Uri.https('gamma-api.polymarket.com', '/events')"),
        isTrue);
    expect(
        uriHttps.hasMatch("Uri.https(_gamma, '/markets/keyset', {"), isFalse);
  });
}
