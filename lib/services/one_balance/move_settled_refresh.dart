// When a move between the spending account's cash accounts ends, the
// balances at both of its ends read again at once.
//
// A move's end is reported by whichever rail carried it: the background
// sync's Orchestra status poll (a row turning success or refunded), the
// settlement reconciler (an operation reaching a terminal stage), the CCTP
// watcher (Investing out by Circle), the HyperCore rail (a native credit
// seen on the venue), the Predictions account (a deposit converted, a
// withdrawal confirmed). Each of those used to leave the figures on screen
// to their own polls: Investing every few seconds, Predictions on its
// tick, Bitcoin and Dollars on the next sync, so a move that had plainly
// landed read as not there for a while, at one end or both. Every rail now
// calls [MoveSettledRefresh.settled] with the accounts it touched, and one
// deferred pass refreshes exactly those.
//
// The pass never runs inside the caller's own stack (several callers run
// inside the sync it would wait on): it is scheduled, and calls landing
// within [debounce] of each other share one pass. Nothing here moves
// funds; a failure to read is left to the ordinary polls.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/background_sync_provider.dart'
    show backgroundSyncNotifierProvider;
import 'package:kute/providers/breez_provider.dart'
    show sparkBitcoinBalanceProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceCheckProvider, usdSdkBalanceProvider;
import 'package:kute/services/one_balance/money_movement_route.dart'
    show MoneyMovementAccount;

class MoveSettledRefresh {
  MoveSettledRefresh._();

  /// Calls landing within this of each other share one refresh pass.
  static Duration debounce = const Duration(milliseconds: 300);

  static Ref? _ref;
  static final Set<MoneyMovementAccount> _pending = {};
  static final Set<String> _pendingSources = {};
  static Timer? _timer;

  /// Test seam: sees every [settled] call (accounts, source) as it lands.
  @visibleForTesting
  static void Function(Set<MoneyMovementAccount> accounts, String source)?
      debugObserver;

  /// Test seam: runs in place of [run] when set.
  @visibleForTesting
  static Future<void> Function(Set<MoneyMovementAccount> accounts)?
      debugRunner;

  /// The app binds the provider scope once (the background sync's
  /// notifier, alive for the session). Without it [settled] only records.
  static void bind(Ref ref) => _ref = ref;

  /// A move touching [accounts] ended (delivered, refunded or failed with
  /// the money back where it was). [source] names the rail, for logs and
  /// tests only. Safe from any stack: the refresh runs later, once.
  static void settled(Set<MoneyMovementAccount> accounts,
      {required String source}) {
    if (accounts.isEmpty) return;
    debugObserver?.call(Set.unmodifiable(accounts), source);
    _pending.addAll(accounts);
    _pendingSources.add(source);
    _timer ??= Timer(debounce, _flush);
  }

  /// [settled] for an Activity row, by its two legs.
  static void settledRow(SwapOrder row, {required String source}) =>
      settled(accountsOfRow(row), source: source);

  /// [settled] for a settlement operation, by its flow.
  static void settledFlow(SettlementFlow flow, {required String source}) =>
      settled(accountsOfFlow(flow), source: source);

  static void _flush() {
    _timer = null;
    final accounts = Set<MoneyMovementAccount>.of(_pending);
    _pending.clear();
    _pendingSources.clear();
    if (accounts.isEmpty) return;
    final runner = debugRunner;
    if (runner != null) {
      unawaited(runner(accounts));
      return;
    }
    final ref = _ref;
    if (ref == null) return;
    unawaited(run(ref, accounts));
  }

  /// Reads [accounts] again now. Each account's read is independent and
  /// its failure is its own: the others still refresh.
  static Future<void> run(Ref ref, Set<MoneyMovementAccount> accounts) async {
    final reads = <Future<void>>[];
    if (accounts.contains(MoneyMovementAccount.predictions)) {
      reads.add(_guard(() async {
        final pm = ref.read(polymarketTradingProvider.notifier);
        pm.invalidateBalanceCache();
        await pm.refresh();
      }));
    }
    if (accounts.contains(MoneyMovementAccount.investing)) {
      reads.add(_guard(
          () => ref.read(hyperliquidAccountProvider.notifier).refresh()));
    }
    final spark = accounts.contains(MoneyMovementAccount.bitcoin) ||
        accounts.contains(MoneyMovementAccount.dollars);
    if (spark) {
      reads.add(_guard(() async {
        if (accounts.contains(MoneyMovementAccount.bitcoin)) {
          ref.invalidate(sparkBitcoinBalanceProvider);
        }
        if (accounts.contains(MoneyMovementAccount.dollars)) {
          ref.invalidate(usdSdkBalanceProvider);
          ref.read(usdBalanceCheckProvider).request('move_settled');
        }
        // The wallet sync that publishes the Bitcoin and Dollars figures
        // (and the history row beside them). Waits for a sync already
        // running, then runs its own, so what it reads was read after
        // the move ended.
        await ref
            .read(backgroundSyncNotifierProvider.notifier)
            .performUserRefresh();
      }));
    }
    await Future.wait(reads);
  }

  static Future<void> _guard(Future<void> Function() read) async {
    try {
      await read();
    } catch (_) {
      // Left to the account's own poll.
    }
  }

  /// The cash account a leg (network, asset) belongs to, or null for a
  /// leg that is none of the four (an external address, a fiat rail).
  static MoneyMovementAccount? accountOf(
      {required String network, required String asset}) {
    final net = network.trim().toUpperCase();
    final coin = asset.trim().toUpperCase();
    switch (net) {
      case 'SPARK':
      case 'LIGHTNING':
      case 'BITCOIN':
        if (coin == 'BTC' || coin == 'SATS') return MoneyMovementAccount.bitcoin;
        if (coin == 'USDB' || coin == 'USD' || coin == 'USDC') {
          return MoneyMovementAccount.dollars;
        }
        return null;
      case 'HYPERCORE':
      case 'HYPERLIQUID':
        return MoneyMovementAccount.investing;
      case 'POLYGON':
        if (coin == 'USDC' || coin == 'USDC.E' || coin == 'PUSD') {
          return MoneyMovementAccount.predictions;
        }
        return null;
      default:
        return null;
    }
  }

  /// Both ends of an Activity row, as far as they are cash accounts.
  static Set<MoneyMovementAccount> accountsOfRow(SwapOrder row) => {
        if (accountOf(network: row.networkFrom, asset: row.coinFrom)
            case final from?)
          from,
        if (accountOf(network: row.networkTo, asset: row.coinTo)
            case final to?)
          to,
      };

  /// Both ends of a settlement flow between the spending account's cash
  /// accounts. A Ledger flow or an external send touches none of them.
  static Set<MoneyMovementAccount> accountsOfFlow(SettlementFlow flow) {
    const b = MoneyMovementAccount.bitcoin;
    const d = MoneyMovementAccount.dollars;
    const i = MoneyMovementAccount.investing;
    const p = MoneyMovementAccount.predictions;
    return switch (flow) {
      SettlementFlow.moveUsdToBtc => {p, b},
      SettlementFlow.moveBtcToPredictions => {b, p},
      SettlementFlow.predictionsDeposit => {b, p},
      SettlementFlow.predictionsWithdraw => {p, b},
      SettlementFlow.predictionsBtcRoute => {b, p},
      SettlementFlow.moveBtcToInvesting => {b, i},
      // Used by both the Bitcoin and the Dollars door into Investing.
      SettlementFlow.sparkToInvestingDirect => {b, d, i},
      SettlementFlow.moveInvestingToBtc => {i, b},
      SettlementFlow.investingToSparkDirect => {i, b},
      SettlementFlow.investingToBtcCctp => {i, b},
      SettlementFlow.moveBtcToUsdc => {b, d},
      SettlementFlow.moveDollarsToBtc => {d, b},
      SettlementFlow.moveUsdToPredictions => {d, p},
      SettlementFlow.moveUsdToInvesting => {d, i},
      SettlementFlow.movePredictionsToDollars => {p, d},
      SettlementFlow.investingToSparkUsdDirect => {i, d},
      SettlementFlow.investingToDollarsCctp => {i, d},
      SettlementFlow.movePredictionsToInvesting => {p, i},
      SettlementFlow.investingToPredictionsDirect => {i, p},
      SettlementFlow.investingToPredictionsCctp => {i, p},
      SettlementFlow.sendExternal ||
      SettlementFlow.ledgerBtcToInvesting ||
      SettlementFlow.investingToLedgerBtc ||
      SettlementFlow.ledgerBtcToPredictions ||
      SettlementFlow.predictionsToLedgerBtc ||
      SettlementFlow.unknown =>
        const {},
    };
  }

  @visibleForTesting
  static void debugReset() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _pendingSources.clear();
    _ref = null;
    debugObserver = null;
    debugRunner = null;
    debounce = const Duration(milliseconds: 300);
  }
}
