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

final portfolioPerformanceProvider = FutureProvider.autoDispose
    .family<PortfolioPerformance, PortfolioPerformanceRequest>(
        (ref, request) async {
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
      final account = await ref.watch(polymarketTradingProvider.selectAsync(
          (s) => (
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
  return request.venue == PortfolioPerformanceVenue.trading
      ? service.hyperliquid(address)
      : service.polymarket(address);
});

const kPortfolioPerformanceRefresh = Duration(minutes: 1);

String _holdings(Iterable<String> positions) =>
    (positions.toList()..sort()).join(',');
