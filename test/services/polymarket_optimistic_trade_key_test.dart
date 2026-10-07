// A buy's or sell's optimistic Activity row is keyed by what the CLOB
// `POST /order` answer names. Since 2026-07-24 that is `tradeIDs` (no
// `transactionsHashes` on FAK/FOK matches): a trade id is not a chain
// hash, so the row is recorded as `clob-trade:<id>` and never linked to an
// explorer; it is still evicted once the Data API lists the fill.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:kute/services/transaction_pdf_export.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Activity;

const _chainHash =
    '0x9f1c3d6a2b7e4f5081a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708';
const _orderId =
    '0x4b2e0c7d9a8f6e5d4c3b2a1908f7e6d5c4b3a29180f7e6d5c4b3a29180f7e6d5';
const _tradeId = '0f9c2a1e-7b3d-4c58-9e6a-2d1b0c9f8e7a';

Activity _sell(String key,
        {double usdc = 1.39, int? timestamp, String side = 'SELL'}) =>
    Activity(
      proxyWallet: '0xproxy',
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      conditionId: 'cond',
      type: 'TRADE',
      size: 9.96,
      usdcSize: usdc,
      transactionHash: key,
      price: usdc / 9.96,
      asset: 'no-token',
      side: side,
    );

void main() {
  group('optimisticTradeKey', () {
    test('a matched order answers with tradeIDs only: keyed as a trade', () {
      // The documented success shape after the async pipeline rollout.
      final key = PolymarketOptimisticActivityService.optimisticTradeKey({
        'success': true,
        'errorMsg': '',
        'orderID': _orderId,
        'status': 'matched',
        'makingAmount': '9.96',
        'takingAmount': '1.39',
        'tradeIDs': [_tradeId],
      });
      expect(key, 'clob-trade:$_tradeId');
      expect(PolymarketOptimisticActivityService.isChainTxHash(key!), isFalse);
    });

    test('an empty transactionsHashes list does not hide the trade id', () {
      expect(
          PolymarketOptimisticActivityService.optimisticTradeKey({
            'orderID': _orderId,
            'transactionsHashes': [],
            'tradeIDs': [_tradeId],
          }),
          'clob-trade:$_tradeId');
    });

    test('a filled BUY answer is keyed by its trade, not the order hash', () {
      // The order id is 0x + 64 hex, shaped like a chain hash: it must not
      // be stored where a transaction hash is read.
      final key = PolymarketOptimisticActivityService.optimisticTradeKey({
        'success': true,
        'errorMsg': '',
        'orderID': _orderId,
        'status': 'matched',
        'makingAmount': '2.80',
        'takingAmount': '18.6',
        'transactionsHashes': [],
        'tradeIDs': [_tradeId],
      });
      expect(key, 'clob-trade:$_tradeId');
      expect(
          PolymarketOptimisticActivityService.isChainTxHash(_orderId), isTrue,
          reason: 'why the raw order id cannot be the key');
    });

    test('a real chain hash is still used as the hash', () {
      final key = PolymarketOptimisticActivityService.optimisticTradeKey({
        'orderID': _orderId,
        'transactionsHashes': [_chainHash],
        'tradeIDs': [_tradeId],
      });
      expect(key, _chainHash);
      expect(PolymarketOptimisticActivityService.isChainTxHash(key!), isTrue);
    });

    test('falls back to the order id, then to nothing', () {
      final key = PolymarketOptimisticActivityService.optimisticTradeKey({
        'orderID': _orderId,
        'tradeIDs': [],
      });
      expect(key, 'clob-order:$_orderId');
      expect(PolymarketOptimisticActivityService.isChainTxHash(key!), isFalse);
      expect(
          PolymarketOptimisticActivityService.optimisticTradeKey(
              {'orderID': '', 'tradeIDs': null}),
          isNull);
    });
  });

  group('dedupe of a trade-keyed row', () {
    late Directory dir;
    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('pm_sell_key');
      Hive.init(dir.path);
      await Hive.openBox<String>('polymarket_optimistic_activity');
    });
    tearDown(() async {
      await Hive.box<String>('polymarket_optimistic_activity').clear();
    });
    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('a trade-keyed BUY is evicted by its Data API fill', () {
      PolymarketOptimisticActivityService.record(
          _sell('clob-trade:$_tradeId', usdc: 2.80, side: 'BUY'));
      expect(PolymarketOptimisticActivityService.snapshot(), hasLength(1));
      final settled = _sell(_chainHash, usdc: 2.79, side: 'BUY');
      expect(
          PolymarketOptimisticActivityService.snapshot(
              confirmedHashes: {_chainHash}, confirmed: [settled]),
          isEmpty);
    });

    test('stays until the Data API lists the fill, then is evicted', () {
      PolymarketOptimisticActivityService.record(_sell('clob-trade:$_tradeId'));
      final pending = PolymarketOptimisticActivityService.snapshot();
      expect(pending.single.transactionHash, 'clob-trade:$_tradeId');

      // The indexed fill carries the chain hash and a slightly different
      // amount; the trade-shape match evicts the optimistic copy.
      final settled = _sell(_chainHash, usdc: 1.385);
      expect(
          PolymarketOptimisticActivityService.snapshot(
              confirmedHashes: {_chainHash}, confirmed: [settled]),
          isEmpty);
      expect(PolymarketOptimisticActivityService.snapshot(), isEmpty);
    });
  });

  group('PDF export txid', () {
    final wallet = WalletConfig(id: 'w', name: 'Spending');
    String txidOf(String key, {String side = 'BUY'}) {
      final a = _sell(key, side: side);
      return TransactionPdfExport.enrichForTest(
              PolymarketTransaction(
                  id: '${key}_${a.timestamp}',
                  timestamp: a.timestampDate,
                  activity: a),
              wallet)!
          .txid;
    }

    test('a CLOB trade or order key prints no txid', () {
      expect(txidOf('clob-trade:$_tradeId'), '');
      expect(txidOf('clob-order:$_orderId', side: 'SELL'), '');
    });

    test('a chain hash prints as the txid', () {
      expect(txidOf(_chainHash), _chainHash);
    });
  });
}
