// lib/providers/refresh_everything_provider.dart
//
// Pull-to-refresh is "update everything" (founder, 2026-10-15: "pulling
// up on the investments should update everything"). One function for
// every surface that has the gesture on the spending account's side, Home
// and Investments (every pill), so the two can never drift apart again.
//
// What it does, all in parallel, for the spending wallet, without tearing
// the wallet session down or asking for anything again:
//
//   * Bitcoin and dollars, as a hot restart does it: the Breez SDK
//     connected again (`BreezSdkSpark.reconnectForPull`: the live handle
//     shut down and the wallet connected from the request it was
//     connected with, so no unlock, PIN or passkey prompt), then one
//     wallet sync on the new handle and a `getInfo` + `listPayments` read
//     published to the balance streams. Why a reconnect: `getInfo` only
//     ever reads the SDK's cached account figure, which only a wallet
//     sync, a payment event or the SDK's start refreshes. The pull's sync
//     on the live handle joins the one already outstanding (the app shares
//     one native `syncWallet` per handle, and a Dart timeout never frees
//     it), which a dead connection after a network change can hold for
//     minutes, and the SDK's sync returns without refreshing the figure
//     when its leaf refresh fails. The SDK's start refreshes leaves and
//     tokens on their own and opens a new event stream: what a restart
//     showed. Never while something is mid-flight on the handle (a
//     payment, prepare, claim or refund, a pending send, a quote being
//     created, a leaf optimization): then the pull syncs the live handle
//     only (`refresh_mode` `sync`). The wrapper's streams outlive the
//     reconnect, so no figure blanks: each keeps its value until the new
//     reading lands. Before either, the balance stream's freshness guard
//     is cleared and a send hold whose send is no longer pending is ended
//     (in-memory caps a restart drops too). The Dollars reading checks
//     itself too (usdBalanceCheckProvider), polling the cached token
//     figure through that sync while it has no dollar entry;
//   * the full background sync (`performUserRefresh`): Spark, dollar and
//     on-chain history, the Predictions activity, the Orchestra order
//     statuses and the currency rates (read again: they were read once a
//     process). It waits for a sync already
//     running rather than returning without doing anything;
//   * Predictions (`PolymarketTradingNotifier.pullRefresh`): one full
//     read, or the account start again when it failed, found no deposit
//     address, is stuck, or ended without CLOB credentials; then the open
//     orders, the activity and the combos;
//   * Investing: the account address derived again when the first try
//     found none (it was cached for the whole process), the trading state
//     read (or built again when it never initialized), the fills, and the
//     always-on badge poll (free USDC, held positions, the once-flag);
//   * the Portfolio's Statistics figures.
//
// Every venue read merges into what is on screen and every provider that
// reloads keeps its last value, so no figure is cleared to blank or "—"
// while this runs: the stale shimmer stays until the new figure lands.
//
// The spinner: [RefreshEverything.call] resolves when everything is done
// or after [RefreshEverything.spinnerCap] (4 s), whichever comes first;
// the rest keeps running and each surface updates as its results land.
// A pull while an earlier one is still running joins it, for at most
// [RefreshEverything.stepLimit]: each step is bounded by it, and a run
// older than it is never joined, so a hung read never keeps a later pull
// from running.
//
// Analytics: `pull_to_refresh_executed` with the surface's `screen` (and
// the Investments pill as `tab`) and the run's `refresh_mode`
// (`reconnect` or `sync`, as decided when the run started; a reconnect
// the SDK's pending-send check then refuses syncs, and
// `usd_token_recovery` with source `pull` reports that outcome). No ids
// or addresses.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show updateCurrencyProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidUserFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventsProvider;
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceCheckProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/network_change_signal.dart'
    show RegionRecheckTrigger;
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/tracking_service.dart';

/// The surface a pull came from, as `pull_to_refresh_executed` reports it.
class RefreshTrigger {
  const RefreshTrigger(this.screen, {this.tab});

  /// Home's pull.
  static const home = RefreshTrigger('home');

  /// The analytics `screen`: `home`, `usd` (Investments, the name the
  /// Dollars screen sent before one balance), `hyperliquid`, `polymarket`.
  final String screen;

  /// The Investments pill on screen (`investing`, `predictions`,
  /// `positions`), when the pull came from Investments.
  final String? tab;
}

/// One part of the refresh, by name (tests replace them).
typedef RefreshStep = Future<void> Function();

/// How a run refreshes the spending wallet's balances, as
/// `pull_to_refresh_executed` reports it (`refresh_mode`).
enum RefreshMode {
  /// One wallet sync on the live SDK connection.
  sync('sync'),

  /// The SDK connected again first, as a hot restart does.
  reconnect('reconnect');

  const RefreshMode(this.id);

  /// The analytics value.
  final String id;
}

/// The shared pull-to-refresh, for every surface ([RefreshEverything]).
final refreshEverythingProvider =
    Provider<RefreshEverything>((ref) => RefreshEverything(ref));

class RefreshEverything {
  RefreshEverything(this._ref,
      {Map<String, RefreshStep>? steps, @visibleForTesting Set<String>? only})
      : _stepsOverride = steps,
        _only = only;

  final Ref _ref;
  final Map<String, RefreshStep>? _stepsOverride;

  /// Tests: only these of the real steps run.
  final Set<String>? _only;

  /// How long the pull's spinner stays up at most; the work goes on.
  @visibleForTesting
  static Duration spinnerCap = const Duration(seconds: 4);

  /// How long one step is waited for before the run counts it done (it
  /// keeps going and still lands on screen).
  @visibleForTesting
  static Duration stepLimit = const Duration(seconds: 30);

  Future<void>? _running;
  Stopwatch? _runningFor;
  RefreshMode _mode = RefreshMode.sync;

  /// How the current (or last) run refreshes the balances.
  @visibleForTesting
  RefreshMode get mode => _mode;

  /// A pull from [trigger]: starts (or joins) [run], reports it with the
  /// run's mode, and resolves when the run is done or after [spinnerCap].
  /// Never throws.
  Future<void> call(RefreshTrigger trigger) async {
    final pending = run();
    TrackingService.pullToRefreshExecuted(
        screen: trigger.screen, tab: trigger.tab, refreshMode: _mode.id);
    try {
      await pending.timeout(spinnerCap);
    } catch (_) {
      // The cap: the spinner goes, the refresh carries on and every
      // surface updates as its results land.
    }
  }

  /// Home's pull: the mascot in `refreshing` while the spinner is up and
  /// the cached predictions feed dropped (Home's own extra, so the markets
  /// list reads again beside the balances and positions), then [call].
  Future<void> home() async {
    try {
      _ref.read(kuteStateProvider.notifier).setRefreshing(true);
    } catch (_) {}
    try {
      _ref.invalidate(polymarketEventsProvider);
    } catch (_) {}
    await call(RefreshTrigger.home);
    try {
      _ref.read(kuteStateProvider.notifier).setRefreshing(false);
    } catch (_) {}
  }

  /// Every part of the refresh by name, as [run] starts them.
  @visibleForTesting
  Map<String, RefreshStep> get steps {
    final override = _stepsOverride;
    if (override != null) return override;
    final only = _only;
    if (only == null) return _steps;
    return {
      for (final e in _steps.entries)
        if (only.contains(e.key)) e.key: e.value
    };
  }

  /// Every step at once; resolves when all of them are done (each bounded
  /// by [stepLimit]). A run already going is joined while it is younger
  /// than [stepLimit]; an older one is hung past every bound, so a fresh
  /// run starts beside it. Never throws.
  Future<void> run() {
    final running = _running;
    final age = _runningFor?.elapsed ?? Duration.zero;
    if (running != null && age < stepLimit) return running;
    _mode = _decideMode();
    final next = _runAll();
    _running = next;
    _runningFor = Stopwatch()..start();
    next.whenComplete(() {
      if (identical(_running, next)) {
        _running = null;
        _runningFor = null;
      }
    });
    return next;
  }

  /// [RefreshMode.reconnect] when the SDK can be connected again now
  /// without disturbing anything ([BreezSdkSpark.canReconnectForPull]) and
  /// no outgoing Spark send is in flight; [RefreshMode.sync] otherwise,
  /// and whenever the connection has not been read yet.
  RefreshMode _decideMode() {
    try {
      if (!_ref.exists(breezSDKProvider)) return RefreshMode.sync;
      final wrapper = _ref.read(breezSDKProvider).valueOrNull;
      if (wrapper == null || !wrapper.canReconnectForPull) {
        return RefreshMode.sync;
      }
      final spendingId = _spendingId();
      if (spendingId != null &&
          _ref.exists(walletBalanceCacheProvider) &&
          _ref
              .read(walletBalanceCacheProvider.notifier)
              .hasOutgoingSparkSendInFlight(spendingId)) {
        return RefreshMode.sync;
      }
      return RefreshMode.reconnect;
    } catch (_) {
      return RefreshMode.sync;
    }
  }

  String? _spendingId() {
    final id = pickSpendingWallet(_ref.read(settingsProvider))?.id;
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _runAll() async {
    // The balance stream's freshness guard first, so the sync's balance
    // write below is taken.
    try {
      _ref.read(balanceNotifierProvider.notifier).invalidateStreamFreshness();
    } catch (_) {}
    // A send hold is in memory only (a restart drops it): one whose send
    // is no longer pending never caps the figure through a pull.
    try {
      final spendingId = _spendingId();
      if (spendingId != null && _ref.exists(walletBalanceCacheProvider)) {
        _ref
            .read(walletBalanceCacheProvider.notifier)
            .releaseSettledSendHolds(spendingId);
      }
    } catch (_) {}
    await Future.wait([
      for (final step in steps.values) _bounded(step),
    ]);
  }

  /// Invalidates [provider] when something holds it; one nobody holds has
  /// nothing on screen to refresh and is read fresh when it is first
  /// wanted (a provider's own `invalidate` would build it first in debug).
  void _invalidate(ProviderBase<Object?> provider) {
    if (_ref.exists(provider)) _ref.invalidate(provider);
  }

  Future<void> _bounded(RefreshStep step) async {
    try {
      await Future<void>.sync(step).timeout(stepLimit);
    } catch (_) {
      // A step that failed or ran out of time leaves the last figures.
    }
  }

  Map<String, RefreshStep> get _steps => {
        // Every "available in your region" answer asked again beside
        // the data: a pull never leaves a stale refusal on screen.
        'region': () => RegionFreshness.recheck(RegionRecheckTrigger.pull),
        'bitcoin': _bitcoin,
        'sync': _sync,
        'predictions': _predictions,
        'investing': _investing,
        'portfolio': _portfolio,
      };

  /// The SDK connected again when the run's mode says so, then one Breez
  /// SDK sync, then `getInfo` (Bitcoin and dollars) and the payments
  /// published to the balance streams.
  Future<void> _bitcoin() async {
    final reconnect = _mode == RefreshMode.reconnect;
    // A connect that failed (offline at unlock) stays failed until the
    // next unlock. When the wrapper kept the request it connected with,
    // the reconnect below connects from it (no unlock); otherwise connect
    // again as the unlock does, while unlocked. A connect under way is
    // not a failed one.
    final current = _ref.read(breezSDKProvider);
    final wrapper = current.valueOrNull;
    final broken = current.hasError ||
        (current.hasValue &&
            wrapper?.instance == null &&
            !(wrapper?.isConnecting ?? false));
    if (broken &&
        !reconnect &&
        !current.isLoading &&
        _ref.read(sessionUnlockedProvider)) {
      _ref.invalidate(breezSDKProvider);
    }
    final BreezSdkSpark sdk;
    try {
      sdk = await _ref.read(breezSDKProvider.future);
    } catch (_) {
      return;
    }
    // As a hot restart: a new handle, whose start refreshes the cached
    // figures from the operators. It refuses (and answers false) when a
    // send turned up meanwhile; the sync below runs either way.
    if (reconnect) await sdk.reconnectForPull();
    // Dollars: the cached token figure read again, and while it has no
    // dollar entry (the SDK's row is behind) read every second through
    // the sync below, so it lands when the sync writes it rather than
    // when the sync answers. It joins the same shared sync.
    _ref.read(usdBalanceCheckProvider).request('refresh');
    await sdk.syncAndReread();
  }

  /// The full background sync: history, Predictions activity, Orchestra
  /// order statuses, currency rates.
  Future<void> _sync() {
    // The rates are read once a process otherwise (the sync awaits this
    // provider's future, which nothing else invalidates).
    _invalidate(updateCurrencyProvider);
    return _ref
        .read(backgroundSyncNotifierProvider.notifier)
        .performUserRefresh();
  }

  /// Predictions: the account read, or started again when it is stuck;
  /// then what hangs off it.
  Future<void> _predictions() async {
    await _ref.read(polymarketTradingProvider.notifier).pullRefresh();
    // A start it asked for: its first state (the cache, or the network).
    await _ref.read(polymarketTradingProvider.future);
    _invalidate(polymarketOpenOrdersProvider);
    _invalidate(polymarketActivityProvider);
    if (_ref.exists(polymarketCombosProvider)) {
      await _ref.read(polymarketCombosProvider.notifier).refresh();
    }
  }

  /// Investing: the address again when none was found, the trading state,
  /// the fills and the badge poll.
  Future<void> _investing() async {
    // A null address is cached for the whole process (the provider is
    // kept and rebuilds only on the wallet's identity or the session): a
    // phrase read that failed once, say on a restore, left Investing
    // empty until a restart. Derive it again; a known one is kept, so the
    // trading notifier and its signer stay.
    final address = _ref.read(hyperliquidAddressProvider);
    final hadAddress = address.valueOrNull != null;
    if (!hadAddress && !address.isLoading) {
      _ref.invalidate(hyperliquidAddressProvider);
    }
    final work = <Future<void>>[];
    if (_ref.exists(hyperliquidTradingProvider)) {
      final hl = _ref.read(hyperliquidTradingProvider).valueOrNull;
      if (hadAddress && hl != null && hl.isInitialized) {
        work.add(_ref.read(hyperliquidTradingProvider.notifier).refresh());
      } else {
        // Never initialized (no address then): build it again.
        _ref.invalidate(hyperliquidTradingProvider);
        work.add(_ref.read(hyperliquidTradingProvider.future));
      }
    } else {
      _invalidate(hyperliquidAccountProvider);
    }
    _invalidate(hyperliquidUserFillsProvider);
    work.add(
        _ref.read(hyperliquidOpenPositionsCountProvider.notifier).refreshNow());
    await Future.wait(work);
  }

  /// The Portfolio's Statistics (P&L, categories); each keeps its last
  /// figures while it reads again.
  Future<void> _portfolio() async {
    _ref
      ..invalidate(portfolioPerformanceProvider)
      ..invalidate(predictionCategoriesProvider)
      ..invalidate(predictionCategoryStakesProvider)
      ..invalidate(predictionOpenCategoriesProvider);
  }
}
