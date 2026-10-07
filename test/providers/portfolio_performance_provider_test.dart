import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/portfolio/portfolio_performance_service.dart';

const ledger = '0x1111111111111111111111111111111111111111';
const proxy = '0x2222222222222222222222222222222222222222';
const spending = '0x3333333333333333333333333333333333333333';
const empty = PortfolioPerformance(
    points: [],
    sourceLabel: 'Test',
    basisLabel: 'PnL',
    coverageLabel: 'All time');

class _Service extends PortfolioPerformanceService {
  final requests = <String>[];
  @override
  Future<PortfolioPerformance> hyperliquid(String address) async {
    requests.add('hl:$address');
    return empty;
  }

  @override
  Future<PortfolioPerformance> polymarket(String address) async {
    requests.add('pm:$address');
    return empty;
  }
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.eoa);
  final String eoa;
  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(walletAddress: eoa, proxyWalletAddress: proxy);
}

void main() {
  for (final venue in PortfolioPerformanceVenue.values) {
    test('Ledger $venue never reads the spending address', () async {
      final service = _Service();
      final scope = ProviderContainer(overrides: [
        portfolioPerformanceServiceProvider.overrideWithValue(service),
        hyperliquidAddressProvider
            .overrideWith((_) => throw StateError('Hot provider accessed')),
        ledgerIdentityProvider('ledger').overrideWith((_) =>
            const LedgerIdentity(
                walletId: 'ledger', evmAddress: ledger, evmVerifiedAtMs: 1)),
        ledgerPmAccountProvider('ledger').overrideWith((_) async =>
            const LedgerPmAccount(
                walletId: 'ledger',
                eoa: ledger,
                account: PolymarketLedgerAccount.legacySafe(proxy))),
      ]);
      addTearDown(scope.dispose);
      addTearDown(service.close);
      await scope.read(portfolioPerformanceProvider(
              PortfolioPerformanceRequest(venue: venue, walletId: 'ledger'))
          .future);
      expect(service.requests, [
        venue == PortfolioPerformanceVenue.trading ? 'hl:$ledger' : 'pm:$proxy'
      ]);
    });
  }

  test('unverified or missing Ledger identity never falls back to hot',
      () async {
    final service = _Service();
    final scope = ProviderContainer(overrides: [
      portfolioPerformanceServiceProvider.overrideWithValue(service),
      ledgerIdentityProvider('missing').overrideWith((_) => null),
      hyperliquidAddressProvider.overrideWith((_) async => spending),
    ]);
    addTearDown(scope.dispose);
    addTearDown(service.close);
    await expectLater(
        scope.read(portfolioPerformanceProvider(
                const PortfolioPerformanceRequest(
                    venue: PortfolioPerformanceVenue.trading,
                    walletId: 'missing'))
            .future),
        throwsA(isA<PortfolioPerformanceUnavailable>()));
    expect(service.requests, isEmpty);
  });

  test('mismatched Ledger snapshot is rejected before a history request',
      () async {
    final service = _Service();
    final scope = ProviderContainer(overrides: [
      portfolioPerformanceServiceProvider.overrideWithValue(service),
      ledgerIdentityProvider('ledger').overrideWith((_) => const LedgerIdentity(
          walletId: 'ledger', evmAddress: ledger, evmVerifiedAtMs: 1)),
      ledgerPmAccountProvider('ledger').overrideWith((_) async =>
          const LedgerPmAccount(
              walletId: 'other',
              eoa: spending,
              account: PolymarketLedgerAccount.legacySafe(proxy))),
    ]);
    addTearDown(scope.dispose);
    addTearDown(service.close);
    await expectLater(
        scope.read(portfolioPerformanceProvider(
                const PortfolioPerformanceRequest(
                    venue: PortfolioPerformanceVenue.predictions,
                    walletId: 'ledger'))
            .future),
        throwsA(isA<PortfolioPerformanceUnavailable>()));
    expect(service.requests, isEmpty);
  });

  test(
      'confirmed absent Ledger Predictions account is empty rather than failure',
      () async {
    final service = _Service();
    final scope = ProviderContainer(overrides: [
      portfolioPerformanceServiceProvider.overrideWithValue(service),
      ledgerIdentityProvider('ledger').overrideWith((_) => const LedgerIdentity(
          walletId: 'ledger', evmAddress: ledger, evmVerifiedAtMs: 1)),
      ledgerPmAccountProvider('ledger').overrideWith((_) async =>
          const LedgerPmAccount(
              walletId: 'ledger',
              eoa: ledger,
              account: PolymarketLedgerAccount.none())),
    ]);
    addTearDown(scope.dispose);
    addTearDown(service.close);
    final data = await scope.read(portfolioPerformanceProvider(
            const PortfolioPerformanceRequest(
                venue: PortfolioPerformanceVenue.predictions,
                walletId: 'ledger'))
        .future);
    expect(data.points, isEmpty);
    expect(data.totalPnlUsd, isNull);
    expect(service.requests, isEmpty);
  });

  for (final match in [false, true]) {
    test(
        'hot Predictions proxy is used only when EOA matches spending ($match)',
        () async {
      final service = _Service();
      final scope = ProviderContainer(overrides: [
        portfolioPerformanceServiceProvider.overrideWithValue(service),
        hyperliquidAddressProvider.overrideWith((_) async => spending),
        polymarketTradingProvider
            .overrideWith(() => _Trading(match ? spending : ledger)),
      ]);
      addTearDown(scope.dispose);
      addTearDown(service.close);
      final future = scope.read(portfolioPerformanceProvider(
              const PortfolioPerformanceRequest(
                  venue: PortfolioPerformanceVenue.predictions))
          .future);
      if (match) {
        await future;
        expect(service.requests, ['pm:$proxy']);
      } else {
        await expectLater(
            future, throwsA(isA<PortfolioPerformanceUnavailable>()));
        expect(service.requests, isEmpty);
      }
    });
  }

  test('a trading poll with the same holdings does not read the history again',
      () async {
    final service = _Service();
    final scope = ProviderContainer(overrides: [
      portfolioPerformanceServiceProvider.overrideWithValue(service),
      hyperliquidAddressProvider.overrideWith((_) async => spending),
      polymarketTradingProvider.overrideWith(() => _Trading(spending)),
    ]);
    addTearDown(scope.dispose);
    addTearDown(service.close);
    const request = PortfolioPerformanceRequest(
        venue: PortfolioPerformanceVenue.predictions);
    final sub = scope.listen(portfolioPerformanceProvider(request), (_, __) {});
    addTearDown(sub.close);
    await scope.read(portfolioPerformanceProvider(request).future);
    expect(service.requests, ['pm:$proxy']);
    final trading = scope.read(polymarketTradingProvider.notifier);
    // ignore: invalid_use_of_protected_member
    trading.state = AsyncData(PolymarketTradingState(
        walletAddress: spending, proxyWalletAddress: proxy, usdcBalance: 3));
    await Future<void>.delayed(Duration.zero);
    await scope.read(portfolioPerformanceProvider(request).future);
    expect(service.requests, ['pm:$proxy']);
  });
}
