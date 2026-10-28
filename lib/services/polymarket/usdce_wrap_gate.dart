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
//
// While a funded bet's legs are still landing nothing converts at all
// ([FundedConversionHold]): one conversion for the whole delivered amount,
// once the wallet's balances show all of it.

import 'package:flutter/foundation.dart' show visibleForTesting;

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

/// No conversion while a funded bet's money is still on its way (founder,
/// 25 October 2026: "We can only execute the last one once it all reaches
/// there, like the pUSD conversion and such. Don't start anything before
/// we have all the actual balances there."). The funding legs run at once;
/// the conversion, like the bet, waits until the deposit wallet's own
/// balances (pUSD + USDC.e, read on chain) show every leg's money, then
/// converts it in ONE batch. The bet's autofire owns the answer
/// ([held]); without one nothing is held.
abstract final class FundedConversionHold {
  static bool _never() => false;

  /// Whether conversions wait now. Never throws (a failing read holds
  /// nothing).
  static bool Function() _held = _never;
  static bool get held {
    try {
      return _held();
    } catch (_) {
      return false;
    }
  }

  /// The bet autofire's answer from now on; the returned callback removes
  /// it (only while it is still the current one).
  static void Function() install(bool Function() held) {
    _held = held;
    return () {
      if (identical(_held, held)) _held = _never;
    };
  }

  @visibleForTesting
  static void reset() => _held = _never;
}

/// Whether a funded bet still holds conversions: its funding is running
/// (`converting`) or queued for its money (`awaitingBalance`) and the
/// deposit wallet's balances have not yet been read covering all of it
/// ([landedConfirmed], set by the autofire from an on-chain read). A bet
/// funded from nothing (venue cash only), placing, done or failed holds
/// nothing, so a stopped run never leaves conversions held. Pure.
bool fundedConversionHeld({
  required bool funded,
  required bool fundingRunning,
  required bool awaitingBalance,
  required bool landedConfirmed,
}) {
  if (!funded) return false;
  if (fundingRunning) return true;
  return awaitingBalance && !landedConfirmed;
}

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

/// What the arrival watch converts with: the account's owner, its deposit
/// wallet and the owner's key.
typedef UsdceWatchAccount = ({String eoa, String wallet, String key});

/// The deposit wallet's arrival watch: one per notifier, started when a
/// deposit into Predictions is sent (or delivered, or the Receive screen
/// opens), converting the USDC.e that lands to pUSD.
///
/// One watch runs at a time: a start while one runs only pushes its end
/// out. It never ends early because the account is not loaded yet (a cold
/// start, the unlock, a rebuild) or its one-time setup is not done: it
/// waits for them ([waitForAccount], woken the moment they change) and
/// converts in the same session, asking a setup that is not running again
/// at most once every [setupEvery]. Past its window it keeps watching,
/// every `lateInterval`, while a deposit into the wallet is still on its
/// way ([onItsWay]); after a conversion it ends unless another one still
/// is. Every conversion goes through [wrap] (the wallet's single-flight
/// gate).
class UsdceArrivalWatch {
  UsdceArrivalWatch({
    required this.account,
    required this.ready,
    required this.wrap,
    required this.onItsWay,
    required this.waitForAccount,
    required this.gone,
    this.askSetup,
    this.setupEvery = const Duration(minutes: 1),
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.log,
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  /// The loaded account, or null while it is not.
  final UsdceWatchAccount? Function() account;

  /// The account's one-time setup is done.
  final bool Function() ready;

  /// Converts what the wallet holds; the micro-USDC.e converted.
  final Future<BigInt> Function(UsdceWatchAccount account) wrap;

  /// A deposit into the wallet is still on its way by its row.
  final bool Function(String wallet) onItsWay;

  /// Waits until the account changes (a state published, setup done), at
  /// most the duration given.
  final Future<void> Function(Duration max) waitForAccount;

  /// The owner is gone (disposed). A rebuild disposes before building
  /// again: the watch ends only when it stays gone for a full pass.
  final bool Function() gone;

  /// Asks the one-time setup again (never throws).
  final void Function()? askSetup;
  final Duration setupEvery;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final void Function(String line)? log;

  DateTime? _until;
  Future<void>? _running;

  /// When the running watch's window ends; null when none runs.
  DateTime? get until => _until;

  /// Starts the watch for [timeout], or pushes the running one's end out.
  /// Returns the running watch (it never throws).
  Future<void> start({
    Duration timeout = const Duration(minutes: 8),
    Duration interval = const Duration(seconds: 4),
    Duration lateInterval = const Duration(seconds: 15),
  }) {
    final until = _clock().add(timeout);
    final running = _until;
    if (running == null || until.isAfter(running)) _until = until;
    final watch = _running;
    if (running != null && watch != null) return watch;
    return _running = Future<void>.microtask(
            () => _run(interval: interval, lateInterval: lateInterval))
        .whenComplete(() {
      _until = null;
      _running = null;
    });
  }

  Future<void> _run(
      {required Duration interval, required Duration lateInterval}) async {
    var goneOnce = false;
    String? lastWallet;
    DateTime? setupAskedAt;
    while (true) {
      var pause = interval;
      if (!_clock().isBefore(_until!)) {
        if (lastWallet == null || !_onItsWay(lastWallet)) return;
        pause = lateInterval;
      }
      if (gone()) {
        if (goneOnce) return;
        goneOnce = true;
        await waitForAccount(pause);
        continue;
      }
      goneOnce = false;
      try {
        final current = account();
        if (current == null) {
          // Still loading: wait for it, never give up the watch.
          await waitForAccount(pause);
          continue;
        }
        lastWallet = current.wallet;
        // A first deposit can land while the wallet's one-time setup
        // (deployment, approvals) is still running. A conversion then
        // fails without the onramp approval and, while its batch runs,
        // refuses the setup's own approvals batch. Keep watching and
        // convert once setup is done.
        if (!ready()) {
          final at = _clock();
          final ask = askSetup;
          if (ask != null &&
              (setupAskedAt == null ||
                  at.difference(setupAskedAt) >= setupEvery)) {
            setupAskedAt = at;
            ask();
          }
          await waitForAccount(pause);
          continue;
        }
        final wrapped = await wrap(current);
        if (wrapped > BigInt.zero && !_onItsWay(current.wallet)) return;
      } catch (e) {
        log?.call('[wrap] poll threw: $e — retrying');
      }
      await _sleep(pause);
    }
  }

  bool _onItsWay(String wallet) {
    try {
      return onItsWay(wallet);
    } catch (_) {
      return false;
    }
  }
}
