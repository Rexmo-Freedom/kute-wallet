// SHARE MY LEVEL (founder, 8 November 2026: "we should be able to share the
// goals"): a level's card in the share-card family (goal_share.dart,
// GoalCardData). The level, its name, Sal's own still for it, a deadpan line
// and the footer, and NO MONEY anywhere: on the card, in its lines in every
// language, in the message under the image, in the event.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/screens/analytics/components/balance_goals.dart'
    show balanceLevelCardClip, balanceLevelName;
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/screens/share/goal_share.dart';
import 'package:kute/screens/share/receipt_share.dart'
    show appInviteShareText;
import 'package:kute/services/balance_milestones.dart' show kBalanceLevelNames;
import 'package:kute/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../helpers/kute_bar_test_support.dart';
import 'cards/share_card_fixtures.dart';
import 'cards/share_card_test_fonts.dart';
import 'share_test_harness.dart';

/// Money on a card or in a line: a currency, a figure, a percent, "sats".
final RegExp _money = RegExp(r'[$€£¥₿%]|\bsats?\b', caseSensitive: false);

/// Words that never leave the phone on this card, whole words only, in the
/// languages' own forms of "bet", "profit", "rich" and "guaranteed".
final RegExp _banned = RegExp(
    r'(?<![\p{L}])(bet|bets|betting|profit|profits|gain|gains|rich|wealth|'
    r'wealthy|millionaire|guaranteed|guarantee|'
    r'wette|wetten|gewinn|reich|'
    r'aposta|apostar|lucro|rico|'
    r'apuesta|apostar|ganancia|'
    r'pari|parier|riche|'
    r'scommessa|profitto|ricco|'
    r'賭け|利益)(?![\p{L}])',
    caseSensitive: false,
    unicode: true);

Widget _card(ShareCardData data, {Locale locale = const Locale('en'), int seed = 0}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Align(
            alignment: Alignment.topLeft,
            child: ShareCard(data: data, lineSeed: seed)),
      ),
    );

/// Every text the card draws.
List<String> _texts(WidgetTester tester) => [
      for (final e in find.byType(RichText).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ];

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('the card', () {
    test('its fields: the level, the name, the still, the code; nothing else',
        () {
      final d = fakeGoalCard();
      expect(d.kind, 'goal');
      expect(d.level, 3);
      expect(d.name, 'Kute Stack');
      expect(d.still, 'level_card_3');
      expect(d.referralCode, kShareTestCode);
      expect(shareCardPalette(d), ShareCardPalette.bitcoinClaim);
      expect(shareCardTopLine(en, d), 'My level');
      expect(shareCardHeadline(en, d), isNull);
      // The message is the entry point's own text alone.
      expect(shareCardMessage(en, d, 'invite'), 'invite');
    });

    testWidgets('draws the caps, the level, the name, the line, the code',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_card(fakeGoalCard()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final texts = _texts(tester);
      expect(texts, contains('MY LEVEL'));
      expect(texts, contains('Level 3'));
      expect(texts, contains('Kute Stack'));
      expect(texts, contains(shareCardEdge(en, fakeGoalCard(), 0)));
      expect(texts.join(' '), contains(kShareTestCode));
    });

    testWidgets('no money anywhere on it, at any level, in any language',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        for (final level in [1, 3, 8, 12, 15]) {
          final index = (level - 1).clamp(0, kBalanceLevelNames - 1);
          await tester.pumpWidget(_card(
              fakeGoalCard(
                  level: level,
                  name: balanceLevelName(l10n, index),
                  code: null),
              locale: locale));
          await tester.pump();
          for (final t in _texts(tester)) {
            expect(_money.hasMatch(t), isFalse, reason: '$locale: $t');
            // The one figure on it is the level's own number.
            final figures =
                RegExp(r'\d+').allMatches(t).map((m) => m.group(0)).toList();
            expect(figures, anyOf(isEmpty, ['$level']), reason: '$locale: $t');
          }
        }
      }
    });

    testWidgets('Sal is the level\'s own still, with his shadow and his place',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      ShareCardSal.debugReset();
      addTearDown(ShareCardSal.debugReset);
      await tester.runAsync(loadShareCardSal);
      await tester.pumpWidget(_card(fakeGoalCard()));
      await tester.pump();
      // His place is kept while it decodes.
      final still = tester.widget<ShareCardSalStill>(
          find.byKey(const ValueKey('share-card-sal')));
      expect(still.clip, 'level_card_3');
      expect(still.pose, isNull);
      expect(still.shadow, ShareCardPalette.bitcoinClaim.salShadow);
      expect(ShareCardSal.still('level_card_3'), isNull);
      // Decoded once, at the cards' own size, for each of the twelve.
      for (var i = 0; i < kBalanceLevelNames; i++) {
        final clip = balanceLevelCardClip(i);
        expect(clip, 'level_card_${i + 1}');
        expect(await tester.runAsync(() => ShareCardSal.loadStill(clip)), isTrue,
            reason: clip);
        final decoded = ShareCardSal.still(clip)!;
        expect(decoded.image.width, 384, reason: clip);
        expect(decoded.image.height, 384, reason: clip);
        expect(await tester.runAsync(() => ShareCardSal.loadStill(clip)), isTrue);
        expect(identical(ShareCardSal.still(clip), decoded), isTrue);
      }
      expect(balanceLevelCardClip(kBalanceLevelNames + 5), 'level_card_12');
      expect(await tester.runAsync(() => ShareCardSal.loadStill('no_such_clip')),
          isFalse);
      // And it draws no footer mark: Sal is on the card already.
      expect(find.byKey(const ValueKey('share-card-mark')), findsNothing);
    });
  });

  group('the lines', () {
    test('at least six, PG, no figure, no money, in all 23 languages', () {
      expect(AppLocalizations.supportedLocales, hasLength(23));
      for (final l in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(l);
        final lines = shareCardEdges(l10n, fakeGoalCard());
        expect(lines.length, greaterThanOrEqualTo(6));
        expect(lines.toSet(), hasLength(lines.length), reason: '$l: a repeat');
        for (final line in [
          ...lines,
          l10n.goalCardCaps,
          l10n.balanceGoalShareMyLevel,
        ]) {
          expect(line.trim(), isNotEmpty);
          expect(line, isNot(contains('{')), reason: '$l: $line');
          expect(_money.hasMatch(line), isFalse, reason: '$l: $line');
          expect(RegExp(r'\d').hasMatch(line), isFalse, reason: '$l: $line');
          expect(_banned.hasMatch(line), isFalse, reason: '$l: $line');
        }
      }
      // The check itself: whole words, so "better" passes and "bet" fails.
      expect(_banned.hasMatch('Slightly better.'), isFalse);
      expect(_banned.hasMatch('Place a bet.'), isTrue);
    });

    test('really translated: no language but English reads English', () {
      final english = shareCardEdges(en, fakeGoalCard()).toSet();
      for (final l in AppLocalizations.supportedLocales) {
        if (l.languageCode == 'en') continue;
        final l10n = lookupAppLocalizations(l);
        for (final line in shareCardEdges(l10n, fakeGoalCard())) {
          expect(english, isNot(contains(line)), reason: '$l: $line');
        }
        expect(l10n.balanceGoalShareMyLevel, isNot('Share my level'),
            reason: '$l');
      }
    });

    testWidgets('every line and every level name fits, in all 23 languages',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final cut = <String>[];
      const keys = [
        'share-card-caps',
        'share-card-number',
        'share-card-plain',
        'share-card-edge',
      ];
      Future<void> check(Locale locale, GoalCardData card, int seed) async {
        await tester.pumpWidget(_card(card, locale: locale, seed: seed));
        await tester.pump();
        if (tester.takeException() != null) {
          cut.add('$locale ${card.name} $seed overflow');
        }
        for (final k in keys) {
          for (final e in find.byKey(ValueKey(k)).evaluate()) {
            final r = e.findRenderObject();
            if (r is RenderParagraph && r.didExceedMaxLines) {
              cut.add('$locale $seed $k: ${r.text.toPlainText()}');
            }
          }
        }
      }

      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        for (var i = 0; i < kBalanceLevelNames; i++) {
          await check(
              locale,
              fakeGoalCard(level: i + 1, name: balanceLevelName(l10n, i)),
              i);
        }
        // Past the twelfth name the number keeps counting: the widest.
        final pool = shareCardEdges(l10n, fakeGoalCard()).length;
        for (var seed = 0; seed < pool; seed++) {
          await check(
              locale,
              fakeGoalCard(level: 15, name: balanceLevelName(l10n, 11)),
              seed);
        }
      }
      expect(cut, isEmpty, reason: cut.join('\n'));
    });
  });

  group('the message', () {
    test('the invite with the code, never an amount; nothing without a code',
        () {
      final text = appInviteShareText(en, 'JOAO42');
      expect(text, contains('JOAO42'));
      expect(_money.hasMatch(text), isFalse);
      expect(appInviteShareText(en, null), '');
      expect(appInviteShareText(en, '  '), '');
    });
  });

  group('sharing', () {
    late ShareTestEnv env;
    setUp(() {
      env = setUpShareTest();
      AffiliateService.debugAffiliateCode = 'JOAO42';
    });
    tearDown(() {
      AffiliateService.debugAffiliateCode = null;
      tearDownShareTest();
    });

    testWidgets(
        'opens the preview, "Share" sends the PNG with the invite, one event '
        'with the exact level', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      final sent = <(XFile, String)>[];
      ShareCardShare.debugSharer = (image, text) async {
        sent.add((image, text));
        return 'success';
      };
      await pumpShareWidget(
          tester,
          env,
          Builder(
            builder: (context) => Center(
              child: GestureDetector(
                key: const ValueKey('open'),
                behavior: HitTestBehavior.opaque,
                onTap: () => openGoalCardShare(context,
                    level: 7,
                    name: 'Serious',
                    still: 'level_card_6',
                    source: kGoalShareLadder),
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ));
      await tester.tap(find.byKey(const ValueKey('open')));
      await settle(tester);
      expect(find.text('Your card is ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-goal')), findsOneWidget);
      expect(find.text('Level 7'), findsOneWidget);
      expect(find.text('Serious'), findsOneWidget);
      expect(kuteBarPrimaryWithText('Share'), findsOneWidget);
      expect(env.paramsOf('balance_goal_card_shared'), isEmpty);

      await shareCardAndWait(tester, sent);
      expect(sent, hasLength(1));
      expect(await tester.runAsync(() => sent.single.$1.length()),
          greaterThan(1000),
          reason: 'the PNG');
      expect(sent.single.$2, contains('JOAO42'));
      expect(_money.hasMatch(sent.single.$2), isFalse);
      expect(env.paramsOf('balance_goal_card_shared').toList(), [
        {'level': 7, 'result': 'success', 'source': 'ladder'}
      ]);
    });
  });
}
