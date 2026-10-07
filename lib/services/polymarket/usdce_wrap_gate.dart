// One USDC.e → pUSD conversion at a time per Predictions deposit wallet.
//
// Several paths convert the USDC.e a deposit delivers: the arrival watch
// started when a deposit is sent or its order completes, the check on app
// resume and Predictions open, and the order path when pUSD alone is short.
// They can fire together (an order tapped as the deposit lands). The
// deposit wallet's relayer batch refuses a second batch while one is in
// flight, and two conversions both sized from the same balance read would
// have the second fail on chain. So a caller arriving while a conversion
// runs for the same wallet gets that conversion's result instead of
// signing a second one.

/// What a Predictions order costs in micro-pUSD at [price] for [size]
/// shares, rounded up.
BigInt polyBuyCostMicros({required double size, required double price}) {
  final cost = size * price * 1e6;
  if (!cost.isFinite || cost <= 0) return BigInt.zero;
  return BigInt.from(cost.ceil());
}

/// Whether a buy costing [costMicros] should convert the wallet's USDC.e
/// before it is signed: pUSD alone is short and pUSD + USDC.e covers it.
/// When even both do not cover it there is nothing to gain, and the order
/// book's own refusal says so.
bool polyShouldWrapBeforeBuy({
  required BigInt pusd,
  required BigInt usdce,
  required BigInt costMicros,
}) =>
    costMicros > BigInt.zero &&
    usdce > BigInt.zero &&
    pusd < costMicros &&
    pusd + usdce >= costMicros;

class UsdceWrapGate {
  final Map<String, Future<BigInt>> _running = {};

  /// Whether a conversion is running for [wallet].
  bool isRunning(String wallet) => _running.containsKey(wallet.toLowerCase());

  /// Runs [wrap] for [wallet] unless one is already running, in which case
  /// that one's result (the micro-USDC.e it wrapped) is returned.
  Future<BigInt> run(String wallet, Future<BigInt> Function() wrap) {
    final key = wallet.toLowerCase();
    final running = _running[key];
    if (running != null) return running;
    final future = wrap();
    _running[key] = future;
    void done() {
      if (identical(_running[key], future)) _running.remove(key);
    }

    future.then((_) => done(), onError: (Object _) => done());
    return future;
  }
}
