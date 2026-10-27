// The icon disk cache: hits and definitive misses survive a relaunch (a
// new instance over the same folder), misses expire, stale hits are
// flagged for a refresh, the oldest rows go past the cap, and the
// prefetch pool never runs more than its limit at once.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/icon_cache/icon_disk_cache.dart';

void main() {
  late Directory dir;
  var now = DateTime(2026, 10, 27, 12);
  DateTime clock() => now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('icon_cache_test');
    now = DateTime(2026, 10, 27, 12);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<IconDiskCache> open({int maxEntries = 3000}) => IconDiskCache.open(
      dir,
      clock: clock,
      maxEntries: maxEntries,
      flushDelay: const Duration(hours: 1));

  final logo = Uint8List.fromList('<svg viewBox="0 0 1 1"/>'.codeUnits);

  test('a hit and a miss survive a relaunch', () async {
    final first = await open();
    await first.putHit('https://a.test/btc.svg', logo);
    await first.putHit('https://a.test/raster.svg', logo, raster: true);
    first.putMiss('https://a.test/none.svg');
    await first.flush();

    final second = await open();
    expect(second.lookup('https://a.test/btc.svg')!.kind, IconCacheKind.svg);
    expect(second.lookup('https://a.test/btc.svg')!.fresh, isTrue);
    expect(second.lookup('https://a.test/raster.svg')!.kind,
        IconCacheKind.raster);
    expect(await second.read('https://a.test/btc.svg'), logo);
    expect(second.lookup('https://a.test/none.svg')!.isMiss, isTrue);
    expect(second.freshMisses(), ['https://a.test/none.svg']);
    expect(second.lookup('https://a.test/never.svg'), isNull);
  });

  test('a miss expires; a hit past its period is served but stale',
      () async {
    final cache = await open();
    await cache.putHit('https://a.test/btc.svg', logo);
    cache.putMiss('https://a.test/none.svg');
    now = now.add(const Duration(days: 4));
    expect(cache.lookup('https://a.test/none.svg'), isNull,
        reason: 'a logo added since must get its chance');
    expect(cache.freshMisses(), isEmpty);
    now = now.add(const Duration(days: 30));
    final stale = cache.lookup('https://a.test/btc.svg')!;
    expect(stale.fresh, isFalse);
    expect(await cache.read('https://a.test/btc.svg'), logo);
  });

  test('a file the OS cleared drops its row', () async {
    final cache = await open();
    await cache.putHit('https://a.test/btc.svg', logo);
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) f.deleteSync();
    }
    expect(await cache.read('https://a.test/btc.svg'), isNull);
    expect(cache.lookup('https://a.test/btc.svg'), isNull);
  });

  test('past the cap the least recently drawn go first', () async {
    final cache = await open();
    for (var i = 0; i < 5; i++) {
      await cache.putHit('https://a.test/$i.svg', logo);
      now = now.add(const Duration(minutes: 2));
    }
    cache.touch('https://a.test/0.svg'); // drawn last
    expect(cache.recentHits(2), ['https://a.test/0.svg', 'https://a.test/4.svg']);
    await cache.flush();

    final capped = await open(maxEntries: 3);
    expect(capped.length, 3);
    expect(capped.lookup('https://a.test/0.svg'), isNotNull);
    expect(capped.lookup('https://a.test/1.svg'), isNull);
    expect(capped.lookup('https://a.test/2.svg'), isNull);
  });

  test('an unreadable index starts empty', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/index.json').writeAsStringSync('{not json');
    final cache = await open();
    expect(cache.length, 0);
    await cache.putHit('https://a.test/btc.svg', logo);
    expect(await cache.read('https://a.test/btc.svg'), logo);
  });

  test('runBounded keeps to its limit, runs everything, survives errors',
      () async {
    var running = 0;
    var peak = 0;
    final done = <int>[];
    await runBounded(List.generate(20, (i) => i), 6, (i) async {
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      if (i == 3) throw StateError('one logo failed');
      done.add(i);
    });
    expect(peak, 6);
    expect(done.length, 19);
  });
}
