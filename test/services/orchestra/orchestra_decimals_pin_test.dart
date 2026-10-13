import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_routes.dart' show kOrchestraSendRoutes;
import 'package:kute/services/tracking_service.dart';

Map<String, dynamic> _row(String chain, String asset, int decimals,
        {List<String> to = const []}) =>
    {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'assetDisplayName': asset,
      'assetDisplaySymbol': asset,
      'decimals': decimals,
      'chainDisplayName': chain,
      'route': {'to': to, 'exactOutTo': [], 'fixedTo': []},
    };

OrchestraRoutesCatalog _catalog(List<Map<String, dynamic>> rows) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', 8, to: ['polygon:USDC.e', 'bsc:USDC']),
          ...rows,
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.utc(2026, 9, 15),
    );

void main() {
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    resetOrchestraDecimalsForTest();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    resetOrchestraDecimalsForTest();
  });

  test('pin table covers the supported settlement assets', () {
    expect(kPinnedOrchestraDecimals, {
      'spark:BTC': 8,
      'spark:USDB': 6,
      'bitcoin:BTC': 8,
      'polygon:USDC.E': 6,
      'polygon:USDC': 6,
      'arbitrum:USDC': 6,
      'base:USDC': 6,
      'ethereum:USDC': 6,
      'optimism:USDC': 6,
      'solana:USDC': 6,
      'arbitrum:USDT': 6,
      'optimism:USDT': 6,
      'tron:USDT': 6,
      'plasma:USDT': 6,
      'hypercore:USDC': 8,
      'bsc:USDC': 18,
    });
    expect(pinnedOrchestraDecimals('Polygon', 'USDC.e'), 6);
    expect(pinnedOrchestraDecimals('bsc', 'USDT'), isNull);
  });

  test('every static Send route has pinned decimals', () {
    kOrchestraSendRoutes.forEach((asset, chains) {
      for (final chain in chains) {
        expect(pinnedOrchestraDecimals(chain, asset), isNotNull,
            reason: '$chain:$asset');
      }
    });
  });

  test('receipt text preserves base units beyond double precision', () {
    expect(orchestraAmountToDecimalString('1', 'USDC', chain: 'bsc'),
        '0.000000000000000001');
    expect(
        orchestraAmountToDecimalString('9007199254740993', 'BTC',
            chain: 'spark'),
        '90071992.54740993');
    expect(
        orchestraAmountToDecimalString('290000000', 'USDC', chain: 'hypercore'),
        '2.9');
    expect(
        orchestraAmountToDecimalString('1000000', 'USDB', chain: 'spark'), '1');
    expect(orchestraAmountToDecimalString('0', 'USDC', chain: 'bsc'), '0');
  });

  test('a hostile catalog row for a Send route cannot rescale it', () {
    setOrchestraDecimalsCatalog(_catalog([_row('tron', 'USDT', 2)]));
    expect(orchestraAssetDecimals('USDT', chain: 'tron'), 6);
    expect(orchestraDecimalsMismatch('tron', 'USDT'), isTrue);
  });

  test('pinned pairs answer with the pin before any catalog loads', () {
    expect(orchestraAssetDecimals('USDC', chain: 'bsc'), 18);
    expect(orchestraAssetDecimals('USDC', chain: 'hypercore'), 8);
    expect(orchestraAssetDecimals('USDC.e', chain: 'polygon'), 6);
  });

  test('a disagreeing catalog cannot change pinned decimals', () {
    setOrchestraDecimalsCatalog(_catalog([
      _row('bsc', 'USDC', 6),
      _row('polygon', 'USDC.e', 18),
    ]));
    expect(orchestraAssetDecimals('USDC', chain: 'bsc'), 18);
    expect(orchestraAssetDecimals('USDC.e', chain: 'polygon'), 6);
    expect(orchestraDecimalsMismatch('bsc', 'USDC'), isTrue);
    expect(orchestraDecimalsMismatch('polygon', 'usdc.e'), isTrue);
    expect(orchestraDecimalsMismatch('spark', 'BTC'), isFalse);
    expect(doubleToOrchestraAmount(1.5, 'USDC.e', chain: 'polygon'), '1500000');
  });

  test('a mismatch emits one event per pair until it clears', () {
    final hostile = _catalog([_row('bsc', 'USDC', 6)]);
    setOrchestraDecimalsCatalog(hostile);
    setOrchestraDecimalsCatalog(hostile);
    expect(events, hasLength(1));
    expect(events.single.$1, 'orchestra_decimals_mismatch');
    expect(events.single.$2, {'chain': 'bsc', 'asset': 'USDC'});

    setOrchestraDecimalsCatalog(_catalog([_row('bsc', 'USDC', 18)]));
    expect(orchestraDecimalsMismatch('bsc', 'USDC'), isFalse);
    expect(events, hasLength(1));
  });

  test('unpinned pairs still read the live catalog; no chain uses tickers', () {
    setOrchestraDecimalsCatalog(_catalog([_row('bsc', 'USDT', 9)]));
    expect(orchestraAssetDecimals('USDT', chain: 'bsc'), 9);
    expect(orchestraAssetDecimals('USDT'), 6);
    expect(orchestraDecimalsMismatch('bsc', 'USDT'), isFalse);
  });
}
