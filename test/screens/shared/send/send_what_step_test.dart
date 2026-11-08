// The What step's cards in every language at 375 pt (founder, 7 November
// 2026, of the two full-width rows they were: "here should be the
// squares"): the money and the gift are two equal squares side by side,
// whatever the language; "A prediction or investment" and its line wrap to
// the lines they need, never cut and never a word broken across lines; the
// gift wears Sal in the money mark's box, as big as the mark, no box of
// his own. Inter, the app's font, so the measures are a phone's.
//
// Then THE GIFT IS ALWAYS THERE (founder, 8 November 2026: "we need to have
// it as an option always"), on the Dollars Send, the one Send with a What
// (the Bitcoin Send just sends bitcoin: send_contacts_step_test.dart and
// money_doors_gating_test.dart hold that under the same policies): with
// nothing held and no venue cash the gift shows and its tap opens the search.
// A refused trade never stops it here (founder, 8 November 2026: "only on the
// last screen, the bet slip, show this error, not in this part"); the slips'
// refusal is in
// bet_slip_check_connection_test.dart and order_slip_check_connection_test
// .dart. Only nothing to list stands in its way: both venues' browse shut
// for a region (or no policy read yet) keeps the card and its tap says why,
// asking again first; a refusal of another kind on both leaves the money
// card alone, full width and compact.

import 'dart:collection' show SetBase;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show CapabilityUnavailableSheet;
import 'package:kute/screens/search/components/search_rows.dart'
    show SearchChanceGauge;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard, KuteActionCardGrid, KuteActionCardIcon;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePillTabs;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendSalShareGlyph;
import 'package:kute/screens/shared/send/send_what_step.dart';
import 'package:kute/services/investment_provider_availability.dart'
    show InvestmentProviderAvailability;
import 'package:kute/services/region_freshness.dart' show RegionFreshness;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../helpers/kute_bar_test_support.dart';
import '../../../helpers/runtime_policy_fixture.dart';

Future<void> _fonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
  await inter.load();
}

Future<void> _pump(WidgetTester tester,
    {required Locale locale, bool dark = false}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final base = dark ? buildDarkTheme() : buildLightTheme();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      usdBalanceProvider.overrideWithValue(12.34),
      usdBalanceUnknownProvider.overrideWithValue(false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'Inter')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SendWhatSheet(name: 'Anna Haro'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// What one person picked on the Send did.
class _Flow {
  int gifts = 0;
}

/// The Dollars Send over an empty account: nothing in Dollars, no venue cash
/// and no position (the What step reads none of them for the gift); a tap on
/// `open` picks a person, as the Send does ([sendToPerson]).
Future<_Flow> _pumpPerson(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final flow = _Flow();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      usdBalanceProvider.overrideWithValue(0),
      usdBalanceUnknownProvider.overrideWithValue(false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        builder: withKuteShellBar,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => sendToPerson(
                  context,
                  phone: '+351 999 888 777',
                  openLink: () async => false,
                  openGift: () async {
                    flow.gifts++;
                    return false;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(SendWhatSheet), findsOneWidget);
  return flow;
}

Future<void> _policy(
  WidgetTester tester, {
  Set<String> Function()? blocked,
  Map<String, String> reasons = const {},
  Map<String, Map<String, Object?>> decorations = const {},
}) async {
  final closed = blocked ?? () => const <String>{};
  // The fixture reads its blocked set at each fetch.
  final policy = runtimePolicyFixture(
      blocked: _LiveSet(closed),
      reasons: reasons,
      decorations: decorations,
      also: const {'polymarket.browse', 'hyperliquid.browse'});
  RuntimeCapabilitiesService.debugInstance = policy;
  await tester.runAsync(policy.refresh);
}

/// A set read afresh each time it is asked.
class _LiveSet extends SetBase<String> {
  _LiveSet(this.read);
  final Set<String> Function() read;
  @override
  bool add(String value) => throw UnsupportedError('read only');
  @override
  bool contains(Object? element) => read().contains(element);
  @override
  Iterator<String> get iterator => read().iterator;
  @override
  int get length => read().length;
  @override
  String? lookup(Object? element) => read().lookup(element);
  @override
  bool remove(Object? value) => throw UnsupportedError('read only');
  @override
  Set<String> toSet() => read().toSet();
}

const _regions = {'label': 'the European Union, the UK and Switzerland'};
const _trading = {'polymarket.trade', 'hyperliquid.trade'};
const _browse = {'polymarket.browse', 'hyperliquid.browse'};
const _regionReasons = {
  'polymarket.trade': 'country_blocked',
  'hyperliquid.trade': 'country_blocked',
  'polymarket.browse': 'country_blocked',
  'hyperliquid.browse': 'country_blocked',
};
const _regionNames = {
  'polymarket.trade': {'regions': _regions},
  'hyperliquid.trade': {'regions': _regions},
  'polymarket.browse': {'regions': _regions},
  'hyperliquid.browse': {'regions': _regions},
};

/// Every word of every paragraph under [card] sits whole on its line, and
/// no paragraph is cut; the number of lines the title takes.
int _checkWhole(WidgetTester tester, Finder card, String title, String tag) {
  var titleLines = 0;
  for (final element in find
      .descendant(of: card, matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$tag: "$text" cut');
    final style = (paragraph.text as TextSpan).style;
    // Japanese wraps between any two characters: no word to keep whole.
    final cjk = RegExp(r'[\u3000-\u9fff\uff00-\uffef]').hasMatch(text);
    for (final word in cjk ? const <String>[] : text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final w = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      expect(w.width, lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: '$tag: "$word" of "$text" broken across lines');
      w.dispose();
    }
    if (text == title) {
      titleLines = paragraph
          .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length))
          .map((b) => b.top.round())
          .toSet()
          .length;
    }
  }
  return titleLines;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _fonts();
  });

  setUp(() {
    SalSpriteCache.debugSetManifest(null);
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() {
    SalSpriteCache.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
  });

  testWidgets(
      'every language at 375 pt: two equal squares side by side, nothing '
      'cut, no word broken; the gift wears Sal in the mark\'s box',
      (tester) async {
    final lines = <String, int>{};
    for (final locale in AppLocalizations.supportedLocales) {
      final tag = locale.languageCode;
      await _pump(tester, locale: locale);
      final l10n = lookupAppLocalizations(locale);
      final money = find.byKey(kSendWhatMoneyKey);
      final gift = find.byKey(kSendWhatGiftKey);
      expect(tester.getSize(money), tester.getSize(gift), reason: tag);
      expect(tester.getTopLeft(gift).dy,
          moreOrLessEquals(tester.getTopLeft(money).dy),
          reason: tag);
      expect(tester.getTopLeft(gift).dx,
          greaterThan(tester.getTopRight(money).dx),
          reason: tag);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing,
          reason: tag);
      // Sal's face in the money mark's own box.
      final sal = find.descendant(
          of: gift, matching: find.byType(SendSalShareGlyph));
      expect(tester.widget<SendSalShareGlyph>(sal).size, kSendWhatSalSize);
      expect(
          tester.getSize(
              find.descendant(of: gift, matching: find.byType(SendWhatSal))),
          tester.getSize(
              find.descendant(of: money, matching: find.byType(SvgPicture))));
      expect(find.byType(KuteActionCardIcon), findsNothing);
      _checkWhole(tester, money, l10n.portfolioBalanceDollars, tag);
      lines[tag] = _checkWhole(tester, gift, l10n.sendWhatGift, tag);
      expect(tester.takeException(), isNull, reason: tag);
    }
    // The gift's title takes one or two lines, never more.
    for (final entry in lines.entries) {
      expect(entry.value, inInclusiveRange(1, 2), reason: entry.key);
    }
    // ignore: avoid_print
    print('What gift title lines at 375 pt: $lines');
  });

  group('the Dollars Send', () {
    testWidgets(
        'the sheet: this Send\'s Dollars and the gift, the app\'s two cards in '
        'the grid, the gift its title and line, Sal and no gift glyph, no '
        'gauge; the bar is Back, clear of the cards, closing it with no answer',
        (tester) async {
      await _policy(tester);
      final events = <String>[];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      await _pumpPerson(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));
      final sheet = find.byType(SendWhatSheet);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      expect(inSheet(find.byType(KuteActionCardGrid)), findsOneWidget);
      expect(inSheet(find.byType(KuteActionCard)), findsNWidgets(2));
      expect(inSheet(find.byType(KutePillTabs)), findsNothing);
      expect(inSheet(find.text(l10n.bitcoin)), findsNothing);
      expect(inSheet(find.text('From')), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(kSendWhatMoneyKey),
              matching: find.text(l10n.portfolioBalanceDollars)),
          findsOneWidget);
      final gift = find.byKey(kSendWhatGiftKey);
      expect(find.descendant(of: gift, matching: find.text(l10n.sendWhatGift)),
          findsOneWidget);
      expect(
          find.descendant(
              of: gift, matching: find.text(l10n.sendToAFriendSub)),
          findsOneWidget);
      expect(
          find.descendant(
              of: gift, matching: find.byIcon(Icons.card_giftcard_rounded)),
          findsNothing);
      expect(inSheet(find.byType(SearchChanceGauge)), findsNothing);
      expect(inSheet(find.byIcon(Icons.chevron_right_rounded)), findsNothing);

      expect(kuteBarPrimaryWithText(l10n.back), findsOneWidget);
      expect(kuteBarPrimaryEnabled(tester), isTrue);
      expect(tester.getRect(gift).bottom,
          lessThanOrEqualTo(tester.getRect(kuteBarPrimary).top));
      await tester.tap(kuteBarPrimary);
      await tester.pumpAndSettle();
      expect(find.byType(SendWhatSheet), findsNothing);
      expect(events, isNot(contains('send_what_picked')));
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'nothing held and no venue cash: two squares; the gift goes on to '
        'the search, send_what_picked counted once with no person in it',
        (tester) async {
      await _policy(tester);
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      final flow = await _pumpPerson(tester);
      final money = find.byKey(kSendWhatMoneyKey);
      final gift = find.byKey(kSendWhatGiftKey);
      expect(tester.getSize(money), tester.getSize(gift));
      await tester.tap(gift);
      await tester.pumpAndSettle();
      expect(flow.gifts, 1);
      expect(find.byType(SendWhatSheet), findsNothing);
      final picked = events.where((e) => e.$1 == 'send_what_picked').toList();
      expect(picked, hasLength(1));
      expect(picked.single.$2, {'what': 'gift', 'home': 'dollars'});
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'both venues\' trade refused, for a region or by a switch: no '
        'Unavailable sheet, the tap counts its answer and opens the search',
        (tester) async {
      for (final reasons in [_regionReasons, const <String, String>{}]) {
        await _policy(tester,
            blocked: () => _trading,
            reasons: reasons,
            decorations: _regionNames);
        final picked = <Map<String, Object?>?>[];
        TrackingService.debugTrackObserver = (e, p) {
          if (e == 'send_what_picked') picked.add(p);
        };
        final flow = await _pumpPerson(tester);
        await tester.tap(find.byKey(kSendWhatGiftKey));
        await tester.pumpAndSettle();
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);
        expect(find.byType(SendWhatSheet), findsNothing);
        expect(flow.gifts, 1);
        expect(picked.single, {'what': 'gift', 'home': 'dollars'});
        RuntimeCapabilitiesService.debugInstance?.dispose();
      }
    });

    testWidgets(
        'neither venue\'s browse open for a region: the card stays and its tap says '
        'why, the named regions and Check connection, opening nothing and '
        'counting no answer; the What step is still under it',
        (tester) async {
      await _policy(tester,
          blocked: () => _browse,
          reasons: _regionReasons,
          decorations: _regionNames);
      final events = <String>[];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      final flow = await _pumpPerson(tester);
      await tester.tap(find.byKey(kSendWhatGiftKey));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      expect(
          find.text(
              'Not available in the European Union, the UK and Switzerland'),
          findsOneWidget);
      expect(kuteBarPrimaryWithText('Check connection'), findsOneWidget);
      expect(flow.gifts, 0);
      expect(events, isNot(contains('send_what_picked')));
      expect(find.byType(SendWhatSheet), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(find.byType(SendWhatSheet), findsOneWidget);
      expect(find.byKey(kSendWhatGiftKey), findsOneWidget);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'a stale region refusal never stops it: the tap asks again, and a '
        'venue open now goes straight on', (tester) async {
      var closed = _browse;
      await _policy(tester,
          blocked: () => closed,
          reasons: _regionReasons,
          decorations: _regionNames);
      final flow = await _pumpPerson(tester);
      closed = const {};
      await tester.runAsync(() async {
        await tester.tap(find.byKey(kSendWhatGiftKey));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(flow.gifts, 1);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'Check connection finding a venue open goes on into the search',
        (tester) async {
      final venues = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                '{"acceptedTerms":true,"userAllowed":true,"restrictions":"n"}',
                200)
            : http.Response('{"blocked":false}', 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) {},
      );
      RegionFreshness.debugVenues = venues;
      addTearDown(() {
        RegionFreshness.debugVenues = null;
        venues.dispose();
      });
      var closed = _browse;
      await _policy(tester,
          blocked: () => closed,
          reasons: _regionReasons,
          decorations: _regionNames);
      final flow = await _pumpPerson(tester);
      await tester.tap(find.byKey(kSendWhatGiftKey));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      expect(flow.gifts, 0);
      // The VPN changed.
      closed = const {};
      await tester.tap(kuteBarPrimaryWithText('Check connection'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(find.byType(SendWhatSheet), findsNothing);
      expect(flow.gifts, 1);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'no policy read yet: browse fails open, as the plain search reads '
        'it, so the gift opens the search (the slip asks its own gate)',
        (tester) async {
      final policy = RuntimeCapabilitiesService.forTesting(
        client: MockClient((_) async => http.Response('', 503)),
        baseUrl: () => 'https://policy.test',
        sessionToken: () => AffiliateService.sessionToken,
        appVersion: () async => '2.2.0',
      );
      RuntimeCapabilitiesService.debugInstance = policy;
      final flow = await _pumpPerson(tester);
      await tester.tap(find.byKey(kSendWhatGiftKey));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(flow.gifts, 1);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'one venue\'s browse open is enough, the other refused for a region: the '
        'gift goes on', (tester) async {
      await _policy(tester,
          blocked: () => const {'polymarket.browse'},
          reasons: _regionReasons,
          decorations: _regionNames);
      final flow = await _pumpPerson(tester);
      await tester.tap(find.byKey(kSendWhatGiftKey));
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(flow.gifts, 1);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'the switch off on both venues: the money card alone, the grid\'s '
        'lone card, full width and compact with its chevron',
        (tester) async {
      await _policy(tester, blocked: () => _browse);
      await _pumpPerson(tester);
      final money = find.byKey(kSendWhatMoneyKey);
      expect(find.byKey(kSendWhatGiftKey), findsNothing);
      expect(tester.getSize(money).width,
          tester.getSize(find.byKey(const ValueKey('send-what-cards'))).width);
      expect(
          find.descendant(
              of: money, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });

    testWidgets(
        'the switch off on one venue, the other refused for a region: the '
        'card stays and its tap names that region', (tester) async {
      await _policy(tester,
          blocked: () => _browse,
          reasons: const {'hyperliquid.browse': 'country_blocked'},
          decorations: const {
            'hyperliquid.browse': {'regions': _regions},
          });
      final flow = await _pumpPerson(tester);
      await tester.tap(find.byKey(kSendWhatGiftKey));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Not available in the European Union, the UK and Switzerland'),
          findsOneWidget);
      expect(flow.gifts, 0);
      RuntimeCapabilitiesService.debugInstance?.dispose();
    });
  });
}
