import 'package:flutter/foundation.dart';

/// Public screen context. Never construct this from account or position data.
/// Only validated public market references and an educational order-type enum
/// can leave the device. Never add account state, order values or trade sides.
@immutable
class AdvisorContext {
  final String surface;
  final String? marketVenue;
  final String? marketId;

  /// Public catalog label for local UI only; never included in request context.
  final String? marketDisplayName;
  final String? orderType;
  final String? submarketId;

  const AdvisorContext({
    required this.surface,
    this.marketVenue,
    this.marketId,
    this.marketDisplayName,
    this.orderType,
    this.submarketId,
  });

  Map<String, String>? get toRequestMarket {
    final id = marketId?.trim();
    if (!const {'hyperliquid', 'polymarket'}.contains(marketVenue) ||
        id == null ||
        id.isEmpty ||
        id.length > 200 ||
        !RegExp(r'^[A-Za-z0-9_:@./-]+$').hasMatch(id) ||
        RegExp(r'^0x[a-fA-F0-9]{40,64}$').hasMatch(id)) {
      return null;
    }
    final valid = marketVenue == 'hyperliquid'
        ? RegExp(
                r'^(?:[A-Za-z0-9_-]{1,24}:)?[A-Za-z0-9_.-]{1,50}$|^@[0-9]{1,8}$|^[A-Za-z0-9_.-]{1,50}/[A-Za-z0-9_.-]{1,50}$')
            .hasMatch(id)
        : RegExp(r'^[a-z0-9][a-z0-9-]{0,159}$').hasMatch(id);
    if (!valid) return null;
    final child = submarketId?.trim();
    return {
      'venue': marketVenue!,
      'id': id,
      if (marketVenue == 'polymarket' &&
          child != null &&
          RegExp(r'^[0-9]{1,20}$').hasMatch(child))
        'submarketId': child,
    };
  }

  static const _orderTypes = {
    'market',
    'limit',
    'scale',
    'stop_market',
    'stop_limit',
    'take_profit_market',
    'take_profit_limit',
    'twap',
  };

  String? get educationalOrderType {
    final value = orderType?.trim().toLowerCase().replaceAll(' ', '_');
    if (toRequestMarket == null || !_orderTypes.contains(value)) {
      return null;
    }
    if (marketVenue == 'polymarket' && value != 'market' && value != 'limit') {
      return null;
    }
    if (isSpot && value != 'market' && value != 'limit') return null;
    return value;
  }

  Map<String, String>? get toRequestEducation => educationalOrderType == null
      ? null
      : {'orderType': educationalOrderType!};

  /// The public ticker of a Hyperliquid market, for local chip text only.
  /// Null for Polymarket (its screens say "this market") and for a spot
  /// pair with no catalogue name.
  String? get publicMarketLabel {
    final market = toRequestMarket;
    if (market == null || marketVenue != 'hyperliquid') return null;
    final name = marketDisplayName?.trim();
    if (name != null && name.isNotEmpty && !name.startsWith('@')) return name;
    final id = market['id']!;
    return id.startsWith('@') ? null : id.split(':').last;
  }

  @override
  bool operator ==(Object other) =>
      other is AdvisorContext &&
      surface == other.surface &&
      mapEquals(toRequestMarket, other.toRequestMarket) &&
      educationalOrderType == other.educationalOrderType;

  @override
  int get hashCode => Object.hash(
      surface,
      toRequestMarket?['venue'],
      toRequestMarket?['id'],
      toRequestMarket?['submarketId'],
      educationalOrderType);

  bool get isSpot =>
      marketVenue == 'hyperliquid' &&
      ((marketId?.trim().startsWith('@') ?? false) ||
          (marketId?.trim().contains('/') ?? false));
}
