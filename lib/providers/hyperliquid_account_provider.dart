import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart' show Settings;
// lib/providers/hyperliquid_account_provider.dart
//
// The user's Hyperliquid account state: address derivation (READ-ONLY —
// the private key is derived and immediately discarded; signing lives in
// the trading notifier), the polled clearinghouse snapshot, cheap derived
// views for the UI, and the non-autoDispose badge count for the home
// pill.
//
// Polling cadence (mirrors PolymarketTradingNotifier._adjustRefreshRate):
//   - 5 s while positions are open OR an order placement is in flight —
//     the position cards animate PnL each tick via RollingNumberText;
//   - 15 s idle — a flat account only needs a heartbeat.
// Snapshots are value-compared before writing state so an idle tick that
// produced identical data doesn't rebuild every consumer.
//
// Lifecycle: everything here except the badge count is autoDispose — the
// account stack only runs while a Hyperliquid surface (or the trading
// notifier) is alive. The badge count is deliberately NOT autoDispose
// (the home pill watches it permanently) and is gated by the
// 'hl_enabled_<walletId>' secure-storage flag written at provisioning:
// users who never traded Hyperliquid get a constant 0 and NEVER hit the
// network — each 60 s tick for them is a local flag read only.

import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/passkey_service.dart'
    show resolveBip39MnemonicFor;

// ────────────────────── model value-equality helpers ──────────────────────
// The hyperliquid_market.dart structs deliberately don't override == (they
// are wire DTOs); the providers compare them field-wise so an unchanged
// poll tick can short-circuit notifications (same GC rationale as
// PolymarketTradingState's operator==).

bool hlPerpPositionEquals(HlPerpPosition a, HlPerpPosition b) =>
    a.coin == b.coin &&
    a.szi == b.szi &&
    a.entryPx == b.entryPx &&
    a.positionValue == b.positionValue &&
    a.unrealizedPnl == b.unrealizedPnl &&
    a.returnOnEquity == b.returnOnEquity &&
    a.liquidationPx == b.liquidationPx &&
    a.marginUsed == b.marginUsed &&
    a.leverageType == b.leverageType &&
    a.leverageValue == b.leverageValue;

bool hlPerpPositionListEquals(List<HlPerpPosition> a, List<HlPerpPosition> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!hlPerpPositionEquals(a[i], b[i])) return false;
  }
  return true;
}

bool hlSpotBalanceListEquals(List<HlSpotBalance> a, List<HlSpotBalance> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].coin != b[i].coin ||
        a[i].total != b[i].total ||
        a[i].hold != b[i].hold ||
        a[i].entryNtl != b[i].entryNtl) {
      return false;
    }
  }
  return true;
}

bool hlOpenOrderListEquals(List<HlOpenOrder> a, List<HlOpenOrder> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].oid != b[i].oid ||
        a[i].coin != b[i].coin ||
        a[i].sz != b[i].sz ||
        a[i].limitPx != b[i].limitPx ||
        a[i].isBuy != b[i].isBuy ||
        // A WS-only row carries placeholder metadata until REST fills it
        // in; the refresh must not be swallowed as "unchanged".
        a[i].orderType != b[i].orderType ||
        a[i].isTrigger != b[i].isTrigger ||
        a[i].triggerPx != b[i].triggerPx ||
        a[i].reduceOnly != b[i].reduceOnly ||
        a[i].tif != b[i].tif ||
        a[i].isPositionTpsl != b[i].isPositionTpsl) {
      return false;
    }
  }
  return true;
}

bool hlFillListEquals(List<HlFill> a, List<HlFill> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].oid != b[i].oid ||
        a[i].time != b[i].time ||
        a[i].coin != b[i].coin ||
        a[i].sz != b[i].sz ||
        a[i].px != b[i].px) {
      return false;
    }
  }
  return true;
}

bool hlAccountSnapshotEquals(HlAccountSnapshot a, HlAccountSnapshot b) =>
    a.accountValue == b.accountValue &&
    a.withdrawable == b.withdrawable &&
    a.totalMarginUsed == b.totalMarginUsed &&
    a.crossMaintenanceMarginUsed == b.crossMaintenanceMarginUsed &&
    hlPerpPositionListEquals(a.positions, b.positions) &&
    hlSpotBalanceListEquals(a.spotBalances, b.spotBalances) &&
    setEquals(a.activeDexes, b.activeDexes);

// ───────────────────────────── address ─────────────────────────────

/// The user's Hyperliquid account address — the SPENDING wallet's EOA at
/// m/44'/60'/0'/0/0, the exact same derivation Polymarket uses (see
/// polymarket_trading_provider.build). Derivation is READ-ONLY: the
/// private key is dropped on the floor here; anything that needs to sign
/// re-derives on demand inside the trading notifier.
///
/// Null when there's no hot wallet, the session isn't unlocked (passkey
/// wallets included), or the mnemonic can't be resolved. Recomputes on
/// wallet switch, on a new unlock, and once the lock overlay lifts after
/// a build behind it.
/// The spending wallet and its EVM format: what selects its EVM account.
(String?, EvmDerivationVersion?) _spendingEvmIdentity(Settings s) {
  final wallet = pickSpendingWallet(s);
  return (wallet?.id, wallet?.evmDerivationVersion);
}

final hyperliquidAddressProvider = FutureProvider<String?>((ref) async {
  // Scope rebuilds to the spending wallet identity + session, not
  // every settings write. The EVM format is part of that identity: a
  // recovered wallet's unlock-time format check can settle it.
  ref.watch(settingsProvider.select(_spendingEvmIdentity));
  ref.watch(sessionAuthProvider);

  final settings = ref.read(settingsProvider);
  final spending = pickSpendingWallet(settings);
  if (spending == null) return null;
  if (!watchSessionUnlock(ref)) return null;

  try {
    final mnemonic = await resolveBip39MnemonicFor(spending,
        access: SeedAccess.automatic, session: ref.read(seedSessionProvider));
    if (mnemonic == null) return null;
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);
    return wallet.address;
  } catch (_) {
    return null;
  }
});

// ───────────────────────── account snapshot ─────────────────────────

class HlAccountNotifier extends AutoDisposeAsyncNotifier<HlAccountSnapshot> {
  Timer? _timer;
  int _currentIntervalSecs = 15;
  bool _disposed = false;
  String? _address;

  @override
  Future<HlAccountSnapshot> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });

    // Placement activity drives the adaptive cadence: a new in-flight
    // order drops the poll to 5 s and forces an immediate tick so the
    // fresh position lands (and the placing tile reconciles) fast.
    // Registered before any await — ref.listen must run synchronously
    // within build.
    ref.listen(placingHyperliquidOrderProvider, (prev, next) {
      _applyCadence();
      if ((prev == null || prev.isEmpty) && next.isNotEmpty) {
        unawaited(_silentRefresh());
      }
    });

    final address = await ref.watch(hyperliquidAddressProvider.future);
    _address = address;
    if (address == null) return HlAccountSnapshot.empty;

    // Timer starts before the first fetch so a failed initial load
    // (error state) still self-heals on the next tick instead of
    // sticking until something re-watches the provider.
    _startTimer();
    final model = ref.read(hyperliquidTradingModelProvider);
    final snap = await model.getPortfolioSnapshot(address);
    _reconcilePlacements(snap);
    _publishPositions(snap);
    return snap;
  }

  int _targetIntervalSecs(HlAccountSnapshot? snap) {
    final placing = ref.read(placingHyperliquidOrderProvider).isNotEmpty;
    final hasPositions = (snap?.positions.isNotEmpty ?? false);
    return (placing || hasPositions) ? 5 : 15;
  }

  void _applyCadence() {
    if (_disposed) return;
    final target = _targetIntervalSecs(state.valueOrNull);
    if (target == _currentIntervalSecs && _timer != null) return;
    _currentIntervalSecs = target;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _currentIntervalSecs),
      (_) => _silentRefresh(),
    );
  }

  Future<void> _silentRefresh() async {
    if (_disposed) return;
    final address = _address;
    if (address == null) return;
    try {
      final model = ref.read(hyperliquidTradingModelProvider);
      final snap = await model.getPortfolioSnapshot(address);
      if (_disposed) return;
      _reconcilePlacements(snap);
      _publishPositions(snap);
      final current = state.valueOrNull;
      // Value-equality short-circuit: identical snapshots don't notify.
      if (current == null || !hlAccountSnapshotEquals(current, snap)) {
        state = AsyncData(snap);
      }
      _applyCadence();
    } catch (_) {
      // Silent — keep the last snapshot on a background refresh failure.
    }
  }

  /// Hands the fresh positions to the trade alerts (liquidation risk,
  /// funding), which run app-wide on the slower badge poll otherwise.
  void _publishPositions(HlAccountSnapshot snap) {
    try {
      final held = ref.read(hyperliquidHeldPositionsProvider.notifier);
      if (!hlPerpPositionListEquals(held.state, snap.positions)) {
        held.state = snap.positions;
      }
    } catch (_) {}
  }

  void _reconcilePlacements(HlAccountSnapshot snap) {
    try {
      ref
          .read(placingHyperliquidOrderProvider.notifier)
          .reconcileWithPositions(snap.positions);
    } catch (_) {
      // Reconcile is a UX nicety — never let it break the fetch path.
    }
  }

  /// One immediate refetch — called by the trading notifier after every
  /// exchange action and by the user-events provider on WS fills (which
  /// also `ref.invalidate`s; this method exists for callers that want to
  /// keep the notifier's timers intact).
  Future<void> refresh() => _silentRefresh();
}

/// Perp clearinghouse summary + open positions + spot balances, polled
/// adaptively (5 s active / 15 s idle — see file header).
final hyperliquidAccountProvider =
    AsyncNotifierProvider.autoDispose<HlAccountNotifier, HlAccountSnapshot>(
  HlAccountNotifier.new,
);

// ───────────────────────── derived views ─────────────────────────

/// Open perp positions (empty while loading / on error / flat account).
final hyperliquidPerpPositionsProvider =
    Provider.autoDispose<List<HlPerpPosition>>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.positions ??
      const [];
});

/// Perp USDC available for withdrawal / new margin, USD.
final hyperliquidWithdrawableProvider = Provider.autoDispose<double>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.withdrawable ?? 0;
});

/// Spot token balances (includes the USDC row).
final hyperliquidSpotBalancesProvider =
    Provider.autoDispose<List<HlSpotBalance>>((ref) {
  return ref.watch(hyperliquidAccountProvider).valueOrNull?.spotBalances ??
      const [];
});

// ───────────────────────── badge count ─────────────────────────

class HlOpenPositionsCountNotifier extends Notifier<int> {
  Timer? _timer;
  bool _fetching = false;
  String? _cachedAddress;

  @override
  int build() {
    // Rebuild (and reset the cached address) on wallet switch.
    ref.watch(settingsProvider.select(_spendingEvmIdentity));
    _cachedAddress = null;

    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
    return 0;
  }

  Future<void> _tick() async {
    if (_fetching) return;
    _fetching = true;
    try {
      // Yield one microtask first: build() kicks the initial _tick
      // synchronously, and writing `state` before build returns throws.
      await Future<void>.value();
      final settings = ref.read(settingsProvider);
      final spending = pickSpendingWallet(settings);
      if (spending == null) {
        state = 0;
        ref.read(hyperliquidFreeUsdcProvider.notifier).state = 0;
        ref.read(hyperliquidProvisionedProvider.notifier).state = false;
        ref.read(hyperliquidHeldPositionsProvider.notifier).state = const [];
        return;
      }

      // Once-flag gate: 'hl_enabled_<walletId>' is written by
      // provisionHyperliquidAccount the first time this wallet trades.
      // Until then every tick is this LOCAL read and nothing else — no
      // address derivation, no network. Re-checked each tick so a user
      // who enables trading mid-session starts counting within 60 s.
      final enabled = await HyperliquidOnboardingService.isEnabled(spending.id);
      if (!enabled) {
        state = 0;
        ref.read(hyperliquidFreeUsdcProvider.notifier).state = 0;
        ref.read(hyperliquidProvisionedProvider.notifier).state = false;
        ref.read(hyperliquidHeldPositionsProvider.notifier).state = const [];
        return;
      }
      ref.read(hyperliquidProvisionedProvider.notifier).state = true;

      final address =
          _cachedAddress ??= await ref.read(hyperliquidAddressProvider.future);
      if (address == null) return;

      final model = ref.read(hyperliquidTradingModelProvider);
      final snap = await model.getPortfolioSnapshot(address);
      final spotHoldings = snap.spotBalances
          .where((b) => b.coin != 'USDC' && b.total > 0)
          .length;
      final count = snap.positions.length + spotHoldings;
      if (count != state) state = count;
      final held = ref.read(hyperliquidHeldPositionsProvider.notifier);
      if (!hlPerpPositionListEquals(held.state, snap.positions)) {
        held.state = snap.positions;
      }

      // Piggyback the unified-USDC number on this same poll so the home
      // balance never spins up the full trading stack. Free cash only
      // (perp withdrawable + unheld spot USDC) — margin locked in open
      // positions is portfolio value, not spendable balance, matching
      // polymarketBalanceProvider's semantics.
      final spotUsdc = snap.spotBalances
          .where((b) => b.coin == 'USDC')
          .fold<double>(0, (sum, b) => sum + b.available);
      ref.read(hyperliquidFreeUsdcProvider.notifier).state =
          snap.withdrawable + spotUsdc;
    } catch (_) {
      // Keep the last-known count on transient failures.
    } finally {
      _fetching = false;
    }
  }
}

/// Open perp positions + non-USDC spot holdings, for the home pill's
/// Trading badge. NOT autoDispose — the pill watches it permanently —
/// and deliberately independent of [hyperliquidAccountProvider] so
/// mounting the pill never spins up the full trading stack: its own
/// 60 s poll only touches the network for wallets that have actually
/// provisioned Hyperliquid (see the once-flag gate in [_tick]).
final hyperliquidOpenPositionsCountProvider =
    NotifierProvider<HlOpenPositionsCountNotifier, int>(
  HlOpenPositionsCountNotifier.new,
);

/// Hyperliquid free USDC (perp withdrawable + unheld spot USDC) for the
/// unified `usdcBalanceProvider`. Written by [HlOpenPositionsCountNotifier]'s
/// 60 s tick — same once-flag gating, zero extra network. NOT autoDispose
/// for the same reason as the badge count: the home balance watches it
/// permanently. While a Hyperliquid surface is open the trading provider's
/// 5–15 s snapshot is fresher; this one is the always-on coarse number.
final hyperliquidFreeUsdcProvider = StateProvider<double>((_) => 0);

/// The spending wallet's open perp positions, from whichever poll ran
/// last: the 5 s account poll while an Investing surface is open, else the
/// 60 s badge poll. Read by the app-wide trade alerts (liquidation risk,
/// funding); NOT autoDispose, and empty for wallets that never traded.
final hyperliquidHeldPositionsProvider =
    StateProvider<List<HlPerpPosition>>((_) => const []);

/// The spending wallet has provisioned Hyperliquid (the badge poll's
/// once-flag gate). The trade alerts keep the user-events socket open
/// only while this is true.
final hyperliquidProvisionedProvider = StateProvider<bool>((_) => false);
