// lib/providers/ledger/ledger_polymarket_activity_feed_provider.dart
//
// The Predictions activity feed for one Ledger wallet: the public history
// `ledgerPmActivityProvider` already reads for the exact resolved account,
// refreshed every 60 s the way the main screen's feed is kept fresh by
// its background sync. Rows without value (a zero redeem) are dropped, as
// the home feed drops them. Read only; nothing here creates credentials.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart' show Activity, ActivityType;
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';

final ledgerPmActivityFeedProvider = FutureProvider.autoDispose
    .family<List<Activity>, String>((ref, walletId) async {
  final timer = Timer.periodic(const Duration(seconds: 60), (_) {
    ref.invalidate(ledgerPmActivityProvider(walletId));
  });
  ref.onDispose(timer.cancel);
  final activity = await ref.watch(ledgerPmActivityProvider(walletId).future);
  return activity.where((a) {
    // `activityType` throws on values the bundled SDK does not know; one
    // unknown row must not blank the whole feed.
    try {
      return !(a.activityType == ActivityType.redeem && a.usdcSize <= 0);
    } catch (_) {
      return false;
    }
  }).toList();
});
