// The wallet step on a shared market (share_wallet_gate.dart) and the
// receive gate for a 12-word wallet made from a share link before its
// words are backed up (receive_sheet.dart, ReceiveBackupGate).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/in_app_browser.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/share/share_wallet_gate.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/share_targets.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: wallets.isEmpty ? null : wallets.first.id,
      wallets: wallets,
    );

void main() {
  final events = <String>[];
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    ShareLinksStore.debugMemory = {};
    ShareTargets.debugReset();
    ShareWalletGate.debugReset();
    events.clear();
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
  });
  tearDown(() {
    ShareLinksStore.debugMemory = null;
    TrackingService.debugTrackObserver = null;
    InAppBrowser.debugUserAgent = null;
  });

  Widget app(Widget home, {List<WalletConfig> wallets = const []}) {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
          path: '/set_pin',
          builder: (_, __) => const Scaffold(body: Text('SET PIN'))),
    ]);
    return ProviderScope(
      overrides: [
        settingsProvider
            .overrideWith((_) => SettingsModel(_settings(wallets))),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
  }

  Widget yes() => Builder(
      builder: (context) => TextButton(
          onPressed: () => ShareWalletGate.open(context,
              target: ShareTarget.of(investing: false, slug: 'will-it-rain'),
              pick: const ShareWalletPick(outcome: 'Yes'),
              resume: () {}),
          child: const Text('Yes')));

  testWidgets('one step, one button; Create account parks and sets the PIN',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(body: yes())));
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your wallet'), findsOneWidget);
    // The one primary is the bar's (drawn by the shell bar in the app).
    final scope = tester.widget<KuteBarContextScope>(find
        .byWidgetPredicate((w) =>
            w is KuteBarContextScope &&
            w.barContext.label == 'Create account'));
    // Nothing is parked or started while the person only reads the step.
    expect(ShareLinksStore.parkedShareTarget, isNull);
    expect(events, isNot(contains('quick_wallet_started')));
    scope.barContext.onPrimary!();
    await tester.pumpAndSettle();
    expect(find.text('SET PIN'), findsOneWidget);
    expect(events, contains('quick_wallet_started'));
    expect(ShareTargets.arrivedThroughShare, isTrue);
    final parked = ShareTargets.takeParked()!;
    expect(parked.target.slug, 'will-it-rain');
    expect(parked.after, 'onboarding');
    expect(ShareWalletGate.takePendingPick()!.outcome, 'Yes');
  });

  testWidgets('closing the step creates nothing and says so',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(body: yes())));
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(events, contains('quick_wallet_abandoned'));
    expect(ShareLinksStore.parkedShareTarget, isNull);
    expect(find.text('SET PIN'), findsNothing);
  });

  testWidgets('an in-app browser is told to open Safari', (tester) async {
    InAppBrowser.debugUserAgent =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram';
    await tester.pumpWidget(app(Scaffold(body: yes())));
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-gate-in-app')), findsOneWidget);
    expect(find.textContaining('Safari'), findsOneWidget);
  });

  group('receive gate', () {
    Future<void> pumpGate(WidgetTester tester, WalletConfig w) async {
      await tester.pumpWidget(app(
          const Scaffold(
              body: ReceiveBackupGate(child: Text('ADDRESS'))),
          wallets: [w]));
      await tester.pumpAndSettle();
    }

    testWidgets('a quick 12-word wallet not backed up shows no address',
        (tester) async {
      ShareLinksStore.markQuickWallet('q1');
      await pumpGate(tester, WalletConfig(id: 'q1', name: 'Q'));
      expect(find.text('ADDRESS'), findsNothing);
      expect(find.byKey(const ValueKey('receive-backup-gate')), findsOneWidget);
    });

    testWidgets('backed up: the address', (tester) async {
      ShareLinksStore.markQuickWallet('q1');
      await pumpGate(tester, WalletConfig(id: 'q1', name: 'Q', backedUp: true));
      expect(find.text('ADDRESS'), findsOneWidget);
    });

    testWidgets('every other wallet is untouched', (tester) async {
      await pumpGate(tester, WalletConfig(id: 'old', name: 'Old'));
      expect(find.text('ADDRESS'), findsOneWidget);
      ShareLinksStore.markQuickWallet('pk');
      await pumpGate(
          tester, WalletConfig(id: 'pk', name: 'P', isPasskey: true));
      expect(find.text('ADDRESS'), findsOneWidget);
    });
  });

  test('in-app browser classification', () {
    expect(
        InAppBrowser.classify('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
            'Mobile/15E148 Safari/604.1'),
        'safari');
    expect(
        InAppBrowser.classify('Mozilla/5.0 (Linux; Android 14; Pixel 8) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile '
            'Safari/537.36'),
        'chrome');
    expect(
        InAppBrowser.classify('Mozilla/5.0 (Linux; Android 14; wv) '
            'AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36; wv)'),
        'in_app');
    expect(InAppBrowser.classify('... Telegram-Android/11 ...'), 'in_app');
    expect(
        InAppBrowser.classify('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'),
        'in_app');
  });
}
