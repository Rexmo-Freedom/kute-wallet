// lib/services/share_targets.dart
//
// What happens to a shared market link once the router has parsed it
// (services/share_target.dart for the link itself): the referral code is
// recorded, the market is parked until a wallet is unlocked, and the
// journey is tracked. Opening the parked market is
// screens/share/share_target_opener.dart's job.
//
// Analytics (never the URL, the slug's link, the referral code, anything
// typed):
//   * `share_link_opened {kind: market, venue, market, has_ref, ref_result,
//     wallet_state: none|locked|unlocked, browser, via: link}` once per
//     link opened. `market` is the public event slug or coin (public
//     market data, allowed by the Data rules). `ref_result` is the
//     pending-referrer outcome (stored | invalid | own_code |
//     already_bound | already_pending | none).
//   * `share_target_lost {reason}`: a link refused (`invalid_link`) or a
//     parked market that could not be opened (`not_found`).
//   * `share_target_restored {after: link|unlock|onboarding, venue}` when
//     the parked market opens.

import 'dart:async';

import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/platform/in_app_browser.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/tracking_service.dart';

abstract final class ShareTargets {
  /// How the parked target arrived (`link`, `unlock`, `onboarding`), for
  /// `share_target_restored`; in memory only (a reload says `unlock`).
  static String? _parkedFrom;

  /// Whether this app run arrived through a share link: onboarding then
  /// skips the survey and the code screens (founder, 27 November 2026).
  static bool _arrivedThroughShare = false;
  static bool get arrivedThroughShare => _arrivedThroughShare;

  /// Test seam.
  static void debugReset() {
    _parkedFrom = null;
    _arrivedThroughShare = false;
  }

  /// Records [target] and [referral] from a link opened with the session
  /// in [walletState] (`none`, `locked`, `unlocked`). Never throws.
  static void ingest(ShareTarget target,
      {required String? referral, required String walletState}) {
    _arrivedThroughShare = true;
    _parkedFrom = switch (walletState) {
      'none' => 'onboarding',
      'locked' => 'unlock',
      _ => 'link',
    };
    try {
      ShareLinksStore.parkShareTarget(target.encode());
    } catch (_) {/* the park is best-effort */}
    unawaited(_recordReferral(referral).then((result) {
      TrackingService.track('share_link_opened', params: {
        'kind': 'market',
        'venue': target.venue.analyticsVenue,
        'market': target.slug,
        'has_ref': referral != null,
        'ref_result': result,
        'wallet_state': walletState,
        'browser': InAppBrowser.kind,
        'via': 'link',
      });
    }).catchError((Object _) {}));
  }

  /// The web app's start with a referral code (`/#/?r=CODE`, the invite /
  /// Earn link): the code only, nothing parked.
  static void ingestInvite(String referral) {
    _arrivedThroughShare = true;
    unawaited(_recordReferral(referral).then((result) {
      TrackingService.track('share_link_opened', params: {
        'kind': 'invite',
        'has_ref': true,
        'ref_result': result,
        'browser': InAppBrowser.kind,
        'via': 'link',
      });
    }).catchError((Object _) {}));
  }

  static Future<String> _recordReferral(String? referral) async {
    if (referral == null) return 'none';
    try {
      return await AffiliateService.setPendingReferrerFromShare(referral);
    } catch (_) {
      return 'error';
    }
  }

  /// A link or a parked market that came to nothing.
  static void lost(String reason) =>
      TrackingService.track('share_target_lost', params: {'reason': reason});

  /// The shell tab a parked [target] opens over: the Dollars home on the
  /// venue's pill.
  static String shellLocationFor(ShareTarget target) =>
      target.investing ? '/usd?tab=investing' : '/usd?tab=predictions';

  /// Reads and clears the parked target and how it arrived.
  static ({ShareTarget target, String after})? takeParked() {
    final raw = ShareLinksStore.takeParkedShareTarget();
    final target = ShareTarget.decode(raw);
    final after = _parkedFrom ?? 'unlock';
    _parkedFrom = null;
    if (target == null) return null;
    return (target: target, after: after);
  }

  static bool get hasParked => ShareLinksStore.parkedShareTarget != null;

  static void restored(ShareTarget target, String after) =>
      TrackingService.track('share_target_restored', params: {
        'after': after,
        'venue': target.venue.analyticsVenue,
      });
}
