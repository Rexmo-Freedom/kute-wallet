// Financial hub navigation: the app's big cards under its title (founder,
// 7 November 2026: "with the bigger cards just like the other parts of the
// app now"): Settings on top, the grid's lead, then Referrals and Support
// as two squares; then the wallet roster, each account and Add account a
// full-width card on the same soft surface. Notifications have no door in
// this sheet; Referrals follows affiliate.program, Rate the app taking its
// card where it is withheld, as on Settings.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show ActiveNavTab;
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
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
    List<Override>? notifications,
    bool dark = false,
    Size size = const Size(430, 932),
    Locale? locale}) async {
  tester.view.physicalSize = size;
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
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        locale: locale,
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

Finder _hubCard(String id) => find.byKey(ValueKey('hub-card-$id'));

/// The soft card surface under [card]: the decoration of its first
/// decorated Container.
BoxDecoration? _surfaceOf(WidgetTester tester, Finder card) {
  final boxes = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration));
  if (boxes.evaluate().isEmpty) return null;
  return tester.widget<Container>(boxes.first).decoration as BoxDecoration?;
}

/// Opens the hub from the top bar's + and gear.
Future<void> _openHub(WidgetTester tester) async {
  await tester.tap(find.byType(HubPlusGearGlyph));
  await tester.pumpAndSettle();
}

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// How many lines [text] takes inside [card].
int _lines(WidgetTester tester, Finder card, String text) {
  final p = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.descendant(of: card, matching: find.text(text)),
      matching: find.byType(RichText)));
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
  )..layout(maxWidth: p.constraints.maxWidth);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
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
    // The big cards where the header pills were: Settings on top, the
    // grid's lead, then Referrals and Support side by side. No pill.
    expect(find.byType(KuteCirclePillButton), findsNothing);
    final grid = tester
        .widget<KuteActionCardGrid>(find.byKey(const ValueKey('hub-cards')));
    expect(grid.lead?.key, const ValueKey('hub-card-settings'));
    expect(grid.cards.map((c) => c.key), [
      const ValueKey('hub-card-referral'),
      const ValueKey('hub-card-support'),
    ]);
    expect(grid.oneLineTitles, isTrue);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.text('Security and more'), findsOneWidget);
    expect(find.text('Referrals'), findsOneWidget);
    expect(find.text('Invite friends'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Get help'), findsOneWidget);
    expect(find.text('Referral program'), findsNothing);
    expect(find.text('Rate the app'), findsNothing);
    final title = tester.widget<Text>(find.text('Financial hub'));
    expect(title.style!.fontSize, 22);
    final settings = tester.getRect(_hubCard('settings'));
    final referral = tester.getRect(_hubCard('referral'));
    final support = tester.getRect(_hubCard('support'));
    // Under the title; Settings across the top, the two squares under it,
    // side by side and equally tall; then the accounts.
    expect(tester.getBottomLeft(find.text('Financial hub')).dy,
        lessThan(settings.top));
    expect(settings.bottom, lessThan(referral.top));
    expect(settings.left, moreOrLessEquals(referral.left));
    expect(settings.right, moreOrLessEquals(support.right));
    expect(referral.top, moreOrLessEquals(support.top));
    expect(referral.height, moreOrLessEquals(support.height));
    expect(referral.right, lessThan(support.left));
    expect(
        support.bottom, lessThan(tester.getTopLeft(find.text('Spending')).dy));
    expect(
        find.bySemanticsLabel('Settings, Security and more'), findsOneWidget);
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

  testWidgets('the Settings card closes the hub and opens /settings',
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
    await tester.tap(find.text('Support'));
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

  testWidgets(
      'where affiliate.program is withheld Rate the app takes the referral '
      'card: still three cards, no reason shown', (tester) async {
    await _pump(tester, withheld: {'affiliate.program'});
    await _openHub(tester);
    expect(find.text('Financial hub'), findsOneWidget);
    expect(find.text('Referrals'), findsNothing);
    expect(find.byIcon(Icons.group_rounded), findsNothing);
    expect(_hubCard('referral'), findsNothing);
    expect(_hubCard('rate'), findsOneWidget);
    expect(find.text('Rate the app'), findsOneWidget);
    expect(find.text('Leave a review'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.textContaining('Not available'), findsNothing);
    final grid = tester
        .widget<KuteActionCardGrid>(find.byKey(const ValueKey('hub-cards')));
    expect(grid.lead?.key, const ValueKey('hub-card-settings'));
    expect(grid.cards.map((c) => c.key), [
      const ValueKey('hub-card-rate'),
      const ValueKey('hub-card-support'),
    ]);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Rate the app closes the hub and asks the store for a review, '
      'tracked as Settings\' rate_app tap from the hub', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('dev.britannio.in_app_review');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'isAvailable' ? true : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final events = _events();
    await _pump(tester, withheld: {'affiliate.program'});
    await _openHub(tester);
    await tester.tap(find.text('Rate the app'));
    await tester.pumpAndSettle();
    expect(find.text('Financial hub'), findsNothing);
    expect(calls, ['isAvailable', 'requestReview']);
    expect(
        events.where((e) => e.$1 == 'settings_action_tapped').map((e) => e.$2),
        [
          {'feature': 'rate_app', 'source': 'financial_hub'}
        ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the cards and the accounts wear the app\'s one soft card, light '
      'and dark: each account its own full-width card, the check mark on '
      'the account the first tab shows, the venue marks on the spending '
      'account, Add account with the cards\' + tile', (tester) async {
    for (final dark in [false, true]) {
      await _pump(tester, dark: dark);
      await _openHub(tester);
      final why = dark ? 'dark' : 'light';
      final context = tester.element(_hubCard('settings'));
      final soft = PremiumGroupContainer.decorationOf(context);
      final spending = find.byKey(const ValueKey('hub-account-spending'));
      final savings = find.byKey(const ValueKey('hub-account-savings'));
      final add = find.byKey(const ValueKey('hub-add-account'));
      for (final card in [
        _hubCard('settings'),
        _hubCard('referral'),
        _hubCard('support'),
        spending,
        savings,
        add,
      ]) {
        expect(card, findsOneWidget, reason: why);
        expect(_surfaceOf(tester, card), soft, reason: why);
      }
      // A list, one card under another, full width, 12 apart, as tall as
      // each other.
      final a = tester.getRect(spending);
      final b = tester.getRect(savings);
      final c = tester.getRect(add);
      final cardsRight = tester.getRect(_hubCard('settings')).right;
      for (final r in [a, b, c]) {
        expect(
            r.left, moreOrLessEquals(tester.getRect(_hubCard('settings')).left),
            reason: why);
        expect(r.right, moreOrLessEquals(cardsRight), reason: why);
      }
      expect(b.top - a.bottom, moreOrLessEquals(12, epsilon: 0.5), reason: why);
      expect(c.top - b.bottom, moreOrLessEquals(12, epsilon: 0.5), reason: why);
      expect(a.height, moreOrLessEquals(b.height), reason: why);
      expect(b.height, moreOrLessEquals(c.height), reason: why);
      // The account the first tab shows wears the check; the others a
      // chevron.
      expect(
          find.descendant(
              of: spending, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget,
          reason: why);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: why);
      expect(
          find.descendant(
              of: savings, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget,
          reason: why);
      expect(
          find.descendant(
              of: add, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget,
          reason: why);
      // The spending account's marks: bitcoin, Hyperliquid, Polymarket;
      // a plain Bitcoin account carries none.
      Finder mark(Finder card, String asset) => find.descendant(
          of: card,
          matching: find.byWidgetPredicate((w) =>
              w is SvgPicture &&
              w.bytesLoader is SvgAssetLoader &&
              (w.bytesLoader as SvgAssetLoader).assetName == asset));
      expect(
          find.descendant(
              of: spending,
              matching: find.byIcon(Icons.currency_bitcoin_rounded)),
          findsOneWidget,
          reason: why);
      expect(mark(spending, 'lib/assets/hyperliquid-logo.svg'), findsOneWidget,
          reason: why);
      expect(mark(spending, 'lib/assets/polymarket-logo.svg'), findsOneWidget,
          reason: why);
      expect(
          find.descendant(
              of: savings,
              matching: find.byIcon(Icons.currency_bitcoin_rounded)),
          findsNothing,
          reason: why);
      expect(mark(savings, 'lib/assets/hyperliquid-logo.svg'), findsNothing,
          reason: why);
      // Add account wears the cards' tile with the +.
      expect(
          find.descendant(of: add, matching: find.byType(KuteActionCardIcon)),
          findsOneWidget,
          reason: why);
      expect(find.descendant(of: add, matching: find.byIcon(Icons.add_rounded)),
          findsOneWidget,
          reason: why);
      expect(tester.takeException(), isNull, reason: why);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      OpenOnce.reset();
    }
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: Settings across the '
      'top, Referrals and Support side by side under it, every title and '
      'line on one line, nothing cut or overflowing', (tester) async {
    await tester.runAsync(_loadInter);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester, size: const Size(375, 812), locale: locale);
      await _openHub(tester);
      expect(tester.takeException(), isNull, reason: why);
      final settings = tester.getRect(_hubCard('settings'));
      final referral = tester.getRect(_hubCard('referral'));
      final support = tester.getRect(_hubCard('support'));
      expect(settings.bottom, lessThan(referral.top), reason: why);
      expect(referral.top, moreOrLessEquals(support.top), reason: why);
      expect(referral.right, lessThan(support.left), reason: why);
      for (final (card, texts) in [
        ('settings', [l10n.settings, l10n.hubSettingsSubtitle]),
        ('referral', [l10n.hubReferrals, l10n.hubReferralsSubtitle]),
        ('support', [l10n.support, l10n.hubSupportSubtitle]),
      ]) {
        for (final text in texts) {
          expect(_lines(tester, _hubCard(card), text), 1,
              reason: '$why: "$text" takes more than one line');
        }
        final box = tester.getRect(_hubCard(card));
        final shown = find.descendant(
            of: _hubCard(card), matching: find.byType(RichText));
        for (var i = 0; i < shown.evaluate().length; i++) {
          final r = tester.getRect(shown.at(i));
          expect(r.right, lessThanOrEqualTo(box.right + 0.5), reason: why);
          expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.5), reason: why);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      OpenOnce.reset();
    }
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
