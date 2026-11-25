// The Predictions browse rows: one text pill per category, and a
// subcategory row whose chips are text, with a small logo only on a
// league or a game.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Column(children: [child])),
      ),
    ),
  ));
  await tester.pump();
}

List<String> _pillLabels(WidgetTester tester) => [
      for (final p in tester.widgetList<KutePill>(find.byType(KutePill)))
        p.label
    ];

void main() {
  final pills = [
    for (final p in PolyPill.values)
      if (p != PolyPill.watchlist) p
  ];

  testWidgets('one text pill per category in the site order, then More',
      (tester) async {
    await _pump(
      tester,
      PolyPillRow(
        pills: pills,
        selected: PolyPill.trending,
        onSelect: (_) {},
        onMore: () {},
      ),
    );
    expect(_pillLabels(tester), [
      'Trending', 'Breaking', 'New', 'Live', 'Politics', 'Sports',
      'Crypto', 'Esports', 'Finance', 'Geopolitics', 'Tech', 'Elections',
      'Culture', 'Economy', 'Weather', 'Mentions', 'Art', 'More ›', //
    ]);
    // No icons and no images on category pills.
    for (final p in tester.widgetList<KutePill>(find.byType(KutePill))) {
      expect(p.icon, isNull);
      expect(p.leading, isNull);
    }
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the categories read in Portuguese', (tester) async {
    await _pump(
      tester,
      PolyPillRow(
        pills: pills,
        selected: PolyPill.trending,
        onSelect: (_) {},
        onMore: () {},
      ),
      locale: const Locale('pt'),
    );
    expect(
        _pillLabels(tester),
        containsAllInOrder([
          'Política', 'Desporto', 'Cripto', 'Esports', 'Finanças',
          'Geopolítica', 'Tecnologia', 'Eleições', 'Cultura', 'Economia',
          'Meteorologia', 'Menções', 'Arte', //
        ]));
  });

  testWidgets(
      'Finance chips carry the site\'s icons; the misspelt slug reads '
      '"Indices"',
      (tester) async {
    PolySub? picked;
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.finance,
        subs: [for (final key in kPolyFinanceSubs) PolySub(key)],
        selectedKey: 'all',
        onSelect: (s) => picked = s,
      ),
    );
    expect(_pillLabels(tester).take(8), [
      'All', 'Daily', 'Weekly', 'Monthly', 'Stocks', 'Earnings', 'Indices',
      'Commodities', //
    ]);
    // Every chip but All wears its row's icon, at the text's height:
    // polymarket.com/finance's own glyph, or the image it draws there.
    for (final p in tester.widgetList<KutePill>(find.byType(KutePill))) {
      if (p.label == 'All') {
        expect(p.leading, isNull);
      } else {
        expect(p.leading, isA<PolySubIcon>(), reason: p.label);
      }
    }
    await tester.tap(find.text('Weekly'));
    expect(picked?.key, 'weekly');
  });

  testWidgets(
      'a row cut as the site\'s side list is: a thin divider between its '
      'groups, Crypto\'s time filters and sections | its coins', (tester) async {
    final subs = polyCryptoSubsFromCounts(null);
    PolySub? picked;
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.crypto,
        subs: subs,
        groups: polySubGroups(PolyPill.crypto, subs),
        selectedKey: 'bitcoin',
        onSelect: (s) => picked = s,
      ),
    );
    final divider = find.byKey(const ValueKey('poly-sub-group-divider'));
    expect(divider, findsOneWidget);
    // The time filters lead; the divider stands after the last section
    // and before the first coin, with the row's spacing either side.
    expect(_pillLabels(tester).take(5),
        ['All', '5 Min', '15 Min', '1 Hour', '4 Hours']);
    final metrics = tester.getRect(find.text('Protocol Metrics'));
    final bitcoin = tester.getRect(find.text('Bitcoin'));
    final line = tester.getRect(divider);
    expect(line.left, greaterThan(metrics.right));
    expect(line.right, lessThan(bitcoin.left));
    expect(line.width, 1);
    // The selected chip is still found past the divider.
    final byLabel = {
      for (final p in tester.widgetList<KutePill>(find.byType(KutePill)))
        p.label: p
    };
    expect(byLabel['Bitcoin']!.selected, isTrue);
    await tester.tap(find.text('Ethereum'));
    expect(picked?.key, 'ethereum');

    // A one-group row (Weather) draws no divider, groups or not.
    final weather = [for (final key in kPolyWeatherSubs) PolySub(key)];
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.weather,
        subs: weather,
        groups: polySubGroups(PolyPill.weather, weather),
        selectedKey: 'all',
        onSelect: (_) {},
      ),
    );
    expect(find.byKey(const ValueKey('poly-sub-group-divider')), findsNothing);
    expect(_pillLabels(tester).length, weather.length);
  });

  testWidgets(
      'Trending\'s row is All then the site\'s themes, each with the '
      'resolver\'s icon; "‹ Trending" leads it drilled in', (tester) async {
    const themes = [
      PolySub('all'),
      PolySub('tag:102289', route: 'midterms', label: 'Midterms', count: 630),
      PolySub('tag:105183', route: 'anthropic-ipo', label: 'Anthropic IPO'),
      PolySub('tag:1', route: 'brand-new-theme', label: 'Brand New'),
    ];
    PolySub? picked;
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.trending,
        subs: themes,
        groups: polySubGroups(PolyPill.trending, themes),
        selectedKey: 'all',
        onSelect: (s) => picked = s,
        onBack: () {},
      ),
    );
    expect(_pillLabels(tester),
        ['Trending', 'All', 'Midterms', 'Anthropic IPO', 'Brand New']);
    expect(find.byKey(const ValueKey('poly-sub-group-divider')), findsNothing);
    final byLabel = {
      for (final p in tester.widgetList<KutePill>(find.byType(KutePill)))
        p.label: p
    };
    expect(byLabel['All']!.leading, isNull);
    expect(byLabel['Midterms']!.leading, isA<PolySubIcon>());
    expect(byLabel['Anthropic IPO']!.leading, isA<PolySubIcon>());
    // A theme the resolver does not know yet stays text in the row.
    expect(byLabel['Brand New']!.leading, isNull);
    await tester.tap(find.text('Midterms'));
    expect(picked?.route, 'midterms');
  });

  testWidgets('every fixed chip has a name in English and Portuguese',
      (tester) async {
    for (final locale in const [Locale('en'), Locale('pt')]) {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final key in kPolyFixedSubKeys) {
        if (kPolyEsportsGames.any((g) => g.slug == key)) continue;
        final sub = polyCryptoSubsFromCounts(null)
            .firstWhere((s) => s.key == key, orElse: () => PolySub(key));
        expect(polySubLabel(l10n, sub), isNot(key),
            reason: '$key in $locale');
      }
    }
  });

  testWidgets('a Sports chip leads with its icon, the same size on each',
      (tester) async {
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.sports,
        subs: polySportsSubsFromLeagues(const [
          {
            'sport': 'nfl',
            'name': 'NFL',
            'image': 'https://example.com/nfl.png',
            'series': '12185',
            'tags': '1,450,100639',
          },
        ]),
        selectedKey: 'live',
        onSelect: (_) {},
      ),
    );
    expect(_pillLabels(tester).take(5),
        ['Live', 'Futures', 'NFL', 'Soccer', 'Tennis']);
    final byLabel = {
      for (final p in tester.widgetList<KutePill>(find.byType(KutePill)))
        p.label: p
    };
    for (final label in const ['NFL', 'Soccer', 'Live', 'Futures']) {
      final icon = byLabel[label]!.leading;
      expect(icon, isA<PolySportIcon>(), reason: label);
      // Every logo is the same size, the text's height.
      expect((icon! as PolySportIcon).size, 14.sp, reason: label);
    }
  });

  testWidgets(
      'a sport\'s league row: "‹ Soccer", All for the sport\'s own chip, '
      'then the leagues with their logos', (tester) async {
    PolySub? picked;
    var back = 0;
    await _pump(
      tester,
      PolySubRow(
        pill: PolyPill.sports,
        subs: const [
          PolySub('soccer'),
          PolySub('series:10193',
              route: 'lal',
              label: 'LaLiga',
              imageUrl: 'https://example.com/lal.png'),
          PolySub('series:10188', route: 'epl', label: 'Premier League'),
        ],
        selectedKey: 'soccer',
        onSelect: (s) => picked = s,
        onBack: () => back++,
        backLabel: 'Soccer',
        allKey: 'soccer',
      ),
    );
    expect(_pillLabels(tester), ['Soccer', 'All', 'LaLiga', 'Premier League']);
    final backPill =
        tester.widget<KutePill>(find.byKey(const ValueKey('kute-back-pill')));
    expect(backPill.label, 'Soccer');
    expect(backPill.icon, Icons.chevron_left_rounded);
    final byLabel = {
      for (final p in tester.widgetList<KutePill>(find.byType(KutePill)))
        p.label: p
    };
    expect(byLabel['All']!.selected, isTrue);
    expect(byLabel['All']!.leading, isNull);
    expect(byLabel['LaLiga']!.leading, isA<PolySportIcon>());
    expect(byLabel['Premier League']!.leading, isA<PolySportIcon>());
    await tester.tap(find.text('LaLiga'));
    expect(picked?.key, 'series:10193');
    await tester.tap(find.byKey(const ValueKey('kute-back-pill')));
    expect(back, 1);
  });

  testWidgets('every topic with rows shows its rows\' own icons; a chip with '
      'none of its own stays text', (tester) async {
    const league = PolySub('series:1',
        label: 'NFL', imageUrl: 'https://example.com/nfl.png');
    late BuildContext context;
    await _pump(tester, Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    expect(context, isNotNull);
    expect(polySubLogo(PolyPill.sports, league), isA<PolySportIcon>());
    expect(polySubLogo(PolyPill.esports, league), isA<PolySubIcon>());
    // Live has no rows: no icon, whatever the chip carries.
    expect(polySubLogo(PolyPill.live, league), isNull);
    expect(polySubLogo(PolyPill.politics, league), isA<PolySubIcon>());
    expect(polySubLogo(PolyPill.sports, const PolySub('soccer')), isNotNull);
    // A chip no topic knows, with no image: text only.
    expect(polySubLogo(PolyPill.esports, const PolySub('soccer')), isNull);
    expect(
        polySubLogo(PolyPill.politics,
            const PolySub('tag:9', route: 'not-a-row', label: 'X')),
        isNull);
    // Crypto: every chip but All carries its icon, the coins their logos.
    final crypto = {
      for (final s in polyCryptoSubsFromCounts(null))
        s.key: polySubLogo(PolyPill.crypto, s)
    };
    for (final s in polyCryptoSubsFromCounts(null)) {
      if (s.key == 'all') {
        expect(crypto['all'], isNull);
      } else {
        expect(crypto[s.key], isA<PolySubIcon>(), reason: s.key);
        expect((crypto[s.key]! as PolySubIcon).size, 14.sp, reason: s.key);
      }
    }
  });
}
