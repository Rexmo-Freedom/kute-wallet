import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/helpers/reconcile_cadence.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';

/// What an Orchestra status read proved.
enum OrchestraStatusReadKind {
  /// The provider returned an order.
  order,

  /// The provider answered and has no order for the id: an HTTP 404, or a
  /// 200 whose envelope carries a null `order` and no payment evidence.
  notFound,

  /// Nothing was learned: a timeout, a transport error, 429, 5xx or any
  /// other failure. Never evidence that an order does not exist.
  unavailable,
}

/// A null-order envelope keeps its data, so Cash App callers still read its
/// status, expiry and payment evidence. It counts as not found only without
/// payment evidence.
OrchestraStatusReadKind classifyOrchestraStatusRead(
    Result<OrchestraOrder> result) {
  final order = result.data;
  if (result.isSuccess && order != null) {
    return order.orderMissing && order.paymentReceived != true
        ? OrchestraStatusReadKind.notFound
        : OrchestraStatusReadKind.order;
  }
  if (result.statusCode == 404) return OrchestraStatusReadKind.notFound;
  return OrchestraStatusReadKind.unavailable;
}

/// A not-found read may close a legacy quote row only this long after its
/// quote expired.
const kLegacyQuoteNotFoundGrace = Duration(minutes: 30);

/// Without a known expiry, a not-found read may close a legacy quote row
/// only this long after the row was created.
const kLegacyQuoteNoExpiryGrace = Duration(hours: 2);

/// An expired legacy quote row keeps a slow status check this long after it
/// was created, so a late auto-detected deposit is still found.
const kLegacyExpiredQuoteWatch = Duration(days: 14);

/// How often an expired legacy quote row is rechecked.
const kLegacyExpiredQuoteCheckInterval = Duration(days: 1);

enum LegacyStatusReadAction {
  /// Apply the returned order to the row.
  apply,

  /// Leave the row as it is.
  keep,

  /// Mark the quote row expired. It stays on the slow check.
  markExpired,
}

/// When a not-found read may first mark [row] expired.
DateTime legacyQuoteClosesAt(SwapOrder row) {
  final expiresAt = row.expiresAt;
  if (expiresAt != null) {
    return DateTime.fromMillisecondsSinceEpoch(expiresAt)
        .add(kLegacyQuoteNotFoundGrace);
  }
  return DateTime.fromMillisecondsSinceEpoch(row.timestamp)
      .add(kLegacyQuoteNoExpiryGrace);
}

/// The per-row decision background sync makes after a status read of a row
/// without a settlement record. Only a successful not-found read of a
/// non-purchase quote row, past its grace, marks it expired. A failed read
/// never changes a row.
LegacyStatusReadAction legacyStatusReadAction({
  required SwapOrder row,
  required OrchestraStatusReadKind read,
  required DateTime now,
}) {
  if (read == OrchestraStatusReadKind.order) {
    return LegacyStatusReadAction.apply;
  }
  if (read != OrchestraStatusReadKind.notFound ||
      // A row linked to a settlement operation is closed by the
      // reconciler from the operation's evidence, never by this rule.
      row.operationId != null ||
      !row.id.startsWith('q_') ||
      row.isCashAppPurchase ||
      row.status == 'expired') {
    return LegacyStatusReadAction.keep;
  }
  return now.isAfter(legacyQuoteClosesAt(row))
      ? LegacyStatusReadAction.markExpired
      : LegacyStatusReadAction.keep;
}

/// Whether an expired legacy quote row still gets its slow status check.
/// `expired` otherwise drops a row from [SwapOrder.shouldPollOrchestra].
bool legacyExpiredQuoteStillWatched(SwapOrder row, DateTime now) =>
    row.isOrchestra &&
    row.id.startsWith('q_') &&
    !row.isCashAppPurchase &&
    row.status == 'expired' &&
    now.difference(DateTime.fromMillisecondsSinceEpoch(row.timestamp)) <
        kLegacyExpiredQuoteWatch;

/// Rows background sync checks: every row still polling, plus expired legacy
/// quote rows inside their watch window.
bool legacyOrchestraRowNeedsStatusCheck(SwapOrder row, DateTime now) =>
    row.shouldPollOrchestra || legacyExpiredQuoteStillWatched(row, now);

/// Whether a read of a watched expired legacy quote row reports an outcome
/// the row has not had yet. Its `expired` may come from the local rule, so a
/// later success or refund is reported once; a repeated expiry is not.
bool legacyExpiredQuoteNewOutcome(
        SwapOrder row, String mappedStatus, DateTime now) =>
    legacyExpiredQuoteStillWatched(row, now) &&
    (mappedStatus == 'success' || mappedStatus == 'refunded');

/// The real order id to move a quote row to, or null when the read did not
/// return one. Any non-empty id that is not a quote id is the real one.
String? legacyReplacementOrderId(String rowId, OrchestraOrder order) {
  if (!rowId.startsWith('q_')) return null;
  final id = order.id;
  if (id.isEmpty || id == rowId || id.startsWith('q_')) return null;
  return id;
}

/// The row under its real order id. Every other field the quote row carried
/// (purchase marker, fiat paid, provider token, expiry) is kept.
SwapOrder legacyRowWithOrderId(SwapOrder row, String orderId) =>
    row.copyWith(id: orderId, provider: 'Orchestra');

/// Moves a row to a new id by writing the new row before deleting the old
/// one, so a kill between the two writes leaves a row that is still polled.
Future<void> replaceOrchestraRowId({
  required String oldId,
  required SwapOrder replacement,
  required Future<void> Function(SwapOrder row) add,
  required Future<void> Function(String id) delete,
}) async {
  await add(replacement);
  if (replacement.id != oldId) await delete(oldId);
}

/// Paces status checks of legacy quote rows (non-purchase `q_` rows). An
/// expired row is checked daily. A pending row is checked on every poll
/// while reads answer; after two failed reads in a row it falls back to
/// the Point 0 ladder by age, then daily. A failed daily check of an expired
/// row is retried once after a minute. In memory only, so each app start
/// rechecks them.
class LegacyExpiredQuoteSchedule {
  LegacyExpiredQuoteSchedule({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const failedCheckRetry = Duration(minutes: 1);
  static const _failureCadence = ReconcileCadence();

  final DateTime Function() _now;
  final Map<String, DateTime> _lastCheckedAt = {};
  final Map<String, int> _failedChecks = {};

  static bool _tracked(SwapOrder row, DateTime now) =>
      legacyExpiredQuoteStillWatched(row, now) ||
      (row.isOrchestra &&
          row.id.startsWith('q_') &&
          !row.isCashAppPurchase &&
          row.shouldPollOrchestra);

  bool _isDue(SwapOrder row, DateTime now) {
    final last = _lastCheckedAt[row.id];
    if (last == null || last.isAfter(now)) return true;
    final failures = _failedChecks[row.id] ?? 0;
    final sinceLast = now.difference(last);
    if (failures == 1 && sinceLast >= failedCheckRetry) return true;
    if (row.status == 'expired') {
      return sinceLast >= kLegacyExpiredQuoteCheckInterval;
    }
    if (failures < 2) return true;
    final age =
        now.difference(DateTime.fromMillisecondsSinceEpoch(row.timestamp));
    final interval =
        _failureCadence.intervalFor(age) ?? kLegacyExpiredQuoteCheckInterval;
    return sinceLast >= interval;
  }

  /// Starts a check of [row] when it is due. The check counts as failed
  /// until [recordRead] reports an answer. Rows that are not legacy quote
  /// rows are always due and are not tracked.
  bool begin(SwapOrder row) {
    final now = _now();
    if (!_tracked(row, now)) {
      _lastCheckedAt.remove(row.id);
      _failedChecks.remove(row.id);
      return true;
    }
    if (!_isDue(row, now)) return false;
    _lastCheckedAt[row.id] = now;
    _failedChecks.update(row.id, (count) => count + 1, ifAbsent: () => 1);
    return true;
  }

  void recordRead(String id, OrchestraStatusReadKind read) {
    if (read != OrchestraStatusReadKind.unavailable) _failedChecks.remove(id);
  }
}
