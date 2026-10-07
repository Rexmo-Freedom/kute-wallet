import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_history.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import '../helpers/runtime_policy_fixture.dart';

// Checksummed vectors (see test/services/security/address_guard_test.dart):
// _spark and _sp are the same identity key under both HRP spellings.
const _spark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _sp = 'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _spark2 =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _sprt =
    'sprt1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucd5rgc0';
const _evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _evm2 = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
// Base58Check 0x41 || 01..14, a second valid Tron address.
const _tron2 = 'TA4Y62o6YC2Zsck9rZVGTvqW1AQ7X9zTnj';

/// SUNSET fund-safety tests for the accumulation-address reuse cache.
///
/// Every entry in the box was minted by Orchestra (the box never held
/// SideShift addresses), so "stale" means the (sourceChain, sourceAsset)
/// pair fell off Orchestra's receive catalog. A stale entry must never
/// be served again — the receive screen captions these addresses
/// "reusable, converts automatically", and a deposit to a dead route can
/// strand — but it must stay visible to background sync's sweep so a
/// late deposit to the already-handed-out address is still discovered.
void main() {
  late Directory tmp;
  final events = <(String, Map<String, Object>?)>[];

  String key(String chain, String asset, String dest, String spark) =>
      '$chain:$asset:$dest:$spark';

  String entry({
    required String chain,
    required String asset,
    String dest = 'BTC',
    String spark = _spark,
    String deposit = _evm,
    bool enabled = true,
  }) =>
      jsonEncode({
        'accumulationAddressId': 'acc_${chain}_$asset',
        'sourceChain': chain,
        'sourceAsset': asset,
        'destinationAsset': dest,
        'recipientSparkAddress': spark,
        'depositAddress': deposit,
        'label': null,
        'enabled': enabled,
        'createdAt': '2026-07-01T00:00:00Z',
        'kuteFeePolicy': {
          'revision': 1,
          'appFeeBps': 50,
          'providerDefault': false
        },
      });

  test('frozen fees distinguish changed terms from unrelated revisions', () {
    OrchestraAccumulationAddress address(Map<String, dynamic>? policy) =>
        OrchestraAccumulationAddress.fromJson({
          ...jsonDecode(entry(chain: 'tron', asset: 'USDT')),
          'kuteFeePolicy': policy,
        });
    final old = address({
      'revision': 1,
      'appFeeBps': 50,
      'affiliateId': 'a',
      'purpose': 'deposit'
    });
    expect(
        AccumulationAddressCache.sameFrozenFeeTerms(
            old,
            address({
              'revision': 2,
              'appFeeBps': 50,
              'affiliateId': 'a',
              'purpose': 'deposit'
            })),
        isTrue);
    expect(
        AccumulationAddressCache.sameFrozenFeeTerms(
            old,
            address({
              'revision': 2,
              'appFeeBps': 60,
              'affiliateId': 'a',
              'purpose': 'deposit'
            })),
        isFalse);
    expect(
        AccumulationAddressCache.sameFrozenFeeTerms(
            old,
            address({
              'revision': 2,
              'appFeeBps': 50,
              'affiliateId': 'b',
              'purpose': 'deposit'
            })),
        isFalse);
    expect(AccumulationAddressCache.sameFrozenFeeTerms(address(null), old),
        isFalse);
    expect(
        AccumulationAddressCache.sameFrozenFeeTerms(
            old, address({'revision': 2, 'providerDefault': true})),
        isFalse);
  });

  setUp(() async {
    setLiveOrchestraRouteCatalog(const OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: kOrchestraReceiveRoutes,
      usdReceive: kOrchestraUsdReceiveRoutes,
    ));
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    tmp = await Directory.systemTemp.createTemp('accum_cache_test');
    Hive.init(tmp.path);
    final box = await Hive.openBox<String>('accumulation_addresses');
    await box.clear();
    await AddressHistory.open();
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs [body] against a mint endpoint that answers with [minted]
  /// (merged over a valid tron USDT response) and counts the calls.
  Future<T> withMint<T>(
    Future<T> Function() body, {
    Map<String, dynamic> minted = const {},
    List<Map<String, dynamic>>? posted,
    List<String?>? idempotencyKeys,
    void Function()? beforeResponse,
  }) =>
      http.runWithClient(
        body,
        () => MockClient((req) async {
          expect(req.url.path, '/api/v1/orchestra/accumulation-addresses');
          idempotencyKeys?.add(req.headers['X-Idempotency-Key']);
          final sent = jsonDecode(req.body) as Map<String, dynamic>;
          posted?.add(sent);
          beforeResponse?.call();
          return http.Response(
              jsonEncode({
                'accumulationAddressId': 'acc_minted',
                'sourceChain': sent['sourceChain'],
                'sourceAsset': sent['sourceAsset'],
                'destinationAsset': sent['destinationAsset'],
                'recipientSparkAddress': sent['recipientSparkAddress'],
                'depositAddress': _tron,
                'enabled': true,
                'createdAt': '2026-09-15T12:00:00Z',
                'kuteFeePolicy': {
                  'revision': 1,
                  'appFeeBps': 50,
                  'providerDefault': false
                },
                ...minted,
              }),
              201);
        }),
      );

  Future<T> withNoNetwork<T>(Future<T> Function() body) => http.runWithClient(
        body,
        () => MockClient((req) async {
          fail('unexpected network call to ${req.url}');
        }),
      );

  OrchestraRoutesCatalog installExactCatalog({
    bool native = true,
    bool bridged = true,
  }) {
    Map<String, Object> row(String chain, String asset, List<String> to) => {
          'id': '$chain:$asset',
          'chain': chain,
          'asset': asset,
          'decimals': asset == 'BTC' ? 8 : 6,
          'route': {'to': to},
        };
    final catalog = OrchestraRoutesCatalog.fromJson({
      'assets': [
        row('spark', 'BTC', []),
        row('spark', 'USDB', []),
        if (native) row('polygon', 'USDC', ['spark:BTC', 'spark:USDB']),
        if (bridged) row('polygon', 'USDC.e', ['spark:BTC', 'spark:USDB']),
      ],
    }, source: OrchestraCatalogSource.live, fetchedAt: DateTime.now());
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: catalog.sendRouteTable,
      receive: catalog.receiveRouteTable,
      usdReceive: catalog.usdReceiveRouteTable,
      receiveExact:
          catalog.exactAccumulationRouteTable(destinationAsset: 'BTC'),
      usdReceiveExact:
          catalog.exactAccumulationRouteTable(destinationAsset: 'USDB'),
    ));
    return catalog;
  }

  for (final destination in ['BTC', 'USDB']) {
    test('retiring USDC.e to $destination does not borrow native USDC support',
        () async {
      installExactCatalog();
      final box = Hive.box<String>('accumulation_addresses');
      final bridgedKey = key('polygon', 'USDC.e', destination, _spark);
      final nativeKey = key('polygon', 'USDC', destination, _spark);
      final bridgedRaw =
          entry(chain: 'polygon', asset: 'USDC.e', dest: destination);
      await box.put(bridgedKey, bridgedRaw);
      await box.put(
          nativeKey,
          entry(
              chain: 'polygon',
              asset: 'USDC',
              dest: destination,
              deposit: _evm2));
      Future<Result<OrchestraAccumulationAddress>> receive(String asset) =>
          AccumulationAddressCache.getOrCreate(
            sourceChain: 'polygon',
            sourceAsset: asset,
            destinationAsset: destination,
            recipientSparkAddress: _spark,
          );
      expect(
          (await withNoNetwork(() => receive('USDC.e'))).data?.depositAddress,
          _evm);

      final updated = installExactCatalog(bridged: false);
      // The visible category remains USDC while instruction validity is exact.
      expect(updated.receiveRouteTable['USDC'], contains('polygon'));
      expect(
          orchestraReceiveChainForDestination('USDC.e', 'polygon',
              destinationAsset: destination),
          isNull);
      final refused = await withNoNetwork(() => receive('USDC.e'));
      expect(refused.data, isNull);
      expect(box.get(bridgedKey), isNull);
      expect(box.get('retired:$bridgedKey'), bridgedRaw);
      expect((await withNoNetwork(() => receive('USDC'))).data?.depositAddress,
          _evm2);
      // Both previously issued addresses are still watched for late deposits.
      expect(AccumulationAddressCache.getAll().map((a) => a.depositAddress),
          containsAll([_evm, _evm2]));
    });
  }

  test('an authoritative empty exact catalog does not revive static routes',
      () async {
    installExactCatalog();
    final box = Hive.box<String>('accumulation_addresses');
    final cacheKey = key('polygon', 'USDC.e', 'BTC', _spark);
    await box.put(cacheKey, entry(chain: 'polygon', asset: 'USDC.e'));
    installExactCatalog(native: false, bridged: false);
    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'polygon',
              sourceAsset: 'USDC.e',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));
    expect(result.data, isNull);
    expect(box.get(cacheKey), isNull);
    expect(box.get('retired:$cacheKey'), isNotNull);
  });

  test('USDC.e removed during mint stays monitored but is never displayed',
      () async {
    installExactCatalog();
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'polygon',
        sourceAsset: 'USDC.e',
        destinationAsset: 'USDB',
        recipientSparkAddress: _spark,
      ),
      minted: {'depositAddress': _evm},
      beforeResponse: () => installExactCatalog(bridged: false),
    );
    expect(result.data, isNull);
    final box = Hive.box<String>('accumulation_addresses');
    final cacheKey = key('polygon', 'USDC.e', 'USDB', _spark);
    expect(box.get(cacheKey), isNull);
    expect(box.get('retired:$cacheKey'), isNotNull);
    expect(AccumulationAddressCache.getAll().single.depositAddress, _evm);
  });

  test('disabled new deposits hide cached addresses but preserve monitoring',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    await box.put(key('tron', 'USDT', 'BTC', _spark),
        entry(chain: 'tron', asset: 'USDT', deposit: _tron));
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance =
        runtimePolicyFixture(blocked: {'crypto.deposit'});
    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'tron',
              sourceAsset: 'USDT',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));
    expect(result.data, isNull);
    expect(result.error, 'This feature is currently unavailable in Kute.');
    expect(AccumulationAddressCache.getAll().single.depositAddress, _tron);
  });

  test('policy changes mint new terms while old addresses keep monitoring',
      () async {
    final keys = <String?>[];
    Future<Result<OrchestraAccumulationAddress>> request() =>
        AccumulationAddressCache.getOrCreate(
            sourceChain: 'tron',
            sourceAsset: 'USDT',
            destinationAsset: 'BTC',
            recipientSparkAddress: _spark);
    final original = await withMint(request, idempotencyKeys: keys);
    expect(original.data?.feePolicyRevision, 1);
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance =
        runtimePolicyFixture(revision: 2);
    // New terms come with a new physical address: the provider freezes
    // terms per address, and the cache refuses a reissued address whose
    // terms changed (see the next test).
    final updated = await withMint(request, idempotencyKeys: keys, minted: {
      'accumulationAddressId': 'acc_revision_2',
      'depositAddress': _tron2,
      'kuteFeePolicy': {
        'revision': 2,
        'appFeeBps': 75,
        'providerDefault': false
      },
    });
    expect(updated.data?.feePolicyRevision, 2);
    expect(keys, hasLength(2));
    expect(keys.every((key) => key != null && key.isNotEmpty), isTrue);
    expect(keys.toSet(), hasLength(2));
    final watched = AccumulationAddressCache.getAll();
    expect(watched.map((address) => address.feePolicyRevision),
        containsAll([1, 2]));
    expect(AddressHistory.all().single.reason, AddressRetireReason.policy);
  });

  test('the same physical address reissued under new terms is refused',
      () async {
    Future<Result<OrchestraAccumulationAddress>> request() =>
        AccumulationAddressCache.getOrCreate(
            sourceChain: 'tron',
            sourceAsset: 'USDT',
            destinationAsset: 'BTC',
            recipientSparkAddress: _spark);
    final original = await withMint(request);
    expect(original.data?.depositAddress, _tron);
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance =
        runtimePolicyFixture(revision: 2);
    final reissued = await withMint(request, minted: {
      'accumulationAddressId': 'acc_revision_2',
      'kuteFeePolicy': {
        'revision': 2,
        'appFeeBps': 75,
        'providerDefault': false
      },
    });
    expect(reissued.data, isNull);
    expect(reissued.error,
        'Reusable deposit terms changed. Use a one-time deposit address.');
    // The original terms stay watched for late deposits.
    expect(AccumulationAddressCache.getAll().single.feePolicyRevision, 1);
  });

  test(
      'unknown legacy terms are reissued and stale server revisions are refused',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final cached =
        jsonDecode(entry(chain: 'tron', asset: 'USDT', deposit: _tron))
            as Map<String, dynamic>;
    cached.remove('kuteFeePolicy');
    await box.put(key('tron', 'USDT', 'BTC', _spark), jsonEncode(cached));
    final posted = <Map<String, dynamic>>[];
    final result = await withMint(
        () => AccumulationAddressCache.getOrCreate(
            sourceChain: 'tron',
            sourceAsset: 'USDT',
            destinationAsset: 'BTC',
            recipientSparkAddress: _spark),
        posted: posted,
        minted: {
          'kuteFeePolicy': {'revision': 0}
        });
    expect(posted, hasLength(1));
    expect(result.data, isNull);
    expect(result.error, 'Deposit terms changed. Please try again.');
    expect(AccumulationAddressCache.getAll().single.id, 'acc_tron_USDT');
    expect(box.get(key('tron', 'USDT', 'BTC', _spark)), isNull);
  });

  test('init retires entries for pairs off the receive catalog', () async {
    final box = Hive.box<String>('accumulation_addresses');
    final ethKey = key('ethereum', 'ETH', 'BTC', _spark);
    final usdtKey = key('tron', 'USDT', 'BTC', _spark);
    await box.put(ethKey, entry(chain: 'ethereum', asset: 'ETH'));
    await box.put(usdtKey, entry(chain: 'tron', asset: 'USDT', deposit: _tron));

    await AccumulationAddressCache.init();

    // ETH on Ethereum is not an Orchestra receive route: moved under
    // the retired prefix, original key gone, payload preserved intact.
    expect(box.get(ethKey), isNull);
    expect(box.get('retired:$ethKey'), entry(chain: 'ethereum', asset: 'ETH'));
    // USDT on Tron is on the catalog: untouched.
    expect(
        box.get(usdtKey), entry(chain: 'tron', asset: 'USDT', deposit: _tron));
    final history = AddressHistory.all();
    expect(history, hasLength(1));
    expect(history.single.reason, AddressRetireReason.catalog);
    expect(history.single.chain, 'ethereum');
  });

  test('getOrCreate refuses an unsupported pair and retires its entry',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final ethKey = key('ethereum', 'ETH', 'BTC', _spark);
    await box.put(ethKey, entry(chain: 'ethereum', asset: 'ETH'));

    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'ethereum',
              sourceAsset: 'ETH',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));

    expect(result.data, isNull);
    expect(result.error, isNotNull);
    expect(box.get(ethKey), isNull);
    expect(box.get('retired:$ethKey'), isNotNull);
  });

  test('a v1 entry that re-verifies is reused without a mint', () async {
    final box = Hive.box<String>('accumulation_addresses');
    final usdcKey = key('base', 'USDC', 'BTC', _spark);
    await box.put(usdcKey, entry(chain: 'base', asset: 'USDC', deposit: _evm2));

    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'base',
              sourceAsset: 'USDC',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));

    expect(result.error, isNull);
    expect(result.data?.depositAddress, _evm2);
    expect(
        box.get(usdcKey), entry(chain: 'base', asset: 'USDC', deposit: _evm2));
    expect(events.map((e) => e.$1),
        isNot(contains('accumulation_address_reverify_failed')));
  });

  test(
      'an entry whose deposit format mismatches its chain retires and re-mints',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final usdtKey = key('tron', 'USDT', 'BTC', _spark);
    await box.put(usdtKey, entry(chain: 'tron', asset: 'USDT', deposit: _evm));
    final posted = <Map<String, dynamic>>[];

    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'tron',
        sourceAsset: 'USDT',
        destinationAsset: 'BTC',
        recipientSparkAddress: _spark,
        refundAddresses: const {'tron': _tron},
      ),
      posted: posted,
    );

    expect(posted, hasLength(1));
    expect(result.data?.depositAddress, _tron);
    expect(box.get('retired:$usdtKey'),
        entry(chain: 'tron', asset: 'USDT', deposit: _evm));
    final cached = jsonDecode(box.get(usdtKey)!) as Map<String, dynamic>;
    expect(cached['depositAddress'], _tron);
    expect(cached['schema'], 3);
    expect(cached['refundAddresses'], {'tron': _tron});
    expect(
        events
            .where((e) => e.$1 == 'accumulation_address_reverify_failed')
            .map((e) => e.$2),
        [
          {'reason': 'deposit_format'}
        ]);
    final history = AddressHistory.all();
    expect(history, hasLength(1));
    expect(history.single.reason, AddressRetireReason.reverify);
    expect(history.single.address, _evm);
    expect(history.single.chain, 'tron');
  });

  test('an entry recorded for another recipient is never served', () async {
    final box = Hive.box<String>('accumulation_addresses');
    final usdcKey = key('base', 'USDC', 'BTC', _spark);
    await box.put(usdcKey, entry(chain: 'base', asset: 'USDC', spark: _spark2));

    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'base',
        sourceAsset: 'USDC',
        destinationAsset: 'BTC',
        recipientSparkAddress: _spark,
      ),
      minted: {'depositAddress': _evm2},
    );

    expect(result.data?.depositAddress, _evm2);
    expect(result.data?.recipientSparkAddress, _spark);
    expect(
        events
            .where((e) => e.$1 == 'accumulation_address_reverify_failed')
            .map((e) => e.$2?['reason']),
        ['recipient']);
  });

  test('a supported Monad entry requires its EVM address format', () async {
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: {
        ...kOrchestraReceiveRoutes,
        'USDT': {...kOrchestraReceiveRoutes['USDT']!, 'monad'},
      },
    ));
    final box = Hive.box<String>('accumulation_addresses');
    final monadKey = key('monad', 'USDT', 'BTC', _spark);
    const monadDeposit = _evm;
    await box.put(
        monadKey, entry(chain: 'monad', asset: 'USDT', deposit: monadDeposit));

    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'monad',
              sourceAsset: 'USDT',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));

    expect(result.error, isNull);
    expect(result.data?.depositAddress, monadDeposit);
    expect(box.get(monadKey), isNotNull);
  });

  test('a chain the accumulation rail cannot mint on is never served',
      () async {
    // The route table may still carry it (a stale live catalog), but a
    // reusable deposit address does not exist on TON, so the entry is
    // retired rather than handed out for a route that cannot convert.
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: {
        ...kOrchestraReceiveRoutes,
        'USDT': {...kOrchestraReceiveRoutes['USDT']!, 'ton'},
      },
    ));
    final box = Hive.box<String>('accumulation_addresses');
    final tonKey = key('ton', 'USDT', 'BTC', _spark);
    await box.put(
        tonKey,
        entry(
            chain: 'ton',
            asset: 'USDT',
            deposit: 'UQBvI0aFLnw2QbZgjMPCLRdtRHxhUyinQudg6sdiohIwg5jL'));

    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'ton',
              sourceAsset: 'USDT',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));

    expect(result.data, isNull);
    expect(result.error, isNotNull);
    expect(box.get(tonKey), isNull);
  });

  test('a minted response with the sp1 respelled as spark1 is accepted',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'tron',
        sourceAsset: 'USDT',
        destinationAsset: 'BTC',
        recipientSparkAddress: _sp,
      ),
      minted: {'recipientSparkAddress': _spark},
    );
    expect(result.error, isNull);
    expect(box.get(key('tron', 'USDT', 'BTC', _sp)), isNotNull);
  });

  test('a minted deposit address in the wrong format is refused, not cached',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'arbitrum',
        sourceAsset: 'USDC',
        destinationAsset: 'BTC',
        recipientSparkAddress: _spark,
      ),
      minted: {'depositAddress': 'lnbc1pjqqqqq'},
    );
    expect(result.data, isNull);
    expect(result.error, AccumulationAddressCache.kInvalidDestinationError);
    expect(box.isEmpty, isTrue);
  });

  for (final (field, value, reason) in [
    ('sourceChain', 'ethereum', 'source_chain'),
    ('sourceAsset', 'USDC.e', 'source_asset'),
    ('enabled', false, 'disabled'),
    ('enabled', null, 'disabled'),
  ]) {
    test('cached $field=$value is retired instead of served', () async {
      final box = Hive.box<String>('accumulation_addresses');
      final cacheKey = key('base', 'USDC', 'BTC', _spark);
      final cached = jsonDecode(entry(chain: 'base', asset: 'USDC'))
          as Map<String, dynamic>;
      cached[field] = value;
      await box.put(cacheKey, jsonEncode(cached));
      final posted = <Map<String, dynamic>>[];
      final result = await withMint(
        () => AccumulationAddressCache.getOrCreate(
          sourceChain: 'base',
          sourceAsset: 'USDC',
          destinationAsset: 'BTC',
          recipientSparkAddress: _spark,
        ),
        minted: {'depositAddress': _evm2},
        posted: posted,
      );
      expect(posted, hasLength(1));
      expect(result.data?.depositAddress, _evm2);
      expect(box.get('retired:$cacheKey'), jsonEncode(cached));
      expect(AccumulationAddressCache.getAll().map((a) => a.depositAddress),
          containsAll([_evm, _evm2]));
      expect(
          events
              .where((e) => e.$1 == 'accumulation_address_reverify_failed')
              .map((e) => e.$2?['reason']),
          [reason]);
    });

    test('minted $field=$value is refused even with an EVM deposit', () async {
      final result = await withMint(
        () => AccumulationAddressCache.getOrCreate(
          sourceChain: 'base',
          sourceAsset: 'USDC',
          destinationAsset: 'BTC',
          recipientSparkAddress: _spark,
        ),
        minted: {'depositAddress': _evm, field: value},
      );
      expect(result.data, isNull);
      expect(result.error, AccumulationAddressCache.kInvalidDestinationError);
      expect(Hive.box<String>('accumulation_addresses').isEmpty, isTrue);
    });
  }

  test('source label case may vary without aliasing distinct assets', () async {
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'polygon',
        sourceAsset: 'USDC.e',
        destinationAsset: 'BTC',
        recipientSparkAddress: _spark,
      ),
      minted: {
        'sourceChain': 'POLYGON',
        'sourceAsset': 'usdc.E',
        'depositAddress': _evm,
      },
    );
    expect(result.error, isNull);
    expect(result.data?.depositAddress, _evm);
  });

  test('a route withdrawn during mint hides the address but keeps monitoring',
      () async {
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'tron',
        sourceAsset: 'USDT',
        destinationAsset: 'USDB',
        recipientSparkAddress: _spark,
      ),
      beforeResponse: () => setLiveOrchestraRouteCatalog(
        const OrchestraRouteCatalog(
          send: kOrchestraSendRoutes,
          receive: kOrchestraReceiveRoutes,
          usdReceive: {},
        ),
      ),
    );
    expect(result.data, isNull);
    final cacheKey = key('tron', 'USDT', 'USDB', _spark);
    final box = Hive.box<String>('accumulation_addresses');
    expect(box.get(cacheKey), isNull);
    expect(box.get('retired:$cacheKey'), isNotNull);
    expect(AccumulationAddressCache.getAll().single.depositAddress, _tron);
    expect(AddressHistory.all().single.reason, AddressRetireReason.catalog);
    // Retired instructions remain monitored after restart as well.
    await Hive.close();
    await AccumulationAddressCache.init();
    expect(AccumulationAddressCache.getAll().single.depositAddress, _tron);
  });

  test('a valid cached USDB destination is accepted without a mint', () async {
    final box = Hive.box<String>('accumulation_addresses');
    await box.put(key('tron', 'USDT', 'USDB', _spark),
        entry(chain: 'tron', asset: 'USDT', dest: 'USDB', deposit: _tron));
    final result = await withNoNetwork(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'tron',
        sourceAsset: 'USDT',
        destinationAsset: 'USDB',
        recipientSparkAddress: _spark,
      ),
    );
    expect(result.error, isNull);
    expect(result.data?.destinationAsset, 'USDB');
  });

  test('retireForRecipient hides entries from getOrCreate but not getAll',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final baseKey = key('base', 'USDC', 'BTC', _spark);
    await box.put(baseKey, entry(chain: 'base', asset: 'USDC', deposit: _evm2));
    await box.put(key('tron', 'USDT', 'BTC', _spark),
        entry(chain: 'tron', asset: 'USDT', deposit: _tron));
    await box.put(key('base', 'USDC', 'BTC', _spark2),
        entry(chain: 'base', asset: 'USDC', spark: _spark2));

    final retired = await AccumulationAddressCache.retireForRecipient(
        _sp, AddressRetireReason.rotation);

    expect(retired, 2);
    expect(box.get(baseKey), isNull);
    expect(box.get('retired:$baseKey'), isNotNull);
    expect(AccumulationAddressCache.getAll().map((a) => a.depositAddress),
        containsAll(<String>{_evm2, _tron, _evm}));
    expect(AddressHistory.all().map((h) => h.reason).toSet(),
        {AddressRetireReason.rotation});

    final posted = <Map<String, dynamic>>[];
    final result = await withMint(
      () => AccumulationAddressCache.getOrCreate(
        sourceChain: 'base',
        sourceAsset: 'USDC',
        destinationAsset: 'BTC',
        recipientSparkAddress: _spark,
      ),
      minted: {'depositAddress': _evm},
      posted: posted,
    );
    expect(posted, hasLength(1), reason: 'the retired entry was not served');
    expect(result.data?.depositAddress, _evm);
  });

  test('a second retirement of the same tuple keeps the first', () async {
    final box = Hive.box<String>('accumulation_addresses');
    final usdtKey = key('tron', 'USDT', 'BTC', _spark);
    await box.put(usdtKey, entry(chain: 'tron', asset: 'USDT', deposit: _evm));
    await withMint(() => AccumulationAddressCache.getOrCreate(
          sourceChain: 'tron',
          sourceAsset: 'USDT',
          destinationAsset: 'BTC',
          recipientSparkAddress: _spark,
        ));
    await AccumulationAddressCache.retireForRecipient(
        _spark, AddressRetireReason.compromise);

    final deposits =
        AccumulationAddressCache.getAll().map((a) => a.depositAddress).toList();
    expect(deposits, containsAll(<String>[_evm, _tron]));
    expect(box.keys.where((k) => (k as String).startsWith('retired:')),
        hasLength(2));
  });

  test('getAll keeps retired entries visible for the background sweep',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    await box.put(key('ethereum', 'ETH', 'BTC', _spark),
        entry(chain: 'ethereum', asset: 'ETH', deposit: '0xoldeth'));
    await box.put(key('tron', 'USDT', 'BTC', _spark),
        entry(chain: 'tron', asset: 'USDT', deposit: 'Ttrondep'));

    await AccumulationAddressCache.init();

    final all = AccumulationAddressCache.getAll();
    final deposits = all.map((a) => a.depositAddress).toSet();
    // The retired ETH address was already handed out to senders once;
    // the sweep must keep watching it for late deposits.
    expect(deposits, containsAll(<String>{'0xoldeth', 'Ttrondep'}));
  });

  group('destination lock (spark BTC or USDB only)', () {
    test('refuses destinations outside BTC and USDB', () async {
      final box = Hive.box<String>('accumulation_addresses');
      // Even a cached entry for the tuple must not be served: the lock
      // runs before every cache read and before any mint.
      final usdbKey = key('tron', 'USDT', 'ETH', _spark);
      await box.put(usdbKey, entry(chain: 'tron', asset: 'USDT', dest: 'ETH'));

      final result = await AccumulationAddressCache.getOrCreate(
        sourceChain: 'tron',
        sourceAsset: 'USDT',
        destinationAsset: 'ETH',
        recipientSparkAddress: _spark,
      );

      expect(result.data, isNull);
      expect(result.error, AccumulationAddressCache.kInvalidDestinationError);
    });

    test('refuses recipients that are not spark-format addresses', () async {
      // A supported pair with a wrong-family recipient must be refused
      // BEFORE any network call.
      for (final bad in [
        '',
        'sp1test',
        '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'lnbc1pjqqqqq',
        _tron,
        _sprt,
      ]) {
        final result =
            await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
                  sourceChain: 'tron',
                  sourceAsset: 'USDT',
                  destinationAsset: 'BTC',
                  recipientSparkAddress: bad,
                ));
        expect(result.data, isNull, reason: 'accepted recipient: "$bad"');
        expect(result.error, AccumulationAddressCache.kInvalidDestinationError,
            reason: 'wrong error for recipient: "$bad"');
      }
    });

    test('accepts both mainnet spark spellings with a valid checksum', () {
      expect(AccumulationAddressCache.isSparkFormatAddress(_sp), isTrue);
      expect(AccumulationAddressCache.isSparkFormatAddress(_spark), isTrue);
      expect(AccumulationAddressCache.isSparkFormatAddress('sp1abc'), isFalse);
      expect(AccumulationAddressCache.isSparkFormatAddress(_sprt), isFalse);
      expect(
          AccumulationAddressCache.isSparkFormatAddress('sprk1abc'), isFalse);
      expect(AccumulationAddressCache.isSparkFormatAddress('0xdead'), isFalse);
    });

    test('a valid spark recipient still reads the cache normally', () async {
      final box = Hive.box<String>('accumulation_addresses');
      final usdtKey = key('tron', 'USDT', 'BTC', _spark);
      await box.put(
          usdtKey, entry(chain: 'tron', asset: 'USDT', deposit: _tron));

      final result =
          await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
                sourceChain: 'tron',
                sourceAsset: 'USDT',
                destinationAsset: 'BTC',
                recipientSparkAddress: _spark,
              ));

      expect(result.error, isNull);
      expect(result.data?.depositAddress, _tron);
    });
  });

  test('a retired entry is restored by one key rename', () async {
    final box = Hive.box<String>('accumulation_addresses');
    final ethKey = key('ethereum', 'ETH', 'BTC', _spark);
    await box.put(ethKey, entry(chain: 'ethereum', asset: 'ETH'));
    await AccumulationAddressCache.init();
    expect(box.get(ethKey), isNull);

    // The documented one-line restore: strip the prefix.
    final raw = box.get('retired:$ethKey');
    await box.put(ethKey, raw!);
    await box.delete('retired:$ethKey');
    expect(box.get(ethKey), entry(chain: 'ethereum', asset: 'ETH'));
  });

  test('an EVM-format deposit on a spark source is retired and never served',
      () async {
    final box = Hive.box<String>('accumulation_addresses');
    final sparkKey = key('spark', 'BTC', 'BTC', _spark);
    await box.put(sparkKey, entry(chain: 'spark', asset: 'BTC', deposit: _evm));

    expect(
        AccumulationAddressCache.reverifyFailure(
          OrchestraAccumulationAddress.fromJson(
              jsonDecode(box.get(sparkKey)!) as Map<String, dynamic>),
          sourceChain: 'spark',
          sourceAsset: 'BTC',
          recipientSparkAddress: _spark,
        ),
        isNotNull);

    final result =
        await withNoNetwork(() => AccumulationAddressCache.getOrCreate(
              sourceChain: 'spark',
              sourceAsset: 'BTC',
              destinationAsset: 'BTC',
              recipientSparkAddress: _spark,
            ));
    expect(result.data, isNull);
    expect(box.get(sparkKey), isNull);
    expect(box.keys.where((k) => '$k'.startsWith('retired:')), isNotEmpty);
  });
}
