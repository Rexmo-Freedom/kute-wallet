// Conversions between Dart values and the plain JS values exchanged with the
// @breeztech/breez-sdk-spark wasm module, plus the base for JS-backed handles.
//
// JS -> Dart: [jsToDart] normalizes a JS value into plain Dart data (Map,
// List, String, num, bool, BigInt for JS bigint, Uint8List for Uint8Array,
// JS Maps become Dart Maps). The generated `fromJs*` functions read that data.
//
// Dart -> JS: the generated `toJs*` functions produce plain Dart data, where
// [JsBig] marks a value the wasm SDK expects as a JS bigint and [JsTyped] one
// it expects as a Uint8Array; [dartToJs] turns that tree into JS values.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show Uint64List;

/// A BigInt the wasm SDK takes as a JS `bigint` (u128 fields and a few u64).
class JsBig {
  final BigInt value;
  const JsBig(this.value);
}

/// Bytes the wasm SDK takes as a `Uint8Array` (instead of `number[]`).
class JsTyped {
  final Uint8List value;
  const JsTyped(this.value);
}

/// A JS value passed through [dartToJs] untouched (callbacks, handles).
class JsRaw {
  final JSAny? value;
  const JsRaw(this.value);
}

@JS('Array.isArray')
external bool _isArray(JSAny? v);

@JS('Array.from')
external JSArray<JSAny?> _arrayFrom(JSAny? v);

@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject o);

@JS('BigInt')
external JSAny _jsBigInt(JSString s);

@JS('String')
external JSString _jsStringOf(JSAny? v);

/// Normalizes a JS value into plain Dart data. See the library comment.
Object? jsToDart(JSAny? v) {
  if (v == null || v.isUndefinedOrNull) return null;
  if (v.typeofEquals('string')) return (v as JSString).toDart;
  if (v.typeofEquals('boolean')) return (v as JSBoolean).toDart;
  if (v.typeofEquals('number')) {
    final d = (v as JSNumber).toDartDouble;
    if (d.isFinite && d == d.truncateToDouble() && d.abs() <= 9007199254740991) return d.toInt();
    return d;
  }
  if (v.typeofEquals('bigint')) {
    // A bigint primitive is not a JSObject: stringify it through String().
    return BigInt.parse(_jsStringOf(v).toDart);
  }
  if (!v.typeofEquals('object')) return v; // functions, symbols
  if (v.instanceOfString('Uint8Array')) return Uint8List.fromList((v as JSUint8Array).toDart);
  if (_isArray(v)) return [for (final e in (v as JSArray<JSAny?>).toDart) jsToDart(e)];
  if (v.instanceOfString('Map')) {
    final out = <String, Object?>{};
    final entries = _arrayFrom((v as JSObject).callMethod<JSAny?>('entries'.toJS)).toDart;
    for (final entry in entries) {
      final pair = (entry as JSArray<JSAny?>).toDart;
      out[jsToDart(pair[0]).toString()] = jsToDart(pair[1]);
    }
    return out;
  }
  final o = v as JSObject;
  final out = <String, Object?>{};
  for (final k in _objectKeys(o).toDart) {
    out[k.toDart] = jsToDart(o.getProperty<JSAny?>(k));
  }
  return out;
}

/// Turns plain Dart data (as produced by the generated `toJs*` functions)
/// into JS values. Null map entries are left out (serde reads a missing
/// field as `None`).
JSAny? dartToJs(Object? v) {
  if (v == null) return null;
  if (v is JsRaw) return v.value;
  if (v is String) return v.toJS;
  if (v is bool) return v.toJS;
  if (v is num) return v.toJS;
  if (v is BigInt) return v.toInt().toJS;
  if (v is JsBig) return _jsBigInt(v.value.toString().toJS);
  if (v is JsTyped) return v.value.toJS;
  if (v is Map) {
    final o = JSObject();
    v.forEach((k, value) {
      if (value != null) o.setProperty(k.toString().toJS, dartToJs(value));
    });
    return o;
  }
  if (v is Iterable) return [for (final e in v) dartToJs(e)].toJS;
  throw ArgumentError.value(v, 'v', 'cannot convert to a JS value');
}

// --------------------------------------------------------------------------
// Readers used by the generated converters
// --------------------------------------------------------------------------

Map<String, Object?> jsObj(Object? o) {
  if (o is Map<String, Object?>) return o;
  if (o is Map) return o.cast<String, Object?>();
  throw ArgumentError.value(o, 'o', 'expected a JS object');
}

String jsString(Object? o) {
  if (o is String) return o;
  if (o == null) throw ArgumentError.notNull('string');
  return o.toString();
}

bool jsBool(Object? o) {
  if (o is bool) return o;
  if (o == null) return false;
  throw ArgumentError.value(o, 'o', 'expected a bool');
}

int jsInt(Object? o) {
  if (o is int) return o;
  if (o is num) return o.toInt();
  if (o is BigInt) return o.toInt();
  if (o is String) return int.parse(o);
  throw ArgumentError.value(o, 'o', 'expected an integer');
}

double jsDouble(Object? o) {
  if (o is num) return o.toDouble();
  if (o is String) return double.parse(o);
  throw ArgumentError.value(o, 'o', 'expected a number');
}

BigInt jsBigInt(Object? o) {
  if (o is BigInt) return o;
  if (o is int) return BigInt.from(o);
  if (o is num) return BigInt.from(o);
  if (o is String) return BigInt.parse(o);
  throw ArgumentError.value(o, 'o', 'expected an integer');
}

Uint8List jsBytes(Object? o) {
  if (o is Uint8List) return o;
  if (o is List) return Uint8List.fromList([for (final e in o) jsInt(e)]);
  if (o is String) return Uint8List.fromList(o.codeUnits);
  throw ArgumentError.value(o, 'o', 'expected bytes');
}

Uint64List jsU64List(Object? o) => Uint64List.fromList([for (final e in o as List) jsInt(e)]);

List<Object> jsFromU64List(Uint64List l) => [for (final e in l) jsInt(e)];

List<T> jsList<T>(Object? o, T Function(Object? x) f) {
  if (o == null) return <T>[];
  return [for (final e in o as List) f(e)];
}

Map<String, T> jsMap<T>(Object? o, T Function(Object? x) f) {
  if (o == null) return <String, T>{};
  return {for (final e in jsObj(o).entries) e.key: f(e.value)};
}

Never unsupportedFromJs(String type) => throw UnsupportedError('$type is not supported on web');

Never unsupportedToJs(String type) => throw UnsupportedError('$type is not supported on web');

// --------------------------------------------------------------------------
// JS-backed handles
// --------------------------------------------------------------------------

/// Message (and `name`, when it is an Error) of something a JS call threw.
({String message, String? name}) jsErrorInfo(Object error) {
  if (error is String) return (message: error, name: null);
  try {
    final a = error as JSAny?;
    if (a != null && a.typeofEquals('object')) {
      final o = a as JSObject;
      final m = o.getProperty<JSAny?>('message'.toJS);
      final n = o.getProperty<JSAny?>('name'.toJS);
      if (m != null && m.typeofEquals('string')) {
        return (
          message: (m as JSString).toDart,
          name: n != null && n.typeofEquals('string') ? (n as JSString).toDart : null,
        );
      }
    }
    if (a != null && a.typeofEquals('string')) return (message: (a as JSString).toDart, name: null);
  } catch (_) {}
  return (message: error.toString(), name: null);
}

/// Awaits [v] when it is a JS Promise.
Future<JSAny?> jsAwait(JSAny? v) async {
  if (v != null && v.typeofEquals('object') && v.instanceOfString('Promise')) {
    return (v as JSPromise<JSAny?>).toDart;
  }
  return v;
}

/// Base for Dart objects backed by a wasm-bindgen class instance.
abstract class JsHandle {
  JsHandle(this.js);

  /// The wasm-bindgen object.
  final JSObject js;

  bool _disposed = false;

  /// Maps an error thrown by the JS side into the Dart error type the FRB
  /// bindings throw for this object.
  Object mapError(Object error);

  /// Calls [method] with [args] (converted by [dartToJs]), awaits a returned
  /// Promise and converts the result with [conv].
  Future<T> call<T>(String method, List<Object?> args, T Function(Object? r) conv) async {
    final JSAny? r;
    try {
      r = await jsAwait(js.callMethodVarArgs<JSAny?>(method.toJS, [for (final a in args) dartToJs(a)]));
    } catch (e) {
      throw mapError(e);
    }
    return conv(jsToDart(r));
  }

  /// Like [call], for methods returning nothing.
  Future<void> callVoid(String method, List<Object?> args) => call(method, args, (_) {});

  /// Calls a synchronous method and returns the raw JS result.
  JSAny? callRawSync(String method, List<Object?> args) {
    try {
      return js.callMethodVarArgs<JSAny?>(method.toJS, [for (final a in args) dartToJs(a)]);
    } catch (e) {
      throw mapError(e);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      js.callMethod<JSAny?>('free'.toJS);
    } catch (_) {}
  }

  bool get isDisposed => _disposed;
}
