/// Largest integer the app treats as exact on this platform.
///
/// Native (Dart VM): the 64-bit signed maximum, 0x7fffffffffffffff.
/// Web (JavaScript numbers): `Number.MAX_SAFE_INTEGER`, 2^53 - 1. A
/// 64-bit literal cannot be written in code compiled to JavaScript, and an
/// integer above 2^53 is no longer exact there anyway.
library;

export 'int_limits_native.dart'
    if (dart.library.js_interop) 'int_limits_web.dart';
