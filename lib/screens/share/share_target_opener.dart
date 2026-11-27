// lib/screens/share/share_target_opener.dart
//
// Opens the parked shared market (services/share_targets.dart) on top of
// the tab shell once a wallet is unlocked: the Predictions event by its
// slug, or the one Investing market with that wire coin, exactly as the
// Claim screen resolves a pick's market (claim_screen.dart). A market that
// cannot be read is dropped (`share_target_lost {reason: not_found}`) and
// the person stays on the tab.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/share/share_wallet_gate.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/share_targets.dart';

/// The `source` every market page opened from a share link carries
/// (`entry_source` on the market and slip events).
const String kShareLinkSource = 'share_link';

abstract final class ShareTargetOpener {
  static bool _opening = false;

  /// Test seam: what opening a resolved target does instead of pushing the
  /// market page.
  @visibleForTesting
  static void Function(ShareTarget target)? debugOpen;

  /// Opens the parked target over [context]'s root navigator. True when
  /// one was taken (opened or lost).
  static bool openParked(BuildContext? context) {
    if (_opening || context == null || !context.mounted) return false;
    final parked = ShareTargets.takeParked();
    if (parked == null) return false;
    _opening = true;
    unawaited(_open(context, parked.target, parked.after)
        .whenComplete(() => _opening = false));
    return true;
  }

  static Future<void> _open(
      BuildContext context, ShareTarget target, String after) async {
    final debug = debugOpen;
    if (debug != null) {
      debug(target);
      ShareTargets.restored(target, after);
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    if (target.investing) {
      final market = await resolveHlMarket(container, target.slug);
      if (!context.mounted) return;
      if (market == null) return ShareTargets.lost('not_found');
      ShareTargets.restored(target, after);
      final pick = ShareWalletGate.takePendingPick();
      HlMarketDetailSheet.show(context,
          market: market,
          source: kShareLinkSource,
          // The side tapped on the guest page (the desk's panel opens on
          // it; a phone opens the market).
          initialSide: pick?.outcome == null ? null : pick!.outcome == 'long',
          slipSource: pick?.outcome == null ? null : kShareLinkSource);
      return;
    }
    final event = await resolvePolyEvent(container, target.slug);
    if (!context.mounted) return;
    if (event == null) return ShareTargets.lost('not_found');
    ShareTargets.restored(target, after);
    MarketDetailSheet.show(context, event: event, source: kShareLinkSource);
    // The pick tapped on the guest page, before its wallet existed: its
    // slip over the market, nothing placed (share_wallet_gate.dart).
    final pick = ShareWalletGate.takePendingPick();
    final index = pick?.outcome == null
        ? null
        : event.outcomes.indexWhere((o) => o.name == pick!.outcome);
    if (pick == null || index == null || index < 0 || !context.mounted) {
      return;
    }
    await BetSlipSheet.show(
      context,
      event: event,
      negRisk: event.negRisk,
      marketQuestion: event.displayTitle,
      marketSlug: event.slug,
      marketImage: event.imageUrl,
      outcomes: event.outcomes,
      initialOutcomeIndex: index,
      initialBuyNo: pick.buyNo,
      marketCategory: event.category,
      marketEndAt: event.endDate,
      source: kShareLinkSource,
    );
  }

  /// The Predictions event with [slug], from public data; null when it
  /// cannot be read.
  static Future<PolymarketEvent?> resolvePolyEvent(
      ProviderContainer container, String slug) async {
    final sub = container.listen(
        polymarketEventDetailsProvider(slug).future, (_, __) {});
    try {
      final event = await sub.read().timeout(const Duration(seconds: 15));
      return event != null && event.slug == slug ? event : null;
    } catch (_) {
      return null;
    } finally {
      sub.close();
    }
  }

  /// The one Investing market whose wire coin is [coin]; null otherwise.
  static Future<HlMarket?> resolveHlMarket(
      ProviderContainer container, String coin) async {
    final markets = <HlMarket>[];
    for (final p in [
      hyperliquidPerpMarketsProvider,
      hyperliquidSpotMarketsProvider,
    ]) {
      final sub = container.listen(p.future, (_, __) {});
      try {
        markets.addAll(await sub.read().timeout(const Duration(seconds: 15)));
      } catch (_) {
        // That half of the venue is not readable now.
      } finally {
        sub.close();
      }
    }
    final matches = markets
        .where((m) => m.wireCoin.toUpperCase() == coin.toUpperCase())
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
}
