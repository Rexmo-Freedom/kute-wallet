import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/tracking_service.dart';

const _spark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

const _ethKey = 'ethereum:ETH:BTC:$_spark';
const _usdtKey = 'tron:USDT:BTC:$_spark';

/// The startup path `_initHive` in lib/main.dart runs: every box opens and
/// the stored analytics opt-out is applied. The legacy deposit addresses
/// are left exactly as stored: they are only read by background sync's
/// silent sweep.
void main() {
  late Directory tmp;
  final events = <(String, Map<String, Object>?)>[];

  String entry(String chain, String asset, String deposit) => jsonEncode({
        'accumulationAddressId': 'acc_${chain}_$asset',
        'sourceChain': chain,
        'sourceAsset': asset,
        'destinationAsset': 'BTC',
        'recipientSparkAddress': _spark,
        'depositAddress': deposit,
        'label': null,
        'enabled': true,
        'createdAt': '2026-07-01T00:00:00Z',
        'kuteFeePolicy': {
          'revision': 1,
          'appFeeBps': 50,
          'providerDefault': false
        },
      });
  final ethEntry = entry('ethereum', 'ETH', _evm);
  final usdtEntry = entry('tron', 'USDT', _tron);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hive_boot_test');
    Hive.init(tmp.path);
    final box = await Hive.openBox<String>('accumulation_addresses');
    await box.put(_ethKey, ethEntry);
    await box.put(_usdtKey, usdtEntry);
    await box.close();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    await Hive.deleteFromDisk();
    // Boxes are gone, so this resets the in-memory opt-out to opted in.
    TrackingService.applyStoredOptOut();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('startup opens the boxes and leaves legacy addresses as stored',
      () async {
    expect(Hive.isBoxOpen('accumulation_addresses'), isFalse);

    await openStartupHiveBoxes();
    await openStartupHiveBoxes();

    expect(Hive.isBoxOpen('accumulation_addresses'), isTrue);
    expect(Hive.isBoxOpen('settings'), isTrue);
    final box = Hive.box<String>('accumulation_addresses');
    expect(box.get(_ethKey), ethEntry);
    expect(box.get(_usdtKey), usdtEntry);
    // Both stay visible to background sync's deposit sweep.
    expect(AccumulationAddressCache.sweepTargets().map((a) => a.depositAddress),
        unorderedEquals([_evm, _tron]));
    expect(events, isEmpty);
  });

  test('a stored analytics opt-out is read from the opened settings box',
      () async {
    final settings = await Hive.openBox('settings');
    await settings.put('analytics_opt_in', false);
    await settings.close();

    await openStartupHiveBoxes();

    expect(TrackingService.isOptedIn, isFalse);
  });
}
