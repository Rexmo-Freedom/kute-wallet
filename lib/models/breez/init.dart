import 'dart:async';
import 'dart:io';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

import 'package:kute/models/breez/claim_policy.dart';

export 'package:kute/models/breez/claim_policy.dart'
    show kSparkAutoClaimMaxFeeSats;

/// Builds the connect request again for a reconnect without a prompt
/// (see [BreezSdkSpark.connect]); null when that would need one now.
typedef ReconnectRequest = Future<ConnectRequest?> Function();

Future<void> initializeSDK(String mnemonic, String walletId,
    {ReconnectRequest? reconnectRequest}) async {
  final connectRequest = await createConnectRequest(mnemonic, walletId);
  await BreezSdkSpark().connect(
      req: connectRequest,
      walletId: walletId,
      reconnectRequest: reconnectRequest);
}

Future<void> initializeSDKWithSeed(Seed seed, String walletId,
    {ReconnectRequest? reconnectRequest}) async {
  final connectRequest = await createConnectRequestWithSeed(seed, walletId);
  await BreezSdkSpark().connect(
      req: connectRequest,
      walletId: walletId,
      reconnectRequest: reconnectRequest);
}

Future<ConnectRequest> createConnectRequest(
    String mnemonic, String walletId) async {
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
  final config = baseConfig.copyWith(
      apiKey: apiKey,
      lnurlDomain: 'paykute.com',
      maxDepositClaimFee:
          MaxFee.fixed(amount: BigInt.from(kSparkAutoClaimMaxFeeSats)));

  return ConnectRequest(
    config: config,
    seed: seed,
    storageDir: walletStorageDir.path,
  );
}

Future<ConnectRequest> createConnectRequestWithSeed(
    Seed seed, String walletId) async {
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
  final config = baseConfig.copyWith(
      apiKey: apiKey,
      lnurlDomain: 'paykute.com',
      maxDepositClaimFee:
          MaxFee.fixed(amount: BigInt.from(kSparkAutoClaimMaxFeeSats)));

  return ConnectRequest(
    config: config,
    seed: seed,
    storageDir: walletStorageDir.path,
  );
}
