// lib/providers/polymarket_combos_provider.dart
//
// Polymarket Combos (parlays) for the hot Predictions account: the held
// combos and their activity, and the three money actions: place a combo
// (BUY RFQ), close it early (SELL RFQ) and claim a settled one (Router
// redeem). Ledger never comes here: a hardware review cannot fit inside
// the few-second quote window, so Ledger keeps placing legs separately.
//
// Money safety:
//   * every quote is checked against the request before signing
//     (combo_order.dart) and the order trades only the combo the legs
//     derive to;
//   * the step-up grant binds the legs, the most the combo may cost and
//     the least it must pay (PmGrants.comboBet / comboClose); a re-quote
//     that is worse needs a new review;
//   * an acceptance with an unknown outcome is journaled (rfq id) and
//     polled before another combo can be placed from the same wallet.
//
// Gates: placing follows `polymarket.trade` (plus each leg's category
// gate), closing and claiming follow `polymarket.close`, exactly like
// single bets. Polymarket's own geoblock answers 403.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart' show appL10n;
import 'package:kute/providers/auth_provider.dart'
    show sessionUnlockedProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show transactionNotifierProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/haptic_gates.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/polymarket/combos/combo_analytics.dart';
import 'package:kute/services/polymarket/combos/combo_feed.dart';
import 'package:kute/services/polymarket/combos/combo_ids.dart';
import 'package:kute/services/polymarket/combos/combo_math.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_service.dart';
import 'package:kute/services/polymarket_backend_service.dart'
    show GeoBlockException;
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Another combo from this wallet has not settled yet; nothing new is sent
/// until its outcome is known.
class ComboStillSettling implements Exception {
  const ComboStillSettling();
  @override
  String toString() => 'An earlier combo is still settling.';
}

/// The makers sent no usable quote (NO_QUOTES, size too large, ...).
class ComboNoQuoteException implements Exception {
  const ComboNoQuoteException(this.code);
  final String code;
  @override
  String toString() => 'No combo quote: $code';
}

/// The combo the user approved is no longer on offer at the approved terms
/// (the fresh quote costs more or pays less): review again.
class ComboQuoteChanged implements Exception {
  const ComboQuoteChanged(this.quote);
  final ComboQuote quote;
  @override
  String toString() => 'The combo quote changed.';
}

class ComboActionResult {
  const ComboActionResult(this.state, this.quote, {this.errorCode});
  final ComboFillState state;
  final ComboQuote quote;
  final String? errorCode;
}

@immutable
class PolymarketCombosState {
  const PolymarketCombosState({
    this.positions = const [],
    this.activity = const [],
    this.claiming = const {},
    this.pendingRfqs = 0,
    this.loaded = false,
  });

  /// Held YES combos (open, claimable and lost-but-held).
  final List<ComboPosition> positions;
  final List<ComboActivity> activity;

  /// Combo condition ids whose claim was sent and is not indexed yet.
  final Set<String> claiming;

  /// Accepted combos whose outcome is still unknown.
  final int pendingRfqs;
  final bool loaded;

  List<ComboPosition> get open =>
      positions.where((p) => p.isOpen && p.shares > 0).toList();

  /// Settled winners (or voided) with a payout to claim.
  List<ComboPosition> get claimable => positions
      .where((p) =>
          p.redeemable &&
          p.shares > 0 &&
          (p.settledPayoutUsd ?? 0) > 0 &&
          !claiming.contains(p.conditionId))
      .toList();

  /// ESTIMATED value of open combos plus the exact payout of claimable
  /// ones, for the Predictions total. Lost combos count zero.
  double get valueUsd {
    var v = 0.0;
    for (final p in positions) {
      if (p.shares <= 0 || claiming.contains(p.conditionId)) continue;
      if (p.isOpen) {
        v += p.estimatedValueUsd;
      } else if (p.redeemable) {
        v += p.settledPayoutUsd ?? 0;
      }
    }
    return v;
  }

  PolymarketCombosState copyWith({
    List<ComboPosition>? positions,
    List<ComboActivity>? activity,
    Set<String>? claiming,
    int? pendingRfqs,
    bool? loaded,
  }) =>
      PolymarketCombosState(
        positions: positions ?? this.positions,
        activity: activity ?? this.activity,
        claiming: claiming ?? this.claiming,
        pendingRfqs: pendingRfqs ?? this.pendingRfqs,
        loaded: loaded ?? this.loaded,
      );
}

final polymarketComboServiceProvider =
    Provider<PolymarketComboService>((ref) => PolymarketComboService());

final polymarketCombosProvider = AsyncNotifierProvider.autoDispose<
    PolymarketCombosNotifier, PolymarketCombosState>(
  PolymarketCombosNotifier.new,
);

/// The combos part of the Predictions total (estimate for open combos).
final polymarketCombosValueProvider = Provider.autoDispose<double>((ref) =>
    ref.watch(polymarketCombosProvider).valueOrNull?.valueUsd ?? 0);

class PolymarketCombosNotifier
    extends AutoDisposeAsyncNotifier<PolymarketCombosState> {
  static const _pendingBox = 'polymarket_combo_pending';
  static const _refreshEvery = Duration(seconds: 20);

  Timer? _timer;
  String? _wallet;
  PolymarketComboAccount? _account;
  bool _refreshing = false;
  bool _autoClaiming = false;
  final Map<String, DateTime> _claimNext = {};
  final Map<String, Duration> _claimBackoff = {};

  /// Acceptances this notifier is still waiting on itself; the journal
  /// poller leaves them alone so an outcome is reported once.
  final Set<String> _inFlightRfqs = {};

  PolymarketComboService get _service =>
      ref.read(polymarketComboServiceProvider);

  @override
  Future<PolymarketCombosState> build() async {
    ref.keepAlive();
    ref.onDispose(() => _timer?.cancel());
    final wallet = ref.watch(polymarketTradingProvider
        .select((s) => s.valueOrNull?.proxyWalletAddress));
    _timer?.cancel();
    _account = null;
    _wallet = wallet;
    if (wallet == null || wallet.isEmpty) {
      return const PolymarketCombosState(loaded: true);
    }
    _timer = Timer.periodic(_refreshEvery, (_) => unawaited(refresh()));
    final data = await _load(wallet, previous: null);
    Future<void>(() => _afterRefresh());
    return data;
  }

  Future<PolymarketCombosState> _load(String wallet,
      {PolymarketCombosState? previous}) async {
    final results = await Future.wait([
      _service.fetchPositions(wallet).then<Object?>((v) => v).catchError(
          (Object _) => previous?.positions),
      _service.fetchActivity(wallet).then<Object?>((v) => v).catchError(
          (Object _) => previous?.activity),
      _pendingFor(wallet).then<Object?>((v) => v.length),
    ]);
    final positions = results[0] as List<ComboPosition>? ?? const [];
    final activity = results[1] as List<ComboActivity>? ?? const [];
    unawaited(_syncFeed(wallet, positions, activity));
    // A claim stays "claiming" until the index drops the payout.
    final claiming = {
      for (final id in previous?.claiming ?? const <String>{})
        if (positions.any((p) => p.conditionId == id && p.redeemable)) id
    };
    return PolymarketCombosState(
      positions: positions,
      activity: activity,
      claiming: claiming,
      pendingRfqs: results[2] as int,
      loaded: true,
    );
  }

  /// Keeps the exact combo rows of the Activity feed (combo_feed.dart).
  Future<void> _syncFeed(String wallet, List<ComboPosition> positions,
      List<ComboActivity> activity) async {
    try {
      await ComboActivityFeed.sync(
        wallet: wallet,
        positions: positions,
        activity: activity,
        label: (n) => appL10n().comboLegsLabel(n),
      );
      _pushFeed(wallet);
    } catch (_) {}
  }

  void _pushFeed(String wallet) {
    unawaited(ComboActivityFeed.rowsFor(wallet).then((rows) {
      if (_wallet != wallet) return;
      try {
        ref
            .read(transactionNotifierProvider.notifier)
            .refreshComboActivity(rows);
      } catch (_) {}
    }));
  }

  /// Re-reads the held combos. Silent on failure (keeps the last state).
  Future<void> refresh() async {
    final wallet = _wallet;
    if (wallet == null || _refreshing) return;
    _refreshing = true;
    try {
      final previous = state.valueOrNull;
      final next = await _load(wallet, previous: previous);
      if (_wallet != wallet) return;
      state = AsyncData(next);
      _buzzResolvedLegs(previous, next);
      await _afterRefresh();
    } catch (_) {
      // The next tick retries.
    } finally {
      _refreshing = false;
    }
  }

  /// A leg that was open on the last read and is settled on this one:
  /// one light success for a win, one soft tap for a loss, once per
  /// refresh. The first load has nothing to compare and stays quiet.
  void _buzzResolvedLegs(
      PolymarketCombosState? previous, PolymarketCombosState next) {
    if (previous == null || !previous.loaded) return;
    final change = comboLegChange(
      previousOpen: {
        for (final p in previous.positions)
          for (final l in p.legs) '${p.conditionId}:${l.index}': l.isOpen,
      },
      next: [
        for (final p in next.positions)
          for (final l in p.legs)
            (
              key: '${p.conditionId}:${l.index}',
              won: l.outcome == ComboLegOutcome.won,
              lost: l.outcome == ComboLegOutcome.lost,
            ),
      ],
    );
    if (change == null) return;
    KuteHaptics.play(change == ComboLegChange.won
        ? KuteHaptic.legWon
        : KuteHaptic.legLost);
  }

  Future<void> _afterRefresh() async {
    await _resolvePending();
    await _maybeAutoClaim();
  }

  // ── Account ───────────────────────────────────────────────────────

  Future<PolymarketComboAccount> _accountFor({bool refresh = false}) async {
    final cached = _account;
    if (!refresh && cached != null && cached.isCurrent) return cached;
    final account = await ref
        .read(polymarketTradingProvider.notifier)
        .comboAccount(refreshCredentials: refresh);
    _account = account;
    return account;
  }

  /// Runs [op] with the account, re-deriving the CLOB credentials once
  /// after a 401. A 403 "restricted" is Polymarket's geoblock.
  Future<T> _withAccount<T>(
      Future<T> Function(PolymarketComboAccount account) op) async {
    var account = await _accountFor();
    try {
      return await op(account);
    } on ComboRfqException catch (e) {
      if (e.isRegionBlocked) throw GeoBlockException();
      if (!e.isUnauthenticated) rethrow;
      account = await _accountFor(refresh: true);
      try {
        return await op(account);
      } on ComboRfqException catch (e2) {
        if (e2.isRegionBlocked) throw GeoBlockException();
        rethrow;
      }
    }
  }

  // ── Quotes ────────────────────────────────────────────────────────

  /// A BUY quote for [legPositionIds] with a [budgetE6] pUSD budget (fees
  /// included). Throws [ComboNoQuoteException] when no maker quoted.
  Future<ComboQuote> quoteBuy({
    required List<String> legPositionIds,
    required BigInt budgetE6,
  }) =>
      _quote(
          legPositionIds: legPositionIds,
          direction: ComboDirection.buy,
          sizeE6: budgetE6);

  /// A SELL quote for every share of [position] the wallet holds on chain.
  Future<ComboQuote> quoteClose(ComboPosition position) async {
    final account = await _accountFor();
    final shares = await PolymarketOnboardingService()
        .readComboBalanceOrThrow(
            owner: account.depositWallet, positionId: position.positionId);
    if (shares <= BigInt.zero) {
      throw const ComboNoQuoteException('NO_BALANCE');
    }
    return _quote(
      legPositionIds: [for (final l in position.legs) l.positionId],
      direction: ComboDirection.sell,
      sizeE6: shares,
    );
  }

  Future<ComboQuote> _quote({
    required List<String> legPositionIds,
    required ComboDirection direction,
    required BigInt sizeE6,
  }) =>
      _withAccount((account) async {
        account.ensureCurrent();
        final r = await _service.requestQuote(
          transport: account.transport,
          depositWallet: account.depositWallet,
          legPositionIds: legPositionIds,
          direction: direction,
          sizeE6: sizeE6,
        );
        return switch (r) {
          ComboQuoted(:final quote) => quote,
          ComboNoQuote(:final code) => throw ComboNoQuoteException(code),
        };
      });

  // ── Place ─────────────────────────────────────────────────────────

  /// Places one combo bet for the [shown] quote the user approved with
  /// [grant] (a [PmGrants.comboBet] review). Sets the combo approvals the
  /// first time, re-quotes when the window is (nearly) gone, and only
  /// signs a quote the grant still covers.
  Future<ComboActionResult> place({
    required ComboQuote shown,
    required AuthGrant grant,
    required List<String> capabilities,
    String? entrySource,
  }) async {
    final legs = shown.legPositionIds.length;
    var stage = 'policy';
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllAllowed(capabilities, maxAge: const Duration(seconds: 60));
      final result = await _withAccount((account) async {
        account.ensureCurrent();
        if ((await _pendingFor(account.depositWallet)).isNotEmpty) {
          throw const ComboStillSettling();
        }
        stage = 'approvals';
        final approved = await PolymarketOnboardingService()
            .ensureComboApprovals(
          eoaAddress: account.eoaAddress,
          privateKey: account.batchSigningKey,
          walletAddress: account.depositWallet,
          ensureCurrent: account.ensureCurrent,
        );
        stage = 'quote';
        var quote = shown;
        if (approved ||
            quote.remaining(DateTime.now()) < const Duration(seconds: 2)) {
          final r = await _service.requestQuote(
            transport: account.transport,
            depositWallet: account.depositWallet,
            legPositionIds: shown.legPositionIds,
            direction: ComboDirection.buy,
            sizeE6: shown.requestedE6,
          );
          quote = switch (r) {
            ComboQuoted(:final quote) => quote,
            ComboNoQuote(:final code) => throw ComboNoQuoteException(code),
          };
        }
        stage = 'sign';
        try {
          GrantGuard.consume(
            grant,
            PmGrants.comboBet(
              walletId: account.walletId,
              legPositionIds: quote.legPositionIds,
              maxStakeE6: quote.totalRequiredE6,
              minPayoutE6: quote.payoutE6,
            ),
            allowed: PmGrants.betActions,
          );
        } on ReauthRequired {
          throw ComboQuoteChanged(quote);
        }
        stage = 'accept';
        final outcome = await _service.acceptQuote(
          account: account,
          quote: quote,
          beforeAccept: () => _journal(account.depositWallet, quote),
        );
        return ComboActionResult(outcome.state, quote,
            errorCode: outcome.errorCode);
      });
      await _settleJournal(result);
      if (result.state == ComboFillState.filled) {
        final q = result.quote;
        ComboAnalytics.placed(
          legs: legs,
          stakeUsd: q.stakeUsd,
          payoutUsd: q.payoutUsd,
          multiplier: q.multiplier,
          feeUsd: q.feesUsd,
          route: _account?.transport.route ?? 'requester',
          entrySource: entrySource,
        );
        TrackingService.refreshLifetimeProps(
          isFunded: true,
          lifetimeBetCount: TrackingService.bumpBetCount(),
          primaryRail: 'predictions',
        );
      } else if (result.state == ComboFillState.failed) {
        ComboAnalytics.failed(
          action: 'place',
          stage: 'execution',
          errorCategory: 'quote_rejected',
          legs: legs,
          amountUsd: result.quote.stakeUsd,
          reasonCode: result.errorCode,
        );
      }
      _afterMoneyMoved();
      return result;
    } catch (e) {
      await _dropRejectedAcceptance(e);
      if (e is! AuthGrantException && e is! ComboQuoteChanged) {
        ComboAnalytics.failed(
          action: 'place',
          stage: stage,
          errorCategory: _category(e),
          legs: legs,
          amountUsd: shown.stakeUsd,
          reasonCode: _code(e),
        );
      }
      rethrow;
    }
  }

  // ── Close early ───────────────────────────────────────────────────

  /// Sells the whole combo for the [shown] SELL quote approved with
  /// [grant] (a [PmGrants.comboClose] review).
  Future<ComboActionResult> close({
    required ComboPosition position,
    required ComboQuote shown,
    required AuthGrant grant,
  }) async {
    final legs = position.legsTotal;
    var stage = 'policy';
    try {
      await RuntimeCapabilitiesService.instance.ensureAllowed(
          'polymarket.close',
          maxAge: const Duration(seconds: 60));
      final result = await _withAccount((account) async {
        account.ensureCurrent();
        if ((await _pendingFor(account.depositWallet)).isNotEmpty) {
          throw const ComboStillSettling();
        }
        stage = 'approvals';
        final approved = await PolymarketOnboardingService()
            .ensureComboApprovals(
          eoaAddress: account.eoaAddress,
          privateKey: account.batchSigningKey,
          walletAddress: account.depositWallet,
          ensureCurrent: account.ensureCurrent,
        );
        stage = 'quote';
        var quote = shown;
        if (approved ||
            quote.remaining(DateTime.now()) < const Duration(seconds: 2)) {
          final r = await _service.requestQuote(
            transport: account.transport,
            depositWallet: account.depositWallet,
            legPositionIds: shown.legPositionIds,
            direction: ComboDirection.sell,
            sizeE6: shown.requestedE6,
          );
          quote = switch (r) {
            ComboQuoted(:final quote) => quote,
            ComboNoQuote(:final code) => throw ComboNoQuoteException(code),
          };
        }
        stage = 'sign';
        try {
          GrantGuard.consume(
            grant,
            PmGrants.comboClose(
              walletId: account.walletId,
              positionId: quote.yesPositionId,
              sharesE6: quote.makerAmountE6,
              minProceedsE6: quote.netReceiveE6,
            ),
            allowed: PmGrants.sellActions,
          );
        } on ReauthRequired {
          throw ComboQuoteChanged(quote);
        }
        stage = 'accept';
        final outcome = await _service.acceptQuote(
          account: account,
          quote: quote,
          beforeAccept: () => _journal(account.depositWallet, quote),
        );
        return ComboActionResult(outcome.state, quote,
            errorCode: outcome.errorCode);
      });
      await _settleJournal(result);
      if (result.state == ComboFillState.filled) {
        final wallet = _wallet;
        if (wallet != null) {
          await ComboActivityFeed.recordClose(
            wallet: wallet,
            position: position,
            proceedsUsd: result.quote.proceedsUsd,
            shares: result.quote.sharesUsd,
            label: appL10n().comboLegsLabel(position.legsTotal),
          );
          _pushFeed(wallet);
        }
        ComboAnalytics.closed(
          legs: legs,
          proceedsUsd: result.quote.proceedsUsd,
          shares: result.quote.sharesUsd,
          feeUsd: result.quote.feesUsd,
          route: _account?.transport.route ?? 'requester',
        );
      } else if (result.state == ComboFillState.failed) {
        ComboAnalytics.failed(
          action: 'close',
          stage: 'execution',
          errorCategory: 'quote_rejected',
          legs: legs,
          amountUsd: result.quote.proceedsUsd,
          reasonCode: result.errorCode,
        );
      }
      _afterMoneyMoved();
      return result;
    } catch (e) {
      await _dropRejectedAcceptance(e);
      if (e is! AuthGrantException && e is! ComboQuoteChanged) {
        ComboAnalytics.failed(
          action: 'close',
          stage: stage,
          errorCategory: _category(e),
          legs: legs,
          amountUsd: shown.proceedsUsd,
          reasonCode: _code(e),
        );
      }
      rethrow;
    }
  }

  // ── Claim ─────────────────────────────────────────────────────────

  /// Redeems a settled combo through the Router (one gasless batch).
  /// Returns the exact payout in USD. [trigger]: manual | auto.
  Future<double> claim(ComboPosition position,
      {String trigger = 'manual'}) async {
    final id = position.conditionId;
    final current = state.valueOrNull;
    if (current != null && current.claiming.contains(id)) {
      throw const ComboStillSettling();
    }
    try {
      await RuntimeCapabilitiesService.instance.ensureAllowed(
          'polymarket.close',
          maxAge: const Duration(seconds: 60));
      final payout = await _withAccount((account) async {
        account.ensureCurrent();
        final onboarding = PolymarketOnboardingService();
        await onboarding.ensureComboApprovals(
          eoaAddress: account.eoaAddress,
          privateKey: account.batchSigningKey,
          walletAddress: account.depositWallet,
          ensureCurrent: account.ensureCurrent,
        );
        final shares = await onboarding.readComboBalanceOrThrow(
            owner: account.depositWallet, positionId: position.positionId);
        if (shares <= BigInt.zero) {
          throw const ComboNoQuoteException('NO_BALANCE');
        }
        final split = ComboIds.split(position.positionId);
        await onboarding.redeemComboPosition(
          eoaAddress: account.eoaAddress,
          privateKey: account.batchSigningKey,
          walletAddress: account.depositWallet,
          conditionId: split.conditionId,
          outcomeIndex: split.outcomeIndex,
          amount: shares,
          ensureCurrent: account.ensureCurrent,
        );
        final factor =
            comboSettlementFactor([for (final l in position.legs) l.mark]) ??
                0;
        return (
          payout: e6ToDouble(comboPayoutE6(sharesE6: shares, factor: factor)),
          shares: e6ToDouble(shares),
        );
      });
      final s = state.valueOrNull;
      if (s != null) {
        state = AsyncData(s.copyWith(claiming: {...s.claiming, id}));
      }
      ComboAnalytics.claimed(
        legs: position.legsTotal,
        payoutUsd: payout.payout,
        shares: payout.shares,
        trigger: trigger,
      );
      _afterMoneyMoved();
      return payout.payout;
    } catch (e) {
      if (trigger == 'manual' || !_claimBackoff.containsKey(id)) {
        ComboAnalytics.failed(
          action: 'claim',
          stage: 'claim',
          errorCategory: _category(e),
          legs: position.legsTotal,
          amountUsd: position.settledPayoutUsd,
          reasonCode: _code(e),
        );
      }
      rethrow;
    }
  }

  /// Claims settled winning combos on their own, like single bets
  /// (ClaimAutoFire): one per refresh, unlocked session only, retrying
  /// with a doubling backoff while the payout is not open on chain.
  Future<void> _maybeAutoClaim() async {
    if (_autoClaiming) return;
    final s = state.valueOrNull;
    if (s == null || s.claimable.isEmpty) return;
    if (pickSpendingWallet(ref.read(settingsProvider)) == null) return;
    if (!ref.read(sessionUnlockedProvider)) return;
    final now = DateTime.now();
    for (final p in s.claimable) {
      final next = _claimNext[p.conditionId];
      if (next != null && now.isBefore(next)) continue;
      _autoClaiming = true;
      try {
        await claim(p, trigger: 'auto');
        _claimNext.remove(p.conditionId);
        _claimBackoff.remove(p.conditionId);
      } catch (_) {
        final cur = _claimBackoff[p.conditionId] ?? const Duration(minutes: 2);
        _claimNext[p.conditionId] = DateTime.now().add(cur);
        final doubled = cur * 2;
        _claimBackoff[p.conditionId] = doubled > const Duration(minutes: 30)
            ? const Duration(minutes: 30)
            : doubled;
      } finally {
        _autoClaiming = false;
      }
      break;
    }
  }

  // ── Unknown outcomes ──────────────────────────────────────────────

  Future<Box<String>> _box() => Hive.openBox<String>(_pendingBox);

  /// Written right before the accept POST: from here the outcome is the
  /// gateway's, and only the rfq id can recover it.
  Future<void> _journal(String wallet, ComboQuote q) async {
    _inFlightRfqs.add(q.rfqId);
    try {
      final box = await _box();
      await box.put(
          '${wallet.toLowerCase()}:${q.rfqId}',
          jsonEncode({
            'v': 1,
            'rfqId': q.rfqId,
            'direction': q.direction.wire,
            'legs': q.legPositionIds.length,
            'amountE6': (q.isBuy ? q.totalRequiredE6 : q.netReceiveE6)
                .toString(),
            'payoutE6': q.payoutE6.toString(),
            'at': DateTime.now().millisecondsSinceEpoch,
          }));
      await box.flush();
    } catch (_) {}
  }

  Future<void> _settleJournal(ComboActionResult r) async {
    _inFlightRfqs.remove(r.quote.rfqId);
    if (r.state == ComboFillState.pending) return;
    try {
      final box = await _box();
      final keys =
          box.keys.where((k) => k.toString().endsWith(':${r.quote.rfqId}'));
      await box.deleteAll(keys.toList());
    } catch (_) {}
  }

  /// A 4xx answer to the accept POST means the gateway did not take the
  /// acceptance (expired window, quote mismatch, bad signature): nothing
  /// can fill, so its journal row goes. A transport failure keeps it.
  Future<void> _dropRejectedAcceptance(Object e) async {
    if (e is! ComboRfqException || e.httpStatus < 400 || e.httpStatus > 499) {
      return;
    }
    final ids = {..._inFlightRfqs};
    _inFlightRfqs.clear();
    if (ids.isEmpty) return;
    try {
      final box = await _box();
      await box.deleteAll(box.keys
          .where((k) => ids.any((id) => k.toString().endsWith(':$id')))
          .toList());
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _pendingFor(String wallet) async {
    try {
      final box = await _box();
      final prefix = '${wallet.toLowerCase()}:';
      return [
        for (final k in box.keys)
          if (k.toString().startsWith(prefix))
            {
              ...(jsonDecode(box.get(k) ?? '{}') as Map<String, dynamic>),
              '_key': k.toString(),
            }
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Polls journaled acceptances; a terminal answer settles them and
  /// reports the outcome once.
  Future<void> _resolvePending() async {
    final wallet = _wallet;
    if (wallet == null) return;
    final pending = await _pendingFor(wallet);
    if (pending.isEmpty) return;
    if (!ref.read(sessionUnlockedProvider)) return;
    PolymarketComboAccount account;
    try {
      account = await _accountFor();
    } catch (_) {
      return;
    }
    final box = await _box();
    var changed = false;
    for (final row in pending) {
      final rfqId = row['rfqId'] as String?;
      if (rfqId != null && _inFlightRfqs.contains(rfqId)) continue;
      if (rfqId == null) {
        await box.delete(row['_key']);
        changed = true;
        continue;
      }
      ComboRfqStatus status;
      try {
        status = await _service.status(account.transport, rfqId);
      } on ComboRfqException catch (e) {
        // Unknown to the gateway (404), or never accepted (409 status
        // read before acceptance) long after its window: no fill.
        final at = row['at'] is int ? row['at'] as int : 0;
        final stale = DateTime.now().millisecondsSinceEpoch - at >
            const Duration(minutes: 10).inMilliseconds;
        if (e.httpStatus != 404 && !(e.httpStatus == 409 && stale)) continue;
        status = ComboRfqStatus(rfqId: rfqId, status: 'FAILED');
      } catch (_) {
        continue;
      }
      if (!status.isTerminal) continue;
      await box.delete(row['_key']);
      changed = true;
      final isBuy = row['direction'] == 'BUY';
      final amount =
          e6ToDouble(BigInt.tryParse('${row['amountE6']}') ?? BigInt.zero);
      final payout =
          e6ToDouble(BigInt.tryParse('${row['payoutE6']}') ?? BigInt.zero);
      final legs = row['legs'] is int ? row['legs'] as int : 0;
      if (status.isFilled) {
        if (isBuy) {
          ComboAnalytics.placed(
            legs: legs,
            stakeUsd: amount,
            payoutUsd: payout,
            multiplier: amount > 0 ? payout / amount : 0,
            feeUsd: 0,
            route: account.transport.route,
          );
        } else {
          ComboAnalytics.closed(
            legs: legs,
            proceedsUsd: amount,
            shares: 0,
            feeUsd: 0,
            route: account.transport.route,
          );
        }
      } else {
        ComboAnalytics.failed(
          action: isBuy ? 'place' : 'close',
          stage: 'execution',
          errorCategory: 'quote_rejected',
          legs: legs,
          amountUsd: amount,
          reasonCode: status.errorCode ?? status.status,
        );
      }
    }
    if (changed) _afterMoneyMoved();
  }

  void _afterMoneyMoved() {
    try {
      unawaited(ref.read(polymarketTradingProvider.notifier).refresh());
    } catch (_) {}
    for (final d in const [2, 6, 15]) {
      Future<void>.delayed(Duration(seconds: d), () => unawaited(refresh()));
    }
  }

  static String _category(Object e) => switch (e) {
        ComboNoQuoteException() => 'no_route',
        ComboStillSettling() => 'settlement',
        ComboQuoteChanged() => 'quote_rejected',
        GeoBlockException() => 'unknown',
        ComboRfqException(:final isRateLimited) when isRateLimited =>
          'rate_limited',
        ComboRfqException(:final isExpired) when isExpired => 'expired',
        _ => TrackingService.errorCategory(e),
      };

  static String? _code(Object e) => switch (e) {
        ComboNoQuoteException(:final code) => code,
        ComboRfqException(:final code) => code,
        GeoBlockException() => 'region_unavailable',
        ComboStillSettling() => 'still_settling',
        _ => null,
      };
}
