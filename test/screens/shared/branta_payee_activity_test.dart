// A send whose payee Branta verified keeps that payee with the payment
// (services/branta/branta_payee_records.dart; founder, 12 November 2026):
// the Bitcoin home's Latest square, the activity rows (Bitcoin, Dollars,
// Portfolio: one row builder) and the receipt show the payee's logo in
// the row's circle and "Sent to Strike", the receipt adds "Verified by
// Branta"; the amount and status are unchanged. The records are read
// from disk as at a launch (the box opened at boot), the lists never ask
// Branta, a send without a record looks exactly as before, and analytics
// hears nothing of the payee.

import 'dart:convert';
import 'dart:io';

import 'package:branta/branta.dart' show VerifyResult, VerifyStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/branta/branta_payee_records.dart';
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';
import 'receipt_fixtures.dart';

const _logo = 'https://branta.pro/logos/strike.png';
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// A Dollars Send of $25 to USDC on Polygon, as usd_send_screen.dart
/// records it.
SwapOrderTransaction _dollarSend({String id = 'ord_strike'}) {
  final at = receiptAt.subtract(const Duration(minutes: 5));
  return SwapOrderTransaction(
    id: id,
    timestamp: at,
    isConfirmed: true,
    details: SwapOrder(
      activityDirection: 'send',
      id: id,
      coinFrom: kOrchestraUsdAssetCode,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: 'spark1deposit',
      depositAmount: '25.00',
      withdrawalAmount: '24.90',
      status: 'success',
      timestamp: at.millisecondsSinceEpoch,
      withdrawalAddress: '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: 'op-strike',
    ),
  );
}

/// A plain Spark send nobody verified.
SparkTransaction _plainSend() => SparkTransaction.fromCache(
      id: 'plain-send',
      timestamp: receiptAt.subtract(const Duration(minutes: 30)),
      isConfirmed: true,
      amountSats: 5000,
      sparkType: SparkTransactionType.spark,
      direction: TransactionType.sent,
      pending: false,
    );

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  late Directory hive;
  var lookups = 0;
  late BrantaPayeeService saved;

  setUpAll(() async {
    hive = await openReceiptHive();
    await Hive.openBox<String>(BrantaPayeeRecordStore.boxName);
    // As an earlier launch left them: the Lightning send and the Dollars
    // send were confirmed with Strike verified on screen.
    final record = BrantaPayeeRecord(
      name: 'Strike',
      logoUrl: _logo,
      verifiedAt: receiptAt,
      rail: BrantaRail.lightning,
    );
    await BrantaPayeeRecordStore.write([receiptLightningId], record);
    await BrantaPayeeRecordStore.write(['op-strike'], record);
  });
  tearDownAll(() => closeReceiptHive(hive));

  setUp(() {
    OwnSparkArrivals.reset();
    lookups = 0;
    saved = BrantaPayeeService.shared;
    BrantaPayeeService.shared = BrantaPayeeService(verifier: (_) async {
      lookups++;
      return const VerifyResult(status: VerifyStatus.unknown, verifyUrl: '');
    });
    BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(_png);
  });
  tearDown(() {
    BrantaPayeeService.shared = saved;
    BrantaPayeeLogo.debugImageProvider = null;
    TrackingService.debugTrackObserver = null;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the Bitcoin home Latest square: logo and "Sent to Strike"',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...portfolioOverrides(
            history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: [receiptLightningSend(), _plainSend()],
          sparkUnclaimedDeposits: const [],
        )),
        ...offlineVenueOverrides,
        hyperliquidActivityFillsProvider.overrideWith((_) => const []),
        currentBtcUsdProvider.overrideWithValue(100000),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ActivityRowStyle(
                  compact: true, child: AllActivityPreview()),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);

    final grid = find.byType(ActivitySquareGrid);
    expect(grid, findsOneWidget);
    expect(find.descendant(of: grid, matching: find.text('Sent to Strike')),
        findsOneWidget);
    expect(
        find.descendant(
            of: grid, matching: find.byKey(const ValueKey('send-branta-logo'))),
        findsOneWidget);
    // The unverified send next to it: "Sent", its own mark.
    expect(find.descendant(of: grid, matching: find.text('Sent')),
        findsOneWidget);
    // The list asked Branta nothing.
    expect(lookups, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
  });

  late BuildContext opener;
  late WidgetRef openerRef;

  Future<void> pumpRows(WidgetTester tester, List<BaseTransaction> rows) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(receiptApp(
      Consumer(builder: (context, ref, _) {
        opener = context;
        openerRef = ref;
        return Column(children: [
          for (final tx in rows) buildUnifiedTransactionItem(tx, context, ref),
        ]);
      }),
      theme: buildLightTheme(),
    ));
    await settle(tester);
  }

  testWidgets('activity rows: Bitcoin and Dollars sends name the payee',
      (tester) async {
    await pumpRows(tester, [receiptLightningSend(), _dollarSend(), _plainSend()]);
    expect(find.text('Sent to Strike'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('send-branta-logo')), findsNWidgets(2));
    // The amounts are the rows' own: ₿2,100 out, $25.00 out.
    expect(find.textContaining('2,100'), findsWidgets);
    expect(find.textContaining('25.00'), findsWidgets);
    // No record: the row exactly as before.
    expect(find.text('Sent'), findsOneWidget);
    expect(lookups, 0);
  });

  testWidgets('the receipt: logo, "Sent to Strike", "Verified by Branta"',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    await pumpRows(tester, const []);
    await openTransactionDetails(opener, openerRef, receiptLightningSend());
    await settle(tester);

    final hero = find.byKey(const ValueKey('receipt-hero'));
    expect(find.descendant(of: hero, matching: find.text('Sent to Strike')),
        findsOneWidget);
    expect(
        find.descendant(
            of: hero, matching: find.byKey(const ValueKey('send-branta-logo'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: hero,
            matching: find.byKey(const ValueKey('send-branta-verified'))),
        findsOneWidget);
    expect(_inSheet(find.text('Verified by Branta')), findsOneWidget);
    expect(lookups, 0);

    // Analytics: the receipt's own event, and nothing of the payee.
    expect(events.map((e) => e.$1), contains('transaction_detail_viewed'));
    for (final (_, params) in events) {
      final text = jsonEncode(params ?? const {});
      expect(text, isNot(contains('Strike')));
      expect(text, isNot(contains('branta.pro')));
    }
  });

  testWidgets('the Dollars receipt names the payee too', (tester) async {
    await pumpRows(tester, const []);
    await openTransactionDetails(opener, openerRef, _dollarSend());
    await settle(tester);
    final hero = find.byKey(const ValueKey('receipt-hero'));
    expect(find.descendant(of: hero, matching: find.text('Sent to Strike')),
        findsOneWidget);
    expect(
        find.descendant(
            of: hero,
            matching: find.byKey(const ValueKey('send-branta-verified'))),
        findsOneWidget);
  });

  testWidgets('a send without a record: no logo, no Verified line',
      (tester) async {
    await pumpRows(tester, const []);
    await openTransactionDetails(opener, openerRef, _plainSend());
    await settle(tester);
    expect(_inSheet(find.text('Sent to Strike')), findsNothing);
    expect(_inSheet(find.byKey(const ValueKey('send-branta-logo'))),
        findsNothing);
    expect(_inSheet(find.text('Verified by Branta')), findsNothing);
  });

  testWidgets('a send stored now shows at once, without a lookup',
      (tester) async {
    await pumpRows(tester, [_plainSend()]);
    expect(find.text('Sent'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Consumer).first));
    // The disk write is real I/O: off the test clock.
    await tester.runAsync(() => container
        .read(brantaPayeeRecordsProvider.notifier)
        .record(
            paymentIds: ['plain-send'],
            payee: const BrantaPayee.verified(name: 'Strike', logoUrl: _logo),
            rail: BrantaRail.bitcoinOnchain));
    await settle(tester);
    expect(find.text('Sent to Strike'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-branta-logo')), findsOneWidget);
    expect(lookups, 0);
    await tester.runAsync(() =>
        Hive.box<String>(BrantaPayeeRecordStore.boxName).delete('plain-send'));
  });
}
