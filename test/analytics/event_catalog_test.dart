// Docs follow code: the analytics event catalog is checked in and must
// match what lib/ can send. Adding, renaming or removing an event without
// updating test/analytics/event_catalog.txt (and the Notion catalog it
// mirrors) fails here.
//
// Regenerate the list with `dart run tool/analytics_events.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'event_catalog_extractor.dart';

const _catalogPath = 'test/analytics/event_catalog.txt';
const _notionNote = 'Update test/analytics/event_catalog.txt AND the Notion '
    'PostHog catalog (Kute docs -> PostHog -> Events pages) for these '
    'events.';

void main() {
  late CatalogScan scan;

  setUpAll(() {
    scan = scanAnalyticsEvents();
  });

  test('every event name is static enough to catalogue', () {
    expect(scan.filesScanned, greaterThan(100));
    expect(scan.events.length, greaterThan(500));
    expect(scan.unresolved, isEmpty,
        reason: 'Event names must be string literals (a ternary of '
            'literals or a same-file const is fine) so the catalog can be '
            'derived from code. Unresolved:\n${scan.unresolved.join('\n')}');
  });

  test('lib/ sends exactly the events in $_catalogPath', () {
    final file = File(_catalogPath);
    expect(file.existsSync(), isTrue,
        reason:
            'Missing $_catalogPath. Run: dart run tool/analytics_events.dart');
    final catalogued =
        file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    expect(catalogued, equals(catalogued.toSet().toList()..sort()),
        reason: '$_catalogPath must be sorted with no duplicates.');

    final expected = catalogued.toSet();
    final added = scan.events.difference(expected).toList()..sort();
    final removed = expected.difference(scan.events).toList()..sort();
    if (added.isEmpty && removed.isEmpty) return;
    final lines = [
      'Analytics event catalog drift (${added.length} added, '
          '${removed.length} removed).',
      for (final n in added) '  + $n  (sent by lib/, not catalogued)',
      for (final n in removed) '  - $n  (catalogued, no longer sent)',
      _notionNote,
      'Regenerate the list with: dart run tool/analytics_events.dart',
    ];
    fail(lines.join('\n'));
  });

  test('no event name or property key names a raw secret or identifier', () {
    // Keys the service replaces with a one-way reference are exempt; the
    // set is read from the source so a removed entry is caught here.
    expect(scan.orderRefKeys, containsAll(['order_id', 'quote_id']));
    final hashed = scan.orderRefKeys;
    final badKeys = scan.propertyKeys
        .where((k) => isForbiddenKey(k, hashedKeys: hashed))
        .toList()
      ..sort();
    final badEvents = scan.events.where((e) => isForbiddenKey(e)).toList()
      ..sort();
    expect(badKeys, isEmpty,
        reason: 'Property keys that would carry a raw secret, address, '
            'invoice or order id. Send a category, a bucket or a hashed '
            'reference (TrackingService.orderRef) instead:\n'
            '${badKeys.join('\n')}');
    expect(badEvents, isEmpty,
        reason: 'Event names that read like a raw value:\n'
            '${badEvents.join('\n')}');
  });

  test('no event property names Kute revenue or a fee estimate', () {
    // Revenue reaches PostHog only from the database (warehouse sync). A
    // fee the user saw is UX analytics and is named fee_shown_*.
    final revenueLike = RegExp(
        r'(revenue|earning|commission|take_rate|markup|spread_estimate)'
        r'|^(fee_usd|fee_basis|fee_bucket)$');
    final keys = {...scan.propertyKeys};
    // Keys built by the shared helpers (moneyParams and friends) live in
    // the service and venue sources, outside any track(...) call.
    for (final path in [trackingServicePath, 'lib/services/venue_analytics.dart']) {
      final src = stripCommentsKeepingLines(File(path).readAsStringSync());
      keys.addAll(RegExp(r"""'([a-z0-9_]+)'\s*:(?!:)""")
          .allMatches(src)
          .map((m) => m.group(1)!));
    }
    final bad = keys.where(revenueLike.hasMatch).toList()..sort();
    expect(bad, isEmpty,
        reason: 'Event properties that read like Kute revenue or a fee '
            'estimate:\n${bad.join('\n')}');
    expect(keys, containsAll(['fee_shown_usd', 'fee_shown_basis']));
  });

  test('the forbidden-key rule is conservative', () {
    expect(isForbiddenKey('xpub'), isTrue);
    expect(isForbiddenKey('wallet_xpub'), isTrue);
    expect(isForbiddenKey('mnemonic'), isTrue);
    expect(isForbiddenKey('address'), isTrue);
    expect(isForbiddenKey('invoice'), isTrue);
    expect(isForbiddenKey('txid'), isTrue);
    expect(isForbiddenKey('funding_txid'), isTrue);
    expect(isForbiddenKey('order_id'), isTrue);
    expect(isForbiddenKey('order_id', hashedKeys: {'order_id'}), isFalse);
    // Categorical keys that merely mention the word are fine.
    expect(isForbiddenKey('address_type'), isFalse);
    expect(isForbiddenKey('has_address'), isFalse);
    expect(isForbiddenKey('invoice_type'), isFalse);
    expect(isForbiddenKey('seed_backup_state'), isFalse);
    expect(isForbiddenKey('wallets_without_address'), isFalse);
  });

  test('the scanner resolves ternaries, consts and money-flow overrides', () {
    final dir = Directory.systemTemp.createTempSync('event_catalog_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
const String kFlow = 'demo';
void f(bool ok) {
  // TrackingService.track('in_a_comment');
  TrackingService.track(ok ? 'demo_done' : 'demo_failed', params: {
    'reason': 'x', 'nested': {'txid': 'y'},
  });
  TrackingService.track(kFlow == 'demo' ? 'demo_a' : (ok ? 'demo_b' : 'demo_c'));
  TrackingService.moneyFlowStarted(kFlow, entrySource: 'tab',
      abandonEvent: 'demo_left');
  TrackingService.moneyFlowStep('demo', 'amount');
  TrackingService.moneyFlowSubmitted(kFlow, event: 'demo_sent');
  TrackingService.moneyFlowAbandoned(kFlow);
  VenueAnalytics.settingChanged('demo_setting_changed', setting: 's', value: 1);
  TrackingService.track(someVariable);
}
''');
    final s = scanAnalyticsEvents(lib: Directory('${dir.path}/lib'));
    expect(s.events, {
      'demo_done',
      'demo_failed',
      'demo_a',
      'demo_b',
      'demo_c',
      'demo_started',
      'demo_step',
      'demo_sent',
      'demo_left',
      'demo_setting_changed',
    });
    expect(s.propertyKeys, containsAll(['reason', 'nested', 'txid']));
    expect(s.unresolved, ['lib/a.dart:14: someVariable']);
  });
}
