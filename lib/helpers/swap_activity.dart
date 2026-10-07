import 'package:hive_ce/hive.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/funding/settlement_codec.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';

enum SwapActivityKind {
  purchase,
  send,
  receive,
  predictionsDeposit,
  predictionsWithdrawal,
  investingDeposit,
  investingWithdrawal,
  dollarDeposit,
  dollarWithdrawal,
  swap;

  bool get isPredictions =>
      this == predictionsDeposit || this == predictionsWithdrawal;
  bool get isInvesting =>
      this == investingDeposit || this == investingWithdrawal;
  bool get isDollars => this == dollarDeposit || this == dollarWithdrawal;
  bool get isExternal => this == send || this == receive;
  bool get isDeposit =>
      this == predictionsDeposit ||
      this == investingDeposit ||
      this == dollarDeposit;
}

/// Pure classification: a shared asset/network is not evidence of a venue
/// move. Old rows without recorded intent keep a generic conversion label.
SwapActivityKind classifySwapActivity(SwapOrder order,
    {SettlementOperation? operation, bool predictionFlowTagged = false}) {
  if (order.isCashAppPurchase) return SwapActivityKind.purchase;
  if (order.activityDirection == 'send') return SwapActivityKind.send;
  if (order.activityDirection == 'receive' ||
      order.purchaseSource == 'crypto_receive') {
    return SwapActivityKind.receive;
  }
  final linked = operation != null &&
      operation.operationId == order.operationId &&
      operation.walletId == order.walletId;
  final flow = linked ? operation.flow : null;
  switch (flow) {
    case SettlementFlow.sendExternal:
      return SwapActivityKind.send;
    case SettlementFlow.moveBtcToPredictions:
    case SettlementFlow.ledgerBtcToPredictions:
    case SettlementFlow.moveUsdToPredictions:
    case SettlementFlow.predictionsDeposit:
      return SwapActivityKind.predictionsDeposit;
    case SettlementFlow.moveUsdToBtc:
    case SettlementFlow.predictionsWithdraw:
    case SettlementFlow.predictionsBtcRoute:
    case SettlementFlow.predictionsToLedgerBtc:
    case SettlementFlow.movePredictionsToDollars:
      return SwapActivityKind.predictionsWithdrawal;
    case SettlementFlow.moveBtcToInvesting:
    case SettlementFlow.ledgerBtcToInvesting:
    case SettlementFlow.sparkToInvestingDirect:
    case SettlementFlow.moveUsdToInvesting:
      return SwapActivityKind.investingDeposit;
    case SettlementFlow.moveInvestingToBtc:
    case SettlementFlow.investingToLedgerBtc:
    case SettlementFlow.investingToSparkDirect:
    case SettlementFlow.investingToSparkUsdDirect:
      return SwapActivityKind.investingWithdrawal;
    case SettlementFlow.moveDollarsToBtc:
      return SwapActivityKind.dollarWithdrawal;
    case SettlementFlow.moveBtcToUsdc:
      // This older flow name served both destinations. Its owned recipient
      // disambiguates them; Polygon alone cannot.
      if (operation!.recipient?.kind ==
          OwnedAddressKind.polymarketDepositWallet) {
        return SwapActivityKind.predictionsDeposit;
      }
      if (operation.recipient?.kind == OwnedAddressKind.sparkSelf) {
        return SwapActivityKind.dollarDeposit;
      }
      break;
    default:
      break;
  }
  if (predictionFlowTagged) {
    return order.networkTo.toUpperCase() == 'POLYGON'
        ? SwapActivityKind.predictionsDeposit
        : SwapActivityKind.predictionsWithdrawal;
  }
  final version = order.routeVersion ?? '';
  if (version.startsWith('spark_to_hypercore') ||
      version.startsWith('spark_usd_to_hypercore') ||
      version.startsWith('ledger_btc_to_hypercore')) {
    return SwapActivityKind.investingDeposit;
  }
  if (version.startsWith('hypercore_to_spark') ||
      version.startsWith('hypercore_to_ledger_btc')) {
    return SwapActivityKind.investingWithdrawal;
  }
  // Older receive records have no operation: incoming external crypto lands
  // on Spark. Known venue operations and bet-flow tags were handled above.
  final from = order.networkFrom.toUpperCase();
  final to = order.networkTo.toUpperCase();
  if (to == 'SPARK' && from != 'SPARK') return SwapActivityKind.receive;
  if (from == 'SPARK' && to != 'SPARK') return SwapActivityKind.send;
  if (from == 'SPARK' && to == 'SPARK') {
    if (order.coinTo.toUpperCase() == 'USDB') {
      return SwapActivityKind.dollarDeposit;
    }
    if (order.coinFrom.toUpperCase() == 'USDB') {
      return SwapActivityKind.dollarWithdrawal;
    }
  }
  return SwapActivityKind.swap;
}

/// Read already-open local metadata only. Rendering must never open storage,
/// mutate settlement records, or make a network request.
SwapActivityKind swapActivityFor(SwapOrder order) {
  SettlementOperation? operation;
  final id = order.operationId;
  if (id != null && Hive.isBoxOpen(SettlementStore.boxName)) {
    final raw = Hive.box<String>(SettlementStore.boxName).get(id);
    if (raw != null) {
      try {
        operation = SettlementCodec.decodeJson(raw);
      } on SettlementCodecException {
        // Unreadable metadata cannot justify a venue label.
      }
    }
  }
  return classifySwapActivity(order,
      operation: operation,
      predictionFlowTagged:
          PolymarketSparkTxsService.isOrchestraOrderTagged(order.id));
}
