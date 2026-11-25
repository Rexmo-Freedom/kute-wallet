// lib/services/standing_orders/standing_order_progress.dart
//
// What others may read of the standing orders in flight (a notification
// or a Live Activity facade, built separately): the stage, the amounts,
// the venue and when it started, as a ChangeNotifier. It knows nothing of
// money: the StandingOrdersNotifier feeds it.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/standing_orders/standing_order.dart';

class StandingOrderProgress extends ChangeNotifier {
  List<StandingOrder> _open = const [];
  StandingOrder? _last;

  /// Every standing order still in flight, oldest first.
  List<StandingOrder> get open => _open;

  /// The one a notification would show: the newest in flight, else the
  /// last one that ended (so a facade can say "Prediction placed").
  StandingOrder? get current => _open.isEmpty ? _last : _open.last;

  StandingOrderState? get stage => current?.state;
  StandingOrderVenue? get venue => current?.venue;
  double? get amountUsd => current?.amountUsd;
  double? get fundUsd => current?.fundUsd;
  DateTime? get startedAt => current?.createdAt;
  bool get active => _open.isNotEmpty;

  void update(List<StandingOrder> all) {
    final open = [for (final o in all) if (o.isOpen) o];
    StandingOrder? last;
    for (final o in all) {
      if (o.isOpen) continue;
      if (last == null || o.updatedAt.isAfter(last.updatedAt)) last = o;
    }
    _open = List.unmodifiable(open);
    _last = last;
    notifyListeners();
  }
}

final standingOrderProgressProvider =
    ChangeNotifierProvider<StandingOrderProgress>(
        (ref) => StandingOrderProgress());
