// The ticket closes on its own order's fills only (its cloid, and a send
// again's), totalled; a same-coin fill with no cloid or another's (a stop
// that triggered, a TWAP slice, another client's order) never closes it.
// A market ticket closes on them before the venue answers once they come to
// the whole size asked for (never on a part), and the answer arriving after
// that changes nothing on the ticket.
// The ticket's prices are re-checked against the price at submit with the
// same rules the ticket shows while typing.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart'
    show hlFillsCoverSize;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show
        HlOrderResult,
        HlOrderResultKind,
        HyperliquidOrderNotPlacedException,
        HyperliquidOrderUnconfirmedException;

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

    test('with no size asked, the stream never closes a market ticket '
        'while its answer is awaited; after an unclear answer it closes on '
        'the total', () {
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

    test('own-cloid fills coming to the whole size close a market ticket '
        'before its answer; a part never does', () {
      const step = 0.00001; // BTC, 5 size decimals
      final whole = [
        _fill(cloid: cloid, px: 66000, sz: 0.001),
        _fill(cloid: cloid, px: 66200, sz: 0.001),
      ];
      final r = hlStreamReceipt(
          unconfirmed: false,
          market: true,
          own: whole,
          requestedSize: 0.002,
          sizeStep: step)!;
      expect(r.size, closeTo(0.002, 1e-12));
      expect(r.avgPx, closeTo(66100, 1e-6));
      // Half of it: the answer says what filled.
      expect(
          hlStreamReceipt(
              unconfirmed: false,
              market: true,
              own: whole.take(1),
              requestedSize: 0.002,
              sizeStep: step),
          isNull);
      // One step short is a part too.
      expect(
          hlStreamReceipt(
              unconfirmed: false,
              market: true,
              own: [_fill(cloid: cloid, sz: 0.00199)],
              requestedSize: 0.002,
              sizeStep: step),
          isNull);
      // A take-profit, stop-loss or trailing stop rides on it (asked size
      // 0): only the answer says whether those were placed.
      expect(
          hlStreamReceipt(
              unconfirmed: false, market: true, own: whole, sizeStep: step),
          isNull);
      // A limit never closes on a stream total.
      expect(
          hlStreamReceipt(
              unconfirmed: false,
              market: false,
              own: whole,
              requestedSize: 0.002,
              sizeStep: step),
          isNull);
    });

    group('the answer after the ticket closed on the stream', () {
      const filled = HlOrderResult(
          kind: HlOrderResultKind.filled, oid: 1, filledSz: 0.002, avgPx: 1);

      test('a late success: no second receipt, the tile marked placed',
          () async {
        var placed = 0;
        final r = await hlMarketAnswer(Future.value(filled),
            closed: () => true, onClosed: () => placed++);
        expect(r, isNull);
        expect(placed, 1);
      });

      test('a late timeout / unconfirmed or error: no error, no lock',
          () async {
        for (final e in <Object>[
          const HyperliquidOrderUnconfirmedException(),
          TimeoutException('15 s'),
          const HyperliquidOrderNotPlacedException(),
        ]) {
          var placed = 0;
          final r = await hlMarketAnswer(Future<HlOrderResult>.error(e),
              closed: () => true, onClosed: () => placed++);
          expect(r, isNull);
          expect(placed, 1);
        }
      });

      test('not closed yet: the answer is the ticket\'s, as it is', () async {
        var placed = 0;
        expect(
            await hlMarketAnswer(Future.value(filled),
                closed: () => false, onClosed: () => placed++),
            same(filled));
        await expectLater(
            hlMarketAnswer(
                Future<HlOrderResult>.error(
                    const HyperliquidOrderUnconfirmedException()),
                closed: () => false,
                onClosed: () => placed++),
            throwsA(isA<HyperliquidOrderUnconfirmedException>()));
        expect(placed, 0);
      });

      test('closed while the answer was in the air counts at its arrival',
          () async {
        var closed = false;
        final answer = Completer<HlOrderResult>();
        final r = hlMarketAnswer(answer.future,
            closed: () => closed, onClosed: () {});
        closed = true; // the stream closed the ticket first
        answer.complete(filled);
        expect(await r, isNull);
      });
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

  group('the stream closes on the size the notifier SENT, not the slip\'s',
      () {
    // The slip estimated 0.010 BTC; the price fell during funding and the
    // notifier sent 0.012 (it sizes after funding, at the live price).
    const sent = 0.012;
    const step = 0.00001;
    List<HlFill> own(List<double> sizes) => [
          for (final sz in sizes) _fill(cloid: cloid, sz: sz, px: 60000),
        ];

    test('fills reaching only the slip\'s estimate do not close it', () {
      expect(
          hlStreamReceipt(
              unconfirmed: false,
              market: true,
              own: own([0.006, 0.004]),
              requestedSize: sent,
              sizeStep: step),
          isNull);
    });

    test('fills reaching the sent size close it, totalled', () {
      final r = hlStreamReceipt(
          unconfirmed: false,
          market: true,
          own: own([0.006, 0.004, 0.002]),
          requestedSize: sent,
          sizeStep: step);
      expect(r, isNotNull);
      expect(r!.size, closeTo(sent, 1e-12));
      expect(r.avgPx, 60000);
      // The notifier's unclear-answer rule is the same rule.
      expect(hlFillsCoverSize(0.012, sent, 5), isTrue);
      expect(hlFillsCoverSize(0.010, sent, 5), isFalse);
    });

    test('nothing closes before the notifier says what it sent', () {
      expect(
          hlStreamReceipt(
              unconfirmed: false,
              market: true,
              own: own([0.012]),
              requestedSize: 0,
              sizeStep: step),
          isNull);
    });

    test('a perp open takes the size from the notifier on both its paths', () {
      final src = File(
              'lib/screens/hyperliquid/components/order_slip_sheet.dart')
          .readAsStringSync();
      // Zeroed for an open after the exit branch, set again by onSent.
      expect(src, contains('if (!isSpot) _sentMarketSize = 0;'));
      expect(src, contains('_sentMarketSize = _sentMarketAttached ? 0 : size;'));
      // The direct ticket and the funded auto-fire both hand it over.
      expect('onSent: _onMarketSent'.allMatches(src).length, 2);
      final provider =
          File('lib/providers/hyperliquid_trading_provider.dart')
              .readAsStringSync();
      final open = provider.indexOf('Future<HlOrderResult> openPosition(');
      final told = provider.indexOf('onSent?.call(size);', open);
      final send = provider.indexOf('ex.placeMarketOrder(', open);
      expect(told, greaterThan(open));
      expect(told, lessThan(send));
    });
  });
}
