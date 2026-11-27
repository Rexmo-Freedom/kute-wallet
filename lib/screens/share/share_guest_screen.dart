// lib/screens/share/share_guest_screen.dart
//
// THE SHARED MARKET FOR A VISITOR WITH NO WALLET (founder, 27 November
// 2026: "show without wallet creation ... and allow user to create wallet
// to start using it"). The web app's `/s/p/<slug>` and `/s/i/<coin>`
// routes (services/share_target.dart) draw the market's own page, read
// only, from public data: the Predictions event by its slug or the
// Investing market by its coin. Nothing is created, registered or read with
// an identity while the person only looks; the wallet-bound providers
// (positions, balances, the venue accounts) answer "nothing" with no
// wallet, as they already do before onboarding.
//
// The page's actions (Yes / No, Long / Short) stay live: their slips meet
// the one-step wallet gate (share_wallet_gate.dart) first. The region
// policy is the public one (`/config/policy`): the slips and the page's
// own blocked states read it as they always do.
//
// A market that cannot be read sends the person to the start screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/share/share_app_notice.dart';
import 'package:kute/screens/share/share_target_opener.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/share_targets.dart';
import 'package:kute/theme/app_theme.dart';

class ShareGuestScreen extends ConsumerStatefulWidget {
  const ShareGuestScreen({super.key, required this.target});

  /// The route's target; null when the location was refused.
  final ShareTarget? target;

  static const String routeName = 'share_guest';

  /// Test seams: the market reads.
  @visibleForTesting
  static Future<PolymarketEvent?> Function(String slug)? debugPolyEvent;
  @visibleForTesting
  static Future<HlMarket?> Function(String coin)? debugHlMarket;

  @override
  ConsumerState<ShareGuestScreen> createState() => _ShareGuestScreenState();
}

class _ShareGuestScreenState extends ConsumerState<ShareGuestScreen> {
  PolymarketEvent? _event;
  HlMarket? _market;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    // The person is on the market now: nothing to open for them later.
    final parked = ShareTargets.takeParked();
    if (parked != null) ShareTargets.restored(parked.target, 'guest');
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final target = widget.target;
    if (target == null) return _lost();
    final container = ProviderScope.containerOf(context, listen: false);
    if (target.investing) {
      final read = ShareGuestScreen.debugHlMarket;
      final market = read != null
          ? await read(target.slug)
          : await ShareTargetOpener.resolveHlMarket(container, target.slug);
      if (!mounted) return;
      if (market == null) return _lost();
      setState(() => _market = market);
    } else {
      final read = ShareGuestScreen.debugPolyEvent;
      final event = read != null
          ? await read(target.slug)
          : await ShareTargetOpener.resolvePolyEvent(container, target.slug);
      if (!mounted) return;
      if (event == null) return _lost();
      setState(() => _event = event);
    }
  }

  void _lost() {
    ShareTargets.lost('not_found');
    if (!mounted) return;
    setState(() => _missing = true);
    // Nothing to show: the ordinary start.
    ShareLinksStore.takeParkedShareTarget();
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final market = _market;
    final Widget page;
    if (event != null) {
      page = MarketDetailSheet(event: event, source: kShareLinkSource);
    } else if (market != null) {
      page = HlMarketDetailSheet(market: market, source: kShareLinkSource);
    } else {
      page = ColoredBox(
        color: context.colors.background,
        child: Center(
          child: _missing
              ? const SizedBox.shrink()
              : const CircularProgressIndicator.adaptive(),
        ),
      );
    }
    return ShareAppNoticeHost(child: page);
  }
}
