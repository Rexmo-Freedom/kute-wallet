import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/funding/settlement_stage.dart';

SwapOrder receiveRow() => SwapOrder(
    id: 'ord_receive',
    coinFrom: 'USDC',
    networkFrom: 'POLYGON',
    coinTo: 'BTC',
    networkTo: 'SPARK',
    depositAddress: 'deposit',
    depositAmount: '10',
    withdrawalAmount: '0.0001',
    status: 'success',
    timestamp: 1,
    withdrawalAddress: 'spark',
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: 'Orchestra',
    walletId: 'spending');

SettlementOperation operation(SettlementFlow flow,
        {String wallet = 'spending'}) =>
    SettlementOperation(
        operationId: 'operation',
        walletId: wallet,
        accountKind: SettlementAccountKind.pmHot,
        flow: flow,
        route: RouteKey(
            fromChain: 'polygon',
            fromAsset: 'USDC',
            toChain: 'spark',
            toAsset: 'BTC'),
        amountInBaseUnits: '10000000',
        stage: SettlementStage.settled,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026));

void main() {
  test('Polygon USDC received externally is not a Predictions withdrawal', () {
    expect(classifySwapActivity(receiveRow()), SwapActivityKind.receive);
  });
  test('Arbitrum USDC alone is not Investing activity', () {
    expect(classifySwapActivity(receiveRow().copyWith(networkFrom: 'ARBITRUM')),
        SwapActivityKind.receive);
  });
  test('external send keeps its intent through status and ID updates', () {
    final row = receiveRow()
        .copyWith(activityDirection: 'send')
        .copyWith(id: 'ord_final', status: 'settled');
    expect(classifySwapActivity(row), SwapActivityKind.send);
  });
  test('actual withdrawal keeps its label using matching wallet operation', () {
    final row = receiveRow().copyWith(operationId: 'operation');
    expect(
        classifySwapActivity(row,
            operation: operation(SettlementFlow.predictionsWithdraw)),
        SwapActivityKind.predictionsWithdrawal);
    expect(
        classifySwapActivity(row,
            operation:
                operation(SettlementFlow.predictionsWithdraw, wallet: 'other')),
        SwapActivityKind.receive);
  });
  test('explicit receive and purchase override token/network guesses', () {
    expect(
        classifySwapActivity(
            receiveRow().copyWith(activityDirection: 'receive'),
            predictionFlowTagged: true),
        SwapActivityKind.receive);
    expect(
        classifySwapActivity(receiveRow().copyWith(purchaseSource: 'cashapp')),
        SwapActivityKind.purchase);
  });
}
