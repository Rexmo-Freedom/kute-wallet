// lib/screens/share/claim_screen.dart
//
// THE RECIPIENT'S SIDE of a share link. Reached by the universal link
// `https://<public web base>/c/{id}`, the OneLink deferred deep link
// (`deep_link_value=claim`, `deep_link_sub1={id}`) and the in-app route
// `/claim/{id}` (app_router.dart). Reads the link, says "{sender} sent you
// {amount}" with Sal, the market line when the link carries one, and one
// Claim button.
//
// Claim takes a destination from THIS wallet (its own Spark receive
// address, the one every inbound settlement uses:
// sparkSelfAddressProvider) and posts it; the sender's app pays it the
// next time it opens, which is what "On its way. It arrives when {sender}
// opens Kute." says. Nothing is received here and now, and nothing here
// can spend.
//
// A link opened before the wallet exists never reaches this screen: the
// router parks the id (ShareLinksStore.parkClaim) and app_widget.dart
// opens it once the session is unlocked.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_mascot.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key, required this.id});

  final String id;

  static const routeName = 'claim';

  /// Test seam: the destination Claim sends. Null reads the wallet's own
  /// Spark address.
  @visibleForTesting
  static Future<String> Function(WidgetRef ref)? debugDestination;

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

enum _Phase { loading, ready, claiming, claimed, error }

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  _Phase _phase = _Phase.loading;
  ShareLink? _link;
  String? _message;

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('share_claim');
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _message = null;
    });
    try {
      final link = await ref.read(shareLinksApiProvider).read(widget.id);
      if (!mounted) return;
      final l10n = context.l10n;
      if (link.status == ShareLinkStatus.claimed ||
          link.status == ShareLinkStatus.paid) {
        setState(() {
          _link = link;
          _phase = _Phase.error;
          _message = l10n.claimAlreadyClaimed;
        });
        return;
      }
      if (!link.claimable) {
        setState(() {
          _link = link;
          _phase = _Phase.error;
          _message = link.status == ShareLinkStatus.expired ||
                  (link.expiresAt?.isBefore(DateTime.now()) ?? false)
              ? l10n.claimExpired
              : l10n.claimUnavailable;
        });
        return;
      }
      setState(() {
        _link = link;
        _phase = _Phase.ready;
      });
    } on ShareLinkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = e.notFound
            ? context.l10n.claimUnavailable
            : context.l10n.claimFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = context.l10n.claimFailed;
      });
    }
  }

  Future<void> _claim() async {
    final link = _link;
    if (link == null || _phase != _Phase.ready) return;
    setState(() {
      _phase = _Phase.claiming;
      _message = null;
    });
    String destination;
    try {
      final debug = ClaimScreen.debugDestination;
      destination = debug != null
          ? await debug(ref)
          : await ref.read(sparkSelfAddressProvider.future);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _message = context.l10n.claimNeedsWallet;
      });
      return;
    }
    try {
      await ref
          .read(shareLinksApiProvider)
          .claim(link.id, destination: destination);
      ShareLinkEvents.claimed(link.kind, link.amountMinor);
      if (!mounted) return;
      setState(() => _phase = _Phase.claimed);
    } on ShareLinkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.conflict) {
          _phase = _Phase.error;
          _message = context.l10n.claimAlreadyClaimed;
        } else {
          _phase = _Phase.ready;
          _message = context.l10n.claimFailed;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _message = context.l10n.claimFailed;
      });
    }
  }

  void _openMarket() {
    final slug = _link?.marketSlug;
    ShareLinkEvents.marketOpened(marketSlug: slug);
    // Phase 1: the Predictions tab. A market opened by its slug is the
    // market detail owners' hook.
    context.go('/polymarket');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final link = _link;
    final sender = link?.senderLabel ?? l10n.claimSomeone;
    final amount = link == null
        ? ''
        : shareLinkAmountLabel(context, ref, link.kind, link.amountMinor);
    final market = link?.marketSlug;

    final KuteState mascot = switch (_phase) {
      _Phase.loading || _Phase.claiming => KuteState.loading,
      _Phase.claimed => KuteState.incoming,
      _Phase.error => KuteState.idle,
      _Phase.ready => KuteState.idle,
    };

    final String headline = switch (_phase) {
      _Phase.loading => '',
      _Phase.claimed => l10n.claimOnItsWay,
      _Phase.error => _message ?? l10n.claimUnavailable,
      _Phase.ready || _Phase.claiming => l10n.claimTitle(sender, amount),
    };

    final String? sub = switch (_phase) {
      _Phase.claimed => l10n.claimArrivesWhenOpens(sender),
      _Phase.ready ||
      _Phase.claiming when market != null =>
        l10n.claimMarketLine(market.replaceAll('-', ' ')),
      _ => null,
    };

    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: const [KuteBackButton(fallbackRoute: '/home')]),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          KuteMascot(state: mascot, size: 120.sp),
                          SizedBox(height: 24.h),
                          Text(
                            headline,
                            key: const ValueKey('claim-headline'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.2,
                            ),
                          ),
                          if (sub != null) ...[
                            SizedBox(height: 10.h),
                            Text(
                              sub,
                              key: const ValueKey('claim-subline'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (_phase == _Phase.ready && _message != null) ...[
                            SizedBox(height: 12.h),
                            Text(
                              _message!,
                              key: const ValueKey('claim-error'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 24.h),
                  child: switch (_phase) {
                    _Phase.ready || _Phase.claiming => AppButton(
                        key: const ValueKey('claim-button'),
                        text: l10n.claimButton,
                        isLoading: _phase == _Phase.claiming,
                        loadingLabel: l10n.claimClaiming,
                        onPressed: _phase == _Phase.ready
                            ? () => unawaited(_claim())
                            : null,
                      ),
                    _Phase.claimed => market != null
                        ? AppButton(
                            key: const ValueKey('claim-open-market'),
                            text: l10n.claimOpenMarket,
                            onPressed: _openMarket,
                          )
                        : AppButton(
                            key: const ValueKey('claim-done'),
                            text: l10n.done,
                            onPressed: () => context.go('/home'),
                          ),
                    _Phase.error => AppButton(
                        key: const ValueKey('claim-done'),
                        text: l10n.done,
                        onPressed: () => context.go('/home'),
                      ),
                    _Phase.loading => const SizedBox.shrink(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
