import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:kute/models/transactions_model.dart';

/// A live Spark Lightning payment row. [lnAddress] is the LNURL-pay
/// Lightning address the SDK records on a Lightning-address send; null
/// is a one-time invoice.
SparkTransaction lnSend(
  String? lnAddress,
  int sats,
  DateTime when, {
  PaymentType type = PaymentType.send,
}) {
  final id = 'p-${lnAddress ?? 'invoice'}-${when.millisecondsSinceEpoch}';
  return SparkTransaction(
    id: id,
    timestamp: when,
    isConfirmed: true,
    details: Payment(
      id: id,
      paymentType: type,
      status: PaymentStatus.completed,
      amount: BigInt.from(sats),
      fees: BigInt.zero,
      timestamp: BigInt.from(when.millisecondsSinceEpoch ~/ 1000),
      method: PaymentMethod.lightning,
      details: PaymentDetails.lightning(
        invoice: 'lnbc1example',
        destinationPubkey: 'pubkey',
        htlcDetails: SparkHtlcDetails(
          paymentHash: 'hash',
          expiryTime: BigInt.zero,
          status: SparkHtlcStatus.preimageShared,
        ),
        lnurlPayInfo:
            lnAddress == null ? null : LnurlPayInfo(lnAddress: lnAddress),
      ),
    ),
  );
}

/// An SDK contact, timestamps in whole seconds as the SDK keeps them.
Contact contact(String address, int updatedAt, {String? id, int? createdAt}) =>
    Contact(
      id: id ?? 'c-$address',
      name: address,
      paymentIdentifier: address,
      createdAt: BigInt.from(createdAt ?? updatedAt),
      updatedAt: BigInt.from(updatedAt),
    );
