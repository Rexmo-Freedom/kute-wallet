// Web stand-in for the flutter_rust_bridge entrypoint (frb_generated.dart),
// selected by conditional imports wherever the generated bindings import
// `frb_generated.dart`. Same class and method names, so code written against
// `BreezSdkSparkLib.init()` / `BreezSdkSparkLib.instance.api.crate*` runs on
// web unchanged; the calls go to the official wasm build of the Breez SDK
// (@breeztech/breez-sdk-spark) instead of the native Rust library.

import 'dart:async';
import 'dart:typed_data';

import '../rust/chain_service.dart';
import '../rust/logger.dart';
import '../rust/models.dart';
import '../rust/passkey.dart';
import '../rust/sdk.dart';
import '../rust/sdk_builder.dart';
import '../rust/sdk_context.dart';
import 'loader.dart';
import 'sdk_web.dart';

/// Main entrypoint of the Breez SDK on web.
class BreezSdkSparkLib {
  BreezSdkSparkLib._();

  static final instance = BreezSdkSparkLib._();

  /// Same shape as the native API object; see [BreezSdkSparkLibApi].
  final BreezSdkSparkLibApi api = const BreezSdkSparkLibApi();

  /// Loads and initializes the wasm module. The native parameters are
  /// accepted and ignored; [moduleUrl] overrides where the npm package's
  /// `web/index.js` is served from (default: `breez_sdk_spark/index.js`
  /// next to the page, unless the page already set `globalThis.breezSdkSpark`).
  static Future<void> init({
    Object? api,
    Object? handler,
    Object? externalLibrary,
    bool forceSameCodegenVersion = true,
    String? moduleUrl,
  }) async {
    await loadBreezWasm(moduleUrl: moduleUrl);
  }

  /// No-op on web (the wasm module lives as long as the page).
  static void dispose() {}
}

/// The subset of the generated `BreezSdkSparkLibApi` reached from the public
/// Dart API (sdk.dart, sdk_builder.dart, sdk_context.dart, chain_service.dart,
/// passkey.dart). Every BreezSdk instance method is implemented on
/// [BreezSdkWeb].
class BreezSdkSparkLibApi {
  const BreezSdkSparkLibApi();

  Future<SparkStatus> crateSdkGetSparkStatus({required GetSparkStatusRequest request}) =>
      webGetSparkStatus(request);

  Future<BreezSdk> crateSdkConnect({required ConnectRequest request}) => webConnect(request);

  Config crateSdkDefaultConfig({required Network network}) => webDefaultConfig(network);

  Config crateSdkDefaultServerConfig({required Network network}) => webDefaultServerConfig(network);

  Stream<LogEntry> crateSdkInitLogging({String? logDir, String? logFilter}) =>
      webInitLogging(logDir: logDir, logFilter: logFilter);

  SdkBuilder crateSdkBuilderSdkBuilderNew({required Config config, required Seed seed}) =>
      SdkBuilderWeb(config, seed);

  Future<SdkContext> crateSdkContextNewSharedSdkContext({required SdkContextConfig config}) =>
      webNewSharedSdkContext(config);

  Future<BitcoinChainServiceHandle> crateChainServiceNewRestChainService({
    required String url,
    required Network network,
    required ChainApiType apiType,
    Credentials? credentials,
    required NewRestChainServiceRequest request,
  }) => webNewRestChainService(
    url: url,
    network: network,
    apiType: apiType,
    credentials: credentials,
    request: request,
  );

  PasskeyClient cratePasskeyPasskeyClientNew({
    required FutureOr<DeriveSeedsOutput> Function(DeriveSeedsRequest) deriveSeeds,
    required FutureOr<bool> Function() isSupported,
    required FutureOr<CreatePasskeyOutput> Function(List<Uint8List>, List<String>) createPasskey,
    String? breezApiKey,
    PasskeyConfig? config,
  }) => PasskeyClientWeb.fromCallbacks(
    deriveSeeds: deriveSeeds,
    isSupported: isSupported,
    createPasskey: createPasskey,
    breezApiKey: breezApiKey,
    config: config,
  );
}
