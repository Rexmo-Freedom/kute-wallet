// lib/providers/usd_account_provider.dart
//
// The spending account's USD balance and its balance-over-time series,
// for the USD tab.
//
// THE BALANCE COMES FROM THE SDK. `GetInfoResponse` carries
// `tokenBalances`, a map keyed by token identifier where every entry
// holds the live `balance` plus the token's own metadata (ticker,
// decimals). That is the authoritative number, the same way
// `balanceSats` is authoritative for bitcoin. An earlier note here
// claimed no balance endpoint existed for the dollar token and summed
// the ledger instead; that was wrong.
//
// The ledger sum survives only as a FALLBACK: for the window before the
// SDK has answered (cold start, reconnect), and for an SDK answer that
// carries no dollar entry at all while the ledger holds settled dollar
// transfers. The SDK builds `tokenBalances` from its own token-output
// store, which only a successful Spark wallet sync refreshes; when that
// sync keeps failing (seen from some networks: the receive shows as
// completed in Activity while the balance stayed $0.00, even across a
// restart) the map simply lacks the token. "No entry" therefore means
// "the SDK has not caught up", not "zero dollars", and the settled
// ledger decides until it does, shown with the stale shimmer
// (usdBalanceUnknownProvider) while UsdLedgerCatchUp brings the SDK's
// figure in. A session's first answer is the row the previous session
// left, so it can lack the entry too. An entry with a zero balance is a
// real zero and still wins.
//
// The balance is the user's own money: no runtime capability (usd.earn
// or any other) gates or hides it in any country. usd.earn hides only
// the Earn tab. Receives add, sends subtract; the network fee
// on a send settles in sats, not dollars, so it never enters the sum.
// Pending and failed rows are skipped (`isConfirmed` is `status ==
// completed`), so the fallback only ever counts money that has actually
// settled.
//
// Internal identifiers keep the token's own name; the user only ever
// sees "USD" or "$".

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show BreezSdk, GetInfoRequest, GetInfoResponse;
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/balance_history.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/models/breez/sdk_balance_telemetry.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/usdb_provider.dart' show isUsdbTokenPayment;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/haptic_gates.dart' show IncomingPaymentGate;
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

/// The dollar token's own identifier on Spark. Only a backstop: the
/// primary match is the ticker in the SDK's token metadata, which is
/// what [kOrchestraUsdAssetCode] already names everywhere else.
const String kUsdTokenIdentifier =
    'btkn1xgrvjwey5ngcagvap2dzzvsy4uk8ua9x69k82dwvt5e7ef9drm9qztux87';

/// Decimals assumed by the ledger fallback, and by the SDK path when a
/// token entry somehow carries none. The dollar token is 6 decimals,
/// like every other dollar in the app.
const int _kUsdFallbackDecimals = 6;

/// Pulls the dollar balance out of a [GetInfoResponse], in dollars.
///
/// Matches on `tokenMetadata.ticker` first — the metadata travels with
/// the balance, it is the same spelling the Orchestra route table uses,
/// and it keeps working if the token is ever reissued under a new
/// identifier. The identifier (map key or metadata) is checked second so
/// a wallet whose metadata came back blank still resolves.
///
/// Null when the response carries no dollar entry at all: the SDK's
/// token store has not caught up with the account (see the header), so
/// [usdBalanceProvider] falls back to the settled ledger. An entry with
/// a zero balance is a real zero and returns 0.
double? usdDollarsFromNodeInfo(GetInfoResponse info) {
  for (final entry in info.tokenBalances.entries) {
    final meta = entry.value.tokenMetadata;
    final tickerMatches =
        meta.ticker.trim().toUpperCase() == kOrchestraUsdAssetCode;
    final identifierMatches = entry.key == kUsdTokenIdentifier ||
        meta.identifier == kUsdTokenIdentifier;
    if (!tickerMatches && !identifierMatches) continue;
    final decimals = meta.decimals > 0 ? meta.decimals : _kUsdFallbackDecimals;
    var scale = 1.0;
    for (var i = 0; i < decimals; i++) {
      scale *= 10;
    }
    return entry.value.balance.toDouble() / scale;
  }
  return null;
}

/// Debug builds only: what the SDK's answer held, so a balance stuck at
/// zero can be told apart from an SDK that never saw the token. Token
/// tickers are public metadata; no amount, identifier or key is printed.
void _debugLogUsdReading(String source, GetInfoResponse info) {
  if (!kDebugMode) return;
  final tickers = [
    for (final b in info.tokenBalances.values) b.tokenMetadata.ticker,
  ];
  debugPrint('[usd-balance] $source tokens=${tickers.length} '
      'tickers=$tickers usdEntry=${usdDollarsFromNodeInfo(info) != null}');
}

/// Debug builds only: which feed published a Dollars reading, so a device
/// log shows exactly which path moved the figure. No amount is printed.
void _debugLogUsdPublish(String source, double? reading) {
  if (!kDebugMode) return;
  debugPrint('[usd-balance] publish source=$source '
      'usdEntry=${reading != null}');
}

/// The spending account's dollar balance in the token's own base units,
/// exactly as the SDK holds it. What a 100% dollar move sends.
BigInt usdBaseUnitsFromNodeInfo(GetInfoResponse info) {
  for (final entry in info.tokenBalances.entries) {
    final meta = entry.value.tokenMetadata;
    final tickerMatches =
        meta.ticker.trim().toUpperCase() == kOrchestraUsdAssetCode;
    final identifierMatches = entry.key == kUsdTokenIdentifier ||
        meta.identifier == kUsdTokenIdentifier;
    if (!tickerMatches && !identifierMatches) continue;
    return entry.value.balance;
  }
  return BigInt.zero;
}

/// The dollar balance a 100% dollar move sends, in base units, read from
/// the SDK's cached `getInfo` at once. It never waits for a sync: a forced
/// sync takes seconds and blocks the SDK's runtime loop, holding back the
/// operator stream updates that keep the cache current. The move sheet
/// starts one shared background sync when it opens (see
/// [kickSharedSyncWallet]) so the cache is fresh by confirm. The SDK
/// refuses a token send it cannot fund (after refreshing its outputs and
/// retrying), so a stale-high figure never overspends; a stale-low one
/// leaves the difference behind as dust.
Future<BigInt> usdDrainBaseUnits(BreezSdk sdk) async {
  return usdBaseUnitsFromNodeInfo(
      await sdk.getInfo(request: const GetInfoRequest()));
}

/// How long a Dollars catch-up waits before trying again while the SDK's
/// answer still has no dollar entry and the settled ledger holds dollars.
/// Bounded: once used up, only a new trigger (a ledger change, resume,
/// pull-to-refresh) tries again, so a wallet the SDK cannot sync is never
/// polled forever.
const List<Duration> kUsdCatchUpRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
];

/// Brings the dollar reading up to date when the SDK's token map is
/// behind.
///
/// WHY (Breez SDK Spark at 2c140a5, client runtime). `getInfo` never asks
/// the network: it returns the stored `CachedAccountInfo` row
/// (`sdk/runtime/client.rs:113`), which only `update_balances`
/// (`utils/payments.rs:272`) writes, from the wallet's IN-MEMORY token
/// output store. The SQLite backend gives the wallet no store of its own
/// (`persist/backend/sqlite.rs:47`), so `wallet_builder.rs:126` builds an
/// `InMemoryTokenOutputStore`, empty on every connect, filled only by the
/// wallet's startup refresh (`spark-wallet/src/wallet.rs:3037`), by
/// `SparkWallet::sync` (`wallet.rs:1466`, and only once the leaf refresh
/// before it has succeeded) and by token transaction events
/// (`wallet.rs:3130`). So:
///
///  * a session's first `getInfo` is the row the previous session wrote,
///    which can carry no dollar entry at all;
///  * a sync rewrites the row in its WalletState step, part-way through,
///    but the app hears of it only through `Synced`, which the SDK raises
///    after the slowest step (deposits) and, the first time, only after
///    the real-time sync pull (`sdk/sync.rs:280`, `events.rs:401`):
///    seconds to tens of seconds later.
///
/// The SDK has no token-only refresh: `syncWallet` is the one call that
/// refreshes the token outputs and rewrites the row.
///
/// What this does, one run at a time (a trigger mid-run queues one more):
///  * when the settled dollar ledger changes, read `getInfo` again; the
///    same figure as before the change means the row has not caught up;
///  * when an answer has no dollar entry while the settled ledger holds
///    dollars, the row is behind as well (the figure is "unknown", see
///    [usdBalanceUnknownProvider]);
///  * either way, start one shared wallet sync and read the cached row
///    every [pollInterval] while it runs, publishing the moment it moves
///    (the WalletState write lands well before the sync answers), then
///    once more when the sync answers or [syncTimeout] passes;
///  * an entry still missing after that is tried again on the bounded
///    [retryDelays], and on every new trigger ([check]). A settled payment
///    also keeps retrying an unchanged numeric entry (including zero).
///    Only a current-session ledger delta with an unmet expected reading,
///    or a missing token entry, may request one guarded SDK reconnect.
class UsdLedgerCatchUp {
  UsdLedgerCatchUp({
    required this.readInfo,
    required this.syncWallet,
    required this.publish,
    this.recoverTokenStore,
    this.telemetry = const SdkBalanceTelemetry(),
    this.debounce = const Duration(milliseconds: 800),
    this.syncTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 1),
    this.retryDelays = kUsdCatchUpRetryDelays,
  });

  /// Reads the SDK's cached `getInfo`. [source] names the trigger, for
  /// the debug log.
  final Future<GetInfoResponse> Function(String source) readInfo;
  final Future<void> Function() syncWallet;

  /// Guarded reconnect of this wallet's SDK, only if a normal sync left
  /// its token store unchanged. False means busy; a bounded retry tries
  /// again. At most one successful recovery per ledger change/check.
  final Future<bool> Function(String source)? recoverTokenStore;
  final SdkBalanceTelemetry telemetry;

  /// Publishes a reading; [source] names the path that produced it.
  final void Function(double? reading, String source) publish;
  final Duration debounce;
  final Duration syncTimeout;
  final Duration pollInterval;
  final List<Duration> retryDelays;

  String? _signature;
  bool _holdsDollars = false;
  double? _lastReading;
  bool _hasReading = false;
  bool _pendingLedgerChange = false;
  double? _ledgerStaleReading;
  double? _ledgerDollars;
  double? _readingAtLedger;
  double? _expectedLedgerReading;
  bool _recoveryEligible = false;
  bool _recovered = false;
  Timer? _timer;
  Timer? _retry;
  int _retries = 0;
  bool _running = false;
  bool _again = false;
  String _againSource = '';
  bool _againLedger = false;
  bool _disposed = false;

  /// The SDK has answered without a dollar entry while the settled ledger
  /// holds dollars: the cached row is behind.
  bool get _missing => _hasReading && _lastReading == null && _holdsDollars;
  bool get _behind => _missing || _pendingLedgerChange;
  bool get _provenBehind =>
      _missing ||
      (_pendingLedgerChange &&
          _expectedLedgerReading != null &&
          _recoveryEligible);

  bool _matchesExpected(double? reading) =>
      reading != null &&
      _expectedLedgerReading != null &&
      (reading - _expectedLedgerReading!).abs() < 0.0000005;

  /// Whether a retry is scheduled.
  @visibleForTesting
  bool get retryPending => _retry != null;

  /// Every reading the provider publishes, from any feed, passes here so
  /// "unchanged" is judged against the latest one. A feed's reading that
  /// still has no dollar entry while the ledger holds dollars (the re-read
  /// after a Synced event, say) schedules a retry; one with an entry ends
  /// them.
  void recordReading(double? reading) {
    if (_pendingLedgerChange &&
        reading != null &&
        (_expectedLedgerReading != null
            ? _matchesExpected(reading)
            : reading != _ledgerStaleReading)) {
      _pendingLedgerChange = false;
    }
    // Freeze the baseline until the ledger changes: a fresh SDK reading
    // may arrive BEFORE its matching payment-list notification.
    if (!_pendingLedgerChange && _readingAtLedger == null) {
      _readingAtLedger = reading;
    }
    _lastReading = reading;
    _hasReading = true;
    if (!_running) _scheduleRetryIfBehind();
  }

  /// The settled dollar ledger's identity, and whether it holds dollars
  /// (its settled sum is at least half a cent). The first call is the
  /// baseline; every later change schedules a catch-up.
  void onLedger(String signature,
      {bool holdsDollars = false,
      double? settledDollars,
      bool recoveryEligible = false}) {
    if (_disposed) return;
    _holdsDollars = holdsDollars;
    final previous = _signature;
    final previousDollars = _ledgerDollars;
    _ledgerDollars = settledDollars;
    _signature = signature;
    if (previous == null) {
      _readingAtLedger = _lastReading;
      return;
    }
    if (previous == signature) return;
    _recoveryEligible = recoveryEligible;
    _expectedLedgerReading = recoveryEligible &&
            _readingAtLedger != null &&
            previousDollars != null &&
            settledDollars != null
        ? _readingAtLedger! + settledDollars - previousDollars
        : null;
    _pendingLedgerChange = !_matchesExpected(_lastReading);
    _ledgerStaleReading = _lastReading;
    _readingAtLedger = _expectedLedgerReading ?? _lastReading;
    _recovered = false;
    _retries = 0;
    _retry?.cancel();
    _retry = null;
    _timer?.cancel();
    _timer = Timer(debounce, () => _start('ledger', ledgerMoved: true));
  }

  /// Reads the row now (the seed read, app resume, pull-to-refresh), and
  /// syncs when it has no dollar entry while the ledger holds dollars. A
  /// new trigger starts the retry budget again.
  void check(String source) {
    if (_disposed) return;
    _retries = 0;
    _recovered = false;
    _retry?.cancel();
    _retry = null;
    _start(source);
  }

  void _start(String source, {bool ledgerMoved = false}) {
    if (_disposed) return;
    if (_running) {
      _again = true;
      _againSource = source;
      _againLedger |= ledgerMoved;
      return;
    }
    unawaited(_run(source, ledgerMoved));
  }

  Future<void> _run(String source, bool ledgerMoved) async {
    _running = true;
    try {
      while (true) {
        await _once(source, ledgerMoved: ledgerMoved);
        if (_disposed || !_again) break;
        source = _againSource;
        ledgerMoved = _againLedger;
        _again = false;
        _againLedger = false;
      }
    } finally {
      _running = false;
    }
    _scheduleRetryIfBehind();
  }

  Future<void> _once(String source, {required bool ledgerMoved}) async {
    final sw = Stopwatch()..start();
    var measured = _behind;
    var reason = _missing
        ? UsdCatchUpReason.missingEntry
        : UsdCatchUpReason.unchangedNumeric;
    var readFailed = true;
    final retryIndex = _retries;
    try {
      final hadReading = _hasReading;
      final before = _lastReading;
      final double? reading;
      try {
        reading = usdDollarsFromNodeInfo(await readInfo(source));
      } catch (_) {
        return;
      }
      if (_disposed) return;
      readFailed = false;
      final changed = !hadReading || reading != before;
      if (changed) _emit(reading, source);
      measured |= _behind;
      if (_missing) reason = UsdCatchUpReason.missingEntry;
      if (!_behind) return;
      await _syncAndPoll(reading, source);
      if (_disposed ||
          !_provenBehind ||
          _recovered ||
          recoverTokenStore == null) {
        return;
      }
      try {
        _recovered = await recoverTokenStore!(source);
        if (_disposed || !_recovered) return;
        final recovered =
            usdDollarsFromNodeInfo(await readInfo('$source-reconnect'));
        if (!_disposed) _emit(recovered, '$source-reconnect');
      } catch (_) {
        // Recovery is display-only. A later trigger retries a busy/offline SDK.
      }
    } finally {
      if (measured && !_disposed) {
        telemetry.catchUp(
            source: source,
            reason: reason,
            result: readFailed
                ? UsdCatchUpResult.readFailed
                : _behind
                    ? UsdCatchUpResult.stillBehind
                    : UsdCatchUpResult.caughtUp,
            durationMs: sw.elapsedMilliseconds,
            retryIndex: retryIndex);
      }
    }
  }

  /// One shared sync, reading the cached row every [pollInterval] while it
  /// runs; publishes the first reading that differs from [stale], else the
  /// one after the sync answers (or [syncTimeout] passes).
  Future<void> _syncAndPoll(double? stale, String source) async {
    var done = false;
    final Future<void> syncing = () async {
      final sw = Stopwatch()..start();
      var result = UsdSyncResult.ok;
      try {
        await syncWallet().timeout(syncTimeout);
      } on TimeoutException {
        result = UsdSyncResult.timeout;
      } catch (_) {
        result = UsdSyncResult.error;
      } finally {
        if (!_disposed) {
          telemetry.sync(
              source: source,
              result: result,
              durationMs: sw.elapsedMilliseconds);
        }
      }
    }()
        .whenComplete(() => done = true);
    while (!done) {
      await Future.any<void>([syncing, Future<void>.delayed(pollInterval)]);
      if (_disposed) return;
      if (done) break;
      final double? polled;
      try {
        polled = usdDollarsFromNodeInfo(await readInfo('$source-poll'));
      } catch (_) {
        continue;
      }
      if (_disposed) return;
      if (polled != stale) {
        _emit(polled, '$source-poll');
        return;
      }
    }
    try {
      final after = usdDollarsFromNodeInfo(await readInfo('$source-sync'));
      if (!_disposed) _emit(after, '$source-sync');
    } catch (_) {
      // The next trigger or SDK event tries again.
    }
  }

  void _scheduleRetryIfBehind() {
    if (_disposed) return;
    if (!_behind) {
      _retries = 0;
      _retry?.cancel();
      _retry = null;
      return;
    }
    if (_retry != null || _retries >= retryDelays.length) return;
    final delay = retryDelays[_retries++];
    _retry = Timer(delay, () {
      _retry = null;
      _start('retry');
    });
  }

  void _emit(double? reading, String source) {
    if (_disposed) return;
    recordReading(reading);
    publish(reading, source);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _retry?.cancel();
  }
}

/// Lets app-wide moments (app resume, pull-to-refresh) ask the live
/// Dollars reading to check itself ([UsdLedgerCatchUp.check]). A no-op
/// while no wallet's reading is live.
class UsdBalanceCheck {
  UsdLedgerCatchUp? _catchUp;

  void request(String source) => _catchUp?.check(source);
}

final usdBalanceCheckProvider =
    Provider<UsdBalanceCheck>((ref) => UsdBalanceCheck());

/// The settled dollar ledger's identity for [UsdLedgerCatchUp]: the ids
/// of the settled dollar payments, in a stable order.
String usdLedgerSignature(Iterable<UsdbTokenTransaction> settled) =>
    (settled.map((tx) => tx.id).toList()..sort()).join(',');

/// The live dollar balance as the SDK reports it. Seeded with a direct
/// `getInfo` read (through [UsdLedgerCatchUp.check], so a seed with no
/// dollar entry while the ledger holds dollars starts the catch-up at
/// once), then follows two feeds: the wallet-info stream, which the SDK
/// wrapper publishes after every event that can change a balance (payment
/// events, an incoming dollar transfer among them, claimed deposits, and
/// each Synced burst: a transfer that arrives through a sync raises only
/// Synced), exactly as the bitcoin balance does
/// (`walletBalanceCacheProvider`), and [UsdLedgerCatchUp], which covers a
/// cached row that is behind: a settled transfer none of those reached
/// the app for, or a row with no dollar entry yet. App resume and
/// pull-to-refresh ask it to check too ([usdBalanceCheckProvider]).
///
/// Emits null when the SDK's answer has no dollar entry (see
/// [usdDollarsFromNodeInfo]); [usdBalanceProvider] then reads the ledger
/// and [usdBalanceUnknownProvider] says the figure is a guess.
///
/// Debug builds log the source of every published reading (`seed`,
/// `walletInfoStream`, `ledger`, `retry`, `refresh`, `resume`, and their
/// `-poll` / `-sync` reads): never an amount.
final usdSdkBalanceProvider = StreamProvider<double?>((ref) async* {
  final wrapper = await ref.watch(breezSDKProvider.future);
  if (wrapper.instance == null) return;
  var live = true;
  final readings = StreamController<double?>();
  late final UsdLedgerCatchUp catchUp;
  void add(double? reading, String source) {
    _debugLogUsdPublish(source, reading);
    if (!readings.isClosed) readings.add(reading);
  }

  catchUp = UsdLedgerCatchUp(
    readInfo: (source) async {
      final sdk = wrapper.instance;
      if (sdk == null) throw StateError('The spending wallet is reconnecting.');
      final info = await sdk.getInfo(request: const GetInfoRequest());
      if (!live || !identical(wrapper.instance, sdk)) {
        throw StateError('The spending wallet connection changed.');
      }
      _debugLogUsdReading(source, info);
      return info;
    },
    syncWallet: () async {
      final sdk = wrapper.instance;
      if (sdk != null) await sharedSyncWallet(sdk);
    },
    recoverTokenStore: (source) async {
      final sdk = wrapper.instance;
      if (sdk == null) return false;
      final recovered =
          await wrapper.recoverStaleTokenBalance(sdk, source: source);
      // Contacts is the only persistent notifier which captures the native
      // handle rather than looking it up for each action. Its Riverpod
      // rebuild leaves the wrapper/session provider connected.
      if (live && recovered) ref.invalidate(sparkContactsProvider);
      if (live && !recovered && wrapper.instance == null) {
        // A native reconnect failed after closing the old handle. Re-enter
        // the normal provider lifecycle, which rebuilds dependents and
        // reports connection errors; never retain a disconnected wrapper.
        ref.invalidate(breezSDKProvider);
      }
      return recovered;
    },
    publish: add,
  );
  final infoSub = wrapper.walletInfoStream.listen((info) {
    _debugLogUsdReading('walletInfoStream', info);
    final reading = usdDollarsFromNodeInfo(info);
    catchUp.recordReading(reading);
    add(reading, 'walletInfoStream');
  });
  // Money landed in Dollars: one haptic per new settled receive of this
  // session. The ledger as first read, and any history a sync or a
  // restore streams in later, is older than the session and stays quiet.
  final arrivals = IncomingPaymentGate(startedAt: DateTime.now());
  // SDK payment timestamps have whole-second precision. Recovery uses
  // this session's first second, without the haptic gate's clock skew.
  final recoveryFloor = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000);
  Set<String>? previousSettled;
  ref.listen<List<UsdbTokenTransaction>>(
    usdSettledTransfersProvider,
    (_, settled) {
      final ids = settled.map((tx) => tx.id).toSet();
      final previous = previousSettled;
      final added = previous == null
          ? <UsdbTokenTransaction>[]
          : settled.where((tx) => !previous.contains(tx.id)).toList();
      // History hydration/pruning changes the signature too. Only a new
      // current-session payment can prove a numeric SDK balance stale.
      final recoveryEligible = previous != null &&
          previous.difference(ids).isEmpty &&
          added.isNotEmpty &&
          added.every((tx) => !tx.timestamp.isBefore(recoveryFloor));
      previousSettled = ids;
      catchUp.onLedger(usdLedgerSignature(settled),
          holdsDollars: usdLedgerSumDollars(settled) >= _kUsdHeldThreshold,
          settledDollars: usdLedgerSumDollars(settled),
          recoveryEligible: recoveryEligible);
      if (arrivals.observe([
        for (final tx in settled)
          if (tx.type == TransactionType.received)
            (id: tx.id, at: tx.timestamp),
      ])) {
        KuteHaptics.play(KuteHaptic.moneyIn);
      }
    },
    fireImmediately: true,
  );
  // The seed read, after the ledger's baseline so a seed with no dollar
  // entry is judged against what the ledger holds.
  catchUp.check('seed');
  final check = ref.read(usdBalanceCheckProvider).._catchUp = catchUp;
  ref.onDispose(() {
    live = false;
    if (identical(check._catchUp, catchUp)) check._catchUp = null;
    catchUp.dispose();
    infoSub.cancel();
    readings.close();
  });
  yield* readings.stream;
});

/// Settled dollar transfers on the spending account, newest last.
final usdSettledTransfersProvider = Provider<List<UsdbTokenTransaction>>((ref) {
  final walletId = pickSpendingWallet(ref.watch(settingsProvider))?.id;
  if (walletId == null) return const <UsdbTokenTransaction>[];
  final rows = ref
          .watch(walletTransactionCacheProvider)[walletId]
          ?.usdbTokenTransactions ??
      const <UsdbTokenTransaction>[];
  final settled = rows
      .where((tx) => tx.isConfirmed && isUsdbTokenPayment(tx.details))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return settled;
});

/// The ledger sum, in dollars. Used only while [usdSdkBalanceProvider]
/// has no dollar reading: before its first answer, or while the SDK's
/// answer carries no dollar entry.
final _usdLedgerBalanceProvider = Provider<double>(
    (ref) => usdLedgerSumDollars(ref.watch(usdSettledTransfersProvider)));

/// The settled dollar ledger's sum, in dollars: receives add, sends
/// subtract.
double usdLedgerSumDollars(Iterable<UsdbTokenTransaction> settled) {
  var net = 0;
  for (final tx in settled) {
    final units = tx.amount.toInt();
    net += tx.type == TransactionType.sent ? -units : units;
  }
  return net / 1e6;
}

/// Under half a cent is no dollars held.
const double _kUsdHeldThreshold = 0.005;

/// Whether the Dollars figure is a guess, not the SDK's: the SDK has not
/// answered, or its answer has no dollar entry, while the settled ledger
/// says the account holds dollars. The SDK's cached row can lack the
/// entry for a while after connect (see [UsdLedgerCatchUp]); the figure
/// shown meanwhile is the ledger sum, so it reads with the stale shimmer
/// until the SDK's own figure lands, never as a confident number. A
/// ledger that holds no dollars agrees with an SDK that has no entry:
/// that zero is known.
final usdBalanceUnknownProvider = Provider<bool>((ref) {
  if (ref.watch(usdSdkBalanceProvider).valueOrNull != null) return false;
  return ref.watch(_usdLedgerBalanceProvider) >= _kUsdHeldThreshold;
});

/// USD held on the spending account, in dollars.
final usdBalanceProvider = Provider<double>((ref) {
  final double? fromSdk = ref.watch(usdSdkBalanceProvider).valueOrNull;
  final double dollars = fromSdk ?? ref.watch(_usdLedgerBalanceProvider);
  // A cache that has lost old receives (history trimmed on a restore)
  // could otherwise show a negative dollar balance.
  return dollars < 0 ? 0 : dollars;
});

/// [usdBalanceProvider] once the SDK has answered with a dollar reading,
/// else null: not known yet. [usdBalanceProvider] cannot tell those apart
/// (before the SDK's first answer it is the ledger sum, `0` while the
/// wallet's history has not loaded), so a decision that must not take an
/// unloaded balance for spent money (a move whose money stayed in Dollars,
/// multi_source_move_activity.dart) reads this one.
final usdBalanceReadingProvider = Provider<double?>((ref) {
  if (ref.watch(usdSdkBalanceProvider).valueOrNull == null) return null;
  return ref.watch(usdBalanceProvider);
});

/// The dollar balance by day, for the Dollars tab's Balance chart.
///
/// Reconstructed the same way the USDC series is: anchor on today's
/// balance and walk the settled transfers backwards, undoing each one to
/// recover what the account held before it. Days with no transfer carry
/// no entry — the chart forward-fills from the previous one.
final usdBalanceHistoryProvider = Provider<Map<DateTime, double>>((ref) {
  final current = ref.watch(usdBalanceProvider);
  final transfers = ref.watch(usdSettledTransfersProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final byDay = <DateTime, double>{today: current};

  // `running` always holds the balance as it stood immediately AFTER the
  // transfer being visited. Walking newest to oldest, undoing a transfer
  // gives the balance before it, which is also the balance after the
  // next older one.
  var running = current;
  for (final tx in transfers.reversed) {
    final day = DateTime(
      tx.timestamp.year,
      tx.timestamp.month,
      tx.timestamp.day,
    );
    // First write for a day wins: newest first means that is the day's
    // closing balance.
    final closing = running < 0 ? 0.0 : running;
    byDay.putIfAbsent(day, () => closing);
    final dollars = tx.amount.toInt() / 1e6;
    running += tx.type == TransactionType.sent ? dollars : -dollars;
  }

  return Map.fromEntries(
    byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
});

/// The dollar balance as the moments it changed, for the Dollars tab's
/// Balance chart: the same walk as [usdBalanceHistoryProvider], kept at
/// the time of each settled transfer instead of folded into days, so a
/// deposit an hour ago is drawn an hour ago.
final usdBalanceStepsProvider = Provider<BalanceHistory>((ref) {
  final current = ref.watch(usdBalanceProvider);
  final transfers = ref.watch(usdSettledTransfersProvider);
  // Newest first, `running` is the balance right after the transfer
  // being visited; undoing it gives the balance before.
  var running = current;
  final newestFirst = <(DateTime, double)>[];
  for (final tx in transfers.reversed) {
    newestFirst.add((tx.timestamp, running < 0 ? 0.0 : running));
    final dollars = tx.amount.toInt() / 1e6;
    running += tx.type == TransactionType.sent ? dollars : -dollars;
  }
  // Under half a cent is float dust from the walk, not money held.
  final opening = running < 0.005 ? 0.0 : running;
  return BalanceHistory(
    opening: opening,
    changes: newestFirst.reversed.toList(growable: false),
    current: current,
  );
});
