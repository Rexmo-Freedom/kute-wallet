// The trading notifier checks a protective trigger's side once more
// against the freshest price it has, right before signing: crossed since
// the sheet checked it, it refuses with nothing signed or sent. Fakes only:
// no exchange exists in these notifiers (a send would throw on it).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hl_trigger_guard.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlAssetCtx;
import 'package:kute/services/runtime_capabilities_service.dart';

import '../gating_audit/investing_gating_policies.dart';

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 66000,
  dayNtlVlm: 0,
);

class _Prices extends HlLivePricesNotifier {
  _Prices(this.mid);
  final double mid;
  @override
  HlLivePriceState build() => HlLivePriceState(mids: {'BTC': mid});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}

void main() {
  setUp(() => RuntimeCapabilitiesService.debugInstance = auditPolicy());
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  ProviderContainer container(double mid) {
    final c = ProviderContainer(overrides: [
      hyperliquidLivePricesProvider.overrideWith(() => _Prices(mid)),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
    ]);
    addTearDown(c.dispose);
    c.listen(hyperliquidLivePricesProvider, (_, __) {});
    return c;
  }

  AuthGrant grantFor(double triggerPx) => AuthGrants.issue(
        HlIntents.trigger(
          walletId: 'spending',
          market: _btc,
          isLong: false,
          size: 0.01,
          triggerPx: triggerPx,
          isMarket: true,
          tpsl: 'sl',
          reduceOnly: true,
        ),
        method: AuthGrantMethod.pin,
      );

  test('a long\'s stop the price fell under since the sheet checked it: '
      'refused, the grant unspent', () async {
    // Typed at 64,000 under a price of 66,000; the price is 63,500 now.
    final c = container(63500);
    await c.read(hyperliquidTradingProvider.future);
    final grant = grantFor(64000);
    await expectLater(
      c.read(hyperliquidTradingProvider.notifier).placeTrigger(
            market: _btc,
            isLong: false,
            size: 0.01,
            triggerPx: 64000,
            isMarket: true,
            tpsl: 'sl',
            grant: grant,
          ),
      throwsA(isA<HlTriggerCrossedException>()
          .having((e) => e.mark, 'mark', 63500)
          .having((e) => e.tpsl, 'tpsl', 'sl')),
    );
    // Nothing was signed: the approval was never consumed.
    expect(grant.consumed, isFalse);
  });

  test('a modify of a stop past the price now: refused before signing',
      () async {
    final c = container(63500);
    await c.read(hyperliquidTradingProvider.future);
    const stop = HlOpenOrder(
      coin: 'BTC',
      oid: 31,
      isBuy: false,
      limitPx: 57000,
      sz: 0.01,
      origSz: 0.01,
      timestamp: 2,
      cloid: null,
      reduceOnly: true,
      orderType: 'Stop Market',
      isTrigger: true,
      triggerPx: 60000,
    );
    await expectLater(
      c.read(hyperliquidTradingProvider.notifier).modifyOrder(
            market: _btc,
            order: stop,
            newPx: 64000,
            grant: grantFor(64000),
          ),
      throwsA(isA<HlTriggerCrossedException>()),
    );
  });

  test(
      'triggers fire on the mark: with the market\'s live mark at 63,500 and '
      'its mid still 66,000, a long\'s stop at 64,000 is refused on the mark',
      () async {
    // Hyperliquid: "The mark price is used to trigger TP/SL orders".
    final c = ProviderContainer(overrides: [
      hyperliquidLivePricesProvider.overrideWith(() => _Prices(66000)),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidActiveAssetCtxProvider.overrideWith((ref, wire) =>
          Stream.value(const HlAssetCtx(
              markPx: 63500,
              midPx: 66000,
              prevDayPx: 66000,
              dayNtlVlm: 0,
              funding: null,
              openInterest: null))),
    ]);
    addTearDown(c.dispose);
    c.listen(hyperliquidLivePricesProvider, (_, __) {});
    // The market sheet holds the live context open.
    c.listen(hyperliquidActiveAssetCtxProvider('BTC'), (_, __) {});
    await c.read(hyperliquidActiveAssetCtxProvider('BTC').future);
    await c.read(hyperliquidTradingProvider.future);
    final n = c.read(hyperliquidTradingProvider.notifier);
    expect(n.triggerMarkPx(_btc), 63500);
    final grant = grantFor(64000);
    await expectLater(
      n.placeTrigger(
        market: _btc,
        isLong: false,
        size: 0.01,
        triggerPx: 64000,
        isMarket: true,
        tpsl: 'sl',
        grant: grant,
      ),
      throwsA(isA<HlTriggerCrossedException>()
          .having((e) => e.mark, 'mark', 63500)),
    );
    expect(grant.consumed, isFalse);
  });

  test('no live context open: the freshest mid stands in for the mark',
      () async {
    final c = container(65000);
    await c.read(hyperliquidTradingProvider.future);
    expect(c.read(hyperliquidTradingProvider.notifier).triggerMarkPx(_btc),
        65000);
  });
}
