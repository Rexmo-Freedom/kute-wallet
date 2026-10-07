/// The Point 0 status ladder, shared by every background reconciliation
/// that keeps checking an order it cannot prove finished: every minute for
/// the first hour, every 10 minutes until a day, hourly until 14 days, then
/// optionally daily until [dailyUntil]. Past the last step a check runs only
/// after the app starts or comes back to the foreground.
class ReconcileCadence {
  const ReconcileCadence({
    this.immediateFor = Duration.zero,
    this.dailyUntil,
  });

  /// How often an order visible in an open sheet is checked.
  static const visibleInterval = Duration(seconds: 5);

  /// For this long a check runs on every background poll.
  final Duration immediateFor;

  /// Daily checks continue after 14 days until this age. Null ends the
  /// scheduled checks at 14 days.
  final Duration? dailyUntil;

  /// The interval for an order [elapsed] into its ladder. Zero means on
  /// every background poll; null means only on start or foreground.
  Duration? intervalFor(Duration elapsed) {
    if (elapsed < immediateFor) return Duration.zero;
    if (elapsed < const Duration(hours: 1)) return const Duration(minutes: 1);
    if (elapsed < const Duration(hours: 24)) {
      return const Duration(minutes: 10);
    }
    if (elapsed < const Duration(days: 14)) return const Duration(hours: 1);
    final daily = dailyUntil;
    if (daily != null && elapsed < daily) return const Duration(days: 1);
    return null;
  }

  /// Whether a check is due. [since] starts the ladder, [foregroundedAt] is
  /// when the app last started or came back to the foreground. A last check
  /// stamped after [now] (the clock moved back) never delays the next one.
  bool isDue({
    required DateTime now,
    required DateTime since,
    required DateTime? lastCheckedAt,
    required DateTime foregroundedAt,
    bool visible = false,
  }) {
    if (lastCheckedAt == null || lastCheckedAt.isAfter(now)) return true;
    if (visible && now.difference(lastCheckedAt) >= visibleInterval) {
      return true;
    }
    final interval = intervalFor(now.difference(since));
    if (interval == null) return lastCheckedAt.isBefore(foregroundedAt);
    return now.difference(lastCheckedAt) >= interval;
  }

  /// When the next scheduled check falls, or null when only a start or
  /// foreground triggers one.
  DateTime? nextCheckAt({
    required DateTime now,
    required DateTime since,
    bool visible = false,
  }) {
    if (visible) return now.add(visibleInterval);
    final interval = intervalFor(now.difference(since));
    return interval == null ? null : now.add(interval);
  }
}
