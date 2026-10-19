// The device wipe deletes every app Hive box from one list. After it, no
// wiped box holds anything (gone from disk, or reopened empty for the
// startup set), the kept boxes keep their data, and a source scan keeps
// the list honest: every box name lib opens is wiped or listed as kept.

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
      expect(await holdsData(name), isFalse, reason: name);
    }
    for (final name in hiveBoxesKeptOnWipe) {
      expect(Hive.box<dynamic>(name).get('k'), 'kept-$name', reason: name);
    }
    expect(keychain.keys(), isEmpty);
  });

  test('a wipe with no boxes on disk is fine, and settings reopens empty',
      () async {
    await wipeHiveBoxes();
    final settings = await Hive.openBox('settings');
    expect(settings.isEmpty, isTrue);
  });

  test('every box name lib opens is wiped or listed as kept', () {
    final known = {...hiveBoxesWipedOnWipe, ...hiveBoxesKeptOnWipe};
    final calls = RegExp(
        r"(?:Hive\.(?:openBox|openLazyBox|box|lazyBox|isBoxOpen|deleteBoxFromDisk|boxExists)|_openHiveBoxSafe)(?:<[^>]*>)?\(\s*'([^']+)'");
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
