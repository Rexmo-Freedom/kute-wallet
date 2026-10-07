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
// ledger decides until it does. An entry with a zero balance is a real
// zero and still wins.
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
    show BreezSdk, GetInfoRequest, GetInfoResponse, SyncWalletRequest;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/balance_history.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
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

/// The dollar balance a 100% dollar move sends, in base units, read after
/// a sync so it is not the cached figure the last background sync left.
/// A failed sync falls back to that cached figure; the SDK still refuses
/// a transfer it cannot fund.
Future<BigInt> usdDrainBaseUnits(BreezSdk sdk) async {
  try {
    await sdk
        .syncWallet(request: const SyncWalletRequest())
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    // Cached reading below.
  }
  return usdBaseUnitsFromNodeInfo(
      await sdk.getInfo(request: const GetInfoRequest()));
}

/// Brings the dollar reading up to date when the ledger moves.
///
/// The SDK caches `tokenBalances` and tells the app about a change only
/// through events, and an incoming dollar transfer can settle without
/// one reaching the app: when a sync records the payment as completed
/// before the operator stream delivers the transfer, the stream's late
/// balance refresh emits no payment event (the status did not advance),
/// and the SDK's Synced event is held back entirely while a sync step
/// keeps failing. Activity, which polls `listPayments`, then shows the
/// receive while the balance keeps the old figure until a restart.
///
/// So the ledger is the trigger: whenever the set of settled dollar
/// payments changes, re-read `getInfo`; when that still returns the
/// figure from before the change, force a wallet sync (it refreshes the
/// token outputs) and read again. One run at a time; a change that lands
/// mid-run queues one more.
class UsdLedgerCatchUp {
  UsdLedgerCatchUp({
    required this.readInfo,
    required this.syncWallet,
    required this.publish,
    this.debounce = const Duration(milliseconds: 800),
    this.syncTimeout = const Duration(seconds: 20),
  });

  final Future<GetInfoResponse> Function() readInfo;
  final Future<void> Function() syncWallet;
  final void Function(double? reading) publish;
  final Duration debounce;
  final Duration syncTimeout;

  String? _signature;
  double? _lastReading;
  bool _hasReading = false;
  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Every reading the provider publishes, from any feed, passes here so
  /// "unchanged" is judged against the latest one.
  void recordReading(double? reading) {
    _lastReading = reading;
    _hasReading = true;
  }

  /// The settled dollar ledger's identity. The first call is the
  /// baseline; every later change schedules a catch-up.
  void onLedger(String signature) {
    if (_disposed) return;
    final previous = _signature;
    _signature = signature;
    if (previous == null || previous == signature) return;
    _timer?.cancel();
    _timer = Timer(debounce, _run);
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final before = _hasReading ? _lastReading : null;
        final hadReading = _hasReading;
        double? reading;
        try {
          reading = usdDollarsFromNodeInfo(await readInfo());
        } catch (_) {
          continue;
        }
        if (_disposed) return;
        if (!hadReading || reading != before) {
          _emit(reading);
          continue;
        }
        // Same figure as before the ledger moved: the SDK's cache has
        // not seen the transfer yet. Sync, then read again.
        try {
          await syncWallet().timeout(syncTimeout);
        } catch (_) {
          // Read what the cache holds anyway.
        }
        if (_disposed) return;
        try {
          _emit(usdDollarsFromNodeInfo(await readInfo()));
        } catch (_) {
          // The next ledger change or SDK event tries again.
        }
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  void _emit(double? reading) {
    if (_disposed) return;
    recordReading(reading);
    publish(reading);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// The settled dollar ledger's identity for [UsdLedgerCatchUp]: the ids
/// of the settled dollar payments, in a stable order.
String usdLedgerSignature(Iterable<UsdbTokenTransaction> settled) =>
    (settled.map((tx) => tx.id).toList()..sort()).join(',');

/// The live dollar balance as the SDK reports it. Seeded with a direct
/// `getInfo` read so the tab has a number immediately, then follows
/// three feeds: the wallet-info stream (re-emitted after payment events
/// the SDK raises), each Synced event (debounced re-read: an incoming
/// transfer can arrive through a sync, which raises only Synced), and
/// the settled dollar ledger through [UsdLedgerCatchUp], which covers a
/// transfer that settled without either event reaching the app.
///
/// Emits null when the SDK's answer has no dollar entry (see
/// [usdDollarsFromNodeInfo]); [usdBalanceProvider] then reads the ledger.
final usdSdkBalanceProvider = StreamProvider<double?>((ref) async* {
  final wrapper = await ref.watch(breezSDKProvider.future);
  final sdk = wrapper.instance;
  if (sdk == null) return;
  final readings = StreamController<double?>();
  late final UsdLedgerCatchUp catchUp;
  void publish(double? reading) {
    catchUp.recordReading(reading);
    if (!readings.isClosed) readings.add(reading);
  }

  catchUp = UsdLedgerCatchUp(
    readInfo: () async {
      final info = await sdk.getInfo(request: const GetInfoRequest());
      _debugLogUsdReading('ledger', info);
      return info;
    },
    syncWallet: () => sdk.syncWallet(request: const SyncWalletRequest()),
    publish: (reading) {
      if (!readings.isClosed) readings.add(reading);
    },
  );
  try {
    final info = await sdk.getInfo(request: const GetInfoRequest());
    _debugLogUsdReading('getInfo', info);
    publish(usdDollarsFromNodeInfo(info));
  } catch (_) {
    // Non-fatal: the feeds below carry the next reading.
  }
  Timer? debounce;
  final infoSub = wrapper.walletInfoStream
      .listen((info) => publish(usdDollarsFromNodeInfo(info)));
  final syncedSub = wrapper.syncedStream.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 1200), () async {
      try {
        final info = await sdk.getInfo(request: const GetInfoRequest());
        _debugLogUsdReading('synced', info);
        publish(usdDollarsFromNodeInfo(info));
      } catch (_) {
        // The next sync, payment event or ledger change reads again.
      }
    });
  });
  // Money landed in Dollars: one haptic per new settled receive of this
  // session. The ledger as first read, and any history a sync or a
  // restore streams in later, is older than the session and stays quiet.
  final arrivals = IncomingPaymentGate(startedAt: DateTime.now());
  ref.listen<List<UsdbTokenTransaction>>(
    _usdSettledTransfersProvider,
    (_, settled) {
      catchUp.onLedger(usdLedgerSignature(settled));
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
  ref.onDispose(() {
    debounce?.cancel();
    catchUp.dispose();
    infoSub.cancel();
    syncedSub.cancel();
    readings.close();
  });
  yield* readings.stream;
});

/// Settled dollar transfers on the spending account, newest last.
final _usdSettledTransfersProvider =
    Provider<List<UsdbTokenTransaction>>((ref) {
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
final _usdLedgerBalanceProvider = Provider<double>((ref) {
  var net = 0;
  for (final tx in ref.watch(_usdSettledTransfersProvider)) {
    final units = tx.amount.toInt();
    net += tx.type == TransactionType.sent ? -units : units;
  }
  return net / 1e6;
});

/// USD held on the spending account, in dollars.
final usdBalanceProvider = Provider<double>((ref) {
  final double? fromSdk = ref.watch(usdSdkBalanceProvider).valueOrNull;
  final double dollars = fromSdk ?? ref.watch(_usdLedgerBalanceProvider);
  // A cache that has lost old receives (history trimmed on a restore)
  // could otherwise show a negative dollar balance.
  return dollars < 0 ? 0 : dollars;
});

/// The dollar balance by day, for the Dollars tab's Balance chart.
///
/// Reconstructed the same way the USDC series is: anchor on today's
/// balance and walk the settled transfers backwards, undoing each one to
/// recover what the account held before it. Days with no transfer carry
/// no entry — the chart forward-fills from the previous one.
final usdBalanceHistoryProvider = Provider<Map<DateTime, double>>((ref) {
  final current = ref.watch(usdBalanceProvider);
  final transfers = ref.watch(_usdSettledTransfersProvider);

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
  final transfers = ref.watch(_usdSettledTransfersProvider);
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
