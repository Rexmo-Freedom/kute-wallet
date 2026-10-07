// lib/providers/hyperliquid_insights_provider.dart
//
// The data behind the Investing chart's pressure strip and its optional
// signal layers. Everything here is public data already
// available for free: Hyperliquid's info API and WebSocket, and
// Polymarket events through the app's own feed (the Kute backend's
// `/api/v1/pm/feed/events`, falling back to Gamma). The decisions live in
// lib/services/hyperliquid/insights/ (pure, tested); these providers only
// fetch, subscribe and hand over.
//
//   * [hlCrowdEventsProvider]: the open Polymarket events of an asset's
//     tag plus the Fed and inflation tags. Empty when Predictions is not
//     offered to this person (`polymarket.browse`), and filtered by the
//     category gates like every other Polymarket list.
//   * [hyperliquidTradeFlowProvider]: buy/sell pressure and big trades
//     from the public `trades` stream, on its own small socket.
//   * [hyperliquidFundingHistoryProvider]: hourly funding (`fundingHistory`).
//   * [hyperliquidOiSignalProvider]: open interest sampled in-session from
//     `activeAssetCtx` (the venue has no open-interest history).
//
// CRASH CONTRACT: the WS `messages` stream emits errors; the listener
// below attaches onError like every other Hyperliquid socket consumer.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';
import 'package:kute/services/hyperliquid/insights/hl_crowd_match.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// Keeps a provider for [duration] after its last listener leaves, so
/// reopening the same market does not read again.
void _cacheFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}

/// The Polymarket events the crowd matcher reads.
typedef HlCrowdEvents = ({
  List<PolymarketEvent> asset,
  List<PolymarketEvent> macro,
});

const HlCrowdEvents _kNoCrowdEvents = (asset: [], macro: []);

/// Open Polymarket events for the asset tag [tag] ('' = none) and the
/// macro tags, most traded first. One page per tag, read like the
/// Predictions topic feeds are.
final hlCrowdEventsProvider =
    FutureProvider.autoDispose.family<HlCrowdEvents, String>((ref, tag) async {
  final policy = ref.watch(runtimeCapabilitiesProvider);
  // Predictions not offered here: nothing of it is shown on Investing.
  if (!policy.allows('polymarket.browse')) return _kNoCrowdEvents;
  _cacheFor(ref, const Duration(minutes: 5));
  final model = PolymarketModel();
  ref.onDispose(model.dispose);

  Future<List<PolymarketEvent>> read(String slug) async {
    try {
      final page = await PolymarketModel.readGammaKeysetPage(
        'events',
        {
          'active': 'true',
          'closed': 'false',
          'order': 'volume24hr',
          'ascending': 'false',
          'tag_slug': slug,
        },
        limit: 40,
      );
      return polymarketEventsOffered(model.parseEventsRaw(page.rows), policy);
    } catch (_) {
      return const [];
    }
  }

  final reads = await Future.wait([
    if (tag.isNotEmpty) read(tag) else Future.value(const <PolymarketEvent>[]),
    read(kHlCrowdFedTag),
    read(kHlCrowdCpiTag),
  ]);
  return (asset: reads[0], macro: [...reads[1], ...reads[2]]);
});

/// Family key of [hlCrowdViewProvider]: the asset's Polymarket tag (''
/// for a market the Predictions levels do not cover, which still gets the
/// macro dates) and the price to three significant figures, so a live tick
/// does not recompute the view.
typedef HlCrowdViewKey = ({String tag, String price});

HlCrowdViewKey hlCrowdViewKey(HlCrowdAsset? asset, double price) =>
    (tag: asset?.tag ?? '', price: price.toStringAsPrecision(3));

/// What Predictions says about one asset at one price: the chart's
/// levels and the macro dates. Empty until the events land,
/// and whenever Predictions is not offered.
final hlCrowdViewProvider =
    Provider.autoDispose.family<HlCrowdView, HlCrowdViewKey>((ref, key) {
  final events = ref.watch(hlCrowdEventsProvider(key.tag)).valueOrNull;
  final price = double.tryParse(key.price);
  if (events == null || price == null) return HlCrowdView.empty;
  HlCrowdAsset? asset;
  for (final a in kHlCrowdAssets.values) {
    if (a.tag == key.tag) asset = a;
  }
  return hlCrowdView(
    asset: asset,
    price: price,
    assetEvents: events.asset,
    macroEvents: events.macro,
    now: DateTime.now(),
  );
});

/// Hourly funding of one perp, oldest first. Keyed by WIRE coin.
final hyperliquidFundingHistoryProvider = FutureProvider.autoDispose
    .family<List<HlFundingPoint>, String>((ref, wireCoin) async {
  _cacheFor(ref, const Duration(minutes: 10));
  return ref
      .read(hyperliquidTradingModelProvider)
      .getFundingHistory(coin: wireCoin);
});

/// Pressure and big trades of one market, as last computed.
class HlTradeFlowState {
  final HlPressure? pressure;
  final List<HlBigTrade> bigTrades;
  const HlTradeFlowState({this.pressure, this.bigTrades = const []});
}

/// Live buy/sell pressure and big trades of one market from the public
/// `trades` stream. Keyed by WIRE coin. Starts empty: the stream carries
/// no history, so both build up while the chart is open.
final hyperliquidTradeFlowProvider = StreamProvider.autoDispose
    .family<HlTradeFlowState, String>((ref, wireCoin) {
  final ws = HyperliquidWebSocket();
  final flow = HlTradeFlow();
  final controller = StreamController<HlTradeFlowState>();
  var bigRevision = -1;
  var bigTrades = const <HlBigTrade>[];
  var dirty = false;

  void emit() {
    if (controller.isClosed) return;
    // The big-trade list keeps its identity until it changes, so the
    // chart layer repaints only then.
    if (flow.bigRevision != bigRevision) {
      bigRevision = flow.bigRevision;
      bigTrades = flow.bigTrades;
    }
    controller.add(HlTradeFlowState(
      pressure: flow.pressure(DateTime.now().millisecondsSinceEpoch),
      bigTrades: bigTrades,
    ));
  }

  ws.subscribeTrades(wireCoin);
  final sub = ws.messages.listen(
    (msg) {
      if (msg is! HlTradesMessage) return;
      for (final t in msg.trades) {
        if (t.coin == wireCoin) {
          flow.add(t);
          dirty = true;
        }
      }
    },
    // A socket that gives up leaves the last reading on screen; the
    // strip fades out as its window empties.
    onError: (Object _, StackTrace __) {},
  );
  // One emission a second at most, and one every few seconds while the
  // tape is quiet so the window still slides.
  var ticks = 0;
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    ticks++;
    if (!dirty && ticks % 5 != 0) return;
    dirty = false;
    emit();
  });
  unawaited(ws.connect().catchError((Object _) {}));
  ref.onDispose(() {
    timer.cancel();
    sub.cancel();
    ws.unsubscribeTrades(wireCoin);
    ws.dispose();
    controller.close();
  });
  return controller.stream;
});

/// "Open interest rising / falling": sampled from the open sheet's
/// `activeAssetCtx` feed, null until [kHlOiMinWatch] of it has been
/// watched and the change is sharp. Keyed by WIRE coin.
class HlOiSignalNotifier
    extends AutoDisposeFamilyNotifier<HlOiSignal?, String> {
  final HlOiTracker _tracker = HlOiTracker();

  @override
  HlOiSignal? build(String arg) {
    ref.listen<AsyncValue<HlAssetCtx>>(hyperliquidActiveAssetCtxProvider(arg),
        (_, next) {
      final oi = next.valueOrNull?.openInterest;
      if (oi == null) return;
      _tracker.sample(DateTime.now().millisecondsSinceEpoch, oi);
      final signal = _tracker.signal;
      final shown = state;
      if (signal?.rising != shown?.rising ||
          signal?.minutes != shown?.minutes ||
          ((signal?.change ?? 0) - (shown?.change ?? 0)).abs() >= 0.001) {
        state = signal;
      }
    });
    return null;
  }
}

final hyperliquidOiSignalProvider = NotifierProvider.autoDispose
    .family<HlOiSignalNotifier, HlOiSignal?, String>(HlOiSignalNotifier.new);
