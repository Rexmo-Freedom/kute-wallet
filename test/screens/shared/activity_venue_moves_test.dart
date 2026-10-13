// A venue move (money into or out of Predictions or Investing) is one row
// on every activity surface for a balance it moved, from the moment it
// starts. The leg that settled it (a Spark payment or a dollar transfer)
// is hidden only behind that row; when the row is missing, the leg stays
// visible. Never both gone.
//
// The bug this pins: a Predictions cash-out to dollars vanished from Home.
// Its dollar receive was hidden behind the conversion row, and the
// bitcoin-ledger filter then dropped that row, because it touches no
// bitcoin. A cash-out to bitcoin made a few minutes after a claim vanished
// the same way: hidden behind the "won" row, which Home does not show.
//
// And its mirror (owner decision October 2026): a move whose two sides
// are Dollars and a venue moved no bitcoin, so the bitcoin surfaces (Home,
// its "See all", the Breakdown) list neither the move nor its dollar
// transfer. It is one row on Dollars and in the Investments activity.

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

    test('Home lists neither the withdrawal nor its dollar receive', () {
      expect(_ids(_surface([cashOut, arrived], kinds: linked)), isEmpty);
      expect(_ids(_surface([cashOut], kinds: linked)), isEmpty);
    });

    test('the row is there while pending, before the dollars arrive', () {
      expect(_ids(_surface([cashOut], kinds: linked, onlyUsdb: true)),
          ['ord_pm_usd']);
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
    test('a cash-out to dollars is off Home and one row on Dollars', () {
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
      const kinds = {'ord_hl_usd': SwapActivityKind.investingWithdrawal};
      expect(_ids(_surface([cashOut, arrived], kinds: kinds)), isEmpty);
      expect(_ids(_surface([cashOut, arrived], kinds: kinds, onlyUsdb: true)),
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
    test('Dollars into Predictions is off Home and one row on the USD tab', () {
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
      expect(_ids(_surface([deposit, left], kinds: kinds)), isEmpty);
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

  // The founder's Bitcoin tab: "Withdraw · from Investing · \$0.00 · from
  // \$6.28" and "Deposit · to Investing · \$6.54 · from \$6.60". The bitcoin
  // surfaces list a conversion only when bitcoin moved.
  group('the bitcoin side lists only moves of bitcoin', () {
    SwapOrderTransaction move(String id,
            {required String coinFrom,
            required String networkFrom,
            required String coinTo,
            required String networkTo,
            String depositAmount = '6.60',
            String withdrawalAmount = '6.54'}) =>
        _swap(
          id: id,
          coinFrom: coinFrom,
          networkFrom: networkFrom,
          coinTo: coinTo,
          networkTo: networkTo,
          depositAmount: depositAmount,
          withdrawalAmount: withdrawalAmount,
          status: 'success',
        );

    final dollarsToInvesting = move('ord_usd_hl',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'HYPERCORE');
    final investingSweep = move('ord_hl_sweep',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '6.28',
        withdrawalAmount: '6.20');
    final predictionsSweep = move('ord_pm_sweep',
        coinFrom: 'USDC.E',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '3.00',
        withdrawalAmount: '2.95');
    final dollarsToPredictions = move('ord_usd_pm2',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'POLYGON',
        depositAmount: '5.00',
        withdrawalAmount: '4.95');
    final venueToVenue = move('ord_pm_hl',
        coinFrom: 'USDC.E',
        networkFrom: 'POLYGON',
        coinTo: 'USDC',
        networkTo: 'HYPERCORE');
    final bitcoinToInvesting = move('ord_btc_hl',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'HYPERCORE',
        depositAmount: '0.00008002',
        withdrawalAmount: '6.60');
    final investingToBitcoin = move('ord_hl_btc2',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        depositAmount: '6.66',
        withdrawalAmount: '0.00008002');
    final bitcoinToDollars = move('ord_btc_usd',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '0.00008002',
        withdrawalAmount: '6.60');
    const kinds = {
      'ord_usd_hl': SwapActivityKind.investingDeposit,
      'ord_hl_sweep': SwapActivityKind.investingWithdrawal,
      'ord_pm_sweep': SwapActivityKind.predictionsWithdrawal,
      'ord_usd_pm2': SwapActivityKind.predictionsDeposit,
      'ord_pm_hl': SwapActivityKind.investingDeposit,
      'ord_btc_hl': SwapActivityKind.investingDeposit,
      'ord_hl_btc2': SwapActivityKind.investingWithdrawal,
      'ord_btc_usd': SwapActivityKind.dollarDeposit,
    };
    // Each Dollars move's own dollar transfer.
    final leftForInvesting = _dollars('usd_out_hl',
        usd: 6.60,
        type: breez.PaymentType.send,
        at: _t0.add(const Duration(seconds: 10)));
    final sweptHome = _dollars('usd_in_sweep',
        usd: 6.20,
        type: breez.PaymentType.receive,
        at: _t0.add(const Duration(minutes: 4)));
    final unrelated = _dollars('usd_in_other',
        usd: 42,
        type: breez.PaymentType.receive,
        at: _t0.add(const Duration(minutes: 20)));

    final all = <BaseTransaction>[
      dollarsToInvesting,
      investingSweep,
      predictionsSweep,
      dollarsToPredictions,
      venueToVenue,
      bitcoinToInvesting,
      investingToBitcoin,
      bitcoinToDollars,
      leftForInvesting,
      sweptHome,
      unrelated,
    ];

    test('Dollars and venue moves are off Home, their dollar legs with them',
        () {
      final home = _ids(_surface(all, kinds: kinds)).toSet();
      expect(
          home.intersection({
            'ord_usd_hl',
            'ord_hl_sweep',
            'ord_pm_sweep',
            'ord_usd_pm2',
            'ord_pm_hl',
            'usd_out_hl',
            'usd_in_sweep',
          }),
          isEmpty);
    });

    test('bitcoin into or out of a venue or Dollars stays on Home', () {
      final home = _ids(_surface(all, kinds: kinds)).toSet();
      expect(home.containsAll({'ord_btc_hl', 'ord_hl_btc2', 'ord_btc_usd'}),
          isTrue);
    });

    test('an unrelated dollar transfer stays where it was', () {
      expect(_ids(_surface(all, kinds: kinds)), contains('usd_in_other'));
    });

    test('the Breakdown reads the same bitcoin rows', () {
      final sorted = [...all]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final rows = assembleActivityRows(
        sorted,
        ownAddresses: {_self},
        isHardwareOrWatchOnly: false,
        onlyUsdb: false,
        keepVenueMoves: true,
        classify: (o) => kinds[o.id] ?? classifySwapActivity(o),
      );
      final swaps = {
        for (final r in rows)
          if (r is SwapOrderTransaction) r.id
      };
      expect(swaps, {'ord_btc_hl', 'ord_hl_btc2', 'ord_btc_usd'});
    });

    test('the Dollars ledger still lists each Dollars move once', () {
      final usd = _ids(_surface(all, kinds: kinds, onlyUsdb: true));
      for (final id in [
        'ord_usd_hl',
        'ord_hl_sweep',
        'ord_pm_sweep',
        'ord_usd_pm2',
      ]) {
        expect(usd.where((x) => x == id), hasLength(1), reason: id);
      }
      expect(usd, isNot(contains('usd_out_hl')));
      expect(usd, isNot(contains('usd_in_sweep')));
    });

    test('a Ledger wallet keeps its venue moves of bitcoin', () {
      final ledgerDeposit = move('ord_ledger_hl',
          coinFrom: 'BTC',
          networkFrom: 'BITCOIN',
          coinTo: 'USDC',
          networkTo: 'HYPERCORE',
          depositAmount: '0.00100000',
          withdrawalAmount: '99.00');
      expect(
          _ids(_surface([ledgerDeposit],
              kinds: {'ord_ledger_hl': SwapActivityKind.investingDeposit},
              hardware: true)),
          ['ord_ledger_hl']);
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
      await box.put(
        'op-cctp',
        SettlementCodec.encodeJson(SettlementOperation(
          operationId: 'op-cctp',
          walletId: 'spending',
          accountKind: SettlementAccountKind.hlHot,
          flow: SettlementFlow.investingToDollarsCctp,
          route: RouteKey(
              fromChain: 'hypercore',
              fromAsset: 'USDC',
              toChain: 'spark',
              toAsset: kOrchestraUsdAssetCode),
          amountInBaseUnits: '6280000',
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

    test('a Predictions cash-out to dollars reads as one Dollars row', () {
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
      List<String> on({required bool onlyUsdb}) => _ids(assembleActivityRows(
            [arrived, cashOut],
            ownAddresses: {_self},
            isHardwareOrWatchOnly: false,
            onlyUsdb: onlyUsdb,
          ));
      expect(on(onlyUsdb: true), ['ord_real']);
      expect(on(onlyUsdb: false), isEmpty);
    });

    test('the Circle CCTP withdrawal to Dollars stays off the bitcoin side',
        () {
      final cctp = _swap(
        id: 'ord_cctp',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '6.28',
        withdrawalAmount: '0.00',
        operationId: 'op-cctp',
      );
      expect(
          swapActivityFor(cctp.details), SwapActivityKind.investingWithdrawal);
      List<String> on({required bool onlyUsdb, bool keep = false}) =>
          _ids(assembleActivityRows(
            [cctp],
            ownAddresses: {_self},
            isHardwareOrWatchOnly: false,
            onlyUsdb: onlyUsdb,
            keepVenueMoves: keep,
          ));
      expect(on(onlyUsdb: false), isEmpty);
      // The Breakdown's pass reads the same rows.
      expect(on(onlyUsdb: false, keep: true), isEmpty);
      expect(on(onlyUsdb: true), ['ord_cctp']);
    });

    group('a CCTP sweep whose dollars Orchestra held for 42 minutes', () {
      // The founder's screenshot: "Withdraw · from Investing · 12:54 ·
      // $6.20 · from $6.28" and "Deposit · 13:36 · $6.20" for one sweep.
      final cctp = _swap(
        id: 'ord_cctp_late',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '6.28',
        withdrawalAmount: '6.20',
        status: 'success',
        operationId: 'op-cctp',
      );
      final landed = _dollars('usd_in_late',
          usd: 6.20,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 42)));
      List<String> on(List<BaseTransaction> rows, {required bool onlyUsdb}) {
        final sorted = [...rows]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return _ids(assembleActivityRows(
          sorted,
          ownAddresses: {_self},
          isHardwareOrWatchOnly: false,
          onlyUsdb: onlyUsdb,
        ));
      }

      test('is one row on Dollars and in the Portfolio activity', () {
        expect(on([cctp, landed], onlyUsdb: true), ['ord_cctp_late']);
      });

      test('leaves nothing on the bitcoin side', () {
        expect(on([cctp, landed], onlyUsdb: false), isEmpty);
      });

      test('an unrelated \$6.20 receive later keeps its own row', () {
        final friend = _dollars('usd_in_friend',
            usd: 6.20,
            type: breez.PaymentType.receive,
            at: _t0.add(const Duration(hours: 3)));
        expect(on([cctp, landed, friend], onlyUsdb: true),
            ['usd_in_friend', 'ord_cctp_late']);
      });

      test('a \$6.20 receive before the sweep started keeps its own row', () {
        final before = _dollars('usd_in_before',
            usd: 6.20,
            type: breez.PaymentType.receive,
            at: _t0.subtract(const Duration(hours: 2)));
        expect(on([cctp, before], onlyUsdb: true),
            ['ord_cctp_late', 'usd_in_before']);
      });

      test('another amount 42 minutes later is not its arrival', () {
        final other = _dollars('usd_in_other',
            usd: 6.15,
            type: breez.PaymentType.receive,
            at: _t0.add(const Duration(minutes: 42)));
        expect(on([cctp, other], onlyUsdb: true),
            ['usd_in_other', 'ord_cctp_late']);
      });

      test('a failed sweep takes no arrival', () {
        final failed = _swap(
          id: 'ord_cctp_failed',
          coinFrom: 'USDC',
          networkFrom: 'HYPERCORE',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          depositAmount: '6.28',
          withdrawalAmount: '6.20',
          status: 'failed',
          operationId: 'op-cctp',
        );
        expect(on([failed, landed], onlyUsdb: true),
            ['usd_in_late', 'ord_cctp_failed']);
      });
    });
  });

  group('venue withdrawals Orchestra holds past half an hour', () {
    test('a Predictions sweep to Dollars landing an hour later is one row',
        () {
      final sweep = _swap(
        id: 'ord_pm_late',
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '10.00',
        withdrawalAmount: '9.85',
        status: 'success',
      );
      final landed = _dollars('usd_in_pm_late',
          usd: 9.85,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 65)));
      const kinds = {'ord_pm_late': SwapActivityKind.predictionsWithdrawal};
      expect(_ids(_surface([sweep, landed], kinds: kinds, onlyUsdb: true)),
          ['ord_pm_late']);
      expect(_ids(_surface([sweep, landed], kinds: kinds)), isEmpty);
    });

    test('the direct HyperCore route landing late is one row', () {
      final sweep = _swap(
        id: 'ord_hl_late',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '20.00',
        withdrawalAmount: '19.90',
      );
      final landed = _dollars('usd_in_hl_late',
          usd: 19.90,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 50)));
      const kinds = {'ord_hl_late': SwapActivityKind.investingWithdrawal};
      expect(_ids(_surface([sweep, landed], kinds: kinds, onlyUsdb: true)),
          ['ord_hl_late']);
    });

    test('a withdrawal to someone else\'s address takes no late receive', () {
      final foreign = _swap(
        id: 'ord_foreign',
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '10.00',
        withdrawalAmount: '9.85',
        withdrawalAddress: 'sp1someoneelse',
      );
      final receive = _dollars('usd_in_unrelated',
          usd: 9.85,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 65)));
      const kinds = {'ord_foreign': SwapActivityKind.predictionsWithdrawal};
      expect(_ids(_surface([foreign, receive], kinds: kinds, onlyUsdb: true)),
          ['usd_in_unrelated', 'ord_foreign']);
    });
  });
}
