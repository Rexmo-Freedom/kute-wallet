// An Investing market page in SEND MODE (send_pick_session.dart; founder,
// 7 November 2026: "same here"): its trade row says it sends, "Send Long"
// | "Send Short" in the market's green and red at even widths, and the
// round Sal share button (the look-only market link) is away. Outside
// send mode the row is Invest | Short with the round button, as before.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';
import '../../helpers/shell_bar_harness.dart';

final _l10n = AppLocalizationsEn();
final Finder _share = find.byKey(const ValueKey('kute-bar-share'));
Finder _trade(String id) => find.byKey(ValueKey('kute-bar-trade-$id'));

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('send-mode-hl-bar').path);
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, {SendPickSession? sendPick}) async {
    installShellBar();
    await pumpHlEditSheet(tester,
        appBuilder: shellBarBuilder, sendPick: sendPick);
    await pumpBar(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets(
      'send mode: "Send Long" | "Send Short" in green and red, even widths, '
      'no round share button; the chip names the friend', (tester) async {
    await pump(tester,
        sendPick:
            SendPickSession(entrySource: 'dollar_send', recipientName: 'Ana'));
    final ctx = scopeContext(tester, within: find.byType(HlMarketDetailSheet));
    expect(ctx.isTrade, isTrue);
    expect(ctx.share, isNull);
    expect(ctx.trades.map((t) => (t.label, t.fill)), [
      (_l10n.sendPickTradeSide(_l10n.longLabel), AppColors.marketUp),
      (_l10n.sendPickTradeSide(_l10n.shortLabel), AppColors.marketDown),
    ]);
    expect(find.text('Send Long'), findsOneWidget);
    expect(find.text('Send Short'), findsOneWidget);
    expect(_share, findsNothing);
    expect(tester.getRect(_trade('invest')).width,
        moreOrLessEquals(tester.getRect(_trade('short')).width, epsilon: 1));
    expect(find.text(_l10n.sendPickChipForNamed('Ana')), findsOneWidget);
    await done(tester);
  });

  testWidgets('outside send mode: Invest | Short and the round share button',
      (tester) async {
    await pump(tester);
    final ctx = scopeContext(tester, within: find.byType(HlMarketDetailSheet));
    expect(ctx.trades.map((t) => t.label),
        [_l10n.hlMarketInvestCta, _l10n.shortLabel]);
    expect(ctx.share, isNotNull);
    expect(_share, findsOneWidget);
    expect(tester.getRect(_trade('invest')).width,
        greaterThan(tester.getRect(_trade('short')).width * 1.5));
    expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
    await done(tester);
  });
}
