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
// A CHALLENGE (founder, 4 November 2026: "entice users on sharing
// predictions to pick the other side") is a prediction link with
// `challenge: true`: the card reads as a dare and the recipient's Claim
// screen offers "Take the other side" beside "Same side as your friend".
// The app sends the flag on create and reads it on the public read, both
// optional (a backend that does not store it yet ignores it and never
// returns it); the shared URL carries it too as `?challenge=1`
// ([kShareChallengeQuery]), which an older build ignores (it reads the
// id from the path only).
//
// Amounts are `amountMinor`: SATOSHIS for bitcoin and CENTS for dollars.
// The dollar token itself has six decimals on Spark; the conversion to
// its base units happens once, at payment time
// (`ShareLinkKind.dollars` -> `amountMinor * 10_000`), and never in copy.

import 'package:flutter/foundation.dart' show immutable;

import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyStepGraph, MoneyStepStatus;

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

/// The query parameter a challenge link's URL carries (`?challenge=1`),
/// and the OneLink's `deep_link_sub2` value for one.
const String kShareChallengeQuery = 'challenge';

/// [url] with the challenge flag (`?challenge=1`) added; [url] as it is
/// when it cannot be read or is empty (a link created on another device).
String shareChallengeUrl(String url) {
  if (url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    kShareChallengeQuery: '1',
  }).toString();
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
    this.venue,
    this.outcome,
    this.outcomeIndex,
    this.side,
    this.senderLabel,
    this.referralCode,
    required this.status,
    required this.rawStatus,
    this.expiresAt,
    this.challenge = false,
  });

  final String id;
  final ShareLinkKind kind;
  final int amountMinor;
  final String? marketSlug;

  /// The sender dared the recipient to take the other side (see the file
  /// header); false when the backend does not say.
  final bool challenge;

  /// THE PICK the sender put on the link (kute_share_actions.dart): the
  /// venue (`polymarket` | `hyperliquid`), the outcome's label ("Yes", a
  /// candidate, "Long"), its index in the event's outcomes and the side
  /// (`buy`, `long` | `short`). All optional: a plain dollars link has
  /// none, and a backend that does not send them yet reads as none.
  final String? venue;
  final String? outcome;
  final int? outcomeIndex;
  final String? side;
  final String? senderLabel;
  final String? referralCode;
  final ShareLinkStatus status;
  final String rawStatus;
  final DateTime? expiresAt;

  String get asset => kind.asset;

  /// Whether the link carries a pick to place after the claim.
  bool get hasPick => outcome != null && outcome!.isNotEmpty;

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
      venue: _string(json['venue']),
      outcome: _string(json['outcome']),
      outcomeIndex: _int(json['outcomeIndex']),
      side: _string(json['side']),
      senderLabel: _string(json['senderLabel']),
      referralCode: _string(json['referralCode']),
      status: ShareLinkStatus.parse(json['status']),
      rawStatus: '${json['status'] ?? ''}',
      expiresAt: _date(json['expiresAt']),
      challenge: json['challenge'] == true,
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
    this.marketTitle,
    this.venue,
    this.outcome,
    required this.url,
    required this.createdAt,
    required this.status,
    this.paymentId,
    this.paidReported = false,
    this.recipientPhone,
    this.challenge = false,
    this.funding,
  });

  final String id;
  final ShareLinkKind kind;
  final int amountMinor;

  /// What the sender's "Send now" moved into Dollars to pay this link
  /// (services/one_balance/gift_funding.dart): the same row as [paymentId],
  /// so a restart knows a leg already went and never sends it again.
  final GiftFundingRecord? funding;

  /// A challenge (see the file header): [url] carries the flag already.
  final bool challenge;

  /// The recipient's first name, as the sender typed it (or the contact
  /// picked on the Send screen). Optional.
  final String? label;

  /// The picked contact's number, LOCAL ONLY: never sent to the backend
  /// or to analytics. It is what "Send again via WhatsApp / SMS" opens
  /// the OS intent with (screens/share/pending_share_links.dart).
  final String? recipientPhone;
  final String? marketSlug;

  /// The pick on the link, as the share text says it: the market's title,
  /// the venue and the outcome's label (see [ShareLink.outcome]).
  final String? marketTitle;
  final String? venue;
  final String? outcome;

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
    GiftFundingRecord? funding,
  }) =>
      PendingShareLink(
        id: id,
        kind: kind,
        amountMinor: amountMinor,
        label: label,
        marketSlug: marketSlug,
        marketTitle: marketTitle,
        venue: venue,
        outcome: outcome,
        url: url,
        createdAt: createdAt,
        status: status ?? this.status,
        paymentId: paymentId ?? this.paymentId,
        paidReported: paidReported ?? this.paidReported,
        recipientPhone: recipientPhone,
        challenge: challenge,
        funding: funding ?? this.funding,
      );

  PendingShareLink withStatus(ShareLinkStatus next) => copyWith(status: next);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'asset': asset,
        'amountMinor': amountMinor,
        if (label != null) 'label': label,
        if (marketSlug != null) 'marketSlug': marketSlug,
        if (marketTitle != null) 'marketTitle': marketTitle,
        if (venue != null) 'venue': venue,
        if (outcome != null) 'outcome': outcome,
        'url': url,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.name,
        if (paymentId != null) 'paymentId': paymentId,
        if (paidReported) 'paidReported': true,
        if (recipientPhone != null) 'recipientPhone': recipientPhone,
        if (challenge) 'challenge': true,
        if (funding != null) 'funding': funding!.toJson(),
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
      marketTitle: _string(json['marketTitle']),
      venue: _string(json['venue']),
      outcome: _string(json['outcome']),
      url: url,
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      status: ShareLinkStatus.parse(json['status']),
      paymentId: _string(json['paymentId']),
      paidReported: json['paidReported'] == true,
      recipientPhone: _string(json['recipientPhone']),
      challenge: json['challenge'] == true,
      funding: GiftFundingRecord.fromJson(json['funding']),
    );
  }
}

/// The money "Send now" moved into Dollars for one link
/// (services/one_balance/gift_funding.dart), kept on the link's own row so
/// the payment id and the funding share one idempotent record. Local only:
/// never tracked, never logged.
@immutable
class GiftFundingRecord {
  const GiftFundingRecord({
    required this.steps,
    required this.startedAt,
    this.landsUsd = const {},
    this.moveId,
    this.reason,
  });

  /// Every leg and the send itself (the leg's `ref`, its quote then order
  /// id, is what a restart follows).
  final MoneyStepGraph steps;

  /// What each leg lands in Dollars, by step id.
  final Map<String, double> landsUsd;

  /// The venue legs' move (`MultiSourceMove`), for its Activity row.
  final String? moveId;

  /// Why the last attempt stopped (a fixed code, never shown).
  final String? reason;
  final DateTime startedAt;

  /// Whether a leg of this record is, or may still be, on its way.
  bool get onItsWay => steps.legs.any((s) =>
      s.id != kGiftFundingSendId && s.status == MoneyStepStatus.running);

  GiftFundingRecord copyWith({
    MoneyStepGraph? steps,
    Map<String, double>? landsUsd,
    String? moveId,
    String? reason,
    bool clearReason = false,
  }) =>
      GiftFundingRecord(
        steps: steps ?? this.steps,
        startedAt: startedAt,
        landsUsd: landsUsd ?? this.landsUsd,
        moveId: moveId ?? this.moveId,
        reason: clearReason ? null : reason ?? this.reason,
      );

  Map<String, Object?> toJson() => {
        'steps': steps.toJson(),
        'startedAt': startedAt.millisecondsSinceEpoch,
        if (landsUsd.isNotEmpty) 'landsUsd': landsUsd,
        if (moveId != null) 'moveId': moveId,
        if (reason != null) 'reason': reason,
      };

  static GiftFundingRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['startedAt'];
    if (at is! int) return null;
    final lands = raw['landsUsd'];
    return GiftFundingRecord(
      steps: MoneyStepGraph.fromJson(raw['steps']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(at),
      landsUsd: {
        if (lands is Map)
          for (final e in lands.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toDouble(),
      },
      moveId: _string(raw['moveId']),
      reason: _string(raw['reason']),
    );
  }
}

/// The send's own step in a [GiftFundingRecord]'s graph
/// (`MoveSteps.sendId`).
const String kGiftFundingSendId = 'send';

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
