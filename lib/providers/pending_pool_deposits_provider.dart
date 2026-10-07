// lib/providers/pending_pool_deposits_provider.dart
//
// "There is a deposit of $X in flight to this pool." Derived entirely
// from the Orchestra exchange rows the deposit dispatchers already
// write (status 'exchanging' → … → 'success'), so there is no new
// polling here: the background sync's 5s Orchestra status loop mutates
// the swap orders notifier and these recompute for free.
//
// Pool identity uses the exact predicate shape the activity builder and
// the sync's revenue attribution already key on: an Orchestra order
// whose settle side is USDC on POLYGON is a Predictions deposit, USDC
// on HYPERCORE an Investing one. Withdrawals have USDC on the FROM side, so
// filtering the TO side excludes them by construction.
//
// The 30 minute age cap is the staleness guard: 'exchanging' never
// expires on its own (`isExpired` only bites on 'wait'), and the UX
// promise is "arriving in ~2 min" — a row still pending after half an
// hour is a stuck order that belongs in Activity with its status label,
// not a hero line promising imminent money.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';

const Duration _kPendingDepositMaxAge = Duration(minutes: 30);

/// True for an Orchestra deposit still on its way into the pool on
/// [network] ('POLYGON' Predictions, 'HYPERCORE' Investing) for
/// [walletId]: the one test the pool hero's arriving line and the slips'
/// "Deposit incoming" button share. The rows are persisted, so this holds
/// across app restarts.
bool isPendingPoolDeposit(
  SwapOrder e, {
  required String network,
  required String? walletId,
  required int nowMs,
}) {
  if (!e.isOrchestra || !e.isPending) return false;
  if (e.coinTo.toUpperCase() != 'USDC') return false;
  if (e.networkTo.toUpperCase() != network) return false;
  if (walletId != null && e.walletId != null && e.walletId != walletId) {
    return false;
  }
  return nowMs - e.timestamp <= _kPendingDepositMaxAge.inMilliseconds;
}

double _pendingUsdTo(Ref ref, String network) {
  final exchanges = ref.watch(swapOrdersProvider);
  final walletId = ref.watch(settingsProvider.select((s) => s.activeWalletId));
  final now = DateTime.now().millisecondsSinceEpoch;
  var sum = 0.0;
  for (final e in exchanges) {
    if (!isPendingPoolDeposit(e,
        network: network, walletId: walletId, nowMs: now)) {
      continue;
    }
    sum += double.tryParse(e.withdrawalAmount) ?? 0;
  }
  return sum;
}

/// USD in flight OUT of a pool (USDC leaving toward BTC). Keyed on the
/// FROM side of the exchange rows the withdraw dispatchers write
/// (`coinFrom USDC` on the pool's network, `depositAmount` = the USD
/// leaving). Retired providers' orders are never pending
/// (`SwapOrder.isPending`), so only live orders count.
double _pendingUsdFrom(Ref ref, String network) {
  final exchanges = ref.watch(swapOrdersProvider);
  final walletId = ref.watch(settingsProvider.select((s) => s.activeWalletId));
  final now = DateTime.now().millisecondsSinceEpoch;
  var sum = 0.0;
  for (final e in exchanges) {
    if (!e.isPending) continue;
    if (e.coinFrom.toUpperCase() != 'USDC') continue;
    if (e.networkFrom.toUpperCase() != network) continue;
    if (walletId != null && e.walletId != null && e.walletId != walletId) {
      continue;
    }
    if (now - e.timestamp > _kPendingDepositMaxAge.inMilliseconds) continue;
    sum += double.tryParse(e.depositAmount) ?? 0;
  }
  return sum;
}

/// USD in flight to the Predictions pool (spark BTC → polygon USDC.e).
final pendingPredictionsDepositUsdProvider =
    Provider.autoDispose<double>((ref) => _pendingUsdTo(ref, 'POLYGON'));

/// USD in flight to Investing through native HyperCore funding.
final pendingTradingDepositUsdProvider =
    Provider.autoDispose<double>((ref) => _pendingUsdTo(ref, 'HYPERCORE'));

/// USD leaving the Predictions pool (polygon USDC → BTC).
final pendingPredictionsWithdrawalUsdProvider =
    Provider.autoDispose<double>((ref) => _pendingUsdFrom(ref, 'POLYGON'));

/// USD leaving Investing through native HyperCore funding.
final pendingTradingWithdrawalUsdProvider =
    Provider.autoDispose<double>((ref) => _pendingUsdFrom(ref, 'HYPERCORE'));
