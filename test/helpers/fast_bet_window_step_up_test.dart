// The fast-bet window end to end through the step-up helper: the first
// short-round order asks (here the Kute PIN fallback, biometrics off), the
// next ones do not, and every way out of a short-round screen, the app or
// the session makes the next order ask again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/session_unlock.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

class _Settings extends SettingsModel {
  _Settings(List<WalletConfig> wallets) : super(_settings(wallets));
  void wallets(List<WalletConfig> wallets) => state = _settings(wallets);
}

Settings _settings(List<WalletConfig> wallets) => Settings(
      wallets: wallets,
      activeWalletId: wallets.first.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

const _round = 'btc-updown-5m-1791152100';
const _normal = 'will-it-rain-in-lisbon-tomorrow';

SensitiveIntent _buy(int cents) => PmIntents.order(
      walletId: 'w1',
      tokenId: '0xabc',
      isBuy: true,
      amountMax: BigInt.from(cents) * BigInt.from(10000),
      limitPrice: 0.55,
      orderType: 'fok',
      maxSlippageBps: 200,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    FastBetWindow.instance.debugReset();
  });

  tearDown(() {
    FastBetWindow.instance.debugReset();
    SecretStores.debugReset();
  });

  final showScope = ValueNotifier<bool>(true);
  late WidgetRef wref;

  Future<(ProviderContainer, _Settings, BuildContext)> pump(
      WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    showScope.value = true;
    final settings = _Settings([
      WalletConfig(id: 'w1', name: 'Spending'),
      WalletConfig(id: 'w2', name: 'Other'),
    ]);
    final container = ProviderContainer(overrides: [
      authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      settingsProvider.overrideWith((ref) => settings),
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
            body: ValueListenableBuilder<bool>(
              valueListenable: showScope,
              builder: (_, show, __) => show
                  ? FastBetScope(
                      active: true,
                      child: Consumer(builder: (c, r, _) {
                        ctx = c;
                        wref = r;
                        return const SizedBox.expand();
                      }),
                    )
                  : Consumer(builder: (c, r, _) {
                      ctx = c;
                      wref = r;
                      return const SizedBox.expand();
                    }),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (container, settings, ctx);
  }

  /// Starts a step-up for [intent] and returns its pending result.
  Future<AuthGrant?> ask(
    WidgetTester tester,
    BuildContext ctx, {
    SensitiveIntent? intent,
    String? slug = _round,
    bool hot = true,
  }) {
    final i = intent ?? _buy(1000);
    return requireFreshAuthGrant(
      ctx,
      wref,
      intent: i,
      reason: 'Confirm',
      smallAction: SmallActionContext(
        amountUsdCents: PmGrants.usdCentsCeil(i.amountMax),
        paidFromVenueBalance: true,
        hasFundingLeg: false,
      ),
      fastBet: FastBetRequest(eventSlug: slug, hot: hot),
    );
  }

  Future<void> typePin(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.byType(PinGateSheet), findsOneWidget,
        reason: 'this order should ask');
    for (final d in '111111'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  }

  /// Approves the first short-round order with the PIN: opens the window.
  Future<AuthGrant?> approveFirst(WidgetTester tester, BuildContext ctx,
      {SensitiveIntent? intent}) async {
    final pending = ask(tester, ctx, intent: intent);
    await typePin(tester);
    return pending;
  }

  Future<AuthGrant?> askNoPrompt(WidgetTester tester, BuildContext ctx,
      {SensitiveIntent? intent, String? slug = _round, bool hot = true}) async {
    final grant = await ask(tester, ctx, intent: intent, slug: slug, hot: hot);
    await tester.pump();
    expect(find.byType(PinGateSheet), findsNothing);
    return grant;
  }

  testWidgets('the first approval opens it and the next bet does not ask',
      (tester) async {
    final (_, _, ctx) = await pump(tester);
    final first = await approveFirst(tester, ctx);
    expect(first!.method, AuthGrantMethod.pin);
    expect(FastBetWindow.instance.isOpen, isTrue);

    final second = await askNoPrompt(tester, ctx);
    expect(second!.method, AuthGrantMethod.fastWindow);
    final third = await askNoPrompt(tester, ctx, intent: _buy(2500));
    expect(third!.method, AuthGrantMethod.fastWindow);
    expect(FastBetWindow.instance.spentCents, 3500);
  });

  testWidgets('past the \$50 cap the next buy asks and opens a fresh window',
      (tester) async {
    final (_, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    expect((await askNoPrompt(tester, ctx, intent: _buy(5000)))!.method,
        AuthGrantMethod.fastWindow);
    final over = await approveFirst(tester, ctx, intent: _buy(100));
    expect(over!.method, AuthGrantMethod.pin);
    expect(FastBetWindow.instance.isOpen, isTrue);
    expect(FastBetWindow.instance.spentCents, 0);
    expect((await askNoPrompt(tester, ctx, intent: _buy(100)))!.method,
        AuthGrantMethod.fastWindow);
  });

  for (final (name, slug, hot) in [
    ('a normal market', _normal, true),
    ('an hourly Up/Down market', 'btc-updown-4h-1791144000', true),
    ('a Ledger order', _round, false),
  ]) {
    testWidgets('$name always asks, even with the window open',
        (tester) async {
      final (_, _, ctx) = await pump(tester);
      await approveFirst(tester, ctx);
      final pending = ask(tester, ctx, slug: slug, hot: hot);
      await tester.pumpAndSettle();
      expect(find.byType(PinGateSheet), findsOneWidget);
      expect(FastBetWindow.instance.isOpen, isTrue,
          reason: 'it asked although the window was open');
      await typePin(tester);
      expect((await pending)!.method, AuthGrantMethod.pin);
    });
  }

  testWidgets('backgrounding ends it', (tester) async {
    final (_, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.background);
    final next = ask(tester, ctx);
    await typePin(tester);
    expect((await next)!.method, AuthGrantMethod.pin);
  });

  testWidgets('the session lock ends it', (tester) async {
    final (container, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    container.read(appLockedProvider.notifier).state = true;
    await tester.pump();
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.sessionLock);
  });

  testWidgets('the lock engaging (resetStepUpSession) ends it',
      (tester) async {
    final (_, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    resetStepUpSession();
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.debugHoldsState, isFalse);
  });

  testWidgets('a logout or wipe (session cleared) ends it', (tester) async {
    final (container, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    container.read(sessionAuthProvider.notifier).state = null;
    await tester.pump();
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.sessionChanged);
  });

  testWidgets('leaving the short-round screens ends it', (tester) async {
    final (_, _, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    showScope.value = false;
    await tester.pumpAndSettle();
    expect(FastBetWindow.instance.scopes, 0);
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.leftScreens);
  });

  testWidgets('a wallet switch ends it', (tester) async {
    final (_, settings, ctx) = await pump(tester);
    await approveFirst(tester, ctx);
    settings.wallets([
      WalletConfig(id: 'w2', name: 'Other'),
      WalletConfig(id: 'w1', name: 'Spending'),
    ]);
    await tester.pump();
    expect(FastBetWindow.instance.isOpen, isFalse);
    expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.walletChanged);
  });
}
