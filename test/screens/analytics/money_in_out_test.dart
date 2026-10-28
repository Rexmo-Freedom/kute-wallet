// The Bitcoin home's In & out tab (the strip's third pill): only the hot
// spending wallet gets it; In and Out figures for the picked month or
// year; a pair of bars per period that picks it; Out lists where it went,
// In where it came from; an empty period is Sal's compact state; hidden
// balances mask the figures; no rail is ever named; the two events carry
// fixed ids only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/address_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/analytics/components/money_in_out.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _now = DateTime(2026, 10, 28, 9);

final _spending = WalletConfig(id: 'spending', name: 'Spending');

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

SparkTransaction _spark(
        String id, int sats, TransactionType direction, DateTime at,
        {SparkTransactionType rail = SparkTransactionType.lightning}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: rail,
      direction: direction,
      pending: false,
    );

SwapOrderTransaction _swap(
  String id, {
  required String coinFrom,
  required String networkFrom,
  required String coinTo,
  required String networkTo,
  required String deposit,
  required String withdrawal,
  required DateTime at,
  String? routeVersion,
  String? purchaseSource,
}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: SwapOrder(
        id: id,
        coinFrom: coinFrom,
        networkFrom: networkFrom,
        coinTo: coinTo,
        networkTo: networkTo,
        depositAddress: 'deposit-$id',
        depositAmount: deposit,
        withdrawalAmount: withdrawal,
        status: 'success',
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: networkTo == 'SPARK' ? 'sp1self' : '0xelsewhere',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
        routeVersion: routeVersion,
        purchaseSource: purchaseSource,
      ),
    );

/// October: out 3,000 to people (Lightning and Spark) + 60,000 into
/// Dollars; in 2,500 from people (on-chain) + 10,000 from Investments.
/// September: out 4,000 into Investments; in 80,000 bought.
/// Nothing before September.
Transaction _history() => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: [
        _spark('ln_out', 1000, TransactionType.sent, DateTime(2026, 10, 2)),
        _spark('sp_out', 2000, TransactionType.sent, DateTime(2026, 10, 9),
            rail: SparkTransactionType.spark),
        _spark('chain_in', 2500, TransactionType.received,
            DateTime(2026, 10, 12),
            rail: SparkTransactionType.bitcoin),
      ],
      sparkUnclaimedDeposits: const [],
      swapOrderTransactions: [
        _swap('btc_usd',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: kOrchestraUsdAssetCode,
            networkTo: 'SPARK',
            deposit: '0.0006',
            withdrawal: '60',
            at: DateTime(2026, 10, 20)),
        _swap('inv_btc',
            coinFrom: 'USDC',
            networkFrom: 'HYPERCORE',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '10',
            withdrawal: '0.0001',
            routeVersion: 'hypercore_to_spark_v1',
            at: DateTime(2026, 10, 22)),
        _swap('btc_inv',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'USDC',
            networkTo: 'HYPERCORE',
            deposit: '0.00004',
            withdrawal: '4',
            routeVersion: 'spark_to_hypercore_v1',
            at: DateTime(2026, 9, 10)),
        _swap('cashapp',
            coinFrom: 'BTC',
            networkFrom: 'LIGHTNING',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '0.0008',
            withdrawal: '0.0008',
            purchaseSource: 'cashapp',
            at: DateTime(2026, 9, 3)),
      ],
    );

Settings _settings({int privacy = 0, WalletConfig? active}) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
      activeWalletId: (active ?? _spending).id,
      balancePrivacy: privacy,
      wallets: [_spending, if (active != null) active],
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Transaction? history,
  int privacy = 0,
  WalletConfig? viewed,
}) async {
  tester.view.physicalSize = const Size(393, 1400) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
          (_) => SettingsModel(_settings(privacy: privacy, active: viewed))),
      walletTransactionCacheProvider.overrideWith(
          (_) => _Cache({if (history != null) 'spending': history})),
      initialAddressesProvider.overrideWith((_) async =>
          Address(bitcoinAddressIndex: 0, bitcoinAddress: 'bc1qself')),
      sparkSelfAddressProvider.overrideWith((_) async => 'sp1self'),
      conversionToFiatProvider
          .overrideWith((ref, sats) => '\$${(sats / 1000).toStringAsFixed(2)}'),
      viewedWalletProvider.overrideWithValue(viewed),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: const Locale('en'),
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Home's strip as home.dart builds it, the clock pinned.
Widget _homeStrip(WalletConfig wallet) => HomeAnalyticsWidget(
      surface: 'home',
      showPrice: false,
      activityChild: const Text('activity rows'),
      breakdownChild: (wallet.isSparkWallet) ? MoneyInOut(now: _now) : null,
    );

List<String> _pills(WidgetTester tester) => [
      for (final p in tester.widgetList<KutePill>(find.descendant(
          of: find.byType(KutePillTabs), matching: find.byType(KutePill))))
        p.label,
    ];

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('In & out'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

String _period(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('in-out-period'))).data!;

/// The category rows on screen, by key suffix (`out-people`, …).
List<String> _rows(WidgetTester tester) => [
      for (final e in find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('in-out-row-'))
          .evaluate())
        (e.widget.key as ValueKey<String>).value.substring('in-out-row-'.length),
    ];

/// Events as lists, so the matcher compares their maps by content.
List<List<Object?>> _named(List<(String, Map<String, Object>?)> events) =>
    [for (final e in events) [e.$1, e.$2]];

Finder _within(String key, String text) => find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.text(text));

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<String> haptics;

  setUp(() {
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    haptics = [];
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  void listenHaptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  group('who gets the tab', () {
    test(
        'only the hot spending wallet: no hardware, Ledger, watch-only, '
        'external or on-chain wallet', () {
      expect(homeBreakdownChild(_spending), isA<MoneyInOut>());
      final others = [
        WalletConfig(id: 'jade', name: 'Jade', isHardware: true),
        WalletConfig(
            id: 'ledger',
            name: 'Ledger',
            isHardware: true,
            walletType: 'ledger'),
        WalletConfig(id: 'watch', name: 'Watch', isWatchOnly: true),
        WalletConfig(id: 'addr', name: 'Address', isExternalAddress: true),
        WalletConfig(id: 'btc', name: 'Bitcoin', sparkEnabled: false),
        WalletConfig(id: 'signer', name: 'Signer', isSigner: true),
      ];
      for (final w in others) {
        expect(homeBreakdownChild(w), isNull, reason: w.id);
      }
      expect(homeBreakdownChild(null), isNull);
    });

    testWidgets('Home: Activity, Balance, In & out, and no Price',
        (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      expect(_pills(tester), ['Activity', 'Balance', 'In & out']);
      expect(find.text('Price'), findsNothing);
      expect(find.text('Breakdown'), findsNothing);
    });

    testWidgets('a hardware wallet\'s strip keeps Price and has no In & out',
        (tester) async {
      final jade = WalletConfig(id: 'jade', name: 'Jade', isHardware: true);
      await _pump(
          tester,
          HomeAnalyticsWidget(
            activityChild: const Text('rows'),
            breakdownChild: homeBreakdownChild(jade),
          ),
          viewed: jade);
      expect(_pills(tester), contains('Price'));
      expect(_pills(tester), isNot(contains('In & out')));
    });
  });

  group('the tab', () {
    testWidgets(
        'this month: In and Out figures with fiat under, six bars, Out '
        'lists where it went largest first', (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      // The strip's own event is unchanged.
      expect(events.where((e) => e.$1 == 'analytics_tab_selected').single.$2,
          {'tab': 'breakdown', 'from_tab': 'activity', 'surface': 'home'});

      expect(_period(tester), 'October');
      expect(_within('in-out-side-in', 'In'), findsOneWidget);
      expect(_within('in-out-side-in', '+₿12,500'), findsOneWidget);
      expect(_within('in-out-side-in', '\$12.50'), findsOneWidget);
      expect(_within('in-out-side-out', 'Out'), findsOneWidget);
      expect(_within('in-out-side-out', '−₿63,000'), findsOneWidget);
      expect(_within('in-out-side-out', '\$63.00'), findsOneWidget);
      // In in the success colour, Out in the primary text colour.
      final c = AppColorsExtension.light();
      expect(
          tester
              .widget<Text>(_within('in-out-side-in', '+₿12,500'))
              .style!
              .color,
          c.success);
      expect(
          tester
              .widget<Text>(_within('in-out-side-out', '−₿63,000'))
              .style!
              .color,
          c.textPrimary);

      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('in-out-bar-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('in-out-bar-6')), findsNothing);
      expect(find.text('May'), findsOneWidget);
      expect(find.text('Oct'), findsOneWidget);

      expect(find.text('Where it went'), findsOneWidget);
      expect(_rows(tester), ['out-dollars', 'out-people']);
      expect(_within('in-out-row-out-dollars', 'Into Dollars'), findsOneWidget);
      expect(_within('in-out-row-out-dollars', '₿60,000'), findsOneWidget);
      expect(_within('in-out-row-out-people', 'Sent to people'),
          findsOneWidget);
      expect(_within('in-out-row-out-people', '₿3,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tapping In lists where it came from, with a selection click and '
        'one event', (tester) async {
      listenHaptics(tester);
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      events.clear();
      haptics.clear();

      await _tap(tester, 'in-out-side-in');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.text('Where it came from'), findsOneWidget);
      expect(find.text('Where it went'), findsNothing);
      expect(_rows(tester), ['in-investments', 'in-people']);
      expect(_within('in-out-row-in-investments', 'From Investments'),
          findsOneWidget);
      expect(_within('in-out-row-in-people', 'From people'), findsOneWidget);
      expect(_named(events), [
        ['bitcoin_in_out_side_changed', {'side': 'in'}],
      ]);

      // The same side again changes nothing and reports nothing.
      await _tap(tester, 'in-out-side-in');
      expect(events, hasLength(1));
    });

    testWidgets('tapping a pair of bars picks its month', (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      events.clear();

      await _tap(tester, 'in-out-bar-4');
      expect(_period(tester), 'September');
      expect(_within('in-out-side-in', '+₿80,000'), findsOneWidget);
      expect(_within('in-out-side-out', '−₿4,000'), findsOneWidget);
      expect(_rows(tester), ['out-investments']);
      expect(_within('in-out-row-out-investments', 'Into Investments'),
          findsOneWidget);
      await _tap(tester, 'in-out-side-in');
      expect(_rows(tester), ['in-bought']);
      expect(_within('in-out-row-in-bought', 'Bought'), findsOneWidget);
      expect(_named(events).first,
          ['bitcoin_in_out_period_changed', {'period': 'month', 'offset': 1}]);
    });

    testWidgets('Year: the year\'s totals, a pair per year', (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      events.clear();

      await _tap(tester, 'in-out-year');
      expect(_period(tester), '2026');
      expect(_within('in-out-side-in', '+₿92,500'), findsOneWidget);
      expect(_within('in-out-side-out', '−₿67,000'), findsOneWidget);
      // A wallet that started this year: this year's pair alone, never
      // empty years before it existed.
      expect(find.byKey(const ValueKey('in-out-bar-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('in-out-bar-1')), findsNothing);
      expect(find.text('2025'), findsNothing);
      expect(_named(events), [
        ['bitcoin_in_out_period_changed', {'period': 'year', 'offset': 0}],
      ]);

      // Back to Month: this month again.
      await _tap(tester, 'in-out-month');
      expect(_period(tester), 'October');
    });

    testWidgets(
        'a month with nothing in it: Sal, compact, and the bars stay to '
        'pick another', (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      await _tap(tester, 'in-out-bar-0');
      expect(_period(tester), 'May');
      expect(find.byKey(const ValueKey('in-out-period-empty')), findsOneWidget);
      expect(find.text('No money in or out'), findsOneWidget);
      expect(find.byKey(const ValueKey('in-out-side-in')), findsNothing);
      expect(find.text('Where it went'), findsNothing);
      expect(find.byKey(const ValueKey('in-out-bar-5')), findsOneWidget);
      await _tap(tester, 'in-out-bar-5');
      expect(find.byKey(const ValueKey('in-out-period-empty')), findsNothing);
    });

    testWidgets('a wallet with nothing yet: only Sal', (tester) async {
      await _pump(tester, _homeStrip(_spending));
      await _open(tester);
      expect(find.byKey(const ValueKey('in-out-empty')), findsOneWidget);
      expect(find.text('No money in or out'), findsOneWidget);
      expect(find.byKey(const ValueKey('in-out-bar-0')), findsNothing);
      expect(find.byKey(const ValueKey('in-out-month')), findsNothing);
    });

    testWidgets('no rail, donut or all-time figure on screen, on either side',
        (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _open(tester);
      void noRails() {
        for (final word in [
          'Lightning',
          'Spark',
          'On-chain',
          'Cash App',
          'All time',
          'Received',
        ]) {
          expect(find.textContaining(word), findsNothing, reason: word);
        }
      }

      noRails();
      await _tap(tester, 'in-out-side-in');
      noRails();
      await _tap(tester, 'in-out-bar-4');
      noRails();
    });

    testWidgets('hidden balances mask every figure', (tester) async {
      await _pump(tester, _homeStrip(_spending),
          history: _history(), privacy: 1);
      await _open(tester);
      expect(find.textContaining('₿'), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.text('••••••'), findsWidgets);
      // The words stay.
      expect(find.text('Into Dollars'), findsOneWidget);
    });
  });
}
