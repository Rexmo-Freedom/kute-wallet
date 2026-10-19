// Financial hub navigation: compact wallet roster under a row of header
// buttons (Settings, Support, Referrals). Notifications have no door in this
// sheet; Referrals follows affiliate.program.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCirclePillButton;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy({this.withheld = const {}});
  final Set<String> withheld;
  @override
  CapabilityDecision decision(String id) =>
      CapabilityDecision(allowed: !withheld.contains(id));
  @override
  bool allows(String id) => !withheld.contains(id);
}

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _savings = WalletConfig(
    id: 'savings', name: 'Savings', sparkEnabled: false, walletType: 'bitcoin');

Future<void> _pump(WidgetTester tester,
    {String? shellWalletId,
    ActiveNavTab activeTab = ActiveNavTab.home,
    Set<String> withheld = const {},
    List<Override>? notifications}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final policy = _Policy(withheld: withheld);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      // Keep all shell dependencies offline.
      ...offlineVenueOverrides,
      // The Portfolio the hub opens, offline.
      ...portfolioOverrides(notifications: false),
      ...?notifications,
      if (notifications == null)
        tradeNotificationsProvider
            .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [_spending, _savings],
          ))),
      shellWalletIdProvider.overrideWith((_) => shellWalletId),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        theme: ThemeData(
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: Stack(children: [
                KuteTopNavBar(activeTab: activeTab, onSelectTab: (_) {}),
              ]),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('settings route')),
          ),
          GoRoute(
            path: '/affiliate',
            builder: (_, __) => const Scaffold(body: Text('referral route')),
          ),
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('home route')),
          ),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets('one +-and-gear button opens the Financial hub', (tester) async {
    final semantics = tester.ensureSemantics();
    final events = _events();
    await _pump(tester);
    // One button, one glyph: no separate gear or + on the bar.
    expect(find.byType(HubPlusGearGlyph), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.bySemanticsLabel('Financial hub and settings'), findsOneWidget);
    final glyph =
        tester.widget<HubPlusGearGlyph>(find.byType(HubPlusGearGlyph));
    expect(glyph.color,
        tester.element(find.byType(HubPlusGearGlyph)).colors.textPrimary);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsOneWidget);
    expect(find.text('Spending'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    // One row under the title: Settings, then Support as a bare icon, then
    // Referrals. The old Support / Referral program rows are gone.
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byType(KuteCirclePillButton), findsNWidgets(2));
    expect(find.text('Support'), findsNothing);
    expect(find.text('Referral program'), findsNothing);
    expect(find.bySemanticsLabel('Support'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Financial hub'));
    expect(title.style!.fontSize, 22);
    final settingsAt = tester.getCenter(find.text('Settings'));
    final supportAt =
        tester.getCenter(find.byIcon(Icons.support_agent_rounded));
    final referralsAt = tester.getCenter(find.text('Referrals'));
    expect(settingsAt.dy, closeTo(supportAt.dy, 1));
    expect(settingsAt.dx, lessThan(supportAt.dx));
    // The row sits on the right, never centred or flush left.
    expect(tester.getTopRight(find.byIcon(Icons.support_agent_rounded)).dx,
        greaterThan(tester.getTopRight(find.text('Financial hub')).dx));
    // Referrals follows Support: beside it, or on the next line where the
    // test font makes the row wider than the sheet (it wraps, never
    // overflows).
    expect(
        referralsAt.dy > supportAt.dy + 1 || referralsAt.dx > supportAt.dx,
        isTrue);
    expect(tester.getBottomLeft(find.text('Financial hub')).dy,
        lessThan(tester.getTopLeft(find.text('Settings')).dy));
    expect(tester.getBottomLeft(find.text('Settings')).dy,
        lessThan(tester.getTopLeft(find.text('Spending')).dy));
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    // Wallets only: search has its own door in the dock, Sal its own.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ask Sal anything'), findsNothing);
    expect(find.text('Ask Sal'), findsNothing);
    expect(
        events.where((e) => e.$1 == 'wallet_actions_opened').map((e) => e.$2), [
      {'source': 'home_plus'}
    ]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('the hub has no Portfolio row (it lives inside Investments)',
      (tester) async {
    await _pump(tester, activeTab: ActiveNavTab.trading);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hub-portfolio')), findsNothing);
    expect(find.text('Portfolio'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the button names the tab it was opened on', (tester) async {
    final events = _events();
    await _pump(tester, activeTab: ActiveNavTab.predictions);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'wallet_actions_opened').map((e) => e.$2), [
      {'source': 'predictions_plus'}
    ]);
  });

  testWidgets('Settings in the hub header closes it and opens /settings',
      (tester) async {
    final events = _events();
    await _pump(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings route'), findsOneWidget);
    expect(find.text('Financial hub'), findsNothing);
    expect(events.where((e) => e.$1 == 'settings_opened').map((e) => e.$2), [
      {'source': 'financial_hub', 'entry_source': 'financial_hub'}
    ]);
  });

  testWidgets('Support closes the hub and opens the existing support action',
      (tester) async {
    final events = _events();
    await _pump(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.support_agent_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsNothing);
    expect(events.where((e) => e.$1 == 'support_opened').map((e) => e.$2), [
      {'source': 'financial_hub'}
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Referrals closes the hub and opens /affiliate', (tester) async {
    await _pump(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Referrals'));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsNothing);
    expect(find.text('referral route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Referrals is hidden where affiliate.program is withheld',
      (tester) async {
    await _pump(tester, withheld: {'affiliate.program'});
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsOneWidget);
    expect(find.text('Referrals'), findsNothing);
    expect(find.byIcon(Icons.group_rounded), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-tapping the active first tab opens nothing', (tester) async {
    final events = _events();
    await _pump(tester);
    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsNothing);
    expect(find.text('Add account'), findsNothing);
    expect(events.where((e) => e.$1 == 'wallet_actions_opened'), isEmpty);
  });

  testWidgets('re-tapping an active wallet tab opens nothing either',
      (tester) async {
    await _pump(tester, shellWalletId: 'savings');
    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsNothing);
    expect(find.text('Add account'), findsNothing);
  });

  testWidgets('unread receipts do not restore a bell in the hub',
      (tester) async {
    await _pump(tester, notifications: [
      tradeNotificationsProvider.overrideWith((_) => Stream.value([
            TradeNotification(
              id: 'unread',
              account: 'acct',
              product: 'predictions',
              title: 'Prediction bought',
              subtitle: 'Market · Yes',
              rows: const {'Bought': r'$5.00'},
              time: 1700000000000,
              read: false,
            ),
          ])),
    ]);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    expect(find.byType(Badge), findsNothing);
    expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
  });
}
