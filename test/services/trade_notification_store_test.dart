import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/trade_notification_store.dart';

void main() {
  test(
      'results survive box reopen, isolate accounts and never reset read state',
      () async {
    final dir = await Directory.systemTemp.createTemp('trade-results-test');
    Hive.init(dir.path);
    const result = TradeNotification(
        id: 'pm:account-a:token:1',
        account: 'account-a',
        product: 'predictions',
        title: 'Prediction won',
        subtitle: 'Yes',
        rows: {'Payout': r'$18.00'},
        time: 1,
        positive: true);
    try {
      await TradeNotificationStore.add(result);
      await TradeNotificationStore.add(result);
      expect(await TradeNotificationStore.read({'account-b'}), isEmpty);
      expect((await TradeNotificationStore.read({'account-a'})).length, 1);
      await TradeNotificationStore.markRead(result);
      await TradeNotificationStore.add(result);
      expect((await TradeNotificationStore.read({'account-a'})).single.read,
          isTrue);
      await TradeNotificationStore.add(TradeNotification(
          id: result.id, account: result.account, product: result.product,
          title: result.title, subtitle: result.subtitle, rows: result.rows,
          time: result.time, imageUrl: 'https://example.com/market.svg'));
      final withArtwork = (await TradeNotificationStore.read({'account-a'})).single;
      expect(withArtwork.read, isTrue);
      expect(withArtwork.imageUrl, 'https://example.com/market.svg');
      await TradeNotificationStore.reconcile(TradeNotification(
          id: result.id,
          account: result.account,
          product: result.product,
          title: 'Reconciled',
          subtitle: result.subtitle,
          rows: const {'Net profit': r'$8.00'},
          time: result.time,
          positive: true));
      final updated = (await TradeNotificationStore.read({'account-a'})).single;
      expect(updated.read, isTrue);
      expect(updated.rows['Net profit'], r'$8.00');
      // Inspect durable storage through a reopened Hive box.
      await Hive.close();
      final box = await Hive.openBox<String>('trade_results_v1');
      expect(box.get(result.id), contains('"read":true'));
    } finally {
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });

  test('opening the list marks every receipt read and the badge count drops',
      () async {
    final dir = await Directory.systemTemp.createTemp('trade-results-seen');
    Hive.init(dir.path);
    TradeNotification receipt(String id, {bool read = false}) =>
        TradeNotification(
            id: id,
            account: 'account-a',
            product: 'trading',
            title: 'Closing fill',
            subtitle: 'BTC',
            rows: const {'Fill fee': '0.1 USDC'},
            time: 1,
            read: read);
    try {
      for (final id in ['a', 'b', 'c']) {
        await TradeNotificationStore.add(receipt(id));
      }
      var items = await TradeNotificationStore.read({'account-a'});
      expect(unreadTradeNotificationCount(items), 3);
      await TradeNotificationStore.markAllRead(items);
      items = await TradeNotificationStore.read({'account-a'});
      expect(unreadTradeNotificationCount(items), 0);
      // A later result counts again; replays of seen ones never do.
      await TradeNotificationStore.add(receipt('d'));
      await TradeNotificationStore.reconcile(receipt('a'));
      items = await TradeNotificationStore.read({'account-a'});
      expect(unreadTradeNotificationCount(items), 1);
      expect(items.where((n) => !n.read).single.id, 'd');
      // Read state is durable: it survives a reopened box (an app restart).
      await Hive.close();
      final box = await Hive.openBox<String>('trade_results_v1');
      for (final id in ['a', 'b', 'c']) {
        expect(box.get(id), contains('"read":true'));
      }
      expect(box.get('d'), contains('"read":false'));
      expect(unreadTradeNotificationCount(const []), 0);
    } finally {
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
