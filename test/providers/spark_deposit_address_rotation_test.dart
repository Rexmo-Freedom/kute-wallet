// The Bitcoin deposit address stays put: the same one across SDK
// reconnects, and a fresh one only the first time on a device or once
// money arrived on it and a receive screen opens. It used to change on
// screen the moment a deposit landed, and on every SDK reconnect.
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

void main() {
  late Directory dir;
  setUpAll(() async {
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.bitcoinAddress()));
    dir = await Directory.systemTemp.createTemp('spark_address');
    Hive.init(dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(SparkDepositAddressRotation.debugReset);

  test('fresh once, then the same address until money arrives and a '
      'receive screen opens', () async {
    final asked = <bool?>[];
    var n = 0;
    final sdk = _Sdk();
    when(() => sdk.receivePayment(request: any(named: 'request')))
        .thenAnswer((call) async {
      final req = call.namedArguments[#request] as ReceivePaymentRequest;
      final method =
          req.paymentMethod as ReceivePaymentMethod_BitcoinAddress;
      asked.add(method.newAddress);
      if (method.newAddress == true) n++;
      return ReceivePaymentResponse(paymentRequest: 'bc1q$n', fee: BigInt.zero);
    });
    final wrapper = _Wrapper();
    when(() => wrapper.instance).thenReturn(sdk);
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: true,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      breezSDKProvider.overrideWith((_) async => wrapper),
    ]);
    addTearDown(c.dispose);

    // First read on this device: a fresh address.
    expect(await c.read(getSparkBitcoinAddressProvider.future), 'bc1q1');
    expect(asked, [true]);
    // An SDK reconnect rebuilds the provider: the current address stays.
    c.invalidate(getSparkBitcoinAddressProvider);
    await c.read(getSparkBitcoinAddressProvider.future);
    expect(asked.last, isFalse);
    // Money arrived: nothing changes yet (a receive screen may be open).
    SparkDepositAddressRotation.request();
    c.invalidate(getSparkBitcoinAddressProvider);
    await c.read(getSparkBitcoinAddressProvider.future);
    expect(asked.last, isFalse);
    // The next receive screen opens: now it rotates, once.
    expect(SparkDepositAddressRotation.apply(), isTrue);
    c.invalidate(getSparkBitcoinAddressProvider);
    expect(await c.read(getSparkBitcoinAddressProvider.future), 'bc1q2');
    expect(asked.last, isTrue);
    expect(SparkDepositAddressRotation.apply(), isFalse);
    c.invalidate(getSparkBitcoinAddressProvider);
    await c.read(getSparkBitcoinAddressProvider.future);
    expect(asked.last, isFalse);
  });
}
