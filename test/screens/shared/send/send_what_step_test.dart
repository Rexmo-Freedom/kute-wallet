// The What step's cards in every language at 375 pt (founder, 7 November
// 2026, of the two full-width rows they were: "here should be the
// squares"): the money and the gift are two equal squares side by side,
// whatever the language; "A prediction or investment" and its line wrap to
// the lines they need, never cut and never a word broken across lines; the
// gift wears Sal in the money mark's box, as big as the mark, no box of
// his own. With no gift, the money card stands alone, full width and
// compact. Inter, the app's font, so the measures are a phone's.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCardIcon;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendSalShareGlyph;
import 'package:kute/screens/shared/send/send_what_step.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _fonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
  await inter.load();
}

Future<void> _pump(WidgetTester tester,
    {required Locale locale, bool gift = true, bool dark = false}) async {
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
            child: SendWhatSheet(
              name: 'Anna Haro',
              from: SendFrom.dollars,
              giftOffered: gift,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

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

  setUp(() => SalSpriteCache.debugSetManifest(null));
  tearDown(SalSpriteCache.debugReset);

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

  testWidgets(
      'no gift offered: the money card alone, the grid\'s lone card, full '
      'width and compact with its chevron', (tester) async {
    await _pump(tester, locale: const Locale('en'), gift: false);
    final money = find.byKey(kSendWhatMoneyKey);
    expect(find.byKey(kSendWhatGiftKey), findsNothing);
    expect(tester.getSize(money).width,
        tester.getSize(find.byKey(const ValueKey('send-what-cards'))).width);
    expect(
        find.descendant(
            of: money, matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
  });
}
