import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/portfolio/portfolio_performance_service.dart';

export 'package:kute/models/portfolio_performance.dart';

final portfolioPerformanceServiceProvider =
    Provider.autoDispose<PortfolioPerformanceService>((ref) {
  final service = PortfolioPerformanceService();
  ref.onDispose(service.close);
  return service;
});

// Keep successfully read history when the Portfolio leaves the widget tree.
// The resolved venue account, rather than the currently selected wallet or
// a widget's lifetime, owns each snapshot. This memory contains display data
// only; orders never read it.
final _performanceSnapshotsProvider = Provider(
    (ref) => <(PortfolioPerformanceVenue, String), PortfolioPerformance>{});

final portfolioPerformanceProvider = FutureProvider.autoDispose
    .family<PortfolioPerformance, PortfolioPerformanceRequest>(
        (ref, request) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final service = ref.watch(portfolioPerformanceServiceProvider);
  // Read again every minute while the statistics are on screen: the
  // positions behind the current figures move with every prediction made,
  // sold or claimed, and the series gains a point each day. The screen
  // keeps the last figures up while it reloads.
  final refresh =
      Timer(kPortfolioPerformanceRefresh, () => ref.invalidateSelf());
  ref.onDispose(refresh.cancel);
  final walletId = request.walletId;
  String address;
  if (walletId != null) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null ||
        identity.walletId != walletId ||
        !identity.hasVerifiedEvm) {
      throw const PortfolioPerformanceUnavailable(
          'Verify this Ledger account to view performance');
    }
    if (request.venue == PortfolioPerformanceVenue.trading) {
      address = identity.evmAddress!;
    } else {
      final account = await ref.watch(ledgerPmAccountProvider(walletId).future);
      if (account.walletId != walletId ||
          account.eoa?.toLowerCase() != identity.evmAddress!.toLowerCase()) {
        throw const PortfolioPerformanceUnavailable(
            'Predictions account does not match this Ledger');
      }
      if (account.account?.kind == PolymarketAccountKind.none) {
        return const PortfolioPerformance(
            points: [],
            sourceLabel: 'Polymarket',
            basisLabel: 'Economic P&L',
            coverageLabel: 'No Predictions account');
      }
      final resolved = account.account;
      if (resolved?.address == null ||
          resolved!.kind == PolymarketAccountKind.uncertain) {
        throw const PortfolioPerformanceUnavailable(
            'Predictions account is unavailable');
      }
      address = resolved.address!;
    }
  } else {
    // This provider re-resolves when the spending identity/session changes.
    // Ledger requests never touch this branch or any hot account provider.
    final eoa = await ref.watch(hyperliquidAddressProvider.future);
    if (eoa == null || eoa.isEmpty) {
      throw const PortfolioPerformanceUnavailable(
          'Unlock your spending account to view performance');
    }
    if (request.venue == PortfolioPerformanceVenue.trading) {
      address = eoa;
    } else {
      // Only the account's addresses and the positions it holds: the
      // trading state re-emits on every poll, and re-reading the whole
      // history on each of those was the "keeps reloading" report. A
      // prediction made, sold or claimed changes the holdings and reads
      // the figures again at once.
      final account =
          await ref.watch(polymarketTradingProvider.selectAsync((s) => (
                wallet: s.walletAddress,
                proxy: s.proxyWalletAddress,
                holdings: _holdings(s.openPositions.map((p) =>
                    '${p.asset}:${p.size.toStringAsFixed(4)}:${p.redeemable}')),
              )));
      if (account.wallet?.toLowerCase() != eoa.toLowerCase() ||
          account.proxy == null ||
          account.proxy!.isEmpty) {
        throw const PortfolioPerformanceUnavailable(
            'Predictions account is unavailable');
      }
      address = account.proxy!;
    }
  }
  final snapshots = ref.read(_performanceSnapshotsProvider);
  final key = (request.venue, address.toLowerCase());
  final cached = snapshots[key];
  // A different account must never inherit the previous AsyncValue. A known
  // account keeps its last successful figures while the current request runs.
  ref.state = cached == null
      ? const AsyncLoading()
      : const AsyncLoading<PortfolioPerformance>()
          .copyWithPrevious(AsyncData(cached));
  try {
    final fresh = await (request.venue == PortfolioPerformanceVenue.trading
        ? service.hyperliquid(address)
        : service.polymarket(address));
    if (!disposed) {
      snapshots[key] = fresh;
      ref.read(_performancePublicationProvider(request).notifier).state =
          _PerformancePublication(address, fresh);
    }
    return fresh;
  } catch (_) {
    if (cached != null) {
      if (!disposed) {
        ref.read(_performancePublicationProvider(request).notifier).state =
            _PerformancePublication(address, cached);
      }
      return cached;
    }
    rethrow;
  }
});

class _PerformancePublication {
  const _PerformancePublication(this.address, this.value);
  final String address;
  final PortfolioPerformance value;
}

// This survives the screen/provider unmount alongside the account cache.
// An overridden FutureProvider has no publication and can remain a simple
// display fixture without opening real account/signing providers.
final _performancePublicationProvider =
    StateProvider.family<_PerformancePublication?, PortfolioPerformanceRequest>(
        (ref, request) => null);

/// The FutureProvider deliberately keeps its previous AsyncValue on reload.
/// That is useful for a same-account refresh but unsafe during a wallet switch:
/// the next address may take time to resolve. Only the display layer masks the
/// previous account; the public .future/override API stays unchanged.
final portfolioPerformanceDisplayProvider = Provider.autoDispose
    .family<AsyncValue<PortfolioPerformance>, PortfolioPerformanceRequest>(
        (ref, request) {
  final history = ref.watch(portfolioPerformanceProvider(request));
  final publication = ref.watch(_performancePublicationProvider(request));
  if (publication == null) return history;

  bool sameAddress(String? value, String expected) =>
      value?.toLowerCase() == expected.toLowerCase();
  final walletId = request.walletId;
  String displayAddress;
  if (walletId == null) {
    final address = ref.watch(hyperliquidAddressProvider);
    if (address.isLoading || address.hasError || address.valueOrNull == null) {
      return const AsyncLoading();
    }
    if (request.venue == PortfolioPerformanceVenue.trading) {
      displayAddress = address.requireValue!;
    } else {
      final account = ref.watch(polymarketTradingProvider.select((value) => (
            loading: value.isLoading,
            error: value.hasError,
            eoa: value.valueOrNull?.walletAddress,
            proxy: value.valueOrNull?.proxyWalletAddress,
          )));
      if (account.loading ||
          account.error ||
          !sameAddress(account.eoa, address.requireValue!) ||
          account.proxy == null ||
          account.proxy!.isEmpty) {
        return const AsyncLoading();
      }
      displayAddress = account.proxy!;
    }
  } else {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null ||
        identity.walletId != walletId ||
        !identity.hasVerifiedEvm) {
      return const AsyncLoading();
    }
    if (request.venue == PortfolioPerformanceVenue.trading) {
      displayAddress = identity.evmAddress!;
    } else {
      final account = ref.watch(ledgerPmAccountProvider(walletId));
      final value = account.valueOrNull;
      if (account.isLoading ||
          account.hasError ||
          value?.walletId != walletId ||
          !sameAddress(value?.eoa, identity.evmAddress!) ||
          value?.account?.address == null ||
          value?.account?.kind == PolymarketAccountKind.uncertain) {
        return const AsyncLoading();
      }
      displayAddress = value!.account!.address!;
    }
  }
  // Publication precedes the FutureProvider's completion by one microtask.
  // Do not expose the old account's value in that handoff window.
  if (!sameAddress(displayAddress, publication.address) ||
      (history.hasValue &&
          !identical(history.valueOrNull, publication.value))) {
    final cached = ref.read(_performanceSnapshotsProvider)[(
      request.venue,
      displayAddress.toLowerCase()
    )];
    return cached == null
        ? const AsyncLoading()
        : const AsyncLoading<PortfolioPerformance>()
            .copyWithPrevious(AsyncData(cached));
  }
  return history;
});

const kPortfolioPerformanceRefresh = Duration(minutes: 1);

String _holdings(Iterable<String> positions) =>
    (positions.toList()..sort()).join(',');
