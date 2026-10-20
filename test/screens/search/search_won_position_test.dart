// A won Predictions position found by search reads like any settled one.
// The spending wallet claims a win automatically (claim_auto_fire.dart),
// so the row never says "Ready to claim", "Claim" or "paying out": it is
// "Settled", with what it paid.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
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

/// The founder's row: a won 5-minute round, resolved and redeemable, not
/// claimed yet.
const _won = PolymarketPosition(
  marketId: '0xwon',
  marketQuestion: 'Bitcoin Up or Down – October 20, 9:00AM-9:05AM ET',
  outcome: 'Up',
  size: 4.67,
  avgPrice: 0.56,
  currentPrice: 1,
  pnl: 2.06,
  pnlPercent: 78.6,
  isResolved: true,
  won: true,
  tokenId: 'tok-up',
);

Future<void> _open(WidgetTester tester, String query) async {
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
      unifiedSearchResultsProvider.overrideWith((ref) async =>
          ref.watch(searchQueryProvider).isEmpty
              ? UnifiedSearchResults.empty
              : const UnifiedSearchResults(
                  transactions: [],
                  ownedPositions: [OwnedPositionSearchResult(_won)],
                )),
      globalMarketResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
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
  await tester.tap(find.text('Open search'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets('a won, redeemable position reads Settled, never a claim',
      (tester) async {
    await _open(tester, 'bitcoin');
    expect(find.byType(PolyPositionCard), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);
    expect(find.textContaining('Ready to claim'), findsNothing);
    expect(find.textContaining('Claim'), findsNothing);
    expect(find.textContaining('paying out', findRichText: true),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
