class OrchestraEstimate {
  final String estimatedOut;
  final String feeAmount;
  final int feeBps;
  final List<String> route;
  final bool hasFeeRate;
  final int? kuteAppFeeBps;

  /// Referee discount (bps) the backend already subtracted from
  /// [kuteAppFeeBps] for this session. Display only.
  final int kuteReferralDiscountBps;
  final int? feePolicyRevision;
  final bool? estimateIncludesAppFee;

  /// Route fees are denominated in feeAssetDetails, which can differ from both
  /// endpoints. feeBps is only the platform rate, not the complete route cost.
  final String? totalFeeAmount;
  final String? totalFeeAmountUsd;
  final String? feeAsset;
  final OrchestraEstimateAsset? feeAssetDetails;
  final OrchestraEstimateAsset? source;
  final OrchestraEstimateAsset? destination;

  OrchestraEstimate({
    required this.estimatedOut,
    required this.feeAmount,
    required this.feeBps,
    required this.route,
    this.hasFeeRate = true,
    this.kuteAppFeeBps,
    this.kuteReferralDiscountBps = 0,
    this.feePolicyRevision,
    this.estimateIncludesAppFee,
    this.totalFeeAmount,
    this.totalFeeAmountUsd,
    this.feeAsset,
    this.feeAssetDetails,
    this.source,
    this.destination,
  });

  factory OrchestraEstimate.fromJson(Map<String, dynamic> json, {Map<String, String> headers = const {}}) {
    final normalized = headers.map((key, value) => MapEntry(key.toLowerCase(), value));
    final included = normalized['x-kute-estimate-includes-app-fee'];
    return OrchestraEstimate(
      kuteAppFeeBps: int.tryParse(normalized['x-kute-app-fee-bps'] ?? ''),
      kuteReferralDiscountBps:
          (int.tryParse(normalized['x-kute-referral-discount-bps'] ?? '') ?? 0)
              .clamp(0, 10000),
      feePolicyRevision: int.tryParse(normalized['x-kute-fee-policy-revision'] ?? ''),
      estimateIncludesAppFee: included == 'true' ? true : included == 'false' ? false : null,
      estimatedOut: json['estimatedOut']?.toString() ?? '0',
      totalFeeAmount: json['totalFeeAmount']?.toString(),
      totalFeeAmountUsd: json['totalFeeAmountUsd']?.toString(),
      feeAsset: json['feeAsset']?.toString(),
      feeAssetDetails: OrchestraEstimateAsset.fromJson(json['feeAssetDetails']),
      source: OrchestraEstimateAsset.fromJson(json['source']),
      destination: OrchestraEstimateAsset.fromJson(json['destination']),
      feeAmount: json['feeAmount']?.toString() ?? '0',
      feeBps: int.tryParse('${json['feeBps']}') ?? 0,
      hasFeeRate: int.tryParse('${json['feeBps']}') != null &&
          (int.tryParse('${json['feeBps']}') ?? -1) >= 0,
      route: (json['route'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Display metadata for a quote amount; never used to choose signing units.
class OrchestraEstimateAsset {
  const OrchestraEstimateAsset(
      {required this.chain, required this.asset, required this.decimals});
  final String chain, asset;
  final int decimals;

  static OrchestraEstimateAsset? fromJson(Object? value) {
    if (value is! Map || value['chain'] is! String || value['asset'] is! String) {
      return null;
    }
    final decimals = int.tryParse('${value['decimals']}');
    if (decimals == null || decimals < 0 || decimals > 36) return null;
    return OrchestraEstimateAsset(
        chain: value['chain'] as String,
        asset: value['asset'] as String,
        decimals: decimals);
  }
}

class OrchestraOnrampResponse {
  final String orderId;
  final String quoteId;
  final String depositAddress;
  final OrchestraPaymentLinks paymentLinks;
  final String amountIn;
  final String estimatedOut;
  final String expiresAt;

  OrchestraOnrampResponse({
    required this.orderId,
    required this.quoteId,
    required this.depositAddress,
    required this.paymentLinks,
    required this.amountIn,
    required this.estimatedOut,
    required this.expiresAt,
  });

  factory OrchestraOnrampResponse.fromJson(Map<String, dynamic> json) {
    return OrchestraOnrampResponse(
      orderId: json['orderId']?.toString() ?? '',
      quoteId: json['quoteId']?.toString() ?? '',
      depositAddress: json['depositAddress']?.toString() ?? '',
      paymentLinks: OrchestraPaymentLinks.fromJson(
        json['paymentLinks'] as Map<String, dynamic>? ?? {},
      ),
      amountIn: json['amountIn']?.toString() ?? '0',
      estimatedOut: json['estimatedOut']?.toString() ?? '0',
      expiresAt: json['expiresAt']?.toString() ?? '',
    );
  }
}

class OrchestraPaymentLinks {
  final String cashApp;
  final String shortUrl;

  OrchestraPaymentLinks({required this.cashApp, required this.shortUrl});

  factory OrchestraPaymentLinks.fromJson(Map<String, dynamic> json) {
    return OrchestraPaymentLinks(
      cashApp: json['cashApp']?.toString() ?? '',
      shortUrl: json['shortUrl']?.toString() ?? '',
    );
  }
}

class OrchestraOrder {
  final String id;
  final String status;
  final String? quoteId;
  final String? sourceChain;
  final String? sourceAsset;
  final String? destinationChain;
  final String? destinationAsset;
  final String? amountIn;
  final String? amountOut;
  final String? recipientAddress;
  final String? depositAddress;
  final String createdAt;
  final String? updatedAt;
  final String? completedAt;
  final String? expiresAt;
  final bool? paymentReceived;

  /// The reply carried a null `order`: no order exists for the id yet. The
  /// envelope's status, expiry and payment evidence are still read.
  final bool orderMissing;

  OrchestraOrder({
    required this.id,
    required this.status,
    this.quoteId,
    this.sourceChain,
    this.sourceAsset,
    this.destinationChain,
    this.destinationAsset,
    this.amountIn,
    this.amountOut,
    this.recipientAddress,
    this.depositAddress,
    required this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.expiresAt,
    this.paymentReceived,
    this.orderMissing = false,
  });

  bool get isTerminal => [
        'completed',
        'complete',
        'success',
        'settled',
        'done',
        'failed',
        'refunded',
        'expired',
        'cancelled',
        'canceled'
      ].contains(status.trim().toLowerCase());

  factory OrchestraOrder.fromJson(Map<String, dynamic> json) {
    final envelopeExpiry = json['expiresAt'];
    final envelopePaymentReceived = json['paymentReceived'];
    final orderMissing = json.containsKey('order') && json['order'] == null;
    // Flashnet wraps the response in an "order" key
    if (json.containsKey('order') && json['order'] is Map<String, dynamic>) {
      json = json['order'] as Map<String, dynamic>;
    }
    // Flashnet nests the delivery target under `destination` on its
    // pay-link and liquidation objects; read the same shape here so a
    // status payload that only carries the nested form still exposes
    // the order's real recipient and chain. Top-level keys win.
    final dest = json['destination'] is Map<String, dynamic>
        ? json['destination'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return OrchestraOrder(
      // Match OrchestraSubmitResponse's fallback chain — Flashnet has
      // returned the order id under `id` OR `orderId` depending on the
      // endpoint/version. Reading only `id` left the status poll with an
      // empty order id, so the q_→ord_ swap below never fired and the row
      // stayed stuck on the quote id.
      id: (json['id'] ?? json['orderId'] ?? '').toString(),
      status: json['status']?.toString() ?? '',
      quoteId: json['quoteId']?.toString(),
      sourceChain: json['sourceChain']?.toString(),
      sourceAsset: json['sourceAsset']?.toString(),
      destinationChain: (json['destinationChain'] ?? dest['chain'])?.toString(),
      destinationAsset: (json['destinationAsset'] ?? dest['asset'])?.toString(),
      amountIn: json['amountIn']?.toString(),
      amountOut: json['amountOut']?.toString(),
      depositAddress: json['depositAddress']?.toString(),
      recipientAddress: (json['recipientAddress'] ??
              dest['address'] ??
              json['destinationAddress'])
          ?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString(),
      completedAt: json['completedAt']?.toString(),
      expiresAt: (envelopeExpiry ?? json['expiresAt'])?.toString(),
      paymentReceived:
          (envelopePaymentReceived ?? json['paymentReceived']) == true
              ? true
              : null,
      orderMissing: orderMissing,
    );
  }
}

class OrchestraQuote {
  final String quoteId;
  final String depositAddress;
  final String amountIn;
  final String estimatedOut;
  final String feeAmount;
  final int feeBps;
  final int? appFeeBps;
  /// The bounded quoted rate includes both provider and known app fees.
  int get combinedFeeBps => feeBps + (appFeeBps ?? 0);
  final List<String> route;
  final String expiresAt;
  final String? depositMemo;
  final String? totalFeeAmount;
  final String? feeAsset;
  final String? priceLockMode;
  final String? lockedMinAmountOut;

  /// Undocumented echoes of the request. Flashnet's quote docs list none
  /// of these, so guards compare them only when the response carries them.
  final String? sourceChain;
  final String? sourceAsset;
  final String? destinationChain;
  final String? destinationAsset;
  final String? recipientAddress;
  final String? refundAddress;

  /// Top-level response keys that carried a non-null value, so a guard
  /// can tell an absent field from a defaulted one.
  final Set<String> present;

  OrchestraQuote({
    required this.quoteId,
    required this.depositAddress,
    required this.amountIn,
    required this.estimatedOut,
    required this.feeAmount,
    required this.feeBps,
    this.appFeeBps,
    required this.route,
    required this.expiresAt,
    this.depositMemo,
    this.totalFeeAmount,
    this.feeAsset,
    this.priceLockMode,
    this.lockedMinAmountOut,
    this.sourceChain,
    this.sourceAsset,
    this.destinationChain,
    this.destinationAsset,
    this.recipientAddress,
    this.refundAddress,
    this.present = const {},
  });

  static final RegExp _unsignedInteger = RegExp(r'^\d+$');

  /// Integral numbers or unsigned integer strings only; anything else is
  /// treated as absent so the fee cap refuses it.
  static int? _parseFeeBps(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) {
      return raw.isFinite && raw == raw.truncateToDouble() ? raw.toInt() : null;
    }
    if (raw is String && _unsignedInteger.hasMatch(raw.trim())) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  factory OrchestraQuote.fromJson(Map<String, dynamic> json) {
    final feeBps = _parseFeeBps(json['feeBps']);
    final appFees = json['appFees'];
    int? appFeeBps;
    if (appFees is List) {
      var sum = 0;
      var valid = true;
      for (final entry in appFees) {
        final rate = entry is Map ? _parseFeeBps(entry['feeBps']) : null;
        if (rate == null || rate < 0 || rate > 9999) { valid = false; break; }
        sum += rate;
      }
      if (valid && sum <= 9999) appFeeBps = sum;
    }
    return OrchestraQuote(
      quoteId: json['quoteId']?.toString() ?? '',
      depositAddress: json['depositAddress']?.toString() ?? '',
      amountIn: json['amountIn']?.toString() ?? '0',
      estimatedOut: json['estimatedOut']?.toString() ?? '0',
      feeAmount: json['feeAmount']?.toString() ?? '0',
      feeBps: feeBps ?? 0,
      appFeeBps: appFeeBps,
      route: (json['route'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      expiresAt: json['expiresAt']?.toString() ?? '',
      depositMemo: json['depositMemo']?.toString(),
      totalFeeAmount: json['totalFeeAmount']?.toString(),
      feeAsset: json['feeAsset']?.toString(),
      priceLockMode: json['priceLockMode']?.toString(),
      lockedMinAmountOut: json['lockedMinAmountOut']?.toString(),
      sourceChain: json['sourceChain']?.toString(),
      sourceAsset: json['sourceAsset']?.toString(),
      destinationChain: json['destinationChain']?.toString(),
      destinationAsset: json['destinationAsset']?.toString(),
      recipientAddress: json['recipientAddress']?.toString(),
      refundAddress: json['refundAddress']?.toString(),
      present: {
        for (final entry in json.entries)
          if (entry.value != null && (entry.key != 'feeBps' || feeBps != null))
            entry.key,
      },
    );
  }
}

class OrchestraSubmitResponse {
  final String orderId;
  final String status;

  OrchestraSubmitResponse({required this.orderId, required this.status});

  factory OrchestraSubmitResponse.fromJson(Map<String, dynamic> json) {
    // Flashnet's `/submit` response wraps the order under an `order` key
    // (same shape as `/status`). The previous parser only looked for a
    // top-level `orderId` field which doesn't exist — so every submit
    // appeared to return an empty orderId, and downstream callers fell
    // back to the quote id (`q_…`). That ended up in the exchange
    // record and produced the broken `…/explorer/ord_q_…` URL on the
    // "View on Orchestra" button. Read the wrapped `id` first; fall
    // back to the legacy field names so old responses still parse.
    final inner = json['order'] is Map<String, dynamic>
        ? json['order'] as Map<String, dynamic>
        : json;
    return OrchestraSubmitResponse(
      orderId: (inner['id'] ??
              inner['orderId'] ??
              json['id'] ??
              json['orderId'] ??
              '')
          .toString(),
      status: (inner['status'] ?? json['status'] ?? '').toString(),
    );
  }
}

/// The Kute fee a reusable deposit address charges on what arrives, read
/// from the terms the backend froze onto it (`kuteFeePolicy.appFeeBps`, the
/// published rule with any referral discount already taken off). Null when
/// the terms do not state a positive rate: no policy, provider-default
/// pricing, or no fee. The caller then shows nothing rather than a guess.
int? disclosedKuteFeeBps(Object? kuteFeePolicy) {
  if (kuteFeePolicy is! Map) return null;
  if (kuteFeePolicy['providerDefault'] == true) return null;
  final bps = kuteFeePolicy['appFeeBps'];
  if (bps is! int || bps <= 0 || bps > 9999) return null;
  return bps;
}

class OrchestraAccumulationAddress {
  final String id;
  final String sourceChain;
  final String sourceAsset;
  final String destinationAsset;
  final String recipientSparkAddress;
  final String? depositAddress;
  final String? label;
  final bool enabled;
  final String createdAt;
  final Map<String, dynamic>? kuteFeePolicy;
  int? get feePolicyRevision => kuteFeePolicy?['revision'] is int
      ? kuteFeePolicy!['revision'] as int
      : null;

  /// See [disclosedKuteFeeBps].
  int? get kuteFeeBps => disclosedKuteFeeBps(kuteFeePolicy);

  OrchestraAccumulationAddress({
    required this.id,
    required this.sourceChain,
    required this.sourceAsset,
    required this.destinationAsset,
    required this.recipientSparkAddress,
    this.depositAddress,
    this.label,
    required this.enabled,
    required this.createdAt,
    this.kuteFeePolicy,
  });

  factory OrchestraAccumulationAddress.fromJson(Map<String, dynamic> json) {
    return OrchestraAccumulationAddress(
      id: json['accumulationAddressId']?.toString() ??
          json['id']?.toString() ??
          '',
      sourceChain: json['sourceChain']?.toString() ?? '',
      sourceAsset: json['sourceAsset']?.toString() ?? '',
      destinationAsset: json['destinationAsset']?.toString() ?? '',
      recipientSparkAddress: json['recipientSparkAddress']?.toString() ?? '',
      depositAddress: json['depositAddress']?.toString(),
      label: json['label']?.toString(),
      // Required by Flashnet's AccumulationAddressRecord schema.
      enabled: json['enabled'] == true,
      createdAt: json['createdAt']?.toString() ?? '',
      kuteFeePolicy: json['kuteFeePolicy'] is Map<String, dynamic>
          ? Map<String, dynamic>.unmodifiable(json['kuteFeePolicy'])
          : null,
    );
  }
}

class OrchestraLiquidationAddress {
  final String id;
  final String sparkAddress;
  final String l1DepositAddress;
  final String destinationChain;
  final String destinationAsset;
  final String destinationAddress;
  final String? label;
  final bool enabled;
  final String createdAt;

  OrchestraLiquidationAddress({
    required this.id,
    required this.sparkAddress,
    required this.l1DepositAddress,
    required this.destinationChain,
    required this.destinationAsset,
    required this.destinationAddress,
    this.label,
    required this.enabled,
    required this.createdAt,
  });

  factory OrchestraLiquidationAddress.fromJson(Map<String, dynamic> json) {
    final dest = json['destination'] as Map<String, dynamic>? ?? {};
    return OrchestraLiquidationAddress(
      id: json['liquidationAddressId']?.toString() ??
          json['id']?.toString() ??
          '',
      sparkAddress: json['sparkAddress']?.toString() ?? '',
      l1DepositAddress: json['l1DepositAddress']?.toString() ?? '',
      destinationChain: dest['chain']?.toString() ??
          json['destinationChain']?.toString() ??
          '',
      destinationAsset: dest['asset']?.toString() ??
          json['destinationAsset']?.toString() ??
          '',
      destinationAddress: dest['address']?.toString() ??
          json['destinationAddress']?.toString() ??
          '',
      label: json['label']?.toString(),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class OrchestraPayLink {
  final String id;
  final String shortId;
  final String shortUrl;
  final String destinationChain;
  final String destinationAsset;
  final String recipientAddress;
  final String amountOut;
  final String? label;
  final bool enabled;
  final String createdAt;

  OrchestraPayLink({
    required this.id,
    required this.shortId,
    required this.shortUrl,
    required this.destinationChain,
    required this.destinationAsset,
    required this.recipientAddress,
    required this.amountOut,
    this.label,
    required this.enabled,
    required this.createdAt,
  });

  factory OrchestraPayLink.fromJson(Map<String, dynamic> json) {
    // Flashnet wraps response in a "payLink" key
    if (json.containsKey('payLink') &&
        json['payLink'] is Map<String, dynamic>) {
      json = json['payLink'] as Map<String, dynamic>;
    }
    final dest = json['destination'] as Map<String, dynamic>? ?? {};
    return OrchestraPayLink(
      id: json['payLinkId']?.toString() ?? json['id']?.toString() ?? '',
      shortId: json['shortId']?.toString() ?? '',
      shortUrl: json['shortUrl']?.toString() ?? json['url']?.toString() ?? '',
      destinationChain: dest['chain']?.toString() ??
          json['destinationChain']?.toString() ??
          '',
      destinationAsset: dest['asset']?.toString() ??
          json['destinationAsset']?.toString() ??
          '',
      recipientAddress: dest['address']?.toString() ??
          json['recipientAddress']?.toString() ??
          '',
      amountOut: json['amountOut']?.toString() ?? '0',
      label: json['label']?.toString(),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
