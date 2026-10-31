// lib/screens/share/claim_screen.dart
//
// THE RECIPIENT'S SIDE of a share link. Reached by the universal link
// `https://<public web base>/c/{id}`, the OneLink deferred deep link
// (`deep_link_value=claim`, `deep_link_sub1={id}`) and the in-app route
// `/claim/{id}` (app_router.dart). Reads the link, says "{sender} sent you
// {amount}" with Sal, the market line when the link carries one, and one
// Claim button.
//
// A link WITH A PICK (models/share_link_model.dart: the venue, the
// outcome, its index, the side; kute_share_actions.dart) reads "{sender}
// sent you a prediction" ("an investment" on Investing) over a preview
// card: the market's title and "{outcome} · {amount}". After the claim the
// screen waits for the money ("Waiting for {sender} to send it"): it polls
// the link until the backend says `paid` and watches the Dollars balance
// for the amount landing, whichever comes first. Then "Place the
// prediction" opens the bet slip (polymarket/components/bet_slip_sheet
// .dart) prefilled with the market, the outcome and the amount, or the
// Investing order slip on the pick's side with the amount; NOTHING is
// placed without the person's own tap in the slip.
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
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_mascot.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key, required this.id});

  final String id;

  static const routeName = 'claim';

  /// How often the claimed link is read again for `paid` while the
  /// screen waits for the money (see the file header).
  static const Duration paidPollInterval = Duration(seconds: 4);

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

  /// The prediction event the pick is on, once resolved by its slug (the
  /// preview card's title and picture; the slip's market).
  PolymarketEvent? _event;

  /// After the claim of a pick: whether the money has landed (the link
  /// read as `paid`, or the Dollars balance grew by the amount).
  bool _arrived = false;
  Timer? _paidPoll;
  ProviderSubscription<double>? _balanceWatch;
  double? _balanceAtClaim;

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('share_claim');
    unawaited(_load());
  }

  @override
  void dispose() {
    _paidPoll?.cancel();
    _balanceWatch?.close();
    super.dispose();
  }

  bool get _investing => _link?.venue == 'hyperliquid';

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
      if (link.hasPick && !_investing) unawaited(_resolveEvent(link));
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

  /// The event the pick is on, by its slug, for the preview card and the
  /// slip. Silent when it cannot be read: the card keeps the slug's words.
  Future<PolymarketEvent?> _resolveEvent(ShareLink link) async {
    final slug = link.marketSlug?.trim();
    if (slug == null || slug.isEmpty) return null;
    final cached = _event;
    if (cached != null && cached.slug == slug) return cached;
    PolymarketEvent? event;
    try {
      event = await ref.read(polymarketEventDetailsProvider(slug).future);
    } catch (_) {
      event = null;
    }
    if (event == null || event.slug != slug) return null;
    if (mounted) setState(() => _event = event);
    return event;
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
      if (link.hasPick) _watchArrival(link);
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

  /// Waits for the money (see the file header): the link read again every
  /// [ClaimScreen.paidPollInterval] until `paid`, and the Dollars balance
  /// watched for a rise of the amount.
  void _watchArrival(ShareLink link) {
    _paidPoll?.cancel();
    _paidPoll = Timer.periodic(ClaimScreen.paidPollInterval, (_) async {
      if (!mounted || _arrived) return;
      try {
        final fresh = await ref.read(shareLinksApiProvider).read(link.id);
        if (fresh.status == ShareLinkStatus.paid) _markArrived();
      } catch (_) {
        // The next tick tries again.
      }
    });
    if (link.kind != ShareLinkKind.dollars) return;
    try {
      _balanceAtClaim = ref.read(usdBalanceProvider);
      _balanceWatch?.close();
      _balanceWatch = ref.listenManual<double>(usdBalanceProvider, (_, next) {
        final base = _balanceAtClaim;
        if (base == null || _arrived) return;
        // A hair under the amount: the figure is a rounded reading.
        if (next - base >= link.amountMinor / 100 * 0.99) _markArrived();
      });
    } catch (_) {
      // No balance to watch (no wallet yet): the poll alone decides.
    }
  }

  void _markArrived() {
    if (!mounted || _arrived) return;
    _paidPoll?.cancel();
    _balanceWatch?.close();
    _balanceWatch = null;
    setState(() => _arrived = true);
  }

  /// The index of the pick in [event]'s outcomes: by its label first (the
  /// event's order may differ from the sender's), then the index the
  /// link carries, else the first.
  int _pickIndex(ShareLink link, PolymarketEvent event) {
    final label = link.outcome?.trim().toLowerCase() ?? '';
    final byLabel =
        event.outcomes.indexWhere((o) => o.name.toLowerCase() == label);
    if (byLabel >= 0) return byLabel;
    final carried = link.outcomeIndex;
    if (carried != null && carried >= 0 && carried < event.outcomes.length) {
      return carried;
    }
    return 0;
  }

  /// "Place the prediction": the slip, prefilled with the pick and the
  /// amount, for the person to confirm. Falls back to opening the market
  /// when the slip cannot be built here.
  Future<void> _placePick() async {
    final link = _link;
    if (link == null || !link.hasPick) return;
    final amountUsd = link.kind == ShareLinkKind.dollars
        ? link.amountMinor / 100
        : null;
    if (_investing) {
      final market = await _resolveHlMarket(link.marketSlug);
      if (!mounted) return;
      if (market == null) return _openMarket();
      await HlOrderSlipSheet.show(
        context,
        ref,
        market: market,
        isLong: link.side != 'short',
        source: 'share_claim',
        entrySource: 'share_claim',
        initialUsd: amountUsd,
      );
      return;
    }
    final event = await _resolveEvent(link);
    if (!mounted) return;
    if (event == null ||
        event.outcomes.isEmpty ||
        !polymarketEventOffered(event, RuntimeCapabilitiesService.instance)) {
      return _openMarket();
    }
    await BetSlipSheet.show(
      context,
      event: event,
      negRisk: event.negRisk,
      marketQuestion: event.title,
      marketSlug: event.slug,
      marketImage: event.imageUrl,
      outcomes: event.outcomes,
      initialOutcomeIndex: _pickIndex(link, event),
      initialAmountUsd: amountUsd,
      marketCategory: event.category,
      marketEndAt: event.endDate,
      source: 'share_claim',
    );
  }

  /// The one Investing market whose wire coin is [slug], offered here.
  Future<HlMarket?> _resolveHlMarket(String? slug) async {
    final coin = slug?.trim() ?? '';
    if (coin.isEmpty) return null;
    final markets = <HlMarket>[];
    try {
      markets
        ..addAll(await ref.read(hyperliquidPerpMarketsProvider.future))
        ..addAll(await ref.read(hyperliquidSpotMarketsProvider.future));
    } catch (_) {}
    final matches = markets
        .where((m) => m.wireCoin.toUpperCase() == coin.toUpperCase())
        .toList();
    if (matches.length == 1 &&
        hlMarketOfferedUnderPolicy(
            matches.single, RuntimeCapabilitiesService.instance)) {
      return matches.single;
    }
    return null;
  }

  Future<void> _openMarket() async {
    final slug = _link?.marketSlug?.trim();
    ShareLinkEvents.marketOpened(marketSlug: slug);
    if (slug == null || slug.isEmpty) {
      context.go('/polymarket');
      return;
    }
    // The slug on a link is a Predictions event slug or an Investing coin
    // (kute_share_actions.dart). Resolve it the way Sal's open_market
    // actions do (advisor/action_dispatcher.dart): the event by its slug,
    // else the one market with that wire coin, each only when the policy
    // offers it here; the venue's tab when neither resolves.
    PolymarketEvent? event;
    try {
      event = await ref.read(polymarketEventDetailsProvider(slug).future);
    } catch (_) {
      event = null;
    }
    if (!mounted) return;
    if (event != null &&
        event.slug == slug &&
        polymarketEventOffered(event, RuntimeCapabilitiesService.instance)) {
      context.go('/polymarket');
      MarketDetailSheet.show(context, event: event, source: 'share_claim');
      return;
    }
    final market = await _resolveHlMarket(slug);
    if (!mounted) return;
    if (market != null) {
      context.go('/hyperliquid');
      HlMarketDetailSheet.show(context, market: market, source: 'share_claim');
      return;
    }
    context.go('/polymarket');
  }

  /// The pick's market title: the resolved event's, else the coin, else
  /// the slug's words.
  String _pickTitle(ShareLink link) {
    final event = _event;
    if (event != null) return event.title;
    final slug = link.marketSlug?.trim() ?? '';
    return _investing ? slug.toUpperCase() : slug.replaceAll('-', ' ');
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
    final pick = link != null && link.hasPick;

    final KuteState mascot = switch (_phase) {
      _Phase.loading || _Phase.claiming => KuteState.loading,
      _Phase.claimed => KuteState.incoming,
      _Phase.error => KuteState.idle,
      _Phase.ready => KuteState.idle,
    };

    final String headline = switch (_phase) {
      _Phase.loading => '',
      _Phase.claimed when pick && _arrived => l10n.claimArrivedInDollars(amount),
      _Phase.claimed => l10n.claimOnItsWay,
      _Phase.error => _message ?? l10n.claimUnavailable,
      _Phase.ready || _Phase.claiming when pick => _investing
          ? l10n.claimSentInvestment(sender)
          : l10n.claimSentPrediction(sender),
      _Phase.ready || _Phase.claiming => l10n.claimTitle(sender, amount),
    };

    final String? sub = switch (_phase) {
      _Phase.claimed when pick && _arrived => null,
      _Phase.claimed when pick => l10n.claimWaitingForSender(sender),
      _Phase.claimed => l10n.claimArrivesWhenOpens(sender),
      _Phase.ready ||
      _Phase.claiming when market != null && !pick =>
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
                          if (pick && _phase != _Phase.error) ...[
                            SizedBox(height: 20.h),
                            _pickCard(c, l10n, link, amount),
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
                    _Phase.claimed when pick => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppButton(
                            key: const ValueKey('claim-place-pick'),
                            text: _arrived
                                ? (_investing
                                    ? l10n.claimPlaceInvestment
                                    : l10n.claimPlacePrediction)
                                : l10n.claimWaitingForSender(sender),
                            onPressed:
                                _arrived ? () => unawaited(_placePick()) : null,
                          ),
                          SizedBox(height: 8.h),
                          AppTextButton(
                            key: const ValueKey('claim-done'),
                            text: l10n.done,
                            onPressed: () => context.go('/home'),
                          ),
                        ],
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

  /// The pick's preview card: the market's picture when known, its title
  /// (two lines) and "{outcome} · {amount}". The share market sheet's
  /// card surface.
  Widget _pickCard(
      AppColorsExtension c, AppLocalizations l10n, ShareLink link, String amount) {
    final image = _event?.displayIconUrl;
    return Container(
      key: const ValueKey('claim-pick-card'),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          if (image != null && image.isNotEmpty) ...[
            PolyCrestImage(url: image, size: 32.w, radius: 8.w),
            SizedBox(width: 12.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pickTitle(link),
                  key: const ValueKey('claim-pick-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  l10n.claimPickAmount(link.outcome!.trim(), amount),
                  key: const ValueKey('claim-pick-line'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
