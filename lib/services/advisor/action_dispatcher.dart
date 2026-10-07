import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/services/advisor/advisor_capability_manifest.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/support_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Sal can navigate to a verified public market. It cannot create order intents,
/// choose outcomes, read account state, prefill amounts or move money.
class AdvisorActionDispatcher {
  AdvisorActionDispatcher._();

  /// The action id as an analytics value: only ids from the closed manifest
  /// leave the device; anything a model invented reads 'unknown'.
  static String analyticsAction(String actionId) =>
      AdvisorCapabilityManifest.isEnabled(actionId) ? actionId : 'unknown';

  static void _result(String actionId, String result) =>
      TrackingService.salActionResult(
          action: analyticsAction(actionId), result: result);

  static Future<void> dispatch(
    BuildContext context,
    ProviderContainer container,
    String actionId,
    Map<String, dynamic> params,
  ) async {
    if (!AdvisorCapabilityManifest.validParams(actionId, params)) {
      _result(actionId, 'unavailable');
      _toast(context, context.l10n.salActionUnavailable);
      return;
    }
    try {
      switch (actionId) {
        case 'open_market_by_slug':
          final slug = params['slug'] as String;
          final event = await container.read(
            polymarketEventDetailsProvider(slug).future,
          );
          if (!context.mounted) return;
          if (event == null || event.slug != slug) {
            _result(actionId, 'unavailable');
            _toast(context, context.l10n.salPredictionMarketUnavailable);
          } else if (!polymarketEventOffered(
              event, RuntimeCapabilitiesService.instance)) {
            // A category the policy hides here: Sal's card came from the
            // backend, so the block is applied when it is acted on.
            _result(actionId, 'unavailable');
            _toast(
                context,
                RuntimeCapabilitiesService.instance.blockReason(
                        polymarketCategoryCapability(
                            event.category, event.tags)!) ??
                    context.l10n.salPredictionMarketUnavailable);
          } else {
            // entry_source for the market-view funnel: opened from Sal.
            MarketDetailSheet.show(context, event: event, source: 'sal');
            _result(actionId, 'opened');
          }
        case 'open_hl_market':
          final coin = params['coin'] as String;
          final kind = params['kind'] as String?;
          final markets = <HlMarket>[];
          if (kind != 'spot') {
            markets.addAll(
              await container.read(hyperliquidPerpMarketsProvider.future),
            );
          }
          if (kind != 'perp') {
            markets.addAll(
              await container.read(hyperliquidSpotMarketsProvider.future),
            );
          }
          if (!context.mounted) return;
          // Exact wire id avoids opening a similarly named market on another DEX.
          final matches = markets
              .where((m) => m.wireCoin.toUpperCase() == coin.toUpperCase())
              .toList();
          if (matches.length != 1) {
            _result(actionId, 'unavailable');
            _toast(context, context.l10n.salMarketUnavailable);
          } else if (!hlMarketOfferedUnderPolicy(
              matches.single, RuntimeCapabilitiesService.instance)) {
            // A stock-linked perp the policy hides here: Sal's card came
            // from the backend, so the block is applied when it is acted on.
            _result(actionId, 'unavailable');
            _toast(
                context,
                RuntimeCapabilitiesService.instance
                        .blockReason('hyperliquid.stocks') ??
                    context.l10n.salMarketUnavailable);
          } else {
            HlMarketDetailSheet.show(context, market: matches.single);
            _result(actionId, 'opened');
          }
        case 'open_money_tab':
          context.go('/home');
          _result(actionId, 'opened');
        case 'open_predictions_tab':
          context.go('/polymarket');
          _result(actionId, 'opened');
        case 'open_trading_tab':
          context.go('/hyperliquid');
          _result(actionId, 'opened');
        case 'open_settings':
          context.pushNamed('settings');
          _result(actionId, 'opened');
        case 'open_support':
          await openSupportChat();
          _result(actionId, 'opened');
        default:
          // Slip controls require the still-open origin's confirmation handler.
          _result(actionId, 'unavailable');
          _toast(context, context.l10n.salOpenFromOrder);
      }
    } catch (_) {
      _result(actionId, 'error');
      if (!context.mounted) return;
      _toast(context, context.l10n.salCouldNotOpenMarket);
    }
  }

  static void _toast(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
