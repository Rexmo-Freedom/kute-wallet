// The device wipe deletes every app Hive box from one list. After it, no
// wiped box holds anything (gone from disk, or reopened empty for the
// startup set), the kept boxes keep their data, and a source scan keeps
// the list honest: every box name lib opens is wiped or listed as kept.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/hive_wipe.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import 'support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;
  late FakeKeychain keychain;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    hiveDir = await Directory.systemTemp.createTemp('hive_wipe');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  /// Whether [name] still holds anything. The wipe reopens the startup
  /// boxes (typed, empty), so an open box is read as whatever type it was
  /// opened with; a closed file on disk counts as data.
  Future<bool> holdsData(String name) async {
    if (!await Hive.boxExists(name)) return false;
    if (Hive.isBoxOpen(name)) {
      for (final probe in [
        () => Hive.box<dynamic>(name).isNotEmpty,
        () => Hive.box<String>(name).isNotEmpty,
        () => Hive.box<bool>(name).isNotEmpty,
        () => Hive.box<double>(name).isNotEmpty,
      ]) {
        try {
          return probe();
        } on HiveError {
          continue;
        }
      }
      fail('$name is open with an unexpected type');
    }
    return true;
  }

  test('the lists do not overlap and have no duplicates', () {
    expect(hiveBoxesWipedOnWipe.toSet().length, hiveBoxesWipedOnWipe.length);
    expect(hiveBoxesWipedOnWipe.toSet().intersection(hiveBoxesKeptOnWipe),
        isEmpty);
  });

  test('after a wipe no listed box holds anything; kept boxes keep theirs',
      () async {
    // Half the boxes stay open (as boot leaves them), half are closed
    // files on disk (opened on demand earlier, then closed).
    var i = 0;
    for (final name in hiveBoxesWipedOnWipe) {
      final box = await Hive.openBox<dynamic>(name);
      await box.put('k', 'v-$name');
      if ((i++).isOdd) await box.close();
    }
    for (final name in hiveBoxesKeptOnWipe) {
      final box = await Hive.openBox<dynamic>(name);
      await box.put('k', 'kept-$name');
    }
    keychain.seed('pin_hash', 'hash');

    await AuthModel().deleteAuthentication();

    for (final name in hiveBoxesWipedOnWipe) {
      if (name == 'settings') continue;
      expect(await holdsData(name), isFalse, reason: name);
    }
    // Reopened as a new install: only the currency one starts on, from the
    // device's region, which says nothing about what was wiped.
    expect(Hive.box<dynamic>('settings').keys, ['currency']);
    for (final name in hiveBoxesKeptOnWipe) {
      expect(Hive.box<dynamic>(name).get('k'), 'kept-$name', reason: name);
    }
    expect(keychain.keys(), isEmpty);
  });

  test(
      'a wipe with no boxes on disk is fine, and settings reopens as a new '
      'install: nothing but the currency a new install starts on', () async {
    await wipeHiveBoxes();
    final settings = await Hive.openBox('settings');
    expect(settings.keys, ['currency']);
  });

  test(
      'web: a delete that never completes (a connection still open on the '
      'database) neither stops the wipe nor keeps the wallet list', () async {
    // The browser case: Hive's IndexedDB delete waits for good while any
    // connection to the database is open (the boot's first-install check
    // used to leak one on `settings`). The keys were gone, the wallet list
    // stayed, and the PIN screen came back.
    final settings = await Hive.openBox<dynamic>('settings');
    await settings.put('wallets', [
      {'id': 'w1'}
    ]);
    final cache = await Hive.openBox<dynamic>('polymarket_feed_cache_v1');
    await cache.put('k', 'v');
    final deleted = <String>[];

    await wipeHiveBoxes(
      web: true,
      webDeleteTimeout: const Duration(milliseconds: 50),
      deleteBox: (name) {
        if (name == 'settings') return Completer<void>().future;
        deleted.add(name);
        return Hive.deleteBoxFromDisk(name);
      },
    );

    // Every box after `settings` in the list was still deleted.
    expect(deleted, [
      for (final n in hiveBoxesWipedOnWipe)
        if (n != 'settings') n
    ]);
    expect(await holdsData('polymarket_feed_cache_v1'), isFalse);
    // The blocked box was emptied before its delete: no wallet list.
    expect(Hive.box<dynamic>('settings').get('wallets'), isNull);
  });

  test('the orphaned refund-reports box is deleted at start and on wipe',
      () async {
    expect(hiveBoxesWipedOnWipe, contains('arbitrum_refund_reports'));
    expect(orphanedHiveBoxes, ['arbitrum_refund_reports']);
    // Nothing on disk: a no-op.
    await deleteOrphanedHiveBoxes();
    expect(await Hive.boxExists('arbitrum_refund_reports'), isFalse);

    // A closed file left by an old build.
    final box = await Hive.openBox<String>('arbitrum_refund_reports');
    await box.put('r', 'report');
    await box.close();
    expect(await Hive.boxExists('arbitrum_refund_reports'), isTrue);
    await deleteOrphanedHiveBoxes();
    expect(await Hive.boxExists('arbitrum_refund_reports'), isFalse);

    // Still open when the start runs: deleted all the same.
    await (await Hive.openBox<String>('arbitrum_refund_reports')).put('r', 'x');
    await deleteOrphanedHiveBoxes();
    expect(await Hive.boxExists('arbitrum_refund_reports'), isFalse);
    expect(Hive.isBoxOpen('arbitrum_refund_reports'), isFalse);
  });

  test('every box name lib opens is wiped or listed as kept', () {
    final known = {...hiveBoxesWipedOnWipe, ...hiveBoxesKeptOnWipe};
    final calls = RegExp(
        r"(?:Hive\.(?:openBox|openLazyBox|box|lazyBox|isBoxOpen|deleteBoxFromDisk|boxExists)|hiveBoxExists|_openHiveBoxSafe)(?:<[^>]*>)?\(\s*'([^']+)'");
    final consts = RegExp(
        r"\b[A-Za-z_][A-Za-z0-9_]*(?:Box|BoxName|_box)\s*=\s*'([^']+)'");
    final found = <String, Set<String>>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (file.path.endsWith('hive_wipe.dart')) continue;
      final text = file.readAsStringSync();
      for (final re in [calls, consts]) {
        for (final m in re.allMatches(text)) {
          found.putIfAbsent(m[1]!, () => {}).add(file.path);
        }
      }
    }
    expect(found, isNotEmpty);
    final unlisted = {
      for (final e in found.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };
    expect(unlisted, isEmpty,
        reason: 'add each to hiveBoxesWipedOnWipe or hiveBoxesKeptOnWipe');
  });
}
