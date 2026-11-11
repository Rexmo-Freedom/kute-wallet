// The Referral program, remade (founder, 7 November 2026: "this screen
// must be remade in a much much better way"; affiliate_screen.dart): the
// ladder read from the backend's rules, the hero and the steps from the
// backend's figures, the copy, Share invite as the bar, the QR behind a
// square in a sheet, the money exact to the cent, and the loading, error,
// coming-soon and no-code states. The policy gate has its own file
// (affiliate_screen_gate_test.dart).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardEdges;
import 'package:kute/screens/share/cards/share_card_data.dart'
    show InviteCardData;
import 'package:kute/screens/share/cards/share_card_preview.dart'
    show ShareCardShare;
import 'package:kute/screens/settings/affiliate_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _link = 'https://kute.onelink.me/aBcD';

/// The program's rules as the backend publishes them (affiliate_me.go).
const Map<String, Object> _rules = {
  'base_rate_pct': 5.0,
  'max_rate_pct': 25.0,
  'tiers': [
    {'activated_referees': 100, 'rate_pct': 20.0},
    {'activated_referees': 50, 'rate_pct': 10.0},
  ],
};

Map<String, Object> _me({
  String code = 'EKVGUY',
  double rate = 5,
  int friends = 0,
  double accrued = 0,
  double paid = 0,
  Object? rules = _rules,
  int discount = 20,
  List<Object> payments = const [],
  bool referred = false,
}) =>
    {
      'affiliate_code': code,
      'commission_rate_pct': rate,
      'referees_bound': friends,
      'referees_activated': friends,
      'accrued_usd': accrued,
      'paid_usd': paid,
      'is_referred': referred,
      'payments': payments,
      'referee_discount_pct': discount,
      if (rules != null) 'rules': rules,
    };

http.Client _backend(Map<String, Object>? me,
        {Completer<void>? gate,
        List<Object> referees = const [],
        int setReferrerStatus = 200}) =>
    MockClient((request) async {
      if (gate != null) await gate.future;
      switch (request.url.path) {
        case '/api/v1/affiliate/set-referrer-by-code':
          return http.Response('{}', setReferrerStatus);
        case '/api/v1/affiliate/me':
          return me == null
              ? http.Response('down', 500)
              : http.Response(jsonEncode(me), 200);
        case '/api/v1/affiliate/me/history':
          return http.Response(jsonEncode({'history': <Object>[]}), 200);
        case '/api/v1/affiliate/me/referees':
          return http.Response(jsonEncode({'referees': referees}), 200);
        default:
          return http.Response('not found', 404);
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<(String, Map<String, Object>?)> events;
  late List<String> copied;
  late List<MethodCall> shared;
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  group('ReferralProgress', () {
    test('reads the ladder from the rules, the tiers in friends order', () {
      final p = ReferralProgress.fromMe(_me(friends: 12));
      expect(p.ladder, const [
        ReferralTier(0, 5),
        ReferralTier(50, 10),
        ReferralTier(100, 20),
      ]);
      expect(p.friends, 12);
      expect(p.currentRate, 5);
      expect(p.next, const ReferralTier(50, 10));
      expect(p.remaining, 38);
      expect(p.top, isFalse);
      expect(p.fill(0), closeTo(12 / 50, 1e-9));
      expect(p.fill(1), 0);
      expect([for (var i = 0; i < 3; i++) p.reached(i)], [true, false, false]);
    });

    test('between the tiers: the next rung is the top one', () {
      final p = ReferralProgress.fromMe(_me(rate: 10, friends: 62));
      expect(p.next, const ReferralTier(100, 20));
      expect(p.remaining, 38);
      expect(p.fill(0), 1);
      expect(p.fill(1), closeTo(12 / 50, 1e-9));
      expect([for (var i = 0; i < 3; i++) p.reached(i)], [true, true, false]);
    });

    test('at the top: nothing next, every bar full', () {
      final p = ReferralProgress.fromMe(_me(rate: 20, friends: 134));
      expect(p.next, isNull);
      expect(p.remaining, isNull);
      expect(p.top, isTrue);
      expect(p.fill(0), 1);
      expect(p.fill(1), 1);
    });

    test('a rate set by hand counts: a rung it already beats is skipped', () {
      // An admin rate of 15% with 30 friends: 10% at 50 pays less.
      final p = ReferralProgress.fromMe(_me(rate: 15, friends: 30));
      expect(p.next, const ReferralTier(100, 20));
      expect(p.remaining, 70);
      expect(p.fill(0), 1);
      expect(p.reached(1), isTrue);
      // Above every rung: the top, whatever the friends.
      expect(ReferralProgress.fromMe(_me(rate: 25, friends: 3)).top, isTrue);
    });

    test('no rules: no ladder, no next step, the rate alone', () {
      final p = ReferralProgress.fromMe(_me(rate: 10, rules: null));
      expect(p.ladder, isEmpty);
      expect(p.currentRate, 10);
      expect(p.next, isNull);
      expect(p.top, isFalse);
      expect(ReferralProgress.fromMe(null).currentRate, isNull);
    });
  });

  group('screen', () {
    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      FlutterSecureStorage.setMockInitialValues({});
      dotenv.loadFromString(
          envString: 'BACKEND=https://backend.test\n'
              'APPSFLYER_ONELINK_TEMPLATE=kute.onelink.me/aBcD');
      AffiliateService.debugSessionToken = 'test-session';
      TrackingService.setDisabled(true);
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });

    tearDown(() {
      TrackingService.debugTrackObserver = null;
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    Future<void> frames(WidgetTester tester, [int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    RuntimeCapabilitiesService? policy;

    /// Unmounts the page and the bar, lets their timers run out and stops
    /// the policy's refresh timer.
    Future<void> away(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      policy?.dispose();
      policy = null;
    }

    Future<void> pump(WidgetTester tester,
        {required Map<String, Object>? me,
        bool allowed = true,
        Completer<void>? gate,
        Size size = const Size(390, 844),
        double textScale = 1,
        Locale? locale,
        String? walletId,
        List<Object> referees = const [],
        int setReferrerStatus = 200,
        Future<void> Function()? then}) async {
      final p = policy = runtimePolicyFixture(
          also: {'affiliate.program'},
          blocked: {if (!allowed) 'affiliate.program'});
      RuntimeCapabilitiesService.debugInstance = p;
      await tester.runAsync(p.refresh);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      copied = [];
      shared = [];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shared.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            settingsProvider.overrideWith((_) => SettingsModel(Settings(
                  currency: 'USD',
                  language: 'en',
                  btcFormat: 'sats',
                  backup: false,
                  biometricsEnabled: false,
                  bitcoinElectrumNode: '',
                  nodeType: 'Blockstream',
                  reviewDone: true,
                  wallets: [
                    if (walletId != null)
                      WalletConfig(id: walletId, name: 'Spending'),
                  ],
                ))),
          ],
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              locale: locale,
              theme: ThemeData(
                  splashFactory: NoSplash.splashFactory,
                  fontFamily: 'Inter',
                  extensions: [AppColorsExtension.light()]),
              builder: withKuteShellBar,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const AffiliateScreen(),
            ),
          ),
        ));
        await frames(tester);
        await then?.call();
      },
          () => _backend(me,
              gate: gate,
              referees: referees,
              setReferrerStatus: setReferrerStatus));
    }

    Finder scrollable() => find
        .descendant(
            of: find.byKey(const ValueKey('referral-dashboard')),
            matching: find.byType(Scrollable))
        .first;

    testWidgets(
        'zero friends: the hero, the code, the progress and the steps from '
        'the backend figures; Share invite is the bar', (tester) async {
      await pump(tester, me: _me());
      expect(find.text("Earn 5% of your friends' fees"), findsOneWidget);
      expect(find.text('They get 20% off Kute fees'), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-code')), findsOneWidget);
      expect(find.text('EKVGUY'), findsOneWidget);
      // No QR on the page: a square opens it.
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byKey(const ValueKey('referral-code-qr')), findsOneWidget);
      // The progress card: friends, the rate, the next rung, the ladder.
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('referral-friends-joined')))
              .data,
          '0');
      expect(find.text('Friends joined'), findsOneWidget);
      expect(find.text('Your rate'), findsOneWidget);
      expect(find.text('Invite 50 more friends to earn 10%'), findsOneWidget);
      for (final label in ['0 friends', '50 friends', '100 friends']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
          find.byKey(const ValueKey('referral-ladder-rate-1')), findsOneWidget);
      // The money, exact to the cent.
      expect(find.text('Pending payout'), findsOneWidget);
      expect(find.text('Paid to date'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNWidgets(2));
      // How it works: three steps, the terms sentences kept.
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('referral-step-earn')), 200,
          scrollable: scrollable());
      expect(find.text('Share your link'), findsOneWidget);
      expect(find.text('They join and trade'), findsOneWidget);
      expect(find.text("Friends get 20% off Kute fees while they're with you."),
          findsOneWidget);
      expect(find.text('You earn 5% of their fees'), findsOneWidget);
      expect(
          find.text('10% at 50 friends, 20% at 100 friends'), findsOneWidget);
      // The old pieces are gone.
      expect(find.text('Users with your code'), findsNothing);
      expect(find.text('Copy link'), findsNothing);
      // Share invite is the bar's primary.
      final bar = kuteBarPrimaryContext(tester);
      expect(bar.label, 'Share invite');
      expect(kuteBarPrimaryEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('mid-tier: the next rung and how far it is', (tester) async {
      await pump(tester,
          me: _me(rate: 10, friends: 62, accrued: 12.4, paid: 1210.5));
      expect(find.text("Earn 10% of your friends' fees"), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('referral-friends-joined')))
              .data,
          '62');
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('referral-your-rate')))
              .data,
          '10%');
      expect(find.text('Invite 38 more friends to earn 20%'), findsOneWidget);
      expect(find.text(r'$12.40'), findsOneWidget);
      expect(find.text(r'$1,210.50'), findsOneWidget);
      // The program's base rate in How it works, not the person's.
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('referral-step-earn')), 200,
          scrollable: scrollable());
      expect(find.text('You earn 5% of their fees'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('top tier: says so, no invite line', (tester) async {
      await pump(tester, me: _me(rate: 20, friends: 134));
      expect(find.text("You're on the top rate"), findsOneWidget);
      expect(find.textContaining('more friends to earn'), findsNothing);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('no rules and no discount: nothing made up', (tester) async {
      await pump(tester, me: _me(rate: 10, rules: null, discount: 0));
      expect(find.text("Earn 10% of your friends' fees"), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-hero-line')), findsNothing);
      expect(find.byKey(const ValueKey('referral-ladder')), findsNothing);
      expect(find.byKey(const ValueKey('referral-next-step')), findsNothing);
      expect(find.textContaining('off Kute fees'), findsNothing);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets(
        'the code card copies the CODE (never the link), the square too, '
        'with a source', (tester) async {
      await pump(tester, me: _me());
      await tester.tap(find.byKey(const ValueKey('referral-code-card')));
      await tester.pump();
      expect(copied.single, 'EKVGUY');
      expect(find.text('Code copied'), findsOneWidget);
      expect(find.text('Link copied'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      // The square beside the QR: the code too.
      await tester.tap(find.byKey(const ValueKey('referral-code-copy')));
      await tester.pump();
      expect(copied, ['EKVGUY', 'EKVGUY']);
      for (final text in copied) {
        expect(text, isNot(contains('://')));
        expect(text, isNot(contains('onelink')));
      }
      final copies = events
          .where((e) => e.$1 == 'affiliate_code_copied')
          .map((e) => e.$2)
          .toList();
      expect(copies, [
        {'surface': 'earn', 'source': 'code_card'},
        {'surface': 'earn', 'source': 'copy_button'},
      ]);
      // Never the code or the link in analytics.
      for (final e in events) {
        expect(jsonEncode(e.$2 ?? const {}), isNot(contains('EKVGUY')));
        expect(jsonEncode(e.$2 ?? const {}), isNot(contains('onelink')));
      }
      await tester.pump(const Duration(seconds: 2));
      await away(tester);
    });

    testWidgets(
        'Share invite still sends the invite LINK after a copy of the code',
        (tester) async {
      await pump(tester, me: _me());
      await tester.tap(find.byKey(const ValueKey('referral-code-copy')));
      await tester.pump();
      expect(copied.single, 'EKVGUY');
      await tester.pump(const Duration(seconds: 2));
      kuteBarPrimaryContext(tester).onPrimary!();
      await frames(tester, 6);
      expect(find.byKey(const ValueKey('share-card-invite')), findsOneWidget);
      final sent = <String>[];
      ShareCardShare.debugSharer = (image, text) async {
        sent.add(text);
        return 'success';
      };
      addTearDown(() => ShareCardShare.debugSharer = null);
      kuteBarPrimaryContext(tester).onPrimary!();
      for (var i = 0; i < 50 && sent.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(sent, hasLength(1));
      expect(sent.single, contains(_link));
      await away(tester);
    });

    group('Got a friend\'s code?', () {
      String walletIdAged(Duration age) =>
          '${DateTime.now().subtract(age).millisecondsSinceEpoch}-123';

      Future<void> toBottom(WidgetTester tester) => tester.scrollUntilVisible(
          find.byKey(const ValueKey('referral-how-it-works')), 300,
          scrollable: scrollable());

      testWidgets('a fresh account with no referrer: shown', (tester) async {
        await pump(tester,
            me: _me(), walletId: walletIdAged(const Duration(days: 2)));
        await toBottom(tester);
        await tester.drag(scrollable(), const Offset(0, -600));
        await tester.pump();
        expect(
            find.byKey(const ValueKey('referral-late-entry')), findsOneWidget);
        expect(find.text("Got a friend's code?"), findsOneWidget);
        expect(
            events.firstWhere((e) => e.$1 == 'affiliate_dashboard_loaded').$2,
            containsPair('late_entry_shown', true));
        await away(tester);
      });

      testWidgets('a referrer already set: hidden', (tester) async {
        await pump(tester,
            me: _me(referred: true),
            walletId: walletIdAged(const Duration(days: 1)));
        await toBottom(tester);
        await tester.drag(scrollable(), const Offset(0, -600));
        await tester.pump();
        expect(find.byKey(const ValueKey('referral-late-entry')), findsNothing);
        expect(find.text("Got a friend's code?"), findsNothing);
        expect(
            events.firstWhere((e) => e.$1 == 'affiliate_dashboard_loaded').$2,
            containsPair('late_entry_shown', false));
        await away(tester);
      });

      testWidgets('past the 7-day window: hidden', (tester) async {
        await pump(tester,
            me: _me(), walletId: walletIdAged(const Duration(days: 30)));
        await toBottom(tester);
        await tester.drag(scrollable(), const Offset(0, -600));
        await tester.pump();
        expect(find.byKey(const ValueKey('referral-late-entry')), findsNothing);
        expect(
            events.firstWhere((e) => e.$1 == 'affiliate_dashboard_loaded').$2,
            containsPair('late_entry_shown', false));
        await away(tester);
      });

      testWidgets('the backend answers "past the window": the card goes',
          (tester) async {
        // A restored wallet reads young locally; the backend knows better.
        await pump(tester,
            me: _me(code: 'RSTRD2'),
            walletId: walletIdAged(const Duration(hours: 1)),
            setReferrerStatus: 410, then: () async {
          await toBottom(tester);
          await tester.drag(scrollable(), const Offset(0, -600));
          await tester.pump();
          await tester.enterText(find.byType(TextField), 'ABCDEF');
          await tester.tap(find.byKey(const ValueKey('referral-apply-code')));
          await frames(tester);
        });
        expect(find.byKey(const ValueKey('referral-late-entry')), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await away(tester);
      });
    });

    testWidgets(
        'Your friends: one friend joined, the card opens onto that friend '
        'and what they earned you', (tester) async {
      await pump(tester,
          me: _me(friends: 1),
          referees: [
            {
              'activated': true,
              'contribution_usd': 12.0,
              'venue_revenue_usd': 0,
            },
          ]);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('referral-friends')), 200,
          scrollable: scrollable());
      expect(find.text('Your friends'), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-friend-0')), findsNothing);
      await tester.tap(find.text('Your friends'));
      await tester.pump();
      expect(find.byKey(const ValueKey('referral-friend-0')), findsOneWidget);
      expect(find.text('User #1'), findsOneWidget);
      // 5% of their $12.00 in fees.
      expect(find.text(r'$0.60'), findsOneWidget);
      expect(
          events.firstWhere((e) => e.$1 == 'affiliate_referees_viewed').$2,
          isNot(contains('EKVGUY')));
      await away(tester);
    });

    testWidgets('Your friends: a friend who paid no fee yet reads \$0.00',
        (tester) async {
      await pump(tester, me: _me(friends: 1), referees: [
        {'activated': true, 'contribution_usd': 0, 'venue_revenue_usd': 0},
      ]);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('referral-friends')), 200,
          scrollable: scrollable());
      await tester.tap(find.text('Your friends'));
      await tester.pump();
      final row = find.byKey(const ValueKey('referral-friend-0'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(r'$0.00')),
          findsOneWidget);
      await away(tester);
    });

    test('referrerEntryOpen: the backend rule, read from what the app knows',
        () {
      final now = DateTime(2026, 11, 11, 12);
      expect(referrerEntryOpen(isReferred: false, now: now), isTrue);
      expect(referrerEntryOpen(isReferred: true, now: now), isFalse);
      expect(referrerEntryOpen(isReferred: false, closed: true, now: now),
          isFalse);
      expect(
          referrerEntryOpen(
              isReferred: false,
              walletCreatedAt: now.subtract(const Duration(days: 7)),
              now: now),
          isTrue);
      expect(
          referrerEntryOpen(
              isReferred: false,
              walletCreatedAt:
                  now.subtract(const Duration(days: 7, minutes: 1)),
              now: now),
          isFalse);
      expect(walletCreatedAtFromId('1762862400000-42'),
          DateTime.fromMillisecondsSinceEpoch(1762862400000));
      expect(walletCreatedAtFromId('spending'), isNull);
      expect(walletCreatedAtFromId(null), isNull);
    });

    testWidgets('Share invite opens the invite card with Sal; its Share is the bar',
        (tester) async {
      await pump(tester, me: _me());
      kuteBarPrimaryContext(tester).onPrimary!();
      await frames(tester, 6);
      expect(find.byKey(const ValueKey('share-card-invite')), findsOneWidget);
      // Still the card, never the OS sheet straight away.
      expect(shared, isEmpty);
      expect(find.text('20% off'), findsOneWidget);
      expect(find.text('Kute fees'), findsOneWidget);
      expect(find.text('EKVGUY'), findsWidgets);
      expect(events.firstWhere((e) => e.$1 == 'affiliate_share_opened').$2,
          {'method': 'card', 'trigger': 'bar'});
      expect(kuteBarPrimaryContext(tester).label, 'Share');
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    test('the invite card has no line promising a profit or saying "bet"', () {
      // The card's words, in every locale's English source.
      final en = lookupAppLocalizations(const Locale('en'));
      final lines = shareCardEdges(
          en, const InviteCardData(discount: '20%', referralCode: 'EKVGUY'));
      expect(lines, hasLength(8));
      for (final line in lines) {
        expect(line, isNot(matches(RegExp(r'\b(bet|profit)\b', caseSensitive: false))));
      }
      // Without a discount no line talks about one.
      final plain = shareCardEdges(en, const InviteCardData());
      expect(plain, hasLength(5));
      expect(plain.join().toLowerCase(), isNot(contains('discount')));
    });

    testWidgets('the QR square opens the QR in a sheet; its Share is the bar',
        (tester) async {
      await pump(tester, me: _me());
      await tester.tap(find.byKey(const ValueKey('referral-code-qr')));
      await frames(tester, 6);
      expect(find.byKey(const ValueKey('referral-qr-sheet')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('referral-qr-code')))
              .data,
          'EKVGUY');
      expect(events.firstWhere((e) => e.$1 == 'affiliate_share_opened').$2,
          {'method': 'qr', 'trigger': 'code_card'});
      final bar = kuteBarPrimaryContext(tester);
      expect(bar.label, 'Share');
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('no code yet: dashes, no squares, the default bar',
        (tester) async {
      await pump(tester, me: _me(code: ''));
      expect(find.text('------'), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-code-qr')), findsNothing);
      expect(find.byKey(const ValueKey('referral-code-copy')), findsNothing);
      expect(find.text('Share invite'), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is KuteBarContextScope && w.active && w.barContext.isPrimary),
          findsNothing);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('loading draws the page shapes, then the dashboard',
        (tester) async {
      final gate = Completer<void>();
      await pump(tester, me: _me(), gate: gate, then: () async {
        expect(find.byKey(const ValueKey('referral-loading')), findsOneWidget);
        expect(find.text('Share invite'), findsNothing);
        gate.complete();
        await frames(tester);
      });
      expect(find.byKey(const ValueKey('referral-dashboard')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('error: the message, Try again is the bar and retries',
        (tester) async {
      await pump(tester, me: null);
      expect(find.byKey(const ValueKey('referral-error')), findsOneWidget);
      expect(find.text("Couldn't load your Earn data"), findsOneWidget);
      expect(kuteBarPrimaryContext(tester).label, 'Try again');
      kuteBarPrimaryContext(tester).onPrimary!();
      await frames(tester);
      expect(events.map((e) => e.$1), contains('affiliate_earn_retry_tapped'));
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('the program not live and no dashboard: Coming soon',
        (tester) async {
      await pump(tester, me: null, allowed: false);
      expect(
          find.byKey(const ValueKey('referral-coming-soon')), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
          '${locale.languageCode} at 320 with large text: nothing overflows',
          (tester) async {
        await pump(tester,
            me: _me(rate: 10, friends: 62, accrued: 12.4, paid: 1210.5),
            size: const Size(320, 2600),
            textScale: 1.3,
            locale: locale);
        expect(find.byKey(const ValueKey('referral-progress')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await away(tester);
      });
    }
  });
}
