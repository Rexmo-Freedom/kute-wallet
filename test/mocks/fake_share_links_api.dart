// An in-memory share-links backend for widget and service tests: links
// are created, read, claimed, cancelled and paid against a map, and every
// call is recorded so a test can assert what the app sent.

import 'package:kute/models/share_link_model.dart';
import 'package:kute/services/api/share_links_api.dart';

class FakeShareLinksApi implements ShareLinksApi {
  FakeShareLinksApi({this.webBase = 'https://web.test'});

  final String webBase;
  final Map<String, ShareLink> links = {};
  final Map<String, String> claimDestinations = {};
  final List<ClaimedShareLink> claimedForMe = [];
  final List<(String call, Map<String, Object?> args)> calls = [];

  /// Thrown by the next call of the named kind, once.
  final Map<String, Object> failNext = {};

  int _seq = 0;

  void _record(String call, Map<String, Object?> args) {
    calls.add((call, args));
    final fail = failNext.remove(call);
    if (fail != null) throw fail;
  }

  /// Seeds a link as the backend would hold it.
  void seed(ShareLink link) => links[link.id] = link;

  @override
  Future<CreatedShareLink> create({
    required ShareLinkKind kind,
    required int amountMinor,
    String? marketSlug,
    String? senderLabel,
    String? venue,
    String? outcome,
    int? outcomeIndex,
    String? side,
  }) async {
    _record('create', {
      'kind': kind.name,
      'asset': kind.asset,
      'amountMinor': amountMinor,
      'marketSlug': marketSlug,
      'senderLabel': senderLabel,
      if (venue != null) 'venue': venue,
      if (outcome != null) 'outcome': outcome,
      if (outcomeIndex != null) 'outcomeIndex': outcomeIndex,
      if (side != null) 'side': side,
    });
    final id = 'lnk_${++_seq}';
    links[id] = ShareLink(
      id: id,
      kind: kind,
      amountMinor: amountMinor,
      marketSlug: marketSlug,
      venue: venue,
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: side,
      senderLabel: senderLabel,
      status: ShareLinkStatus.open,
      rawStatus: 'open',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    return CreatedShareLink(id: id, url: '$webBase/c/$id');
  }

  @override
  Future<ShareLink> read(String id) async {
    _record('read', {'id': id});
    final link = links[id];
    if (link == null) {
      throw const ShareLinkApiException(404, code: 'link_not_found');
    }
    return link;
  }

  @override
  Future<ShareLinkStatus> claim(String id,
      {required String destination}) async {
    _record('claim', {'id': id, 'destination': destination});
    final link = links[id];
    if (link == null) {
      throw const ShareLinkApiException(404, code: 'link_not_found');
    }
    if (link.status != ShareLinkStatus.open) {
      throw const ShareLinkApiException(409, code: 'link_not_open');
    }
    links[id] = ShareLink(
      id: link.id,
      kind: link.kind,
      amountMinor: link.amountMinor,
      marketSlug: link.marketSlug,
      venue: link.venue,
      outcome: link.outcome,
      outcomeIndex: link.outcomeIndex,
      side: link.side,
      senderLabel: link.senderLabel,
      referralCode: link.referralCode,
      status: ShareLinkStatus.claimed,
      rawStatus: 'claimed',
      expiresAt: link.expiresAt,
    );
    claimDestinations[id] = destination;
    return ShareLinkStatus.claimed;
  }

  @override
  Future<List<ClaimedShareLink>> claimed() async {
    _record('claimed', const {});
    return List.of(claimedForMe);
  }

  @override
  Future<void> markPaid(String id, {required String paymentId}) async {
    _record('markPaid', {'id': id, 'paymentId': paymentId});
    claimedForMe.removeWhere((c) => c.id == id);
  }

  @override
  Future<void> cancel(String id) async {
    _record('cancel', {'id': id});
    final link = links[id];
    if (link != null && link.status != ShareLinkStatus.open) {
      throw const ShareLinkApiException(409, code: 'link_not_open');
    }
    if (link != null) {
      links[id] = ShareLink(
        id: link.id,
        kind: link.kind,
        amountMinor: link.amountMinor,
        status: ShareLinkStatus.cancelled,
        rawStatus: 'cancelled',
      );
    }
  }

  List<String> get callNames => [for (final c in calls) c.$1];
}
