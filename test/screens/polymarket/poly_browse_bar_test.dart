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
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
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
      'Trending', 'Breaking', 'New', 'Live', 'Politics', 'Sports', 'Crypto',
      'Esports', 'Finance', 'Geopolitics', 'Tech', 'Culture', 'Economy',
      'Weather', 'Mentions', 'Elections', 'More ›', //
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
          'Geopolítica', 'Tecnologia', 'Cultura', 'Economia', 'Meteorologia',
          'Menções', 'Eleições', //
        ]));
  });

  testWidgets('Finance chips are text; the misspelt slug reads "Indices"',
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
    expect(find.byType(PolyCrestImage), findsNothing);
    await tester.tap(find.text('Weekly'));
    expect(picked?.key, 'weekly');
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

  testWidgets('a league chip leads with its logo; a sport is text',
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
    expect(byLabel['NFL']!.leading, isA<PolyCrestImage>());
    expect(byLabel['Soccer']!.leading, isNull);
    expect(byLabel['Live']!.leading, isNull);
    // Every logo is the same size, the text's height.
    expect((byLabel['NFL']!.leading! as PolyCrestImage).size, 14.sp);
  });

  testWidgets('a logo shows only on Sports, Esports and the Crypto coins',
      (tester) async {
    const league = PolySub('series:1',
        label: 'NFL', imageUrl: 'https://example.com/nfl.png');
    late BuildContext context;
    await _pump(tester, Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    expect(context, isNotNull);
    expect(polySubLogo(PolyPill.sports, league), isNotNull);
    expect(polySubLogo(PolyPill.esports, league), isNotNull);
    expect(polySubLogo(PolyPill.live, league), isNull);
    expect(polySubLogo(PolyPill.politics, league), isNull);
    expect(polySubLogo(PolyPill.sports, const PolySub('soccer')), isNull);
    // Crypto: the coins carry the site's logos, the other chips none.
    final crypto = {
      for (final s in polyCryptoSubsFromCounts(null))
        s.key: polySubLogo(PolyPill.crypto, s)
    };
    for (final coin in const [
      'bitcoin', 'ethereum', 'solana', 'xrp', 'dogecoin', 'bnb',
      'microstrategy', //
    ]) {
      expect(crypto[coin], isA<PolyCrestImage>(), reason: coin);
    }
    for (final other in const ['all', '5m', 'weekly', 'targets']) {
      expect(crypto[other], isNull, reason: other);
    }
  });
}
