import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:kute/services/api/api_client.dart';
import 'package:kute/services/mempool_address_service.dart';

import '../mocks/mock_http_client.dart';

void main() {
  group('MempoolAddressData', () {
    test('stores fields correctly', () {
      final data = MempoolAddressData(
        balanceSats: 100000,
        txCount: 5,
        fundedSum: 200000,
        spentSum: 100000,
      );
      expect(data.balanceSats, 100000);
      expect(data.txCount, 5);
      expect(data.fundedSum, 200000);
      expect(data.spentSum, 100000);
    });
  });

  group('MempoolTransaction', () {
    test('stores fields correctly', () {
      final tx = MempoolTransaction(
        txid: 'abc123',
        blockHeight: 800000,
        blockTime: 1700000000,
        confirmed: true,
        fee: 250,
        balanceChange: 50000,
      );
      expect(tx.txid, 'abc123');
      expect(tx.confirmed, isTrue);
      expect(tx.fee, 250);
      expect(tx.balanceChange, 50000);
    });

    test('handles unconfirmed tx', () {
      final tx = MempoolTransaction(
        txid: 'def456',
        confirmed: false,
        fee: 100,
        balanceChange: -30000,
      );
      expect(tx.blockHeight, isNull);
      expect(tx.blockTime, isNull);
      expect(tx.confirmed, isFalse);
    });
  });

  group('MempoolAddressUpdate', () {
    test('defaults newBlock to false', () {
      final update = MempoolAddressUpdate();
      expect(update.newBlock, isFalse);
      expect(update.newTx, isNull);
    });

    test('stores newTx', () {
      final update = MempoolAddressUpdate(newTx: {'txid': 'abc'});
      expect(update.newTx, {'txid': 'abc'});
    });

    test('stores newBlock', () {
      final update = MempoolAddressUpdate(newBlock: true);
      expect(update.newBlock, isTrue);
    });
  });

  group('fetchBlockTipHeight logic', () {
    late MockHttpClient mockHttp;
    late ApiClient apiClient;

    setUpAll(() {
      registerFallbackValue(FakeUri());
    });

    setUp(() {
      mockHttp = MockHttpClient();
      apiClient = ApiClient('https://mempool.space/api', client: mockHttp);
    });

    test('parses block height from raw response', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('850000', 200));

      final res = await apiClient.getRaw('/blocks/tip/height');
      expect(res.isSuccess, isTrue);
      final height = int.parse(res.data!.trim());
      expect(height, 850000);
    });

    test('error on non-2xx', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('error', 500));

      final res = await apiClient.getRaw('/blocks/tip/height');
      expect(res.isSuccess, isFalse);
    });
  });

  group('fetchAddressData logic', () {
    late MockHttpClient mockHttp;
    late ApiClient apiClient;

    setUpAll(() {
      registerFallbackValue(FakeUri());
    });

    setUp(() {
      mockHttp = MockHttpClient();
      apiClient = ApiClient('https://mempool.space/api', client: mockHttp);
    });

    test('parses address data correctly', () async {
      final responseBody = jsonEncode({
        'chain_stats': {
          'funded_txo_sum': 500000,
          'spent_txo_sum': 200000,
          'tx_count': 10,
        },
        'mempool_stats': {
          'funded_txo_sum': 50000,
          'spent_txo_sum': 10000,
          'tx_count': 2,
        },
      });

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(responseBody, 200));

      final res = await apiClient.get<Map<String, dynamic>>(
        '/address/bc1test',
        (json) => json as Map<String, dynamic>,
      );

      expect(res.isSuccess, isTrue);
      final data = res.data!;
      final chain = data['chain_stats'] as Map<String, dynamic>;
      final mempool = data['mempool_stats'] as Map<String, dynamic>;

      final fundedChain = (chain['funded_txo_sum'] as num).toInt();
      final spentChain = (chain['spent_txo_sum'] as num).toInt();
      final fundedMempool = (mempool['funded_txo_sum'] as num).toInt();
      final spentMempool = (mempool['spent_txo_sum'] as num).toInt();

      final totalFunded = fundedChain + fundedMempool;
      final totalSpent = spentChain + spentMempool;

      expect(totalFunded - totalSpent, 340000);
      expect(
        (chain['tx_count'] as num).toInt() +
            (mempool['tx_count'] as num).toInt(),
        12,
      );
    });
  });

  group('fetchAddressTransactions logic', () {
    late MockHttpClient mockHttp;
    late ApiClient apiClient;
    const address = 'bc1qtest';

    setUpAll(() {
      registerFallbackValue(FakeUri());
    });

    setUp(() {
      mockHttp = MockHttpClient();
      apiClient = ApiClient('https://mempool.space/api', client: mockHttp);
    });

    test('parses confirmed tx with balance change', () async {
      final txJson = [
        {
          'txid': 'tx1',
          'status': {
            'confirmed': true,
            'block_height': 800000,
            'block_time': 1700000000,
          },
          'fee': 250,
          'vout': [
            {'scriptpubkey_address': address, 'value': 100000},
            {'scriptpubkey_address': 'other', 'value': 50000},
          ],
          'vin': [
            {
              'prevout': {'scriptpubkey_address': 'other', 'value': 150000}
            },
          ],
        }
      ];

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode(txJson), 200));

      final res = await apiClient.get<List<dynamic>>(
        '/address/$address/txs',
        (json) => json as List<dynamic>,
      );

      expect(res.isSuccess, isTrue);
      final txList = res.data!;
      final tx = txList[0] as Map<String, dynamic>;
      final status = tx['status'] as Map<String, dynamic>;
      expect(status['confirmed'], isTrue);

      int received = 0;
      for (final output in (tx['vout'] as List)) {
        if (output['scriptpubkey_address'] == address) {
          received += (output['value'] as num).toInt();
        }
      }
      expect(received, 100000);
    });

    test('parses unconfirmed tx', () async {
      final txJson = [
        {
          'txid': 'tx2',
          'status': {'confirmed': false},
          'fee': 100,
          'vout': [
            {'scriptpubkey_address': address, 'value': 25000},
          ],
          'vin': [],
        }
      ];

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode(txJson), 200));

      final res = await apiClient.get<List<dynamic>>(
        '/address/$address/txs',
        (json) => json as List<dynamic>,
      );

      expect(res.isSuccess, isTrue);
      final tx = res.data![0] as Map<String, dynamic>;
      final status = tx['status'] as Map<String, dynamic>;
      expect(status['confirmed'], isFalse);
    });

    test('calculates sent correctly', () async {
      final txJson = [
        {
          'txid': 'tx3',
          'status': {'confirmed': true, 'block_height': 800001, 'block_time': 1700000100},
          'fee': 300,
          'vout': [
            {'scriptpubkey_address': 'other', 'value': 80000},
          ],
          'vin': [
            {
              'prevout': {'scriptpubkey_address': address, 'value': 100000}
            },
          ],
        }
      ];

      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode(txJson), 200));

      final res = await apiClient.get<List<dynamic>>(
        '/address/$address/txs',
        (json) => json as List<dynamic>,
      );

      final tx = res.data![0] as Map<String, dynamic>;
      int received = 0;
      int sent = 0;

      for (final output in (tx['vout'] as List)) {
        if (output['scriptpubkey_address'] == address) {
          received += (output['value'] as num).toInt();
        }
      }
      for (final input in (tx['vin'] as List)) {
        final prevout = input['prevout'] as Map<String, dynamic>?;
        if (prevout != null && prevout['scriptpubkey_address'] == address) {
          sent += (prevout['value'] as num).toInt();
        }
      }

      expect(received - sent, -100000);
    });

    test('handles empty tx list', () async {
      when(() => mockHttp.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(jsonEncode([]), 200));

      final res = await apiClient.get<List<dynamic>>(
        '/address/$address/txs',
        (json) => json as List<dynamic>,
      );

      expect(res.isSuccess, isTrue);
      expect(res.data, isEmpty);
    });
  });
}
