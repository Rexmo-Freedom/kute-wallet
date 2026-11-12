// The standing orders notifier: a funded prediction accepted is signed
// once and kept; its states mirror the queued bet; cancel before posting;
// a restart mid-funding queues it again; an expired or posted one is
// settled from the venue's record; the price moved past the approval
// waits for the person; analytics once per order.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlFill, HlMarket, HlMarketKind;
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId, polymarketFundedWorstPrice;
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HlOrderResult, HlOrderResultKind;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/standing_orders/polymarket_signed_order.dart';
import 'package:kute/services/standing_orders/standing_order_progress.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

import 'fake_secret_store.dart';

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

final _now = DateTime.utc(2026, 11, 9, 12);

PendingBetIntent _bet({DateTime? queuedAt, String? eventSlug, String? window}) =>
    PendingBetIntent(
      tokenId: '111',
      amount: 10,
      slippagePct: 5,
      marketQuestion: 'Will it rain?',
      outcomeName: 'Yes',
      expectedPrice: 0.5,
      status: PendingBetStatus.awaitingBalance,
      fundUsd: 10.3,
      fundArrivingUsd: 10.1,
      fundReadyUsd: 0,
      queuedAt: queuedAt ?? _now,
      eventSlug: eventSlug,
      roundWindow: window,
      entrySource: 'feed_card',
    );

/// A fake signer: one signed order per call, counted.
class _Signer {
  int calls = 0;
  AuthGrant? lastGrant;
  double? lastPrice;
  bool refuse = false;

  Future<StandingSignedOrder?> call({
    required String tokenId,
    required double size,
    required double price,
    required double spendUsd,
    required bool negRisk,
    required OrderType orderType,
    required AuthGrant grant,
  }) async {
    calls++;
    lastGrant = grant;
    lastPrice = price;
    if (refuse) return null;
    // The notifier consumes the child grant against the exact order, as
    // the trading notifier does.
    PmGrants.consumeOrder(grant,
        walletId: 'w1',
        tokenId: tokenId,
        isBuy: true,
        size: size,
        price: price,
        orderType: orderType.name,
        spendUsd: orderType == OrderType.fak ? spendUsd : null);
    final order = OrderStructV2(
      salt: BigInt.from(calls),
      maker: '0x${'ab' * 20}',
      signer: '0x${'ab' * 20}',
      tokenId: tokenId,
      makerAmount: BigInt.from((spendUsd * 1e6).round()),
      takerAmount: BigInt.from((size * 1e6).round()),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(calls),
      metadata: PolymarketConstants.bytes32Zero,
      builder: PolymarketConstants.bytes32Zero,
    );
    return StandingSignedOrder(
      signed: SignedOrderV2(order: order, signature: '0x${'cd' * 65}'),
      exchange: PolymarketConstants.exchangeAddress,
      orderType: orderType,
      negRisk: negRisk,
      orderHash:
          polymarketOrderHash(order, PolymarketConstants.exchangeAddress),
    );
  }
}

/// A venue market: [wire] its wire coin ("xyz:NVDA"), shown as the bare
/// ticker; [dex] its builder dex, '' for the main one.
HlMarket _market(String wire,
        {String dex = '', HlMarketKind kind = HlMarketKind.perp}) =>
    HlMarket(
      coin: wire.contains(':') ? wire.split(':').last : wire,
      wireCoin: wire,
      assetId: wire.hashCode & 0xffff,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 180,
      midPx: 180,
      prevDayPx: 180,
      dayNtlVlm: 1,
      dex: dex,
      isHip3: dex.isNotEmpty,
    );

/// A fill on the Investing account: [coin], bought ('B') or sold ('A'),
/// at [at].
HlFill _fill(String coin,
        {String side = 'B', required DateTime at, double sz = 0.0002}) =>
    HlFill(
      coin: coin,
      px: 60000,
      sz: sz,
      side: side,
      time: at.millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0.01,
      feeToken: 'USDC',
      oid: 7,
      hash: '0x1',
      dir: side == 'B' ? 'Open Long' : 'Open Short',
      cloid: null,
    );

void main() {
  late Directory dir;
  late FakeSecretStore secrets;
  late StandingOrderStore store;
  late _Signer signer;
  late List<(String, Map<String, Object>?)> events;
  Map<String, dynamic>? Function(String hash)? lookup;

  /// The venue's markets a resumed Investing order is found in; null: the
  /// list cannot be read.
  List<HlMarket>? hlMarkets;

  /// The Investing account's recent fills; null: the account cannot be
  /// read.
  List<HlFill>? hlFills;

  /// The Predictions account's trades on a token; null: the account
  /// cannot be read.
  List<Map<String, dynamic>>? pmTrades;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('standing_provider_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    secrets = FakeSecretStore();
    store = StandingOrderStore(secrets: secrets, boxName: 'standing_prov');
    await (await Hive.openBox<String>('standing_prov')).clear();
    signer = _Signer();
    events = [];
    lookup = null;
    hlFills = null;
    pmTrades = null;
    hlMarkets = [
      _market('BTC'),
      _market('xyz:NVDA', dex: 'xyz'),
      _market('io:NVDA', dex: 'io'),
    ];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    StandingOrdersNotifier.clock = () => _now;
    AuthGrants.clock = () => _now;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
    PredictionFundingLedger.reset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    StandingOrdersNotifier.clock = DateTime.now;
    AuthGrants.clock = DateTime.now;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
  });

  ProviderContainer container({int wakes = 0}) {
    var woke = 0;
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      standingOrderStoreProvider.overrideWithValue(store),
      standingPredictionSignerProvider.overrideWithValue(signer.call),
      standingOrderLookupProvider.overrideWithValue((hash) async {
        final l = lookup;
        if (l == null) throw StateError('no venue');
        return l(hash);
      }),
      standingHlMarketsProvider.overrideWithValue(({required bool spot}) async {
        final m = hlMarkets;
        if (m == null) throw StateError('no venue');
        return [for (final x in m) if (x.isSpot == spot) x];
      }),
      standingOrderWatchersProvider.overrideWithValue(StandingOrderWatchers(
          wakePredictions: () => woke++, wakeInvesting: () => woke++)),
      standingHlFillsProvider.overrideWithValue(() async {
        final f = hlFills;
        if (f == null) throw StateError('no account');
        return f;
      }),
      standingPmTradesProvider.overrideWithValue((token, since) async {
        final t = pmTrades;
        if (t == null) throw StateError('no account');
        return t;
      }),
    ]);
    addTearDown(() {
      expect(woke, wakes, reason: 'the venue watcher woken');
      c.dispose();
    });
    // The notifier listens to the queued bets from its birth.
    c.read(standingOrdersProvider);
    return c;
  }

  /// The one approval the slip asked for: the bet and its funding leg.
  AuthGrant approve(PendingBetIntent intent) =>
      AuthGrantRegistry.instance.issueAutofire(
        kPendingBetAutofireId,
        PmGrants.fundedBetReview(
          PmGrants.betReview(
              walletId: 'w1',
              tokenId: intent.tokenId,
              maxCostUsd: intent.amount + 0.02,
              worstPrice: polymarketFundedWorstPrice(intent),
              orderType: OrderType.fak.name),
          fundUsd: intent.fundUsd!,
          venue: IntentVenue.polymarket,
        ),
        method: AuthGrantMethod.biometric,
      );

  // Real Hive and secret writes run between the accept and the event:
  // waited for generously, so a loaded machine never reads them early.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 250));

  List<(String, Map<String, Object>?)> named(String name) =>
      events.where((e) => e.$1 == name).toList();

  group('accept', () {
    test('a funded prediction queued is signed once, kept, and marked', () async {
      final c = container();
      final intent = _bet();
      final parent = approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final orders = c.read(standingOrdersProvider);
      expect(orders, hasLength(1));
      final o = orders.single;
      expect(o.venue, StandingOrderVenue.predictions);
      expect(o.state, StandingOrderState.funding);
      expect(o.amountUsd, 10);
      expect(o.fundUsd, 10.3);
      expect(o.orderKind, 'market');
      expect(o.attempts, 1);
      // Signed at the approved worst price on the market's increment.
      expect(signer.calls, 1);
      expect(signer.lastPrice, closeTo(0.52, 1e-9));
      expect(o.approvedPrice, closeTo(0.52, 1e-9));
      expect(o.orderHash, isNotNull);
      // The parent approval stays live for the funding legs; the child
      // was consumed by the signature.
      expect(parent.consumed, isFalse);
      expect(signer.lastGrant!.consumed, isTrue);
      expect(signer.lastGrant!.method, AuthGrantMethod.biometric);
      // The queued bet carries the id; the secret and the row are stored.
      expect(c.read(pendingPolymarketBetProvider)!.standingOrderId, o.id);
      expect(await store.hasSecret(o.id), isTrue);
      expect((await store.load('w1')).single.orderHash, o.orderHash);
      final created = named('standing_order_created');
      expect(created, hasLength(1));
      expect(created.single.$2!['venue'], 'polymarket');
      expect(created.single.$2!['amount_usd'], 10);
      expect(created.single.$2!['waits_for_round'], false);
      expect(c.read(standingOrderProgressProvider).stage, StandingOrderState.funding);
      expect(c.read(standingOrderProgressProvider).amountUsd, 10);
    });

    test('never a second signature for the same queued bet', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      // The same bet, re-set at the same queue time: no new order.
      notifier.setIntent(
          c.read(pendingPolymarketBetProvider)!.copyWith(fundQuoteRef: 'r1'));
      notifier.setReadiness(PredictionsReadiness.converting);
      await settle();
      expect(signer.calls, 1);
      expect(c.read(standingOrdersProvider), hasLength(1));
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.funded);
      expect(secrets.writes, 1);
    });

    test('a pick for the next round waits for it to open', () async {
      final start = DateTime.fromMillisecondsSinceEpoch(1791152100 * 1000, isUtc: true);
      StandingOrdersNotifier.clock = () => start.subtract(const Duration(minutes: 2));
      AuthGrants.clock = StandingOrdersNotifier.clock;
      final c = container();
      final intent = _bet(
          queuedAt: StandingOrdersNotifier.clock(),
          eventSlug: 'btc-updown-5m-1791152100',
          window: 'next');
      approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final o = c.read(standingOrdersProvider).single;
      expect(o.postNotBefore, start);
      final notifier = c.read(standingOrdersProvider.notifier);
      expect(notifier.mayPost(o.id), isFalse);
      expect(notifier.mayPost(o.id, now: start), isTrue);
      expect(named('standing_order_created').single.$2!['waits_for_round'], true);
    });

    test('no approval in memory: nothing is signed, the autofire goes on as before',
        () async {
      final c = container();
      c.read(pendingPolymarketBetProvider.notifier).setIntent(_bet());
      await settle();
      expect(signer.calls, 0);
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(c.read(pendingPolymarketBetProvider)!.standingOrderId, isNull);
    });

    test('a signature that fails stops the bet honestly, the money on the venue',
        () async {
      signer.refuse = true;
      final c = container();
      final intent = _bet();
      approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final bet = c.read(pendingPolymarketBetProvider)!;
      expect(bet.status, PendingBetStatus.failed);
      expect(bet.failureCode, StandingOrderFailure.approvalMissing);
      expect(bet.errorMessage, contains('available'));
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.failed);
      expect(await store.hasSecret(o.id), isFalse);
      expect(named('standing_order_created'), isEmpty);
    });
  });

  group('mirror and results', () {
    test('placing, then done, reads posting then filled; the secret goes', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      notifier.updateStatus(PendingBetStatus.placing);
      await settle();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.posting);
      expect(c.read(standingOrdersProvider.notifier).byId(id)!.canCancel, isFalse);
      notifier.updateStatus(PendingBetStatus.done);
      await settle();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.filled);
      expect(await store.hasSecret(id), isFalse);
      expect(outcomes.single.state, StandingOrderState.filled);
      expect((await store.load('w1')).single.state, StandingOrderState.filled);
      // Cleared after done: stays filled, nothing more.
      notifier.clear();
      await settle();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.filled);
    });

    test('the fill\'s own figures go on the record, also when the venue\'s '
        'settlement read comes after the fill', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      notifier.updateStatus(PendingBetStatus.placing);
      await settle();
      notifier.updateStatus(PendingBetStatus.done);
      await settle();
      final filled = c.read(standingOrdersProvider).single;
      expect(filled.state, StandingOrderState.filled);
      expect(filled.filledUsd, isNull);
      expect(filled.placedUsd, filled.amountUsd);
      notifier.recordSettlement(
          filledShares: 19.6, filledCost: 9.8, orderedShares: 20);
      await settle();
      final noted = c.read(standingOrdersProvider).single;
      expect(noted.state, StandingOrderState.filled);
      expect(noted.filledSize, 19.6);
      expect(noted.filledUsd, 9.8);
      expect(noted.placedUsd, 9.8);
      expect((await store.load('w1')).single.filledUsd, 9.8);
    });

    // One order, one outcome: an order the venue TOOK is never said
    // "wasn't placed" afterwards because its queued intent was cleared.
    PendingHlOrderIntent hlOrder({String orderKind = 'limit'}) =>
        PendingHlOrderIntent(
          coin: 'BTC',
          market: _market('BTC'),
          kind: HlMarketKind.perp,
          isLong: true,
          marginUsd: 10,
          leverage: 2,
          slippagePct: 1,
          expectedPx: 180,
          marketLabel: 'BTC · Perp',
          status: PendingHlOrderStatus.awaitingBalance,
          fundUsd: 10.3,
          requiredUsd: 10.2,
          arrivingUsd: 10.2,
          orderKind: orderKind,
          createdAt: _now,
        );

    Future<(ProviderContainer, String, List<StandingOrder>)> standHl(
        PendingHlOrderIntent intent) async {
      final c = container();
      addTearDown(() => AuthGrantRegistry.instance
          .cancelAutofire(kPendingHlOrderAutofireId));
      AuthGrantRegistry.instance.issueAutofire(
        kPendingHlOrderAutofireId,
        pendingHlOrderAutofireIntent(intent, intent.market!, walletId: 'w1'),
        method: AuthGrantMethod.biometric,
      );
      c.read(pendingHyperliquidOrderProvider.notifier).setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      expect(c.read(pendingHyperliquidOrderProvider)!.standingOrderId, id);
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      return (c, id, outcomes);
    }

    test(
        'an Investing order the exchange took and holds (a resting limit): '
        'its queued intent ending is not a failure, nothing says "not placed"',
        () async {
      final (c, id, outcomes) = await standHl(hlOrder());
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.updateStatus(PendingHlOrderStatus.placing);
      // Done clears the queued intent right away (the notifier settles a
      // finished order): the standing order must not read that as dropped.
      notifier.setIntent(c.read(pendingHyperliquidOrderProvider)!.copyWith(
          status: PendingHlOrderStatus.done,
          result: const HlOrderResult(kind: HlOrderResultKind.resting, oid: 7)));
      await settle();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(outcomes.where((o) => o.state == StandingOrderState.failed), isEmpty,
          reason: 'the exchange holds the order: never "wasn\'t placed"');
      expect(
          c.read(standingOrdersProvider).where((o) => o.isOpen), isEmpty,
          reason: 'nothing left to place: no "Placing" card stays');
      expect(
          c.read(standingOrdersProvider)
              .where((o) => o.state == StandingOrderState.failed),
          isEmpty);
      expect(await store.hasSecret(id), isFalse);
      expect((await store.load('w1')).where((o) => o.isOpen), isEmpty,
          reason: 'never resumed after a restart');
    });

    test(
        'an Investing order sent whose answer never came (unconfirmed): '
        'never said failed', () async {
      final (c, id, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.updateStatus(PendingHlOrderStatus.placing);
      notifier.updateStatus(PendingHlOrderStatus.unconfirmed);
      await settle();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(outcomes, isEmpty);
      expect(
          c.read(standingOrdersProvider)
              .where((o) => o.state == StandingOrderState.failed),
          isEmpty);
      expect(await store.hasSecret(id), isFalse);
      expect((await store.load('w1')).where((o) => o.isOpen), isEmpty);
    });

    // Nothing may stay "Placing" once the venue has the order (founder,
    // 11 November 2026, on 2.2.0 (109)): every end of an Investing order
    // that left for the venue ends its standing order, said as it is.
    test(
        'an Investing limit resting on the book is said once, calmly '
        '(posted: "Order placed", resting), then off the list', () async {
      final (c, id, outcomes) = await standHl(hlOrder());
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.updateStatus(PendingHlOrderStatus.placing);
      notifier.setIntent(c.read(pendingHyperliquidOrderProvider)!.copyWith(
          status: PendingHlOrderStatus.done,
          result: const HlOrderResult(kind: HlOrderResultKind.resting, oid: 7)));
      await settle();
      expect([for (final o in outcomes) o.state], [StandingOrderState.posted]);
      expect(outcomes.single.id, id);
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.load('w1'), isEmpty);
    });

    test(
        'unconfirmed, and the account shows its fill: placed (Sal\'s "Order '
        'placed"), never left "Placing"', () async {
      hlFills = [
        _fill('ETH', at: _now.add(const Duration(seconds: 3))),
        _fill('BTC', side: 'A', at: _now.add(const Duration(seconds: 3))),
        _fill('BTC', at: _now.subtract(const Duration(minutes: 5))),
        _fill('BTC', at: _now.add(const Duration(seconds: 3))),
      ];
      final (c, id, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.updateStatus(PendingHlOrderStatus.placing);
      notifier.updateStatus(PendingHlOrderStatus.unconfirmed);
      await settle();
      expect([for (final o in outcomes) o.state], [StandingOrderState.filled]);
      final order = c.read(standingOrdersProvider).single;
      expect(order.id, id);
      expect(order.state, StandingOrderState.filled);
      expect(order.filledSize, 0.0002,
          reason: 'only its own fill: its coin, its side, after its accept');
      expect((await store.load('w1')).single.state, StandingOrderState.filled);
    });

    test('unconfirmed, the account shows nothing of it: over quietly',
        () async {
      hlFills = [_fill('BTC', at: _now.subtract(const Duration(minutes: 5)))];
      final (c, _, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.updateStatus(PendingHlOrderStatus.placing);
      notifier.updateStatus(PendingHlOrderStatus.unconfirmed);
      await settle();
      expect(outcomes, isEmpty);
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.load('w1'), isEmpty);
    });

    test(
        'the account\'s fills settle an order that left for the venue at '
        'once; one still queued behind its money is its queued order\'s',
        () async {
      final (c, id, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      final standing = c.read(standingOrdersProvider.notifier);
      final fills = [_fill('BTC', at: _now.add(const Duration(seconds: 2)))];
      // Funding, its queued order alive: a fill on its market is not its.
      expect(standing.settleInvestingFromFills(fills), isEmpty);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
      c.read(pendingHyperliquidOrderProvider.notifier)
          .updateStatus(PendingHlOrderStatus.placing);
      await settle();
      expect(standing.placedInAccount(
          c.read(standingOrdersProvider).single, fills), isTrue);
      expect(standing.settleInvestingFromFills(fills), [id]);
      await settle();
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.filled);
      expect([for (final o in outcomes) o.state], [StandingOrderState.filled]);
      // Its answer landing after changes nothing: one order, one outcome.
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      notifier.setIntent(c.read(pendingHyperliquidOrderProvider)!.copyWith(
          status: PendingHlOrderStatus.done,
          result: const HlOrderResult(
              kind: HlOrderResultKind.filled,
              oid: 7,
              filledSz: 0.0002,
              avgPx: 60000)));
      await settle();
      expect(outcomes, hasLength(1));
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.filled);
    });

    test(
        'a prediction the venue took and holds (posted): its queued bet '
        'cleared is not a failure', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      // The venue took it and holds it (posted): as a resting limit or an
      // order awaiting the venue's confirmation reads.
      await c
          .read(standingOrdersProvider.notifier)
          .advance(id, StandingOrderState.posting);
      await c
          .read(standingOrdersProvider.notifier)
          .advance(id, StandingOrderState.posted);
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      notifier.clear();
      await settle();
      expect(outcomes, isEmpty);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.posted);
    });

    test(
        'a queued order cleared before it left for the venue, its money '
        'already moved, is dropped', () async {
      final (c, id, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      final hl = c.read(pendingHyperliquidOrderProvider.notifier);
      // The move left Dollars (the funding controller's answer).
      hl.setIntent(c
          .read(pendingHyperliquidOrderProvider)!
          .copyWith(fundQuoteId: 'q', fundedAt: _now));
      hl.clear();
      await settle();
      final o = c.read(standingOrdersProvider.notifier).byId(id)!;
      expect(o.state, StandingOrderState.failed);
      expect(o.failureCode, 'dropped');
      expect(outcomes.single.state, StandingOrderState.failed);
    });

    test(
        'refused before any money moved (the move refused, Dollars short): '
        'removed quietly, the slip\'s own message is the only one', () async {
      final (c, id, outcomes) = await standHl(hlOrder(orderKind: 'market'));
      // fundAndQueue's refusal clears the queued order it set first.
      c.read(pendingHyperliquidOrderProvider.notifier).clear();
      await settle();
      expect(outcomes, isEmpty, reason: 'no "wasn\'t placed" toast');
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.hasSecret(id), isFalse);
      expect(await store.load('w1'), isEmpty, reason: 'never resumed');
    });

    test(
        'a prediction whose funding stopped before any money reached '
        'Predictions: removed quietly, the slip says where the money is',
        () async {
      final c = container();
      final runs = c.read(fundedOrdersProvider.notifier);
      final run = runs.start(
          const FundedOrderLabel(
              venue: OneBalanceVenue.predictions,
              orderUsd: 10,
              side: 'Yes',
              market: 'Will it rain?',
              marketKey: '111'),
          stage: FundedOrderStage.preparing);
      // Queued behind its legs only (nothing from Dollars), as the
      // venue-cash chain does at once.
      final intent = _bet().copyWith(fundedRunId: run);
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      // The leg was refused at its quote: the run stops, the bet goes.
      runs.stop(run,
          stage: FundedOrderStage.failed,
          reason: 'venue_refused',
          moneyAt: FundedMoneyAt.investments);
      notifier.clear();
      await settle();
      expect(outcomes, isEmpty);
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.hasSecret(id), isFalse);
    });

    test('a failure is reported once, with its code', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      notifier.updateStatus(PendingBetStatus.placing);
      notifier.updateStatus(PendingBetStatus.failed, failureCode: 'insufficient_usdc');
      await settle();
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.failed);
      expect(o.failureCode, 'insufficient_usdc');
      expect(outcomes, hasLength(1));
    });

    group('one order, one outcome: a queued bet going away after its order '
        'went to the venue', () {
      Future<
          ({
            ProviderContainer c,
            PendingPolymarketBetNotifier notifier,
            String id,
            List<StandingOrder> outcomes
          })> posted({bool limit = false}) async {
        final c = container();
        final intent = limit
            ? PendingBetIntent(
                tokenId: '111',
                amount: 10,
                slippagePct: 5,
                marketQuestion: 'Will it rain?',
                outcomeName: 'Yes',
                expectedPrice: 0.5,
                isLimit: true,
                limitPrice: 0.4,
                status: PendingBetStatus.awaitingBalance,
                fundUsd: 10.3,
                fundArrivingUsd: 10.1,
                fundReadyUsd: 0,
                queuedAt: _now)
            : _bet();
        if (limit) {
          AuthGrantRegistry.instance.issueAutofire(
            kPendingBetAutofireId,
            PmGrants.fundedBetReview(
              PmGrants.betReview(
                  walletId: 'w1',
                  tokenId: intent.tokenId,
                  maxCostUsd: intent.amount + 0.02,
                  worstPrice: 0.4,
                  orderType: OrderType.gtc.name),
              fundUsd: intent.fundUsd!,
              venue: IntentVenue.polymarket,
            ),
            method: AuthGrantMethod.biometric,
          );
        } else {
          approve(intent);
        }
        final notifier = c.read(pendingPolymarketBetProvider.notifier);
        notifier.setIntent(intent);
        await settle();
        final id = c.read(standingOrdersProvider).single.id;
        final outcomes = <StandingOrder>[];
        c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
        notifier.updateStatus(PendingBetStatus.placing);
        await settle();
        return (c: c, notifier: notifier, id: id, outcomes: outcomes);
      }

      setUp(() => StandingOrdersNotifier.settleLooks = const [
            Duration.zero,
            Duration(milliseconds: 40),
            Duration(milliseconds: 40),
          ]);
      tearDown(() => StandingOrdersNotifier.settleLooks =
          StandingOrdersNotifier.defaultSettleLooks);

      test(
          'a limit resting on the book, its queued bet cleared: never "not '
          'placed"', () async {
        final r = await posted(limit: true);
        lookup = (hash) => {'id': hash, 'status': 'LIVE', 'size_matched': '0'};
        r.notifier.updateStatus(PendingBetStatus.done);
        await settle();
        // Said once, calmly: resting on the book (founder, 11 November
        // 2026), never a failure, never a position card.
        expect(r.outcomes.single.state, StandingOrderState.posted);
        expect(r.c.read(standingOrdersProvider), isEmpty);
        // The autofire clears the placed bet 600 ms after `done`.
        r.notifier.clear();
        await settle();
        expect(r.outcomes, hasLength(1),
            reason: 'one order, one outcome: nothing more is said');
        // Its part is over: no "Placing" card left behind, never resumed.
        expect(r.c.read(standingOrdersProvider).where((o) => o.isOpen),
            isEmpty);
        expect((await store.load('w1')).where((o) => o.isOpen), isEmpty);
      });

      test(
          'a limit found resting by the venue\'s record (its answer lost): '
          'the same one calm "resting", never a failure', () async {
        final r = await posted(limit: true);
        lookup = (hash) => {'id': hash, 'status': 'LIVE', 'size_matched': '0'};
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        r.notifier.clear();
        await settle();
        expect(r.outcomes.single.state, StandingOrderState.posted);
        expect(r.c.read(standingOrdersProvider), isEmpty);
        expect((await store.load('w1')), isEmpty);
      });

      test(
          'a market order the venue took with no answer, the slip dismissed: '
          'settled by the venue\'s own record, matched is placed', () async {
        final r = await posted();
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.posted);
        lookup = (hash) => {'id': hash, 'status': 'MATCHED'};
        r.notifier.clear();
        await settle();
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.filled);
        expect(r.outcomes.single.state, StandingOrderState.filled);
      });

      test(
          'awaiting its confirmation with the slip gone: the venue\'s record '
          'ends the order AND the queued bet, so the next bet is not refused',
          () async {
        final r = await posted();
        // Unknown at first (the venue has not filed it yet).
        lookup = (hash) => null;
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(r.c.read(pendingPolymarketBetProvider)!.status,
            PendingBetStatus.awaitingConfirmation);
        lookup = (hash) => {'id': hash, 'status': 'MATCHED'};
        await settle();
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.filled);
        expect(r.outcomes.single.state, StandingOrderState.filled);
        final bet = r.c.read(pendingPolymarketBetProvider);
        expect(
            bet == null || bet.status == PendingBetStatus.done, isTrue,
            reason: 'no bet left "still being confirmed"');
      });

      test(
          'killed unfilled by the venue\'s record: not placed, said once, '
          'the queued bet failed with it', () async {
        final r = await posted();
        lookup = (hash) =>
            {'id': hash, 'status': 'CANCELED', 'size_matched': '0'};
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        final o = r.c.read(standingOrdersProvider).single;
        expect(o.state, StandingOrderState.failed);
        expect(o.failureCode, StandingOrderFailure.notFilled);
        expect(r.outcomes, hasLength(1));
        expect(r.c.read(pendingPolymarketBetProvider)!.status,
            PendingBetStatus.failed);
      });

      // Founder, 12 November 2026, on 2.2.0 (110): a funded bet on a live
      // CS game ($4.83 on MOUZ) "after transfer got stuck here at
      // placing". The venue holds a game in play's order for its in-play
      // delay, then matches or kills it; an order whose end was not heard
      // stayed "Placing" for good once the looks ran out.
      test(
          'a live game\'s order held for its in-play delay, then matched: '
          'placed, its queued bet with it', () async {
        final r = await posted();
        var looks = 0;
        lookup = (hash) => {
              'id': hash,
              'status': looks++ == 0 ? 'DELAYED' : 'MATCHED',
              'size_matched': looks > 1 ? '19.23' : '0',
            };
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.filled);
        expect(r.outcomes.single.state, StandingOrderState.filled);
        final bet = r.c.read(pendingPolymarketBetProvider);
        expect(bet == null || bet.status == PendingBetStatus.done, isTrue);
      });

      test(
          'held past every look, its own trade in the account: placed with '
          'the trade\'s figures, whatever its record says yet', () async {
        final r = await posted();
        final hash = r.c.read(standingOrdersProvider).single.orderHash!;
        lookup = (hash) => {'id': hash, 'status': 'DELAYED'};
        pmTrades = [
          // Another order's trade on the market: never this one's.
          {
            'taker_order_id': '0x${'ef' * 32}',
            'size': '50',
            'price': '0.5',
            'status': 'CONFIRMED',
          },
          {
            'taker_order_id': hash,
            'size': '20.5',
            'price': '0.48',
            'status': 'MATCHED',
          },
        ];
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        final o = r.c.read(standingOrdersProvider).single;
        expect(o.state, StandingOrderState.filled);
        expect(o.filledSize, closeTo(20.5, 1e-9));
        expect(o.filledUsd, closeTo(9.84, 1e-9));
        expect(r.outcomes, hasLength(1));
        final bet = r.c.read(pendingPolymarketBetProvider);
        expect(bet == null || bet.status == PendingBetStatus.done, isTrue);
      });

      test(
          'killed at the end of its in-play delay (the venue no longer knows '
          'it, nothing of it traded): not placed, said once, the money in '
          'Predictions, the queued bet failed with it', () async {
        final r = await posted();
        lookup = (hash) => null;
        pmTrades = const [];
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        final o = r.c.read(standingOrdersProvider).single;
        expect(o.state, StandingOrderState.failed);
        expect(o.failureCode, StandingOrderFailure.notFilled);
        expect(r.outcomes, hasLength(1));
        final bet = r.c.read(pendingPolymarketBetProvider)!;
        expect(bet.status, PendingBetStatus.failed);
        expect(bet.errorMessage, l10nForLanguage('en').betBuyNotMatched);
        // Nothing left to place or resume.
        expect((await store.load('w1')).where((o) => o.isOpen), isEmpty);
      });

      test(
          'held past every look with nothing traded: over quietly, never '
          '"Placing" for good, never "not placed" for an order the venue '
          'holds', () async {
        final r = await posted();
        lookup = (hash) => {'id': hash, 'status': 'DELAYED'};
        pmTrades = const [];
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        expect(r.c.read(standingOrdersProvider), isEmpty);
        expect(r.outcomes, isEmpty);
        expect(r.c.read(pendingPolymarketBetProvider), isNull,
            reason: 'no bet left "still being confirmed"');
        expect((await store.load('w1')).where((o) => o.isOpen), isEmpty);
      });

      test(
          'the venue\'s own id from its answer: looked up by it from then on',
          () async {
        final r = await posted();
        final venueId = '0x${'9a' * 32}';
        await r.c
            .read(standingOrdersProvider.notifier)
            .noteVenueOrderId(r.id, venueId.toUpperCase().replaceFirst('0X', '0x'));
        expect(r.c.read(standingOrdersProvider).single.orderHash, venueId);
        final asked = <String>[];
        lookup = (hash) {
          asked.add(hash);
          return {'id': hash, 'status': 'MATCHED'};
        };
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        await settle();
        expect(asked, isNotEmpty);
        expect(asked.toSet(), {venueId});
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.filled);
      });

      test('the venue unreadable: left as it is, never guessed', () async {
        final r = await posted();
        r.notifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        r.notifier.clear();
        await settle();
        expect(r.c.read(standingOrdersProvider).single.state,
            StandingOrderState.posted);
        expect(r.outcomes, isEmpty);
      });

      test('cleared before anything was posted: still "not placed", as before',
          () async {
        final c = container();
        final intent = _bet();
        approve(intent);
        final notifier = c.read(pendingPolymarketBetProvider.notifier);
        notifier.setIntent(intent);
        await settle();
        final outcomes = <StandingOrder>[];
        c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
        notifier.clear();
        await settle();
        final o = c.read(standingOrdersProvider).single;
        expect(o.state, StandingOrderState.failed);
        expect(o.failureCode, 'dropped');
        expect(outcomes.single.state, StandingOrderState.failed);
      });
    });

    test('the price past the approval waits for the person, never a failure by itself',
        () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      notifier.updateStatus(PendingBetStatus.placing);
      await settle();
      // The autofire's order: needsApproval first, then the queued bet
      // stops with the price now.
      await c.read(standingOrdersProvider.notifier).needsApproval(id, priceNow: 0.81);
      notifier.updateStatus(PendingBetStatus.failed,
          failureCode: 'price_moved', movedToPrice: 0.81, retryMaxPrice: 0.85);
      await settle();
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.needsApproval);
      expect(o.movedToPrice, 0.81);
      expect(o.canCancel, isTrue);
      expect(o.isOpen, isTrue);
      expect(outcomes, isEmpty);
      expect(await store.hasSecret(id), isFalse, reason: 'nothing may be posted');
      // The person tapped: ends quietly.
      await c.read(standingOrdersProvider.notifier).advance(id, StandingOrderState.failed,
          failureCode: 'price_moved', quiet: true);
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.failed);
      expect(outcomes, isEmpty);
    });
  });

  group('re-price', () {
    test('inside the approval: a new order signed, attempts counted, old secret replaced',
        () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      final firstHash = c.read(standingOrdersProvider).single.orderHash;
      final signed = await c.read(standingOrdersProvider.notifier).reprice(id,
          intent: intent, price: 0.51, shares: 19.6, spendUsd: 10, since: _now);
      expect(signed, isNotNull);
      expect(signer.calls, 2);
      final o = c.read(standingOrdersProvider).single;
      expect(o.attempts, 2);
      expect(o.approvedPrice, 0.51);
      expect(o.orderHash, isNot(firstHash));
      expect(o.orderHash, signed!.orderHash);
      expect(secrets.values, hasLength(1), reason: 'one signature unaccounted for');
      expect(StandingSignedOrder.fromJson((await store.readSecret(id))!)!.orderHash,
          signed.orderHash);
    });

    test('past the approved worst price, too often or too late: nothing is signed',
        () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      final notifier = c.read(standingOrdersProvider.notifier);
      // Above the worst price approved (0.525): refused by the grant check.
      expect(
          await notifier.reprice(id,
              intent: intent, price: 0.6, shares: 16.6, spendUsd: 10, since: _now),
          isNull);
      // Past the window.
      expect(
          await notifier.reprice(id,
              intent: intent,
              price: 0.51,
              shares: 19.6,
              spendUsd: 10,
              since: _now.subtract(kStandingRepriceWindow + const Duration(seconds: 1))),
          isNull);
      // Three re-prices at most.
      for (var i = 0; i < kStandingReprices; i++) {
        expect(
            await notifier.reprice(id,
                intent: intent, price: 0.51, shares: 19.6, spendUsd: 10, since: _now),
            isNotNull,
            reason: 'reprice ${i + 1}');
      }
      expect(
          await notifier.reprice(id,
              intent: intent, price: 0.51, shares: 19.6, spendUsd: 10, since: _now),
          isNull);
      expect(notifier.byId(id)!.attempts, 1 + kStandingReprices);
      // No approval in memory (a restart): nothing is signed.
      AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
      expect(
          await notifier.reprice(id,
              intent: intent, price: 0.5, shares: 20, spendUsd: 10, since: _now),
          isNull);
    });
  });

  group('cancel', () {
    test('before posting: the queued bet goes, the secret goes, the money stays',
        () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      expect(await c.read(standingOrdersProvider.notifier).cancel(id), isTrue);
      expect(c.read(pendingPolymarketBetProvider), isNull);
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.cancelled);
      expect(await store.hasSecret(id), isFalse);
      final cancelled = named('standing_order_cancelled');
      expect(cancelled, hasLength(1));
      expect(cancelled.single.$2!['stage'], 'funding');
      expect(cancelled.single.$2!['amount_usd'], 10);
      expect(cancelled.single.$2!['wait_ms'], 0);
      // The grant went with the cleared bet: nothing can sign under it.
      expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingBetAutofireId), isFalse);
      expect(c.read(standingOrderProgressProvider).active, isFalse);
    });

    test('once posting, cancel is refused', () async {
      final c = container();
      final intent = _bet();
      approve(intent);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(intent);
      await settle();
      notifier.updateStatus(PendingBetStatus.placing);
      await settle();
      final id = c.read(standingOrdersProvider).single.id;
      expect(await c.read(standingOrdersProvider.notifier).cancel(id), isFalse);
      expect(c.read(pendingPolymarketBetProvider)!.status, PendingBetStatus.placing);
      expect(named('standing_order_cancelled'), isEmpty);
    });
  });

  group('resume', () {
    StandingOrder stored({
      StandingOrderState state = StandingOrderState.funding,
      DateTime? createdAt,
      StandingOrderVenue venue = StandingOrderVenue.predictions,
      String orderKind = 'market',
      String? marketKey,
      String? positionCoin,
    }) =>
        StandingOrder(
          id: 'so_restart',
          walletId: 'w1',
          venue: venue,
          marketKey: marketKey ??
              (venue == StandingOrderVenue.predictions ? '111' : 'BTC'),
          positionCoin: positionCoin,
          marketTitle: 'Will it rain?',
          sideLabel: 'Yes',
          isBuy: true,
          size: 19.23,
          approvedPrice: 0.52,
          amountUsd: 10,
          orderKind: orderKind,
          state: state,
          createdAt: createdAt ?? _now.subtract(const Duration(minutes: 3)),
          updatedAt: createdAt ?? _now.subtract(const Duration(minutes: 3)),
          fundUsd: 10.3,
          arrivingUsd: 10.1,
          slippagePct: 5,
          leverage: 2,
          marketKind: 'perp',
          orderHash: '0x${'ab' * 32}',
        );

    test('mid-funding: queued again with its id, the watcher woken', () async {
      await store.save(stored());
      await store.writeSecret('so_restart', {'venue': 'predictions'});
      final c = container(wakes: 1);
      await c.read(standingOrdersProvider.notifier).resume();
      final bet = c.read(pendingPolymarketBetProvider)!;
      expect(bet.standingOrderId, 'so_restart');
      expect(bet.status, PendingBetStatus.awaitingBalance);
      expect(bet.funded, isTrue);
      expect(bet.fundUsd, 10.3);
      expect(bet.queuedAt, _now.subtract(const Duration(minutes: 3)));
      expect(bet.tokenId, '111');
      expect(bet.amount, 10);
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.funding);
      final resumed = named('standing_order_resumed');
      expect(resumed, hasLength(1));
      expect(resumed.single.$2!['stage'], 'funding');
      expect(resumed.single.$2!['wait_ms'], 3 * 60 * 1000);
      // A second resume changes nothing.
      await c.read(standingOrdersProvider.notifier).resume();
      expect(named('standing_order_resumed'), hasLength(1));
    });

    test('expired: settled as failed with nothing placed, the secret gone', () async {
      await store.save(stored(createdAt: _now.subtract(const Duration(minutes: 31))));
      await store.writeSecret('so_restart', {'venue': 'predictions'});
      final c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingPolymarketBetProvider), isNull);
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.failed);
      expect(o.failureCode, StandingOrderFailure.expired);
      expect(await store.hasSecret('so_restart'), isFalse);
    });

    test('without its signed order: settled as failed, never signed anew', () async {
      await store.save(stored());
      final c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingPolymarketBetProvider), isNull);
      expect(c.read(standingOrdersProvider).single.failureCode,
          StandingOrderFailure.approvalMissing);
      expect(signer.calls, 0);
    });

    test('posting: the venue\'s record settles it, matched is filled', () async {
      await store.save(stored(state: StandingOrderState.posting));
      lookup = (hash) => {'id': hash, 'status': 'MATCHED'};
      final c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.filled);
      expect(c.read(pendingPolymarketBetProvider), isNull);
    });

    test('posting: killed unfilled is failed; live is posted; unknown waits', () async {
      await store.save(stored(state: StandingOrderState.posting));
      lookup = (hash) => {'id': hash, 'status': 'CANCELED', 'size_matched': '0'};
      var c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.failed);
      expect(c.read(standingOrdersProvider).single.failureCode,
          StandingOrderFailure.notFilled);

      await (await Hive.openBox<String>('standing_prov')).clear();
      secrets.values.clear();
      await store.save(stored(state: StandingOrderState.posting));
      lookup = (hash) => {'id': hash, 'status': 'LIVE'};
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.posted);

      await (await Hive.openBox<String>('standing_prov')).clear();
      secrets.values.clear();
      await store.save(stored(state: StandingOrderState.posting));
      lookup = null; // the venue cannot be read
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.posting);
    });

    test('posting but never reached the venue: queued again, posted by the guard',
        () async {
      await store.save(stored(state: StandingOrderState.posting));
      await store.writeSecret('so_restart', {'venue': 'predictions'});
      lookup = (hash) => null;
      final c = container(wakes: 1);
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingPolymarketBetProvider)!.standingOrderId, 'so_restart');
    });

    test(
        'posting, the venue does not know it but the account shows its own '
        'trade: placed with the trade\'s figures, never posted again',
        () async {
      await store.save(stored(state: StandingOrderState.posting));
      await store.writeSecret('so_restart', {'venue': 'predictions'});
      lookup = (hash) => null;
      pmTrades = [
        {
          'maker_orders': [
            {
              'order_id': '0x${'ab' * 32}',
              'matched_amount': '19.23',
              'price': '0.52',
            }
          ],
          'taker_order_id': '0x${'01' * 32}',
          'size': '100',
          'price': '0.48',
          'status': 'CONFIRMED',
        }
      ];
      final c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.filled);
      expect(o.filledSize, closeTo(19.23, 1e-9));
      expect(c.read(pendingPolymarketBetProvider), isNull);
    });

    test('an Investing market order is queued again; a limit is settled honestly',
        () async {
      await store.save(stored(venue: StandingOrderVenue.investing));
      await store.writeSecret('so_restart', {'venue': 'investing'});
      var c = container(wakes: 1);
      await c.read(standingOrdersProvider.notifier).resume();
      final hl = c.read(pendingHyperliquidOrderProvider)!;
      expect(hl.standingOrderId, 'so_restart');
      expect(hl.status, PendingHlOrderStatus.awaitingBalance);
      expect(hl.coin, 'BTC');
      expect(hl.market?.wireCoin, 'BTC');
      expect(hl.leverage, 2);
      expect(hl.marginUsd, 10);
      expect(hl.placement, isNull);

      await (await Hive.openBox<String>('standing_prov')).clear();
      secrets.values.clear();
      await store.save(stored(venue: StandingOrderVenue.investing, orderKind: 'limit'));
      await store.writeSecret('so_restart', {'venue': 'investing'});
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.failureCode,
          StandingOrderFailure.notResumable);
      expect(c.read(pendingHyperliquidOrderProvider), isNull);

      // Sent before the restart: never sent again, said as posted.
      await (await Hive.openBox<String>('standing_prov')).clear();
      secrets.values.clear();
      await store.save(stored(
          venue: StandingOrderVenue.investing, state: StandingOrderState.posting));
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider).single.state, StandingOrderState.posted);
    });

    // Founder, 11 November 2026, on 2.2.0 (109): a placed order kept
    // saying "Placing" (the toast, the Overview, a reopened ticket). One
    // sent before the restart is read from the account's fills, never
    // left posted for good and never "not placed".
    test(
        'Investing sent before the restart: its fill in the account is '
        'placed; nothing of it, over quietly; past its life and unreadable, '
        'over quietly, never "not placed"', () async {
      final placedAt = _now.subtract(const Duration(minutes: 2));
      hlFills = [_fill('BTC', at: placedAt)];
      await store.save(stored(
          venue: StandingOrderVenue.investing, state: StandingOrderState.posted));
      var c = container();
      final outcomes = <StandingOrder>[];
      c.read(standingOrdersProvider.notifier).outcomes.listen(outcomes.add);
      await c.read(standingOrdersProvider.notifier).resume();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.filled);
      expect([for (final o in outcomes) o.state], [StandingOrderState.filled]);
      expect(c.read(pendingHyperliquidOrderProvider), isNull,
          reason: 'never sent again');

      await (await Hive.openBox<String>('standing_prov')).clear();
      hlFills = const [];
      await store.save(stored(
          venue: StandingOrderVenue.investing, state: StandingOrderState.posting));
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.load('w1'), isEmpty);

      hlFills = null;
      await store.save(stored(
          venue: StandingOrderVenue.investing,
          state: StandingOrderState.posted,
          createdAt: _now.subtract(const Duration(hours: 1))));
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(standingOrdersProvider), isEmpty);
      expect(await store.load('w1'), isEmpty);
    });
  });

  group('resume, Investing on a builder dex (HIP-3)', () {
    StandingOrder nvda({String? positionCoin}) => StandingOrder(
          id: 'so_nvda',
          walletId: 'w1',
          venue: StandingOrderVenue.investing,
          marketKey: 'NVDA',
          positionCoin: positionCoin,
          marketTitle: 'NVDA · Perp',
          sideLabel: 'short',
          isBuy: false,
          size: 10,
          approvedPrice: 180,
          amountUsd: 10,
          orderKind: 'market',
          state: StandingOrderState.funding,
          createdAt: _now.subtract(const Duration(minutes: 3)),
          updatedAt: _now.subtract(const Duration(minutes: 3)),
          fundUsd: 10.3,
          slippagePct: 5,
          leverage: 1,
          marketKind: 'perp',
        );

    test('queued again on the very dex it was approved on, never the first '
        '"NVDA" listed', () async {
      await store.save(nvda(positionCoin: 'xyz:NVDA'));
      await store.writeSecret('so_nvda', {'venue': 'investing'});
      // io's Nvidia listed first: the old lookup by the bare coin took it.
      hlMarkets = [_market('io:NVDA', dex: 'io'), ...hlMarkets!];
      final c = container(wakes: 1);
      await c.read(standingOrdersProvider.notifier).resume();
      final hl = c.read(pendingHyperliquidOrderProvider)!;
      expect(hl.standingOrderId, 'so_nvda');
      expect(hl.market?.wireCoin, 'xyz:NVDA');
      expect(hl.market?.dex, 'xyz');
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
    });

    test('kept before its position coin was, its coin on more than one dex: '
        'settled as not resumable, never posted', () async {
      await store.save(nvda());
      await store.writeSecret('so_nvda', {'venue': 'investing'});
      final c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      final o = c.read(standingOrdersProvider).single;
      expect(o.state, StandingOrderState.failed);
      expect(o.failureCode, StandingOrderFailure.notResumable);
      expect(await store.hasSecret('so_nvda'), isFalse);
    });

    test('kept before its position coin was, its coin on one dex only: '
        'queued again there', () async {
      await store.save(nvda());
      await store.writeSecret('so_nvda', {'venue': 'investing'});
      hlMarkets = [_market('BTC'), _market('xyz:NVDA', dex: 'xyz')];
      final c = container(wakes: 1);
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingHyperliquidOrderProvider)!.market?.wireCoin,
          'xyz:NVDA');
    });

    test('its market gone: not resumable; the list unreadable: left as it '
        'is for the next resume', () async {
      await store.save(nvda(positionCoin: 'xyz:NVDA'));
      await store.writeSecret('so_nvda', {'venue': 'investing'});
      hlMarkets = [_market('BTC'), _market('io:NVDA', dex: 'io')];
      var c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(c.read(standingOrdersProvider).single.failureCode,
          StandingOrderFailure.notResumable);

      await (await Hive.openBox<String>('standing_prov')).clear();
      secrets.values.clear();
      await store.save(nvda(positionCoin: 'xyz:NVDA'));
      await store.writeSecret('so_nvda', {'venue': 'investing'});
      hlMarkets = null;
      c = container();
      await c.read(standingOrdersProvider.notifier).resume();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
    });

    test('resumeMarketFor: by the position coin; a spot order by its token; '
        'an old order only when one market has its coin', () {
      final markets = [
        _market('BTC'),
        _market('xyz:NVDA', dex: 'xyz'),
        _market('io:NVDA', dex: 'io'),
        _market('NVDAX', kind: HlMarketKind.spot),
      ];
      expect(
          StandingOrdersNotifier.resumeMarketFor(
                  nvda(positionCoin: 'io:NVDA'), markets)
              ?.wireCoin,
          'io:NVDA');
      expect(StandingOrdersNotifier.resumeMarketFor(nvda(), markets), isNull);
      final btc = StandingOrder.fromJson(
          {...nvda().toJson(), 'marketKey': 'BTC'})!;
      expect(StandingOrdersNotifier.resumeMarketFor(btc, markets)?.wireCoin,
          'BTC');
      final spot = StandingOrder.fromJson({
        ...nvda().toJson(),
        'marketKey': 'NVDAX',
        'positionCoin': 'NVDAX',
        'marketKind': 'spot',
      })!;
      expect(StandingOrdersNotifier.resumeMarketFor(spot, markets)?.coin,
          'NVDAX');
    });
  });

  test('standingPmPlacedBy: its own order as taker or maker, never another\'s '
      'nor a trade failed on chain', () {
    final order = StandingOrder(
      id: 'so',
      walletId: 'w1',
      venue: StandingOrderVenue.predictions,
      marketKey: '111',
      marketTitle: 'Will it rain?',
      sideLabel: 'Yes',
      isBuy: true,
      size: 10,
      approvedPrice: 0.5,
      amountUsd: 5,
      orderKind: 'market',
      state: StandingOrderState.posted,
      createdAt: _now,
      updatedAt: _now,
      orderHash: '0x${'ab' * 32}',
    );
    final mine = {
      'taker_order_id': '0x${'AB' * 32}',
      'size': '10',
      'price': '0.5',
      'status': 'MATCHED'
    };
    final asMaker = {
      'taker_order_id': '0x${'01' * 32}',
      'maker_orders': [
        {'order_id': '0x${'ab' * 32}', 'matched_amount': '2', 'price': '0.4'},
        {'order_id': '0x${'02' * 32}', 'matched_amount': '9', 'price': '0.4'},
      ],
      'size': '11',
      'price': '0.6',
    };
    final failed = {...mine, 'status': 'FAILED'};
    final other = {...mine, 'taker_order_id': '0x${'cd' * 32}'};
    final own = standingPmPlacedBy(order, [mine, asMaker, failed, other]);
    expect(own, [mine, asMaker]);
    final figures = standingPmTradeFigures(order, own);
    expect(figures.shares, closeTo(12, 1e-9));
    expect(figures.usd, closeTo(5.8, 1e-9));
  });

  test('settleFromVenue reads the venue\'s record, nothing else', () {
    final o = StandingOrder(
      id: 'x',
      walletId: 'w1',
      venue: StandingOrderVenue.predictions,
      marketKey: '111',
      marketTitle: '',
      sideLabel: '',
      isBuy: true,
      size: 1,
      approvedPrice: 0.5,
      amountUsd: 1,
      orderKind: 'market',
      state: StandingOrderState.posting,
      createdAt: _now,
      updatedAt: _now,
      orderHash: '0xaa',
    );
    expect(StandingOrdersNotifier.settleFromVenue(o, null), isNull);
    expect(StandingOrdersNotifier.settleFromVenue(o, {'id': '0xbb', 'status': 'MATCHED'}),
        isNull, reason: 'another order proves nothing');
    expect(StandingOrdersNotifier.settleFromVenue(o, {'id': '0xaa', 'status': 'weird'}),
        isNull);
    expect(
        StandingOrdersNotifier.settleFromVenue(
            o, {'id': '0xaa', 'status': 'CANCELED', 'size_matched': '3'})!.state,
        StandingOrderState.filled);
    expect(StandingOrdersNotifier.settleFromVenue(o, {'id': '0xaa', 'status': 'DELAYED'})!.state,
        StandingOrderState.posted);
  });

  test('a SensitiveIntent round-trips with no drift', () {
    final intent = SensitiveIntent(
      action: SensitiveAction.hlOrder,
      walletId: 'w1',
      venue: IntentVenue.hyperliquid,
      destination: 'BTC',
      asset: 'BTC',
      amountMax: BigInt.from(20000000),
      limits: {
        IntentLimit.side: 'long',
        IntentLimit.leverage: 2,
        IntentLimit.maxSlippageBps: 100,
        IntentLimit.limitPrice: 0.5,
        VenueLimit.fundingUsd: BigInt.from(20030000),
        'legs': ['a', 'b'],
      },
    );
    final back = sensitiveIntentFromJson(sensitiveIntentToJson(intent));
    expect(AuthGrants.driftError(back, intent), isNull);
    expect(AuthGrants.driftError(intent, back), isNull);
    final approval = StandingHlApproval(intent: intent, method: AuthGrantMethod.pin);
    final decoded = StandingHlApproval.fromJson(approval.toJson())!;
    expect(decoded.method, AuthGrantMethod.pin);
    expect(AuthGrants.driftError(decoded.intent, intent), isNull);
  });
}
