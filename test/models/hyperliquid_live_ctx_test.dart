// The open market sheet takes 24h volume, funding and open interest live
// from `activeAssetCtx` (payload below as the venue sent it for
// xyz:TSLA), and every live price shows its own 24h change.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

const _tsla = HlMarket(
  coin: 'TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110001,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: false,
  markPx: 360,
  midPx: 360,
  prevDayPx: 350,
  dayNtlVlm: 1000,
  funding: 0.0001,
  openInterest: 10,
  category: 'stocks',
  dex: 'xyz',
  isHip3: true,
);

void main() {
  test('activeAssetCtx frames replace the cached stats', () {
    final ctx = HlAssetCtx.fromJson(const {
      'funding': '0.00000625',
      'openInterest': '135049.0080000001',
      'prevDayPx': '371.03',
      'dayNtlVlm': '871475.7344000004',
      'premium': '-0.0000807428',
      'oraclePx': '371.55',
      'markPx': '371.55',
      'midPx': '371.52',
      'impactPxs': ['371.499', '371.541'],
      'dayBaseVlm': '2347.527',
    });
    final live = hlMarketWithLiveCtx(_tsla, ctx);
    expect(live.markPx, 371.55);
    expect(live.midPx, 371.52);
    expect(live.prevDayPx, 371.03);
    expect(live.dayNtlVlm, closeTo(871475.73, 0.01));
    expect(live.funding, 0.00000625);
    expect(live.openInterest, closeTo(135049.008, 0.001));
    // Identity and metadata are untouched.
    expect(live.wireCoin, 'xyz:TSLA');
    expect(live.assetId, 110001);
    expect(live.category, 'stocks');
    expect(hlMarketWithLiveCtx(_tsla, null), same(_tsla));
  });

  test('the 24h change follows the live price', () {
    expect(_tsla.dayChangePct, closeTo(10 / 350, 1e-9));
    expect(_tsla.dayChangeAt(385), closeTo(35 / 350, 1e-9));
    // No live price yet: the snapshot change stands.
    expect(_tsla.dayChangeAt(0), _tsla.dayChangePct);
  });
}
