// USDC returned on Arbitrum (arbitrum_refund_watch.dart): what is shown,
// the dust rule, the throttle, the once-per-amount report. Fakes only:
// no RPC, nothing signed or sent.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/arbitrum_refund_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/services/hyperliquid/arbitrum_refund_watch.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show kHypercoreCctpRouteVersion;
import 'package:kute/services/tracking_service.dart';

import '../../helpers/fake_swap_orders.dart';

const _owner = '0x1111111111111111111111111111111111111111';

class _Reports implements ArbitrumRefundReports {
  final Map<String, BigInt?> values = {};

  @override
  Future<BigInt?> lastReported(String walletId) async => values[walletId];

  @override
  Future<void> setReported(String walletId, BigInt? usdc6) async =>
      values[walletId] = usdc6;
}

class _Harness {
  _Harness({BigInt? balance, this.refund = false})
      : balance = balance ?? BigInt.zero;

  BigInt balance;
  bool refund;
  Object? fail;
  int reads = 0;
  String walletId = 'w1';
  DateTime now = DateTime(2026, 10, 19, 12);
  final reports = _Reports();
  final detected = <(double, String)>[];
  final owners = <String>[];

  late final ArbitrumRefundWatch watch = ArbitrumRefundWatch(
    account: () async => (walletId: walletId, owner: _owner),
    knownRefund: (_) => refund,
    readBalance: (owner) async {
      reads++;
      owners.add(owner);
      final f = fail;
      if (f != null) throw f;
      return balance;
    },
    reports: reports,
    clock: () => now,
    onDetected: (usd, source) => detected.add((usd, source)),
  );

  void advance(Duration d) => now = now.add(d);
}

BigInt _usdc(double usd) => BigInt.from((usd * 1e6).round());

SwapOrder _row({
  required String id,
  String status = 'refunded',
  String? routeVersion = kHypercoreCctpRouteVersion,
  String walletId = 'w1',
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: 'USDB',
      networkTo: 'SPARK',
      depositAddress: '0xdeposit',
      depositAmount: '12.40',
      withdrawalAmount: '12.30',
      status: status,
      timestamp: 0,
      withdrawalAddress: 'spark1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: _owner,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: 'op1',
      routeVersion: routeVersion,
    );

void main() {
  group('what is shown', () {
    test('a balance at the Bridge2 minimum or more: shown, not dust', () {
      final s = ArbitrumRefundState(usdc6: _usdc(5));
      expect(s.shown, isTrue);
      expect(s.belowMinimum, isFalse);
      expect(s.usd, 5);
    });

    test('dust below 5 USDC with no refund: ignored', () {
      expect(ArbitrumRefundState(usdc6: _usdc(4.99)).shown, isFalse);
      expect(ArbitrumRefundState(usdc6: _usdc(0.5)).shown, isFalse);
    });

    test('below 5 USDC from a known refund: shown, with the minimum note', () {
      final s = ArbitrumRefundState(usdc6: _usdc(3.1), fromRefund: true);
      expect(s.shown, isTrue);
      expect(s.belowMinimum, isTrue);
    });

    test('under a cent is never shown, even from a refund', () {
      expect(
          ArbitrumRefundState(usdc6: BigInt.from(9999), fromRefund: true).shown,
          isFalse);
      expect(const ArbitrumRefundState().shown, isFalse);
    });

    test('Bridge2 minimum is 5 USDC in base units', () {
      expect(kBridge2MinimumUsdc6, BigInt.from(5000000));
    });
  });

  group('refunded CCTP rows', () {
    test('a CCTP move refunded (order row or Arbitrum leg) counts', () {
      expect(isRefundedCctpMoveRow(_row(id: 'ord_1')), isTrue);
      expect(isRefundedCctpMoveRow(_row(id: 'cctp-op1', routeVersion: null)),
          isTrue);
    });

    test('not refunded, or not a CCTP move: does not count', () {
      expect(
          isRefundedCctpMoveRow(_row(id: 'ord_1', status: 'success')), isFalse);
      expect(isRefundedCctpMoveRow(_row(id: 'ord_2', routeVersion: 'other_v1')),
          isFalse);
    });

    test('only the wallet’s own rows', () {
      final rows = [
        _row(id: 'ord_1'),
        _row(id: 'ord_2', walletId: 'w2'),
        _row(id: 'ord_3', status: 'exchanging'),
      ];
      expect(refundedCctpMoveIds(rows, walletId: 'w1'), {'ord_1'});
      expect(refundedCctpMoveIds(rows, walletId: null), isEmpty);
    });
  });

  group('the scan', () {
    test('balance found: state shown and reported once, exact amount',
        () async {
      final h = _Harness(balance: _usdc(12.4));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.watch.state.shown, isTrue);
      expect(h.watch.state.usd, 12.4);
      expect(h.owners, [_owner]);
      expect(h.detected, [(12.4, 'balance_scan')]);

      // The same amount read again later: not reported again.
      h.advance(kArbitrumRefundScanEvery);
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.reads, 2);
      expect(h.detected, hasLength(1));
    });

    test('a refund-triggered read reports cctp_refund', () async {
      final h = _Harness(balance: _usdc(3.1), refund: true);
      await h.watch.scan(ArbitrumRefundTrigger.cctpRefund);
      expect(h.watch.state.belowMinimum, isTrue);
      expect(h.detected, [(3.1, 'cctp_refund')]);
    });

    test('dust with no refund: not shown, not reported', () async {
      final h = _Harness(balance: _usdc(2));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.watch.state.usdc6, _usdc(2));
      expect(h.watch.state.shown, isFalse);
      expect(h.detected, isEmpty);
    });

    test('a new amount is reported; gone and back is reported again', () async {
      final h = _Harness(balance: _usdc(10));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.balance = _usdc(25);
      h.advance(kArbitrumRefundScanEvery);
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.detected.map((e) => e.$1), [10, 25]);

      h.balance = BigInt.zero;
      h.advance(kArbitrumRefundScanEvery);
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.watch.state.shown, isFalse);
      expect(h.reports.values['w1'], isNull);

      h.balance = _usdc(25);
      h.advance(kArbitrumRefundScanEvery);
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.detected.map((e) => e.$1), [10, 25, 25]);
    });

    test('a failed read keeps the last figure, never a zero', () async {
      final h = _Harness(balance: _usdc(12));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.fail = Exception('no rpc');
      h.advance(kArbitrumRefundScanEvery);
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.watch.state.usdc6, _usdc(12));
      expect(h.watch.state.shown, isTrue);
    });

    test('another wallet starts from nothing', () async {
      final h = _Harness(balance: _usdc(12));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.walletId = 'w2';
      h.balance = BigInt.zero;
      await h.watch.scan(ArbitrumRefundTrigger.view);
      // Read at once for the new wallet, not held by the old one's throttle.
      expect(h.reads, 2);
      expect(h.watch.state.shown, isFalse);
    });
  });

  group('the throttle', () {
    test('a view refresh reads at most every 10 minutes', () async {
      final h = _Harness(balance: _usdc(6));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.advance(const Duration(minutes: 9, seconds: 59));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.reads, 1);
      h.advance(const Duration(seconds: 1));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.reads, 2);
    });

    test('resume and a refund read after a minute, never sooner', () async {
      final h = _Harness(balance: _usdc(6));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.advance(const Duration(seconds: 30));
      await h.watch.scan(ArbitrumRefundTrigger.resume);
      await h.watch.scan(ArbitrumRefundTrigger.cctpRefund);
      expect(h.reads, 1);
      h.advance(const Duration(seconds: 30));
      await h.watch.scan(ArbitrumRefundTrigger.resume);
      expect(h.reads, 2);
      h.advance(kArbitrumRefundScanFloor);
      await h.watch.scan(ArbitrumRefundTrigger.cctpRefund);
      expect(h.reads, 3);
    });

    test('a failed read is tried again after the floor, not the 10 minutes',
        () async {
      final h = _Harness(balance: _usdc(6))..fail = Exception('down');
      await h.watch.scan(ArbitrumRefundTrigger.view);
      h.advance(const Duration(seconds: 59));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.reads, 1);
      h.fail = null;
      h.advance(const Duration(seconds: 1));
      await h.watch.scan(ArbitrumRefundTrigger.view);
      expect(h.reads, 2);
      expect(h.watch.state.shown, isTrue);
    });

    test('overlapping asks share one read', () async {
      final h = _Harness(balance: _usdc(6));
      await Future.wait([
        h.watch.scan(ArbitrumRefundTrigger.view),
        h.watch.scan(ArbitrumRefundTrigger.resume),
        h.watch.scan(ArbitrumRefundTrigger.cctpRefund),
      ]);
      expect(h.reads, 1);
    });
  });

  group('analytics', () {
    test('arbitrum_refund_detected: exact amount and source, no address', () {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      TrackingService.arbitrumRefundDetected(
          amountUsd: 12.4, source: 'balance_scan');
      expect(events.single.$1, 'arbitrum_refund_detected');
      final params = events.single.$2!;
      expect(params['amount_usd'], 12.4);
      expect(params['source'], 'balance_scan');
      expect(params.containsKey('amount_bucket'), isFalse);
      expect(params.values.whereType<String>().any((v) => v.startsWith('0x')),
          isFalse);
    });
  });

  group('the provider', () {
    ProviderContainer container(
        FakeSwapOrders rows, List<String> reads, _Reports reports) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true,
              wallets: [WalletConfig(id: 'w1', name: 'Main')],
            ))),
        hyperliquidAddressProvider.overrideWith((_) async => _owner),
        swapOrdersProvider.overrideWith((_) => rows),
        arbitrumUsdcReaderProvider.overrideWithValue((owner) async {
          reads.add(owner);
          return _usdc(7.5);
        }),
        arbitrumRefundReportsProvider.overrideWithValue(reports),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test(
        'a CCTP move turning refunded reads the balance at once and reports '
        'it as cctp_refund', () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final rows = FakeSwapOrders([_row(id: 'ord_1', status: 'exchanging')]);
      final reads = <String>[];
      final c = container(rows, reads, _Reports());
      c.listen(arbitrumRefundRowsWatcherProvider, (_, __) {});
      await pumpEventQueue();
      expect(reads, isEmpty);

      rows.set([_row(id: 'ord_1')]);
      await pumpEventQueue();
      expect(reads, [_owner]);
      final state = c.read(arbitrumRefundProvider);
      expect(state.shown, isTrue);
      expect(state.fromRefund, isTrue);
      expect(events.single.$1, 'arbitrum_refund_detected');
      expect(events.single.$2!['source'], 'cctp_refund');
      expect(events.single.$2!['amount_usd'], 7.5);

      // The same refunded row again (another sync): no new read.
      rows.set([_row(id: 'ord_1')]);
      await pumpEventQueue();
      expect(reads, hasLength(1));
    });

    test('a refund already in the rows when it first runs is read', () async {
      final rows = FakeSwapOrders([_row(id: 'ord_1')]);
      final reads = <String>[];
      final c = container(rows, reads, _Reports());
      c.listen(arbitrumRefundRowsWatcherProvider, (_, __) {});
      await pumpEventQueue();
      expect(reads, [_owner]);
    });
  });
}
