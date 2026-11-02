// The Dollars tab's Investing | Predictions switch never cuts the picked
// pill's words (founder, 2 November 2026: "Investing · Stocks and ⌄",
// "stuff gets cut here"). On a 375 pt phone, in Inter, in every shipped
// language, at the page's large size and in the collapsed bar's compact
// one: the picked pill grows (the other hugs its name), falls back to the
// subcategory alone when the full context still does not fit, and only
// then shrinks its words: never in English, a little in the longer
// languages (Greek's "★ Λίστα παρακολούθησης" the most, to 85%).
//
// Every switch row is one size (founder, 2 November 2026): the Bitcoin
// home's See all | Balance, the Dollars halves and the Portfolio's
// Portfolio | P&L Charts stand at the same height on the same gutters.
//
// The pills with the longest categories, and the three switches side by
// side, are written as PNGs when asked:
//
//   PILL_FRAMES=<dir> flutter test test/screens/usd/investments_pill_fit_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// The picked pill's context and its shorter form, as
/// investmentsCategoryLabel / investmentsCategoryShortLabel compose them.
typedef _Case = ({String detail, String? short});

List<_Case> _investing(AppLocalizations l10n) {
  final out = <_Case>[(detail: l10n.categoryFilterPrompt, short: null)];
  for (final t in HlBrowseTab.values) {
    out.add((detail: t.localizedLabel(l10n), short: null));
  }
  const tradfi = [
    HlBrowseSub.stocks,
    HlBrowseSub.indices,
    HlBrowseSub.commodities,
    HlBrowseSub.fx,
    HlBrowseSub.preipo,
    HlBrowseSub.other,
  ];
  const crypto = [
    HlBrowseSub.ai,
    HlBrowseSub.defi,
    HlBrowseSub.gaming,
    HlBrowseSub.layer1,
    HlBrowseSub.layer2,
    HlBrowseSub.meme,
  ];
  for (final (tab, subs) in [
    (HlBrowseTab.tradfi, tradfi),
    (HlBrowseTab.crypto, crypto),
    (HlBrowseTab.perps, crypto),
    (HlBrowseTab.spot, crypto),
  ]) {
    for (final sub in subs) {
      out.add((
        detail: '${tab.localizedLabel(l10n)} · ${sub.localizedLabel(l10n)}',
        short: sub.localizedLabel(l10n),
      ));
    }
  }
  return out;
}

List<_Case> _predictions(AppLocalizations l10n) {
  final out = <_Case>[(detail: l10n.categoryFilterPrompt, short: null)];
  for (final p in PolyPill.values) {
    out.add((detail: polyPillLabel(l10n, p), short: null));
  }
  final subs = [
    (PolyPill.crypto, l10n.polySubProtocolMetrics),
    (PolyPill.crypto, l10n.polySubInstitutions),
    (PolyPill.crypto, l10n.polySubPreMarket),
    (PolyPill.finance, l10n.polySubPredictionMarkets),
    (PolyPill.finance, l10n.polySubAcquisitions),
    (PolyPill.weather, l10n.polySubPrecipitation),
    (PolyPill.geopolitics, l10n.polySubMonthly),
  ];
  for (final (pill, sub) in subs) {
    out.add((detail: '${polyPillLabel(l10n, pill)} · $sub', short: sub));
  }
  return out;
}

List<KutePillItem> _items(AppLocalizations l10n, int selected, _Case c) => [
      for (final (i, name) in [l10n.trading, l10n.predictions].indexed)
        i == selected
            ? KutePillItem(
                label: name, detail: c.detail, shortDetail: c.short, menu: true)
            : KutePillItem(label: name),
    ];

Widget _app(Locale locale, Widget child) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        home: Scaffold(backgroundColor: const Color(0xFFF7F8FA), body: child),
      ),
    );

/// The page's strip (12 gutters, the switch size) and the collapsed bar's
/// (12 gutters, the expand chevron's 40 at the right, compact).
Widget _strip(List<KutePillItem> items, int selected,
        {required bool compact}) =>
    Builder(
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(12.w, 8, compact ? 52.w : 12.w, 8),
        child: KutePillTabs(
          items: items,
          selectedIndex: selected,
          onTap: (_) {},
          size: compact ? KutePillSize.compact : kutePillSwitchSize,
        ),
      ),
    );

/// How much the picked pill's words were shrunk (1 = full size), after
/// checking they are whole and inside the pill.
double _checkWhole(WidgetTester tester, String text, String why) {
  final label = find.text(text);
  expect(label, findsOneWidget, reason: why);
  final p = tester.renderObject<RenderParagraph>(label);
  expect(p.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(p.size.width + 0.5),
      reason: '$why: "$text" is cut');
  final shown = tester.getRect(label);
  final pill = tester
      .getRect(find.ancestor(of: label, matching: find.byType(KutePill)).first);
  expect(shown.left, greaterThanOrEqualTo(pill.left - 0.5), reason: why);
  expect(shown.right, lessThanOrEqualTo(pill.right + 0.5), reason: why);
  return shown.width / p.size.width;
}

Future<void> _snap(WidgetTester tester, GlobalKey key, String path) =>
    tester.runAsync(() async {
      final ro =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });

void main() {
  final dir = Platform.environment['PILL_FRAMES'];

  testWidgets(
      'the picked pill never cuts its category at 375 pt in every language',
      (tester) async {
    await tester.runAsync(_loadInter);
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      for (final (selected, cases) in [
        (0, _investing(l10n)),
        (1, _predictions(l10n)),
      ]) {
        for (final c in cases) {
          for (final compact in [false, true]) {
            await tester.pumpWidget(_app(
                locale,
                Center(
                    child: _strip(_items(l10n, selected, c), selected,
                        compact: compact))));
            await tester.pump(const Duration(seconds: 1));
            final why = '${locale.languageCode}'
                '${compact ? ' compact' : ''}';
            final picked = tester
                .widgetList<KutePill>(find.byType(KutePill))
                .elementAt(selected);
            final name = selected == 0 ? l10n.trading : l10n.predictions;
            final scale = _checkWhole(tester, '$name · ${picked.detail}', why);
            final other = selected == 0 ? l10n.predictions : l10n.trading;
            expect(_checkWhole(tester, other, why), closeTo(1, 0.001),
                reason: '$why: "$other" shrank');
            // In English every context fits at full size; elsewhere the
            // words shrink only a little, the longest (Greek's watchlist)
            // to 85%.
            if (locale.languageCode == 'en') {
              expect(scale, closeTo(1, 0.001),
                  reason: '$why: "${picked.detail}" shrank to $scale');
            }
            expect(scale, greaterThan(c.short == null ? 0.84 : 0.9),
                reason: '$why: "${picked.detail}" shrank to $scale');
          }
        }
      }
    }
  });

  testWidgets('every switch row stands at one size on the same gutters',
      (tester) async {
    await tester.runAsync(_loadInter);
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final l10n = l10nForLanguage('en');
    final boundary = GlobalKey();
    await tester.pumpWidget(_app(
      const Locale('en'),
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: const Color(0xFFF7F8FA),
            child: Builder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The Bitcoin home (home_analytics_widget.dart).
                  Padding(
                    key: const ValueKey('bitcoin'),
                    padding: EdgeInsets.fromLTRB(16.w, 12, 16.w, 12),
                    child: KutePillTabs(
                      horizontalPadding: 0,
                      items: [
                        KutePillItem(
                            label: l10n.seeAll,
                            icon: Icons.arrow_forward_rounded),
                        KutePillItem(
                            label: l10n.balance, icon: Icons.savings_rounded),
                      ],
                      selectedIndex: 0,
                      onTap: (_) {},
                    ),
                  ),
                  // The Dollars tab (usd_account_screen.dart).
                  Padding(
                    key: const ValueKey('dollars'),
                    padding: EdgeInsets.fromLTRB(12.w, 12, 12.w, 12),
                    child: KutePillTabs(
                      items: [
                        KutePillItem(
                            label: l10n.trading,
                            detail: l10n.categoryFilterPrompt,
                            menu: true),
                        KutePillItem(label: l10n.predictions),
                      ],
                      selectedIndex: 0,
                      onTap: (_) {},
                      size: kutePillSwitchSize,
                    ),
                  ),
                  // The Portfolio screen (investments_portfolio.dart).
                  Padding(
                    key: const ValueKey('portfolio'),
                    padding: EdgeInsets.fromLTRB(16.w, 12, 16.w, 12),
                    child: KutePillTabs(
                      horizontalPadding: 0,
                      items: [
                        KutePillItem(label: l10n.portfolioSectionBalances),
                        KutePillItem(label: l10n.portfolioSectionPnlCharts),
                      ],
                      selectedIndex: 0,
                      onTap: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final indicators = find.byKey(kutePillIndicatorKey);
    expect(indicators, findsNWidgets(3));
    final rects = [
      for (var i = 0; i < 3; i++) tester.getRect(indicators.at(i))
    ];
    for (final r in rects.skip(1)) {
      expect(r.height, moreOrLessEquals(rects.first.height, epsilon: 0.5));
      expect(r.left, moreOrLessEquals(rects.first.left, epsilon: 0.5));
    }
    for (final strip
        in tester.widgetList<KutePillTabs>(find.byType(KutePillTabs))) {
      expect(strip.resolvedSize, kutePillSwitchSize);
    }
    final labels = [l10n.seeAll, l10n.balance, l10n.portfolioSectionBalances];
    final sizes = {
      for (final l in labels)
        tester.renderObject<RenderParagraph>(find.text(l)).text.style?.fontSize
    };
    expect(sizes, hasLength(1));
    if (dir != null) {
      Directory(dir).createSync(recursive: true);
      await _snap(tester, boundary, '$dir/switch_rows_en.png');
    }
  });

  testWidgets('the longest categories, written as PNGs', (tester) async {
    if (dir == null) return;
    await tester.runAsync(_loadInter);
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Directory(dir).createSync(recursive: true);
    for (final lang in ['en', 'de', 'el', 'fr']) {
      final l10n = l10nForLanguage(lang);
      final boundary = GlobalKey();
      final rows = <Widget>[];
      for (final (selected, cases) in [
        (0, _investing(l10n)),
        (1, _predictions(l10n)),
      ]) {
        // The two longest plain categories and the two longest with a
        // subcategory, each side.
        int byLength(_Case a, _Case b) => b.detail.length - a.detail.length;
        final plain = cases.where((c) => c.short == null).toList()
          ..sort(byLength);
        final nested = cases.where((c) => c.short != null).toList()
          ..sort(byLength);
        for (final c in [...plain.take(2), ...nested.take(2)]) {
          rows.add(_strip(_items(l10n, selected, c), selected, compact: false));
        }
        rows.add(_strip(_items(l10n, selected, plain.first), selected,
            compact: true));
      }
      await tester.pumpWidget(_app(
        Locale(lang),
        Center(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFFF7F8FA),
              child: Column(mainAxisSize: MainAxisSize.min, children: rows),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await _snap(tester, boundary, '$dir/dollars_pill_longest_$lang.png');
    }
  });
}
