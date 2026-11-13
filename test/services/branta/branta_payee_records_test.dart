// The payee a send went to, kept with the payment
// (services/branta/branta_payee_records.dart): a send confirmed with a
// payee Branta VERIFIED on screen stores its name, logo URL, when and the
// rail under the payment's ids, once; a tampered or unknown answer, or
// none, stores nothing; the records come back after a restart; nothing
// but those four fields is written (never the address, the code or the
// secret) and nothing reaches analytics.

import 'dart:convert';
import 'dart:io';

import 'package:branta/branta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/branta/branta_payee_records.dart';
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/tracking_service.dart';

const _logo = 'https://branta.pro/logos/strike.png';
const _strike = BrantaPayee.verified(name: 'Strike', logoUrl: _logo);

void main() {
  late Directory dir;
  final prefetched = <String>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('branta_payees');
    Hive.init(dir.path);
    await Hive.openBox<String>(BrantaPayeeRecordStore.boxName);
    BrantaPayeeRecords.debugPrefetchLogo = (url) async => prefetched.add(url);
    prefetched.clear();
  });

  tearDown(() async {
    BrantaPayeeRecords.debugPrefetchLogo = null;
    TrackingService.debugTrackObserver = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  BrantaPayeeRecords notifier(ProviderContainer c) =>
      c.read(brantaPayeeRecordsProvider.notifier);

  test('a verified send stores the payee once, under every id it has',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final at = DateTime(2026, 11, 12, 15, 4);
    expect(
        await notifier(c).record(
            paymentIds: ['ord_1', 'op-1', null, ''],
            payee: _strike,
            rail: BrantaRail.usdcPolygon,
            at: at),
        isTrue);
    final record = c.read(brantaPayeeRecordsProvider)['ord_1']!;
    expect(record.name, 'Strike');
    expect(record.logoUrl, _logo);
    expect(record.verifiedAt, at);
    expect(record.rail, BrantaRail.usdcPolygon);
    expect(c.read(brantaPayeeRecordsProvider)['op-1'], record);
    expect(c.read(brantaPayeeRecordsProvider).length, 2);
    // The logo goes into the disk cache the rows draw from.
    expect(prefetched, [_logo]);

    // A second store for the same payment changes nothing.
    expect(
        await notifier(c).record(
            paymentIds: ['ord_1'],
            payee: const BrantaPayee.verified(name: 'Someone else'),
            rail: BrantaRail.usdcPolygon),
        isFalse);
    expect(c.read(brantaPayeeRecordsProvider)['ord_1'], record);
    expect(Hive.box<String>(BrantaPayeeRecordStore.boxName).length, 2);
  });

  test('tampered, unknown, no rail or no ids: nothing is stored', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = notifier(c);
    expect(
        await n.record(
            paymentIds: ['a'],
            payee: const BrantaPayee.tampered(),
            rail: BrantaRail.bitcoinOnchain),
        isFalse);
    expect(
        await n.record(
            paymentIds: ['b'], payee: null, rail: BrantaRail.lightning),
        isFalse);
    expect(
        await n.record(paymentIds: ['c'], payee: _strike, rail: null),
        isFalse);
    expect(
        await n.record(
            paymentIds: [null, ' '],
            payee: _strike,
            rail: BrantaRail.lightning),
        isFalse);
    expect(c.read(brantaPayeeRecordsProvider), isEmpty);
    expect(Hive.box<String>(BrantaPayeeRecordStore.boxName).isEmpty, isTrue);
    expect(prefetched, isEmpty);
  });

  test('only what Send showed as verified is kept (from memory, no lookup)',
      () async {
    var lookups = 0;
    final saved = BrantaPayeeService.shared;
    addTearDown(() => BrantaPayeeService.shared = saved);
    VerifyStatus answer = VerifyStatus.tampered;
    BrantaPayeeService.shared = BrantaPayeeService(verifier: (_) async {
      lookups++;
      return VerifyResult(status: answer, verifyUrl: '');
    });
    const invoice = 'lnbc10u1brantatestinvoice';
    // Nothing looked up yet: nothing to keep, and asking starts nothing.
    expect(brantaVerifiedPayeeShown(invoice, BrantaRail.lightning), isNull);
    expect(lookups, 0);
    // A tampered answer on screen: still nothing to keep.
    await BrantaPayeeService.shared.lookup(invoice, BrantaRail.lightning);
    expect(lookups, 1);
    expect(brantaVerifiedPayeeShown(invoice, BrantaRail.lightning), isNull);
    expect(brantaVerifiedPayeeShown(invoice, null), isNull);
    expect(lookups, 1);
  });

  test('records come back after a restart; a restored wallet has none',
      () async {
    final first = ProviderContainer();
    await notifier(first).record(
        paymentIds: ['ln-1'], payee: _strike, rail: BrantaRail.lightning);
    // Every stablecoin rail of branta 4.3.0 is kept by its name too.
    final stableRails = [
      BrantaRail.usdcEthereum,
      BrantaRail.usdtEthereum,
      BrantaRail.usdcBsc,
      BrantaRail.usdtBsc,
      BrantaRail.usdtTron,
      BrantaRail.usdcSolana,
      BrantaRail.usdtSolana,
    ];
    for (final rail in stableRails) {
      expect(
          await notifier(first).record(
              paymentIds: ['ord-${rail.name}'], payee: _strike, rail: rail),
          isTrue);
    }
    first.dispose();
    await Hive.close();

    // The next launch: the box opened again at boot.
    Hive.init(dir.path);
    await Hive.openBox<String>(BrantaPayeeRecordStore.boxName);
    final next = ProviderContainer();
    addTearDown(next.dispose);
    final r = next.read(brantaPayeeRecordsProvider)['ln-1'];
    expect(r?.name, 'Strike');
    expect(r?.logoUrl, _logo);
    expect(r?.rail, BrantaRail.lightning);
    for (final rail in stableRails) {
      expect(next.read(brantaPayeeRecordsProvider)['ord-${rail.name}']?.rail,
          rail);
    }

    // Another phone (nothing on disk): no record, the row as always.
    await Hive.deleteBoxFromDisk(BrantaPayeeRecordStore.boxName);
    await Hive.openBox<String>(BrantaPayeeRecordStore.boxName);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(restored.read(brantaPayeeRecordsProvider), isEmpty);
  });

  test('a record is the four fields only, and analytics hears nothing',
      () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await notifier(c).record(
        paymentIds: ['tx-1'], payee: _strike, rail: BrantaRail.bitcoinOnchain);
    final raw = Hive.box<String>(BrantaPayeeRecordStore.boxName).get('tx-1')!;
    expect((jsonDecode(raw) as Map).keys.toSet(),
        {'name', 'logo', 'verified_at', 'rail'});
    expect(raw, isNot(contains('secret')));
    expect(events, isEmpty);
  });

  test('a corrupt or foreign row is skipped; the store is bounded', () async {
    final box = Hive.box<String>(BrantaPayeeRecordStore.boxName);
    await box.put('bad', 'not json');
    await box.put('http', jsonEncode({
      'name': 'X',
      'logo': 'http://evil.example/x.png',
      'verified_at': 1,
      'rail': 'lightning',
    }));
    final all = BrantaPayeeRecordStore.readAll();
    expect(all.containsKey('bad'), isFalse);
    // An http logo is never drawn.
    expect(all['http']?.logoUrl, isNull);

    final c = ProviderContainer();
    addTearDown(c.dispose);
    for (var i = 0; i < BrantaPayeeRecordStore.maxEntries + 5; i++) {
      await notifier(c).record(
          paymentIds: ['p$i'],
          payee: _strike,
          rail: BrantaRail.lightning,
          at: DateTime(2026, 1, 1).add(Duration(minutes: i)));
    }
    expect(box.length, BrantaPayeeRecordStore.maxEntries);
    expect(box.containsKey('p0'), isFalse);
    expect(box.containsKey('p${BrantaPayeeRecordStore.maxEntries + 4}'),
        isTrue);
  });
}
