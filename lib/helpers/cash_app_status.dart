import 'package:kute/helpers/reconcile_cadence.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/swap_order_model.dart';

/// A payment sent just before the deadline can take a while to reach the
/// provider status. For this long after a window closes nothing offers a
/// new purchase, and background checks keep their normal rate.
const kCashAppPaymentGracePeriod = Duration(minutes: 2);

/// Localized status for a Cash App purchase in the activity row and detail
/// sheet. A closed payment window is not a provider cancellation, so it has
/// its own label and never reads as expired.
String cashAppStatusLabel(SwapOrder order, AppLocalizations l10n) {
  if (order.cashAppPaymentWindowClosed) return l10n.cashAppPaymentWindowEnded;
  switch (order.status) {
    case 'wait':
    case 'waiting':
    case 'pending':
    case 'unfulfilled':
      return l10n.awaitingPayment;
    case 'exchanging':
    case 'confirmation':
    case 'sending':
      return l10n.processing;
    case 'success':
    case 'settled':
      return l10n.completed;
    case 'refunded':
      return l10n.refunded;
    case 'expired':
    case 'canceled':
      return l10n.expired;
    case 'overdue':
      return l10n.refunding;
    default:
      return l10n.pending;
  }
}

/// The Point 0 ladder for closed Cash App payment windows: every poll during
/// the grace period, then the shared ladder until 14 days.
const kCashAppClosedWindowCadence =
    ReconcileCadence(immediateFor: kCashAppPaymentGracePeriod);

/// How often background sync rechecks an unpaid Cash App order after its
/// payment window closed, by time since it closed. Zero means on every
/// background status poll; null means only on the first sync after the app
/// starts or comes back to the foreground.
Duration? cashAppClosedWindowPollInterval(Duration sinceClosed) =>
    kCashAppClosedWindowCadence.intervalFor(sinceClosed);

/// Whether a closed-window order is due for a background status check.
/// [foregroundedAt] is when the app last started or came back to the
/// foreground. A last check stamped after [now] (the clock moved back)
/// never delays the next one.
bool cashAppClosedWindowPollDue({
  required DateTime now,
  required DateTime closedAt,
  required DateTime? lastPolledAt,
  required DateTime foregroundedAt,
}) =>
    kCashAppClosedWindowCadence.isDue(
      now: now,
      since: closedAt,
      lastCheckedAt: lastPolledAt,
      foregroundedAt: foregroundedAt,
    );

/// Paces background status checks of unpaid Cash App orders whose payment
/// window closed. In memory only, so each app start rechecks them.
class CashAppClosedWindowSchedule {
  CashAppClosedWindowSchedule({DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _foregroundedAt = _now();
  }

  /// A failed check is retried once this soon instead of after a full
  /// interval, so a brief outage doesn't hide a late payment for hours.
  static const failedCheckRetry = Duration(minutes: 1);

  final DateTime Function() _now;
  late DateTime _foregroundedAt;
  final Map<String, DateTime> _lastCheckedAt = {};
  final Map<String, int> _failedChecks = {};

  void markForegrounded() => _foregroundedAt = _now();

  /// Whether [order] is due for a status check. Paid, refunding and
  /// in-window orders always are.
  bool isDue(SwapOrder order) {
    final closedAt = order.cashAppWindowClosedAt;
    if (closedAt == null) return true;
    final now = _now();
    final last = _lastCheckedAt[order.id];
    if (cashAppClosedWindowPollDue(
      now: now,
      closedAt: DateTime.fromMillisecondsSinceEpoch(closedAt),
      lastPolledAt: last,
      foregroundedAt: _foregroundedAt,
    )) {
      return true;
    }
    return _failedChecks[order.id] == 1 &&
        now.difference(last!) >= failedCheckRetry;
  }

  /// Starts a check of [order] when it is due. The check counts as failed
  /// until [recordSuccess] reports a status response for it.
  bool begin(SwapOrder order) {
    if (order.cashAppWindowClosedAt == null) {
      _lastCheckedAt.remove(order.id);
      _failedChecks.remove(order.id);
      return true;
    }
    if (!isDue(order)) return false;
    _lastCheckedAt[order.id] = _now();
    _failedChecks.update(order.id, (count) => count + 1, ifAbsent: () => 1);
    return true;
  }

  void recordSuccess(String id) => _failedChecks.remove(id);

  /// Whether an order whose window closed within the last day has a check
  /// due, so sync runs off its usual routes only when there is work.
  bool anyRecentlyClosedDue(Iterable<SwapOrder> orders) {
    final dayAgo =
        _now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    return orders.any((order) {
      final closedAt = order.cashAppWindowClosedAt;
      return closedAt != null && closedAt > dayAgo && isDue(order);
    });
  }
}
