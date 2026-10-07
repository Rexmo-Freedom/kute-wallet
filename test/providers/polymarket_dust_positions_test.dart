// A position sold down to dust (under 0.01 share, what a "sell all" can
// leave behind) is gone: never on the Portfolio's Open positions and never
// claimable. On 5 Oct 2026 a CS2 position sold down to 0.002917 shares
// still read as a position on Portfolio.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart';

Position _position(String asset, double size, {bool redeemable = false}) =>
    Position(
      proxyWallet: 'wallet',
      asset: asset,
      conditionId: 'c-$asset',
      size: size,
      avgPrice: 0.96,
      initialValue: size * 0.96,
      currentValue: size,
      cashPnl: size * 0.04,
      percentPnl: 4,
      totalBought: 2.07,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: 1,
      redeemable: redeemable,
      title: 'Counter-Strike: ShindeN vs G2 (BO3)',
      slug: 'cs2-shin-g2-2026-10-05',
      eventSlug: 'cs2-shin-g2-2026-10-05',
      outcome: 'G2',
      outcomeIndex: 1,
      oppositeOutcome: 'ShindeN',
      oppositeAsset: 'shinden-$asset',
    );

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.positions);
  final List<Position> positions;
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      isAuthenticated: true, openPositions: positions);
}

void main() {
  test('dust under 0.01 share is neither open nor claimable', () async {
    final scope = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => _Trading([
            _position('held', 2.07),
            _position('dust', 0.002917),
            _position('won', 4.53, redeemable: true),
            _position('won-dust', 0.0099, redeemable: true),
            _position('cent', 0.01),
          ])),
    ]);
    addTearDown(scope.dispose);
    final sub = scope.listen(polymarketTradingProvider, (_, __) {});
    addTearDown(sub.close);
    await scope.read(polymarketTradingProvider.future);

    expect(scope.read(polymarketActivePositionsProvider).map((p) => p.tokenId),
        ['held', 'cent']);
    expect(
        scope.read(polymarketClaimablePositionsProvider).map((p) => p.tokenId),
        ['won']);
  });
}
