import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';

// A reconnect must never retire a native handle while an app-initiated
// payment/claim/refund is running. The reservation is synchronous, so a send
// cannot start in the gap between a recovery's safety check and disconnect.
final _operations = Expando<_SdkOperations>('sparkOperations');

class _SdkOperations {
  int active = 0;
  bool recovering = false;
  bool retired = false;
}

Future<T> runSparkMutation<T>(
    BreezSdk sdk, Future<T> Function() operation) async {
  final state = _operations[sdk] ??= _SdkOperations();
  if (state.recovering || state.retired) {
    throw StateError('The wallet is reconnecting. Review the payment again.');
  }
  state.active++;
  try {
    return await operation();
  } finally {
    state.active--;
  }
}

/// Returns a recovery reservation only while no mutation is in flight.
/// Retiring it permanently rejects submissions using a prepared old handle.
SparkRecoveryReservation? reserveSparkRecovery(BreezSdk sdk) {
  final state = _operations[sdk] ??= _SdkOperations();
  if (state.active != 0 || state.recovering || state.retired) return null;
  state.recovering = true;
  return SparkRecoveryReservation._(state);
}

class SparkRecoveryReservation {
  SparkRecoveryReservation._(this._state);
  final _SdkOperations _state;

  void retire() => _state.retired = true;
  void release() => _state.recovering = false;
}
