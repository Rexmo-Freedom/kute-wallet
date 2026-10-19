// lib/services/hyperliquid/arbitrum_refund_watch.dart
//
// USDC that came back to the wallet's own EVM address on Arbitrum.
//
// An Investing move by CCTP (cctp_withdrawal.dart) pays a one-time
// Orchestra quote from `arbitrum:USDC`, whose refund address is the
// wallet's account-zero EOA: the same address as its Hyperliquid account.
// When Flashnet rejects or refunds that deposit, the USDC lands on the EOA
// on Arbitrum, where nothing else in the app looks. This watch reads that
// balance (read-only, ArbitrumReadRpc) so Investing can show it:
//
//  * when the Investing tab or the Portfolio refreshes, at most every
//    [kArbitrumRefundScanEvery];
//  * on app resume and when a CCTP move's row turns refunded, at most
//    every [kArbitrumRefundScanFloor];
//  * a read that fails keeps the last figure: a failure is never a zero.
//
// Shown: a balance at or above Hyperliquid Bridge2's minimum deposit
// ([kBridge2MinimumUsdc6], 5 USDC: smaller deposits are never credited and
// are lost), or any balance above a cent while the wallet has a refunded
// CCTP move (with the below-the-minimum note). Anything else is dust some
// stranger sent, ignored.
//
// Moving it back to Investing is not built: the EOA holds no ETH on
// Arbitrum to pay for a transfer and Kute has no relayer to submit a
// Bridge2 `batchedDepositWithPermit` for it (the backend's was removed on
// 22 September 2026). Display only; nothing here signs or sends.
//
// PostHog: `arbitrum_refund_detected` (exact `amount_usd`, `source`
// cctp_refund | balance_scan) once per new shown amount per wallet. Never
// the address.

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/arbitrum_read_rpc.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show
        kHypercoreCctpBtcRouteVersion,
        kHypercoreCctpPredictionsRouteVersion,
        kHypercoreCctpRouteVersion;
import 'package:kute/services/tracking_service.dart';

/// Hyperliquid Bridge2's minimum deposit, in USDC base units (6 decimals).
/// "Deposits less than 5 USDC will not be credited and be lost forever"
/// (https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/bridge2,
/// read 2026-10-19).
final BigInt kBridge2MinimumUsdc6 = BigInt.from(5000000);

/// The smallest refunded balance worth a line: one cent.
final BigInt kArbitrumRefundShownFloor6 = BigInt.from(10000);

/// How often a view's refresh reads the balance again.
const Duration kArbitrumRefundScanEvery = Duration(minutes: 10);

/// The least time between two reads, whatever asks (resume, a refund).
const Duration kArbitrumRefundScanFloor = Duration(minutes: 1);

/// What asked for a read.
enum ArbitrumRefundTrigger {
  /// The Investing tab or the Portfolio refreshing.
  view,

  /// The app coming back to the foreground.
  resume,

  /// A CCTP move's row turned refunded.
  cctpRefund,
}

/// Row-id prefix of a CCTP move's Arbitrum leg (cctp_withdrawal.dart's
/// `kCctpRowPrefix`, repeated here so this file needs none of its ports).
const String _cctpRowPrefix = 'cctp-';

/// Whether [row] is an Investing move by CCTP whose Orchestra order was
/// refunded: its USDC went back to the wallet's own EOA on Arbitrum.
bool isRefundedCctpMoveRow(SwapOrder row) =>
    row.status == 'refunded' &&
    (row.id.startsWith(_cctpRowPrefix) ||
        const {
          kHypercoreCctpRouteVersion,
          kHypercoreCctpBtcRouteVersion,
          kHypercoreCctpPredictionsRouteVersion,
        }.contains(row.routeVersion));

/// The ids of [walletId]'s refunded CCTP moves among [rows].
Set<String> refundedCctpMoveIds(List<SwapOrder> rows,
        {required String? walletId}) =>
    {
      for (final row in rows)
        if (walletId != null &&
            row.walletId == walletId &&
            isRefundedCctpMoveRow(row))
          row.id,
    };

/// What the watch knows of the EOA's Arbitrum USDC.
@immutable
class ArbitrumRefundState {
  const ArbitrumRefundState({this.usdc6, this.fromRefund = false});

  /// The last balance read, USDC base units; null before any read.
  final BigInt? usdc6;

  /// The wallet has a refunded CCTP move: the balance is (at least partly)
  /// that refund.
  final bool fromRefund;

  static const ArbitrumRefundState none = ArbitrumRefundState();

  double get usd => (usdc6 ?? BigInt.zero).toDouble() / 1e6;

  /// Whether Investing shows a line for it.
  bool get shown {
    final b = usdc6;
    if (b == null) return false;
    if (b >= kBridge2MinimumUsdc6) return true;
    return fromRefund && b >= kArbitrumRefundShownFloor6;
  }

  /// Shown, but too little for a Bridge2 deposit.
  bool get belowMinimum => shown && usdc6! < kBridge2MinimumUsdc6;
}

/// The last amount `arbitrum_refund_detected` reported, per wallet, so a
/// balance sitting there is reported once, not on every read.
abstract class ArbitrumRefundReports {
  Future<BigInt?> lastReported(String walletId);
  Future<void> setReported(String walletId, BigInt? usdc6);
}

/// [ArbitrumRefundReports] in a small Hive box (amounts only).
class HiveArbitrumRefundReports implements ArbitrumRefundReports {
  static const String boxName = 'arbitrum_refund_reports';

  final Map<String, BigInt?> _memory = {};

  Future<Box<String>?> _box() async {
    try {
      return Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
    } catch (_) {
      return null; // In memory only for this run.
    }
  }

  @override
  Future<BigInt?> lastReported(String walletId) async {
    if (_memory.containsKey(walletId)) return _memory[walletId];
    final raw = (await _box())?.get(walletId);
    final value = raw == null ? null : BigInt.tryParse(raw);
    _memory[walletId] = value;
    return value;
  }

  @override
  Future<void> setReported(String walletId, BigInt? usdc6) async {
    _memory[walletId] = usdc6;
    try {
      final box = await _box();
      if (box == null) return;
      if (usdc6 == null) {
        await box.delete(walletId);
      } else {
        await box.put(walletId, usdc6.toString());
      }
    } catch (_) {/* the memory copy still dedupes this run */}
  }
}

/// The wallet whose EOA is read: its id (for the report dedupe) and the
/// address (read only; never leaves this file except to the RPC).
typedef ArbitrumRefundAccount = ({String walletId, String owner});

class ArbitrumRefundWatch extends StateNotifier<ArbitrumRefundState> {
  ArbitrumRefundWatch({
    required Future<ArbitrumRefundAccount?> Function() account,
    required bool Function(String walletId) knownRefund,
    required Future<BigInt> Function(String owner) readBalance,
    required ArbitrumRefundReports reports,
    DateTime Function()? clock,
    void Function(double amountUsd, String source)? onDetected,
  })  : _account = account,
        _knownRefund = knownRefund,
        _readBalance = readBalance,
        _reports = reports,
        _clock = clock ?? DateTime.now,
        _onDetected = onDetected ?? _trackDetected,
        super(ArbitrumRefundState.none);

  final Future<ArbitrumRefundAccount?> Function() _account;
  final bool Function(String walletId) _knownRefund;
  final Future<BigInt> Function(String owner) _readBalance;
  final ArbitrumRefundReports _reports;
  final DateTime Function() _clock;
  final void Function(double amountUsd, String source) _onDetected;

  static void _trackDetected(double amountUsd, String source) =>
      TrackingService.arbitrumRefundDetected(
          amountUsd: amountUsd, source: source);

  String? _walletId;
  DateTime? _lastAttempt;
  DateTime? _lastRead;
  Future<void>? _inFlight;

  /// Reads the balance when [trigger]'s throttle allows. Never throws.
  Future<void> scan(ArbitrumRefundTrigger trigger) {
    final running = _inFlight;
    if (running != null) return running;
    final run = _scan(trigger).catchError((Object _) {});
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  /// Whether a read for [trigger] is due at [now].
  @visibleForTesting
  bool due(ArbitrumRefundTrigger trigger, DateTime now) {
    final attempt = _lastAttempt;
    if (attempt != null && now.difference(attempt) < kArbitrumRefundScanFloor) {
      return false;
    }
    final read = _lastRead;
    if (read == null) return true;
    final every = trigger == ArbitrumRefundTrigger.view
        ? kArbitrumRefundScanEvery
        : kArbitrumRefundScanFloor;
    return now.difference(read) >= every;
  }

  Future<void> _scan(ArbitrumRefundTrigger trigger) async {
    final account = await _account();
    if (account == null) return;
    if (account.walletId != _walletId) {
      // Another wallet: nothing of the last one carries over.
      _walletId = account.walletId;
      _lastAttempt = null;
      _lastRead = null;
      if (mounted) state = ArbitrumRefundState.none;
    }
    final now = _clock();
    if (!due(trigger, now)) return;
    _lastAttempt = now;
    final BigInt balance;
    try {
      balance = await _readBalance(account.owner);
    } catch (_) {
      return; // The last figure stays; a failed read is never a zero.
    }
    if (_walletId != account.walletId || !mounted) return;
    _lastRead = now;
    final next = ArbitrumRefundState(
        usdc6: balance, fromRefund: _knownRefund(account.walletId));
    state = next;
    await _report(account.walletId, next, trigger);
  }

  Future<void> _report(String walletId, ArbitrumRefundState s,
      ArbitrumRefundTrigger trigger) async {
    final last = await _reports.lastReported(walletId);
    if (!s.shown) {
      // Gone (moved, or never there): a later refund is reported again.
      if (s.usdc6 == BigInt.zero && last != null) {
        await _reports.setReported(walletId, null);
      }
      return;
    }
    if (last == s.usdc6) return;
    await _reports.setReported(walletId, s.usdc6);
    final String source;
    if (trigger == ArbitrumRefundTrigger.cctpRefund) {
      source = 'cctp_refund';
    } else {
      source = 'balance_scan';
    }
    _onDetected(s.usd, source);
  }
}

/// The live balance read: Circle's native USDC on Arbitrum One.
Future<BigInt> readArbitrumUsdc(String owner) => ArbitrumReadRpc()
    .erc20Balance(token: ArbitrumReadRpc.usdcAddress, owner: owner);
