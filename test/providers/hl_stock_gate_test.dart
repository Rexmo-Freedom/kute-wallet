import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

HlMarket _market(String coin,
        {HlMarketKind kind = HlMarketKind.perp,
        String category = 'crypto',
        String wire = ''}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire.isEmpty ? coin : wire,
      assetId: 1,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 1,
      category: category,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  final btc = _market('BTC');
  final tsla = _market('TSLA', category: 'stocks', wire: 'xyz:TSLA');
  final unannotatedStock = _market('AAPL', category: 'other');
  final stockToken =
      _market('TSLA', kind: HlMarketKind.spot, category: 'stocks');

  test('a stock-linked perp is a perp annotated or known as a stock', () {
    expect(isHlStockPerp(btc), isFalse);
    expect(isHlStockPerp(tsla), isTrue);
    expect(isHlStockPerp(unannotatedStock), isTrue);
    expect(isHlStockPerp(stockToken), isFalse,
        reason: 'a spot token is not a perpetual');
    expect(hlOpenCapabilities(btc), ['hyperliquid.trade']);
    expect(
        hlOpenCapabilities(tsla), ['hyperliquid.trade', 'hyperliquid.stocks']);
    expect(hlOpenCapabilities(stockToken), ['hyperliquid.trade']);
  });

  test(
      'the stock gate refuses new positions on stock perps only, leaving '
      'other markets and exits alone; it never filters a list (founder, '
      '12 November 2026)', () async {
    final open = runtimePolicyFixture();
    addTearDown(open.dispose);
    expect(await open.refresh(), isTrue);
    for (final m in [btc, tsla, unannotatedStock, stockToken]) {
      expect(hlStockGateAllows(m, open), isTrue, reason: m.coin);
    }
    final blocked = runtimePolicyFixture(blocked: {'hyperliquid.stocks'});
    addTearDown(blocked.dispose);
    expect(await blocked.refresh(), isTrue);
    expect(hlStockGateAllows(btc, blocked), isTrue);
    expect(hlStockGateAllows(tsla, blocked), isFalse);
    expect(hlStockGateAllows(unannotatedStock, blocked), isFalse);
    expect(hlStockGateAllows(stockToken, blocked), isTrue,
        reason: 'a spot token is not a perpetual');
    await blocked.ensureAllAllowed(hlOpenCapabilities(btc));
    await expectLater(
        blocked.ensureAllAllowed(hlOpenCapabilities(tsla)),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.capability, 'capability', 'hyperliquid.stocks')));
    await blocked.ensureAllAllowed(const ['hyperliquid.close']);
  });

  test('the stock gate fails closed without a readable policy', () {
    final unavailable = runtimePolicyFixture();
    addTearDown(unavailable.dispose);
    expect(hlStockGateAllows(btc, unavailable), isTrue);
    expect(hlStockGateAllows(tsla, unavailable), isFalse);
    expect(unavailable.allows('hyperliquid.browse'), isTrue,
        reason: 'markets stay visible while the policy is unavailable');
    expect(unavailable.allows('hyperliquid.trade'), isFalse,
        reason: 'no new positions while the policy is unavailable');
  });
}
