// A venue move (money into or out of Predictions or Investing) is one row
// on every activity surface, from the moment it starts. The leg that
// settled it (a Spark payment or a dollar transfer) is hidden only behind
// that row; when the row is missing, the leg stays visible. Never both gone.
//
// The bug this pins: a Predictions cash-out to dollars vanished from Home.
// Its dollar receive was hidden behind the conversion row, and the
// bitcoin-ledger filter then dropped that row, because it touches no
// bitcoin. A cash-out to bitcoin made a few minutes after a claim vanished
// the same way: hidden behind the "won" row, which Home does not show.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/funding/settlement_codec.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 10, 5, 12);

SwapOrderTransaction _swap({
  required String id,
  required String coinFrom,
  required String networkFrom,
  required String coinTo,
  required String networkTo,
  required String depositAmount,
  required String withdrawalAmount,
  String status = 'exchanging',
  DateTime? at,
  String? operationId,
  String? activityDirection,
  String? withdrawalAddress,
}) {
  final ts = at ?? _t0;
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: false,
    details: SwapOrder(
      id: id,
      activityDirection: activityDirection,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'deposit-$id',
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress:
          withdrawalAddress ?? (networkTo == 'SPARK' ? _self : '0xsafe'),
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: operationId,
    ),
  );
}

UsdbTokenTransaction _dollars(String id,
        {required double usd,
        required breez.PaymentType type,
        required DateTime at}) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: type,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

SparkTransaction _spark(String id,
        {required int sats,
        required TransactionType direction,
        required DateTime at}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: direction,
      pending: false,
    );

PolymarketTransaction _prediction(String type, {required DateTime at}) =>
    PolymarketTransaction(
      id: '0xhash-$type',
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xsafe',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xcondition',
        type: type,
        size: 10,
        usdcSize: 10,
        transactionHash: '0xhash-$type',
        side: type == 'TRADE' ? 'BUY' : null,
      ),
    );

/// A Home or USD-tab pass with the conversions' intent given per id.
List<BaseTransaction> _surface(
  List<BaseTransaction> rows, {
  required Map<String, SwapActivityKind> kinds,
  bool onlyUsdb = false,
  bool hardware = false,
}) {
  final sorted = [...rows]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return assembleActivityRows(
    sorted,
    ownAddresses: {_self},
    isHardwareOrWatchOnly: hardware,
    onlyUsdb: onlyUsdb,
    classify: (o) => kinds[o.id] ?? classifySwapActivity(o),
  );
}

List<String> _ids(List<BaseTransaction> rows) =>
    [for (final r in rows) r.id];

void main() {
  group('Predictions cash-out to dollars', () {
    final cashOut = _swap(
      id: 'ord_pm_usd',
      coinFrom: 'USDC',
      networkFrom: 'POLYGON',
      coinTo: kOrchestraUsdAssetCode,
      networkTo: 'SPARK',
      depositAmount: '10.00',
      withdrawalAmount: '9.85',
    );
    final arrived = _dollars('usd_in',
        usd: 9.85,
        type: breez.PaymentType.receive,
        at: _t0.add(const Duration(minutes: 3)));
    const linked = {'ord_pm_usd': SwapActivityKind.predictionsWithdrawal};

    test('Home shows one Predictions withdrawal row and hides the receive',
        () {
      expect(_ids(_surface([cashOut, arrived], kinds: linked)),
          ['ord_pm_usd']);
    });

    test('the row is there while pending, before the dollars arrive', () {
      expect(_ids(_surface([cashOut], kinds: linked)), ['ord_pm_usd']);
    });

    test('the USD tab shows the same single row', () {
      expect(
          _ids(_surface([cashOut, arrived], kinds: linked, onlyUsdb: true)),
          ['ord_pm_usd']);
    });

    test('with no link to the move, the dollar receive stays visible', () {
      // No settlement record: the conversion reads as a plain dollar
      // conversion, which Home leaves to the USD tab. The receive is
      // then the only trace of the money and must show.
      expect(_ids(_surface([cashOut, arrived], kinds: const {})),
          ['usd_in']);
    });
  });

  group('Predictions cash-out to bitcoin', () {
    final cashOut = _swap(
      id: 'ord_pm_btc',
      coinFrom: 'USDC',
      networkFrom: 'POLYGON',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAmount: '10.00',
      withdrawalAmount: '0.00010000',
    );
    final arrived = _spark('btc_in',
        sats: 10000,
        direction: TransactionType.received,
        at: _t0.add(const Duration(minutes: 4)));
    const linked = {'ord_pm_btc': SwapActivityKind.predictionsWithdrawal};

    test('one row, the receive hidden behind it', () {
      expect(_ids(_surface([cashOut, arrived], kinds: linked)),
          ['ord_pm_btc']);
    });

    test('a claim just before it no longer hides the withdrawal', () {
      final won =
          _prediction('REDEEM', at: _t0.subtract(const Duration(minutes: 5)));
      expect(_ids(_surface([won, cashOut, arrived], kinds: linked)),
          ['ord_pm_btc']);
    });

    test('a receive with no withdrawal row beside it stays visible', () {
      expect(_ids(_surface([arrived], kinds: linked)), ['btc_in']);
    });
  });

  group('Investing', () {
    test('a cash-out to dollars is one row on Home', () {
      final cashOut = _swap(
        id: 'ord_hl_usd',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '20.00',
        withdrawalAmount: '19.90',
      );
      final arrived = _dollars('usd_in_hl',
          usd: 19.9,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 2)));
      expect(
          _ids(_surface([cashOut, arrived],
              kinds: {'ord_hl_usd': SwapActivityKind.investingWithdrawal})),
          ['ord_hl_usd']);
    });

    test('a cash-out to bitcoin is one row on Home', () {
      final cashOut = _swap(
        id: 'ord_hl_btc',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        depositAmount: '20.00',
        withdrawalAmount: '0.00020000',
      );
      final arrived = _spark('btc_in_hl',
          sats: 19800,
          direction: TransactionType.received,
          at: _t0.add(const Duration(minutes: 6)));
      expect(
          _ids(_surface([cashOut, arrived],
              kinds: {'ord_hl_btc': SwapActivityKind.investingWithdrawal})),
          ['ord_hl_btc']);
    });
  });

  group('venue deposits', () {
    test('Dollars into Predictions is one row on Home and on the USD tab',
        () {
      final deposit = _swap(
        id: 'ord_usd_pm',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'POLYGON',
        depositAmount: '15.00',
        withdrawalAmount: '14.90',
      );
      final left = _dollars('usd_out',
          usd: 15,
          type: breez.PaymentType.send,
          at: _t0.add(const Duration(seconds: 20)));
      const kinds = {'ord_usd_pm': SwapActivityKind.predictionsDeposit};
      expect(_ids(_surface([deposit, left], kinds: kinds)), ['ord_usd_pm']);
      expect(_ids(_surface([deposit, left], kinds: kinds, onlyUsdb: true)),
          ['ord_usd_pm']);
    });

    test('bitcoin into Predictions keeps its row next to a placed prediction',
        () {
      final deposit = _swap(
        id: 'ord_btc_pm',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'POLYGON',
        depositAmount: '0.00010000',
        withdrawalAmount: '9.90',
      );
      final funding = _spark('btc_out',
          sats: 10000,
          direction: TransactionType.sent,
          at: _t0.add(const Duration(seconds: 30)));
      final placed =
          _prediction('TRADE', at: _t0.add(const Duration(minutes: 8)));
      expect(
          _ids(_surface([deposit, funding, placed],
              kinds: {'ord_btc_pm': SwapActivityKind.predictionsDeposit})),
          ['ord_btc_pm']);
    });

    test('a Ledger venue deposit keeps its on-chain leg and its row', () {
      final deposit = _swap(
        id: 'ord_ledger_pm',
        coinFrom: 'BTC',
        networkFrom: 'BITCOIN',
        coinTo: 'USDC',
        networkTo: 'POLYGON',
        depositAmount: '0.00100000',
        withdrawalAmount: '99.00',
      );
      final rows = _surface([deposit],
          kinds: {'ord_ledger_pm': SwapActivityKind.predictionsDeposit},
          hardware: true);
      expect(_ids(rows), ['ord_ledger_pm']);
    });
  });

  // João on his phone: paying someone's bitcoin address from Dollars
  // showed on Home and the Bitcoin wallet as a bitcoin "Sent". The Dollars
  // send screen records an Orchestra order (USDB on Spark → the
  // recipient's BTC, activityDirection 'send') and funds it with a dollar
  // token transfer to the order's deposit address. Because the order
  // delivers BTC, the bitcoin-side filter kept it. A send belongs to the
  // balance that paid it: Dollars only, as one row.
  group('sends paid from Dollars', () {
    SwapOrderTransaction dollarSend(String id,
            {required String coinTo,
            required String networkTo,
            required String withdrawalAmount,
            required String to}) =>
        _swap(
          id: id,
          activityDirection: 'send',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          coinTo: coinTo,
          networkTo: networkTo,
          depositAmount: '25.00',
          withdrawalAmount: withdrawalAmount,
          withdrawalAddress: to,
        );
    final funding = _dollars('usd_out_send',
        usd: 25,
        type: breez.PaymentType.send,
        at: _t0.add(const Duration(seconds: 12)));

    test('to a bitcoin address: nothing on Home, one row on Dollars', () {
      final send = dollarSend('ord_usd_to_btc',
          coinTo: 'BTC',
          networkTo: 'BITCOIN',
          withdrawalAmount: '0.00021450',
          to: 'bc1qrecipientaddress0000000000000000000000');
      expect(_ids(_surface([send, funding], kinds: const {})), isEmpty);
      expect(_ids(_surface([send, funding], kinds: const {}, onlyUsdb: true)),
          ['ord_usd_to_btc']);
    });

    test('to a Lightning invoice: nothing on Home, one row on Dollars', () {
      final send = dollarSend('ord_usd_to_ln',
          coinTo: 'BTC',
          networkTo: 'LIGHTNING',
          withdrawalAmount: '0.00021450',
          to: 'lnbc214500n1recipientinvoice');
      expect(_ids(_surface([send, funding], kinds: const {})), isEmpty);
      expect(_ids(_surface([send, funding], kinds: const {}, onlyUsdb: true)),
          ['ord_usd_to_ln']);
    });

    test('to a dollar address: its funding transfer leaves Home too', () {
      final send = dollarSend('ord_usd_to_base',
          coinTo: 'USDC',
          networkTo: 'BASE',
          withdrawalAmount: '24.80',
          to: '0xrecipient');
      expect(_ids(_surface([send, funding], kinds: const {})), isEmpty);
      expect(_ids(_surface([send, funding], kinds: const {}, onlyUsdb: true)),
          ['ord_usd_to_base']);
    });

    test('an unrelated dollar transfer beside it stays where it was', () {
      final send = dollarSend('ord_usd_to_btc2',
          coinTo: 'BTC',
          networkTo: 'BITCOIN',
          withdrawalAmount: '0.00021450',
          to: 'bc1qrecipientaddress0000000000000000000000');
      final other = _dollars('usd_out_other',
          usd: 7,
          type: breez.PaymentType.send,
          at: _t0.add(const Duration(minutes: 2)));
      expect(_ids(_surface([send, funding, other], kinds: const {})),
          ['usd_out_other']);
    });

    test('a bitcoin send stays on the bitcoin side and off Dollars', () {
      final send = _swap(
        id: 'ord_btc_to_usdb',
        activityDirection: 'send',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '0.00030000',
        withdrawalAmount: '29.70',
        withdrawalAddress: 'sp1someoneelse',
      );
      final paid = _spark('btc_out_send',
          sats: 30000,
          direction: TransactionType.sent,
          at: _t0.add(const Duration(seconds: 15)));
      expect(_ids(_surface([send, paid], kinds: const {})),
          ['ord_btc_to_usdb']);
      expect(_ids(_surface([send, paid], kinds: const {}, onlyUsdb: true)),
          isEmpty);
    });

    // The send screen saves the quote's estimate to two decimals, so a
    // fresh send to bitcoin holds "0.00" until the first status check
    // writes the delivered amount. The row (and its detail sheet header)
    // shows no "→ ₿0" figure until then.
    test('the delivered figure waits for the real bitcoin amount', () {
      SwapOrder order(String coinTo, String delivered) => dollarSend(
            'ord_figure_$coinTo',
            coinTo: coinTo,
            networkTo: coinTo == 'BTC' ? 'BITCOIN' : 'BASE',
            withdrawalAmount: delivered,
            to: 'recipient',
          ).details;
      expect(dollarSendDeliveredKnown(order('BTC', '0.00')), isFalse);
      expect(dollarSendDeliveredKnown(order('BTC', '')), isFalse);
      expect(dollarSendDeliveredKnown(order('BTC', '0.000000004')), isFalse);
      expect(dollarSendDeliveredKnown(order('BTC', '0.00021450')), isTrue);
      expect(dollarSendDeliveredKnown(order('BTC', '0.00000001')), isTrue);
      expect(dollarSendDeliveredKnown(order('USDC', '0.00')), isFalse);
      expect(dollarSendDeliveredKnown(order('USDC', '24.80')), isTrue);
    });

    test('a plain bitcoin send with no order still shows on Home', () {
      final paid = _spark('btc_out_plain',
          sats: 30000,
          direction: TransactionType.sent,
          at: _t0.add(const Duration(seconds: 15)));
      expect(_ids(_surface([paid], kinds: const {})), ['btc_out_plain']);
    });

    test('Dollars into own Bitcoin is still one row on Home and on Dollars',
        () {
      final buy = _swap(
        id: 'ord_usd_btc_own',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        depositAmount: '25.00',
        withdrawalAmount: '0.00021450',
      );
      final arrived = _spark('btc_in_own',
          sats: 21450,
          direction: TransactionType.received,
          at: _t0.add(const Duration(minutes: 1)));
      final rows = [buy, funding, arrived];
      expect(_ids(_surface(rows, kinds: const {})), ['ord_usd_btc_own']);
      expect(_ids(_surface(rows, kinds: const {}, onlyUsdb: true)),
          ['ord_usd_btc_own']);
    });
  });

  group('with the real settlement record', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('activity_venue_moves');
      Hive.init(dir.path);
      final box = await Hive.openBox<String>(SettlementStore.boxName);
      await box.put(
        'op-cashout',
        SettlementCodec.encodeJson(SettlementOperation(
          operationId: 'op-cashout',
          walletId: 'spending',
          accountKind: SettlementAccountKind.pmHot,
          flow: SettlementFlow.movePredictionsToDollars,
          route: RouteKey(
              fromChain: 'polygon',
              fromAsset: 'USDC.e',
              toChain: 'spark',
              toAsset: kOrchestraUsdAssetCode),
          amountInBaseUnits: '10000000',
          stage: SettlementStage.submitted,
          createdAt: _t0,
          updatedAt: _t0,
        )),
      );
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a Predictions cash-out to dollars reads and shows as one row', () {
      final cashOut = _swap(
        id: 'ord_real',
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '10.00',
        withdrawalAmount: '9.85',
        operationId: 'op-cashout',
      );
      expect(swapActivityFor(cashOut.details),
          SwapActivityKind.predictionsWithdrawal);
      final arrived = _dollars('usd_in_real',
          usd: 9.85,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 3)));
      final rows = assembleActivityRows(
        [arrived, cashOut],
        ownAddresses: {_self},
        isHardwareOrWatchOnly: false,
        onlyUsdb: false,
      );
      expect(_ids(rows), ['ord_real']);
    });
  });
}
