// lib/services/share_link_claims.dart
//
// PAYING CLAIMED SHARE LINKS. A share link moves no money when it is
// created (models/share_link_model.dart); the sender's app pays the
// recipient's destination the next time it is in the foreground with the
// session unlocked. app_widget.dart calls [ShareLinkClaims.check] from
// its two "we are back" points: the short-gap resume branch and the
// moment `sessionUnlockedProvider` turns true (a cold start past the PIN,
// the lock overlay going down).
//
// One pass:
//   1. Retries `POST /paid` for links this device already paid but could
//      not report (the money moved; the backend must stop listing them).
//      A local row with a paymentId is never paid again.
//   2. Reads `GET /mine?status=claimed` and, for every claim not already
//      paid here, shows the pay prompt (screens/share/claimed_prompt_sheet
//      .dart) one at a time. The prompt runs the normal Spark or Lightning
//      send behind the app's PIN/biometric step-up and reports the
//      payment. A declined or failed prompt leaves the claim as it is; the
//      next pass asks again.
//
// Also opens the PARKED CLAIM (ShareLinksStore.parkedClaimId): a `/c/{id}`
// link that arrived while the session was locked or before the wallet
// existed, opened on the Claim screen once the session is unlocked.
//
// Passes are serialized and rate-limited (one per 20 s), and silent on
// every error: a dead link or a missing session simply means no prompt.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/claimed_prompt_sheet.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_links_store.dart';

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

abstract final class ShareLinkClaims {
  static bool _running = false;
  static DateTime? _lastRun;

  /// The gap under which a second trigger is ignored.
  static const Duration minGap = Duration(seconds: 20);

  /// Test seam: what the pass shows for a claim. Null shows the prompt
  /// sheet.
  @visibleForTesting
  static Future<void> Function(BuildContext context, ClaimedShareLink claim)?
      debugPrompt;

  @visibleForTesting
  static void debugReset() {
    _running = false;
    _lastRun = null;
  }

  /// One pass (see the file header). [contextOf] yields the root
  /// navigator's context when a sheet can be shown, null otherwise.
  static Future<void> check({
    required ProviderReader read,
    required BuildContext? Function() contextOf,
    required String trigger,
  }) async {
    final now = DateTime.now();
    final last = _lastRun;
    if (_running || (last != null && now.difference(last) < minGap)) return;
    _running = true;
    _lastRun = now;
    try {
      final api = read(shareLinksApiProvider);
      await _reportUnreported(api);
      final claims = await api.claimed();
      for (final claim in claims) {
        final local = ShareLinksStore.byId(claim.id);
        if (local?.paymentId != null) continue; // paid here already
        ShareLinksStore.put((local ??
                PendingShareLink(
                  id: claim.id,
                  kind: claim.kind,
                  amountMinor: claim.amountMinor,
                  marketSlug: claim.marketSlug,
                  url: '',
                  createdAt: claim.claimedAt ?? now,
                  status: ShareLinkStatus.claimed,
                ))
            .withStatus(ShareLinkStatus.claimed));
        final context = contextOf();
        if (context == null || !context.mounted) return;
        final prompt = debugPrompt ?? showClaimedPromptSheet;
        await prompt(context, claim);
      }
    } catch (_) {
      // No session, no network, a backend that is not there yet: the
      // next pass tries again. Nothing to show.
    } finally {
      _running = false;
    }
  }

  /// `POST /paid` for every link paid here that the backend has not
  /// acknowledged. Failures stay unreported for the next pass.
  static Future<void> _reportUnreported(ShareLinksApi api) async {
    for (final row in ShareLinksStore.all()) {
      final paymentId = row.paymentId;
      if (paymentId == null || row.paidReported) continue;
      try {
        await api.markPaid(row.id, paymentId: paymentId);
        ShareLinksStore.put(
            row.copyWith(status: ShareLinkStatus.paid, paidReported: true));
      } catch (_) {/* next pass */}
    }
  }

  /// Opens the Claim screen for a parked `/c/{id}`, if one is waiting.
  /// Returns whether one was opened.
  static bool openParkedClaim(BuildContext? context) {
    final id = ShareLinksStore.parkedClaimId;
    if (id == null || context == null || !context.mounted) return false;
    ShareLinksStore.takeParkedClaim();
    unawaited(GoRouter.of(context).push(claimRoutePath(id)));
    return true;
  }

  /// The in-app route for a claim id.
  static String claimRoutePath(String id) =>
      '/claim/${Uri.encodeComponent(id)}';

  /// The id in a public `/c/{id}` link, or null when [uri] is not one.
  static String? claimIdFromLink(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length == 2 && segments.first == 'c') {
      return _validId(segments[1]);
    }
    // OneLink / custom-scheme form: deep_link_value=claim&deep_link_sub1=id.
    final q = uri.queryParameters;
    final value = q['deep_link_value'] ?? q['af_sub1'];
    if (value == 'claim') {
      return _validId(q['deep_link_sub1'] ?? q['af_sub2'] ?? q['id']);
    }
    return null;
  }

  /// Whether the OneLink `deep_link_value` names a claim rather than a
  /// referral code (the AppsFlyer hooks must not treat it as one).
  static bool isClaimDeepLinkValue(String? value) => value == 'claim';

  static String? _validId(String? raw) {
    if (raw == null) return null;
    final id = raw.trim();
    if (id.isEmpty || id.length > 64) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) return null;
    return id;
  }
}
