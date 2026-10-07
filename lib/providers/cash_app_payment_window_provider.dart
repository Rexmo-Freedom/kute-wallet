import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/cash_app_status.dart';

/// Paces background checks of Cash App orders whose payment window closed.
/// Coming back from a biometric prompt, a system dialog or the notification
/// shade is not the app returning, so only a return from hidden counts.
final cashAppClosedWindowScheduleProvider =
    Provider<CashAppClosedWindowSchedule>((ref) {
  final schedule = CashAppClosedWindowSchedule();
  final lifecycle = AppLifecycleListener(onShow: schedule.markForegrounded);
  ref.onDispose(lifecycle.dispose);
  return schedule;
});

/// Rebuilds a visible purchase when its payment deadline passes, even if
/// Orchestra cannot be reached. This is only a display clock: callers still
/// check the order's funding/settlement state before showing a closed window.
final cashAppDeadlinePassedProvider = StateNotifierProvider.autoDispose
    .family<CashAppDeadlineNotifier, bool, int?>((ref, expiresAt) {
  return CashAppDeadlineNotifier(expiresAt);
});

class CashAppDeadlineNotifier extends StateNotifier<bool>
    with WidgetsBindingObserver {
  CashAppDeadlineNotifier(this._expiresAt, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(false) {
    if (_expiresAt != null) {
      WidgetsBinding.instance.addObserver(this);
      _refresh();
    }
  }

  final int? _expiresAt;
  final DateTime Function() _now;
  Timer? _deadline;

  void _refresh() {
    _deadline?.cancel();
    final remaining = _expiresAt! - _now().millisecondsSinceEpoch;
    state = remaining <= 0;
    if (remaining > 0) {
      // Bound very distant/malformed deadlines without creating a fast
      // repeating timer for every historical purchase.
      final delay = remaining.clamp(1, const Duration(days: 1).inMilliseconds);
      _deadline = Timer(Duration(milliseconds: delay), _refresh);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _expiresAt != null) _refresh();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    if (_expiresAt != null) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
