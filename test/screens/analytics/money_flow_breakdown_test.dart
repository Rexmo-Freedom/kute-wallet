// The analytics strip's Breakdown tab: Home (the spending wallet) loses
// Price and gains Breakdown, Dollars gains Breakdown, no other kind of
// wallet gets it; Sent | Received switch the categories; a pick names the
// category, its amount and its share and reports once it settles; hidden
// balances mask it all; a direction with nothing in it says so.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
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
import 'package:kute/screens/analytics/components/money_flow_breakdown.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/portfolio/money_flow_categories.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _t0 = DateTime.utc(2026, 10, 1, 12);

final _spending = WalletConfig(id: 'spending', name: 'Spending');

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

SparkTransaction _spark(String id, int sats, SparkTransactionType rail,
        TransactionType direction, int minutes) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: _t0.add(Duration(minutes: minutes)),
      isConfirmed: true,
      amountSats: sats,
      sparkType: rail,
      direction: direction,
      pending: false,
    );

UsdbTokenTransaction _dollars(
    String id, double usd, breez.PaymentType type, int minutes) {
  final ts = _t0.add(Duration(minutes: minutes));
  return UsdbTokenTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: true,
    details: breez.Payment(
      id: id,
      paymentType: type,
      status: breez.PaymentStatus.completed,
      amount: BigInt.from((usd * 1e6).round()),
      fees: BigInt.zero,
      timestamp: BigInt.from(ts.millisecondsSinceEpoch ~/ 1000),
      method: breez.PaymentMethod.token,
      details: breez.PaymentDetails.token(
        metadata: breez.TokenMetadata(
          identifier: 'btkn1usdb',
          issuerPublicKey: 'issuer',
          name: 'USDB',
          ticker: 'USDB',
          decimals: 6,
          maxSupply: BigInt.zero,
          isFreezable: false,
        ),
        txHash: 'tx-$id',
        txType: breez.TokenTransactionType.transfer,
      ),
    ),
  );
}

/// Bitcoin into dollars: a dollar receive on the Dollars ledger, a sent
/// conversion on the bitcoin one (a plain Spark-to-Spark swap reads as a
/// dollar deposit with no settlement record).
SwapOrderTransaction _toDollars(int minutes) {
  final ts = _t0.add(Duration(minutes: minutes));
  return SwapOrderTransaction(
    id: 'btc_usd',
    timestamp: ts,
    isConfirmed: true,
    details: SwapOrder(
      id: 'btc_usd',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: kOrchestraUsdAssetCode,
      networkTo: 'SPARK',
      depositAddress: 'deposit-btc_usd',
      depositAmount: '0.0006',
      withdrawalAmount: '60',
      status: 'success',
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress: 'sp1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
    ),
  );
}

/// Sent: Lightning 1,000 · Spark 3,000 · Dollars 60,000 sats.
/// Received: Lightning 500 · on-chain 2,500 sats.
Transaction _history() => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: [
        _spark('ln_out', 1000, SparkTransactionType.lightning,
            TransactionType.sent, 1),
        _spark('sp_out', 3000, SparkTransactionType.spark, TransactionType.sent,
            200),
        _spark('ln_in', 500, SparkTransactionType.lightning,
            TransactionType.received, 400),
        _spark('chain_in', 2500, SparkTransactionType.bitcoin,
            TransactionType.received, 600),
      ],
      sparkUnclaimedDeposits: const [],
      usdbTokenTransactions: [
        _dollars('usd_out', 15, breez.PaymentType.send, 800),
      ],
      swapOrderTransactions: [_toDollars(1000)],
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

/// Home's strip exactly as home.dart builds it for [wallet].
Widget _homeStrip(WalletConfig wallet) => HomeAnalyticsWidget(
      surface: 'home',
      showPrice: false,
      activityChild: const Text('activity rows'),
      breakdownChild: homeBreakdownChild(wallet),
    );

/// The Dollars strip as usd_account_screen.dart builds it.
const _dollarsStrip = HomeAnalyticsWidget(
  activityAndBalanceOnly: true,
  activityChild: Text('dollar rows'),
  valuationChild: SizedBox(height: 10),
  breakdownChild: MoneyFlowBreakdown(ledger: MoneyFlowLedger.dollars),
);

List<String> _pills(WidgetTester tester) => [
      for (final p in tester.widgetList<KutePill>(find.descendant(
          of: find.byType(KutePillTabs), matching: find.byType(KutePill))))
        p.label,
    ];

Set<String> _legend(WidgetTester tester) => {
      for (final e in find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('category-legend-'))
          .evaluate())
        (e.widget.key as ValueKey<String>)
            .value
            .substring('category-legend-'.length),
    };

Future<void> _openBreakdown(WidgetTester tester) async {
  await tester.tap(find.text('Breakdown'));
  await tester.pumpAndSettle();
}

void main() {
  group('who gets the tab', () {
    test(
        'only the hot spending wallet: no hardware, Ledger, watch-only, '
        'external or on-chain wallet', () {
      expect(homeBreakdownChild(_spending), isA<MoneyFlowBreakdown>());
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

    testWidgets('Home: Activity, Balance, Breakdown, and no Price',
        (tester) async {
      await _pump(tester, _homeStrip(_spending), history: _history());
      expect(_pills(tester), ['Activity', 'Balance', 'Breakdown']);
      expect(find.text('Price'), findsNothing);
    });

    testWidgets('a hardware wallet\'s strip keeps Price and has no Breakdown',
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
      expect(_pills(tester), isNot(contains('Breakdown')));
    });

    testWidgets('a watch-only wallet\'s strip has no Breakdown',
        (tester) async {
      final watch = WalletConfig(id: 'watch', name: 'Watch', isWatchOnly: true);
      await _pump(
          tester,
          HomeAnalyticsWidget(
            activityChild: const Text('rows'),
            breakdownChild: homeBreakdownChild(watch),
          ),
          viewed: watch);
      expect(_pills(tester), isNot(contains('Breakdown')));
    });

    testWidgets('Dollars: Activity, Balance, Breakdown', (tester) async {
      await _pump(tester, _dollarsStrip, history: _history());
      expect(_pills(tester), ['Activity', 'Balance', 'Breakdown']);
    });
  });

  group('the donut', () {
    testWidgets(
        'Home: the tab is reported; Sent by default, Received switches the '
        'categories with a selection click', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, _homeStrip(_spending), history: _history());
      await _openBreakdown(tester);
      expect(events.where((e) => e.$1 == 'analytics_tab_selected').single.$2,
          {'tab': 'breakdown', 'from_tab': 'activity', 'surface': 'home'});
      expect(find.byType(KuteDonutChart), findsOneWidget);
      // Sent: the dollar transfer is the Dollars ledger's, not bitcoin's.
      expect(_legend(tester), {'dollars', 'spark', 'lightning'});
      expect(find.text('All time'), findsOneWidget);

      haptics.clear();
      await tester.tap(find.byKey(const ValueKey('money-flow-received')));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(_legend(tester), {'onchain', 'lightning'});
      // The same ring, morphed: never a second chart.
      expect(find.byType(KuteDonutChart), findsOneWidget);
      // The pills report nothing of their own.
      expect(events.where((e) => e.$1 != 'analytics_tab_selected'), isEmpty);
    });

    testWidgets(
        'a pick names the category with its amount and share and reports '
        'once it settles, with the venue and the direction', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pump(tester, _homeStrip(_spending), history: _history());
      await _openBreakdown(tester);
      await tester.tap(find.byKey(const ValueKey('category-legend-spark')));
      await tester.pumpAndSettle();
      final ring = tester.widget<KuteDonutChart>(find.byType(KuteDonutChart));
      expect(ring.selectedId, 'spark');
      // 3,000 of 64,000 sats.
      expect(find.text('5% of total'), findsOneWidget);
      expect(find.text(r'$3.00'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
          events
              .where((e) => e.$1 == 'portfolio_category_slice_selected')
              .single
              .$2,
          {
            'venue': 'bitcoin',
            'direction': 'sent',
            'wallet_kind': 'hot',
            'slice_rank': 2,
            'category_kind': 'category',
            'category': 'spark',
          });
      // Switching direction clears the pick.
      await tester.tap(find.byKey(const ValueKey('money-flow-received')));
      await tester.pumpAndSettle();
      expect(
          tester.widget<KuteDonutChart>(find.byType(KuteDonutChart)).selectedId,
          isNull);
    });

    testWidgets('Dollars weighs dollars', (tester) async {
      await _pump(tester, _dollarsStrip, history: _history());
      await _openBreakdown(tester);
      expect(_legend(tester), {'spark'});
      expect(find.text(r'$15.00'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('money-flow-received')));
      await tester.pumpAndSettle();
      // Bitcoin converted into dollars.
      expect(_legend(tester), {'bitcoin'});
      expect(find.text(r'$60.00'), findsWidgets);
    });

    testWidgets('hidden balances mask the amounts and the shares',
        (tester) async {
      await _pump(tester, _homeStrip(_spending),
          history: _history(), privacy: 1);
      await _openBreakdown(tester);
      expect(find.text('••••••'), findsWidgets);
      expect(find.text('••%'), findsWidgets);
      expect(
          find.textContaining('%').evaluate().map((e) {
            final w = e.widget as Text;
            return w.data ?? '';
          }).where((t) => RegExp(r'\d%').hasMatch(t)),
          isEmpty);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('nothing ever sent: one quiet line instead of a ring',
        (tester) async {
      await _pump(tester, _homeStrip(_spending),
          history: Transaction(
            bitcoinTransactions: const [],
            sparkTransactions: [
              _spark('in', 800, SparkTransactionType.spark,
                  TransactionType.received, 1),
            ],
            sparkUnclaimedDeposits: const [],
          ));
      await _openBreakdown(tester);
      expect(find.byKey(const ValueKey('money-flow-empty')), findsOneWidget);
      expect(find.text('No activity yet'), findsOneWidget);
      expect(find.byType(KuteDonutChart), findsNothing);
      await tester.tap(find.byKey(const ValueKey('money-flow-received')));
      await tester.pumpAndSettle();
      expect(find.byType(KuteDonutChart), findsOneWidget);
    });
  });
}
