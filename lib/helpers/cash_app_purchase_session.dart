import 'package:kute/helpers/cash_app_invoice_expiry.dart';
import 'package:kute/helpers/cash_app_status.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra_routes.dart' show cashAppExchangeStatus;

/// The purchase currently shown in the payment sheet. Persisted orders and
/// background reconciliation deliberately live outside this short-lived view.
class CashAppPurchaseSession {
  CashAppPurchaseSession({
    DateTime Function()? now,
    Iterable<SwapOrder> Function()? storedOrders,
  })  : _now = now ?? DateTime.now,
        _storedOrders = storedOrders;

  /// Keep checking quickly and hold back a new purchase offer for this long
  /// after the window ends.
  static const endedGracePeriod = kCashAppPaymentGracePeriod;
  static const activePollInterval = Duration(seconds: 5);
  static const endedPollInterval = Duration(seconds: 30);

  /// Periodic timer ticks can land slightly early; don't skip them.
  static const _pollJitter = Duration(milliseconds: 500);

  final DateTime Function() _now;
  final Iterable<SwapOrder> Function()? _storedOrders;
  OrchestraOnrampResponse? _order;
  OrchestraOnrampResponse? _pollingOrder;
  DateTime? _deadline;
  DateTime? _lastPoll;
  bool _paymentEvidence = false;
  DateTime? _providerExpiredAt;
  DateTime? _lastUnpaidCheckSentAt;

  OrchestraOnrampResponse? get order => _order;

  /// Sticky. Payment evidence from the provider or from the persisted order,
  /// which background sync may update first, both count.
  bool get paymentReceived {
    final storedOrders = _storedOrders;
    if (!_paymentEvidence &&
        storedOrders != null &&
        showsPaymentIn(storedOrders())) {
      _paymentEvidence = true;
    }
    return _paymentEvidence;
  }

  int? get expiresAt => _deadline?.millisecondsSinceEpoch;

  /// The invoice deadline, or when the provider reported the quote
  /// unfulfilled if that came first (a slow clock or a missing deadline).
  DateTime? get _windowEndsAt {
    final deadline = _deadline;
    final providerExpiredAt = _providerExpiredAt;
    if (deadline == null || providerExpiredAt == null) {
      return deadline ?? providerExpiredAt;
    }
    return providerExpiredAt.isBefore(deadline) ? providerExpiredAt : deadline;
  }

  bool get paymentWindowEnded {
    final endsAt = _windowEndsAt;
    return endsAt != null && !paymentReceived && !_now().isBefore(endsAt);
  }

  /// When a new purchase may first be offered, for the display clock.
  int? get newPurchaseOfferAt =>
      _windowEndsAt?.add(endedGracePeriod).millisecondsSinceEpoch;

  /// True only once the window ended, the grace period elapsed, the latest
  /// status check reported the order unpaid and was sent no earlier than one
  /// fast poll before the grace period ended, and nothing shows a payment.
  /// Until then the caller keeps checking.
  bool get canOfferNewPurchase {
    if (!paymentWindowEnded) return false;
    final offerAt = _windowEndsAt!.add(endedGracePeriod);
    final checkedAt = _lastUnpaidCheckSentAt;
    return checkedAt != null &&
        !checkedAt.isBefore(offerAt.subtract(activePollInterval)) &&
        !_now().isBefore(offerAt);
  }

  /// Closed unpaid invoices remain reconcilable, with a slower automatic
  /// cadence after the grace period. Check status bypasses this delay.
  Duration get pollInterval => paymentWindowEnded &&
          !_now().isBefore(_windowEndsAt!.add(endedGracePeriod))
      ? endedPollInterval
      : activePollInterval;

  bool isCurrent(OrchestraOnrampResponse attempt) => identical(attempt, _order);

  void begin(OrchestraOnrampResponse order) {
    _order = order;
    _deadline = DateTime.tryParse(order.expiresAt) ??
        cashAppInvoiceExpiry(order.depositAddress);
    _reset();
  }

  /// Checks a stored purchase whose payment window already closed, outside
  /// the payment sheet. Its window counts as ended when the stored order
  /// closed.
  void beginStored(SwapOrder row) {
    final isQuote = row.id.startsWith('q_');
    final closedAt = row.cashAppWindowClosedAt;
    begin(OrchestraOnrampResponse(
      orderId: isQuote ? '' : row.id,
      quoteId: isQuote ? row.id : '',
      depositAddress: row.depositAddress,
      paymentLinks: OrchestraPaymentLinks(cashApp: '', shortUrl: ''),
      amountIn: row.depositAmount,
      estimatedOut: row.withdrawalAmount,
      expiresAt: closedAt == null
          ? ''
          : DateTime.fromMillisecondsSinceEpoch(closedAt, isUtc: true)
              .toIso8601String(),
    ));
  }

  void clear() {
    _order = null;
    _deadline = null;
    _reset();
  }

  void _reset() {
    _lastPoll = null;
    _paymentEvidence = false;
    _providerExpiredAt = null;
    _lastUnpaidCheckSentAt = null;
  }

  /// Return to amount review only after an explicit user action. This does
  /// not cancel/expire the previous provider order, delete its history, create
  /// another invoice or pay anything; background sync still owns that order.
  bool prepareNewPurchase() {
    if (_order == null || !canOfferNewPurchase) return false;
    clear();
    return true;
  }

  Future<OrchestraOrder?> poll(
    Future<OrchestraOrder?> Function(String id) fetch, {
    bool force = false,
  }) async {
    final current = _order;
    if (current == null || identical(_pollingOrder, current)) return null;
    final sentAt = _now();
    if (!force &&
        _lastPoll != null &&
        sentAt.difference(_lastPoll!) < pollInterval - _pollJitter) {
      return null;
    }
    final id = current.orderId.isNotEmpty ? current.orderId : current.quoteId;
    if (id.isEmpty) return null;
    _pollingOrder = current;
    _lastPoll = sentAt;
    try {
      final response = await fetch(id);
      // A late response for the old invoice must neither mutate nor close
      // the replacement purchase. Requests for a new attempt needn't wait
      // for an old request to time out.
      if (!isCurrent(current)) return null;
      final status = response == null
          ? null
          : cashAppExchangeStatus(response.status,
              paymentReceived: response.paymentReceived == true);
      if (response?.paymentReceived == true ||
          kCashAppPaidStatuses.contains(status)) {
        _paymentEvidence = true;
      } else if (kCashAppUnpaidStatuses.contains(status)) {
        // Unfulfilled is the provider confirming the quote expired.
        if (status == 'unfulfilled') _providerExpiredAt ??= _now();
        _lastUnpaidCheckSentAt = sentAt;
      } else {
        // A failed check or an unknown state no longer confirms the order
        // is unpaid.
        _lastUnpaidCheckSentAt = null;
      }
      return response;
    } finally {
      if (identical(_pollingOrder, current)) _pollingOrder = null;
    }
  }

  /// Whether [rows] hold this purchase with a status that only follows a
  /// payment. Background sync swaps a quote id for the real order id, so the
  /// invoice identifies the row too.
  bool showsPaymentIn(Iterable<SwapOrder> rows) {
    final current = _order;
    if (current == null) return false;
    return rows.any((row) =>
        ((current.orderId.isNotEmpty && row.id == current.orderId) ||
            (current.quoteId.isNotEmpty && row.id == current.quoteId) ||
            (current.depositAddress.isNotEmpty &&
                row.depositAddress == current.depositAddress)) &&
        kCashAppPaidStatuses.contains(row.status));
  }
}
