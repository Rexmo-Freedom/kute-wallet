// lib/models/share_link_model.dart
//
// SHARE LINKS: SEND TO ANYONE. A share link is a PENDING SEND. The money
// stays in the sender's wallet until the recipient opens the link and
// claims it with a destination from their own Kute wallet; then the
// sender's app pays that destination the next time it opens
// (`services/share_link_claims.dart`). Nothing moves when the link is
// created, so a link nobody claims costs nothing and a cancelled link
// never has to be refunded.
//
// The backend (`/api/v1/share/links`, branch `share-links`) holds the
// link rows; the app keeps the sender's own pending links locally
// (`services/share_links_store.dart`) so the receipt row and the Cancel
// action work offline and the pay-on-open pass knows which links are
// its own.
//
// Amounts are `amountMinor`: SATOSHIS for bitcoin and CENTS for dollars.
// The dollar token itself has six decimals on Spark; the conversion to
// its base units happens once, at payment time
// (`ShareLinkKind.dollars` -> `amountMinor * 10_000`), and never in copy.

import 'package:flutter/foundation.dart' show immutable;

/// Which balance the link is paid from. The wire value is `name`.
enum ShareLinkKind {
  bitcoin('BTC'),
  dollars('USDB');

  const ShareLinkKind(this.asset);

  /// The asset the backend expects for this kind.
  final String asset;

  static ShareLinkKind? tryParse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// A link's life on the backend. `unknown` is any value this build does
/// not know, kept as the raw string in [ShareLink.rawStatus].
enum ShareLinkStatus {
  open,
  claimed,
  paid,
  cancelled,
  expired,
  unknown;

  static ShareLinkStatus parse(Object? raw) {
    for (final s in values) {
      if (s != unknown && s.name == raw) return s;
    }
    return unknown;
  }
}

/// `GET /api/v1/share/links/{id}`: what a recipient (or the sender) sees.
@immutable
class ShareLink {
  const ShareLink({
    required this.id,
    required this.kind,
    required this.amountMinor,
    this.marketSlug,
    this.senderLabel,
    this.referralCode,
    required this.status,
    required this.rawStatus,
    this.expiresAt,
  });

  final String id;
  final ShareLinkKind kind;
  final int amountMinor;
  final String? marketSlug;
  final String? senderLabel;
  final String? referralCode;
  final ShareLinkStatus status;
  final String rawStatus;
  final DateTime? expiresAt;

  String get asset => kind.asset;

  /// Whether a recipient can still claim it.
  bool get claimable =>
      status == ShareLinkStatus.open &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  static ShareLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ShareLinkKind.tryParse(json['kind']);
    final id = json['id'];
    final amount = _int(json['amountMinor']);
    if (kind == null || id is! String || id.isEmpty || amount == null) {
      return null;
    }
    return ShareLink(
      id: id,
      kind: kind,
      amountMinor: amount,
      marketSlug: _string(json['marketSlug']),
      senderLabel: _string(json['senderLabel']),
      referralCode: _string(json['referralCode']),
      status: ShareLinkStatus.parse(json['status']),
      rawStatus: '${json['status'] ?? ''}',
      expiresAt: _date(json['expiresAt']),
    );
  }
}

/// `POST /api/v1/share/links`: the created link.
@immutable
class CreatedShareLink {
  const CreatedShareLink({required this.id, required this.url, this.expiresAt});

  final String id;
  final String url;
  final DateTime? expiresAt;

  static CreatedShareLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final url = json['url'];
    if (id is! String || id.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    return CreatedShareLink(
        id: id, url: url, expiresAt: _date(json['expiresAt']));
  }
}

/// `GET /api/v1/share/links/mine?status=claimed`: a link of this wallet
/// the recipient claimed, with where to pay.
@immutable
class ClaimedShareLink {
  const ClaimedShareLink({
    required this.id,
    required this.kind,
    required this.amountMinor,
    this.marketSlug,
    required this.claimDestination,
    this.claimedAt,
  });

  final String id;
  final ShareLinkKind kind;
  final int amountMinor;
  final String? marketSlug;

  /// A Spark address or a BOLT11 invoice from the recipient's wallet.
  final String claimDestination;
  final DateTime? claimedAt;

  String get asset => kind.asset;

  static ClaimedShareLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ShareLinkKind.tryParse(json['kind']);
    final id = json['id'];
    final amount = _int(json['amountMinor']);
    final destination = _string(json['claimDestination']);
    if (kind == null ||
        id is! String ||
        id.isEmpty ||
        amount == null ||
        destination == null) {
      return null;
    }
    return ClaimedShareLink(
      id: id,
      kind: kind,
      amountMinor: amount,
      marketSlug: _string(json['marketSlug']),
      claimDestination: destination,
      claimedAt: _date(json['claimedAt']),
    );
  }
}

/// A link this wallet created, as the local store keeps it.
@immutable
class PendingShareLink {
  const PendingShareLink({
    required this.id,
    required this.kind,
    required this.amountMinor,
    this.label,
    this.marketSlug,
    required this.url,
    required this.createdAt,
    required this.status,
    this.paymentId,
    this.paidReported = false,
  });

  final String id;
  final ShareLinkKind kind;
  final int amountMinor;

  /// The recipient's first name, as the sender typed it. Optional.
  final String? label;
  final String? marketSlug;

  /// Empty when the link was created on another device (the claim came
  /// from the backend with no local row to match).
  final String url;
  final DateTime createdAt;
  final ShareLinkStatus status;

  /// The Spark payment that paid the claim, kept so `POST /paid` can be
  /// retried when it failed after the money moved. Never a second
  /// payment: a row with a [paymentId] is paid, whatever the backend says.
  final String? paymentId;

  /// Whether the backend has acknowledged [paymentId].
  final bool paidReported;

  String get asset => kind.asset;

  PendingShareLink copyWith({
    ShareLinkStatus? status,
    String? paymentId,
    bool? paidReported,
  }) =>
      PendingShareLink(
        id: id,
        kind: kind,
        amountMinor: amountMinor,
        label: label,
        marketSlug: marketSlug,
        url: url,
        createdAt: createdAt,
        status: status ?? this.status,
        paymentId: paymentId ?? this.paymentId,
        paidReported: paidReported ?? this.paidReported,
      );

  PendingShareLink withStatus(ShareLinkStatus next) => copyWith(status: next);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'asset': asset,
        'amountMinor': amountMinor,
        if (label != null) 'label': label,
        if (marketSlug != null) 'marketSlug': marketSlug,
        'url': url,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.name,
        if (paymentId != null) 'paymentId': paymentId,
        if (paidReported) 'paidReported': true,
      };

  static PendingShareLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ShareLinkKind.tryParse(json['kind']);
    final id = json['id'];
    final amount = _int(json['amountMinor']);
    // Empty for a link created on another device (see [url]).
    final url = json['url'];
    if (kind == null || id is! String || amount == null || url is! String) {
      return null;
    }
    return PendingShareLink(
      id: id,
      kind: kind,
      amountMinor: amount,
      label: _string(json['label']),
      marketSlug: _string(json['marketSlug']),
      url: url,
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      status: ShareLinkStatus.parse(json['status']),
      paymentId: _string(json['paymentId']),
      paidReported: json['paidReported'] == true,
    );
  }
}

/// The dollar token's base units for a cents amount (six decimals on
/// Spark, two in the minor unit). Payment time only.
BigInt dollarsBaseUnitsFromCents(int cents) =>
    BigInt.from(cents) * BigInt.from(10000);

int? _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    return raw.toInt();
  }
  if (raw is String) return int.tryParse(raw);
  return null;
}

String? _string(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

DateTime? _date(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
