import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/cash_app_invoice_expiry.dart';

part 'swap_order_model.g.dart';

/// Hive box that stores every [SwapOrder]. The name is from the first
/// provider the store held and is kept because existing installs read
/// their order history from it.
const String kSwapOrdersBoxName = 'sideshiftExchanges';

/// Providers Kute no longer talks to. Their orders stay on the device as
/// read-only history: no status polling, no refunds, no new orders.
const Set<String> kRetiredSwapProviders = {'SideShift', 'BitcoinVN'};

/// Statuses after which an order never changes again.
const Set<String> kFinalSwapStatuses = {
  'success',
  'settled',
  'refunded',
  'expired',
  'canceled',
};

/// Cash App purchase statuses with no evidence that the invoice was paid.
const kCashAppUnpaidStatuses = {'wait', 'waiting', 'pending', 'unfulfilled'};

/// Cash App purchase statuses that only follow a paid invoice. Failed,
/// cancelled and unknown states are neither paid nor unpaid.
const kCashAppPaidStatuses = {
  'exchanging',
  'confirmation',
  'sending',
  'overdue',
  'success',
  'settled',
  'refunded',
};

/// Id prefix of an Activity row for a standing deposit that never
/// became an order; the provider's deposit id follows it. See
/// [SwapOrder.isStuckStandingDeposit].
const String kStuckStandingDepositRowPrefix = 'sdep_';

/// One exchange-style order the app tracks, regardless of who fills
/// it: an Orchestra swap, a Cash App deposit or bitcoin purchase (see
/// [purchaseSource]), or a retired provider's order kept as history.
/// [providerName] tells them apart; the field layout is the shared
/// deposit-leg / settle-leg shape every provider maps into.
///
/// Persisted in the [kSwapOrdersBoxName] Hive box as typeId 31. The
/// box name, typeId and field indices predate the rename and must
/// stay as they are so existing rows keep reading back.
@HiveType(typeId: 31)
class SwapOrder {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String coinFrom;
  @HiveField(2)
  final String networkFrom;
  @HiveField(3)
  final String coinTo;
  @HiveField(4)
  final String networkTo;
  @HiveField(5)
  final String depositAddress;
  @HiveField(6)
  final String? depositExtraId;
  @HiveField(7)
  final String depositAmount;
  @HiveField(8)
  final String withdrawalAmount;
  @HiveField(9)
  final String status;
  @HiveField(10)
  final int timestamp;
  @HiveField(11)
  final String withdrawalAddress;
  @HiveField(12)
  final String depositMin;
  @HiveField(13)
  final String depositMax;
  @HiveField(14)
  final String rate;
  @HiveField(15)
  final String refundAddress;
  @HiveField(16)
  final String? refundExtraId;
  @HiveField(17)
  final String? provider;
  @HiveField(18)
  final String? providerToken;
  @HiveField(19)
  final String? walletId;
  @HiveField(20)
  final int? expiresAt;
  /// Set when this row is a fiat-funded deposit rather than a crypto
  /// swap. 'cashapp' marks the Cash App onramp (Orchestra / Flashnet):
  /// the BOLT11 deposit leg is an implementation detail, so the
  /// activity row and detail sheet render Cash App as the source
  /// with the fiat paid instead of "Lightning → Bitcoin". Null on
  /// ordinary swap rows. Additive: older records read back as null.
  @HiveField(21)
  final String? purchaseSource;
  /// Fiat the user paid on a purchase row, USD with two decimals
  /// ('55.00'). Null on ordinary swap rows.
  @HiveField(22)
  final String? purchaseFiatUsd;
  /// The settlement operation this row tracks (Phase 5 plan B6). Null on
  /// legacy rows and on rows no operation owns. Additive: older records
  /// read back as null.
  @HiveField(23)
  final String? operationId;
  /// The funding route version this row was written by (P4.12), for
  /// example `spark_to_hypercore_v1`. Absent means v0: the legacy route
  /// (Spark to Arbitrum USDC and Bridge2 for Investing). Additive: older
  /// records read back as null.
  @HiveField(24)
  final String? routeVersion;

  /// Explicit external activity direction: `send` or `receive`. Venue moves
  /// are identified by their settlement operation, never by token/network.
  @HiveField(25)
  final String? activityDirection;

  SwapOrder({
    required this.id,
    required this.coinFrom,
    required this.networkFrom,
    required this.coinTo,
    required this.networkTo,
    required this.depositAddress,
    this.depositExtraId,
    required this.depositAmount,
    required this.withdrawalAmount,
    required this.status,
    required this.timestamp,
    required this.withdrawalAddress,
    required this.depositMin,
    required this.depositMax,
    required this.rate,
    required this.refundAddress,
    this.refundExtraId,
    this.provider,
    this.providerToken,
    this.walletId,
    this.expiresAt,
    this.purchaseSource,
    this.purchaseFiatUsd,
    this.operationId,
    this.routeVersion,
    this.activityDirection,
  });

  /// True for rows written before route versions existed (v0).
  bool get isLegacyRoute => routeVersion == null;

  // Backwards-compatible getters
  String get depositCoin => coinFrom;
  String get depositNetwork => networkFrom;
  String get settleCoin => coinTo;
  String get settleNetwork => networkTo;
  String get settleAddress => withdrawalAddress;
  String get settleAmount => withdrawalAmount;
  String? get depositMemo => depositExtraId;

  /// User-facing provider name. Falls back from the stored `provider`
  /// field through ID-based heuristics so historical entries written
  /// before the field was always populated still surface the correct
  /// brand. Order matters:
  ///   1. Stored `provider` if present and non-empty (authoritative).
  ///   2. `id` starting with `ord_` → Orchestra (their order ID
  ///      format; the polling block in `background_sync_provider`
  ///      replaces a `q_` quote ID with the `ord_` order ID and
  ///      stamps `provider: 'Orchestra'`, but exchanges from before
  ///      that pass would still have a null provider on disk).
  ///   3. Default to `SideShift`: the store's first provider, whose
  ///      old rows carry no provider field. Those rows are history only
  ///      (see [isRetiredProvider]).
  String get providerName {
    final p = provider;
    if (p != null && p.isNotEmpty) return p;
    // `q_…` is Orchestra's quote-id prefix; `ord_…` is the order-id
    // prefix returned by /submit. Either form is unambiguously
    // Orchestra — SideShift IDs are uuids with no prefix. Treating q_
    // as Orchestra here keeps the "Predictions withdraw" label on
    // records whose order id never got upgraded from quote to order
    // (Orchestra expired before the background-sync poll ran, the old
    // submit-response parser dropped `orderId`, etc.). Without this
    // those rows defaulted to "USDC → Bitcoin via SideShift" and the
    // home Activity feed lost track of which provider actually held
    // the funds.
    // `acu-` is the synthetic accumulation-placeholder prefix the HL
    // withdraw writes — also unambiguously Orchestra.
    if (id.startsWith('ord_') ||
        id.startsWith('q_') ||
        id.startsWith('acu-')) {
      return 'Orchestra';
    }
    return 'SideShift';
  }

  /// True when this exchange is an Orchestra order. Same heuristic as
  /// [providerName] — keeps every "is this Orchestra?" callsite
  /// (detail sheet explorer link, refund visibility, etc.) consistent
  /// with the displayed provider name.
  bool get isOrchestra => providerName == 'Orchestra';

  /// True for an order from a provider Kute no longer supports
  /// ([kRetiredSwapProviders]). Such orders are read-only history.
  bool get isRetiredProvider => kRetiredSwapProviders.contains(providerName);

  /// A retired-provider order whose last saved status was not final.
  /// Kute cannot check it any more, so it is shown as history with a
  /// note instead of as a pending order.
  bool get isUntrackedLegacyOrder =>
      isRetiredProvider && !kFinalSwapStatuses.contains(status);

  /// True when this row is a Cash App purchase or venue deposit. The explicit
  /// [purchaseSource] marker is authoritative; rows recorded before the
  /// marker existed fall back to
  /// the one shape only the Cash App onramp produces in this app: an
  /// Orchestra order paying a Lightning invoice that settles BTC to
  /// Spark or on-chain. No other Orchestra flow deposits over
  /// Lightning, so ordinary swap rows never match.
  bool get isCashAppPurchase {
    if (purchaseSource != null) return purchaseSource == 'cashapp';
    return isOrchestra &&
        coinFrom == 'BTC' &&
        networkFrom.toUpperCase() == 'LIGHTNING' &&
        coinTo == 'BTC' &&
        (networkTo.toUpperCase() == 'SPARK' ||
            networkTo.toUpperCase() == 'BITCOIN');
  }

  bool get canRefund =>
      status == 'overdue' ||
      status == 'emergency' ||
      status == 'expired' ||
      status == 'settle_data_error';

  double get amount => _toDouble(depositAmount);
  double get amountTo => _toDouble(withdrawalAmount);
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// Reads the JSON shape the transaction cache writes
  /// (`TransactionCacheCodec`): deposit/settle legs plus the saved status.
  factory SwapOrder.fromJson(Map<String, dynamic> json) {
    final coinFrom = json['depositCoin']?.toString().toUpperCase() ?? '';
    final coinTo = json['settleCoin']?.toString().toUpperCase() ?? '';
    final networkFrom = json['depositNetwork']?.toString() ?? '';
    final networkTo = json['settleNetwork']?.toString() ?? '';
    final depositAddress = json['depositAddress']?.toString() ?? '';
    final depositExtraId = json['depositMemo']?.toString();
    final withdrawalAddress = json['settleAddress']?.toString() ?? '';
    final depositAmount = json['depositAmount']?.toString() ?? '0';
    final withdrawalAmount = json['settleAmount']?.toString() ?? '0';
    final status = json['status']?.toString() ?? 'wait';
    final depositMin = json['depositMin']?.toString() ?? '0';
    final depositMax = json['depositMax']?.toString() ?? '0';
    final rate = json['rate']?.toString() ?? '0';
    final refundAddress = json['refundAddress']?.toString();
    final refundExtraId = json['refundMemo']?.toString();
    final timestamp = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;

    final expiresAt = json['expiresAt'] != null
        ? DateTime.tryParse(json['expiresAt'].toString())?.millisecondsSinceEpoch
        : null;

    return SwapOrder(
      id: json['id']?.toString() ?? '',
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: depositAddress,
      depositExtraId: depositExtraId,
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp: timestamp,
      withdrawalAddress: withdrawalAddress,
      depositMin: depositMin,
      depositMax: depositMax,
      rate: rate,
      refundAddress: refundAddress ?? '',
      refundExtraId: refundExtraId,
      expiresAt: expiresAt,
    );
  }

  SwapOrder copyWith({
    String? id,
    String? coinFrom,
    String? networkFrom,
    String? coinTo,
    String? networkTo,
    String? depositAddress,
    String? depositExtraId,
    String? depositAmount,
    String? withdrawalAmount,
    String? status,
    int? timestamp,
    String? withdrawalAddress,
    String? depositMin,
    String? depositMax,
    String? rate,
    String? refundAddress,
    String? refundExtraId,
    String? provider,
    String? providerToken,
    String? walletId,
    int? expiresAt,
    String? purchaseSource,
    String? purchaseFiatUsd,
    String? operationId,
    String? routeVersion,
    String? activityDirection,
  }) {
    return SwapOrder(
      id: id ?? this.id,
      coinFrom: coinFrom ?? this.coinFrom,
      networkFrom: networkFrom ?? this.networkFrom,
      coinTo: coinTo ?? this.coinTo,
      networkTo: networkTo ?? this.networkTo,
      depositAddress: depositAddress ?? this.depositAddress,
      depositExtraId: depositExtraId ?? this.depositExtraId,
      depositAmount: depositAmount ?? this.depositAmount,
      withdrawalAmount: withdrawalAmount ?? this.withdrawalAmount,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      withdrawalAddress: withdrawalAddress ?? this.withdrawalAddress,
      depositMin: depositMin ?? this.depositMin,
      depositMax: depositMax ?? this.depositMax,
      rate: rate ?? this.rate,
      refundAddress: refundAddress ?? this.refundAddress,
      refundExtraId: refundExtraId ?? this.refundExtraId,
      provider: provider ?? this.provider,
      providerToken: providerToken ?? this.providerToken,
      walletId: walletId ?? this.walletId,
      expiresAt: expiresAt ?? this.expiresAt,
      purchaseSource: purchaseSource ?? this.purchaseSource,
      purchaseFiatUsd: purchaseFiatUsd ?? this.purchaseFiatUsd,
      operationId: operationId ?? this.operationId,
      routeVersion: routeVersion ?? this.routeVersion,
      activityDirection: activityDirection ?? this.activityDirection,
    );
  }

  String get statusLabel {
    if (cashAppPaymentWindowClosed) return 'Payment window ended';
    if (isCashAppPurchase && kCashAppUnpaidStatuses.contains(status)) {
      return 'Awaiting payment';
    }
    switch (status) {
      case 'wait':
        return 'Awaiting Deposit';
      case 'confirmation':
        return 'Confirming';
      case 'exchanging':
        return 'Exchanging';
      case 'sending':
        return 'Sending';
      case 'success':
        return 'Completed';
      case 'overdue':
        return 'Overdue';
      case 'refunded':
        return 'Refunded';
      case 'emergency':
        return 'Emergency';
      case 'expired':
        return 'Expired';
      // Raw provider spellings saved by older builds
      case 'pending':
        return 'Confirming';
      case 'processing':
        return 'Exchanging';
      case 'review':
        return 'Under Review';
      case 'settling':
        return 'Sending';
      case 'settled':
        return 'Completed';
      default:
        return status;
    }
  }

  bool get isComplete => status == 'success' || status == 'settled';
  bool get isPending {
    // Nothing updates a retired provider's order any more, so it is never
    // shown as in flight (see [isUntrackedLegacyOrder]).
    if (isRetiredProvider) return false;
    // An unfulfilled Orchestra order needs reconciliation, not a progress
    // spinner. This does not authorize a retry or claim that funds returned.
    if (isOrchestra && status == 'unfulfilled') return false;
    if (cashAppPaymentWindowClosed) return false;
    if (isExpired) return false;
    return const [
      'wait',
      'confirmation',
      'exchanging',
      'sending',
      'pending',
      'processing',
      'review',
      'settling',
      'waiting',
      'multiple',
      'overdue',
      'unfulfilled',
    ].contains(status);
  }

  bool get isExpired {
    if (status == 'expired' || status == 'canceled') return true;
    // A purchase invoice expiring doesn't prove a payment wasn't received.
    // Show its closed payment window separately and keep reconciling status.
    if (isCashAppPurchase) return false;
    if (status == 'wait') {
      // Explicit expiry time
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch > expiresAt!) return true;
      // No expiresAt — treat as expired if created over 2 hours ago
      if (expiresAt == null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > 2 * 60 * 60 * 1000) return true;
      }
    }
    return false;
  }

  int? get cashAppExpiresAt => !isCashAppPurchase
      ? null
      : expiresAt ??
          cashAppInvoiceExpiry(depositAddress)?.millisecondsSinceEpoch;

  /// Provider-reported 'unfulfilled' confirms the quote expired, even when
  /// the local clock is behind or no deadline is known. Paid, refunding and
  /// terminal states never close the window.
  bool get cashAppPaymentWindowClosed {
    if (!isCashAppPurchase || !kCashAppUnpaidStatuses.contains(status)) {
      return false;
    }
    if (status == 'unfulfilled') return true;
    final expiry = cashAppExpiresAt;
    return expiry != null && DateTime.now().millisecondsSinceEpoch >= expiry;
  }

  /// When an unpaid purchase's payment window closed, to pace
  /// reconciliation. Provider-confirmed expiry with no known deadline falls
  /// back to the order's creation time.
  int? get cashAppWindowClosedAt =>
      cashAppPaymentWindowClosed ? cashAppExpiresAt ?? timestamp : null;

  /// Keep paid/refunding and unknown provider states reconciling. A locally
  /// closed invoice window must never remove the order from status polling.
  bool get shouldPollOrchestra =>
      isOrchestra &&
      !isStuckStandingDeposit &&
      !const ['success', 'settled', 'refunded', 'expired', 'canceled']
          .contains(status);

  /// An Activity row for money that reached a reusable deposit address
  /// and never became an order (below the minimum, the wrong asset, and
  /// the like), so it waits to be returned. It has no order id to poll:
  /// background sync's standing sweep keeps it current from the
  /// provider's deposit listing, and its details offer the refund.
  bool get isStuckStandingDeposit =>
      id.startsWith(kStuckStandingDepositRowPrefix);

  /// The provider's deposit id behind a stuck-deposit row, else null.
  String? get stuckStandingDepositId => isStuckStandingDeposit
      ? id.substring(kStuckStandingDepositRowPrefix.length)
      : null;
}

class SwapOrdersNotifier extends StateNotifier<List<SwapOrder>> {
  SwapOrdersNotifier() : super([]) {
    _loadExchanges();
  }

  SwapOrder getExchangeById(String id) {
    return state.firstWhere((exchange) => exchange.id == id, orElse: () => throw 'Exchange not found');
  }

  Future<void> _loadExchanges() async {
    final box = await Hive.openBox<SwapOrder>(kSwapOrdersBoxName);
    box.watch().listen((event) => _updateExchanges());
    _updateExchanges();
  }

  void _updateExchanges() {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    final exchanges = box.values.toList();
    exchanges.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = exchanges;
  }

  Future<void> addExchange(SwapOrder exchange) async {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    await box.put(exchange.id, exchange);
    _updateExchanges();
  }

  Future<void> updateExchange(SwapOrder updatedExchange) async {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    await box.put(updatedExchange.id, updatedExchange);
    _updateExchanges();
  }

  Future<void> deleteExchange(String id) async {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    await box.delete(id);
    _updateExchanges();
  }

  /// Drop every exchange that belonged to [walletId]. Called on
  /// wallet deletion so a recreated wallet doesn't inherit the prior
  /// wallet's USDC↔BTC swap history (which would otherwise reconstruct
  /// a non-zero past USDC balance against the new wallet's $0 today).
  Future<void> deleteAllForWallet(String walletId) async {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      final ex = box.get(key);
      if (ex != null && ex.walletId == walletId) toDelete.add(key);
    }
    if (toDelete.isEmpty) return;
    await box.deleteAll(toDelete);
    _updateExchanges();
  }

  Future<void> mergeExchange(SwapOrder serverData) async {
    final box = Hive.box<SwapOrder>(kSwapOrdersBoxName);
    final existing = box.get(serverData.id);

    if (existing == null) {
      await box.put(serverData.id, serverData);
      _updateExchanges();
      return;
    }

    final updated = existing.copyWith(
      coinFrom: serverData.coinFrom,
      networkFrom: serverData.networkFrom,
      coinTo: serverData.coinTo,
      networkTo: serverData.networkTo,
      depositAddress: serverData.depositAddress,
      depositExtraId: serverData.depositExtraId,
      depositAmount: serverData.depositAmount,
      withdrawalAmount: serverData.withdrawalAmount,
      status: serverData.status,
      timestamp: serverData.timestamp,
      withdrawalAddress: serverData.withdrawalAddress,
      depositMin: serverData.depositMin,
      depositMax: serverData.depositMax,
      rate: serverData.rate,
      refundAddress: serverData.refundAddress,
      refundExtraId: serverData.refundExtraId,
    );

    await box.put(serverData.id, updated);
    _updateExchanges();
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}
