import 'package:flutter_riverpod/flutter_riverpod.dart';

class TransactionSearchModel {
  bool? isLiquid;
  String? txid;
  int? amount;
  String? assetId;
  String? amountBlinder;
  String? assetBlinder;
  String? unblindedUrl;
  String? sparkPaymentId;

  TransactionSearchModel({
    this.isLiquid,
    this.txid,
    this.amount,
    this.assetId,
    this.amountBlinder,
    this.assetBlinder,
    this.unblindedUrl,
    this.sparkPaymentId,
  });

  TransactionSearchModel copyWith({
    bool? isLiquid,
    String? txid,
    int? amount,
    String? assetId,
    String? amountBlinder,
    String? assetBlinder,
    String? unblindedUrl,
    String? sparkPaymentId,
  }) {
    return TransactionSearchModel(
      isLiquid: isLiquid ?? this.isLiquid,
      txid: txid ?? this.txid,
      amount: amount ?? this.amount,
      assetId: assetId ?? this.assetId,
      amountBlinder: amountBlinder ?? this.amountBlinder,
      assetBlinder: assetBlinder ?? this.assetBlinder,
      unblindedUrl: unblindedUrl ?? this.unblindedUrl,
      sparkPaymentId: sparkPaymentId ?? this.sparkPaymentId,
    );
  }

  // Method to clear all fields
  TransactionSearchModel clear() {
    return TransactionSearchModel();
  }
}


final transactionSearchProvider = StateProvider<TransactionSearchModel>((ref) {
  return TransactionSearchModel();
});
