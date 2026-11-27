// lib/services/share_target.dart
//
// A SHARED MARKET LINK (founder, 27 November 2026: "when a user shares
// something, take him directly to app.kutewallet.com ... and open that
// directly"). Market, position, result and receipt shares carry a link to
// the web app's hash route for the market they are about:
//
//     https://app.kutewallet.com/#/s/p/<polymarket event slug>?o=<outcome>&r=<CODE>
//     https://app.kutewallet.com/#/s/i/<hyperliquid coin>?r=<CODE>
//
// `o` (one outcome of the event, by its name) and `r` (the sharer's
// referral code) are optional. NOTHING ELSE is ever put in the link: no
// key, address, id, token or analytics id. The host is a static site with
// no rewrites, so only the hash route works; the app's own router sees
// the part after `#` as its location.
//
// What a `/s/...` location does (app_router.dart, app_widget.dart):
//   * the referral code becomes the pending referrer
//     (AffiliateService.setPendingReferrerFromShare: shape checked, never
//     the wallet's own code, never over a referrer already bound or one
//     already pending), which the existing authWallet sends once a wallet
//     exists;
//   * the target (venue, slug, outcome) is parked (ShareLinksStore) and
//     opened on top of the tab shell once the session is unlocked with a
//     wallet: right away for an unlocked visitor, after the PIN for a
//     locked one, after onboarding for a new one;
//   * `share_link_opened` once per link opened.
//
// [ShareTarget.parseLocation] is the one parser; anything it refuses is
// dropped whole (an invalid slug drops the referral code with it).

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

/// The two venues a share link names, by their one-letter path segment.
enum ShareTargetVenue {
  predictions('p'),
  investing('i');

  const ShareTargetVenue(this.segment);

  /// The path segment: `p` (Polymarket event) or `i` (Hyperliquid coin).
  final String segment;

  /// The analytics value (`venue` on share events).
  String get analyticsVenue =>
      this == ShareTargetVenue.predictions ? 'polymarket' : 'hyperliquid';

  static ShareTargetVenue? fromSegment(String s) => switch (s) {
        'p' => ShareTargetVenue.predictions,
        'i' => ShareTargetVenue.investing,
        _ => null,
      };
}

/// The base of every share link (the web app, hash routes).
const String kShareWebBase = 'https://app.kutewallet.com/#';

/// The path prefix of a share location.
const String kShareLocationPrefix = '/s/';

/// The query keys a share link may carry; nothing else is read or built.
const String kShareOutcomeQuery = 'o';
const String kShareReferralQuery = 'r';

final RegExp _polySlug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _hlCoin = RegExp(r'^[A-Za-z0-9]+(?::[A-Za-z0-9]+)?$');
final RegExp _referral = RegExp(r'^[A-Z0-9]{3,16}$');
// Printable text only: no control characters, no angle brackets.
final RegExp _outcomeBad = RegExp(r'[\u0000-\u001f\u007f<>]');

/// One shared market: [venue], its [slug] (event slug or coin) and, on
/// Predictions, one [outcome] of the event by its name.
@immutable
class ShareTarget {
  const ShareTarget({required this.venue, required this.slug, this.outcome});

  final ShareTargetVenue venue;
  final String slug;
  final String? outcome;

  bool get investing => venue == ShareTargetVenue.investing;

  /// The in-app location: `/s/p/<slug>[?o=…]` (never a referral code: the
  /// parked target is the market alone).
  String get location {
    final path = '$kShareLocationPrefix${venue.segment}/'
        '${Uri.encodeComponent(slug)}';
    final o = outcome;
    if (o == null) return path;
    return Uri(path: path, queryParameters: {kShareOutcomeQuery: o})
        .toString();
  }

  /// The shareable link for this market, with [referralCode] when it has a
  /// valid shape (an invalid one is left off, never sent).
  String link({String? referralCode}) {
    final code = normalizeReferral(referralCode);
    final query = <String, String>{
      if (outcome != null) kShareOutcomeQuery: outcome!,
      if (code != null) kShareReferralQuery: code,
    };
    final path = '$kShareLocationPrefix${venue.segment}/'
        '${Uri.encodeComponent(slug)}';
    return '$kShareWebBase'
        '${Uri(path: path, queryParameters: query.isEmpty ? null : query)}';
  }

  /// Serialized for the park (ShareLinksStore): `venue|slug|outcome`.
  String encode() =>
      [venue.segment, slug, outcome ?? ''].map(Uri.encodeComponent).join('|');

  static ShareTarget? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parts = raw.split('|').map(Uri.decodeComponent).toList();
      if (parts.length != 3) return null;
      final venue = ShareTargetVenue.fromSegment(parts[0]);
      if (venue == null) return null;
      return _validated(venue, parts[1], parts[2].isEmpty ? null : parts[2]);
    } catch (_) {
      return null;
    }
  }

  /// A Predictions or Investing target, validated; null when refused.
  static ShareTarget? of(
      {required bool investing, required String? slug, String? outcome}) {
    final s = slug?.trim() ?? '';
    if (s.isEmpty) return null;
    return _validated(
        investing ? ShareTargetVenue.investing : ShareTargetVenue.predictions,
        s,
        investing ? null : outcome);
  }

  static ShareTarget? _validated(
      ShareTargetVenue venue, String slug, String? outcome) {
    if (slug.isEmpty || slug.length > 200) return null;
    final ok = venue == ShareTargetVenue.predictions
        ? _polySlug.hasMatch(slug)
        : (slug.length <= 40 && _hlCoin.hasMatch(slug));
    if (!ok) return null;
    String? o = outcome?.trim();
    if (o != null && o.isEmpty) o = null;
    if (o != null) {
      if (venue == ShareTargetVenue.investing) return null;
      if (o.length > 120 || _outcomeBad.hasMatch(o)) return null;
    }
    return ShareTarget(venue: venue, slug: slug, outcome: o);
  }

  /// Whether [location] (a router location, the part after `#`) is a share
  /// location at all, valid or not.
  static bool isShareLocation(Uri location) =>
      location.path.startsWith(kShareLocationPrefix);

  /// The target and the referral code a share location carries. Null when
  /// it is not a share location or anything in it is refused (unknown
  /// venue, a slug or outcome of the wrong shape, extra path segments).
  /// A referral code of the wrong shape is dropped alone.
  static ({ShareTarget target, String? referral})? parseLocation(
      Uri location) {
    if (!isShareLocation(location)) return null;
    final segments =
        location.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 3 || segments[0] != 's') return null;
    final venue = ShareTargetVenue.fromSegment(segments[1]);
    if (venue == null) return null;
    final Map<String, String> q;
    try {
      q = location.queryParameters;
    } catch (_) {
      return null;
    }
    final target = _validated(venue, segments[2], q[kShareOutcomeQuery]);
    if (target == null) return null;
    return (
      target: target,
      referral: normalizeReferral(q[kShareReferralQuery]),
    );
  }

  /// [raw] upper-cased when it has a referral code's shape (3 to 16
  /// letters and digits, the backend's own limit), else null.
  static String? normalizeReferral(String? raw) {
    final c = raw?.trim().toUpperCase() ?? '';
    return _referral.hasMatch(c) ? c : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ShareTarget &&
      other.venue == venue &&
      other.slug == slug &&
      other.outcome == outcome;

  @override
  int get hashCode => Object.hash(venue, slug, outcome);

  @override
  String toString() => 'ShareTarget(${venue.segment})';
}

/// The web app's start with the sharer's referral code, `/#/?r=CODE` (the
/// invite / Earn link, and a share about no one market): the code is
/// recorded at boot like a market link's. Without a valid code, the start.
String webInviteLink(String? referralCode) {
  final code = ShareTarget.normalizeReferral(referralCode);
  return code == null
      ? '$kShareWebBase/'
      : '$kShareWebBase/?$kShareReferralQuery=$code';
}

/// [link] (a share link this app built) with [referralCode] on it: a
/// market link keeps its market, anything else becomes the invite link.
/// Nothing but the market, the outcome and the code is ever carried.
String webShareLinkWithReferral(String link, {String? referralCode}) {
  if (link.startsWith(kShareWebBase)) {
    try {
      final parsed = ShareTarget.parseLocation(
          Uri.parse(link.substring(kShareWebBase.length)));
      if (parsed != null) return parsed.target.link(referralCode: referralCode);
    } catch (_) {/* not one of ours: the invite */}
  }
  // The older market address (`/m/predictions/{slug}[?outcome=]`,
  // `/m/investing/{coin}`), never shown again: its market on the web app.
  try {
    final uri = Uri.parse(link);
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length == 3 &&
        seg[0] == 'm' &&
        (seg[1] == 'predictions' || seg[1] == 'investing')) {
      final target = ShareTarget.of(
          investing: seg[1] == 'investing',
          slug: seg[2],
          outcome: uri.queryParameters['outcome']);
      if (target != null) return target.link(referralCode: referralCode);
    }
  } catch (_) {/* the invite */}
  return webInviteLink(referralCode);
}

/// Test seam for the dedupe of repeated redirect evaluations.
@visibleForTesting
void debugResetShareTargetDedupe() => ShareTargetIngest.debugReset();

/// Dedupe of the redirect's repeated evaluations of the same location
/// (go_router may run the top-level redirect more than once per URI).
abstract final class ShareTargetIngest {
  static int? _lastHash;
  static DateTime? _lastAt;

  /// True the first time [location] is seen within a few seconds.
  static bool firstSighting(Uri location, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final h = location.toString().hashCode;
    final last = _lastAt;
    if (h == _lastHash &&
        last != null &&
        t.difference(last) < const Duration(seconds: 3)) {
      return false;
    }
    _lastHash = h;
    _lastAt = t;
    return true;
  }

  static void debugReset() {
    _lastHash = null;
    _lastAt = null;
  }
}
