// The Financial hub (owner decision October 2026): the one button at the
// top right of the shell's top bar, where the Settings gear was, wearing a
// rounded + with a gear badge (HubPlusGearGlyph), opens the hub sheet:
// the wallet list, switch wallet and Add wallet, Settings (a labelled
// pill) and Notifications (the round bell) side by side in its header,
// and nothing else (no search, no Ask Sal). The strip's first tab is a plain tab: re-tapping it opens
// nothing, so that button is the one door on the shell.

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
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show AppBottomSheetHeader;
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCircleButton, KuteCirclePillButton;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => true;
}

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _savings = WalletConfig(
    id: 'savings', name: 'Savings', sparkEnabled: false, walletType: 'bitcoin');

Future<void> _pump(WidgetTester tester,
    {String? shellWalletId,
    ActiveNavTab activeTab = ActiveNavTab.home,
    List<Override>? notifications}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final policy = _Policy();
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      // The sheet's header carries the trade results button; the venues
      // and the notification store stay offline here.
      ...offlineVenueOverrides,
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
    // Settings and Notifications side by side in the header: Settings a
    // labelled pill (gear + word) left of the bell, no Settings row in
    // the list below Add account.
    final header = find.byType(AppBottomSheetHeader);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final f in [
      find.byIcon(Icons.settings_rounded),
      find.text('Settings'),
      find.byIcon(Icons.notifications_none_rounded),
    ]) {
      expect(find.descendant(of: header, matching: f), findsOneWidget);
    }
    final settingsPill = find.byType(KuteCirclePillButton);
    expect(tester.getTopRight(settingsPill).dx,
        lessThan(tester.getTopLeft(find.byType(KuteCircleButton)).dx));
    // Same height and vertical centre as the bell's circle beside it.
    expect(tester.getSize(settingsPill).height,
        tester.getSize(find.byType(KuteCircleButton)).height);
    expect(tester.getCenter(settingsPill).dy,
        tester.getCenter(find.byType(KuteCircleButton)).dy);
    expect(tester.getBottomLeft(find.text('Settings')).dy,
        lessThan(tester.getTopLeft(find.text('Spending')).dy));
    // Add account is the hub's last item again.
    expect(tester.getTopLeft(find.text('Settings')).dy,
        lessThan(tester.getTopLeft(find.text('Add account')).dy));
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    // Wallets only: search has its own door in the dock, Sal its own.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ask Sal anything'), findsNothing);
    expect(find.text('Ask Sal'), findsNothing);
    expect(
        events.where((e) => e.$1 == 'wallet_actions_opened').map((e) => e.$2),
        [
          {'source': 'home_plus'}
        ]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('the button names the tab it was opened on', (tester) async {
    final events = _events();
    await _pump(tester, activeTab: ActiveNavTab.predictions);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'wallet_actions_opened').map((e) => e.$2),
        [
          {'source': 'predictions_plus'}
        ]);
  });

  testWidgets('Settings in the hub header closes it and opens /settings',
      (tester) async {
    final events = _events();
    await _pump(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AppBottomSheetHeader),
        matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(find.text('settings route'), findsOneWidget);
    expect(find.text('Financial hub'), findsNothing);
    expect(events.where((e) => e.$1 == 'settings_opened').map((e) => e.$2), [
      {'source': 'financial_hub', 'entry_source': 'financial_hub'}
    ]);
  });

  testWidgets('Notifications in the hub opens the notifications sheet',
      (tester) async {
    final events = _events();
    await _pump(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Your notifications'), findsOneWidget);
    expect(
        events
            .where((e) => e.$1 == 'trade_notifications_opened')
            .map((e) => e.$2),
        [
          {'unread': 0, 'entry_source': 'financial_hub'}
        ]);
  });

  testWidgets('re-tapping the active first tab opens nothing',
      (tester) async {
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

  group('the Notifications badge', () {
    TradeNotification receipt(String id, {bool read = false}) =>
        TradeNotification(
            id: id,
            account: 'acct',
            product: 'predictions',
            title: 'Prediction bought',
            subtitle: 'Market $id · Yes',
            rows: const {'Bought': r'$5.00'},
            time: 1700000000000,
            read: read);
    // An in-memory stand-in for the durable store (its own read state is
    // covered in trade_notification_store_test): the provider re-reads it
    // on every refresh, as the real one does.
    late Map<String, TradeNotification> store;
    late List<Override> overrides;
    setUp(() {
      store = {};
      overrides = [
        tradeNotificationsProvider
            .overrideWith((_) => Stream.value(store.values.toList())),
        markTradeNotificationsReadProvider.overrideWithValue((items) async {
          for (final n in items) {
            store[n.id] = TradeNotification.fromJson(
                {...n.toJson(), 'read': true});
          }
        }),
      ];
    });
    Badge badge(WidgetTester tester) =>
        tester.widget<Badge>(find.byType(Badge));

    testWidgets('stays hidden when every receipt is read', (tester) async {
      store['seen'] = receipt('seen', read: true);
      await _pump(tester, notifications: overrides);
      await tester.tap(find.byType(HubPlusGearGlyph));
      await tester.pumpAndSettle();
      expect(badge(tester).isLabelVisible, isFalse);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('counts unread receipts and clears once they are opened',
        (tester) async {
      final events = _events();
      store['a'] = receipt('a');
      store['b'] = receipt('b');
      store['old'] = receipt('old', read: true);
      await _pump(tester, notifications: overrides);
      await tester.tap(find.byType(HubPlusGearGlyph));
      await tester.pumpAndSettle();
      expect(badge(tester).isLabelVisible, isTrue);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Your notifications'), findsOneWidget);
      expect(store.values.where((n) => !n.read), isEmpty);
      // This visit still marks what was new when it opened.
      expect(find.byIcon(Icons.circle), findsNWidgets(2));
      expect(
          events
              .where((e) => e.$1 == 'trade_notifications_opened')
              .map((e) => e.$2),
          [
            {'unread': 2, 'entry_source': 'financial_hub'}
          ]);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(badge(tester).isLabelVisible, isFalse);
      expect(find.text('2'), findsNothing);

      // A new result brings it back.
      store['c'] = receipt('c');
      ProviderScope.containerOf(tester.element(find.byType(Badge)))
          .invalidate(tradeNotificationsProvider);
      await tester.pumpAndSettle();
      expect(badge(tester).isLabelVisible, isTrue);
      expect(find.text('1'), findsOneWidget);
    });
  });
}
