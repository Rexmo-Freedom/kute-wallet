import 'package:kute/models/hyperliquid_market.dart';

/// Only reconstruct complete, continuous flat-to-flat perpetual trades.
/// Missing opening fills, flips and liquidations deliberately remain provisional.
class HlClosedTrade {
  final int openedAt, closedAt;
  final double gross, fees;
  const HlClosedTrade(this.openedAt, this.closedAt, this.gross, this.fees);
  double net(double funding) => gross - fees + funding;

  static HlClosedTrade? fromFills(List<HlFill> source, HlFill last) {
    if (last.tradeId == null || !last.dir.startsWith('Close ')) return null;
    final fills = source.where((f) => f.coin == last.coin).toList()
      ..sort((a, b) {
        final time = a.time.compareTo(b.time);
        if (time != 0) return time;
        return (BigInt.tryParse(a.tradeId ?? '') ?? BigInt.zero)
            .compareTo(BigInt.tryParse(b.tradeId ?? '') ?? BigInt.zero);
      });
    final end = fills.indexWhere((f) => f.tradeId == last.tradeId);
    if (end < 0) return null;
    var expected = 0.0;
    var gross = 0.0;
    var fees = 0.0;
    final seen = <String>{};
    for (var i = end; i >= 0; i--) {
      final f = fills[i];
      final start = f.startPosition;
      if (!f.accountingComplete ||
          start == null ||
          !start.isFinite ||
          !f.sz.isFinite ||
          f.sz <= 0 ||
          !f.fee.isFinite ||
          !f.closedPnl.isFinite ||
          f.liquidated ||
          f.feeToken.trim() != 'USDC' ||
          !['B', 'A'].contains(f.side) ||
          f.tradeId == null ||
          !seen.add(f.tradeId!) ||
          !(f.dir.startsWith('Open ') || f.dir.startsWith('Close '))) {
        return null;
      }
      final after = start + (f.isBuy ? f.sz : -f.sz);
      final tolerance = f.sz.abs() * 1e-9 + 1e-12;
      if ((after - expected).abs() > tolerance ||
          (start * after < 0 && after.abs() > tolerance)) {
        return null;
      }
      // Equal-time fills need an exchange sequence id to order safely.
      if (i > 0 &&
          fills[i - 1].time == f.time &&
          (BigInt.tryParse(f.tradeId!) == null ||
              BigInt.tryParse(fills[i - 1].tradeId ?? '') == null)) {
        return null;
      }
      gross += f.closedPnl;
      fees += f.fee; // Exchange fee already includes builderFee.
      if (start == 0) {
        if (i == end || f.closedPnl != 0) return null;
        return HlClosedTrade(f.time, last.time, gross, fees);
      }
      expected = start;
    }
    return null;
  }
}
