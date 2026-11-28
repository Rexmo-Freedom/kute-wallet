/// Uniform Resources (BC-UR) for animated hardware-wallet QR codes.
///
/// Native builds use `bc_ur_dart`'s [UR] unchanged. Web builds cannot:
/// that package pulls in `crypto_wallet_util` (dart:ffi, 64-bit literals)
/// and its fountain-code generator (`xrandom`'s Xoshiro256**) refuses to
/// run without 64-bit integers. On web, [UR] is the pure-Dart port in
/// ur_portable.dart, with the same constructor and members the app uses
/// and the same frames on the wire.
library;

export 'ur_native.dart' if (dart.library.js_interop) 'ur_portable.dart';
