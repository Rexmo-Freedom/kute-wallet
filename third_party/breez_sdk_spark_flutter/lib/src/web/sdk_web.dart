// Web implementations of the FRB opaque types (BreezSdk, SdkBuilder,
// TokenIssuer, PasskeyClient, ...) on top of the wasm-bindgen classes of
// @breeztech/breez-sdk-spark. Plain request/response forwarding lives in the
// generated sdk_web.g.dart; this file holds the parts that need callbacks,
// streams or builders.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../passkey_prf_provider.dart' show PasskeyPrfException;
import '../rust/chain_service.dart';
import '../rust/errors.dart';
import '../rust/events.dart';
import '../rust/issuer.dart';
import '../rust/logger.dart';
import '../rust/models.dart';
import '../rust/passkey.dart' as rust;
import '../rust/sdk.dart';
import '../rust/sdk_builder.dart';
import '../rust/sdk_context.dart';
import 'convert.g.dart';
import 'errors_web.dart';
import 'js_values.dart';
import 'loader.dart';
import 'sdk_web.g.dart';

// --------------------------------------------------------------------------
// JS helpers
// --------------------------------------------------------------------------

@JS('Error')
extension type _JsError._(JSObject _) implements JSObject {
  external _JsError(String message);
  external set name(String value);
}

@JS('Promise')
extension type _JsPromiseCtor._(JSObject _) implements JSObject {
  external _JsPromiseCtor(JSFunction executor);
}

/// Runs [body] and exposes it to JS as a Promise. Unlike `Future.toJS`, a
/// failure rejects with a plain JS `Error` carrying the message (and the
/// `name` wasm reads to pick a PrfProviderError variant).
JSPromise<JSAny?> _promise(Future<JSAny?> Function() body) {
  return _JsPromiseCtor(
        ((JSFunction resolve, JSFunction reject) {
          body().then(
            (v) => resolve.callAsFunction(null, v),
            onError: (Object e, StackTrace _) => reject.callAsFunction(null, _toJsError(e)),
          );
        }).toJS,
      )
      as JSPromise<JSAny?>;
}

JSObject _toJsError(Object e) {
  String message;
  String? name;
  if (e is PasskeyPrfException) {
    message = e.message;
    name = switch (e.code) {
      'userCancelled' => 'PasskeyUserCancelledError',
      'userTimedOut' => 'PasskeyTimedOutError',
      'noCredential' => 'PasskeyCredentialNotFoundError',
      'credentialAlreadyExists' => 'PasskeyAlreadyExistsError',
      _ => null,
    };
    if (e.code == 'prfNotSupported') message = 'PRF not supported by authenticator';
  } else if (e is PrfProviderError) {
    (message, name) = switch (e) {
      PrfProviderError_UserCancelled() => ('User cancelled authentication', 'PasskeyUserCancelledError'),
      PrfProviderError_UserTimedOut() => ('Authenticator timed out', 'PasskeyTimedOutError'),
      PrfProviderError_CredentialNotFound(:final field0) => (field0, 'PasskeyCredentialNotFoundError'),
      PrfProviderError_CredentialAlreadyExists(:final field0) => (field0, 'PasskeyAlreadyExistsError'),
      PrfProviderError_PrfNotSupported() => ('PRF not supported by authenticator', null),
      PrfProviderError_AuthenticationFailed(:final field0) => ('Authentication failed: $field0', null),
      PrfProviderError_PrfEvaluationFailed(:final field0) => ('PRF evaluation failed: $field0', null),
      PrfProviderError_Configuration(:final field0) => ('Configuration error: $field0', null),
      PrfProviderError_Generic(:final field0) => (field0, null),
    };
  } else {
    final info = jsErrorInfo(e);
    message = info.message;
    name = info.name;
  }
  final err = _JsError(message);
  if (name != null) err.name = name;
  return err;
}

Never _unsupported(String what) =>
    throw UnsupportedError('$what is not available in the Breez SDK web (wasm) build');

// --------------------------------------------------------------------------
// BreezSdk
// --------------------------------------------------------------------------

class BreezSdkWeb extends JsHandle with BreezSdkForwarders implements BreezSdk {
  BreezSdkWeb(super.js);

  @override
  Object mapError(Object error) => mapJsSdkError(error);

  @override
  Stream<SdkEvent> addEventListener() {
    final controller = StreamController<SdkEvent>();
    final listener = JSObject();
    listener.setProperty(
      'onEvent'.toJS,
      ((JSAny? e) {
        if (controller.isClosed) return;
        try {
          controller.add(fromJsSdkEvent(jsToDart(e)));
        } catch (err, st) {
          controller.addError(err, st);
        }
      }).toJS,
    );
    final id = call('addEventListener', [JsRaw(listener)], jsString).then<String?>(
      (v) => v,
      onError: (Object e, StackTrace st) {
        controller.addError(e, st);
        return null;
      },
    );
    controller.onCancel = () async {
      final listenerId = await id;
      if (listenerId != null && !isDisposed) {
        try {
          await removeEventListener(id: listenerId);
        } catch (_) {}
      }
    };
    return controller.stream;
  }

  @override
  Future<bool> removeEventListener({required String id}) => call('removeEventListener', [id], jsBool);

  @override
  Future<void> deleteContact({required String id}) => callVoid('deleteContact', [id]);

  @override
  Future<InputType> parse({required String input}) => call('parse', [input], fromJsInputType);

  @override
  TokenIssuer getTokenIssuer() => TokenIssuerWeb(callRawSync('getTokenIssuer', []) as JSObject);

  @override
  Future<UnilateralExitResponse> unilateralExit({
    required UnilateralExitRequest request,
    required List<int> signerSecretKey,
  }) {
    final JSAny? signer;
    try {
      signer = breezModule.callMethod<JSAny?>(
        'singleKeyCpfpSigner'.toJS,
        Uint8List.fromList(signerSecretKey).toJS,
      );
    } catch (e) {
      return Future.error(mapError(e));
    }
    return call('unilateralExit', [
      toJsUnilateralExitRequest(request),
      JsRaw(signer),
    ], fromJsUnilateralExitResponse);
  }

  @override
  Future<UnilateralExitResponse> unilateralExitWithSigner({
    required UnilateralExitRequest request,
    required FutureOr<Uint8List> Function(Uint8List) signPsbt,
  }) {
    final signer = JSObject();
    signer.setProperty(
      'signPsbt'.toJS,
      ((JSUint8Array psbt) => _promise(() async => (await signPsbt(psbt.toDart)).toJS)).toJS,
    );
    return call('unilateralExit', [
      toJsUnilateralExitRequest(request),
      JsRaw(signer),
    ], fromJsUnilateralExitResponse);
  }
}

class TokenIssuerWeb extends JsHandle with TokenIssuerForwarders implements TokenIssuer {
  TokenIssuerWeb(super.js);

  @override
  Object mapError(Object error) => mapJsSdkError(error);
}

// --------------------------------------------------------------------------
// Opaque handles
// --------------------------------------------------------------------------

class SdkContextWeb extends JsHandle implements SdkContext {
  SdkContextWeb(super.js);

  @override
  Object mapError(Object error) => mapJsSdkError(error);
}

class BitcoinChainServiceHandleWeb extends JsHandle implements BitcoinChainServiceHandle {
  BitcoinChainServiceHandleWeb(super.js);

  @override
  Object mapError(Object error) => mapJsSdkError(error);
}

// --------------------------------------------------------------------------
// SdkBuilder
// --------------------------------------------------------------------------

typedef _BuilderStep = JSAny? Function(JSObject builder);

/// The native builder methods are synchronous while some wasm ones return a
/// Promise (withDefaultStorage), so the steps are recorded and replayed on
/// the wasm `SdkBuilder` in [build].
class SdkBuilderWeb implements SdkBuilder {
  SdkBuilderWeb(this._config, this._seed) : _steps = const [];

  SdkBuilderWeb._(this._config, this._seed, this._steps);

  final Config _config;
  final Seed _seed;
  final List<_BuilderStep> _steps;
  bool _disposed = false;

  SdkBuilder _with(_BuilderStep step) => SdkBuilderWeb._(_config, _seed, [..._steps, step]);

  static JSAny? _invoke(JSObject b, String method, List<Object?> args) =>
      b.callMethodVarArgs<JSAny?>(method.toJS, [for (final a in args) dartToJs(a)]);

  @override
  Future<BreezSdk> build() async {
    try {
      final ctor = breezModule.getProperty<JSObject>('SdkBuilder'.toJS);
      var builder = ctor.callMethodVarArgs<JSObject>('new'.toJS, [
        dartToJs(toJsConfig(_config)),
        dartToJs(toJsSeed(_seed)),
      ]);
      for (final step in _steps) {
        builder = (await jsAwait(step(builder))) as JSObject;
      }
      final sdk = await jsAwait(builder.callMethod<JSAny?>('build'.toJS));
      return BreezSdkWeb(sdk as JSObject);
    } catch (e) {
      throw mapJsSdkError(e);
    }
  }

  @override
  SdkBuilder withAccountNumber({required int accountNumber}) =>
      _with((b) => _invoke(b, 'withAccountNumber', [accountNumber]));

  @override
  SdkBuilder withChainService({required BitcoinChainServiceHandle handle}) =>
      _with((b) => _invoke(b, 'withChainService', [JsRaw((handle as BitcoinChainServiceHandleWeb).js)]));

  @override
  SdkBuilder withDefaultStorage({required String storageDir}) =>
      _with((b) => _invoke(b, 'withDefaultStorage', [storageDir]));

  @override
  SdkBuilder withRestChainService({
    required String url,
    required ChainApiType apiType,
    Credentials? credentials,
  }) => _with(
    (b) => _invoke(b, 'withRestChainService', [
      url,
      toJsChainApiType(apiType),
      credentials == null ? null : toJsCredentials(credentials),
    ]),
  );

  @override
  SdkBuilder withSharedContext({required SdkContext context}) =>
      _with((b) => _invoke(b, 'withSharedContext', [JsRaw((context as SdkContextWeb).js)]));

  @override
  void dispose() => _disposed = true;

  @override
  bool get isDisposed => _disposed;
}

// --------------------------------------------------------------------------
// Passkeys
// --------------------------------------------------------------------------

/// A JS `PrfProvider` (see the wasm d.ts) calling the Dart callbacks.
JSObject _prfProvider({
  required FutureOr<DeriveSeedsOutput> Function(DeriveSeedsRequest) deriveSeeds,
  required FutureOr<bool> Function() isSupported,
  required FutureOr<CreatePasskeyOutput> Function(List<Uint8List>, List<String>) createPasskey,
}) {
  final p = JSObject();
  p.setProperty(
    'deriveSeeds'.toJS,
    ((JSAny? salts, JSAny? options) => _promise(() async {
      final opts = jsToDart(options);
      final o = opts is Map ? opts.cast<String, Object?>() : const <String, Object?>{};
      final out = await deriveSeeds(
        DeriveSeedsRequest(
          salts: jsList(jsToDart(salts), jsString),
          allowCredentials: jsList(o['allowCredentials'], jsBytes),
          preferImmediatelyAvailableCredentials: o['preferImmediatelyAvailableCredentials'] as bool?,
        ),
      );
      return dartToJs({
        'seeds': [for (final s in out.seeds) JsTyped(s)],
        'credentialId': out.credentialId == null ? null : JsTyped(out.credentialId!),
      });
    })).toJS,
  );
  p.setProperty('isSupported'.toJS, (() => _promise(() async => (await isSupported()).toJS)).toJS);
  p.setProperty(
    'createPasskey'.toJS,
    ((JSAny? exclude, JSAny? salts) => _promise(() async {
      final out = await createPasskey(jsList(jsToDart(exclude), jsBytes), jsList(jsToDart(salts), jsString));
      final c = out.credential;
      return dartToJs({
        'credential': {
          'credentialId': JsTyped(c.credentialId),
          'userId': c.userId == null ? null : JsTyped(c.userId!),
          'aaguid': c.aaguid == null ? null : JsTyped(c.aaguid!),
          'backupEligible': c.backupEligible,
        },
        'seeds': out.seeds == null ? null : [for (final s in out.seeds!) JsTyped(s)],
      });
    })).toJS,
  );
  return p;
}

class PasskeyClientWeb extends JsHandle implements rust.PasskeyClient {
  PasskeyClientWeb(super.js);

  factory PasskeyClientWeb.fromCallbacks({
    required FutureOr<DeriveSeedsOutput> Function(DeriveSeedsRequest) deriveSeeds,
    required FutureOr<bool> Function() isSupported,
    required FutureOr<CreatePasskeyOutput> Function(List<Uint8List>, List<String>) createPasskey,
    String? breezApiKey,
    PasskeyConfig? config,
  }) {
    final provider = _prfProvider(
      deriveSeeds: deriveSeeds,
      isSupported: isSupported,
      createPasskey: createPasskey,
    );
    try {
      final ctor = breezModule.getProperty<JSFunction>('PasskeyClient'.toJS);
      final client = ctor.callAsConstructorVarArgs<JSObject>([
        provider,
        breezApiKey?.toJS,
        config == null ? null : dartToJs(toJsPasskeyConfig(config)),
      ]);
      return PasskeyClientWeb(client);
    } catch (e) {
      throw mapJsPasskeyError(e);
    }
  }

  @override
  Object mapError(Object error) => mapJsPasskeyError(error);

  @override
  Future<PasskeyAvailability> checkAvailability() => call('checkAvailability', [], fromJsPasskeyAvailability);

  @override
  Future<ConnectWithPasskeyResponse> connectWithPasskey({required ConnectWithPasskeyRequest request}) =>
      call('connectWithPasskey', [toJsConnectWithPasskeyRequest(request)], fromJsConnectWithPasskeyResponse);

  @override
  rust.PasskeyLabels labels() => PasskeyLabelsWeb(callRawSync('labels', []) as JSObject);

  @override
  Future<RegisterResponse> register({required RegisterRequest request}) =>
      call('register', [toJsRegisterRequest(request)], fromJsRegisterResponse);

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) =>
      call('signIn', [toJsSignInRequest(request)], fromJsSignInResponse);
}

class PasskeyLabelsWeb extends JsHandle implements rust.PasskeyLabels {
  PasskeyLabelsWeb(super.js);

  @override
  Object mapError(Object error) => mapJsPasskeyError(error);

  @override
  Future<List<String>> list() => call('list', [], (r) => jsList(r, jsString));

  @override
  Future<void> store({required String label}) => callVoid('store', [label]);
}

// --------------------------------------------------------------------------
// Top-level functions (BreezSdkSparkLib.instance.api on web)
// --------------------------------------------------------------------------

Future<JSAny?> _callModule(String fn, List<Object?> args) async {
  try {
    return await jsAwait(breezModule.callMethodVarArgs<JSAny?>(fn.toJS, [for (final a in args) dartToJs(a)]));
  } catch (e) {
    throw mapJsSdkError(e);
  }
}

JSAny? _callModuleSync(String fn, List<Object?> args) {
  try {
    return breezModule.callMethodVarArgs<JSAny?>(fn.toJS, [for (final a in args) dartToJs(a)]);
  } catch (e) {
    throw mapJsSdkError(e);
  }
}

Future<BreezSdk> webConnect(ConnectRequest request) async =>
    BreezSdkWeb((await _callModule('connect', [toJsConnectRequest(request)])) as JSObject);

Config webDefaultConfig(Network network) =>
    fromJsConfig(jsToDart(_callModuleSync('defaultConfig', [toJsNetwork(network)])));

Config webDefaultServerConfig(Network network) =>
    fromJsConfig(jsToDart(_callModuleSync('defaultServerConfig', [toJsNetwork(network)])));

Future<SparkStatus> webGetSparkStatus(GetSparkStatusRequest request) async {
  if (request.proxy != null) _unsupported('GetSparkStatusRequest.proxy');
  return fromJsSparkStatus(jsToDart(await _callModule('getSparkStatus', [])));
}

Stream<LogEntry>? _logStream;

/// Same contract as the native `initLogging`: one global subscriber, so a
/// second call returns the first stream. `logDir` has no meaning in a browser.
Stream<LogEntry> webInitLogging({String? logDir, String? logFilter}) {
  final existing = _logStream;
  if (existing != null) return existing;
  final controller = StreamController<LogEntry>.broadcast();
  final logger = JSObject();
  logger.setProperty(
    'log'.toJS,
    ((JSAny? entry) {
      try {
        controller.add(fromJsLogEntry(jsToDart(entry)));
      } catch (_) {}
    }).toJS,
  );
  _callModule('initLogging', [JsRaw(logger), logFilter]).catchError((Object e, StackTrace st) {
    controller.addError(e, st);
    return null;
  });
  return _logStream = controller.stream;
}

Future<SdkContext> webNewSharedSdkContext(SdkContextConfig config) async {
  if (config.proxy != null) _unsupported('SdkContextConfig.proxy');
  final ctx = await _callModule('newSharedSdkContext', [
    {'network': toJsNetwork(config.network), 'apiKey': config.apiKey},
  ]);
  return SdkContextWeb(ctx as JSObject);
}

Future<BitcoinChainServiceHandle> webNewRestChainService({
  required String url,
  required Network network,
  required ChainApiType apiType,
  Credentials? credentials,
  required NewRestChainServiceRequest request,
}) async {
  if (request.proxy != null) _unsupported('NewRestChainServiceRequest.proxy');
  final svc = await _callModule('newRestChainService', [
    url,
    toJsNetwork(network),
    toJsChainApiType(apiType),
    credentials == null ? null : toJsCredentials(credentials),
  ]);
  return BitcoinChainServiceHandleWeb(svc as JSObject);
}
