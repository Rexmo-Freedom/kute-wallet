import 'dart:async';
import 'dart:io';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

// Flat sat ceiling on the Spark service claim quote, identical to the previous 25 sat/vB x 99 vB.
const int kSparkAutoClaimMaxFeeSats = 2475;

Future<void> initializeSDK(String mnemonic, String walletId) async {
  final connectRequest = await createConnectRequest(mnemonic, walletId);
  await BreezSdkSpark().connect(req: connectRequest);
}

Future<void> initializeSDKWithSeed(Seed seed, String walletId) async {
  final connectRequest = await createConnectRequestWithSeed(seed, walletId);
  await BreezSdkSpark().connect(req: connectRequest);
}

Future<ConnectRequest> createConnectRequest(String mnemonic, String walletId) async {
  final appDir = await getApplicationDocumentsDirectory();

  final walletStorageDir = Directory('${appDir.path}/breez_$walletId');
  if (!await walletStorageDir.exists()) {
    await walletStorageDir.create(recursive: true);
  }

  final apiKey = dotenv.env['BREEZ_API_KEY'];
  if (apiKey == null) {
    throw Exception("BREEZ_API_KEY is not set in .env file");
  }

  final seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: null);

  final baseConfig = defaultConfig(network: Network.mainnet);
  final config = baseConfig.copyWith(apiKey: apiKey, lnurlDomain: 'paykute.com', maxDepositClaimFee: MaxFee.fixed(amount: BigInt.from(kSparkAutoClaimMaxFeeSats)));

  return ConnectRequest(
    config: config,
    seed: seed,
    storageDir: walletStorageDir.path,
  );
}

Future<ConnectRequest> createConnectRequestWithSeed(Seed seed, String walletId) async {
  final appDir = await getApplicationDocumentsDirectory();

  final walletStorageDir = Directory('${appDir.path}/breez_$walletId');
  if (!await walletStorageDir.exists()) {
    await walletStorageDir.create(recursive: true);
  }

  final apiKey = dotenv.env['BREEZ_API_KEY'];
  if (apiKey == null) {
    throw Exception("BREEZ_API_KEY is not set in .env file");
  }

  final baseConfig = defaultConfig(network: Network.mainnet);
  final config = baseConfig.copyWith(apiKey: apiKey, lnurlDomain: 'paykute.com', maxDepositClaimFee: MaxFee.fixed(amount: BigInt.from(kSparkAutoClaimMaxFeeSats)));

  return ConnectRequest(
    config: config,
    seed: seed,
    storageDir: walletStorageDir.path,
  );
}
