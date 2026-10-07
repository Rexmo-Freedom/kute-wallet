// Data models for past Outlogic fiat orders. The Outlogic on/off ramp
// itself was removed (bank transfers are coming soon via a new rail);
// [OutlogicOrder] and [OutlogicTrade] remain because previously
// persisted orders (Hive box 'outlogicOrders' + the wallet transaction
// cache) still render as fiat rows in the user's transaction history.

class OutlogicTrade {
  final double fromAmount;
  final String fromAsset;
  final double toAmount;
  final String toAsset;
  final double feeAmount;
  final double price;
  final String timestamp;

  OutlogicTrade({
    required this.fromAmount,
    required this.fromAsset,
    required this.toAmount,
    required this.toAsset,
    required this.feeAmount,
    required this.price,
    required this.timestamp,
  });

  factory OutlogicTrade.fromJson(Map<String, dynamic> json) {
    return OutlogicTrade(
      fromAmount: double.tryParse(json['from_amount']?.toString() ?? '0') ?? 0,
      fromAsset: json['from_asset']?.toString() ?? '',
      toAmount: double.tryParse(json['to_amount']?.toString() ?? '0') ?? 0,
      toAsset: json['to_asset']?.toString() ?? '',
      feeAmount: double.tryParse(json['fee_amount']?.toString() ?? '0') ?? 0,
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0,
      timestamp: json['timestamp']?.toString() ?? '',
    );
  }
}

class OutlogicOrder {
  final String id;
  final String status;
  final String email;
  final String depositCryptoAddress;
  final double fromAmount;
  final String fromAsset;
  final String toAsset;
  final String destinationType;
  final String destinationCryptoAddress;
  final String? destinationBankAddress;
  final String? destinationBankName;
  final String? destinationBankAccountNumber;
  final String createdAt;
  final String? expiresAt;
  final OutlogicTrade? trade;
  // SEPA deposit details (returned by API on order creation)
  final String? transferCode;
  final String? depositSepaAddress;
  final String? depositSepaBic;
  final String? depositSepaBeneficiary;
  final String? depositSepaBankName;
  /// Local-only — id of the wallet this order was created against.
  /// Used to scope the order's activity row to the wallet whose
  /// address received the BTC: without it, a multi-wallet user would
  /// see every fiat purchase across every wallet's activity feed.
  /// Server doesn't know about this; we tag locally at create time.
  /// Null = legacy order from a build that pre-dated this field;
  /// such rows fall back to the active wallet so they don't vanish.
  final String? walletId;

  OutlogicOrder({
    required this.id,
    required this.status,
    required this.email,
    required this.depositCryptoAddress,
    required this.fromAmount,
    required this.fromAsset,
    required this.toAsset,
    required this.destinationType,
    required this.destinationCryptoAddress,
    this.destinationBankAddress,
    this.destinationBankName,
    this.destinationBankAccountNumber,
    required this.createdAt,
    this.expiresAt,
    this.trade,
    this.transferCode,
    this.depositSepaAddress,
    this.depositSepaBic,
    this.depositSepaBeneficiary,
    this.depositSepaBankName,
    this.walletId,
  });

  factory OutlogicOrder.fromJson(Map<String, dynamic> json) {
    return OutlogicOrder(
      id: json['id']?.toString() ?? '',
      // Normalize status casing/whitespace at the boundary. Outlogic's
      // status casing is NOT guaranteed (the backend's
      // normalizeOutlogicStatus defensively uppercases before matching);
      // every client-side check (isTerminal, the poll's completion
      // detection, the badge, isPending) compares against exact UPPERCASE
      // literals. A lowercase/mixed-case 'completed' from the provider
      // therefore matched nothing on the client, leaving a fully
      // completed order stuck on "Awaiting deposit" forever even though
      // the backend had marked it complete. Uppercase here so all of
      // them agree.
      status: (json['status']?.toString() ?? '').trim().toUpperCase(),
      email: json['email']?.toString() ?? '',
      depositCryptoAddress: json['deposit_crypto_address']?.toString() ?? '',
      fromAmount: double.tryParse(json['from_amount']?.toString() ?? '0') ?? 0,
      fromAsset: json['from_asset']?.toString() ?? '',
      toAsset: json['to_asset']?.toString() ?? '',
      destinationType: json['destination_type']?.toString() ?? '',
      destinationCryptoAddress: json['destination_crypto_address']?.toString() ?? '',
      destinationBankAddress: json['destination_bank_address']?.toString(),
      destinationBankName: json['destination_bank_name']?.toString(),
      destinationBankAccountNumber: json['destination_bank_account_number']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      expiresAt: json['expires_at']?.toString(),
      trade: json['trade'] != null ? OutlogicTrade.fromJson(json['trade'] as Map<String, dynamic>) : null,
      transferCode: json['transfer_code']?.toString(),
      depositSepaAddress: json['deposit_sepa_address']?.toString(),
      depositSepaBic: json['deposit_sepa_bic']?.toString(),
      depositSepaBeneficiary: json['deposit_sepa_beneficiary']?.toString(),
      depositSepaBankName: json['deposit_sepa_bank_name']?.toString(),
      walletId: json['walletId']?.toString(),
    );
  }

  bool get isTerminal => ['COMPLETED', 'DEPOSIT_CONFIRMED', 'DEPOSIT_RECEIVED', 'SETTLED', 'CANCELED', 'EXPIRED', 'REJECTED', 'REFUNDED'].contains(status);
  // Outlogic's pre-deposit status string has appeared as both
  // WAITING_FOR_DEPOSIT and AWAITING_DEPOSIT (the backend's
  // normalizeOutlogicStatus keys on the latter); accept either so the
  // cancel affordance and the "Awaiting Deposit" label don't silently
  // break if the provider flips spelling.
  bool get isCancellable =>
      status == 'WAITING_FOR_DEPOSIT' || status == 'AWAITING_DEPOSIT';

  OutlogicOrder copyWith({String? walletId}) {
    return OutlogicOrder(
      id: id,
      status: status,
      email: email,
      depositCryptoAddress: depositCryptoAddress,
      fromAmount: fromAmount,
      fromAsset: fromAsset,
      toAsset: toAsset,
      destinationType: destinationType,
      destinationCryptoAddress: destinationCryptoAddress,
      destinationBankAddress: destinationBankAddress,
      destinationBankName: destinationBankName,
      destinationBankAccountNumber: destinationBankAccountNumber,
      createdAt: createdAt,
      expiresAt: expiresAt,
      trade: trade,
      transferCode: transferCode,
      depositSepaAddress: depositSepaAddress,
      depositSepaBic: depositSepaBic,
      depositSepaBeneficiary: depositSepaBeneficiary,
      depositSepaBankName: depositSepaBankName,
      walletId: walletId ?? this.walletId,
    );
  }
}
