// Stacked pill rows read as one hierarchy (owner decision 2026-10-13):
// level 1 (Investing · Predictions · Portfolio) keeps the boxed chip;
// level 2 (the categories, the Portfolio's tabs) is text tabs with an
// underline under the one on screen; level 3 (the subcategories) is
// smaller text. Neither text level draws a box, both announce the
// selected one, and every tab keeps a 44 pt hit target.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 844), disableAnimations: reduceMotion),
          child: Scaffold(body: Column(children: [child])),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Every box decoration painted inside the pill labelled [label] that has
/// a fill, a border or a shadow, other than the tab's own underline.
List<BoxDecoration> _chrome(WidgetTester tester, String label) {
  final pill =
      find.ancestor(of: find.text(label), matching: find.byType(KutePill));
  final underline = find.descendant(
      of: pill, matching: find.byKey(const ValueKey('kute-pill-underline')));
  final underlineBoxes = find
      .descendant(of: underline, matching: find.byType(DecoratedBox))
      .evaluate()
      .toSet();
  final out = <BoxDecoration>[];
  for (final e in find
      .descendant(of: pill, matching: find.byType(DecoratedBox))
      .evaluate()) {
    if (underlineBoxes.contains(e)) continue;
    final d = (e.widget as DecoratedBox).decoration;
    if (d is! BoxDecoration) continue;
    final filled = d.color != null && d.color!.a > 0;
    final bordered = d.border != null && (d.border as Border).top.color.a > 0;
    if (filled || bordered || (d.boxShadow?.isNotEmpty ?? false)) out.add(d);
  }
  return out;
}

Color _underlineColor(WidgetTester tester, String label) {
  final pill =
      find.ancestor(of: find.text(label), matching: find.byType(KutePill));
  final box = tester.widget<DecoratedBox>(find.descendant(
      of: find.descendant(
          of: pill,
          matching: find.byKey(const ValueKey('kute-pill-underline'))),
      matching: find.byType(DecoratedBox)));
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  final pills = [
    for (final p in PolyPill.values)
      if (p != PolyPill.watchlist) p
  ];

  testWidgets(
      'level 2 categories are text tabs: no box, an underline only under '
      'the one on screen, selection announced', (tester) async {
    final handle = tester.ensureSemantics();
    PolyPill? picked;
    await _pump(
      tester,
      PolyPillRow(
        pills: pills,
        selected: PolyPill.trending,
        onSelect: (p) => picked = p,
        onMore: () {},
      ),
    );

    for (final p in tester.widgetList<KutePill>(find.byType(KutePill))) {
      expect(p.style, KutePillStyle.tab, reason: p.label);
    }
    expect(_chrome(tester, 'Trending'), isEmpty);
    expect(_chrome(tester, 'Breaking'), isEmpty);

    final c = AppColorsExtension.light();
    expect(_underlineColor(tester, 'Trending'), c.textPrimary);
    expect(_underlineColor(tester, 'Breaking').a, 0);
    expect(
        DefaultTextStyle.of(tester.element(find.text('Trending'))).style.color,
        c.textPrimary);
    expect(
        DefaultTextStyle.of(tester.element(find.text('Breaking'))).style.color,
        c.textTertiary);

    expect(
        tester.getSemantics(find.text('Trending')),
        matchesSemantics(
            label: 'Trending',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    expect(
        tester.getSemantics(find.text('Breaking')),
        matchesSemantics(
            label: 'Breaking',
            isButton: true,
            hasSelectedState: true,
            hasTapAction: true));
    // "More" is a link: a button, never "selected".
    expect(
        tester.getSemantics(find.text('More ›')),
        isSemantics(
            label: 'More ›',
            isButton: true,
            hasSelectedState: false,
            isSelected: false));

    // 44 pt hit targets.
    final size = tester.getSize(
        find.ancestor(of: find.text('New'), matching: find.byType(KutePill)));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Breaking'));
    expect(picked, PolyPill.breaking);
    handle.dispose();
  });

  testWidgets(
      'level 3 subcategories are smaller text: no box, no underline, '
      'selection announced', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.finance,
        subs: [for (final key in kPolyFinanceSubs) PolySub(key)],
        selectedKey: 'stocks',
        onSelect: (_) {},
      ),
    );

    for (final p in tester.widgetList<KutePill>(find.byType(KutePill))) {
      expect(p.style, KutePillStyle.subtle, reason: p.label);
    }
    expect(_chrome(tester, 'Stocks'), isEmpty);
    expect(_chrome(tester, 'Indices'), isEmpty);
    expect(find.byKey(const ValueKey('kute-pill-underline')), findsNothing);

    // Smaller than the level 2 label.
    final subSize = DefaultTextStyle.of(tester.element(find.text('Stocks')))
        .style
        .fontSize!;
    final ctx = tester.element(find.text('Stocks'));
    expect(subSize, lessThan(AppTextStyles.modalItem(ctx).fontSize!));

    expect(
        tester.getSemantics(find.text('Stocks')),
        matchesSemantics(
            label: 'Stocks',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    expect(
        tester.getSemantics(find.text('Indices')),
        matchesSemantics(
            label: 'Indices',
            isButton: true,
            hasSelectedState: true,
            hasTapAction: true));

    final size = tester.getSize(
        find.ancestor(of: find.text('All'), matching: find.byType(KutePill)));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets('level 1 keeps the boxed chip on the one on screen',
      (tester) async {
    await _pump(
      tester,
      KutePillTabs(
        items: const [
          KutePillItem(label: 'Investing'),
          KutePillItem(label: 'Predictions'),
          KutePillItem(label: 'Portfolio'),
        ],
        selectedIndex: 0,
        onTap: (_) {},
        size: KutePillSize.large,
      ),
    );
    expect(_chrome(tester, 'Investing'), isNotEmpty);
    expect(_chrome(tester, 'Predictions'), isEmpty);
    expect(find.byKey(const ValueKey('kute-pill-underline')), findsNothing);
  });

  testWidgets('the Portfolio tabs are level 2 text tabs and still track',
      (tester) async {
    await _pump(
      tester,
      DefaultTabController(
        length: 4,
        child: const PortfolioTabs(tabs: [
          ('Open', Icons.account_balance_wallet_outlined),
          ('Orders', Icons.receipt_long_outlined),
          ('Activity', Icons.history_rounded),
          ('Statistics', Icons.insights_outlined),
        ]),
      ),
    );
    final row = tester.widget<KutePillTabs>(find.byType(KutePillTabs));
    expect(row.style, KutePillStyle.tab);
    expect(_chrome(tester, 'Open'), isEmpty);
    expect(_underlineColor(tester, 'Open'),
        AppColorsExtension.light().textPrimary);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(_underlineColor(tester, 'Orders'),
        AppColorsExtension.light().textPrimary);
    expect(_underlineColor(tester, 'Open').a, 0);
  });

  testWidgets('under Reduce Motion the underline moves at once',
      (tester) async {
    var selected = PolyPill.trending;
    late StateSetter setState;
    await _pump(
      tester,
      StatefulBuilder(builder: (context, set) {
        setState = set;
        return PolyPillRow(
          pills: pills,
          selected: selected,
          onSelect: (p) => setState(() => selected = p),
          onMore: () {},
        );
      }),
      reduceMotion: true,
    );
    await tester.tap(find.text('Breaking'));
    await tester.pump();
    expect(_underlineColor(tester, 'Breaking'),
        AppColorsExtension.light().textPrimary);
    expect(_underlineColor(tester, 'Trending').a, 0);
  });
}
