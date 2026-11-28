// Web replacement for the native `breez_sdk_spark_passkey` method channel.
// Speaks the same method/argument protocol as the iOS / Android plugins
// (base64 byte strings, PlatformException codes), backed by the browser
// WebAuthn PRF provider shipped with the wasm SDK
// (`@breeztech/breez-sdk-spark/passkey-prf-provider`), so PasskeyProvider and
// everything above it run unchanged.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

import 'js_values.dart';
import 'loader.dart';

const passkeyChannel = WebPasskeyChannel();

const _passkeyModuleGlobal = 'breezSdkSparkPasskeyUrl';

@JS('document.baseURI')
external String? get _baseUri;

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external _Url(String url, String base);
  external String get href;
}

JSObject? _passkeyModule;

Future<JSObject> _loadPasskeyModule() async {
  final m = _passkeyModule;
  if (m != null) return m;
  await loadBreezWasm();
  final override = globalContext.getProperty<JSAny?>(_passkeyModuleGlobal.toJS);
  final url = override != null && override.typeofEquals('string')
      ? (override as JSString).toDart
      : _Url(defaultModuleUrl.replaceFirst('index.js', 'passkey-prf-provider/index.js'), _baseUri ?? '').href;
  return _passkeyModule = await importModule(url.toJS).toDart;
}

class WebPasskeyChannel {
  const WebPasskeyChannel();

  Future<JSObject> _provider(Map<Object?, Object?> args) async {
    final module = await _loadPasskeyModule();
    final ctor = module.getProperty<JSFunction>('PasskeyProvider'.toJS);
    return ctor.callAsConstructor<JSObject>(
      dartToJs({
        'rpId': args['rpId'],
        'rpName': args['rpName'],
        'userName': args['userName'],
        'userDisplayName': args['userDisplayName'],
      }),
    );
  }

  static List<JsTyped> _b64List(Object? list) => [
    for (final s in (list as List<Object?>? ?? const [])) JsTyped(base64Decode(s as String)),
  ];

  static String? _b64(Object? bytes) => bytes is Uint8List ? base64Encode(bytes) : null;

  static PlatformException _platformError(Object e) {
    final info = jsErrorInfo(e);
    final code = switch (info.name) {
      'PasskeyUserCancelledError' => 'ERR_USER_CANCELLED',
      'PasskeyTimedOutError' => 'ERR_USER_TIMED_OUT',
      'PasskeyCredentialNotFoundError' => 'ERR_NO_CREDENTIAL',
      'PasskeyAlreadyExistsError' => 'ERR_CREDENTIAL_ALREADY_EXISTS',
      'NotAllowedError' => 'ERR_USER_CANCELLED',
      'SecurityError' => 'ERR_CONFIGURATION',
      _ => info.message.toLowerCase().contains('prf') ? 'ERR_PRF_NOT_SUPPORTED' : 'ERR_UNKNOWN',
    };
    return PlatformException(code: code, message: info.message);
  }

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final args = (arguments as Map<Object?, Object?>?) ?? const {};
    try {
      switch (method) {
        case 'isSupported':
          final p = await _provider(args);
          final r = await jsAwait(p.callMethod<JSAny?>('isSupported'.toJS));
          return (jsToDart(r) == true) as T;
        case 'deriveSeeds':
          final p = await _provider(args);
          final r = await jsAwait(
            p.callMethod<JSAny?>(
              'deriveSeeds'.toJS,
              dartToJs(args['salts']),
              dartToJs({
                'allowCredentials': args['allowCredentials'] == null
                    ? null
                    : _b64List(args['allowCredentials']),
                'preferImmediatelyAvailableCredentials': args['preferImmediatelyAvailableCredentials'],
              }),
            ),
          );
          final m = jsObj(jsToDart(r));
          return <Object?, Object?>{
                'seeds': [for (final s in m['seeds'] as List) base64Encode(jsBytes(s))],
                'credentialId': _b64(m['credentialId']),
              }
              as T;
        case 'createPasskey':
          final p = await _provider(args);
          final r = await jsAwait(
            p.callMethod<JSAny?>(
              'createPasskey'.toJS,
              dartToJs(_b64List(args['excludeCredentials'])),
              dartToJs(args['salts']),
            ),
          );
          final m = jsObj(jsToDart(r));
          final c = jsObj(m['credential']);
          final seeds = m['seeds'] as List?;
          return <Object?, Object?>{
                'credentialId': base64Encode(jsBytes(c['credentialId'])),
                'userId': _b64(c['userId']),
                'aaguid': _b64(c['aaguid']),
                'backupEligible': c['backupEligible'],
                'seeds': seeds == null ? null : [for (final s in seeds) base64Encode(jsBytes(s))],
              }
              as T;
        case 'checkDomainAssociation':
          final p = await _provider(args);
          final r = await jsAwait(p.callMethod<JSAny?>('checkDomainAssociation'.toJS));
          return jsToDart(r) as T;
      }
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw _platformError(e);
    }
    throw MissingPluginException('No implementation found for method $method on the web passkey channel');
  }
}
