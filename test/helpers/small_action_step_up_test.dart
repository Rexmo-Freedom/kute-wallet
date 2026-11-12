// Orders under $50 through the step-up helper itself (founder decision,
// 2026-11-12): with the backend policy on, a small bet, sell, Investing
// order or close comes back approved by the allowance with no Face ID or
// PIN sheet, funded orders included (held as the order's autofire grant);
// $50.00 and above, the session cap, the policy off and every send still
// open the PIN sheet (the Kute PIN fallback here, biometrics off). Relock
// resets the session budget.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/session_unlock.dart';
import 'package:kute/helpers/small_action_allowance.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart'
    show kFundUsdLimit, kFundVenueLimit, kFundVenueInvesting;
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
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

RuntimeCapabilities _policy(int cents) {
  final now = DateTime.now().toUtc();
  return RuntimeCapabilities.fromJson(jsonDecode(jsonEncode({
    'schemaVersion': 1,
    'revision': 9,
    'evaluatedAt': now.toIso8601String(),
    'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
    'capabilities': {},
    'fees': {},
    'ai': {},
    'referral': {},
    'security': {'smallActionAllowanceCents': cents},
  })) as Map<String, dynamic>);
}

const _perp = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

SensitiveIntent _bet(double usd) => PmGrants.betReview(
    walletId: 'w1',
    tokenId: '0xyes',
    maxCostUsd: usd,
    worstPrice: 0.55,
    orderType: 'fok');

SensitiveIntent _fundedBet(double usd) => PmGrants.fundedBetReview(_bet(usd),
    fundUsd: usd, venue: IntentVenue.polymarket);

SensitiveIntent _sell(double shares) => PmGrants.sellReview(
    walletId: 'w1',
    tokenId: '0xyes',
    shares: shares,
    worstPrice: 0.5,
    orderType: 'fok');

SensitiveIntent _perpOrder(double usd) => HlIntents.openPosition(
    walletId: 'w1',
    market: _perp,
    isLong: true,
    marginUsd: usd,
    leverage: 1,
    isCross: true);

SensitiveIntent _spotOrder(double usd) => HlIntents.spotOrder(
    walletId: 'w1',
    market: _perp.copyWith(),
    isBuy: true,
    usd: usd);

SensitiveIntent _close() => HlIntents.close(
    walletId: 'w1', market: _perp, positionIsLong: true, fraction: 0.25);

SensitiveIntent _fundedPerp(double usd) {
  final order = _perpOrder(usd);
  return order.copyWith(limits: {
    ...order.limits,
    kFundUsdLimit: IntentUnits.usd(usd).toString(),
    kFundVenueLimit: kFundVenueInvesting,
  });
}

SensitiveIntent _send(SensitiveAction action) => SensitiveIntent(
      action: action,
      walletId: 'w1',
      venue: IntentVenue.orchestra,
      destination: 'sp1someoneelse',
      asset: 'USDB',
      amountMax: IntentUnits.usd(5),
      limits: const {IntentLimit.provider: 'orchestra'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late int policyCents;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    FastBetWindow.instance.debugReset();
    policyCents = 5000;
    SmallActionAllowance.debugInstance = SmallActionAllowance(
        readSnapshot: () => policyCents < 0 ? null : _policy(policyCents));
  });

  tearDown(() {
    SmallActionAllowance.debugInstance = null;
    AuthGrantRegistry.instance.revokeAll(includeAutofire: true);
    FastBetWindow.instance.debugReset();
    SecretStores.debugReset();
  });

  late WidgetRef wref;

  Future<BuildContext> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
    ]);
    addTearDown(container.dispose);
    container.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    late BuildContext ctx;
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
            body: Consumer(builder: (c, r, _) {
              ctx = c;
              wref = r;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return ctx;
  }

  Future<AuthGrant?> ask(BuildContext ctx, SensitiveIntent intent, double usd,
          {String? autofireIntentId}) =>
      requireFreshAuthGrant(
        ctx,
        wref,
        intent: intent,
        reason: 'Confirm',
        amountUsd: usd,
        smallAction: SmallActionContext.usd(usd),
        autofireIntentId: autofireIntentId,
      );

  Future<AuthGrant?> noPrompt(WidgetTester tester, BuildContext ctx,
      SensitiveIntent intent, double usd,
      {String? autofireIntentId}) async {
    final grant = await ask(ctx, intent, usd, autofireIntentId: autofireIntentId);
    await tester.pump();
    expect(find.byType(PinGateSheet), findsNothing,
        reason: 'this order should not ask');
    expect(grant, isNotNull);
    expect(grant!.method, AuthGrantMethod.allowance);
    return grant;
  }

  /// The order asks: the PIN sheet opens; typing the PIN approves it.
  Future<void> prompts(WidgetTester tester, BuildContext ctx,
      SensitiveIntent intent, double usd) async {
    final pending = ask(ctx, intent, usd);
    await tester.pumpAndSettle();
    expect(find.byType(PinGateSheet), findsOneWidget,
        reason: 'this order should ask');
    for (final d in '111111'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect((await pending)!.method, AuthGrantMethod.pin);
  }

  testWidgets('bets, sells, Investing orders and closes under \$50 do not ask',
      (tester) async {
    final ctx = await pump(tester);
    for (final (intent, usd) in [
      (_bet(49.99), 49.99),
      (_sell(60), 30.0),
      (_perpOrder(20), 20.0),
      (_spotOrder(10), 10.0),
      (_close(), 15.0),
    ]) {
      final grant = await noPrompt(tester, ctx, intent, usd);
      // Bound to exactly this order: the executor consumes it as usual.
      AuthGrants.consume(grant!, intent);
    }
    expect(SmallActionAllowance.instance.sessionSpentCents, 12499);
  });

  testWidgets('a funded order under \$50 is held as its autofire grant',
      (tester) async {
    final ctx = await pump(tester);
    final bet = _fundedBet(12);
    await noPrompt(tester, ctx, bet, 12, autofireIntentId: 'pending-bet');
    expect(AuthGrantRegistry.instance.hasAutofireGrant('pending-bet'), isTrue);
    final held = AuthGrantRegistry.instance.peekAutofire('pending-bet')!;
    expect(held.method, AuthGrantMethod.allowance);
    // The funding leg's cap is bound: the rail's hook honours it, and the
    // order consumes the same grant.
    expect(
        PmGrants.fundingGrantCovers(held,
            amountIn: IntentUnits.usd(12), venue: IntentVenue.polymarket),
        isTrue);
    AuthGrantRegistry.instance.consumeAutofire('pending-bet', bet,
        session: const _Unlocked());

    final perp = _fundedPerp(30);
    await noPrompt(tester, ctx, perp, 30, autofireIntentId: 'pending-hl');
    expect(AuthGrantRegistry.instance.hasAutofireGrant('pending-hl'), isTrue);
    // The order was cancelled: its 30 min timer goes with it.
    AuthGrantRegistry.instance.cancelAutofire('pending-hl');
  });

  testWidgets('\$50.00 and above asks', (tester) async {
    final ctx = await pump(tester);
    await prompts(tester, ctx, _bet(50), 50);
    await prompts(tester, ctx, _perpOrder(75), 75);
    expect(SmallActionAllowance.instance.sessionSpentCents, 0);
  });

  testWidgets('the session cap asks; relock starts a new budget',
      (tester) async {
    final ctx = await pump(tester);
    for (var i = 0; i < 5; i++) {
      await noPrompt(tester, ctx, _bet(49.99), 49.99);
    }
    await prompts(tester, ctx, _bet(1), 1);
    resetStepUpSession();
    expect(SmallActionAllowance.instance.sessionSpentCents, 0);
    await noPrompt(tester, ctx, _bet(1), 1);
  });

  testWidgets('the policy off, stale or missing asks', (tester) async {
    final ctx = await pump(tester);
    policyCents = 0;
    await prompts(tester, ctx, _bet(5), 5);
    policyCents = -1; // no fresh snapshot
    await prompts(tester, ctx, _bet(5), 5);
  });

  testWidgets('sends, withdrawals, gifts and Swap under \$50 still ask',
      (tester) async {
    final ctx = await pump(tester);
    for (final action in [
      SensitiveAction.send,
      SensitiveAction.moveTransfer,
      SensitiveAction.venueWithdraw,
      SensitiveAction.venueDeposit,
    ]) {
      await prompts(tester, ctx, _send(action), 5);
    }
    expect(SmallActionAllowance.instance.sessionSpentCents, 0);
  });
}

class _Unlocked implements StepUpSessionState {
  const _Unlocked();
  @override
  bool get isSessionUnlocked => true;
}
