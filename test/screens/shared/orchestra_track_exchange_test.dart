// "Track this exchange" opens an Orchestra ORDER on Flashnet's explorer,
// never a quote: the explorer answers a quote id with "id must be an order
// id". A row still on its quote id asks for its order at tap time, moves
// the record to it and opens it; with no order yet nothing opens. An open
// detail sheet follows the row when background sync moves it to its order.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/helpers/orchestra_track_exchange.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

const _quoteId = 'q_01a159a6-71d1-4c2b-9d1e-000000000001';
const _orderId = 'ord_01a159a6-71d1-4c2b-9d1e-000000000002';
final _t0 = DateTime.utc(2026, 10, 20, 12);

SwapOrder _row(String id, {String status = 'exchanging'}) => SwapOrder(
      id: id,
      coinFrom: 'USDB',
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'LIGHTNING',
      depositAddress: 'spark-deposit-1',
      depositAmount: '20.00',
      withdrawalAmount: '0.00030000',
      status: status,
      timestamp: _t0.millisecondsSinceEpoch,
      withdrawalAddress: 'lnbc1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
    );

Result<OrchestraOrder> _order(String id, {String status = 'completed'}) =>
    Result(
        data: OrchestraOrder(
            id: id, status: status, quoteId: _quoteId, createdAt: ''),
        statusCode: 200);

/// A quote with no order yet: a 200 whose envelope carries a null order.
Result<OrchestraOrder> _noOrder() => Result(
    data: OrchestraOrder.fromJson({'order': null, 'status': 'pending'}),
    statusCode: 200);

/// The swap store with the writes a quote-to-order move makes.
class _Store extends FakeSwapOrders {
  _Store(super.state);

  @override
  Future<void> addExchange(SwapOrder exchange) async =>
      state = [...state.where((o) => o.id != exchange.id), exchange];

  @override
  Future<void> deleteExchange(String id) async =>
      state = state.where((o) => o.id != id).toList();
}

void main() {
  group('explorer id', () {
    test('only an order id opens', () {
      expect(orchestraExplorerOrderId(_orderId), _orderId);
      expect(
          orchestraExplorerOrderId('6f0d2c1e-legacy'), 'ord_6f0d2c1e-legacy');
      expect(orchestraExplorerOrderId(_quoteId), isNull);
      expect(orchestraExplorerOrderId('acu-1'), isNull);
      expect(orchestraExplorerOrderId('cctp-op'), isNull);
      expect(orchestraExplorerOrderId(''), isNull);
      expect(orchestraExplorerUri(_orderId).toString(),
          'https://orchestra.flashnet.xyz/explorer/$_orderId');
    });

    test('an expired quote has no order to look for', () {
      expect(orchestraTrackResolvable(_row(_quoteId)), isTrue);
      expect(
          orchestraTrackResolvable(_row(_quoteId, status: 'expired')), isFalse);
      expect(orchestraTrackResolvable(_row(_orderId)), isFalse);
    });
  });

  group('resolving a quote row', () {
    test('the order the quote became is stored and opened', () async {
      SwapOrder? stored;
      final id = await resolveOrchestraTrackOrderId(_row(_quoteId),
          read: (quoteId) async {
            expect(quoteId, _quoteId);
            return _order(_orderId);
          },
          store: (replacement, _) async => stored = replacement);
      expect(id, _orderId);
      expect(stored!.id, _orderId);
      expect(stored!.depositAddress, 'spark-deposit-1');
      expect(stored!.timestamp, _t0.millisecondsSinceEpoch);
    });

    test('no order yet, or no answer: nothing to open, nothing stored',
        () async {
      for (final read in [
        _noOrder(),
        Result<OrchestraOrder>(error: 'unavailable', statusCode: 503),
        Result<OrchestraOrder>(error: 'not found', statusCode: 404),
        _order(_quoteId),
      ]) {
        var stored = false;
        final id = await resolveOrchestraTrackOrderId(_row(_quoteId),
            read: (_) async => read, store: (_, __) async => stored = true);
        expect(id, isNull);
        expect(stored, isFalse);
      }
      final thrown = await resolveOrchestraTrackOrderId(_row(_quoteId),
          read: (_) => throw Exception('offline'), store: (_, __) async {});
      expect(thrown, isNull);
    });

    test('an order row opens without a read', () async {
      final id = await resolveOrchestraTrackOrderId(_row(_orderId),
          read: (_) => throw StateError('no read'),
          store: (_, __) => throw StateError('no write'));
      expect(id, _orderId);
    });
  });

  group('live row', () {
    test('a quote row follows to its order row', () {
      final moved = _row(_orderId, status: 'success');
      expect(liveSwapOrderRow(_row(_quoteId), [moved]), same(moved));
      // Another row on the same address made at another time is not it.
      final other = _row(_orderId).copyWith(timestamp: 1);
      expect(liveSwapOrderRow(_row(_quoteId), [other]).id, _quoteId);
      // An order row is never matched by address.
      expect(
          liveSwapOrderRow(_row(_orderId), [_row('ord_other')]).id, _orderId);
    });
  });

  group('detail sheet', () {
    final launched = <Uri>[];
    setUp(() {
      Intl.defaultLocale = 'en_US';
      launched.clear();
      debugOrchestraTrackLaunch = launched.add;
    });
    tearDown(() {
      Intl.defaultLocale = null;
      debugOrchestraTrackLaunch = null;
      debugOrchestraTrackStatusRead = null;
    });

    Future<_Store> openSheet(WidgetTester tester, SwapOrder row) async {
      tester.view.physicalSize = const Size(430, 932) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = _Store([row]);
      final tx = SwapOrderTransaction(
          id: row.id,
          timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestamp),
          isConfirmed: row.isComplete,
          details: row);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                balancePrivacy: 0,
                biometricsEnabled: false,
                bitcoinElectrumNode: 'localhost',
                nodeType: 'Blockstream',
                reviewDone: false,
                wallets: [WalletConfig(id: 'spending', name: 'Spending')],
                activeWalletId: 'spending',
              ))),
          swapOrdersProvider.overrideWith((_) => store),
          sparkSelfAddressProvider.overrideWith((_) async => 'sp1self'),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                  builder: (context, ref, _) =>
                      buildUnifiedTransactionItem(tx, context, ref)),
            ),
          ),
        ),
      ));
      await tester.tap(find
          .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_TransactionRow')
          .first);
      // A pending row's spinner never settles: pump frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return store;
    }

    Future<void> tapTrack(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Track this exchange'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Track this exchange'));
      // The read, the store writes and the Activity cache's write debounce.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('a quote row opens the order it became, and keeps it',
        (tester) async {
      final reads = <String>[];
      debugOrchestraTrackStatusRead = (id) async {
        reads.add(id);
        return _order(_orderId);
      };
      final store = await openSheet(tester, _row(_quoteId));
      await tapTrack(tester);
      expect(reads, [_quoteId]);
      expect(launched.map((u) => u.toString()),
          ['https://orchestra.flashnet.xyz/explorer/$_orderId']);
      expect(store.state.map((o) => o.id), [_orderId]);

      // The sheet now holds the order: a second tap reads nothing.
      await tapTrack(tester);
      expect(reads, [_quoteId]);
      expect(launched.last.path, '/explorer/$_orderId');
    });

    testWidgets('a quote with no order yet opens no page', (tester) async {
      debugOrchestraTrackStatusRead = (_) async => _noOrder();
      final store = await openSheet(tester, _row(_quoteId));
      final shown = find.text('Processing').evaluate().length;
      await tapTrack(tester);
      expect(launched, isEmpty);
      expect(store.state.map((o) => o.id), [_quoteId]);
      // It says the exchange is processing, in the sheet's own word.
      expect(find.text('Processing').evaluate().length, shown + 1);
      // Let the message's own timer run out.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the open sheet follows the row sync moves to its order',
        (tester) async {
      debugOrchestraTrackStatusRead = (_) => throw StateError('no read');
      final store = await openSheet(tester, _row(_quoteId));
      store.set([_row(_orderId)]);
      await tester.pump(const Duration(milliseconds: 100));
      await tapTrack(tester);
      expect(launched.map((u) => u.path), ['/explorer/$_orderId']);
    });

    testWidgets('an expired quote has no button', (tester) async {
      await openSheet(tester, _row(_quoteId, status: 'expired'));
      expect(find.text('Track this exchange'), findsNothing);
    });
  });
}
