import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/accumulation_address_cache.dart';

// Checksummed vectors (see test/services/security/address_guard_test.dart).
const _spark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _evm2 = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

/// The legacy accumulation addresses a device handed out are read only:
/// never created, reused or shown again (the receive screens use standing
/// addresses alone), and still watched by background sync so a late
/// deposit to one gets its Activity row.
void main() {
  late Directory tmp;

  String key(String chain, String asset, String dest) =>
      '$chain:$asset:$dest:$_spark';

  String entry({
    required String chain,
    required String asset,
    String dest = 'BTC',
    String deposit = _evm,
  }) =>
      jsonEncode({
        'accumulationAddressId': 'acc_${chain}_$asset',
        'sourceChain': chain,
        'sourceAsset': asset,
        'destinationAsset': dest,
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

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('accum_cache_test');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('before the box opens there is nothing to watch', () {
    expect(AccumulationAddressCache.getAll(), isEmpty);
    expect(AccumulationAddressCache.sweepTargets(), isEmpty);
  });

  test(
      'every handed-out address stays watched, retired ones included; '
      'HyperCore sources and corrupt entries are skipped', () async {
    await AccumulationAddressCache.init();
    final box = Hive.box<String>('accumulation_addresses');
    await box.put(key('tron', 'USDT', 'BTC'),
        entry(chain: 'tron', asset: 'USDT', deposit: _tron));
    // Parked by an older build when its route fell off the catalog: the
    // address was handed out, so a late deposit must still be discovered.
    await box.put('retired:${key('ethereum', 'ETH', 'BTC')}',
        entry(chain: 'ethereum', asset: 'ETH'));
    await box.put(key('base', 'USDC', 'USDB'),
        entry(chain: 'base', asset: 'USDC', dest: 'USDB', deposit: _evm2));
    // A HyperCore source cannot be verified by the provider, so history
    // polling cannot credit it: left to the provider, never swept.
    await box.put(key('hypercore', 'USDC', 'BTC'),
        entry(chain: 'hypercore', asset: 'USDC'));
    await box.put('corrupt', '{not json');

    expect(AccumulationAddressCache.getAll().map((a) => a.sourceChain),
        unorderedEquals(['tron', 'ethereum', 'base', 'hypercore']));
    expect(AccumulationAddressCache.sweepTargets().map((a) => a.sourceChain),
        unorderedEquals(['tron', 'ethereum', 'base']));
    // Reading never rewrites the box.
    expect(box.keys, hasLength(5));
  });

  test('init only opens the box and leaves every entry where it was', () async {
    final box = await Hive.openBox<String>('accumulation_addresses');
    await box.put(
        key('ethereum', 'ETH', 'BTC'), entry(chain: 'ethereum', asset: 'ETH'));
    await box.close();

    await AccumulationAddressCache.init();
    await AccumulationAddressCache.init();

    final reopened = Hive.box<String>('accumulation_addresses');
    expect(reopened.keys, [key('ethereum', 'ETH', 'BTC')]);
    expect(AccumulationAddressCache.sweepTargets().single.depositAddress, _evm);
  });
}
