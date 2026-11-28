import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

import 'package:kute/models/breez/claim_policy.dart';
import 'package:kute/platform/breez_web_storage.dart';

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

/// The wallet's Breez storage: a folder in the app's documents on a
/// device; on the web the Breez wasm SDK keeps its data in the browser's
/// own database and the value is only that database's name.
Future<String> _walletStorageDir(String walletId) async {
  if (kIsWeb) return 'breez_$walletId';
  final appDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${appDir.path}/breez_$walletId');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}

/// Web: deletes the SDK's browser databases for [walletId] (named from
/// the same `breez_<walletId>` storage directory as [_walletStorageDir]),
/// once no SDK handle can be writing to them. [disconnectAny] disconnects
/// whichever wallet is connected (a device wipe). Answers whether they
/// were deleted; a no-op answering false off the web. Never throws.
Future<bool> deleteWalletWebStorage(String walletId,
    {bool disconnectAny = false}) async {
  if (!kIsWeb || walletId.isEmpty) return false;
  try {
    final released = await BreezSdkSpark()
        .releaseWalletStorage(walletId, disconnectAny: disconnectAny);
    if (!released) return false;
    await deleteBreezWebStorage('breez_$walletId');
    return true;
  } catch (_) {
    return false;
  }
}

Future<ConnectRequest> createConnectRequest(
    String mnemonic, String walletId) async {
  final storageDir = await _walletStorageDir(walletId);

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
    storageDir: storageDir,
  );
}

Future<ConnectRequest> createConnectRequestWithSeed(
    Seed seed, String walletId) async {
  final storageDir = await _walletStorageDir(walletId);

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
    storageDir: storageDir,
  );
}
