import 'package:kute/models/polymarket_model.dart' show Activity, ActivityType;
import 'package:kute/services/trade_notification_store.dart';

/// Confirmed fills only. Multiple fills of one side/outcome in the same
/// transaction share a receipt; buys and sells remain distinct.
List<TradeNotification> polymarketTradeNotifications(
  List<Activity> activities, {
  required String account,
  required String walletId,
  required String walletName,
}) {
  final owner = account.toLowerCase();
  final groups = <String, List<Activity>>{};
  for (final a in activities) {
    final side = a.side?.toUpperCase();
    if (a.proxyWallet.toLowerCase() != owner ||
        a.activityType != ActivityType.trade ||
        (side != 'BUY' && side != 'SELL') ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(a.transactionHash) ||
        !a.size.isFinite ||
        a.size <= 0 ||
        !a.usdcSize.isFinite ||
        a.usdcSize < 0) {
      continue;
    }
    final key = 'pm-fill:$owner:${a.transactionHash.toLowerCase()}:'
        '${a.asset ?? a.conditionId}:${a.outcomeIndex}:$side';
    (groups[key] ??= []).add(a);
  }
  return [
    for (final entry in groups.entries)
      _receipt(entry.key, entry.value, owner, walletId, walletName)
  ];
}

TradeNotification _receipt(String id, List<Activity> fills, String account,
    String walletId, String walletName) {
  final a = fills.first;
  final buy = a.side!.toUpperCase() == 'BUY';
  final amount = fills.fold<double>(0, (sum, a) => sum + a.usdcSize);
  final size = fills.fold<double>(0, (sum, a) => sum + a.size);
  final time = fills.map((a) => a.timestamp).reduce((a, b) => a > b ? a : b);
  return TradeNotification(
    id: id,
    account: account,
    walletId: walletId,
    walletName: walletName,
    product: 'predictions',
    imageUrl: a.icon,
    title: buy ? 'Prediction bought' : 'Prediction sold',
    subtitle: [
      a.title ?? 'Prediction',
      if (a.outcome?.isNotEmpty == true) a.outcome!
    ].join(' · '),
    time: time * 1000,
    rows: {
      buy ? 'Bought' : 'Sold': '\$${amount.toStringAsFixed(2)}',
      'Wallet': walletName,
      'Shares': size.toStringAsFixed(4),
      'Average fill price': '${(amount / size * 100).toStringAsFixed(2)}¢',
      'Status': 'Filled',
      'Transaction': a.transactionHash,
    },
  );
}
