import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/services/polymarket_trade_notification.dart';
import 'package:kute/services/trade_notification_store.dart';

Activity fill(
        {String account = 'ledger-account',
        String side = 'BUY',
        String type = 'TRADE',
        String? hash,
        double size = 2,
        double usd = 1}) =>
    Activity(
        proxyWallet: account,
        timestamp: 1790520000,
        conditionId: 'condition',
        type: type,
        size: size,
        usdcSize: usd,
        transactionHash: hash ?? '0x${List.filled(64, 'a').join()}',
        asset: 'token',
        side: side,
        outcomeIndex: 0,
        title: 'Bitcoin up?',
        outcome: 'Up',
        icon: 'https://example.com/btc.svg');

void main() {
  test('Ledger buys and sells retain wallet attribution and remain distinct',
      () {
    final receipts = polymarketTradeNotifications([fill(), fill(side: 'SELL')],
        account: 'LEDGER-ACCOUNT',
        walletId: 'ledger-1',
        walletName: 'My Ledger');
    expect(receipts, hasLength(2));
    expect(
        receipts.map((r) => r.title), ['Prediction bought', 'Prediction sold']);
    expect(receipts.map((r) => r.id).toSet(), hasLength(2));
    for (final r in receipts) {
      final saved = TradeNotification.fromJson(r.toJson());
      expect(saved.walletId, 'ledger-1');
      expect(saved.walletName, 'My Ledger');
      expect(saved.rows['Wallet'], 'My Ledger');
      expect(saved.rows['Status'], 'Filled');
      expect(saved.imageUrl, 'https://example.com/btc.svg');
    }
  });
  test('unconfirmed orders, another account and non-trades cannot become fills',
      () {
    final receipts = polymarketTradeNotifications([
      fill(account: 'spending-account'),
      fill(hash: 'pending-order'),
      fill(type: 'REDEEM'),
      fill(side: 'UNKNOWN'),
      fill(size: 0),
      fill(usd: double.nan),
    ], account: 'ledger-account', walletId: 'ledger-1', walletName: 'Ledger');
    expect(receipts, isEmpty);
  });
  test('multiple fills in a transaction aggregate without merging buy and sell',
      () {
    final receipts = polymarketTradeNotifications([
      fill(),
      fill(size: 4, usd: 3),
      fill(side: 'SELL'),
    ], account: 'ledger-account', walletId: 'ledger-1', walletName: 'Ledger');
    expect(receipts, hasLength(2));
    expect(receipts.first.rows['Bought'], r'$4.00');
    expect(receipts.first.rows['Shares'], '6.0000');
    expect(receipts.first.rows['Average fill price'], '66.67¢');
  });
}
