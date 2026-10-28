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
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/deposit_quick_claim.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/spark_transaction_details.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/models/breez/deposit_update.dart' show sparkOutpointKey;
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
          activeWalletId: 'spending',
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
    bool early = false,
  }) async {
    calls.add('claim $maxFeeSats${early ? ' early' : ''}');
    final failure = claimFailure;
    if (failure != null) throw failure;
    return claimResult;
  }

  SparkDepositQuote? quoteResult;

  @override
  Future<SparkDepositQuote> quote(
      {required String walletId,
      required String txid,
      required int vout}) async {
    final result = quoteResult;
    if (result == null) throw UnimplementedError();
    return result;
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
          breez.DepositClaimError? claimError,
          int sats = 1000}) =>
      breez.DepositInfo(
          txid: 'ab' * 32,
          vout: 1,
          amountSats: BigInt.from(sats),
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
  late List<SensitiveIntent> approvals;
  AuthGrant? Function(SensitiveIntent)? answer;

  const failed = breez.DepositClaimError.generic(message: 'boom');
  // A 0.119 BTC deposit refused for a 40,000 sat fee: above the app's
  // automatic ceiling (0.25 % = 29,750), so it waits for the person.
  breez.DepositClaimError feeAboveCeiling([int fee = 40000]) =>
      breez.DepositClaimError.maxDepositClaimFeeExceeded(
          tx: 'ab' * 32,
          vout: 1,
          requiredFeeSats: BigInt.from(fee),
          requiredFeeRateSatPerVbyte: BigInt.from(fee ~/ 99));

  setUp(() {
    actions = _Actions();
    sync = _Sync();
    approvals = [];
    answer = (intent) => AuthGrants.issue(intent, method: AuthGrantMethod.pin);
    debugDepositClaimApproval = (intent) async {
      approvals.add(intent);
      return answer?.call(intent);
    };
  });
  tearDown(() => debugDepositClaimApproval = null);

  List<SparkUnclaimedDeposit> cachedRows() => container
      .read(walletTransactionCacheProvider)['spending']!
      .sparkUnclaimedDeposits;

  // Pending icons and loading buttons animate forever, so settle by time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, SparkUnclaimedDeposit tx,
      {Widget Function(BuildContext context, WidgetRef ref)? body,
      bool tapOpen = true}) async {
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
            builder: (context, ref, _) =>
                body?.call(context, ref) ??
                Center(
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
    if (tapOpen) {
      await tester.tap(find.text('open'));
    }
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  // No Send it back on any deposit sheet (founder, 2026-10-26): nothing
  // offers to return the deposit, whatever its state.
  void expectNoSendBack() {
    expect(find.text('Send it back'), findsNothing);
    expect(
        find.textContaining(
            RegExp(r'send it back|refund', caseSensitive: false)),
        findsNothing);
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
    // The normal path is said plainly; no quote, so no Claim now.
    expect(find.text(l10n.depositAutoAfterConfirmations), findsOneWidget);
    expect(find.textContaining('Claim now'), findsNothing);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expectNoSendBack();
  });

  // The default stays the automatic claim: a mature deposit with no error
  // is about to be added by the SDK, so the person is offered nothing.
  testWidgets('a mature deposit without an error is being added, no action',
      (tester) async {
    await open(tester, rowFor(info()));
    expect(find.text(l10n.activityAddingToBalance), findsWidgets);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expect(find.textContaining('Claim now'), findsNothing);
    expectNoSendBack();
  });

  // A quote at or below the automatic ceiling (max(2,475 sats, 0.25 % of
  // the deposit)) never waits: the app claims it, and the sheet says it is
  // being added with nothing to do.
  testWidgets('a fee within the automatic ceiling is being added, no wait',
      (tester) async {
    // 0.25 % of 0.119 BTC is exactly 29,750 sats.
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling(29750));
    expect(rowFor(deposit).stage, SparkDepositStage.adding);
    await open(tester, rowFor(deposit));
    expect(find.text(l10n.activityAddingToBalance), findsWidgets);
    expect(find.text(l10n.depositStatusWaitingFee), findsNothing);
    expect(find.text(l10n.depositReasonFeeHigh), findsNothing);
    expect(find.text(l10n.depositWaitForLowerFee), findsNothing);
    expect(find.textContaining('Claim now'), findsNothing);
    expectNoSendBack();
  });

  testWidgets('a small deposit at the flat floor is being added, no wait',
      (tester) async {
    final deposit = info(sats: 100000, claimError: feeAboveCeiling(2475));
    await open(tester, rowFor(deposit));
    expect(find.text(l10n.activityAddingToBalance), findsWidgets);
    expect(find.text(l10n.depositStatusWaitingFee), findsNothing);
    expect(find.textContaining('Claim now'), findsNothing);
  });

  testWidgets('refunding deposits open the action sheet without actions',
      (tester) async {
    await open(tester, rowFor(info(mature: false, refundTxId: 'refund')));
    expect(find.text(l10n.refunding), findsWidgets);
    expect(find.text(l10n.activityAddToWallet), findsNothing);
    expect(find.text('Send it back'), findsNothing);
  });

  testWidgets('a failed claim opens the claim sheet with the plain reason',
      (tester) async {
    await open(tester, rowFor(info(claimError: failed)));
    expect(find.text(l10n.depositStatusFailed), findsOneWidget);
    expect(find.text(l10n.depositReasonFailed), findsOneWidget);
    expect(find.text(l10n.activityAddToWallet), findsOneWidget);
    expect(find.text(l10n.depositWaitForLowerFee), findsNothing);
    expectNoSendBack();
  });

  testWidgets('a fee above the automatic ceiling waits, with Claim now',
      (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    await open(tester, rowFor(deposit));
    expect(find.text(l10n.depositStatusWaitingFee), findsOneWidget);
    expect(find.text(l10n.depositReasonFeeHigh), findsOneWidget);
    // The reason says the fee is unusually high and both ways forward.
    expect(l10n.depositReasonFeeHigh,
        "The fee to add this right now is unusually high. It's added "
        'automatically when it drops, or you can claim it now.');
    expect(find.text(l10n.depositFeeToClaimNow), findsOneWidget);
    final fee = container.read(conversionProvider(40000));
    expect(find.text(l10n.depositClaimNowFee(fee)), findsOneWidget);
    expect(find.text(l10n.depositWaitForLowerFee), findsOneWidget);
    expectNoSendBack();
    // Waiting closes the sheet and attempts nothing.
    await tapText(tester, l10n.depositWaitForLowerFee);
    expect(find.text(l10n.depositStatusWaitingFee), findsNothing);
    expect(actions.calls, isEmpty);
  });

  // With no network quote yet the picker is the only way to a ceiling.
  testWidgets('cancelling the fee picker attempts nothing and keeps the row',
      (tester) async {
    actions.live = info(claimError: failed);
    await open(tester, rowFor(info(claimError: failed)));
    await tapText(tester, l10n.activityAddToWallet);
    expect(find.byType(ClaimFeePickerSheet), findsOneWidget);
    await tapText(tester, l10n.cancel);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(actions.calls, ['live']);
    expect(approvals, isEmpty);
    expect(sync.refreshes, 0);
    expect(cachedRows(), hasLength(1));
    expect(find.text(l10n.activityAddToWallet), findsOneWidget);
  });

  // Claim now uses the recommended ceiling (quote plus headroom) after one
  // approval bound to that ceiling, and ends on the shared confirmation.
  testWidgets(
      'Claim now asks once, claims under quote plus headroom, '
      'drops the row and refreshes', (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    actions.live = deposit;
    await open(tester, rowFor(deposit));
    await tapText(tester,
        l10n.depositClaimNowFee(container.read(conversionProvider(40000))));
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.depositClaim);
    expect(approvals.single.amountMax, BigInt.from(44000));
    expect(actions.calls, ['live', 'claim 44000']);
    expect(cachedRows(), isEmpty);
    expect(sync.refreshes, 1);
    expect(find.text(l10n.activityBitcoinAdded), findsOneWidget);
    expect(find.text(l10n.activityBitcoinAddedPending), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('a declined approval claims nothing', (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    actions.live = deposit;
    answer = null;
    await open(tester, rowFor(deposit));
    await tapText(tester,
        l10n.depositClaimNowFee(container.read(conversionProvider(40000))));
    expect(approvals, hasLength(1));
    expect(actions.calls, ['live']);
    expect(cachedRows(), hasLength(1));
    expect(sync.refreshes, 0);
  });

  testWidgets('an unknown claim status keeps the row and refreshes',
      (tester) async {
    actions
      ..live = info(claimError: failed)
      ..claimResult =
          const SparkDepositClaimResult(SparkDepositClaimOutcome.statusUnknown);
    await open(tester, rowFor(info(claimError: failed)));
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

  // Raw SDK text never reaches the user; the failure sheet carries the
  // add flow's own copy and Try again runs the claim again.
  testWidgets('a failed claim ends on the failure sheet with Try again',
      (tester) async {
    actions
      ..live = info(claimError: failed)
      ..claimFailure = Exception('Service unavailable');
    await open(tester, rowFor(info(claimError: failed)));
    await tapText(tester, l10n.activityAddToWallet);
    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();
    await tapText(tester, l10n.confirmClaim);
    expect(find.byType(KuteConfirmation), findsOneWidget);
    expect(find.text(l10n.depositClaimFailedTitle), findsOneWidget);
    expect(find.text(l10n.depositAddFailed), findsOneWidget);
    expect(find.textContaining('Service unavailable'), findsNothing);
    expect(cachedRows(), hasLength(1));
    expect(sync.refreshes, 1);
    // Try again: the claim runs again (the picker asks for a ceiling again).
    actions.claimFailure = null;
    await tapText(tester, l10n.walletsTryAgain);
    expect(find.byType(ClaimFeePickerSheet), findsOneWidget);
  });

  testWidgets(
      'a deposit the SDK no longer lists reconciles without a fee prompt',
      (tester) async {
    await open(tester, rowFor(info(claimError: failed)));
    await tapText(tester, l10n.activityAddToWallet);
    expect(actions.calls, ['live', 'missing']);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(approvals, isEmpty);
    expect(cachedRows(), isEmpty);
    expect(sync.refreshes, 1);
    expect(find.text(l10n.depositAlreadyReceived), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('a wallet that is not ready stops before the fee prompt',
      (tester) async {
    actions.liveError = const SparkDepositActionException(
        SparkDepositActionReason.walletUnavailable);
    await open(tester, rowFor(info(claimError: failed)));
    await tapText(tester, l10n.activityAddToWallet);
    expect(actions.calls, ['live']);
    expect(find.byType(ClaimFeePickerSheet), findsNothing);
    expect(find.text(l10n.depositActionWalletUnavailable), findsOneWidget);
    expect(sync.refreshes, 0);
    expect(cachedRows(), hasLength(1));
    await clearToasts(tester);
  });

  // One guard for every claim of the outpoint: while the automatic claim
  // runs, the sheet says it is being added and holds Claim now, so the
  // person cannot start a second claim.
  testWidgets('a claim running elsewhere holds the sheet\'s actions',
      (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    await open(tester, rowFor(deposit));
    actions.busyOutpoints.value = {
      sparkOutpointKey(deposit.txid, deposit.vout)
    };
    await settle(tester);
    expect(find.text(l10n.activityAddingToBalance), findsWidgets);
    expectNoSendBack();
    final claimNow = tester.widget<AppButton>(find.byWidgetPredicate(
        (w) => w is AppButton && w.text.startsWith('Claim now')));
    expect(claimNow.onPressed, isNull);
    expect(actions.calls, isEmpty);
    actions.busyOutpoints.value = const {};
    await settle(tester);
    expect(find.text(l10n.depositStatusWaitingFee), findsOneWidget);
    expectNoSendBack();
  });

  testWidgets('the Activity row of a waiting deposit opens its sheet',
      (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    await open(tester, rowFor(deposit),
        tapOpen: false,
        body: (context, ref) =>
            buildUnifiedTransactionItem(rowFor(deposit), context, ref));
    expect(find.text(l10n.activityDepositWaiting), findsOneWidget);
    expect(find.text(l10n.activityTapToAddToBalance), findsOneWidget);
    await tester.tap(find.text(l10n.activityDepositWaiting));
    await settle(tester);
    expect(find.text(l10n.depositStatusWaitingFee), findsOneWidget);
  });

  test('waiting deposits lead the Activity list', () {
    final older = rowFor(info(sats: 11900000, claimError: feeAboveCeiling()));
    final newer = SparkUnclaimedDeposit(
        id: 'cd:0',
        timestamp: DateTime.utc(2026, 10, 26),
        depositInfo: breez.DepositInfo(
            txid: 'cd' * 32,
            vout: 0,
            amountSats: BigInt.from(5000),
            isMature: false));
    final ordered = waitingDepositsFirst([newer, older]);
    expect(ordered, [older, newer]);
    expect(isWaitingDeposit(older), isTrue);
    expect(isWaitingDeposit(newer), isFalse);
  });

  testWidgets('Home shows one quiet line for a deposit waiting for a fee',
      (tester) async {
    final deposit = info(sats: 11900000, claimError: feeAboveCeiling());
    await open(tester, rowFor(deposit),
        tapOpen: false, body: (_, __) => const DepositWaitingLine());
    final amount = container.read(conversionProvider(11900000));
    expect(find.text(l10n.depositHomeWaiting(amount)), findsOneWidget);
    await tester.tap(find.text(l10n.depositHomeWaiting(amount)));
    await settle(tester);
    expect(find.text(l10n.depositStatusWaitingFee), findsOneWidget);
  });

  testWidgets('Home shows nothing while a deposit is only confirming',
      (tester) async {
    await open(tester, rowFor(info(mature: false)),
        tapOpen: false, body: (_, __) => const DepositWaitingLine());
    expect(find.byType(DepositSheetNote), findsNothing);
  });

  // The optional, costlier path while confirming: shown only when the
  // provider quotes an early claim, claimed early after one approval.
  testWidgets(
      'a confirming deposit offers Claim now when an early claim is '
      'quoted', (tester) async {
    final deposit = info(mature: false, sats: 11900000);
    actions
      ..live = deposit
      ..quoteResult = const SparkDepositQuote(
          confirmations: 1,
          matureFeeSats: 12000,
          earlyFeeSats: 30000,
          earlyConfirmations: 1);
    await open(tester, rowFor(deposit));
    expect(find.text(l10n.depositAutoAfterConfirmations), findsOneWidget);
    final fee = container.read(conversionProvider(30000));
    expect(find.text(l10n.depositClaimNowFee(fee)), findsOneWidget);
    expectNoSendBack();
    await tapText(tester, l10n.depositClaimNowFee(fee));
    expect(approvals.single.amountMax, BigInt.from(33000));
    expect(actions.calls, ['claim 33000 early']);
    expect(find.text(l10n.activityBitcoinAdded), findsOneWidget);
    expect(sync.refreshes, 1);
    await clearToasts(tester);
  });
}
