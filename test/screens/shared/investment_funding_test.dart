// Deposit / Withdraw on a venue answers to the venue's funding capability.
// A refusal sends `<venue>_funding_blocked` with the policy's own reason
// code and opens the unavailable sheet; an offline-grace decision is
// allowed, so it opens the Move sheet and only says the check is stale.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/investment_funding.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy(this.decisionFor);
  final CapabilityDecision Function(String id) decisionFor;
  @override
  CapabilityDecision decision(String id) => decisionFor(id);
}

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

const _gotIt = ValueKey('capability-unavailable-got-it');

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<MoveLockedSide> opened;
  late Map<String, CapabilityDecision> decisions;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    events = [];
    opened = [];
    decisions = {};
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    debugOpenFundingSheet = (_, side) => opened.add(side);
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    debugOpenFundingSheet = null;
  });

  Future<void> tap(WidgetTester tester, InvestmentsProduct product,
      {required bool deposit}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      runtimeCapabilitiesProvider.overrideWithValue(_Policy((id) =>
          decisions[id] ?? const CapabilityDecision(allowed: true))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => openInvestmentFunding(context, ref, product,
                    deposit: deposit),
                child: const Text('Fund'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Fund'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a refusal carries the policy reason and opens the sheet',
      (tester) async {
    decisions['polymarket.deposit'] =
        const CapabilityDecision(allowed: false, reason: 'country_blocked');
    await tap(tester, InvestmentsProduct.predictions, deposit: true);

    expect(events, hasLength(1));
    expect(events.single.$1, 'polymarket_funding_blocked');
    expect(events.single.$2, {
      'direction': 'deposit',
      'reason': 'geoblocked',
      'decision_reason': 'country_blocked',
    });
    expect(find.byKey(_gotIt), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('no policy at all is told apart from a block', (tester) async {
    decisions['hyperliquid.withdraw'] = const CapabilityDecision(
        allowed: false, reason: 'policy_unavailable');
    await tap(tester, InvestmentsProduct.trading, deposit: false);

    expect(events.single.$1, 'hyperliquid_funding_blocked');
    expect(events.single.$2!['reason'], 'capability');
    expect(events.single.$2!['decision_reason'], 'policy_unavailable');
    expect(opened, isEmpty);
  });

  testWidgets('offline grace opens the Move sheet and says the check is stale',
      (tester) async {
    decisions['polymarket.withdraw'] =
        const CapabilityDecision(allowed: true, reason: 'offline_grace');
    await tap(tester, InvestmentsProduct.predictions, deposit: false);

    expect(events, isEmpty);
    expect(find.byKey(_gotIt), findsNothing);
    expect(opened, [MoveLockedSide.withdrawFromPredictions]);
    expect(
        find.text(
            "Kute can't be reached right now. This is still available from your last check."),
        findsOneWidget);
    // Past the toast's own duration and exit animation.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('allowed opens the Move sheet with nothing said',
      (tester) async {
    await tap(tester, InvestmentsProduct.trading, deposit: true);

    expect(events, isEmpty);
    expect(opened, [MoveLockedSide.depositToHyperliquid]);
    expect(find.byType(Overlay), findsOneWidget);
    expect(find.textContaining("can't be reached"), findsNothing);
  });
}
