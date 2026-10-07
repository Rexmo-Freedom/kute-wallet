// A Predictions result row (a prediction held to its resolved market, read
// from the positions: "Lost · Up", "Won · Up") opens the activity detail
// sheet like every venue record: the shares held at the resolution, what
// they cost, the payout, the realised profit or loss, and the Claim of a
// win not claimed yet. It has no transaction, so no explorer link.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, PolymarketEvent, PolymarketOutcome, Position;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventTeamsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart'
    show LedgerPmActivityList;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/transactions_builder.dart'
    show buildUnifiedTransactionItem;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';

const _btc = 'Bitcoin Up or Down - October 5, 7:00AM-7:05AM ET';

Position _resolved(
        {required double curPrice,
        required double size,
        required double cost,
        String eventSlug = ''}) =>
    Position(
      proxyWallet: '0xme',
      asset: 'up',
      conditionId: '0xbtc',
      size: size,
      avgPrice: cost / size,
      initialValue: cost,
      currentValue: size * curPrice,
      cashPnl: size * curPrice - cost,
      percentPnl: 0,
      totalBought: size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: curPrice,
      redeemable: true,
      title: _btc,
      slug: 'btc',
      eventSlug: eventSlug,
      outcome: 'Up',
      outcomeIndex: 0,
      oppositeOutcome: 'Down',
      oppositeAsset: 'down',
    );

final _buy = Activity(
  proxyWallet: '0xme',
  timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600,
  conditionId: '0xbtc',
  type: 'TRADE',
  size: 6.3,
  usdcSize: 3.21,
  transactionHash: '0xbuy',
  side: 'BUY',
  asset: 'up',
  outcomeIndex: 0,
  title: _btc,
  outcome: 'Up',
  eventSlug: '',
);

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.state0);
  final PolymarketTradingState state0;
  @override
  Future<PolymarketTradingState> build() async => state0;
}

Widget _app(Widget body, List<Override> overrides) => ProviderScope(
    overrides: [
      ...offlineVenueOverrides,
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      ...overrides,
    ],
    child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
              theme: ThemeData(
                  fontFamily: 'Inter',
                  extensions: [AppColorsExtension.light()]),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: body),
            )));

/// The spending account's result row for [position], tapped open.
Future<void> _openSpending(WidgetTester tester, Position position,
    {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final result = predictionResults(
          open: [position], closed: const [], history: [_buy])
      .single;
  await tester.pumpWidget(_app(
      Consumer(
          builder: (context, ref, _) => buildUnifiedTransactionItem(
              PolymarketTransaction.result(result), context, ref)),
      [
        polymarketTradingProvider.overrideWith(() => _Trading(
            PolymarketTradingState(
                isAuthenticated: true,
                proxyWalletAddress: '0xme',
                openPositions: [position]))),
        ...overrides,
      ]));
  await tester.pump();
  await tester.tap(find.text(result.won ? 'Won · Up' : 'Lost · Up'));
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

/// The value drawn on the detail row labelled [label].
String _valueOf(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: _inSheet(find.text(label)), matching: find.byType(Row))
      .first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts.last!;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  testWidgets('a lost row opens its sheet with the stake it lost',
      (tester) async {
    await _openSpending(
        tester, _resolved(curPrice: 0, size: 6.3, cost: 3.21));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_inSheet(find.text('Lost · Up')), findsOneWidget);
    expect(_valueOf(tester, 'Market'), _btc);
    expect(_valueOf(tester, 'Predicted'), 'Up');
    expect(_valueOf(tester, 'Shares'), '6.30');
    expect(_valueOf(tester, 'Cost'), '\$3.21');
    expect(_valueOf(tester, 'Payout'), '\$0.00');
    expect(_valueOf(tester, 'Realized P&L'), '−\$3.21');
    expect(_inSheet(find.text('Resolved')), findsOneWidget);
    // No transaction: no explorer link, no hash, no claim.
    expect(find.text('View on the blockchain'), findsNothing);
    expect(find.textContaining('polygonscan'), findsNothing);
    expect(find.textContaining('Claim'), findsNothing);
    expect(
        events.where((e) =>
            e.$1 == 'transaction_detail_viewed' &&
            e.$2?['type'] == 'polymarket_result'),
        hasLength(1));
  });

  testWidgets('a won row, not claimed yet, opens its sheet with the Claim',
      (tester) async {
    await _openSpending(tester, _resolved(curPrice: 1, size: 5, cost: 3));
    expect(_inSheet(find.text('Won · Up')), findsOneWidget);
    expect(_valueOf(tester, 'Shares'), '5.00');
    expect(_valueOf(tester, 'Cost'), '\$3.00');
    expect(_valueOf(tester, 'Payout'), '\$5.00');
    expect(_valueOf(tester, 'Realized P&L'), '+\$2.00');
    expect(_inSheet(find.text('Claim \$5.00')), findsOneWidget);
    expect(find.text('View on the blockchain'), findsNothing);
  });

  testWidgets('the market opens from the sheet once its event is known',
      (tester) async {
    const event = PolymarketEvent(
      id: '1',
      slug: 'btc-updown',
      title: _btc,
      volume: 0,
      liquidity: 0,
      category: 'crypto',
      conditionId: '0xbtc',
      outcomes: [PolymarketOutcome(name: 'Up', price: 1, tokenId: 'up')],
    );
    await _openSpending(
        tester,
        _resolved(
            curPrice: 0, size: 6.3, cost: 3.21, eventSlug: 'btc-updown'),
        overrides: [
          polyPositionEventProvider.overrideWith((ref, slug) => event),
          polymarketEventTeamsProvider
              .overrideWith((ref, slug) async => const []),
        ]);
    expect(_inSheet(find.text('View market')), findsOneWidget);
  });

  testWidgets('a Ledger account\'s won row opens the same sheet, no claim',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
        LedgerPmActivityList(
            rows: [_buy],
            positions: [_resolved(curPrice: 1, size: 5, cost: 3)],
            walletId: 'ledger-1'),
        const []));
    await tester.pump();
    await tester.tap(find.text('Won · Up'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_valueOf(tester, 'Payout'), '\$5.00');
    expect(_inSheet(find.textContaining('Claim')), findsNothing);
    expect(find.text('View on the blockchain'), findsNothing);
  });
}
