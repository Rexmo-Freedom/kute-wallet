// Shared action fixtures for the Hyperliquid engine tests. Each entry must
// construct — through the production builders — the exact action the vector
// generator (fixtures/generate_hl_vectors.py) built through the Python SDK.

import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';

const kHlTestCloid = '0x00000000000000000000000000000001';
const kHlTestBuilder = '0x8c967E73E6B15087c42A10D344cFf4c96D877f1D';

Map<String, Map<String, dynamic>> buildHlTestActions() {
  final ethIoc = HlOrderWire(
    assetId: 4,
    isBuy: true,
    px: '1670.1',
    sz: '0.0147',
    reduceOnly: false,
    orderType: limitOrderType('Ioc'),
  );
  return {
    'order_gtc': buildOrderAction(orders: [ethIoc]),
    'order_cloid': buildOrderAction(orders: [
      HlOrderWire(
        assetId: 4,
        isBuy: true,
        px: '1670.1',
        sz: '0.0147',
        reduceOnly: false,
        orderType: limitOrderType('Ioc'),
        cloid: kHlTestCloid,
      ),
    ]),
    'order_builder': buildOrderAction(
      orders: [ethIoc],
      builder: const HlBuilderFee(address: kHlTestBuilder, feeTenthsBp: 10),
    ),
    'order_trigger': buildOrderAction(orders: [
      HlOrderWire(
        assetId: 4,
        isBuy: false,
        px: '1670.1',
        sz: '0.0147',
        reduceOnly: true,
        orderType:
            triggerOrderType(isMarket: true, triggerPx: '1600', tpsl: 'sl'),
      ),
    ]),
    'spot_order': buildOrderAction(orders: [
      HlOrderWire(
        assetId: 10008,
        isBuy: true,
        px: '172.21',
        sz: '12',
        reduceOnly: false,
        orderType: limitOrderType('Gtc'),
      ),
    ]),
    'cancel': buildCancelAction([(assetId: 4, oid: 77738308)]),
    'cancel_cloid':
        buildCancelByCloidAction([(assetId: 4, cloid: kHlTestCloid)]),
    'update_leverage':
        buildUpdateLeverageAction(assetId: 4, isCross: true, leverage: 5),
    'set_referrer': buildSetReferrerAction(code: 'KUTE'),
  };
}
