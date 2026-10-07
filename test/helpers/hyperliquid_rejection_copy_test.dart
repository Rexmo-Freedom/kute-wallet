// The venue's documented order rejections (Hyperliquid docs, "Error
// responses") read in plain words; anything else keeps the generic line.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_error_message.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

void main() {
  final l10n = l10nForLanguage('en');

  test('maps the documented venue strings', () {
    String msg(String reason) =>
        hlTradeErrorMessage(l10n, HyperliquidRejectedException(reason));
    expect(msg('Price must be divisible by tick size. asset=0'),
        l10n.hlRejectTick);
    expect(msg('Order must have minimum value of \$10. asset=0'),
        l10n.hlRejectMinNotional);
    expect(msg('Insufficient margin to place order. asset=3'),
        l10n.investingInsufficientBalance);
    expect(msg('Reduce only order would increase position. asset=3'),
        l10n.hlRejectReduceOnly);
    expect(
        msg('Order would increase open interest while open interest is capped'),
        l10n.hlRejectOiCap);
    expect(
        msg('Order rejected due to price more aggressive than oracle while at '
            'open interest cap'),
        l10n.hlRejectOiCap);
    expect(msg('Post only order would have immediately matched, bbo was 1@2'),
        l10n.hlRejectPostOnly);
    expect(msg('Order could not immediately match against any resting orders.'),
        l10n.hlRejectNoLiquidity);
    expect(msg('Invalid TP/SL price. asset=1'), l10n.hlRejectTpsl);
    expect(msg('Order price too far from oracle'), l10n.hlRejectOracle);
    expect(msg('Something new'), l10n.investingTradeRejected);
  });
}
