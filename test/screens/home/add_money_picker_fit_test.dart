// The "Add money to Dollars" picker's two big cards (founder, 5 November
// 2026: "this is cut"): "Bitcoin · Your spending wallet · $285.48" and
// "Another crypto · Get an address to send dollars to". On a
// 375 pt phone, in Inter, in every shipped language, no word of either
// card is cut: a line wraps to the lines it needs and the two cards of the
// row grow together, equally tall.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MovePickerRow;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// The picker's body as the sheet lays it out (deposit_sheet.dart,
/// _movePickerBody): the cards on the sheet's 20 gutters.
Widget _picker(Locale locale, String balance) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: Brightness.dark,
          extensions: [AppColorsExtension.dark()],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Builder(
              builder: (context) {
                final l10n = context.l10n;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: KuteActionCardGrid(
                    key: const ValueKey('move-picker-cards'),
                    cards: [
                      MovePickerRow(
                        key: const ValueKey('card-bitcoin'),
                        asset: 'lib/assets/bitcoin-icon.svg',
                        title: 'Bitcoin',
                        subtitle: l10n
                            .depositFromSpendingWalletWithBalance(balance),
                        onTap: () {},
                      ).toCard(),
                      MovePickerRow(
                        key: const ValueKey('card-other'),
                        icon: Icons.south_west_rounded,
                        title: l10n.receiveAnotherCrypto,
                        subtitle: l10n.depositFromAnotherWalletSubtitle,
                        onTap: () {},
                      ).toCard(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'the Add money cards never cut a word at 375 pt in every language',
      (tester) async {
    await tester.runAsync(_loadInter);
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var wrapped = 0;
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      for (final balance in [r'$285.48', r'$12,345.67']) {
        await tester.pumpWidget(_picker(locale, balance));
        await tester.pump();
        final why = '${locale.languageCode} $balance';
        expect(tester.takeException(), isNull, reason: why);
        final bitcoin = tester.getRect(find.byKey(const ValueKey('card-bitcoin')));
        final other = tester.getRect(find.byKey(const ValueKey('card-other')));
        // One row, the two cards equally tall.
        expect(other.top, moreOrLessEquals(bitcoin.top, epsilon: 0.5),
            reason: why);
        expect(other.height, moreOrLessEquals(bitcoin.height, epsilon: 0.5),
            reason: why);
        for (final (card, texts) in [
          (
            const ValueKey('card-bitcoin'),
            ['Bitcoin', l10n.depositFromSpendingWalletWithBalance(balance)],
          ),
          (
            const ValueKey('card-other'),
            [
              l10n.receiveAnotherCrypto,
              l10n.depositFromAnotherWalletSubtitle,
            ],
          ),
        ]) {
          final box = tester.getRect(find.byKey(card));
          for (final text in texts) {
            final label =
                find.descendant(of: find.byKey(card), matching: find.text(text));
            expect(label, findsOneWidget, reason: '$why: "$text"');
            final p = tester.renderObject<RenderParagraph>(label);
            // Whole: no line dropped, no ellipsis, no word broken.
            expect(p.didExceedMaxLines, isFalse,
                reason: '$why: "$text" is cut');
            final shown = tester.getRect(label);
            expect(shown.left, greaterThanOrEqualTo(box.left), reason: why);
            expect(shown.right, lessThanOrEqualTo(box.right + 0.5),
                reason: why);
            expect(shown.bottom, lessThanOrEqualTo(box.bottom + 0.5),
                reason: '$why: "$text" runs past its card');
            final lines = p
                .getBoxesForSelection(
                    TextSelection(baseOffset: 0, extentOffset: text.length))
                .map((b) => b.top)
                .toSet()
                .length;
            if (lines > 2) wrapped++;
          }
        }
      }
    }
    // The longer languages do need a third line somewhere: the old two-line
    // cap is what cut them.
    expect(wrapped, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
