// Predictions and Investing search markets only. The person's own past
// bets (settled, lost, claimable or open positions) are history and show
// with the Transactions, never mixed into the market results.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/investment_market_browser.dart'
    show PredictionBrowseCard;
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

/// No wallet history on the device: the only "history" is the person's
/// own prediction positions.
class _EmptyCache extends WalletTransactionCacheNotifier {
  _EmptyCache() {
    state = {};
  }
}

const _upOrDown20 = PolymarketPosition(
  marketId: 'cond-oct20',
  marketQuestion: 'Bitcoin Up or Down - October 20, 4PM ET',
  outcome: 'Up',
  size: 4.67,
  avgPrice: 0.56,
  currentPrice: 1,
  pnl: 2.05,
  pnlPercent: 78,
  isResolved: true,
  won: false,
  eventSlug: 'bitcoin-up-or-down-october-20-4pm-et',
);

const _upOrDown19 = PolymarketPosition(
  marketId: 'cond-oct19',
  marketQuestion: 'Bitcoin Up or Down - October 19, 4PM ET',
  outcome: 'Down',
  size: 10,
  avgPrice: 0.5,
  currentPrice: 0,
  pnl: -5,
  pnlPercent: -100,
  isResolved: true,
  won: false,
  eventSlug: 'bitcoin-up-or-down-october-19-4pm-et',
);

const _marketTitle = 'Bitcoin above 120k on October 31?';

final _market = GlobalMarketSearchResult(
  PolymarketEvent(
    id: 'btc-120k',
    slug: 'bitcoin-above-120k-on-october-31',
    title: _marketTitle,
    volume: 1000,
    liquidity: 5000,
    category: 'crypto',
    // The same market the person once bet on: Predictions still lists it.
    conditionId: 'cond-oct20',
    outcomes: const [
      PolymarketOutcome(name: 'Yes', price: 0.5),
      PolymarketOutcome(name: 'No', price: 0.5),
    ],
  ),
);

List<Override> _overrides() => [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      walletTransactionCacheProvider.overrideWith((_) => _EmptyCache()),
      polymarketActivePositionsProvider.overrideWith((_) => const []),
      polymarketClaimablePositionsProvider.overrideWith((_) => const []),
      polymarketResolvedPositionsProvider
          .overrideWith((_) => const [_upOrDown20, _upOrDown19]),
    ];

Future<ProviderContainer> _open(WidgetTester tester, String query) async {
  tester.view.physicalSize = const Size(430, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ..._overrides(),
      currencyProvider.overrideWith((_) => _Currency()),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      // The venue leg, gated by tab like the real provider.
      globalMarketResultsProvider.overrideWith((ref) {
        final category = ref.watch(selectedSearchCategoryProvider);
        return ref.watch(searchQueryProvider).isEmpty ||
                (category != SearchCategory.all &&
                    category != SearchCategory.predictions)
            ? const AsyncValue.data([])
            : AsyncValue.data([_market]);
      }),
      globalHyperliquidResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
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

Future<void> _pickTab(WidgetTester tester, String label) async {
  // The pill row scrolls: Transactions, the last pill, can sit past the
  // edge.
  await tester.ensureVisible(find.text(label).first);
  await tester.pump();
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

/// A past bet, drawn with the Portfolio's position card.
Finder _bet(String s) => find
    .byWidgetPredicate((w) => w is PolyPositionCard && w.question.contains(s));

/// A market, drawn with the Predictions list's card.
Finder _marketCard(String s) => find.byWidgetPredicate(
    (w) => w is PredictionBrowseCard && w.event.title.contains(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  group('local results by tab', () {
    Future<UnifiedSearchResults> search(SearchCategory category) async {
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);
      container.read(searchQueryProvider.notifier).state = 'bitcoin';
      container.read(selectedSearchCategoryProvider.notifier).state = category;
      return container.read(unifiedSearchResultsProvider.future);
    }

    test('Predictions and Investing carry no past positions', () async {
      for (final c in [SearchCategory.predictions, SearchCategory.perpetuals]) {
        final r = await search(c);
        expect(r.ownedPositions, isEmpty, reason: c.name);
        expect(r.transactions, isEmpty, reason: c.name);
      }
    });

    test('Transactions and All carry the past positions', () async {
      for (final c in [SearchCategory.transactions, SearchCategory.all]) {
        final r = await search(c);
        expect(r.ownedPositions.map((p) => p.position.marketId),
            ['cond-oct20', 'cond-oct19'],
            reason: c.name);
      }
    });
  });

  testWidgets(
      '"bitcoin": Predictions shows only markets, Transactions the past bets',
      (tester) async {
    final container = await _open(tester, 'bitcoin');

    await _pickTab(tester, 'Predictions');
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.predictions);
    expect(_marketCard(_marketTitle), findsWidgets);
    expect(_bet('Up or Down - October 20'), findsNothing);
    expect(_bet('Up or Down - October 19'), findsNothing);

    await _pickTab(tester, 'Transactions');
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.transactions);
    expect(_bet('Up or Down - October 20'), findsWidgets);
    expect(_bet('Up or Down - October 19'), findsWidgets);
    expect(_marketCard(_marketTitle), findsNothing);
    await _close(tester);
  });

  testWidgets('All files the past bets under Transactions, not Predictions',
      (tester) async {
    await _open(tester, 'bitcoin');
    final headers = [
      for (final e in find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('header-'))
          .evaluate())
        (e.widget.key! as ValueKey<String>).value.substring('header-'.length),
    ];
    expect(headers, containsAll(['predictions', 'transactions']));
    final txHeader =
        tester.getTopLeft(find.byKey(const ValueKey('header-transactions'))).dy;
    final predictionsHeader =
        tester.getTopLeft(find.byKey(const ValueKey('header-predictions'))).dy;
    final bet = tester.getTopLeft(_bet('Up or Down - October 20').first).dy;
    final market = tester.getTopLeft(_marketCard(_marketTitle).first).dy;
    // Each sits in its own group: below its header, above the next one.
    bool inGroup(double y, double own, double other) =>
        y > own && (other < own || y < other);
    expect(inGroup(bet, txHeader, predictionsHeader), isTrue);
    expect(inGroup(market, predictionsHeader, txHeader), isTrue);
    await _close(tester);
  });
}
