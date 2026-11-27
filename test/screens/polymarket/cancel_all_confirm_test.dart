// Cancel all asks first, and its question lists the orders only from a
// read that is settled and succeeded (polyCancelAllKnownOrders): every
// caller, the Predictions Open orders sheet (hot wallet and Ledger) and
// the Portfolio's Cancel all. A list being read again, or one whose last
// read failed, may not be the venue's whole list while Cancel all removes
// every order: then the question alone. Nothing is cancelled here (the
// test keeps the orders).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/ledger/ledger_pm_open_orders_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart'
    show PortfolioCancelAllLink;
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

final _order = Order(
  id: 'o1',
  market: 'm1',
  assetId: 't1',
  owner: 'x',
  side: 'BUY',
  price: '0.4',
  originalSize: '10',
  sizeMatched: '0',
  outcome: 'Yes',
);

const _listed = 'This removes 1 open order:';

Future<void> _pump(WidgetTester tester, Widget home,
    {required List<Override> overrides}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      livePriceProvider.overrideWith(_Prices.new),
      polymarketTradingProvider.overrideWith(_Trading.new),
      polymarketOrderMetadataProvider.overrideWith((ref) async => const {}),
      polymarketMarketMetadataProvider.overrideWith((ref, id) async => null),
      ...overrides,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens the question from [cancelAll], reads whether it lists the order,
/// and keeps the orders.
Future<bool> _asksWithList(WidgetTester tester, Finder cancelAll) async {
  await tester.tap(cancelAll);
  await tester.pumpAndSettle();
  expect(find.text('Cancel all orders?'), findsOneWidget);
  final listed = find.textContaining(_listed).evaluate().isNotEmpty;
  await tester.tap(find.byKey(const ValueKey('orders-cancel-all-keep')));
  await tester.pumpAndSettle();
  return listed;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'the Open orders sheet: listed after a good read, the question alone '
      'after a failed poll that kept the last list', (tester) async {
    final feed = StreamController<List<Order>>.broadcast();
    addTearDown(feed.close);
    await _pump(tester, const OpenOrdersSheet(embedded: true), overrides: [
      polymarketOpenOrdersProvider.overrideWith((ref) => feed.stream),
    ]);
    feed.add([_order]);
    await tester.pumpAndSettle();
    final cancelAll = find.text('Cancel all');
    expect(await _asksWithList(tester, cancelAll), isTrue);
    feed.addError(StateError('poll failed'));
    await tester.pumpAndSettle();
    // The last list is still drawn, the Cancel all still offered.
    expect(cancelAll, findsOneWidget);
    expect(await _asksWithList(tester, cancelAll), isFalse);
  });

  testWidgets(
      'the Ledger Open orders sheet: the question alone while the list is '
      'read again', (tester) async {
    var reads = 0;
    final again = Completer<List<Order>?>();
    await _pump(tester, const OpenOrdersSheet(embedded: true, ledgerWalletId: 'L'),
        overrides: [
          ledgerPmOpenOrdersProvider.overrideWith(
              (ref, id) => reads++ == 0 ? Future.value([_order]) : again.future),
          ledgerPmAccountProvider
              .overrideWith((ref, id) => Completer<LedgerPmAccount>().future),
        ]);
    await tester.pumpAndSettle();
    final cancelAll = find.text('Cancel all');
    expect(await _asksWithList(tester, cancelAll), isTrue);
    ProviderScope.containerOf(tester.element(cancelAll))
        .invalidate(ledgerPmOpenOrdersProvider('L'));
    await tester.pump();
    expect(cancelAll, findsOneWidget);
    expect(await _asksWithList(tester, cancelAll), isFalse);
  });

  testWidgets(
      'the Portfolio\'s Cancel all: listed after a good read, the question '
      'alone after a failed poll', (tester) async {
    final feed = StreamController<List<Order>>.broadcast();
    addTearDown(feed.close);
    await _pump(
        tester,
        const Center(
            child: PortfolioCancelAllLink(investing: false, predictions: true)),
        overrides: [
          polymarketOpenOrdersProvider.overrideWith((ref) => feed.stream),
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PortfolioCancelAllLink)));
    container.listen(polymarketOpenOrdersProvider, (_, __) {});
    feed.add([_order]);
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('portfolio-orders-cancel-all'));
    expect(await _asksWithList(tester, link), isTrue);
    feed.addError(StateError('poll failed'));
    await tester.pumpAndSettle();
    expect(await _asksWithList(tester, link), isFalse);
  });
}
