import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_history.dart';
import 'package:kute/services/tracking_service.dart';

// Checksummed vectors shared with accumulation_address_cache_test.dart.
const _spark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

const _ethKey = 'ethereum:ETH:BTC:$_spark';
const _usdtKey = 'tron:USDT:BTC:$_spark';

/// The startup path `_initHive` in lib/main.dart runs: every box opens,
/// the stored analytics opt-out is applied, and the reusable-deposit
/// sweep parks cached addresses whose route fell off Orchestra's receive
/// catalog. Before this path existed the sweep only ever ran in tests.
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
    setLiveOrchestraRouteCatalog(const OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: kOrchestraReceiveRoutes,
      usdReceive: kOrchestraUsdReceiveRoutes,
    ));
    tmp = await Directory.systemTemp.createTemp('hive_boot_test');
    Hive.init(tmp.path);
    // Seed the cache as a previous launch left it — one pair still on
    // the catalog, one that fell off — then close the box so the startup
    // path has to open it (and the history box) itself.
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

  test('startup opens the boxes and retires entries off the receive catalog',
      () async {
    expect(Hive.isBoxOpen('accumulation_addresses'), isFalse);
    expect(Hive.isBoxOpen(AddressHistory.boxName), isFalse);

    await openStartupHiveBoxes();

    expect(Hive.isBoxOpen('accumulation_addresses'), isTrue);
    expect(Hive.isBoxOpen(AddressHistory.boxName), isTrue);
    expect(Hive.isBoxOpen('settings'), isTrue);

    // ETH on Ethereum is not an Orchestra receive route: parked under the
    // retired prefix with its payload intact. USDT on Tron is untouched.
    final box = Hive.box<String>('accumulation_addresses');
    expect(box.get(_ethKey), isNull);
    expect(box.get('retired:$_ethKey'), ethEntry);
    expect(box.get(_usdtKey), usdtEntry);
    // Both stay visible to background sync's deposit sweep.
    expect(AccumulationAddressCache.getAll().map((a) => a.depositAddress),
        unorderedEquals([_evm, _tron]));

    // The history box was open before the sweep ran, so the retirement
    // left its row instead of being dropped by a closed box.
    final history = AddressHistory.all();
    expect(history, hasLength(1));
    expect(history.single.reason, AddressRetireReason.catalog);
    expect(history.single.chain, 'ethereum');
    expect(history.single.address, _evm);

    final retired =
        events.where((e) => e.$1 == 'reusable_deposit_address_retired');
    expect(retired.single.$2,
        {'source_chain': 'ethereum', 'source_asset': 'ETH'});
  });

  test('a second launch leaves the parked entry alone', () async {
    await openStartupHiveBoxes();
    await openStartupHiveBoxes();

    final box = Hive.box<String>('accumulation_addresses');
    expect(box.keys.where((k) => '$k'.startsWith('retired:')), hasLength(1));
    expect(AddressHistory.all(), hasLength(1));
  });

  test('a stored analytics opt-out is read from the opened settings box',
      () async {
    final settings = await Hive.openBox('settings');
    await settings.put('analytics_opt_in', false);
    await settings.close();

    await openStartupHiveBoxes();

    expect(TrackingService.isOptedIn, isFalse);
    // Hygiene does not depend on analytics being on.
    expect(Hive.box<String>('accumulation_addresses').get(_ethKey), isNull);
  });
}
