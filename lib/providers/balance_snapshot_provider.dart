// lib/providers/balance_snapshot_provider.dart
//
// `balance_snapshot`: where the spending account's money sits, once per
// app session (and at most once per 6 h across sessions), so PostHog can
// count how many people hold money in several places and see what the
// one-balance sweeper leaves at the venues (`waiting_usd`) and on the
// rails (`in_flight_usd`).
//
// Exact USD amounts (the owner's analytics rule allows exact amounts and
// balances); never a key, address, id or anything typed. Spending (hot)
// account only: a Ledger, Bitcoin-only, watch-only or tracked wallet never
// sends one. The values come from the providers the Home hero and the
// one-balance header already watch. Analytics only: nothing here moves
// money or reads the network.
//
// Ported from the `unification-test` branch (2026-10) and extended with
// the one-balance fields.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/services/tracking_service.dart';

/// What the snapshot needs, as the providers know it right now.
@immutable
class BalanceSnapshotInputs {
  /// The wallet Home shows is the spending (hot) account. False for a
  /// Ledger, Bitcoin-only, watch-only or tracked wallet.
  final bool isSpendingAccount;

  /// The live wallet has answered (not only the cached figure).
  final bool bitcoinLoaded;

  /// The dollar balance has had its first reading.
  final bool dollarsKnown;

  /// Spark + on-chain sats, as the hero shows them.
  final int btcSats;

  /// USD per bitcoin; null (or not positive) until rates load.
  final double? usdPerBtc;

  final double dollarsUsd;
  final UnifiedVenueBalances venues;

  /// Venue cash the sweeper still owes back (below the minimum, batching,
  /// backing off), all venues.
  final double waitingUsd;

  /// Dollars on a rail in either direction, plus dollars arriving.
  final double inFlightUsd;

  const BalanceSnapshotInputs({
    required this.isSpendingAccount,
    this.bitcoinLoaded = false,
    this.dollarsKnown = false,
    this.btcSats = 0,
    this.usdPerBtc,
    this.dollarsUsd = 0,
    this.venues = UnifiedVenueBalances.empty,
    this.waitingUsd = 0,
    this.inFlightUsd = 0,
  });

  static const notSpending = BalanceSnapshotInputs(isSpendingAccount: false);

  bool get _priceKnown {
    final p = usdPerBtc;
    return p != null && p.isFinite && p > 0;
  }

  /// Bitcoin, its price and Dollars are known on the spending account.
  bool get coreKnown =>
      isSpendingAccount && bitcoinLoaded && dollarsKnown && _priceKnown;

  /// Both venues have answered too, so nothing would be omitted.
  bool get allKnown =>
      coreKnown && venues.investingKnown && venues.predictionsKnown;
}

double _usd(double v) =>
    v.isFinite && v > 0 ? (v * 100).roundToDouble() / 100 : 0;

/// The event's properties, or null until [BalanceSnapshotInputs.coreKnown].
/// Venue fields are omitted while their venue is unknown; `invested_usd`
/// needs both venues. `buckets_with_money` counts the sent amounts over $1
/// (bitcoin, dollars, the venues' cash), not the rail figures.
@visibleForTesting
Map<String, Object>? balanceSnapshotParams(BalanceSnapshotInputs i) {
  if (!i.coreKnown) return null;
  final v = i.venues;
  final amounts = <String, double>{
    'btc_usd': _usd(i.btcSats / 1e8 * i.usdPerBtc!),
    'dollars_usd': _usd(i.dollarsUsd),
    if (v.investingKnown) 'investing_cash_usd': _usd(v.readyInInvestingUsd),
    if (v.predictionsKnown)
      'predictions_cash_usd': _usd(v.readyInPredictionsUsd),
    if (v.investingKnown && v.predictionsKnown)
      'invested_usd': _usd(v.investedUsd),
  };
  return {
    ...amounts,
    'waiting_usd': _usd(i.waitingUsd),
    'in_flight_usd': _usd(i.inFlightUsd),
    'buckets_with_money': amounts.values.where((a) => a > 1).length,
    'wallet_kind': 'hot',
  };
}

/// Sends `balance_snapshot` once the balances are known: at once when every
/// venue has answered, else after [venueGrace] with what is known by then.
/// At most once per process and once per [minInterval] (persisted). While
/// analytics are off (opt-out or debug) it does nothing at all, so the
/// session's slot and the 6 h stamp are left for a session that can send.
class BalanceSnapshotReporter {
  BalanceSnapshotReporter({
    DateTime Function()? clock,
    DateTime? Function()? readLastSentAt,
    void Function(DateTime)? writeLastSentAt,
    bool Function()? analyticsDisabled,
    void Function(String event, Map<String, Object> params)? send,
  })  : _clock = clock ?? DateTime.now,
        _readLastSentAt = readLastSentAt ?? _hiveLastSentAt,
        _writeLastSentAt = writeLastSentAt ?? _hiveWriteLastSentAt,
        _analyticsDisabled = analyticsDisabled ?? (() => TrackingService.isDisabled),
        _send = send ??
            ((event, params) => TrackingService.track(event, params: params));

  /// The app-wide reporter.
  static final BalanceSnapshotReporter shared = BalanceSnapshotReporter();

  static const Duration minInterval = Duration(hours: 6);
  static const Duration venueGrace = Duration(seconds: 20);
  static const String lastSentKey = 'analytics_balance_snapshot_at';

  final DateTime Function() _clock;
  final DateTime? Function() _readLastSentAt;
  final void Function(DateTime) _writeLastSentAt;
  final bool Function() _analyticsDisabled;
  final void Function(String event, Map<String, Object> params) _send;

  bool _done = false;
  Timer? _grace;
  BalanceSnapshotInputs _latest = BalanceSnapshotInputs.notSpending;

  /// True once this session sent its snapshot (or found one sent < 6 h ago).
  bool get isDone => _done;

  void observe(BalanceSnapshotInputs inputs) {
    _latest = inputs;
    if (_done) return;
    if (_analyticsDisabled() || !inputs.coreKnown) {
      // Opted out, or the wallet changed / balances not known: wait again.
      _cancelGrace();
      return;
    }
    final last = _readLastSentAt();
    if (last != null && _clock().difference(last).abs() < minInterval) {
      _done = true;
      _cancelGrace();
      return;
    }
    if (inputs.allKnown) {
      _sendNow();
      return;
    }
    _grace ??= Timer(venueGrace, () {
      _grace = null;
      if (!_done && !_analyticsDisabled() && _latest.coreKnown) _sendNow();
    });
  }

  void _sendNow() {
    final params = balanceSnapshotParams(_latest);
    if (params == null) return;
    _done = true;
    _cancelGrace();
    _send('balance_snapshot', params);
    try {
      _writeLastSentAt(_clock());
    } catch (_) {/* best-effort */}
  }

  void _cancelGrace() {
    _grace?.cancel();
    _grace = null;
  }

  /// Stops a pending grace timer (provider disposed).
  void dispose() => _cancelGrace();

  static DateTime? _hiveLastSentAt() {
    try {
      if (!Hive.isBoxOpen('settings')) return null;
      final v = Hive.box('settings').get(lastSentKey);
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    } catch (_) {
      return null;
    }
  }

  static void _hiveWriteLastSentAt(DateTime at) {
    if (!Hive.isBoxOpen('settings')) return;
    Hive.box('settings').put(lastSentKey, at.millisecondsSinceEpoch);
  }
}

/// The snapshot's inputs from the providers Home already watches: the
/// hero's bitcoin (active-wallet balance + the live SDK state), the USD
/// rate, the Dollars reading, the venue split and the one-balance rail
/// figures. Nothing past the wallet check is read for a wallet that is
/// not the spending account.
final balanceSnapshotInputsProvider = Provider<BalanceSnapshotInputs>((ref) {
  final isSpending = ref.watch(
      settingsProvider.select((s) => s.activeWallet?.isSparkWallet ?? false));
  if (!isSpending) return BalanceSnapshotInputs.notSpending;
  final sdk = ref.watch(breezSDKProvider);
  final balance = ref.watch(balanceNotifierProvider);
  final usd = ref.watch(usdSdkBalanceProvider);
  final oneBalance = ref.watch(oneBalanceProvider);
  return BalanceSnapshotInputs(
    isSpendingAccount: true,
    bitcoinLoaded: sdk.hasValue && !sdk.isLoading,
    dollarsKnown: usd.hasValue,
    btcSats: balance.sparkBitcoinbalance + balance.onChainBtcBalance,
    usdPerBtc: ref.watch(selectedCurrencyProvider('USD')).toDouble(),
    dollarsUsd: ref.watch(usdBalanceProvider),
    venues: ref.watch(unifiedVenueBalancesProvider),
    waitingUsd: oneBalance.waitingUsd,
    inFlightUsd: oneBalance.inFlightUsd,
  );
});

/// Feeds [BalanceSnapshotReporter.shared]. Home reads it once (like the
/// other long-lived listeners it pre-flushes) and it lives for the app.
/// Once the session's snapshot is sent the inputs are released, so the
/// venue reads behind them are kept warm only by the screens that show
/// them.
final balanceSnapshotReporterProvider =
    Provider<BalanceSnapshotReporter>((ref) {
  final reporter = BalanceSnapshotReporter.shared;
  if (reporter.isDone) return reporter;
  ProviderSubscription<BalanceSnapshotInputs>? sub;
  sub = ref.listen<BalanceSnapshotInputs>(
    balanceSnapshotInputsProvider,
    (_, next) {
      reporter.observe(next);
      if (reporter.isDone) {
        sub?.close();
        sub = null;
      }
    },
    fireImmediately: true,
  );
  ref.onDispose(() {
    sub?.close();
    reporter.dispose();
  });
  return reporter;
});
