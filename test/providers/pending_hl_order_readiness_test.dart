// A funded Investing order fires on the account the order draws on, not on
// the rail saying the move was delivered: while the credit is said but the
// account does not show it, the order waits (`crediting`) and moves to
// `placing` only once ready. A market order the venue still refuses for
// margin right after the credit waits for the account again and is sent
// again under the same approval, a few times at most; a limit order is
// never sent twice. Fakes only: nothing is signed or sent.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/fake_hyperliquid_move_rail.dart';

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

/// The Investing account: perp cash and spot USDC, read fresh each time.
class _Account extends HlAccountNotifier {
  _Account(this.perp, this.spot);
  final double Function() perp;
  final double Function() spot;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: perp(),
        withdrawable: perp(),
        totalMarginUsed: 0,
        positions: const [],
        spotBalances: [HlSpotBalance(coin: 'USDC', total: spot(), hold: 0)],
      );
}

class _Controller implements OrderFundingController {
  @override
  Future<OrderFundingOutcome> fundAndQueue({
    required OneBalanceVenue venue,
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    required MoveAuthorization auth,
    void Function(OrderFundingStage)? onStage,
    double? fundUsd,
    String? entrySource,
    String purpose = 'order_funding',
    bool keepUnconfirmed = false,
    bool continueJourney = false,
    String? marketKind,
  }) async =>
      const OrderFundingFunded(VenueMoveResult(
          quoteId: 'q1', orderId: 'o1', sentUsd: 20.03, arrivingUsdEstimate: 20));

  @override
  OrderFundingController withDollars(double Function() dollarsUsd) => this;
}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'w1',
      wallets: [WalletConfig(id: 'w1', name: 'Hot')],
    );

/// The slip's handover; [refusals] are thrown by the next sends in turn.
class _Placement {
  _Placement({required this.resizable, this.refusals = const []});
  final bool resizable;
  final List<Object> refusals;
  final placed = <double>[];

  SensitiveIntent intentAt(double margin) => HlIntents.openPosition(
        walletId: 'w1',
        market: _market,
        isLong: true,
        marginUsd: margin,
        leverage: 1,
        slippagePct: 1,
      );

  PendingHlOrderPlacement get placement => PendingHlOrderPlacement(
        intentAt: intentAt,
        placeAt: (g, margin) async {
          // The notifier consumes the grant against the exact order.
          GrantGuard.consume(g, intentAt(margin),
              allowed: const {SensitiveAction.hlOrder});
          placed.add(margin);
          if (refusals.isNotEmpty) throw refusals.removeAt(0);
          return HlOrderResult(
              kind: HlOrderResultKind.filled,
              oid: 7,
              filledSz: margin / 60000,
              avgPx: 60000);
        },
        resizable: resizable,
        cloid: 'c1',
      );
}

PendingHlOrderIntent _intent(_Placement placement,
        {String orderKind = 'market'}) =>
    PendingHlOrderIntent(
      coin: 'BTC',
      kind: HlMarketKind.perp,
      isLong: true,
      marginUsd: 20,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 60000,
      marketLabel: 'BTC · Perp',
      market: _market,
      placement: placement.placement,
      fundUsd: 20.03,
      requiredUsd: 20 * 1.01 * 1.0019,
      readyAtQueueUsd: 0,
      arrivingUsd: 20 * 1.01 * 1.0019,
      orderKind: orderKind,
    );

const _margin = HyperliquidInsufficientMarginException(
    'Insufficient margin to place order.');

void main() {
  late FakeHyperliquidMoveRail rail;
  late double perp;
  late double spot;
  late List<(String, Map<String, Object?>?)> events;
  late List<PendingHlOrderIntent?> history;
  PendingHlOrderIntent terminal() => history.lastWhere((s) =>
      s != null &&
      (s.status == PendingHlOrderStatus.done ||
          s.status == PendingHlOrderStatus.failed))!;

  setUp(() {
    rail = FakeHyperliquidMoveRail();
    perp = 0;
    spot = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    rail.creditedController.close();
  });

  /// Queues [placement]'s order behind its funding, with its approval.
  ProviderContainer queue(_Placement placement, {String orderKind = 'market'}) {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWith((_) => true),
      hyperliquidAccountProvider
          .overrideWith(() => _Account(() => perp, () => spot)),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
    ]);
    addTearDown(c.dispose);
    c.read(pendingHlOrderAutoFireProvider);
    history = [];
    c.listen(pendingHyperliquidOrderProvider, (_, n) => history.add(n));
    final intent = _intent(placement, orderKind: orderKind);
    final grant = AuthGrantRegistry.instance.issueAutofire(
      kPendingHlOrderAutofireId,
      pendingHlOrderAutofireIntent(intent, _market, walletId: 'w1'),
      method: AuthGrantMethod.pin,
    );
    c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
        grant: grant,
        controller: _Controller(),
        orderUsd: 20,
        requiredUsd: intent.requiredUsd,
        readyUsd: 0);
    return c;
  }

  test('credited by the rail but not showing in the account: waits '
      '(crediting), then places once the account covers it', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true);
      final c = queue(placement);
      async.flushMicrotasks();
      expect(c.read(pendingHyperliquidOrderProvider)!.readiness,
          HlReadiness.waitingFunds);

      // Orchestra says delivered; the account still shows nothing.
      rail.creditedController.add(null);
      async.elapse(const Duration(seconds: 3));
      expect(placement.placed, isEmpty);
      final waiting = c.read(pendingHyperliquidOrderProvider)!;
      expect(waiting.status, PendingHlOrderStatus.awaitingBalance);
      expect(waiting.readiness, HlReadiness.crediting);

      perp = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      final placing = history.firstWhere(
          (s) => s?.status == PendingHlOrderStatus.placing)!;
      expect(placing.readiness, HlReadiness.ready);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test('cash credited to spot for a perp order is usable: the order moves '
      'it under its own grant', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true);
      queue(placement);
      async.flushMicrotasks();
      spot = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test('refused for margin right after the credit: waits for the account, '
      'then the send again goes through under the same approval', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [_margin]);
      final c = queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, hasLength(1));
      // Not a failure: still placing, waiting for the account.
      final waiting = c.read(pendingHyperliquidOrderProvider)!;
      expect(waiting.status, PendingHlOrderStatus.placing);
      expect(waiting.readiness, HlReadiness.crediting);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20, 20]);
      expect(terminal().status, PendingHlOrderStatus.done);
      expect(events.where((e) => e.$1 == 'order_funding_failed'), isEmpty);
      expect(events.where((e) => e.$1 == 'hyperliquid_autofire_failed'),
          isEmpty);
    });
  });

  test('bounded: after five sends again the failure shows', () {
    fakeAsync((async) {
      final placement = _Placement(
          resizable: true, refusals: List.filled(6, _margin, growable: true));
      queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(placement.placed, hasLength(1 + kHlNotReadyRetries));
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test('a limit order refused for margin is a real failure: never sent '
      'twice', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: false, refusals: [_margin]);
      queue(placement, orderKind: 'limit');
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test('another venue refusal is a real failure: shown at once', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [
        const HyperliquidRejectedException('Order could not immediately match')
      ]);
      queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });
}
