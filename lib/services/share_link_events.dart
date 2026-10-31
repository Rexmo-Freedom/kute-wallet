// lib/services/share_link_events.dart
//
// The PostHog events of Share and send to anyone, in one place so every
// surface sends the same shape. Exact amounts (the house rule: PostHog
// gets exact values, never buckets); the kind and the asset as categories;
// the market SLUG as the market (a public catalogue name, not an
// identifier of the user). NEVER the link id, the URL, a destination
// address or invoice, a payment id or the recipient's name.

import 'package:kute/models/share_link_model.dart';
import 'package:kute/services/tracking_service.dart';

abstract final class ShareLinkEvents {
  /// `amountMinor` as the human figure: dollars for cents, sats for sats.
  static Object _amount(ShareLinkKind kind, int amountMinor) =>
      kind == ShareLinkKind.dollars ? amountMinor / 100 : amountMinor;

  static Map<String, Object> _money(ShareLinkKind kind, int amountMinor) => {
        'kind': kind.name,
        'asset': kind.asset,
        'amount': _amount(kind, amountMinor),
      };

  /// The sender created a link (the backend row exists; nothing moved).
  static void created(ShareLinkKind kind, int amountMinor,
      {String? marketSlug}) {
    TrackingService.track('share_link_created', params: {
      ..._money(kind, amountMinor),
      if (marketSlug != null && marketSlug.isNotEmpty) 'market': marketSlug,
    });
  }

  /// The OS share sheet closed after a link was handed to it. [result]
  /// is the platform's `ShareResultStatus` name.
  static void shared(ShareLinkKind kind, {required String result}) {
    TrackingService.track('share_link_shared',
        params: {'kind': kind.name, 'result': result});
  }

  /// The recipient claimed a link on this device.
  static void claimed(ShareLinkKind kind, int amountMinor) {
    TrackingService.track('share_link_claimed',
        params: _money(kind, amountMinor));
  }

  /// The sender's wallet paid a claimed link.
  static void paid(ShareLinkKind kind, int amountMinor) {
    TrackingService.track('share_link_paid', params: _money(kind, amountMinor));
  }

  static void cancelled(ShareLinkKind kind) {
    TrackingService.track('share_link_cancelled', params: {'kind': kind.name});
  }

  /// The market share sheet opened for a market.
  static void marketOpened({String? marketSlug}) {
    TrackingService.track('share_market_opened', params: {
      'market': marketSlug == null || marketSlug.isEmpty ? 'none' : marketSlug,
    });
  }
}
