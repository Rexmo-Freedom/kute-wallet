// What All searches: transactions, Predictions and Investing at once, and
// nothing else. No balances, no Send/Receive shortcuts, no Settings rows,
// even for a query like "bitcoin" that used to surface all three. The
// groups always read Predictions, Investing, Transactions, and the pills
// read All, Predictions, Investing, Transactions; each group shows
// three with a "See all" that switches to its pill; the pills narrow to
// one group.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// Rates without Hive.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100000)}));
  @override
  Future<void> updateRates() async {}
}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      activeWalletId: 'spending',
    );

HlMarketSearchResult _hl(String coin) => HlMarketSearchResult(
      coin: coin,
      wireCoin: coin,
      kind: HlMarketKind.perp,
      isStock: false,
      name: null,
      category: 'crypto',
      iconUrl: null,
      markPx: 10,
      dayChangePct: 0.01,
      maxLeverage: 10,
    );

GlobalMarketSearchResult _poly(String title) => GlobalMarketSearchResult(
      PolymarketEvent(
        id: title,
        slug: title.toLowerCase().replaceAll(' ', '-'),
        title: title,
        volume: 1000,
        liquidity: 5000,
        category: 'other',
        conditionId: 'c-$title',
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.5),
          PolymarketOutcome(name: 'No', price: 0.5),
        ],
      ),
    );

TransactionSearchResult _tx(int i) => TransactionSearchResult(
      BitcoinTransaction.fromCache(
        id: 'tx-$i',
        timestamp: DateTime(2026, 1, i + 1),
        isConfirmed: true,
        receivedSats: 1000 + i,
        sentSats: 0,
      ),
      walletName: 'Spending',
    );

final _local = UnifiedSearchResults(
  transactions: [for (var i = 0; i < 6; i++) _tx(i)],
  ownedPositions: const [],
);

Future<ProviderContainer> _open(WidgetTester tester, String query,
    {bool investing = true}) async {
  tester.view.physicalSize = const Size(430, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      currencyProvider.overrideWith((_) => _Currency()),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      unifiedSearchResultsProvider.overrideWith((ref) async {
        final category = ref.watch(selectedSearchCategoryProvider);
        return ref.watch(searchQueryProvider).isEmpty ||
                (category != SearchCategory.all &&
                    category != SearchCategory.transactions)
            ? UnifiedSearchResults.empty
            : _local;
      }),
      globalMarketResultsProvider
          .overrideWith((ref) => ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data([
                  for (final t in ['A', 'B', 'C', 'D', 'E'])
                    _poly('Bitcoin above $t?'),
                ])),
      globalHyperliquidResultsProvider
          .overrideWith((ref) => ref.watch(searchQueryProvider).isEmpty ||
                  !investing
              ? const AsyncValue.data([])
              : AsyncValue.data([
                  for (final c in ['BTC', 'WBTC', 'UBTC', 'XBTC', 'TBTC'])
                    _hl(c),
                ])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context, source: 'home'),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  ));
  final container =
      ProviderScope.containerOf(tester.element(find.text('Open search')));
  await tester.tap(find.text('Open search'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

/// The group headers on screen, top to bottom.
List<String> _headers(WidgetTester tester) {
  final keys = [
    for (final e in find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('header-'))
        .evaluate())
      (e.widget.key! as ValueKey<String>).value.substring('header-'.length),
  ];
  return keys;
}

/// Transaction rows on screen (every fixture row is a receive).
int _txRows(WidgetTester tester) => find.text('Received').evaluate().length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets('"bitcoin" under All: only Predictions, Investing, Transactions',
      (tester) async {
    await _open(tester, 'bitcoin');
    expect(_headers(tester), ['predictions', 'investing', 'transactions']);
    // The pills read in the same order as the groups.
    expect(
        tester
            .widget<KutePillTabs>(find.byType(KutePillTabs))
            .items
            .map((i) => i.label),
        ['All', 'Predictions', 'Investing', 'Transactions']);
    for (final gone in [
      'Balances',
      'Spending balance',
      'Send & receive',
      'Send Bitcoin',
      'Receive Bitcoin',
      'Settings',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    // Every group is capped at three with its own "See all".
    expect(find.text('See all'), findsNWidgets(3));
    expect(_txRows(tester), 3);
    // One wallet: its tag would only repeat on every row.
    expect(find.text('Spending'), findsNothing);
    await _close(tester);
  });

  testWidgets('the sheet has a close X beside its drag handle', (tester) async {
    await _open(tester, 'bitcoin');
    final close = find.byType(AppBottomSheetCloseButton);
    expect(close, findsOneWidget);
    await tester.tap(close);
    await _settle(tester);
    expect(find.byType(UnifiedSearchSurface), findsNothing);
    await _close(tester);
  });

  testWidgets('a query that names no market keeps the same order',
      (tester) async {
    await _open(tester, 'payment');
    expect(_headers(tester), ['predictions', 'investing', 'transactions']);
    await _close(tester);
  });

  testWidgets('a group with no results is left out, the order kept',
      (tester) async {
    await _open(tester, 'bitcoin', investing: false);
    expect(_headers(tester), ['predictions', 'transactions']);
    // Drawn top to bottom in that order.
    expect(tester.getTopLeft(find.byKey(const ValueKey('header-predictions'))).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('header-transactions')))
            .dy));
    await _close(tester);
  });

  testWidgets('the Predictions group\'s See all switches to Predictions',
      (tester) async {
    final container = await _open(tester, 'bitcoin');
    await tester.tap(find.text('See all').first);
    await _settle(tester);
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.predictions);
    expect(_headers(tester), isEmpty);
    expect(_txRows(tester), 0);
    // All five markets, whole.
    for (final t in ['A', 'B', 'C', 'D', 'E']) {
      expect(find.text('Bitcoin above $t?'), findsOneWidget, reason: t);
    }
    await _close(tester);
  });

  testWidgets('See all and the pills narrow to one group, unlabelled',
      (tester) async {
    final container = await _open(tester, 'bitcoin');
    // The Transactions group's See all (the last one on screen).
    await tester.ensureVisible(find.text('See all').last);
    await _settle(tester);
    await tester.tap(find.text('See all').last);
    await _settle(tester);
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.transactions);
    expect(_headers(tester), isEmpty);
    expect(find.text('See all'), findsNothing);
    expect(_txRows(tester), 6);

    // Back to All, then the Predictions pill.
    await tester.tap(find.text('All'));
    await _settle(tester);
    expect(_headers(tester), hasLength(3));
    await tester.tap(find.text('Predictions').first);
    await _settle(tester);
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.predictions);
    expect(_headers(tester), isEmpty);
    expect(_txRows(tester), 0);
    await _close(tester);
  });
}
