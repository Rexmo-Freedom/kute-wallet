// The words on an activity row: one short verb-first title, one line of
// context, and a sign rule that is the same on every surface.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/screens/shared/activity_row_copy.dart';

final _en = l10nForLanguage('en');
final _pt = l10nForLanguage('pt');

Activity _activity(String type,
        {String? side,
        double usdc = 0,
        double size = 2.07,
        int at = 1759650000,
        String? title,
        String? outcome}) =>
    Activity(
      proxyWallet: '0xsafe',
      timestamp: at,
      conditionId: '0xc',
      type: type,
      size: size,
      usdcSize: usdc,
      transactionHash: '0xhash',
      side: side,
      title: title,
      outcome: outcome,
    );

HlFill _fill(String coin, String side,
        {double sz = 1, double? start, bool liquidated = false}) =>
    HlFill(
      coin: coin,
      px: 100,
      sz: sz,
      side: side,
      time: 0,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: 1,
      hash: '0x',
      dir: '',
      cloid: null,
      startPosition: start,
      liquidated: liquidated,
    );

const _g2 = 'Counter-Strike: ShindeN vs G2 (BO3) - ESL Pro League Group Stage';
const _round = 'Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET';

extension on Activity {
  Activity copyWithUsdc(double usdc) => Activity(
        proxyWallet: proxyWallet,
        timestamp: timestamp,
        conditionId: conditionId,
        type: type,
        size: size,
        usdcSize: usdc,
        transactionHash: transactionHash,
        side: side,
        outcome: outcome,
      );
}

void main() {
  group('short market label', () {
    test('a game keeps only the two sides', () {
      expect(shortMarketLabel(_g2), 'ShindeN vs G2');
    });

    test('a crypto round keeps the asset and its window', () {
      expect(shortMarketLabel(_round), 'Bitcoin 5:50–5:55');
      expect(
          shortMarketLabel('Ethereum Up or Down - October 5, 11AM-12PM ET'),
          'Ethereum 11AM–12PM');
    });

    test('a question is left whole for the row to ellipsize', () {
      const q = 'Will the Democratic Party win the 2028 US election?';
      expect(shortMarketLabel(q), q);
      expect(shortMarketLabel(null), '');
    });
  });

  group('prediction rows', () {
    test('a sale names the outcome sold, never the result', () {
      final copy = predictionRowCopy(
          _en,
          _activity('TRADE',
              side: 'SELL', usdc: 1.95, title: _g2, outcome: 'G2'),
          time: '12:05');
      expect(copy.title, 'Sold · G2');
      expect(copy.subtitle, 'ShindeN vs G2 · 12:05');
      expect(copy.flow, ActivityFlow.moneyIn);
      expect(copy.title, isNot(contains('Won')));
      expect(copy.title, isNot(contains('Lost')));
    });

    test('a purchase reads as a prediction, unsigned: the stake moved in',
        () {
      final copy = predictionRowCopy(
          _en,
          _activity('TRADE',
              side: 'BUY', usdc: 3.07, title: _round, outcome: 'Up'),
          time: '09:48');
      expect(copy.title, 'Prediction · Up');
      expect(copy.subtitle, 'Bitcoin 5:50–5:55 · 09:48');
      expect(copy.flow, ActivityFlow.neutral);
    });

    test('only a redeem says Won or Lost', () {
      final won = predictionRowCopy(
          _en, _activity('REDEEM', usdc: 4.53, title: _round, outcome: 'Up'),
          time: '10:02');
      expect(won.title, 'Won · Up');
      expect(won.flow, ActivityFlow.moneyIn);
      final lost = predictionRowCopy(
          _en, _activity('REDEEM', title: _round, outcome: 'Up'),
          time: '10:02');
      expect(lost.title, 'Lost · Up');
      expect(lost.flow, ActivityFlow.neutral);
    });

    test('with no outcome the market names the row and the time follows',
        () {
      final copy = predictionRowCopy(
          _en, _activity('TRADE', side: 'SELL', usdc: 1, title: _g2),
          time: '12:05');
      expect(copy.title, 'Sold · ShindeN vs G2');
      expect(copy.subtitle, '12:05');
    });

    test('money moves say where the money went', () {
      final deposit =
          predictionRowCopy(_en, _activity('DEPOSIT', usdc: 3), time: '12:09');
      expect(deposit.title, 'Deposit');
      expect(deposit.subtitle, 'to Predictions · 12:09');
      expect(deposit.flow, ActivityFlow.neutral);
    });

    test('Portuguese reads the same way', () {
      final copy = predictionRowCopy(
          _pt,
          _activity('TRADE',
              side: 'SELL', usdc: 1.95, title: _g2, outcome: 'G2'),
          time: '12:05');
      expect(copy.title, 'Vendeu · G2');
      expect(copy.title, isNot(contains('Ganhou')));
      final deposit =
          predictionRowCopy(_pt, _activity('DEPOSIT', usdc: 3), time: '12:09');
      expect(deposit.title, 'Depósito');
      expect(deposit.subtitle, 'para Previsões · 12:09');
    });
  });

  group('prediction figures', () {
    final buy = _activity('TRADE',
        side: 'BUY', usdc: 2.11, size: 2.07, at: 1759640000, outcome: 'G2');
    final sell = _activity('TRADE',
        side: 'SELL', usdc: 2.07, size: 2.07, at: 1759650000, outcome: 'G2');

    test('a sale carries its realised profit or loss', () {
      final f = predictionRowFigures(sell, [sell, buy],
          flow: ActivityFlow.moneyIn);
      expect(f.amount, 2.07);
      expect(f.flow, ActivityFlow.moneyIn);
      expect(f.pnl, closeTo(-0.04, 1e-9));
    });

    test('a win carries its profit over the stake', () {
      final won = _activity('REDEEM', usdc: 4.53, at: 1759660000);
      final f = predictionRowFigures(won, [won, buy.copyWithUsdc(3.07)],
          flow: ActivityFlow.moneyIn);
      expect(f.amount, 4.53);
      expect(f.pnl, closeTo(1.46, 1e-9));
    });

    test('a loss shows what was lost as the amount, nothing under it', () {
      final lost = _activity('REDEEM', at: 1759660000);
      final f = predictionRowFigures(lost, [lost, buy.copyWithUsdc(5)],
          flow: ActivityFlow.neutral);
      expect(f.amount, 5);
      expect(f.flow, ActivityFlow.moneyOut);
      expect(f.pnl, isNull);
    });

    test('a prediction shows its stake unsigned and uncoloured', () {
      final copy = predictionRowCopy(_en, buy, time: '09:48');
      final f = predictionRowFigures(buy, [buy], flow: copy.flow);
      expect(f.amount, 2.11);
      expect(f.flow, ActivityFlow.neutral);
      expect(f.settled, isFalse);
      expect(f.pnl, isNull);
    });

    test('a sale is not a settled result', () {
      expect(
          predictionRowFigures(sell, [sell, buy], flow: ActivityFlow.moneyIn)
              .settled,
          isFalse);
    });

    test('a redeem is a settled result', () {
      final won = _activity('REDEEM', usdc: 4.53, at: 1759660000);
      expect(
          predictionRowFigures(won, [won, buy], flow: ActivityFlow.moneyIn)
              .settled,
          isTrue);
    });

    test('no cost known: no line under the amount', () {
      expect(
          predictionRowFigures(sell, [sell], flow: ActivityFlow.moneyIn).pnl,
          isNull);
    });
  });

  group('Investing fills', () {
    test('opening and adding read as the side held', () {
      expect(hlFillRowTitle(_fill('BTC', 'B', start: 0), 'BTC', _en),
          'Long BTC');
      expect(hlFillRowTitle(_fill('BTC', 'A', start: 0), 'BTC', _en),
          'Short BTC');
      expect(hlFillRowTitle(_fill('BTC', 'B', start: 1), 'BTC', _en),
          'Long BTC');
    });

    test('closing and reducing say so', () {
      expect(hlFillRowTitle(_fill('BTC', 'A', start: 1), 'BTC', _en),
          'Closed BTC');
      expect(hlFillRowTitle(_fill('BTC', 'A', sz: 0.5, start: 1), 'BTC', _en),
          'Reduced BTC');
      expect(
          hlFillRowTitle(
              _fill('BTC', 'A', start: 1, liquidated: true), 'BTC', _en),
          'Liquidated BTC');
    });

    test('a spot token is bought or sold, and only spot moves money', () {
      final buy = _fill('@107', 'B');
      expect(hlFillRowTitle(buy, 'HYPE', _en), 'Bought · HYPE');
      expect(hlFillFlow(buy), ActivityFlow.moneyOut);
      expect(hlFillFlow(_fill('@107', 'A')), ActivityFlow.moneyIn);
      expect(hlFillFlow(_fill('BTC', 'B', start: 0)), ActivityFlow.neutral);
    });
  });
}
