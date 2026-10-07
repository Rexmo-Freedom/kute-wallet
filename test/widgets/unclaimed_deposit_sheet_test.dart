import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/screens/shared/spark_transaction_details.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:money2/money2.dart';

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'default',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync extends BackgroundSyncNotifier {
  int refreshes = 0;

  @override
  Future<void> performFullUpdate({bool force = true}) async {
    refreshes++;
  }
}

class _Actions extends SparkDepositActions {
  _Actions()
      : super(
            loadSdk: (_) => throw UnimplementedError(),
            currentWalletId: () => 'spending');

  final calls = <String>[];
  Object? liveError;
  breez.DepositInfo? live;
  Object? claimFailure;
  SparkDepositClaimResult claimResult = const SparkDepositClaimResult(
      SparkDepositClaimOutcome.submitted,
      paymentStatus: breez.PaymentStatus.pending);
  SparkDepositClaimResult missingResult =
      const SparkDepositClaimResult(SparkDepositClaimOutcome.alreadyReceived);

  @override
  Future<breez.DepositInfo?> liveDeposit(
      {required String walletId,
      required String txid,
      required int vout}) async {
    calls.add('live');
    final error = liveError;
    if (error != null) throw error;
    return live;
  }

  @override
  Future<SparkDepositClaimResult> missingDepositOutcome(
      {required String walletId,
      required String txid,
      required int vout}) async {
    calls.add('missing');
    return missingResult;
  }

  @override
  Future<SparkDepositClaimResult> claim({
    required String walletId,
    required String txid,
    required int vout,
    required BigInt maxFeeSats,
    required BigInt depositAmountSats,
  }) async {
    calls.add('claim $maxFeeSats');
    final failure = claimFailure;
    if (failure != null) throw failure;
    return claimResult;
  }

  @override
  Future<breez.RefundDepositResponse> refund({
    required String walletId,
    required String txid,
    required int vout,
    required String address,
    required BigInt satPerVbyte,
  }) async {
    calls.add('refund');
    throw UnimplementedError();
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final seenAt = DateTime.utc(2026, 9, 15);

  breez.DepositInfo info(
          {bool mature = true,
          String? refundTxId,
          breez.DepositClaimError? claimError}) =>
      breez.DepositInfo(
          txid: 'ab' * 32,
          vout: 1,
          amountSats: BigInt.from(1000),
          isMature: mature,
          refundTxId: refundTxId,
          claimError: claimError);
  SparkUnclaimedDeposit rowFor(breez.DepositInfo deposit) =>
      SparkUnclaimedDeposit(
          id: '${deposit.txid}:${deposit.vout}',
          timestamp: seenAt,
          depositInfo: deposit);

  late _Actions actions;
  late _Sync sync;
  late ProviderContainer container;

  setUp(() {
    actions = _Actions();
    sync = _Sync();
  });

  List<SparkUnclaimedDeposit> cachedRows() => container
      .read(walletTransactionCacheProvider)['spending']!
      .sparkUnclaimedDeposits;

  // Pending icons and loading buttons animate forever, so settle by time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, SparkUnclaimedDeposit tx) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings()),
      conversionToFiatProvider.overrideWith((ref, amount) => '\$0.25'),
      selectedCurrencyProvider.overrideWith((ref, currency) =>
          Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      sparkDepositActionsProvider.overrideWithValue(actions),
      backgroundSyncNotifierProvider.overrideWith(() => sync),
    ]);
    addTearDown(container.dispose);
    container.read(walletTransactionCacheProvider.notifier).setForWallet(
        'spending',
        Transaction(
            bitcoinTransactions: [],
            sparkTransactions: [],
            sparkUnclaimedDeposits: [tx]));
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => openTransactionDetails(context, ref, tx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  // Toasts close on a timer.
  Future<void> clearToasts(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('deposits waiting for confirmations open the read-only sheet',
      (tester) async {
    await open(tester, rowFor(info(mature: false)));
    // The sheet opens with the deposit's own row: Received, still pending.
    expect(find.text(l10n.received), findsOneWidget);
    expect(find.text(l10n.activityArriving), findsOneWidget);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expect(find.text(l10n.refund), findsNothing);
  });

  testWidgets('mature deposits open the sheet with add to wallet and refund',
      (tester) async {
    await open(tester, rowFor(info()));
    expect(find.text(l10n.received), findsOneWidget);
    expect(find.text(l10n.activityAddToWallet), findsOneWidget);
    expect(find.text(l10n.refund), findsOneWidget);
  });

  testWidgets('refunding deposits open the action sheet without actions',
      (tester) async {
    await open(tester, rowFor(info(mature: false, refundTxId: 'refund')));
    expect(find.text(l10n.refunding), findsOneWidget);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expect(find.text(l10n.refund), findsNothing);
  });

  // With no network quote yet the picker is the only way to a ceiling.
  testWidgets('cancelling the fee picker attempts nothing and keeps the row',
      (tester) async {
    actions.live = info();
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.activityAddToWallet);
    expect(find.byType(ClaimFeePickerSheet), findsOneWidget);
    await tapText(tester, l10n.cancel);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(actions.calls, ['live']);
    expect(sync.refreshes, 0);
    expect(cachedRows(), hasLength(1));
    expect(find.text(l10n.activityAddToWallet), findsOneWidget);
  });

  // A quoted claim uses the recommended ceiling (quote plus headroom)
  // without asking for a number, and ends on the shared confirmation.
  testWidgets('a submitted claim drops the row, refreshes once and closes',
      (tester) async {
    final deposit = info(
        claimError: breez.DepositClaimError.maxDepositClaimFeeExceeded(
            tx: 'ab' * 32,
            vout: 1,
            requiredFeeSats: BigInt.from(250),
            requiredFeeRateSatPerVbyte: BigInt.from(3)));
    actions.live = deposit;
    await open(tester, rowFor(deposit));
    expect(find.text(l10n.activityUpToAmount('₿350')), findsOneWidget);
    await tapText(tester, l10n.activityAddToWallet);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(actions.calls, ['live', 'claim 350']);
    expect(cachedRows(), isEmpty);
    expect(sync.refreshes, 1);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expect(find.text(l10n.activityBitcoinAdded), findsOneWidget);
    expect(find.text(l10n.activityBitcoinAddedPending), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('an unknown claim status keeps the row and refreshes',
      (tester) async {
    actions
      ..live = info()
      ..claimResult =
          const SparkDepositClaimResult(SparkDepositClaimOutcome.statusUnknown);
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.activityAddToWallet);
    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();
    await tapText(tester, l10n.confirmClaim);
    expect(actions.calls, ['live', 'claim 300']);
    expect(cachedRows(), hasLength(1));
    expect(sync.refreshes, 1);
    expect(find.text(l10n.depositClaimStatusUnknown), findsOneWidget);
    await clearToasts(tester);
  });

  // Raw SDK text never reaches the user; the add flow's own copy does.
  testWidgets('an unknown SDK error shows the add failure copy, not its text',
      (tester) async {
    actions
      ..live = info()
      ..claimFailure = Exception('Service unavailable');
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.activityAddToWallet);
    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();
    await tapText(tester, l10n.confirmClaim);
    expect(find.text(l10n.depositAddFailed), findsOneWidget);
    expect(find.textContaining('Service unavailable'), findsNothing);
    expect(cachedRows(), hasLength(1));
    expect(sync.refreshes, 1);
    await clearToasts(tester);
  });

  testWidgets(
      'a deposit the SDK no longer lists reconciles without a fee prompt',
      (tester) async {
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.activityAddToWallet);
    expect(actions.calls, ['live', 'missing']);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(cachedRows(), isEmpty);
    expect(sync.refreshes, 1);
    expect(find.text(l10n.depositAlreadyReceived), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('a wallet that is not ready stops before the fee prompt',
      (tester) async {
    actions.liveError = const SparkDepositActionException(
        SparkDepositActionReason.walletUnavailable);
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.activityAddToWallet);
    expect(actions.calls, ['live']);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(find.text(l10n.depositActionWalletUnavailable), findsOneWidget);
    expect(sync.refreshes, 0);
    expect(cachedRows(), hasLength(1));
    await clearToasts(tester);
  });

  testWidgets('closing the refund address sheet attempts nothing',
      (tester) async {
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.refund);
    expect(find.byType(RefundAddressModalSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(RefundAddressModalSheet))).pop();
    await settle(tester);
    expect(actions.calls, isEmpty);
    expect(sync.refreshes, 0);
    expect(find.text(l10n.refund), findsOneWidget);
  });

  testWidgets('declining step-up auth attempts no refund', (tester) async {
    await open(tester, rowFor(info()));
    await tapText(tester, l10n.refund);
    await tester.enterText(find.byType(TextFormField).first, 'bc1qtest');
    await tester.enterText(find.byType(TextFormField).last, '3');
    await tester.pump();
    await tapText(tester, l10n.confirmRefund);
    expect(find.byType(PinGateSheet), findsOneWidget);
    await tapText(tester, l10n.cancel);
    expect(find.byType(PinGateSheet), findsNothing);
    expect(actions.calls, isEmpty);
    expect(sync.refreshes, 0);
    expect(find.text(l10n.refund), findsOneWidget);
  });
}
