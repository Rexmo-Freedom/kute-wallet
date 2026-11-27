// The ticket closes on its own order's fills only (its cloid, and a send
// again's), totalled; a same-coin fill with no cloid or another's (a stop
// that triggered, a TWAP slice, another client's order) never closes it.
// The ticket's prices are re-checked against the price at submit with the
// same rules the ticket shows while typing.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';

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

HlFill _fill(
        {String coin = 'BTC',
        String? cloid,
        double px = 66000,
        double sz = 0.001,
        double fee = 0.03,
        double closedPnl = 0}) =>
    HlFill(
        coin: coin,
        px: px,
        sz: sz,
        side: 'B',
        time: 0,
        closedPnl: closedPnl,
        fee: fee,
        feeToken: 'USDC',
        oid: 1,
        hash: '',
        dir: 'Open Long',
        cloid: cloid);

void main() {
  const cloid = '0x000000000000000000000000000000ab';

  setUp(HlResendCloids.reset);
  tearDown(HlResendCloids.reset);

  group('a fill is the ticket\'s by its own cloid only', () {
    test('another cloid or none on the same coin is never the ticket\'s',
        () {
      expect(hlFillOfOrder(_btc, cloid, _fill(cloid: cloid)), isTrue);
      expect(hlFillOfOrder(_btc, cloid, _fill(cloid: cloid.toUpperCase())),
          isTrue);
      // A stop that triggered, a TWAP slice: no cloid.
      expect(hlFillOfOrder(_btc, cloid, _fill()), isFalse);
      // Another client's order on the same coin.
      expect(hlFillOfOrder(_btc, cloid, _fill(cloid: '0xother')), isFalse);
      // Its cloid on another market.
      expect(hlFillOfOrder(_btc, cloid, _fill(coin: 'ETH', cloid: cloid)),
          isFalse);
    });

    test('a send again under a fresh cloid is still the ticket\'s', () {
      final fresh = HlResendCloids.renew(cloid);
      expect(hlFillOfOrder(_btc, cloid, _fill(cloid: fresh)), isTrue);
    });
  });

  group('the receipt totals the order\'s fills', () {
    test('two fills of this cloid: summed size, size-weighted price', () {
      final own = [
        _fill(cloid: cloid, px: 66000, sz: 0.001),
        _fill(cloid: cloid, px: 66300, sz: 0.002),
      ];
      final total = hlOwnFillsTotal(own)!;
      expect(total.size, closeTo(0.003, 1e-12));
      expect(total.avgPx, closeTo((66000 * 0.001 + 66300 * 0.002) / 0.003,
          1e-6));
      expect(hlOwnFillsTotal(const []), isNull);
    });

    test('the stream never closes a market ticket while its answer is '
        'awaited; after an unclear answer it closes on the total', () {
      final own = [
        _fill(cloid: cloid, px: 66000, sz: 0.001),
        _fill(cloid: cloid, px: 66100, sz: 0.001),
      ];
      expect(hlStreamReceipt(unconfirmed: false, market: true, own: own),
          isNull);
      final r = hlStreamReceipt(unconfirmed: true, market: true, own: own)!;
      expect(r.size, closeTo(0.002, 1e-12));
      expect(r.avgPx, closeTo(66050, 1e-6));
      // A limit, Scale or TWAP never closes on a stream total.
      expect(hlStreamReceipt(unconfirmed: true, market: false, own: own),
          isNull);
      expect(
          hlStreamReceipt(unconfirmed: true, market: true, own: const []),
          isNull);
    });

    test('only the ticket\'s fills reach the total', () {
      final stream = [
        _fill(cloid: cloid, sz: 0.001),
        _fill(sz: 0.5), // a triggered stop, no cloid
        _fill(cloid: '0xother', sz: 0.2),
        _fill(cloid: cloid, sz: 0.001),
      ];
      final own = stream.where((f) => hlFillOfOrder(_btc, cloid, f));
      expect(hlOwnFillsTotal(own)!.size, closeTo(0.002, 1e-12));
    });
  });

  group('the ticket\'s prices at submit', () {
    final l = l10nForLanguage('en');

    test('a buy ladder must rest under the price now', () {
      expect(
          hlScaleSideIssue(l,
              isLong: true, startPx: 65000, endPx: 63000, mid: 66000),
          isNull);
      // The price fell under the top leg since it was typed.
      expect(
          hlScaleSideIssue(l,
              isLong: true, startPx: 65000, endPx: 63000, mid: 64900),
          l.hlAdvScaleBelowPrice);
      expect(
          hlScaleSideIssue(l,
              isLong: false, startPx: 67000, endPx: 69000, mid: 67100),
          l.hlAdvScaleAbovePrice);
    });

    test('a market long\'s attached take-profit and stop-loss against the '
        'entry now', () {
      expect(
          hlTpSlEntryIssue(l,
              isLong: true, entry: 66000, takeProfit: 70000, stopLoss: 62000),
          isNull);
      // The price ran past the take-profit while Face ID was up.
      expect(
          hlTpSlEntryIssue(l,
              isLong: true, entry: 70100, takeProfit: 70000, stopLoss: 62000),
          l.slipTpAboveEntry);
      expect(
          hlTpSlEntryIssue(l,
              isLong: true, entry: 61900, takeProfit: 70000, stopLoss: 62000),
          l.slipSlBelowEntry);
      expect(
          hlTpSlEntryIssue(l,
              isLong: false, entry: 66000, takeProfit: 67000),
          l.slipTpBelowEntry);
    });
  });
}
