// Category rows are boxed pills again, and never stacked (owner decision
// 2026-10-13: "I loved the pills before"). A category with subcategories
// drills in: its row gives way to a back pill ("‹ Finance") and the
// subcategory pills, all the same boxed chip; the back pill brings the
// categories back. Every pill is a button that announces its selection
// (links never), keeps a 44 pt hit target, and the swap is at once under
// Reduce Motion.

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
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child, const Text('content under the row')],
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Whether the pill labelled [label] wears the boxed chip's card (a fill
/// and a border): the one on screen does, the others sit tonal.
bool _boxed(WidgetTester tester, String label) {
  final pill =
      find.ancestor(of: find.text(label), matching: find.byType(KutePill));
  for (final e in find
      .descendant(of: pill, matching: find.byType(DecoratedBox))
      .evaluate()) {
    final d = (e.widget as DecoratedBox).decoration;
    if (d is! BoxDecoration) continue;
    final filled = d.color != null && d.color!.a > 0;
    final bordered = d.border != null && (d.border as Border).top.color.a > 0;
    if (filled && bordered) return true;
  }
  return false;
}

Finder _pillOf(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(KutePill));

final _back = find.byKey(const ValueKey('kute-back-pill'));

/// The Predictions browse row as the screen wires it: the categories, and
/// a category with subcategories drilled into on a tap.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  PolyPill pill = PolyPill.trending;
  String sub = 'all';
  PolyPill? drilledInto;
  final picks = <String>[];

  /// Puts [p] on screen at [s] without drilling in.
  void show(PolyPill p, String s) => setState(() {
        pill = p;
        sub = s;
      });

  static List<PolySub> subsOf(PolyPill p) => p == PolyPill.finance
      ? [for (final key in kPolyFinanceSubs) PolySub(key)]
      : const [];

  @override
  Widget build(BuildContext context) {
    final subs = subsOf(pill);
    final drilled = drilledInto == pill && subs.length > 1;
    return PolyDrillRow(
      drilledInto: drilled ? pill : null,
      builder: (context, revealOnMount) => drilled
          ? PolySubRow(
              pill: pill,
              subs: subs,
              selectedKey: sub,
              revealOnMount: revealOnMount,
              onSelect: (s) => setState(() {
                picks.add('sub:${s.key}');
                sub = s.key;
              }),
              onBack: () => setState(() {
                picks.add('back:${pill.key}');
                drilledInto = null;
                sub = 'all';
              }),
            )
          : PolyPillRow(
              pills: const [
                PolyPill.trending,
                PolyPill.breaking,
                PolyPill.finance,
                PolyPill.mentions,
              ],
              selected: pill,
              revealOnMount: revealOnMount,
              onSelect: (p) => setState(() {
                picks.add('pill:${p.key}');
                drilledInto = p;
                if (p != pill) sub = 'all';
                pill = p;
              }),
              onMore: () {},
            ),
    );
  }
}

void main() {
  final pills = [
    for (final p in PolyPill.values)
      if (p != PolyPill.watchlist) p
  ];

  testWidgets(
      'the categories are boxed pills again: the one on screen wears the '
      'card, each announces its selection, More is a link', (tester) async {
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

    expect(_boxed(tester, 'Trending'), isTrue);
    expect(_boxed(tester, 'Breaking'), isFalse);
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
    expect(
        tester.getSemantics(find.text('More ›')),
        isSemantics(
            label: 'More ›',
            isButton: true,
            hasSelectedState: false,
            isSelected: false));

    // 44 pt hit targets around the 34 pt chip.
    final size = tester.getSize(_pillOf('New'));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Breaking'));
    expect(picked, PolyPill.breaking);
    handle.dispose();
  });

  testWidgets(
      'a category with subcategories swaps the row for its back pill and '
      'subcategories; the back pill brings the categories back',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    final rowSize = tester.getSize(find.byType(PolyDrillRow));
    final contentTop = tester.getTopLeft(find.text('content under the row'));

    expect(_back, findsNothing);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();

    // One row: the back pill, then Finance's subcategories, All selected.
    expect(find.text('Trending'), findsNothing);
    expect(_back, findsOneWidget);
    final back = tester.widget<KutePill>(_back);
    expect(back.label, 'Finance');
    expect(back.icon, Icons.chevron_left_rounded);
    expect(tester.getTopLeft(_back).dx,
        lessThan(tester.getTopLeft(_pillOf('All')).dx));
    expect(_boxed(tester, 'All'), isTrue);
    expect(_boxed(tester, 'Daily'), isFalse);
    expect(
        tester.getSemantics(_back),
        isSemantics(
            label: 'Back, Finance',
            isButton: true,
            hasTapAction: true,
            hasSelectedState: false,
            isSelected: false));
    expect(
        tester.getSemantics(find.text('All')),
        matchesSemantics(
            label: 'All',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    expect(tester.getSize(_back).height, greaterThanOrEqualTo(44));

    // The row keeps its height: the content under it never moves.
    expect(tester.getSize(find.byType(PolyDrillRow)), rowSize);
    expect(tester.getTopLeft(find.text('content under the row')), contentTop);

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(_boxed(tester, 'Daily'), isTrue);
    expect(_back, findsOneWidget);

    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(_back, findsNothing);
    expect(find.text('Daily'), findsNothing);
    // Finance stays the category on screen.
    expect(_boxed(tester, 'Finance'), isTrue);
    expect(state.sub, 'all');
    expect(state.picks, ['pill:finance', 'sub:daily', 'back:finance']);

    // Tapped again, Finance drills in again.
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(_back, findsOneWidget);
    handle.dispose();
  });

  testWidgets('a category with no subcategories selects and the row stays',
      (tester) async {
    await _pump(tester, const _Harness());
    await tester.tap(find.text('Breaking'));
    await tester.pumpAndSettle();
    expect(_back, findsNothing);
    expect(find.text('Trending'), findsOneWidget);
    expect(_boxed(tester, 'Breaking'), isTrue);
    expect(_boxed(tester, 'Trending'), isFalse);
  });

  testWidgets('the swap cross-fades, and is at once under Reduce Motion',
      (tester) async {
    await _pump(tester, const _Harness());
    await tester.tap(find.text('Finance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Mid-fade both rows are drawn.
    expect(find.text('Trending'), findsOneWidget);
    expect(_back, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Trending'), findsNothing);

    await _pump(tester, const SizedBox());
    await _pump(tester, const _Harness(), reduceMotion: true);
    await tester.tap(find.text('Finance'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Trending'), findsNothing);
    expect(_back, findsOneWidget);
    await tester.tap(_back);
    await tester.pump();
    await tester.pump();
    expect(_back, findsNothing);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets(
      'the row swapped in starts at its beginning, even with its selected '
      'subcategory far along it', (tester) async {
    await _pump(tester, const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.show(PolyPill.finance, 'treasuries');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(_back, findsOneWidget);
    // The back pill leads at the screen's margin; the row was not
    // scrolled to Treasuries.
    expect(tester.getTopLeft(_back).dx, closeTo(16 * 390 / 430, 1));
  });

  testWidgets('the Investments pills keep the boxed chip', (tester) async {
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
    expect(_boxed(tester, 'Investing'), isTrue);
    expect(_boxed(tester, 'Predictions'), isFalse);
  });

  testWidgets(
      'the Portfolio tabs are boxed pills with 44 pt hit targets and still '
      'track', (tester) async {
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
    expect(_boxed(tester, 'Open'), isTrue);
    expect(_boxed(tester, 'Orders'), isFalse);
    expect(tester.getSize(_pillOf('Orders')).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(_boxed(tester, 'Orders'), isTrue);
    expect(_boxed(tester, 'Open'), isFalse);
  });

  testWidgets('under Reduce Motion the chip moves at once', (tester) async {
    var selected = PolyPill.trending;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PolyPillRow(
          pills: pills,
          selected: selected,
          onSelect: (p) => setState(() => selected = p),
          onMore: () {},
        ),
      ),
      reduceMotion: true,
    );
    await tester.tap(find.text('Breaking'));
    await tester.pump();
    expect(_boxed(tester, 'Breaking'), isTrue);
    expect(_boxed(tester, 'Trending'), isFalse);
  });
}
