// A Retry of a move home to Dollars asks the step-up like every other
// Retry, before any leg moves (founder rule: money moves only after the
// person accepts with Face ID or the passcode). Declined, nothing moves.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show MultiSourceMoveTransaction;
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

final _t0 = DateTime.utc(2026, 11, 11, 12);

/// Investing cash: each pull recorded; the leg comes home to Dollars.
class _Source implements VenueCashSource {
  final pulls = <double>[];

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => const Duration(minutes: 5);

  @override
  Future<double> availableUsd() async => 500;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}

/// A send's shortfall home to Dollars: Predictions came home, the
/// Investing leg did not go ($21 left to pull).
MultiSourceMove _homeMove() => MultiSourceMove(
      id: 'msm_home',
      walletId: 'spending',
      forAction: VenueCashFor.send,
      destination: VenueCashDestination.dollars,
      totalUsd: 50,
      dollarsUsd: 10,
      createdAt: _t0.add(const Duration(seconds: 1)),
      legs: [
        MultiSourceMoveLeg(
          venue: OneBalanceVenue.predictions,
          usd: 20,
          arrivingUsd: 19.8,
          route: VenueCashRoute.viaDollars,
          ok: true,
          at: _t0,
          operationId: 'op-pm',
        ),
        MultiSourceMoveLeg(
          venue: OneBalanceVenue.investing,
          usd: 21,
          arrivingUsd: 20.79,
          route: VenueCashRoute.viaDollars,
          ok: false,
          at: _t0,
          error: 'route',
        ),
      ],
    );

void main() {
  late List<String> events;
  setUp(() {
    Intl.defaultLocale = 'en_US';
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
  });
  tearDown(() {
    Intl.defaultLocale = null;
    TrackingService.debugTrackObserver = null;
    debugMultiSourceRetryApproval = null;
  });

  /// Pumps the move's Activity row, opens its detail and taps Retry.
  Future<void> retry(WidgetTester tester, VenueCashPuller puller) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    MultiSourceMoveStore.start(_homeMove());
    final tx = MultiSourceMoveTransaction(
        move: MultiSourceMoveStore.get('msm_home')!, legRows: const []);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              balancePrivacy: 0,
              biometricsEnabled: false,
              bitcoinElectrumNode: 'localhost',
              nodeType: 'Blockstream',
              reviewDone: false,
              wallets: [WalletConfig(id: 'spending', name: 'Spending')],
              activeWalletId: 'spending',
            ))),
        venueCashPullerProvider.overrideWithValue(puller),
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
                builder: (context, ref, _) =>
                    buildUnifiedTransactionItem(tx, context, ref)),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Move \$50.00 to Dollars'));
    // A running step's spinner never settles: pump.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Retry'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Retry'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
      'Retry of a move home to Dollars asks the step-up first; declined, '
      'nothing moves', (tester) async {
    final source = _Source();
    final prompts = <SensitiveIntent>[];
    debugMultiSourceRetryApproval = (intent) async {
      prompts.add(intent);
      return null;
    };
    final puller = VenueCashPuller(
        sources: [source], readDollars: () => 0, minimumUsd: (_) async => 1);

    await retry(tester, puller);

    expect(prompts, hasLength(1));
    expect(prompts.single.action, SensitiveAction.moveTransfer);
    expect(prompts.single.destination, VenueCashDestination.dollars.code);
    expect(source.pulls, isEmpty, reason: 'declined: no leg went');
    expect(events, isNot(contains('multi_source_move_retry_tapped')));
    expect(MultiSourceMoveStore.get('msm_home')!.partial, isTrue,
        reason: 'the remainder is still there to retry');
  });

  testWidgets(
      'Retry of a move home to Dollars, accepted: the one prompt, then the '
      'remainder comes home', (tester) async {
    final source = _Source();
    final prompts = <SensitiveIntent>[];
    final pulledAtPrompt = <int>[];
    debugMultiSourceRetryApproval = (intent) async {
      prompts.add(intent);
      pulledAtPrompt.add(source.pulls.length);
      return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    };
    final puller = VenueCashPuller(
        sources: [source], readDollars: () => 0, minimumUsd: (_) async => 1);

    await retry(tester, puller);

    expect(prompts, hasLength(1));
    expect(pulledAtPrompt, [0], reason: 'nothing moved before it');
    expect(source.pulls, hasLength(1));
    expect(events, contains('multi_source_move_retry_tapped'));
  });
}
