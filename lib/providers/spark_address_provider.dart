// lib/providers/spark_address_provider.dart
//
// The wallet's own Spark receive address. Lived in flashnet_provider.dart
// while the Flashnet USDB Earn product existed, but there was never
// anything Flashnet about it: it is the destination for ANY inbound
// settlement to the spending wallet (Polymarket claim proceeds, Orchestra
// bridge legs, receive flows), so it moved here when the Earn product was
// removed.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/breez_config_provider.dart';

final sparkSelfAddressProvider = FutureProvider.autoDispose<String>((ref) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  final sdk = sdkWrapper.instance;
  if (sdk == null) throw Exception('Spark wallet not connected');

  const req = ReceivePaymentRequest(
    paymentMethod: ReceivePaymentMethod.sparkAddress(),
  );
  final response = await sdk.receivePayment(request: req);
  return response.paymentRequest;
});
